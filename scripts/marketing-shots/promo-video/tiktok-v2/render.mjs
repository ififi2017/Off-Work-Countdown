// Render one of three isolated 1080×1920 TikTok edits. Legacy files remain untouched.
//
// The page draws every frame from a timestamp (window.render(t)), so the
// output does not depend on how fast Chrome runs: we step t, screenshot, and
// pipe the frames into ffmpeg. The frame range is split across several
// headless Chromes and the segments are concatenated without re-encoding.
//
//   node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --variant office
//   node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --stills 0,3,18
//   node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --check

import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { cpus, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SELF = fileURLToPath(import.meta.url);
const VARIANT = process.argv.includes("--variant") ? process.argv[process.argv.indexOf("--variant") + 1] : "progress";
if (!["progress", "office", "woodfish"].includes(VARIANT)) throw new Error(`Unknown variant: ${VARIANT}`);
const OUT = join(HERE, "out", VARIANT);
const CHROME = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FPS = Number(process.env.FPS || 60);
const WORKERS = Number(process.env.WORKERS || Math.max(2, Math.min(4, Math.floor(cpus().length / 2))));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const args = process.argv.slice(2);
const arg = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : null);
const stillsArg = arg("--stills");
const workerArg = arg("--worker"); // "index,firstFrame,endFrame"

mkdirSync(OUT, { recursive: true });

/** Open one headless Chrome with scene.html loaded; returns helpers bound to it. */
async function openScene(port) {
  // A headless page counts as a background tab. Without these switches Chrome
  // starts intensive throttling after a few minutes and every screenshot waits
  // on a throttled frame — a one-minute video then takes an hour.
  const chrome = spawn(CHROME, [
    "--headless=new", `--remote-debugging-port=${port}`, "--hide-scrollbars", "--force-color-profile=srgb",
    "--font-render-hinting=none", "--allow-file-access-from-files",
    "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
    "--disable-backgrounding-occluded-windows", "--disable-features=IntensiveWakeUpThrottling,MacAppCodeSignClone",
    `--user-data-dir=${join(tmpdir(), `doneat-tiktok-v2-${port}`)}`, "about:blank",
  ], { stdio: "ignore" });
  process.on("exit", () => chrome.kill());

  let wsUrl;
  for (let i = 0; i < 80 && !wsUrl; i++) {
    try { wsUrl = (await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()).webSocketDebuggerUrl; }
    catch { await sleep(250); }
  }
  if (!wsUrl) throw new Error("Chrome DevTools did not start");
  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));

  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", (e) => {
    const d = JSON.parse(e.data);
    const p = pending.get(d.id);
    if (!p) return;
    pending.delete(d.id);
    clearTimeout(p.timer);
    d.error ? p.rej(new Error(`${p.method}: ${d.error.message}`)) : p.res(d.result);
  });
  const send = (method, params = {}, sessionId) => new Promise((res, rej) => {
    const n = ++id;
    // Fail loudly instead of hanging forever on a stuck frame.
    const timer = setTimeout(() => { pending.delete(n); rej(new Error(`${method} timed out`)); }, 30000);
    pending.set(n, { res, rej, method, timer });
    ws.send(JSON.stringify({ id: n, method, params, sessionId }));
  });

  const { targetId } = await send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
  await send("Page.enable", {}, sessionId);
  await send("Page.bringToFront", {}, sessionId);
  await send("Emulation.setFocusEmulationEnabled", { enabled: true }, sessionId);
  await send("Emulation.setDeviceMetricsOverride", { width: 1080, height: 1920, deviceScaleFactor: 1, mobile: false }, sessionId);
  await send("Page.navigate", { url: `${pathToFileURL(join(HERE, "scene.html")).href}?variant=${VARIANT}` }, sessionId);
  await sleep(1500);
  const ready = await send("Runtime.evaluate", { expression: "window.ready", awaitPromise: true }, sessionId);
  if (ready.exceptionDetails) throw new Error(ready.exceptionDetails.exception?.description ?? ready.exceptionDetails.text);

  return {
    async render(t) {
      const r = await send("Runtime.evaluate", { expression: `render(${t}); 0`, returnByValue: true }, sessionId);
      if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
    },
    async grab(format) {
      const { data } = await send("Page.captureScreenshot", { format, quality: format === "jpeg" ? 96 : undefined, optimizeForSpeed: format === "jpeg" }, sessionId);
      return Buffer.from(data, "base64");
    },
    async total() {
      return (await send("Runtime.evaluate", { expression: "window.VIDEO_LENGTH", returnByValue: true }, sessionId)).result.value;
    },
    async timeline() {
      return (await send("Runtime.evaluate", { expression: "JSON.stringify(window.AUDIO_TIMELINE)", returnByValue: true }, sessionId)).result.value;
    },
    async validate() {
      const result = await send("Runtime.evaluate", { expression: `JSON.stringify([...document.querySelectorAll('[data-safe]')].flatMap(el => {
        const r = el.getBoundingClientRect();
        return r.width && r.height && (r.left < 64 || r.right > 920 || r.top < 190 || r.bottom > 1500) ? [el.id] : [];
      }))`, returnByValue: true }, sessionId);
      const outside = JSON.parse(result.result.value);
      if (outside.length) throw new Error('Text outside editorial safe area: ' + outside.join(', '));
    },
    close() { ws.close(); chrome.kill(); },
  };
}

const encoder = (file) => spawn("ffmpeg", [
  "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "mjpeg", "-i", "-",
  "-vf", "scale=in_range=full:out_range=limited,format=yuv420p", "-color_range", "tv",
  "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
  "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-profile:v", "high",
  "-r", String(FPS), file,
], { stdio: ["pipe", "inherit", "inherit"] });

if (args.includes("--check")) {
  const scene = await openScene(9457);
  try {
    for (const t of [0, .65, 1.1, 1.65, 2.9, 3, 3.3, 5.6, 6.8, 8.4, 10.8, 11.5, 13.8, 16.8, 17.8, 20.9]) {
      await scene.render(t);
      await scene.validate();
    }
    console.log(`${VARIANT}: all editorial cuts render; captions and CTA fit the safe area`);
  } finally { scene.close(); }
} else if (stillsArg) {
  const scene = await openScene(9457);
  for (const t of stillsArg.split(",").map(Number)) {
    await scene.render(t);
    const file = join(OUT, `still-${t.toFixed(2)}.png`);
    writeFileSync(file, await scene.grab("png"));
    console.log(file);
  }
  scene.close();
} else if (workerArg) {
  const [index, first, end] = workerArg.split(",").map(Number);
  const scene = await openScene(9460 + index);
  const file = join(OUT, `segment-${index}.mp4`);
  const ff = encoder(file);
  for (let f = first; f < end; f++) {
    await scene.render(f / FPS);
    const buf = await scene.grab("jpeg");
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if ((f - first) % 120 === 0) console.log(`worker ${index}: ${f - first}/${end - first}`);
  }
  ff.stdin.end();
  await new Promise((res, rej) => ff.on("close", code => code === 0 ? res() : rej(new Error(`ffmpeg exited ${code}`))));
  scene.close();
} else {
  const probe = await openScene(9457);
  const total = await probe.total();
  const timelineFile = join(OUT, "timeline.json");
  writeFileSync(timelineFile, await probe.timeline());
  probe.close();
  if (!(total > 0 && total < 300)) throw new Error(`unexpected video length: ${total}s`);
  const frames = Math.round(total * FPS);
  const started = Date.now();
  const bounds = Array.from({ length: WORKERS + 1 }, (_, i) => Math.round((frames * i) / WORKERS));
  await Promise.all(bounds.slice(0, -1).map((first, i) => new Promise((res, rej) => {
    const child = spawn(process.execPath, [SELF, "--variant", VARIANT, "--worker", `${i},${first},${bounds[i + 1]}`], { stdio: "inherit", env: process.env });
    child.on("close", (code) => (code === 0 ? res() : rej(new Error(`worker ${i} exited ${code}`))));
  })));
  const list = join(OUT, "segments.txt");
  writeFileSync(list, bounds.slice(0, -1).map((_, i) => `file 'segment-${i}.mp4'`).join("\n"));
  const run = (cmd, argv) => new Promise((res, rej) => spawn(cmd, argv, { stdio: "inherit" })
    .on("close", (code) => (code === 0 ? res() : rej(new Error(`${cmd} exited ${code}`)))));
  const silent = join(OUT, "video-only.mp4");
  await run("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", silent]);
  for (let i = 0; i < WORKERS; i++) rmSync(join(OUT, `segment-${i}.mp4`), { force: true });
  rmSync(list, { force: true });

  // Two cuts: effects only (pick a platform track on top), and effects + the synthesized bed.
  const outputs = [["", "sfx.wav", []], ["-music", "mix.wav", ["--music"]]];
  for (const [suffix, wav, flags] of outputs) {
    const wavFile = join(OUT, wav);
    await run(process.execPath, [join(HERE, "audio.mjs"), timelineFile, wavFile, ...flags]);
    const file = join(OUT, `doneat-${VARIANT}-zh-${FPS}fps${suffix}.mp4`);
    await run("ffmpeg", ["-y", "-loglevel", "error", "-i", silent, "-i", wavFile, "-map", "0:v", "-map", "1:a",
      "-c:v", "copy", "-af", "loudnorm=I=-16:TP=-1.5:LRA=20", "-ar", "48000", "-c:a", "aac", "-b:a", "192k",
      "-shortest", "-movflags", "+faststart", file]);
    rmSync(wavFile, { force: true });
    console.log(file);
  }
  rmSync(silent, { force: true });
  console.log(`${frames} frames, ${WORKERS} workers, ${((Date.now() - started) / 1000).toFixed(0)}s`);
}

process.exit(0);

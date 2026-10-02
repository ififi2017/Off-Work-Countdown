// Render promo V4 (scene.html) to a 1080×1920 video.
//
// Same approach as ../render.mjs: the page draws any frame from a timestamp,
// we step t, screenshot in parallel headless Chromes, stitch with ffmpeg, then
// synthesize the soundtrack from the page's cue list.
//
//   node render.mjs                        # effects-only + music cuts
//   node render.mjs --stills 0,6.5         # preview PNGs
//   node render.mjs --safe --stills 0      # with the safe-area overlay
//   node render.mjs --align --stills 13    # real screenshot at 50% over the redraw
//   FPS=30 WORKERS=4 node render.mjs

import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { cpus, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SELF = fileURLToPath(import.meta.url);
const OUT = join(HERE, "out");
const CHROME = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FPS = Number(process.env.FPS || 60);
const WORKERS = Number(process.env.WORKERS || Math.max(2, Math.min(6, Math.floor(cpus().length / 2))));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const args = process.argv.slice(2);
const arg = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : null);
const stillsArg = arg("--stills");
const workerArg = arg("--worker"); // "index,firstFrame,endFrame"
const flags = ["safe", "align", "measure"].filter((f) => args.includes(`--${f}`));
const QUERY = flags.length ? `?${flags.join("&")}` : "";
const OUTV = OUT;
const PORT0 = 9480;

mkdirSync(OUTV, { recursive: true });

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
    `--user-data-dir=${join(tmpdir(), `doneat-promo-v4-${port}`)}`, "about:blank",
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
  await send("Page.navigate", { url: pathToFileURL(join(HERE, "scene.html")).href + QUERY }, sessionId);
  await sleep(1500);
  await send("Runtime.evaluate", { expression: "document.fonts.ready.then(() => Promise.all([...document.images].map(i => i.decode())))", awaitPromise: true }, sessionId);

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

if (stillsArg) {
  const scene = await openScene(PORT0);
  for (const t of stillsArg.split(",").map(Number)) {
    await scene.render(t);
    const file = join(OUTV, `still-${t.toFixed(2)}.png`);
    writeFileSync(file, await scene.grab("png"));
    console.log(file);
  }
  scene.close();
} else if (workerArg) {
  const [index, first, end] = workerArg.split(",").map(Number);
  const scene = await openScene(PORT0 + 1 + index);
  const file = join(OUTV, `segment-${index}.mp4`);
  const ff = encoder(file);
  for (let f = first; f < end; f++) {
    await scene.render(f / FPS);
    const buf = await scene.grab("jpeg");
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if ((f - first) % 120 === 0) console.log(`worker ${index}: ${f - first}/${end - first}`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
  scene.close();
} else {
  const probe = await openScene(PORT0);
  const total = await probe.total();
  const timelineFile = join(OUTV, "timeline.json");
  writeFileSync(timelineFile, await probe.timeline());
  probe.close();
  if (!(total > 0 && total < 120)) throw new Error(`unexpected video length: ${total}s`);
  const frames = Math.round(total * FPS);
  const started = Date.now();
  const bounds = Array.from({ length: WORKERS + 1 }, (_, i) => Math.round((frames * i) / WORKERS));
  await Promise.all(bounds.slice(0, -1).map((first, i) => new Promise((res, rej) => {
    const child = spawn(process.execPath, [SELF, "--worker", `${i},${first},${bounds[i + 1]}`], { stdio: "inherit", env: process.env });
    child.on("close", (code) => (code === 0 ? res() : rej(new Error(`worker ${i} exited ${code}`))));
  })));
  const list = join(OUTV, "segments.txt");
  writeFileSync(list, bounds.slice(0, -1).map((_, i) => `file 'segment-${i}.mp4'`).join("\n"));
  const run = (cmd, argv) => new Promise((res, rej) => spawn(cmd, argv, { stdio: "inherit" })
    .on("close", (code) => (code === 0 ? res() : rej(new Error(`${cmd} exited ${code}`)))));
  const silent = join(OUTV, "video-only.mp4");
  await run("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", silent]);
  for (let i = 0; i < WORKERS; i++) rmSync(join(OUTV, `segment-${i}.mp4`), { force: true });
  rmSync(list, { force: true });

  // Two cuts: effects only (pick a platform track on top), and effects + the synthesized bed.
  // Only the music cut is loudness-normalized; the effects-only cut is sparse and stays quiet.
  const outputs = [["", "sfx.wav", [], []], ["-music", "mix.wav", ["--music"], ["-af", "loudnorm=I=-16:TP=-2:LRA=20"]]];
  for (const [suffix, wav, flags, filter] of outputs) {
    const wavFile = join(OUTV, wav);
    await run(process.execPath, [join(HERE, "audio.mjs"), timelineFile, wavFile, ...flags]);
    const file = join(OUTV, `doneat-v4-zh-${FPS}fps${suffix}.mp4`);
    await run("ffmpeg", ["-y", "-loglevel", "error", "-i", silent, "-i", wavFile, "-map", "0:v", "-map", "1:a",
      "-c:v", "copy", ...filter, "-ar", "48000", "-c:a", "aac", "-b:a", "192k",
      "-shortest", "-movflags", "+faststart", file]);
    rmSync(wavFile, { force: true });
    console.log(file);
  }
  rmSync(silent, { force: true });
  console.log(`${frames} frames, ${WORKERS} workers, ${((Date.now() - started) / 1000).toFixed(0)}s`);
}

process.exit(0);

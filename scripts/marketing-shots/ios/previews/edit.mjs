// Cut the recorded beats into the 886×1920 App Preview the store wants.
//
// The preview's job is not to explain the app. In search results it autoplays
// muted, in a card the size of a thumbnail, next to competitors — so it has to
// win a tap before it can say anything. That sets every decision here: hard
// cuts, no beat longer than four and a half seconds, one short line per beat in
// type that survives being shrunk, and the strongest claim we have at 0:03
// rather than 0:15.
//
// ⚠️ The capture fills the whole frame, and the caption sits **on top of it**.
// Do not letterbox the recording or put it inside a band, a border or a device
// frame: guideline 2.3.4 requires an App Preview to be a screen capture, and
// 3.1.9 was rejected on 2026-09-11 for exactly that ("Includes framing around
// the video screen capture", "Includes device images and/or device frames").
// Text and graphics laid over the capture are explicitly allowed; anything that
// shrinks the capture inside the frame is not.
//
// Sound is silent stereo AAC. App Store Connect rejects a preview with no audio
// track, and autoplay is muted anyway, so the only job of the audio is to exist.
//
// Beats come from capture.mjs (`IOS_SHOTS_MODE=previews`); the Life beat is a
// still from the screenshot pipeline, because that screen does not move.

import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { captureHtml } from "../../chrome.mjs";
import { BRAND, escapeHTML, fontStack } from "../../brand.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const STILLS = join(DIR, "../raw");
const WIDTH = 886;
const HEIGHT = 1920;
const FPS = 30;

// The capture is 1320×2868 (0.4602) and the store slot is 886×1920 (0.4615):
// scaling to width and trimming five pixels of height fills the frame without
// distorting it. The status bar and Dynamic Island stay in shot — they are part
// of the screen, and cropping them is what used to cost the full width.
const FILL = `scale=${WIDTH}:-2,crop=${WIDTH}:${HEIGHT}`;

// The caption overlays the bottom of the capture, where the tab bar is the least
// informative part of the screen. Translucent so it reads as part of the video
// rather than a band bolted onto it.
const CAPTION_HEIGHT = 230;

// App Previews must run 15–30s. Apple re-saves the upload, and a file that sits
// exactly on 15.000 can come back a few milliseconds short and fail processing,
// so the floor here has margin. Tracks of unequal length fail the same way with
// MOV_RESAVE_LONGER — hence SYNC_TOLERANCE below.
const MIN_SECONDS = 15.5;
const MAX_SECONDS = 30;
const SYNC_TOLERANCE = 0.05;

// One line each, and shorter than the screenshot captions on purpose: those
// carry a subtitle and are read at arm's length, these are read at the size of
// a fingernail. The order is the listing's order, minus the Lock Screen, which
// a compliant preview cannot show.
const LINES = {
  en: {
    timer: "When work actually ends",
    lunch: "Lunch doesn’t count",
    records: "See where the time went",
    life: "Work, in the bigger picture",
    focus: "Room for focused work",
  },
  "zh-CN": {
    timer: "一眼看清几点下班",
    lunch: "午休不算工时",
    records: "时间去哪了，看得见",
    life: "把工作放回人生里",
    focus: "上班时间，留一段专注",
  },
};

// Seconds are the whole argument. The first two beats are the hook and the
// claim no competitor makes; Records gets the extra second because its bars
// grow, which is the one place motion earns its own time.
const BEATS = [
  { key: "timer", clip: "1-timer.mov", seek: 1.4, seconds: 3.0 },
  { key: "lunch", clip: "3-lunch.mov", seek: 1.2, seconds: 3.0 },
  { key: "records", clip: "4-records-week.mov", seek: 0.4, seconds: 4.5 },
  { key: "life", still: "5.png", seconds: 3.0 },
  { key: "focus", clip: "6-focus.mov", seek: 1.6, seconds: 3.5 },
];

const TOTAL_SECONDS = BEATS.reduce((total, beat) => total + beat.seconds, 0);
if (TOTAL_SECONDS < MIN_SECONDS || TOTAL_SECONDS > MAX_SECONDS) {
  throw new Error(`Beats add up to ${TOTAL_SECONDS}s; App Previews must run ${MIN_SECONDS}–${MAX_SECONDS}s`);
}

const LANGUAGES = (process.env.IOS_PREVIEW_LANGUAGE || "en,zh-CN")
  .split(",")
  .map((value) => value.trim());
const STEMS = { en: "en", "zh-CN": "zh" };

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    throw new Error(
      `${command} ${args.slice(0, 6).join(" ")}… failed:\n${result.stderr ?? result.error?.message}`,
    );
  }
  return result.stdout ?? "";
}

function captionHtml(text, language) {
  // Type sized so the line still reads when the card is a thumbnail: one line,
  // no subtitle, and a weight heavy enough to survive the store's own scaling.
  // The plate is translucent because the capture underneath must stay visible.
  return `<!doctype html><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { background: transparent; }
  body {
    width: ${WIDTH}px; height: ${CAPTION_HEIGHT}px;
    display: flex; align-items: center; justify-content: center;
    font-family: ${fontStack(language)};
  }
  div {
    width: 100%; height: 100%;
    display: flex; align-items: center; justify-content: center;
    background: color-mix(in srgb, ${BRAND.cream} 92%, transparent);
    backdrop-filter: blur(12px);
  }
  p {
    color: ${BRAND.plum};
    font-size: 58px; font-weight: 700; line-height: 1.12;
    letter-spacing: ${language.startsWith("zh") ? "0" : "-0.015em"};
    text-align: center; padding: 0 44px;
    text-wrap: balance;
  }
  </style><div><p>${escapeHTML(text)}</p></div>`;
}

async function renderCaptions(language, workDir) {
  const captions = {};
  for (const beat of BEATS) {
    const outFile = join(workDir, `caption-${beat.key}.png`);
    await captureHtml({
      html: captionHtml(LINES[language][beat.key], language),
      htmlPath: join(workDir, `caption-${beat.key}.html`),
      width: WIDTH,
      height: CAPTION_HEIGHT,
      scale: 1,
      transparent: true,
      outFile,
    });
    captions[beat.key] = outFile;
  }
  return captions;
}

function renderBeat(beat, stem, captionPng, workDir) {
  const out = join(workDir, `beat-${beat.key}.mp4`);
  const common = [
    "-filter_complex",
    beat.still
      // A screen that does not move gets its motion from a slow push. Without
      // it this beat reads as a dead frame in a cut that is otherwise moving.
      ? `[0:v]scale=${WIDTH * 2}:-2,crop=${WIDTH * 2}:${HEIGHT * 2},` +
        `zoompan=z='min(1.0006*zoom\\,1.06)':d=${beat.seconds * FPS}:` +
        `x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${WIDTH}x${HEIGHT}:fps=${FPS}[base];` +
        `[base][1:v]overlay=0:main_h-overlay_h,setsar=1[v]`
      : `[0:v]${FILL},fps=${FPS}[base];` +
        `[base][1:v]overlay=0:main_h-overlay_h,setsar=1[v]`,
    "-map", "[v]",
    "-t", String(beat.seconds),
    "-vsync", "cfr",
    "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
    "-crf", "18", "-preset", "slow", "-an", "-y", out,
  ];
  const input = beat.still
    ? ["-loop", "1", "-t", String(beat.seconds), "-i", join(STILLS, `${stem}-${beat.still}`)]
    : ["-ss", String(beat.seek), "-t", String(beat.seconds), "-i", join(RAW, `${stem}-${beat.clip}`)];
  run("ffmpeg", ["-v", "error", ...input, "-i", captionPng, ...common]);
  return out;
}

function probe(file, entries) {
  return run("ffprobe", [
    "-v", "error", "-show_entries", entries, "-of", "default=nw=1:nk=1", file,
  ]).trim().split("\n");
}

/**
 * Check what the store checks, rather than trusting that ffmpeg ran.
 *
 * The duration floor and the track-alignment check are not pedantry: 3.1.9's
 * first re-upload was refused with MOV_RESAVE_LONGER because the cut was 14.97s
 * with an audio track 31ms longer than the video.
 */
function verify(file) {
  const kinds = probe(file, "stream=codec_type");
  const videos = kinds.filter((kind) => kind === "video");
  const audios = kinds.filter((kind) => kind === "audio");
  if (videos.length !== 1 || audios.length !== 1) {
    throw new Error(`${file}: ${videos.length} video and ${audios.length} audio tracks, expected 1 of each`);
  }

  const [width, height] = probe(file, "stream=width,height");
  if (Number(width) !== WIDTH || Number(height) !== HEIGHT) {
    throw new Error(`${file}: ${width}×${height}, expected ${WIDTH}×${HEIGHT}`);
  }

  const [pixelFormat] = probe(file, "stream=pix_fmt");
  if (pixelFormat !== "yuv420p") {
    throw new Error(`${file}: pixel format ${pixelFormat}, expected yuv420p`);
  }

  const [frameRate] = probe(file, "stream=r_frame_rate");
  if (frameRate !== `${FPS}/1`) {
    throw new Error(`${file}: ${frameRate} fps, expected constant ${FPS}`);
  }

  const [seconds] = probe(file, "format=duration").map(Number);
  if (!(seconds >= MIN_SECONDS && seconds <= MAX_SECONDS)) {
    throw new Error(
      `${file}: ${seconds.toFixed(3)}s, App Previews must run 15–30s and this pipeline keeps ` +
      `${MIN_SECONDS}s of margin so Apple's re-save cannot land under the floor`,
    );
  }

  const [videoSeconds, audioSeconds] = probe(file, "stream=duration").map(Number);
  const drift = Math.abs(videoSeconds - audioSeconds);
  if (!(drift <= SYNC_TOLERANCE)) {
    throw new Error(
      `${file}: video ${videoSeconds.toFixed(3)}s vs audio ${audioSeconds.toFixed(3)}s ` +
      `(${(drift * 1000).toFixed(0)}ms apart). App Store Connect rejects that with MOV_RESAVE_LONGER`,
    );
  }

  return { seconds, width, height, drift };
}

async function build(language) {
  const stem = STEMS[language];
  if (!stem) throw new Error(`IOS_PREVIEW_LANGUAGE must be one of ${Object.keys(STEMS).join(", ")}`);
  const workDir = mkdtempSync(join(tmpdir(), "owc-preview-"));
  try {
    const captions = await renderCaptions(language, workDir);
    const parts = BEATS.map((beat) => renderBeat(beat, stem, captions[beat.key], workDir));
    const listFile = join(workDir, "parts.txt");
    writeFileSync(listFile, parts.map((part) => `file '${part}'`).join("\n"));
    const out = join(DIR, `${stem}-review-${WIDTH}x${HEIGHT}.mov`);
    run("ffmpeg", [
      "-v", "error",
      "-f", "concat", "-safe", "0", "-i", listFile,
      // Silence is not optional: App Store Connect rejects a preview with no
      // audio track, however muted the store plays it. Give it the exact length
      // of the cut rather than -shortest, which leaves the tracks milliseconds
      // apart and fails processing.
      "-f", "lavfi", "-t", String(TOTAL_SECONDS), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
      "-map", "0:v", "-map", "1:a",
      "-t", String(TOTAL_SECONDS),
      "-c:v", "copy", "-c:a", "aac", "-b:a", "128k",
      "-movflags", "+faststart", "-y", out,
    ]);

    const { seconds, drift } = verify(out);
    console.log(
      `built ${out} (${seconds.toFixed(2)}s, ${WIDTH}×${HEIGHT}, tracks ${(drift * 1000).toFixed(0)}ms apart, silent stereo AAC)`,
    );
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
}

mkdirSync(DIR, { recursive: true });
readFileSync(join(RAW, `${STEMS[LANGUAGES[0]] ?? "en"}-1-timer.mov`));
for (const language of LANGUAGES) await build(language);

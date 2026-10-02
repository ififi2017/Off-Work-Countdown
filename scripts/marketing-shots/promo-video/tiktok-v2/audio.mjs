// Synthesize the 21-second TikTok edit soundtrack; cues match scene.html.
//
//   node audio.mjs out/timeline.json out/sfx.wav            # sound effects only
//   node audio.mjs out/timeline.json out/mix.wav --music    # effects + music bed
//
// Everything is generated here, with no sample files, so there is nothing to
// license. The woodfish knock uses the same recipe as components/MiniCountdown.tsx.

import { readFileSync, writeFileSync } from "node:fs";

const [timelinePath, outPath] = process.argv.slice(2);
const withMusic = process.argv.includes("--music");
const { variant, duration, cuts, knocks } = JSON.parse(readFileSync(timelinePath, "utf8"));
const T = { total: duration };

const SR = 48000;
const LEN = Math.ceil((T.total + 0.2) * SR);
const L = new Float32Array(LEN), R = new Float32Array(LEN);
const verbSend = new Float32Array(LEN);

let seed = 97;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const noise = () => rnd() * 2 - 1;
const TAU = Math.PI * 2;
const midi = (n) => 440 * 2 ** ((n - 69) / 12);

/** Mix a mono buffer into the stereo bus. pan -1..1, verb = reverb send. */
function place(t0, buf, gain = 1, pan = 0, verb = 0) {
  const start = Math.round(t0 * SR);
  const gl = Math.cos(((pan + 1) * Math.PI) / 4) * gain, gr = Math.sin(((pan + 1) * Math.PI) / 4) * gain;
  for (let i = 0; i < buf.length; i++) {
    const j = start + i;
    if (j < 0 || j >= LEN) continue;
    L[j] += buf[i] * gl; R[j] += buf[i] * gr;
    if (verb) verbSend[j] += buf[i] * gain * verb;
  }
}
const make = (sec, fn) => { const n = Math.ceil(sec * SR), b = new Float32Array(n); for (let i = 0; i < n; i++) b[i] = fn(i / SR, i); return b; };

/* simple filters */
function onePoleLP(buf, hz) { const a = Math.exp(-TAU * hz / SR); let y = 0; for (let i = 0; i < buf.length; i++) { y = (1 - a) * buf[i] + a * y; buf[i] = y; } return buf; }
function onePoleHP(buf, hz) { const a = Math.exp(-TAU * hz / SR); let y = 0, x1 = 0; for (let i = 0; i < buf.length; i++) { y = a * (y + buf[i] - x1); x1 = buf[i]; buf[i] = y; } return buf; }
/** State-variable band-pass with a per-sample cutoff. */
function svfBP(buf, hzAt, q = 0.7) {
  let low = 0, band = 0;
  for (let i = 0; i < buf.length; i++) {
    const f = 2 * Math.sin(Math.PI * Math.min(hzAt(i / SR), SR / 6) / SR);
    low += f * band; const high = buf[i] - low - q * band; band += f * high; buf[i] = band;
  }
  return buf;
}

/* ---------------- sound effects ---------------- */
const tick = (bright = 1) => onePoleHP(make(0.045, (s) => (noise() * Math.exp(-s * 900) * 0.8 + Math.sin(TAU * 2600 * bright * s) * Math.exp(-s * 160) * 0.5)), 900);
const tap = () => onePoleHP(make(0.05, (s) => Math.sin(TAU * 1650 * s) * Math.exp(-s * 140) * 0.7 + noise() * Math.exp(-s * 700) * 0.4), 400);
const whoosh = (dur, up = true) => {
  const b = make(dur, (s) => { const p = s / dur; return noise() * Math.sin(Math.PI * p) ** 1.6; });
  return svfBP(b, (s) => { const p = s / dur; return up ? 300 + 2600 * p : 2900 - 2500 * p; }, 0.9);
};
const bell = (freq, dur = 1.6, bright = 1) => make(dur, (s) => {
  const env = Math.min(1, s / 0.008);
  return env * (Math.sin(TAU * freq * s) * Math.exp(-s * 2.6) * 0.6
    + Math.sin(TAU * freq * 2.01 * s) * Math.exp(-s * 5) * 0.25 * bright
    + Math.sin(TAU * freq * 3.02 * s) * Math.exp(-s * 9) * 0.12 * bright);
});
const beep = (freq, dur = 0.14) => make(dur, (s) => Math.sin(TAU * freq * s) * Math.min(1, s / 0.004) * Math.exp(-s * 18) * 0.8);
/** components/MiniCountdown.tsx: impact noise exciting three cavity modes, plus a soft rebound. */
function woodfish(variation = 0) {
  const strike = (level) => make(0.15, (s) => {
    const attack = Math.min(1, s / 0.0012), decay = Math.exp(-s * 34);
    const cavity = Math.sin(TAU * (560 + variation) * s) * 0.52 + Math.sin(TAU * (873 + variation * 0.7) * s) * 0.27 + Math.sin(TAU * (1327 + variation * 0.4) * s) * 0.12;
    return (cavity + noise() * Math.exp(-s * 95) * 0.32) * attack * decay * level;
  });
  const a = strike(1), b = strike(0.22), out = new Float32Array(a.length + 600);
  a.forEach((v, i) => (out[i] += v)); b.forEach((v, i) => (out[i + 576] += v));
  return onePoleLP(onePoleHP(out, 180), 2600);
}
const popper = () => {
  const b = make(0.35, (s) => (noise() * Math.exp(-s * 38) + Math.sin(TAU * (140 - 90 * s) * s) * Math.exp(-s * 16) * 0.9) * Math.min(1, s / 0.003));
  return onePoleLP(onePoleLP(b, 3800), 6000);
};
/** Falling confetti: sparse, soft high chimes from a pentatonic set, thinning out. */
const sparkle = (dur) => {
  const b = new Float32Array(Math.ceil(dur * SR));
  const notes = [88, 91, 93, 95, 98, 100].map(midi);
  for (let i = 0; i < b.length; i++) {
    const p = i / b.length;
    if (rnd() < 0.00045 * (1 - p) ** 1.4) {
      const f = notes[Math.floor(rnd() * notes.length)], amp = 0.12 + rnd() * 0.18;
      for (let k = 0; k < SR * 0.3 && i + k < b.length; k++) { const s = k / SR; b[i + k] += Math.sin(TAU * f * s) * amp * Math.min(1, s / 0.01) * Math.exp(-s * 16); }
    }
  }
  return b;
};
const sub = () => make(1.4, (s) => Math.sin(TAU * (52 + 20 * Math.exp(-s * 8)) * s) * Math.exp(-s * 2.8) * Math.min(1, s / 0.01));
function rain(dur) {
  const b = make(dur, () => noise() * 0.5);
  onePoleHP(onePoleLP(b, 2400), 350);
  for (let i = 0; i < b.length; i++) if (rnd() < 0.0009) { const amp = 0.15 + rnd() * 0.35; for (let k = 0; k < 200 && i + k < b.length; k++) b[i + k] += noise() * amp * Math.exp(-k / 30); }
  return b;
}
function ratchet(t0, dur, from, to, gain) {
  let t = 0;
  while (t < dur) { place(t0 + t, tick(1.25), gain, 0.3); t += 1 / (from + (to - from) * (t / dur)); }
}

/* ---------------- editorial cues ---------------- */
// Opening action is audible immediately; the shared body starts at 3 seconds.
if (variant === "office") {
  [.03, .65, 1.25].forEach((at, i) => place(at, tick(1 + i * .08), .26));
  place(1.58, whoosh(.24), .12, 0, .08);
} else if (variant === "progress") {
  place(.02, tap(), .27);
  place(.08, bell(midi(79), .55, .3), .1, 0, .1);
}
knocks.forEach((at, i) => place(at, woodfish(i % 2 * 7), .66, 0, .07));
for (const at of cuts.slice(0, 5)) place(at - .06, whoosh(.22), .075, 0, .08);
place(8.4, tap(), .18);
[13.8, 14.8, 15.8].forEach(at => place(at, beep(880, .11), .25));
place(16.8, bell(midi(84), 1.5, .6), .22, 0, .25);
place(16.8, popper(), .22, -.2, .12);
place(16.88, sparkle(1.5), .16, .2, .2);
place(17.8, bell(midi(79), 1.3, .4), .1, 0, .2);

/* A light, muted electric-piano bed; few transients leave room for the UI. */
if (withMusic) {
  const key = (freq, dur) => make(dur, s => {
    const env = Math.min(1, s / .009) * Math.exp(-s * 2.8) * Math.min(1, (dur - s) / .08);
    return (Math.sin(TAU * freq * s) + .24 * Math.sin(TAU * freq * 2 * s) * Math.exp(-s * 5)
      + .05 * Math.sin(TAU * freq * 3 * s)) * env;
  });
  const bass = freq => make(.7, s => Math.sin(TAU * freq * s) * Math.min(1, s / .025) * Math.exp(-s * 5));
  const chords = [[60, 64, 67, 71], [55, 59, 62, 69], [57, 60, 64, 67], [53, 57, 60, 64]];
  const beat = .6;
  for (let i = 0; i * beat < 13.8; i++) {
    const at = i * beat, chord = chords[Math.floor(i / 4) % 4];
    const n = chord[i % 4];
    place(at, key(midi(n + 12), 1.3), .065, i % 2 ? .22 : -.22, .17);
    if (i % 2 === 0) place(at, bass(midi(chord[0] - 12)), .08, 0, .04);
    if (i % 4 === 0) chord.forEach((note, j) => place(at + j * .008, key(midi(note), 2), .027, 0, .2));
  }
  [60, 64, 67, 74].forEach((n, i) => place(16.8 + i * .065, key(midi(n), 3), .07, -.2 + i * .13, .22));
}

/* ---------------- reverb (Schroeder) + master ---------------- */
{
  const combs = [1557, 1617, 1491, 1422].map((d) => ({ d, buf: new Float32Array(d), i: 0, fb: 0.78, lp: 0 }));
  const aps = [225, 556].map((d) => ({ d, buf: new Float32Array(d), i: 0 }));
  for (let n = 0; n < LEN; n++) {
    const x = verbSend[n] * 0.25;
    let y = 0;
    for (const c of combs) { const out = c.buf[c.i]; c.lp = out * 0.6 + c.lp * 0.4; c.buf[c.i] = x + c.lp * c.fb; c.i = (c.i + 1) % c.d; y += out; }
    for (const a of aps) { const bo = a.buf[a.i]; const v = -y * 0.5 + bo; a.buf[a.i] = y + bo * 0.5; a.i = (a.i + 1) % a.d; y = v; }
    L[n] += y * 0.9; R[n] += y * 0.85;
  }
}
// Level by loudness, not by the loudest hit: gated RMS to about -17 dBFS,
// then a soft knee from -4.4 dBFS so transients (and their inter-sample peaks) stay under 0 dBTP.
let sum = 0, count = 0;
const block = SR / 10;
for (let b = 0; b + block <= LEN; b += block) {
  let e = 0;
  for (let i = b; i < b + block; i++) e += (L[i] * L[i] + R[i] * R[i]) / 2;
  e /= block;
  if (e > 1e-5) { sum += e; count++; }
}
const norm = 10 ** (-17 / 20) / Math.sqrt(sum / Math.max(1, count));
const knee = 0.6, room = 0.1;
const limit = (x) => { const a = Math.abs(x); return a <= knee ? x : Math.sign(x) * (knee + room * Math.tanh((a - knee) / room)); };
for (let i = 0; i < LEN; i++) { L[i] = limit(L[i] * norm); R[i] = limit(R[i] * norm); }
const data = Buffer.alloc(44 + LEN * 4);
data.write("RIFF", 0); data.writeUInt32LE(36 + LEN * 4, 4); data.write("WAVEfmt ", 8);
data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(2, 22); data.writeUInt32LE(SR, 24);
data.writeUInt32LE(SR * 4, 28); data.writeUInt16LE(4, 32); data.writeUInt16LE(16, 34); data.write("data", 36); data.writeUInt32LE(LEN * 4, 40);
for (let i = 0; i < LEN; i++) {
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i])) * 32767), 44 + i * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i])) * 32767), 46 + i * 4);
}
writeFileSync(outPath, data);
console.log(`${outPath}  (${(LEN / SR).toFixed(1)}s${withMusic ? ", with music" : ""})`);

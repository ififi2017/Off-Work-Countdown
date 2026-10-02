// Synthesize the promo soundtrack from scene.html's timeline.
//
//   node audio.mjs out/timeline.json out/sfx.wav            # sound effects only
//   node audio.mjs out/timeline.json out/mix.wav --music    # effects + music bed
//
// Everything is generated here, with no sample files, so there is nothing to
// license. The woodfish knock uses the same recipe as components/MiniCountdown.tsx.

import { readFileSync, writeFileSync } from "node:fs";

const [timelinePath, outPath] = process.argv.slice(2);
const withMusic = process.argv.includes("--music");
const { O, T, cam } = JSON.parse(readFileSync(timelinePath, "utf8"));

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

/* ---- act 1 ---- */
const warmEnd = O.warm + 1.0;
{
  const r = rain(warmEnd + 0.5);
  for (let i = 0; i < r.length; i++) { const s = i / SR; r[i] *= s > O.warm ? Math.max(0, 1 - (s - O.warm) / 1.0) : Math.min(1, s / 0.8); }
  place(0, r, 0.22, 0);
}
for (let s = 0.4; s < O.phone2; s += 1) {
  const near = s >= O.clock && s < O.phone1 ? 1 : 0.35;
  place(s, tick(), 0.28 * near, 0.45);
}
ratchet(O.clock, 0.6, 18, 60, 0.12);
ratchet(O.phone1, 0.6, 18, 60, 0.1);
for (const [at, d] of cam) if (at > 0.5 && at < O.fade) place(at, whoosh(d + 0.15, at !== O.back), 0.18, 0, 0.2);
place(O.get - 0.02, tap(), 0.45, 0.1);
place(O.ringB, bell(midi(88), 0.8), 0.18, 0.2, 0.3);
place(O.tapOpen - 0.02, tap(), 0.45, 0.1);
place(O.launch, whoosh(0.55, true), 0.22, 0, 0.3);
// relief: a bright arpeggio as the room warms up
[76, 79, 83, 88, 91].forEach((n, i) => place(O.warm + i * 0.09, bell(midi(n), 2.2), 0.13, i % 2 ? 0.3 : -0.3, 0.5));
[O.knock, O.knock + 0.45].forEach((k, i) => place(k, woodfish(i * 7), 0.9, -0.1, 0.1));
place(O.banner, bell(midi(84), 0.9), 0.2, 0.25, 0.3);
place(O.banner + 0.12, bell(midi(91), 1.1), 0.18, 0.25, 0.3);

/* ---- brand reveal ---- */
place(T.rv, whoosh(1.1, true), 0.12, 0, 0.4);
place(T.rv + 1.0, sub(), 0.28, 0);
place(T.rv + 1.0, bell(midi(84), 2.4), 0.16, 0, 0.6);

/* ---- product tour ---- */
place(T.phoneIn, whoosh(1.0, true), 0.2, 0, 0.2);
ratchet(T.ff1, T.ff1End - T.ff1, 6, 26, 0.08);
ratchet(T.ff2, T.ff2End - T.ff2, 6, 26, 0.08);
place(T.lunch, bell(midi(79), 1.2), 0.16, -0.2, 0.3);
place(T.lunch + 0.14, bell(midi(74), 1.4), 0.14, -0.2, 0.3);
place(T.home, whoosh(0.7, false), 0.18, 0, 0.2);
place(T.home + 0.7, beep(midi(88), 0.09), 0.14, 0.2, 0.2);
place(T.watch, whoosh(0.8, true), 0.16, 0.4, 0.2);
place(T.sched + 0.3, whoosh(0.6, true), 0.14, 0, 0.2);
[72, 74, 76, 79, 81].forEach((n, i) => place(T.sched + 1.0 + i * 0.12, bell(midi(n + 12), 0.5, 0.5), 0.1, -0.4 + i * 0.2, 0.2));
place(T.sched + 1.7 + 1.6, bell(midi(96), 0.8), 0.08, 0.3, 0.4);
place(T.desk, whoosh(0.8, false), 0.18, 0, 0.2);
[2.5, 2.95, 3.3, 3.6].forEach((d, i) => place(T.desk + d, woodfish((i % 5) * 7), 0.9, 0, 0.1));

/* ---- finale ---- */
[3, 2, 1].forEach((n) => place(T.zero - n, beep(880, 0.12), 0.32, 0));
place(T.zero, beep(1320, 0.3), 0.3, 0);
place(T.zero, popper(), 0.42, -0.6, 0.2);
place(T.zero + 0.04, popper(), 0.42, 0.6, 0.2);
place(T.zero + 0.05, sparkle(4.5), 0.35, -0.35, 0.5);
place(T.zero + 0.08, sparkle(4.5), 0.35, 0.35, 0.5);
place(T.end + 1.05, bell(midi(84), 2.6), 0.16, 0, 0.6);

/* ---------------- music bed ---------------- */
if (withMusic) {
  const music = { L: new Float32Array(LEN), R: new Float32Array(LEN) };
  const mplace = (t0, buf, gain, pan = 0) => {
    const start = Math.round(t0 * SR);
    const gl = Math.cos(((pan + 1) * Math.PI) / 4) * gain, gr = Math.sin(((pan + 1) * Math.PI) / 4) * gain;
    for (let i = 0; i < buf.length; i++) { const j = start + i; if (j < 0 || j >= LEN) continue; music.L[j] += buf[i] * gl; music.R[j] += buf[i] * gr; verbSend[j] += buf[i] * gain * 0.35; }
  };
  const padNote = (freq, dur, attack = 0.8, release = 1.2) => onePoleLP(make(dur + release, (s) => {
    const env = Math.min(1, s / attack) * (s > dur ? Math.max(0, 1 - (s - dur) / release) : 1);
    let v = 0;
    for (const det of [-0.004, 0.004]) for (let h = 1; h <= 5; h++) v += Math.sin(TAU * freq * (1 + det) * h * s + h) / (h * 1.6);
    return v * env * 0.18;
  }), 1600);
  const pluck = (freq, dur = 1.2) => {
    const n = Math.round(SR / freq), line = Float32Array.from({ length: n }, () => noise());
    const out = new Float32Array(Math.ceil(dur * SR));
    let idx = 0;
    for (let i = 0; i < out.length; i++) { const a = line[idx], b = line[(idx + 1) % n]; line[idx] = (a + b) * 0.5 * 0.996; out[i] = a; idx = (idx + 1) % n; }
    return onePoleLP(out, 3800);
  };
  const kick = () => make(0.4, (s) => Math.sin(TAU * (48 + 80 * Math.exp(-s * 30)) * s) * Math.exp(-s * 9));
  const hat = () => onePoleHP(make(0.05, (s) => noise() * Math.exp(-s * 90)), 7000);

  // before DoneAt: a low, uneasy drone that swells as the App Store opens
  const dark = [45, 52, 59, 60];
  dark.forEach((n) => mplace(0, padNote(midi(n), O.warm - 0.3, 2.5, 0.8), 0.26, n % 2 ? 0.3 : -0.3));
  // after: C – G – Am – F at 100 bpm, starting on the relief beat
  const beat = 0.6, bar = beat * 4, t0 = O.warm;
  const chords = [[48, 55, 64, 67, 72], [43, 50, 59, 62, 67], [45, 52, 60, 64, 69], [41, 48, 57, 60, 65]];
  const endAt = T.fin - 0.2;
  for (let b = 0; t0 + b * bar < endAt; b++) {
    const at = t0 + b * bar, ch = chords[b % 4];
    const dur = Math.min(bar, endAt - at);
    ch.forEach((n, i) => mplace(at, padNote(midi(n), dur, 0.25, 0.9), 0.32, -0.4 + i * 0.2));
    const arp = [ch[2] + 12, ch[3] + 12, ch[4] + 12, ch[3] + 12];
    for (let e = 0; e < 8; e++) {
      const tt = at + e * beat / 2;
      if (tt >= endAt) break;
      mplace(tt, pluck(midi(arp[e % 4])), 0.2 * (tt < T.rv ? 0.7 : 1), e % 2 ? 0.35 : -0.35);
    }
    if (at >= T.phoneIn - 0.1) for (let q = 0; q < 4; q++) {
      const tt = at + q * beat;
      if (tt >= endAt) break;
      if (q % 2 === 0) mplace(tt, kick(), 0.5);
      mplace(tt + beat / 2, hat(), 0.12, 0.25);
    }
  }
  // the countdown: a held, filtered chord; then the resolution at zero
  [48, 55, 64].forEach((n) => mplace(T.fin - 0.2, padNote(midi(n), T.zero - T.fin, 0.6, 0.4), 0.22));
  [36, 48, 55, 64, 67, 74, 79].forEach((n, i) => mplace(T.zero, padNote(midi(n), T.total - T.zero - 1.2, 0.05, 1.2), 0.3, -0.45 + i * 0.15));
  [72, 76, 79, 84, 88].forEach((n, i) => mplace(T.zero + i * 0.08, pluck(midi(n), 2.0), 0.28, -0.4 + i * 0.2));
  // fade the bed at the very end
  for (let i = 0; i < LEN; i++) {
    const s = i / SR, fade = s > T.total - 1.5 ? Math.max(0, (T.total - s) / 1.5) : 1;
    L[i] += music.L[i] * 0.55 * fade; R[i] += music.R[i] * 0.55 * fade;
  }
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

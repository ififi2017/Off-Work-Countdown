// Soundtrack for promo V4, synthesized from the page's cue list. No sample files.
//
//   node audio.mjs out/timeline.json out/sfx.wav           # effects only
//   node audio.mjs out/timeline.json out/mix.wav --music   # effects + music bed
//
// 96 BPM, one bar = 2.5 s, and every shot change sits on a bar line, so the music
// changes where the picture does: a question (Am–F) while the clock is alone, the
// answer (C–G) when the countdown arrives, a light groove as the phone appears, a held
// suspension through the last three seconds, and C again at zero.
// Generators are carried over from ../tiktok-v3/audio.mjs.

import { readFileSync, writeFileSync } from "node:fs";

const [timelinePath, outPath] = process.argv.slice(2);
const withMusic = process.argv.includes("--music");
const TL = JSON.parse(readFileSync(timelinePath, "utf8"));
const { bar: BAR } = TL;

const SR = 48000;
const LEN = Math.ceil(TL.end * SR);
const L = new Float32Array(LEN), R = new Float32Array(LEN), verb = new Float32Array(LEN);
let seed = 131;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const noise = () => rnd() * 2 - 1;
const TAU = Math.PI * 2;
const midi = (n) => 440 * 2 ** ((n - 69) / 12);

function place(t0, buf, gain = 1, pan = 0, send = 0, bus = null) {
  const start = Math.round(t0 * SR);
  const gl = Math.cos(((pan + 1) * Math.PI) / 4) * gain, gr = Math.sin(((pan + 1) * Math.PI) / 4) * gain;
  const oL = bus ? bus.L : L, oR = bus ? bus.R : R;
  for (let i = 0; i < buf.length; i++) {
    const j = start + i;
    if (j < 0 || j >= LEN) continue;
    oL[j] += buf[i] * gl; oR[j] += buf[i] * gr;
    if (send) verb[j] += buf[i] * gain * send;
  }
}
const make = (sec, fn) => { const n = Math.ceil(sec * SR), b = new Float32Array(n); for (let i = 0; i < n; i++) b[i] = fn(i / SR, i); return b; };
function lp(buf, hz) { const a = Math.exp(-TAU * hz / SR); let y = 0; for (let i = 0; i < buf.length; i++) { y = (1 - a) * buf[i] + a * y; buf[i] = y; } return buf; }
function hp(buf, hz) { const a = Math.exp(-TAU * hz / SR); let y = 0, x1 = 0; for (let i = 0; i < buf.length; i++) { y = a * (y + buf[i] - x1); x1 = buf[i]; buf[i] = y; } return buf; }

/* ---------- effects: few, quiet, each tied to something on screen ---------- */
const bell = (freq, dur = 1.6, bright = 1, attack = 0.008) => make(dur, (s) => Math.min(1, s / attack) * (
  Math.sin(TAU * freq * s) * Math.exp(-s * 2.6) * 0.6 + Math.sin(TAU * freq * 2.01 * s) * Math.exp(-s * 5) * 0.25 * bright + Math.sin(TAU * freq * 3.02 * s) * Math.exp(-s * 9) * 0.12 * bright));
const tick = (bright = 1) => hp(make(0.05, (s) => noise() * Math.exp(-s * 900) * 0.7 + Math.sin(TAU * 2400 * bright * s) * Math.exp(-s * 150) * 0.55 + Math.sin(TAU * 900 * s) * Math.exp(-s * 90) * 0.3), 500);

for (const { t, kind } of TL.cues) {
  switch (kind) {
    // eight characters arrive 45 ms apart: eight soft ticks, rising a little
    case "roll": for (let i = 0; i < 8; i++) place(t + i * 0.045, tick(0.7 + i * 0.05), 0.12 + i * 0.01, -0.3 + i * 0.08, 0.1); break;
    case "fill": place(t, make(1.1, (s) => Math.sin(TAU * (520 + 240 * (s / 1.1) ** 0.6) * s) * Math.sin(Math.PI * s / 1.1) ** 2 * 0.16), 0.55, 0, 0.3); break;
    case "tick": place(t, tick(1), 0.34, 0, 0.12); break;
    case "zero": [72, 76, 79, 84].forEach((n, i) => place(t + i * 0.05, bell(midi(n), 2.6), 0.1, (i - 1.5) * 0.25, 0.5)); break;
    case "brand": place(t, bell(midi(84), 2.6, 0.6), 0.12, 0, 0.6); place(t + 0.09, bell(midi(91), 2.2, 0.5), 0.07, 0.15, 0.6); break;
    default: throw new Error(`unknown cue ${kind}`);
  }
}

/* ---------- music bed ---------- */
if (withMusic) {
  const bus = { L: new Float32Array(LEN), R: new Float32Array(LEN) };
  const pad = (freq, dur, attack = 0.4, release = 1.0) => lp(make(dur + release, (s) => {
    const env = Math.min(1, s / attack) * (s > dur ? Math.max(0, 1 - (s - dur) / release) : 1);
    let v = 0;
    for (const det of [-0.004, 0.004]) for (let h = 1; h <= 5; h++) v += Math.sin(TAU * freq * (1 + det) * h * s + h) / (h * 1.6);
    return v * env * 0.16;
  }), 1500);
  const pluck = (freq, dur = 1.1) => {
    const n = Math.round(SR / freq), line = Float32Array.from({ length: n }, () => noise());
    const o = new Float32Array(Math.ceil(dur * SR)); let idx = 0;
    for (let i = 0; i < o.length; i++) { const a = line[idx], b = line[(idx + 1) % n]; line[idx] = (a + b) * 0.5 * 0.996; o[i] = a; idx = (idx + 1) % n; }
    return lp(o, 3200);
  };
  const kick = () => make(0.35, (s) => Math.sin(TAU * (48 + 80 * Math.exp(-s * 30)) * s) * Math.exp(-s * 10));
  const hat = () => hp(make(0.04, (s) => noise() * Math.exp(-s * 100)), 7000);
  const beat = BAR / 4;
  const V = {
    Am: [45, 52, 60, 64, 69], F: [41, 48, 57, 60, 65], C: [48, 55, 64, 67, 72],
    G: [43, 50, 59, 62, 67], Gsus: [43, 50, 60, 62, 67], Fadd9: [41, 48, 55, 57, 64],
  };
  // [chord, pad gain, arpeggio?, groove?] per bar
  const bars = [
    ["Am", 0.2, false, false], ["F", 0.22, false, false],        // the clock alone: a question
    ["C", 0.26, true, false], ["G", 0.26, true, false],          // the countdown arrives: the answer
    ["Am", 0.26, true, true], ["F", 0.26, true, true],           // the phone: a light groove
    ["Gsus", 0.24, false, false],                                // 16:59:57 — hold still
    ["C", 0.26, true, false],                                    // zero
    ["Fadd9", 0.24, true, false], ["C", 0.24, false, false],     // end card, then ring out
  ];
  bars.forEach(([name, g, arp, groove], b) => {
    const at = b * BAR, ch = V[name], last = b === bars.length - 1;
    const attack = b < 2 ? 0.9 : b === 7 ? 0.04 : 0.25;
    ch.forEach((n, i) => place(at, pad(midi(n), last ? BAR - 1.2 : BAR, attack, last ? 1.2 : 0.8), g, -0.4 + i * 0.2, 0.3, bus));
    if (b === 7) [36, 79, 84].forEach((n, i) => place(at, pad(midi(n), BAR, 0.04, 1.0), 0.1, -0.3 + i * 0.3, 0.4, bus));
    if (arp) {
      const line = [ch[2] + 12, ch[3] + 12, ch[4] + 12, ch[3] + 12, ch[2] + 24, ch[4] + 12, ch[3] + 12, ch[4] + 12];
      for (let e = 0; e < 8; e++) place(at + (e * beat) / 2, pluck(midi(line[e])), 0.16 + (e === 0 ? 0.04 : 0), e % 2 ? 0.35 : -0.35, 0.3, bus);
    }
    if (groove) for (let q = 0; q < 4; q++) {
      if (q % 2 === 0) place(at + q * beat, kick(), 0.36, 0, 0, bus);
      place(at + q * beat + beat / 2, hat(), 0.08, 0.25, 0, bus);
    }
  });
  // the end card's last note
  [72, 76, 79].forEach((n, i) => place(9 * BAR + i * 0.12, pluck(midi(n), 2.0), 0.16, -0.3 + i * 0.3, 0.4, bus));
  for (let i = 0; i < LEN; i++) {
    const s = i / SR, fade = s > TL.end - 1.0 ? Math.max(0, (TL.end - s) / 1.0) : 1;
    L[i] += bus.L[i] * fade * 0.6; R[i] += bus.R[i] * fade * 0.6;
  }
}

/* ---------- reverb + level ---------- */
{
  const combs = [1557, 1617, 1491, 1422].map((d) => ({ d, buf: new Float32Array(d), i: 0, lp: 0 }));
  const aps = [225, 556].map((d) => ({ d, buf: new Float32Array(d), i: 0 }));
  for (let n = 0; n < LEN; n++) {
    const x = verb[n] * 0.25; let y = 0;
    for (const c of combs) { const o = c.buf[c.i]; c.lp = o * 0.6 + c.lp * 0.4; c.buf[c.i] = x + c.lp * 0.78; c.i = (c.i + 1) % c.d; y += o; }
    for (const a of aps) { const bo = a.buf[a.i]; const v = -y * 0.5 + bo; a.buf[a.i] = y + bo * 0.5; a.i = (a.i + 1) % a.d; y = v; }
    L[n] += y * 0.9; R[n] += y * 0.85;
  }
}
// The music cut is brought to about -17 dBFS RMS here and finished with loudnorm in
// render.mjs. The effects-only cut is mostly silence, so loudness normalization would
// blow its few cues up; it is peak-normalized instead and left quiet under platform music.
let norm;
if (withMusic) {
  let sum = 0, count = 0;
  const block = SR / 10;
  for (let b = 0; b + block <= LEN; b += block) { let e = 0; for (let i = b; i < b + block; i++) e += (L[i] * L[i] + R[i] * R[i]) / 2; e /= block; if (e > 1e-5) { sum += e; count++; } }
  norm = 10 ** (-17 / 20) / Math.sqrt(sum / Math.max(1, count));
} else {
  let peak = 1e-9;
  for (let i = 0; i < LEN; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  norm = 10 ** (-6 / 20) / peak;
}
const knee = 0.6, room = 0.1;
const limit = (x) => { const a = Math.abs(x); return a <= knee ? x : Math.sign(x) * (knee + room * Math.tanh((a - knee) / room)); };
const data = Buffer.alloc(44 + LEN * 4);
data.write("RIFF", 0); data.writeUInt32LE(36 + LEN * 4, 4); data.write("WAVEfmt ", 8);
data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(2, 22); data.writeUInt32LE(SR, 24);
data.writeUInt32LE(SR * 4, 28); data.writeUInt16LE(4, 32); data.writeUInt16LE(16, 34); data.write("data", 36); data.writeUInt32LE(LEN * 4, 40);
for (let i = 0; i < LEN; i++) {
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, limit(L[i] * norm))) * 32767), 44 + i * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, limit(R[i] * norm))) * 32767), 46 + i * 4);
}
writeFileSync(outPath, data);
console.log(`${outPath}  (${(LEN / SR).toFixed(1)}s${withMusic ? ", with music" : ""})`);

// Soundtrack for one TikTok v3 variant, synthesized from the page's cue list.
//
//   node audio.mjs out/glance/timeline.json out/glance/sfx.wav           # effects only
//   node audio.mjs out/glance/timeline.json out/glance/mix.wav --music   # effects + music bed
//
// No sample files. The woodfish knock follows components/MiniCountdown.tsx;
// several generators are carried over from ../audio.mjs.

import { readFileSync, writeFileSync } from "node:fs";

const [timelinePath, outPath] = process.argv.slice(2);
const withMusic = process.argv.includes("--music");
const TL = JSON.parse(readFileSync(timelinePath, "utf8"));
const { B } = TL;

const SR = 48000;
const LEN = Math.ceil((TL.end + 0.3) * SR);
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
function bp(buf, hzAt, q = 0.7) {
  let low = 0, band = 0;
  for (let i = 0; i < buf.length; i++) {
    const f = 2 * Math.sin(Math.PI * Math.min(hzAt(i / SR), SR / 6) / SR);
    low += f * band; const high = buf[i] - low - q * band; band += f * high; buf[i] = band;
  }
  return buf;
}

/* ---------- generators ---------- */
const bell = (freq, dur = 1.6, bright = 1, attack = 0.008) => make(dur, (s) => Math.min(1, s / attack) * (
  Math.sin(TAU * freq * s) * Math.exp(-s * 2.6) * 0.6 + Math.sin(TAU * freq * 2.01 * s) * Math.exp(-s * 5) * 0.25 * bright + Math.sin(TAU * freq * 3.02 * s) * Math.exp(-s * 9) * 0.12 * bright));
const tick = (bright = 1) => hp(make(0.05, (s) => noise() * Math.exp(-s * 900) * 0.7 + Math.sin(TAU * 2400 * bright * s) * Math.exp(-s * 150) * 0.55 + Math.sin(TAU * 900 * s) * Math.exp(-s * 90) * 0.3), 500);
const click = () => hp(make(0.04, (s) => Math.sin(TAU * 2100 * s) * Math.exp(-s * 220) * 0.6 + noise() * Math.exp(-s * 900) * 0.5), 600);
const key = () => { const f = 1400 + rnd() * 900; return hp(make(0.035, (s) => (noise() * 0.6 + Math.sin(TAU * f * s) * 0.5) * Math.exp(-s * 260)), 900); };
const whoosh = (dur, up = true) => bp(make(dur, (s) => noise() * Math.sin(Math.PI * (s / dur)) ** 1.8), (s) => { const p = s / dur; return up ? 350 + 2400 * p : 2600 - 2200 * p; }, 0.9);
const woodfish = (variation = 0) => {
  const strike = (level) => make(0.15, (s) => {
    const cavity = Math.sin(TAU * (560 + variation) * s) * 0.52 + Math.sin(TAU * (873 + variation * 0.7) * s) * 0.27 + Math.sin(TAU * (1327 + variation * 0.4) * s) * 0.12;
    return (cavity + noise() * Math.exp(-s * 95) * 0.32) * Math.min(1, s / 0.0012) * Math.exp(-s * 34) * level;
  });
  const a = strike(1), b2 = strike(0.22), out = new Float32Array(a.length + 600);
  a.forEach((v, i) => (out[i] += v)); b2.forEach((v, i) => (out[i + 576] += v));
  return lp(hp(out, 180), 2600);
};
const buzz = () => make(0.62, (s) => {
  const on = (s < 0.22 || (s > 0.36 && s < 0.58)) ? 1 : 0;
  const env = on * Math.min(1, (s % 0.36) / 0.01);
  return Math.tanh(Math.sin(TAU * 172 * s) * 3) * 0.35 * env * (0.8 + 0.2 * Math.sin(TAU * 31 * s));
});
const beep = (freq, dur = 0.14) => make(dur, (s) => Math.sin(TAU * freq * s) * Math.min(1, s / 0.005) * Math.exp(-s * 18) * 0.8);
const popper = () => lp(lp(make(0.35, (s) => (noise() * Math.exp(-s * 38) + Math.sin(TAU * (140 - 90 * s) * s) * Math.exp(-s * 16) * 0.9) * Math.min(1, s / 0.003)), 3800), 6000);
const sparkle = (dur) => {
  const b = new Float32Array(Math.ceil(dur * SR)), notes = [88, 91, 93, 95, 98, 100].map(midi);
  for (let i = 0; i < b.length; i++) {
    const p = i / b.length;
    if (rnd() < 0.00045 * (1 - p) ** 1.4) {
      const f = notes[Math.floor(rnd() * notes.length)], amp = 0.12 + rnd() * 0.18;
      for (let kk = 0; kk < SR * 0.3 && i + kk < b.length; kk++) { const s = kk / SR; b[i + kk] += Math.sin(TAU * f * s) * amp * Math.min(1, s / 0.01) * Math.exp(-s * 16); }
    }
  }
  return b;
};
const thump = (f = 90, dur = 0.18) => make(dur, (s) => Math.sin(TAU * (f + 60 * Math.exp(-s * 40)) * s) * Math.exp(-s * 24));
const step = () => { const b = thump(70, 0.16), n = lp(make(0.16, (s) => noise() * Math.exp(-s * 60) * 0.4), 1800); return b.map((v, i) => v + (n[i] || 0)); };
const chairRoll = () => lp(make(0.55, (s) => noise() * Math.sin(Math.PI * s / 0.55) * (0.6 + 0.4 * Math.sin(TAU * 23 * s))), 700);
const breath = () => bp(make(0.7, (s) => noise() * Math.sin(Math.PI * s / 0.7) ** 2 * 0.5), () => 900, 1.4);
const lidPop = () => { const t0 = thump(180, 0.12), n = hp(make(0.08, (s) => noise() * Math.exp(-s * 120)), 1500); return t0.map((v, i) => v * 0.8 + (n[i] || 0) * 0.5); };
const room = (dur) => { const b = lp(make(dur, () => noise() * 0.5), 500); return hp(b, 60); };
function ratchet(t0, dur, from, to, gain) { let t = 0; while (t < dur) { place(t0 + t, tick(1.3), gain * (0.6 + 0.4 * (t / dur)), 0.25, 0.05); t += 1 / (from + (to - from) * (t / dur)); } }

/* ---------- cues ---------- */
place(0, room(TL.end + 0.2), 0.08);
for (const [a, b, rate] of TL.typing) {
  let t = a;
  while (t < b) { place(t, key(), 0.11 + rnd() * 0.06, 0.15 + rnd() * 0.2); t += (0.6 + rnd() * 0.8) / rate; }
}
for (const c of TL.cues) {
  const { t, kind, gain, pan } = c;
  switch (kind) {
    case "room": break;
    case "tickLoud": place(t, tick(1), 0.55 * gain, pan, 0.15); break;
    case "whip": place(t - 0.05, whoosh(0.28, true), 0.34 * gain, pan, 0.1); break;
    case "click": place(t, click(), 0.5 * gain, pan); break;
    case "wake": place(t, bell(midi(96), 0.5, 0.4), 0.12 * gain, pan, 0.3); break;
    case "whooshIn": place(t, whoosh(0.6, true), 0.24 * gain, pan, 0.2); break;
    case "whooshOut": place(t, whoosh(0.75, false), 0.22 * gain, pan, 0.2); break;
    case "chime": [79, 83, 86].forEach((n, i) => place(t + i * 0.07, bell(midi(n), 1.6), 0.13 * gain, pan + (i - 1) * 0.2, 0.45)); break;
    case "fill": place(t, make(1.0, (s) => Math.sin(TAU * (520 + 260 * (s / 1.0) ** 0.7) * s) * Math.sin(Math.PI * s / 1.0) * 0.18), gain, 0, 0.3); break;
    case "timelapse": ratchet(t, 1.1, 8, 32, 0.22 * gain); place(t, whoosh(1.1, true), 0.1 * gain, 0, 0.2); break;
    case "lid": place(t, lidPop(), 0.5 * gain, pan, 0.1); break;
    case "pauseChime": place(t, bell(midi(79), 1.2), 0.16 * gain, pan, 0.3); place(t + 0.14, bell(midi(74), 1.4), 0.14 * gain, pan, 0.3); break;
    case "yawn": place(t, breath(), 0.35 * gain, pan, 0.1); break;
    case "woodfish": place(t, woodfish(Math.round(t * 7) % 5 * 7), 0.95 * gain, pan, 0.12); break;
    case "buzz": place(t, buzz(), 0.55 * gain, pan); break;
    case "notify": place(t, bell(midi(84), 0.9), 0.2 * gain, pan, 0.3); place(t + 0.12, bell(midi(91), 1.1), 0.18 * gain, pan, 0.3); break;
    case "beep": place(t, beep(880, 0.12), 0.34 * gain, 0); break;
    case "zero": place(t, beep(1320, 0.3), 0.32 * gain, 0); [72, 76, 79, 84].forEach((n, i) => place(t + 0.02 + i * 0.05, bell(midi(n), 2.4), 0.14 * gain, (i - 1.5) * 0.25, 0.5)); break;
    case "popper": place(t, popper(), 0.42 * gain, pan, 0.2); break;
    case "sparkle": place(t, sparkle(4.2), 0.32 * gain, -0.35, 0.5); place(t + 0.03, sparkle(4.2), 0.32 * gain, 0.35, 0.5); break;
    case "cheer": [84, 88, 91].forEach((n, i) => place(t + i * 0.06, bell(midi(n), 1.4), 0.1 * gain, (i - 1) * 0.3, 0.5)); break;
    case "chair": place(t, chairRoll(), 0.35 * gain, pan); break;
    case "step": place(t, step(), 0.45 * gain, pan); break;
    case "brand": place(t, bell(midi(84), 2.6), 0.18 * gain, 0, 0.6); place(t, thump(55, 1.0), 0.25 * gain, 0); break;
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
    const out = new Float32Array(Math.ceil(dur * SR)); let idx = 0;
    for (let i = 0; i < out.length; i++) { const a = line[idx], b2 = line[(idx + 1) % n]; line[idx] = (a + b2) * 0.5 * 0.996; out[i] = a; idx = (idx + 1) % n; }
    return lp(out, 3600);
  };
  const kick = () => make(0.35, (s) => Math.sin(TAU * (48 + 80 * Math.exp(-s * 30)) * s) * Math.exp(-s * 10));
  const hat = () => hp(make(0.04, (s) => noise() * Math.exp(-s * 100)), 7000);
  const beat = 60 / 96, bar = beat * 4, t0 = TL.musicFrom;
  const chords = [[48, 55, 64, 67, 72], [43, 50, 59, 62, 67], [45, 52, 60, 64, 69], [41, 48, 57, 60, 65]];
  const dropAt = B.zeroIn - 0.1, grooveFrom = B.tl1;
  for (let b = 0; t0 + b * bar < dropAt; b++) {
    const at = t0 + b * bar, ch = chords[b % 4], dur = Math.min(bar, dropAt - at);
    ch.forEach((n, i) => place(at, pad(midi(n), dur, 0.2, 0.8), 0.3, -0.4 + i * 0.2, 0.3, bus));
    const arp = [ch[2] + 12, ch[3] + 12, ch[4] + 12, ch[3] + 12];
    for (let e = 0; e < 8; e++) { const tt = at + (e * beat) / 2; if (tt >= dropAt) break; place(tt, pluck(midi(arp[e % 4])), 0.2, e % 2 ? 0.35 : -0.35, 0.3, bus); }
    if (at + bar > grooveFrom) for (let q = 0; q < 4; q++) {
      const tt = at + q * beat; if (tt < grooveFrom || tt >= dropAt) continue;
      if (q % 2 === 0) place(tt, kick(), 0.45, 0, 0, bus);
      place(tt + beat / 2, hat(), 0.1, 0.25, 0, bus);
    }
  }
  // the last seconds hang on one chord, then resolve at zero and carry the ending
  [48, 55, 64].forEach((n) => place(dropAt, pad(midi(n), B.zero - dropAt, 0.3, 0.3), 0.24, 0, 0.3, bus));
  // zero resolves on a full chord for one bar, then the song moves on through the walk-out and the tour
  const resolveBar = bar * 0.75;
  [36, 48, 55, 64, 67, 74, 79].forEach((n, i) => place(B.zero, pad(midi(n), resolveBar, 0.05, 1.0), 0.28, -0.45 + i * 0.15, 0.3, bus));
  const outro = B.zero + resolveBar, finalAt = B.cta;
  const outroChords = [[41, 48, 57, 60, 65], [43, 50, 59, 62, 67], [45, 52, 60, 64, 69], [43, 50, 59, 62, 67]];
  for (let b = 0; outro + b * bar < finalAt - 0.05; b++) {
    const at = outro + b * bar, ch = outroChords[b % 4], dur = Math.min(bar, finalAt - at);
    ch.forEach((n, i) => place(at, pad(midi(n), dur, 0.15, 0.7), 0.26, -0.4 + i * 0.2, 0.3, bus));
    const arp = [ch[2] + 12, ch[4] + 12, ch[3] + 12, ch[4] + 12, ch[2] + 24, ch[4] + 12, ch[3] + 12, ch[4] + 12];
    for (let e = 0; e < 8; e++) { const tt = at + (e * beat) / 2; if (tt >= finalAt) break; place(tt, pluck(midi(arp[e])), 0.18, e % 2 ? 0.35 : -0.35, 0.3, bus); }
    for (let q = 0; q < 4; q++) {
      const tt = at + q * beat; if (tt >= finalAt) break;
      if (q % 2 === 0) place(tt, kick(), 0.38, 0, 0, bus);
      place(tt + beat / 2, hat(), 0.09, 0.25, 0, bus);
    }
  }
  // the end card lands home on C and lets it ring out
  [36, 48, 55, 64, 67, 72].forEach((n, i) => place(finalAt, pad(midi(n), TL.end - finalAt - 1.0, 0.08, 1.0), 0.26, -0.4 + i * 0.16, 0.3, bus));
  [72, 76, 79, 84].forEach((n, i) => place(finalAt + i * 0.12, pluck(midi(n), 2.0), 0.2, -0.3 + i * 0.2, 0.3, bus));
  for (let i = 0; i < LEN; i++) {
    const s = i / SR, fin = Math.min(1, (s - t0 + 0.3) / 0.6), fade = s > TL.end - 1.2 ? Math.max(0, (TL.end - s) / 1.2) : 1;
    const g = s < t0 - 0.3 ? 0 : Math.max(0, fin) * fade * 0.6;
    L[i] += bus.L[i] * g; R[i] += bus.R[i] * g;
  }
}

/* ---------- reverb + level ---------- */
{
  const combs = [1557, 1617, 1491, 1422].map((d) => ({ d, buf: new Float32Array(d), i: 0, lp: 0 }));
  const aps = [225, 556].map((d) => ({ d, buf: new Float32Array(d), i: 0 }));
  for (let n = 0; n < LEN; n++) {
    const x = verb[n] * 0.25; let y = 0;
    for (const c of combs) { const out = c.buf[c.i]; c.lp = out * 0.6 + c.lp * 0.4; c.buf[c.i] = x + c.lp * 0.78; c.i = (c.i + 1) % c.d; y += out; }
    for (const a of aps) { const bo = a.buf[a.i]; const v = -y * 0.5 + bo; a.buf[a.i] = y + bo * 0.5; a.i = (a.i + 1) % a.d; y = v; }
    L[n] += y * 0.9; R[n] += y * 0.85;
  }
}
// gated RMS to about -17 dBFS, soft knee from -4.4 dBFS; render.mjs finishes with loudnorm
let sum = 0, count = 0;
const block = SR / 10;
for (let b = 0; b + block <= LEN; b += block) { let e = 0; for (let i = b; i < b + block; i++) e += (L[i] * L[i] + R[i] * R[i]) / 2; e /= block; if (e > 1e-5) { sum += e; count++; } }
const norm = 10 ** (-17 / 20) / Math.sqrt(sum / Math.max(1, count));
const knee = 0.6, room2 = 0.1;
const limit = (x) => { const a = Math.abs(x); return a <= knee ? x : Math.sign(x) * (knee + room2 * Math.tanh((a - knee) / room2)); };
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

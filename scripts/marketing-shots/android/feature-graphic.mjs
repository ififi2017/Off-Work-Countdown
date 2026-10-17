// Play feature graphic, using the same typography as the ASC-derived screenshots.
//
//   node scripts/marketing-shots/android/feature-graphic.mjs [media-directory] [play-image-directory]
//
// Crops the countdown and progress bar from the real Pixel timer capture
// (<media>/raw/en-timer.png, pixel-capture.mjs) without retouching it. With a
// Play image directory, the PNG is also copied to <dir>/en-US/featureGraphic.png.
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { brandMark } from '../brand.mjs';
import { captureHtml, flattenPng } from '../chrome.mjs';
import { posterFonts } from '../ios/creative-fonts.mjs';
import sharp from 'sharp';

const out = resolve(process.argv[2] || 'build/play-store-media');
const source = join(out, 'raw/en-timer.png');
const bytes = readFileSync(source);
const sourceMeta = await sharp(bytes).metadata();
if (sourceMeta.width !== 1280 || sourceMeta.height !== 2856) throw new Error('Expected the 1280 × 2856 Pixel timer capture.');
// Countdown digits through the progress bar, in capture pixels.
const crop = { left: 40, top: 380, width: 1200, height: 460 };
const scale = 338 / crop.width;
// The card takes the capture's own background colour, so the crop has no visible edge.
const { data: bg } = await sharp(bytes).extract({ left: 20, top: crop.top + 10, width: 1, height: 1 }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
const cardColour = `rgb(${bg[0]},${bg[1]},${bg[2]})`;
mkdirSync(out, { recursive: true });
const fonts = posterFonts('en');
const html = `<!doctype html><html lang="en"><meta charset="utf-8"><style>
${fonts.css}
*{box-sizing:border-box}html,body{margin:0;width:1024px;height:500px;overflow:hidden}
body{position:relative;background:radial-gradient(ellipse at 86% 80%,#ffe9d3,transparent 56%),#fcf7ef;color:#25231f;font-family:${fonts.sans};font-synthesis:none}
.brand{position:absolute;left:64px;top:48px;display:flex;align-items:center;gap:10px;font-size:23px;font-weight:700}.mark{width:30px;height:30px}
h1{position:absolute;left:64px;top:142px;margin:0;font:700 72px/1.13 ${fonts.serif};letter-spacing:-1.8px}h1 span{display:block;color:#ff5100}
.caption{position:absolute;left:68px;top:341px;font-size:22px;color:#776e63}
.card{position:absolute;left:591px;top:162px;padding:22px 22px 18px;background:${cardColour};border-radius:28px;box-shadow:0 18px 38px #5b3a1b1a,0 2px 6px #5b3a1b0a;transform:rotate(-5deg)}
.capture{width:${crop.width * scale}px;height:${crop.height * scale}px;overflow:hidden;position:relative}.capture img{position:absolute;width:${1280 * scale}px;max-width:none;left:${-crop.left * scale}px;top:${-crop.top * scale}px}
</style><body><div class="brand">${brandMark('#25231f')}DoneAt</div><h1>After work,<span>time for you.</span></h1><div class="caption">Your shift, at a glance.</div><div class="card"><div class="capture"><img alt="Android shift countdown and progress" src="data:image/png;base64,${bytes.toString('base64')}"></div></div></body></html>`;
const file = join(out, 'feature-graphic-en-1024x500.png');
await captureHtml({ html, htmlPath: join(out, 'feature-graphic-en.html'), width: 1024, height: 500, scale: 1, outFile: file });
flattenPng(file);
const meta = await sharp(file).metadata();
const png = readFileSync(file);
if (meta.width !== 1024 || meta.height !== 500 || meta.hasAlpha || png.length > 15 * 1024 * 1024) throw new Error('Invalid Play feature graphic.');
writeFileSync(join(out, 'feature-graphic-manifest.json'), JSON.stringify({ source, sourceSHA256: createHash('sha256').update(bytes).digest('hex'), file, pngSHA256: createHash('sha256').update(png).digest('hex'), width: meta.width, height: meta.height, bytes: png.length }, null, 2) + '\n');
if (process.argv[3]) {
  const target = join(resolve(process.argv[3]), 'en-US');
  mkdirSync(target, { recursive: true });
  copyFileSync(file, join(target, 'featureGraphic.png'));
}
console.log(file);

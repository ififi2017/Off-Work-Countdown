// Play feature graphic, using the same typography as the ASC-derived screenshots.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { brandMark } from '../brand.mjs';
import { captureHtml, flattenPng } from '../chrome.mjs';
import { posterFonts } from '../ios/creative-fonts.mjs';
import sharp from 'sharp';

const out = resolve(process.argv[2] || 'build/android-play-internal/store-listing');
const source = join(out, 'asc-style/raw/en-timer.png');
const bytes = readFileSync(source);
const sourceMeta = await sharp(bytes).metadata();
if (sourceMeta.width !== 1080 || sourceMeta.height !== 2400) throw new Error('Expected the verified 1080 × 2400 Android timer capture.');
mkdirSync(out, { recursive: true });
const fonts = posterFonts('en');
const html = `<!doctype html><html lang="en"><meta charset="utf-8"><style>
${fonts.css}
*{box-sizing:border-box}html,body{margin:0;width:1024px;height:500px;overflow:hidden}
body{position:relative;background:radial-gradient(ellipse at 86% 80%,#ffe9d3,transparent 56%),#fcf7ef;color:#25231f;font-family:${fonts.sans};font-synthesis:none}
.brand{position:absolute;left:64px;top:48px;display:flex;align-items:center;gap:10px;font-size:23px;font-weight:700}.mark{width:30px;height:30px}
h1{position:absolute;left:64px;top:142px;margin:0;font:700 72px/1.13 ${fonts.serif};letter-spacing:-1.8px}h1 span{display:block;color:#ff5100}
.caption{position:absolute;left:68px;top:341px;font-size:22px;color:#776e63}
.card{position:absolute;left:591px;top:172px;padding:27px 22px 23px;background:#fff8f6;border-radius:28px;box-shadow:0 18px 38px #5b3a1b1a,0 2px 6px #5b3a1b0a;transform:rotate(-5deg)}
.capture{width:338px;height:147px;overflow:hidden;position:relative}.capture img{position:absolute;width:367.2px;max-width:none;left:-14.3px;top:-102px}
</style><body><div class="brand">${brandMark('#25231f')}DoneAt</div><h1>After work,<span>time for you.</span></h1><div class="caption">Your shift, at a glance.</div><div class="card"><div class="capture"><img alt="Android shift countdown and progress" src="data:image/png;base64,${bytes.toString('base64')}"></div></div></body></html>`;
const file = join(out, 'feature-graphic-en-1024x500.png');
await captureHtml({ html, htmlPath: join(out, 'feature-graphic-en.html'), width: 1024, height: 500, scale: 1, outFile: file });
flattenPng(file);
const meta = await sharp(file).metadata();
const png = readFileSync(file);
if (meta.width !== 1024 || meta.height !== 500 || meta.hasAlpha || png.length > 15 * 1024 * 1024) throw new Error('Invalid Play feature graphic.');
writeFileSync(join(out, 'feature-graphic-manifest.json'), JSON.stringify({ source, sourceSHA256: createHash('sha256').update(bytes).digest('hex'), file, pngSHA256: createHash('sha256').update(png).digest('hex'), width: meta.width, height: meta.height, bytes: png.length }, null, 2) + '\n');
console.log(file);

// Google Play adaptation of the ASC 3.2.0 creative. Requires real Android captures.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { brandMark, escapeHTML } from '../brand.mjs';
import { captureHtml, flattenPng } from '../chrome.mjs';
import { COPY } from '../ios/creative-copy.mjs';
import { posterFonts } from '../ios/creative-fonts.mjs';
import sharp from 'sharp';

const out = resolve(process.argv[2] || 'build/android-play-internal/store-listing/asc-style');
const raw = join(out, 'raw');
const shots = join(out, 'screenshots');
mkdirSync(shots, { recursive: true });
const copy = COPY.en;
const fonts = posterFonts('en');
const width = 540, height = 960, scale = 2;
const pages = [
  { name: '01-countdown', source: 'en-timer', kind: 'hero', label: 'DoneAt', lines: copy.hero, sub: copy.intro.split('|') },
  { name: '02-countdown-detail', source: 'en-timer', kind: 'detail', label: copy.pages[0].label, lines: [], sub: [] },
  { name: '03-calendar', source: 'en-calendar', ...copy.pages[2] },
  { name: '04-records', source: 'en-records', ...copy.pages[3] },
  { name: '05-focus', source: 'en-focus', ...copy.pages[4] },
  { name: '06-breaks', source: 'en-breaks', ...copy.pages[6] },
];
const manifest = [];
for (const [index, page] of pages.entries()) {
  const source = join(raw, `${page.source}.png`);
  const sourceMeta = await sharp(source).metadata();
  if (sourceMeta.width !== 1080 || sourceMeta.height !== 2400) throw new Error(`Expected 1080×2400 Android capture: ${source}`);
  const html = `<!doctype html><html lang="en"><meta charset="utf-8"><style>
${fonts.css}
*{box-sizing:border-box}html,body{margin:0;width:${width}px;height:${height}px;overflow:hidden}
body{position:relative;background:radial-gradient(ellipse at 80% 90%,#ffecd9 0%,transparent 60%),#fcf7ef;color:#25231f;font:500 18px/1.5 ${fonts.sans};font-synthesis:none}
.label{position:absolute;left:44px;top:36px;font-size:15px;color:#776e63;max-width:452px}
.editorial{position:absolute;left:44px;top:86px;z-index:2}
h1{margin:0;font:700 55px/1.18 ${fonts.serif};letter-spacing:-1.4px}
h1 span{display:block;white-space:nowrap}h1 span:last-child{color:#ff5100}
.sub{margin-top:20px;font-size:18px;line-height:1.5;color:#776e63}.sub span{display:block}
.phone{position:absolute;top:328px;left:42px;width:456px;padding:6px;border-radius:40px;background:#282b2d;border:1px solid #666b70;box-shadow:0 12px 22px #3a271322;overflow:hidden}
.phone img{width:100%;display:block;border-radius:34px}
.hero,.detail{background:#fcf7ef}.hero .label{display:flex;align-items:center;gap:10px;color:#25231f;font-size:20px;font-weight:700}.mark{width:25px;height:25px}
.hero .editorial{display:contents}.hero h1{position:absolute;left:43px;top:156px;font-size:60px;line-height:1.3}.hero .sub{position:absolute;left:45px;top:525px;color:#38352f;font-size:25px}
.hero .phone,.detail .phone{width:600px;top:172px;transform:rotate(8deg);transform-origin:center center;border-radius:47px;padding:7px}.hero .phone img,.detail .phone img{border-radius:39px}
.hero .phone{left:408px}.detail .phone{left:-132px}.detail .label{font:700 21px/1.4 ${fonts.serif};color:#25231f;max-width:460px}
.foot{position:absolute;left:44px;bottom:80px;width:232px;border-top:2px solid #ff5100;padding-top:16px;font-size:18px;line-height:1.5}
</style><body class="${page.kind || ''}"><div class="label">${page.kind === 'hero' ? brandMark('#25231f') : ''}${escapeHTML(page.label)}</div><div class="editorial"><h1>${page.lines.filter(Boolean).map(line => `<span>${escapeHTML(line)}</span>`).join('')}</h1><div class="sub">${page.sub.filter(Boolean).map(line => `<span>${escapeHTML(line)}</span>`).join('')}</div></div><div class="phone"><img src="${pathToFileURL(source).href}"></div>${page.kind === 'hero' ? `<div class="foot">${escapeHTML(copy.pages[0].label)}</div>` : ''}</body></html>`;
  const file = `en-US-${page.name}.png`;
  const pngPath = join(shots, file);
  const htmlPath = join(out, `${page.name}.html`);
  await captureHtml({ html, htmlPath, width, height, scale, outFile: pngPath });
  flattenPng(pngPath);
  const outputMeta = await sharp(pngPath).metadata();
  const png = readFileSync(pngPath);
  if (outputMeta.width !== 1080 || outputMeta.height !== 1920 || outputMeta.hasAlpha || png.length > 8 * 1024 * 1024) throw new Error(`Invalid Play asset: ${file}`);
  manifest.push({ order: index + 1, file, source: `${page.source}.png`, sourceSHA256: createHash('sha256').update(readFileSync(source)).digest('hex'), pngSHA256: createHash('sha256').update(png).digest('hex'), width: 1080, height: 1920, bytes: png.length });
  console.log(file);
}
const overview = `<!doctype html><style>body{margin:0;padding:20px;background:#20231f;display:grid;grid-template-columns:repeat(3,270px);gap:16px}img{display:block;width:270px;height:480px;border-radius:16px}</style>${manifest.map(item => `<img src="${pathToFileURL(join(shots, item.file)).href}">`).join('')}`;
await captureHtml({ html: overview, htmlPath: join(out, 'overview.html'), width: 882, height: 1016, scale: 1, outFile: join(out, 'overview.png') });
writeFileSync(join(out, 'manifest.json'), JSON.stringify({ createdAt: new Date().toISOString(), locale: 'en-US', template: 'ASC 3.2.0 creative', captures: 'Android API 36.1, current debug build, synthetic data; Plus debug override for demonstrations; no purchase screen', items: manifest }, null, 2) + '\n');

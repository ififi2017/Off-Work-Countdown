// Google Play adaptation of the ASC iPhone creative. Requires real Android captures.
//
//   ANDROID_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/android/compose.mjs [output-directory]
//
// Reads <output>/raw/<lang>-<scene>.png (pixel-capture.mjs, 1280 × 2856) and
// writes <output>/screenshots/<lang>/<NN-scene>.png at 1080 × 1920, plus a
// contact sheet per language. Captions come from play-copy.mjs. With
// PLAY_IMAGE_DIR=play-store/images the sets are also copied to each Play
// language's phoneScreenshots folder (en-GB and es-419 reuse en and es).
import { mkdirSync, readFileSync, writeFileSync, existsSync, rmSync, copyFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { brandMark, escapeHTML } from '../brand.mjs';
import { captureHtml, flattenPng } from '../chrome.mjs';
import { posterFonts } from '../ios/creative-fonts.mjs';
import { playPages, PLAY_TARGETS } from './play-copy.mjs';
import sharp from 'sharp';

const out = resolve(process.argv[2] || 'build/play-store-media');
const raw = join(out, 'raw');
const masked = join(out, 'masked');
const pages = join(out, 'html');
mkdirSync(masked, { recursive: true });
mkdirSync(pages, { recursive: true });
const langs = (process.env.ANDROID_SHOTS_LANGUAGE || Object.keys(PLAY_TARGETS).join(',')).split(',');
const width = 540, height = 960, scale = 2;
const RAW = [1280, 2856];
const sha = buffer => createHash('sha256').update(buffer).digest('hex');

// The phone's own notification, VPN, ringer and Do Not Disturb icons are not
// part of the app, and System UI demo mode on this Pixel does not hide them.
// Between the demo clock and the battery, each status-bar row is filled with
// its own background colour; the app content below is untouched.
const STATUS_BAR = { bottom: 150, from: 215, to: 1105, sample: 600 };
async function maskStatusBar(source, target) {
  const { data, info } = await sharp(source).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  if (info.width !== RAW[0] || info.height !== RAW[1]) throw new Error(`Expected ${RAW.join(' × ')} Pixel capture: ${source}`);
  for (let y = 0; y < STATUS_BAR.bottom; y++) {
    const row = y * info.width * 3, s = row + STATUS_BAR.sample * 3;
    for (let x = STATUS_BAR.from; x < STATUS_BAR.to; x++) data.copy(data, row + x * 3, s, s + 3);
  }
  await sharp(data, { raw: info }).png().toFile(target);
}

function html(lang, page, img, fonts) {
  const rtl = lang === 'ar';
  const lines = page.lines.filter(Boolean).map(line => `<span>${escapeHTML(line)}</span>`).join('');
  const sub = page.sub.filter(Boolean).map(line => `<span>${escapeHTML(line)}</span>`).join('');
  return `<!doctype html><html lang="${lang}" dir="${rtl ? 'rtl' : 'ltr'}"><meta charset="utf-8"><style>
${fonts.css}
*{box-sizing:border-box}html,body{margin:0;width:${width}px;height:${height}px;overflow:hidden}
body{position:relative;background:radial-gradient(ellipse at 80% 90%,#ffecd9 0%,transparent 60%),#fcf7ef;color:#25231f;font:500 18px/1.5 ${fonts.sans};font-synthesis:none;${lang === 'ko' ? 'word-break:keep-all;' : ''}}
.copy{position:absolute;inset-inline:44px;top:0}
.label{position:absolute;inset-inline-start:0;top:36px;font-size:15px;color:#776e63;white-space:nowrap}
.editorial{position:absolute;inset-inline-start:0;top:86px;z-index:2;width:452px}
h1{margin:0;font:700 55px/1.18 ${fonts.serif};letter-spacing:${/^(ar|hi-IN|mr-IN|th)$/.test(lang) ? '0' : '-1.4px'}}
h1 span{display:block;white-space:nowrap;width:max-content}h1 span:last-child{color:#ff5100}
.sub{margin-top:20px;font-size:18px;line-height:1.5;color:#776e63}.sub span{display:block;white-space:nowrap;width:max-content}
.note{margin-top:8px;font-size:11px;line-height:1.4;color:#9a8f82}
.hero .note{position:absolute;inset-inline-start:44px;bottom:24px;margin:0}
.phone{position:absolute;top:328px;left:42px;width:456px;padding:6px;border-radius:40px;background:#282b2d;border:1px solid #666b70;box-shadow:0 12px 22px #3a271322;overflow:hidden}
.phone img{width:100%;display:block;border-radius:34px}
.hero .label{display:flex;align-items:center;gap:10px;color:#25231f;font-size:20px;font-weight:700}.mark{width:25px;height:25px}
.hero h1{font-size:60px;line-height:1.3;margin-top:70px}.hero .editorial{width:330px}
.hero .sub{position:absolute;top:439px;color:#38352f;font-size:25px;width:250px}.hero .sub span{white-space:normal;width:auto}
.hero .phone,.detail .phone{width:600px;top:172px;transform:rotate(${rtl ? -8 : 8}deg);transform-origin:center center;border-radius:47px;padding:7px}.hero .phone img,.detail .phone img{border-radius:39px}
.hero .phone{${rtl ? 'left:-468px' : 'left:408px'}}.detail .phone{${rtl ? 'left:72px' : 'left:-132px'}}
.detail .label{font:700 21px/1.4 ${fonts.serif};color:#25231f;width:452px;white-space:normal}
.foot{position:absolute;inset-inline-start:44px;bottom:80px;width:232px;border-top:2px solid #ff5100;padding-top:16px;font-size:18px;line-height:1.5}
</style><body class="${page.kind || ''}"><div class="copy"><div class="label">${page.kind === 'hero' ? brandMark('#25231f') : ''}${escapeHTML(page.label)}</div>${page.kind === 'detail' ? '' : `<div class="editorial"><h1>${lines}</h1><div class="sub">${sub}</div>${page.kind === 'hero' ? '' : `<div class="note">${escapeHTML(page.note)}</div>`}</div>`}</div><div class="phone"><img src="${pathToFileURL(img).href}"></div>${page.kind === 'hero' ? `<div class="foot">${escapeHTML(page.foot)}</div><div class="note">${escapeHTML(page.note)}</div>` : ''}
<script>
// Shrink a headline, subline or label whose widest line would overflow its column, never below 70%.
function fit(selector,max){for(const el of document.querySelectorAll(selector)){let size=parseFloat(getComputedStyle(el).fontSize);const floor=size*.7;const widest=()=>Math.max(el.scrollWidth,...[...el.children].map(n=>n.getBoundingClientRect().width));while(size>floor&&widest()>max+1){size-=1;el.style.fontSize=size+'px';}}}
document.fonts.ready.then(()=>{const hero=document.body.classList.contains('hero');fit('.editorial h1',hero?330:452);if(!hero)fit('.editorial .sub',452);fit('.label',452);});
</script></body></html>`;
}

const manifest = { template: 'ASC 3.2.1/3.2.2 iPhone creative, Android scenes', captures: 'Pixel 10 Pro, Debug `.shots` install, synthetic data; Plus via Debug-only switch; status-bar icons between clock and battery masked', languages: {} };
for (const lang of langs) {
  const fonts = posterFonts(lang === 'zh-HK' ? 'zh-TW' : lang);
  const dir = join(out, 'screenshots', lang);
  mkdirSync(dir, { recursive: true });
  const items = [];
  for (const page of playPages(lang)) {
    const source = join(raw, `${lang}-${page.source}.png`);
    if (!existsSync(source)) throw new Error(`Missing capture ${source}`);
    const img = join(masked, `${lang}-${page.source}.png`);
    await maskStatusBar(source, img);
    const file = join(dir, `${page.name}.png`);
    await captureHtml({ html: html(lang, page, img, fonts), htmlPath: join(pages, `${lang}-${page.name}.html`), width, height, scale, outFile: file });
    flattenPng(file);
    const meta = await sharp(file).metadata();
    const png = readFileSync(file);
    if (meta.width !== 1080 || meta.height !== 1920 || meta.hasAlpha || png.length > 8 * 1024 * 1024) throw new Error(`Invalid Play asset: ${file}`);
    items.push({ file: `${page.name}.png`, source: `${lang}-${page.source}.png`, sourceSHA256: sha(readFileSync(source)), pngSHA256: sha(png), bytes: png.length, label: page.label, headline: page.lines });
  }
  const sheet = `<!doctype html><style>body{margin:0;padding:20px;background:#20231f;display:grid;grid-template-columns:repeat(4,270px);gap:16px}img{display:block;width:270px;height:480px;border-radius:12px}</style>${items.map(item => `<img src="${pathToFileURL(join(dir, item.file)).href}">`).join('')}`;
  await captureHtml({ html: sheet, htmlPath: join(pages, `${lang}-overview.html`), width: 1180, height: 1036, scale: 1, outFile: join(out, `overview-${lang}.png`) });
  manifest.languages[lang] = { playLanguages: PLAY_TARGETS[lang], items };
  // PLAY_IMAGE_DIR=play-store/images replaces each Play language's phone set with this one.
  if (process.env.PLAY_IMAGE_DIR) for (const play of PLAY_TARGETS[lang]) {
    const target = join(resolve(process.env.PLAY_IMAGE_DIR), play, 'phoneScreenshots');
    rmSync(target, { recursive: true, force: true });
    mkdirSync(target, { recursive: true });
    for (const item of items) copyFileSync(join(dir, item.file), join(target, item.file));
  }
  console.log(lang);
}
const path = join(out, 'compose-manifest.json');
const previous = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : { languages: {} };
writeFileSync(path, JSON.stringify({ ...manifest, createdAt: new Date().toISOString(), languages: { ...previous.languages, ...manifest.languages } }, null, 2) + '\n');

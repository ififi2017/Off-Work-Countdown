// Review contact sheets only; never included in the 272 ASC assets.
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureHtml} from '../chrome.mjs';
import {COPY,PAGE_NAMES} from './creative-copy.mjs';
const out=process.env.IOS_CREATIVE_OUT||fileURLToPath(new URL('./out/creative-3.2.0',import.meta.url));
for(const lang of (process.env.IOS_SHOTS_LANGUAGE||Object.keys(COPY).join(',')).split(',')){
 for(const device of (process.env.IOS_SHOTS_PLATFORM||'iphone,ipad').split(',')){
  const paths=PAGE_NAMES.map(name=>join(out,`${lang}-${device}-${name}.png`));
  if(paths.some(path=>!existsSync(path)))throw new Error(`Incomplete ${lang} ${device} artwork`);
  const height=device==='ipad'?440:717;
  const html=`<!doctype html><style>body{margin:0;padding:24px;background:#20231f;display:grid;grid-template-columns:repeat(4,330px);gap:18px}img{width:330px;height:${height}px;border-radius:20px}</style>${paths.map(path=>`<img src="${pathToFileURL(path).href}">`).join('')}`;
  await captureHtml({html,htmlPath:join(out,`${lang}-${device}-overview.html`),outFile:join(out,`${lang}-${device}-overview.png`),width:1422,height:height*2+66,scale:1});
  console.log(`${lang}-${device}-overview`);
 }
}

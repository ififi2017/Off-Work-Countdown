// Localized 3.2.0 artwork, composed from real simulator captures and Apple frames.
// Capture first. Missing inputs are errors; English/CN fallbacks are never uploadable.
import {mkdirSync,existsSync,writeFileSync,readFileSync,statSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {brandMark,escapeHTML} from '../brand.mjs';
import {captureHtml as renderHtml,flattenPng} from '../chrome.mjs';
import {createHash} from 'node:crypto';
import {COPY,PAGE_NAMES,FOOTERS} from './creative-copy.mjs';
import {posterFonts} from './creative-fonts.mjs';
async function captureHtml(options){try{return await renderHtml(options);}catch(error){console.warn(`Retrying Chrome capture: ${options.outFile}: ${error.message}`);return renderHtml(options);}}
const dir=fileURLToPath(new URL('.',import.meta.url));
const out=process.env.IOS_CREATIVE_OUT||join(dir,'out/creative-3.2.0');
const preview=process.env.IOS_CREATIVE_LAYOUT_PREVIEW==='1';
const langs=(process.env.IOS_SHOTS_LANGUAGE||Object.keys(COPY).join(',')).split(',');
const devices=(process.env.IOS_SHOTS_PLATFORM||'iphone,ipad').split(',');
const selectedPages=process.env.IOS_CREATIVE_PAGES?.split(',').map(Number);
const uri=p=>pathToFileURL(p).href;
mkdirSync(out,{recursive:true});
const sizes={en:72,de:66,fr:64,es:65,it:59,pt:62,ja:68,ko:60,ru:58,tr:64,id:62,vi:60,th:65,'hi-IN':60,ar:76,'zh-CN':76,'zh-TW':76};
const cropTable=JSON.parse(readFileSync(join(dir,'widget-crops.json'),'utf8'));
const manifest=[];
for(const lang of langs){
 if(!COPY[lang])throw new Error(`Unknown language ${lang}`);
 const c=COPY[lang];
 const type=posterFonts(lang);
 for(const device of devices){
  const pad=device==='ipad', w=pad?1032:660,h=pad?1376:1434;
  const stem=c.stem+(pad?'-ipad':'');
  function raw(scene){
   const canonical=join(dir,`raw/${stem}-${scene}.png`);
   // Existing corrected Chinese proofs remain usable until refreshed by capture.
   const legacy=lang==='zh-CN'&&!pad?join(dir,`raw/zh-${scene}-3.2.0.png`):null;
   const p=existsSync(canonical)?canonical:legacy&&existsSync(legacy)?legacy:null;
   if(p)return uri(p);
   if(preview){const fallback=join(dir,`raw/zh-${scene}-3.2.0.png`);if(existsSync(fallback))return uri(fallback);}
   if(selectedPages)return uri(canonical);
   throw new Error(`Missing real ${lang} ${device} screenshot: ${canonical}`);
  }
  const watchPath=join(dir,`raw/${c.stem}-watch-3.2.0.png`);
  if(!existsSync(watchPath)&&!preview)throw new Error(`Missing localized Watch screenshot: ${watchPath}`);
  const watch=uri(existsSync(watchPath)?watchPath:join(dir,'raw/zh-watch-3.2.0.png'));
  const frame=uri(join(dir,`frames/${pad?'ipad-pro-m5-13-inch-space-black-portrait':'iphone-17-pro-max-deep-blue'}.png`));
  function phone(src,style){return `<div class="phone" style="${style}"><div class="screen"><img src="${src}"></div><img class="frame" src="${frame}"></div>`;}
  function crop(src,x,y,cw,ch,width,style){const s=width/cw;return `<div class="crop" style="width:${width}px;height:${ch*s}px;${style}"><img src="${src}" style="width:${1320*s}px;left:${-x*s}px;top:${-y*s}px"></div>`;}
  const openingPhone=panel=>phone(raw(1),pad?`width:1170px;left:${750-panel*w}px;top:230px;transform:rotate(8deg)`:`width:740px;left:${495-panel*w}px;top:200px;transform:rotate(8deg)`);
  const normal=src=>phone(src,pad?'width:866px;left:83px;top:480px':'width:566px;left:47px;top:455px');
  const widgetSource=uri(join(dir,`raw/${c.stem}-2.png`));
  const boxes=cropTable[c.stem];if(!boxes)throw new Error(`Missing verified widget bounds ${lang}`);
  const widgetScale=pad?1.22:1;
  const arts=[openingPhone(0),openingPhone(1),`<div class="watch"><img class="watch-frame" src="${uri(join(dir,'frames/watch-s11-46mm-gold-milanese.png'))}"><img class="watch-screen" src="${watch}"></div><div class="watch-note">Apple Watch<small>${escapeHTML(c.free)}</small></div>`,normal(raw('calendar')),normal(raw(4)),normal(raw('focus')),`<div class="widgets-art" style="transform:scale(${widgetScale});transform-origin:top left;left:${pad?110:0}px">${crop(widgetSource,...boxes.island,330,'left:225px;top:460px;border-radius:60px;transform:rotate(5deg)')}${crop(widgetSource,...boxes.live,515,'left:60px;top:595px;border-radius:38px;transform:rotate(-4deg)')}${crop(widgetSource,...boxes.widget,520,'left:80px;top:805px;border-radius:42px;transform:rotate(4deg)')}</div>`,normal(raw(3))];
  for(let i=0;i<8;i++){
   if(selectedPages&&!selectedPages.includes(i+1))continue;
   const p=i===0?{label:lang==='zh-CN'?'DoneAt · 下班倒计时':lang==='zh-TW'?'DoneAt · 下班倒數':'DoneAt',lines:c.hero,sub:c.intro.split('|')}:c.pages[i-1];
   const cls=i===0?'hero':i===1?'hero-continuation':i===2?'watch-page':'';
   const title=p.lines.filter(Boolean).map((line,n)=>`<span class="line ${n===p.lines.length-1?'accent':''}">${escapeHTML(line)}</span>`).join('');
   const html=`<!doctype html><html lang="${lang}"><meta charset="utf-8"><style>
${type.css}
*{box-sizing:border-box}html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden}
body{position:relative;background:radial-gradient(ellipse at 80% 90%,#ffecd9 0%,transparent 60%),#fcf7ef;color:#25231f;font-family:${type.sans};font-weight:500;font-synthesis:none}
.label{position:absolute;left:${pad?70:55}px;top:58px;max-width:${w-(pad?140:110)}px;font-size:${pad?25:21}px;line-height:1.4;color:#776e63;letter-spacing:.1px}
.copy{direction:${lang==='ar'?'rtl':'ltr'}}
.editorial{position:absolute;left:${pad?70:55}px;top:126px;width:${w-(pad?140:110)}px;z-index:3}
h1{margin:0;font-size:${sizes[lang]*(pad?1.16:1)}px;line-height:1.24;font-family:${type.serif};font-weight:700;letter-spacing:${['zh-CN','zh-TW','ja'].includes(lang)?'-3px':['ar','th','hi-IN'].includes(lang)?'0':'-1.5px'}}
.line{display:block;white-space:nowrap}.accent{color:#ff5100}
.sub{margin-top:${pad?32:28}px;font-size:${pad?28:24}px;line-height:1.5;color:#776e63}
.subline{display:block}
.phone{position:absolute;filter:drop-shadow(0 16px 22px #3a271322)}
.screen{position:absolute;top:${pad?'4.133333%':'2.2%'};left:${pad?'5.130435%':'5.102041%'};width:${pad?'89.739130%':'89.795918%'};height:${pad?'91.733333%':'95.6%'};border-radius:${pad?'2.91% / 2.18%':'14.4% / 6.62%'};overflow:hidden}
.screen img{width:100%;height:100%;object-fit:cover;object-position:top}.frame{position:relative;width:100%;display:block}
.crop{position:absolute;overflow:hidden;filter:drop-shadow(0 15px 13px #3a271321)}.crop img{position:absolute}.widgets-art{position:absolute;top:0}
.hero,.hero-continuation{background:#fcf7ef}
.hero-continuation .label{font:700 ${pad?31:26}px/1.4 ${type.serif};color:#25231f}
.hero .editorial{display:contents}
.hero h1{position:absolute;left:${pad?67:52}px;top:202px;width:${pad?560:385}px;font-size:${c.heroSize*(pad?1.2:1)}px;line-height:1.35}
.hero .label .mark{width:32px;height:32px;flex:none}
.hero .label{display:flex;align-items:center;gap:12px;color:#25231f;font-weight:700;font-size:25px;direction:ltr}
.hero .sub{position:absolute;left:${pad?71:56}px;top:745px;margin:0;width:${pad?490:355}px;color:#38352f;font-size:${pad?36:32}px;line-height:1.5}
.watch{position:absolute;left:${pad?292:91}px;top:${pad?480:432}px;width:${pad?448:478}px;height:${pad?704:751}px;filter:drop-shadow(0 22px 24px #41270c26)}
.watch-frame{z-index:2;position:absolute;width:100%;height:100%;object-fit:contain}
.watch-screen{position:absolute;left:12.857143%;top:21.818182%;width:74.285714%;height:56.363636%;object-fit:contain;border-radius:20%;background:#000}
.watch-note{position:absolute;top:${pad?1220:1200}px;width:100%;text-align:center;font-size:30px;font-weight:700}
.watch-note small{display:block;margin-top:10px;font-size:23px;font-weight:500;color:#776e63}
.foot{position:absolute;left:${pad?70:55}px;bottom:48px;max-width:calc(100% - ${pad?140:110}px);font-size:${pad?27:24}px;line-height:1.5;z-index:5}
:lang(ko) .hero .foot{word-break:keep-all}
.hero .foot{width:${pad?400:290}px;bottom:155px;border-top:2px solid #ff5100;padding-top:22px}
${lang==='ar'?`body:not(.hero):not(.hero-continuation) .label.copy,body:not(.hero):not(.hero-continuation) .foot.copy{right:${pad?70:55}px;left:auto;text-align:right}`:''}
.preview{position:absolute;bottom:5px;right:10px;font:12px ${type.sans};color:#b23;z-index:99}
</style><body class="${cls}"><div class="label copy">${i===0?brandMark('#25231f'):''}${escapeHTML(p.label)}</div><div class="editorial"><h1 class="copy">${title}</h1><div class="sub copy">${p.sub.filter(Boolean).map(line=>`<span class="subline">${escapeHTML(line)}</span>`).join('')}</div></div>${arts[i]}${[0,2,6].includes(i)?`<div class="foot copy">${escapeHTML(i===0?c.pages[0].label:FOOTERS[lang][i===2?0:1])}</div>`:''}${preview?'<div class="preview">LAYOUT PROOF — NOT FOR UPLOAD</div>':''}<script>document.fonts.ready.then(()=>{
 const body=document.body,header=document.querySelector('.editorial');
 if(!body.classList.contains('hero')&&!body.classList.contains('hero-continuation')){
  const artTop=Math.max(${pad?480:455},header.getBoundingClientRect().bottom+${pad?44:40});
  const phone=document.querySelector('.phone');if(phone)phone.style.top=artTop+'px';
  const watch=document.querySelector('.watch');
  if(watch){const note=document.querySelector('.watch-note'),foot=document.querySelector('.foot');const bottom=foot.getBoundingClientRect().top-30;const height=Math.min(${pad?704:751},bottom-artTop-note.offsetHeight-22);watch.style.height=height+'px';watch.style.width=height*560/880+'px';watch.style.left=(${w}-height*560/880)/2+'px';watch.style.top=artTop+'px';note.style.top=artTop+height+22+'px';}
  const widgets=document.querySelector('.widgets-art');if(widgets){
   widgets.style.transform='none';widgets.style.left='0px';widgets.style.top='0px';
   const boxes=[...widgets.children].map(child=>child.getBoundingClientRect());
   const minX=Math.min(...boxes.map(box=>box.left)),minY=Math.min(...boxes.map(box=>box.top));
   const width=Math.max(...boxes.map(box=>box.right))-minX,height=Math.max(...boxes.map(box=>box.bottom))-minY;
   const bottom=document.querySelector('.foot').getBoundingClientRect().top-34;
   const scale=Math.min(${pad?1.22:1},(bottom-artTop)/height,(${w}-${pad?140:100})/width);
   widgets.style.transform='scale('+scale+')';widgets.style.left=((${w}-width*scale)/2-minX*scale)+'px';widgets.style.top=(artTop-minY*scale)+'px';
  }
 }
 body.dataset.layoutReady='true';
});</script></body></html>`;
   const name=`${lang}-${device}-${PAGE_NAMES[i]}`,outFile=join(out,`${name}.png`);
   writeFileSync(join(out,`${name}.html`),html);
   if(process.env.IOS_CREATIVE_HTML_ONLY!=='1'){await captureHtml({html,htmlPath:join(out,`${name}.html`),width:w,height:h,scale:2,outFile});flattenPng(outFile);console.log(name);}
   const sourceURLs=i<2?[raw(1)]:i===2?[watch]:i===3?[raw('calendar')]:i===4?[raw(4)]:i===5?[raw('focus')]:i===6?[widgetSource]:[raw(3)];
   const sources=sourceURLs.map(url=>{const path=fileURLToPath(url);return{path,sha256:createHash('sha256').update(readFileSync(path)).digest('hex'),modifiedAt:statSync(path).mtime.toISOString()}});
   manifest.push({htmlSHA256:createHash('sha256').update(readFileSync(join(out,`${name}.html`))).digest('hex'),pngSHA256:process.env.IOS_CREATIVE_HTML_ONLY==='1'?null:createHash('sha256').update(readFileSync(outFile)).digest('hex'),rendered:process.env.IOS_CREATIVE_HTML_ONLY!=='1',sources,locale:lang,ascLocale:c.asc,device,order:i+1,scene:PAGE_NAMES[i],file:`${name}.png`,width:w*2,height:h*2,preview});
  }
  const names=PAGE_NAMES.map(n=>`${lang}-${device}-${n}.png`);
  const thumbH=pad?440:717,thumbW=pad?330:330;
  if(process.env.IOS_CREATIVE_HTML_ONLY!=='1'&&!selectedPages){
   const overview=`<!doctype html><style>body{margin:0;padding:24px;background:#20231f;display:flex;gap:18px}img{width:${thumbW}px;height:${thumbH}px;border-radius:25px}</style>${names.map(n=>`<img src="${uri(join(out,n))}">`).join('')}`;
   await captureHtml({html:overview,htmlPath:join(out,`${lang}-${device}-overview.html`),width:48+8*thumbW+7*18,height:thumbH+48,scale:1,outFile:join(out,`${lang}-${device}-overview.png`)});
  }
 }
}
writeFileSync(join(out,`manifest-${langs.join('_')}-${devices.join('_')}${selectedPages?'-pages-'+selectedPages.join('_'):''}.json`),JSON.stringify(manifest,null,2)+'\n');

if(!selectedPages&&langs.length===17&&devices.length===2&&process.env.IOS_CREATIVE_HTML_ONLY!=='1')writeFileSync(join(out,'manifest.json'),JSON.stringify({createdAt:new Date().toISOString(),complete:!preview,items:manifest},null,2)+'\n');

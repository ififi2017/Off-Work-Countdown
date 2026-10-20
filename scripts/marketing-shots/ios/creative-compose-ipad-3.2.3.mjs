// 3.2.3 App Store screenshots: the two widget pages for the iPad 13″ set
// (APP_IPAD_PRO_3GEN_129, 2064×2752), in the approved 3.2.0 iPad page layout
// (creative-compose.mjs, `pad`) with the 3.2.3 copy (creative-copy-3.2.3.mjs).
//   3 · Home Screen: a real iPad Home Screen of DoneAt widgets.
//   4 · Lock Screen: the iPad Lock Screen widgets. No Watch: it pairs only
//       with iPhone. Copy: IPAD_LOCK in creative-copy-3.2.3.mjs.
// They take positions 3 and 4; the old Watch (3) and widgets (7) pages
// retire. Other pages keep their uploads; see
// app-store-connect/ios/3.2.3/ipad-screenshots.md for the new order.
//
// Inputs: raw/3.2.3/widgets/<lang>-ipad-home.png and <lang>-ipad-lock.png
// (creative-capture-widgets-3.2.3.mjs on the iPad simulator).
//
//   IOS_SHOTS_LANGUAGE=zh-CN,en node scripts/marketing-shots/ios/creative-compose-ipad-3.2.3.mjs
import{readFileSync,writeFileSync,mkdirSync,existsSync}from'node:fs';import{execFileSync}from'node:child_process';
import{join,relative}from'node:path';import{fileURLToPath,pathToFileURL}from'node:url';import{createHash}from'node:crypto';
import{COPY}from'./creative-copy-3.2.1.mjs';import{PAGES,IPAD_LOCK}from'./creative-copy-3.2.3.mjs';import{posterFonts,assertPosterFonts}from'./creative-fonts.mjs';import{escapeHTML as esc}from'../brand.mjs';import{flattenPng}from'../chrome.mjs';import{renderer}from'./creative-renderer-3.2.1.mjs';

const dir=fileURLToPath(new URL('.',import.meta.url)),widgets=join(dir,'raw/3.2.3/widgets'),out=join(dir,'out/creative-3.2.3/ipad');mkdirSync(out,{recursive:true});
const uri=p=>pathToFileURL(p).href,hash=b=>createHash('sha256').update(b).digest('hex');
// The 3.2.0 iPad frame and its screen opening (creative-compose.mjs).
const frame={file:join(dir,'frames/ipad-pro-m5-13-inch-space-black-portrait.png'),w:2300,h:3000,x:'5.130435%',y:'4.133333%',sw:'89.739130%',sh:'91.733333%',r:'2.91% / 2.18%'};
// Headline sizes of the 3.2.0 iPad pages (creative-compose.mjs `sizes` × 1.16).
const sizes={en:72,de:66,fr:64,es:65,it:59,pt:62,ja:68,ko:60,ru:58,tr:64,id:62,vi:60,th:65,'hi-IN':60,ar:76,'zh-CN':76,'zh-TW':76};
const languages=(process.env.IOS_SHOTS_LANGUAGE||Object.keys(sizes).join(',')).split(',');

const layoutScript=`<script>window.layoutReady=document.fonts.ready.then(()=>{
const fit=(e,min)=>{let n=parseFloat(getComputedStyle(e).fontSize);const r=document.createRange();r.selectNodeContents(e);while(r.getBoundingClientRect().width>e.getBoundingClientRect().width-1&&n>min){n-=.5;e.style.fontSize=n+'px';}};
for(const e of document.querySelectorAll('.line,.subline,.label'))fit(e,14);
const lines=[...document.querySelectorAll('h1 .line')],common=Math.min(...lines.map(e=>parseFloat(getComputedStyle(e).fontSize)));for(const e of lines)e.style.fontSize=common+'px';
// As in the 3.2.0 iPad pages: the device starts below the copy, never above
// 480 px. Rects are measured at zoom 2, so they are halved here.
const b=document.querySelector('.editorial').getBoundingClientRect(),top=Math.max(480,b.bottom/2+44);document.querySelector('.art').style.top=top+'px';
return new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));});
window.layoutAudit=()=>{const issues=[],body=document.body.getBoundingClientRect();
for(const e of document.querySelectorAll('.line,.subline,.label')){const r=document.createRange();r.selectNodeContents(e);const a=r.getBoundingClientRect(),b=e.getBoundingClientRect();if(a.width>b.width+2)issues.push({text:e.textContent,issue:'horizontal overflow'});if(a.left<body.left-1||a.right>body.right+1||a.bottom>body.bottom)issues.push({text:e.textContent,issue:'text outside canvas'});}
const art=document.querySelector('.device').getBoundingClientRect(),copy=document.querySelector('.editorial').getBoundingClientRect();
if(art.top<copy.bottom+30)issues.push({issue:'art overlaps text'});
for(const e of document.querySelectorAll('.device,.loupe')){const r=e.getBoundingClientRect();if(r.left<body.left||r.right>body.right)issues.push({issue:'art outside canvas'});}
const h1=Math.min(...[...document.querySelectorAll('h1 .line')].map(e=>parseFloat(e.style.fontSize||getComputedStyle(e).fontSize)));
return{issues,headlinePx:h1};};</script>`;

const device=(src,width,left)=>`<div class="device" style="left:${left}px;width:${width}px"><div class="screen"><img src="${uri(src)}"></div><img class="frame" src="${uri(frame.file)}"></div>`;

const manifestFile=join(out,'screenshot-manifest.json');let items=existsSync(manifestFile)?JSON.parse(readFileSync(manifestFile,'utf8')).items:[];
const r=await renderer();
try{for(const lang of languages){
 const c=COPY[lang],font=posterFonts(lang),dest=join(out,lang),rtl=lang==='ar';mkdirSync(dest,{recursive:true});
 for(const [order,scene] of [[3,'home'],[4,'lock']]){
  const p=scene==='lock'?IPAD_LOCK[lang]:PAGES[lang][scene],w=1032,h=1376,src=join(widgets,`${lang}-ipad-${scene}.png`),sources=[frame.file,src];
  if(!existsSync(src))throw Error(`Missing iPad ${scene} capture for ${lang}: ${src}`);
  let art=device(src,866,83);
  if(scene==='lock'){
   // Lock Screen only: Apple Watch pairs only with iPhone, so an iPad page
   // shows no Watch. The widgets sit near the bottom of the display, which
   // the 866 px crop of the other pages would cut off, so this page shows
   // the whole iPad, centred, at 660 px. On a 13″ display those widgets are
   // small, so the real widget row (native 600–1464 × 2330–2530, the same on
   // every locale) is also shown enlarged just above itself, as the 3.2.0
   // widget page shows real widget crops.
   const dw=660,dh=dw*frame.h/frame.w,left=(w-dw)/2;
   const rowCrop=[600,2330,864,200],rw=580,rs=rw/rowCrop[2],rowCX=left+dw*(0.051304+0.897391*0.5),rowCY=dh*(0.041333+0.917333*((rowCrop[1]+rowCrop[3]/2)/2752));
   const loupe=`<div class="loupe" style="left:${Math.round(rowCX-rw/2)}px;top:${Math.round(rowCY-110-rowCrop[3]*rs/2)}px;width:${rw}px;height:${Math.round(rowCrop[3]*rs)}px"><img src="${uri(src)}" style="width:${2064*rs}px;left:${-rowCrop[0]*rs}px;top:${-rowCrop[1]*rs}px"></div>`;
   art=device(src,dw,left)+loupe;
  }
  const lines=(xs,accent)=>xs.filter(Boolean).map((t,n)=>`<span class="${accent?'line':'subline'} ${accent&&n===xs.length-1?'accent':''}">${esc(t)}</span>`).join('');
  const tall=['ar','th','hi-IN'].includes(lang);
  const html=`<!doctype html><html lang="${lang}"><meta charset="utf-8"><style>${font.css}*{box-sizing:border-box}html,body{margin:0;width:${w*2}px;height:${h*2}px;overflow:hidden}body{width:${w}px;height:${h}px;zoom:2;position:relative;background:radial-gradient(ellipse at 80% 90%,#ffecd9 0%,transparent 60%),#fcf7ef;color:#25231f;font-family:${font.sans};font-weight:500;font-synthesis:none}h1,p{margin:0}.accent{color:#ff5100}.line,.subline{display:block;white-space:nowrap;word-break:keep-all;overflow-wrap:normal;hyphens:none}.label{position:absolute;left:70px;top:58px;width:${w-140}px;font-size:25px;line-height:1.4;color:#776e63;letter-spacing:.1px;white-space:nowrap}.editorial{position:absolute;left:70px;top:126px;width:${w-140}px;z-index:3}h1{font-size:${sizes[lang]*1.16}px;line-height:${tall?1.38:1.24};font-family:${font.serif};font-weight:700;letter-spacing:${['zh-CN','zh-TW','ja'].includes(lang)?'-3px':tall?'0':'-1.5px'}}.sub{margin-top:32px;font-size:28px;line-height:1.5;color:#776e63}.art{position:absolute;left:0;top:480px;width:${w}px;height:${h}px}.device{position:absolute;top:0;filter:drop-shadow(0 16px 22px #3a271322)}.screen{position:absolute;top:${frame.y};left:${frame.x};width:${frame.sw};height:${frame.sh};border-radius:${frame.r};overflow:hidden}.screen img{width:100%;height:100%;object-fit:cover;object-position:top;display:block}.frame{position:relative;width:100%;display:block}.loupe{position:absolute;z-index:1;overflow:hidden;border-radius:26px;box-shadow:0 18px 30px #2a1d1040,0 0 0 1.5px #ffffff70}.loupe img{position:absolute;max-width:none}.copy{direction:${rtl?'rtl':'ltr'}}${rtl?'.label.copy{text-align:right}':''}</style><body><div class="label copy">${esc(p.label)}</div><div class="editorial copy"><h1>${lines(p.lines,true)}</h1><p class="sub">${lines(p.sub)}</p></div><div class="art">${art}</div>${layoutScript}</body></html>`;
  const name=`${String(order).padStart(2,'0')}-widgets-${scene}`,htmlFile=join(dest,name+'.html'),pngFile=join(dest,name+'.png');
  const audit=await r.still(htmlFile,html,w*2,h*2,pngFile);const fontsUsed=await assertPosterFonts(r,'.label, h1 .line, .subline',`${lang} ipad ${name}`);if(audit.issues.length)throw Error(JSON.stringify({lang,scene,audit}));flattenPng(pngFile);
  const png=readFileSync(pngFile);if(png.readUInt32BE(16)!==w*2||png.readUInt32BE(20)!==h*2||png[25]!==2)throw Error('Invalid opaque PNG '+pngFile);
  const item={locale:lang,ascLocale:c.asc,platform:'ipad',order,scene:'widgets-'+scene,file:relative(out,pngFile),width:w*2,height:h*2,display:'APP_IPAD_PRO_3GEN_129',sha256:hash(png),sources:sources.map(f=>({file:relative(dir,f),sha256:hash(readFileSync(f))})),copy:p,fontsUsed,layoutAudit:audit,status:'proof-not-uploaded'};
  items=items.filter(x=>!(x.locale===lang&&x.order===order));items.push(item);
  writeFileSync(manifestFile,JSON.stringify({createdAt:new Date().toISOString(),uploaded:false,items},null,2)+'\n');console.log(lang,name,`${audit.headlinePx}px`);
 }
}}finally{await r.close();}

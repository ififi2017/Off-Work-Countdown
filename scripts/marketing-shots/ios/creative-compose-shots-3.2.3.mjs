// 3.2.3 App Store screenshots: two widget pages for the iPhone 6.9″ set
// (APP_IPHONE_67, 1320×2868), in the approved 3.2.1/3.2.2 page layout.
//   3 · Home Screen: a real Home Screen of free DoneAt widgets.
//   4 · Lock Screen and Apple Watch: the Lock Screen widgets and controls,
//       with the upgraded Watch countdown in front.
// They take positions 3 and 4; the old Watch (5) and widgets (9) pages
// retire. Other pages keep their 3.2.2 uploads; see
// app-store-connect/ios/3.2.3/screenshots.md for the new order.
//
//   IOS_SHOTS_LANGUAGE=zh-CN,en node scripts/marketing-shots/ios/creative-compose-shots-3.2.3.mjs
import{readFileSync,writeFileSync,mkdirSync,existsSync}from'node:fs';import{execFileSync}from'node:child_process';
import{join,relative}from'node:path';import{fileURLToPath,pathToFileURL}from'node:url';import{createHash}from'node:crypto';
import{COPY}from'./creative-copy-3.2.1.mjs';import{PAGES}from'./creative-copy-3.2.3.mjs';import{posterFonts,assertPosterFonts}from'./creative-fonts.mjs';import{escapeHTML as esc}from'../brand.mjs';import{flattenPng}from'../chrome.mjs';import{renderer}from'./creative-renderer-3.2.1.mjs';

const dir=fileURLToPath(new URL('.',import.meta.url)),widgets=join(dir,'raw/3.2.3/widgets'),search=join(dir,'raw/3.2.3/search'),out=join(dir,'out/creative-3.2.3/shots');mkdirSync(out,{recursive:true});
const uri=p=>pathToFileURL(p).href,hash=b=>createHash('sha256').update(b).digest('hex');
const frame={file:join(dir,'frames/iPhone 18 Pro Max - Silver - Portrait.png'),w:1470,h:3000,x:75,y:66,sw:1320,sh:2868,r:'14.4% / 6.62%'};
const watchFrame=join(dir,'frames/watch-s11-46mm-gold-milanese.png');

// Page copy lives in creative-copy-3.2.3.mjs (PAGES).
const languages=(process.env.IOS_SHOTS_LANGUAGE||Object.keys(PAGES).join(',')).split(',');

const layoutScript=`<script>window.layoutReady=document.fonts.ready.then(()=>{
const fit=(e,min)=>{let n=parseFloat(getComputedStyle(e).fontSize);const r=document.createRange();r.selectNodeContents(e);while(r.getBoundingClientRect().width>e.getBoundingClientRect().width-1&&n>min){n-=.5;e.style.fontSize=n+'px';}};
for(const e of document.querySelectorAll('.line,.subline,.label,.note'))fit(e,12);
const lines=[...document.querySelectorAll('h1 .line')],common=Math.min(...lines.map(e=>parseFloat(getComputedStyle(e).fontSize)));for(const e of lines)e.style.fontSize=common+'px';
// The art starts below the copy, and never above the approved 475 px line.
const b=document.querySelector('.editorial').getBoundingClientRect(),top=Math.max(475,b.bottom/2+30),art=document.querySelector('.art');art.style.top=top+'px';
return new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));});
window.layoutAudit=()=>{const issues=[],body=document.body.getBoundingClientRect();
for(const e of document.querySelectorAll('.line,.subline,.label,.note')){const r=document.createRange();r.selectNodeContents(e);const a=r.getBoundingClientRect(),b=e.getBoundingClientRect();if(a.width>b.width+2)issues.push({text:e.textContent,issue:'horizontal overflow'});if(a.left<body.left-1||a.right>body.right+1||a.bottom>body.bottom)issues.push({text:e.textContent,issue:'text outside canvas'});}
const art=document.querySelector('.art').getBoundingClientRect(),copy=document.querySelector('.editorial').getBoundingClientRect(),note=document.querySelector('.note').getBoundingClientRect();
if(art.top<copy.bottom+35*2)issues.push({issue:'art overlaps text'});
for(const e of document.querySelectorAll('.device,.watch')){const r=e.getBoundingClientRect();if(r.left<body.left||r.right>body.right)issues.push({issue:'art outside canvas'});if(r.bottom>note.top-8)issues.push({issue:'art over note'});}
return{issues};};</script>`;

const phone=(src,width,left)=>`<div class="device" style="left:${left}px;width:${width}px;height:${width*frame.h/frame.w}px"><div class="screen" style="left:${frame.x/frame.w*100}%;top:${frame.y/frame.h*100}%;width:${frame.sw/frame.w*100}%;height:${frame.sh/frame.h*100}%;border-radius:${frame.r}"><img src="${uri(src)}"></div><img class="frame" src="${uri(frame.file)}"></div>`;

const manifestFile=join(out,'screenshot-manifest.json');let items=existsSync(manifestFile)?JSON.parse(readFileSync(manifestFile,'utf8')).items:[];
const r=await renderer();
try{for(const lang of languages){
 const c=COPY[lang],font=posterFonts(lang),dest=join(out,lang);mkdirSync(dest,{recursive:true});
 for(const [order,scene] of [[3,'home'],[4,'lock']]){
  const p=PAGES[lang][scene],w=660,h=1434,sources=[frame.file];let art;
  if(scene==='home'){const src=join(widgets,`${lang}-home1.png`);sources.push(src);art=`<div class="art">${phone(src,443,(w-443)/2)}</div>`;}
  else{
   // The phone moves left so the Watch sits in front of its bezel only,
   // clear of every Lock Screen widget and control.
   // The Watch fixture's status-bar clock shows the capture time, not the
   // phone's; its top 100 px (clock only) are blacked out like the bezel.
   const src=join(widgets,`${lang}-lock.png`),raw=join(search,`${lang}-watch.png`),watch=join(dest,'sources/watch.png');sources.push(src,raw,watchFrame);
   mkdirSync(join(dest,'sources'),{recursive:true});execFileSync('python3',['-c','from PIL import Image,ImageDraw;import sys;im=Image.open(sys.argv[1]).convert("RGB");ImageDraw.Draw(im).rectangle((0,0,im.width,100),fill=(0,0,0));im.save(sys.argv[2])',raw,watch]);
   art=`<div class="art">${phone(src,443,32)}<div class="watch" style="left:418px;top:420px;width:214px;height:${214*880/560}px"><img class="watch-screen" src="${uri(watch)}"><img class="watch-frame" src="${uri(watchFrame)}"></div></div>`;
  }
  const lines=(xs,accent)=>xs.filter(Boolean).map((t,n)=>`<span class="${accent?'line':'subline'} ${accent&&n===xs.length-1?'accent':''}">${esc(t)}</span>`).join('');
  const tall=['ar','th','hi-IN'].includes(lang);
  const html=`<!doctype html><html lang="${lang}"><meta charset="utf-8"><style>${font.css}*{box-sizing:border-box}html,body{margin:0;width:${w*2}px;height:${h*2}px;overflow:hidden}body{width:${w}px;height:${h}px;zoom:2;position:relative;background:radial-gradient(ellipse at 80% 95%,#ffe9d2,transparent 60%),#fcf7ef;color:#25231f;font-family:${font.sans};font-synthesis:none}h1,p{margin:0}.accent{color:#ff5100}.line,.subline{display:block;white-space:nowrap;word-break:keep-all;overflow-wrap:normal;hyphens:none}.label{position:absolute;top:45px;left:55px;right:45px;color:#776e63;font-size:20px;line-height:1.4;white-space:nowrap}.editorial{position:absolute;top:112px;left:55px;right:45px;z-index:2}h1{font-family:${font.serif};font-size:73px;line-height:${tall?1.38:1.23};font-weight:700;letter-spacing:${tall?0:-1.5}px}.sub{font-size:24px;line-height:1.55;margin-top:22px;color:#776e63}.art{position:absolute;left:0;top:475px;width:${w}px}.device{position:absolute;top:0;filter:drop-shadow(0 18px 25px #30202c28)}.screen{position:absolute;overflow:hidden}.screen img{display:block;width:100%;height:100%;object-fit:contain}.frame{position:relative;width:100%;display:block}.watch{position:absolute;filter:drop-shadow(0 16px 22px #30202c40)}.watch-frame{position:absolute;width:100%;height:100%}.watch-screen{position:absolute;left:12.857143%;top:21.818182%;width:74.285714%;height:56.363636%;object-fit:contain;border-radius:20%;background:#000}.note{position:absolute;left:55px;right:45px;bottom:20px;color:#8b8074;font-size:14px;white-space:nowrap}</style><body><div class="label">${esc(p.label)}</div><div class="editorial"><h1>${lines(p.lines,true)}</h1><p class="sub">${lines(p.sub)}</p></div>${art}<p class="note">${esc(c.note)}</p>${layoutScript}</body></html>`;
  const name=`${String(order).padStart(2,'0')}-widgets-${scene}`,htmlFile=join(dest,name+'.html'),pngFile=join(dest,name+'.png');
  const audit=await r.still(htmlFile,html,w*2,h*2,pngFile);const fontsUsed=await assertPosterFonts(r,'.label, h1 .line, .subline, .note',`${lang} ${name}`);if(audit.issues.length)throw Error(JSON.stringify({lang,scene,audit}));flattenPng(pngFile);
  const png=readFileSync(pngFile);if(png.readUInt32BE(16)!==w*2||png.readUInt32BE(20)!==h*2||png[25]!==2)throw Error('Invalid opaque PNG '+pngFile);
  const item={locale:lang,ascLocale:c.asc,platform:'iphone',order,scene:'widgets-'+scene,file:relative(out,pngFile),width:w*2,height:h*2,display:'APP_IPHONE_67',sha256:hash(png),sources:sources.map(f=>({file:relative(dir,f),sha256:hash(readFileSync(f))})),copy:p,fontsUsed,layoutAudit:audit,status:'proof-not-uploaded'};
  items=items.filter(x=>!(x.locale===lang&&x.order===order));items.push(item);
  writeFileSync(manifestFile,JSON.stringify({createdAt:new Date().toISOString(),uploaded:false,items},null,2)+'\n');console.log(lang,name);
 }
}}finally{await r.close();}

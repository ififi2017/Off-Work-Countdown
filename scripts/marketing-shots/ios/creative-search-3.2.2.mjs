// 3.2.2 App Store search-results video: 1920×1280, 24 s, 30 fps, silent loop.
//
//   IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/creative-search-3.2.2.mjs [--stills]
//
// Same six-feature tour as the 3.2.1 V4 (countdown, widgets, focus, records,
// cycle report, time off) recaptured from the 3.2.2 build, re-composed so every
// essential element sits inside the Art Safe Area of Apple's search-results
// template. 3.2.1 V4 spread its brand, copy and phone across the full canvas and
// was cropped on real devices; shrinking that layout into the safe area (V5)
// left the UI too small to read. Here the phone frame is dropped and each scene
// shows a native crop of the screen region that carries the feature, so the
// subject fills most of the safe area. Only the background extends beyond it.
//
// Every rendered frame is audited against the safe area and for clipped text;
// a violation stops the render rather than producing a file.
import {spawn,execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync,renameSync} from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {COPY} from './creative-copy-3.2.1.mjs';
import {renderer} from './creative-renderer-3.2.1.mjs';
import {posterFonts} from './creative-fonts.mjs';

const dir=fileURLToPath(new URL('.',import.meta.url));
const raw=join(dir,'raw/3.2.2/search'),out=join(dir,'out/creative-3.2.2/search');mkdirSync(out,{recursive:true});
const TEMPLATE=JSON.parse(readFileSync(join(dir,'../../../app-store-connect/ios/3.2.2/apple-creative-template-guides.json'),'utf8')).templates.find(t=>t.scene==='search-3x2');
const W=1920,H=1280,FPS=30,DURATION=24,k=W/TEMPLATE.width;
const SAFE={x:TEMPLATE.safeArea.x*k,y:TEMPLATE.safeArea.y*k,width:TEMPLATE.safeArea.width*k,height:TEMPLATE.safeArea.height*k};
// Working area: the safe area less a 16 px margin, so shadows stay inside too.
const M=16,L=Math.ceil(SAFE.x+M),T=Math.ceil(SAFE.y+M),R=Math.floor(SAFE.x+SAFE.width-M),B=Math.floor(SAFE.y+SAFE.height-M);
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const run=(cmd,args)=>new Promise((resolve,reject)=>{const c=spawn(cmd,args,{stdio:'inherit'});c.on('error',reject);c.on('close',n=>n===0?resolve():reject(Error(cmd+': '+n)))});

// Native crop [x,y,w,h] on the 1320×2868 capture and where it lands. Crops keep
// the card's aspect exactly, so nothing is stretched or letterboxed.
const card=(cropW,cropH,h=B-T)=>{const w=Math.round(h*cropW/cropH);return[R-w,T,w,h];};
const SCENES=[
 // The countdown is the hook: a wide card under a single centred headline.
 {key:'timer',crop:[0,330,1320,500],inPoint:0.2,box:(()=>{const h=280,w=Math.round(h*1320/500);return[Math.round((L+R-w)/2),B-22-h,w,h];})(),radius:34},
 {key:'widgets',crop:null,inPoint:0.2,box:card(1050,960),radius:30},
 {key:'focus',crop:[40,520,1240,1140],inPoint:0.2,box:card(1240,1140),radius:30},
 {key:'records',crop:[40,570,1240,1330],inPoint:0.2,box:card(1240,1330),radius:30},
 // The report counts its hours up while the month's bars fill.
 {key:'report',crop:[0,380,1320,2060],inPoint:5.0,box:card(1320,2060),radius:30,dark:true},
 {key:'leave',crop:[0,440,1320,1500],inPoint:0.2,box:card(1320,1500),radius:30},
];
const transitions=[4,8,12,16,20,23.45];
const languages=(process.env.IOS_SHOTS_LANGUAGE||'en,zh-CN').split(',');

function copyFor(lang){
 const c=COPY[lang];
 return c.tour.map((p,i)=>{const lines=p.lines.length>2?[p.lines.slice(0,-1).join(' '),p.lines.at(-1)]:p.lines;
  return{label:p.label,lines,sub:p.sub.join(' '),note:(i===2||i===4?'DoneAt Plus · ':i===5?c.trials+' · ':'')+c.note};});
}

async function prepare(lang){
 const sources=[];
 for(const s of SCENES){
  const source=join(raw,`${lang}-${s.key}.mov`),png=join(raw,`${lang}-${s.key}.png`);
  const crop=s.crop||(()=>{const c=JSON.parse(execFileSync('python3',[join(dir,'creative-widget-crop.py'),png],{encoding:'utf8'}));return[c.x,c.y,c.w,c.h];})();
  const nativeDuration=Number(execFileSync('ffprobe',['-v','error','-show_entries','format=duration','-of','csv=p=0',source],{encoding:'utf8'}));
  // simctl only writes a frame when the screen changes, so a settled screen can
  // be a single frame long. Hold the last native frame rather than invent one.
  const inPoint=nativeDuration>s.inPoint+4.8?s.inPoint:Math.max(0,Math.min(s.inPoint,nativeDuration-0.05));
  const [,, bw,bh]=s.box,scale=[Math.min(crop[2],bw*2),Math.round(Math.min(crop[2],bw*2)*bh/bw/2)*2];
  const filter=`tpad=stop_mode=clone:stop_duration=6,crop=${crop[2]}:${crop[3]}:${crop[0]}:${crop[1]},fps=${FPS},scale=${scale[0]}:${scale[1]}:flags=lanczos,setsar=1`;
  const prepared=join(out,`${lang}-${s.key}-clip.mp4`),recipe=JSON.stringify({sha:sha(source),inPoint,filter});
  if(!existsSync(prepared)||!existsSync(prepared+'.json')||readFileSync(prepared+'.json','utf8')!==recipe){
   await run('ffmpeg',['-y','-loglevel','error','-i',source,'-ss',String(inPoint),'-t','4.8','-an','-vf',filter,'-c:v','libx264','-preset','fast','-crf','14','-pix_fmt','yuv420p',prepared]);
   writeFileSync(prepared+'.json',recipe);
  }
  sources.push({scene:s.key,file:`${lang}-${s.key}.mov`,sha256:sha(source),capture:`${lang}-${s.key}.png`,captureSHA256:sha(png),inPoint,crop,nativeDuration});
 }
 return sources;
}

function html(lang){
 const font=posterFonts(lang),c=copyFor(lang),rtl=lang==='ar',tall=['ar','th','hi-IN','mr-IN'].includes(lang),cjk=['zh-CN','zh-TW','ja','ko'].includes(lang);
 const line=(text,cls='')=>`<div class="line ${cls}"><div class="ink">${text}</div></div>`;
 const sections=SCENES.map((s,i)=>{
  const [bx]=s.box,width=s.key==='timer'?R-L:bx-48-L;
  const style=s.key==='timer'?`left:${L}px;top:${T+14}px;width:${width}px`:`left:${L}px;width:${width}px`;
  return `<section id="s${i}" class="scene ${s.key}"><div class="copy" style="${style}">${line(c[i].label,'label')}<h1>${s.key==='timer'?line(`${c[i].lines[0]} <span class="accent">${c[i].lines[1]||''}</span>`):line(c[i].lines[0])+line(c[i].lines[1]||'','accent')}</h1>${line(c[i].sub,'sub')}${s.key==='timer'?'':line(c[i].note,'note')}</div></section>`;
 }).join('');
 const media=SCENES.map((s,i)=>`<video id="v${i}" muted playsinline preload="auto" src="${pathToFileURL(join(out,`${lang}-${s.key}-clip.mp4`)).href}"></video>`).join('');
 return `<!doctype html><meta charset="utf-8"><style>${font.css}
*{box-sizing:border-box}html,body{margin:0;width:${W}px;height:${H}px;overflow:hidden}
body{background:#fcf7ef;color:#25231f;font-family:${font.sans};font-synthesis:none}
.glow{position:absolute;width:1500px;height:1100px;left:620px;top:220px;background:radial-gradient(ellipse,#ffbf8050,transparent 66%)}
.wordmark{position:absolute;left:${L}px;top:${T-6}px;font-size:30px;font-weight:750;letter-spacing:-1px;line-height:1.2}
.scene{position:absolute;inset:0;visibility:hidden}
.copy{position:absolute;direction:${rtl?'rtl':'ltr'}}
.line{overflow:hidden;white-space:nowrap;word-break:keep-all;hyphens:none}.ink{will-change:transform}
.label{color:#776e63;font-size:19px;font-weight:650;letter-spacing:${tall||cjk?0:1.2}px;line-height:1.5}
h1{margin:14px 0 0;font-family:${font.serif};font-size:${cjk?66:58}px;line-height:${tall?1.55:1.2};letter-spacing:${tall?0:-1}px;font-weight:700}
.accent{color:#f45a1e}
.sub{font-size:21px;color:#6f665c;line-height:1.45;margin-top:22px}
.note{font-size:15px;color:#958a7d;line-height:1.4;margin-top:12px}
.timer .copy{text-align:center}.timer h1{margin-top:6px;font-size:${cjk?60:52}px}.timer .sub{margin-top:10px}
.surface{position:absolute;overflow:hidden;background:#f1f0f6;box-shadow:0 6px 10px #30202c1c,0 1px 3px #30202c14}
.surface video{position:absolute;inset:0;width:100%;height:100%;object-fit:fill;visibility:hidden}
.rail{position:absolute;left:${L}px;top:${B-8}px;height:8px;display:flex;gap:10px}.rail i{display:block;width:22px;height:6px;border-radius:6px;background:#30202c20}
</style><div class="glow"></div><div class="wordmark">DoneAt</div>${sections}<div class="surface">${media}</div><div class="rail">${SCENES.map(()=>'<i></i>').join('')}</div><script>
const SAFE=${JSON.stringify(SAFE)},boxes=${JSON.stringify(SCENES.map(s=>[...s.box,s.radius]))},darks=${JSON.stringify(SCENES.map(s=>!!s.dark))},transitions=${JSON.stringify(transitions)};
// Fit each line to its column, then centre the copy block in the space left of the card.
window.layoutReady=document.fonts.ready.then(()=>{
 for(const e of document.querySelectorAll('.ink')){let n=parseFloat(getComputedStyle(e).fontSize);const r=document.createRange();r.selectNodeContents(e);while(r.getBoundingClientRect().width>e.parentElement.getBoundingClientRect().width-1&&n>14){n-=.5;e.style.fontSize=n+'px';}}
 for(const h of document.querySelectorAll('h1')){const es=[...h.querySelectorAll('.ink')],n=Math.min(...es.map(e=>parseFloat(getComputedStyle(e).fontSize)));for(const e of es)e.style.fontSize=n+'px';}
 for(const s of document.querySelectorAll('.scene:not(.timer) .copy')){s.parentElement.style.visibility='visible';const h=s.getBoundingClientRect().height;s.parentElement.style.visibility='';s.style.top=Math.round(${T+40}+(${B-24-T-40}-h)/2)+'px';}
});
const clamp=x=>Math.max(0,Math.min(1,x)),ease=x=>{x=clamp(x);return x*x*x*(x*(x*6-15)+10)},lerp=(a,b,p)=>a+(b-a)*p;
async function seek(v,t){t=Math.min(t,Math.max(0,v.duration-.04));if(Math.abs(v.currentTime-t)<.0001)return;await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('seek timeout')),5000);v.addEventListener('seeked',()=>{clearTimeout(timer);resolve()},{once:true});v.currentTime=t})}
window.render=async t=>{
 t=t%${DURATION};let from=0,to=0,u=0;
 for(let k=0;k<6;k++){const begin=transitions[k]-.5,end=transitions[k]+.5;if(t>=end){from=(k+1)%6;to=from;u=0;continue;}if(t>=begin){from=k;to=(k+1)%6;u=(t-begin)/(end-begin);}break;}
 window.settled=from===to;const p=ease(u),active=from!==to,box=boxes[from].map((v,i)=>lerp(v,boxes[to][i],p)),surface=document.querySelector('.surface');
 Object.assign(surface.style,{left:box[0]+'px',top:box[1]+'px',width:box[2]+'px',height:box[3]+'px',borderRadius:box[4]+'px',background:darks[active&&p>.5?to:from]?'#2a1c2e':'#f1f0f6'});
 const jobs=[];
 for(let i=0;i<6;i++){
  const visible=i===from||i===to,s=document.querySelector('#s'+i),v=document.querySelector('#v'+i);
  s.style.visibility=visible?'visible':'hidden';v.style.visibility=visible?'visible':'hidden';if(!visible)continue;
  // Copy blocks sit at different heights, so the outgoing lines leave in the
  // first half and the incoming ones arrive in the second; never both at once.
  s.querySelectorAll('.ink').forEach((node,n)=>{const q=active?ease((u-(i===from?0:.5)-n*.03)/.4):0;node.style.transform='translateY('+(active?(i===from?-105*q:105*(1-q)):0)+'%)';});
  // The incoming screen wipes up over the outgoing one; no fade through empty.
  v.style.zIndex=active&&i===to?2:1;v.style.clipPath=active&&i===to?'inset('+(100*(1-ease((u-.16)/.68)))+'% 0 0 0)':'none';
  const start=i===0?0:transitions[i-1]-.5;jobs.push(seek(v,i===0&&t>22?0:Math.min(4.7,Math.max(0,t-start))));
 }
 const weights=Array(6).fill(0);weights[from]=1-p;weights[to]+=p;
 document.querySelectorAll('.rail i').forEach((n,i)=>{n.style.width=(22+22*weights[i])+'px';n.style.background='color-mix(in srgb,#f45a1e '+(weights[i]*100)+'%,#30202c20)';});
 const g=(1-Math.cos(t*Math.PI/12))/2;document.querySelector('.glow').style.transform='translate('+(-90*g)+'px,'+(-40*g)+'px) scale('+(1+.08*g)+')';
 await Promise.all(jobs);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 const audit=layoutAudit();if(audit.issues.length)throw Error(JSON.stringify({time:t,issues:audit.issues}));window.validatedFrames=(window.validatedFrames||0)+1;
};
// Essential content: brand, card (with shadow), rail and every visible glyph.
window.layoutAudit=()=>{
 const issues=[],bounds=[];let minHeadline=Infinity;
 const check=(name,b,pad=0)=>{if(b.right<=b.left||b.bottom<=b.top)return;bounds.push({name,x:b.left,y:b.top,width:b.right-b.left,height:b.bottom-b.top});
  if(b.left-pad<SAFE.x-.5||b.top-pad<SAFE.y-.5||b.right+pad>SAFE.x+SAFE.width+.5||b.bottom+pad*2>SAFE.y+SAFE.height+.5)issues.push({issue:'outside Apple search safe area',name});};
 const card=document.querySelector('.surface').getBoundingClientRect();check('native card',card,8);
 check('brand',document.querySelector('.wordmark').getBoundingClientRect());check('rail',document.querySelector('.rail').getBoundingClientRect());
 for(const s of document.querySelectorAll('.scene'))if(s.style.visibility==='visible')for(const e of s.querySelectorAll('.ink')){
  if(!e.textContent)continue;const r=document.createRange();r.selectNodeContents(e);const b=r.getBoundingClientRect(),line=e.parentElement.getBoundingClientRect();
  if(b.width>line.width+1)issues.push({issue:'text clipped',text:e.textContent});
  const v={left:Math.max(b.left,line.left),right:Math.min(b.right,line.right),top:Math.max(b.top,line.top),bottom:Math.min(b.bottom,line.bottom)};
  if(v.bottom<=v.top)continue;check(e.textContent,v);
  if(window.settled!==false&&v.right>card.left-8&&v.left<card.right+8&&v.bottom>card.top-8&&v.top<card.bottom+8)issues.push({issue:'copy overlaps the native card',text:e.textContent});
  if(e.closest('h1'))minHeadline=Math.min(minHeadline,parseFloat(getComputedStyle(e).fontSize));
 }
 if(minHeadline<34)issues.push({issue:'headline too small',minHeadline});
 return{safeArea:SAFE,bounds,minHeadline,issues};
};
</script>`;
}

const STILLS=[0,2,3.75,4.25,6,8,10,12,14,16,18,20,22,23.75];
const manifestPath=join(out,'video-manifest.json');
let items=existsSync(manifestPath)?JSON.parse(readFileSync(manifestPath,'utf8')).items:[];
const r=await renderer();
try{for(const lang of languages){
 const sources=await prepare(lang),name=`${lang}-search-video-3.2.2`,htmlPath=join(out,name+'.html'),file=join(out,name+'.mp4');
 writeFileSync(htmlPath,html(lang));await r.load(htmlPath,W,H);
 await r.evaluate(`window.layoutReady.then(()=>Promise.all([...document.querySelectorAll('video')].map(v=>v.readyState>=2?0:new Promise((ok,no)=>{v.addEventListener('loadeddata',ok,{once:true});v.addEventListener('error',()=>no(Error('decode failed: '+v.src)),{once:true});}))))`);
 const audits=[];
 for(const t of STILLS){await r.evaluate(`render(${t})`);audits.push({time:t,...await r.evaluate('layoutAudit()')});writeFileSync(join(out,`${name}-${t.toFixed(2)}.png`),await r.grab());}
 if(process.argv.includes('--stills')){console.log('stills '+name);continue;}
 const working=file.replace(/\.mp4$/,'.encoding.mp4');
 const ff=spawn('ffmpeg',['-y','-loglevel','error','-f','image2pipe','-framerate',String(FPS),'-c:v','png','-i','-','-vf','scale=in_range=full:out_range=limited,format=yuv420p','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-c:v','libx264','-preset','slow','-crf','16','-movflags','+faststart',working],{stdio:['pipe','inherit','inherit']});
 const done=once(ff,'close');
 try{for(let f=0;f<DURATION*FPS;f++){for(let a=0;;a++){try{await r.evaluate(`render(${f/FPS})`);break;}catch(e){if(a>=2||!String(e).includes('seek timeout'))throw e;}}if(!ff.stdin.write(await r.grab()))await once(ff.stdin,'drain');if(f%180===0)console.log(name,f+'/'+DURATION*FPS);}ff.stdin.end();const[code]=await done;if(code)throw Error('encoder failed');renameSync(working,file);}catch(e){ff.kill();throw e;}
 const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-show_entries','stream=codec_type,width,height,r_frame_rate,nb_frames,pix_fmt:format=duration','-of','json',file],{encoding:'utf8'}));
 const v=probe.streams.find(s=>s.codec_type==='video');
 if(probe.streams.length!==1||v.width!==W||v.height!==H||v.r_frame_rate!==`${FPS}/1`||Number(v.nb_frames)!==DURATION*FPS||v.pix_fmt!=='yuv420p')throw Error('spec mismatch '+JSON.stringify(probe));
 const item={locale:lang,ascLocale:COPY[lang].asc,file:name+'.mp4',width:W,height:H,fps:FPS,duration:DURATION,frames:DURATION*FPS,audio:false,sha256:sha(file),
  validatedFrames:await r.evaluate('window.validatedFrames'),safeArea:SAFE,template:TEMPLATE,stillAudits:audits.map(a=>({time:a.time,minHeadline:a.minHeadline,issues:a.issues})),sources,status:'local-not-uploaded'};
 items=items.filter(x=>x.locale!==lang);items.push(item);
 writeFileSync(manifestPath,JSON.stringify({createdAt:new Date().toISOString(),uploaded:false,items},null,2)+'\n');console.log('Completed '+name);
}}finally{await r.close();}

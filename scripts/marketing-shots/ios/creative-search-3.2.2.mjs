// 3.2.2 App Store search-results video: 1920×1280, 24 s, 30 fps, silent loop.
//
//   IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/creative-search-3.2.2.mjs [--stills]
//
// Eight beats of three seconds, cut in 0.3 s: countdown → widget → focus →
// records → cycle report → time off → Apple Watch → life. Search results
// autoplay muted at thumbnail size, so each beat lands its one line and one
// native hero within the first second and moves on.
//
// Heroes are native pixels at or below capture resolution (never upscaled).
// Headline and hero sit inside the Art Safe Area of Apple's search-results
// template; the native surface around the hero bleeds past it so the full
// 3:2 frame reads as full while a device crop keeps the message.
//
// Motion comes from the app: the countdown, widget, focus timer, Watch and
// report count live; recorded days fill in order and the leave run lights up
// day by day. A slow push carries each beat. Every frame is audited: glyphs
// and hero inside the safe area, nothing clipped, settled copy clear of every
// surface. A violation stops the render.
import {spawn,execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync,renameSync,readdirSync} from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {COPY} from './creative-copy-3.2.1.mjs';
import {searchLine,LOCALES} from './creative-copy-3.2.2.mjs';
import {renderer} from './creative-renderer-3.2.1.mjs';
import {posterFonts} from './creative-fonts.mjs';

const dir=fileURLToPath(new URL('.',import.meta.url));
const raw=join(dir,'raw/3.2.2/search'),out=join(dir,'out/creative-3.2.2/search');mkdirSync(out,{recursive:true});
const TEMPLATE=JSON.parse(readFileSync(join(dir,'../../../app-store-connect/ios/3.2.2/apple-creative-template-guides.json'),'utf8')).templates.find(t=>t.scene==='search-3x2');
const W=1920,H=1280,FPS=30,DURATION=24,k=W/TEMPLATE.width;
const SAFE={x:TEMPLATE.safeArea.x*k,y:TEMPLATE.safeArea.y*k,width:TEMPLATE.safeArea.width*k,height:TEMPLATE.safeArea.height*k};
const M=16,L=Math.ceil(SAFE.x+M),T=Math.ceil(SAFE.y+M),R=Math.floor(SAFE.x+SAFE.width-M),B=Math.floor(SAFE.y+SAFE.height-M);
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const run=(cmd,args)=>new Promise((resolve,reject)=>{const c=spawn(cmd,args,{stdio:'inherit'});c.on('error',reject);c.on('close',n=>n===0?resolve():reject(Error(cmd+': '+n)))});

// Headlines live in creative-copy-3.2.2.mjs (one [dark, accent] pair per scene).
const NOTE={'zh-CN':'界面为演示数据',en:'Illustrative data'};

// Native coordinates on each capture (iPhone 1320×2868, Watch 416×496).
// `key` must stay in the safe area; `show` is the surface around it (bleed).
// `radius` is one value or [top-left, top-right, bottom-right, bottom-left].
const SCENES=[
 {key:'timer',line:'countdown',video:true,inPoint:0.2,bg:'#f2f2f7',
  pieces:[{key:[0,372,1320,448],show:[0,372,1320,2496],radius:56}]},
 {key:'widgets',line:'widget',align:'center',video:true,inPoint:0.2,bg:'#3a2a3f',
  pieces:[{key:[330,930,662,536],show:[140,930,1040,852],radius:66}],anchor:{piece:0,widget:true,at:821}},
 // The running focus block; the day's planned blocks bleed below.
 {key:'focus',line:'focus',plus:true,video:true,inPoint:0.2,bg:'#f2f2f7',
  pieces:[{key:[40,512,1240,390],show:[40,512,1240,1350],radius:44}]},
 // Month header joined to last week: regular days, overtime (two days), a
 // day of leave and weekend rest. Marked cells fill in reading order.
 {key:'records',line:'records',bg:'#ffffff',
  pieces:[{key:[53,725,1214,105],show:[53,725,1214,105],radius:[44,44,0,0]},{key:[53,1170,1214,185],show:[53,1170,1214,700],radius:[0,0,44,44]}],
  reveal:{strips:[[1290,1340]],start:.45,step:.2},anchor:{piece:1,color:'blue',band:[1280,1440],at:1313}},
 // The month's hours counting up; the bars bleed below.
 // The in-point follows the recording: 0.6 s into its hours chapter.
 {key:'report',line:'report',plus:true,video:true,inPoint:'hours',bg:'#2a1c2e',
  pieces:[{key:[0,470,1320,330],show:[0,470,1320,2000],radius:56}]},
 // The plan's cost and result ("5 days of leave / 9 days off in a row"), then
 // both calendar rows of the run (Monday-first weeks); each day lights up.
 {key:'leave',line:'leave',align:'center',bg:'#ffffff',
  pieces:[{key:[53,512,1214,168],show:[53,498,1214,204],radius:44},{key:[53,1030,1214,358],show:[53,1030,1214,760],radius:44,gap:24}],
  reveal:{strips:[[1140,1192],[1290,1390]],start:.35,step:.13},anchor:{piece:1,color:'green',band:[1300,1500],at:1345}},
 // The Watch app's own review fixture, below its status bar.
 {key:'watch',line:'watch',align:'center',video:true,inPoint:0.5,bg:'#000000',native:[416,496],
  pieces:[{key:[0,118,416,290],show:[0,118,416,378],radius:64}]},
 // The life grid itself: lived years filled, the years ahead still open.
 {key:'life',line:'life',align:'center',bg:'#ffffff',
  pieces:[{key:[53,895,1214,580],show:[53,895,1214,800],radius:44}]},
];
const BEAT=3,HALF=.15,CENTERS=SCENES.map((_,i)=>i<SCENES.length-1?(i+1)*BEAT:DURATION-HALF);
if(CENTERS.at(-2)>=DURATION-2*HALF)throw Error('Scenes do not fit the loop');
const languages=(process.env.IOS_SHOTS_LANGUAGE||LOCALES.join(',')).split(',');
// All eight headlines in a video share one size: the largest at which every
// line fits. A line that pulls it below the floor is flagged (log and
// manifest) and needs a shorter translation; 56 px is the hard audit limit.
const FLOOR={latin:64,cjk:68};

// Taller scripts push calendar rows down: shift the anchored piece and its
// reveal strips by however far this capture's rows moved from the English one.
// The widget preview also sits at a different height per language (longer
// onboarding titles); creative-widget-crop.py finds it.
function placed(s,lang){
 if(!s.anchor)return s;
 const png=join(raw,`${lang}-${s.key}.png`);
 const y=s.anchor.widget?JSON.parse(execFileSync('python3',[join(dir,'creative-widget-crop.py'),png],{encoding:'utf8'})).y
  :Number(execFileSync('python3',[join(dir,'creative-marks.py'),png,JSON.stringify({anchor:s.anchor.color,band:s.anchor.band})],{encoding:'utf8'})),d=y-s.anchor.at;
 const move=([x,yy,w,h])=>[x,yy+d,w,h];
 return {...s,shift:d,pieces:s.pieces.map((p,j)=>j===s.anchor.piece?{...p,key:move(p.key),show:move(p.show)}:p),reveal:s.reveal&&{...s.reveal,strips:s.reveal.strips.map(([a,b])=>[a+d,b+d])}};
}

async function prepare(lang,scenes){
 const sources=[];
 for(let s of scenes){
  const png=join(raw,`${lang}-${s.key}.png`),mov=join(raw,`${lang}-${s.key}.mov`);
  const entry={scene:s.key,capture:`${lang}-${s.key}.png`,captureSHA256:sha(png)};
  if(s.video){
   // Full-frame clip at capture resolution, long enough for the beat plus both
   // cuts and the loop, so the numbers keep counting the whole time.
   if(s.inPoint==='hours')s={...s,inPoint:+(Number(execFileSync('python3',[join(dir,'creative-marks.py'),mov,JSON.stringify({reportHours:true})],{encoding:'utf8'}))+.6).toFixed(1)};
   const nativeDuration=Number(execFileSync('ffprobe',['-v','error','-show_entries','format=duration','-of','csv=p=0',mov],{encoding:'utf8'}));
   if(nativeDuration<s.inPoint+4)throw Error(`${mov} is ${nativeDuration}s; the beat needs ${s.inPoint+4}s`);
   const clip=join(out,`${lang}-${s.key}-clip.mp4`),recipe=JSON.stringify({sha:sha(mov),inPoint:s.inPoint,v:3});
   if(!existsSync(clip)||!existsSync(clip+'.json')||readFileSync(clip+'.json','utf8')!==recipe){
    await run('ffmpeg',['-y','-loglevel','error','-i',mov,'-ss',String(s.inPoint),'-t','4','-an','-vf',`fps=${FPS},setsar=1`,'-c:v','libx264','-preset','slow','-crf','10','-pix_fmt','yuv420p',clip]);
    writeFileSync(clip+'.json',recipe);
   }
   Object.assign(entry,{recording:`${lang}-${s.key}.mov`,recordingSHA256:sha(mov),inPoint:s.inPoint,nativeDuration});
  }
  // Arabic reads right to left, so its marked cells reveal in that order.
  if(s.reveal){const cells=JSON.parse(execFileSync('python3',[join(dir,'creative-marks.py'),png,JSON.stringify({x:53,width:1214,strips:s.reveal.strips})],{encoding:'utf8'}));
   entry.reveal=lang==='ar'?s.reveal.strips.flatMap(([y])=>cells.filter(c=>c[1]===y).reverse()):cells;}
  if(s.shift!=null)entry.rowShift=s.shift;
  sources.push(entry);
 }
 return sources;
}

function html(lang,sources,scenes){
 const font=posterFonts(lang),tall=['ar','th','hi-IN','mr-IN'].includes(lang),cjk=['zh-CN','zh-TW','ja','ko'].includes(lang);
 const note=NOTE[lang]??COPY[lang].note;
 const sections=scenes.map((s,i)=>{
  const [a,b]=searchLine(lang,s.line).lines,[nw,nh]=s.native||[1320,2868];
  const src=s.video?`<video muted playsinline preload="auto" src="${pathToFileURL(join(out,`${lang}-${s.key}-clip.mp4`)).href}"></video>`:`<img src="${pathToFileURL(join(raw,`${lang}-${s.key}.png`)).href}">`;
  const pieces=s.pieces.map(p=>`<div class="piece" style="background:${s.bg}"><div class="native" style="width:${nw}px;height:${nh}px">${src}${(sources[i].reveal||[]).map((r,q)=>r[1]>=p.show[1]&&r[1]<p.show[1]+p.show[3]?`<i class="mask" data-q="${q}" style="left:${r[0]}px;top:${r[1]}px;width:${r[2]}px;height:${r[3]}px"></i>`:'').join('')}</div></div>`).join('');
  return `<section id="s${i}" class="scene"><h1><div class="line"><div class="ink">${a} <span class="accent">${b}</span></div></div></h1><div class="hero">${pieces}<div class="key"></div></div><div class="note">${s.plus?'DoneAt Plus · ':''}${note}</div></section>`;
 }).join('');
 return `<!doctype html><meta charset="utf-8"><style>${font.css}
*{box-sizing:border-box}html,body{margin:0;width:${W}px;height:${H}px;overflow:hidden}
body{background:#fbf6ee;color:#25231f;font-family:${font.sans};font-synthesis:none}
.glow{position:absolute;width:1700px;height:1300px;left:420px;top:120px;background:radial-gradient(ellipse,#ffc48a4a,transparent 64%)}
.scene{position:absolute;inset:0;visibility:hidden}
h1{position:absolute;margin:0;font-family:${font.serif};font-weight:700;line-height:${tall?1.5:1.18};letter-spacing:${tall||cjk?0:-1.5}px;direction:${lang==='ar'?'rtl':'ltr'}}
.line{overflow:hidden;white-space:nowrap;word-break:keep-all}.ink{will-change:transform;display:inline-block}.accent{color:#f45a1e}
.hero{position:absolute;transform-origin:50% 50%}
.piece{position:absolute;overflow:hidden;box-shadow:0 18px 40px #30202c1f,0 2px 6px #30202c12}
.native{position:absolute;left:0;top:0;transform-origin:0 0}
.native img,.native video{position:absolute;inset:0;width:100%;height:100%}
.mask{position:absolute;background:#fff}
.key{position:absolute;pointer-events:none}
.note{position:absolute;right:28px;bottom:22px;font-size:15px;color:#a39686;letter-spacing:.2px}
</style><div class="glow"></div>${sections}<script>
const RTL=${lang==='ar'},REVEAL=${JSON.stringify(sources.map(x=>x.reveal||[]))},SAFE=${JSON.stringify(SAFE)},AREA=${JSON.stringify({L,T,R,B})},SCENES=${JSON.stringify(scenes)},CENTERS=${JSON.stringify(CENTERS)},HALF=${HALF},DURATION=${DURATION},MAX=${cjk?104:88};
const clamp=x=>Math.max(0,Math.min(1,x)),ease=x=>{x=clamp(x);return x*x*x*(x*(x*6-15)+10)};
function fit(h1,width,max){let n=max;h1.style.fontSize=n+'px';const e=h1.querySelector('.ink');while(e.getBoundingClientRect().width>width&&n>30){n-=1;h1.style.fontSize=n+'px';}return n;}
// Lay out once: headline at the top of the safe area, hero below it, scaled
// to the room left and never above native resolution.
window.shrink=[];window.layoutReady=document.fonts.ready.then(()=>{
 const G=28;
 SCENES.forEach((s,i)=>{const sec=document.getElementById('s'+i);sec.style.visibility='visible';window.shrink[i]=fit(sec.querySelector('h1'),AREA.R-AREA.L,MAX);sec.style.visibility='';});
 window.headlineSize=Math.min(...window.shrink);
 SCENES.forEach((s,i)=>{
  const sec=document.getElementById('s'+i),h1=sec.querySelector('h1'),hero=sec.querySelector('.hero');sec.style.visibility='visible';
  let oy=0;const rows=s.pieces.map(p=>{oy+=(p.gap||0);const y=oy;oy+=p.key[3];return y;});
  const kx0=Math.min(...s.pieces.map(p=>p.key[0])),kw=Math.max(...s.pieces.map(p=>p.key[0]+p.key[2]))-kx0,kh=oy;
  h1.style.fontSize=window.headlineSize+'px';Object.assign(h1.style,RTL?{right:(${W}-AREA.R)+'px',top:AREA.T+'px'}:{left:AREA.L+'px',top:AREA.T+'px'});
  const top=Math.ceil(h1.getBoundingClientRect().bottom+G),scale=Math.min(1,(AREA.R-AREA.L)/kw,(AREA.B-top)/kh);
  const left=s.align==='center'?(AREA.L+AREA.R-kw*scale)/2:RTL?AREA.R-kw*scale:AREA.L;
  Object.assign(hero.style,{left:left+'px',top:top+'px',width:kw*scale+'px',height:kh*scale+'px'});
  Object.assign(hero.querySelector('.key').style,{left:0,top:0,width:kw*scale+'px',height:kh*scale+'px'});
  // Each piece shows its surface around the key; the native layer is offset
  // so key pixels land exactly on the key rectangle.
  s.pieces.forEach((p,j)=>{
   const el=hero.querySelectorAll('.piece')[j],[sx,sy,sw,sh]=p.show,r=[].concat(p.radius);
   Object.assign(el.style,{left:(sx-kx0)*scale+'px',top:(rows[j]+(sy-p.key[1]))*scale+'px',width:sw*scale+'px',height:sh*scale+'px',borderRadius:(r.length===1?[r[0],r[0],r[0],r[0]]:r).map(v=>v*scale+'px').join(' ')});
   el.querySelector('.native').style.transform='scale('+scale+') translate('+(-sx)+'px,'+(-sy)+'px)';
  });
  sec.style.visibility='';
 });
});
async function seek(v,t){t=Math.min(t,Math.max(0,v.duration-.04));if(Math.abs(v.currentTime-t)<.0001)return;await new Promise((ok,no)=>{const timer=setTimeout(()=>no(Error('seek timeout')),5000);v.addEventListener('seeked',()=>{clearTimeout(timer);ok()},{once:true});v.currentTime=t})}
// Local time from the start of each scene's entrance. The countdown enters
// at the end of the loop, so its digits keep counting across 24 s → 0 s.
const entry=i=>i===0?DURATION-2*HALF:CENTERS[i-1]-HALF;
const local=(i,t)=>((t-entry(i))%DURATION+DURATION)%DURATION;
window.render=async t=>{
 t=((t%DURATION)+DURATION)%DURATION;
 const n=SCENES.length;let from=0,to=0,u=0;
 for(let k=0;k<n;k++){const b=CENTERS[k]-HALF,e=CENTERS[k]+HALF;if(t>=e){from=to=(k+1)%n;continue;}if(t>=b){from=k;to=(k+1)%n;u=(t-b)/(e-b);}break;}
 window.settled=from===to;const jobs=[];
 SCENES.forEach((s,i)=>{
  const sec=document.getElementById('s'+i),on=i===from||i===to;sec.style.visibility=on?'visible':'hidden';if(!on)return;
  const tl=local(i,t),out=i===from&&from!==to,inn=i===to&&from!==to;
  // A short cut: the outgoing line and hero leave, then the next arrive.
  const q=out?ease(u/.5):inn?ease((u-.5)/.5):1;
  sec.querySelector('.ink').style.transform='translateY('+(out?-110*q:inn?110*(1-q):0)+'%)';
  sec.querySelector('.note').style.opacity=out?1-q:inn?q:1;
  // The push grows from 98.5 % so the hero never leaves the safe area.
  const hero=sec.querySelector('.hero');hero.style.opacity=out?1-ease(u/.5):inn?ease((u-.4)/.6):1;
  hero.style.transform='scale('+(.985+.02*ease(clamp(tl/(BEAT+2*HALF))))+')';
  sec.style.zIndex=inn?2:1;
  // Marked cells uncover left to right, one after another, in reading order.
  if(s.reveal)sec.querySelectorAll('.mask').forEach(m=>{const q2=+m.dataset.q,p=ease((tl-s.reveal.start-q2*s.reveal.step)/.2),[x,,w]=REVEAL[i][q2];m.style.left=(RTL?x:x+w*p)+'px';m.style.width=(w*(1-p))+'px';});
  sec.querySelectorAll('video').forEach(v=>jobs.push(seek(v,tl)));
 });
 const g=(1-Math.cos(t*Math.PI/12))/2;document.querySelector('.glow').style.transform='translate('+(-70*g)+'px,'+(-30*g)+'px)';
 await Promise.all(jobs);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 const audit=layoutAudit();if(audit.issues.length)throw Error(JSON.stringify({time:t,issues:audit.issues}));window.validatedFrames=(window.validatedFrames||0)+1;
};
const BEAT=${BEAT};
window.layoutAudit=()=>{
 const issues=[];let minHeadline=Infinity;
 const inside=(name,b)=>{if(b.left<SAFE.x-.5||b.top<SAFE.y-.5||b.right>SAFE.x+SAFE.width+.5||b.bottom>SAFE.y+SAFE.height+.5)issues.push({issue:'outside Apple search safe area',name,box:[b.left,b.top,b.right,b.bottom].map(Math.round)});};
 for(const sec of document.querySelectorAll('.scene'))if(sec.style.visibility==='visible'){
  const key=sec.querySelector('.key').getBoundingClientRect();inside('hero '+sec.id,key);
  const e=sec.querySelector('.ink'),line=e.parentElement.getBoundingClientRect(),r=document.createRange();r.selectNodeContents(e);const b=r.getBoundingClientRect();
  if(b.width>line.width+1)issues.push({issue:'text clipped',text:e.textContent});
  const v={left:Math.max(b.left,line.left),right:Math.min(b.right,line.right),top:Math.max(b.top,line.top),bottom:Math.min(b.bottom,line.bottom)};
  if(v.bottom>v.top){inside(e.textContent,v);
   if(window.settled)for(const p of [key,...[...sec.querySelectorAll('.piece')].map(x=>x.getBoundingClientRect())])if(v.right>p.left-12&&v.left<p.right+12&&v.bottom>p.top-12&&v.top<p.bottom+12){issues.push({issue:'copy overlaps hero',text:e.textContent});break;}
   minHeadline=Math.min(minHeadline,parseFloat(getComputedStyle(e.closest('h1')).fontSize));}
 }
 if(minHeadline<56)issues.push({issue:'headline too small',minHeadline});
 return{safeArea:SAFE,minHeadline,issues};
};
</script>`;
}

const STILLS=[0,1,2.5,2.95,3.05,4.5,7.5,10.5,13.5,16.5,19.5,22.5,23.8];
const manifestPath=join(out,'video-manifest.json'),itemsDir=join(out,'manifest-items');
let items;
const r=await renderer();
try{for(const lang of languages){
 const scenes=SCENES.map(x=>placed(x,lang)),sources=await prepare(lang,scenes),name=`${lang}-search-video-3.2.2`,htmlPath=join(out,name+'.html'),file=join(out,name+'.mp4');
 writeFileSync(htmlPath,html(lang,sources,scenes));await r.load(htmlPath,W,H);
 await r.evaluate(`window.layoutReady.then(()=>Promise.all([...document.querySelectorAll('video')].map(v=>v.readyState>=2?0:new Promise((ok,no)=>{v.addEventListener('loadeddata',ok,{once:true});v.addEventListener('error',()=>no(Error('decode failed: '+v.src)),{once:true});}))))`);
 const fits=await r.evaluate('window.shrink'),size=Math.min(...fits),floor=['zh-CN','zh-TW','ja','ko'].includes(lang)?FLOOR.cjk:FLOOR.latin;
 const flagged=fits.map((v,i)=>({scene:SCENES[i].key,fitsAt:v})).filter(x=>x.fitsAt<floor);
 console.log(`${lang}: headlines at ${size}px (longest: ${SCENES[fits.indexOf(size)].key})`);
 if(flagged.length)console.warn(`${lang}: below the ${floor}px floor in ${flagged.map(x=>`${x.scene} (${x.fitsAt}px)`).join(', ')}; write a shorter line`);
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
  validatedFrames:await r.evaluate('window.validatedFrames'),headlineSize:size,headlineFits:Object.fromEntries(fits.map((v,i)=>[SCENES[i].key,v])),shrinkFlagged:flagged,safeArea:SAFE,template:TEMPLATE,
  stillAudits:audits.map(a=>({time:a.time,minHeadline:a.minHeadline,issues:a.issues})),sources,status:'local-not-uploaded'};
 // Parallel workers each own one entry file; the manifest is rebuilt from all
 // of them, so no worker can overwrite another's entry.
 mkdirSync(itemsDir,{recursive:true});writeFileSync(join(itemsDir,lang+'.json'),JSON.stringify(item,null,2)+'\n');
 items=readdirSync(itemsDir).filter(f=>f.endsWith('.json')).sort().map(f=>JSON.parse(readFileSync(join(itemsDir,f),'utf8')));
 writeFileSync(manifestPath,JSON.stringify({createdAt:new Date().toISOString(),uploaded:false,items},null,2)+'\n');console.log('Completed '+name);
}}finally{await r.close();}

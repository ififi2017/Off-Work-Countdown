// 3.2.2 App Store search-results video: 1920×1280, 24 s, 30 fps, silent loop.
//
//   IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/creative-search-3.2.2.mjs [--stills]
//
// Four beats of six seconds: countdown → widget → records → time off. Each
// beat is one line of copy and one native hero, shown at or below its
// capture resolution so nothing is upscaled. The hero and the headline sit
// inside the Art Safe Area of Apple's search-results template; the rest of
// the native surface the hero lives on (the timer screen, the wallpaper, the
// calendar) bleeds past it towards the frame edge, so the full 3:2 frame
// reads as full while any device crop keeps the message.
//
// Motion comes from the app: the countdown and widget tick live, recorded
// days fill in order, and the leave run lights up day by day. A slow push
// carries each beat. Every frame is audited: headline glyphs and hero must
// stay inside the safe area, nothing may be clipped, and settled frames may
// not overlap copy and hero. A violation stops the render.
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
const M=16,L=Math.ceil(SAFE.x+M),T=Math.ceil(SAFE.y+M),R=Math.floor(SAFE.x+SAFE.width-M),B=Math.floor(SAFE.y+SAFE.height-M);
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const run=(cmd,args)=>new Promise((resolve,reject)=>{const c=spawn(cmd,args,{stdio:'inherit'});c.on('error',reject);c.on('close',n=>n===0?resolve():reject(Error(cmd+': '+n)))});

// Native coordinates on the 1320×2868 capture. `key` is the part that must
// stay in the safe area; `show` is the surface drawn around it (bleed).
// Copy comes from the reviewed V4 tour lines: [countdown, widgets, records, leave].
const SCENES=[
 {key:'timer',copy:0,layout:'stack',video:true,inPoint:0.2,bg:'#f2f2f7',
  pieces:[{key:[0,372,1320,448],show:[0,372,1320,2496],radius:56}]},
 // The widget, centred, with its Home Screen wallpaper bleeding out sideways.
 {key:'widgets',copy:1,layout:'stack',align:'center',video:true,inPoint:0.2,bg:'#3a2a3f',
  pieces:[{key:[330,930,662,536],show:[140,930,1040,852],radius:66}]},
 // Month header, weekdays and the two weeks before this one: regular days,
 // overtime (Oct 6, 8), a day of leave (Oct 9) and weekend rest. Marked cells
 // are found in the capture (creative-marks.py) and fill in reading order.
 {key:'records',copy:3,layout:'stack',bg:'#ffffff',
  pieces:[{key:[53,725,1214,620],show:[53,725,1214,1000],radius:44}],
  reveal:{strips:[[1105,1155],[1290,1340]],start:1.2,step:.32}},
 // The plan's cost and result, then the two calendar rows the whole run
 // spans (Monday-first weeks), with its "9 days off in a row" label. The
 // run's days light up in order.
 {key:'leave',copy:5,layout:'stack',bg:'#ffffff',
  pieces:[{key:[53,515,1214,165],show:[53,500,1214,190],radius:44},{key:[53,1020,1214,375],show:[53,1020,1214,770],radius:44,gap:36}],
  reveal:{strips:[[1140,1192],[1290,1390]],start:1.2,step:.26}},
];
const CENTERS=[6,12,18,23.5],HALF=0.5;
const languages=(process.env.IOS_SHOTS_LANGUAGE||'en,zh-CN').split(',');
const NOTE={'zh-CN':'界面为演示数据',en:'Illustrative data'};
// Headlines that replace a reviewed V4 line for this video only. The V4 English
// countdown line was too long to set near the Chinese size on one line.
const LINES={en:{0:['Know when','you’re done.']}};
// A headline that has to shrink below this share of full size is flagged in
// the manifest and the log, so long translations are caught before review.
const SHRINK_FLAG=.85;

async function prepare(lang){
 const sources=[];
 for(const s of SCENES){
  const png=join(raw,`${lang}-${s.key}.png`),mov=join(raw,`${lang}-${s.key}.mov`);
  const entry={scene:s.key,capture:`${lang}-${s.key}.png`,captureSHA256:sha(png)};
  if(s.video){
   // Full-frame clip at capture resolution, long enough for the beat and both
   // transitions, so the digits keep ticking the whole time it is on screen.
   const nativeDuration=Number(execFileSync('ffprobe',['-v','error','-show_entries','format=duration','-of','csv=p=0',mov],{encoding:'utf8'}));
   if(nativeDuration<s.inPoint+7.2)throw Error(`${mov} is ${nativeDuration}s; the beat needs 7.4s of live footage`);
   const clip=join(out,`${lang}-${s.key}-clip.mp4`),recipe=JSON.stringify({sha:sha(mov),inPoint:s.inPoint,v:2});
   if(!existsSync(clip)||!existsSync(clip+'.json')||readFileSync(clip+'.json','utf8')!==recipe){
    await run('ffmpeg',['-y','-loglevel','error','-i',mov,'-ss',String(s.inPoint),'-t','7.2','-an','-vf',`fps=${FPS},setsar=1`,'-c:v','libx264','-preset','slow','-crf','10','-pix_fmt','yuv420p',clip]);
    writeFileSync(clip+'.json',recipe);
   }
   Object.assign(entry,{recording:`${lang}-${s.key}.mov`,recordingSHA256:sha(mov),inPoint:s.inPoint,nativeDuration});
  }
  if(s.reveal)entry.reveal=JSON.parse(execFileSync('python3',[join(dir,'creative-marks.py'),png,JSON.stringify({x:53,width:1214,strips:s.reveal.strips})],{encoding:'utf8'}));
  sources.push(entry);
 }
 return sources;
}

function html(lang,sources){
 const font=posterFonts(lang),c=COPY[lang].tour,tall=['ar','th','hi-IN','mr-IN'].includes(lang),cjk=['zh-CN','zh-TW','ja','ko'].includes(lang);
 const scenes=SCENES.map((s,i)=>{
  const [a,b]=LINES[lang]?.[i]??(c[s.copy].lines.length>2?[c[s.copy].lines.slice(0,-1).join(' '),c[s.copy].lines.at(-1)]:c[s.copy].lines);
  const ink=s.layout==='stack'?`<div class="line"><div class="ink">${a} <span class="accent">${b}</span></div></div>`
   :`<div class="line"><div class="ink">${a}</div></div><div class="line"><div class="ink accent">${b}</div></div>`;
  const src=s.video?`<video muted playsinline preload="auto" src="${pathToFileURL(join(out,`${lang}-${s.key}-clip.mp4`)).href}"></video>`:`<img src="${pathToFileURL(join(raw,`${lang}-${s.key}.png`)).href}">`;
  const pieces=s.pieces.map((p,j)=>`<div class="piece" style="background:${s.bg}"><div class="native">${src}${(sources[i].reveal||[]).map((r,q)=>r[1]>=p.show[1]&&r[1]<p.show[1]+p.show[3]?`<i class="mask" data-q="${q}" style="left:${r[0]}px;top:${r[1]}px;width:${r[2]}px;height:${r[3]}px"></i>`:'').join('')}</div></div>`).join('');
  return `<section id="s${i}" class="scene ${s.layout}"><h1>${ink}</h1><div class="hero">${pieces}<div class="key"></div></div></section>`;
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
.native{position:absolute;left:0;top:0;width:1320px;height:2868px;transform-origin:0 0}
.native img,.native video{position:absolute;inset:0;width:100%;height:100%}
.mask{position:absolute;background:#fff}
.key{position:absolute;pointer-events:none}
.note{position:absolute;right:28px;bottom:22px;font-size:15px;color:#a39686;letter-spacing:.2px}
</style><div class="glow"></div>${scenes}<div class="note">${NOTE[lang]??COPY[lang].note}</div><script>
const REVEAL=${JSON.stringify(sources.map(x=>x.reveal||[]))},SAFE=${JSON.stringify(SAFE)},AREA=${JSON.stringify({L,T,R,B})},SCENES=${JSON.stringify(SCENES)},CENTERS=${JSON.stringify(CENTERS)},HALF=${HALF},MAX=${JSON.stringify({stack:cjk?104:88,side:cjk?100:84})};
const clamp=x=>Math.max(0,Math.min(1,x)),ease=x=>{x=clamp(x);return x*x*x*(x*(x*6-15)+10)};
function fit(h1,width,max){let n=max;h1.style.fontSize=n+'px';const lines=[...h1.querySelectorAll('.ink')];while(lines.some(e=>e.getBoundingClientRect().width>width)&&n>30){n-=1;h1.style.fontSize=n+'px';}return n;}
// Lay out once: headline at the top of the safe area (stack) or left of the
// hero (side); hero scaled to the room left, never above native resolution.
window.shrink=[];window.layoutReady=document.fonts.ready.then(()=>{
 const G=28;
 SCENES.forEach((s,i)=>{
  const sec=document.getElementById('s'+i),h1=sec.querySelector('h1'),hero=sec.querySelector('.hero');sec.style.visibility='visible';
  let oy=0;const rects=s.pieces.map(p=>{oy+=(p.gap||0);const r={y:oy};oy+=p.key[3];return r;});
  const kx0=Math.min(...s.pieces.map(p=>p.key[0])),kw=Math.max(...s.pieces.map(p=>p.key[0]+p.key[2]))-kx0,kh=oy;
  let scale,left,top;
  if(s.layout==='stack'){
   window.shrink[i]=fit(h1,AREA.R-AREA.L,MAX.stack)/MAX.stack;Object.assign(h1.style,{left:AREA.L+'px',top:AREA.T+'px'});
   top=Math.ceil(h1.getBoundingClientRect().bottom+G);
   scale=Math.min(1,(AREA.R-AREA.L)/kw,(AREA.B-top)/kh);left=s.align==='center'?(AREA.L+AREA.R-kw*scale)/2:AREA.L;
  }else{
   scale=Math.min(1,(AREA.B-AREA.T)/kh);left=AREA.R-kw*scale;top=AREA.T;
   window.shrink[i]=fit(h1,left-G*2-AREA.L,MAX.side)/MAX.side;const hh=h1.getBoundingClientRect().height;Object.assign(h1.style,{left:AREA.L+'px',top:Math.round((AREA.T+AREA.B-hh)/2)+'px'});
  }
  Object.assign(hero.style,{left:left+'px',top:top+'px',width:kw*scale+'px',height:kh*scale+'px'});
  Object.assign(hero.querySelector('.key').style,{left:0,top:0,width:kw*scale+'px',height:kh*scale+'px'});
  // Each piece shows its surface around the key; the native layer is offset so
  // key pixels land exactly on the key rectangle.
  s.pieces.forEach((p,j)=>{
   const el=hero.querySelectorAll('.piece')[j],[sx,sy,sw,sh]=p.show;
   Object.assign(el.style,{left:(sx-kx0)*scale+'px',top:(rects[j].y+(sy-p.key[1]))*scale+'px',width:sw*scale+'px',height:sh*scale+'px',borderRadius:p.radius*scale+'px'});
   const n=el.querySelector('.native');n.style.transform='scale('+scale+') translate('+(-sx)+'px,'+(-sy)+'px)';
  });
  sec.style.visibility='';
 });
});
async function seek(v,t){t=Math.min(t,Math.max(0,v.duration-.04));if(Math.abs(v.currentTime-t)<.0001)return;await new Promise((ok,no)=>{const timer=setTimeout(()=>no(Error('seek timeout')),5000);v.addEventListener('seeked',()=>{clearTimeout(timer);ok()},{once:true});v.currentTime=t})}
// Local time of scene i from the start of its entrance. The countdown wraps
// across the loop point so its digits keep ticking from 23.99 s into 0 s.
const local=(i,t)=>i===0?(t>=CENTERS[3]-HALF?t-(CENTERS[3]-HALF):t+2*HALF):t-(CENTERS[i-1]-HALF);
window.render=async t=>{
 t=((t%${DURATION})+${DURATION})%${DURATION};
 let from=0,to=0,u=0;
 for(let k=0;k<4;k++){const b=CENTERS[k]-HALF,e=CENTERS[k]+HALF;if(t>=e){from=to=(k+1)%4;continue;}if(t>=b){from=k;to=(k+1)%4;u=(t-b)/(e-b);}break;}
 window.settled=from===to;const jobs=[];
 SCENES.forEach((s,i)=>{
  const sec=document.getElementById('s'+i),on=i===from||i===to;sec.style.visibility=on?'visible':'hidden';if(!on)return;
  const tl=local(i,t),out=i===from&&from!==to,inn=i===to&&from!==to;
  // Copy: the outgoing line leaves before the incoming one arrives.
  const q=out?ease(u/.45):inn?ease((u-.5)/.45):1;
  sec.querySelectorAll('.ink').forEach(e=>{e.style.transform='translateY('+(out?-110*q:inn?110*(1-q):0)+'%)';});
  // Hero: fades out, then the next fades in (no ghosted digits), then a slow
  // push. It grows from 98.5 % so it never leaves the safe area while moving.
  const hero=sec.querySelector('.hero'),o=out?1-ease(u/.5):inn?ease((u-.4)/.6):1,push=.985+.035*ease(clamp(tl/7));
  hero.style.opacity=o;hero.style.transform='scale('+push+')';
  sec.style.zIndex=inn?2:1;
  // Marked cells uncover left to right, one after another, in reading order.
  if(s.reveal)sec.querySelectorAll('.mask').forEach(m=>{const q=+m.dataset.q,p=ease((tl-s.reveal.start-q*s.reveal.step)/.24),[x,,w]=REVEAL[i][q];m.style.left=(x+w*p)+'px';m.style.width=(w*(1-p))+'px';});
  sec.querySelectorAll('video').forEach(v=>jobs.push(seek(v,tl)));
 });
 const g=(1-Math.cos(t*Math.PI/12))/2;document.querySelector('.glow').style.transform='translate('+(-70*g)+'px,'+(-30*g)+'px)';
 await Promise.all(jobs);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 const audit=layoutAudit();if(audit.issues.length)throw Error(JSON.stringify({time:t,issues:audit.issues}));window.validatedFrames=(window.validatedFrames||0)+1;
};
window.layoutAudit=()=>{
 const issues=[];let minHeadline=Infinity;
 const inside=(name,b)=>{if(b.left<SAFE.x-.5||b.top<SAFE.y-.5||b.right>SAFE.x+SAFE.width+.5||b.bottom>SAFE.y+SAFE.height+.5)issues.push({issue:'outside Apple search safe area',name,box:[b.left,b.top,b.right,b.bottom].map(Math.round)});};
 for(const sec of document.querySelectorAll('.scene'))if(sec.style.visibility==='visible'){
  const key=sec.querySelector('.key').getBoundingClientRect();inside('hero '+sec.id,key);
  for(const e of sec.querySelectorAll('.ink')){
   const line=e.parentElement.getBoundingClientRect(),r=document.createRange();r.selectNodeContents(e);const b=r.getBoundingClientRect();
   if(b.width>line.width+1)issues.push({issue:'text clipped',text:e.textContent});
   const v={left:Math.max(b.left,line.left),right:Math.min(b.right,line.right),top:Math.max(b.top,line.top),bottom:Math.min(b.bottom,line.bottom)};
   if(v.bottom<=v.top)continue;inside(e.textContent,v);
   if(window.settled)for(const p of [key,...[...sec.querySelectorAll('.piece')].map(x=>x.getBoundingClientRect())])if(v.right>p.left-12&&v.left<p.right+12&&v.bottom>p.top-12&&v.top<p.bottom+12){issues.push({issue:'copy overlaps hero',text:e.textContent});break;}
   minHeadline=Math.min(minHeadline,parseFloat(getComputedStyle(e.closest('h1')).fontSize));
  }
 }
 if(minHeadline<56)issues.push({issue:'headline too small',minHeadline});
 return{safeArea:SAFE,minHeadline,issues};
};
</script>`;
}

const STILLS=[0,1.5,3,4.5,5.75,6,6.25,8,10,12,14,16,18,20,22,23.5,23.9];
const manifestPath=join(out,'video-manifest.json');
let items=existsSync(manifestPath)?JSON.parse(readFileSync(manifestPath,'utf8')).items:[];
const r=await renderer();
try{for(const lang of languages){
 const sources=await prepare(lang),name=`${lang}-search-video-3.2.2`,htmlPath=join(out,name+'.html'),file=join(out,name+'.mp4');
 writeFileSync(htmlPath,html(lang,sources));await r.load(htmlPath,W,H);
 await r.evaluate(`window.layoutReady.then(()=>Promise.all([...document.querySelectorAll('video')].map(v=>v.readyState>=2?0:new Promise((ok,no)=>{v.addEventListener('loadeddata',ok,{once:true});v.addEventListener('error',()=>no(Error('decode failed: '+v.src)),{once:true});}))))`);
 const shrink=await r.evaluate('window.shrink'),flagged=shrink.map((v,i)=>({scene:SCENES[i].key,headlineScale:+v.toFixed(3)})).filter(x=>x.headlineScale<SHRINK_FLAG);
 if(flagged.length)console.warn(`${lang}: headline shrinks below ${SHRINK_FLAG*100}% in ${flagged.map(x=>`${x.scene} (${Math.round(x.headlineScale*100)}%)`).join(', ')}; consider a shorter line`);
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
  validatedFrames:await r.evaluate('window.validatedFrames'),headlineScale:shrink.map(v=>+v.toFixed(3)),shrinkFlagged:flagged,safeArea:SAFE,template:TEMPLATE,stillAudits:audits.map(a=>({time:a.time,minHeadline:a.minHeadline,issues:a.issues})),sources,status:'local-not-uploaded'};
 items=items.filter(x=>x.locale!==lang);items.push(item);
 writeFileSync(manifestPath,JSON.stringify({createdAt:new Date().toISOString(),uploaded:false,items},null,2)+'\n');console.log('Completed '+name);
}}finally{await r.close();}

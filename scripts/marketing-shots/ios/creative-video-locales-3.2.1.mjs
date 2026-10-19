// Six-feature search creative. Render existing native recordings; never boots a simulator.
// node scripts/marketing-shots/ios/creative-video-locales-3.2.1.mjs [--stills]
// IOS_SHOTS_VIDEO_KINDS=header skips all native search clip preparation.
import {spawn,execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,rmSync,existsSync,renameSync} from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {COPY} from './creative-copy-3.2.1.mjs';
import {renderer} from './creative-renderer-3.2.1.mjs';
import {brandMark,escapeHTML} from '../brand.mjs';
import {posterFonts,assertPosterFonts} from './creative-fonts.mjs';
import {safeHeader,HEADER_TEMPLATE} from './creative-header-safe-3.2.1.mjs';
import {safeSearch,SEARCH_TEMPLATE} from './creative-search-safe-3.2.1.mjs';
// IOS_CREATIVE_OUT renders into another folder (3.2.3 re-renders the header
// with refreshed poster fonts without touching the 3.2.1 originals).
const dir=fileURLToPath(new URL('.',import.meta.url)),out=process.env.IOS_CREATIVE_OUT?join(dir,process.env.IOS_CREATIVE_OUT):join(dir,'out/creative-3.2.1/all-locales'),raw=join(dir,'raw/3.2.1/all-locales');
const uri=p=>pathToFileURL(p).href,sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const run=(cmd,args)=>new Promise((resolve,reject)=>{const c=spawn(cmd,args,{stdio:'inherit'});c.on('error',reject);c.on('close',n=>n===0?resolve():reject(Error(cmd+': '+n)))});
const keys=['timer','widgets','focus','records','report','leave'];
const languages=(process.env.IOS_SHOTS_LANGUAGE||Object.keys(COPY).join(',')).split(',');
const kinds=(process.env.IOS_SHOTS_VIDEO_KINDS||'header,search').split(',');
if(kinds.some(k=>!['header','search'].includes(k)))throw Error('Unknown video kind');
const copy=Object.fromEntries(languages.map(lang=>[lang,COPY[lang].tour.map((p,i)=>{const lines=p.lines.length>2?[p.lines.slice(0,-1).join(' '),p.lines.at(-1)]:p.lines;return[p.label,lines[0],lines[1]||'',p.sub.join(' '),(i===2||i===4?'DoneAt Plus · ':i===5?COPY[lang].trials+' · ':'')+COPY[lang].note]})]));
const sources={};mkdirSync(out,{recursive:true});
for(const locale of kinds.includes('search')?Object.keys(copy):[]){
 sources[locale]=[];
 for(const key of keys){
  let inPoint=key==='report'?7.5:0.2;
  const source=join(raw,`${locale}-iphone-${key}.mov`);
  const nativeDuration=Number(JSON.parse(execFileSync('ffprobe',['-v','error','-show_entries','format=duration','-of','json',source],{encoding:'utf8'})).format.duration);if(nativeDuration<inPoint+.1)inPoint=0;
  // The opening is a precise crop of the live native countdown, not a recreated UI.
  // Widget scene crops the native onboarding Home Screen preview only.
  const crop=key==='timer'?[0,390,1320,450]:key==='widgets'?(()=>{const c=JSON.parse(execFileSync('python3',[join(dir,'creative-widget-crop.py'),join(raw,`${locale}-iphone-widgets.png`)],{encoding:'utf8'}));return[c.x,c.y,c.w,c.h]})():null;
  const filter='tpad=stop_mode=clone:stop_duration=5,'+(crop?`crop=${crop[2]}:${crop[3]}:${crop[0]}:${crop[1]},fps=30,scale=${key==='timer'?'1320:450':'840:768'},setsar=1`:'fps=30,scale=660:1434,setsar=1');
  const prepared=join(out,`${locale}-tour-${key}-source.mp4`),cache=prepared+'.json',sourceSHA=sha(source);
  const recipe={sourceSHA,inPoint,filter,duration:4.8,seekMode:'output-after-fps'};
  if(!existsSync(prepared)||!existsSync(cache)||readFileSync(cache,'utf8')!==JSON.stringify(recipe)){
   // simctl emits frames only when the surface changes. Resample before seeking
   // so a sparse native recording still contains the requested interval.
   await run('ffmpeg',['-y','-loglevel','error','-i',source,'-ss',String(inPoint),'-t','4.8','-an','-vf',filter,'-c:v','libx264','-threads','2','-preset','fast','-crf','17','-pix_fmt','yuv420p','-movflags','+faststart',prepared]);
   const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-select_streams','v:0','-show_entries','stream=width,height,duration','-of','json',prepared],{encoding:'utf8'}));
   if(!probe.streams?.[0]||Number(probe.streams[0].duration)<4.7)throw Error(`Prepared native clip is empty or too short: ${prepared}`);
   writeFileSync(cache,JSON.stringify(recipe));
  }
  sources[locale].push({scene:key,file:source.split('/').at(-1),sha256:sourceSHA,inPoint,crop,nativeDuration});
 }
}
function tour(locale){
 const font=posterFonts(locale),c=copy[locale];
 const line=(text,cls='')=>`<div class="line ${cls}"><div class="ink">${text}</div></div>`;
 const scenes=keys.map((key,i)=>`<section id="s${i}" class="scene ${key}"><div class="copy">${line(c[i][0],'label')}<h1>${line(c[i][1])}${line(c[i][2],'accent')}</h1>${line(c[i][3],'sub')}${line(c[i][4],'note')}</div></section>`).join('');
 const media=keys.map((key,i)=>`<video id="v${i}" muted playsinline preload="auto" src="${uri(join(out,`${locale}-tour-${key}-source.mp4`))}"></video>`).join('');
 return `<!doctype html><meta charset="utf-8"><style>${font.css}
 *{box-sizing:border-box}html,body{margin:0;width:1920px;height:1280px;overflow:hidden}body{background:#fcf7ef;color:#25231f;font-family:${font.sans};font-synthesis:none}.glow{position:absolute;width:1400px;height:1400px;left:800px;top:320px;background:radial-gradient(ellipse,#ffbf8055,transparent 65%);pointer-events:none}.wordmark{position:absolute;left:140px;top:115px;font-size:58px;font-weight:750;letter-spacing:-2px;z-index:10}.scene{position:absolute;inset:0;visibility:hidden;perspective:1800px}.copy{position:absolute;left:140px;top:370px;width:1040px}.label{color:#776e63;font-size:34px;font-weight:600;letter-spacing:${['ar','th','hi-IN','mr-IN'].includes(locale)?0:1}px}h1{margin:30px 0;font-family:${font.serif};font-size:${['zh-CN','zh-TW','ja'].includes(locale)?122:100}px;line-height:${['ar','th','hi-IN','mr-IN'].includes(locale)?1.7:1.24};letter-spacing:${['ar','th','hi-IN','mr-IN'].includes(locale)?0:-2}px}h1 span{display:block;white-space:nowrap}.accent{color:#f45a1e}p{font-size:31px;color:#776e63;margin:38px 0 24px;max-width:930px}small{font-size:24px;color:#8b8074}.visual{position:absolute;left:1230px;top:90px;width:555px;filter:drop-shadow(0 26px 34px #30202c24);transform-origin:50% 65%}.visual>img{position:relative;display:block;width:100%}.screen{position:absolute;top:2.2%;left:5.102041%;width:89.795918%;height:95.6%;border-radius:14.4% / 6.62%;overflow:hidden}.screen video{width:100%;height:100%;display:block;object-fit:contain}
 .timer .copy{top:255px;width:1700px;text-align:center;left:110px}.timer h1{margin:18px 0 20px;font-size:${['zh-CN','zh-TW','ja'].includes(locale)?122:102}px}.timer h1 span{display:inline}.timer h1 span+span{margin-left:26px}.timer p{margin:18px auto}.timer small{display:none}.timer .visual{top:660px;left:180px;width:1560px;height:532px;background:#f1f0f6;border-radius:58px;overflow:hidden;filter:drop-shadow(0 26px 35px #30202c18)}.timer .screen,.widgets .screen{position:relative;inset:auto;width:100%;height:100%;border-radius:0}
 .widgets .visual{left:1090px;top:280px;width:710px;height:650px;border-radius:66px;overflow:hidden}.widgets .copy{width:850px}.widgets p{max-width:800px}
 .line{overflow:hidden;white-space:nowrap;word-break:keep-all;hyphens:none}.copy{direction:${locale==='ar'?'rtl':'ltr'}}.ink{will-change:transform}.sub{font-size:31px;color:#776e63;margin:38px 0 24px}.note{font-size:24px;color:#8b8074}.timer .sub{margin:18px auto}.timer .note{display:none}.timer h1{display:flex;justify-content:center;gap:26px}.timer h1 .line{display:block;min-width:0;flex:1;max-width:calc((100% - 26px)/2)}.timer h1 .line+.line{margin-left:0}
 .stage{position:absolute;filter:drop-shadow(0 26px 34px #30202c24)}.surface{position:absolute;overflow:hidden;background:#f1f0f6}.surface video{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;background:#f1f0f6;visibility:hidden}.frame{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;pointer-events:none}
 .rail{position:absolute;left:140px;bottom:76px;display:flex;gap:15px;z-index:10}.rail i{display:block;width:34px;height:8px;border-radius:12px;background:#30202c20}
 </style><div class="glow"></div><div class="wordmark">DoneAt</div>${scenes}<div class="stage"><div class="surface">${media}</div><img class="frame" src="${uri(join(dir,'frames/iPhone 18 Pro Max - Silver - Portrait.png'))}"></div><div class="rail">${keys.map(()=>'<i></i>').join('')}</div><script>
 window.layoutReady=document.fonts.ready.then(()=>{for(const e of document.querySelectorAll('.ink')){let n=parseFloat(getComputedStyle(e).fontSize);const range=document.createRange();range.selectNodeContents(e);while(range.getBoundingClientRect().width>e.parentElement.getBoundingClientRect().width-1&&n>18){n-=.5;e.style.fontSize=n+'px';}}for(const h of document.querySelectorAll('h1')){const es=[...h.querySelectorAll('.ink')],n=Math.min(...es.map(e=>parseFloat(getComputedStyle(e).fontSize)));for(const e of es)e.style.fontSize=n+'px';}});
 const clamp=x=>Math.max(0,Math.min(1,x));
 // Quintic smoothstep has zero velocity and acceleration at both endpoints.
 const ease=x=>{x=clamp(x);return x*x*x*(x*(x*6-15)+10)};
 const lerp=(a,b,p)=>a+(b-a)*p;
 const boxes=[[180,660,1560,532,58,0],[1090,280,710,650,66,0],...[2,3,4,5].map(()=>[1230,90,555,555*3000/1470,80,1])];
 const transitions=[4,8,12,16,20,23.45];
 async function seek(v,t){t=Math.min(t,Math.max(0,v.duration-.04));if(Math.abs(v.currentTime-t)<.0001)return;await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('seek timeout')),5000);v.addEventListener('seeked',()=>{clearTimeout(timer);resolve()},{once:true});v.currentTime=t})}
 window.render=async t=>{
  t=t%24;let from=0,to=0,u=0;
  for(let k=0;k<6;k++){
   const begin=transitions[k]-.5,end=transitions[k]+.5;
   if(t>=end){from=(k+1)%6;to=from;u=0;continue;}
   if(t>=begin){from=k;to=(k+1)%6;u=(t-begin)/(end-begin);}break;
  }
  const p=ease(u),active=from!==to,weights=Array(6).fill(0);weights[from]=1-p;weights[to]+=p;
  const a=boxes[from],b=boxes[to],box=a.map((v,i)=>lerp(v,b[i],p));
  const stage=document.querySelector('.stage'),surface=document.querySelector('.surface'),frame=document.querySelector('.frame');
  Object.assign(stage.style,{left:box[0]+'px',top:box[1]+'px',width:box[2]+'px',height:box[3]+'px'});
  const phone=box[5],sx=box[2]*.05102041*phone,sy=box[3]*.022*phone;
  Object.assign(surface.style,{left:sx+'px',right:sx+'px',top:sy+'px',bottom:box[3]*.022*phone+'px',borderRadius:lerp(box[4],box[2]*.129,phone)+'px'});
  // The frame is one persistent element: subsequent page changes never move it.
  frame.style.opacity=from>=2&&to>=2?1:ease((phone-.7)/.3);
  const jobs=[];
  for(let i=0;i<6;i++){
   const visible=i===from||i===to,s=document.querySelector('#s'+i),v=document.querySelector('#v'+i);
   s.style.visibility=visible?'visible':'hidden';v.style.visibility=visible?'visible':'hidden';if(!visible)continue;
   s.querySelectorAll('.ink').forEach((node,n)=>{
    const q=active?ease((u-n*.025)/.88):0;
    node.style.transform='translateY('+(active?(i===from?-100*q:100*(1-q)):0)+'%)';
   });
   // A directional reveal over opaque media avoids ghosted digits and empty frames.
   v.style.zIndex=active&&i===to?2:1;v.style.opacity=1;v.style.clipPath=active&&i===to?'inset('+(100*(1-ease((u-.16)/.68)))+'% 0 0 0)':'none';
   v.style.transform=from>=2&&to>=2&&active?'translateY('+(i===to?24*(1-p):-24*p)+'px)':'none';
   const start=i===0?0:transitions[i-1]-.5;
   const clipTime=i===0&&t>22?0:Math.min(4.7,Math.max(0,t-start));jobs.push(seek(v,clipTime));
  }
  document.querySelectorAll('.rail i').forEach((n,i)=>{n.style.width=(34+34*weights[i])+'px';n.style.background='color-mix(in srgb,#f45a1e '+(weights[i]*100)+'%,#30202c20)';});
  const glow=(1-Math.cos(t*Math.PI/12))/2;document.querySelector('.glow').style.transform='translate('+(-120*glow)+'px,'+(-60*glow)+'px) scale('+(1+.1*glow)+')';
  await Promise.all(jobs);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 };</script>`;
}

const r=await renderer(),manifestPath=join(out,'video-manifest.json');let items=existsSync(manifestPath)?JSON.parse(readFileSync(manifestPath,'utf8')).items:[];
try{for(const locale of languages)for(const kind of kinds){
 const width=kind==='header'?3840:1920,height=kind==='header'?1646:1280,duration=kind==='header'?8:24,revision=kind==='header'?4:5,name=`${locale}-${kind}-video-v${revision}`,htmlPath=join(out,name+'.html'),file=join(out,name+'.mp4');
 const html=kind==='header'?safeHeader(locale):safeSearch(tour(locale),locale),recipeSHA=createHash('sha256').update('layout-audit-v1'+html+JSON.stringify(kind==='search'?sources[locale]:[])).digest('hex');
 if(items.some(x=>x.locale===locale&&x.kind===kind&&x.recipeSHA===recipeSHA&&existsSync(file)&&x.sha256===sha(file)))continue;
 writeFileSync(htmlPath,html);await r.load(htmlPath,width,height);await r.evaluate(`window.layoutReady.then(()=>Promise.all([...document.querySelectorAll('video')].map(v=>v.readyState>=2?Promise.resolve():new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Native media failed to load: '+v.src)),10000);v.addEventListener('loadeddata',()=>{clearTimeout(timer);resolve()},{once:true});v.addEventListener('error',()=>{clearTimeout(timer);reject(Error('Native media decode failed: '+v.src))},{once:true});}))))`);
 const fontsUsed=await assertPosterFonts(r,'.wordmark, h1 span, h1, .ink, .note, .label',name);
 const layoutAudits=[];

 for(const t of kind==='header'?[0,3.2,7.96]:[0,2,3.75,4.25,6,8.25,10,12.25,14,16.25,18,20.25,22,23.75]){await r.evaluate('render('+t+')');if(true){const audit=await r.evaluate('layoutAudit()');layoutAudits.push({time:t,...audit});if(audit.issues.length)throw Error(JSON.stringify({locale,kind,time:t,audit}));}writeFileSync(join(out,name+'-'+t.toFixed(2)+'.png'),await r.grab());}
 const auditPath=join(out,'header-safe-layout-audit.json');
 if(kind==='search'){const path=join(out,'search-safe-layout-audit.json'),audits=existsSync(path)?JSON.parse(readFileSync(path,'utf8')).items:[];writeFileSync(path,JSON.stringify({createdAt:new Date().toISOString(),template:SEARCH_TEMPLATE,items:[...audits.filter(x=>x.locale!==locale),{locale,layoutAudits}]},null,2)+'\n')}
 if(kind==='header'){const audits=existsSync(auditPath)?JSON.parse(readFileSync(auditPath,'utf8')).items:[];writeFileSync(auditPath,JSON.stringify({createdAt:new Date().toISOString(),template:HEADER_TEMPLATE,items:[...audits.filter(x=>x.locale!==locale),{locale,layoutAudits}]},null,2)+'\n')}
 if(process.argv.includes('--stills')){console.log('Checked '+name);continue;}
 const workingFile=file.replace(/\.mp4$/,'.encoding.mp4');
 const ff=spawn('ffmpeg',['-y','-loglevel','error','-f','image2pipe','-framerate','30','-c:v','mjpeg','-i','-','-vf','scale=in_range=full:out_range=limited,format=yuv420p','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-c:v','libx264','-threads','2','-preset','fast','-crf','18','-movflags','+faststart',workingFile],{stdio:['pipe','inherit','inherit']});const done=once(ff,'close');
 try{for(let f=0;f<duration*30;f++){for(let attempt=0;;attempt++){try{await r.evaluate('render('+(f/30)+')');break;}catch(e){if(attempt>=2||!String(e).includes('seek timeout'))throw e;}}if(!ff.stdin.write(await r.grab('jpeg')))await once(ff.stdin,'drain');if(f%90===0)console.log(name,f+'/'+duration*30);}ff.stdin.end();const[code]=await done;if(code!==0)throw Error('Encoder failed');renameSync(workingFile,file);}catch(e){ff.kill();throw e;}
 const item={locale,ascLocale:COPY[locale].asc,kind,fontsUsed,file:name+'.mp4',poster:name+'-0.00.png',width,height,fps:30,duration,recipeSHA,sha256:sha(file),revision,layoutAudits,sources:kind==='search'?sources[locale]:[],safeTemplate:kind==='header'?HEADER_TEMPLATE:SEARCH_TEMPLATE,validatedFrames:await r.evaluate('window.validatedFrames||0'),status:'proof-not-uploaded'};
 items=items.filter(x=>!(x.locale===locale&&x.kind===kind));items.push(item);writeFileSync(manifestPath,JSON.stringify({createdAt:new Date().toISOString(),uploaded:false,items},null,2)+'\n');console.log('Completed '+name);
}}finally{await r.close();}

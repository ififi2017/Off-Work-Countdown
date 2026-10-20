// Audit the 3.2.3 store media before review or upload.
//
//   node scripts/marketing-shots/ios/creative-audit-3.2.3.mjs
//
// creative-audit.mjs checks the 272-page 3.2.0 set; this checks what 3.2.3
// adds or re-renders (pages and header videos whose copy fell back to
// system fonts). Search videos: Apple's search-results spec (3:2, 1920×1280, 30 fps,
// 5–30 s, mp4), a single silent video stream, every frame decoded, the
// per-frame safe-area audit recorded by the renderer, and the file hash in
// the manifest. Screenshots: 1320×2868 opaque PNG (APP_IPHONE_67), an empty
// layout audit, and hashes for the page and every source still.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const dir=fileURLToPath(new URL('.',import.meta.url)),out=join(dir,'out/creative-3.2.3');
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const findings=[],checked=[];
const fail=(file,issue,detail)=>findings.push({file,issue,...(detail?{detail}:{})});

const videos=JSON.parse(readFileSync(join(out,'search/video-manifest.json'),'utf8')).items;
for(const v of videos){
 const file=join(out,'search',v.file);
 if(!existsSync(file)){fail(v.file,'missing');continue;}
 const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-count_frames','-show_entries','stream=codec_type,codec_name,width,height,r_frame_rate,nb_read_frames,pix_fmt:format=duration,format_name','-of','json',file],{encoding:'utf8'}));
 const s=probe.streams,video=s.find(x=>x.codec_type==='video'),duration=Number(probe.format.duration);
 if(s.length!==1||!video)fail(v.file,'expected one video stream and no audio',s.map(x=>x.codec_type));
 if(video.width!==1920||video.height!==1280)fail(v.file,'not 1920×1280',[video.width,video.height]);
 if(video.r_frame_rate!=='30/1')fail(v.file,'not 30 fps',video.r_frame_rate);
 if(duration<5||duration>30)fail(v.file,'outside 5–30 s',duration);
 if(Number(video.nb_read_frames)!==v.frames)fail(v.file,'decoded frame count differs',[video.nb_read_frames,v.frames]);
 if(video.pix_fmt!=='yuv420p'||video.codec_name!=='h264')fail(v.file,'not H.264 yuv420p',[video.codec_name,video.pix_fmt]);
 if(sha(file)!==v.sha256)fail(v.file,'hash differs from manifest');
 if(v.validatedFrames<v.frames)fail(v.file,'not every frame passed the layout audit',[v.validatedFrames,v.frames]);
 for(const a of v.stillAudits)if(a.issues.length)fail(v.file,'still audit issues at '+a.time,a.issues);
 checked.push({file:v.file,duration,frames:Number(video.nb_read_frames),headlineSize:v.headlineSize});
}

const shots=JSON.parse(readFileSync(join(out,'shots/screenshot-manifest.json'),'utf8')).items;
for(const p of shots){
 const file=join(out,'shots',p.file);
 if(!existsSync(file)){fail(p.file,'missing');continue;}
 const png=readFileSync(file);
 if(png.readUInt32BE(16)!==1320||png.readUInt32BE(20)!==2868)fail(p.file,'not 1320×2868');
 if(png[25]!==2)fail(p.file,'not opaque RGB (colour type '+png[25]+')');
 if(sha(file)!==p.sha256)fail(p.file,'hash differs from manifest');
 if(p.layoutAudit.issues.length)fail(p.file,'layout audit issues',p.layoutAudit.issues);
 for(const s of p.sources){const f=join(dir,s.file);if(!existsSync(f)||sha(f)!==s.sha256)fail(p.file,'source changed since render',s.file);}
 checked.push({file:p.file,order:p.order,display:p.display});
}

// Pages re-rendered with the refreshed poster fonts (3.2.1/3.2.2 layouts).
const SIZES={APP_IPHONE_67:[[1320,2868]],APP_IPHONE_DUO:[[1398,2034],[2007,2853],[2853,2007],[2034,1398]]};
const pagesFile=join(out,'pages/screenshot-manifest.json'),pages=existsSync(pagesFile)?JSON.parse(readFileSync(pagesFile,'utf8')).items:[];
for(const p of pages){
 const file=join(out,'pages',p.file);
 if(!existsSync(file)){fail(p.file,'missing');continue;}
 const png=readFileSync(file),size=[png.readUInt32BE(16),png.readUInt32BE(20)];
 if(!SIZES[p.display]?.some(([w,h])=>w===size[0]&&h===size[1]))fail(p.file,'size not accepted for '+p.display,size);
 if(png[25]!==2)fail(p.file,'not opaque RGB');
 if(sha(file)!==p.sha256)fail(p.file,'hash differs from manifest');
 if(p.layoutAudit.issues.length)fail(p.file,'layout audit issues',p.layoutAudit.issues);
 if(!p.fontsUsed?.length)fail(p.file,'no actual-font check recorded');
 checked.push({file:'pages/'+p.file,display:p.display});
}
// Header videos re-rendered with the refreshed poster fonts.
const headerFile=join(out,'header/video-manifest.json'),headers=existsSync(headerFile)?JSON.parse(readFileSync(headerFile,'utf8')).items:[];
for(const v of headers){
 const file=join(out,'header',v.file);
 if(!existsSync(file)){fail(v.file,'missing');continue;}
 const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-count_frames','-show_entries','stream=codec_type,width,height,r_frame_rate,nb_read_frames:format=duration','-of','json',file],{encoding:'utf8'}));
 const video=probe.streams.find(x=>x.codec_type==='video'),duration=Number(probe.format.duration);
 if(probe.streams.length!==1)fail(v.file,'expected one video stream and no audio');
 if(video.width!==3840||video.height!==1646||video.r_frame_rate!=='30/1')fail(v.file,'not 3840×1646 at 30 fps');
 if(duration<5||duration>30)fail(v.file,'outside 5–30 s',duration);
 if(sha(file)!==v.sha256)fail(v.file,'hash differs from manifest');
 if(!v.fontsUsed?.length)fail(v.file,'no actual-font check recorded');
 for(const a of v.layoutAudits)if(a.issues.length)fail(v.file,'safe-area audit issues at '+a.time,a.issues);
 checked.push({file:'header/'+v.file,frames:Number(video.nb_read_frames)});
}

const report={checkedAt:new Date().toISOString(),videos:videos.length,screenshots:shots.length,pages:pages.length,headers:headers.length,checked,findings};
writeFileSync(join(out,'audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({videos:videos.length,screenshots:shots.length,pages:pages.length,headers:headers.length,findings},null,1));
if(findings.length)process.exitCode=1;

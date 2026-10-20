// Home and Lock Screen captures for the 3.2.3 widget media.
//
//   node scripts/marketing-shots/ios/creative-capture-widgets-3.2.3.mjs <lang>-<name> [seconds]
//
// Captures whatever the iPhone simulator shows now: a still (<name>.png) and
// a clip (<name>.mov). The widgets themselves are arranged by hand first (see
// app-store-connect/ios/3.2.3/search-video.md). `simctl recordVideo` writes a
// frame only when the screen changes, and the Home Screen's widget timers do
// not count as a change, so the clip is a screenshot every quarter second,
// each held until the next one: the countdowns tick once a second, so this
// matches what the screen shows. Appends to raw/3.2.3/widgets/capture-manifest.json.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const dir=fileURLToPath(new URL('.',import.meta.url)),raw=join(dir,'raw/3.2.3/widgets');mkdirSync(raw,{recursive:true});
const id=process.env.IOS_SHOTS_SIMULATOR||'3C9FDCBC-0FA4-4E18-BFF4-2A8C36877966';
const [name,secondsArg]=process.argv.slice(2);if(!name)throw Error('usage: <lang>-<name> [seconds]');
const seconds=Number(secondsArg||8),FPS=30;
const run=(cmd,args)=>{const r=spawnSync(cmd,args,{encoding:'utf8'});if(r.status)throw Error(`${cmd} ${args.join(' ')}\n${r.stderr}`);return r.stdout;};
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');

const frames=join(raw,`.${name}-frames`);rmSync(frames,{recursive:true,force:true});mkdirSync(frames);
const shots=[],start=Date.now();
while(Date.now()-start<seconds*1000){
 const t=(Date.now()-start)/1000,file=join(frames,`${String(shots.length).padStart(4,'0')}.png`);
 run('xcrun',['simctl','io',id,'screenshot','--type=png',file]);shots.push({file,t});
 const wait=250-((Date.now()-start)%250);spawnSync('sleep',[String(wait/1000)]);
}
// Hold each screenshot until the next one, on a constant 30 fps clock.
const list=shots.map((s,i)=>`file '${s.file}'\nduration ${((shots[i+1]?.t??seconds)-s.t).toFixed(3)}`).join('\n')+`\nfile '${shots.at(-1).file}'\n`;
writeFileSync(join(frames,'list.txt'),list);
const mov=join(raw,name+'.mov'),png=join(raw,name+'.png');
run('ffmpeg',['-y','-loglevel','error','-f','concat','-safe','0','-i',join(frames,'list.txt'),'-vf',`fps=${FPS},format=yuv420p`,'-c:v','libx264','-crf','10','-preset','slow',mov]);
writeFileSync(png,readFileSync(shots[0].file));rmSync(frames,{recursive:true,force:true});

const log=join(raw,'capture-manifest.json');
const manifest=existsSync(log)?JSON.parse(readFileSync(log,'utf8')):{simulator:id,note:'Home/Lock Screen arranged by hand; see app-store-connect/ios/3.2.3/search-video.md',items:[]};
manifest.items=manifest.items.filter(x=>x.name!==name);
manifest.items.push({name,file:name+'.png',sha256:hash(png),video:{file:name+'.mov',sha256:hash(mov),seconds,screenshots:shots.length},capturedAt:new Date().toISOString()});
writeFileSync(log,JSON.stringify(manifest,null,2)+'\n');console.log(`captured ${name}: ${shots.length} screenshots over ${seconds}s`);

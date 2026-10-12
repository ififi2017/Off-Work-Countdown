// Native recordings for the 3.2.2 App Store search-results video.
// Four iPhone scenes per language: timer, widgets, records, leave. Records and
// Time off were redesigned in 3.2.2, so every scene is recaptured from one
// Debug build. Demo data is identical across languages: no holiday region,
// so no localized holiday names (or truncated ones) differ between videos.
//
//   IOS_SHOTS_APP=<Debug-iphonesimulator/App.app> IOS_SHOTS_LANGUAGE=en,zh-CN \
//     node scripts/marketing-shots/ios/creative-capture-search-3.2.2.mjs
//
// Resumable: a scene is skipped when its PNG/MOV still match the manifest and
// the build hash. The simulator's record archive is backed up first and
// restored afterwards; other booted simulators are left alone.
import {spawn,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync,copyFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {setTimeout as sleep} from 'node:timers/promises';
import {COPY} from './creative-copy.mjs';
import {sim,stop,archivePath,decode,encode,launch,regularSeed} from './creative-seed-3.2.1.mjs';

const dir=fileURLToPath(new URL('.',import.meta.url)),raw=join(dir,'raw/3.2.2/search');mkdirSync(raw,{recursive:true});
const id=process.env.IOS_SHOTS_SIMULATOR||'3C9FDCBC-0FA4-4E18-BFF4-2A8C36877966';
const app=process.env.IOS_SHOTS_APP||'/private/tmp/owc-322-creative-build/Build/Products/Debug-iphonesimulator/App.app';
const SCENES=['timer','widgets','records','leave'];
const scenes=process.env.IOS_SHOTS_SCENES?.split(',')||SCENES;
const langs=(process.env.IOS_SHOTS_LANGUAGE||Object.keys(COPY).join(',')).split(',');
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const git=args=>spawnSync('git',args,{cwd:dir,encoding:'utf8'}).stdout.trim();
const build={executableSHA256:hash(join(app,'App')),debugLibrarySHA256:existsSync(join(app,'App.debug.dylib'))?hash(join(app,'App.debug.dylib')):undefined};
const version=spawnSync('/usr/libexec/PlistBuddy',['-c','Print :CFBundleShortVersionString',join(app,'Info.plist')],{encoding:'utf8'}).stdout.trim();
const log=join(raw,'capture-manifest.json');
const manifest=existsSync(log)?JSON.parse(readFileSync(log,'utf8')):{appVersion:version,buildKind:'Debug with QA launch arguments',items:[]};
manifest.sourceCommit=git(['rev-parse','HEAD']);manifest.sourceDirty=git(['status','--porcelain','--','../../../src-mobile'])!=='';
const save=()=>writeFileSync(log,JSON.stringify(manifest,null,2)+'\n');

// A frame counts as ready when it is not the launch screen.
const py=(code,p)=>spawnSync('python3',['-c',code,p],{encoding:'utf8'}).stdout;
const visible=p=>JSON.parse(py("from PIL import Image,ImageStat;import sys;im=Image.open(sys.argv[1]).convert('L');w,h=im.size;print(ImageStat.Stat(im.crop((w*.05,h*.15,w*.95,h*.7))).stddev[0])",p))>12;

const booted=()=>Object.values(JSON.parse(sim(['list','devices','booted','-j'])).devices).flat().some(x=>x.udid===id);
if(!booted()){sim(['boot',id]);sim(['bootstatus',id,'-b']);}
sim(['install',id,app]);sim(['ui',id,'appearance','light']);sim(['ui',id,'content_size','large']);
const backup=join(raw,'before-capture-archive.json');
if(!existsSync(archivePath(id))){launch(id,'en',['-ios.native.qaRecordsScale','year']);await sleep(10000);stop(id);}
if(!existsSync(backup))copyFileSync(archivePath(id),backup);

async function record(path,seconds){
 const p=spawn('xcrun',['simctl','io',id,'recordVideo','--codec=h264','--mask=ignored','--force',path],{stdio:['ignore','ignore','pipe']});let errors='';p.stderr.on('data',b=>errors+=b);
 const done=new Promise((resolve,reject)=>{p.on('error',reject);p.on('close',code=>existsSync(path)?resolve():reject(Error(errors+' code '+code)))});
 await sleep(seconds*1000);p.kill('SIGINT');await done;
}

function sceneArgs(scene,lang){
 switch(scene){
  // 3.2.2 Records: the redesigned month calendar.
  case 'records':return{extra:['-ios.native.selectedTab','records','-ios.native.qaRecordsScale','month']};
  // 3.2.2 Time off: the plan screen. An empty region plans around weekends only.
  case 'leave':return{extra:['-ios.native.selectedTab','settings','-ios.native.qaRoute','leave','-ios.native.qaLeavePlanner','YES','-ios.native.qaLeaveRegion','']};
  // Onboarding picks the holiday template from the locale's region, and the
  // US one makes some capture days (Columbus Day) read "next shift". English
  // without a region keeps the preview counting down the live shift.
  case 'widgets':return{extra:['-ios.native.debugAlwaysOnboarding','YES','-ios.native.qaOnboardingPage','4',...(lang==='en'?['-AppleLocale','en_001']:[])]};
  default:return{extra:['-ios.native.qaDebugScenario','working']};
 }
}
const settle={leave:22,records:12};
// The timer and widget tick for the whole six-second beat.
const seconds={timer:9,widgets:9,records:5,leave:5};

try{
 for(const lang of langs)for(const scene of scenes){
  const prefix=`${lang}-${scene}`,png=join(raw,prefix+'.png'),mov=join(raw,prefix+'.mov');
  const old=manifest.items.find(x=>x.locale===lang&&x.scene===scene);
  if(old&&old.build?.executableSHA256===build.executableSHA256&&old.build?.debugLibrarySHA256===build.debugLibrarySHA256&&existsSync(png)&&hash(png)===old.sha256&&existsSync(mov)&&hash(mov)===old.video.sha256)continue;
  stop(id);copyFileSync(backup,archivePath(id));regularSeed(id,lang);
  const[e,a]=decode(id);if(e.sync)e.sync.syncEnabled=false;encode(id,e,a);
  const {extra}=sceneArgs(scene,lang),time='14:22';
  sim(['status_bar',id,'override','--time',time,'--batteryState','charged','--batteryLevel','100','--wifiMode','active','--wifiBars','3','--cellularMode','active','--cellularBars','4']);
  launch(id,lang,extra);await sleep((settle[scene]??7)*1000);
  for(let attempt=0;;attempt++){
   sim(['io',id,'screenshot','--type=png','--mask=ignored',png]);
   if(visible(png))break;
   if(attempt===11)throw Error('Capture remained on launch screen: '+prefix);
   if(attempt===4||attempt===8){launch(id,lang,extra);await sleep(10000);}else await sleep(3000);
  }
  const duration=seconds[scene]??7;await record(mov,duration);
  const item={locale:lang,ascLocale:COPY[lang].asc,scene,build,file:prefix+'.png',sha256:hash(png),video:{file:prefix+'.mov',sha256:hash(mov),duration},demoData:true,capturedAt:new Date().toISOString()};
  manifest.items=manifest.items.filter(x=>!(x.locale===lang&&x.scene===scene));manifest.items.push(item);save();console.log('captured '+prefix);
 }
}finally{stop(id);copyFileSync(backup,archivePath(id));manifest.archiveRestored=true;save();}

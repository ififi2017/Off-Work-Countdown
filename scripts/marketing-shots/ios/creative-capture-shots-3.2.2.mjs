// Native stills for the 3.2.2 App Store screenshots. Records and Time off were
// redesigned in 3.2.2; every other page keeps its 3.2.1 capture, so only those
// two scenes are retaken: iPhone and the Duo inner display.
//
//   IOS_SHOTS_PLATFORM=iphone|duo-inner IOS_SHOTS_LANGUAGE=en,zh-CN \
//     node scripts/marketing-shots/ios/creative-capture-shots-3.2.2.mjs
//
// Every capture starts from the 3.2.1 marketing demo archive
// (raw/3.2.2/shots/demo-archive.json) so the pages match the rest of the set.
// The simulator's own archive is backed up first and restored afterwards;
// other booted simulators are left alone. Duo must be booted with its inner
// display active and portrait in Device Hub before capture.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync,copyFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {setTimeout as sleep} from 'node:timers/promises';
import {COPY} from './creative-copy.mjs';
import {sim,stop,archivePath,decode,encode,launch,regularSeed,holidays} from './creative-seed-3.2.1.mjs';

const dir=fileURLToPath(new URL('.',import.meta.url)),raw=join(dir,'raw/3.2.2/shots');mkdirSync(raw,{recursive:true});
const platform=process.env.IOS_SHOTS_PLATFORM||'iphone';
if(!['iphone','duo-inner'].includes(platform))throw Error('IOS_SHOTS_PLATFORM must be iphone or duo-inner');
const id=process.env.IOS_SHOTS_SIMULATOR||(platform==='iphone'?'3C9FDCBC-0FA4-4E18-BFF4-2A8C36877966':'F0CC6979-665C-4300-B40E-46F2AD110582');
const display=platform==='duo-inner'?'3':'1',expected=platform==='iphone'?[1320,2868]:[2007,2853];
const SCENES=['leave','records'],scenes=process.env.IOS_SHOTS_SCENES?.split(',')||SCENES;
const langs=(process.env.IOS_SHOTS_LANGUAGE||Object.keys(COPY).join(',')).split(',');
const app=process.env.IOS_SHOTS_APP||'/private/tmp/owc-322-shots-build/Build/Products/Debug-iphonesimulator/App.app';
// Leave plan shown per language when the top-ranked one reads poorly in a still.
const PROPOSALS={};
const proposal=lang=>process.env.IOS_SHOTS_LEAVE_PROPOSAL??PROPOSALS[lang];
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const git=args=>spawnSync('git',args,{cwd:dir,encoding:'utf8'}).stdout.trim();
const build={executableSHA256:hash(join(app,'App')),debugLibrarySHA256:existsSync(join(app,'App.debug.dylib'))?hash(join(app,'App.debug.dylib')):undefined};
const version=spawnSync('/usr/libexec/PlistBuddy',['-c','Print :CFBundleShortVersionString',join(app,'Info.plist')],{encoding:'utf8'}).stdout.trim();
const log=join(raw,`${platform}-capture-manifest.json`);
const manifest=existsSync(log)?JSON.parse(readFileSync(log,'utf8')):{appVersion:version,buildKind:'Debug with regional QA launch arguments',platform,items:[]};
manifest.sourceCommit=git(['rev-parse','HEAD']);manifest.sourceDirty=git(['status','--porcelain','--','../../../src-mobile'])!=='';
const save=()=>writeFileSync(log,JSON.stringify(manifest,null,2)+'\n');
const visible=p=>Number(spawnSync('python3',['-c',"from PIL import Image,ImageStat;import sys;im=Image.open(sys.argv[1]).convert('L');w,h=im.size;print(ImageStat.Stat(im.crop((w*.05,h*.15,w*.95,h*.7))).stddev[0])",p],{encoding:'utf8'}).stdout)>12;

const booted=()=>Object.values(JSON.parse(sim(['list','devices','booted','-j'])).devices).flat().some(x=>x.udid===id);
if(!booted()){if(platform!=='iphone')throw Error('Boot Duo and set its inner display active and portrait in Device Hub first.');sim(['boot',id]);sim(['bootstatus',id,'-b']);}
if(platform!=='iphone'){
 const preflight=join(raw,platform+'-orientation-preflight.png');sim(['io',id,'screenshot','--display='+display,'--mask=ignored',preflight]);
 const px=readFileSync(preflight);if(px.readUInt32BE(16)!==expected[0]||px.readUInt32BE(20)!==expected[1])throw Error('Set the Duo inner display active and portrait in Device Hub before capture.');
}
sim(['install',id,app]);sim(['ui',id,'appearance','light']);
if(!existsSync(archivePath(id))){launch(id,'en');await sleep(10000);stop(id);}
const backup=join(raw,`${platform}-${id}-before-capture-archive.json`);
if(!existsSync(backup))copyFileSync(archivePath(id),backup);

try{
 for(const lang of langs)for(const scene of scenes){
  const prefix=`${lang}-${platform}-${scene}`,png=join(raw,prefix+'.png');
  const old=manifest.items.find(x=>x.locale===lang&&x.scene===scene);
  if(old&&old.build.executableSHA256===build.executableSHA256&&old.build.debugLibrarySHA256===build.debugLibrarySHA256&&existsSync(png)&&hash(png)===old.sha256&&process.env.IOS_SHOTS_FORCE!=='1')continue;
  stop(id);copyFileSync(join(raw,'demo-archive.json'),archivePath(id));regularSeed(id,lang);const[e,a]=decode(id);if(e.sync)e.sync.syncEnabled=false;encode(id,e,a);
  const region=holidays.find(x=>x.ascLocale===COPY[lang].asc);
  const extra=scene==='leave'
   ?['-ios.native.selectedTab','settings','-ios.native.qaRoute','leave','-ios.native.qaLeavePlanner','YES','-ios.native.qaLeaveRegion',region.regionIdentifier,'-ios.native.qaLeaveFrom',region.month+'-01',...(proposal(lang)!==undefined?['-ios.native.qaLeaveProposal',String(proposal(lang))]:[]),...(process.env.IOS_SHOTS_LEAVE_SCREEN?['-ios.native.qaLeaveScreen',process.env.IOS_SHOTS_LEAVE_SCREEN]:[])]
   :['-ios.native.qaRecordsScale',process.env.IOS_SHOTS_RECORDS_SCALE||'year'];
  sim(['status_bar',id,'override','--time','14:22','--batteryState','charged','--batteryLevel','100','--wifiMode','active','--wifiBars','3']);
  launch(id,lang,extra);await sleep(scene==='leave'?22000:12000);
  for(let attempt=0;;attempt++){
   sim(['io',id,'screenshot','--type=png',`--display=${display}`,'--mask=ignored',png]);if(visible(png))break;
   if(attempt===20)throw Error('Capture remained on launch screen: '+prefix);if(attempt===6||attempt===12){launch(id,lang,extra);await sleep(10000);}await sleep(3000);
  }
  const px=readFileSync(png),width=px.readUInt32BE(16),height=px.readUInt32BE(20);
  if(width!==expected[0]||height!==expected[1])throw Error(`Wrong display ${prefix}: ${width}x${height}`);
  manifest.items=manifest.items.filter(x=>!(x.locale===lang&&x.scene===scene));
  manifest.items.push({simulatorUDID:id,build,locale:lang,ascLocale:COPY[lang].asc,scene,file:prefix+'.png',width,height,sha256:hash(png),demoData:true,region:scene==='leave'?region.regionIdentifier:undefined,capturedAt:new Date().toISOString()});save();console.log(prefix);
 }
 manifest.complete=Object.keys(COPY).every(l=>SCENES.every(s=>manifest.items.some(x=>x.locale===l&&x.scene===s)));save();
}finally{stop(id);copyFileSync(backup,archivePath(id));sim(['status_bar',id,'clear'],true);manifest.archiveRestored=true;save();}

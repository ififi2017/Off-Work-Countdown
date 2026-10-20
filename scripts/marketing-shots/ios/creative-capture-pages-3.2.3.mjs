// Native stills for the 3.2.3 font re-render: the Time off and Records pages
// as redesigned in 3.2.2 (whose captures were not kept), retaken from the
// 3.2.3 Debug build for the locales whose page copy fell back to system fonts.
// Same seed and launch arguments as creative-capture-shots-3.2.2.mjs.
//
//   IOS_SHOTS_PLATFORM=iphone|duo-inner IOS_SHOTS_LANGUAGE=zh-CN,ja \
//     node scripts/marketing-shots/ios/creative-capture-pages-3.2.3.mjs
//
// Needs raw/3.2.3/pages/demo-archive.json (raw/iphone-
// before-capture-archive.json from the 3.2.1 capture). Duo must be booted alone with its inner
// display active and portrait in Device Hub.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync,copyFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {setTimeout as sleep} from 'node:timers/promises';
import {COPY} from './creative-copy.mjs';
import {sim,stop,archivePath,decode,encode,launch,regularSeed,holidays} from './creative-seed-3.2.1.mjs';

const dir=fileURLToPath(new URL('.',import.meta.url)),raw=join(dir,'raw/3.2.3/pages');mkdirSync(raw,{recursive:true});
const platform=process.env.IOS_SHOTS_PLATFORM||'iphone';
if(!['iphone','duo-inner'].includes(platform))throw Error('IOS_SHOTS_PLATFORM must be iphone or duo-inner');
const id=process.env.IOS_SHOTS_SIMULATOR||(platform==='iphone'?'3C9FDCBC-0FA4-4E18-BFF4-2A8C36877966':'7F3A6C1A-E341-47FF-B71D-055AB14E538B');
const display=platform==='duo-inner'?'3':'1',expected=platform==='iphone'?[1320,2868]:[2007,2853];
const SCENES=['leave','records'],scenes=process.env.IOS_SHOTS_SCENES?.split(',')||SCENES;
const langs=(process.env.IOS_SHOTS_LANGUAGE||Object.keys(COPY).join(',')).split(',');
const app=process.env.IOS_SHOTS_APP||'/private/tmp/owc-323-creative-build/Build/Products/Debug-iphonesimulator/App.app';
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

// Real Android captures for the Google Play screenshots, on a physical Pixel.
//
//   ANDROID_SERIAL=<serial> ANDROID_SHOTS_DEMO_ARCHIVE=<iOS demo-archive.json> \
//   ANDROID_SHOTS_LANGUAGE=en,zh-CN ANDROID_SHOTS_SCENES=records,report \
//     node scripts/marketing-shots/android/pixel-capture.mjs [output-directory]
//
// Only the isolated Debug install (`-PdoneatDebugApplicationIdSuffix=.shots`)
// is written, through `run-as`. Its archive is synthetic: the iOS 3.2.1/3.2.2
// marketing demo history, reseeded per scene (pixel-seed.mjs). Plus scenes use
// the Debug-only switch. Put System UI demo mode on first; the status-bar
// clock is set to the real time of each capture so it matches the app.
//
// Scenes that depend on the time of day: `timer` and `focus` need 09:00–12:00
// or 13:00–18:00 in Asia/Shanghai (the Pixel's zone), `breaks` 12:00–13:00.
import {mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import * as p from './pixel.mjs';
import {loadDemo,seedDocument,localFile} from './pixel-seed.mjs';
import sharp from 'sharp';

async function rollScore(png){
  const {data}=await sharp(png).extract({left:60,top:330,width:1160,height:330}).greyscale().raw().toBuffer({resolveWithObject:true});
  let grey=0;for(const v of data)if(v>70&&v<190)grey++;
  return grey;
}

const root=fileURLToPath(new URL('../../..',import.meta.url));
const out=resolve(process.argv[2]||'build/play-store-media');
const raw=join(out,'raw');mkdirSync(raw,{recursive:true});
const demo=loadDemo(process.env.ANDROID_SHOTS_DEMO_ARCHIVE||join(root,'scripts/marketing-shots/ios/raw/3.2.2/shots/demo-archive.json'));

// App language → per-app locale tag, string resource folder, holiday region, months after October 2026 to show.
export const LANGUAGES={
  en:{tag:'en-US',res:'values',region:'US',months:1},
  de:{tag:'de-DE',res:'values-de',region:'DE',months:2},
  fr:{tag:'fr-FR',res:'values-fr',region:'FR',months:1},
  es:{tag:'es-ES',res:'values-es',region:'ES',months:2},
  it:{tag:'it-IT',res:'values-it',region:'IT',months:2},
  pt:{tag:'pt-BR',res:'values-pt',region:'BR',months:1},
  ja:{tag:'ja-JP',res:'values-ja',region:'JP',months:1},
  ko:{tag:'ko-KR',res:'values-ko',region:'KR',months:4},
  ru:{tag:'ru-RU',res:'values-ru',region:'RU',months:3},
  tr:{tag:'tr-TR',res:'values-tr',region:'TR',months:0},
  id:{tag:'id-ID',res:'values-in',region:'ID',months:2},
  vi:{tag:'vi-VN',res:'values-vi',region:'VN',months:4},
  th:{tag:'th-TH',res:'values-th',region:'TH',months:2},
  'hi-IN':{tag:'hi-IN',res:'values-b+hi+IN',region:'IN',months:1},
  'mr-IN':{tag:'mr-IN',res:'values-b+mr+IN',region:'IN',months:1},
  ar:{tag:'ar-SA',res:'values-ar',region:'SA',months:4},
  'zh-CN':{tag:'zh-Hans-CN',res:'values-b+zh+Hans+CN',region:'CN',months:4},
  'zh-TW':{tag:'zh-Hant-TW',res:'values-b+zh+Hant+TW',region:'TW',months:4},
  'zh-HK':{tag:'zh-Hant-HK',res:'values-b+zh+Hant+HK',region:'HK',months:0},
};
const SCENES=['records','report','calendar','leave','timer','focus','breaks'];
const langs=(process.env.ANDROID_SHOTS_LANGUAGE||Object.keys(LANGUAGES).join(',')).split(',');
const scenes=(process.env.ANDROID_SHOTS_SCENES||SCENES.join(',')).split(',');

const resCache=new Map();
function string(lang,key){
  const dir=LANGUAGES[lang].res;
  if(!resCache.has(dir))resCache.set(dir,readFileSync(join(root,'src-mobile/android/app/src/main/res',dir,'strings_catalog.xml'),'utf8'));
  const m=resCache.get(dir).match(new RegExp(`<string name="${key}">([^<]*)</string>`));
  if(!m)throw Error(`Missing ${key} in ${dir}`);
  return m[1].replace(/\\'/g,"'").replace(/\\"/g,'"').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>');
}
const minutes=()=>{const [h,m]=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date()).split(':').map(Number);return h*60+m;};
function checkTime(scene){
  const t=minutes();
  if((scene==='timer'||scene==='focus')&&!((t>=540&&t<715)||(t>=785&&t<1070)))throw Error(`${scene} needs working hours (09:00–11:55 or 13:05–17:50)`);
  if(scene==='breaks'&&!(t>=725&&t<775))throw Error('breaks needs 12:05–12:55');
}

const manifestPath=join(raw,'capture-manifest.json');
const manifest=existsSync(manifestPath)?JSON.parse(readFileSync(manifestPath,'utf8')):{items:[]};
const save=()=>writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');

async function prepare(lang,scene){
  const {tag,region}=LANGUAGES[lang];
  p.stop();
  p.setLocale(tag);
  p.writeFile('files/records/records.json',localFile(seedDocument(demo,lang,scene,region)));
  p.runAs('rm -f files/device/session.json files/device/focus-queue.json');
  const tab=scene==='focus'?'focus':scene==='records'||scene==='report'?'records':scene==='calendar'||scene==='leave'?'settings':'timer';
  p.writeFile('files/device/settings.json',JSON.stringify({onboardingComplete:true,notificationPermissionRequested:true,hideEarnings:true,recordsScale:'year',selectedTab:tab,lifeSetupPromptDismissed:true}));
  p.setPlus(true);p.markReleaseNotesSeen();
  return tab;
}

async function capture(lang,scene){
  checkTime(scene);
  const tab=await prepare(lang,scene),s=key=>string(lang,key);
  p.demoClock();
  if(scene==='report'){
    p.launch({tab,data:'doneat://report?kind=month&start=2026-09-01&end=2026-09-30&tz=Asia%2FShanghai'});
    await p.tapText(s('reportPlay'),{timeout:20000});
    await p.sleep(5000);
    await p.tapText(s('reportPause'));
    await p.sleep(900);
  }else{
    p.launch({tab});
    await p.sleep(3500);
    if(scene==='calendar'){
      await p.tapText(s('workSchedule'));await p.sleep(1500);
      for(let i=0;i<LANGUAGES[lang].months;i++){await p.tapText(s('extendedNextMonth'));await p.sleep(700);}
    }
    if(scene==='leave'){
      await p.tapText(s('leaveTitle'));await p.sleep(1200);
      await p.tapText(s('leavePlanAction'));await p.sleep(1200);
      await p.tapText(s('leaveFind'));await p.sleep(4000);
    }
    if(scene==='records')await p.sleep(4000);
  }
  p.demoClock();await p.sleep(700);
  const file=`${lang}-${scene}.png`;
  let png=p.screencap();
  // The countdown's seconds roll every second; keep the frame with the least
  // in-between grey in the digit band, so no digit is caught mid-roll.
  if(scene==='timer'||scene==='breaks'){
    let best=[await rollScore(png),png];
    for(let i=0;i<7;i++){await p.sleep(140);const next=p.screencap(),score=await rollScore(next);if(score<best[0])best=[score,next];}
    png=best[1];
  }
  if(png.readUInt32BE(16)!==1280||png.readUInt32BE(20)!==2856)throw Error('Unexpected capture size for '+file);
  writeFileSync(join(raw,file),png);
  manifest.items=manifest.items.filter(x=>x.file!==file);
  manifest.items.push({file,lang,scene,localeTag:LANGUAGES[lang].tag,region:['calendar','leave'].includes(scene)?LANGUAGES[lang].region:undefined,sha256:createHash('sha256').update(png).digest('hex'),capturedAt:new Date().toISOString()});
  save();console.log(file);
}

manifest.device={model:p.shell('getprop ro.product.model').trim(),sdk:p.shell('getprop ro.build.version.sdk').trim(),package:p.PKG,size:[1280,2856]};
manifest.data='Synthetic: iOS 3.2.1/3.2.2 marketing demo history reseeded per scene; Plus via Debug-only switch; no purchase screen';
try{
  for(const lang of langs)for(const scene of scenes){
    for(let attempt=1;;attempt++){
      try{await capture(lang,scene);break;}
      catch(e){if(attempt>=2||/needs/.test(e.message))throw e;console.warn(`retry ${lang}-${scene}: ${e.message}`);}
    }
  }
}finally{p.stop();save();}

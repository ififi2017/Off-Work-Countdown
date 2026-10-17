// adb helpers for the isolated `.shots` Debug install on a physical Pixel.
// Every write goes through `run-as` into that package only; the Play-installed
// app and any other package are never touched.
import {spawnSync} from 'node:child_process';
import {setTimeout as sleep} from 'node:timers/promises';

export const PKG=process.env.ANDROID_SHOTS_PACKAGE||'com.rainif.doneat.shots';
if(!/\.shots$/.test(PKG))throw Error('Refusing to touch a package without the .shots suffix: '+PKG);
const SERIAL=process.env.ANDROID_SERIAL;
const ACTIVITY=`${PKG}/com.rainif.doneat.MainActivity`;

export function adb(args,{input,allow=false,binary=false}={}){
  const r=spawnSync('adb',[...(SERIAL?['-s',SERIAL]:[]),...args],{input,encoding:binary?'buffer':'utf8',maxBuffer:64*1024*1024,timeout:120000});
  if(r.error)throw r.error;
  if(r.status&&!allow)throw Error(`adb ${args.join(' ')}\n${r.stderr}`);
  return r.stdout;
}
export const shell=(cmd,opts)=>adb(['shell',cmd],opts);
export const runAs=(cmd,opts)=>adb(['shell',`run-as ${PKG} sh -c '${cmd}'`],opts);

export function stop(){shell(`am force-stop ${PKG}`);}
export function writeFile(path,content){
  runAs(`mkdir -p ${path.replace(/\/[^/]+$/,'')} && cat > ${path}`,{input:content});
}
export function setPlus(on){
  writeFile('shared_prefs/debug_plus.xml',`<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n    <boolean name="authorized" value="${on}" />\n</map>\n`);
}
export function markReleaseNotesSeen(){writeFile('no_backup/release-notes.json','{"seenRelease":"3.2.2"}');}
export function setLocale(tag){shell(`cmd locale set-app-locales ${PKG} --locales ${tag}`);}
export function launch({tab,data}={}){
  shell(`am start -W -n ${ACTIVITY}${tab?` --es com.rainif.doneat.TAB ${tab}`:''}${data?` -d '${data}'`:''}`);
}
export function demoClock(date=new Date()){
  const hhmm=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit',hour12:false}).format(date).replace(':','');
  shell(`am broadcast -a com.android.systemui.demo -e command clock -e hhmm ${hhmm}`);
  return hhmm;
}
export function screencap(){return adb(['exec-out','screencap','-p'],{binary:true});}
export function dump(){
  shell('uiautomator dump /sdcard/owc-shots-ui.xml',{allow:true});
  const xml=adb(['exec-out','cat','/sdcard/owc-shots-ui.xml']);
  shell('rm -f /sdcard/owc-shots-ui.xml',{allow:true});
  return xml;
}
/** Nodes whose text or content-desc matches; centre coordinates. */
export function find(xml,match){
  const out=[];
  for(const m of xml.matchAll(/<node [^>]*?text="([^"]*)"[^>]*?content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/g)){
    const [,text,desc,x1,y1,x2,y2]=m;const t=decode(text),d=decode(desc);
    if((typeof match==='string'?[t,d].some(v=>v===match):[t,d].some(v=>match.test(v))))out.push({text:t,desc:d,x:(+x1+ +x2)>>1,y:(+y1+ +y2)>>1,bounds:[+x1,+y1,+x2,+y2]});
  }
  return out;
}
const decode=s=>s.replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&#10;/g,'\n').replace(/&amp;/g,'&');
export function tap(x,y){shell(`input tap ${x} ${y}`);}
export async function tapText(match,{timeout=15000,index=0}={}){
  const end=Date.now()+timeout;
  for(;;){const hit=find(dump(),match);if(hit.length>index){tap(hit[index].x,hit[index].y);return hit[index];}
    if(Date.now()>end)throw Error('Not found on screen: '+match);await sleep(800);}
}
export async function waitText(match,timeout=20000){
  const end=Date.now()+timeout;
  for(;;){const hit=find(dump(),match);if(hit.length)return hit;if(Date.now()>end)throw Error('Never appeared: '+match);await sleep(800);}
}
export {sleep};

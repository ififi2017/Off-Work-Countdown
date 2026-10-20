#!/usr/bin/env node
// Upload the iOS 3.2.3 store media to App Store Connect:
//   - iPhone 6.9″ sets (17 locales): new widget pages at 3 and 4; the old
//     Watch (5) and widgets (9) pages retire; Time off, Cycle report,
//     Calendar, Records, Focus and Rest move to 5–10, swapped for their
//     poster-font re-renders where one exists.
//   - iPhone Duo sets: the poster-font re-renders swapped in place.
//   - Search-results video (20 store locales; en-GB reuses en, es-MX reuses es).
//   - Product page header video V4 re-rendered in poster fonts (6 locales).
// Sources are the audited manifests in scripts/marketing-shots/ios/out/creative-3.2.3.
//
//   set -a; source ~/.config/doneat/asc.env; set +a
//   node scripts/app-store-connect/creative-3.2.3.mjs            # dry run, read-only
//   node scripts/app-store-connect/creative-3.2.3.mjs --apply    # upload, swap, bind
//
// Read-only unless --apply. Never selects a build or submits for review.
// --apply needs an editable iOS 3.2.3 version
// (npm run asc:sync -- --config app-store-connect/ios/3.2.3.json). Until it
// exists, the dry run plans against the live version, whose screenshots and
// placements a new version starts from. Resumable through the receipt.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createApiClient,credentialsFromEnv} from './api.mjs';

const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const OUT=join(ROOT,'scripts/marketing-shots/ios/out/creative-3.2.3');
const RECEIPT=join(ROOT,'app-store-connect/ios/3.2.3/asc-media-receipt.json');
const APP_ID='6802803318',VERSION='3.2.3',GROUP='DEFAULT_PROFILE';
const EDITABLE=['PREPARE_FOR_SUBMISSION','DEVELOPER_REJECTED','REJECTED','METADATA_REJECTED'];
const REUSE={'en-US':['en-GB'],'es-ES':['es-MX']};
// 3.2.2 iPhone positions → 3.2.3 positions. 5 (Watch) and 9 (widgets) retire.
const IPHONE_MOVES=[[1,1],[2,2],[3,5],[4,6],[6,7],[7,8],[8,9],[10,10]];
const apply=process.argv.includes('--apply');

const base=createApiClient({credentials:credentialsFromEnv()});
const retryable=e=>['ECONNRESET','ETIMEDOUT','UND_ERR_CONNECT_TIMEOUT'].includes(e.cause?.code);
const api={...base,async request(path,options={}){for(let i=0;;i++){try{return await base.request(path,options)}catch(e){if((options.method??'GET')!=='GET'||i>=4||!retryable(e))throw e;await new Promise(r=>setTimeout(r,500*2**i))}}}};
const receipt=existsSync(RECEIPT)?JSON.parse(readFileSync(RECEIPT,'utf8')):{appId:APP_ID,versionString:VERSION,sets:{},videos:{},placements:{}};
const save=()=>{receipt.updatedAt=new Date().toISOString();writeFileSync(RECEIPT,JSON.stringify(receipt,null,2)+'\n')};
const digest=(algo,b)=>createHash(algo).update(b).digest('hex');
const manifest=f=>JSON.parse(readFileSync(join(OUT,f),'utf8')).items;

// 1. Local: audited files, hashes unchanged since render, Apple's specs.
const audit=JSON.parse(readFileSync(join(OUT,'audit.json'),'utf8'));
if(audit.findings.length)throw Error(`creative-audit-3.2.3 reports ${audit.findings.length} finding(s)`);
function png(dirName,item){
 const bytes=readFileSync(join(OUT,dirName,item.file)),sha=digest('sha256',bytes);
 if(sha!==item.sha256)throw Error(`${item.file} changed since it was rendered`);
 if(bytes.readUInt32BE(16)!==item.width||bytes.readUInt32BE(20)!==item.height||bytes[25]!==2)throw Error(`${item.file} is not an opaque ${item.width}×${item.height} PNG`);
 const platform=item.platform==='duo'?'duo':'iphone';
 return {...item,bytes,md5:digest('md5',bytes),at:n=>({...item,bytes,md5:digest('md5',bytes),fileName:`doneat-${VERSION}-${item.locale}-${platform}-${String(n).padStart(2,'0')}-${item.scene}-${sha.slice(0,12)}.png`})};
}
const widgetPages=manifest('shots/screenshot-manifest.json').map(i=>png('shots',i));
const fontPages=manifest('pages/screenshot-manifest.json').map(i=>png('pages',i));

const specs=(await api.request('/v1/appAssetLibraryRefData')).data[0].attributes.videoSpecs;
const seconds=iso=>Number(/PT(\d+(?:\.\d+)?)S/.exec(iso)[1]);
function videos(dirName,type,label){
 const spec=specs.find(s=>s.compatiblePlacementTypes.includes(type));
 if(!spec)throw Error(`Apple no longer lists a video spec for ${type}`);
 return manifest(`${dirName}/video-manifest.json`).map(item=>{
  const path=join(OUT,dirName,item.file),hash=digest('sha256',readFileSync(path));
  if(hash!==item.sha256)throw Error(`${item.file} changed since it was rendered`);
  const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',path],{encoding:'utf8'}));
  const v=probe.streams.find(s=>s.codec_type==='video'),d=Number(probe.format.duration),size=Number(probe.format.size),[n,den]=v.r_frame_rate.split('/').map(Number);
  const ok=probe.streams.length===1&&!spec.audioRequired&&v.width>=spec.dimensions.minWidth&&v.width<=spec.dimensions.maxWidth&&v.height>=spec.dimensions.minHeight&&v.height<=spec.dimensions.maxHeight
   &&spec.frameRates.some(f=>n/den>=f.minFps&&n/den<=f.maxFps)&&d>=seconds(spec.duration.min)&&d<=seconds(spec.duration.max)&&size<=spec.maxFileSize;
  if(!ok)throw Error(`${item.file} does not meet Apple's ${spec.shortName}`);
  return {...item,type,label,spec,path,size,duration:d,key:`${type} ${item.locale}`,ascLocales:[item.ascLocale,...(type==='APP_STORE_SEARCH_RESULTS_ASSET'?REUSE[item.ascLocale]??[]:[])],
   fileName:`doneat-${VERSION}-${item.locale}-${label}-${hash.slice(0,12)}.mp4`};
 });
}
const allVideos=[...videos('search','APP_STORE_SEARCH_RESULTS_ASSET','search'),...videos('header','PRODUCT_PAGE_HEADER_ASSET','header-v4')];
console.log(`Local: audit clean; ${widgetPages.length} widget pages, ${fontPages.length} font-fixed pages, ${allVideos.length} videos meet Apple's current specs.`);

// 2. Remote: the version the plan runs against.
const versions=await api.list(`/v1/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&limit=10`);
let version=versions.find(v=>v.attributes.versionString===VERSION),preview=false;
if(!version){
 if(apply)throw Error(`iOS ${VERSION} does not exist yet. Create it first: npm run asc:sync -- --config app-store-connect/ios/${VERSION}.json`);
 version=versions.find(v=>v.attributes.appStoreState==='READY_FOR_SALE');preview=true;
}
const state=version.attributes.appStoreState;
if(apply&&!EDITABLE.includes(state))throw Error(`iOS ${VERSION} is ${state}; media can only change on an editable version`);
const localizations=Object.fromEntries((await api.list(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`)).map(l=>[l.attributes.locale,l.id]));

// Screenshot sets: each target slot keeps an existing screenshot or uploads a new one.
const posRe=(platform,n)=>new RegExp(`-${platform}-0?${n}-`);
async function loadSet(locale,display){
 const set=(await api.list(`/v1/appStoreVersionLocalizations/${localizations[locale]}/appScreenshotSets?limit=50`)).find(s=>s.attributes.screenshotDisplayType===display);
 if(!set)throw Error(`${locale} ${display}: no screenshot set`);
 return {id:set.id,shots:await api.list(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`)};
}
const byLocale=(list,platform)=>Object.groupBy(list.filter(p=>p.platform===platform),p=>p.ascLocale);
const iphoneFix=byLocale(fontPages,'iphone'),duoFix=byLocale(fontPages,'duo'),widgets=byLocale(widgetPages,'iphone');
const setPlans=[];
function done(set,target){return set.shots.length===target.length&&target.every((t,i)=>t.keep?set.shots[i].id===t.keep.id:set.shots[i].attributes.sourceFileChecksum===t.upload.md5)}
for(const locale of Object.keys(widgets)){
 const set=await loadSet(locale,'APP_IPHONE_67'),key=`${locale} APP_IPHONE_67`,rec=receipt.sets[key];
 const original=rec?.original??set.shots.map(s=>({id:s.id,fileName:s.attributes.fileName}));
 if(original.length!==10)throw Error(`${key}: expected the 10 screenshots of 3.2.2, found ${original.length}`);
 original.forEach((s,i)=>{if(!posRe('iphone',i+1).test(s.fileName))throw Error(`${key}: unexpected ${s.fileName} at position ${i+1}`)});
 const target=Array(10);
 for(const p of widgets[locale])target[p.order-1]={upload:p.at(p.order)};
 for(const [from,to] of IPHONE_MOVES){
  const fix=iphoneFix[locale]?.find(p=>p.order===from);
  target[to-1]=fix?{upload:fix.at(to),replaces:original[from-1]}:{keep:original[from-1]};
 }
 setPlans.push({key,locale,display:'APP_IPHONE_67',setId:set.id,original,target,retired:[original[4],original[8]],done:done(set,target)});
}
for(const locale of Object.keys(duoFix)){
 const set=await loadSet(locale,'APP_IPHONE_DUO'),key=`${locale} APP_IPHONE_DUO`,rec=receipt.sets[key];
 const original=rec?.original??set.shots.map(s=>({id:s.id,fileName:s.attributes.fileName}));
 const target=original.map((s,i)=>{
  if(!posRe('duo',i+1).test(s.fileName))throw Error(`${key}: unexpected ${s.fileName} at position ${i+1}`);
  const fix=duoFix[locale].find(p=>p.order===i+1);return fix?{upload:fix.at(i+1),replaces:s}:{keep:s};
 });
 setPlans.push({key,locale,display:'APP_IPHONE_DUO',setId:set.id,original,target,retired:[],done:done(set,target)});
}

// Video placements.
async function placements(locale,type){
 return (await api.list(`/v1/appStoreVersionLocalizations/${localizations[locale]}/placements?include=video&limit=200`)).filter(p=>p.attributes.placementType===type);
}
const missing=allVideos.flatMap(v=>v.ascLocales).filter(l=>!localizations[l]);
if(missing.length)throw Error(`iOS ${version.attributes.versionString} has no localization for ${missing.join(', ')}`);
const videoPlans=[];
for(const v of allVideos)for(const locale of v.ascLocales){
 const current=await placements(locale,v.type),bound=receipt.placements[`${v.type} ${locale}`];
 videoPlans.push({v,locale,current,done:!!bound&&current.length===1&&current[0].id===bound.id});
}

// 3. The plan.
const short=s=>s.fileName.replace(/^doneat-/,'').replace(/-[0-9a-f]{12}\.png$/,'');
const lines=[`Remote: iOS ${version.attributes.versionString} (${state})${preview?` — iOS ${VERSION} does not exist yet; this previews what it will start from`:''}, ${Object.keys(localizations).length} localizations.`,''];
let uploads=0,deletes=0;
for(const p of setPlans){
 const up=p.target.filter(t=>t.upload),del=p.original.length-p.target.filter(t=>t.keep).length;
 if(!p.done){uploads+=up.length;deletes+=del;}
 lines.push(`${p.done?'=':'~'} ${p.key}: ${p.done?'already done':`${up.length} upload, ${del} delete`}`);
 if(!p.done)p.target.forEach((t,i)=>lines.push(`    ${String(i+1).padStart(2)} ${t.keep?`keep ${short(t.keep)}`:`NEW  ${short(t.upload)}${t.replaces?`  (replaces ${short(t.replaces)})`:''}`}`));
 for(const r of p.done?[]:p.retired)lines.push(`       retire ${short(r)}`);
}
lines.push('');
for(const x of videoPlans)lines.push(`${x.done?'=':x.current.length?'~':'+'} ${x.v.type==='APP_STORE_SEARCH_RESULTS_ASSET'?'search':'header'} ${x.locale}: ${x.done?'already bound':`${x.current.length?`replace ${x.current.length} placement(s) with`:'bind'} ${x.v.file} (${x.v.duration.toFixed(1)} s)`}`);
const newVideos=allVideos.filter(v=>!receipt.videos[v.key]?.uploaded).length;
lines.push('',`Totals: ${uploads} screenshot uploads, ${deletes} screenshot deletions in ${setPlans.filter(p=>!p.done).length} sets; ${newVideos} video uploads; ${videoPlans.filter(x=>!x.done).length} placements.`);
console.log(lines.join('\n'));
if(!apply){console.log('\nDry run only. Nothing was changed.');process.exit(0);}

// 4. Screenshots: delete what the set no longer keeps, upload the new pages,
//    wait for processing, then set the order and read it back.
async function waitShot(id,name){
 for(let i=0;i<90;i++){
  const a=(await api.request(`/v1/appScreenshots/${id}`)).data.attributes,st=a.assetDeliveryState?.state;
  if(st==='COMPLETE')return;if(st==='FAILED')throw Error(`Apple failed to process ${name}: ${JSON.stringify(a.assetDeliveryState.errors)}`);
  await new Promise(r=>setTimeout(r,2000));
 }
 throw Error(`Timed out waiting for Apple to process ${name}; rerun to continue`);
}
for(const p of setPlans.filter(p=>!p.done)){
 const rec=receipt.sets[p.key]??={setId:p.setId,original:p.original,uploads:{}};save();
 const keep=new Set(p.target.filter(t=>t.keep).map(t=>t.keep.id));
 let current=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`);
 for(const s of p.original)if(!keep.has(s.id)&&current.some(c=>c.id===s.id)){await api.request(`/v1/appScreenshots/${s.id}`,{method:'DELETE'});console.log(`${p.key}: deleted ${s.fileName}`);}
 current=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`);
 for(const [i,t] of p.target.entries()){
  if(!t.upload)continue;
  const slot=String(i+1);let id=rec.uploads[slot]?.id;
  if(!id||!current.some(c=>c.id===id)){
   const created=(await api.request('/v1/appScreenshots',{method:'POST',body:{data:{type:'appScreenshots',attributes:{fileName:t.upload.fileName,fileSize:t.upload.bytes.length},relationships:{appScreenshotSet:{data:{type:'appScreenshotSets',id:p.setId}}}}}})).data;
   id=created.id;rec.uploads[slot]={id,fileName:t.upload.fileName,md5:t.upload.md5};save();
   await api.uploadParts(created.attributes.uploadOperations,t.upload.bytes);
   await api.request(`/v1/appScreenshots/${id}`,{method:'PATCH',body:{data:{type:'appScreenshots',id,attributes:{uploaded:true,sourceFileChecksum:t.upload.md5}}}});
   console.log(`${p.key} ${slot}: uploaded ${t.upload.fileName}`);
  }
  await waitShot(id,t.upload.fileName);
 }
 const order=p.target.map((t,i)=>t.keep?t.keep.id:rec.uploads[String(i+1)].id);
 await api.request(`/v1/appScreenshotSets/${p.setId}/relationships/appScreenshots`,{method:'PATCH',body:{data:order.map(id=>({type:'appScreenshots',id}))}});
 const after=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`);
 rec.readback={checkedAt:new Date().toISOString(),ok:after.length===order.length&&after.every((s,i)=>s.id===order[i]&&s.attributes.assetDeliveryState?.state==='COMPLETE'),files:after.map(s=>s.attributes.fileName)};save();
 if(!rec.readback.ok)throw Error(`${p.key}: the set did not read back in the planned order`);
 console.log(`${p.key}: ${after.length} screenshots in order`);
}

// 5. Videos: reserve, upload, wait for processing, then bind each locale.
const library=(await api.request(`/v1/apps/${APP_ID}/assetLibrary`)).data;
const existing=await api.list(`/v1/appAssetLibraries/${library.id}/videos?limit=200`);
for(const v of allVideos){
 let rec=receipt.videos[v.key];
 if(rec&&rec.sha256!==v.sha256)throw Error(`${v.key}: the receipt records a different file; inspect before retrying`);
 if(!rec){
  if(existing.some(x=>x.attributes.fileName===v.fileName))throw Error(`${v.fileName} is already in the asset library but not in the receipt; inspect before retrying`);
  const created=(await api.request('/v1/appAssetLibraryVideos',{method:'POST',body:{data:{type:'appAssetLibraryVideos',
   attributes:{category:'CREATIVE_ASSETS',fileName:v.fileName,fileSize:v.size,previewFrameTimeCode:'00:00:01:00',referenceName:`iOS ${VERSION} ${v.ascLocale} ${v.label} video`},
   relationships:{assetLibrary:{data:{type:'appAssetLibraries',id:library.id}}}}}})).data;
  rec=receipt.videos[v.key]={id:created.id,file:v.file,fileName:v.fileName,sha256:v.sha256,specId:v.spec.specId,reservedAt:new Date().toISOString(),uploaded:false};save();
 }
 if(!rec.uploaded){
  const remote=(await api.request(`/v1/appAssetLibraryVideos/${rec.id}`)).data.attributes;
  if(remote.state==='AWAITING_UPLOAD'){
   await api.uploadParts(remote.uploadOperations,readFileSync(v.path));
   await api.request(`/v1/appAssetLibraryVideos/${rec.id}`,{method:'PATCH',body:{data:{type:'appAssetLibraryVideos',id:rec.id,attributes:{uploaded:true}}}});
  }
  rec.uploaded=true;rec.uploadedAt=new Date().toISOString();save();console.log(`${v.key}: uploaded ${v.fileName}`);
 }
}
for(let attempt=0;;attempt++){
 let ready=0;
 for(const v of allVideos){
  const rec=receipt.videos[v.key],a=(await api.request(`/v1/appAssetLibraryVideos/${rec.id}`)).data.attributes;
  rec.state=a.state;if(a.state==='FAILED')throw Error(`${rec.file}: Apple failed to process it (${JSON.stringify(a.stateDetails)})`);
  if(['PREPARE_FOR_SUBMISSION','COMPLETE'].includes(a.state))ready++;
 }
 save();console.log(`Processing: ${ready}/${allVideos.length} ready`);
 if(ready===allVideos.length)break;
 if(attempt>=80)throw Error('Apple is still processing; rerun later to continue from the receipt');
 await new Promise(r=>setTimeout(r,15000));
}
for(const x of videoPlans.filter(x=>!x.done)){
 const rec=receipt.videos[x.v.key],key=`${x.v.type} ${x.locale}`,current=await placements(x.locale,x.v.type);
 const previous=current.map(p=>({id:p.id,videoId:p.relationships?.video?.data?.id}));
 if(!(current.length===1&&previous[0].videoId===rec.id)){
  for(const p of current)await api.request(`/v1/appAssetLibraryPlacements/${p.id}`,{method:'DELETE'});
  const placed=(await api.request('/v1/appAssetLibraryPlacements',{method:'POST',body:{data:{type:'appAssetLibraryPlacements',
   attributes:{placementType:x.v.type,placementGroup:GROUP},
   relationships:{video:{data:{type:'appAssetLibraryVideos',id:rec.id}},appStoreVersionLocalization:{data:{type:'appStoreVersionLocalizations',id:localizations[x.locale]}}}}}})).data;
  receipt.placements[key]={id:placed.id,videoId:rec.id,file:x.v.file,previous,boundAt:new Date().toISOString()};
 }else receipt.placements[key]={id:current[0].id,videoId:rec.id,file:x.v.file};
 save();console.log(`${key}: bound ${x.v.file}`);
}
const readback=[];
for(const [key,p] of Object.entries(receipt.placements)){
 const [type,locale]=key.split(' '),current=await placements(locale,type);
 readback.push({key,file:p.file,state:current[0]?.attributes.state,ok:current.length===1&&current[0].id===p.id&&current[0].relationships?.video?.data?.id===p.videoId&&current[0].attributes.state==='ACTIVE'});
}
receipt.readback={checkedAt:new Date().toISOString(),items:readback,errors:readback.filter(x=>!x.ok).length};save();
console.log(readback.map(x=>`${x.ok?'✓':'✗'} ${x.key} ${x.file} ${x.state}`).join('\n'));
if(receipt.readback.errors)throw Error(`${receipt.readback.errors} placement(s) did not read back as expected`);
console.log('Done. No build selected, nothing submitted.');

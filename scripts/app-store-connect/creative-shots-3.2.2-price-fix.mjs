#!/usr/bin/env node
// Guideline 2.3.7 fix for iOS 3.2.2: replace the screenshots whose captions
// mentioned a price ("3 free tries" on Time off, "free on your wrist" and
// "Free to use" on Apple Watch) in place. iPhone 3 and 5, Duo 2 and 4, iPad 3;
// every other screenshot and each set's order stay as they are.
//
//   source ~/.config/doneat/asc.env
//   node scripts/app-store-connect/creative-shots-3.2.2-price-fix.mjs <dir>            # dry run
//   node scripts/app-store-connect/creative-shots-3.2.2-price-fix.mjs <dir> --apply    # swap
//
// <dir> holds the re-rendered PNGs and jobs.json ({lang, display, order,
// pngOut, width, height}). Read-only unless --apply. Never selects a build or
// submits for review. Resumable through the receipt.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createApiClient,credentialsFromEnv} from './api.mjs';

const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const RECEIPT=join(ROOT,'app-store-connect/ios/3.2.2/asc-screenshots-price-fix-receipt.json');
const APP_ID='6802803318',VERSION='3.2.2';
const ASC={ar:'ar-SA',de:'de-DE',en:'en-US',es:'es-ES',fr:'fr-FR','hi-IN':'hi',id:'id',it:'it',ja:'ja',ko:'ko',pt:'pt-BR',ru:'ru',th:'th',tr:'tr',vi:'vi','zh-CN':'zh-Hans','zh-TW':'zh-Hant'};
// The screenshot currently at each position must be the one being replaced.
const EXPECT={'APP_IPHONE_67 3':/-iphone-03-/,'APP_IPHONE_67 5':/-iphone-0?5-|watch/,'APP_IPHONE_DUO 2':/-duo-0?2-|leave/,'APP_IPHONE_DUO 4':/-duo-0?4-|watch/,'APP_IPAD_PRO_3GEN_129 3':/ipad-03-watch|-ipad-0?3-/};
const dir=process.argv[2];if(!dir||dir.startsWith('--'))throw Error('Pass the directory with jobs.json');
const apply=process.argv.includes('--apply');

const base=createApiClient({credentials:credentialsFromEnv()});
const retryable=e=>['ECONNRESET','ETIMEDOUT','UND_ERR_CONNECT_TIMEOUT'].includes(e.cause?.code);
const api={...base,async request(path,options={}){for(let i=0;;i++){try{return await base.request(path,options)}catch(e){if((options.method??'GET')!=='GET'||i>=4||!retryable(e))throw e;await new Promise(r=>setTimeout(r,500*2**i))}}}};
const receipt=existsSync(RECEIPT)?JSON.parse(readFileSync(RECEIPT,'utf8')):{appId:APP_ID,versionString:VERSION,reason:'Guideline 2.3.7: remove price references from screenshots',swaps:{}};
const save=()=>{receipt.updatedAt=new Date().toISOString();writeFileSync(RECEIPT,JSON.stringify(receipt,null,2)+'\n')};

const digest=(algo,b)=>createHash(algo).update(b).digest('hex');
const shots=JSON.parse(readFileSync(join(dir,'jobs.json'),'utf8')).map(j=>{
 const bytes=readFileSync(j.pngOut),sha=digest('sha256',bytes);
 if(bytes.readUInt32BE(16)!==j.width||bytes.readUInt32BE(20)!==j.height||bytes[25]!==2)throw Error(`${j.pngOut} is not an opaque ${j.width}×${j.height} PNG`);
 const platform={APP_IPHONE_67:'iphone',APP_IPHONE_DUO:'duo',APP_IPAD_PRO_3GEN_129:'ipad'}[j.display];
 return {...j,locale:ASC[j.lang],bytes,md5:digest('md5',bytes),fileName:`doneat-${VERSION}-${j.lang}-${platform}-${String(j.order).padStart(2,'0')}-nofree-${sha.slice(0,12)}.png`};
});
console.log(`Local: ${shots.length} screenshots.`);

const version=(await api.list(`/v1/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=${VERSION}&limit=5`))[0];
const state=version.attributes.appStoreState;
if(!['PREPARE_FOR_SUBMISSION','DEVELOPER_REJECTED','REJECTED','METADATA_REJECTED'].includes(state))throw Error(`iOS ${VERSION} is ${state}; screenshots can only change on an editable version`);
const localizations=Object.fromEntries((await api.list(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`)).map(l=>[l.attributes.locale,l.id]));
const sets={};
async function set(locale,display){
 const key=locale+' '+display;
 if(!sets[key]){
  const found=(await api.list(`/v1/appStoreVersionLocalizations/${localizations[locale]}/appScreenshotSets?limit=50`)).find(s=>s.attributes.screenshotDisplayType===display);
  if(!found)throw Error(`${key}: no screenshot set`);
  sets[key]={id:found.id,shots:await api.list(`/v1/appScreenshotSets/${found.id}/appScreenshots?limit=50`)};
 }
 return sets[key];
}
const plan=[];
for(const s of shots){
 const {id,shots:current}=await set(s.locale,s.display),key=`${s.locale} ${s.display} ${s.order}`,at=current[s.order-1];
 if(!at)throw Error(`${key}: the set has only ${current.length} screenshots`);
 const done=at.attributes.sourceFileChecksum===s.md5||at.attributes.fileName===s.fileName;
 if(!done&&!EXPECT[`${s.display} ${s.order}`].test(at.attributes.fileName))throw Error(`${key}: unexpected ${at.attributes.fileName} at this position`);
 plan.push({key,setId:id,shot:s,old:{id:at.id,fileName:at.attributes.fileName},done});
}
console.log(`Remote: iOS ${VERSION} (${state}).\n`+plan.map(p=>`${p.done?'=':'~'} ${p.key}: ${p.done?'already':`${p.old.fileName} →`} ${p.shot.fileName}`).join('\n'));
if(!apply){console.log('\nDry run only. Rerun with --apply to upload and swap. Nothing was changed.');process.exit(0);}

async function waitComplete(id,name){
 for(let i=0;i<90;i++){
  const a=(await api.request(`/v1/appScreenshots/${id}`)).data.attributes,st=a.assetDeliveryState?.state;
  if(st==='COMPLETE')return;if(st==='FAILED')throw Error(`Apple failed to process ${name}: ${JSON.stringify(a.assetDeliveryState.errors)}`);
  await new Promise(r=>setTimeout(r,2000));
 }
 throw Error(`Timed out waiting for Apple to process ${name}; rerun to continue`);
}
for(const p of plan.filter(p=>!p.done)){
 const rec=receipt.swaps[p.key]??={fileName:p.shot.fileName,md5:p.shot.md5,setId:p.setId,previous:p.old};
 if(!rec.order){rec.order=(await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`)).map(x=>x.id);save();}
 if(!rec.deleted){
  if(rec.order.indexOf(p.old.id)!==p.shot.order-1)throw Error(`${p.key}: ${p.old.fileName} is no longer at position ${p.shot.order}`);
  await api.request(`/v1/appScreenshots/${p.old.id}`,{method:'DELETE'});rec.deleted=true;save();
 }
 if(!rec.newId){
  const created=(await api.request('/v1/appScreenshots',{method:'POST',body:{data:{type:'appScreenshots',attributes:{fileName:p.shot.fileName,fileSize:p.shot.bytes.length},relationships:{appScreenshotSet:{data:{type:'appScreenshotSets',id:p.setId}}}}}})).data;
  rec.newId=created.id;save();
  await api.uploadParts(created.attributes.uploadOperations,p.shot.bytes);
  await api.request(`/v1/appScreenshots/${created.id}`,{method:'PATCH',body:{data:{type:'appScreenshots',id:created.id,attributes:{uploaded:true,sourceFileChecksum:p.shot.md5}}}});
 }
 await waitComplete(rec.newId,p.shot.fileName);
 const ids=rec.order.map(id=>id===p.old.id?rec.newId:id);
 await api.request(`/v1/appScreenshotSets/${p.setId}/relationships/appScreenshots`,{method:'PATCH',body:{data:ids.map(id=>({type:'appScreenshots',id}))}});
 rec.swappedAt=new Date().toISOString();save();console.log(`${p.key}: swapped`);
}

const readback=[];
for(const p of plan){
 const current=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`),at=current[p.shot.order-1];
 readback.push({key:p.key,fileName:at?.attributes.fileName,count:current.length,ok:at?.attributes.sourceFileChecksum===p.shot.md5&&at.attributes.assetDeliveryState?.state==='COMPLETE'&&at.attributes.imageAsset?.width===p.shot.width});
}
receipt.readback={checkedAt:new Date().toISOString(),items:readback,errors:readback.filter(x=>!x.ok).length};save();
console.log(readback.filter(x=>!x.ok).map(x=>`✗ ${x.key} ${x.fileName}`).join('\n'));
if(receipt.readback.errors)throw Error(`${receipt.readback.errors} position(s) did not read back as expected`);
console.log(`Done: ${readback.length} positions read back. No build selected, nothing submitted.`);

#!/usr/bin/env node
// Replace the Records and Time off screenshots of iOS 3.2.2 in place: iPhone
// pages 3 and 7, Duo pages 2 and 6. Every other screenshot, the iPad and
// Watch sets, and the order of each set stay as they are.
//
//   source ~/.config/doneat/asc.env
//   node scripts/app-store-connect/creative-shots-3.2.2.mjs            # dry run, read-only
//   node scripts/app-store-connect/creative-shots-3.2.2.mjs --apply    # upload and swap
//
// Read-only unless --apply. Never selects a build or submits for review.
// Resumable: the receipt records each uploaded screenshot and swap, so a rerun
// continues instead of uploading twice.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createApiClient,credentialsFromEnv} from './api.mjs';

const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const OUT=join(ROOT,'scripts/marketing-shots/ios/out/creative-3.2.2/shots');
const RECEIPT=join(ROOT,'app-store-connect/ios/3.2.2/asc-screenshots-receipt.json');
const APP_ID='6802803318',VERSION='3.2.2';
// en-GB, es-MX and mr-IN carry no screenshot sets of their own (the store
// falls back to the primary locale's), so only locales with a set are swapped.
const apply=process.argv.includes('--apply');

const base=createApiClient({credentials:credentialsFromEnv()});
const retryable=e=>['ECONNRESET','ETIMEDOUT','UND_ERR_CONNECT_TIMEOUT'].includes(e.cause?.code);
const api={...base,async request(path,options={}){for(let i=0;;i++){try{return await base.request(path,options)}catch(e){if((options.method??'GET')!=='GET'||i>=4||!retryable(e))throw e;await new Promise(r=>setTimeout(r,500*2**i))}}}};
const receipt=existsSync(RECEIPT)?JSON.parse(readFileSync(RECEIPT,'utf8')):{appId:APP_ID,versionString:VERSION,swaps:{}};
const save=()=>{receipt.updatedAt=new Date().toISOString();writeFileSync(RECEIPT,JSON.stringify(receipt,null,2)+'\n')};

// 1. Local files from the compose manifest; dimensions and hashes are rechecked.
const digest=(algo,b)=>createHash(algo).update(b).digest('hex');
const shots=JSON.parse(readFileSync(join(OUT,'screenshot-manifest.json'),'utf8')).items.map(item=>{
 const path=join(OUT,item.file),bytes=readFileSync(path),sha=digest('sha256',bytes);
 if(sha!==item.sha256)throw Error(`${item.file} changed since it was composed`);
 if(bytes.readUInt32BE(16)!==item.width||bytes.readUInt32BE(20)!==item.height||bytes[25]!==2)throw Error(`${item.file} is not an opaque ${item.width}×${item.height} PNG`);
 return {...item,path,bytes,md5:digest('md5',bytes),fileName:`doneat-${VERSION}-${item.locale}-${item.platform}-${String(item.order).padStart(2,'0')}-${sha.slice(0,12)}.png`};
});
const expected={APP_IPHONE_67:[3,7],APP_IPHONE_DUO:[2,6]};
for(const s of shots)if(!expected[s.display]?.includes(s.order))throw Error(`${s.file}: unexpected ${s.display} position ${s.order}`);
console.log(`Local: ${shots.length} screenshots.`);

// 2. Remote: the editable 3.2.2 version and the screenshot at each position.
const version=(await api.list(`/v1/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=${VERSION}&limit=5`))[0];
if(!version)throw Error(`iOS ${VERSION} does not exist`);
const state=version.attributes.appStoreState;
if(!['PREPARE_FOR_SUBMISSION','DEVELOPER_REJECTED','REJECTED','METADATA_REJECTED'].includes(state))throw Error(`iOS ${VERSION} is ${state}; screenshots can only change on an editable version`);
const localizations=Object.fromEntries((await api.list(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`)).map(l=>[l.attributes.locale,l.id]));
const sets={};
async function set(locale,display){
 const key=locale+' '+display;
 if(!sets[key]){
  const found=(await api.list(`/v1/appStoreVersionLocalizations/${localizations[locale]}/appScreenshotSets?limit=50`)).find(s=>s.attributes.screenshotDisplayType===display);
  if(!found)return sets[key]=null;
  sets[key]={id:found.id,shots:await api.list(`/v1/appScreenshotSets/${found.id}/appScreenshots?limit=50`)};
 }
 return sets[key];
}
const plan=[];
const skipped=new Set();
for(const s of shots){
 const locale=s.ascLocale;
 if(!localizations[locale])throw Error(`iOS ${VERSION} has no ${locale} localization`);
 const found=await set(locale,s.display);if(!found){skipped.add(locale);continue;}
 const {id,shots:current}=found,key=`${locale} ${s.display} ${s.order}`,at=current[s.order-1];
 if(!at)throw Error(`${key}: the set has only ${current.length} screenshots`);
 const done=at.attributes.sourceFileChecksum===s.md5||at.attributes.fileName===s.fileName;
 plan.push({key,locale,setId:id,shot:s,old:{id:at.id,fileName:at.attributes.fileName},done});
}
console.log(`Remote: iOS ${VERSION} (${state}). No set of its own, left as is: ${[...skipped].join(', ')||'none'}.\n`+plan.map(p=>`${p.done?'=':'~'} ${p.key}: ${p.done?'already':`${p.old.fileName} →`} ${p.shot.fileName}`).join('\n'));
if(!apply){console.log('\nDry run only. Rerun with --apply to upload and swap. Nothing was changed.');process.exit(0);}

async function waitComplete(id,name){
 for(let i=0;i<90;i++){
  const a=(await api.request(`/v1/appScreenshots/${id}`)).data.attributes,st=a.assetDeliveryState?.state;
  if(st==='COMPLETE')return;if(st==='FAILED')throw Error(`Apple failed to process ${name}: ${JSON.stringify(a.assetDeliveryState.errors)}`);
  await new Promise(r=>setTimeout(r,2000));
 }
 throw Error(`Timed out waiting for Apple to process ${name}; rerun to continue`);
}
// 3. A set holds at most ten screenshots, so the old one goes first: note the
//    set's order, delete it, upload the new one and put it in the same place.
for(const p of plan.filter(p=>!p.done)){
 const rec=receipt.swaps[p.key]??={file:p.shot.file,fileName:p.shot.fileName,md5:p.shot.md5,setId:p.setId,previous:p.old};
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

// 4. Read every position back.
const readback=[];
for(const p of plan){
 const current=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`),at=current[p.shot.order-1];
 readback.push({key:p.key,fileName:at?.attributes.fileName,count:current.length,ok:at?.attributes.sourceFileChecksum===p.shot.md5&&at.attributes.assetDeliveryState?.state==='COMPLETE'&&at.attributes.imageAsset?.width===p.shot.width});
}
receipt.readback={checkedAt:new Date().toISOString(),items:readback,errors:readback.filter(x=>!x.ok).length};save();
console.log(readback.filter(x=>!x.ok).map(x=>`✗ ${x.key} ${x.fileName}`).join('\n'));
if(receipt.readback.errors)throw Error(`${receipt.readback.errors} position(s) did not read back as expected`);
console.log(`Done: ${readback.length} positions read back. No build selected, nothing submitted.`);

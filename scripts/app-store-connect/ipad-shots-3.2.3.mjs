#!/usr/bin/env node
// Upload the iOS 3.2.3 iPad 13″ widget pages to App Store Connect
// (APP_IPAD_PRO_3GEN_129, 17 locales):
//   new order 1 hero · 2 detail · 3 Home Screen (new) · 4 Lock Screen (new)
//   · 5 calendar · 6 records · 7 focus · 8 breaks; the live Watch (3) and
//   widgets (7) pages retire. The kept pages must still be the exact files
//   the review sheets were built from (raw/3.2.3/ipad-live/index.json).
// Sources: the audited manifest in scripts/marketing-shots/ios/out/creative-3.2.3/ipad.
//
//   set -a; source ~/.config/doneat/asc.env; set +a
//   node scripts/app-store-connect/ipad-shots-3.2.3.mjs            # dry run, read-only
//   node scripts/app-store-connect/ipad-shots-3.2.3.mjs --apply    # upload, delete, reorder
//
// Read-only unless --apply. Only the iOS 3.2.3 version's iPad 13″ sets
// change. Never selects a build or submits for review. Resumable through
// the receipt.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createApiClient,credentialsFromEnv} from './api.mjs';

const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const OUT=join(ROOT,'scripts/marketing-shots/ios/out/creative-3.2.3');
const LIVE=join(ROOT,'scripts/marketing-shots/ios/raw/3.2.3/ipad-live/index.json');
const RECEIPT=join(ROOT,'app-store-connect/ios/3.2.3/asc-ipad-receipt.json');
const APP_ID='6802803318',VERSION='3.2.3',DISPLAY='APP_IPAD_PRO_3GEN_129';
const EDITABLE=['PREPARE_FOR_SUBMISSION','DEVELOPER_REJECTED','REJECTED','METADATA_REJECTED'];
// Live position → new position. 3 (Watch) and 7 (widgets) retire.
const MOVES=[[1,1],[2,2],[4,5],[5,6],[6,7],[8,8]];
const apply=process.argv.includes('--apply');

const base=createApiClient({credentials:credentialsFromEnv()});
const retryable=e=>['ECONNRESET','ETIMEDOUT','UND_ERR_CONNECT_TIMEOUT'].includes(e.cause?.code);
const api={...base,async request(path,options={}){for(let i=0;;i++){try{return await base.request(path,options)}catch(e){if((options.method??'GET')!=='GET'||i>=4||!retryable(e))throw e;await new Promise(r=>setTimeout(r,500*(i+1)))}}}};
api.list=async path=>{const items=[];let next=path;while(next){const page=await api.request(next);items.push(...(page?.data??[]));next=page?.links?.next??null;}return items;};
const receipt=existsSync(RECEIPT)?JSON.parse(readFileSync(RECEIPT,'utf8')):{appId:APP_ID,versionString:VERSION,display:DISPLAY,sets:{}};
const save=()=>{receipt.updatedAt=new Date().toISOString();writeFileSync(RECEIPT,JSON.stringify(receipt,null,2)+'\n')};
const digest=(algo,b)=>createHash(algo).update(b).digest('hex');

// 1. Local: audited pages, unchanged since render, Apple's iPad 13″ size.
const audit=JSON.parse(readFileSync(join(OUT,'audit.json'),'utf8'));
if(audit.findings.length)throw Error(`creative-audit-3.2.3 reports ${audit.findings.length} finding(s)`);
const pages=JSON.parse(readFileSync(join(OUT,'ipad/screenshot-manifest.json'),'utf8')).items.map(item=>{
 const bytes=readFileSync(join(OUT,'ipad',item.file)),sha=digest('sha256',bytes);
 if(sha!==item.sha256)throw Error(`${item.file} changed since it was rendered`);
 if(bytes.readUInt32BE(16)!==2064||bytes.readUInt32BE(20)!==2752||bytes[25]!==2)throw Error(`${item.file} is not an opaque 2064×2752 PNG`);
 return {...item,bytes,md5:digest('md5',bytes),fileName:`doneat-${VERSION}-${item.locale}-ipad-${String(item.order).padStart(2,'0')}-${item.scene}-${sha.slice(0,12)}.png`};
});
const byLocale=Object.groupBy(pages,p=>p.ascLocale);
for(const [l,ps] of Object.entries(byLocale))if(ps.length!==2)throw Error(`${l}: expected pages 3 and 4, found ${ps.length}`);
const live=JSON.parse(readFileSync(LIVE,'utf8')).locales;
console.log(`Local: audit clean; ${pages.length} iPad pages for ${Object.keys(byLocale).length} locales.`);

// 2. Remote: the editable 3.2.3 version and each locale's iPad 13″ set.
const version=(await api.list(`/v1/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=${VERSION}`))[0];
if(!version)throw Error(`iOS ${VERSION} does not exist`);
const state=version.attributes.appStoreState;
if(apply&&!EDITABLE.includes(state))throw Error(`iOS ${VERSION} is ${state}; media can only change on an editable version`);
const localizations=Object.fromEntries((await api.list(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`)).map(l=>[l.attributes.locale,l.id]));
const plans=[];
for(const [locale,ps] of Object.entries(byLocale)){
 if(!localizations[locale])throw Error(`iOS ${VERSION} has no ${locale} localization`);
 const set=(await api.list(`/v1/appStoreVersionLocalizations/${localizations[locale]}/appScreenshotSets?limit=50`)).find(s=>s.attributes.screenshotDisplayType===DISPLAY);
 if(!set)throw Error(`${locale}: no ${DISPLAY} set`);
 const shots=await api.list(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`),rec=receipt.sets[locale];
 const original=rec?.original??shots.map(s=>({id:s.id,fileName:s.attributes.fileName}));
 // What the review sheets showed must be what the set still holds.
 const reviewed=live[locale];
 if(!reviewed||reviewed.length!==8)throw Error(`${locale}: no reviewed 8-page iPad set in ipad-live/index.json`);
 if(original.length!==8||original.some((s,i)=>s.id!==reviewed[i].id))throw Error(`${locale}: the iPad set changed since the review sheets were made; refetch and review again`);
 const target=Array(8);
 for(const p of ps)target[p.order-1]={upload:p};
 for(const [from,to] of MOVES)target[to-1]={keep:original[from-1]};
 const done=shots.length===8&&target.every((t,i)=>t.keep?shots[i].id===t.keep.id:shots[i].attributes.sourceFileChecksum===t.upload.md5);
 plans.push({locale,setId:set.id,original,target,retired:[original[2],original[6]],done});
}

// 3. The plan.
const short=f=>f.replace(/^doneat-/,'').replace(/-[0-9a-f]{12}\.png$/,'');
const lines=[`Remote: iOS ${VERSION} (${state}), ${Object.keys(localizations).length} localizations; ${DISPLAY} sets only.`,''];
for(const p of plans){
 lines.push(`${p.done?'=':'~'} ${p.locale}: ${p.done?'already done':'2 upload, 2 delete, reorder'}`);
 if(p.done)continue;
 p.target.forEach((t,i)=>lines.push(`    ${i+1} ${t.keep?`keep ${short(t.keep.fileName)}`:`NEW  ${short(t.upload.fileName)}`}`));
 for(const r of p.retired)lines.push(`      retire ${short(r.fileName)}`);
}
const todo=plans.filter(p=>!p.done);
lines.push('',`Totals: ${todo.length*2} screenshot uploads, ${todo.length*2} screenshot deletions, ${todo.length} reorders in ${todo.length} sets. No videos, metadata, builds or other sets.`);
console.log(lines.join('\n'));
if(!apply){console.log('\nDry run only. Nothing was changed.');process.exit(0);}

// 4. Delete the retiring pages, upload the new ones, wait for processing,
//    set the order and read it back.
async function waitShot(id,name){
 for(let i=0;i<90;i++){
  const a=(await api.request(`/v1/appScreenshots/${id}`)).data.attributes,st=a.assetDeliveryState?.state;
  if(st==='COMPLETE')return;if(st==='FAILED')throw Error(`Apple failed to process ${name}: ${JSON.stringify(a.assetDeliveryState.errors)}`);
  await new Promise(r=>setTimeout(r,2000));
 }
 throw Error(`Timed out waiting for Apple to process ${name}; rerun to continue`);
}
for(const p of todo){
 const rec=receipt.sets[p.locale]??={setId:p.setId,original:p.original,uploads:{}};save();
 let current=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`);
 for(const s of p.retired)if(current.some(c=>c.id===s.id)){await api.request(`/v1/appScreenshots/${s.id}`,{method:'DELETE'});console.log(`${p.locale}: deleted ${s.fileName}`);}
 current=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`);
 for(const [i,t] of p.target.entries()){
  if(!t.upload)continue;
  const slot=String(i+1);let id=rec.uploads[slot]?.id;
  if(!id||!current.some(c=>c.id===id)){
   const created=(await api.request('/v1/appScreenshots',{method:'POST',body:{data:{type:'appScreenshots',attributes:{fileName:t.upload.fileName,fileSize:t.upload.bytes.length},relationships:{appScreenshotSet:{data:{type:'appScreenshotSets',id:p.setId}}}}}})).data;
   id=created.id;rec.uploads[slot]={id,fileName:t.upload.fileName,md5:t.upload.md5};save();
   await api.uploadParts(created.attributes.uploadOperations,t.upload.bytes);
   await api.request(`/v1/appScreenshots/${id}`,{method:'PATCH',body:{data:{type:'appScreenshots',id,attributes:{uploaded:true,sourceFileChecksum:t.upload.md5}}}});
   console.log(`${p.locale} ${slot}: uploaded ${t.upload.fileName}`);
  }
  await waitShot(id,t.upload.fileName);
 }
 const order=p.target.map((t,i)=>t.keep?t.keep.id:rec.uploads[String(i+1)].id);
 await api.request(`/v1/appScreenshotSets/${p.setId}/relationships/appScreenshots`,{method:'PATCH',body:{data:order.map(id=>({type:'appScreenshots',id}))}});
 // The new order shows up a moment after the PATCH, so read back a few times.
 let after,ok=false;
 for(let i=0;i<10&&!ok;i++){
  if(i)await new Promise(r=>setTimeout(r,3000));
  after=await api.list(`/v1/appScreenshotSets/${p.setId}/appScreenshots?limit=50`);
  ok=after.length===8&&after.every((s,i)=>s.id===order[i]&&s.attributes.assetDeliveryState?.state==='COMPLETE');
 }
 rec.readback={checkedAt:new Date().toISOString(),ok,files:after.map(s=>s.attributes.fileName)};save();
 if(!rec.readback.ok)throw Error(`${p.locale}: the set did not read back in the planned order`);
 console.log(`${p.locale}: 8 screenshots in order`);
}
console.log('Done. No build selected, nothing submitted.');

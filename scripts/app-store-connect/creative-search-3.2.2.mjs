#!/usr/bin/env node
// Upload the 3.2.2 search-results videos to the app's asset library and bind
// each one to the matching iOS 3.2.2 store locale (Product page → Header and
// search results → search results asset).
//
//   source ~/.config/doneat/asc.env   # ASC_KEY_ID, ASC_ISSUER_ID (+ .p8 in the default path)
//   node scripts/app-store-connect/creative-search-3.2.2.mjs            # dry run, read-only
//   node scripts/app-store-connect/creative-search-3.2.2.mjs --apply    # upload and bind
//
// Read-only unless --apply. Never selects a build, submits for review or
// touches the header (title) asset. The iOS 3.2.2 version must already exist
// (npm run asc:sync -- --config app-store-connect/ios/3.2.2.json).
// Resumable: the receipt records each reserved upload and placement, so a
// rerun continues instead of uploading twice.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createApiClient,credentialsFromEnv} from './api.mjs';

const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const OUT=join(ROOT,'scripts/marketing-shots/ios/out/creative-3.2.2/search');
const RECEIPT=join(ROOT,'app-store-connect/ios/3.2.2/asc-search-video-receipt.json');
const APP_ID='6802803318',VERSION='3.2.2',TYPE='APP_STORE_SEARCH_RESULTS_ASSET',GROUP='DEFAULT_PROFILE';
// en-GB reuses en and es-MX reuses es, as in 3.2.1.
const REUSE={'en-US':['en-GB'],'es-ES':['es-MX']};
const apply=process.argv.includes('--apply');

const base=createApiClient({credentials:credentialsFromEnv()});
const retryable=e=>['ECONNRESET','ETIMEDOUT','UND_ERR_CONNECT_TIMEOUT'].includes(e.cause?.code);
const api={...base,async request(path,options={}){for(let i=0;;i++){try{return await base.request(path,options)}catch(e){if((options.method??'GET')!=='GET'||i>=4||!retryable(e))throw e;await new Promise(r=>setTimeout(r,500*2**i))}}}};
const receipt=existsSync(RECEIPT)?JSON.parse(readFileSync(RECEIPT,'utf8')):{appId:APP_ID,versionString:VERSION,placementType:TYPE,videos:{},placements:{}};
const save=()=>{receipt.updatedAt=new Date().toISOString();writeFileSync(RECEIPT,JSON.stringify(receipt,null,2)+'\n')};

// 1. Local files: the rendered manifest, hashes and Apple's search video spec.
const manifest=JSON.parse(readFileSync(join(OUT,'video-manifest.json'),'utf8')).items;
const spec=(await api.request('/v1/appAssetLibraryRefData')).data[0].attributes.videoSpecs.find(s=>s.compatiblePlacementTypes.includes(TYPE));
if(!spec)throw Error('Apple no longer lists a search-results video spec');
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const videos=manifest.map(item=>{
 const file=join(OUT,item.file),hash=sha(file);
 if(hash!==item.sha256)throw Error(`${item.file} changed since it was rendered`);
 const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',file],{encoding:'utf8'}));
 const v=probe.streams.find(s=>s.codec_type==='video'),seconds=Number(probe.format.duration),size=Number(probe.format.size);
 const ok=probe.streams.length===1&&v.width>=spec.dimensions.minWidth&&v.width<=spec.dimensions.maxWidth&&v.height>=spec.dimensions.minHeight&&v.height<=spec.dimensions.maxHeight
  &&v.width*2===v.height*3&&v.r_frame_rate==='30/1'&&seconds>=15&&seconds<=30&&size<=spec.maxFileSize;
 if(!ok)throw Error(`${item.file} does not meet Apple's search video spec ${spec.shortName}`);
 return {...item,path:file,size,ascLocales:[item.ascLocale,...(REUSE[item.ascLocale]??[])],fileName:`doneat-${VERSION}-${item.locale}-search-${hash.slice(0,12)}.mp4`};
});
console.log(`Local: ${videos.length} videos meet ${spec.shortName}; they cover ${videos.flatMap(v=>v.ascLocales).length} store locales.`);

// 2. Remote: the 3.2.2 version, its localizations and their current search placement.
const version=(await api.list(`/v1/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=${VERSION}&limit=5`))[0];
if(!version)throw Error(`iOS ${VERSION} does not exist yet. Run: npm run asc:sync -- --config app-store-connect/ios/${VERSION}.json`);
const state=version.attributes.appStoreState;
if(!['PREPARE_FOR_SUBMISSION','DEVELOPER_REJECTED','REJECTED','METADATA_REJECTED'].includes(state))throw Error(`iOS ${VERSION} is ${state}; placements can only change on an editable version`);
const localizations=Object.fromEntries((await api.list(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`)).map(l=>[l.attributes.locale,l.id]));
const missing=videos.flatMap(v=>v.ascLocales).filter(l=>!localizations[l]);
if(missing.length)throw Error(`iOS ${VERSION} has no localization for ${missing.join(', ')}`);
async function searchPlacements(localizationId){
 const all=await api.list(`/v1/appStoreVersionLocalizations/${localizationId}/placements?include=video&limit=200`);
 return all.filter(p=>p.attributes.placementType===TYPE);
}
const library=(await api.request(`/v1/apps/${APP_ID}/assetLibrary`)).data;
const plan=[];
for(const v of videos)for(const locale of v.ascLocales){
 const current=await searchPlacements(localizations[locale]);
 const done=receipt.placements[locale];
 if(done&&current.some(p=>p.id===done.id))plan.push(`= ${locale}: already bound to ${v.file}`);
 else plan.push(`${current.length?'~':'+'} ${locale}: ${current.length?`replace ${current.length} existing search placement(s) with`:'bind'} ${v.file}`);
}
console.log(`Remote: iOS ${VERSION} (${state}), ${Object.keys(localizations).length} localizations.\n${plan.join('\n')}`);
if(!apply){console.log('\nDry run only. Rerun with --apply to upload and bind. Nothing was changed.');process.exit(0);}

// 3. Upload: reserve, upload the parts, mark uploaded, wait for processing.
const existing=await api.list(`/v1/appAssetLibraries/${library.id}/videos?limit=200`);
for(const v of videos){
 let rec=receipt.videos[v.locale];
 if(rec&&rec.sha256!==v.sha256)throw Error(`${v.locale}: the receipt records a different file; inspect before retrying`);
 if(!rec){
  if(existing.some(x=>x.attributes.fileName===v.fileName))throw Error(`${v.fileName} is already in the asset library but not in the receipt; inspect before retrying`);
  const created=(await api.request('/v1/appAssetLibraryVideos',{method:'POST',body:{data:{type:'appAssetLibraryVideos',
   attributes:{category:'CREATIVE_ASSETS',fileName:v.fileName,fileSize:v.size,previewFrameTimeCode:'00:00:01:00',referenceName:`iOS ${VERSION} ${v.ascLocale} search video`},
   relationships:{assetLibrary:{data:{type:'appAssetLibraries',id:library.id}}}}}})).data;
  rec=receipt.videos[v.locale]={id:created.id,file:v.file,fileName:v.fileName,sha256:v.sha256,fileSize:v.size,specId:spec.specId,ascLocales:v.ascLocales,reservedAt:new Date().toISOString(),uploaded:false};save();
 }
 if(!rec.uploaded){
  const remote=(await api.request(`/v1/appAssetLibraryVideos/${rec.id}`)).data.attributes;
  if(remote.state==='AWAITING_UPLOAD'){
   await api.uploadParts(remote.uploadOperations,readFileSync(v.path));
   await api.request(`/v1/appAssetLibraryVideos/${rec.id}`,{method:'PATCH',body:{data:{type:'appAssetLibraryVideos',id:rec.id,attributes:{uploaded:true}}}});
  }
  rec.uploaded=true;rec.uploadedAt=new Date().toISOString();save();console.log(`${v.locale}: uploaded ${v.fileName}`);
 }
}
for(let attempt=0;;attempt++){
 let ready=0;
 for(const rec of Object.values(receipt.videos)){
  const a=(await api.request(`/v1/appAssetLibraryVideos/${rec.id}`)).data.attributes,preview=a.previewFrameImage?.state;
  Object.assign(rec,{state:a.state,previewState:typeof preview==='object'?preview?.state:preview,playable:!!a.videoAsset});
  if(a.state==='FAILED')throw Error(`${rec.file}: Apple failed to process it (${JSON.stringify(a.stateDetails)})`);
  if(['PREPARE_FOR_SUBMISSION','COMPLETE'].includes(a.state))ready++;
 }
 save();console.log(`Processing: ${ready}/${videos.length} ready`);
 if(ready===videos.length)break;
 if(attempt>=80)throw Error('Apple is still processing; rerun later to continue from the receipt');
 await new Promise(r=>setTimeout(r,15000));
}

// 4. Bind each store locale, replacing any search placement the new version
//    carried over, then read every locale back.
for(const v of videos)for(const locale of v.ascLocales){
 const rec=receipt.videos[v.locale],current=await searchPlacements(localizations[locale]);
 if(current.length===1&&current[0].relationships?.video?.data?.id===rec.id){receipt.placements[locale]={id:current[0].id,videoId:rec.id,file:v.file};continue;}
 const previous=current.map(p=>({id:p.id,videoId:p.relationships?.video?.data?.id}));
 for(const p of current)await api.request(`/v1/appAssetLibraryPlacements/${p.id}`,{method:'DELETE'});
 const placed=(await api.request('/v1/appAssetLibraryPlacements',{method:'POST',body:{data:{type:'appAssetLibraryPlacements',
  attributes:{placementType:TYPE,placementGroup:GROUP},
  relationships:{video:{data:{type:'appAssetLibraryVideos',id:rec.id}},appStoreVersionLocalization:{data:{type:'appStoreVersionLocalizations',id:localizations[locale]}}}}}})).data;
 receipt.placements[locale]={id:placed.id,videoId:rec.id,file:v.file,previous,boundAt:new Date().toISOString()};save();console.log(`${locale}: bound ${v.file}`);
}
const readback=[];
for(const [locale,p] of Object.entries(receipt.placements)){
 const current=await searchPlacements(localizations[locale]);
 const ok=current.length===1&&current[0].id===p.id&&current[0].relationships?.video?.data?.id===p.videoId&&current[0].attributes.state==='ACTIVE';
 readback.push({locale,file:p.file,placementId:p.id,state:current[0]?.attributes.state,ok});
}
receipt.readback={checkedAt:new Date().toISOString(),items:readback,errors:readback.filter(x=>!x.ok).length};save();
console.log(readback.map(x=>`${x.ok?'✓':'✗'} ${x.locale} ${x.file} ${x.state}`).join('\n'));
if(receipt.readback.errors)throw Error(`${receipt.readback.errors} locale(s) did not read back as expected`);
console.log(`Done: ${readback.length} store locales bound. No build selected, nothing submitted.`);

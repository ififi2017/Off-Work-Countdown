#!/usr/bin/env node
// Read-only: download the iPad 13″ screenshots (APP_IPAD_PRO_3GEN_129) of the
// iOS 3.2.3 version, in set order, as layout references and for review sheets.
//
//   set -a; source ~/.config/doneat/asc.env; set +a
//   node scripts/app-store-connect/ipad-shots-fetch-3.2.3.mjs
//
// Writes scripts/marketing-shots/ios/raw/3.2.3/ipad-live/<ascLocale>/NN.png
// and index.json. Never changes anything in App Store Connect.
import {mkdirSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createApiClient,credentialsFromEnv} from './api.mjs';

const ROOT=fileURLToPath(new URL('../../',import.meta.url)),OUT=join(ROOT,'scripts/marketing-shots/ios/raw/3.2.3/ipad-live');
const APP_ID='6802803318',VERSION='3.2.3',TYPE='APP_IPAD_PRO_3GEN_129';
const api=createApiClient({credentials:credentialsFromEnv()});
const versions=await api.list(`/v1/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=${VERSION}`);
if(versions.length!==1)throw Error(`expected one iOS ${VERSION} version, found ${versions.length}`);
const locs=await api.list(`/v1/appStoreVersions/${versions[0].id}/appStoreVersionLocalizations`);
const index={version:VERSION,displayType:TYPE,fetchedAt:new Date().toISOString(),locales:{}};
for(const loc of locs){
 const locale=loc.attributes.locale;
 const sets=(await api.list(`/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`)).filter(s=>s.attributes.screenshotDisplayType===TYPE);
 if(!sets.length)continue;
 const shots=await api.list(`/v1/appScreenshotSets/${sets[0].id}/appScreenshots`);
 const dir=join(OUT,locale);mkdirSync(dir,{recursive:true});
 index.locales[locale]=[];
 for(const [n,s] of shots.entries()){
  const a=s.attributes.imageAsset;if(!a)throw Error(`${locale} ${n+1}: no image asset`);
  const url=a.templateUrl.replace('{w}',a.width).replace('{h}',a.height).replace('{f}','png');
  const res=await fetch(url);if(!res.ok)throw Error(`${locale} ${n+1}: ${res.status}`);
  const file=`${String(n+1).padStart(2,'0')}.png`;writeFileSync(join(dir,file),Buffer.from(await res.arrayBuffer()));
  index.locales[locale].push({order:n+1,id:s.id,fileName:s.attributes.fileName,file,width:a.width,height:a.height});
 }
 console.log(locale,shots.length);
}
writeFileSync(join(OUT,'index.json'),JSON.stringify(index,null,2)+'\n');

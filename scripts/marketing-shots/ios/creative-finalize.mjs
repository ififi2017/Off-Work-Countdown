// Assemble only current, rendered pairs from incremental batches.
import {readFileSync,writeFileSync,readdirSync,existsSync,statSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {COPY,PAGE_NAMES} from './creative-copy.mjs';
const out=process.env.IOS_CREATIVE_OUT||fileURLToPath(new URL('./out/creative-3.2.0',import.meta.url));
const digest=path=>existsSync(path)?createHash('sha256').update(readFileSync(path)).digest('hex'):null;
const batches=readdirSync(out).filter(name=>name.startsWith('manifest-')&&name.endsWith('.json')).sort((a,b)=>statSync(join(out,b)).mtimeMs-statSync(join(out,a)).mtimeMs);
const current=new Map();
for(const batch of batches){
 const items=JSON.parse(readFileSync(join(out,batch),'utf8'));
 for(const item of items){
  if(current.has(item.file)||item.preview||!item.rendered||!item.htmlSHA256||!item.pngSHA256)continue;
  if(digest(join(out,item.file))!==item.pngSHA256||digest(join(out,item.file.replace('.png','.html')))!==item.htmlSHA256)continue;
  if(!item.sources?.length||item.sources.some(source=>digest(source.path)!==source.sha256))continue;
  current.set(item.file,item);
 }
}
const items=[],missing=[];
for(const locale of Object.keys(COPY))for(const device of ['iphone','ipad'])for(const scene of PAGE_NAMES){
 const file=`${locale}-${device}-${scene}.png`,item=current.get(file);
 if(item)items.push(item);else missing.push(file);
}
if(missing.length)throw new Error(`Missing current rendered pairs (${missing.length}):\n${missing.join('\n')}`);
writeFileSync(join(out,'manifest.json'),JSON.stringify({createdAt:new Date().toISOString(),complete:true,items},null,2)+'\n');
console.log('Finalized 272 current PNG/HTML/raw digest triples. Run creative-validate.mjs.');

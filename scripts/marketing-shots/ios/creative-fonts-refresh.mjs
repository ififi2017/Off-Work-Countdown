// Refresh a poster font's Google Fonts text subset when marketing copy adds
// characters (fonts/README.md). Keeps every character the subset already
// had, adds the new ones, downloads the files Google Fonts returns for the
// same CSS request shape, and records the new request, source and hashes in
// fonts/manifest.json. Files keep their names, so fonts/*.css is unchanged.
//
//   node scripts/marketing-shots/ios/creative-fonts-refresh.mjs "Noto Serif SC" "新的文案"
//
// Afterwards render and let the actual-font check confirm no system fallback.
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const dir=new URL('./fonts/',import.meta.url),manifestURL=new URL('manifest.json',dir);
const [family,...texts]=process.argv.slice(2);if(!family||!texts.length)throw Error('usage: <family> <text>...');
const manifest=JSON.parse(readFileSync(manifestURL,'utf8')),entries=manifest.filter(e=>e.family===family&&e.cssRequest);
if(!entries.length)throw Error(`No subset entry for ${family}`);
const request=new URL(entries[0].cssRequest),old=request.searchParams.get('text');
const chars=[...new Set([...old,...texts.join('')])].filter(c=>c.trim()||c===' ').sort((a,b)=>a.codePointAt(0)-b.codePointAt(0)).join('');
const added=[...chars].filter(c=>!old.includes(c));
if(!added.length){console.log(`${family}: subset already covers the text`);process.exit(0);}
request.searchParams.set('text',chars);
const css=await (await fetch(request)).text();
const sources=[...css.matchAll(/src:\s*url\(([^)]+)\)/g)].map(m=>m[1]);
if(sources.length!==entries.length)throw Error(`${family}: expected ${entries.length} files, got ${sources.length}\n${css}`);
for(const [i,entry] of entries.entries()){
 const bytes=Buffer.from(await (await fetch(sources[i])).arrayBuffer());
 if(bytes.readUInt32BE(0)!==0x00010000)throw Error(`${family}: ${sources[i]} is not TrueType`);
 writeFileSync(new URL(entry.file,dir),bytes);
 Object.assign(entry,{source:sources[i],sha256:createHash('sha256').update(bytes).digest('hex'),cssRequest:request.href});
}
writeFileSync(manifestURL,JSON.stringify(manifest,null,2)+'\n');
console.log(`${family}: added ${added.length} characters (${added.join('')}) to ${entries.map(e=>e.file).join(', ')}`);

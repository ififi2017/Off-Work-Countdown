// Only these locally pinned, licensed files may render poster typography.
// Native app screenshots remain unmodified; see fonts/README.md.
import {readFileSync} from 'node:fs';
const scripts={
 'zh-CN':['Noto Serif SC','Noto Sans SC'],
 'zh-TW':['Noto Serif TC','Noto Sans TC'],
 ja:['Noto Serif JP','Noto Sans JP'],ko:['Noto Serif KR','Noto Sans KR'],
 ar:['Noto Naskh Arabic','Noto Sans Arabic'],
 'hi-IN':['Noto Serif Devanagari','Noto Sans Devanagari'],
 th:['Noto Serif Thai','Noto Sans Thai'],
};
const dir=new URL('./fonts/',import.meta.url);
export function posterFonts(lang){
 const families=scripts[lang]||[];
 const serif=families[0]||(['ru','vi'].includes(lang)?'Source Serif 4':'Poster Charter');
 const sans=['Manrope',...(families[1]?[families[1]]:[])].map(f=>`"${f}"`).join(',');
 const files=['manrope','sourceserif4',...families.map(f=>f.replaceAll(' ','').toLowerCase())];
 let css=`/* ${readFileSync(new URL('charter-LICENSE.txt',dir),'utf8')} */\n@font-face{font-family:"Poster Charter";font-style:normal;font-weight:700;font-display:block;src:url(data:font/woff2;base64,${readFileSync(new URL('charter-bold.woff2',dir)).toString('base64')}) format("woff2");}`;
 for(const slug of files){
  css+=`/* ${readFileSync(new URL(`${slug}-OFL.txt`,dir),'utf8')} */\n`+readFileSync(new URL(`${slug}.css`,dir),'utf8').replace(/url\(([^)]+)\)/g,(_,file)=>`url(data:font/ttf;base64,${readFileSync(new URL(file,dir)).toString('base64')})`);
 }
 return {css,serif:`"${serif}","Source Serif 4"`,sans};
}

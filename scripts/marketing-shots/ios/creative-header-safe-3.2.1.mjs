import {COPY} from './creative-copy-3.2.1.mjs';
import {posterFonts} from './creative-fonts.mjs';
import {brandMark,escapeHTML} from '../brand.mjs';
import {readFileSync} from 'node:fs';

// Named Art Safe Area layer in Apple's official 3840 × 1646 PSD.
// Keep the template evidence and renderer geometry tied to one source.
export const HEADER_TEMPLATE = JSON.parse(readFileSync(new URL('../../../app-store-connect/ios/3.2.1/apple-creative-template-guides.json',import.meta.url),'utf8')).templates.find(t=>t.scene==='header-21x9');
export function safeHeader(locale){
 const c=COPY[locale],font=posterFonts(locale),safe=HEADER_TEMPLATE.safeArea;
 const complex=['ar','th','hi-IN','mr-IN'].includes(locale);
 return `<!doctype html><meta charset="utf-8"><style>${font.css}
 *{box-sizing:border-box}html,body{margin:0;width:3840px;height:1646px;overflow:hidden}
 body{position:relative;font-family:${font.sans};font-synthesis:none;background:radial-gradient(ellipse at 78% 91%,#a245272e,transparent 46%),linear-gradient(120deg,#382335,#251927 80%);color:#fff1d8}
 .sunset{position:absolute;width:4147.2px;height:2962.8px;left:20%;top:9%;background:radial-gradient(ellipse,#ff954845,#f45a1e18 36%,transparent 62%)}
 .art-safe{position:absolute;left:${safe.x}px;top:${safe.y}px;width:${safe.width}px;height:${safe.height}px;padding:48px;display:flex;align-items:center;gap:100px}
 .brand-copy{width:1050px;flex:none;z-index:2;direction:${locale==='ar'?'rtl':'ltr'}}
 .wordmark{font-size:68px;line-height:1.1;margin-bottom:22px;direction:ltr;text-align:${locale==='ar'?'right':'left'}}
 h1{margin:0;font:700 ${['zh-CN','zh-TW','ja'].includes(locale)?142:132}px/${complex?1.4:1.12} ${font.serif};letter-spacing:${complex?0:-1}px}
 h1 span{display:block;white-space:nowrap;word-break:keep-all;hyphens:none}
 .brand-art{width:400px;height:400px;flex:none;filter:drop-shadow(0 14px 12px #140d2170)}.brand-art svg{display:block;width:100%;height:100%}
 </style><body><div class="sunset"></div><div class="art-safe"><div class="brand-copy"><div class="wordmark">DoneAt</div><h1>${c.brand.map(t=>'<span>'+escapeHTML(t)+'</span>').join('')}</h1></div><div class="brand-art">${brandMark('#FFF1D8')}</div></div><script>
 const safe=${JSON.stringify(safe)};
 window.layoutReady=document.fonts.ready.then(()=>{
  const lines=[...document.querySelectorAll('h1 span')],copy=document.querySelector('.brand-copy');
  let n=parseFloat(getComputedStyle(lines[0]).fontSize);
  const fits=()=>lines.every(e=>{const r=document.createRange();r.selectNodeContents(e);return r.getBoundingClientRect().width<=e.getBoundingClientRect().width-4})&&copy.getBoundingClientRect().height<=safe.height-96;
  while(!fits()&&n>72){n-=.5;for(const e of lines)e.style.fontSize=n+'px'}
  if(!fits())throw Error('Brand copy cannot fit official safe area');
 });
 window.layoutAudit=()=>{
  const issues=[],bounds=[],art=document.querySelector('.brand-art').getBoundingClientRect();
  const check=(name,b)=>{const box={x:b.left,y:b.top,width:b.width,height:b.height};bounds.push({name,...box});if(b.left<safe.x||b.top<safe.y||b.right>safe.x+safe.width||b.bottom>safe.y+safe.height)issues.push({issue:'essential artwork outside Apple Art Safe Area',name,box})};
  for(const e of document.querySelectorAll('.wordmark,h1 span')){const r=document.createRange();r.selectNodeContents(e);const b=r.getBoundingClientRect();check(e.textContent,b);if(b.width>e.getBoundingClientRect().width+1)issues.push({issue:'text clips',text:e.textContent});if(b.right>art.left-48)issues.push({issue:'text overlaps mark',text:e.textContent})}
  check('mark including conservative shadow envelope',{left:art.left-36,top:art.top-36,right:art.right+36,bottom:art.bottom+50,width:art.width+72,height:art.height+86});
  return {safeArea:safe,bounds,headlineFontSize:parseFloat(getComputedStyle(document.querySelector('h1 span')).fontSize),issues};
 };
 window.render=async t=>{const p=(t%8)/8,pulse=(1-Math.cos(p*Math.PI*2))/2,spin=Math.max(0,Math.min(1,(t-2.4)/1.6)),ease=spin*spin*(3-2*spin);document.querySelector('.mark path:nth-of-type(2)').setAttribute('transform','rotate('+(360*ease)+' 512 512)');const glow=document.querySelector('.sunset');glow.style.transform='translate('+(-50*pulse)+'px,'+(-32*pulse)+'px) scale('+(1+.06*pulse)+')';glow.style.opacity=.72+.28*pulse;await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))};
 </script></body>`;
}

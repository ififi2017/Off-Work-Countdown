import {readFileSync} from 'node:fs';
export const SEARCH_TEMPLATE=JSON.parse(readFileSync(new URL('../../../app-store-connect/ios/3.2.1/apple-creative-template-guides.json',import.meta.url),'utf8')).templates.find(t=>t.scene==='search-3x2');
// Retain the existing native six-scene tour and timing, constrain its essential art.
export function safeSearch(html,locale){
 const a=SEARCH_TEMPLATE.safeArea,safe={x:a.x/2,y:a.y/2,width:a.width/2,height:a.height/2},pad=24;
 const css=`
 .safe-art{position:absolute;left:${safe.x+pad}px;top:${safe.y+pad}px;width:${safe.width-pad*2}px;height:${safe.height-pad*2}px;overflow:hidden}
 .wordmark{left:0;top:0;font-size:30px;line-height:1.2;letter-spacing:-1px}
 .copy{left:0;top:84px;width:720px}.label{font-size:18px;line-height:1.3}
 h1{font-size:${['zh-CN','zh-TW','ja'].includes(locale)?64:60}px;line-height:${['ar','th','hi-IN','mr-IN'].includes(locale)?1.5:1.25};margin:16px 0}
 .sub{font-size:22px;line-height:1.4;margin:18px 0 14px}.note{font-size:16px;line-height:1.4}
 .timer .copy{left:0;top:46px;width:1036px}.timer h1{font-size:52px;line-height:1.25;margin:12px 0;gap:18px}.timer h1 .line{max-width:calc((100% - 18px)/2)}.timer .sub{margin:12px auto}.timer .note{display:none}
 .widgets .copy{width:660px}.stage{filter:drop-shadow(0 8px 10px #30202c24)}
 .rail{left:0;bottom:0;gap:8px}.rail i{height:5px;width:18px}
 `;
 html=html.replace('</style>',css+'</style>')
 .replace('<div class="wordmark">','<div class="safe-art"><div class="wordmark">')
 .replace('</div><script>','</div></div><script>')
 .replace('const p=ease(u),active=from!==to', 'const p=ease((u-.24)/.52),active=from!==to')
 .replace('const q=active?ease((u-n*.025)/.88):0;', 'const q=active?ease(i===from?u/.24:(u-.76)/.24):0;node.style.opacity=active?(i===from?(u<.24?1:0):(u>.76?1:0)):1;')
 .replace('[[180,660,1560,532,58,0],[1090,280,710,650,66,0],...[2,3,4,5].map(()=>[1230,90,555,555*3000/1470,80,1])]','[[128,200,780,780*450/1320,32,0],[700,95,330,330*768/840,32,0],...[2,3,4,5].map(()=>[806,20,210,210*3000/1470,30,1])]');
 if(html.includes('const boxes=[[180'))throw Error('Legacy search geometry was not replaced');
 return html+`<script>
 const officialSafe=${JSON.stringify(safe)};
 window.layoutAudit=()=>{
  const issues=[],bounds=[],safe=officialSafe,stage=document.querySelector('.stage').getBoundingClientRect();
  const check=(name,b)=>{if(b.right<=b.left||b.bottom<=b.top)return;bounds.push({name,x:b.left,y:b.top,width:b.right-b.left,height:b.bottom-b.top});if(b.left<safe.x-.5||b.top<safe.y-.5||b.right>safe.x+safe.width+.5||b.bottom>safe.y+safe.height+.5)issues.push({issue:'essential content outside Apple search safe area',name});};
  check('native media/device',stage);check('brand',document.querySelector('.wordmark').getBoundingClientRect());check('scene rail',document.querySelector('.rail').getBoundingClientRect());
  let minHeadline=Infinity;
  for(const s of [...document.querySelectorAll('.scene')].filter(s=>s.style.visibility==='visible'))for(const e of s.querySelectorAll('.ink')){
   if(!e.getClientRects().length||e.style.opacity==='0')continue;const r=document.createRange();r.selectNodeContents(e);const b=r.getBoundingClientRect(),line=e.parentElement.getBoundingClientRect();
   if(b.width>line.width+1)issues.push({issue:'text clipping',text:e.textContent});
   const visible={left:Math.max(b.left,line.left),right:Math.min(b.right,line.right),top:Math.max(b.top,line.top),bottom:Math.min(b.bottom,line.bottom)};check(e.textContent,visible);
   if(visible.bottom>visible.top&&visible.right>visible.left){if(s.classList.contains('timer')){if(visible.bottom>stage.top-8)issues.push({issue:'opening copy overlaps native countdown'});}else if(visible.right>stage.left-10)issues.push({issue:'copy overlaps native device',text:e.textContent});}
   if(e.closest('h1'))minHeadline=Math.min(minHeadline,parseFloat(getComputedStyle(e).fontSize));
  }
  if(minHeadline<28)issues.push({issue:'headline too small',minHeadline});return{safeArea:safe,bounds,minHeadline,issues};
 };
 const nativeRender=window.render;window.validatedFrames=0;window.render=async t=>{await nativeRender(t);const audit=layoutAudit();if(audit.issues.length)throw Error(JSON.stringify({time:t,audit}));window.validatedFrames++};
 </script>`;
}

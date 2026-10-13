// Persistent renderer for repository-owned marketing HTML; bounded memory, one encoder.
import {spawn} from 'node:child_process';
import {mkdtempSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {once} from 'node:events';
// IOS_SHOTS_RENDER_PORT lets several renderers run side by side.
export async function renderer(){
 const port=process.env.IOS_SHOTS_RENDER_PORT||'9497';
 const profile=mkdtempSync(join(tmpdir(),'doneat-all-locale-render-'));
 const chrome=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--disable-gpu',`--remote-debugging-port=${port}`,'--hide-scrollbars','--force-color-profile=srgb','--allow-file-access-from-files','--disable-background-networking','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows','--disable-features=MacAppCodeSignClone',`--user-data-dir=${profile}`,'about:blank'],{stdio:'ignore'});
 let ws,seq=0;const pending=new Map();
 try{
  let endpoint;for(let i=0;i<80&&!endpoint;i++){try{endpoint=(await(await fetch(`http://127.0.0.1:${port}/json/version`)).json()).webSocketDebuggerUrl}catch{await new Promise(r=>setTimeout(r,250));}}
  if(!endpoint)throw Error('Local renderer unavailable');ws=new WebSocket(endpoint);await once(ws,'open');
  ws.addEventListener('message',e=>{const d=JSON.parse(e.data),p=pending.get(d.id);if(p){pending.delete(d.id);clearTimeout(p.timer);d.error?p.reject(Error(d.error.message)):p.resolve(d.result)}});
  const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++seq,timer=setTimeout(()=>{pending.delete(id);reject(Error(method+' timeout'))},60000);pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params,sessionId}))});
  const{targetId}=await send('Target.createTarget',{url:'about:blank'}),{sessionId}=await send('Target.attachToTarget',{targetId,flatten:true});
  const call=(method,params)=>send(method,params,sessionId);await call('Page.enable');
  const evaluate=async expression=>{const r=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;};
  const load=async(path,width,height)=>{await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await call('Page.navigate',{url:pathToFileURL(path).href});for(let i=0;i<100;i++){if(await evaluate('location.href==='+JSON.stringify(pathToFileURL(path).href)+'&&document.readyState==="complete"'))break;await new Promise(r=>setTimeout(r,100))}await evaluate(`document.fonts.ready.then(()=>Promise.all([...document.images].map(i=>i.decode()))).then(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))))`);};
  const grab=async(format='png')=>Buffer.from((await call('Page.captureScreenshot',{format,...(format==='jpeg'?{quality:96}:{}),fromSurface:true})).data,'base64');
  return {load,evaluate,grab,async still(path,html,width,height,out){writeFileSync(path,html);await load(path,width,height);await evaluate('window.layoutReady||Promise.resolve()');await new Promise(r=>setTimeout(r,300));const audit=await evaluate('window.layoutAudit?layoutAudit():null');writeFileSync(out,await grab());return audit;},async close(){if(ws)ws.close();if(chrome.exitCode===null){const done=once(chrome,'close');chrome.kill();await done;}rmSync(profile,{recursive:true,force:true});}};
 }catch(e){if(ws)ws.close();chrome.kill();rmSync(profile,{recursive:true,force:true});throw e;}
}

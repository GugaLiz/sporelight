import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {get as httpGet} from 'node:http';
import {get as httpsGet} from 'node:https';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(name,fallback)=>process.argv.find(value=>value.startsWith('--'+name+'='))?.slice(name.length+3)??fallback;
const {chromium}=createRequire(import.meta.url)(option('playwright',join(process.env.USERPROFILE??'','.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')));
const output=resolve(root,option('output','docs/qa-godot-migration/performance'));
const qa=option('qa','1')!=='0';
const level=option('level','1-1');
const buildUrl=new URL('/__build.json',option('url','http://localhost:4185/'));
const build=await new Promise((resolve,reject)=>{
 (buildUrl.protocol==='https:'?httpsGet:httpGet)(buildUrl,response=>{
  let body='';response.setEncoding('utf8');response.on('data',chunk=>body+=chunk);
  response.on('error',reject);response.on('end',()=>{
   try{if(response.statusCode!==200)throw Error('Build metadata HTTP '+response.statusCode);resolve(JSON.parse(body));}catch(error){reject(error);}
  });
 }).on('error',reject);
});
const fixture=JSON.parse(await readFile(join(root,'godot/tests/fixtures/reference.json'),'utf8'));
const initial=fixture.cases.find(entry=>entry.name==='authored/'+level).initial.snapshot;
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});
if(!qa){
 const origin=new URL(option('url','http://localhost:4185/')).origin;
 await context.route(url=>url.origin===origin&&['/','/index.html'].includes(url.pathname),async route=>{
  const response=await route.fetch();const html=await response.text();
  if(!html.includes('"args":[]'))throw Error('Export bootstrap args not found');
  await route.fulfill({response,body:html.replace('"args":[]','"args":'+JSON.stringify(['--','--level='+level]))});
 });
}
const page=await context.newPage();
const errors=[],samples=[];
let environment=null;
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
const percentile=(values,fraction)=>values[Math.min(values.length-1,Math.floor(values.length*fraction))];
await mkdir(output,{recursive:true});
let failure=null;
try{
 const url=new URL(option('url','http://localhost:4185/'));if(qa)url.searchParams.set('qa','1');
 await page.goto(url.href,{waitUntil:'networkidle'});
 if(qa)await page.waitForFunction(()=>window.__sporelightState?.character);
 else await page.waitForFunction(()=>!document.querySelector('#status'));
 environment=await page.evaluate(()=>{
  const gl=document.querySelector('#canvas').getContext('webgl2');
  const debug=gl?.getExtension('WEBGL_debug_renderer_info');
  return {userAgent:navigator.userAgent,hardwareConcurrency:navigator.hardwareConcurrency,dpr:devicePixelRatio,screen:[screen.width,screen.height],renderer:debug?gl.getParameter(debug.UNMASKED_RENDERER_WEBGL):null};
 });
 await page.screenshot({path:join(output,'initial.png')});
 for(const [width,height]of [[1280,720],[1920,1080]]){
  await page.setViewportSize({width,height});
  await page.waitForFunction(([w,h])=>document.querySelector('#canvas').width===w&&document.querySelector('#canvas').height===h,[width,height]);
  if(qa)await page.evaluate(snapshot=>{
   window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot}));
   window.__sporelightRequest(JSON.stringify({type:'action',command:'resume'}));
  },initial);
  await page.waitForTimeout(1000);
  for(const mode of ['idle','walking']){
   const before=qa?await page.evaluate(()=>window.__sporelightState.revision):null;
   const capture=page.evaluate(()=>new Promise(resolve=>{
    const times=[],telemetry=[];let last=null,start=null;
    function frame(now){
     if(start===null)start=now;
     if(last!==null)times.push(now-last);
     last=now;
     if(window.__sporelightState&&(telemetry.length===0||now-telemetry.at(-1).at>200))telemetry.push({at:now,moving:window.__sporelightState.moving,position:window.__sporelightState.native?.actors?.luvie?.position,...window.__sporelightState.performance});
     if(now-start<4000)requestAnimationFrame(frame);else resolve({times,telemetry});
    }
    requestAnimationFrame(frame);
   }));
   if(mode==='walking'){
    for(let index=0;index<6;index++){
     const key=index%2===0?'ArrowLeft':'ArrowRight';
     await page.keyboard.down(key);
     try{await page.waitForTimeout(600);}finally{await page.keyboard.up(key);}
    }
   }
   const data=await capture;
   const after=qa?await page.evaluate(()=>window.__sporelightState.revision):null;
   const positions=data.telemetry.map(sample=>sample.position).filter(Boolean);
   const travelled=positions.slice(1).reduce((sum,p,i)=>sum+Math.hypot(p[0]-positions[i][0],p[2]-positions[i][2]),0);
   if(qa&&mode==='walking'&&(travelled<0.5||!data.telemetry.some(sample=>sample.moving)))throw Error('Continuous walking workload did not execute');
   const values=data.times.slice().sort((a,b)=>a-b);
   samples.push({width,height,mode,commands:qa?after-before:null,travelled:qa?travelled:null,frames:values.length,medianMs:percentile(values,.5),p95Ms:percentile(values,.95),p99Ms:percentile(values,.99),maxMs:values.at(-1),over33ms:values.filter(value=>value>33.4).length,...data});
  }
 }
 if(errors.length)throw Error('Browser reported errors');
}catch(error){failure=String(error);process.exitCode=1;}
finally{
 const budget={targetP95Ms:16.7,meetsTarget:samples.length===4&&samples.every(sample=>sample.p95Ms<=16.7)};
 await writeFile(join(output,'checks.json'),JSON.stringify({passed:!failure,completedWithoutErrors:!failure,budget,date:new Date().toISOString(),browser:browser.version(),environment,build,qa,level,startupArgs:!qa?['--','--level='+level]:[],scope:'passed means collection completed without errors, not a frame-budget pass. Single host, headless Chrome; rAF pacing is not GPU timing or device certification. Walking holds alternating directions for 600ms; qa=false omits telemetry verification. Release uses the existing CLI entry via a test-only bootstrap override.',samples,errors,failure},null,2)+'\n');
 console.log(JSON.stringify({passed:!failure,samples:samples.map(({times,telemetry,...sample})=>sample),errors,failure,output}));
 await context.close();await browser.close();
}

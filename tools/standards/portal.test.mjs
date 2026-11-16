import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {readFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {createStandardsPortal,isLocalRequest,localStandardsPlugin} from './portal.mjs';

const projectRoot=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const request=(overrides={})=>({url:'/__standards/data.json',method:'GET',headers:{host:'localhost:4222'},socket:{remoteAddress:'127.0.0.1'},...overrides});
const document='<html><body><canvas id="canvas"></canvas></body></html>';
async function dispatch(portal,req){
 const result={};
 const response={writeHead(status,headers){Object.assign(result,{status,headers});return this;},end(body){result.body=body??Buffer.alloc(0);return this;}};
 result.handled=await portal.handle(req,response);
 return result;
}

test('local entry injection is idempotent and changes only the served string',async()=>{
 const portal=createStandardsPortal({projectRoot});
 const file=resolve(projectRoot,'godot/build/element-library-20261115-release/index.html');
 const original=await readFile(file,'utf8');
 const html=portal.inject(original,request({url:'/'}));
 assert.equal(html.includes('data-sporelight-standards'),true);
 assert.equal(html.includes('/__standards/entry.js'),true);
 assert.equal(portal.inject(html,request({url:'/'})),html);
 assert.equal(await readFile(file,'utf8'),original);
 assert.equal(original.includes('data-sporelight-standards'),false);
 assert.equal(portal.inject(document,request({url:'/__standards/'})),document,'handbook HTML has no launcher back to itself');
 assert.equal(portal.inject(document,request({url:'/__standards/index.html'})),document,'explicit handbook index has no duplicate launcher');
});

test('off mode removes the entry and all portal routes',async()=>{
 const portal=createStandardsPortal({projectRoot,enabled:false});
 assert.equal(portal.inject(document,request({url:'/'})),document);
 for(const url of ['/__standards','/__standards/','/__standards/data.json','/__standards/entry.js','/__standards/assets/flower']){
  const result=await dispatch(portal,request({url}));
  assert.equal(result.handled,true);assert.equal(result.status,404,url);
 }
});

test('public hosts, remote peers and forwarded requests cannot read or inject',async()=>{
 const portal=createStandardsPortal({projectRoot});
 const cases=[
  request({headers:{host:'sporelight.example'}}),
  request({headers:{host:'localhost.example'}}),
  request({headers:{host:'127.0.0.1.example'}}),
  request({headers:{host:'localhost'},socket:{remoteAddress:'192.168.1.15'}}),
  request({headers:{host:'localhost',forwarded:'for=203.0.113.10;host=public.example'}}),
  request({headers:{host:'localhost','x-forwarded-host':'public.example'}}),
  request({headers:{host:'localhost','x-forwarded-for':'203.0.113.10'}}),
  request({headers:{host:'localhost','x-forwarded-proto':'https'}}),
  request({headers:{host:'localhost','x-real-ip':'203.0.113.10'}}),
 ];
 for(const req of cases){
  assert.equal(isLocalRequest(req),false,JSON.stringify(req.headers));
  assert.equal(portal.inject(document,{...req,url:'/'}),document);
  assert.equal((await dispatch(portal,req)).status,404);
 }
 for(const [host,address] of [['localhost:4222','127.0.0.1'],['127.0.0.1:4222','::ffff:127.0.0.1'],['[::1]:4222','::1']]){
  assert.equal(isLocalRequest(request({headers:{host},socket:{remoteAddress:address}})),true);
 }
});

test('Vite integration is a development middleware only',()=>{
 const plugin=localStandardsPlugin(projectRoot);
 assert.equal(plugin.apply,'serve');
 assert.equal(typeof plugin.configureServer,'function');
 assert.equal(plugin.configurePreviewServer,undefined);
 assert.equal(plugin.generateBundle,undefined);
 assert.equal(plugin.transformIndexHtml,undefined);
});

test('data contains the twelve real levels, eight current documents and registered image aliases',async()=>{
 const portal=createStandardsPortal({projectRoot});
 const result=await dispatch(portal,request());
 assert.equal(result.status,200);
 assert.equal(result.headers['Cache-Control'],'no-store');
 assert.match(result.headers['Content-Security-Policy'],/default-src 'none'/);
 const data=JSON.parse(result.body);
 assert.deepEqual(data.inventory.levels.map(level=>level.level_id),['1-1','1-2','1-3','1-4','2-1','2-2','2-3','2-4','3-1','3-2','3-3','3-4']);
 assert.equal(data.documents.length,8);
 for(const doc of data.documents)assert.equal(doc.body,await readFile(resolve(projectRoot,doc.path),'utf8'),doc.id);
 assert.equal(data.assets.flower,'/__standards/assets/flower');
 const image=await dispatch(portal,request({url:data.assets.flower}));
 assert.equal(image.status,200);assert.match(image.headers['Content-Type'],/^image\//);
 const file=data.inventory.definitions.resources.flower.replace('res://','godot/');
 assert.deepEqual(image.body,await readFile(resolve(projectRoot,file)));
});

test('routing is allowlisted and never exposes arbitrary source files',async()=>{
 const portal=createStandardsPortal({projectRoot});
 for(const url of ['/__standards/portal.mjs','/__standards/%2e%2e%2fportal.mjs','/__standards/assets/unknown','/__standards/assets/%2e%2e%2fcontent/levels.json','/__standards/constructor','/__standards/assets/toString']){
  const response=await dispatch(portal,request({url}));
  assert.equal(response.handled,true);assert.equal(response.status,404,url);
  assert.doesNotMatch(String(response.body),/class_name|projectRoot|C:\\Users/);
 }
 assert.equal((await dispatch(portal,request({url:'/unrelated'}))).handled,false);
 const redirect=await dispatch(portal,request({url:'/__standards'}));
 assert.equal(redirect.status,302);assert.equal(redirect.headers.Location,'/__standards/');
});

test('GET and HEAD are read-only; writes and unknown assets fail explicitly',async()=>{
 const portal=createStandardsPortal({projectRoot});
 const get=await dispatch(portal,request({url:'/__standards/assets/flower'}));
 const head=await dispatch(portal,request({url:'/__standards/assets/flower',method:'HEAD'}));
 assert.equal(head.status,200);assert.equal(head.body.length,0);
 assert.equal(head.headers['Content-Length'],get.body.length);
 for(const method of ['POST','PUT','PATCH','DELETE'])assert.equal((await dispatch(portal,request({method}))).status,405);
 const invalid=await dispatch(portal,request({url:'/__standards/assets/not-real'}));
 assert.equal(invalid.status,404);
});

test('actual preview server serves a local entry and disables it with --standards=off',async(t)=>{
 const reserve=http.createServer();reserve.listen(0,'127.0.0.1');await once(reserve,'listening');
 const port=reserve.address().port;await new Promise(done=>reserve.close(done));
 const path=resolve(projectRoot,'godot/build/element-library-20261115-release/index.html');
 const original=await readFile(path,'utf8');
 for(const off of [false,true]){
  const args=['tools/godot-migration/serve-preview.mjs','--variant=element-library-20261115-release','--port='+port];
  if(off)args.push('--standards=off');
  const child=spawn(process.execPath,args,{cwd:projectRoot,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let log='';child.stdout.on('data',bytes=>log+=bytes);child.stderr.on('data',bytes=>log+=bytes);
  t.after(()=>{if(child.exitCode===null)child.kill();});
  const stopped=once(child,'exit');
  try{
   for(let i=0;i<100&&!log.includes('preview:');i++){assert.equal(child.exitCode,null,log);await delay(30);}
   assert.match(log,/preview:/);
   const response=await fetch(`http://127.0.0.1:${port}/`);
   const html=await response.text();
   assert.equal(response.status,200);
   assert.equal(Number(response.headers.get('content-length')),Buffer.byteLength(html));
   assert.equal(html.includes('data-sporelight-standards'),!off);
   if(off)assert.equal(html,original);
   assert.equal((await fetch(`http://127.0.0.1:${port}/__standards/data.json`)).status,off?404:200);
   assert.equal(await readFile(path,'utf8'),original);
  }finally{child.kill();await stopped;}
 }
});

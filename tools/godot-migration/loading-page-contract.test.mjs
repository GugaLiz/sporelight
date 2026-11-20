import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';

const shell=await readFile(new URL('../../godot/web/loading-shell.html',import.meta.url),'utf8');
const page=await readFile(new URL('../../godot/web/loading/loading-page.js',import.meta.url),'utf8');
const origin='http://localhost:4223';
const protocol='sporelight-loading-v1';

function element(){
 const listeners={};const attrs={};
 return {listeners,attrs,dataset:{},hidden:false,inert:false,isConnected:true,textContent:'',
  classList:{add(){},remove(){}},setAttribute(k,v){attrs[k]=v;},getAttribute(k){return attrs[k]??null;},
  removeAttribute(k){delete attrs[k];if(k==='value')delete this.value;if(k==='max')delete this.max;},
  addEventListener(k,f){(listeners[k]??=[]).push(f);},emit(k,...args){return listeners[k]?.map(f=>f(...args));},
  remove(){this.isConnected=false;},focus(){this.focused=true;},blur(){this.focused=false;}};
}
function shellHarness({portrait=false}={}){
 const nodes=Object.fromEntries(['status','canvas','loading-page','loading-fallback','rotate-screen','fallback-message','fallback-retry'].map(k=>[k,element()]));
 nodes.canvas.setAttribute('aria-busy','true');
 const sent=[];const remote={postMessage:(data,target)=>sent.push({data,target})};
 nodes['loading-page'].contentWindow=remote;
 nodes['loading-page'].contentDocument={getElementById:()=>({dataset:{scriptReady:'true'}})};
 const window=element();let reloads=0;const raf=[];const timers=[];let progress;let resolveGame;let rejectGame;let bootstrap;
 Object.assign(window,{location:{origin,reload(){reloads++;}},innerWidth:portrait?390:1280,innerHeight:portrait?844:720,
  matchMedia:q=>({matches:q.includes('coarse')&&portrait,addEventListener(){}}),setTimeout:f=>timers.push(f)});
 const document={getElementById:k=>nodes[k],createElement:()=>element(),body:{appendChild:v=>{bootstrap=v;}}};
 class Engine{static getMissingFeatures(){return [];}startGame(o){progress=o.onProgress;return new Promise((r,j)=>{resolveGame=r;rejectGame=j;});}}
 const source=shell.match(/<script>([\s\S]*?)<\/script>/)[1].replace('$GODOT_CONFIG','{}').replace('$GODOT_THREADS_ENABLED','false').replace('$GODOT_URL','index.js');
 vm.runInNewContext(source,{window,document,Engine,navigator:{maxTouchPoints:portrait?1:0},requestAnimationFrame:f=>raf.push(f),console:{error(){}}});
 return {nodes,window,sent,remote,raf,timers,get reloads(){return reloads;},start(){bootstrap.emit('load');},progress:(...args)=>progress(...args),resolve:()=>resolveGame(),reject:e=>rejectGame(e),message:(data,{source=remote,eventOrigin=origin}={})=>window.emit('message',{data,source,origin:eventOrigin})};
}
function viewHarness({embedded=true}={}){
 const nodes=Object.fromEntries(['loading-view','status-progress','load-percent','loading-label','status-caption','status-notice','progress-region','error-details','retry-button'].map(k=>[k,element()]));
 const line=element();const window=element();const sent=[];let reloads=0;
 const parent={postMessage:(data,target)=>sent.push({data,target})};
 Object.assign(window,{location:{origin,reload(){reloads++;}},parent:embedded?parent:window});
 const document={getElementById:k=>nodes[k],querySelector:()=>line};
 vm.runInNewContext(page,{window,document});
 return {nodes,line,sent,parent,window,get reloads(){return reloads;},message:(state,{source=parent,eventOrigin=origin}={})=>window.emit('message',{data:{protocol,type:'state',...state},source,origin:eventOrigin})};
}
const flush=()=>new Promise(resolve=>setImmediate(resolve));

test('standalone page stays indeterminate and does not invent download progress',()=>{
 const h=viewHarness({embedded:false});
 assert.equal(h.sent.length,0);
 h.message({phase:'downloading',current:75,total:100});
 assert.equal(h.nodes['load-percent'].textContent,'');
 assert.equal(h.nodes['status-progress'].value,undefined);
});
test('frame accepts progress only from its same-origin parent and renders real bytes',()=>{
 const h=viewHarness();
 assert.deepEqual(JSON.parse(JSON.stringify(h.sent)),[{data:{protocol,type:'ready'},target:origin}]);
 h.message({phase:'downloading',current:321,total:1000},{eventOrigin:'https://untrusted.invalid'});
 h.message({phase:'downloading',current:321,total:1000},{source:{}});
 assert.equal(h.nodes['load-percent'].textContent,'');
 h.message({phase:'downloading',current:321,total:1000});
 assert.equal(h.nodes['load-percent'].textContent,'32%');
 assert.equal(h.nodes['status-progress'].value,321);
 h.message({phase:'preparing',current:0,total:0});
 assert.equal(h.nodes['status-progress'].value,undefined);
 assert.equal(h.nodes['load-percent'].textContent,'');
});
test('downloaded is distinct from ready; error uses text and retry reaches trusted parent',()=>{
 const h=viewHarness();
 h.message({phase:'opening',current:100,total:100});
 assert.equal(h.nodes['load-percent'].textContent,'100%');
 assert.equal(h.nodes['loading-view'].getAttribute('aria-busy'),'true');
 assert.match(h.nodes['loading-label'].textContent,/唤醒/);
 h.message({phase:'error',message:'<script>bad</script>'});
 assert.equal(h.nodes['error-details'].textContent,'<script>bad</script>');
 assert.equal(h.nodes['status-notice'].hidden,false);
 assert.equal(h.nodes['retry-button'].focused,true);
 h.nodes['retry-button'].emit('click');
 assert.equal(h.sent.at(-1).data.type,'retry');
 assert.equal(h.sent.at(-1).target,origin);
});
test('shell buffers latest progress before frame ready and rejects unrelated messages',()=>{
 const h=shellHarness();h.start();h.progress(512,1024);
 assert.equal(h.sent.length,0);
 h.message({protocol,type:'ready'},{source:{}});
 h.message({protocol,type:'ready'},{eventOrigin:'https://untrusted.invalid'});
 assert.equal(h.sent.length,0);
 h.message({protocol,type:'ready'});
 assert.equal(h.sent.at(-1).data.current,512);
 assert.equal(h.sent.at(-1).target,origin);
 h.progress(1024,1024);
 assert.equal(h.nodes.status.dataset.phase,'opening');
 assert.equal(h.nodes.status.isConnected,true);
 assert.equal(h.nodes.canvas.getAttribute('aria-busy'),'true');
});
test('ready reveals canvas after two display frames; portrait guide waits until game ready',async()=>{
 const h=shellHarness({portrait:true});h.start();
 assert.equal(h.nodes['rotate-screen'].hidden,true);
 h.resolve();await flush();
 assert.equal(h.raf.length,1);
 assert.equal(h.nodes.canvas.getAttribute('aria-busy'),'true');
 h.raf.shift()();assert.equal(h.nodes.canvas.getAttribute('aria-busy'),'true');
 h.raf.shift()();assert.equal(h.nodes.canvas.getAttribute('aria-busy'),'false');
 assert.equal(h.nodes['rotate-screen'].hidden,false);
 h.timers.shift()();assert.equal(h.nodes.status.isConnected,false);
 assert.notEqual(h.nodes.canvas.focused,true);
});
test('engine error before frame readiness survives late handshake and retry reloads original URL',async()=>{
 const h=shellHarness();h.start();h.reject(new Error('PCK download failed'));await flush();
 assert.equal(h.nodes.status.dataset.phase,'error');
 assert.equal(h.nodes['loading-fallback'].hidden,false);
 h.message({protocol,type:'ready'});
 assert.equal(h.sent.at(-1).data.phase,'error');
 assert.equal(h.nodes['loading-fallback'].hidden,true);
 h.message({protocol,type:'retry'});
 assert.equal(h.reloads,1);
});
test('frame load replays state even when ready event was missed',()=>{
 const h=shellHarness();h.start();h.progress(0,100);
 h.nodes['loading-page'].emit('load');
 assert.equal(h.sent.at(-1).data.current,0);
 assert.equal(h.sent.at(-1).data.total,100);
});

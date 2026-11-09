import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(name,fallback)=>process.argv.find(v=>v.startsWith('--'+name+'='))?.slice(name.length+3)??fallback;
const base=option('base','http://localhost:4185/');
const output=resolve(option('output',resolve(tmpdir(),'sporelight-godot-web-motion')));
const video=option('video','0')==='1';
const {chromium}=createRequire(import.meta.url)(option('playwright',process.env.PLAYWRIGHT_MODULE??'C:/Users/jeffrey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'));
const reference=JSON.parse(await readFile(resolve(root,'godot/tests/fixtures/reference.json'),'utf8'));
const initial=id=>structuredClone(reference.cases.find(c=>c.name==='authored/'+id).initial.snapshot);
const room=()=>{const s=initial('2-2');s.actors={luvie:'f:4:2',buddy:'f:4:2'};s.follow=false;return s;};
const errors=[],cases=[],events=[];
let errorEvents=0,currentCase='',build=null;
const error=value=>{errorEvents++;if(!errors.includes(value))errors.push(value);};
await mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true});
// Time-sensitive input runs without an encoder. Optional video is a separate route demonstration.
const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1});
await context.route('**/favicon.ico',route=>route.fulfill({status:204,body:''}));
await context.addInitScript(()=>{
 window.__motionTrack={caseName:'',samples:[],publicationSamples:[],keys:[]};
 const summarize=s=>{
  const m=s.motion??{},c=s.character??{};
  return {wallMs:performance.now(),moving:s.moving,paused:s.paused,revision:s.revision,level:s.snapshot?.levelId,actors:s.snapshot?.actors,message:s.message,
   scale:s.scale,origin:s.origin,motion:{kind:m.kind??'',elapsed:m.elapsed??0,duration:m.duration??0,from:m.before?.actors?.luvie??'',to:m.after?.actors?.luvie??'',sharedFrom:m.before?.actors?.luvie===m.before?.actors?.buddy,sharedTo:m.after?.actors?.luvie===m.after?.actors?.buddy},
   input:structuredClone(s.input??{}),character:{key:c.key,facing:c.facing,walk_started:c.walk_started,moving:c.moving,stop_blend_active:c.stop_blend_active,stop_progress:c.stop_progress,weight:c.weight,from_key:c.from_key,to_key:c.to_key,footpoint:c.footpoint,screen_footpoint:c.screen_footpoint,pose:c.pose},
   performance:structuredClone(s.performance??{})};
 };
 // Capture every diagnostic publication before a busy browser can overwrite it.
 // These may include intermediate controller states; timer samples remain the
 // independent observations used for movement continuity checks.
 let publishedState=window.__sporelightState;
 Object.defineProperty(window,'__sporelightState',{
  configurable:true,enumerable:true,get:()=>publishedState,
  set(value){
   publishedState=value;
   const track=window.__motionTrack;
   if(value&&track.caseName)track.publicationSamples.push(summarize(value));
  }
 });
 for(const type of ['keydown','keyup'])window.addEventListener(type,event=>{
  const track=window.__motionTrack,s=window.__sporelightState;if(!track.caseName)return;
  track.keys.push({type,key:event.key,repeat:event.repeat,trusted:event.isTrusted,wallMs:performance.now(),moving:s?.moving,revision:s?.revision,elapsed:s?.motion?.elapsed});
 },true);
 setInterval(()=>{
  const s=window.__sporelightState,track=window.__motionTrack;if(!s||!track.caseName)return;
  track.samples.push(summarize(s));
 },50);
});
const page=await context.newPage();
page.on('pageerror',value=>error(value.message));
page.on('console',message=>{if(message.type()==='error')error(message.text());});
page.on('response',response=>{if(response.status()>=400&&!response.url().endsWith('/favicon.ico'))error(response.status()+' '+response.url());});
const state=()=>page.evaluate(()=>structuredClone(window.__sporelightState));
const request=payload=>page.evaluate(value=>window.__sporelightRequest(JSON.stringify(value)),payload);
const wait=async(predicate,arg,timeout=7000)=>page.waitForFunction(predicate,arg,{timeout,polling:5});
const waitStable=async(tile,revision)=>wait(({tile,revision})=>{const s=window.__sporelightState;return s&&!s.moving&&s.snapshot.actors.luvie===tile&&s.revision===revision;},{tile,revision});
async function event(kind,key){
 events.push({caseName:currentCase,kind,key,hostMs:performance.now()});
 if(kind==='down')await page.keyboard.down(key);else if(kind==='up')await page.keyboard.up(key);else await page.keyboard.press(key);
}
async function release(){
 for(const key of ['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','e'])await page.keyboard.up(key);
}
async function load(snapshot){
 await release();
 await request({type:'snapshot',snapshot,time:1200});
 await wait(expected=>{const s=window.__sporelightState;return s&&!s.moving&&s.revision===0&&s.snapshot.levelId===expected.levelId&&s.snapshot.actors.luvie===expected.actors.luvie;},snapshot);
 // Snapshot setup deliberately freezes the visual clock; resume it before testing real animation.
 await request({type:'action',command:'resume'});
 await page.waitForTimeout(80);
}
async function begin(name){
 currentCase=name;
 await page.evaluate(name=>{window.__motionTrack={caseName:name,samples:[],publicationSamples:[],keys:[]};},name);
}
async function finish(extra={},validate=()=>{}){
 await page.waitForTimeout(180);
 const record=await page.evaluate(()=>{const t=window.__motionTrack;t.caseName='';return {samples:t.samples,publicationSamples:t.publicationSamples,keys:t.keys,state:structuredClone(window.__sporelightState)};});
 const result={name:currentCase,passed:true,...extra,samples:record.samples,publicationSamples:record.publicationSamples,keys:record.keys,final:record.state};
 validate(result);
 cases.push(result);
 await writeFile(resolve(output,currentCase+'.json'),JSON.stringify(result,null,2));
 console.log('PASS '+currentCase);
 return result;
}
async function button(match){
 const s=await state();
 const found=s.buttons.find(b=>!b.disabled&&!b.clipped&&(typeof match==='string'?b.text===match:b.text.includes(match.includes)));
 assert.ok(found,'Visible enabled button '+JSON.stringify(match));
 const canvas=await page.locator('#canvas').boundingBox();
 const backing=await page.locator('#canvas').evaluate(c=>({width:c.width,height:c.height}));
 await page.mouse.click(canvas.x+(found.x+found.width/2)*canvas.width/backing.width,canvas.y+(found.y+found.height/2)*canvas.height/backing.height);
}
async function activeStep(){
 await wait(()=>{const s=window.__sporelightState,m=s?.motion;return s?.moving&&m?.kind==='move'&&m.elapsed>=0.04&&m.elapsed<0.12;});
}
function footEqual(a,b){return a&&b&&a.x===b.x&&a.z===b.z&&a.h===b.h;}

try{
 const url=new URL(base);url.searchParams.set('qa','1');
 await page.goto(url.href,{waitUntil:'networkidle',timeout:120000});
 await wait(()=>typeof window.__sporelightRequest==='function'&&window.__sporelightState?.snapshot,undefined,120000);
 build=await page.evaluate(async()=>{const r=await fetch('/__build.json',{cache:'no-store'});if(!r.ok)throw Error('Missing build fingerprint');return r.json();});
 await writeFile(resolve(output,'build.json'),JSON.stringify(build,null,2));
 const diagnostics=await state();
 assert.ok('character' in diagnostics&&'motion' in diagnostics&&'input' in diagnostics,'New debug motion/input/character diagnostics are required');
 assert.equal(diagnostics.continuousInput,true,'Normal movement continues while a direction is held');
 assert.equal(diagnostics.safeCamera,false,'Restoring continuous movement does not change the camera');

 await load(room());await begin('released-tap-chain');
 await event('press','ArrowLeft');
 // Keep the real tap rhythm independent of diagnostic polling round trips.
 await new Promise(resolve=>setTimeout(resolve,80));
 await event('press','ArrowLeft');
 const secondTap=await page.evaluate(()=>window.__motionTrack.keys.filter(key=>key.type==='keydown'&&key.key==='ArrowLeft'&&!key.repeat)[1]);
 assert.ok(secondTap?.trusted&&secondTap.moving&&secondTap.revision===0&&secondTap.elapsed>=0.045&&secondTap.elapsed<0.205,'The second real Left tap must reach the first uncommitted movement within its buffer window; early or late scheduling cannot count as a buffered chain');
 await wait(()=>{const s=window.__sporelightState;return s?.moving&&s.revision===1&&s.motion?.after?.actors?.luvie==='f:2:2';});
 await waitStable('f:2:2',2);
 await wait(()=>window.__sporelightState?.character?.stop_blend_active===false&&window.__sporelightState?.character?.stop_progress===1);
 const stopped=await state();
 assert.equal(stopped.character.stop_blend_active,false);
 assert.equal(stopped.character.stop_progress,1);
 assert.ok(footEqual(stopped.character.footpoint,{x:2,z:2,h:0}),'Stopped foot remains at the committed logical tile');
 await page.screenshot({path:resolve(output,'tap-chain-idle.png')});
 await finish({bufferWindowMs:160},chain=>{
  const moving=chain.samples.filter(s=>s.moving&&s.character.moving);
  assert.ok(moving.length>=3,'Moving frames were sampled');
  assert.ok(moving.some(s=>s.revision===0)&&moving.some(s=>s.revision===1),'Both motion segments have real samples; continuity checks are not vacuously true');
  assert.ok(new Set(moving.map(s=>s.character.key)).size>=2,'The resumed visual clock advances actual walk frames');
  assert.ok(moving.every(s=>s.character.facing==='left'&&['walk-3','walk-4','walk-5'].includes(s.character.key)),'Side walking never flashes front-facing frames');
  assert.equal(new Set(moving.map(s=>s.character.walk_started)).size,1,'The linked segment preserves its walk phase clock');
  for(const s of moving){
   const p=Math.min(1,Math.max(0,s.motion.elapsed/s.motion.duration)),f=s.character.footpoint;
   const offset=8*((s.motion.sharedFrom?1:0)*(1-p)+(s.motion.sharedTo?1:0)*p);
   const expected={x:s.origin[0]+((f.x-f.z)*35+offset)*s.scale,y:s.origin[1]+((f.x+f.z)*17.5-f.h*48+7)*s.scale};
   assert.ok(Math.abs(s.character.screen_footpoint.x-expected.x)<0.01&&Math.abs(s.character.screen_footpoint.y-expected.y)<0.01,'Shared-tile spacing follows motion progress without an offset jump at commit');
  }
  assert.ok(chain.samples.filter(s=>s.revision===1).every(s=>s.moving&&!s.character.stop_blend_active),'No idle/settle is sampled between linked segments');
  // Commit diagnostics can precede clear_motion in the same frame; settling begins when both layers have ended travel.
  const settling=chain.samples.filter(s=>s.revision===2&&!s.moving&&!s.character.moving);
  const publishedSettling=chain.publicationSamples.filter(s=>s.revision===2&&!s.moving&&!s.character.moving);
  assert.ok(publishedSettling.some(s=>s.character.stop_blend_active&&s.character.stop_progress>=0&&s.character.stop_progress<1),'A final stop transition is observed in actual diagnostic publications');
  assert.ok(publishedSettling.every(s=>s.character.facing==='left'&&s.character.to_key==='idle-side'),'Published stopping phases preserve side orientation');
  assert.ok(publishedSettling.every(s=>footEqual(s.character.footpoint,{x:2,z:2,h:0})),'Every published stop phase retains the committed world foot');
  assert.ok(settling.some(s=>!s.character.stop_blend_active&&s.character.stop_progress===1),'Independent timer samples observe the completed stop transition');
  assert.ok(settling.every(s=>s.character.facing==='left'&&s.character.to_key==='idle-side'),'Stopping preserves side orientation');
  assert.ok(settling.every(s=>footEqual(s.character.footpoint,{x:2,z:2,h:0})),'Settling never adds position inertia');
  const screenFeet=[...publishedSettling,...settling].map(s=>s.character.screen_footpoint).filter(Boolean);
  assert.ok(screenFeet.length>0&&screenFeet.every(p=>p.x===screenFeet[0].x&&p.y===screenFeet[0].y),'The visual screen foot anchor remains fixed during settling');
 });

 await load(room());await begin('mouse-route-stays-contiguous');
 const target=(await state()).targets.find(tile=>tile.id==='f:0:2');
 assert.ok(target,'The map exposes the requested route destination');
 const canvasRect=await page.locator('#canvas').boundingBox();
 const canvasSize=await page.locator('#canvas').evaluate(c=>({width:c.width,height:c.height}));
 await page.mouse.click(canvasRect.x+target.x*canvasRect.width/canvasSize.width,canvasRect.y+target.y*canvasRect.height/canvasSize.height);
 await waitStable('f:0:2',4);
 await finish({},route=>{
  const moving=route.samples.filter(sample=>sample.moving&&sample.character.moving);
  assert.ok(moving.length>=4,'The real mouse route supplies multiple movement samples');
  assert.equal(new Set(moving.map(sample=>sample.character.walk_started)).size,1,'All click-route segments retain a single walk phase clock');
  assert.ok(route.samples.filter(sample=>sample.revision>0&&sample.revision<4).every(sample=>sample.moving&&!sample.character.stop_blend_active),'A click route shows no intervening idle/stop transition');
 });

 await load(room());await begin('default-hold-is-continuous');
 await event('down','ArrowLeft');
 await waitStable('f:-1:2',5);
 await event('up','ArrowLeft');
 await finish({continuousInput:true},hold=>{
  const middle=hold.samples.filter(sample=>sample.revision>0&&sample.revision<5);
  assert.ok(middle.length>1,'One held key traverses multiple segments');
  assert.ok(middle.every(sample=>sample.moving&&!sample.character.stop_blend_active),'Held walking has no intermediate idle frame');
 });

 // An explicitly chosen single-step preference remains available after migration.
 await event('press','Escape');
 await wait(()=>window.__sporelightState?.paused===true);
 await button('按住方向键连续行走');
 await wait(()=>window.__sporelightState?.continuousInput===false);
 await event('press','Escape');
 await load(room());await begin('explicit-single-step-preference');
 await event('down','ArrowLeft');
 await page.waitForTimeout(550);
 await event('down','ArrowLeft'); // A repeated down is a real browser key event with repeat=true.
 await page.waitForTimeout(160);
 await event('up','ArrowLeft');
 await waitStable('f:3:2',1);
 await finish({continuousInput:false});

 await load(initial('1-1'));await begin('early-tap-expires-during-interaction');
 await event('press','e');
 await wait(()=>window.__sporelightState?.motion?.kind?.startsWith('grow:')&&window.__sporelightState.motion.elapsed>=0.07&&window.__sporelightState.motion.elapsed<0.25);
 await event('press','ArrowLeft');
 await waitStable('f:0:0',1);
 await page.waitForTimeout(250);
 assert.equal((await state()).input.buffered,'');
 assert.equal((await state()).snapshot.actors.luvie,'f:0:0');
 await finish();

 await load(initial('1-1'));await begin('interaction-hold-never-repeats');
 await event('down','e');
 await page.waitForTimeout(100);
 await event('down','e');
 await waitStable('f:0:0',1);
 await event('down','e');
 await page.waitForTimeout(250);
 await event('up','e');
 assert.equal((await state()).revision,1);
 assert.equal((await state()).snapshot.growth.root.length,1,'E key repeat does not retract or spend another resource');
 await finish();

 await load(room());await begin('pause-clears-held-and-tap');
 await event('down','ArrowLeft');await activeStep();
 await event('press','ArrowUp');
 await event('press','Escape');
 await wait(()=>window.__sporelightState?.paused===true);
 const paused=await state();
 assert.ok(paused.moving&&paused.motion.after,'Pause occurs during a real pending segment');
 assert.deepEqual(paused.input.held,[]);
 assert.equal(paused.input.buffered,'');
 const pausedElapsed=paused.motion.elapsed;
 await event('up','ArrowLeft');
 await page.waitForTimeout(300);
 const pausedAfter=await state();
 assert.equal(pausedAfter.motion.elapsed,pausedElapsed,'Pause freezes the pending animation');
 assert.deepEqual({key:pausedAfter.character.key,pose:pausedAfter.character.pose,weight:pausedAfter.character.weight},{key:paused.character.key,pose:paused.character.pose,weight:paused.character.weight},'Pause also freezes the character visual clock, pose and blending');
 await event('press','Escape');
 await waitStable(paused.motion.after.actors.luvie,paused.revision+1);
 await page.waitForTimeout(220);
 assert.equal((await state()).revision,paused.revision+1,'Resume completes only the segment pending at pause and does not replay cleared input');
 await finish({revisionAtPause:paused.revision,pendingTileAtPause:paused.motion.after.actors.luvie});

 await load(room());await begin('moving-undo-queues-until-commit');
 const originalBefore=await state();
 await event('down','ArrowLeft');
 await new Promise(resolve=>setTimeout(resolve,80));
 await event('down','z');
 await event('up','z');
 await event('up','ArrowLeft');
 const undoKey=await page.evaluate(()=>window.__motionTrack.keys.find(key=>key.type==='keydown'&&key.key==='z'&&!key.repeat));
 assert.ok(undoKey?.trusted&&undoKey.moving&&undoKey.revision===0&&undoKey.elapsed>=0&&undoKey.elapsed<0.205,'The real Z key reaches an uncommitted movement');
 await waitStable('f:4:2',originalBefore.revision+2);
 const undoneAfterMove=await state();
 assert.equal(undoneAfterMove.revision,originalBefore.revision+2,'The pending move commits once before the queued undo advances the revision again');
 assert.deepEqual(undoneAfterMove.snapshot,originalBefore.snapshot,'Queued undo restores the complete original snapshot after the movement commits');
 assert.ok(footEqual(undoneAfterMove.character.footpoint,originalBefore.character.footpoint),'Queued undo restores the original logical foot anchor');
 assert.deepEqual(undoneAfterMove.input.held,[]);
 assert.equal(undoneAfterMove.input.buffered,'');
 await finish({originalRevision:originalBefore.revision,moveCommittedBeforeUndo:true},queuedUndo=>{
  const pending=queuedUndo.publicationSamples.filter(sample=>sample.moving&&sample.revision===originalBefore.revision);
  assert.ok(pending.length>0,'An actual engine diagnostic publication contains the uncommitted movement before queued undo');
  assert.ok(pending.every(sample=>sample.actors.luvie==='f:4:2'&&sample.motion.from==='f:4:2'&&sample.motion.to==='f:3:2'),'Movement remains an uncommitted preview from the original tile before undo');
  assert.equal(queuedUndo.final.revision,originalBefore.revision+2,'Queued undo cannot replay the old held direction');
  assert.deepEqual(queuedUndo.final.snapshot,originalBefore.snapshot,'The restored snapshot stays unchanged after queued undo settles');
  assert.ok(footEqual(queuedUndo.final.character.footpoint,originalBefore.character.footpoint),'The restored foot anchor stays fixed after queued undo settles');
 });

 // Enable held movement through the actual independent settings option, leaving the camera option alone.
 await event('press','Escape');
 await wait(()=>window.__sporelightState?.paused===true);
 const cameraBefore=(await state()).safeCamera;
 await button('按住方向键连续行走');
 await wait(()=>window.__sporelightState?.continuousInput===true);
 assert.equal((await state()).safeCamera,cameraBefore,'Continuous input does not silently enable a different camera');
 await event('press','Escape');

 await load(room());await begin('optional-hold-boundary-and-undo');
 await event('down','ArrowLeft');
 await waitStable('f:-1:2',5);
 await wait(()=>window.__sporelightState?.input?.blocked==='left');
 const boundary=await state();
 await page.waitForTimeout(400);
 const quiet=await state();
 assert.equal(quiet.revision,boundary.revision,'Holding at a boundary creates no further command');
 assert.equal(quiet.message,boundary.message,'Holding at a boundary does not cycle feedback messages');
 await event('press','z');
 await waitStable('f:0:2',6);
 assert.deepEqual((await state()).input.held,[]);
 assert.equal((await state()).input.buffered,'');
 await event('up','ArrowLeft');
 await page.waitForTimeout(250);
 assert.equal((await state()).snapshot.actors.luvie,'f:0:2','Undo does not replay the old held direction');
 await finish({continuousInput:true,cameraUnchanged:true});

 await load(room());await begin('level-change-clears-pending-intent');
 await event('down','ArrowLeft');await activeStep();
 await event('press','ArrowUp');
 await button('返回');
 await wait(()=>window.__sporelightState?.paused===true);
 await button({includes:'1-3'});
 await wait(()=>window.__sporelightState?.snapshot?.levelId==='1-3'&&!window.__sporelightState?.paused);
 await event('up','ArrowLeft');
 const entered=await state();
 assert.deepEqual(entered.input.held,[]);
 assert.equal(entered.input.buffered,'');
 assert.equal(entered.revision,0);
 await page.waitForTimeout(300);
 assert.equal((await state()).revision,0,'The new level receives no stale movement');
 await page.screenshot({path:resolve(output,'new-level-stable.png')});
 await finish();

 let videoFile=null;
 if(video){
  const recorded=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1,recordVideo:{dir:resolve(output,'video'),size:{width:1440,height:900}}});
  await recorded.route('**/favicon.ico',route=>route.fulfill({status:204,body:''}));
  const demo=await recorded.newPage();
  demo.on('pageerror',value=>error('video: '+value.message));
  demo.on('console',message=>{if(message.type()==='error')error('video: '+message.text());});
  await demo.goto(url.href,{waitUntil:'networkidle',timeout:120000});
  await demo.waitForFunction(()=>typeof window.__sporelightRequest==='function'&&window.__sporelightState?.snapshot,undefined,{timeout:120000});
  await demo.evaluate(snapshot=>{window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot,time:1200}));window.__sporelightRequest(JSON.stringify({type:'action',command:'resume'}));},room());
  await demo.waitForTimeout(200);
  await demo.screenshot({path:resolve(output,'video-route-start.png')});
  await demo.evaluate(()=>window.__sporelightRequest(JSON.stringify({type:'movement',tile:'f:0:2'})));
  await demo.waitForFunction(()=>window.__sporelightState?.moving===true,undefined,{timeout:7000});
  await demo.screenshot({path:resolve(output,'video-route-moving.png')});
  await demo.waitForFunction(()=>window.__sporelightState?.snapshot?.actors?.luvie==='f:0:2'&&!window.__sporelightState?.moving,undefined,{timeout:15000});
  await demo.waitForTimeout(450);
  await demo.screenshot({path:resolve(output,'video-route-idle.png')});
  const capture=demo.video();
  await recorded.close();
  videoFile=await capture.path();
 }
 assert.deepEqual(errors,[],'No script, renderer, browser or HTTP errors');
 await writeFile(resolve(output,'checks.json'),JSON.stringify({passed:true,date:new Date().toISOString(),base,build,referenceCommit:reference.referenceCommit,cases:cases.map(c=>({name:c.name,samples:c.samples.length,publicationSamples:c.publicationSamples.length})),events,errors,errorEvents,sampleIntervalMs:50,video,videoFile,limitations:['Timer sampling targets 50ms but browser stalls can lengthen the observed interval; every diagnostic publication is recorded separately to verify the short final stop phase.','Diagnostic publications confirm controller state and do not prove a painted frame. They may include intermediate controller states; continuity assertions use timer samples, with exact same-frame handoff additionally asserted by the headless controller suite.','Time-sensitive keyboard checks run without an encoder; optional video records a separate deterministic mouse-route demonstration.']},null,2));
 console.log(JSON.stringify({passed:true,cases:cases.length,samples:cases.reduce((n,c)=>n+c.samples.length,0),errors,errorEvents,output},null,2));
}catch(errorValue){
 const current=await state().catch(()=>null);
 const track=await page.evaluate(()=>window.__motionTrack).catch(()=>null);
 await page.screenshot({path:resolve(output,'failure.png')}).catch(()=>{});
 await writeFile(resolve(output,'failure-state.json'),JSON.stringify({caseName:currentCase,error:String(errorValue),current,track,events,errors,errorEvents},null,2));
 await writeFile(resolve(output,'checks.json'),JSON.stringify({passed:false,date:new Date().toISOString(),base,build,caseName:currentCase,error:String(errorValue),cases:cases.map(c=>({name:c.name,samples:c.samples.length})),errors,errorEvents},null,2));
 console.error(JSON.stringify({passed:false,caseName:currentCase,error:String(errorValue),errors,errorEvents,output},null,2));
 process.exitCode=1;
}finally{
 await release().catch(()=>{});
 await context.close();
 await browser.close();
}

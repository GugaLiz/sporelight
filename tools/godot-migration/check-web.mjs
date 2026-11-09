import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(name,fallback)=>process.argv.find(value=>value.startsWith('--'+name+'='))?.slice(name.length+3)??fallback;
const base=option('base','http://localhost:4185/');
const build=await fetch(new URL('/__build.json',base)).then(response=>response.json());
const mode=option('mode','all');
const output=resolve(option('output',resolve(tmpdir(),'sporelight-godot-web-qa')));
const playwrightPath=option('playwright',process.env.PLAYWRIGHT_MODULE??'C:/Users/jeffrey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const {chromium}=createRequire(import.meta.url)(playwrightPath);
const fixture=JSON.parse(await readFile(resolve(root,'godot/tests/fixtures/reference.json'),'utf8'));
const filter=option('levels','').split(',').filter(Boolean);
const cases=fixture.cases.filter(entry=>entry.name.startsWith('authored/')&&(!filter.length||filter.includes(entry.levelId))&&(mode!=='persistence'||entry.levelId==='1-1'));
await mkdir(output,{recursive:true});
const errors=[],checks=[],results=[];
let errorEvents=0;
const error=value=>{errorEvents++;if(!errors.includes(value))errors.push(value);};
const canonical=(value,field='')=>{
 if(field==='trial'&&typeof value==='string')return canonical(JSON.parse(value));
 if(Array.isArray(value))return value.map(item=>canonical(item));
 if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key],key)]));
 return Object.is(value,-0)?0:value;
};
const equivalent=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1});
// The preview does not supply a favicon. Keep that browser-only request out of the game error audit.
await context.route('**/favicon.ico',route=>route.fulfill({status:204,body:''}));
const page=await context.newPage();
page.on('pageerror',value=>error(value.message));
page.on('console',message=>{if(message.type()==='error')error(message.text());});
page.on('response',response=>{if(response.status()>=400&&!response.url().endsWith('/favicon.ico'))error(response.status()+' '+response.url());});
const state=()=>page.evaluate(()=>structuredClone(window.__sporelightState));
const request=value=>page.evaluate(payload=>window.__sporelightRequest(JSON.stringify(payload)),value);
async function snapshotReady(expected,label,timeout=12000){
 try{
  await page.waitForFunction(expected=>{
   const s=window.__sporelightState;if(!s||s.moving)return false;
   const norm=(value,field='')=>{if(field==='trial'&&typeof value==='string')return norm(JSON.parse(value));if(Array.isArray(value))return value.map(v=>norm(v));if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,norm(value[k],k)]));return Object.is(value,-0)?0:value;};
   return JSON.stringify(norm(s.snapshot))===JSON.stringify(norm(expected));
  },expected,{timeout,polling:25});
 }catch(error){
  const actual=await state().catch(()=>null);
  await writeFile(resolve(output,'failure-state.json'),JSON.stringify({label,expected,actual,errors},null,2));
  throw new Error(label+': did not reach expected stable snapshot; details in failure-state.json',{cause:error});
 }
}
async function loadSnapshot(snapshot){
 await request({type:'snapshot',snapshot,time:1200});
 await snapshotReady(snapshot,'QA snapshot setup');
}
async function uiButton(text){
 const current=await state();
 const button=current.buttons.find(value=>!value.disabled&&value.text===text);
 assert.ok(button,'Visible enabled button: '+text);
 const canvas=await page.locator('#canvas').boundingBox();
 const backing=await page.locator('#canvas').evaluate(element=>({width:element.width,height:element.height}));
 await page.mouse.click(canvas.x+(button.x+button.width/2)*canvas.width/backing.width,canvas.y+(button.y+button.height/2)*canvas.height/backing.height);
}
async function doCommand(previous,step){
 const {kind,value}=step.command;
 if(kind==='move'){
  const actor=previous.snapshot.active;
  const from=previous.tiles.find(tile=>tile.id===previous.snapshot.actors[actor]);
  const to=previous.tiles.find(tile=>tile.id===value);
  assert.ok(from&&to,'Fixture has both movement anchors');
  const key=to.x>from.x?'ArrowRight':to.x<from.x?'ArrowLeft':to.z>from.z?'ArrowDown':'ArrowUp';
  await page.keyboard.press(key);
 }else if(value==='switch'){
  await page.keyboard.press('t');
 }else if(value==='follow'){
  const command=previous.commands.find(command=>command.id===value);
  await uiButton(command.label);
 }else{
  const local=previous.commands.filter(command=>!['switch','follow'].includes(command.id));
  const index=local.findIndex(command=>command.id===value);
  assert.ok(index>=0&&index<9,'UI exposes a numbered command: '+value);
  // This traverses Godot's real keyboard event path and the dynamically displayed command index.
  await page.keyboard.press(String(index+1));
 }
}
async function runLevel(entry){
 await loadSnapshot(entry.initial.snapshot);
 await page.screenshot({path:resolve(output,entry.levelId+'-arrival.png')});
 let previous=entry.initial;
 for(const [index,step]of entry.steps.entries()){
  assert.ok(['move','act'].includes(step.command.kind),'Authored fixtures contain only UI commands');
  await doCommand(previous,step);
  await snapshotReady(step.snapshot,entry.levelId+'/'+index+'/'+step.command.kind+'/'+step.command.value);
  const current=await state();
  assert.equal(current.revision,index+1,entry.levelId+' each authored command changes the world once');
  previous=step;
 }
 await page.waitForFunction(()=>window.__sporelightState?.snapshot?.completed===true&&window.__sporelightState?.paused===true&&window.__sporelightState?.buttons?.some(button=>button.text==='留下看看'&&!button.disabled),{},{timeout:5000});
 const done=await state();
 assert.equal(done.snapshot.completed,true);
 assert.equal(done.paused,true,'Completion opens a modal and pauses input');
 assert.ok(done.buttons.some(button=>button.text==='留下看看'&&!button.disabled));
 await page.screenshot({path:resolve(output,entry.levelId+'-restored.png')});
 await uiButton('留下看看');
 await page.waitForFunction(()=>window.__sporelightState&&!window.__sporelightState.paused&&!window.__sporelightState.moving,{},{timeout:5000});
 const beforeUndo=(await state()).snapshot;
 await page.keyboard.press('z');
 await page.waitForTimeout(100);
 assert.ok(equivalent(beforeUndo,(await state()).snapshot),'Completed stroll rejects undo');
 checks.push(entry.levelId+': authored solution through real keyboard and UI, completion/stay/undo');
 results.push({level:entry.levelId,commands:entry.steps.length,completed:true});
 console.log('PASS '+entry.levelId+' ('+entry.steps.length+' commands)');
}
try{
 const url=new URL(base);url.searchParams.set('qa','1');
 await page.goto(url.href,{waitUntil:'networkidle',timeout:120000});
 await page.waitForFunction(()=>typeof window.__sporelightRequest==='function'&&window.__sporelightState?.snapshot,{},{timeout:120000});
 assert.equal(await page.locator('#canvas').count(),1);
 await page.screenshot({path:resolve(output,'initial-observation.png')});
 for(const entry of cases)await runLevel(entry);
 // Normal entry into a completed run restarts it; archived completion memories remain independent.
 if(results.length&&mode!=='gameplay'){
  const done=await state(),id=done.snapshot.levelId;
  assert.ok(done.progress?.memories?.[id]?.completed,'Completion memory exists before replay');
  const memory=structuredClone(done.progress.memories[id]);
  const arrival=fixture.cases.find(entry=>entry.name==='authored/'+id).initial;
  await uiButton('返回');
  await page.waitForFunction(()=>window.__sporelightState?.paused===true,{},{timeout:5000});
  const menu=await state();
  const choice=menu.buttons.find(button=>!button.disabled&&button.text.includes(id)&&!button.text.includes('回看'));
  assert.ok(choice,'The map exposes a replay entry for '+id);
  await uiButton(choice.text);
  await snapshotReady(arrival.snapshot,'Ordinary map entry restarts a completed run');
  const first=fixture.cases.find(entry=>entry.name==='authored/'+id).steps[0];
  await doCommand(arrival,first);
  await snapshotReady(first.snapshot,'A replay produces an unfinished active run');
  assert.equal(first.snapshot.completed,false);
  await page.waitForTimeout(800);
  await page.reload({waitUntil:'networkidle',timeout:120000});
  await page.waitForFunction(()=>window.__sporelightState?.snapshot,{},{timeout:120000});
  await snapshotReady(first.snapshot,'Web reload restores the complete active snapshot');
  assert.ok(equivalent(memory,(await state()).progress.memories[id]),'Replay and reload preserve archived completion');
  checks.push('Map replay resets a completed run, active state survives IndexedDB reload, completion memory remains intact');
  console.log('PASS active-run persistence and completion-memory isolation');
 }
 // Normal held movement is checked in independent storage, without camera flags.
 const comfort=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1});
 await comfort.route('**/favicon.ico',route=>route.fulfill({status:204,body:''}));
 const comfortPage=await comfort.newPage();
 comfortPage.on('pageerror',value=>error('comfort: '+value.message));
 comfortPage.on('console',message=>{if(message.type()==='error')error('comfort: '+message.text());});
 const comfortUrl=new URL(base);comfortUrl.searchParams.set('qa','1');
 await comfortPage.goto(comfortUrl.href,{waitUntil:'networkidle',timeout:120000});
 await comfortPage.waitForFunction(()=>typeof window.__sporelightRequest==='function'&&window.__sporelightState?.snapshot,{},{timeout:120000});
 assert.equal(await comfortPage.evaluate(()=>window.__sporelightState.continuousInput),true,'Held movement is on by default');
 assert.equal(await comfortPage.evaluate(()=>window.__sporelightState.safeCamera),false,'The original camera remains in use');
 const initial=fixture.cases.find(entry=>entry.name==='authored/1-1').initial.snapshot;
 await comfortPage.evaluate(snapshot=>window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot,time:1200})),initial);
 await comfortPage.keyboard.down('ArrowLeft');
 await comfortPage.waitForFunction(()=>window.__sporelightState?.snapshot?.actors?.luvie==='f:-2:0',{},{timeout:8000});
 await comfortPage.keyboard.up('ArrowLeft');
 await comfortPage.waitForFunction(()=>!window.__sporelightState?.moving,{},{timeout:5000});
 const released=await comfortPage.evaluate(()=>structuredClone(window.__sporelightState.snapshot));
 await comfortPage.waitForTimeout(500);
 assert.ok(equivalent(released,await comfortPage.evaluate(()=>window.__sporelightState.snapshot)),'Key release stops additional movement');
 checks.push('Normal keyboard hold traverses valid tiles and release stops, with the original camera');
 await comfort.close();
 assert.deepEqual(errors,[],'No JavaScript/Godot/HTTP errors');
 await writeFile(resolve(output,'checks.json'),JSON.stringify({date:new Date().toISOString(),base,build,mode,checks,results,errors,errorEvents,referenceCommit:fixture.referenceCommit},null,2));
 console.log(JSON.stringify({passed:true,levels:results.length,commands:results.reduce((n,result)=>n+result.commands,0),checks,errors,errorEvents,output},null,2));
}catch(error){
 await page.screenshot({path:resolve(output,'failure.png')}).catch(()=>{});
 const actual=await state().catch(()=>null);
 await writeFile(resolve(output,'failure-state.json'),JSON.stringify({actual,errors},null,2));
 await writeFile(resolve(output,'checks.json'),JSON.stringify({date:new Date().toISOString(),base,build,mode,passed:false,error:String(error),checks,results,errors,errorEvents},null,2));
 console.error(JSON.stringify({passed:false,error:String(error),errors,errorEvents,output},null,2));
 process.exitCode=1;
}finally{
 await context.close();
 await browser.close();
}

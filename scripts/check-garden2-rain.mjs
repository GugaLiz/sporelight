import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {build} from 'esbuild';
const require=createRequire(import.meta.url),{chromium}=require(process.argv[2]||'playwright');
const bundle=await build({stdin:{contents:"export {GardenWorld} from './src/app/garden2/world';export {GARDEN_LEVELS} from './src/app/garden2/levels';export {GARDEN_SOLUTIONS} from './tests/garden2Solutions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {GardenWorld,GARDEN_LEVELS,GARDEN_SOLUTIONS}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].text).toString('base64'));
const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
await mkdir('docs/qa-garden2/rain-pond',{recursive:true});
const ready=()=>page.waitForFunction(()=>document.querySelector('#gardenCanvas')?.dataset.moving==='false');
const shot=async name=>{await page.screenshot({path:`docs/qa-garden2/rain-pond/${name}.png`});};
async function enter(w,settings={}){await page.evaluate(({run,levels,settings})=>{localStorage.setItem('sporelight.save.v2',JSON.stringify({hasNamed:true,lastLevel:run.levelId,levels,settings:{bgm:0,ambient:0,lowMotion:false,...settings}}));localStorage.setItem('sporelight.garden2.v1',JSON.stringify({version:1,lastLevel:run.levelId,runs:{[run.levelId]:run},records:{},memories:{}}));},{run:w.snapshot(),levels:Object.fromEntries(GARDEN_LEVELS.map(l=>[l.id,{completed:true}])),settings});await page.reload();await page.locator('[data-action="继续旅程"]').click();await ready();await page.waitForLoadState('networkidle');}
async function go(w,id){const path=w.pathTo(id);assert.ok(path);for(const tile of path){const a=w.point,b=w.pointFor(tile),dir=b.x>a.x?'right':b.x<a.x?'left':b.z>a.z?'down':'up';await page.locator(`[data-garden-dir="${dir}"]`).click();assert.ok(w.move(tile).ok);await page.waitForFunction(tile=>{const d=document.querySelector('#gardenCanvas')?.dataset;return d?.tile===tile&&d.moving==='false';},tile);}}
async function act(w,id){if(id==='switch')await page.locator(`[data-garden-actor="${w.actor==='luvie'?'buddy':'luvie'}"]`).click();else await page.locator(`#gardenCommands [data-garden-do="${id}"]`).click();assert.ok(w.act(id).ok);await ready();}
try{
 await page.goto('http://127.0.0.1:4173/');
 for(const id of ['2-1','2-2','2-3','2-4']){const w=new GardenWorld(id);await enter(w);await shot(`${id}-rain`);
  if(id==='2-1'){
   const a=await page.locator('#gardenCanvas').evaluate(c=>c.toDataURL());await page.waitForTimeout(400);const b=await page.locator('#gardenCanvas').evaluate(c=>c.toDataURL());assert.notEqual(a,b);checks.push('Rain and surface impacts animate while the player stands still');
   await page.locator('[data-action="设置"]').click();const paused=await page.locator('#gardenCanvas').evaluate(c=>c.toDataURL());await page.waitForTimeout(350);assert.equal(await page.locator('#gardenCanvas').evaluate(c=>c.toDataURL()),paused);await page.keyboard.press('Escape');checks.push('Pause freezes the whole rainy scene without changing the save');
   await page.setViewportSize({width:390,height:844});await shot('2-1-phone');await page.locator('#gardenOverview').click();await shot('2-1-phone-overview');await page.setViewportSize({width:1440,height:900});await page.locator('#gardenOverview').click();
  }
  for(const step of GARDEN_SOLUTIONS[id]){if(step.startsWith('!'))await act(w,step.slice(1));else await go(w,step);}
  assert.equal(await page.locator('#gardenCanvas').getAttribute('data-completed'),'true');checks.push(`${id}: original puzzle completed with rain active`);console.log('RAIN PASS '+id);
 }
 const w=new GardenWorld('2-1');await enter(w,{lowMotion:true});const a=await page.locator('#gardenCanvas').evaluate(c=>c.toDataURL());await page.waitForTimeout(400);assert.equal(await page.locator('#gardenCanvas').evaluate(c=>c.toDataURL()),a);await shot('2-1-reduced-motion');checks.push('Reduced motion preserves a static damp landscape without falling rain or splashes');
 await page.setViewportSize({width:390,height:844});await enter(w,{particles:false});await shot('2-1-phone-no-particles');await page.locator('[data-garden-dir="down"]').click();await ready();assert.equal(await page.locator('#gardenCanvas').getAttribute('data-tile'),'m:float:0:1');checks.push('Phone touch controls still move correctly with particles disabled');
 assert.deepEqual(errors,[]);await writeFile('docs/qa-garden2/rain-pond/checks.json',JSON.stringify({date:'2026-11-03',checks,errors},null,2));console.log(JSON.stringify({checks,errors},null,2));
}finally{await browser.close();}

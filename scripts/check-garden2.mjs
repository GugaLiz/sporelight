import {createRequire} from 'node:module';import {mkdir,writeFile} from 'node:fs/promises';import assert from 'node:assert/strict';import {build} from 'esbuild';
const require=createRequire(import.meta.url),{chromium}=require(process.argv[2]||'playwright');
const bundle=await build({stdin:{contents:"export {GardenWorld} from './src/app/garden2/world';export {GARDEN_LEVELS} from './src/app/garden2/levels';export {GARDEN_SOLUTIONS} from './tests/garden2Solutions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {GardenWorld,GARDEN_LEVELS,GARDEN_SOLUTIONS}=await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
const outputDir=process.env.QA_GARDEN_DIR||'docs/qa-garden2';await mkdir(outputDir,{recursive:true});
await page.addInitScript(()=>{if(sessionStorage.getItem('garden2-test'))return;sessionStorage.setItem('garden2-test','1');localStorage.setItem('sporelight.save.v2',JSON.stringify({version:2,hasNamed:true,playerName:'露薇',settings:{lowMotion:true,bgm:0,ambient:0}}));});
const ready=()=>page.waitForFunction(()=>document.querySelector('#gardenCanvas')?.dataset.moving==='false');
const shot=async name=>{await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));await page.screenshot({path:`${outputDir}/${name}.png`,animations:'disabled'});};
async function go(w,id){const path=w.pathTo(id);assert.ok(path,`${w.level.id} ${w.actor} -> ${id}`);for(const tile of path){const a=w.point,b=w.pointFor(tile),key=b.x>a.x?'ArrowRight':b.x<a.x?'ArrowLeft':b.z>a.z?'ArrowDown':'ArrowUp';await page.keyboard.press(key);assert.ok(w.move(tile).ok);await page.waitForFunction(id=>{const c=document.querySelector('#gardenCanvas');return c?.dataset.tile===id&&c.dataset.moving==='false';},tile);}}
async function act(w,id){if(id==='switch')await page.locator(`[data-garden-actor="${w.actor==='luvie'?'buddy':'luvie'}"]`).click();else await page.locator(`#gardenCommands [data-garden-do="${id}"]`).click();const result=w.act(id);assert.ok(result.ok,`${w.level.id} ${id}: ${result.message}`);await ready();}
async function collect(w){const origin=w.state.actors[w.actor];for(const c of w.level.collectibles)if(!w.state.collected.includes(c.id)&&w.pathTo(c.tile)){await go(w,c.tile);await go(w,origin);}}
try{
 await page.goto('http://127.0.0.1:4173/');await page.locator('[data-action="开始游戏"]').click();await page.locator('.map-enter-button').click();await ready();
 for(const level of GARDEN_LEVELS){
  const w=new GardenWorld(level.id);await ready();assert.equal(await page.locator('#gardenCanvas').getAttribute('data-level'),level.id);await shot(`${level.id}-arrival`);
  await collect(w);
  for(const [i,step]of GARDEN_SOLUTIONS[level.id].entries()){
   if(step==='!repair')await collect(w);
   if(step.startsWith('!'))await act(w,step.slice(1));else await go(w,step);
   if(level.id==='1-2'&&i===2){const before=await page.evaluate(()=>JSON.parse(localStorage.getItem('sporelight.garden2.v1')).runs['1-2']);await page.reload();await page.locator('[data-action="继续旅程"]').click();await ready();assert.equal(await page.locator('#gardenCanvas').getAttribute('data-tile'),w.state.actors[w.actor]);assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('sporelight.garden2.v1')).runs['1-2']),before);checks.push('Mid-growth reload resumes both actors, root path, collection and budget');}
   if((level.id==='1-3'&&step==='!turn:garden')||(level.id==='1-4'&&step==='!use:latch')||(level.id==='2-2'&&step==='!angle:mirrorA')||(level.id==='2-4'&&step==='!turn:boat')||(level.id==='3-3'&&step==='!turn:water')||(level.id==='3-4'&&step==='!turn:light'))await shot(`${level.id}-mechanism`);
  }
  assert.equal(w.state.completed,true);assert.equal(w.state.collected.length,level.total);await page.locator('#gardenEnding:not([hidden])').waitFor();await shot(`${level.id}-restored`);
  const record=await page.evaluate(id=>JSON.parse(localStorage.getItem('sporelight.garden2.v1')).records[id],level.id);assert.equal(record.collected,level.total);assert.equal(record.stars,3);checks.push(`${level.id}: full collection and explicit final planting through keyboard and UI`);console.log(`PASS ${level.id}`);
  await page.locator('#gardenEnding [data-action="下一关"]').click();
 }
 await page.locator('.garden-journal-screen').waitFor();assert.equal(await page.locator('[data-garden-review]').count(),12);await shot('journal-complete');checks.push('12 earned story pages and restored-garden revisits');
 await page.locator('.garden-journal details').last().locator('summary').click();await page.locator('[data-garden-review="3-4"]').click();assert.equal(await page.locator('#gardenCanvas').getAttribute('data-completed'),'true');await page.locator('#gardenStay').click();const archive=await page.evaluate(()=>localStorage.getItem('sporelight.garden2.v1'));await page.keyboard.press('ArrowLeft');await ready();assert.equal(await page.locator('#gardenCanvas').getAttribute('data-tile'),'f:-5:0');assert.equal(await page.evaluate(()=>localStorage.getItem('sporelight.garden2.v1')),archive);await shot('final-garden-revisit');checks.push('Completed garden supports free walking without overwriting the saved completion or replay');
 assert.deepEqual(errors,[]);await writeFile(`${outputDir}/checks.json`,JSON.stringify({date:new Date().toISOString(),checks,errors},null,2));console.log(JSON.stringify({checks,errors},null,2));
}catch(e){await shot('failure');console.error(errors);throw e;}finally{await browser.close();}

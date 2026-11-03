import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const require=createRequire(import.meta.url),{chromium}=require(process.argv[2]||'playwright');
const bundle=await build({stdin:{contents:"export {GardenWorld} from './src/app/garden2/world';export {GARDEN_LEVELS} from './src/app/garden2/levels';export {GARDEN_SOLUTIONS} from './tests/garden2Solutions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {GardenWorld,GARDEN_LEVELS,GARDEN_SOLUTIONS}=await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
const output=process.env.QA_GARDEN_DIR||'docs/qa-garden2/journey-ui/interaction';await mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:process.env.PLAYWRIGHT_CHANNEL||'chrome',headless:true});
const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[],checks=[];
page.on('pageerror',error=>errors.push(error.message));page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
const ready=()=>page.waitForFunction(()=>document.querySelector('#gardenCanvas')?.dataset.moving==='false');
const state=()=>page.evaluate(()=>{const p=JSON.parse(localStorage.getItem('sporelight.garden2.v1'));return p.runs[p.lastLevel];});
async function enter(w,lowMotion=true){
 await page.evaluate(({run,levels,lowMotion})=>{localStorage.setItem('sporelight.save.v2',JSON.stringify({version:2,hasNamed:true,playerName:'露薇',lastLevel:run.levelId,levels,settings:{lowMotion,bgm:0,ambient:0}}));localStorage.setItem('sporelight.garden2.v1',JSON.stringify({version:1,lastLevel:run.levelId,runs:{[run.levelId]:run},records:{},memories:{}}));},{run:w.snapshot(),levels:Object.fromEntries(GARDEN_LEVELS.map(l=>[l.id,{completed:true,bestStars:3}])),lowMotion});
 await page.reload();await page.locator('[data-action="继续旅程"]').click();await ready();
}
const shot=name=>page.screenshot({path:`${output}/${name}.png`,animations:'disabled'});
const go=(w,tile)=>{const path=w.pathTo(tile);assert.ok(path);for(const id of path)assert.ok(w.move(id).ok);};
try{
 await page.goto('http://127.0.0.1:4173/');
 await enter(new GardenWorld('2-3'));
 const first=page.locator('#gardenCommands button').filter({has:page.locator('kbd')}).first();
 assert.equal(await first.getAttribute('data-garden-do'),'swap:0');await page.keyboard.press('1');assert.deepEqual((await state()).song,['rise','turn','rest']);
 await page.locator('[data-action="提示"]').focus();const beforeHint=await state();await page.keyboard.press('Space');await ready();assert.deepEqual(await state(),beforeHint);assert.match(await page.locator('#gardenMessage').innerText(),/转庭/);
 checks.push('Displayed 1 maps to swap:0; Space activates a focused hint button without jumping');
 const rain=new GardenWorld('2-3');go(rain,'m:stage:0:0');rain.act('switch');await enter(rain);
 await page.locator('[data-garden-do="play"]').click();await page.locator('[data-garden-actor="luvie"]').click();assert.equal((await state()).active,'luvie');
 await page.locator('[data-garden-do="play"]').click();await ready();assert.equal((await state()).playing,false);
 await page.locator('[data-garden-do="resetSong"]').click();await ready();assert.deepEqual((await state()).actors,rain.state.actors);assert.equal((await state()).beat,0);
 checks.push('Playing song can be stopped and reset while controlling a passenger away from piano');
 for(const size of [{width:320,height:568},{width:390,height:844},{width:844,height:390},{width:1440,height:900}]){
  await page.setViewportSize(size);await enter(new GardenWorld('2-2'));await page.locator('[data-action="提示"]').click();
  const boxes=await page.evaluate(()=>{const rect=s=>{const r=document.querySelector(s).getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};};return {guide:rect('[data-mirror-guide]'),panel:rect('.garden-panel'),heading:rect('.garden-heading'),title:rect('#gardenTitle'),tools:rect('.garden-tools'),overflow:document.documentElement.scrollWidth>innerWidth};});
  assert.equal(boxes.overflow,false);assert.ok(boxes.tools.x>=0&&boxes.tools.x+boxes.tools.w<=size.width+1);
  if(size.width<650){assert.ok(boxes.guide.y+boxes.guide.h<=boxes.panel.y+1,'mirror guidance must not be covered by action panel');assert.ok(boxes.guide.y>=boxes.heading.y+boxes.heading.h,'mirror guidance must not be covered by heading');}
  await shot(`mirror-${size.width}x${size.height}`);
 }
 checks.push('320px, 390px, landscape and desktop layouts fit; mobile mirror instructions remain above controls');
 await page.setViewportSize({width:1440,height:900});
 const finish=new GardenWorld('1-1');for(const step of GARDEN_SOLUTIONS['1-1']){if(step==='!repair')break;if(step.startsWith('!'))finish.act(step.slice(1));else go(finish,step);}
 await enter(finish);await page.locator('[data-garden-do="repair"]').click();await ready();
 assert.equal(await page.evaluate(()=>document.activeElement?.getAttribute('data-action')),'下一关');const completed=await state();
 await page.keyboard.press('z');await page.keyboard.press('ArrowLeft');assert.deepEqual(await state(),completed);
 for(let n=0;n<5;n++){await page.keyboard.press('Tab');assert.equal(await page.evaluate(()=>!!document.activeElement.closest('#gardenEnding')),true);}
 await shot('completion-focus');await page.locator('#gardenStay').click();assert.equal(await page.locator('.garden-tools').evaluate(e=>e.inert),false);
 checks.push('Completion traps focus and blocks hidden undo/movement; staying restores controls');
 await enter(new GardenWorld('1-2'));await page.keyboard.press('h');const hint=await page.locator('#gardenMessage').innerText();await page.keyboard.press('ArrowLeft');await ready();assert.equal(await page.locator('#gardenMessage').innerText(),hint);
 checks.push('Movement preserves explicit hint text');
 assert.deepEqual(errors,[]);await writeFile(`${output}/checks.json`,JSON.stringify({date:new Date().toISOString(),checks,errors},null,2));console.log(JSON.stringify({checks,errors},null,2));
}catch(error){await shot('failure');throw error;}finally{await browser.close();}

import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.argv[2]||'playwright');
const bundle=await build({stdin:{contents:"export {GardenWorld} from './src/app/garden2/world';export {GARDEN_SOLUTIONS} from './tests/garden2Solutions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {GardenWorld,GARDEN_SOLUTIONS}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].text).toString('base64'));
const world=new GardenWorld('1-4');
for(const step of GARDEN_SOLUTIONS['1-4']){if(step==='!repair')break;if(step.startsWith('!'))assert.ok(world.act(step.slice(1)).ok);else for(const t of world.pathTo(step))assert.ok(world.move(t).ok);}
world.state.actors={luvie:'f:-11:-1',buddy:'f:-10:-1'};world.state.follow=false;
const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));
await mkdir('docs/qa-garden2/walking',{recursive:true});
const ready=()=>page.waitForFunction(()=>document.querySelector('#gardenCanvas')?.dataset.moving==='false');
async function enter(completed=false,lowMotion=false){const run=world.snapshot();run.completed=completed;await page.evaluate(({run,lowMotion})=>{localStorage.setItem('sporelight.save.v2',JSON.stringify({hasNamed:true,lastLevel:'1-4',levels:{'1-1':{completed:true},'1-2':{completed:true},'1-3':{completed:true}},settings:{bgm:0,ambient:0,lowMotion}}));localStorage.setItem('sporelight.garden2.v1',JSON.stringify({version:1,lastLevel:'1-4',runs:{'1-4':run},records:run.completed?{'1-4':{completed:true,stars:3,collected:4}}:{},memories:run.completed?{'1-4':run}:{}}));},{run,lowMotion});await page.reload();if(completed){await page.locator('[data-action="花园纪事"]').click();await page.locator('details').filter({has:page.locator('[data-garden-review="1-4"]')}).locator('summary').click();await page.locator('[data-garden-review="1-4"]').click();}else await page.locator('[data-action="继续旅程"]').click();await ready();await page.waitForLoadState('networkidle');if(completed)await page.locator('#gardenStay').click();}
async function traceWalk(tile,capture=false){
 await page.evaluate(capture=>{window.walkTrace=[];window.walkFrames=[];window.walkDone=false;let seen=false,framesAt=-1;const start=performance.now();function tick(now){const canvas=document.querySelector('#gardenCanvas'),d=canvas.dataset;if(d.moving==='true'){seen=true;window.walkTrace.push({frame:d.characterFrame,clip:d.characterClip,facing:d.characterFacing,tile:d.tile,time:now});if(capture&&now-framesAt>=75){framesAt=now;const crop=document.createElement('canvas');crop.width=200;crop.height=190;const c=crop.getContext('2d'),ratio=canvas.width/canvas.clientWidth;c.fillStyle='#f3e6cc';c.fillRect(0,0,200,190);c.drawImage(canvas,(+d.characterX-100)*ratio,(+d.characterY-155)*ratio,200*ratio,190*ratio,0,0,200,190);window.walkFrames.push(crop.toDataURL('image/png'));}}else if(seen){window.walkDone=true;return;}if(now-start>5000){window.walkDone=true;return;}requestAnimationFrame(tick);}requestAnimationFrame(tick);},capture);
 await page.locator(`[data-garden-tile="${tile}"]`).first().click();await page.waitForFunction(()=>window.walkDone);
 const result=await page.evaluate(()=>({trace:window.walkTrace,frames:window.walkFrames}));await ready();return result;
}
try{
 await page.goto('http://127.0.0.1:4173/');await enter();const walking=await traceWalk('f:-7:2',true);
 const keys=new Set(walking.trace.map(p=>p.frame));assert.equal(keys.size,12,'a route must reach all twelve walking frames');assert.ok(walking.trace.every(p=>p.clip==='walk'));assert.ok(walking.trace.some(p=>p.facing==='left')&&walking.trace.some(p=>p.facing==='right'));
 const tiles=[...new Set(walking.trace.map(p=>p.tile))];assert.ok(tiles.length>=6);for(const tile of tiles.slice(1)){const segment=walking.trace.filter(p=>p.tile===tile);assert.ok(segment.length>0);}assert.ok(walking.trace.filter((p,i)=>i&&p.tile!==walking.trace[i-1].tile).some(p=>Number(p.frame.split('-').at(-1))>4),'stride does not reset at each tile');
 for(const [i,data]of walking.frames.entries())await writeFile(`docs/qa-garden2/walking/step-${String(i).padStart(2,'0')}.png`,Buffer.from(data.split(',')[1],'base64'));
 await page.screenshot({path:'docs/qa-garden2/walking/desktop.png'});checks.push('Desktop multi-tile route plays all twelve frames continuously and turns with the isometric path');
 await page.waitForTimeout(350);await traceWalk('f:-8:2');assert.equal(await page.locator('#gardenCanvas').getAttribute('data-character-facing'),'left');
 await enter(true);const completed=await traceWalk('f:-7:2');assert.equal(new Set(completed.trace.map(p=>p.frame)).size,12);assert.ok(completed.trace.every(p=>p.clip==='walk'));checks.push('After completion, strolling walks normally instead of sliding in the bow pose');
 await enter();await page.locator('[data-garden-actor="buddy"]').click();await ready();const buddy=await traceWalk('f:-7:2');assert.ok(buddy.trace.length>0);assert.ok(buddy.trace.every(p=>p.clip==='idle'));checks.push('Moving only the companion leaves Luvie idle');
 await page.setViewportSize({width:390,height:844});await enter();const phone=await traceWalk('f:-7:2');assert.ok(new Set(phone.trace.map(p=>p.frame)).size>=10);await page.screenshot({path:'docs/qa-garden2/walking/phone.png'});checks.push('Phone click-to-walk uses the same continuous gait');
 await enter(false,true);await page.locator('[data-garden-dir="right"]').click();await ready();assert.equal(await page.locator('#gardenCanvas').getAttribute('data-tile'),'f:-10:-1');assert.equal(await page.locator('#gardenCanvas').getAttribute('data-character-clip'),'idle');checks.push('Reduced motion still commits movement instantly without gait animation');
 assert.deepEqual(errors,[]);await writeFile('docs/qa-garden2/walking/checks.json',JSON.stringify({checks,frames:[...keys],errors},null,2));console.log(JSON.stringify({checks,frames:[...keys],errors},null,2));
}finally{await browser.close();}

/** Run against npm run dev; optional argv[2] points to a shared Playwright installation. */
import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const require=createRequire(import.meta.url),{chromium}=require(process.argv[2]||'playwright');
const output=await build({stdin:{contents:"export {LEVELS,getLevel} from './src/app/game/levels'; export {GridWorld} from './src/app/game/GridWorld'; export {SOLUTIONS} from './tests/solutions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {LEVELS,getLevel,GridWorld,SOLUTIONS}=await import(`data:text/javascript;base64,${Buffer.from(output.outputFiles[0].text).toString('base64')}`);
const browser=await chromium.launch({channel:process.env.PLAYWRIGHT_CHANNEL||'chrome',headless:true});
const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[],checks=[],folder='.cache/qa-level-detail';
page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
await mkdir(folder,{recursive:true});
const fixture=(id,prefix=[],settings={})=>{const w=new GridWorld(getLevel(id));for(const step of prefix){if(step.startsWith('!'))assert.ok(w.act(step.slice(1),0,true).ok,step);else {const path=w.pathToNode(step);assert.ok(path,step);for(const move of path)assert.ok(w.commit(move.position,move.jump).ok,step);}}return {version:2,playerName:'露薇',hasNamed:true,lastLevel:id,levels:Object.fromEntries(LEVELS.map(l=>[l.id,{completed:true,bestStars:3,bestCollected:l.nodes.filter(n=>n.spore).length}])),settings:{lowMotion:false,bgm:0,ambient:0,sfx:0,...settings},run:w.model.snapshot()};};
const ready=()=>page.waitForFunction(()=>document.querySelector('#gameCanvas')?.dataset.moving==='false');
const enter=async(id,prefix=[],settings={})=>{await page.evaluate(save=>localStorage.setItem('sporelight.save.v2',JSON.stringify(save)),fixture(id,prefix,settings));await page.reload();await page.locator('[data-action="继续旅程"]').click();await page.locator('#gameCanvas').waitFor();await ready();await page.waitForFunction(()=>[...document.images].every(i=>i.complete));};
const shot=name=>page.screenshot({path:`${folder}/${name}.png`,animations:'disabled'});
const act=async action=>{await page.locator(`[data-puzzle-action="${action}"]`).click();await page.waitForFunction(()=>document.querySelector('#gameCanvas')?.dataset.structure==='false');await ready();};
const walk=async id=>{await page.locator(`[data-node="${id}"]`).click();if(id==='end'){await page.waitForFunction(()=>document.querySelector('#gameCanvas')?.dataset.characterClip==='bow'||document.querySelector('.illustrated-result'));return;}await page.locator(`[data-node="${id}"][aria-current="location"]`).waitFor();await ready();};
const bow=()=>page.waitForFunction(()=>document.querySelector('#gameCanvas')?.dataset.characterClip==='bow');
try{
 await page.goto('http://127.0.0.1:4173/');
 for(const level of LEVELS){await enter(level.id);await shot(`entry-${level.id}`);}checks.push('All 12 entry scenes render with no missing assets');
 await enter('1-2',['north']);await page.locator('[data-puzzle-action="plant"]').click();await page.waitForFunction(()=>document.querySelector('#gameCanvas')?.dataset.structure==='true');await page.waitForTimeout(320);await shot('flower-growing');await ready();await act('reclaim');assert.match(await page.locator('#puzzlePanel').innerText(),/可用种子 1/);checks.push('Growing flower animates, then reclaim restores the seed');
 await enter('1-4',['near']);await act('wait');await shot('buddy-waiting');await walk('garden');await act('unlatch');await shot('mole-greeting');await page.reload();await page.locator('[data-action="继续旅程"]').click();await ready();assert.equal(await page.locator('#gameCanvas').getAttribute('data-buddy'),'wait');await shot('mole-restored');checks.push('Mole garden response and waiting buddy survive a reload');
 await enter('2-2',SOLUTIONS['2-2'].slice(0,-1));await shot('beam-connected');await act('choose:pool');assert.match(await page.locator('#puzzlePanel').innerText(),/未照亮水晶/);await page.locator('[data-action="撤销"]').click();assert.match(await page.locator('#puzzlePanel').innerText(),/已连通/);checks.push('Reflection feedback follows disconnect and undo');
 await enter('3-2',['dial','!choose:moon']);await shot('moon-bridge');await act('choose:sun');await shot('sun-bridge');checks.push('Both shadow bridge phases render on actual walkable tiles');
 await enter('3-4',SOLUTIONS['3-4'].slice(0,-1));await walk('end');await bow();await shot('guardian-awakening');
 await page.locator('[data-action="设置"]').first().click();await page.waitForTimeout(700);assert.equal(await page.locator('.illustrated-result').count(),0);await page.keyboard.press('Escape');await page.locator('.illustrated-result').waitFor();checks.push('Finale shows bow and bloom before results; pause freezes the celebration');
 await enter('1-1',SOLUTIONS['1-1'].slice(0,-1));await walk('end');await bow();
 const pending=await page.evaluate(()=>JSON.parse(localStorage.getItem('sporelight.save.v2')).run);assert.ok(pending&&!pending.completed);
 await page.reload();await page.locator('[data-action="继续旅程"]').click();await ready();await walk('end');await page.locator('.illustrated-result').waitFor();checks.push('Refresh during the bloom restores the last safe step and can finish normally');
 await enter('3-4',SOLUTIONS['3-4'].slice(0,-1),{lowMotion:true,particles:false,dynamicLight:false});await walk('end');await page.locator('.illustrated-result').waitFor();checks.push('Reduced motion and disabled particles/light complete without a cinematic wait');
 await enter('1-4',['near','!wait']);await page.setViewportSize({width:390,height:844});await page.waitForFunction(()=>document.querySelector('#gameCanvas')?.clientHeight===844);await shot('buddy-phone');for(const button of await page.locator('[data-grid-direction]').all()){const r=await button.boundingBox();assert.ok(r.width>=44&&r.height>=44);}checks.push('Phone portrait keeps the waiting buddy and 44px direction buttons');
 assert.deepEqual(errors,[]);await writeFile(`${folder}/checks.json`,JSON.stringify({checks,errors},null,2));console.log(JSON.stringify({checks,errors},null,2));
}catch(error){await shot('failure');console.error(errors);throw error;}finally{await browser.close();}

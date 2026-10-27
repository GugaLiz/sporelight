import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url);
const {chromium}=require(process.argv[2]||'playwright');
const browser=await chromium.launch({channel:'chrome',headless:true});
const page=await browser.newPage({viewport:{width:1280,height:720}});
const errors=[];const checks=[];
page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
await mkdir('docs/qa-material',{recursive:true});
await page.addInitScript(()=>{localStorage.setItem('sporelight.save.v2',JSON.stringify({hasNamed:true,playerName:'露薇',lastLevel:'1-2',levels:{'1-1':{completed:true,bestStars:3,bestCollected:3},'1-2':{completed:true,bestStars:3,bestCollected:2},'1-3':{completed:true,bestStars:3,bestCollected:3},'1-4':{completed:true,bestStars:3,bestCollected:3}},settings:{lowMotion:false,bgm:0}}));});
const capture=async name=>{await page.evaluate(async()=>{await Promise.all([...document.images].map(i=>i.decode().catch(()=>{})));});await page.screenshot({path:`docs/qa-material/${name}.png`,animations:'disabled'});};
const at=async id=>page.locator(`[data-node="${id}"][aria-current="location"]`).waitFor();
try {
 await page.goto('http://127.0.0.1:4173/');await page.locator('.journey-menu').waitFor();await capture('01-menu');
 assert.match(await page.locator('.journey-menu-actions > button').first().evaluate(el=>getComputedStyle(el).backgroundImage),/material-ready/);
 checks.push('Menu uses extracted paper buttons with actual DOM labels');
 await page.locator('[data-action="设置"]').click();await capture('02-settings');
 const low=page.locator('[data-setting-toggle="lowMotion"]');await low.click();assert.equal(await low.getAttribute('aria-pressed'),'true');await low.click();
 await page.locator('[data-action="关闭设置"]').last().click();
 await page.locator('[data-action="开始游戏"]').click();await page.locator('[data-map-level="1-2"]').click();await page.locator('.map-enter-button').click();await page.locator('#gameCanvas').waitFor();
 // Record the supplied frames while actually travelling, not a gallery of sprites.
 const frames=page.evaluate(async()=>{const result=[];const end=performance.now()+1100;while(performance.now()<end){const c=document.querySelector('#gameCanvas');if(c?.dataset.characterClip==='walk')result.push(c.dataset.characterFrame);await new Promise(r=>requestAnimationFrame(r));}return [...new Set(result)];});
 await page.locator('[data-node="north"]').click();await at('north');const seen=await frames;assert.ok(seen.length>=4,JSON.stringify(seen));
 assert.equal(await page.locator('#gameCanvas').getAttribute('data-character-facing'),'right');checks.push(`Actual walking changes supplied frames: ${seen.join(', ')}`);
 const sowFrames=page.evaluate(async()=>{const result=[];const end=performance.now()+1050;while(performance.now()<end){const c=document.querySelector('#gameCanvas');if(c?.dataset.characterClip==='sow')result.push(c.dataset.characterFrame);await new Promise(r=>requestAnimationFrame(r));}return [...new Set(result)];});
 await page.locator('[data-puzzle-action="plant"]').click();
 const marker=await page.locator('[data-node="north"]').boundingBox();const crop={x:Math.max(0,Math.round(marker.x+marker.width/2-90)),y:Math.max(0,Math.round(marker.y+80*marker.width/78-150)),width:180,height:210};
 for(let i=0;i<5;i++){await page.screenshot({path:`docs/qa-material/sow-${i+1}.png`,clip:crop});await page.waitForTimeout(100);}
 const sowSeen=await sowFrames;assert.deepEqual(sowSeen,['sow-1','sow-2','sow-3','sow-4','sow-5']);checks.push('Five supplied sowing frames play once in order');
 await capture('03-game-controls');
 await page.locator('[data-action="切换移动"]').click();assert.equal(await page.locator('[data-action="切换移动"]').getAttribute('aria-pressed'),'true');
 await page.locator('[data-node="east"]').click();await page.waitForFunction(()=>document.querySelector('#gameCanvas')?.dataset.characterClip==='roll');
 await capture('04-roll');await at('east');checks.push('Roll toggle changes the moving character to the mushroom ball');
 await page.locator('[data-action="切换移动"]').click();await page.locator('[data-node="start"]').click();await at('start');assert.equal(await page.locator('#gameCanvas').getAttribute('data-character-facing'),'left');
 await page.locator('[data-action="设置"]').first().click();const before=await page.locator('#gameCanvas').getAttribute('data-characterFrame');await page.waitForTimeout(220);assert.equal(await page.locator('#gameCanvas').getAttribute('data-characterFrame'),before);await page.keyboard.press('Escape');checks.push('Returning changes facing; pause freezes animation');
 await page.setViewportSize({width:390,height:844});await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));await capture('05-portrait');
 for(const b of await page.locator('.journey-toolbar > button').all()){const box=await b.boundingBox();assert.ok(box.x>=0&&box.x+box.width<=391&&box.height>=44);}
 checks.push('Portrait controller keeps all six controls within the viewport and at least 44px high');
 await page.setViewportSize({width:1280,height:720});await page.locator('[data-action="返回关卡选择"]').click();await page.locator('[data-map-chapter="pond"]').click();await page.locator('[data-map-level="2-1"]').click();await page.locator('.map-enter-button').click();
 await page.locator('[data-puzzle-action="jump:west"]').click();await page.waitForFunction(()=>document.querySelector('#gameCanvas')?.dataset.characterClip==='jump');await capture('06-jump');await page.getByText('睡莲接住了你的选择。',{exact:true}).waitFor();checks.push('Lily launches the jumping pose and returns to a standing pose');
 assert.deepEqual(errors,[]);await writeFile('docs/qa-material/checks.json',JSON.stringify({date:'2026-10-27',checks,errors},null,2));console.log(JSON.stringify({checks,errors},null,2));
}catch(e){await capture('failure');console.error(errors);throw e;}finally{await browser.close();}

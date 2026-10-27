import { createRequire } from 'node:module';
import { mkdir,writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url);
const {chromium}=require(process.argv[2]||'playwright');
const browser=await chromium.launch({channel:'chrome',headless:true});
const page=await browser.newPage({viewport:{width:1280,height:720}});
const errors=[];const checks=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
await mkdir('docs/qa-reference',{recursive:true});
await page.addInitScript(()=>{
  if(!sessionStorage.getItem('fixture-ready')) {
    localStorage.setItem('sporelight.save.v2',JSON.stringify({version:2,hasNamed:true,playerName:'露薇',lastLevel:'1-2',levels:{'1-1':{completed:true,bestStars:3,bestCollected:3}},settings:{lowMotion:true,bgm:0}}));
    sessionStorage.setItem('fixture-ready','true');
  }
});
const capture=async name=>{
  await page.evaluate(async()=>{await Promise.all([...document.images].map(i=>i.decode().catch(()=>{})));});
  await page.screenshot({path:`docs/qa-reference/${name}.png`,animations:'disabled'});
};
try {
  await page.goto('http://127.0.0.1:4173/');
  await page.locator('[data-action="开始游戏"]').click();
  await page.locator('.illustrated-map').waitFor();
  assert.equal(await page.locator('.plant-marker').count(),4);
  assert.equal(await page.locator('.plant-marker.is-blooming').count(),1);
  assert.equal(await page.locator('.plant-marker.is-budding').count(),1);
  assert.equal(await page.locator('.plant-marker.is-dormant').count(),2);
  assert.equal(await page.locator('.map-enter-button').isEnabled(),true);
  await capture('01-valley-map');checks.push('Bloom, bud and dormant states match real saved progression');
  await page.locator('[data-map-level="1-3"]').click();
  assert.equal(await page.locator('.map-enter-button').isEnabled(),false);
  assert.match(await page.locator('#mapSelectedTitle').innerText(),/1-3/);
  checks.push('Locked plants can be inspected; entry remains disabled');
  await page.locator('[data-map-chapter="pond"]').click();
  assert.equal(await page.locator('.plant-marker.is-dormant').count(),4);
  assert.equal(await page.locator('.map-enter-button').isEnabled(),false);
  await capture('02-pond-locked');checks.push('Chapter switching shows its own four levels and locked state');
  await page.locator('[data-action="世界总览"]').click();
  assert.equal(await page.locator('.world-overview-chapters > button').count(),3);
  await capture('03-world-overview');await page.keyboard.press('Escape');
  assert.equal(await page.locator('.world-overview-layer').count(),0);
  checks.push('World overview opens, shows three chapters, closes with Escape');
  await page.locator('[data-map-chapter="valley"]').click();
  await page.locator('[data-map-level="1-1"]').click();
  await page.locator('.map-enter-button').click();
  await page.locator('#gameCanvas').waitFor();
  for(const node of ['fork','fern','fork','stone','end']) {
    await page.locator(`[data-node="${node}"]`).click();
    if(node!=='end')await page.locator(`[data-node="${node}"][aria-current="location"]`).waitFor();
  }
  await page.locator('.illustrated-result').waitFor();
  assert.match(await page.locator('.illustrated-result-stats').innerText(),/3\s*\/ 3/);
  assert.match(await page.locator('.illustrated-result-stats').innerText(),/1\s*\/ 1/);
  assert.equal(await page.locator('.illustrated-result-stars').getAttribute('aria-label'),'3枚星光');
  await capture('04-complete');checks.push('Completion artwork shows real 3/3 collection, terminal flower and three stars');
  await page.locator('[data-action="重玩"]').click();await page.locator('#gameCanvas').waitFor();
  assert.equal(await page.locator('[data-node="start"]').getAttribute('aria-current'),'location');
  await page.locator('[data-action="返回关卡选择"]').click();
  assert.match(await page.locator('#mapSelectedTitle').innerText(),/1-1/);
  checks.push('Replay starts from the beginning; return selects the correct plant');
  await page.setViewportSize({width:1024,height:576});
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const bounds=await page.locator('.map-enter-button').boundingBox();
  assert.ok(bounds.x>=0&&bounds.y>=0&&bounds.x+bounds.width<=1025&&bounds.y+bounds.height<=577);
  await capture('05-small-landscape');checks.push('1024×576 preserves visible entry control');
  assert.deepEqual(errors,[]);
  await writeFile('docs/qa-reference/checks.json',JSON.stringify({date:'2026-10-27',checks,errors},null,2));
  console.log(JSON.stringify({checks,errors},null,2));
} catch(e) {await capture('failure');console.error(errors);throw e;}
finally {await browser.close();}

/** Standalone regression runner; uses an isolated test browser and the authored solutions. */
import { createRequire } from 'node:module';
import { mkdir,writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const require=createRequire(import.meta.url);
const {chromium}=require(process.argv[2]||'playwright');
const bundled=await build({stdin:{contents:"export { LEVELS } from './src/app/game/levels';export { SOLUTIONS } from './tests/solutions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {LEVELS,SOLUTIONS}=await import(`data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`);
const browser=await chromium.launch({headless:true,channel:process.env.PLAYWRIGHT_CHANNEL||'chrome'});
const page=await browser.newPage({viewport:{width:1280,height:720}});
const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
await mkdir('docs/qa-reference/full-journey',{recursive:true});
const checks=[];
try{
 await page.goto('http://127.0.0.1:4173/');await page.locator('#playerNameInput').waitFor();await page.locator('#playerNameInput').press('Enter');
 await page.locator('[data-action="设置"]').click();await page.locator('[data-setting-toggle="lowMotion"]').click();await page.keyboard.press('Escape');
 await page.locator('[data-action="开始游戏"]').click();await page.locator('[data-level="1-1"]').click();
 for(const level of LEVELS){
  await page.locator('#gameCanvas').waitFor();
  for(const step of SOLUTIONS[level.id]){
   if(step.startsWith('!')){
    const action=step.slice(1);await page.locator(`[data-puzzle-action="${action}"]`).click();
    if(action.startsWith('jump:') && action!=='jump:end')await page.getByText('睡莲接住了你的选择。',{exact:true}).waitFor();
   }else{
    await page.locator(`[data-node="${step}"]`).click();
    if(step!==level.exit)await page.locator(`[data-node="${step}"][aria-current="location"]`).waitFor();
   }
  }
  await page.locator('.illustrated-result').waitFor();
  assert.equal(await page.locator('.illustrated-result-stars').getAttribute('aria-label'),'3枚星光');checks.push(`${level.id} all-spore solution through UI`);
  await page.screenshot({path:`docs/qa-reference/full-journey/result-${level.id}.png`,animations:'disabled'});
  if(level.id!=='3-4')await page.locator('[data-action="下一关"]').click();
 }
 assert.deepEqual(errors,[]);await writeFile('docs/qa-reference/full-journey/automated-browser.json',JSON.stringify({date:'2026-10-27',checks,errors},null,2));console.log(checks);
}finally{await browser.close();}

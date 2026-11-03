import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const require = createRequire(import.meta.url);
const { chromium } = require(process.argv[2] || 'playwright');
const bundle = await build({ entryPoints:['src/app/scenes/menuVignetteMotion.ts'], bundle:true, platform:'node', format:'esm', write:false });
const {menuVignettePose:pose, MENU_LOOP_MS:loop} = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
const checks = [], errors = [];
const frames = new Set();
for(let t = 0; t <= loop; t += 16) {
  const current = pose(t), next = pose(t + 16);
  assert.ok(Math.hypot(next.hero.x-current.hero.x,next.hero.y-current.hero.y)<1.1,'no teleport at phase or loop boundaries');
  assert.ok(Math.hypot(next.buddy.x-current.buddy.x,next.buddy.y-current.buddy.y)<1.1);
  assert.ok(Math.hypot(next.light.x-current.light.x,next.light.y-current.light.y)<2,'continuous light path');
  assert.ok(current.hero.x>=325 && current.hero.x<=475 && current.hero.y>=606 && current.hero.y<=642);
  if(current.hero.walking) {frames.add(current.hero.key); assert.equal(current.hero.flip, t<10000);}
  assert.deepEqual(pose(t,true),pose(0,true));
}
assert.equal(frames.size,8);
assert.deepEqual(pose(0),pose(loop));
checks.push('24-second loop stays on the terrace, has continuous positions, eight redrawn whole-body walking poses and correct facing');
const turnTimes=[12300,12600,12900,13200,13400];
assert.deepEqual(turnTimes.map(t=>[pose(t).hero.key,pose(t).hero.flip]),[
  ['idle-side',true],['turn-quarter',true],['idle-front',false],['turn-quarter',false],['idle-side',false],
]);
assert.ok(turnTimes.every(t=>!pose(t).hero.walking && pose(t).hero.x===475 && pose(t).hero.y===606));
assert.deepEqual([6800,7100,8000,10500,11500,11900,12300].map(t=>pose(t).hero.key),[
  'idle-side','crouch-lower','crouch','crouch-happy','crouch','crouch-lower','idle-side',
]);
assert.equal(pose(18500).hero.key,'idle-front');
checks.push('Crouch lowers and rises through a half-squat; reversal holds a front pose between both three-quarter views with feet planted');
const output = 'docs/qa-menu-vignette'; await mkdir(output,{recursive:true});
const browser = await chromium.launch({headless:true,...(process.env.QA_BROWSER_PATH?{executablePath:process.env.QA_BROWSER_PATH}:{channel:'chrome'})});
try {
  const context=await browser.newContext({viewport:{width:1280,height:720}});
  await context.addInitScript(()=>localStorage.setItem('sporelight.save.v2',JSON.stringify({hasNamed:true,playerName:'露薇',settings:{bgm:0,ambient:0}})));
  const page=await context.newPage(); page.on('pageerror',e=>errors.push(e.message));
  page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
  await page.goto(process.env.QA_URL||'http://127.0.0.1:4173/');
  await page.locator('.journey-vignette.is-ready').waitFor();
  await page.clock.install(); await page.clock.pauseAt(new Date());
  const pixels=()=>page.locator('#menuVignette').evaluate(c=>c.toDataURL());
  const initial=await pixels();
  await page.screenshot({path:`${output}/desktop.png`});
  await page.clock.runFor(4200); assert.notEqual(await pixels(),initial);
  await page.screenshot({path:`${output}/walking.png`});
  await page.clock.runFor(4100); await page.screenshot({path:`${output}/curious.png`});
  await page.clock.runFor(2400); await page.screenshot({path:`${output}/delighted.png`});
  await page.clock.runFor(4400); await page.screenshot({path:`${output}/return.png`});
  await page.locator('[data-action="设置"]').click();
  const paused=await pixels(); await page.clock.runFor(2000); assert.equal(await pixels(),paused);
  await page.locator('[data-setting-toggle="lowMotion"]').click();
  await page.locator('[data-action="关闭设置"]').first().click();
  const quiet=await pixels(); await page.clock.runFor(3000); assert.equal(await pixels(),quiet);
  checks.push('Opening settings pauses the scene; reduced motion is fully static');
  await page.locator('[data-action="设置"]').click();
  await page.locator('[data-setting-toggle="lowMotion"]').click();
  await page.locator('[data-action="关闭设置"]').first().click();
  await page.clock.runFor(1000); assert.notEqual(await pixels(),quiet);
  await page.emulateMedia({reducedMotion:'reduce'}); await page.clock.runFor(100);
  const osQuiet=await pixels(); await page.clock.runFor(2000); assert.equal(await pixels(),osQuiet);
  await page.emulateMedia({reducedMotion:'no-preference'}); await page.clock.runFor(1000);
  assert.notEqual(await pixels(),osQuiet);
  checks.push('OS reduced-motion changes stop animation live and resume without a time jump');
  await page.evaluate(()=>{Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'));});
  const hidden=await pixels(); await page.clock.runFor(5000); assert.equal(await pixels(),hidden);
  await page.evaluate(()=>{delete document.hidden;document.dispatchEvent(new Event('visibilitychange'));});
  await page.clock.runFor(300); assert.notEqual(await pixels(),hidden);
  checks.push('Hidden-tab lifecycle pauses and resumes the scene');
  for (const [width,height,name] of [[2560,1080,'ultrawide'],[1440,900,'desktop-tall'],[1024,768,'tablet-landscape'],[844,390,'phone-landscape']]) {
    await page.setViewportSize({width,height}); await page.clock.runFor(100);
    const fit=await page.locator('.journey-menu').evaluate(el=>{
      const r=el.getBoundingClientRect(),land=el.querySelector('.journey-landscape').getBoundingClientRect();
      return {width:r.width,height:r.height,x:r.x,y:r.y,covers:land.left<=1&&land.right>=innerWidth-1&&land.top<=1&&land.bottom>=innerHeight-1};
    });
    assert.equal(fit.width,width);assert.equal(fit.height,height);assert.equal(fit.x,0);assert.equal(fit.y,0);assert.ok(fit.covers);
    await page.screenshot({path:`${output}/${name}.png`});
    const start=await page.locator('[data-action="开始游戏"]').boundingBox();
    assert.ok(start.x>=0&&start.y>=0&&start.x+start.width<=width&&start.y+start.height<=height);
  }
  checks.push('Ultrawide, tall desktop, tablet and landscape phone: background and actors cover the viewport without bars, start button stays visible');
  await page.setViewportSize({width:390,height:844}); await page.clock.runFor(80);
  await page.screenshot({path:`${output}/phone.png`});
  assert.equal(await page.locator('.journey-menu').evaluate(el=>el.scrollWidth<=el.clientWidth),true);
  await page.setViewportSize({width:360,height:640}); await page.clock.runFor(80);
  await page.locator('[data-action="设置"]').click(); await page.locator('[data-action="关闭设置"]').first().click();
  checks.push('390px and 360px portrait layouts have no horizontal overflow; menu scrolls and settings remain usable');
  await page.evaluate(()=>window.oldMenu=document.querySelector('#menuVignette'));
  await page.locator('[data-action="开始游戏"]').click();
  assert.equal(await page.locator('#menuVignette').count(),0);
  const oldPixels=await page.evaluate(()=>window.oldMenu.toDataURL()); await page.clock.runFor(1000);
  assert.equal(await page.evaluate(()=>window.oldMenu.toDataURL()),oldPixels);
  await page.locator('[data-action="返回主菜单"]').click(); await page.locator('.journey-vignette.is-ready').waitFor();
  assert.equal(await page.locator('#menuVignette').count(),1);
  checks.push('Starting a journey releases the old canvas animation; returning creates one fresh scene');
  assert.deepEqual(errors,[]);
  await writeFile(`${output}/checks.json`,JSON.stringify({checks,errors},null,2));
  console.log(JSON.stringify({checks,errors},null,2));
} finally {await browser.close();}

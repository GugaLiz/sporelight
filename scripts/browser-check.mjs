import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const require = createRequire(import.meta.url);
const { chromium } = require(process.argv[2] || 'playwright');
const bundle = await build({ stdin: { contents: "export { LEVELS } from './src/app/game/levels'; export { GameModel } from './src/app/game/model';", resolveDir: process.cwd() }, platform: 'node', bundle: true, format: 'esm', write: false });
const { LEVELS, GameModel } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
await mkdir('docs/qa', { recursive: true });
const browser = await chromium.launch({ headless: true, channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome' });
const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const page = await context.newPage(); const errors = []; const checks = [];
page.on('pageerror', error => errors.push(error.message));
page.on('response', response => { if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`); });
const screenshot = async name => {
  await page.evaluate(async () => { await Promise.all(Array.from(document.images).map(img => img.decode().catch(() => {}))); });
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  return page.screenshot({ path: `docs/qa/${name}.png`, animations: 'disabled' });
};
const save = () => page.evaluate(() => JSON.parse(localStorage.getItem('sporelight.save.v2')));
try {
  await page.goto('http://127.0.0.1:4173/');
  await page.locator('#playerNameInput').waitFor();
  await page.locator('#playerNameInput').fill('<bad>'); await page.getByRole('button', { name: '开始旅程', exact: true }).click();
  await page.locator('#nameError').filter({ hasText: '请输入' }).waitFor();
  await page.locator('#playerNameInput').fill('露薇'); await page.locator('#playerNameInput').press('Enter');
  await page.locator('.journey-menu').waitFor(); await screenshot('01-main-menu'); checks.push('Naming validation and menu');
  await page.locator('[data-action="设置"]').click();
  await page.locator('[data-setting-toggle="lowMotion"]').click();
  await page.locator('[data-setting-slider="bgm"]').fill('0');
  await page.keyboard.press('Escape');
  await page.locator('[data-action="开始游戏"]').click();
  assert.equal(await page.locator('[data-level]:not(:disabled)').count(), 1);
  await screenshot('02-chapter-map'); await page.locator('[data-level="1-1"]').click();
  for (const level of LEVELS) {
    await page.locator('#gameCanvas').waitFor();
    let model = new GameModel(level, (await save()).run);
    if (level.id === '1-2') {
      await page.locator('[data-node="n1"]').click();
      assert.equal((await save()).run.node, 'start');
      await page.locator('[data-node="n0"]').click();
      await page.waitForFunction(() => JSON.parse(localStorage.getItem('sporelight.save.v2')).run.node === 'n0');
      await page.locator('[data-action="播种"]').click();
      assert.equal((await save()).run.activated.length, 1);
      await page.locator('[data-action="撤销"]').click();
      assert.equal((await save()).run.activated.length, 0);
      await page.locator('[data-action="提示"]').click();
      await page.locator('#gameTip').filter({ hasText: '亮圈' }).waitFor();
      model = new GameModel(level, (await save()).run);
      checks.push('UI rejects blocked bridge; planting, undo and contextual hint work');
    }
    if (level.id === '1-1') {
      await screenshot('03-game-valley');
      const before = (await save()).run;
      await page.locator('[data-action="设置"]').first().click();
      await page.keyboard.press('e');
      assert.deepEqual((await save()).run, before);
      await screenshot('04-settings'); await page.keyboard.press('Escape');
      await page.setViewportSize({ width: 844, height: 390 }); await screenshot('05-mobile-landscape');
      assert.deepEqual((await save()).run, before);
      await page.setViewportSize({ width: 390, height: 844 }); await screenshot('06-mobile-portrait');
      const bounds = await page.locator('.journey-toolbar').boundingBox(); assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 391);
      await page.setViewportSize({ width: 1280, height: 720 }); checks.push('Pause and resize preserve gameplay; portrait controls visible');
    }
    const walk = async id => {
      const route = model.pathTo(id); assert.ok(route);
      for (const node of route.slice(1)) {
        await page.locator(`[data-node="${node}"]`).click(); model.move(node);
        if (!model.state.completed) await page.waitForFunction(id => JSON.parse(localStorage.getItem('sporelight.save.v2')).run?.node === id, node);
      }
    };
    for (let i = 0; i < 40 && !model.state.completed; i++) {
      const collectible = level.nodes.find(n => n.spore && !model.state.collected.includes(n.id) && model.pathTo(n.id));
      if (collectible) { await walk(collectible.id); continue; }
      const mechanism = level.nodes.find(n => n.mechanism && !model.state.activated.includes(n.id) && model.pathTo(n.id));
      if (mechanism) {
        await walk(mechanism.id);
        for (let j = 0; j < 3 && !model.state.activated.includes(mechanism.id); j++) {
          await page.keyboard.press('e'); model.interact(0, true);
          await page.waitForFunction(angles => JSON.stringify(JSON.parse(localStorage.getItem('sporelight.save.v2')).run?.angles) === JSON.stringify(angles), model.state.angles);
        }
        await page.waitForFunction(id => JSON.parse(localStorage.getItem('sporelight.save.v2')).run?.activated.includes(id), mechanism.id);
        if (level.id === '1-3' && mechanism.id === 'n0') {
          const run = (await save()).run; await page.reload(); await page.locator('.journey-menu').waitFor();
          await page.locator('[data-action="继续旅程"]').click(); await page.locator('#gameCanvas').waitFor();
          assert.deepEqual((await save()).run, run); checks.push('Refresh resumes exact position, inventory and mechanism state');
        }
        if (level.id === '2-2' && mechanism.id === 'n1') await screenshot('07-reflection');
        if (level.id === '3-4' && mechanism.id === 's5') await screenshot('08-finale-ritual');
        continue;
      }
      await walk(level.exit);
    }
    await page.locator('.journey-result').waitFor();
    const progress = (await save()).levels[level.id]; assert.equal(progress.completed, true); assert.equal(progress.bestStars, 3);
    assert.equal(progress.bestCollected, level.nodes.filter(n => n.spore).length);
    checks.push(`${level.id} completed through real UI with all spores and three stars`);
    if (level.id === '1-1') await screenshot('09-result');
    if (level.id !== '3-4') await page.locator('[data-action="下一关"]').click();
  }
  await screenshot('10-ending'); await page.locator('[data-action="图鉴"]').click();
  assert.equal(await page.locator('.gallery-card.unlocked').count(), 8);
  await page.locator('[data-gallery-id="starflower"]').click();
  await page.locator('#galleryDetail .detail-title').filter({ hasText: '星花' }).waitFor();
  await screenshot('11-gallery');
  await page.locator('[data-gallery-cat="生物"]').click(); assert.equal(await page.locator('.gallery-card:visible').count(), 1);
  checks.push('All eight gallery entries unlocked; category filter works');
  assert.deepEqual(errors, []);
  await writeFile('docs/qa/browser-check.json', JSON.stringify({ browser: 'Chromium (Playwright)', date: '2026-10-19', checks, errors }, null, 2));
  console.log(JSON.stringify({ checks, errors }, null, 2));
} catch (error) {
  await screenshot('failure'); console.error('Browser errors:', errors); throw error;
} finally { await browser.close(); }

import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const option = (name, fallback) => process.argv.find(value => value.startsWith(`--${name}=`))?.slice(name.length + 3) ?? fallback;
const base = option('base', 'http://localhost:4185/');
const output = resolve(option('output', resolve(root, 'docs/qa-godot-migration/web-services')));
const modulePath = option('playwright', process.env.PLAYWRIGHT_MODULE ?? 'C:/Users/jeffrey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const {chromium} = createRequire(import.meta.url)(modulePath);
const reference = JSON.parse(await readFile(resolve(root, 'godot/tests/fixtures/reference.json'), 'utf8'));
const first = reference.cases.find(entry => entry.name === 'authored/1-1');
const third = reference.cases.find(entry => entry.name === 'authored/1-3');
const memory = structuredClone(first.steps.at(-1).snapshot);
const ongoing = structuredClone(third.initial.snapshot);
const cloudRaw = JSON.stringify({version: 1, lastLevel: 'cloud-2', records: {'cloud-1': {completed: true, collected: 2}}, syntheticOnly: 'isolated-browser-fixture'});
const oldKeys = {
  'sporelight.save.v2': JSON.stringify({version: 2, playerName: '迁移旅人', hasNamed: true, lastLevel: '1-3', settings: {bgm: 0, sfx: 0.2, ambient: 0, lowMotion: true, dynamicLight: false, particles: false}, gallery: {flowerbud: true}, levels: {'1-1': {completed: true, bestStars: 1, bestCollected: 1}, '1-2': {completed: true, bestStars: 2, bestCollected: 2}}}),
  'sporelight.garden2.v1': JSON.stringify({version: 1, lastLevel: '1-3', runs: {'1-3': ongoing}, memories: {'1-1': memory}, records: {'1-1': {completed: true, stars: 3, collected: 3}}}),
  'sporelight.cloud-gardens.v1': cloudRaw
};
await mkdir(output, {recursive: true});
const checks = [], errors = [], actions = [];
const browser = await chromium.launch({channel: 'chrome', headless: true});
const context = await browser.newContext({viewport: {width: 1440, height: 900}, acceptDownloads: true});
await context.route('**/favicon.ico', route => route.fulfill({status: 204, body: ''}));
// Brand-new browser context only. No attachment to the user's tab/profile.
await context.addInitScript(keys => {for (const [key, value] of Object.entries(keys)) localStorage.setItem(key, value);}, oldKeys);
const page = await context.newPage();
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {if (message.type() === 'error') errors.push(message.text());});
page.on('response', response => {if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) errors.push(`${response.status()} ${response.url()}`);});
const state = () => page.evaluate(() => structuredClone(window.__sporelightState));
const check = (condition, description) => {assert.ok(condition, description); checks.push(description);};

async function currentButton(text, disabled = false) {
  return (await state()).buttons.find(button => button.text === text && (disabled || !button.disabled));
}

async function button(text) {
  for (let attempt = 0; attempt < 14; attempt++) {
    const item = await currentButton(text);
    assert.ok(item, `Enabled button exists: ${text}`);
    const canvas = await page.locator('#canvas').boundingBox();
    const backing = await page.locator('#canvas').evaluate(element => ({width: element.width, height: element.height}));
    const middleY = item.y + item.height / 2;
    // Modal content is scrollable; exercise real wheel input to expose it.
    if (text !== '地图' && text !== '返回' && (middleY < 190 || middleY > 720)) {
      await page.mouse.move(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2);
      await page.mouse.wheel(0, Math.max(-600, Math.min(600, middleY - 450)));
      await page.waitForTimeout(160);
      continue;
    }
    await page.mouse.click(canvas.x + (item.x + item.width / 2) * canvas.width / backing.width, canvas.y + middleY * canvas.height / backing.height);
    actions.push({kind: 'mouse', button: text});
    await page.waitForTimeout(180);
    return;
  }
  throw new Error(`Could not scroll button into view: ${text}`);
}

async function openTools() {
  await button('地图');
  await button('导入 / 导出旅程');
  await page.waitForFunction(() => window.__sporelightState?.buttons.some(button => button.text === '读取本网站的旧旅程（先预览）'), {}, {timeout: 5000});
}

async function download(name) {
  const pending = page.waitForEvent('download', {timeout: 10000});
  await button('导出当前旅程');
  const artifact = await pending;
  const target = resolve(output, name);
  await artifact.saveAs(target);
  check(artifact.suggestedFilename() === 'sporelight-save.json', 'JSBridge downloads a named versioned JSON save');
  return JSON.parse(await readFile(target, 'utf8'));
}

try {
  const url = new URL(base);
  url.searchParams.set('qa', '1');
  await page.goto(url.href, {waitUntil: 'networkidle'});
  await page.waitForFunction(() => window.__sporelightState?.snapshot && typeof window.__sporelightRequest === 'function', {}, {timeout: 120000});
  check(!(await state()).progress.records['1-1'], 'Legacy browser data is not imported automatically');
  await openTools();
  await page.screenshot({path: resolve(output, '01-before-import.png')});
  const before = structuredClone((await state()).progress);
  await button('读取本网站的旧旅程（先预览）');
  await page.waitForFunction(() => window.__sporelightState?.buttons.some(button => button.text === '确认导入' && !button.disabled), {}, {timeout: 5000});
  assert.deepEqual((await state()).progress, before);
  checks.push('Reading legacy browser keys previews without changing progress');
  await page.screenshot({path: resolve(output, '02-import-preview.png')});
  await button('确认导入');
  await page.waitForFunction(() => window.__sporelightState?.progress?.records?.['1-1']?.collected === 3, {}, {timeout: 5000});
  const imported = await state();
  check(imported.snapshot.levelId === '1-3', 'Confirmed import resumes the original last level');
  check(imported.progress.records['1-1'].stars === 3 && imported.progress.records['1-1'].collected === 3, 'New mainline records take priority over old lower scores');
  check(imported.progress.records['1-2'].completed && imported.progress.records['1-2'].collected === 2, 'Old record fallback fills a missing mainline record');
  assert.deepEqual(imported.progress.runs['1-3'].actors, ongoing.actors);
  assert.deepEqual(imported.progress.memories['1-1'], memory);
  checks.push('Active runs and authentic completion memories survive browser import');
  await button('回到花园');
  await page.keyboard.press('ArrowLeft');
  actions.push({kind: 'keyboard', key: 'ArrowLeft'});
  await page.waitForFunction(() => window.__sporelightState?.snapshot?.actors?.luvie === 'f:-5:0' && !window.__sporelightState?.moving, {}, {timeout: 5000});
  await openTools();
  const exported = await download('export-after-import-and-move.json');
  check(exported.format === 'sporelight.godot' && exported.version === 1, 'Downloaded save identifies its format and version');
  check(exported.player.name === '迁移旅人' && exported.player.has_named, 'Player name and naming state survive import and export');
  check(exported.settings.bgm === 0 && exported.settings.sfx === 0.2 && exported.settings.lowMotion && !exported.settings.dynamicLight && !exported.settings.particles, 'Settings survive the real browser migration path');
  check(exported.legacy_raw['sporelight.cloud-gardens.v1'] === cloudRaw, 'Independent cloud data remains byte-for-byte intact');
  for (const [key, raw] of Object.entries(oldKeys)) check(exported.legacy_raw[key] === raw, `Original raw data retained: ${key}`);
  check(exported.mainline.runs['1-3'].actors.luvie === 'f:-5:0', 'Downloaded JSON includes progress made after the import');
  await page.screenshot({path: resolve(output, '03-exported.png')});
  await button('回到花园');
  await page.reload({waitUntil: 'networkidle'});
  await page.waitForFunction(() => window.__sporelightState?.snapshot?.actors?.luvie === 'f:-5:0', {}, {timeout: 120000});
  check((await state()).progress.memories['1-1'].completed, 'IndexedDB persistence survives reload with the archived memory');
  await openTools();
  const unchanged = structuredClone((await state()).progress);
  await button('导出当前旅程');
  // The clicked export button has focus. Four preceding focusable controls
  // lead to TextEdit through the real Godot focus path.
  await page.keyboard.press('Shift+Tab');
  await page.keyboard.press('Shift+Tab');
  await page.keyboard.press('Shift+Tab');
  await page.keyboard.press('Shift+Tab');
  await page.keyboard.press('Control+a');
  await page.keyboard.type('{broken-json');
  actions.push({kind: 'keyboard', text: '{broken-json', target: 'TextEdit'});
  await button('检查粘贴的旅程');
  check((await currentButton('确认导入', true)).disabled, 'Broken pasted JSON keeps import confirmation disabled');
  assert.deepEqual((await state()).progress, unchanged);
  checks.push('Broken pasted JSON cannot overwrite existing progress');
  await page.screenshot({path: resolve(output, '04-rejected-json.png')});
  const stillValid = await download('export-after-invalid-import.json');
  assert.deepEqual(stillValid.mainline, exported.mainline);
  check(stillValid.player.name === exported.player.name && stillValid.legacy_raw['sporelight.cloud-gardens.v1'] === cloudRaw, 'Rejected import leaves player data and cloud data unchanged');
  const originalKeys = await page.evaluate(keys => Object.fromEntries(keys.map(key => [key, localStorage.getItem(key)])), Object.keys(oldKeys));
  assert.deepEqual(originalKeys, oldKeys);
  checks.push('Browser legacy keys remain unchanged after preview, import and download');
  assert.deepEqual(errors, []);
} catch (error) {
  errors.push(error.stack ?? String(error));
  await page.screenshot({path: resolve(output, 'failure.png')}).catch(() => {});
  await writeFile(resolve(output, 'failure-state.json'), JSON.stringify(await state().catch(() => null), null, 2));
  process.exitCode = 1;
} finally {
  await writeFile(resolve(output, 'checks.json'), JSON.stringify({date: new Date().toISOString(), base, isolatedContext: true, checks, actions, errors}, null, 2) + '\n');
  await context.close();
  await browser.close();
}
console.log(JSON.stringify({checks: checks.length, errors, output}, null, 2));

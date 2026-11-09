import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';

// QA is observation only. This suite makes no snapshot/action write requests.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const option = (key, fallback) => process.argv.find(v => v.startsWith(`--${key}=`))?.slice(key.length + 3) ?? fallback;
const base = option('base', 'http://localhost:4186/');
const output = resolve(option('output', resolve(tmpdir(), 'sporelight-home-navigation')));
const sizes = option('sizes', '1280x720,390x844,568x320,594x462').split(',').map(value => {
  const parts = /^(\d+)x(\d+)$/.exec(value); assert.ok(parts, '--sizes=WIDTHxHEIGHT,...');
  return {width: Number(parts[1]), height: Number(parts[2])};
});
const inputs = option('inputs', 'mouse,touch').split(',');
assert.ok(inputs.every(input => ['mouse', 'touch'].includes(input)), '--inputs=mouse,touch');
const selectedCases = option('cases', '').split(',').filter(Boolean);
const {chromium} = createRequire(import.meta.url)(option('playwright', process.env.PLAYWRIGHT_MODULE ?? 'C:/Users/jeffrey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'));
const fixture = JSON.parse(await readFile(resolve(root, 'godot/tests/fixtures/reference.json'), 'utf8'));
const authored = fixture.cases.find(entry => entry.name === 'authored/1-1');
const initial = authored.initial.snapshot;
const normalize = (value, key = '') => key === 'trial' && typeof value === 'string' ? normalize(JSON.parse(value)) : Array.isArray(value) ? value.map(v => normalize(v)) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k => [k, normalize(value[k], k)])) : Object.is(value, -0) ? 0 : value;
const equivalent = (left, right) => JSON.stringify(normalize(left)) === JSON.stringify(normalize(right));
const controls = state => state.ui?.controls ?? [];
const matches = (control, query) => typeof query === 'string' ? control.text === query : Object.entries(query).every(([key, value]) => key === 'includes' ? String(control.text).includes(value) : control[key] === value);
const rect = control => control.visibleRect ?? [control.x, control.y, control.width, control.height];
const cut = (a, b) => {const x = Math.max(a[0], b[0]), y = Math.max(a[1], b[1]); return [x, y, Math.max(0, Math.min(a[0] + a[2], b[0] + b[2]) - x), Math.max(0, Math.min(a[1] + a[3], b[1] + b[3]) - y)];};
const results = [], errors = [];
let browser = null, build = null, fatal = null;
await mkdir(output, {recursive: true});

async function run(size, input, name, body) {
  if (selectedCases.length && !selectedCases.some(value => name.includes(value))) return;
  const row = `${size.width}x${size.height}-${input}-${name}`, folder = resolve(output, row);
  await mkdir(folder, {recursive: true});
  const context = await browser.newContext({viewport: size, deviceScaleFactor: 1, hasTouch: input === 'touch', acceptDownloads: true});
  await context.route('**/favicon.ico', route => route.fulfill({status: 204, body: ''}));
  await context.addInitScript(() => {
    window.__homeEvents = [];
    for (const type of ['pointerdown', 'pointerup', 'keydown', 'keyup']) window.addEventListener(type, event => {
      const s = window.__sporelightState, canvas = document.querySelector('#canvas'), r = canvas?.getBoundingClientRect();
      const x = r ? (event.clientX - r.x) * canvas.width / r.width : null, y = r ? (event.clientY - r.y) * canvas.height / r.height : null;
      const hits = (s?.buttons ?? []).filter(button => {const b = button.visibleRect ?? [button.x, button.y, button.width, button.height]; return x >= b[0] && y >= b[1] && x < b[0] + b[2] && y < b[1] + b[3];}).map(button => ({text: button.text, action: button.action, disabled: button.disabled, instanceId: button.instanceId}));
      window.__homeEvents.push({type, trusted: event.isTrusted, pointerType: event.pointerType, key: event.key, at: performance.now(), target: event.target?.id,
        homeActive: s?.homeActive, paused: s?.paused, moving: s?.moving, revision: s?.revision, qaSequence: s?.qaSequence, hits});
    }, true);
  });
  const page = await context.newPage(), evidence = [], started = Date.now(), errorStart = errors.length;
  let phase = 'startup', result;
  const noteError = (kind, message) => errors.push({row, phase, kind, message});
  page.on('pageerror', error => noteError('javascript', error.message));
  page.on('console', message => {if (message.type() === 'error' || /SCRIPT ERROR:|ERROR:/.test(message.text())) noteError('godot/browser', message.text());});
  page.on('response', response => {if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) noteError('http', `${response.status()} ${response.url()}`);});
  const wait = (predicate, argument, timeout = 12000) => page.waitForFunction(predicate, argument, {timeout, polling: 10});
  const state = () => page.evaluate(() => structuredClone(window.__sporelightState));
  const fresh = async () => {const before = (await state())?.qaSequence; assert.ok(Number.isFinite(before)); await wait(sequence => window.__sporelightState?.qaSequence > sequence, before); return state();};
  const visible = (control, current) => cut(rect(control), [0, 0, ...(current.viewport ?? [size.width, size.height])]);
  const coordinate = async (control, current) => {
    const r = visible(control, current); assert.ok(r.every(Number.isFinite) && r[2] > 1 && r[3] > 1, 'A real visible hit area exists inside the viewport');
    const canvas = await page.locator('#canvas').boundingBox(), backing = await page.locator('#canvas').evaluate(element => ({width: element.width, height: element.height}));
    return {x: canvas.x + (r[0] + r[2] / 2) * canvas.width / backing.width, y: canvas.y + (r[1] + r[3] / 2) * canvas.height / backing.height};
  };
  const find = async (query, {allowDisabled = false} = {}) => {
    for (let attempt = 0; attempt < 24; attempt++) {
      const current = await fresh(), target = controls(current).filter(c => /Button$/.test(c.class) && matches(c, query)).at(-1);
      if (target) {
        const r = visible(target, current);
        if (r[2] > 1 && r[3] > 1) {assert.ok(allowDisabled || !target.disabled, `The requested real control is enabled: ${target.text}`); return {control: target, state: current};}
      }
      if (!target && attempt < 3) continue;
      const owner = controls(current).filter(c => c.class === 'ScrollContainer' && (!target || target.path.startsWith(c.path + '/')))
        .filter(c => visible(c, current)[2] > 1 && visible(c, current)[3] > 1).sort((a, b) => target ? b.path.length - a.path.length : rect(b)[2] * rect(b)[3] - rect(a)[2] * rect(a)[3])[0];
      assert.ok(owner, `A real scrolling ancestor exists for ${JSON.stringify(query)}`);
      const r = visible(owner, current), direction = target && target.y < r[1] ? -1 : target && target.y + target.height > r[1] + r[3] ? 1 : attempt < 16 ? 1 : -1;
      const point = await coordinate(owner, current); evidence.push({phase, kind: 'scroll', input: 'mouse-wheel', owner: owner.path, target: target?.path, direction});
      await page.mouse.move(point.x, point.y); await page.mouse.wheel(0, direction * 260); await page.waitForTimeout(60);
    }
    throw Error(`Control did not become visible through actual scrolling: ${JSON.stringify(query)}`);
  };
  const click = async (query, options) => {
    const found = await find(query, options), point = await coordinate(found.control, found.state), eventStart = await page.evaluate(() => window.__homeEvents.length);
    if (query?.action === 'home') assert.equal(found.control.text, '返回主界面', 'Home navigation has an explicit destination label');
    if (input === 'touch') await page.touchscreen.tap(point.x, point.y); else await page.mouse.click(point.x, point.y);
    const downs = await page.evaluate(start => window.__homeEvents.slice(start).filter(event => event.type === 'pointerdown'), eventStart);
    assert.equal(downs.length, 1, 'One trusted pointer press performs the advertised navigation');
    assert.ok(downs[0].trusted && downs[0].target === 'canvas' && downs[0].pointerType === input && downs[0].hits.some(hit => hit.instanceId === found.control.instanceId), 'The real press hits the actual requested button instance');
    evidence.push({phase, kind: 'button', query, button: found.control, point, event: downs[0]}); await fresh(); return found.control;
  };
  const expectSnapshot = async (expected, description) => {
    phase = description;
    await wait(expected => {
      const s = window.__sporelightState, norm = (v, key = '') => key === 'trial' && typeof v === 'string' ? norm(JSON.parse(v)) : Array.isArray(v) ? v.map(x => norm(x)) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, norm(v[k], k)])) : Object.is(v, -0) ? 0 : v;
      return s && !s.moving && JSON.stringify(norm(s.snapshot)) === JSON.stringify(norm(expected));
    }, expected);
    assert.ok(equivalent((await state()).snapshot, expected), description + ': complete rule snapshot agrees');
  };
  const assertHome = async description => {
    phase = description;
    await wait(() => {const s = window.__sporelightState; return s?.homeActive === true && s.worldVisible === false && s.gameHudVisible === false && s.paused === true && s.ui?.modalOpen === true
      && (s.ui.controls ?? []).some(c => /Button$/.test(c.class) && c.action === 'map') && (s.ui.controls ?? []).some(c => /Button$/.test(c.class) && c.action === 'continue');});
    const current = await fresh();
    assert.ok(!controls(current).some(c => ['primary', 'mode', 'jump', 'undo', 'restart', 'switch', 'hint'].includes(c.action)), 'A genuine home contains no visible in-level operation controls');
    assert.ok(!controls(current).some(c => /\/(?:Heading|NearbyActions|JourneyTools|DirectionPad)\//.test(c.path)), 'The level heading and controls are hidden, not behind another menu');
    evidence.push({phase, kind: 'home-state', homeActive: current.homeActive, worldVisible: current.worldVisible, gameHudVisible: current.gameHudVisible, paused: current.paused, revision: current.revision});
    return current;
  };
  const assertGame = async description => {
    phase = description; await wait(() => {const s = window.__sporelightState; return s?.homeActive === false && s.worldVisible === true && s.gameHudVisible === true && s.paused === false && s.ui?.modalOpen === false;});
    return fresh();
  };
  const noWorldInputAtHome = async description => {
    const before = await assertHome(description); await page.keyboard.press('ArrowRight'); await page.keyboard.press('e'); await page.waitForTimeout(250);
    const after = await fresh(); assert.ok(equivalent(after.snapshot, before.snapshot), 'Direction and E at home cannot change the hidden level');
    assert.equal(after.revision, before.revision, 'Home input does not create rule history'); assert.equal(after.moving, false, 'Home input cannot start a hidden animation');
    assert.equal(after.pendingButton, '', 'Home input does not queue a later interaction');
  };
  const startFirstGarden = async () => {
    await click({action: 'map'}); await wait(() => (window.__sporelightState?.ui?.controls ?? []).some(c => c.class === 'Label' && c.text === '关卡地图'));
    await click({includes: '1-1  '}); await assertGame('map enters the first garden'); await expectSnapshot(initial, 'a real map selection creates the original initial garden');
  };
  try {
    const url = new URL(base); url.searchParams.set('qa', '1'); url.searchParams.set('home', '1'); url.searchParams.set('unlockAll', '0');
    await page.goto(url.href, {waitUntil: 'networkidle', timeout: 120000}); await wait(() => window.__sporelightState?.snapshot, undefined, 120000);
    const tools = {page, state, fresh, wait, click, find, expectSnapshot, assertHome, assertGame, noWorldInputAtHome, startFirstGarden,
      screenshot: name => page.screenshot({path: resolve(folder, name + '.png')}), mark: value => {phase = value;}, evidence};
    const details = await body(tools); assert.equal(errors.length, errorStart, 'The navigation produced no JavaScript, Godot or HTTP errors'); result = {row, viewport: size, input, name, passed: true, details};
  } catch (error) {
    result = {row, viewport: size, input, name, passed: false, phase, reason: String(error), actual: await state().catch(() => null)};
    await page.screenshot({path: resolve(folder, 'failure.png')}).catch(() => {});
  } finally {
    const events = await page.evaluate(() => window.__homeEvents).catch(() => []);
    await writeFile(resolve(folder, 'evidence.json'), JSON.stringify({evidence, events}, null, 2) + '\n'); await context.close();
  }
  result.elapsedMs = Date.now() - started; results.push(result); await writeFile(resolve(folder, 'checks.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({row, passed: result.passed, phase: result.phase, reason: result.reason, elapsedMs: result.elapsedMs}));
}

try {
  build = await fetch(new URL('/__build.json', base)).then(response => {assert.ok(response.ok); return response.json();});
  browser = await chromium.launch({channel: 'chrome', headless: true});
  for (const size of sizes) for (const input of inputs) {
    await run(size, input, 'home-pages-and-saved-seed-continue', async t => {
      const home = await t.assertHome('fresh launch is a genuine home');
      const disabled = await t.find({action: 'continue'}, {allowDisabled: true}); assert.equal(disabled.control.disabled, true, 'A new journey does not advertise a nonexistent saved game');
      await t.click({action: 'continue'}, {allowDisabled: true}); await t.expectSnapshot(home.snapshot, 'disabled fresh-home continue cannot start a level'); await t.assertHome('disabled continue stays home');
      await t.noWorldInputAtHome('fresh home blocks hidden level input');
      for (const title of ['设置', '图鉴', '花园纪事', '导入 / 导出旅程']) {
        t.mark('home child/' + title); await t.click(title); const child = await t.fresh();
        assert.equal(child.homeActive, true); assert.equal(child.worldVisible, false); assert.equal(child.gameHudVisible, false); assert.equal(child.paused, true);
        assert.ok(!controls(child).some(c => c.text === '继续当前关卡'), 'A home child does not pretend it is an in-level pause');
        await t.click({action: 'home'}); await t.assertHome('home child returns to actual home: ' + title);
      }
      await t.click('设置'); await t.page.keyboard.press('Escape'); await t.assertHome('Escape from home settings cannot resume a hidden level');
      await t.screenshot('fresh-home'); await t.startFirstGarden();
      await t.click({command_id: 'grow:root:down'}); await t.expectSnapshot(authored.steps[0].snapshot, 'a real seed button grows the original downward road');
      await t.page.keyboard.press('ArrowDown'); await t.expectSnapshot(authored.steps[1].snapshot, 'a real direction enters the planted road');
      const committed = await t.state(); await t.click('Ⅱ'); await t.click({action: 'home'}); await t.assertHome('return-to-home actually leaves the level view');
      await t.expectSnapshot(committed.snapshot, 'returning home preserves the committed seed road and position'); await t.noWorldInputAtHome('home after playing blocks world input'); await t.screenshot('returned-home');
      const active = await t.find({action: 'continue'}); assert.equal(active.control.disabled, false, 'A saved active garden exposes continue');
      await t.page.reload({waitUntil: 'networkidle', timeout: 120000}); await t.wait(() => window.__sporelightState?.snapshot, undefined, 120000);
      await t.assertHome('a Web reload returns to home rather than silently entering 1-1'); await t.expectSnapshot(committed.snapshot, 'the same Web save restores the committed seed road');
      await t.click({action: 'continue'}); await t.assertGame('continue opens the saved garden'); await t.expectSnapshot(committed.snapshot, 'continue preserves the original planted road and position');
      const resumed = await t.state(); await t.page.keyboard.press('ArrowUp'); await t.expectSnapshot(authored.steps[0].snapshot, 'real movement works after continuing the saved garden');
      assert.equal((await t.state()).revision, resumed.revision + 1); await t.screenshot('continued-game');
      return {qaWriteRequests: 0, homeChildPages: 4, savedRoad: 'g:root:0:1', reload: true, directionAndPrimaryBlockedAtHome: true, actualMovementAfterContinue: true};
    });
    await run(size, input, 'home-cancels-uncommitted-seed-without-ghost-replay', async t => {
      await t.assertHome('fresh home'); await t.startFirstGarden(); const original = await t.state();
      await t.click({action: 'primary'}); await t.wait(() => window.__sporelightState?.moving && window.__sporelightState.motion?.kind === 'grow:root:right' && window.__sporelightState.revision === 0);
      await t.click('Ⅱ'); await t.wait(() => window.__sporelightState?.paused && window.__sporelightState.moving && window.__sporelightState.motion?.kind === 'grow:root:right');
      const paused = await t.state(); assert.equal(paused.revision, 0, 'The actual pause arrived before the seed committed'); assert.ok(equivalent(paused.snapshot, original.snapshot));
      await t.click({action: 'home'}); await t.assertHome('home cancels the unfinished action'); await t.expectSnapshot(original.snapshot, 'an unfinished seed cannot appear in the home save');
      const home = await t.state(); assert.equal(home.revision, 0); assert.equal(home.pendingButton, ''); assert.deepEqual(home.input.held, []); assert.equal(home.input.buffered, '');
      await t.click({action: 'continue'}); await t.assertGame('continue after cancelling an unfinished seed'); await t.expectSnapshot(original.snapshot, 'continue restores only committed state');
      await t.page.waitForTimeout(400); await t.expectSnapshot(original.snapshot, 'cancelled growth never replays behind the new screen'); assert.equal((await t.state()).revision, 0);
      await t.page.keyboard.press('e'); const right = structuredClone(initial); right.growth.root = ['g:root:1:0']; await t.expectSnapshot(right, 'a new deliberate E still plants one original road'); assert.equal((await t.state()).revision, 1);
      return {qaWriteRequests: 0, pendingGrowthWasActuallyPaused: true, cancelledSeedNotSaved: true, ghostReplay: false, deliberateNewSeedCommits: 1};
    });
  }
} catch (error) {fatal = String(error); process.exitCode = 1;}
finally {
  if (browser) await browser.close();
  const passed = !fatal && results.length > 0 && results.every(result => result.passed) && errors.length === 0;
  const report = {date: new Date().toISOString(), passed, base, build, sizes, inputs, results, errors, fatal,
    summary: {executed: results.length, passed: results.filter(result => result.passed).length, failed: results.filter(result => !result.passed).length},
    scope: 'Fresh isolated Web storage per case. QA observes only (qa=1&home=1&unlockAll=0); no snapshot or action write requests. All navigation and seed/movement actions use trusted pointer/key input. Returning home is independently distinguished from closing a pause overlay or opening the map.',
    limitations: ['Mouse-wheel scrolling is real but does not certify touch inertia or swipe gestures.', 'Controller snapshots and visibility flags are not a GPU pixel/performance or native desktop dialog verdict.', 'The interrupted seed case fails unless the actual settings action pauses an uncommitted seed; no synthetic signal replaces that precondition.']};
  await writeFile(resolve(output, 'checks.json'), JSON.stringify(report, null, 2) + '\n'); if (!passed) process.exitCode = 1;
  console.log(JSON.stringify({passed, ...report.summary, errors: errors.length, fatal, output}));
}

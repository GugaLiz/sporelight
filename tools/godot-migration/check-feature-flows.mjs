import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';

// This suite uses QA for observation and one initial legal fixture per garden.
// Every command being tested goes through a trusted key or an actual button.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const option = (key, fallback) => process.argv.find(v => v.startsWith(`--${key}=`))?.slice(key.length + 3) ?? fallback;
const base = option('base', 'http://localhost:4186/');
const output = resolve(option('output', resolve(tmpdir(), 'sporelight-feature-flows')));
const phase = option('phase', 'all');
const input = option('input', 'mouse');
const selectedLevels = option('levels', '').split(',').filter(Boolean);
const dimensions = /^(\d+)x(\d+)$/.exec(option('size', '1280x720'));
assert.ok(dimensions, '--size=WIDTHxHEIGHT');
assert.ok(['all', 'levels', 'progression', 'settings'].includes(phase), '--phase=all|levels|progression|settings');
assert.ok(['mouse', 'touch'].includes(input), '--input=mouse|touch');
const viewport = {width: Number(dimensions[1]), height: Number(dimensions[2])};
assert.ok(viewport.width >= 240 && viewport.height >= 240, 'The viewport must be at least 240px in each dimension');
const {chromium} = createRequire(import.meta.url)(option('playwright', process.env.PLAYWRIGHT_MODULE ?? 'C:/Users/jeffrey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'));
const fixture = JSON.parse(await readFile(resolve(root, 'godot/tests/fixtures/reference.json'), 'utf8'));
const authored = fixture.cases.filter(entry => entry.name.startsWith('authored/'));
assert.equal(authored.length, 12, 'The authored solution suite covers all twelve gardens');
assert.ok(selectedLevels.every(id => authored.some(entry => entry.levelId === id)), '--levels contains only existing authored gardens');
const normalize = (value, key = '') => key === 'trial' && typeof value === 'string' ? normalize(JSON.parse(value)) : Array.isArray(value) ? value.map(v => normalize(v)) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k => [k, normalize(value[k], k)])) : Object.is(value, -0) ? 0 : value;
const equivalent = (a, b) => JSON.stringify(normalize(a)) === JSON.stringify(normalize(b));
const controls = state => state.ui?.controls ?? [];
const hasModal = state => state.hudRegions?.some(region => region.name === 'ModalOverlay') === true;
const rect = control => control.visibleRect ?? [control.x, control.y, control.width, control.height];
const intersection = (a, b) => {
  const x = Math.max(a[0], b[0]), y = Math.max(a[1], b[1]);
  return [x, y, Math.max(0, Math.min(a[0] + a[2], b[0] + b[2]) - x), Math.max(0, Math.min(a[1] + a[3], b[1] + b[3]) - y)];
};
const matches = (control, query) => typeof query === 'string' ? control.text === query : Object.entries(query).every(([key, value]) => key === 'includes' ? String(control.text).includes(value) : control[key] === value);
const errors = [], results = [];
let build = null, browser = null, fatal = null;
await mkdir(output, {recursive: true});

async function withPage(name, body) {
  const folder = resolve(output, name); await mkdir(folder, {recursive: true});
  const context = await browser.newContext({viewport, deviceScaleFactor: 1, hasTouch: input === 'touch', acceptDownloads: true});
  await context.route('**/favicon.ico', route => route.fulfill({status: 204, body: ''}));
  await context.addInitScript(() => {
    window.__featureFlowEvents = [];
    for (const type of ['pointerdown', 'pointerup', 'keydown', 'keyup']) window.addEventListener(type, event => {
      const s = window.__sporelightState;
      window.__featureFlowEvents.push({type, trusted: event.isTrusted, target: event.target?.id, pointerType: event.pointerType,
        key: event.key, x: event.clientX, y: event.clientY, at: performance.now(), revision: s?.revision,
        paused: s?.paused, moving: s?.moving, level: s?.snapshot?.levelId, qaSequence: s?.qaSequence});
    }, true);
  });
  const page = await context.newPage(), evidence = [], started = Date.now();
  const errorStart = errors.length;
  let expectedSnapshot = null, label = 'startup';
  const noteError = (kind, message) => errors.push({case: name, label, kind, message});
  page.on('pageerror', error => noteError('javascript', error.message));
  page.on('console', message => {if (message.type() === 'error' || /SCRIPT ERROR:|ERROR:/.test(message.text())) noteError('godot/browser', message.text());});
  page.on('response', response => {if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) noteError('http', `${response.status()} ${response.url()}`);});
  const wait = (predicate, value, timeout = 12000) => page.waitForFunction(predicate, value, {timeout, polling: 10});
  const state = () => page.evaluate(() => structuredClone(window.__sporelightState));
  const fresh = async () => {
    const sequence = (await state())?.qaSequence;
    assert.ok(Number.isFinite(sequence), 'The actual diagnostic publication sequence is observable');
    await wait(seq => window.__sporelightState?.qaSequence > seq, sequence);
    return state();
  };
  const inViewport = (control, current) => intersection(rect(control), [0, 0, ...(current.viewport ?? [viewport.width, viewport.height])]);
  const coordinate = async (control, current) => {
    const r = inViewport(control, current);
    assert.ok(r.every(Number.isFinite) && r[2] > 1 && r[3] > 1, 'A nonempty actual visible hit rectangle lies inside the viewport');
    const canvas = await page.locator('#canvas').boundingBox();
    const backing = await page.locator('#canvas').evaluate(element => ({width: element.width, height: element.height}));
    assert.ok(canvas && canvas.width > 0 && canvas.height > 0, 'The game canvas has real CSS geometry');
    const point = {x: canvas.x + (r[0] + r[2] / 2) * canvas.width / backing.width, y: canvas.y + (r[1] + r[3] / 2) * canvas.height / backing.height};
    assert.ok(point.x >= canvas.x && point.y >= canvas.y && point.x < canvas.x + canvas.width && point.y < canvas.y + canvas.height, 'Input stays inside the visible canvas');
    return point;
  };
  const tap = point => input === 'touch' ? page.touchscreen.tap(point.x, point.y) : page.mouse.click(point.x, point.y);
  const scrollToward = async (current, target, direction) => {
    const candidates = controls(current).filter(c => c.class === 'ScrollContainer');
    const owners = target?.path ? candidates.filter(c => target.path.startsWith(c.path + '/')).sort((a, b) => b.path.length - a.path.length) : [];
    const owner = owners[0] ?? candidates.filter(c => hasModal(current) ? !/\/(?:Heading|NearbyActions|JourneyMessage)\//.test(c.path) : c.path.includes('/NearbyActions/')).sort((a, b) => rect(b)[2] * rect(b)[3] - rect(a)[2] * rect(a)[3])[0];
    assert.ok(owner, 'A real ancestor scrolling container exists for the target');
    const r = inViewport(owner, current);
    assert.ok(r[2] > 1 && r[3] > 1, 'The actual scrolling container intersects the viewport');
    let sign = direction;
    if (target && target.y < r[1]) sign = -1;
    else if (target && target.y + target.height > r[1] + r[3]) sign = 1;
    const point = await coordinate({visibleRect: r}, current);
    evidence.push({label, kind: 'scroll', method: 'real-mouse-wheel', path: owner.path, target: target?.path, rect: r, direction: sign});
    await page.mouse.move(point.x, point.y); await page.mouse.wheel(0, sign * 260);
    await page.waitForTimeout(60);
  };
  const findControl = async (predicate, {allowDisabled = false} = {}) => {
    let disabledCount = 0;
    for (let attempt = 0; attempt < 24; attempt++) {
      const current = await fresh(), target = controls(current).filter(predicate).at(-1);
      if (target) {
        const r = inViewport(target, current);
        if (r[2] > 1 && r[3] > 1) {
          if (!target.disabled || allowDisabled) return {control: target, state: current};
          if (++disabledCount >= 3) throw Error(`The requested visible control remains disabled: ${target.text ?? target.name}`);
          continue;
        }
      }
      if (!target && attempt < 3) continue;
      await scrollToward(current, target, attempt < 16 ? 1 : -1);
    }
    throw Error('The requested actual control did not become visible after real scrolling');
  };
  const click = async (query, options) => {
    const found = await findControl(c => /Button$/.test(c.class) && matches(c, query), options);
    const point = await coordinate(found.control, found.state);
    evidence.push({label, kind: 'button', query, text: found.control.text, command: found.control.command_id, action: found.control.action, instanceId: found.control.instanceId, disabled: found.control.disabled, path: found.control.path, visibleRect: inViewport(found.control, found.state), point});
    await tap(point); await fresh();
    return found.control;
  };
  const expectSnapshot = async (expected, description) => {
    expectedSnapshot = structuredClone(expected); label = description;
    await wait(expected => {
      const s = window.__sporelightState;
      const norm = (v, key = '') => key === 'trial' && typeof v === 'string' ? norm(JSON.parse(v)) : Array.isArray(v) ? v.map(x => norm(x)) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, norm(v[k], k)])) : Object.is(v, -0) ? 0 : v;
      return s && !s.moving && JSON.stringify(norm(s.snapshot)) === JSON.stringify(norm(expected));
    }, expected);
    assert.ok(equivalent((await state()).snapshot, expected), description + ': complete rule snapshot agrees');
  };
  const assertNoModal = async oldButton => {
    await wait(oldId => {
      const s = window.__sporelightState;
      return s && !s.paused && !(s.hudRegions ?? []).some(r => r.name === 'ModalOverlay') && !(s.ui?.controls ?? []).some(c => c.instanceId === oldId);
    }, oldButton?.instanceId ?? -1);
    const actual = await state();
    assert.equal(hasModal(actual), false, 'The actual modal overlay disappeared');
    assert.equal(actual.paused, false, 'Game processing is no longer paused');
    assert.ok(!controls(actual).some(c => c.instanceId === oldButton?.instanceId), 'The clicked closing control was removed with its modal');
  };
  const close = async () => {const button = await click('继续当前关卡'); await assertNoModal(button);};
  const modeProof = async () => {
    const before = await state();
    await click({action: 'mode'});
    await wait(value => window.__sporelightState?.rolling === !value, before.rolling);
    const after = await state();
    assert.ok(equivalent(before.snapshot, after.snapshot), 'A real post-return mode click responds without a rule mutation');
    assert.equal(after.revision, before.revision, 'A post-return mode click does not create world history');
    await click({action: 'mode'}); await wait(value => window.__sporelightState?.rolling === value, before.rolling);
  };
  const disabledUndoProof = async () => {
    const before = await state();
    assert.equal(before.snapshot.completed, true, 'The disabled undo check runs in the actual completed garden');
    assert.equal(before.strolling, true, 'Completed browsing remains interactive for ordinary controls');
    const found = await findControl(c => c.class === 'Button' && c.action === 'undo', {allowDisabled: true});
    assert.equal(found.control.disabled, true, 'Undo is visibly disabled during completed-garden browsing');
    const reason = String(found.control.tooltip ?? '').trim();
    assert.ok(reason.length > 5 && /修复|完成/.test(reason) && /退回|撤销|回退/.test(reason), 'The disabled undo control explains the completion-related restriction');
    evidence.push({label, kind: 'completed-disabled-undo', reason, revision: before.revision});
    await click({action: 'undo'}, {allowDisabled: true});
    await fresh();
    await expectSnapshot(before.snapshot, 'a real click on disabled completed-garden undo preserves the complete snapshot');
    assert.equal((await state()).revision, before.revision, 'A real disabled undo click cannot create or replay history');
  };
  const openMap = async () => {await click('地图'); await wait(() => window.__sporelightState?.paused === true && window.__sporelightState.hudRegions?.some(r => r.name === 'ModalOverlay'));};
  const execute = async (previous, step, index) => {
    label = `command/${index}/${step.command.kind}/${step.command.value}`;
    if (step.command.kind === 'move') {
      const actor = previous.snapshot.active, from = previous.tiles.find(tile => tile.id === previous.snapshot.actors[actor]), to = previous.tiles.find(tile => tile.id === step.command.value);
      assert.ok(from && to, 'Both legal movement anchors exist in the frozen before-state');
      const dx = to.x - from.x, dz = to.z - from.z;
      assert.equal(Number(dx !== 0) + Number(dz !== 0), 1, 'A real cardinal key represents this authored movement edge');
      const key = dx > 0 ? 'ArrowRight' : dx < 0 ? 'ArrowLeft' : dz > 0 ? 'ArrowDown' : 'ArrowUp';
      evidence.push({label, kind: 'key', key, actor, from: from.id, to: to.id});
      await page.keyboard.press(key);
    } else {
      assert.equal(step.command.kind, 'act', 'Authored solutions only contain movement and interaction');
      assert.ok(previous.commands.some(c => c.id === step.command.value), 'The rule command was actually offered in the complete before-state');
      await click(step.command.value === 'switch' ? {action: 'switch'} : {command_id: step.command.value});
    }
    await expectSnapshot(step.snapshot, label);
    assert.equal((await state()).revision, index + 1, 'Each authored command commits exactly once');
  };
  const solve = async entry => {
    let previous = entry.initial;
    for (const [index, step] of entry.steps.entries()) {await execute(previous, step, index); previous = step;}
    await wait(() => {
      const s = window.__sporelightState;
      return s?.snapshot?.completed && s.paused && s.hudRegions?.some(r => r.name === 'ModalOverlay') && s.buttons?.some(b => b.text === '留下看看' && !b.disabled);
    });
    const complete = await state(), final = entry.steps.at(-1).snapshot;
    assert.ok(equivalent(complete.progress?.memories?.[entry.levelId], final), 'The actual completed memory is the final rule snapshot');
    assert.equal(complete.progress.records[entry.levelId].completed, true, 'Completion records are written by the actual repair command');
    await page.screenshot({path: resolve(folder, 'completed.png')});
    return complete;
  };
  const tools = {page, state, fresh, wait, click, close, findControl, coordinate, tap, expectSnapshot, assertNoModal, modeProof, disabledUndoProof, openMap, solve,
    evidence, mark: value => {label = value;}};
  let result;
  try {
    const url = new URL(base); url.searchParams.set('qa', '1'); url.searchParams.set('unlockAll', '0');
    await page.goto(url.href, {waitUntil: 'networkidle', timeout: 120000});
    await wait(() => window.__sporelightState?.snapshot && typeof window.__sporelightRequest === 'function', undefined, 120000);
    result = {name, passed: true, details: await body(tools)};
    assert.equal(errors.length, errorStart, 'This feature flow produced no JavaScript, Godot or HTTP errors');
  } catch (error) {
    result = {name, passed: false, error: String(error), label};
    await writeFile(resolve(folder, 'failure-state.json'), JSON.stringify({label, expectedSnapshot, actual: await state().catch(() => null)}, null, 2));
    await page.screenshot({path: resolve(folder, 'failure.png')}).catch(() => {});
  } finally {
    await writeFile(resolve(folder, 'events.json'), JSON.stringify(await page.evaluate(() => window.__featureFlowEvents ?? []).catch(() => []), null, 2));
    await writeFile(resolve(folder, 'evidence.json'), JSON.stringify(evidence, null, 2));
    await context.close();
  }
  result.elapsedMs = Date.now() - started; results.push(result);
  await writeFile(resolve(folder, 'checks.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}

try {
  build = await fetch(new URL('/__build.json', base)).then(response => {assert.ok(response.ok); return response.json();});
  browser = await chromium.launch({channel: 'chrome', headless: true});
  if (phase === 'all' || phase === 'levels') for (const entry of authored.filter(entry => !selectedLevels.length || selectedLevels.includes(entry.levelId))) {
    await withPage('level-' + entry.levelId, async t => {
      // Only the initial state is arranged. No mid-solution requests or direct
      // action replay can paper over a missing button or a broken rule flow.
      await t.page.evaluate(snapshot => window.__sporelightRequest(JSON.stringify({type: 'snapshot', snapshot, time: 1200})), entry.initial.snapshot);
      await t.page.evaluate(() => window.__sporelightRequest(JSON.stringify({type: 'action', command: 'resume'})));
      await t.expectSnapshot(entry.initial.snapshot, 'initial legal fixture');
      assert.equal((await t.state()).revision, 0);
      await t.solve(entry);
      const index = authored.indexOf(entry), complete = entry.steps.at(-1).snapshot;
      let ending;
      if (index === authored.length - 1 || index % 3 === 2) {
        const caption = index === authored.length - 1 ? '看看一路的纪事 ↗' : '去下一片微光 ↗';
        const nextControl = await t.findControl(c => c.class === 'Button' && c.action === 'next');
        assert.equal(nextControl.control.text, caption, 'The ending control describes the destination it actually opens');
        const button = await t.click({action: 'next'});
        if (index === authored.length - 1) {
          await t.wait(() => {
            const s = window.__sporelightState;
            return s?.paused && s.hudRegions?.some(r => r.name === 'ModalOverlay') && (s.ui?.controls ?? []).some(c => c.class === 'Label' && c.text === '花园纪事');
          });
          assert.ok(equivalent((await t.state()).snapshot, complete), 'Final-garden next opens the journal without inventing a thirteenth garden');
          await t.close(); await t.modeProof(); await t.disabledUndoProof(); ending = 'last-next-journal-return-interactive';
        } else {
          const next = authored[index + 1];
          await t.expectSnapshot(next.initial.snapshot, 'next garden through the actual ending control'); await t.assertNoModal(button);
          ending = 'next-initial-snapshot';
        }
      } else {
        const choice = index % 3 === 0 ? '留下看看' : '返回地图';
        const button = await t.click(choice);
        if (choice === '返回地图') {await t.wait(() => window.__sporelightState?.paused === true); await t.close();}
        else await t.assertNoModal(button);
        await t.expectSnapshot(complete, 'ending return preserves the completed garden');
        assert.equal((await t.state()).strolling, true, 'Returning to a completed garden enters an interactive stroll');
        await t.modeProof();
        await t.disabledUndoProof();
        const revisionBeforeKeyUndo = (await t.state()).revision;
        await t.page.keyboard.press('z'); await t.fresh();
        await t.expectSnapshot(complete, 'completed stroll keeps repair and rejects undo');
        assert.equal((await t.state()).revision, revisionBeforeKeyUndo, 'The original real Z shortcut cannot create completed-garden history');
        if (choice === '留下看看') {await t.openMap(); await t.close(); await t.modeProof();}
        ending = choice === '留下看看' ? 'stay-map-return-interactive' : 'map-return-interactive';
      }
      assert.ok(equivalent((await t.state()).progress.memories[entry.levelId], complete), 'Ending navigation does not overwrite the completion memory');
      return {level: entry.levelId, commands: entry.steps.length, interactionCommandsViaActualButtons: entry.steps.filter(s => s.command.kind === 'act').length, ending};
    });
  }
  if (phase === 'all' || phase === 'progression') await withPage('normal-progression-gates', async t => {
    const first = authored[0];
    await t.expectSnapshot(first.initial.snapshot, 'fresh storage enters the first garden without fixture setup');
    assert.equal((await t.state()).revision, 0);
    await t.openMap();
    const menuEntries = s => controls(s).filter(c => c.class === 'Button' && /^\d-\d  /.test(c.text));
    let buttons = menuEntries(await t.fresh());
    assert.equal(buttons.length, 12, 'Normal progression exposes twelve actual garden choices');
    for (const button of buttons) assert.equal(button.disabled, !button.text.startsWith('1-1  '), 'Fresh storage enables only the first garden: ' + button.text);
    const snapshot = (await t.state()).snapshot;
    await t.click({includes: '1-2  '}, {allowDisabled: true});
    await t.wait(() => window.__sporelightState?.paused && window.__sporelightState.hudRegions?.some(r => r.name === 'ModalOverlay'));
    assert.ok(equivalent((await t.state()).snapshot, snapshot), 'A trusted click on a locked map choice cannot enter it');
    const chosen = await t.click({includes: '1-1  '}); await t.assertNoModal(chosen);
    await t.expectSnapshot(first.initial.snapshot, 'normal unlocked selection enters the first garden');
    await t.solve(first);
    await t.click('返回地图'); await t.wait(() => window.__sporelightState?.paused === true);
    buttons = menuEntries(await t.fresh()); assert.equal(buttons.length, 12);
    for (const button of buttons) assert.equal(button.disabled, !['1-1', '1-2'].includes(button.text.slice(0, 3)), 'Completing first garden unlocks exactly the next ordinary choice: ' + button.text);
    const memory = (await t.state()).progress.memories['1-1'];
    const next = await t.click({includes: '1-2  '}); await t.assertNoModal(next);
    await t.expectSnapshot(authored[1].initial.snapshot, 'normal progress unlock leads to the second garden');
    assert.ok(equivalent((await t.state()).progress.memories['1-1'], memory), 'Unlocking the next garden preserves the first completion memory');
    return {qaUsedOnlyForObservation: true, query: 'qa=1&unlockAll=0', fixtureOrActionRequests: 0, lockedChoicesInitially: 11, lockedChoicesAfterFirstRepair: 10, completedCommands: first.steps.length};
  });
  if (phase === 'all' || phase === 'settings') await withPage('settings-persist-and-first-map-entry', async t => {
    const initial = (await t.state()).snapshot;
    await t.click('Ⅱ'); await t.wait(() => window.__sporelightState?.paused === true);
    const before = await t.state(), particles = before.settings.particles;
    await t.click('环境粒子'); await t.wait(value => window.__sporelightState?.settings?.particles === !value, particles);
    const slider = await t.findControl(c => c.class === 'HSlider' && c.setting_id === 'bgm');
    await t.tap(await t.coordinate(slider.control, slider.state));
    await t.page.keyboard.press('Home'); await t.page.keyboard.press('ArrowRight'); await t.page.keyboard.press('ArrowRight');
    await t.wait(() => Math.abs((window.__sporelightState?.settings?.bgm ?? -1) - 0.1) < 0.000001);
    assert.ok(controls(await t.fresh()).some(c => c.setting_id === 'bgm' && Math.abs(c.value - 0.1) < 0.000001), 'The visible native slider and runtime setting agree');
    await t.close(); await t.modeProof(); await t.expectSnapshot(initial, 'settings and resumed mode input do not change rules');
    // Allow the existing asynchronous Web filesystem flush before testing a
    // real navigation reload. No storage API or diagnostic write is injected.
    await t.page.waitForTimeout(800);
    await t.page.reload({waitUntil: 'networkidle', timeout: 120000});
    await t.wait(() => window.__sporelightState?.snapshot, undefined, 120000);
    await t.expectSnapshot(initial, 'reload restores the active garden');
    assert.equal((await t.state()).settings.particles, !particles);
    assert.ok(Math.abs((await t.state()).settings.bgm - 0.1) < 0.000001, 'The actual Web reload restores the selected audio setting');
    await t.openMap(); await t.click('设置');
    const toggle = await t.findControl(c => c.setting_id === 'particles');
    assert.equal(toggle.control.pressed, !particles, 'The first settings entry through the map reflects persisted toggle data');
    const reloadedSlider = await t.findControl(c => c.setting_id === 'bgm');
    assert.ok(Math.abs(reloadedSlider.control.value - 0.1) < 0.000001, 'The first map settings entry displays the persisted slider value');
    await t.close(); await t.modeProof();
    return {fixtureOrActionRequests: 0, particlesBefore: particles, particlesAfter: !particles, bgmAfter: 0.1, reload: true, actualPostReturnInput: 'mode toggled in both directions'};
  });
} catch (error) {fatal = String(error);}
finally {
  if (browser) await browser.close();
  const passed = !fatal && errors.length === 0 && results.length > 0 && results.every(result => result.passed);
  const report = {date: new Date().toISOString(), passed, phase, base, build, viewport, input, hasTouch: input === 'touch', results, errors, fatal,
    summary: {executed: results.length, passed: results.filter(r => r.passed).length, failed: results.filter(r => !r.passed).length, authoredCommands: results.filter(r => r.passed).reduce((total, result) => total + (result.details?.commands ?? 0), 0)},
    scope: 'The level phase runs every selected frozen authored solution from one initial legal fixture. Moves use actual directional keys and interactions use actual command_id/switch buttons, with complete rule snapshot and exact revision checks after every step. Progression uses fresh storage and the normal gates (qa=1&unlockAll=0) without fixture/action requests. Settings uses actual controls and a same-context Web reload.',
    limitations: ['Diagnostic QA is a debug-only observation facility, so this is not release-build instrumentation or a native Windows file-dialog test.',
      'The authored solutions cover their actual successful parameter sequence; rejection branches and alternate puzzle solutions remain in the independent rule and button suites.',
      'Touch button mode uses real native touchscreen taps; long-panel scrolling uses real mouse-wheel events, not finger swipe or inertia.',
      'Per-step published snapshots prove rule/controller outcomes, not exact painted-frame latency, visual comfort or performance.',
      'The normal progression check requires the explicit debug-only unlockAll=0 observation option; it must fail if the running build still forces all QA map choices open.']};
  await writeFile(resolve(output, 'checks.json'), JSON.stringify(report, null, 2) + '\n');
  if (!passed) process.exitCode = 1;
  console.log(JSON.stringify({passed, ...report.summary, errors: errors.length, fatal, output}));
}

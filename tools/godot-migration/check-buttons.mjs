import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';

// All mutations under test travel through native pointer/text input. QA is used
// only to arrange a valid before-state and read diagnostics, never emit signals.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const option = (name, fallback) => process.argv.find(v => v.startsWith(`--${name}=`))?.slice(name.length + 3) ?? fallback;
const base = option('base', 'http://localhost:4186/');
const output = resolve(option('output', resolve(tmpdir(), 'sporelight-buttons')));
const phase = option('phase', 'all');
assert.ok(['all', 'hud', 'commands', 'overlays', 'lifecycle'].includes(phase), '--phase=hud|commands|overlays|lifecycle|all');
const phases = phase === 'all' ? ['hud', 'commands', 'overlays', 'lifecycle'] : [phase];
const inputs = option('inputs', 'mouse,touch').split(',');
assert.ok(inputs.every(v => ['mouse', 'touch'].includes(v)), '--inputs=mouse,touch');
const sizes = option('sizes', '1280x720,390x844,568x320,594x462').split(',').map(value => {
  const match = /^(\d+)x(\d+)$/.exec(value); assert.ok(match, 'Size must be WIDTHxHEIGHT');
  return {width: Number(match[1]), height: Number(match[2])};
});
const filter = option('cases', '').split(',').filter(Boolean);
const {chromium} = createRequire(import.meta.url)(option('playwright', process.env.PLAYWRIGHT_MODULE ?? 'C:/Users/jeffrey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'));
const fixture = JSON.parse(await readFile(resolve(root, 'godot/tests/fixtures/reference.json'), 'utf8'));
const levels = JSON.parse(await readFile(resolve(root, 'godot/content/levels.json'), 'utf8')).levels;
const initial = id => structuredClone(fixture.cases.find(c => c.name === 'authored/' + id).initial.snapshot);
const normalize = (v, key = '') => key === 'trial' && typeof v === 'string' ? normalize(JSON.parse(v)) : Array.isArray(v) ? v.map(x => normalize(x)) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, normalize(v[k], k)])) : Object.is(v, -0) ? 0 : v;
const equivalent = (a, b) => JSON.stringify(normalize(a)) === JSON.stringify(normalize(b));
const point = (s, target) => {
  const clone = structuredClone(s), actor = clone.active;
  clone.actors[actor] = target;
  if (clone.follow) clone.actors[actor === 'luvie' ? 'buddy' : 'luvie'] = target;
  for (const c of levels.find(l => l.id === clone.levelId).collectibles) if (Object.values(clone.actors).includes(c.tile) && !clone.collected.includes(c.id)) clone.collected.push(c.id);
  return clone;
};
const rootWith = direction => {const s = initial('1-1'); s.growth.root = [`g:root:${direction === 'right' ? '1:0' : '0:1'}`]; return s;};
const rows = [], errors = [];
let browser = null, build = null, fatal = null;
await mkdir(output, {recursive: true});

class NotCovered extends Error {}
const controls = s => s.ui?.controls ?? s.uiControls ?? s.controls ?? [];
const settings = s => s.settings ?? s.ui?.settings ?? null;
const labels = s => controls(s).filter(c => (c.class ?? c.type ?? '').includes('Label')).map(c => String(c.text ?? '')).join('\n');
const pressed = b => b.pressed ?? b.button_pressed ?? b.buttonPressed;
const hasModal = s => s.hudRegions?.some(r => r.name === 'ModalOverlay') || s.ui?.modalOpen === true;

function commandCases() {
  const found = new Map();
  for (const entry of fixture.cases) {
    let previous = entry.initial;
    for (const step of entry.steps ?? []) {
      const {kind, value} = step.command ?? {};
      if (kind === 'act' && step.result?.ok === true) {
        const family = value.startsWith('use:') || value.startsWith('grow:root:') ? value : value.split(':')[0];
        if (!found.has(family)) {
          const before = structuredClone(previous.snapshot), after = structuredClone(step.snapshot);
          // The sole observe fixture is a completed stroll. Arrange its same
          // valid position before completion for the nearby-button test; the
          // real completed/stay flow is tested separately in the overlay phase.
          const arrangement = value.startsWith('observe:') && before.completed ? 'same fixture position with completed=false; ending/stay is a separate real UI case' : 'unmodified frozen fixture before/after';
          if (value.startsWith('observe:')) {before.completed = false; after.completed = false;}
          found.set(family, {family, id: value, level: entry.levelId, before, after, fixture: entry.name, arrangement});
        }
      }
      previous = step;
    }
  }
  return [...found.values()];
}

async function matrixRow(size, input, selectedPhase) {
  const key = `${size.width}x${size.height}-${input}-${selectedPhase}`;
  const folder = resolve(output, key); await mkdir(folder, {recursive: true});
  const context = await browser.newContext({viewport: size, deviceScaleFactor: 1, hasTouch: input === 'touch', acceptDownloads: true});
  await context.route('**/favicon.ico', r => r.fulfill({status: 204, body: ''}));
  await context.addInitScript(() => {
    window.__buttonEvents = [];
    window.__buttonKeys = [];
    for (const type of ['keydown', 'keyup']) window.addEventListener(type, e => {
      const s = window.__sporelightState;
      window.__buttonKeys.push({type, key: e.key, trusted: e.isTrusted, repeat: e.repeat, time: performance.now(),
        paused: s?.paused, revision: s?.revision, moving: s?.moving});
    }, true);
    for (const type of ['pointerdown', 'pointerup', 'touchstart', 'touchend']) window.addEventListener(type, e => {
      const s = window.__sporelightState, point = e.changedTouches?.[0] ?? e, canvas = document.querySelector('#canvas'), rect = canvas?.getBoundingClientRect();
      const x = point.clientX, y = point.clientY;
      const canvasX = rect ? (x - rect.x) * canvas.width / rect.width : null, canvasY = rect ? (y - rect.y) * canvas.height / rect.height : null;
      const hits = (s?.buttons ?? []).filter(b => {
        const r = b.visibleRect ?? b.rect ?? [b.x, b.y, b.width, b.height];
        return r[2] > 0 && r[3] > 0 && canvasX >= r[0] && canvasX < r[0] + r[2] && canvasY >= r[1] && canvasY < r[1] + r[3];
      }).map(b => ({text: b.text, action: b.action, command_id: b.command_id, disabled: b.disabled, path: b.path, instanceId: b.instanceId}));
      window.__buttonEvents.push({type, trusted: e.isTrusted, pointerType: e.pointerType ?? 'touch', time: performance.now(), target: e.target?.id,
        x, y, canvasX, canvasY, hits, moving: s?.moving, revision: s?.revision, qaSequence: s?.qaSequence, pendingButton: s?.pendingButton,
        hintVisible: s?.hintVisible, rolling: s?.rolling,
        motion: {kind: s?.motion?.kind, elapsed: s?.motion?.elapsed, duration: s?.motion?.duration}});
    }, true);
  });
  const page = await context.newPage(), cdp = await context.newCDPSession(page);
  const results = [], inventory = []; let activeCase = 'startup';
  const noteError = (kind, text) => errors.push({row: key, case: activeCase, kind, text});
  page.on('pageerror', e => noteError('javascript', e.message));
  page.on('console', m => {if (m.type() === 'error' || /SCRIPT ERROR:|ERROR:/.test(m.text())) noteError('godot/browser', m.text());});
  page.on('response', r => {if (r.status() >= 400 && !r.url().endsWith('/favicon.ico')) noteError('http', `${r.status()} ${r.url()}`);});
  const state = () => page.evaluate(() => structuredClone(window.__sporelightState));
  const wait = (fn, arg, timeout = 10000) => page.waitForFunction(fn, arg, {timeout, polling: 10});
  const publication = async () => {
    const sequence = (await state())?.qaSequence;
    assert.ok(Number.isFinite(sequence), 'The running build must expose the actual QA publication sequence');
    return sequence;
  };
  const freshQA = async (after = undefined) => {
    const sequence = after ?? await publication();
    await wait(previous => Number.isFinite(window.__sporelightState?.qaSequence) && window.__sporelightState.qaSequence > previous, sequence);
    return state();
  };
  const request = payload => page.evaluate(v => window.__sporelightRequest(JSON.stringify(v)), payload);
  const snapshot = async (expected, label = activeCase) => {
    await wait(expected => {
      const s = window.__sporelightState;
      const norm = (v, k = '') => k === 'trial' && typeof v === 'string' ? norm(JSON.parse(v)) : Array.isArray(v) ? v.map(x => norm(x)) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, norm(v[k], k)])) : Object.is(v, -0) ? 0 : v;
      return s && !s.moving && JSON.stringify(norm(s.snapshot)) === JSON.stringify(norm(expected));
    }, expected);
    assert.ok(equivalent((await state()).snapshot, expected), label + ': full rule snapshot agrees');
  };
  const load = async s => {
    await request({type: 'snapshot', snapshot: structuredClone(s), time: 1200});
    await request({type: 'action', command: 'resume'});
    await snapshot(s, 'legal fixture setup');
    await freshQA();
  };
  const coordinates = async (control, fraction = {x: 0.5, y: 0.5}) => {
    const rect = control.visibleRect ?? control.rect ?? [control.x, control.y, control.width, control.height];
    assert.ok(rect?.length === 4 && rect.every(Number.isFinite) && rect[2] > 0 && rect[3] > 0, 'A real visible hit region exists');
    const canvas = await page.locator('#canvas').boundingBox();
    const backing = await page.locator('#canvas').evaluate(c => ({width: c.width, height: c.height}));
    const value = {x: canvas.x + (rect[0] + rect[2] * fraction.x) * canvas.width / backing.width, y: canvas.y + (rect[1] + rect[3] * fraction.y) * canvas.height / backing.height};
    assert.ok(value.x >= canvas.x && value.y >= canvas.y && value.x < canvas.x + canvas.width && value.y < canvas.y + canvas.height, 'The actual pointer location is inside the displayed canvas');
    return value;
  };
  const rawTap = async coordinate => input === 'touch' ? page.touchscreen.tap(coordinate.x, coordinate.y) : page.mouse.click(coordinate.x, coordinate.y);
  const down = async coordinate => {
    if (input === 'touch') await cdp.send('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{x: coordinate.x, y: coordinate.y, id: 1}]});
    else {await page.mouse.move(coordinate.x, coordinate.y); await page.mouse.down();}
  };
  const up = async () => input === 'touch' ? cdp.send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []}) : page.mouse.up();
  const matches = (b, query) => typeof query === 'string' ? b.text === query : Object.entries(query).every(([k, v]) => k === 'includes' ? String(b.text).includes(v) : b[k] === v);
  const rectOf = control => control?.visibleRect ?? control?.rect ?? [control?.x, control?.y, control?.width, control?.height];
  const intersect = (a, b) => {
    const x = Math.max(a[0], b[0]), y = Math.max(a[1], b[1]);
    return [x, y, Math.max(0, Math.min(a[0] + a[2], b[0] + b[2]) - x), Math.max(0, Math.min(a[1] + a[3], b[1] + b[3]) - y)];
  };
  const wheelInside = async (s, target, fallbackDirection = 1) => {
    const list = controls(s), viewport = [0, 0, ...(s.viewport ?? [size.width, size.height])];
    const scrolls = list.filter(c => String(c.class ?? c.type ?? '') === 'ScrollContainer' && rectOf(c)[2] > 0 && rectOf(c)[3] > 0);
    let owner = target?.path ? scrolls.filter(c => target.path.startsWith(c.path + '/')).sort((a, b) => b.path.length - a.path.length)[0] : null;
    const region = (s.hudRegions ?? []).find(r => r.name === (hasModal(s) ? 'ModalOverlay' : 'NearbyActions'));
    if (!owner && region) {
      const candidates = scrolls.filter(c => {
        const cut = intersect(rectOf(c), region.rect);
        return cut[2] > 0 && cut[3] > 0 && (hasModal(s) ? !String(c.path).includes('/NearbyActions/') && !String(c.path).includes('/Heading/') : String(c.path).includes('/NearbyActions/'));
      });
      owner = candidates.sort((a, b) => rectOf(b)[2] * rectOf(b)[3] - rectOf(a)[2] * rectOf(a)[3])[0];
    }
    let hit = owner ? rectOf(owner) : region?.rect;
    if (!hit) throw new NotCovered('No actual visible scrolling container/region is available for this target');
    hit = intersect(hit, viewport);
    if (region) hit = intersect(hit, region.rect);
    assert.ok(hit[2] > 0 && hit[3] > 0, 'Scrolling uses a real visible panel intersection');
    let direction = fallbackDirection;
    if (target && Number.isFinite(target.y) && Number.isFinite(target.height)) {
      if (target.y + target.height <= hit[1] || target.y < hit[1]) direction = -1;
      else if (target.y >= hit[1] + hit[3] || target.y + target.height > hit[1] + hit[3]) direction = 1;
    }
    const coordinate = await coordinates({visibleRect: hit});
    inventory.push({case: activeCase, kind: 'scroll', input: 'real-mouse-wheel', ownerPath: owner?.path ?? null,
      targetPath: target?.path ?? null, visibleRect: hit, canvasCssPoint: coordinate, direction});
    await page.mouse.move(coordinate.x, coordinate.y);
    await page.mouse.wheel(0, direction * 240);
    await page.waitForTimeout(70);
  };
  const find = async (query, {allowDisabled = false, scroll = true} = {}) => {
    let disabledPublications = 0, disabledIdentity = null;
    for (let attempt = 0; attempt < (scroll ? 20 : 4); attempt++) {
      const s = await freshQA(), candidates = (s.buttons ?? []).filter(b => matches(b, query));
      const button = candidates.at(-1);
      if (button && (allowDisabled || !button.disabled)) return button;
      if (button?.disabled) {
        const identity = button.instanceId ?? button.path ?? button.text;
        disabledPublications = identity === disabledIdentity ? disabledPublications + 1 : 1;
        disabledIdentity = identity;
        if (disabledPublications >= 3) throw new Error(`Button disabled across three fresh QA publications: ${JSON.stringify(query)}; ${button.tooltip ?? 'no reason exposed'}`);
        continue;
      }
      disabledPublications = 0; disabledIdentity = null;
      const target = controls(s).filter(c => matches(c, query)).at(-1);
      // An overlay may be queued for the next frame. First wait for its actual
      // controls; scrolling the previous panel cannot make it appear sooner.
      if (!scroll || (!target && attempt < 3)) continue;
      await wheelInside(s, target, attempt < 12 ? 1 : -1);
    }
    throw new NotCovered(`No visible matching button after actual scroll: ${JSON.stringify(query)}`);
  };
  const click = async query => {
    const b = await find(query); inventory.push({case: activeCase, input, button: b});
    const coordinate = await coordinates(b), before = await publication();
    await rawTap(coordinate); await freshQA(before); return b;
  };
  const closed = async button => {
    assert.ok(Number.isFinite(button.instanceId), 'Closing is checked against an actual native widget identity');
    await wait(identity => {
      const s = window.__sporelightState;
      const list = s?.ui?.controls ?? s?.uiControls ?? s?.controls ?? [];
      return s && !s.paused && !s.hudRegions?.some(r => r.name === 'ModalOverlay') && s.ui?.modalOpen !== true
        && !(s.buttons ?? []).some(b => b.instanceId === identity)
        && !list.some(c => c.instanceId === identity);
    }, button.instanceId);
    const after = await freshQA();
    assert.equal(hasModal(after), false, 'Returning removes the actual modal, not only its paused flag');
    assert.equal(after.paused, false, 'Returning resumes the application');
    inventory.push({case: activeCase, kind: 'closed-overlay', removedInstanceId: button.instanceId,
      paused: after.paused, modal: hasModal(after), revision: after.revision});
    return after;
  };
  const close = async ({fraction = {x: 0.5, y: 0.5}, button = null} = {}) => {
    const target = button ?? await find('继续当前关卡');
    inventory.push({case: activeCase, input, kind: 'return-to-garden', button: target, fraction});
    const eventStart = await page.evaluate(() => window.__buttonEvents.length);
    await rawTap(await coordinates(target, fraction));
    const presses = await page.evaluate(start => window.__buttonEvents.slice(start).filter(e => e.type === 'pointerdown'), eventStart);
    assert.equal(presses.length, 1, 'One actual pointer press attempts to return to the garden');
    assert.ok(presses[0].trusted && presses[0].target === 'canvas' && presses[0].pointerType === input
      && presses[0].hits.some(b => b.instanceId === target.instanceId && b.text === '继续当前关卡' && !b.disabled),
    'The trusted return press hits the actual visible enabled return button');
    return closed(target);
  };
  const run = async (name, body) => {
    if (filter.length && !filter.some(f => name.includes(f))) return;
    activeCase = name; const start = Date.now();
    const eventStart = await page.evaluate(() => window.__buttonEvents.length);
    const keyStart = await page.evaluate(() => window.__buttonKeys.length);
    const row = {name, status: 'passed', details: null};
    try {row.details = await body();}
    catch (e) {
      row.status = e instanceof NotCovered ? 'uncovered' : 'failed'; row.reason = String(e);
      row.observed = await state().catch(() => null);
      await page.screenshot({path: resolve(folder, name.replace(/[^a-z0-9_-]/gi, '_') + '.png')}).catch(() => {});
    } finally {
      await up().catch(() => {});
      row.pointerEvents = await page.evaluate(start => window.__buttonEvents.slice(start), eventStart).catch(() => []);
      row.keyEvents = await page.evaluate(start => window.__buttonKeys.slice(start), keyStart).catch(() => []);
    }
    row.elapsedMs = Date.now() - start; results.push(row);
    await writeFile(resolve(folder, 'checks.json'), JSON.stringify({row: key, results, inventory}, null, 2) + '\n');
    console.log(JSON.stringify({row: key, case: name, status: row.status, reason: row.reason}));
  };
  const waitMoving = revision => wait(r => window.__sporelightState?.moving || window.__sporelightState?.revision > r, revision);
  const actualCommand = async test => {
    await load(test.before);
    if (test.id === 'switch') await click({action: 'switch'});
    else if (test.id === 'follow') {
      const s = await state();
      const header = s.buttons.find(b => b.path?.includes('/NearbyActions/') && ['同行', '等候'].includes(b.text) && !b.command_id);
      if (header) {
        inventory.push({case: activeCase, input, button: header, equivalentControl: 'Actual visible follow header executes the same follow command; no claim that a hidden local command was clicked'});
        await rawTap(await coordinates(header));
      } else await click({command_id: test.id});
    } else await click({command_id: test.id});
    await snapshot(test.after);
    return {command: test.id, family: test.family, fixture: test.fixture, arrangement: test.arrangement, before: test.before, after: test.after};
  };
  const openMap = async () => {await click('地图'); await wait(() => window.__sporelightState?.paused === true);};
  const exportSave = async name => {
    const downloaded = page.waitForEvent('download', {timeout: 15000});
    await click('导出当前旅程');
    const item = await downloaded; const file = resolve(folder, name + '.json');
    await item.saveAs(file);
    return JSON.parse(await readFile(file, 'utf8'));
  };
  const findControl = async predicate => {
    for (let attempt = 0; attempt < 20; attempt++) {
      const current = await freshQA(), value = controls(current).find(predicate);
      if (!value) {
        if (attempt < 3) continue;
        throw new NotCovered('Required read-only QA native-control metadata is absent across fresh publications');
      }
      const rect = value.visibleRect ?? value.rect ?? [];
      if (rect[2] > 0 && rect[3] > 0) return value;
      await wheelInside(current, value);
    }
    throw new NotCovered('Native control remains outside the visible panel after real scrolling');
  };
  const enterText = async text => {
    const control = await findControl(c => String(c.class ?? c.type ?? '').includes('TextEdit')); await rawTap(await coordinates(control));
    await page.keyboard.press('ControlOrMeta+a'); await page.keyboard.type(text);
    await wait(expected => (window.__sporelightState?.ui?.controls ?? window.__sporelightState?.uiControls ?? window.__sporelightState?.controls ?? [])
      .some(c => String(c.class ?? c.type ?? '').includes('TextEdit') && c.text === expected), text);
    const actual = controls(await freshQA()).find(c => String(c.class ?? c.type ?? '').includes('TextEdit'));
    assert.equal(actual?.text, text, 'The real native text input contains the complete requested text before preview');
    return text;
  };
  const enterJson = async candidate => {
    // Native keyboard.type drops non-ASCII characters in this Godot Web path.
    // JSON Unicode escapes preserve the actual imported content using real
    // ASCII key events; this does not validate direct Chinese/IME text input.
    const text = JSON.stringify(candidate).replace(/[^\x00-\x7f]/g, character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));
    await enterText(text);
    const actual = controls(await state()).find(c => String(c.class ?? c.type ?? '').includes('TextEdit'));
    assert.ok(equivalent(JSON.parse(actual.text), candidate), 'The actual typed JSON decodes to the complete intended candidate');
    inventory.push({case: activeCase, kind: 'json-input', input: 'real-keyboard-ascii-with-json-unicode-escapes', decodedCandidateVerified: true});
    return text;
  };
  const previewImport = async (text, status, disabled) => {
    await click('检查粘贴的旅程');
    await wait(({text, status, disabled}) => {
      const s = window.__sporelightState, list = s?.ui?.controls ?? s?.uiControls ?? s?.controls ?? [];
      return list.some(c => String(c.class ?? c.type ?? '').includes('TextEdit') && c.text === text)
        && list.some(c => String(c.class ?? c.type ?? '').includes('Label') && String(c.text ?? '').includes(status))
        && list.some(c => c.class === 'Button' && Number.isFinite(c.instanceId)
          && c.text === '确认导入' && c.disabled === disabled);
    }, {text, status, disabled});
    const confirm = await find('确认导入', {allowDisabled: true});
    assert.equal(confirm.disabled, disabled, 'The matching preview status and actual confirm state agree');
    return confirm;
  };
  const first = fixture.cases.find(c => c.name === 'authored/1-1');
  const repair = first.steps.at(-1), beforeRepair = first.steps.at(-2).snapshot;
  const finish = async () => {
    await load(beforeRepair); await click({command_id: 'repair'}); await snapshot(repair.snapshot);
    await wait(() => window.__sporelightState?.paused === true
      && window.__sporelightState.buttons.some(b => b.text === '留下看看' && !b.disabled));
  };
  const knownFirstTiles = new Map();
  for (const entry of fixture.cases.filter(c => c.levelId === '1-1')) for (const observation of [entry.initial, ...entry.steps]) {
    for (const tile of observation.tiles ?? []) knownFirstTiles.set(tile.id, tile);
  }
  const arrowFor = (from, to) => to.x > from.x ? '→' : to.x < from.x ? '←' : to.z > from.z ? '↓' : '↑';
  const keyFor = {'←': 'ArrowLeft', '→': 'ArrowRight', '↑': 'ArrowUp', '↓': 'ArrowDown'};
  const assertInteractive = async label => {
    const before = await freshQA();
    assert.equal(before.paused, false, label + ': no application pause remains');
    assert.equal(hasModal(before), false, label + ': no modal remains');
    assert.equal(before.moving, false, label + ': starts from an actual settled state');
    assert.equal(before.snapshot.levelId, '1-1', 'Lifecycle movement uses only the independently known first-garden grid');
    assert.equal(typeof before.rolling, 'boolean', 'The actual movement mode is observable');
    await click({action: 'mode'});
    await wait(value => window.__sporelightState?.rolling === !value, before.rolling);
    let current = await freshQA();
    assert.ok(equivalent(current.snapshot, before.snapshot), label + ': a real mode click after return preserves the complete puzzle snapshot');
    assert.equal(current.revision, before.revision, label + ': mode does not manufacture a rule commit');
    await click({action: 'mode'});
    await wait(value => window.__sporelightState?.rolling === value, before.rolling);
    current = await freshQA();
    const source = knownFirstTiles.get(current.snapshot.actors[current.snapshot.active]);
    assert.ok(source, label + ': the actual actor has a frozen first-garden coordinate');
    const neighbors = (current.targets ?? []).map(t => knownFirstTiles.get(t.id)).filter(t => t && t.id !== source.id && !t.solid
      && Math.abs(t.x - source.x) + Math.abs(t.z - source.z) === 1 && Math.abs(t.h - source.h) <= 1)
      .sort((a, b) => Math.abs(a.h - source.h) - Math.abs(b.h - source.h) || a.x - b.x || a.z - b.z);
    assert.ok(neighbors.length > 0, label + ': a real available cardinal neighbor exists');
    const target = neighbors[0], expected = point(current.snapshot, target.id), revision = current.revision;
    await click(arrowFor(source, target));
    await snapshot(expected, label + ': actual direction button after return');
    const moved = await freshQA();
    assert.equal(moved.revision, revision + 1, label + ': one real direction click commits one legal step');
    assert.equal(moved.paused, false, label + ': stepping does not reopen a modal');
    assert.equal(hasModal(moved), false, label + ': no modal intercepts the step');
    // No QA reset occurs between return, the pointer movement and this key.
    // This additionally catches focus left behind by the import TextEdit.
    const back = point(moved.snapshot, source.id);
    await page.keyboard.press(keyFor[arrowFor(target, source)]);
    await snapshot(back, label + ': actual keyboard movement after return');
    const restored = await freshQA();
    assert.equal(restored.revision, revision + 2, label + ': the real return key commits once');
    assert.equal(restored.pendingButton, '', label + ': no old button is queued after return');
    assert.deepEqual(restored.input.held, [], label + ': no held key survives the real key release');
    inventory.push({case: activeCase, kind: 'interactive-after-return', label, source: source.id, target: target.id,
      before: before.snapshot, moved: moved.snapshot, after: restored.snapshot, revisions: [revision, moved.revision, restored.revision],
      pointerAndKeyboard: true, noQaResetBetweenReturnAndActions: true});
    return restored;
  };
  const resize = async extent => {
    await page.setViewportSize(extent);
    await wait(({width, height}) => {
      const s = window.__sporelightState, c = document.querySelector('#canvas');
      return s?.viewport?.[0] === width && s.viewport[1] === height && c?.width === width && c.height === height;
    }, extent);
    await freshQA();
  };
  const assertModalViewport = async label => {
    const current = await freshQA(), target = controls(current).find(c => c.text === '继续当前关卡');
    assert.ok(current.paused && hasModal(current) && target, label + ': the actual modal is still open');
    const owner = controls(current).filter(c => c.class === 'ScrollContainer' && target.path.startsWith(c.path + '/'))
      .sort((a, b) => b.path.length - a.path.length)[0];
    assert.ok(owner, label + ': the return button has its actual scroll owner');
    const [width, height] = current.viewport;
    assert.ok(owner.x >= -1 && owner.y >= -1 && owner.x + owner.width <= width + 1 && owner.y + owner.height <= height + 1,
      label + ': the complete modal scroll viewport fits the resized game viewport');
    inventory.push({case: activeCase, kind: 'modal-resize-bounds', label, viewport: current.viewport, scroll: owner});
  };
  const rawDrag = async (start, end) => {
    await down(start);
    try {
      for (let step = 1; step <= 5; step++) {
        const at = {x: start.x + (end.x - start.x) * step / 5, y: start.y + (end.y - start.y) * step / 5};
        if (input === 'touch') await cdp.send('Input.dispatchTouchEvent', {type: 'touchMove', touchPoints: [{...at, id: 1}]});
        else await page.mouse.move(at.x, at.y);
      }
    } finally {await up();}
  };
  try {
    const url = new URL(base); url.searchParams.set('qa', '1');
    await page.goto(url.href, {waitUntil: 'networkidle', timeout: 120000});
    await wait(() => typeof window.__sporelightRequest === 'function' && window.__sporelightState?.snapshot, undefined, 120000);

    if (selectedPhase === 'hud') {
      for (const [name, direction, before, target] of [
        ['left', '←', initial('1-1'), 'f:-1:0'], ['up', '↑', initial('1-1'), 'f:0:-1'],
        ['right', '→', rootWith('right'), 'g:root:1:0'], ['down', '↓', rootWith('down'), 'g:root:0:1'],
      ]) await run('direction-' + name, async () => {await load(before); await click(direction); await snapshot(point(before, target)); return {target};});
      await run('primary-seed-road', async () => {const s = initial('1-1'); await load(s); await click({action: 'primary'}); await snapshot(rootWith('right')); return {result: 'right root grows exactly once'};});
      await run('early-direction-click-survives-long-growth', async () => {
        const before = initial('1-1'); await load(before);
        const primary = await find({action: 'primary'}), left = await find('←');
        const primaryPoint = await coordinates(primary), leftPoint = await coordinates(left);
        const eventStart = await page.evaluate(() => window.__buttonEvents.length);
        let retained = null;
        try {
          assert.equal((await state()).revision, 0, 'A fresh real interaction starts before any commit');
          inventory.push({case: activeCase, kind: 'timed-button-targets', input, buttons: [primary, left], coordinates: [primaryPoint, leftPoint]});
          await rawTap(primaryPoint);
          await wait(() => {
            const s = window.__sporelightState;
            return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.motion.duration === 0.78 && s.motion.elapsed < 0.2;
          }, undefined, 3000);
          await rawTap(leftPoint);
          const downs = await page.evaluate(start => window.__buttonEvents.slice(start).filter(e => e.type === 'pointerdown'), eventStart);
          inventory.push({case: activeCase, kind: 'early-direction-pointerdowns', events: downs});
          assert.equal(downs.length, 2, 'Two actual pointer presses start growth and choose its pending direction');
          assert.ok(downs.every(e => e.trusted && e.pointerType === input && e.target === 'canvas'), 'Growth and direction use trusted native canvas input');
          assert.ok(!downs[0].moving && downs[0].revision === 0 && downs[0].hits.some(b => b.action === 'primary' && !b.disabled), 'The original real primary press starts from the advertised idle control');
          const direction = downs[1];
          assert.ok(direction.moving && direction.revision === 0 && direction.motion.kind === 'grow:root:right' && direction.motion.duration === 0.78 && direction.motion.elapsed < 0.25,
            'The real Left press must arrive early in the original uncommitted growth; late signal scheduling fails this case');
          assert.ok(direction.hits.some(b => b.text === '←' && !b.disabled), 'The precomputed direction coordinate still hits the actual enabled control during growth');
          const handle = await wait(({time, elapsed, sequence}) => {
            const s = window.__sporelightState, now = performance.now();
            if (!s || now - time <= 220 || s.qaSequence <= sequence) return false;
            if (!s.moving || s.revision !== 0 || s.motion?.kind !== 'grow:root:right') return {observedAt: now, state: structuredClone(s), escapedGrowthWindow: true};
            if (s.motion.elapsed - elapsed <= 0.2) return false;
            return {observedAt: now, state: structuredClone(s), escapedGrowthWindow: false};
          }, {time: direction.time, elapsed: direction.motion.elapsed, sequence: direction.qaSequence}, 3000);
          retained = await handle.jsonValue(); await handle.dispose();
          inventory.push({case: activeCase, kind: 'pending-direction-after-old-expiry', evidence: retained});
          assert.equal(retained.escapedGrowthWindow, false, 'The >200ms observation must still belong to the same original growth action');
          assert.equal(retained.state.pendingButton, 'dir:left', 'An explicit direction remains pending beyond the old 160ms keyboard lifetime');
          assert.ok(retained.observedAt - direction.time > 220 && retained.state.motion.elapsed - direction.motion.elapsed > 0.2, 'Both real browser time and actual growth time advance beyond 200ms after the click');
          assert.ok(equivalent(retained.state.snapshot, before), 'Waiting for the pending button cannot prematurely mutate the puzzle');
          const expected = point(rootWith('right'), 'f:-1:0');
          await snapshot(expected); const final = await freshQA();
          assert.equal(final.revision, 2, 'Only the real growth and one pending left move commit');
          assert.equal(final.pendingButton, '', 'The consumed button does not remain queued');
          assert.ok(!final.moving && equivalent(final.snapshot, expected), 'The complete final rule snapshot includes the seed, both travellers and the collected spore');
          return {result: 'early real direction survives the full interaction instead of expiring after 160ms', retained, final};
        } finally {
          inventory.push({case: activeCase, kind: 'trusted-pointer-events', events: await page.evaluate(start => window.__buttonEvents.slice(start), eventStart)});
        }
      });
      await run('repeat-primary-hint-mode-during-growth', async () => {
        const before = initial('1-1'); await load(before);
        const primary = await find({action: 'primary'}), hint = await find({action: 'hint'}), mode = await find({action: 'mode'});
        const primaryPoint = await coordinates(primary), hintPoint = await coordinates(hint), modePoint = await coordinates(mode);
        const baseline = await state(), eventStart = await page.evaluate(() => window.__buttonEvents.length);
        try {
          assert.equal(baseline.revision, 0); assert.equal(baseline.hintVisible, false, 'This case starts before a hint has been displayed');
          assert.equal(baseline.rolling, false, 'This case starts in walking mode');
          inventory.push({case: activeCase, kind: 'timed-button-targets', input, buttons: [primary, hint, mode], coordinates: [primaryPoint, hintPoint, modePoint]});
          await rawTap(primaryPoint);
          await wait(() => {const s = window.__sporelightState; return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.motion.duration === 0.78 && s.motion.elapsed < 0.2;}, undefined, 3000);
          await rawTap(primaryPoint);
          await wait(() => {const s = window.__sporelightState; return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.message?.includes('正在完成这次动作');}, undefined, 3000);
          const repeated = await state();
          assert.equal(repeated.pendingButton, '', 'Repeating the current primary action does not queue a future retract or second growth');
          assert.ok(equivalent(repeated.snapshot, before) && equivalent(repeated.motion.after, rootWith('right')), 'The repeated press leaves the same detached growth preview and uncommitted puzzle');
          await rawTap(hintPoint);
          await wait(() => {const s = window.__sporelightState; return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.hintVisible === true && s.message?.includes('向右引一节芽');}, undefined, 3000);
          const hinted = await state();
          await rawTap(modePoint);
          await wait(() => {const s = window.__sporelightState; return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.rolling === true && s.buttons?.some(b => b.action === 'mode' && b.text === '滚动中');}, undefined, 3000);
          const toggled = await state(), downs = await page.evaluate(start => window.__buttonEvents.slice(start).filter(e => e.type === 'pointerdown'), eventStart);
          inventory.push({case: activeCase, kind: 'growth-controls-immediate-response', repeated, hinted, toggled, events: downs});
          assert.equal(downs.length, 4, 'Growth, repeated primary, hint and mode each receive a real pointer press');
          assert.ok(downs.every(e => e.trusted && e.pointerType === input && e.target === 'canvas'), 'All four actions use trusted native canvas input');
          assert.ok(!downs[0].moving && downs[0].revision === 0 && downs[0].hits.some(b => b.action === 'primary' && !b.disabled), 'The first real primary starts from idle');
          for (const [index, action] of [[1, 'primary'], [2, 'hint'], [3, 'mode']]) {
            const event = downs[index];
            assert.ok(event.moving && event.revision === 0 && event.motion.kind === 'grow:root:right' && event.motion.elapsed < event.motion.duration,
              action + ' must actually arrive before the original growth commits; a late click cannot count as an immediate response');
            assert.ok(event.hits.some(b => b.action === action && !b.disabled), action + ' precomputed coordinate still hits the actual enabled control');
          }
          assert.ok(hinted.moving && hinted.hintVisible && hinted.revision === 0 && toggled.moving && toggled.rolling && toggled.revision === 0, 'Hint and mode actually apply while the same growth remains uncommitted');
          assert.equal(toggled.pendingButton, '', 'Immediate view controls do not queue another puzzle action');
          await snapshot(rootWith('right'));
          // A short idle observation catches a queued repeat starting on the
          // next legal frame; it is never used to schedule the busy clicks.
          await page.waitForTimeout(250); const final = await freshQA();
          assert.ok(!final.moving && equivalent(final.snapshot, rootWith('right')), 'The only completed puzzle action is the original right-root growth');
          assert.equal(final.revision, 1); assert.equal(final.pendingButton, '');
          assert.equal(final.rolling, true); assert.equal(final.hintVisible, true);
          await click({action: 'mode'}); await wait(() => window.__sporelightState?.rolling === false);
          return {result: 'repeated primary is filtered while hint and mode respond inside real growth', repeated, hinted, toggled, final, restoredWalkingMode: true};
        } finally {
          inventory.push({case: activeCase, kind: 'trusted-pointer-events', events: await page.evaluate(start => window.__buttonEvents.slice(start), eventStart)});
        }
      });
      await run('undo-after-real-button-action', async () => {await load(initial('1-1')); await click({action: 'primary'}); await snapshot(rootWith('right')); await click({action: 'undo'}); await snapshot(initial('1-1'));});
      await run('undo-no-history-disabled', async () => {await load(initial('1-1')); const b = await find({action: 'undo'}, {allowDisabled: true}); assert.equal(b.disabled, true); return {status: 'verified-disabled', reason: 'No undo history in a freshly loaded rule state'};});
      await run('restart', async () => {await load(rootWith('down')); await click({action: 'restart'}); await snapshot(initial('1-1'));});
      await run('hint', async () => {await load(initial('1-1')); await click({action: 'hint'}); await wait(() => window.__sporelightState?.message?.includes('向右引一节芽')); assert.ok(equivalent((await state()).snapshot, initial('1-1')));});
      await run('mode-toggle', async () => {await load(initial('1-1')); await click({action: 'mode'}); await wait(() => window.__sporelightState?.buttons?.some(b => b.action === 'mode' && b.text === '滚动中')); await click({action: 'mode'}); await wait(() => window.__sporelightState?.buttons?.some(b => b.action === 'mode' && b.text === '行走')); await snapshot(initial('1-1'));});
      await run('overview-toggle', async () => {
        await load(initial('1-1'));
        const before = await state(), overview = await find('全景', {allowDisabled: true});
        if (size.width >= 650 || before.safeCamera) {
          assert.equal(overview.disabled, true, 'An already complete wide/safe view offers no false overview toggle');
          assert.equal(overview.tooltip, '当前已展示整片花园；全景切换适用于小屏跟随镜头。', 'The disabled overview explains its actual camera applicability');
          await rawTap(await coordinates(overview));
          await snapshot(initial('1-1'));
          assert.equal((await state()).overview, before.overview, 'Clicking the inapplicable overview cannot change camera mode');
          return {status: 'verified-disabled', reason: overview.tooltip};
        }
        assert.equal(overview.disabled, false, 'Small-screen following view exposes an actual overview control');
        await click('全景'); await wait(() => window.__sporelightState?.overview === true); await find('跟随');
        const wide = await state();
        assert.ok(!equivalent({scale: before.scale, origin: before.origin}, {scale: wide.scale, origin: wide.origin}), 'Small-screen overview actually changes camera framing');
        await click('跟随'); await wait(() => window.__sporelightState?.overview === false); await find('全景');
        await snapshot(initial('1-1')); return {result: 'real pointer toggles actual small-screen camera framing in both directions'};
      });
      await run('jump-real-motion', async () => {
        const before = initial('1-1'); await load(before);
        const revision = (await state()).revision;
        // Fixture loading preserves the controller's last facing. Establish a
        // real blocked right-facing choice before testing an in-place jump.
        await click('→'); await snapshot(before);
        const blocked = await freshQA();
        assert.ok(!blocked.moving && blocked.revision === revision && equivalent(blocked.snapshot, before), 'The real right-direction attempt is blocked without changing the complete puzzle');
        if ('lastDirection' in blocked) assert.equal(blocked.lastDirection, 'right');
        await click({action: 'jump'});
        const startedHandle = await wait(expectedRevision => {
          const s = window.__sporelightState;
          return s?.moving && s.revision === expectedRevision && s.motion?.kind === 'jump'
            ? {moving: s.moving, revision: s.revision, kind: s.motion.kind, before: structuredClone(s.motion.before), after: structuredClone(s.motion.after), elapsed: s.motion.elapsed}
            : false;
        }, revision);
        const started = await startedHandle.jsonValue(); await startedHandle.dispose();
        assert.ok(started.moving && started.kind === 'jump' && equivalent(started.before, before) && equivalent(started.after, before), 'The actual stationary jump animates with identical complete rule snapshots');
        await snapshot(before);
        assert.equal((await state()).revision, revision, 'An in-place jump commits no invented movement or puzzle action');
        return {result: 'a real blocked right-direction attempt establishes stationary jump semantics independently of earlier cases', started};
      });
      await run('switch-and-follow', async () => {const s = initial('1-4'); await load(s); await click({action: 'switch'}); await wait(() => window.__sporelightState?.snapshot?.active === 'buddy'); await click('等候'); await wait(() => window.__sporelightState?.snapshot?.follow === true); return {result: 'actual actor switch and follow toggle'};});
      await run('switch-single-actor-not-offered', async () => {await load(initial('1-1')); assert.ok(!(await state()).buttons.some(b => b.action === 'switch')); return {status: 'verified-not-offered', reason: '1-1 has no character switching control'};});
      await run('return-tool-and-close', async () => {await load(initial('1-1')); await click({action: 'menu'}); await wait(() => window.__sporelightState?.paused); await find('设置'); await close(); await snapshot(initial('1-1'));});
      await run('direction-pad-during-motion-buffer', async () => {
        const s = initial('1-1'); await load(s); const left = await coordinates(await find('←')), upButton = await coordinates(await find('↑'));
        await rawTap(left); await waitMoving(0); await rawTap(upButton);
        await snapshot(point(point(s, 'f:-1:0'), 'f:-1:-1'));
        return {result: 'a direction tapped while moving executes at the next legal boundary'};
      });
      await run('press-release-across-motion-boundary', async () => {
        const s = initial('1-1'); await load(s); const left = await coordinates(await find('←')), upButton = await coordinates(await find('↑'));
        await rawTap(left); await waitMoving(0); await down(upButton);
        await snapshot(point(s, 'f:-1:0')); await up();
        await snapshot(point(point(s, 'f:-1:0'), 'f:-1:-1'));
        return {result: 'a button pressed during motion and released after its boundary is not lost'};
      });
      await run('overview-during-motion', async () => {
        await load(initial('1-1'));
        const before = await state(), button = await find('全景', {allowDisabled: true});
        const primary = await find({action: 'primary'}), coordinate = await coordinates(button), primaryPoint = await coordinates(primary);
        const eventStart = await page.evaluate(() => window.__buttonEvents.length), inapplicable = size.width >= 650 || before.safeCamera;
        inventory.push({case: activeCase, kind: 'timed-button-targets', input, buttons: [primary, button], coordinates: [primaryPoint, coordinate]});
        try {
          await rawTap(primaryPoint);
          await wait(() => {const s = window.__sporelightState; return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.motion.duration === 0.78 && s.motion.elapsed < 0.25;}, undefined, 3000);
          await rawTap(coordinate);
          const downs = await page.evaluate(start => window.__buttonEvents.slice(start).filter(e => e.type === 'pointerdown'), eventStart);
          assert.equal(downs.length, 2, 'Growth and overview each receive an actual pointer press');
          assert.ok(downs.every(e => e.trusted && e.pointerType === input && e.target === 'canvas'), 'Both actions use trusted native canvas input');
          assert.ok(!downs[0].moving && downs[0].revision === 0 && downs[0].hits.some(b => b.action === 'primary' && !b.disabled), 'The real primary starts growth from idle');
          const pressedOverview = downs[1];
          assert.ok(pressedOverview.moving && pressedOverview.revision === 0 && pressedOverview.motion.kind === 'grow:root:right' && pressedOverview.motion.elapsed < pressedOverview.motion.duration,
            'The overview press must actually arrive inside the original uncommitted growth; a late click cannot count');
          assert.ok(pressedOverview.hits.some(b => b.path?.endsWith('/Overview') && b.disabled === inapplicable), 'The cached overview coordinate still hits the actual control with its expected availability');
          let response;
          if (inapplicable) {
            assert.equal(button.disabled, true);
            assert.equal(button.tooltip, '当前已展示整片花园；全景切换适用于小屏跟随镜头。');
            response = await freshQA();
            assert.equal(response.overview, before.overview, 'An inapplicable overview remains inert when pressed inside growth');
          } else {
            assert.equal(button.disabled, false);
            const responseHandle = await wait(() => {
              const s = window.__sporelightState;
              return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.overview === true
                ? {moving: s.moving, revision: s.revision, overview: s.overview, snapshot: structuredClone(s.snapshot), motion: structuredClone(s.motion)} : false;
            }, undefined, 3000);
            response = await responseHandle.jsonValue(); await responseHandle.dispose();
            assert.ok(response.moving && response.overview && response.revision === 0 && equivalent(response.snapshot, initial('1-1')) && equivalent(response.motion.after, rootWith('right')),
              'Overview responds immediately inside the same growth without changing the prepared rule transaction');
          }
          await snapshot(rootWith('right'));
          assert.equal((await state()).revision, 1, 'Only the original root growth commits');
          if (inapplicable) assert.equal((await state()).overview, before.overview, 'A disabled overview never changes the camera mode');
          else {
            await click('跟随'); await wait(() => window.__sporelightState?.overview === false);
            await snapshot(rootWith('right'));
            assert.equal((await state()).revision, 1, 'Restoring the following view cannot change puzzle history');
          }
          return inapplicable ? {status: 'verified-disabled', reason: button.tooltip, response, events: downs}
            : {result: 'small-screen overview responds to a trusted pointer inside the actual 0.78s growth window', response, events: downs};
        } finally {
          inventory.push({case: activeCase, kind: 'trusted-pointer-events', events: await page.evaluate(start => window.__buttonEvents.slice(start), eventStart)});
        }
      });
      await run('pause-and-close', async () => {await load(initial('1-1')); await click('Ⅱ'); await wait(() => window.__sporelightState?.paused); await find('低动态'); await close(); await snapshot(initial('1-1'));});
    }

    if (selectedPhase === 'lifecycle') {
      const closeAndPlay = async label => {
        const before = await freshQA();
        assert.equal(before.moving, false, label + ': close starts from a settled puzzle');
        await close();
        const after = await freshQA();
        assert.ok(equivalent(after.snapshot, before.snapshot), label + ': returning alone preserves the complete puzzle snapshot');
        assert.equal(after.revision, before.revision, label + ': returning alone does not add history');
        return assertInteractive(label);
      };
      await run('settings-return-resumes-pointer-and-keyboard', async () => {
        await load(initial('1-1')); await click('Ⅱ');
        await closeAndPlay('pause settings return');
        return {result: 'actual scrolled return removes its widget and modal, then mode, pointer step and keyboard step work without QA reset'};
      });
      await run('map-settings-return-resumes-pointer-and-keyboard', async () => {
        await load(initial('1-1')); await openMap(); await click('设置');
        await closeAndPlay('map settings return');
      });
      await run('settings-return-button-visible-hit-area', async () => {
        await load(initial('1-1'));
        for (const fraction of [{x: 0.15, y: 0.5}, {x: 0.5, y: 0.5}, {x: 0.85, y: 0.8}]) {
          await click('Ⅱ'); const before = await freshQA();
          await close({fraction});
          assert.ok(equivalent((await state()).snapshot, before.snapshot), 'Each real position on the return button preserves the puzzle');
          await assertInteractive('return hit area ' + JSON.stringify(fraction));
        }
      });
      await run('settings-rapid-wheel-then-return', async () => {
        await load(initial('1-1')); await click('Ⅱ');
        const back = await find('继续当前关卡'), s = await freshQA();
        const owner = controls(s).filter(c => c.class === 'ScrollContainer' && back.path.startsWith(c.path + '/'))
          .sort((a, b) => b.path.length - a.path.length)[0];
        assert.ok(owner, 'Rapid scrolling targets the return button actual scroll owner');
        const scrollPoint = await coordinates(owner);
        await page.mouse.move(scrollPoint.x, scrollPoint.y);
        for (const amount of [-1600, 1800, -600, 2400]) await page.mouse.wheel(0, amount);
        // Read the first new actual geometry after the burst. No arbitrary
        // settling sleep is used to make a scrolling click appear reliable.
        const afterWheel = await freshQA();
        const visible = afterWheel.buttons.find(b => b.instanceId === back.instanceId && !b.disabled);
        assert.ok(visible, 'The real bottom return button is visible after scrolling');
        await close({button: visible});
        await assertInteractive('rapid wheel then return');
        return {scrollInput: 'actual mouse wheel for both pointer contexts; not a touch swipe claim'};
      });
      await run('settings-open-resize-sequence-and-return', async () => {
        await load(initial('1-1'));
        try {
          await resize({width: 1280, height: 720}); await click('Ⅱ');
          for (const extent of [{width: 594, height: 462}, {width: 390, height: 844}, {width: 1280, height: 720}, size]) {
            await resize(extent); await assertModalViewport('settings open at ' + extent.width + 'x' + extent.height);
            await page.screenshot({path: resolve(folder, 'settings-open-resize-' + extent.width + 'x' + extent.height + '.png')});
          }
          await closeAndPlay('settings kept open through viewport changes');
        } finally {await resize(size);}
      });
      await run('settings-return-resumes-paused-growth-once', async () => {
        await load(initial('1-1'));
        const primary = await find({action: 'primary'}), pause = await find('Ⅱ');
        const primaryPoint = await coordinates(primary), pausePoint = await coordinates(pause);
        const eventStart = await page.evaluate(() => window.__buttonEvents.length);
        await rawTap(primaryPoint);
        await wait(() => {
          const s = window.__sporelightState;
          return s?.moving && s.revision === 0 && s.motion?.kind === 'grow:root:right' && s.motion.elapsed < 0.3;
        });
        await rawTap(pausePoint); await wait(() => window.__sporelightState?.paused === true
          && window.__sporelightState.motion?.kind === 'grow:root:right');
        const presses = await page.evaluate(start => window.__buttonEvents.slice(start).filter(e => e.type === 'pointerdown'), eventStart);
        assert.ok(presses.length === 2 && presses[1].trusted && presses[1].pointerType === input && presses[1].moving
          && presses[1].revision === 0 && presses[1].motion.kind === 'grow:root:right', 'The real settings press actually pauses an uncommitted growth');
        const frozen = await state(); await page.waitForTimeout(250);
        const still = await freshQA();
        assert.equal(still.motion.elapsed, frozen.motion.elapsed, 'The actual paused growth clock remains frozen');
        assert.equal(still.revision, 0, 'Pausing cannot commit the seed');
        await close(); await snapshot(rootWith('right'));
        assert.equal((await state()).revision, 1, 'Returning resumes and commits the same growth exactly once');
        await assertInteractive('resumed growth');
      });
      await run('settings-toggles-sliders-and-return-persist', async () => {
        await load(initial('1-1')); await click('Ⅱ');
        const changes = [];
        for (const [label, key] of [['低动态', 'lowMotion'], ['柔和光效', 'dynamicLight'], ['环境粒子', 'particles'], ['按住方向键连续行走', 'continuousInput'], ['镜头避开界面面板', 'safeCamera']]) {
          const value = pressed(await find(label)); await click(label);
          await wait(({key, value}) => window.__sporelightState?.settings?.[key] === value, {key, value: !value});
          changes.push({key, before: value, after: !value});
        }
        for (const setting_id of ['bgm', 'sfx', 'ambient']) {
          const slider = await findControl(c => c.setting_id === setting_id && String(c.class).includes('Slider'));
          const targetFraction = slider.value > 0.65 ? 0.25 : 0.8;
          await rawDrag(await coordinates(slider, {x: 0.5, y: 0.5}), await coordinates(slider, {x: targetFraction, y: 0.5}));
          await wait(({key, before}) => window.__sporelightState?.settings?.[key] !== before, {key: setting_id, before: slider.value});
          const native = controls(await freshQA()).find(c => c.path === slider.path);
          assert.equal(settings(await state())[setting_id], native.value, 'Dragging the actual slider applies its real audio value');
          changes.push({key: setting_id, before: slider.value, after: native.value});
        }
        const expected = structuredClone(settings(await state()));
        await closeAndPlay('settings after toggles and slider drags');
        assert.ok(equivalent(settings(await state()), expected), 'Returning does not discard any changed settings');
        await page.reload({waitUntil: 'networkidle', timeout: 120000});
        await wait(() => window.__sporelightState?.snapshot, undefined, 120000);
        assert.ok(equivalent(settings(await freshQA()), expected), 'The real browser reload preserves every changed setting');
        await assertInteractive('reloaded changed settings');
        return changes;
      });
      await run('completed-ending-map-return-remains-playable', async () => {
        await finish(); const memory = structuredClone((await state()).progress.memories['1-1']);
        await click('返回地图'); await find('设置'); await closeAndPlay('completed ending map return');
        assert.ok(equivalent((await state()).progress.memories['1-1'], memory), 'Walking after map return preserves the completion memory');
      });
      await run('completed-undo-is-explicitly-disabled', async () => {
        await finish(); await click('留下看看');
        await wait(() => window.__sporelightState?.strolling === true && !window.__sporelightState.paused);
        const before = await freshQA();
        assert.equal(before.snapshot.completed, true, 'The real repair and stay flow retains the completed world');
        assert.equal(before.strolling, true, 'The completed garden is actually in stroll mode');
        assert.equal(hasModal(before), false, 'The real ending has closed before inspecting undo');
        const undo = await find({action: 'undo'}, {allowDisabled: true});
        assert.equal(undo.disabled, true, 'Completed-world undo is visibly disabled instead of advertising a silent action');
        assert.ok(typeof undo.tooltip === 'string' && undo.tooltip.trim().length > 0, 'Disabled completed-world undo explains why it cannot run');
        const eventStart = await page.evaluate(() => window.__buttonEvents.length);
        inventory.push({case: activeCase, input, kind: 'completed-disabled-undo', button: undo});
        await rawTap(await coordinates(undo));
        const presses = await page.evaluate(start => window.__buttonEvents.slice(start).filter(e => e.type === 'pointerdown'), eventStart);
        assert.ok(presses.length === 1 && presses[0].trusted && presses[0].pointerType === input && presses[0].target === 'canvas'
          && presses[0].hits.some(b => b.instanceId === undo.instanceId && b.action === 'undo' && b.disabled),
        'A real pointer presses the actual disabled undo control');
        await page.waitForTimeout(150);
        const after = await freshQA();
        assert.ok(equivalent(after.snapshot, before.snapshot), 'Pressing disabled undo preserves the complete completed-world snapshot');
        assert.equal(after.revision, before.revision, 'Pressing disabled undo does not create or replay a commit');
        assert.equal(after.strolling, true, 'Disabled undo does not leave stroll mode');
        assert.equal(hasModal(after), false, 'Disabled undo does not reopen an overlay');
        await assertInteractive('other tools remain usable after disabled completed undo');
        return {result: 'completed undo has an explicit disabled state and reason; the actual press is inert while mode and walking remain usable'};
      });
      await run('completed-ending-map-settings-return-remains-playable', async () => {
        await finish(); const memory = structuredClone((await state()).progress.memories['1-1']);
        await click('返回地图'); await click('设置'); await closeAndPlay('completed ending map settings return');
        assert.ok(equivalent((await state()).progress.memories['1-1'], memory), 'Settings return and subsequent steps preserve the completion memory');
      });
      await run('review-map-settings-return-remains-playable', async () => {
        await finish(); await click('留下看看');
        const memory = structuredClone((await state()).progress.memories['1-1']);
        await openMap(); await click('花园纪事'); await click('看看修复后的花园');
        await wait(() => window.__sporelightState?.reviewing === true && !window.__sporelightState.paused);
        await assertInteractive('actual journal review entry');
        await openMap(); await click('设置'); await closeAndPlay('review map settings return');
        assert.ok(equivalent((await state()).progress.memories['1-1'], memory), 'Review walking and settings do not replace the preserved memory');
      });
      await run('overlay-navigation-chain-without-qa-reset', async () => {
        await finish(); await click('留下看看');
        const memory = structuredClone((await state()).progress.memories['1-1']);
        const legs = [];
        await click('Ⅱ'); await closeAndPlay('chain/pause settings'); legs.push('pause/settings/return/play');
        await openMap(); await closeAndPlay('chain/map'); legs.push('map/return/play');
        await openMap(); await click('设置'); await closeAndPlay('chain/map settings'); legs.push('map/settings/return/play');
        await openMap(); await click('花园纪事'); await closeAndPlay('chain/journal'); legs.push('map/journal/return/play');
        await openMap(); await click('图鉴'); await click('植物'); await click('读一段微光故事');
        await find('返回图鉴'); assert.ok(labels(await state()).includes('雨停之后'), 'The chain opens the real unlocked story');
        await click('返回图鉴'); await find('植物'); await closeAndPlay('chain/gallery story'); legs.push('map/gallery/story/gallery/return/play');
        await openMap(); await click('导入 / 导出旅程'); const saved = await exportSave('navigation-chain-export');
        assert.equal(saved.format, 'sporelight.godot');
        await closeAndPlay('chain/save tools'); legs.push('map/save/export/return/play');
        assert.ok(equivalent((await state()).progress.memories['1-1'], memory), 'The entire no-reset navigation chain retains its completion memory');
        return {legs, qaResetsAfterChainStarted: 0};
      });
      await run('rejected-import-return-remains-playable', async () => {
        await load(initial('1-1')); await openMap(); await click('导入 / 导出旅程');
        const before = (await state()).snapshot;
        const text = await enterText('{broken'); await previewImport(text, '无法读取', true);
        await closeAndPlay('rejected import return');
        assert.equal((await state()).snapshot.levelId, before.levelId);
      });
      await run('successful-import-closes-modal-and-remains-playable', async () => {
        await load(initial('1-1')); await openMap(); await click('导入 / 导出旅程');
        const candidate = await exportSave('lifecycle-import-source');
        candidate.player.name = '返回按钮复查'; candidate.mainline.last_level = '1-1';
        candidate.mainline.runs['1-1'] = initial('1-1');
        candidate.settings.futureLifecyclePreference = {kept: true, revision: 9};
        const text = await enterJson(candidate); await previewImport(text, '检查通过', false);
        const confirm = await click('确认导入'); await closed(confirm);
        await snapshot(initial('1-1'), 'successful import enters its actual unfinished run');
        await assertInteractive('successful import automatic return');
        await openMap(); await click('导入 / 导出旅程');
        const actual = await exportSave('lifecycle-import-confirmed');
        assert.equal(actual.player.name, candidate.player.name, 'The actual accepted import is exported again');
        assert.ok(equivalent(actual.settings.futureLifecyclePreference, candidate.settings.futureLifecyclePreference), 'The import preserves unknown settings fields');
        await closeAndPlay('save tools after accepted import');
      });
    }

    if (selectedPhase === 'commands') {
      for (const test of commandCases()) await run('command-' + test.family.replaceAll(':', '-'), () => actualCommand(test));
      await run('command-family-coverage-manifest', async () => {
        const family = id => id.startsWith('use:') || id.startsWith('grow:root:') ? id : id.split(':')[0];
        const offered = [...new Set(fixture.cases.flatMap(c => [c.initial, ...c.steps].flatMap(s => (s.commands ?? []).map(v => family(v.id)))))].sort();
        const represented = [...new Set(commandCases().map(t => t.family))].sort();
        const tested = [...new Set(results.filter(r => r.status === 'passed' && r.name.startsWith('command-') && r.details?.family).map(r => r.details.family))].sort();
        assert.deepEqual(represented, offered, 'Every advertised fixture command family has an executable successful representative');
        assert.deepEqual(tested, offered, 'Every advertised family was actually clicked and passed in this viewport/input row');
        return {testedFamilies: tested, offeredFamiliesInFixtures: offered,
          testedRepresentatives: results.filter(r => r.status === 'passed' && r.details?.command).map(r => r.details.command),
          scope: 'One successful real pointer action per family, use subtype and first-garden growth direction; not every parameter/angle/level combination'};
      });
    }

    if (selectedPhase === 'overlays') {
      await run('map-open-select-level', async () => {await load(initial('1-1')); await openMap(); await click({includes: '1-2  '}); await wait(() => window.__sporelightState?.snapshot?.levelId === '1-2' && !window.__sporelightState?.paused); return {note: 'QA map intentionally unlocks level choices; this does not validate normal progression gating'};});
      await run('map-first-settings-nondefault', async () => {
        await load(initial('1-1')); await openMap(); await click('导入 / 导出旅程');
        const store = await exportSave('settings-seed-export');
        store.settings.lowMotion = true; store.settings.particles = false; store.settings.dynamicLight = false; store.settings.continuousInput = false; store.settings.safeCamera = true;
        store.settings.bgm = 0.1; store.settings.sfx = 0.2; store.settings.ambient = 0.15;
        const text = await enterJson(store); await previewImport(text, '检查通过', false); await click('确认导入');
        await wait(() => window.__sporelightState?.continuousInput === false && window.__sporelightState?.safeCamera === true);
        await page.reload({waitUntil: 'networkidle', timeout: 120000}); await wait(() => window.__sporelightState?.snapshot, undefined, 120000);
        // This is the first settings entry after reload. Never click Ⅱ first:
        // doing so would populate HUD._settings and hide the map-entry bug.
        await openMap(); await click('设置');
        const current = await state();
        if (!settings(current) || !controls(current).length) throw new NotCovered('Read-only settings/control values are needed to verify the first map settings view');
        for (const [key, value] of Object.entries(store.settings)) assert.ok(equivalent(settings(current)[key], value), 'The actual reloaded settings retain the imported nondefault ' + key);
        for (const [label, expectedValue] of [['低动态', true], ['环境粒子', false], ['柔和光效', false], ['按住方向键连续行走', false], ['镜头避开界面面板', true]]) {
          const b = await find(label); assert.equal(pressed(b), expectedValue, 'First map settings reflects saved nondefault ' + label);
        }
        for (const [setting_id, value] of [['bgm', 0.1], ['sfx', 0.2], ['ambient', 0.15]]) {
          const slider = controls(await state()).find(c => c.setting_id === setting_id);
          assert.ok(slider && Math.abs(slider.value - value) < 0.000001, 'First map settings displays the actual nondefault slider ' + setting_id);
        }
        await close(); return {result: 'nondefault settings imported, reloaded, then first entered through map'};
      });
      for (const label of ['低动态', '柔和光效', '环境粒子', '按住方向键连续行走', '镜头避开界面面板']) await run('settings-toggle-' + label, async () => {
        await load(initial('1-1')); await click('Ⅱ'); const b = await find(label), before = pressed(b);
        if (typeof before !== 'boolean') throw new NotCovered('QA button pressed state is not exposed');
        await click(label); await wait(({text, value}) => window.__sporelightState?.buttons?.some(b => b.text === text && (b.pressed ?? b.button_pressed ?? b.buttonPressed) === value), {text: label, value: !before});
        const setting_id = ({'低动态': 'lowMotion', '柔和光效': 'dynamicLight', '环境粒子': 'particles', '按住方向键连续行走': 'continuousInput', '镜头避开界面面板': 'safeCamera'})[label];
        assert.equal(settings(await state())?.[setting_id], !before, 'Toggle changes the actual application setting, not only the drawn check mark');
        await click(label); await close(); return {before, after: !before, restored: before};
      });
      await run('settings-three-sliders', async () => {
        await load(initial('1-1')); await click('Ⅱ'); await findControl(c => String(c.class ?? c.type ?? '').includes('Slider'));
        const sliders = controls(await freshQA()).filter(c => String(c.class ?? c.type ?? '').includes('Slider'));
        if (sliders.length !== 3) throw new NotCovered('Read-only HSlider geometry/value metadata is not exposed');
        const changed = [];
        for (const source of sliders) {
          const slider = await findControl(c => c.path === source.path);
          const coordinate = await coordinates(slider); const r = slider.visibleRect ?? slider.rect ?? [slider.x, slider.y, slider.width, slider.height];
          coordinate.x -= r[2] * 0.2; const before = await publication(); await rawTap(coordinate); await freshQA(before);
          await wait(({path, before}) => (window.__sporelightState?.ui?.controls ?? window.__sporelightState?.uiControls ?? window.__sporelightState?.controls ?? [])
            .some(c => c.path === path && c.value !== before), {path: slider.path, before: slider.value});
          const actual = controls(await state()).find(c => c.path === slider.path); assert.ok(actual && actual.value !== slider.value, 'Real slider click changes its actual value'); changed.push({path: slider.path, before: slider.value, after: actual.value});
          assert.ok(slider.setting_id && Math.abs(settings(await state())[slider.setting_id] - actual.value) < 0.000001, 'Slider value is applied to the real audio setting');
        }
        await close(); return changed;
      });
      await run('ending-stay', async () => {await finish(); await click('留下看看'); await wait(() => window.__sporelightState?.strolling === true && !window.__sporelightState?.paused);});
      await run('ending-next', async () => {await finish(); await click('去下一片微光 ↗'); await wait(() => window.__sporelightState?.snapshot?.levelId === '1-2' && !window.__sporelightState?.paused);});
      await run('ending-return-map', async () => {await finish(); await click('返回地图'); await find('设置'); assert.equal((await state()).paused, true); await close();});
      await run('journal-review-and-return', async () => {await finish(); await click('留下看看'); await openMap(); await click('花园纪事'); await click('看看修复后的花园'); await wait(() => window.__sporelightState?.reviewing === true); assert.equal((await state()).snapshot.completed, true);});
      await run('gallery-categories-story-back', async () => {
        await finish(); await click('留下看看'); await openMap(); await click('图鉴');
        if (!controls(await state()).length) throw new NotCovered('Read-only overlay labels are needed to prove category/detail content, beyond button counts');
        for (const category of ['全部', '植物', '生物', '建筑', '奇物']) {
          await click(category); await page.waitForTimeout(100); const s = await state();
          assert.equal(pressed(await find(category)), true, 'The clicked category becomes selected');
          if (category === '植物' || category === '全部') assert.ok(labels(s).includes('萌芽花台'), 'Unlocked first-flower entry appears in its real category');
          else assert.ok(!labels(s).includes('萌芽花台'), 'Other categories remove the first-flower entry');
        }
        await click('植物'); await click('读一段微光故事'); await find('返回图鉴');
        assert.ok(labels(await state()).includes('雨停之后'), 'The real story detail displays its narrative');
        await click('返回图鉴'); await find('植物'); await close();
      });
      await run('save-export-invalid-valid-duplicate-import', async () => {
        await load(initial('1-1')); await openMap(); await click('导入 / 导出旅程');
        const exported = await exportSave('export-click'); assert.equal(exported.format, 'sporelight.godot');
        const before = (await state()).snapshot;
        const invalidText = await enterText('{broken');
        const disabled = await previewImport(invalidText, '无法读取', true); assert.equal(disabled.disabled, true); assert.ok(equivalent((await state()).snapshot, before), 'Invalid import does not replace the run');
        assert.ok(labels(await state()).includes('无法读取'), 'Invalid JSON displays its actual rejection status');
        exported.player.name = '按钮验收'; const validText = await enterJson(exported); await previewImport(validText, '检查通过', false);
        assert.ok(labels(await state()).includes('检查通过'), 'Valid JSON displays a preview before confirmation');
        await click('确认导入');
        await wait(() => window.__sporelightState && !window.__sporelightState.moving && !window.__sporelightState.paused
          && !window.__sporelightState.hudRegions?.some(r => r.name === 'ModalOverlay'));
        await openMap(); await click('导入 / 导出旅程');
        const actual = await exportSave('export-after-import'); assert.equal(actual.player.name, '按钮验收', 'Confirmed import actually persisted the candidate');
        const duplicateText = await enterJson(exported); await previewImport(duplicateText, '已经导入', true); assert.equal((await find('确认导入', {allowDisabled: true})).disabled, true, 'Duplicate import cannot be confirmed twice');
        assert.ok(labels(await state()).includes('已经导入'), 'Duplicate JSON displays a duplicate status rather than silently reapplying');
        await click('读取本网站的旧旅程（先预览）'); assert.equal((await find('确认导入', {allowDisabled: true})).disabled, true, 'Fresh browser storage has no old journey to silently import');
        await close();
      });
    }
  } catch (error) {results.push({name: activeCase, status: 'failed', reason: String(error), fatalRow: true});}
  finally {await up().catch(() => {}); await context.close();}
  const result = {row: key, phase: selectedPhase, viewport: size, input, results, inventory,
    scope: 'Only executed cases marked passed were verified. Disabled/not-offered controls are explicit expectations; uncovered cases require follow-up and are never reported as all buttons passed.'};
  await writeFile(resolve(folder, 'checks.json'), JSON.stringify(result, null, 2) + '\n');
  return result;
}

try {
  build = await fetch(new URL('/__build.json', base)).then(r => {assert.ok(r.ok); return r.json();});
  browser = await chromium.launch({channel: 'chrome', headless: true});
  for (const size of sizes) for (const input of inputs) for (const selectedPhase of phases) rows.push(await matrixRow(size, input, selectedPhase));
} catch (error) {fatal = String(error);}
finally {
  if (browser) await browser.close();
  const executed = rows.flatMap(r => r.results.map(test => ({row: r.row, ...test})));
  const failed = executed.filter(r => r.status === 'failed'), uncovered = executed.filter(r => r.status === 'uncovered');
  const report = {passed: !fatal && !failed.length && !uncovered.length && !errors.length,
    date: new Date().toISOString(), base, build, phase, sizes, inputs, caseFilter: filter,
    fatal, summary: {executed: executed.length, passed: executed.filter(r => r.status === 'passed').length, failed: failed.length, uncovered: uncovered.length},
    failed: failed.map(({name, row, reason}) => ({name, row, reason})), uncovered: uncovered.map(({name, row, reason}) => ({name, row, reason})), errors,
    rows: rows.map(({inventory, results, ...row}) => ({...row, results: results.map(({observed, details, ...r}) => r)})),
    limitations: ['Fresh isolated storage per viewport/input/phase; fixture snapshots arrange legal states, but actions under test use actual mouse/touch/text input.',
      'All command families represented by successful fixtures are sampled; this does not claim every parameter, angle, failure branch or level combination.',
      'Sliders, toggles, text and modal content need read-only QA control metadata. Missing data is recorded as uncovered rather than substituting signal emission or node counts.',
      'Touch buttons use native touchscreen events, while scrolling long canvas panels uses actual mouse-wheel input; touch swipe/pinch gesture coverage is separate.',
      'Pasted JSON uses real ASCII keyboard events with Unicode escapes and exact TextEdit/decoded-JSON verification. Direct Chinese/IME entry is not covered; earlier evidence showed non-ASCII keyboard.type characters being dropped.',
      'Desktop native file dialogs are outside this Web matrix. A Web download and pasted import are validated when corresponding controls are observable.',
      'Mouse contexts do not advertise touch capability. Lifecycle return checks use the first-garden fixed grid and verify modal removal plus real pointer and keyboard play without QA reset; they do not exhaust every later-level navigation state.',
      'A passing input matrix does not certify artwork, comfort, native-depth correctness or performance.']};
  await writeFile(resolve(output, 'checks.json'), JSON.stringify(report, null, 2) + '\n');
  if (!report.passed) process.exitCode = 1;
  console.log(JSON.stringify({passed: report.passed, ...report.summary, fatal, errors: errors.length, output}));
}

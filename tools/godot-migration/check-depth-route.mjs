import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve, dirname, relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';

// A real-keyboard route recording, deliberately separate from performance
// sampling. A video encoder can change pacing; its output needs human review.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const option = (name, fallback) => process.argv.find(value => value.startsWith(`--${name}=`))?.slice(name.length + 3) ?? fallback;
const base = option('base', 'http://localhost:4186/');
const output = resolve(option('output', resolve(tmpdir(), 'sporelight-depth-route')));
const sizes = option('sizes', '1280x720,390x844,568x320').split(',').map(value => {
  const match = /^(\d+)x(\d+)$/.exec(value);
  assert.ok(match, `Viewport must be WIDTHxHEIGHT: ${value}`);
  const [width, height] = match.slice(1).map(Number);
  assert.ok(width > 0 && height > 0 && width <= 8192 && height <= 8192, 'Viewport is within a practical recording range');
  return {width, height};
});
const {chromium} = createRequire(import.meta.url)(option('playwright', process.env.PLAYWRIGHT_MODULE ?? 'C:/Users/jeffrey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'));
const fixtures = JSON.parse(await readFile(resolve(root, 'godot/tests/fixtures/reference.json'), 'utf8'));
const initial = fixtures.cases.find(entry => entry.name === 'authored/1-1')?.initial.snapshot;
assert.ok(initial && !initial.completed && initial.growth.root.length === 0, 'The frozen fixture starts without a generated road');
const catalog = JSON.parse(await readFile(resolve(root, 'godot/content/levels.json'), 'utf8'));
const level = catalog.levels.find(entry => entry.id === '1-1');
assert.ok(level && level.roots[0].budget === 1, 'The route consumes the existing one-root puzzle');
const loop = ['f:0:0', 'g:root:1:0', 'f:2:0', 'f:2:-1', 'f:3:-1', 'f:4:-1', 'f:4:0', 'f:3:0', 'f:2:0', 'g:root:1:0', 'f:0:0'];
const reversal = ['f:0:0', 'g:root:1:0', 'f:2:0', 'g:root:1:0', 'f:0:0'];
const arrow = (from, to) => {
  const point = id => {
    const parts = /^(?:f|g:root):(-?\d+):(-?\d+)$/.exec(id);
    assert.ok(parts, 'This first-garden route uses fixed/root tile identities');
    return parts.slice(1).map(Number);
  };
  const [x, z] = point(from), [tx, tz] = point(to);
  assert.equal(Math.abs(tx - x) + Math.abs(tz - z), 1, 'Each key traverses exactly one cardinal rule edge');
  return tx > x ? 'ArrowRight' : tx < x ? 'ArrowLeft' : tz > z ? 'ArrowDown' : 'ArrowUp';
};
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : Object.is(value, -0) ? 0 : value;
const equivalent = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const errors = [], results = [];
let errorEvents = 0, build = null, browser = null, failure = null;
await mkdir(output, {recursive: true});

async function recordSize(size) {
  const name = `${size.width}x${size.height}`;
  const folder = resolve(output, name);
  await mkdir(folder, {recursive: true});
  // Every viewport gets fresh isolated storage; no user browser or existing
  // context is opened, and no grown snapshot is ever used as a shortcut.
  const context = await browser.newContext({viewport: size, deviceScaleFactor: 1, recordVideo: {dir: resolve(folder, 'video'), size}});
  await context.route('**/favicon.ico', route => route.fulfill({status: 204, body: ''}));
  await context.addInitScript(() => {
    window.__depthRouteTrack = {phase: 'startup', samples: [], keys: []};
    for (const type of ['keydown', 'keyup']) window.addEventListener(type, event => {
      const track = window.__depthRouteTrack, state = window.__sporelightState;
      track.keys.push({type, key: event.key, repeat: event.repeat, trusted: event.isTrusted, phase: track.phase,
        wallMs: performance.now(), moving: state?.moving, revision: state?.revision});
    }, true);
    setInterval(() => {
      const track = window.__depthRouteTrack, state = window.__sporelightState;
      if (!state?.snapshot) return;
      const character = state.character ?? {}, foot = character.footpoint ?? character.anchor ?? null;
      track.samples.push({wallMs: performance.now(), phase: track.phase, moving: state.moving, paused: state.paused,
        revision: state.revision, actors: structuredClone(state.snapshot.actors), footpoint: structuredClone(foot),
        screenFootpoint: structuredClone(character.screen_footpoint ?? null),
        worldDepthFromFoot: foot && Number.isFinite(foot.x) && Number.isFinite(foot.z) ? foot.x + foot.z : null,
        facing: character.facing ?? null, poseKey: character.key ?? null, walkStartedMs: character.walk_started ?? null,
        scale: state.scale, origin: structuredClone(state.origin),
        motion: {kind: state.motion?.kind ?? '', elapsed: state.motion?.elapsed ?? 0, duration: state.motion?.duration ?? 0,
          from: state.motion?.before?.actors?.luvie ?? '', to: state.motion?.after?.actors?.luvie ?? ''},
        input: structuredClone(state.input ?? {})});
    }, 20);
  });
  const page = await context.newPage();
  const video = page.video();
  const steps = [], screenshots = [], sizeErrors = [];
  let expected = structuredClone(initial), expectedRevision = 0, phase = 'startup', sizeFailure = null, track = null, final = null;
  let snapshotsRequested = 0;
  const recordError = (category, text) => {
    errorEvents++;
    const entry = {viewport: name, phase, category, text};
    errors.push(entry); sizeErrors.push(entry);
  };
  page.on('pageerror', value => recordError('javascript', value.message));
  page.on('console', message => {
    if (message.type() === 'error' || /SCRIPT ERROR:|ERROR:/.test(message.text())) recordError('godot-or-browser', message.text());
  });
  page.on('response', response => {
    if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) recordError('http', `${response.status()} ${response.url()}`);
  });
  const state = () => page.evaluate(() => structuredClone(window.__sporelightState));
  const wait = (predicate, arg, timeout = 15000) => page.waitForFunction(predicate, arg, {timeout, polling: 10});
  const release = async () => {
    for (const key of ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'e']) await page.keyboard.up(key).catch(() => {});
  };
  const setPhase = async value => {
    phase = value;
    await page.evaluate(label => {window.__depthRouteTrack.phase = label;}, value);
  };
  const stable = async (label, timeout = 15000) => {
    await wait(({snapshot, revision}) => {
      const s = window.__sporelightState;
      if (!s || s.moving || s.revision !== revision) return false;
      const norm = v => Array.isArray(v) ? v.map(norm) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, norm(v[k])])) : Object.is(v, -0) ? 0 : v;
      return JSON.stringify(norm(s.snapshot)) === JSON.stringify(norm(snapshot));
    }, {snapshot: expected, revision: expectedRevision}, timeout).catch(async cause => {
      const actual = await state().catch(() => null);
      await writeFile(resolve(folder, 'failure-state.json'), JSON.stringify({label, expected, expectedRevision, actual}, null, 2) + '\n');
      throw new Error(`${label}: expected stable tile ${expected.actors.luvie} / revision ${expectedRevision}; inspect ${name}/failure-state.json`, {cause});
    });
    const current = await state();
    assert.ok(equivalent(current.snapshot, expected), label + ' retains the full expected puzzle snapshot');
    assert.equal(current.safeCamera, false, 'The recording retains the original camera mode');
    return current;
  };
  const screenshot = async label => {
    const file = `${label}.png`;
    await page.screenshot({path: resolve(folder, file)});
    screenshots.push(file);
  };
  const expectMove = target => {
    expected.actors.luvie = target;
    expected.actors.buddy = target;
    for (const collectible of level.collectibles) if (collectible.tile === target && !expected.collected.includes(collectible.id)) expected.collected.push(collectible.id);
    expectedRevision++;
  };
  const keyTransition = async (key, oldRevision, label) => {
    // Start observing before delivering the trusted event. This avoids relying
    // on a sleep to guess when a 205ms move or sowing animation has started.
    await Promise.all([
      page.keyboard.press(key),
      wait(revision => {
        const state = window.__sporelightState, track = window.__depthRouteTrack;
        return state?.moving || state?.revision > revision || track.samples.some(sample => sample.phase === track.phase && sample.moving);
      }, oldRevision),
    ]);
    await stable(label);
  };
  const step = async (target, label) => {
    const source = expected.actors.luvie, revision = expectedRevision, key = arrow(source, target);
    await setPhase(label);
    expectMove(target);
    await keyTransition(key, revision, label);
    steps.push({label, key, from: source, to: target, revision: expectedRevision, input: 'trusted-keyboard-press'});
  };
  try {
    const url = new URL(base); url.searchParams.set('qa', '1');
    await page.goto(url.href, {waitUntil: 'networkidle', timeout: 120000});
    await wait(() => typeof window.__sporelightRequest === 'function' && window.__sporelightState?.snapshot, undefined, 120000);
    assert.equal(await page.locator('#canvas').count(), 1, 'The actual Godot canvas is present');
    snapshotsRequested++;
    await page.evaluate(snapshot => window.__sporelightRequest(JSON.stringify({type: 'snapshot', snapshot, time: 1200})), initial);
    await stable('one initial fixture setup');
    await page.evaluate(() => window.__sporelightRequest(JSON.stringify({type: 'action', command: 'resume'})));
    await wait(() => !window.__sporelightState?.paused);
    await page.locator('#canvas').evaluate(canvas => canvas.focus());
    assert.equal((await state()).continuousInput, true, 'Normal held keyboard movement is enabled');
    await setPhase('initial-unplanted');
    await screenshot('initial');

    await setPhase('real-E-seed-road');
    expected.growth.root = ['g:root:1:0']; expectedRevision++;
    await keyTransition('e', 0, 'real E creates the original right root road');
    assert.deepEqual((await state()).snapshot.growth.root, ['g:root:1:0'], 'E actually generated the road; no grown snapshot was injected');
    steps.push({label: phase, key: 'e', revision: expectedRevision, input: 'trusted-keyboard-press'});

    for (const [routeName, route] of [['loop', loop], ['reverse-loop', [...loop].reverse()]]) {
      for (const [index, target] of route.slice(1).entries()) {
        await step(target, `${routeName}/${index + 1}/${target}`);
        if (routeName === 'loop') {
          if (index === 0) await screenshot('upstairs');
          if (index === 1) await screenshot('landing');
          if (index === 2) await screenshot('toprear');
          if (index === 3) await screenshot('turn');
          if (index === route.length - 2) await screenshot('returned');
        }
      }
    }
    // Explicitly turn back at the first landing, in addition to the main
    // loop's immediate turn toward the rear platform after disembarking.
    for (const [index, target] of reversal.slice(1).entries()) await step(target, `landing-immediate-reverse/${index + 1}/${target}`);

    await setPhase('held-left-to-boundary');
    const revisionBeforeHold = expectedRevision;
    expectMove('f:-1:0'); expectMove('f:-2:0');
    try {
      await Promise.all([
        page.keyboard.down('ArrowLeft'),
        wait(revision => window.__sporelightState?.moving || window.__sporelightState?.revision > revision, revisionBeforeHold),
      ]);
      await stable('held left reaches the actual left boundary');
    } finally {
      await page.keyboard.up('ArrowLeft').catch(() => {});
    }
    await wait(() => !window.__sporelightState?.moving && (window.__sporelightState?.input?.held?.length ?? 0) === 0);
    await setPhase('release-500ms');
    const released = await state();
    await page.waitForTimeout(500);
    const afterRelease = await state();
    assert.ok(equivalent(released.snapshot, afterRelease.snapshot), 'Key release preserves the complete puzzle snapshot for 500ms');
    assert.equal(afterRelease.revision, released.revision, 'No continued movement commits after release');
    assert.ok(equivalent(released.character?.footpoint, afterRelease.character?.footpoint), 'The world foot does not drift during the release wait');
    steps.push({label: 'hold-left-and-release', from: 'f:0:0', to: 'f:-2:0', revision: expectedRevision, releaseWaitMs: 500});
    await step('f:-1:0', 'real-right-return/1');
    await step('f:0:0', 'real-right-return/2');
    assert.equal(snapshotsRequested, 1, 'Only the original unplanted snapshot was loaded');
    final = await stable('final root-island state');
    assert.equal(final.snapshot.completed, false, 'The visual route did not silently plant/complete the puzzle');
    await screenshot('returned-after-release');
    await release();
    track = await page.evaluate(() => structuredClone(window.__depthRouteTrack));
    assert.ok(track.keys.some(event => event.type === 'keydown' && event.key === 'e' && event.trusted), 'The seed road originated from a real trusted E event');
    assert.ok(track.keys.filter(event => event.type === 'keydown' && event.key.startsWith('Arrow')).every(event => event.trusted), 'Every route arrow came through the browser input path');
    const measured = track.samples.filter(sample => sample.phase !== 'startup');
    assert.ok(measured.length > 20, 'The real-time route sampler observed the run');
    for (const sample of measured) {
      assert.ok(sample.footpoint && ['x', 'z', 'h'].every(key => Number.isFinite(sample.footpoint[key])), 'Published actual world foot remains finite');
      assert.ok(sample.screenFootpoint && ['x', 'y'].every(key => Number.isFinite(sample.screenFootpoint[key])), 'Published body screen foot remains finite');
      assert.ok(Number.isFinite(sample.worldDepthFromFoot) && Number.isFinite(sample.scale) && sample.scale > 0 && sample.origin.every(Number.isFinite), 'Depth anchor and camera remain finite');
    }
    assert.deepEqual(sizeErrors, [], 'No JavaScript, Godot, browser or HTTP errors occurred');
  } catch (error) {
    sizeFailure = String(error);
    final = await state().catch(() => null);
    track = await page.evaluate(() => structuredClone(window.__depthRouteTrack)).catch(() => null);
    await page.screenshot({path: resolve(folder, 'failure.png')}).catch(() => {});
  } finally {
    await release();
    // Closing the context flushes the encoder. Resolve/save its video only
    // after close; an unfinished video path is not delivery evidence.
    await context.close();
  }
  let videoFile = null;
  if (video) {
    const destination = resolve(folder, 'route-review.webm');
    await video.saveAs(destination);
    videoFile = relative(output, destination).replaceAll('\\', '/');
  }
  const result = {passed: !sizeFailure, viewport: size, phase, error: sizeFailure, snapshotsRequested,
    steps, screenshots, videoFile, sampleIntervalRequestedMs: 20, samples: track?.samples ?? [], keys: track?.keys ?? [],
    errors: sizeErrors, final, manualReview: {required: true, status: 'not-performed-by-this-script',
      scope: 'Play route-review.webm and inspect the stair, island movement, characters, foreground occlusion and readability. Automated success does not mean the user finds the movement natural.'}};
  await writeFile(resolve(folder, 'checks.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({viewport: name, passed: result.passed, steps: steps.length, samples: result.samples.length, videoFile, error: sizeFailure}));
  return result;
}

try {
  build = await fetch(new URL('/__build.json', base)).then(response => {
    assert.ok(response.ok, 'The preview exposes current build metadata');
    return response.json();
  });
  browser = await chromium.launch({channel: 'chrome', headless: true});
  for (const size of sizes) results.push(await recordSize(size));
  if (results.some(result => !result.passed)) throw new Error('At least one real-keyboard viewport case failed; inspect its checks.json and video');
} catch (error) {
  failure = String(error);
  process.exitCode = 1;
} finally {
  if (browser) await browser.close();
  const report = {passed: !failure, date: new Date().toISOString(), base, build, referenceCommit: fixtures.referenceCommit,
    failure, results: results.map(({samples, keys, final, ...result}) => ({...result, samples: samples.length, keys: keys.length, finalSnapshot: final?.snapshot ?? null})),
    errors, errorEvents, source: 'Fresh browser context per viewport; one unplanted fixture setup followed solely by real E/arrow input. No generated-road snapshot, direct action replay or user storage was used.',
    scope: 'passed means input/rule-snapshot agreement, finite published foot/camera values and the release-stop check succeeded. This is not a visual-quality or performance verdict.',
    limitations: ['20ms sampling reads a QA state published approximately every 50ms; repeated state values are expected and these are not exact-frame GPU measurements.',
      'Video encoding and recording may affect pacing. No frame-rate or input-latency claim is inferred from this recording.',
      'Human review of all three videos and key images is required; comfort, actual sprite pixels and native depth occlusion are not certified by numeric success.']};
  await writeFile(resolve(output, 'checks.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({passed: report.passed, viewports: results.length, errors: errors.length, failure, output}));
}

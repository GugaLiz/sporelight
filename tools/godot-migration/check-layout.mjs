import {createRequire} from 'node:module';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {resolve, dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {inflateSync} from 'node:zlib';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const option = (key, fallback) => process.argv.find(value => value.startsWith(`--${key}=`))?.slice(key.length + 3) ?? fallback;
const {chromium} = createRequire(import.meta.url)(option('playwright', join(process.env.USERPROFILE ?? '', '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')));
const output = resolve(root, option('output', 'docs/qa-godot-migration/layout'));
const base = option('url', 'http://localhost:4185/');
const fixture = JSON.parse(await readFile(join(root, 'godot/tests/fixtures/reference.json'), 'utf8'));
const levels = JSON.parse(await readFile(join(root, 'godot/content/levels.json'), 'utf8')).levels;
const sizes = option('sizes', '1280x720,1440x900,1920x1080,738x672,649x700,650x700,900x700,901x700,390x844,844x390,320x568,568x320').split(',').map(value => value.split('x').map(Number));
const ids = option('levels', '1-1,1-4,2-2,3-4').split(',');
const modes = option('modes', 'reference,safe-camera').split(',');
const checks = [], captures = [], errors = [], consoleEvents = [];
const buildSources = [];
let activePage, activeCase;
await mkdir(output, {recursive: true});

const inside = (point, rect, tolerance = 1) => point[0] >= rect[0] - tolerance && point[1] >= rect[1] - tolerance && point[0] <= rect[0] + rect[2] + tolerance && point[1] <= rect[1] + rect[3] + tolerance;
const area = rect => Math.max(0, rect[2]) * Math.max(0, rect[3]);
const intersection = (a, b) => {const x = Math.max(a[0], b[0]), y = Math.max(a[1], b[1]); return [x, y, Math.max(0, Math.min(a[0] + a[2], b[0] + b[2]) - x), Math.max(0, Math.min(a[1] + a[3], b[1] + b[3]) - y)];};
const within = (a, b) => inside([a[0], a[1]], b) && inside([a[0] + a[2], a[1] + a[3]], b);
const intersects = (a, b, tolerance = 1) => {const cut = intersection(a, b); return cut[2] > tolerance && cut[3] > tolerance;};
const rectOf = button => [button.x, button.y, button.width, button.height];
const plain = value => Array.isArray(value) ? value.map(plain) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, plain(value[key])])) : Object.is(value, -0) ? 0 : value;
const equivalent = (a, b) => JSON.stringify(plain(a)) === JSON.stringify(plain(b));

function bindErrors(page) {
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    const graphicsFailure = /could not create render target|framebuffer.*(?:fail|incomplete|unsupported)|(?:webgl|graphics|gpu)\s*context\s*(?:was\s*)?lost|context_lost_webgl/i.test(message.text());
    if (['warning', 'error'].includes(message.type()) || /WARNING:|ERROR:/i.test(message.text()) || graphicsFailure) consoleEvents.push({time: new Date().toISOString(), case: activeCase && {...activeCase}, type: message.type(), text: message.text()});
    if (message.type() === 'error' || /SCRIPT ERROR:|ERROR:/.test(message.text()) || graphicsFailure) errors.push(message.text());
  });
  page.on('response', response => {if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) errors.push(`${response.status()} ${response.url()}`);});
}

// Decode actual screenshot pixels: live QA geometry alone cannot prove that WebGL drew a frame.
function frameStats(png) {
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  let width, height, channels;
  const chunks = [];
  for (let at = 8; at < png.length;) {
    const length = png.readUInt32BE(at), type = png.toString('ascii', at + 4, at + 8), data = png.subarray(at + 8, at + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4);
      assert.equal(data[8], 8, 'Screenshot PNG must use 8-bit channels');
      channels = ({2: 3, 6: 4})[data[9]];
      assert.ok(channels && data[12] === 0, 'Screenshot PNG must be non-interlaced RGB/RGBA');
    } else if (type === 'IDAT') chunks.push(data);
    at += length + 12;
  }
  const raw = inflateSync(Buffer.concat(chunks)), stride = width * channels;
  assert.equal(raw.length, (stride + 1) * height);
  let previous = Buffer.alloc(stride), current = Buffer.alloc(stride), nearBlack = 0, transparent = 0;
  const paeth = (a, b, c) => {const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;};
  for (let y = 0; y < height; y++) {
    const at = y * (stride + 1), filter = raw[at];
    assert.ok(filter <= 4);
    for (let x = 0; x < stride; x++) {
      const left = x < channels ? 0 : current[x - channels], above = previous[x], upperLeft = x < channels ? 0 : previous[x - channels];
      current[x] = (raw[at + 1 + x] + (filter === 0 ? 0 : filter === 1 ? left : filter === 2 ? above : filter === 3 ? Math.floor((left + above) / 2) : paeth(left, above, upperLeft))) & 255;
    }
    for (let x = 0; x < stride; x += channels) {
      if (Math.max(current[x], current[x + 1], current[x + 2]) < 8) nearBlack++;
      if (channels === 4 && current[x + 3] < 8) transparent++;
    }
    [current, previous] = [previous, current];
  }
  return {width, height, bytes: png.length, nearBlackFraction: nearBlack / (width * height), transparentFraction: transparent / (width * height)};
}

async function glDiagnostic(page) {
  return page.evaluate(() => {
    const canvas = document.querySelector('#canvas'), gl = canvas?.getContext('webgl2');
    const ext = gl?.getExtension('WEBGL_debug_renderer_info');
    return {canvas: canvas && {width: canvas.width, height: canvas.height}, contextEvents: window.__contextEvents,
      gl: gl && {isContextLost: gl.isContextLost(), error: gl.getError(), renderer: ext && gl.getParameter(ext.UNMASKED_RENDERER_WEBGL), drawingBuffer: [gl.drawingBufferWidth, gl.drawingBufferHeight]}};
  });
}

async function settled(page, snapshot, width, height) {
  await page.waitForFunction(({id, width, height}) => {
    const state = window.__sporelightState, canvas = document.querySelector('#canvas');
    return state?.snapshot?.levelId === id && !state.moving && state.viewport?.[0] === width && state.viewport?.[1] === height && canvas.width === width && canvas.height === height;
  }, {id: snapshot.levelId, width, height}, {timeout: 15000, polling: 40});
  let previous = '', stable = 0, latest;
  for (let attempt = 0; attempt < 30; attempt++) {
    latest = await page.evaluate(() => structuredClone(window.__sporelightState));
    assert.ok(Array.isArray(latest.hudRegions), 'Fresh QA payload must expose actual HUD regions');
    assert.ok(equivalent(latest.snapshot, snapshot), 'Layout setup must retain the requested rule snapshot');
    const key = JSON.stringify({scale: latest.scale, origin: latest.origin, safeRect: latest.safeRect, hud: latest.hudRegions, buttons: latest.buttons.map(button => [button.path, button.x, button.y, button.width, button.height, button.clipped])});
    stable = key === previous ? stable + 1 : 0;
    if (stable >= 2) return latest;
    previous = key;
    await page.waitForTimeout(120);
  }
  throw new Error('HUD/camera geometry did not settle after the requested snapshot and resize');
}

function observations(current, level, width, height) {
  const viewport = [0, 0, width, height], regions = current.hudRegions;
  const targetById = new Map(current.targets.map(target => [target.id, target]));
  const pointObservation = (id, x, y) => ({id, x, y, insideViewport: inside([x, y], viewport), coveredBy: regions.filter(region => inside([x, y], region.rect, 0)).map(region => region.name)});
  const actors = [];
  for (const actor of ['luvie', 'buddy']) {
    const tile = targetById.get(current.snapshot.actors[actor]);
    if (!tile) {actors.push({id: actor, projected: false}); continue;}
    const sameTile = current.snapshot.actors.luvie === current.snapshot.actors.buddy;
    const offset = sameTile ? actor === 'luvie' ? 8 : -24 : 0;
    actors.push({...pointObservation(actor, tile.x + offset * current.scale, tile.y + (actor === 'luvie' ? 7 : 4) * current.scale), projected: true, measurement: 'foot anchor; not a sprite alpha-mask test'});
  }
  const important = level.marks.filter(mark => ['core', 'root', 'turn', 'valve', 'lever', 'plate', 'latch', 'item', 'slot', 'song', 'lamp', 'flower'].includes(mark.kind)).map(mark => {
    const point = targetById.get(mark.tile);
    return point ? {...pointObservation(mark.id, point.x, point.y), tile: mark.tile, kind: mark.kind} : {id: mark.id, tile: mark.tile, kind: mark.kind, projected: false};
  });
  const coveredTargets = current.targets.map(target => pointObservation(target.id, target.x, target.y)).filter(target => target.coveredBy.length);
  const offscreenTargets = current.targets.filter(target => !inside([target.x, target.y], viewport)).map(target => target.id);
  const regionOverlaps = [];
  for (let a = 0; a < regions.length; a++) for (let b = a + 1; b < regions.length; b++) {
    const cut = intersection(regions[a].rect, regions[b].rect);
    if (area(cut) > 1) regionOverlaps.push({a: regions[a].name, b: regions[b].name, area: area(cut)});
  }
  return {actors, important, coveredTargets, offscreenTargets, regionOverlaps, projectedTileWidth: 70 * current.scale,
    readabilityWarning: 70 * current.scale < 28 ? 'Projected world tiles are under 28 CSS pixels wide; manual readability review required.' : null};
}

function verify(current, id, width, height, safeCamera) {
  assert.equal(current.snapshot.levelId, id);
  assert.equal(current.safeCamera, safeCamera, 'Reference and opt-in camera modes must remain separate');
  assert.ok(current.scale > 0 && Number.isFinite(current.scale));
  const viewport = [0, 0, width, height];
  const regions = new Map(current.hudRegions.map(region => [region.name, region.rect]));
  assert.ok(regions.has('Heading') && regions.has('JourneyTools'), 'Real HUD geometry is present');
  assert.ok(!regions.has('ModalOverlay'), 'Layout cases must not accidentally remain behind a modal');
  for (const [name, rect] of regions) assert.ok(area(rect) > 0 && within(rect, viewport), `${id} ${name} exceeds ${width}x${height}: ${JSON.stringify(rect)}`);
  assert.ok(!intersects(regions.get('Heading'), regions.get('DirectionPad')), `${id} title overlaps the direction pad at ${width}x${height}`);
  assert.ok(!intersects(regions.get('Heading'), regions.get('NearbyActions')), `${id} title/action text regions overlap at ${width}x${height}`);
  const toolRegion = regions.get('JourneyTools');
  for (const button of current.buttons) {
    assert.ok(Array.isArray(button.visibleRect), 'Fresh QA payload must expose the actual clipped button rectangle');
    assert.ok(area(button.visibleRect) > 0 && within(button.visibleRect, viewport), `${id} visible button exceeds ${width}x${height}: ${button.text}`);
    if (button.action) {
      assert.ok(!button.clipped, `${id} toolbar action is actually clipped: ${button.action}`);
      assert.ok(within(rectOf(button), toolRegion), `${id} visible toolbar action exceeds its paper container: ${button.action}`);
      assert.ok(button.width >= 43 && button.height >= 43, `${id} toolbar action has an undersized hit area: ${button.action}`);
    }
  }
  const result = observations(current, levels.find(level => level.id === id), width, height);
  if (!safeCamera) {
    const controlled = result.actors.find(actor => actor.id === current.snapshot.active);
    assert.ok(controlled?.projected && controlled.insideViewport && controlled.coveredBy.length === 0, `${id} controlled character foot anchor is hidden by HUD at ${width}x${height}: ${JSON.stringify(controlled)}`);
    const actorProtection = [controlled.x - 38 * current.scale, controlled.y - 100 * current.scale, 76 * current.scale, 100 * current.scale];
    for (const region of current.hudRegions) assert.ok(!intersects(actorProtection, region.rect), `${id} controlled character protection area intersects ${region.name} at ${width}x${height}`);
    if (levels.find(level => level.id === id).dual) {
      const companion = result.actors.find(actor => actor.id !== current.snapshot.active);
      assert.ok(companion?.projected && companion.insideViewport && companion.coveredBy.length === 0, `${id} companion foot anchor is hidden by HUD at ${width}x${height}: ${JSON.stringify(companion)}`);
    }
    if (id === '1-1' && width < 650 && height > width) {
      for (const target of result.important.filter(target => ['core', 'root'].includes(target.kind))) {
        assert.ok(target.projected !== false && target.insideViewport && target.coveredBy.length === 0, `First-lesson ${target.id} landing point is covered by HUD at ${width}x${height}`);
      }
      const core = levels.find(level => level.id === id).roots[0];
      for (const [x, z] of core.sockets) {
        const px = current.origin[0] + (x - z) * 35 * current.scale;
        const py = current.origin[1] + ((x + z) * 17.5 - core.h * 48) * current.scale;
        assert.ok(inside([px, py], viewport) && current.hudRegions.every(region => !inside([px, py], region.rect, 0)), `First-lesson growth socket ${x},${z} is covered by HUD at ${width}x${height}`);
      }
    }
  }
  if (safeCamera) {
    assert.ok(area(current.safeRect) > 0 && within(current.safeRect, viewport), 'Safe camera area must exist inside the viewport');
    for (const region of current.hudRegions) assert.ok(!intersects(current.safeRect, region.rect), `${id} safe rectangle intersects ${region.name} at ${width}x${height}`);
    for (const tile of current.targets) {
      // Checking centers alone misses half of a walkable diamond behind a panel.
      const halfWidth = 35 * current.scale, halfHeight = 17.5 * current.scale;
      for (const point of [[tile.x - halfWidth, tile.y], [tile.x + halfWidth, tile.y], [tile.x, tile.y - halfHeight], [tile.x, tile.y + halfHeight]]) {
        assert.ok(inside(point, current.safeRect), `${id} safe-camera tile diamond ${tile.id} exceeds its actual area at ${width}x${height}`);
      }
    }
  }
  return result;
}

const browser = await chromium.launch({channel: 'chrome', headless: true});
const contexts = [];
try {
  for (const mode of modes) {
    assert.ok(['reference', 'safe-camera'].includes(mode), 'Unknown matrix mode');
    const safeCamera = mode === 'safe-camera';
    const context = await browser.newContext({viewport: {width: 1280, height: 720}, deviceScaleFactor: 1});
    contexts.push(context);
    await context.route('**/favicon.ico', route => route.fulfill({status: 204, body: ''}));
    const page = await context.newPage();
    activePage = page;
    bindErrors(page);
    await page.addInitScript(() => {
      window.__contextEvents = [];
      document.addEventListener('DOMContentLoaded', () => {
        for (const type of ['webglcontextlost', 'webglcontextrestored', 'webglcontextcreationerror']) document.querySelector('#canvas')?.addEventListener(type, event => window.__contextEvents.push({type, statusMessage: event.statusMessage, time: performance.now()}));
      });
    });
    const buildResponse = await context.request.get(new URL('/__build.json', base).href);
    assert.ok(buildResponse.ok(), 'Preview must publish its build source fingerprint');
    const build = await buildResponse.json();
    buildSources.push({mode, loadedAt: new Date().toISOString(), build});
    const url = new URL(base); url.searchParams.set('qa', '1');
    url.searchParams.set('safeCamera', safeCamera ? '1' : '0');
    await page.goto(url.href, {waitUntil: 'networkidle'});
    await page.waitForFunction(() => typeof window.__sporelightRequest === 'function' && window.__sporelightState?.targets && window.__sporelightState?.hudRegions && window.__sporelightState?.viewport, {}, {timeout: 120000});
    for (const [width, height] of sizes) {
      activeCase = {mode, id: null, width, height};
      await page.setViewportSize({width, height});
      for (const id of ids) {
        activeCase = {mode, id, width, height};
        const snapshot = fixture.cases.find(entry => entry.name === `authored/${id}`).initial.snapshot;
        await page.evaluate(snapshot => window.__sporelightRequest(JSON.stringify({type: 'snapshot', snapshot, time: 1200})), snapshot);
        const current = await settled(page, snapshot, width, height);
        const record = {...activeCase, sourceFingerprint: build.sourceFingerprint ?? build.source?.sha256 ?? build.source?.fingerprint ?? build.fingerprint ?? null, scale: current.scale, safeRect: current.safeRect, hudRegions: current.hudRegions, buttons: current.buttons.length, clippedButtons: current.buttons.filter(button => button.clipped).length, performance: current.performance};
        // Capture observed occlusion even if a subsequent hard safe-camera check fails.
        record.occlusion = observations(current, levels.find(level => level.id === id), width, height);
        checks.push(record);
        verify(current, id, width, height, safeCamera);
        const screenshot = await page.screenshot();
        record.frame = frameStats(screenshot);
        assert.ok(record.frame.nearBlackFraction < 0.995 && record.frame.transparentFraction < 0.995, `${id} actual rendered frame is near-black or empty at ${width}x${height}: ${JSON.stringify(record.frame)}`);
        assert.deepEqual(errors, [], 'Browser/runtime errors invalidate a layout frame');
        if (id === '1-1' || (id === '1-4' && [1280, 390, 844, 568].includes(width))) {
          const file = `${mode}-${id}-${width}x${height}.png`;
          await writeFile(join(output, file), screenshot); captures.push(file);
        }
      }
    }
    const endingBuild = await (await context.request.get(new URL('/__build.json', base).href)).json();
    assert.ok(equivalent(build, endingBuild), 'Build changed while the matrix page was running');
    await context.close();
  }
  assert.deepEqual(errors, []);
  await writeFile(join(output, 'checks.json'), JSON.stringify({passed: true, buildSources, scope: 'Actual nonempty screenshot pixels, HUD rectangles, visible hit areas, HUD occlusion at logical anchors, safe-camera tile diamonds; no in-world alpha/depth or text-legibility proof', checks, captures, errors, consoleEvents}, null, 2) + '\n');
  console.log(JSON.stringify({passed: true, cases: checks.length, captures: captures.length, errors, output}));
} catch (error) {
  await activePage?.screenshot({path: join(output, 'failure.png')}).catch(() => {});
  await activePage?.locator('#canvas').screenshot({path: join(output, 'failure-canvas.png')}).catch(() => {});
  const state = await activePage?.evaluate(() => structuredClone(window.__sporelightState)).catch(() => null);
  const diagnostic = await glDiagnostic(activePage).catch(() => null);
  await writeFile(join(output, 'failure-state.json'), JSON.stringify({case: activeCase, state, diagnostic}, null, 2));
  await writeFile(join(output, 'checks.json'), JSON.stringify({passed: false, buildSources, failedCase: activeCase, error: String(error), checks, captures, errors, consoleEvents}, null, 2) + '\n');
  console.error(String(error)); process.exitCode = 1;
} finally {
  for (const context of contexts) await context.close().catch(() => {});
  await browser.close();
}

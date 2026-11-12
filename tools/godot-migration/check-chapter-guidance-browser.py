"""Chapter detail art, actual map settings, 1-4 milestones and resident speech.

Map interactions and setting toggles use real input. Fourth-garden milestone
snapshots are explicitly prepared; hold/switch/hint input remains real. No clock
seeking or synthetic effect state. PNGs require independent visual review.
"""
import argparse
import copy
import json
import sys
import time
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base', default='http://localhost:4291/')
parser.add_argument('--output', required=True)
parser.add_argument('--sizes', default='1280x720,844x390')
parser.add_argument('--only', choices=['map', 'fourth', 'all'], default='all')
args = parser.parse_args()
OUT = ROOT / args.output
OUT.mkdir(parents=True, exist_ok=True)


def helpers(filename, delimiter):
    path = ROOT / 'tools/godot-migration' / filename
    namespace = {'__file__': str(path), '__name__': 'chapter_guidance_helpers'}
    saved = sys.argv
    try:
        sys.argv = [str(path), '--base', args.base, '--output', args.output]
        exec(compile(path.read_text(encoding='utf8').split(delimiter)[0], str(path), 'exec'), namespace)
    finally:
        sys.argv = saved
    return namespace


m = helpers('check-map-menu.py', '\nwith sync_playwright() as p:')
h = helpers('check-native-browser.py', '\nwith sync_playwright() as p:')
assert h['build']['webMode'] == 'debug', 'Requires observable debug build'
assert m['build'] == h['build'], 'Build changed while loading helpers'
_map_click = m['click']


def traced_map_click(page, touch=False, **query):
    h['input_trace'].append({'kind': 'map-control', 'query': query, 'input': 'touch' if touch else 'mouse'})
    return _map_click(page, touch, **query)


m['click'] = traced_map_click
report = {'build': h['build'], 'scope': __doc__, 'results': [], 'visualReview': 'pending',
          'limitations': ['Decorative Godot effect clocks are not exported by the existing QA bridge.',
                         'Hidden-page screenshots prove visible behavior, not an invisible effect clock.',
                         'Explicit map set_paused API is covered by CPU; no ordinary UI button exposes it.']}


def visible_text(page):
    return [c.get('text', '') for c in h['fresh'](page)['ui']['controls']
            if c.get('class') == 'Label' and c.get('visibleRect', [0, 0, 0, 0])[3] > 0]


def map_rect(page, rect):
    width, height = page.locator('#canvas').evaluate('c => [c.width,c.height]')
    scale = min(width / 1280, height / 720)
    x, y, w, ht = rect
    return m['css_rect'](page, [(width - 1280 * scale) / 2 + x * scale,
                              (height - 720 * scale) / 2 + y * scale, w * scale, ht * scale])


def pair(page, folder, name, clip=None):
    page.mouse.move(1, 1)
    page.wait_for_timeout(500)
    options = {'scale': 'css'}
    if clip:
        options['clip'] = clip
    a = page.screenshot(path=str(folder / (name + '-a.png')), **options)
    page.wait_for_timeout(1000)
    b = page.screenshot(path=str(folder / (name + '-b.png')), **options)
    return {'identicalPng': a == b, 'gapMs': 1000, 'files': [name + '-a.png', name + '-b.png']}


def setting(page, key, value):
    m['click'](page, action='settings')
    for attempt in range(24):
        state = h['fresh'](page)
        if state['settings'][key] == value:
            break
        candidates = [c for c in state['ui']['controls'] if c.get('setting_id') == key]
        usable = [c for c in candidates if c.get('visibleRect', [0, 0, 0, 0])[3] >= 25]
        if usable:
            h['click_rect'](page, usable[0]['visibleRect'])
            page.wait_for_timeout(180)
            assert h['fresh'](page)['settings'][key] == value, key + ' actual toggle applied'
            break
        scrolls = [c for c in state['ui']['controls'] if c['class'] == 'ScrollContainer'
                   and c.get('visibleRect', [0, 0, 0, 0])[3] > 25]
        assert scrolls, key + ' has reachable settings scroll'
        page.mouse.move(*m['point'](page, scrolls[-1]['visibleRect']))
        page.mouse.wheel(0, -180 if candidates and candidates[0]['y'] < scrolls[-1]['y'] else 180)
        page.wait_for_timeout(100)
    else:
        raise AssertionError('Setting unavailable: ' + key)
    page.keyboard.press('Escape')
    page.wait_for_function("() => window.__sporelightState?.buttons.some(b=>b.path.endsWith('/MapEnterLevel'))")


def run_map(page, folder, row):
    page.goto(args.base.rstrip('/') + '/?qa=1&home=1&unlockAll=0', wait_until='networkidle')
    page.wait_for_function('window.__sporelightState?.snapshot', timeout=120000)
    m['click'](page, action='map')
    snapshot = h['fresh'](page)['snapshot']
    row['details'] = []
    for chapter, prefix in [('valley', '1'), ('pond', '2'), ('cave', '3')]:
        if chapter != 'valley':
            m['select_chapter'](page, chapter)
        for number in range(1, 5):
            level = prefix + '-' + str(number)
            m['click'](page, suffix='/MapMarker_' + level)
            assert m['selected'](page, level), 'Actual selected detail ' + level
            page.mouse.move(1, 1)
            page.wait_for_timeout(300)
            page.screenshot(path=str(folder / (level + '-map.png')), scale='css')
            page.screenshot(path=str(folder / (level + '-detail.png')),
                            clip=map_rect(page, [930, 165, 318, 350]), scale='css')
            row['details'].append({'level': level, 'entryDisabled': m['pick'](page, suffix='/MapEnterLevel')['disabled'],
                                   'labels': visible_text(page), 'input': 'actual original landmark click'})
    assert h['fresh'](page)['snapshot'] == snapshot, 'Selecting twelve details preserves puzzle snapshot'
    m['select_chapter'](page, 'valley')
    m['click'](page, suffix='/MapMarker_1-1')
    setting(page, 'lowMotion', False)
    setting(page, 'particles', True)
    landscape = map_rect(page, [20, 140, 850, 465])
    row['normalMotion'] = pair(page, folder, 'normal-motion', landscape)
    assert not row['normalMotion']['identicalPng'], 'Live map changes actual pixels'
    setting(page, 'lowMotion', True)
    row['reducedMotion'] = pair(page, folder, 'low-motion', landscape)
    assert row['reducedMotion']['identicalPng'], 'Reduced-motion map remains still'
    with_particles = page.screenshot(clip=landscape, scale='css')
    setting(page, 'particles', False)
    row['particlesOff'] = pair(page, folder, 'particles-off', landscape)
    without_particles = page.screenshot(clip=landscape, scale='css')
    row['particleToggleChangesPixels'] = with_particles != without_particles
    assert row['particlesOff']['identicalPng'] and row['particleToggleChangesPixels'], 'Actual particles toggle changes the still map'
    setting(page, 'lowMotion', False)
    row['pathWithoutParticles'] = pair(page, folder, 'path-without-particles', landscape)
    assert not row['pathWithoutParticles']['identicalPng'], 'Path still moves when decorative particles are off'
    setting(page, 'particles', True)
    m['click'](page, action='world_overview')
    row['overview'] = pair(page, folder, 'overview')
    assert row['overview']['identicalPng'], 'Overview freezes actual background pixels'
    page.keyboard.press('Escape')
    assert m['selected'](page, '1-1'), 'Overview returns to original selection'
    row['resumedMotion'] = pair(page, folder, 'resumed-motion', landscape)
    assert not row['resumedMotion']['identicalPng'], 'Closing overview resumes actual map motion'
    m['click'](page, action='settings')
    row['hiddenMapControlsAbsent'] = not any('/IllustratedChapterMap/' in c['path'] for c in m['controls'](page))
    assert row['hiddenMapControlsAbsent'], 'Settings owns the screen while map is hidden'
    row['hiddenPage'] = pair(page, folder, 'settings-page')
    row['hiddenClockVerified'] = False
    page.keyboard.press('Escape')
    assert m['selected'](page, '1-1'), 'Hidden-page return retains original selected level'
    assert h['fresh'](page)['snapshot'] == snapshot, 'Map/settings never mutate puzzle progress'


def wait_speech(page, prefix):
    deadline = time.monotonic() + 18
    while time.monotonic() < deadline:
        lines = [text for text in visible_text(page) if text.startswith('鼹鼠：') and prefix in text]
        if lines:
            return lines[0]
        page.wait_for_timeout(150)
    raise AssertionError('No actual resident dialogue: ' + prefix)


def run_fourth(page, folder, row):
    case = next(c for c in h['cases'] if c['id'] == '1-4')
    page.goto(args.base.rstrip('/') + '/?qa=1', wait_until='networkidle')
    page.wait_for_function('window.__sporelightState?.snapshot', timeout=120000)
    h['prepare'](page, copy.deepcopy(case['initial']))
    row['initialSpeech'] = wait_speech(page, '雨把我的门铃')
    page.screenshot(path=str(folder / 'resident-initial.png'), scale='css')
    h['action'](page, 'use:hold')
    row['holdSpeech'] = wait_speech(page, '你们配合得真好')
    page.screenshot(path=str(folder / 'resident-holding.png'), scale='css')
    before = h['fresh'](page)['snapshot']
    h['find_button'](page, {'action': 'hint'})
    page.wait_for_timeout(400)
    assert not any(text.startswith('鼹鼠：') for text in visible_text(page)), 'Requested hint has priority over resident message'
    page.screenshot(path=str(folder / 'requested-hint-priority.png'), scale='css')
    assert h['fresh'](page)['snapshot'] == before, 'Requested help changes no puzzle state'
    h['find_button'](page, {'action': 'hint'})
    h['action'](page, 'switch')
    page.wait_for_timeout(400)
    assert not any(text.startswith('鼹鼠：') for text in visible_text(page)), 'Distant active partner does not inherit resident proximity'
    page.screenshot(path=str(folder / 'resident-distant-partner.png'), scale='css')
    states = [('initial', case['initial'], 0)]
    action_states = {'use:latch': ('latched', 1), 'take:bell': ('bell', 1), 'use:home': ('home', 2)}
    for index, step in enumerate(case['steps']):
        command = step['command'].get('value')
        if command in action_states:
            name, done = action_states[command]
            states.append((name, step['snapshot'], done))
        if command == 'repair':
            states.append(('at-flower', case['steps'][index - 1]['snapshot'], 3))
    states.append(('completed', case['steps'][-1]['snapshot'], 4))
    row['milestones'] = []
    for name, snapshot, done in states:
        h['prepare'](page, copy.deepcopy(snapshot))
        # A previous requested hint can still be visible: dismiss by real button.
        if any(b.get('action') == 'hint_next' for b in h['fresh'](page)['buttons']):
            h['find_button'](page, {'action': 'hint'})
        text = visible_text(page)
        assert any(('归家旅程  %d / 4' % done) in s or s.startswith('%d/4 · ' % done) for s in text), name + ' correct visible milestone count'
        page.mouse.move(1, 1)
        page.screenshot(path=str(folder / (name + '-stages.png')), scale='css')
        entry = {'name': name, 'done': done, 'source': 'authored snapshot preparation', 'labels': text, 'hints': []}
        if not snapshot.get('completed'):
            h['find_button'](page, {'action': 'hint'})
            for tier in range(3):
                if tier:
                    h['find_button'](page, {'action': 'hint_next'})
                page.wait_for_timeout(150)
                entry['hints'].append(visible_text(page))
                page.mouse.move(1, 1)
                page.screenshot(path=str(folder / (name + '-hint-' + str(tier + 1) + '.png')), scale='css')
            h['find_button'](page, {'action': 'hint'})
        row['milestones'].append(entry)
    row['scopeLimits'] = 'Six original NPC lines/timing remain manual; this script tests actual lost/help/leave plus staged hint screenshots, not a complete route.'


with sync_playwright() as pw:
    browser = pw.chromium.launch(channel='chrome', headless=True)
    for dimensions in args.sizes.split(','):
        width, height = map(int, dimensions.split('x'))
        for kind in (['map', 'fourth'] if args.only == 'all' else [args.only]):
            folder = OUT / dimensions / kind
            folder.mkdir(parents=True, exist_ok=True)
            row = {'size': dimensions, 'kind': kind, 'passed': False, 'errors': []}
            context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=1)
            page = context.new_page()
            page.on('pageerror', lambda e: row['errors'].append(str(e)))
            page.on('console', lambda msg: row['errors'].append(msg.text) if msg.type == 'error' or 'SCRIPT ERROR:' in msg.text else None)
            h['input_trace'].clear()
            try:
                (run_map if kind == 'map' else run_fourth)(page, folder, row)
                assert not row['errors'], row['errors']
                row['passed'] = True
            except Exception as error:
                row.update(reason=str(error), traceback=traceback.format_exc())
                page.screenshot(path=str(folder / 'failure.png'))
            finally:
                row['inputTrace'] = list(h['input_trace'])
                context.close()
            (folder / 'checks.json').write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding='utf8')
            report['results'].append(row)
            print(json.dumps({k: row.get(k) for k in ['size', 'kind', 'passed', 'reason']}, ensure_ascii=False), flush=True)
    browser.close()
report['passed'] = bool(report['results']) and all(row['passed'] for row in report['results'])
(OUT / 'checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
raise SystemExit(0 if report['passed'] else 1)

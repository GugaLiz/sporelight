"""Real-input mechanism frames and per-level projected scale; never a performance test.

QA restores only the authored precondition. No runtime edits, seeking, time freeze,
animation slowdown, or injected action commands. Visual review remains separate.
"""
import argparse
import base64
import json
import math
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright

MOTIONS = [
    ('1-3', 'turn:garden'), ('2-1', 'valve:water'), ('2-4', 'turn:boat'),
    ('3-3', 'turn:water'), ('3-3', 'valve:lift'),
    ('3-4', 'turn:light'), ('3-4', 'turn:inner'), ('3-4', 'valve:lift'),
    ('cloud-1', 'rotate'), ('cloud-2', 'lift'), ('cloud-3', 'rotate'),
]

ARM = """() => {
 window.__motionReview={active:true,started:false,done:false,frames:[],limit:false};
 function observe(){
  const r=window.__motionReview,s=window.__sporelightState,m=s?.motion;
  if(!r.active)return;
  const running=m?.duration>0;
  if(running)r.started=true;
  if(r.started){
   r.frames.push({at:performance.now(),qaSequence:s.qaSequence,
    observedProgress:running?m.elapsed/m.duration:1,finished:!running,
    motion:structuredClone(m),native:structuredClone(s.native),
    character:structuredClone(s.character),origin:s.origin,scale:s.scale,
    png:document.querySelector('#canvas').toDataURL('image/png')});
   if(!running){r.done=true;r.active=false;return;}
   if(r.frames.length>=240){r.limit=true;r.active=false;return;}
  }
  if(r.active)requestAnimationFrame(observe);
 }
 requestAnimationFrame(observe);
}"""


def projected_density(s):
    """Camera-independent measurement from the actual projected tile centres."""
    targets = {t['id']: t for t in s['targets']}
    tiles = [t for t in s['tiles'] if t['id'] in targets and not t.get('solid')]
    pairs = []
    for i, a in enumerate(tiles):
        for b in tiles[i+1:]:
            if a['h'] != b['h'] or abs(a['x']-b['x'])+abs(a['z']-b['z']) != 1:
                continue
            pa, pb = targets[a['id']], targets[b['id']]
            length = math.hypot(pa['x']-pb['x'], pa['y']-pb['y'])
            pairs.append({'tiles': [a['id'], b['id']], 'pixelDistance': length,
                          'pixelsPerWorldUnit': length/math.sqrt(0.625)})
    assert len(pairs) >= 2, 'At least two same-height neighbouring projected tile pairs'
    density = statistics.median(p['pixelsPerWorldUnit'] for p in pairs)
    assert math.isfinite(density) and density > 0, 'Finite positive projected density'
    return {'pixelsPerWorldUnit': density, 'pairs': pairs}


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def save_state(page, h, folder, name):
    s = h['fresh'](page)
    page.screenshot(path=str(folder/(name+'.png')))
    write_json(folder/(name+'.json'), s)
    return s


def transitions(case, command):
    previous = case['initial']
    for step in case['steps']:
        if step['command'] == {'kind': 'act', 'value': command}:
            return previous, step['snapshot']
        previous = step['snapshot']
    raise AssertionError('No authored transition: '+case['id']+' '+command)


def capture_motion(page, h, case, command, folder):
    before, expected = transitions(case, command)
    h['prepare'](page, before)
    page.wait_for_timeout(600)
    s = save_state(page, h, folder, '000-before')
    assert not s['settings']['lowMotion'], 'Normal animation required'
    h['check_contacts'](s, 'mechanism before')
    row = {'command': command, 'before': s, 'expected': expected,
           'visualReview': 'pending', 'samples': [], 'keyframes': []}
    page.evaluate(ARM)
    after = h['action'](page, command)
    page.wait_for_function('() => window.__motionReview.done || window.__motionReview.limit', timeout=15000)
    capture = page.evaluate('() => {window.__motionReview.active=false;return window.__motionReview;}')
    for i, frame in enumerate(capture['frames']):
        name = f'frame-{i:03d}.png'
        (folder/name).write_bytes(base64.b64decode(frame.pop('png').split(',', 1)[1]))
        frame['image'] = name
        row['samples'].append(frame)
    # Save every sampled frame before asserting coverage, including failures.
    write_json(folder/'frames.json', row)
    assert capture['started'] and capture['done'] and not capture['limit'], 'Observed motion and completion'
    moving = [f for f in row['samples'] if not f['finished']]
    assert len(moving) >= 3, 'Missing real intermediate rendered frames'
    row['keyframes'].append({'targetProgress': 0, 'observedProgress': 0, 'image': '000-before.png', 'source': 'pre-input'})
    for target in [0.25, 0.5, 0.75]:
        frame = min(moving, key=lambda f: abs(f['observedProgress']-target))
        delta = abs(frame['observedProgress']-target)
        row['keyframes'].append({'targetProgress': target, 'observedProgress': frame['observedProgress'],
                                 'delta': delta, 'image': frame['image'], 'qaSequence': frame['qaSequence']})
    end = next(f for f in row['samples'] if f['finished'])
    row['keyframes'].append({'targetProgress': 1, 'observedProgress': 1, 'image': end['image'], 'source': 'first observed motion cleared'})
    page.wait_for_timeout(700)
    after = save_state(page, h, folder, '999-settled')
    row['after'] = after
    h['check_contacts'](after, 'mechanism settled')
    # Actor supports can settle through the native follower; compare mechanism
    # and puzzle fields, then inspect native contact separately above.
    for key in ['growth', 'turns', 'water', 'mode', 'flags', 'items', 'collected', 'completed',
                'cloudSeed', 'cloudLatch', 'cloudBuddy']:
        assert after['snapshot'].get(key) == expected.get(key), 'Authored result mismatch: '+key
    write_json(folder/'frames.json', row)
    assert all(k.get('delta', 0) <= 0.15 for k in row['keyframes']), 'Intermediate coverage exceeds 0.15 progress tolerance'
    assert len({k['image'] for k in row['keyframes']}) == 5, 'Keyframes must be distinct actual images'
    row['passed'] = True
    return row


def capture_framing(page, h, case, folder):
    h['prepare'](page, case['initial'])
    s = h['fresh'](page)
    if s['overview']:
        h['find_button'](page, {'text': '跟随'})
    page.wait_for_timeout(900)
    arrival = save_state(page, h, folder, 'arrival')
    assert not arrival['overview'], 'Arrival uses normal framing'
    h['check_contacts'](arrival, 'arrival')
    row = {'arrival': projected_density(arrival), 'visualReview': 'pending'}
    h['find_button'](page, {'text': '全景'})
    page.wait_for_timeout(900)
    overview = save_state(page, h, folder, 'overview')
    assert overview['overview'], 'Real overview control activates overview'
    row['overview'] = projected_density(overview)
    h['find_button'](page, {'text': '跟随'})
    page.wait_for_timeout(900)
    restored = save_state(page, h, folder, 'returned')
    assert not restored['overview'], 'Real overview control returns to normal framing'
    row['returned'] = projected_density(restored)
    row['returnScaleRatio'] = row['returned']['pixelsPerWorldUnit']/row['arrival']['pixelsPerWorldUnit']
    assert abs(row['returnScaleRatio']-1) <= 0.02, 'Normal projection restored after overview'
    assert restored['snapshot'] == arrival['snapshot'], 'Overview preserves puzzle state'
    row['passed'] = True
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--sizes', default='1280x720,844x390')
    parser.add_argument('--mode', choices=['all', 'motion', 'framing'], default='all')
    parser.add_argument('--levels', default='', help='Filter both matrices; framing also includes 1-1 as scale reference')
    parser.add_argument('--motion-levels', default='', help='Optional additional motion-only filter, for focused regressions alongside the framing matrix')
    parser.add_argument('--fail-fast', action='store_true', help='Preserve the first failed job and stop before expanding the matrix')
    args = parser.parse_args()
    out = ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    helper_path = ROOT/'tools/godot-migration/check-native-browser.py'
    source = helper_path.read_text(encoding='utf-8').split('\nwith sync_playwright() as p:')[0]
    saved_argv = sys.argv
    try:
        sys.argv = [str(helper_path), '--base', args.base, '--output', args.output]
        h = {'__file__': str(helper_path), '__name__': 'native_helpers'}
        exec(compile(source, str(helper_path), 'exec'), h)
    finally:
        sys.argv = saved_argv
    selected = set(args.levels.split(',')) if args.levels else set()
    motion_selected = set(args.motion_levels.split(',')) if args.motion_levels else set()
    report = {'build': h['build'], 'results': [], 'visualReview': 'pending',
              'scope': 'Real-input visual QA, no performance claim. QA restores preconditions only. Every rAF image retained. Progress is observed QA state, not an exact GPU timestamp. No freeze, seek or slowdown.'}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome', headless=True)
        for size in args.sizes.split(','):
            width, height = map(int, size.split('x'))
            context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=1)
            page = context.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.on('console', lambda m: errors.append(m.text) if m.type == 'error' or 'SCRIPT ERROR:' in m.text else None)
            page.goto(args.base.rstrip('/')+'/?qa=1', wait_until='domcontentloaded', timeout=300000)
            page.wait_for_function('() => window.__sporelightState?.snapshot', timeout=300000)
            page.wait_for_selector('#status', state='detached', timeout=300000)
            jobs = []
            if args.mode in ['all', 'framing']:
                jobs += [('framing', c['id'], '') for c in h['cases'] if not selected or c['id'] in selected or c['id'] == '1-1']
            if args.mode in ['all', 'motion']:
                jobs += [('motion', level, command) for level, command in MOTIONS
                         if (not selected or level in selected) and (not motion_selected or level in motion_selected)]
            baseline = None
            for kind, level, command in jobs:
                folder = out/size/kind/level
                if command:
                    folder /= command.replace(':', '-')
                folder.mkdir(parents=True, exist_ok=True)
                start_errors = len(errors)
                row = {'kind': kind, 'level': level, 'command': command, 'size': size, 'passed': False}
                try:
                    case = next(c for c in h['cases'] if c['id'] == level)
                    result = capture_motion(page, h, case, command, folder) if kind == 'motion' else capture_framing(page, h, case, folder)
                    row.update(result)
                    if kind == 'framing':
                        if level == '1-1':
                            baseline = row['arrival']['pixelsPerWorldUnit']
                        assert baseline is not None, '1-1 scale reference captured first'
                        row['arrivalRatioToFirstGarden'] = row['arrival']['pixelsPerWorldUnit']/baseline
                        assert abs(row['arrivalRatioToFirstGarden']-1) <= 0.02, 'Arrival projection differs from first garden by over 2%'
                    assert len(errors) == start_errors, 'Browser/Godot errors: '+str(errors[start_errors:])
                except Exception as exc:
                    row.update(passed=False, reason=str(exc))
                    page.evaluate('() => {if(window.__motionReview)window.__motionReview.active=false;}')
                    page.screenshot(path=str(folder/'failure.png'), timeout=120000)
                row['errors'] = errors[start_errors:]
                row['inputTrace'] = list(h['input_trace'])
                h['input_trace'].clear()
                write_json(folder/'checks.json', row)
                report['results'].append(row)
                write_json(out/'checks.json', report)
                print(json.dumps({k: row.get(k) for k in ['kind', 'level', 'command', 'size', 'passed', 'reason']}), flush=True)
                if args.fail_fast and not row['passed']:
                    report['passed'] = False
                    report['stoppedOnFirstFailure'] = True
                    write_json(out/'checks.json', report)
                    context.close()
                    browser.close()
                    return 1
            context.close()
        browser.close()
    report['passed'] = bool(report['results']) and all(r['passed'] for r in report['results'])
    write_json(out/'checks.json', report)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())

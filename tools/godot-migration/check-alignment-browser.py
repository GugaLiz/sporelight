"""Focused visual alignment capture: real turns and stair traversal, no performance claim."""
import argparse
import base64
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright

# Each entry uses the first authored precondition for a real available action.
PROPS = [
    ('1-2', 'grow:root:down'), ('1-4', 'use:hold'), ('1-4', 'use:latch'),
    ('2-1', 'valve:water'), ('2-2', 'angle:mirrorA'), ('2-3', 'beat'),
    ('2-4', 'turn:boat'), ('2-4', 'use:invite'), ('3-1', 'take:lamp'),
    ('3-2', 'valve:mode'), ('3-2', 'freeze'), ('3-3', 'turn:water'),
    ('3-3', 'valve:lift'), ('3-4', 'turn:light'), ('3-4', 'turn:inner'),
    ('3-4', 'valve:water'), ('3-4', 'valve:lift'),
    ('cloud-1', 'rotate'), ('cloud-2', 'lift'), ('cloud-3', 'rotate'),
]

GARDEN_EDGES = {
    0: set(),
    1: {frozenset(['m:garden:-2:0', 'f:0:-3'])},
    2: {frozenset(['m:garden:0:2', 'f:0:-3']), frozenset(['m:garden:-2:0', 'f:3:0'])},
    3: {frozenset(['m:garden:0:2', 'f:3:0'])},
}

ARM_WALK = """() => {
 window.__alignmentWalk={active:true,frames:[],limit:false};
 function sample(){
  const r=window.__alignmentWalk,s=window.__sporelightState;
  if(!r.active)return;
  r.frames.push({qaSequence:s.qaSequence,native:structuredClone(s.native),character:structuredClone(s.character),snapshot:structuredClone(s.snapshot),
   png:document.querySelector('#canvas').toDataURL('image/png')});
  if(r.frames.length>=240){r.limit=true;r.active=false;return;}
  requestAnimationFrame(sample);
 }
 requestAnimationFrame(sample);
}"""


def slope_walk(page, h, folder, key, target_z, direction):
    page.evaluate(ARM_WALK)
    page.keyboard.down(key)
    try:
        page.wait_for_function("v => {const z=window.__sporelightState.native.actors.luvie.position[2]; return v.direction<0?z<=v.z+0.04:z>=v.z-0.04;}",
                               arg={'z': target_z, 'direction': direction}, timeout=7000)
    finally:
        page.keyboard.up(key)
    frames = page.evaluate('() => {window.__alignmentWalk.active=false; return window.__alignmentWalk;}')
    h['input_trace'].append({'kind': 'bounded-stair-walk', 'key': key, 'targetZ': target_z})
    folder.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(frames['frames']):
        frame['image'] = f'frame-{i:03d}.png'
        (folder / frame['image']).write_bytes(base64.b64decode(frame.pop('png').split(',', 1)[1]))
    write(folder / 'frames.json', frames)
    assert not frames['limit'], 'Bounded stair walk exceeded frame budget'
    intermediate = [f for f in frames['frames'] if 0.04 < f['character']['luvie']['contact']['supportHeight'] < 0.61]
    assert intermediate, 'Actual intermediate tread must be observed'
    for frame in frames['frames']:
        h['check_contacts'](frame, 'stair traversal frame')
    frames['keyframes'] = []
    for height in [0.1625, 0.325, 0.4875]:
        frame = min(intermediate, key=lambda f: abs(f['character']['luvie']['contact']['supportHeight']-height))
        frames['keyframes'].append({'targetHeight': height, 'observedHeight': frame['character']['luvie']['contact']['supportHeight'], 'image': frame['image']})
    frames['passed'] = True
    write(folder / 'frames.json', frames)
    return h['stable'](page)


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def tread_stops(page, h, folder, low, high, ascending):
    """Real held inputs, then stationary samples on four independently known treads."""
    folder.mkdir(parents=True, exist_ok=True)
    axis = 0 if low['x'] != high['x'] else 2
    origin = low['x'] if axis == 0 else low['z']
    sign = (high['x'] - low['x']) if axis == 0 else (high['z'] - low['z'])
    travel = sign if ascending else -sign
    key = ('ArrowRight' if travel > 0 else 'ArrowLeft') if axis == 0 else ('ArrowDown' if travel > 0 else 'ArrowUp')
    records = []
    for step in (range(4) if ascending else reversed(range(4))):
        distance = 0.275 + (step + 0.5) * 0.15
        target = origin + sign * distance
        h['input_trace'].append({'kind': 'stationary-tread', 'key': key, 'axis': axis, 'target': target, 'step': step})
        # A continuous hold can overshoot a .15 tread while the QA bridge
        # publishes its next snapshot. Short real presses settle between reads.
        state = h['stable'](page)
        for attempt in range(32):
            position = state['native']['actors']['luvie']['position'][axis]
            if abs(position - target) < 0.04:
                break
            direction = 1 if target > position else -1
            pulse = ('ArrowRight' if direction > 0 else 'ArrowLeft') if axis == 0 else ('ArrowDown' if direction > 0 else 'ArrowUp')
            page.keyboard.press(pulse, delay=8)
            h['input_trace'].append({'kind': 'tread-position-pulse', 'key': pulse, 'holdMs': 8, 'attempt': attempt})
            state = h['stable'](page)
        else:
            raise AssertionError(f'Step {step}: bounded real presses could not settle on tread')
        actor = state['native']['actors']['luvie']
        actual_distance = (actor['position'][axis] - origin) * sign
        expected = low['h'] * 0.65 + (step + 1) * 0.1625
        # Assert the sample really stopped within this tread, not the landing.
        assert 0.275 + step * 0.15 < actual_distance < 0.275 + (step + 1) * 0.15, f'Step {step}: missed stationary tread: {actual_distance}'
        assert abs(actor['floorHeight'] - expected) < 0.0001, f'Step {step}: actual support is not the expected horizontal tread'
        contact = state['character']['luvie']['contact']
        assert abs(contact['supportHeight'] - expected) < 0.0001, 'Visible sole must sample the independently expected tread'
        assert abs(contact['visualHeight'] - expected) < 0.001, 'Stopped visible sole must sit exactly on the tread'
        h['check_contacts'](state, f'stopped tread {step}')
        page.screenshot(path=str(folder / f'step-{step}.png'))
        write(folder / f'step-{step}.json', state)
        page.wait_for_timeout(160)
        later = h['fresh'](page)
        after = later['native']['actors']['luvie']
        assert max(abs(a-b) for a,b in zip(actor['position'], after['position'])) < 0.01, 'Stopped tread must not slide or recenter'
        assert abs(after['floorHeight'] - expected) < 0.0001, 'Stationary support changed'
        records.append({'step': step, 'supportHeight': expected, 'distance': actual_distance,
                        'bodyCentreGapDiagnostic': actor['position'][1] - actor['floorHeight'],
                        'visibleSoleError': contact['visualHeight'] - expected})
    h['move_to'](page, high['id'] if ascending else low['id'])
    write(folder / 'checks.json', {'passed': True, 'ascending': ascending, 'stops': records})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--sizes', default='1280x720,844x390')
    parser.add_argument('--mode', choices=['all', 'stairs', 'props', 'focus', 'treads'], default='all')
    parser.add_argument('--levels', default='')
    args = parser.parse_args()
    out = ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    helper = ROOT / 'tools/godot-migration/check-native-browser.py'
    source = helper.read_text(encoding='utf-8').split('\nwith sync_playwright() as p:')[0]
    old = sys.argv
    try:
        sys.argv = [str(helper), '--base', args.base, '--output', args.output]
        h = {'__file__': str(helper), '__name__': 'alignment_helpers'}
        exec(compile(source, str(helper), 'exec'), h)
    finally:
        sys.argv = old
    cases = {c['id']: c for c in h['cases']}
    selected = set(args.levels.split(',')) if args.levels else set()
    report = {'build': h['build'], 'results': [], 'visualReview': 'pending',
              'scope': 'Full-frame screenshots and real-input traversal. Automatic pass is not visual acceptance.'}

    def save(page, folder, name):
        state = h['fresh'](page)
        page.screenshot(path=str(folder / (name + '.png')))
        write(folder / (name + '.json'), state)
        h['check_contacts'](state, name)
        return state

    def precondition(level, command):
        previous = cases[level]['initial']
        for step in cases[level]['steps']:
            if step['command'] == {'kind': 'act', 'value': command}:
                return previous, step['snapshot']
            previous = step['snapshot']
        raise AssertionError('Missing authored action ' + level + ' ' + command)

    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome', headless=True)
        for size in args.sizes.split(','):
            width, height = map(int, size.split('x'))
            context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=1)
            page = context.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.on('console', lambda m: errors.append(m.text) if m.type == 'error' or 'SCRIPT ERROR:' in m.text else None)
            page.goto(args.base.rstrip('/') + '/?qa=1', wait_until='domcontentloaded', timeout=300000)
            page.wait_for_function('() => window.__sporelightState?.snapshot', timeout=300000)
            jobs = [('baseline', '1-1', ''), ('baseline', '1-2', '')]
            if args.mode == 'focus':
                jobs += [('focus', '1-3', '')]
            if args.mode in ['all', 'stairs', 'treads'] and (not selected or '1-3' in selected):
                jobs += [('stairs', '1-3', '')]
            if args.mode in ['all', 'stairs'] and (not selected or 'cloud-1' in selected):
                jobs += [('cloud-stairs', 'cloud-1', '')]
            if args.mode in ['all', 'props']:
                jobs += [('props', level, cmd) for level, cmd in PROPS if not selected or level in selected]
            for kind, level, command in jobs:
                folder = out / size / kind / level / (command.replace(':', '-') or 'states')
                folder.mkdir(parents=True, exist_ok=True)
                start = len(errors)
                h['input_trace'].clear()
                row = {'kind': kind, 'level': level, 'command': command, 'size': size, 'passed': False}
                try:
                    if kind == 'baseline':
                        h['prepare'](page, cases[level]['initial'])
                        page.wait_for_timeout(900)
                        save(page, folder, 'arrival')
                    elif kind == 'focus':
                        before, _ = precondition(level, 'turn:garden')
                        h['prepare'](page, before)
                        h['find_button'](page, {'action': 'primary'})
                        h['stable'](page)
                        assert h['fresh'](page)['snapshot']['turns']['garden'] == 1, 'Primary button performs the real rotation'
                        page.keyboard.down('ArrowLeft')
                        page.wait_for_timeout(150)
                        page.keyboard.up('ArrowLeft')
                        h['input_trace'].append({'kind': 'showcase-side-step', 'key': 'ArrowLeft', 'holdMs': 150})
                        page.wait_for_timeout(900)
                        s = save(page, folder, 'side-step')
                        assert s['context'].get('id') == 'turn:garden', 'Showcase keeps mechanism selected'
                        row['actorPosition'] = s['native']['actors']['luvie']['position']
                        h['move_to'](page, 'm:garden:-2:0')
                        save(page, folder, 'slope-low')
                        up = slope_walk(page, h, folder / 'up', 'ArrowUp', -3, -1)
                        assert up['snapshot']['actors']['luvie'] == 'f:0:-3'
                        save(page, folder, 'slope-high')
                        down = slope_walk(page, h, folder / 'down', 'ArrowDown', -2, 1)
                        assert down['snapshot']['actors']['luvie'] == 'm:garden:-2:0'
                        save(page, folder, 'slope-returned')
                    elif kind == 'cloud-stairs':
                        h['prepare'](page, cases[level]['initial'])
                        page.wait_for_timeout(900)
                        save(page, folder, 'arrival')
                        for name, tile in [('low', 'stair:3:5'), ('high', 'stair:3:4'), ('returned', 'stair:3:5')]:
                            h['move_to'](page, tile)
                            s = save(page, folder, name)
                            assert s['snapshot']['actors']['luvie'] == tile
                        row['upAndDown'] = True
                    elif kind == 'props':
                        before, expected = precondition(level, command)
                        h['prepare'](page, before)
                        page.wait_for_timeout(900)
                        save(page, folder, 'before')
                        h['action'](page, command)
                        page.wait_for_timeout(900)
                        after = save(page, folder, 'after')
                        for key in ['growth', 'turns', 'water', 'mode', 'flags', 'items', 'collected', 'completed', 'cloudSeed', 'cloudLatch', 'cloudBuddy']:
                            assert after['snapshot'].get(key) == expected.get(key), 'Authored state mismatch: ' + key
                    else:
                        before, _ = precondition(level, 'turn:garden')
                        h['prepare'](page, before)
                        row['orientations'] = []
                        for orientation in range(4):
                            page.wait_for_timeout(900)
                            s = save(page, folder, f'turn-{orientation}-settled')
                            assert s['snapshot']['turns']['garden'] == orientation
                            h['find_button'](page, {'text': '全景'})
                            page.wait_for_timeout(900)
                            save(page, folder, f'turn-{orientation}-overview')
                            h['find_button'](page, {'text': '跟随'})
                            tiles = s['tiles']
                            edges = [(a, b) for a in tiles for b in tiles
                                     if b['h'] - a['h'] == 1
                                     and abs(a['x']-b['x']) + abs(a['z']-b['z']) == 1
                                     and not a.get('solid') and not b.get('solid')]
                            assert {frozenset([a['id'], b['id']]) for a, b in edges} == GARDEN_EDGES[orientation], 'Stair topology differs from authored four-way garden'
                            paths = []
                            for index, (low, high) in enumerate(edges):
                                h['move_to'](page, low['id'])
                                save(page, folder, f'turn-{orientation}-edge-{index}-low')
                                if args.mode == 'treads':
                                    tread_stops(page, h, folder / f'turn-{orientation}-edge-{index}-up', low, high, True)
                                else:
                                    h['move_to'](page, high['id'])
                                up = save(page, folder, f'turn-{orientation}-edge-{index}-high')
                                assert up['snapshot']['actors']['luvie'] == high['id']
                                if args.mode == 'treads':
                                    tread_stops(page, h, folder / f'turn-{orientation}-edge-{index}-down', low, high, False)
                                else:
                                    h['move_to'](page, low['id'])
                                down = save(page, folder, f'turn-{orientation}-edge-{index}-returned')
                                assert down['snapshot']['actors']['luvie'] == low['id']
                                assert down['snapshot']['turns']['garden'] == orientation
                                paths.append({'low': low['id'], 'high': high['id'], 'upAndDown': True})
                            row['orientations'].append({'orientation': orientation, 'crossings': paths})
                            h['move_to'](page, 'm:garden:0:0')
                            h['action'](page, 'turn:garden')
                        assert h['fresh'](page)['snapshot']['turns']['garden'] == 0
                    assert len(errors) == start, 'Browser/Godot errors: ' + str(errors[start:])
                    row['passed'] = True
                except Exception as exc:
                    row['reason'] = str(exc)
                    page.screenshot(path=str(folder / 'failure.png'))
                row['errors'] = errors[start:]
                row['inputTrace'] = list(h['input_trace'])
                write(folder / 'checks.json', row)
                report['results'].append(row)
                report['passed'] = all(r['passed'] for r in report['results'])
                write(out / 'checks.json', report)
                print(json.dumps({k: row.get(k) for k in ['kind', 'level', 'command', 'size', 'passed', 'reason']}), flush=True)
                if not row['passed']:
                    context.close()
                    browser.close()
                    return 1
            context.close()
        browser.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())

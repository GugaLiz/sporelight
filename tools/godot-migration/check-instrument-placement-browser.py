"""Real operation poses: four carried turns and the day/night control.

QA prepares authored preconditions; extended light also seats both passengers
on its unchanged logical centre for a deliberate overlap check. All operations are real
keyboard/control input. Images require independent review; no timing claim.
"""
import argparse
import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--base', required=True)
p.add_argument('--output', required=True)
p.add_argument('--extended', action='store_true', help='Also operate 3-3 water and lift, and 3-4 light controls.')
args = p.parse_args()
out = ROOT/args.output
out.mkdir(parents=True, exist_ok=True)
helper = ROOT/'tools/godot-migration/check-native-browser.py'
saved = sys.argv
sys.argv = [str(helper), '--base', args.base, '--output', args.output]
h = {'__file__': str(helper), '__name__': 'instrument_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0], str(helper), 'exec'), h)
sys.argv = saved
if h['build'].get('webMode') != 'debug':
    raise RuntimeError('QA capture requires a debug Web build; release has no QA state bridge. Use ordinary-input checks for release.')
report = {'build': h['build'], 'scope': __doc__, 'results': [], 'visualReview': 'pending'}
with sync_playwright() as pw:
    browser = pw.chromium.launch(channel='chrome', headless=True)
    for width, height in [(1280, 720), (844, 390)]:
        size = f'{width}x{height}'
        context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('console', lambda m: errors.append(m.text) if m.type == 'error' or 'SCRIPT ERROR:' in m.text else None)
        page.goto(args.base+'?qa=1', wait_until='networkidle', timeout=120000)
        page.wait_for_function('window.__sporelightState?.snapshot', timeout=120000)
        cases = [('1-3', 'turn:garden', 4), ('3-2', 'valve:mode', 2)]
        if args.extended:
            cases += [('3-3', 'turn:water', 4), ('3-3', 'valve:lift', 2), ('3-4', 'turn:light', 4)]
        for level, command, count in cases:
            case = next(c for c in h['cases'] if c['id'] == level)
            before = copy.deepcopy(case['initial'])
            for step in case['steps']:
                if step['command'] == {'kind': 'act', 'value': command}:
                    break
                before = copy.deepcopy(step['snapshot'])
            if args.extended and level == '3-4':
                before['actors']['buddy'] = before['actors']['luvie']
                before['follow'] = False
                before.pop('runtime', None)
            folder = out/size/level
            if level in ['3-3', '3-4']:
                folder = folder/command.replace(':', '-')
            folder.mkdir(parents=True, exist_ok=True)
            row = {'level': level, 'size': size, 'command': command, 'passed': False, 'states': []}
            row['preparedBothPassengers'] = args.extended and level == '3-4'
            start_errors = len(errors)
            h['input_trace'].clear()
            try:
                h['prepare'](page, before)
                for index in range(count+1):
                    if index:
                        h['action'](page, command)
                    page.wait_for_timeout(700)
                    s = h['fresh'](page)
                    h['check_contacts'](s, f'{level} operation {index}')
                    assert not s['moving'], 'operation settled'
                    if level == '3-2':
                        assert s['snapshot']['mode'] == (before['mode']+index) % 2
                    else:
                        module = command.split(':')[1]
                        period = 2 if command == 'valve:lift' else 4
                        assert s['snapshot']['turns'][module] == (before['turns'].get(module, 0)+index) % period
                    page.mouse.move(1, 1)
                    name = f'{index:02d}-operation.png'
                    page.screenshot(path=str(folder/name))
                    row['states'].append({'image': name, 'state': s})
                assert not errors[start_errors:], errors[start_errors:]
                row['passed'] = True
            except Exception as error:
                row['reason'] = str(error)
                page.screenshot(path=str(folder/'failure.png'))
            row.update(errors=errors[start_errors:], inputTrace=list(h['input_trace']))
            (folder/'checks.json').write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding='utf8')
            report['results'].append(row)
            print(json.dumps({k: row.get(k) for k in ['level', 'size', 'passed', 'reason']}), flush=True)
        context.close()
    browser.close()
report['passed'] = all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
sys.exit(0 if report['passed'] else 1)

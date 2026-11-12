"""Exact full-frame comparison of verification-only release engine fixtures.

Both exports must use byte-identical PCKs. Settings change only inside isolated
browser profiles: lowMotion=true, particles=false; lights/materials/MSAA remain.
Self-comparison detects animation/camera noise; no masks or tolerances are used.
Restored states cover visual output, not real-input gameplay or motion timing.
"""
import argparse
import hashlib
import importlib.util
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from PIL import Image, ImageChops, ImageStat
from playwright.sync_api import sync_playwright


def get(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def difference(first, second, output):
    a, b = Image.open(first).convert('RGB'), Image.open(second).convert('RGB')
    assert a.size == b.size, 'Image dimensions differ'
    diff = ImageChops.difference(a, b)
    channel = ImageChops.lighter(ImageChops.lighter(*diff.split()[:2]), diff.split()[2])
    histogram = channel.histogram()
    changed = sum(histogram[1:])
    row = {'exact': changed == 0, 'changedPixels': changed, 'totalPixels': a.width*a.height,
           'maxChannelDifference': max(e[1] for e in diff.getextrema()),
           'meanAbsoluteChannelDifference': ImageStat.Stat(diff).mean, 'bbox': diff.getbbox()}
    if changed:
        diff.point(lambda x: min(255, x*8)).save(output)
        row['differenceImage'] = str(output)
    return row


def read(page):
    return page.evaluate('() => structuredClone(window.__sporelightState)')


def click_visible(page, predicate):
    for unused in range(40):
        controls = read(page)['ui']['controls']
        candidate = next((c for c in controls if predicate(c) and not c.get('disabled')
                          and c.get('visibleRect', [0,0,0,0])[2] > 12 and c['visibleRect'][3] > 12), None)
        if candidate:
            x, y, w, h = candidate['visibleRect']
            page.mouse.click(x+w/2, y+h/2)
            page.wait_for_timeout(180)
            return
        page.mouse.move(page.viewport_size['width']/2, page.viewport_size['height']/2)
        page.mouse.wheel(0, 180)
        page.wait_for_timeout(150)
    raise AssertionError('Visible requested settings/menu control not found')


def deterministic_settings(page):
    page.keyboard.press('Escape')
    page.wait_for_timeout(250)
    if not any(c.get('setting_id') == 'lowMotion' for c in read(page)['ui']['controls']):
        click_visible(page, lambda c: c.get('action') == 'settings')
    for key, target in [('lowMotion', True), ('particles', False)]:
        if read(page)['settings'].get(key) != target:
            click_visible(page, lambda c: c.get('setting_id') == key)
            page.wait_for_function('p => window.__sporelightState.settings[p.key]===p.value',
                                   arg={'key':key, 'value':target}, timeout=30000)
    settings = read(page)['settings']
    assert settings.get('dynamicLight', True), 'Lighting must remain enabled'
    assert settings.get('quality', 'standard') == 'standard', 'Do not lower rendering quality'
    return settings


def restore(page, snapshot):
    before = read(page)['qaSequence']
    page.evaluate('s => window.__sporelightRequest(JSON.stringify({type:"snapshot",snapshot:s,time:1200,hideHud:true,freezePhysics:true}))', snapshot)
    page.wait_for_function('p => {const s=window.__sporelightState;return s?.qaSequence>p.seq+3 && s.snapshot.levelId===p.id && !s.moving && !s.homeActive;}',
                           arg={'seq':before, 'id':snapshot['levelId']}, timeout=90000)
    page.wait_for_timeout(300)
    s = read(page)
    assert s['worldVisible'] and not s['ui']['modalOpen'], 'World must be unobscured'
    for key, value in snapshot.items():
        assert s['snapshot'].get(key) == value, 'Fixture differs in '+key
    for actor in s['native']['actors'].values():
        assert abs(actor['position'][1]-actor['floorHeight']) < .16, 'Actor support mismatch'
    return s


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--official', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--sizes', default='1280x720')
    parser.add_argument('--levels', default='')
    parser.add_argument('--states', default='arrival,mechanism,before-completion,restored-completion')
    parser.add_argument('--fixture-manifest', default='docs/qa-godot-native/full-performance/template-visual/fixture.json')
    args = parser.parse_args()
    out = ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    metadata = {label: json.loads(get(base.rstrip('/')+'/__build.json')) for label,base in [('official',args.official),('candidate',args.candidate)]}
    fixture = json.loads((ROOT/args.fixture_manifest).read_text(encoding='utf-8'))
    assert metadata['official']['template']['kind'] == 'official', 'Official endpoint must use official template'
    assert metadata['candidate']['template']['kind'] == 'scene-demand', 'Candidate endpoint must use the optimized template'
    assert metadata['candidate']['template']['customTemplateSha256'] == fixture['templateSha256'], 'Candidate template does not match fixture provenance'
    for label, base in [('official',args.official),('candidate',args.candidate)]:
        m = metadata[label]
        assert m['verificationOnly'] and m['webMode'] == 'release', 'Require non-delivery release fixture'
        assert m['pckSha256'] == fixture['pckSha256'] == sha(get(base.rstrip('/')+'/index.pck')), 'PCK identity failed'
    assert metadata['official']['originalMainSha256'] == metadata['candidate']['originalMainSha256']
    assert metadata['official']['fixtureMainSha256'] == metadata['candidate']['fixtureMainSha256']
    original = (ROOT/'godot/application/main.gd').read_bytes().decode('utf-8')
    assert sha(original.encode()) == metadata['official']['originalMainSha256'], 'Runtime main changed after fixture export'
    assert original.count(' and OS.is_debug_build()') == 1 and original.count(' or not OS.is_debug_build()') == 2
    changed = original.replace(' and OS.is_debug_build()', '').replace(' or not OS.is_debug_build()', '')
    line_ending = '\r\n' if '\r\n' in changed else '\n'
    anchor = '\t\t\t_sync_hud()' + line_ending + '\t\t"action":'
    assert changed.count(anchor) == 1
    freeze = ('\t\t\t_sync_hud()' + line_ending +
              '\t\t\tif bool(request.get("freezePhysics", false)) and native_movement != null:' + line_ending +
              '\t\t\t\tnative_movement.suspended = true' + line_ending +
              '\t\t\t\tview.reset_camera()' + line_ending + '\t\t"action":')
    changed = changed.replace(anchor, freeze)
    assert sha(changed.encode()) == metadata['official']['fixtureMainSha256'], 'Unexpected fixture main edits'
    actual_files = {str(path.relative_to(ROOT/'godot')).replace('\\','/') for path in (ROOT/'godot').rglob('*')
                    if path.is_file() and not any(part in ['.godot','build','tests'] for part in path.relative_to(ROOT/'godot').parts)}
    assert actual_files == set(fixture['runtimeFiles']), 'Runtime file set changed after fixture export'
    for relative, expected in fixture['runtimeFiles'].items():
        assert sha((ROOT/'godot'/relative).read_bytes()) == expected, 'Runtime changed: '+relative
    spec = importlib.util.spec_from_file_location('level_states', ROOT/'tools/godot-migration/check-level-acceptance.py')
    states_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(states_module)
    selected = set(args.levels.split(',')) if args.levels else None
    wanted = set(args.states.split(','))
    samples = [(case['id'], name, snapshot, origin) for case in states_module.cases()
               if selected is None or case['id'] in selected
               for name,snapshot,origin in states_module.review_states(case) if name in wanted]
    assert samples, 'No requested states'
    report = {'metadata':metadata, 'pckSha256':fixture['pckSha256'], 'samples':[], 'errors':[],
              'scope':__doc__, 'fixtureOnlySettings':{'lowMotion':True,'particles':False,'hideHud':True,'visualTimeMs':1200,'freezePhysics':True},
              'guardAudit':'Current runtime matches exported manifest; fixture main is exactly three QA guards removed plus opt-in snapshot movement suspension/camera reset; PCK bytes independently hashed and identical.'}
    captured = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome', headless=True)
        try:
            for label, base in [('official',args.official),('candidate',args.candidate)]:
                for size in args.sizes.split(','):
                    width,height = map(int,size.split('x'))
                    context = browser.new_context(viewport={'width':width,'height':height}, device_scale_factor=1)
                    page = context.new_page()
                    page.on('pageerror', lambda e:report['errors'].append(str(e)))
                    page.on('console', lambda m:report['errors'].append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
                    page.goto(base.rstrip('/')+'/?qa=1', wait_until='domcontentloaded', timeout=300000)
                    page.wait_for_function('() => window.__sporelightState?.snapshot', timeout=300000)
                    page.wait_for_selector('#status', state='detached', timeout=300000)
                    settings = deterministic_settings(page)
                    page.mouse.move(1,1)
                    for level,name,snapshot,origin in samples:
                        folder = out/size/level
                        folder.mkdir(parents=True, exist_ok=True)
                        state = restore(page,snapshot)
                        paths = [folder/(name+'-'+label+'-'+suffix+'.png') for suffix in ['a','b']]
                        page.screenshot(path=str(paths[0]))
                        page.wait_for_timeout(250)
                        page.screenshot(path=str(paths[1]))
                        after_state = read(page)
                        self_diff = difference(*paths, folder/(name+'-'+label+'-self-diff.png'))
                        captured[(size,level,name,label)] = {'images':[str(path.relative_to(out)) for path in paths],
                            'selfDifference':self_diff, 'snapshot':state['snapshot'], 'native':state['native'], 'settings':settings,
                            'renderStateA':{key:state.get(key) for key in ['native','character','origin','scale']},
                            'renderStateB':{key:after_state.get(key) for key in ['native','character','origin','scale']}}
                        print(json.dumps({'template':label,'size':size,'level':level,'state':name,'selfExact':self_diff['exact']}),flush=True)
                    context.close()
        except Exception as error:
            report['failure'] = str(error)
            try:
                report['failureState'] = read(page)
                page.screenshot(path=str(out/'failure.png'))
            except Exception as capture_error:
                report['failureCaptureError'] = str(capture_error)
        finally:
            browser.close()
    for size in args.sizes.split(','):
        for level,name,snapshot,origin in samples:
            a = captured.get((size,level,name,'official'))
            b = captured.get((size,level,name,'candidate'))
            row = {'size':size,'level':level,'state':name,'origin':origin,'official':a,'candidate':b,'passed':False}
            if a and b:
                diff = difference(out/a['images'][0], out/b['images'][0], out/size/level/(name+'-engine-diff.png'))
                row['engineDifference'] = diff
                row['passed'] = a['selfDifference']['exact'] and b['selfDifference']['exact'] and diff['exact']
            report['samples'].append(row)
    report['passed'] = bool(report['samples']) and all(r['passed'] for r in report['samples']) and not report['errors'] and not report.get('failure')
    (out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())

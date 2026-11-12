"""Authored preconditions via QA, real prop actions/undo, images for review."""
import argparse, copy, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--sizes', default='1280x720,844x390')
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)
helper = ROOT / 'tools/godot-migration/check-native-browser.py'
saved_argv = sys.argv
sys.argv = [str(helper), '--base', args.base, '--output', args.output]
h = {'__file__': str(helper), '__name__': 'element_scale_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0], str(helper), 'exec'), h)
sys.argv = saved_argv
scenarios = [('1-4', 'take:bell'), ('2-1', 'take:dew'), ('2-2', 'take:mirrorB'),
 ('2-2', 'drop:mirrorB:f:1:0'), ('2-4', 'use:plant'), ('2-4', 'use:invite'),
 ('3-1', 'take:lamp'), ('3-2', 'take:sunPost'), ('3-2', 'drop:moonPost:f:3:-1'),
 ('3-3', 'use:care'), ('3-4', 'take:mirror'), ('cloud-1', 'seed')]
report = {'build': h['build'], 'scope': 'QA preconditions; real action/undo; images require review.', 'results': []}
def assert_puzzle(actual, expected):
 for key in ['growth','turns','flags','items','water','mode','frozen','song','beat','cloudSeed','cloudLatch']:
  if key in expected: assert actual['snapshot'].get(key) == expected[key], key+' differs after actual input'
with sync_playwright() as p:
 browser = p.chromium.launch(channel='chrome', headless=True)
 for size in args.sizes.split(','):
  width, height = map(int, size.split('x'))
  context = browser.new_context(viewport={'width':width,'height':height}, has_touch=width<1000)
  page = context.new_page(); errors=[]
  page.on('pageerror', lambda e: errors.append(str(e)))
  page.on('console', lambda m: errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  page.goto(args.base+'?qa=1', wait_until='networkidle', timeout=120000)
  page.wait_for_function('window.__sporelightState?.snapshot', timeout=120000)
  h['args'].touch = width<1000
  for level, command in scenarios:
   folder = out/size/(level+'-'+command.replace(':','-')); folder.mkdir(parents=True,exist_ok=True)
   row={'level':level,'command':command,'size':[width,height],'passed':False}
   h['input_trace'].clear(); error_start=len(errors)
   try:
    case=next(c for c in h['cases'] if c['id']==level); before=case['initial']
    for step in case['steps']:
     if step['command']=={'kind':'act','value':command}: after=step['snapshot']; break
     before=step['snapshot']
    else: raise AssertionError('Missing authored transition')
    h['prepare'](page,before); page.mouse.move(1,1)
    page.screenshot(path=str(folder/'before.png'))
    s=h['action'](page,command); h['check_contacts'](s,command); assert_puzzle(s,after)
    page.screenshot(path=str(folder/'after.png')); row['after']=s
    if width<1000: h['find_button'](page,{'action':'undo'},True)
    else: page.keyboard.press('z'); h['input_trace'].append({'kind':'key','key':'z'})
    s=h['stable'](page,level); assert_puzzle(s,before); h['check_contacts'](s,'undo '+command)
    page.screenshot(path=str(folder/'undo.png'))
    assert len(errors)==error_start,errors[error_start:]
    row.update(passed=True,undo=s)
   except Exception as e:
    row.update(reason=str(e),actual=h['state'](page)); page.screenshot(path=str(folder/'failure.png'))
   row.update(inputTrace=list(h['input_trace']),errors=errors[error_start:])
   (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
   report['results'].append(row)
   print(json.dumps({k:row.get(k) for k in ['level','command','size','passed','reason']},ensure_ascii=False),flush=True)
  # Separate visibility evidence: seed the reference end state, then physically
  # step off the core. This is not evidence of completing the whole puzzle.
  for case in h['cases']:
   level=case['id']; folder=out/size/(level+'-core-clear'); folder.mkdir(parents=True,exist_ok=True)
   row={'level':level,'command':'core-clear','size':[width,height],'passed':False}
   h['input_trace'].clear(); error_start=len(errors)
   try:
    view_snapshot=copy.deepcopy(case['steps'][-1]['snapshot'])
    # Completed worlds intentionally lock movement. Only this visual setup
    # reopens the end-state scene; the action/undo cases above stay unmodified.
    view_snapshot['completed']=False
    s=h['prepare'](page,view_snapshot)
    actor=s['snapshot']['active']; at=next(t for t in s['tiles'] if t['id']==s['snapshot']['actors'][actor])
    choices=[t for t in s['tiles'] if not t.get('solid') and not (actor=='luvie' and t.get('small')) and abs(t['x']-at['x'])+abs(t['z']-at['z'])==1 and abs(t['h']-at['h'])<=1]
    choices.sort(key=lambda t:(t['x']+t['z'],abs(t['h']-at['h'])))
    assert choices,'no safe adjacent view position'
    s=h['move_to'](page,choices[0]['id']); h['check_contacts'](s,'clear core')
    page.mouse.move(1,1); page.screenshot(path=str(folder/'clear.png'))
    assert len(errors)==error_start,errors[error_start:]
    row.update(passed=True,actual=s)
   except Exception as e:
    row.update(reason=str(e)); page.screenshot(path=str(folder/'failure.png'))
   row.update(inputTrace=list(h['input_trace']),errors=errors[error_start:])
   (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
   report['results'].append(row)
   print(json.dumps({k:row.get(k) for k in ['level','command','size','passed','reason']},ensure_ascii=False),flush=True)
  context.close()
 browser.close()
report['passed']=bool(report['results']) and all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

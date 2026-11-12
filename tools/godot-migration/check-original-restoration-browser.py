"""Original-art acceptance: completed worlds stay completed during real strolls.

QA only prepares the authored ending state. Settings/resume, walking and overview
use real controls. Screenshots are visual evidence, not a full-route test.
"""
import argparse, copy, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--base', required=True)
p.add_argument('--output', required=True)
p.add_argument('--levels', default='')
p.add_argument('--sizes', default='1280x720,844x390')
args = p.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)
helper = ROOT/'tools/godot-migration/check-native-browser.py'
saved = sys.argv
sys.argv = [str(helper),'--base',args.base,'--output',args.output]
h = {'__file__':str(helper),'__name__':'original_restoration_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv = saved
selected = set(args.levels.split(',')) if args.levels else set()
report = {'build':h['build'],'scope':__doc__,'results':[],'visualReview':'pending'}
with sync_playwright() as pw:
 browser = pw.chromium.launch(channel='chrome',headless=True)
 for size in args.sizes.split(','):
  width,height = map(int,size.split('x'))
  context = browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1,has_touch=width<1000)
  page = context.new_page(); errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
  page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
  h['args'].touch=width<1000
  for case in h['cases']:
   level=case['id']
   if selected and level not in selected: continue
   folder=out/size/level; folder.mkdir(parents=True,exist_ok=True)
   row={'level':level,'size':size,'passed':False}; start_errors=len(errors); h['input_trace'].clear()
   try:
    completed=copy.deepcopy(case['steps'][-1]['snapshot'])
    assert completed['completed'],'authored ending is completed'
    s=h['prepare'](page,completed)
    page.mouse.move(1,1); page.wait_for_timeout(500)
    page.screenshot(path=str(folder/'completed.png'))
    row['completed']=s
    # A real settings close resumes an already completed garden as a stroll.
    h['find_button'](page,{'path_suffix':'/Pause'})
    page.keyboard.press('Escape'); h['input_trace'].append({'kind':'key','key':'Escape'})
    s=h['stable'](page,level)
    assert s['snapshot']['completed'] and s['strolling'] and not s['paused'],'completed stroll remains repaired'
    actor=s['snapshot']['active']
    at=next(t for t in s['tiles'] if t['id']==s['snapshot']['actors'][actor])
    candidates=[t for t in s['tiles'] if not t.get('solid') and not t.get('small') and abs(t['h']-at['h'])<.01 and 1<=abs(t['x']-at['x'])+abs(t['z']-at['z'])<=2]
    # Prefer the same front terrace so neither actor covers the core's picture.
    candidates.sort(key=lambda t:(-(t['x']+t['z']),-abs(t['x']-at['x'])-abs(t['z']-at['z'])))
    assert candidates,'nearby same-height legal clearing support'
    s=h['move_to'](page,candidates[0]['id'])
    h['check_contacts'](s,'completed stroll clear')
    assert s['snapshot']['completed'],'walking retains bloom, pool and lantern completion art'
    for key in ['growth','turns','flags','items','water','mode','frozen','song','beat','cloudSeed','cloudLatch']:
     assert s['snapshot'].get(key)==completed.get(key),'stroll preserves '+key
    page.mouse.move(1,1); page.screenshot(path=str(folder/'completed-clear.png'))
    row['clear']=s
    h['find_button'](page,{'text':'全景'}); page.wait_for_timeout(900)
    s=h['fresh'](page); assert s['overview'] and s['snapshot']['completed']
    page.screenshot(path=str(folder/'overview.png')); row['overview']=s
    h['find_button'](page,{'text':'跟随'}); page.wait_for_timeout(900)
    s=h['fresh'](page); assert not s['overview']
    page.screenshot(path=str(folder/'returned.png')); row['returned']=s
    assert len(errors)==start_errors,errors[start_errors:]
    row['passed']=True
   except Exception as e:
    row.update(reason=str(e),actual=h['state'](page)); page.screenshot(path=str(folder/'failure.png'))
   row.update(errors=errors[start_errors:],inputTrace=list(h['input_trace']))
   (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
   report['results'].append(row)
   (out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
   print(json.dumps({k:row.get(k) for k in ['level','size','passed','reason']},ensure_ascii=False),flush=True)
  context.close()
 browser.close()
report['passed']=bool(report['results']) and all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

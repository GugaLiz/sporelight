"""QA precondition; real bell delivery, undo, reopening and sanctuary approach.
Images check the restored original gate, seal, NPC and fountain; not a full route.
"""
import argparse, json, math, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',required=True); p.add_argument('--output',required=True)
args=p.parse_args(); out=ROOT/args.output; out.mkdir(parents=True,exist_ok=True)
helper=ROOT/'tools/godot-migration/check-native-browser.py'
saved=sys.argv; sys.argv=[str(helper),'--base',args.base,'--output',args.output]
h={'__file__':str(helper),'__name__':'sanctuary_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv=saved
case=next(c for c in h['cases'] if c['id']=='1-4'); before=case['initial']
for step in case['steps']:
 if step['command']=={'kind':'act','value':'use:home'}: expected=step['snapshot']; break
 before=step['snapshot']
report={'build':h['build'],'scope':__doc__,'results':[],'visualReview':'pending'}
with sync_playwright() as pw:
 browser=pw.chromium.launch(channel='chrome',headless=True)
 for width,height in [(1280,720),(844,390)]:
  folder=out/f'{width}x{height}'; folder.mkdir(parents=True,exist_ok=True)
  context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1,has_touch=width<1000)
  page=context.new_page(); errors=[]; h['input_trace'].clear(); h['args'].touch=width<1000
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  row={'size':[width,height],'passed':False}
  try:
   page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
   page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
   h['prepare'](page,before); page.mouse.move(1,1); page.screenshot(path=str(folder/'closed.png'))
   s=h['action'](page,'use:home'); assert s['snapshot']['flags']==expected['flags']
   h['check_contacts'](s,'bell delivery'); page.screenshot(path=str(folder/'opened.png'))
   if width<1000: h['find_button'](page,{'action':'undo'},True)
   else: page.keyboard.press('z'); h['input_trace'].append({'kind':'key','key':'z'})
   s=h['stable'](page); assert s['snapshot']['flags']==before['flags']
   page.screenshot(path=str(folder/'undo.png'))
   h['action'](page,'use:home')
   s=h['move_to'](page,'f:-9:0'); h['check_contacts'](s,'enter restored sanctuary')
   assert 'home' in s['snapshot']['flags'] and not s['snapshot']['completed']
   page.mouse.move(1,1); page.screenshot(path=str(folder/'fountain.png'))
   page.wait_for_timeout(1100); page.screenshot(path=str(folder/'fountain-later.png'))
   h['find_button'](page,{'text':'全景'}); page.wait_for_timeout(900)
   page.screenshot(path=str(folder/'overview.png'))
   s=h['fresh'](page); assert s['overview'] and not errors,errors
   h['find_button'](page,{'text':'跟随'})
   # Prepare the authored repair precondition, then click the visible bud.
   # The shifted picture must route to its unchanged rule support.
   h['prepare'](page,case['steps'][-2]['snapshot'])
   h['move_to'](page,'f:-8:-1'); page.wait_for_timeout(900)
   s=h['fresh'](page); targets={t['id']:t for t in s['targets']}
   core=targets['f:-9:0']; east=targets['f:-8:0']
   density=(east['x']-core['x'])/math.sqrt(.5)
   width=110*math.sqrt(2)/70
   # Source bud (128,80), canvas256, offset(0,102), safe layout(+1.2,-.7).
   dx=1.2+.27*width/1.16; dz=-.7+.34*width/1.16
   point=[core['x']+(dx-dz)*math.sqrt(.5)*density,
          core['y']+((dx+dz)*math.sqrt(.125)-.012*width/1.16*math.sqrt(.75)-150*width/256)*density]
   page.screenshot(path=str(folder/'before-flower-click.png'))
   page.mouse.click(*point); h['input_trace'].append({'kind':'click-visible-flower','point':point})
   page.wait_for_function("() => window.__sporelightState?.snapshot.actors.luvie==='f:-9:0' && !window.__sporelightState.moving",timeout=15000)
   s=h['stable'](page,'1-4'); h['check_contacts'](s,'visible flower click')
   assert not s['snapshot']['completed'],'walking to flower must not auto-complete'
   page.screenshot(path=str(folder/'after-flower-click.png'))
   s=h['action'](page,'repair'); assert s['snapshot']['completed'],'explicit repair after physical flower approach'
   row['flowerClick']={'point':point,'support':s['snapshot']['actors']['luvie'],'completedAfterExplicitRepair':True}
   h['find_button'](page,{'text':'留下看看'})
   page.screenshot(path=str(folder/'explicit-repair.png'))
   s=h['fresh'](page); assert not errors,errors
   row.update(passed=True,actual=s)
  except Exception as e:
   row.update(reason=str(e),actual=h['state'](page)); page.screenshot(path=str(folder/'failure.png'))
  row.update(errors=errors,inputTrace=list(h['input_trace']))
  (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
  report['results'].append(row); context.close()
  print(json.dumps({k:row.get(k) for k in ['size','passed','reason']},ensure_ascii=False),flush=True)
 browser.close()
report['passed']=all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

"""Prepare the previous cloud-3 tile, then really walk to and use its control."""
import argparse, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',required=True);p.add_argument('--output',required=True)
args=p.parse_args();out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
helper=ROOT/'tools/godot-migration/check-native-browser.py'
saved=sys.argv;sys.argv=[str(helper),'--base',args.base,'--output',args.output]
h={'__file__':str(helper),'__name__':'cloud_operator_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv=saved
assert h['build']['webMode']=='debug','QA preconditions need the debug build'
case=next(c for c in h['cases'] if c['id']=='cloud-3')
before=case['initial']
for step in case['steps']:
 if step['command']=={'kind':'move','value':'floor:8:5'}:break
 before=step['snapshot']
report={'build':h['build'],'scope':__doc__,'results':[],'visualReview':'pending'}
with sync_playwright() as pw:
 browser=pw.chromium.launch(channel='chrome',headless=True)
 for width,height in [(1280,720),(844,390)]:
  folder=out/f'{width}x{height}';folder.mkdir(parents=True,exist_ok=True)
  context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1)
  page=context.new_page();errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  row={'size':[width,height],'passed':False};h['input_trace'].clear()
  try:
   page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
   page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
   h['prepare'](page,before)
   h['move_to'](page,'floor:8:5');page.wait_for_timeout(900)
   s=h['fresh'](page);h['check_contacts'](s,'cloud-3 natural arrival')
   assert all(t=='floor:8:5' for t in s['snapshot']['actors'].values())
   page.mouse.move(1,1);page.screenshot(path=str(folder/'natural-arrival.png'));row['arrival']=s
   h['action'](page,'rotate');page.wait_for_timeout(700)
   s=h['fresh'](page);h['check_contacts'](s,'cloud-3 actual rotation')
   assert all(t=='floor:8:5' for t in s['snapshot']['actors'].values())
   page.screenshot(path=str(folder/'after-rotate.png'));row['after']=s
   assert not errors,errors
   row['passed']=True
  except Exception as error:
   row['reason']=str(error);page.screenshot(path=str(folder/'failure.png'))
  row.update(errors=errors,inputTrace=list(h['input_trace']))
  (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
  report['results'].append(row);context.close()
  print(json.dumps({'size':row['size'],'passed':row['passed'],'reason':row.get('reason')}),flush=True)
 browser.close()
report['passed']=all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

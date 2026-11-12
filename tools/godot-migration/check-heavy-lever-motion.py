"""Capture real pull/release frames using the established motion QA harness."""
import argparse, copy, json, runpy, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',required=True);p.add_argument('--output',required=True)
args=p.parse_args();out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
helper=ROOT/'tools/godot-migration/check-native-browser.py'
saved=sys.argv;sys.argv=[str(helper),'--base',args.base,'--output',args.output]
h={'__file__':str(helper),'__name__':'heavy_lever_motion_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv=saved
m=runpy.run_path(str(ROOT/'tools/godot-migration/check-motion-framing-browser.py'),run_name='heavy_lever_motion')
case=next(c for c in h['cases'] if c['id']=='1-4')
before,held=m['transitions'](case,'use:hold')
released=copy.deepcopy(held);released['flags']=[f for f in held['flags'] if f!='hold']
release_case={'id':'1-4','initial':held,'steps':[{'command':{'kind':'act','value':'release:hold'},'snapshot':released}]}
report={'build':h['build'],'scope':__doc__,'results':[],'visualReview':'pending'}
with sync_playwright() as pw:
 browser=pw.chromium.launch(channel='chrome',headless=True)
 for width,height in [(1280,720),(844,390)]:
  size=f'{width}x{height}';context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1)
  page=context.new_page();errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda msg:errors.append(msg.text) if msg.type=='error' or 'SCRIPT ERROR:' in msg.text else None)
  page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
  page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
  for command,scenario in [('use:hold',case),('release:hold',release_case)]:
   folder=out/size/'motion'/'1-4'/command.replace(':','-');folder.mkdir(parents=True,exist_ok=True)
   row={'size':size,'level':'1-4','command':command,'passed':False};h['input_trace'].clear()
   try:
    row.update(m['capture_motion'](page,h,scenario,command,folder))
    assert not errors,errors
   except Exception as error:
    row['reason']=str(error);page.screenshot(path=str(folder/'failure.png'))
   row.update(errors=list(errors),inputTrace=list(h['input_trace']))
   (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
   report['results'].append(row)
   print(json.dumps({k:row.get(k) for k in ['size','command','passed','reason']}),flush=True)
  context.close()
 browser.close()
report['passed']=all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

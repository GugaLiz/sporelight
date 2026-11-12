"""1-4 spacing review at authored milestones; QA prepares states, not routes.

Pulling and camera overview use actual controls. Other milestones are prepared
from the unchanged reference; screenshots need separate human review.
"""
import argparse, copy, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',required=True);p.add_argument('--output',required=True)
p.add_argument('--sizes',default='1280x720,844x390')
args=p.parse_args();out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
helper=ROOT/'tools/godot-migration/check-native-browser.py'
saved=sys.argv;sys.argv=[str(helper),'--base',args.base,'--output',args.output]
h={'__file__':str(helper),'__name__':'spacing_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv=saved
assert h['build']['webMode']=='debug'
case=next(c for c in h['cases'] if c['id']=='1-4')
def before(action):
 i=next(i for i,s in enumerate(case['steps']) if s['command'].get('value')==action)
 return copy.deepcopy(case['steps'][i-1]['snapshot'] if i else case['initial'])
scenes=[('01-arrival',case['initial']),('02-holding',case['initial']),
 ('03-plate',case['steps'][11]['snapshot']),
 ('04-latch',before('use:latch')),('05-bell',before('take:bell')),
 ('06-home',before('use:home')),('07-opened',case['steps'][28]['snapshot']),
 ('07b-rejoined',case['steps'][42]['snapshot']),
 ('08-completed',case['steps'][-1]['snapshot'])]
report={'build':h['build'],'scope':__doc__,'results':[],'visualReview':'pending'}
with sync_playwright() as pw:
 browser=pw.chromium.launch(channel='chrome',headless=True)
 for size in args.sizes.split(','):
  w,ht=map(int,size.split('x'));folder=out/size;folder.mkdir(parents=True,exist_ok=True)
  context=browser.new_context(viewport={'width':w,'height':ht},device_scale_factor=1)
  page=context.new_page();errors=[];row={'size':size,'states':{},'passed':False}
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  h['input_trace'].clear()
  try:
   page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
   page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
   for name,snapshot in scenes:
    h['prepare'](page,copy.deepcopy(snapshot))
    if name=='02-holding':h['action'](page,'use:hold')
    page.wait_for_timeout(650);s=h['stable'](page,'1-4');h['check_contacts'](s,name)
    row['states'][name]=s;page.mouse.move(1,1);page.screenshot(path=str(folder/(name+'.png')))
   h['find_button'](page,{'path_suffix':'/Pause'})
   page.keyboard.press('Escape');h['stable'](page,'1-4')
   if not h['fresh'](page)['overview']:
    h['find_button'](page,{'text':'全景'});page.wait_for_timeout(900)
   row['states']['09-overview']=h['fresh'](page)
   page.mouse.move(1,1);page.screenshot(path=str(folder/'09-overview.png'))
   assert not errors,errors
   row['passed']=True
  except Exception as error:
   row['reason']=str(error);page.screenshot(path=str(folder/'failure.png'))
  row.update(errors=errors,inputTrace=list(h['input_trace']));report['results'].append(row)
  (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
  print(json.dumps({'size':size,'passed':row['passed'],'reason':row.get('reason')},ensure_ascii=False),flush=True)
  context.close()
 browser.close()
report['passed']=all(r['passed'] for r in report['results']) and bool(report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

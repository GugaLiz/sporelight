"""1-4 lever: QA prepares preconditions; all actions use real player input.

Checks approach, sustained hold, same-tile release, blocked release, switch,
undo, pause/resume and a latched return. Actual PNGs require visual review.
"""
import argparse, copy, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',required=True);p.add_argument('--output',required=True)
args=p.parse_args();out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
helper=ROOT/'tools/godot-migration/check-native-browser.py'
saved=sys.argv;sys.argv=[str(helper),'--base',args.base,'--output',args.output]
h={'__file__':str(helper),'__name__':'heavy_lever_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv=saved
assert h['build']['webMode']=='debug','QA preconditions need the debug Web build'
case=next(c for c in h['cases'] if c['id']=='1-4')
report={'build':h['build'],'scope':__doc__,'results':[],'visualReview':'pending'}
with sync_playwright() as pw:
 browser=pw.chromium.launch(channel='chrome',headless=True)
 for width,height in [(1280,720),(844,390)]:
  folder=out/f'{width}x{height}';folder.mkdir(parents=True,exist_ok=True)
  context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1)
  page=context.new_page();errors=[];states={}
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  row={'size':[width,height],'passed':False};h['input_trace'].clear()
  def capture(name):
   s=h['fresh'](page);h['check_contacts'](s,name)
   page.mouse.move(1,1);page.screenshot(path=str(folder/(name+'.png')));states[name]=s
   return s
  try:
   page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
   page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
   h['prepare'](page,case['initial'])
   h['move_to'](page,'f:-4:0');capture('01-adjacent')
   h['action'](page,'use:hold')
   page.wait_for_timeout(650);s=h['stable'](page,'1-4');capture('02-holding')
   assert s['snapshot']['actors']['luvie']=='f:-3:0' and 'hold' in s['snapshot']['flags'],'real approach before holding'
   held=s['snapshot'];revision=s['revision']
   # Repeating the held command is deliberately a no-op, so the shared
   # helper's 'every action must increase revision' assertion is unsuitable.
   commands=[c for c in s['commands'] if c['id'] not in ['switch','follow']]
   index=next(i for i,c in enumerate(commands) if c['id']=='use:hold')
   page.keyboard.press(str(index+1));h['input_trace'].append({'kind':'repeat-hold','key':str(index+1)})
   s=h['stable'](page,'1-4')
   assert s['revision']==revision and s['snapshot']==held,'repeat does not toggle or restart action'
   h['action'](page,'switch');capture('03-switched')
   h['action'](page,'switch')
   page.keyboard.press('Escape');page.keyboard.press('Escape');page.wait_for_timeout(500)
   s=capture('04-resumed');assert 'hold' in s['snapshot']['flags'] and not s['paused']
   page.keyboard.down('ArrowLeft');page.wait_for_timeout(45);page.keyboard.up('ArrowLeft')
   s=h['stable'](page,'1-4');capture('05-released-by-walk')
   assert 'hold' not in s['snapshot']['flags'] and s['snapshot']['actors']['luvie']=='f:-3:0','same tile walk releases'
   h['find_button'](page,{'action':'undo'});s=h['stable'](page,'1-4');capture('06-undo-hold')
   assert 'hold' in s['snapshot']['flags'],'undo restores hold'
   h['action'](page,'release:hold');s=h['stable'](page,'1-4');capture('07-explicit-release')
   assert 'hold' not in s['snapshot']['flags']
   blocked=copy.deepcopy(case['initial']);blocked['flags']=['hold'];blocked['actors']['buddy']='f:0:0'
   h['prepare'](page,blocked);capture('08-passenger-on-bridge')
   start=h['fresh'](page);pos=start['native']['actors']['luvie']['position']
   page.keyboard.down('ArrowLeft');page.wait_for_timeout(150);page.keyboard.up('ArrowLeft')
   s=h['stable'](page,'1-4');capture('09-blocked-release')
   assert 'hold' in s['snapshot']['flags'],'bridge occupant keeps hold'
   actual=s['native']['actors']['luvie']['position'];assert abs(actual[0]-pos[0])<.005 and abs(actual[2]-pos[2])<.005,'failed release rolls back body'
   late=copy.deepcopy(case['steps'][-1]['snapshot']);late['completed']=False
   late['actors']={'luvie':'f:-3:0','buddy':'f:-2:0'};late['active']='luvie';late['follow']=False
   late['flags']=list(set(late['flags']+['latch','hold']));late.pop('runtime',None)
   h['prepare'](page,late);s=capture('10-return-after-latch')
   assert 'hold' not in s['snapshot']['flags'] and not any(c['id']=='use:hold' for c in s['commands']),'fixed bridge does not rearm hold'
   assert not errors,errors
   row['passed']=True
  except Exception as error:
   row['reason']=str(error);page.screenshot(path=str(folder/'failure.png'))
  row.update(states=states,errors=errors,inputTrace=list(h['input_trace']))
  (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
  report['results'].append(row);context.close()
  print(json.dumps({'size':row['size'],'passed':row['passed'],'reason':row.get('reason')}),flush=True)
 browser.close()
report['passed']=all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

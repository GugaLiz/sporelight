"""Real input through both four-root detours. Snapshot prepares only fresh starts."""
import argparse,json,sys,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser()
parser.add_argument('--base',required=True)
parser.add_argument('--output',required=True)
args=parser.parse_args()
out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
helper=ROOT/'tools/godot-migration/check-native-browser.py'
original=sys.argv
sys.argv=[str(helper),'--base',args.base,'--output',args.output]
h={'__file__':str(helper),'__name__':'second_fourth_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv=original
report={'build':h['build'],'results':[]}
with sync_playwright() as p:
 browser=p.chromium.launch(channel='chrome',headless=True)
 for width,height in [(1280,720),(844,390)]:
  for branch in ['up','down']:
   folder=out/f'{width}x{height}'/branch;folder.mkdir(parents=True,exist_ok=True)
   context=browser.new_context(viewport={'width':width,'height':height},has_touch=width<1000)
   page=context.new_page();errors=[]
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
   row={'size':[width,height],'branch':branch,'passed':False}
   h['args'].touch=width<1000;h['input_trace'].clear()
   def save(name):
    page.screenshot(path=str(folder/(name+'.png')))
    (folder/(name+'.json')).write_text(json.dumps(h['fresh'](page),ensure_ascii=False,indent=2),encoding='utf8')
   try:
    page.goto(args.base+'?qa=1&level=1-2',wait_until='networkidle',timeout=120000)
    page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
    initial=next(c['initial'] for c in h['cases'] if c['id']=='1-2')
    h['prepare'](page,initial);save('arrival')
    h['move_to'](page,'f:1:1')
    for direction in [branch,'right','right']: h['action'](page,'grow:root:'+direction)
    s=h['fresh'](page);assert len(s['snapshot']['growth']['root'])==3
    save('three-roots')
    tip=s['snapshot']['growth']['root'][-1]
    h['move_to'](page,tip)
    gap='ArrowDown' if branch=='up' else 'ArrowUp'
    for keys in [['ArrowRight'],[gap],['ArrowRight',gap]]:
     h['move_to'](page,tip)
     for key in keys:page.keyboard.down(key)
     page.wait_for_timeout(700)
     for key in keys:page.keyboard.up(key)
     s=h['stable'](page,'1-2')
     assert s['snapshot']['actors']['luvie']==tip,'Three roots cannot cross by held/diagonal input'
    save('three-blocked')
    h['move_to'](page,'f:1:1')
    h['action'](page,'grow:root:'+('down' if branch=='up' else 'up'))
    s=h['fresh'](page);assert len(s['snapshot']['growth']['root'])==4
    assert any(t['id']=='g:root:3:1' for t in s['tiles'])
    save('four-linked')
    h['move_to'](page,'f:4:1');h['check_contacts'](h['fresh'](page),'fourth root and entry stair');save('on-bank')
    h['move_to'](page,'f:5:2');save('observation-bank')
    h['move_to'](page,'f:4:1');h['action'](page,'repair')
    assert h['fresh'](page)['snapshot']['completed'],'Real-input route completes'
    save('completed');assert not errors,errors
    row['passed']=True
   except Exception as e:
    row.update(reason=str(e),traceback=traceback.format_exc())
    save('failure')
   row['errors']=errors;row['inputs']=list(h['input_trace'])
   (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
   report['results'].append(row);context.close()
   print(json.dumps({k:row.get(k) for k in ['size','branch','passed','reason']}),flush=True)
 browser.close()
report['passed']=all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
raise SystemExit(0 if report['passed'] else 1)

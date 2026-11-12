"""Real actions and movement to expose mechanism flowers and insects."""
import argparse, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser()
p.add_argument('--base',required=True)
p.add_argument('--output',required=True)
args=p.parse_args(); out=ROOT/args.output; out.mkdir(parents=True,exist_ok=True)
helper=ROOT/'tools/godot-migration/check-native-browser.py'
sys.argv=[str(helper),'--base',args.base,'--output',args.output]
h={'__file__':str(helper),'__name__':'detail_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
report={'build':h['build'],'scope':'Authored precondition; real action and movement; no full-route claim.','results':[]}
with sync_playwright() as p:
 browser=p.chromium.launch(channel='chrome',headless=True)
 for width,height in [(1280,720),(844,390)]:
  context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1,has_touch=width<1000)
  page=context.new_page(); errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
  page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
  h['args'].touch=width<1000
  for level,command in [('2-4','use:plant'),('2-4','use:invite'),('3-3','use:care')]:
   folder=out/f'{width}x{height}'/(level+'-'+command.replace(':','-')); folder.mkdir(parents=True,exist_ok=True)
   row={'level':level,'command':command,'size':[width,height],'passed':False}; error_start=len(errors); h['input_trace'].clear()
   try:
    case=next(c for c in h['cases'] if c['id']==level); before=case['initial']
    for step in case['steps']:
     if step['command']=={'kind':'act','value':command}: expected=step['snapshot']; break
     before=step['snapshot']
    h['prepare'](page,before); s=h['action'](page,command)
    for key in ['flags','items','growth','turns','water']:
     assert s['snapshot'].get(key)==expected.get(key),key
    at=next(t for t in s['tiles'] if t['id']==s['snapshot']['actors'][s['snapshot']['active']])
    group=':'.join(at['id'].split(':')[:2]) if at['id'].startswith('m:') else 'f'
    candidates=[t for t in s['tiles'] if t['id'].startswith(group+':') and not t.get('solid') and abs(t['h']-at['h'])<.01 and 0<abs(t['x']-at['x'])+abs(t['z']-at['z'])<=2]
    candidates.sort(key=lambda t:(t['x']+t['z'],t['x']))
    assert candidates,'same platform view position'
    s=h['move_to'](page,candidates[0]['id']); h['check_contacts'](s,'expose mechanism')
    for key in ['flags','items','growth','turns','water']:
     assert s['snapshot'].get(key)==expected.get(key),key+' changed while moving'
    page.mouse.move(1,1); page.screenshot(path=str(folder/'clear.png'))
    assert len(errors)==error_start,errors[error_start:]
    row.update(passed=True,actual=s)
   except Exception as e:
    row.update(reason=str(e)); page.screenshot(path=str(folder/'failure.png'))
   row.update(inputTrace=list(h['input_trace']),errors=errors[error_start:])
   (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8'); report['results'].append(row)
   print(json.dumps({k:row.get(k) for k in ['level','command','size','passed','reason']},ensure_ascii=False),flush=True)
  context.close()
 browser.close()
report['passed']=all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

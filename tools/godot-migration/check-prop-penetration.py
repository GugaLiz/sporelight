"""GPU/real input acceptance for hard bases, mirror placement and foreground crowns.

QA prepares initial states; route steps and negative motion use real controls.
Screenshots require a separate visual review, never inferred from assertions.
"""
import argparse,copy,json,sys
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
h={'__file__':str(helper),'__name__':'prop_helpers'}
exec(compile(helper.read_text(encoding='utf8').split('\nwith sync_playwright() as p:')[0],str(helper),'exec'),h)
sys.argv=saved
report={'build':h['build'],'scope':__doc__,'results':[],'visualReview':'pending'}
with sync_playwright() as pw:
 browser=pw.chromium.launch(channel='chrome',headless=True)
 for size in args.sizes.split(','):
  width,height=map(int,size.split('x'));folder=out/size;folder.mkdir(parents=True,exist_ok=True)
  context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1)
  page=context.new_page();errors=[];h['input_trace'].clear()
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' or 'SCRIPT ERROR:' in m.text else None)
  row={'size':size,'passed':False,'states':{}}
  def capture(name):
   s=h['stable'](page);h['check_contacts'](s,name)
   row['states'][name]=s;page.mouse.move(1,1);page.screenshot(path=str(folder/(name+'.png')))
   return s
  try:
   page.goto(args.base+'?qa=1',wait_until='networkidle',timeout=120000)
   page.wait_for_function('window.__sporelightState?.snapshot',timeout=120000)
   fourth=next(c for c in h['cases'] if c['id']=='1-4')
   state=copy.deepcopy(fourth['steps'][-2]['snapshot'])
   state['actors']={'luvie':'f:-8:1','buddy':'f:-9:0'};state['follow']=False;state.pop('runtime',None)
   h['prepare'](page,state);capture('fourth-01-before-contact')
   page.keyboard.down('ArrowUp');page.wait_for_timeout(700);page.keyboard.up('ArrowUp')
   contact=capture('fourth-02-stone-contact')
   actor=contact['native']['actors']['luvie'];assert actor['position'][2]>.29,'stone blocks entry from south'
   h['move_to'](page,'f:-9:0');capture('fourth-03-care-approach')
   # Fixed supported pose exercises the user-reported foreground crown.
   state['actors']['luvie']='f:-8:1'
   state['runtime']={'version':1,'poses':{'luvie':{'support':'f:-8:1','offset':[.3,0,.2],'facing':'front'}}}
   h['prepare'](page,state);capture('fourth-04-lotus-behind')
   page.keyboard.down('ArrowRight');page.wait_for_timeout(120);page.keyboard.up('ArrowRight')
   page.keyboard.down('ArrowDown');page.wait_for_timeout(120);page.keyboard.up('ArrowDown')
   capture('fourth-05-lotus-walking')
   pond=next(c for c in h['cases'] if c['id']=='2-2')
   h['prepare'](page,copy.deepcopy(pond['initial']));capture('pond-00-arrival')
   expected=pond['initial']
   shots={4:'01-ground-mirror',5:'02-carry',10:'03-fixed-mirror',11:'04-slot-approach',12:'05-placed',13:'06-angle-b',15:'07-beam',19:'08-care',20:'09-completed'}
   for index,step in enumerate(pond['steps']):
    command=step['command'];row['step']=index;row['command']=command
    if command['kind']=='move':s=h['move_to'](page,command['value'])
    else:
     active=h['fresh'](page)['snapshot']['active'];intended=expected['actors'][active]
     if h['fresh'](page)['snapshot']['actors'][active]!=intended:h['move_to'](page,intended)
     s=h['action'](page,command['value'])
     for key in ['flags','items','turns']:
      assert s['snapshot'].get(key)==step['snapshot'].get(key),'authored action preserved: '+command['value']+'/'+key
    h['check_contacts'](s,'pond step '+str(index));expected=step['snapshot']
    if index in shots:capture('pond-'+shots[index])
   assert h['fresh'](page)['snapshot']['completed'],'entire pond route completes through real input'
   h['find_button'](page,{'contains':'留下看看'})
   clear=capture('pond-10-completed-clear')
   assert clear['snapshot']['completed'],'clearing completion panel preserves progress'
   assert not errors,errors
   row['passed']=True
  except Exception as error:
   row['reason']=str(error);row['actual']=h['state'](page);page.screenshot(path=str(folder/'failure.png'))
  row['errors']=errors;row['inputTrace']=list(h['input_trace']);report['results'].append(row)
  (folder/'checks.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
  print(json.dumps({'size':size,'passed':row['passed'],'step':row.get('step'),'reason':row.get('reason')},ensure_ascii=False),flush=True)
  context.close()
 browser.close()
report['passed']=all(r['passed'] for r in report['results']) and bool(report['results'])
(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

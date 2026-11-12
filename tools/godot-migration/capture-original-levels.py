"""Isolated reference-site profiles; seeded states are visual setup only."""
import argparse,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser();p.add_argument('--base',default='https://gugaliz.github.io/sporelight/');p.add_argument('--output',default='docs/qa-godot-native/original-level-restoration/reference');p.add_argument('--sizes',default='1280x720,844x390');p.add_argument('--levels',default='')
p.add_argument('--states',default='initial,final')
args=p.parse_args();out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
ref=json.loads((ROOT/'godot/tests/fixtures/reference.json').read_text(encoding='utf8'))
cloud=json.loads((ROOT/'godot/tests/fixtures/cloud-reference.json').read_text(encoding='utf8'))['levels']
cases=[{'id':c['levelId'],'initial':c['initial']['snapshot'],'final':c['steps'][-1]['snapshot']} for c in ref['cases'] if c['name'].startswith('authored/')]
cases += [{'id':c['id'],'initial':c['initial'],'final':c['steps'][-1]['snapshot']} for c in cloud]
settings={'bgm':0,'sfx':0,'ambient':0,'quality':'standard','dynamicLight':True,'particles':True,'lowMotion':False,'vibration':False,'fullscreen':False,'language':'zh-CN'}
ids=[c['id'] for c in cases if not c['id'].startswith('cloud')]
report={'base':args.base,'scope':'Isolated profiles, seeded authored states, real menu entry. Not full-gameplay evidence.','results':[]}
with sync_playwright() as p:
 browser=p.chromium.launch(channel='chrome',headless=True)
 for size in args.sizes.split(','):
  width,height=map(int,size.split('x'))
  for case in cases:
   level=case['id']
   if args.levels and level not in args.levels.split(','):continue
   for state in args.states.split(','):
    folder=out/size/level;folder.mkdir(parents=True,exist_ok=True)
    context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1)
    save={'version':2,'playerName':'露薇','hasNamed':True,'lastLevel':level if level in ids else '1-1','run':None,'levels':{i:{'unlocked':True,'completed':True,'bestStars':0,'bestCollected':0} for i in ids},'gallery':{},'settings':settings}
    garden={'version':1,'lastLevel':level if level in ids else '1-1','runs':{},'memories':{},'records':{i:{'completed':True,'stars':0,'collected':0} for i in ids},'legacy':save}
    clouds={'version':1,'lastLevel':level if level.startswith('cloud') else 'cloud-1','runs':{},'memories':{},'completed':[c['id'] for c in cloud],'discoveries':{}}
    (clouds if level.startswith('cloud') else garden)['memories' if state=='final' else 'runs'][level]=case[state]
    storage={'sporelight.save.v2':save,'sporelight.garden2.v1':garden,'sporelight.cloud-gardens.v1':clouds}
    context.add_init_script('const referenceSaves='+json.dumps(storage,ensure_ascii=False)+';for(const [k,v]of Object.entries(referenceSaves))localStorage.setItem(k,JSON.stringify(v));')
    page=context.new_page();errors=[];failed=[]
    page.on('pageerror',lambda e:errors.append(str(e)));page.on('requestfailed',lambda r:failed.append({'url':r.url,'reason':r.failure}))
    row={'level':level,'state':state,'size':[width,height],'passed':False}
    try:
     page.goto(args.base,wait_until='networkidle',timeout=120000);page.locator('[data-action="开始游戏"]').wait_for(timeout=30000)
     if level.startswith('cloud'):
      page.locator('[data-action="云庭目录"]').click();page.locator(('[data-cloud-review="' if state=='final' else '[data-cloud-enter="')+level+'"]').click()
     elif state=='final':
      page.locator('[data-action="花园纪事"]').click()
      page.locator('details:has([data-garden-review="'+level+'"]) > summary').click()
      page.locator('[data-garden-review="'+level+'"]').click()
     else:page.locator('[data-action="继续旅程"]').click()
     canvas=page.locator('#cloudCanvas' if level.startswith('cloud') else '#gardenCanvas');canvas.wait_for();page.wait_for_load_state('networkidle',timeout=120000)
     if state=='final': page.locator('#cloudStay' if level.startswith('cloud') else '#gardenStay').click()
     page.wait_for_timeout(900)
     page.screenshot(path=str(folder/(state+'.png')));canvas.screenshot(path=str(folder/(state+'-canvas.png')))
     (folder/(state+'-dom.txt')).write_text(page.locator('body').aria_snapshot(),encoding='utf8')
     row.update(passed=not errors,errors=errors,failedResources=failed,canvas=canvas.evaluate('(e)=>({width:e.width,height:e.height,rect:e.getBoundingClientRect().toJSON(),dataset:{...e.dataset}})'),seed=case[state])
    except Exception as e:
     row.update(reason=str(e),errors=errors,failedResources=failed);page.screenshot(path=str(folder/(state+'-failure.png')))
    (folder/(state+'-checks.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8');report['results'].append(row)
    print(json.dumps({k:row.get(k) for k in ['level','state','size','passed','reason']},ensure_ascii=False),flush=True);context.close()
 browser.close()
report['passed']=all(r['passed'] for r in report['results']);(out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(0 if report['passed'] else 1)

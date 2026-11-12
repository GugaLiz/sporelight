"""Normal Web entry and real input, without the full QA state publisher."""
import argparse,json,sys,time,statistics,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser()
parser.add_argument('--base',default='http://localhost:4222/')
parser.add_argument('--output',default='docs/qa-godot-native/loading-startup/baseline')
parser.add_argument('--dpr',type=float,default=1)
parser.add_argument('--level',default='')
parser.add_argument('--verbose',action='store_true')
parser.add_argument('--gl-profile',action='store_true')
parser.add_argument('--reload-once',action='store_true')
parser.add_argument('--growth',action='store_true',help='Sample first and repeated real root-growth actions on 1-1 or 1-2.')
args=parser.parse_args()
out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
with urllib.request.urlopen(args.base.rstrip('/')+'/__build.json') as response:build=json.load(response)
events=[];samples=[];failure=None;warm_startup=None;cold_trace=None
with sync_playwright() as p:
 browser=p.chromium.launch(channel='chrome',headless=True)
 context=browser.new_context(viewport={'width':1280,'height':720},device_scale_factor=args.dpr)
 if args.level or args.verbose:
  def bootstrap(route):
   response=route.fetch();html=response.text()
   assert '"args":[]' in html
   startup_args=(['--verbose'] if args.verbose else [])+(['--','--level='+args.level] if args.level else [])
   route.fulfill(response=response,body=html.replace('"args":[]','"args":'+json.dumps(startup_args)))
  context.route(args.base.rstrip('/')+'/',bootstrap)
 page=context.new_page();started=time.monotonic();environment=None
 if args.gl_profile:
  page.add_init_script('''window.__glTimings={};for(const name of ['compileShader','linkProgram','getProgramParameter','getShaderParameter','texImage2D','texSubImage2D','compressedTexImage2D','bufferData','drawElements','drawArrays','finish','getError','getUniformLocation']){const original=WebGL2RenderingContext.prototype[name];if(!original)continue;WebGL2RenderingContext.prototype[name]=function(...args){const start=performance.now();try{return original.apply(this,args);}finally{const ms=performance.now()-start;const row=window.__glTimings[name]||{count:0,totalMs:0,maxMs:0,slow:[]};row.count++;row.totalMs+=ms;row.maxMs=Math.max(row.maxMs,ms);if(ms>20){const sample={at:start,ms};if(name==='getProgramParameter'&&ms>500)sample.sources=(this.getAttachedShaders(args[0])||[]).map(s=>this.getShaderSource(s));row.slow.push(sample);}window.__glTimings[name]=row;}};}''')
 page.on('console',lambda m:events.append({'seconds':time.monotonic()-started,'type':m.type,'text':m.text}))
 page.on('pageerror',lambda e:events.append({'seconds':time.monotonic()-started,'type':'error','text':str(e)}))
 page.add_init_script('''window.__startupTrace=[];window.__longTasks=[];
 new PerformanceObserver(list=>{for(const e of list.getEntries())window.__longTasks.push({start:e.startTime,ms:e.duration});}).observe({entryTypes:['longtask']});
 new MutationObserver(()=>{const s=document.querySelector('#status');const phase=s?.dataset.phase||'removed';if(window.__startupTrace.at(-1)?.phase!==phase)window.__startupTrace.push({phase,ms:performance.now()});}).observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['data-phase']});''')
 try:
  page.goto(args.base,wait_until='domcontentloaded',timeout=120000)
  page.wait_for_selector('#status',state='detached',timeout=120000)
  startup=time.monotonic()-started
  if args.reload_once:
   cold_trace=page.evaluate('window.__startupTrace')
   warm_started=time.monotonic()
   page.reload(wait_until='domcontentloaded',timeout=120000)
   page.wait_for_selector('#status',state='detached',timeout=120000)
   warm_startup=time.monotonic()-warm_started
  environment=page.evaluate('''() => {const gl=document.querySelector('#canvas').getContext('webgl2');const ext=gl.getExtension('WEBGL_debug_renderer_info');return {renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):'',dpr:devicePixelRatio,canvas:[gl.drawingBufferWidth,gl.drawingBufferHeight],qa:typeof window.__sporelightState!=='undefined'};}''')
  assert not environment['qa']
  page.screenshot(path=str(out/'ready.png'))
  if not args.level:
   page.keyboard.press('Enter');page.wait_for_timeout(350);page.keyboard.press('Enter')
  page.wait_for_timeout(1500)
  page.screenshot(path=str(out/'game.png'))
  for mode in (['growth-cold','growth-warm'] if args.growth else [])+['idle','walking']:
   if mode=='growth-warm':
    page.keyboard.press('z');page.wait_for_timeout(700)
   page.evaluate('''() => {window.__frameSample=[];window.__frameDone=false;let start=null,previous=null;function frame(now){if(start===null)start=now;if(previous!==null)window.__frameSample.push(now-previous);previous=now;if(now-start<6000)requestAnimationFrame(frame);else window.__frameDone=true;}requestAnimationFrame(frame);}''')
   if mode.startswith('growth-'):
    page.keyboard.press('1')
   if mode=='walking':
    for i in range(8):
     key='ArrowLeft' if i%2==0 else 'ArrowRight'
     page.keyboard.down(key);page.wait_for_timeout(600);page.keyboard.up(key)
   page.wait_for_function('window.__frameDone',timeout=60000)
   values=page.evaluate('window.__frameSample');ordered=sorted(values)
   row={'mode':mode,'frames':len(values),'medianMs':statistics.median(values),'p95Ms':ordered[int(len(values)*.95)],'maxMs':max(values),'times':values}
   samples.append(row);print(json.dumps({k:v for k,v in row.items() if k!='times'}),flush=True)
   if mode.startswith('growth-'):page.screenshot(path=str(out/(mode+'.png')))
  page.screenshot(path=str(out/'after-walking.png'))
 except Exception as error:failure=str(error);startup=None
 finally:
  trace=page.evaluate('({startup:window.__startupTrace,longTasks:window.__longTasks,gl:window.__glTimings})')
  report={'completedWithoutErrors':not failure and not any(e['type']=='error' for e in events),'build':build,'level':args.level or 'normal-home-then-start','startupSeconds':startup,'warmStartupSeconds':warm_startup,'coldStartupTrace':cold_trace,'environment':environment,'samples':samples,'trace':trace,'events':events,'failure':failure,'scope':'Fresh isolated headless Chrome context, no QA publisher. Normal home entry or explicit test-only level CLI; real keyboard input. rAF timing is not physical GPU/device certification.'}
  (out/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
  print(json.dumps({'startupSeconds':startup,'warmStartupSeconds':warm_startup,'environment':environment,'failure':failure}),flush=True)
  browser.close()
if not report['completedWithoutErrors']:sys.exit(1)

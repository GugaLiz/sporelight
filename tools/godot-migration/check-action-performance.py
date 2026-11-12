"""No-QA real-input performance scenarios. Collection is not gameplay acceptance.

Scenario JSON: {"name": "...", "phases": [{"name": "...", "actions":
[{"key": "ArrowRight", "holdMs": 600}, {"waitMs": 300},
 {"click": [640, 360]}, {"key": "e"}], "settleMs": 1200}]}.
Coordinates are CSS pixels. Include normal menu navigation in the scenario.
An optional --level bootstrap is a separate diagnostic, never normal-home proof.
Screenshots are outside measured phases; review them to confirm actual actions.
"""
import argparse
import json
import math
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright

PROBE = r"""(() => {
 const p = window.__actionPerf = {frames:[], longTasks:[], phases:[], gl:[], marks:[]};
 let previous = performance.now(),previousDelivery=previous;
 function frame(now) {const delivered=performance.now();p.frames.push({start:previous,end:now,ms:now-previous,deliveryStart:previousDelivery,deliveryEnd:delivered,deliveryMs:delivered-previousDelivery});previous=now;previousDelivery=delivered;requestAnimationFrame(frame);}
 requestAnimationFrame(frame);
 try {new PerformanceObserver(list => {for (const e of list.getEntries()) p.longTasks.push({start:e.startTime,end:e.startTime+e.duration,ms:e.duration});}).observe({type:'longtask',buffered:true});} catch(e) {p.longTaskUnsupported=String(e);}
 new MutationObserver(() => {const el=document.querySelector('#status');const phase=el?.dataset.phase||'removed';if(p.phases.at(-1)?.phase!==phase)p.phases.push({phase,at:performance.now()});}).observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['data-phase']});
 p.mark = name => {const row={name,at:performance.now()};p.marks.push(row);return row.at;};
 if (GL_ENABLED) for (const type of [window.WebGLRenderingContext,window.WebGL2RenderingContext]) {
  if(!type)continue;
  for(const name of ['compileShader','linkProgram','getProgramParameter','getShaderParameter','texImage2D','texSubImage2D','compressedTexImage2D','bufferData','drawElements','drawArrays','finish']) {
   const original=type.prototype[name];if(!original)continue;
   type.prototype[name]=function(...args){const start=performance.now();try{return original.apply(this,args);}finally{const end=performance.now();const row={name,start,end,ms:end-start};if(name==='getProgramParameter'&&row.ms>80)row.shaderSources=(this.getAttachedShaders(args[0])||[]).map(s=>this.getShaderSource(s));p.gl.push(row);}};
  }
 }
})();"""


def stats(values):
    ordered = sorted(values)
    if not ordered:
        return {'count': 0}
    return {'count': len(ordered), 'medianMs': ordered[len(ordered)//2],
            'p95Ms': ordered[min(len(ordered)-1, math.ceil(len(ordered)*.95)-1)],
            'p99Ms': ordered[min(len(ordered)-1, math.ceil(len(ordered)*.99)-1)],
            'maxMs': ordered[-1], 'over33ms': sum(x > 33.4 for x in ordered),
            'over50ms': sum(x > 50 for x in ordered), 'over100ms': sum(x > 100 for x in ordered)}


def metrics(cdp):
    return {m['name']: m['value'] for m in cdp.send('Performance.getMetrics')['metrics']}


def summarize(probe, start, end):
    # Overlap includes a stall that begins before the action marker and ends after it.
    overlap = lambda row: row['end'] > start and row['start'] < end
    frames = [r for r in probe['frames'] if overlap(r)]
    delivery_frames = [r for r in probe['frames'] if r.get('deliveryEnd',r['end']) > start and r.get('deliveryStart',r['start']) < end]
    tasks = [r for r in probe['longTasks'] if overlap(r)]
    gl = {}
    for row in probe['gl']:
        if overlap(row):
            aggregate = gl.setdefault(row['name'], {'count': 0, 'totalMs': 0, 'maxMs': 0, 'slowCalls': []})
            aggregate['count'] += 1
            aggregate['totalMs'] += row['ms']
            aggregate['maxMs'] = max(aggregate['maxMs'], row['ms'])
            if row['ms'] > 20:
                aggregate['slowCalls'].append(row)
    return {'startMs': start, 'endMs': end, 'durationMs': end-start,
            'rAF': stats([r['ms'] for r in frames]),
            'callbackDelivery': stats([r.get('deliveryMs',r['ms']) for r in delivery_frames]), 'frames': frames,
            'longTasks': tasks, 'longTaskTotalMs': sum(min(end,r['end'])-max(start,r['start']) for r in tasks), 'glSyncCalls': gl}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--scenario', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--level', default='')
    parser.add_argument('--size', default='1280x720')
    parser.add_argument('--dpr', type=float, default=1)
    parser.add_argument('--gl-profile', action='store_true', help='Diagnostic pass only: wrappers add overhead; values are sync JS/driver latency, not GPU execution.')
    parser.add_argument('--reload-once', action='store_true', help='Run the scenario again after reload; preserve both complete traces.')
    parser.add_argument('--cpu-profile', action='store_true', help='Diagnostic only: collect a sampled CDP CPU profile; do not mix with clean timing runs.')
    args = parser.parse_args()
    scenario = json.loads(args.scenario.read_text(encoding='utf-8'))
    assert scenario.get('phases'), 'Scenario must provide explicit phases'
    names = [p['name'] for p in scenario['phases']]
    assert len(set(names)) == len(names), 'Phase names must be unique'
    width, height = map(int, args.size.split('x'))
    assert scenario.get('requiredViewport', [width, height]) == [width, height], 'Scenario coordinates require its recorded viewport'
    assert scenario.get('requiredDpr', args.dpr) == args.dpr, 'Scenario requires its recorded DPR'
    out = args.output if args.output.is_absolute() else ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(args.base.rstrip('/')+'/__build.json') as response:
        build = json.load(response)
    report = {'build': build, 'scenario': scenario, 'runs': [], 'errors': [], 'failure': None,
              'entry': 'explicit-level-diagnostic' if args.level else 'ordinary-home',
              'levelOverride': args.level, 'glProfile': args.gl_profile, 'cpuProfile': args.cpu_profile,
              'scope': 'Fresh isolated browser profile does not guarantee empty OS/driver caches. No QA publisher. CDP TaskDuration is renderer main-thread task time, not isolated Godot CPU or GPU duration. GL wrappers measure synchronous API latency and add overhead. First action and repeated action must both be present and visually verified. Collection completion is not a frame-budget or gameplay pass.',
              'visualReview': 'pending', 'performanceVerdict': 'not-assessed'}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome', headless=True)
        context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=args.dpr)
        if args.level:
            def bootstrap(route):
                response = route.fetch()
                html = response.text()
                assert '"args":[]' in html
                route.fulfill(response=response, body=html.replace('"args":[]', '"args":'+json.dumps(['--', '--level='+args.level])))
            context.route(args.base.rstrip('/')+'/', bootstrap)
        page = context.new_page()
        page.add_init_script(PROBE.replace('GL_ENABLED', 'true' if args.gl_profile else 'false'))
        page.on('pageerror', lambda e: report['errors'].append(str(e)))
        page.on('console', lambda m: report['errors'].append(m.text) if m.type == 'error' or 'SCRIPT ERROR:' in m.text else None)
        cdp = context.new_cdp_session(page)
        cdp.send('Performance.enable', {'timeDomain': 'timeTicks'})
        try:
            for run_index in range(2 if args.reload_once else 1):
                run = {'index': run_index, 'kind': 'fresh-context-first-visit' if not run_index else 'same-context-reload', 'phases': []}
                report['runs'].append(run)
                folder = out / str(run_index)
                folder.mkdir(exist_ok=True)
                if args.cpu_profile:
                    cdp.send('Profiler.enable')
                    cdp.send('Profiler.start')
                if not run_index:
                    page.goto(args.base, wait_until='domcontentloaded', timeout=120000)
                else:
                    page.reload(wait_until='domcontentloaded', timeout=120000)
                page.wait_for_selector('#status', state='detached', timeout=120000)
                startup_end = page.evaluate('window.__actionPerf.mark("startup-end")')
                run['startupMs'] = startup_end
                run['environment'] = page.evaluate('''() => {const canvas=document.querySelector('#canvas'),gl=canvas.getContext('webgl2'),ext=gl?.getExtension('WEBGL_debug_renderer_info');return {qa:typeof window.__sporelightState!=='undefined',renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):null,dpr:devicePixelRatio,canvas:[canvas.width,canvas.height],userAgent:navigator.userAgent};}''')
                assert not run['environment']['qa'], 'QA publisher must be absent'
                page.screenshot(path=str(folder/'ready.png'))
                for phase_index, phase in enumerate(scenario['phases']):
                    slug = str(phase_index)+'-'+re.sub(r'[^a-zA-Z0-9_-]', '_', phase['name'])
                    page.screenshot(path=str(folder/(slug+'-before.png')))
                    # Flush screenshot-induced frames before the measurement boundary.
                    page.evaluate('()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))')
                    before = metrics(cdp)
                    start = page.evaluate('(name)=>window.__actionPerf.mark(name)', phase['name']+'-start')
                    inputs = []
                    for action in phase.get('actions', []):
                        at = page.evaluate('(name)=>window.__actionPerf.mark(name)', phase['name']+'-input')
                        inputs.append({'at': at, 'action': action})
                        if 'key' in action:
                            if action.get('holdMs', 0):
                                page.keyboard.down(action['key'])
                                try:
                                    page.wait_for_timeout(action['holdMs'])
                                finally:
                                    page.keyboard.up(action['key'])
                            else:
                                page.keyboard.press(action['key'])
                        elif 'click' in action:
                            page.mouse.click(*action['click'])
                        elif 'waitMs' in action:
                            page.wait_for_timeout(action['waitMs'])
                        else:
                            raise ValueError('Unknown action '+repr(action))
                    # A shader stall can consume a wall-clock timeout while
                    # Godot advances its animation by only one capped delta.
                    # Let the first affected draw complete before starting the
                    # settling timer. These frames/stalls stay IN the sample.
                    page.evaluate('()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))')
                    page.wait_for_timeout(phase.get('settleMs', 1200))
                    # Deliver an ending frame so a trailing stall is not dropped.
                    end = page.evaluate('()=>new Promise(resolve=>requestAnimationFrame(()=>resolve(window.__actionPerf.mark("phase-end"))))')
                    after = metrics(cdp)
                    row = {'name': phase['name'], 'startMs': start, 'endMs': end, 'inputs': inputs,
                           'expected': phase.get('expected', ''), 'visualReview': 'pending',
                           'cpu': {key+'Ms': (after.get(key,0)-before.get(key,0))*1000 for key in ['TaskDuration','ScriptDuration','LayoutDuration','RecalcStyleDuration']}}
                    row['cpu']['taskBusyFraction'] = row['cpu']['TaskDurationMs']/max(1,end-start)
                    run['phases'].append(row)
                    page.screenshot(path=str(folder/(slug+'-after.png')))
                    print(json.dumps({'run': run_index, 'phase': phase['name'], 'durationMs': end-start}), flush=True)
                page.wait_for_timeout(100)
                probe = page.evaluate('JSON.parse(JSON.stringify(window.__actionPerf))')
                run['startup'] = summarize(probe, 0, startup_end)
                run['loaderPhases'] = probe['phases']
                for row in run['phases']:
                    row.update(summarize(probe, row['startMs'], row['endMs']))
                (folder/'raw-probe.json').write_text(json.dumps(probe, ensure_ascii=False), encoding='utf-8')
                if args.cpu_profile:
                    profile = cdp.send('Profiler.stop')['profile']
                    (folder/'cpu-profile.json').write_text(json.dumps(profile), encoding='utf-8')
        except Exception as error:
            report['failure'] = str(error)
            try:
                probe = page.evaluate('JSON.parse(JSON.stringify(window.__actionPerf || null))')
                (out/'failure-probe.json').write_text(json.dumps(probe, ensure_ascii=False), encoding='utf-8')
                page.screenshot(path=str(out/'failure.png'), timeout=10000)
            except Exception as diagnostic_error:
                report['failureCaptureError'] = str(diagnostic_error)
        finally:
            report['collectionCompletedWithoutErrors'] = not report['failure'] and not report['errors']
            (out/'checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
            context.close()
            browser.close()
    return 0 if report['collectionCompletedWithoutErrors'] else 1


if __name__ == '__main__':
    sys.exit(main())

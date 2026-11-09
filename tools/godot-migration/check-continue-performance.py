"""Measure real Continue clicks after restoring isolated saved progress.

QA prepares the save and observes state. Timings are browser rAF intervals,
not GPU timer queries; WebGL call timing identifies synchronous preparation.
"""
import argparse, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--level", choices=["1-1","1-2"], default="1-1")
parser.add_argument("--base", default="http://localhost:4217/")
parser.add_argument("--output", default="docs/qa-godot-native/continue-performance")
parser.add_argument("--expect-prepared", action="store_true", help="Require no shader compilation/relinking or geometry rebuild on Continue.")
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)
initial = next(c["initial"]["snapshot"] for c in json.loads((ROOT / "godot/tests/fixtures/reference.json").read_text(encoding="utf-8"))["cases"] if c["name"] == "authored/" + args.level)
initial["growth"]["root"] = ["g:root:1:0"] if args.level == "1-1" else ["g:root:1:0","g:root:2:0","g:root:3:0","g:root:3:1"]

instrument = """(() => {
  window.__continueProbe = {active:false, calls:{}, frames:[], start:0, shown:null};
  const proto=WebGL2RenderingContext.prototype;
  for(const name of ['compileShader','linkProgram','texImage2D','texSubImage2D','bufferData','drawElements','drawArrays']) {
    const original=proto[name];
    proto[name]=function(...args) {
      const p=window.__continueProbe, start=performance.now();
      const value=original.apply(this,args);
      if(p.active) { const elapsed=performance.now()-start, row=p.calls[name]??={count:0,totalMs:0,maxMs:0}; row.count++;row.totalMs+=elapsed;row.maxMs=Math.max(row.maxMs,elapsed); }
      return value;
    };
  }
  window.addEventListener('pointerup', () => {
    const p=window.__continueProbe;
    if(p.armed){p.armed=false;p.active=true;p.start=performance.now();}
  },true);
  let last=0;
  function frame(now) {
    const p=window.__continueProbe;
    if(p.active) {
      p.frames.push(now-last);
      if(p.shown===null && window.__sporelightState?.homeActive===false) p.shown=performance.now()-p.start;
      if(now-p.start>1800){p.active=false;p.done=true;}
    }
    last=now; requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();"""

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport={"width":1280,"height":720})
    context.add_init_script(instrument)
    page = context.new_page()
    errors = []
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" or "SCRIPT ERROR:" in m.text else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(args.base + "?qa=1&home=1", wait_until="networkidle")
    page.wait_for_function("window.__sporelightState?.snapshot", timeout=120000)
    page.evaluate("s=>window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot:s,time:1200}))", initial)
    page.wait_for_timeout(800)
    page.evaluate("window.__sporelightRequest(JSON.stringify({type:'action',command:'home'}))")
    page.wait_for_timeout(1200)
    page.reload(wait_until="networkidle")
    page.wait_for_function("window.__sporelightState?.homeActive && window.__sporelightState?.hasActiveGame", timeout=120000)
    page.wait_for_selector("#status", state="detached", timeout=120000)
    page.wait_for_timeout(1200)
    rows = []
    for index in range(3):
        if index:
            page.evaluate("window.__sporelightRequest(JSON.stringify({type:'action',command:'home'}))")
            page.wait_for_function("window.__sporelightState?.homeActive")
            page.wait_for_timeout(800)
        state = page.evaluate("window.__sporelightState")
        render_before = state.get("render", {})
        if args.expect_prepared:
            assert render_before.get("viewportUpdateMode") == 0, "Home must not keep rendering the prepared garden."
        button = next(b for b in state["buttons"] if b.get("action") == "continue" and not b.get("disabled"))
        rect = button.get("visibleRect", [button["x"],button["y"],button["width"],button["height"]])
        page.evaluate("Object.assign(window.__continueProbe,{armed:true,active:false,done:false,calls:{},frames:[],shown:null})")
        page.mouse.click(rect[0]+rect[2]/2, rect[1]+rect[3]/2)
        page.wait_for_function("window.__continueProbe.done", timeout=30000)
        probe = page.evaluate("window.__continueProbe")
        intervals = sorted(probe["frames"])
        row = {"case":"first-saved-continue" if not index else "return-continue", "maxFrameMs":max(intervals), "p95FrameMs":intervals[int(len(intervals)*.95)], "framesOver50ms":sum(v>50 for v in intervals), "stateChangedMs":probe["shown"], "webgl":probe["calls"], "render":page.evaluate("window.__sporelightState?.render")}
        rows.append(row)
        print(json.dumps(row), flush=True)
        if args.expect_prepared:
            assert not probe["calls"].get("compileShader") and not probe["calls"].get("linkProgram"), "Continue must use prepared shader programs."
            assert row["render"]["meshRebuilds"] == render_before["meshRebuilds"], "Continue must reuse existing geometry."
        assert page.evaluate("!window.__sporelightState.homeActive && window.__sporelightState.worldVisible && !window.__sporelightState.paused")
    page.screenshot(path=str(out / "continued.png"))
    result = {"rows":rows,"errors":errors,"level":args.level,"scope":"Isolated saved level with grown roots; actual pointer Continue; browser rAF and synchronous WebGL instrumentation. Timing depends on browser/GPU and is not a device-wide guarantee."}
    (out / "checks.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    browser.close()
    assert not errors, errors

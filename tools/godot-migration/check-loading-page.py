"""Exercise the exported loader with real throttled files and controlled failures.
The two explicit Engine contract cases test unknown progress / downloaded-not-ready;
all slow, retry and entry cases use the actual exported engine and PCK.
"""
import argparse, json, mimetypes, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

p=argparse.ArgumentParser()
p.add_argument("--variant",default="loading-candidate")
p.add_argument("--output",default="docs/qa-godot-native/loading-page")
p.add_argument("--sizes",default="1280x720,390x844,320x568,568x320,594x462,2560x1440,3440x1440")
args=p.parse_args()
BUILD=(ROOT/"godot/build"/args.variant).resolve()
assert BUILD.is_relative_to((ROOT/"godot/build").resolve())
OUT=(ROOT/args.output).resolve();OUT.mkdir(parents=True,exist_ok=True)
metadata=json.loads((BUILD/"build.json").read_text(encoding="utf-8"))
RELEASE=metadata.get("webMode")=="release"
rows=[]

class Preview(BaseHTTPRequestHandler):
    def log_message(self,*unused): pass
    def do_GET(self):
        name=unquote(urlparse(self.path).path).lstrip("/") or "index.html"
        if name=="favicon.ico":
            self.send_response(204);self.end_headers();return
        mode=self.server.mode
        file=(BUILD/name).resolve()
        if not file.is_relative_to(BUILD) or not file.is_file():
            self.send_error(404);return
        if (mode=="script-error" and name=="index.js") or (mode=="pck-error" and name.endswith(".pck")):
            self.send_error(503,"Controlled loading test");return
        if mode in ["unknown-contract","opening-contract"] and name=="index.js":
            current="0,0" if mode=="unknown-contract" else "100,100"
            data=("window.Engine=class {static getMissingFeatures(){return [];} startGame(o){o.onProgress("+current+");return new Promise(()=>{});}};").encode()
        else: data=file.read_bytes()
        self.send_response(200)
        mime="application/wasm" if name.endswith(".wasm") else mimetypes.guess_type(name)[0] or "application/octet-stream"
        self.send_header("Content-Type",mime);self.send_header("Content-Length",str(len(data)))
        self.send_header("Cache-Control","no-store")
        self.send_header("Cross-Origin-Opener-Policy","same-origin")
        self.send_header("Cross-Origin-Embedder-Policy","require-corp")
        self.end_headers()
        try:
            if mode=="slow" and name.endswith((".wasm",".pck")):
                time.sleep(.4)
                for offset in range(0,len(data),524288):
                    self.wfile.write(data[offset:offset+524288]);self.wfile.flush();time.sleep(.08)
            else: self.wfile.write(data)
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError): pass

server=ThreadingHTTPServer(("127.0.0.1",0),Preview);server.daemon_threads=True;server.mode="slow"
threading.Thread(target=server.serve_forever,daemon=True).start()
BASE="http://127.0.0.1:"+str(server.server_port)+"/"

def run(browser,mode,size=(1280,720),js=True,reduced=False):
    server.mode=mode
    name=mode+"-"+str(size[0])+"x"+str(size[1])
    folder=OUT/name;folder.mkdir(parents=True,exist_ok=True)
    row={"mode":mode,"size":list(size),"engineContractMock":mode.endswith("-contract"),"errors":[]}
    context=browser.new_context(viewport={"width":size[0],"height":size[1]},java_script_enabled=js,reduced_motion="reduce" if reduced else "no-preference",device_scale_factor=1)
    page=context.new_page()
    page.on("pageerror",lambda e:row["errors"].append(str(e)))
    page.on("console",lambda m:row["errors"].append(m.text) if m.type=="error" else None)
    def shot(label): page.screenshot(path=str(folder/(label+".png")))
    def ready():
        page.wait_for_selector("#status",state="detached",timeout=90000)
        if RELEASE:
            assert page.evaluate("() => typeof window.__sporelightState==='undefined'&&typeof window.__sporelightRequest==='undefined'"),"release has no QA bridge"
        else:
            page.wait_for_function("() => window.__sporelightState?.homeActive",timeout=15000)
        assert page.locator("#status").count()==0
        assert page.evaluate("document.activeElement.id")== "canvas","keyboard focus reaches the actual game"
    try:
        page.goto(BASE+"?qa=1&home=1",wait_until="domcontentloaded",timeout=90000)
        if not js:
            page.locator(".no-script").wait_for(state="visible")
            shot("no-javascript")
            assert "JavaScript" in page.locator(".no-script").inner_text()
        elif mode=="slow":
            page.wait_for_function("() => {const p=document.querySelector('#status-progress');return p?.hasAttribute('value')&&p.value>0&&p.value<p.max*.9;}",timeout=30000)
            page.wait_for_function("() => [...document.images].every(i=>i.complete&&i.naturalWidth>0)")
            row["layout"]=page.evaluate("""() => {
                const c=document.querySelector('.loading-copy'),p=document.querySelector('#status-progress'),r=p.getBoundingClientRect(),b=c.getBoundingClientRect();
                const h=document.querySelector('.hero').getBoundingClientRect(),s=document.querySelector('.scenery').getBoundingClientRect(),l=document.querySelector('.brand').getBoundingClientRect();
                const overlap=Math.max(0,Math.min(l.right,b.right)-Math.max(l.left,b.left))*Math.max(0,Math.min(l.bottom,b.bottom)-Math.max(l.top,b.top));
                return {value:p.value,max:p.max,percent:document.querySelector('#load-percent').textContent,viewport:[innerWidth,innerHeight],progress:[r.x,r.y,r.width,r.height],copy:[b.x,b.y,b.width,b.height],copyOverflowX:c.scrollWidth>c.clientWidth+1,brandOverlap:overlap,footError:Math.abs(h.y+h.height*236/256-(s.y+s.height*642/720))};
            }""")
            v=row["layout"];x,y,w,h=v["progress"];cx,cy,cw,ch=v["copy"]
            assert v["value"]>0 and v["value"]<v["max"],"actual streamed engine bytes reported"
            assert v["percent"]==str(int(v["value"]/v["max"]*100))+"%","percentage matches real downloaded bytes"
            assert y>=cy and y+h<=cy+ch+1 and x>=0 and x+w<=size[0]+1,"progress is on screen without scrolling"
            assert not v["copyOverflowX"],"loading panel does not develop horizontal overflow"
            assert v["brandOverlap"]<1,"brand and loading text remain separate"
            assert v["footError"]<1,"hero retains the original scene foot registration"
            shot("loading")
            ready();shot("home")
            page.keyboard.press("Enter");page.wait_for_timeout(250);page.keyboard.press("Enter")
            if RELEASE:
                page.wait_for_timeout(700)
                row["entryScope"]="Actual release Enter navigation; named canvas screenshots require semantic visual review."
            else:
                page.wait_for_function("() => window.__sporelightState?.worldVisible&&!window.__sporelightState?.homeActive&&!window.__sporelightState?.paused",timeout=15000)
            shot("entered-level")
            assert not row["errors"],str(row["errors"])
        elif mode.endswith("-contract"):
            expected="opening" if mode=="opening-contract" else "preparing"
            page.wait_for_selector("#status[data-phase='"+expected+"']")
            page.wait_for_timeout(500)
            assert page.locator("#status").is_visible(),"download completion is not game readiness"
            if mode=="opening-contract":
                assert page.locator("#load-percent").inner_text()=="100%"
                assert "唤醒" in page.locator("#loading-label").inner_text()
                assert page.evaluate("() => {const c=document.querySelector('.loading-copy');return c.scrollWidth<=c.clientWidth+1;}"),"full progress has no horizontal scrollbar"
            else:
                assert page.locator("#status-progress").get_attribute("value") is None
                assert page.locator("#load-percent").inner_text()=="加载中"
                if reduced:
                    assert page.locator(".scene-orb").evaluate("e=>getComputedStyle(e).animationName")=="none"
            shot(expected)
        else:
            page.wait_for_selector("#status[data-phase='error']",timeout=45000)
            assert page.locator("#retry-button").is_visible()
            assert "微光" in page.locator("#status-heading").inner_text()
            shot("error")
            server.mode="fast"
            page.locator("#retry-button").click()
            ready();shot("retried-home")
        row["passed"]=True
    except Exception as e:
        row.update(passed=False,reason=str(e))
        shot("failure")
    finally:
        context.close();rows.append(row)
        (folder/"checks.json").write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding="utf-8")
        print(json.dumps({k:row.get(k) for k in ["mode","size","passed","reason"]},ensure_ascii=False),flush=True)

try:
    with sync_playwright() as p:
        browser=p.chromium.launch(channel="chrome",headless=True)
        for size in args.sizes.split(","):run(browser,"slow",tuple(map(int,size.split("x"))))
        run(browser,"unknown-contract",reduced=True)
        run(browser,"opening-contract")
        run(browser,"script-error");run(browser,"pck-error")
        run(browser,"no-js",js=False)
        browser.close()
finally: server.shutdown();server.server_close()
passed=bool(rows) and all(r["passed"] for r in rows)
(OUT/"checks.json").write_text(json.dumps({"passed":passed,"build":metadata,"results":rows,"scope":"Actual local throttled engine/PCK for slow and failure/retry cases. Two explicitly marked Engine contract mocks exercise unknown totals and 100%-not-ready; not GPU or hardware evidence."},ensure_ascii=False,indent=2),encoding="utf-8")
raise SystemExit(0 if passed else 1)

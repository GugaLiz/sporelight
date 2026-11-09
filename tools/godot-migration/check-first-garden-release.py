"""Play the same pointer sequence in debug and release; compare pixels.
Only the debug run reads QA. Release uses recorded visible button rectangles.
"""
import argparse, json, sys, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright
from PIL import Image, ImageChops, ImageStat

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--debug", default="http://localhost:4213/")
parser.add_argument("--release", default="http://localhost:4214/")
parser.add_argument("--output", default="docs/qa-godot-native/first-garden-art/release")
args = parser.parse_args()
OUT = ROOT / args.output
OUT.mkdir(parents=True, exist_ok=True)
reports, rectangles = [], {}

def current(page):
    page.wait_for_timeout(140)
    return page.evaluate("() => structuredClone(window.__sporelightState)")

def click(page, rect):
    page.mouse.click(rect[0]+rect[2]/2, rect[1]+rect[3]/2)
    page.wait_for_timeout(350)

def button(page, key, action=None, text=None, command=None):
    controls = current(page)["ui"]["controls"]
    item = next(c for c in controls if c["class"]=="Button" and
                (action is None or c.get("action")==action) and
                (text is None or text in c.get("text", "")) and
                (command is None or c.get("command_id")==command))
    rect = item["visibleRect"]
    assert rect[2]>30 and rect[3]>30, "visible button " + key
    rectangles[key] = rect
    click(page, rect)

def capture(page, mode, label):
    page.wait_for_timeout(450)
    page.screenshot(path=str(OUT/(mode+"-"+label+".png")))

def walk_to(page, mode, tile):
    # Fixed key durations depend on stair pace and platform spacing. Replay
    # real pointer targets instead, then verify the debug destination.
    key = "walk:" + tile
    if mode == "debug":
        target = next(t for t in current(page)["targets"] if t["id"] == tile)
        rectangles[key] = [target["x"] - 1, target["y"] - 1, 2, 2]
    click(page, rectangles[key])
    page.wait_for_timeout(1800)
    if mode == "debug":
        page.wait_for_function("tile => {const s=window.__sporelightState; return s?.snapshot.actors.luvie===tile && !s.moving;}", arg=tile, timeout=10000)

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    for mode, base in [("debug",args.debug), ("release",args.release)]:
        context = browser.new_context(viewport={"width":1280,"height":720}, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: errors.append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
        row = {"mode":mode}
        try:
            page.goto(base+("?qa=1&home=1&unlockAll=0" if mode=="debug" else ""), wait_until="networkidle", timeout=120000)
            page.wait_for_selector("#status", state="detached", timeout=90000)
            page.wait_for_timeout(700)
            if mode=="debug":
                button(page,"map",action="map")
                button(page,"first-level",text="1-1  ")
            else:
                assert page.evaluate("() => typeof window.__sporelightRequest==='undefined' && typeof window.__sporelightState==='undefined'"), "release has no QA bridge"
                click(page,rectangles["map"])
                click(page,rectangles["first-level"])
            capture(page,mode,"arrival")
            if mode=="debug":
                button(page,"root-options",action="primary")
                button(page,"east-seed",command="grow:root:right")
            else:
                click(page,rectangles["root-options"])
                click(page,rectangles["east-seed"])
            page.wait_for_timeout(3000)
            if mode == "debug":
                page.wait_for_function("window.__sporelightState?.snapshot.growth.root.includes('g:root:1:0') && !window.__sporelightState.moving", timeout=15000)
            capture(page,mode,"planted")
            for tile in ["f:3:0"]:
                walk_to(page, mode, tile)
            if mode=="debug":
                assert current(page)["snapshot"]["actors"]["luvie"] == "f:3:0", "approach reaches the old lower landing"
            for tile in ["f:3:-2"]:
                walk_to(page, mode, tile)
            capture(page,mode,"flower-bed")
            if mode=="debug":
                s=current(page)
                assert s["snapshot"]["actors"]["luvie"] == "f:3:-2", "walk climbed to the relocated flowerbed"
                assert abs(s["native"]["actors"]["luvie"]["position"][1] - 1.30) < 0.03
                assert s["snapshot"]["growth"]["root"]==["g:root:1:0"]
                assert not s["snapshot"]["collected"]
            page.keyboard.press("e")
            page.wait_for_timeout(2200)
            capture(page,mode,"complete")
            if mode=="debug":
                s=current(page)
                assert s["snapshot"]["completed"], "real E repaired flower bed"
                row["final"] = s["snapshot"]
            assert not errors, str(errors[:5])
            row["passed"] = True
        except Exception as e:
            row.update(passed=False, reason=str(e))
            page.screenshot(path=str(OUT/(mode+"-failure.png")))
        row["errors"]=errors
        reports.append(row)
        context.close()
        print(json.dumps({k:row.get(k) for k in ["mode","passed","reason"]}), flush=True)
    browser.close()

pixels=[]
if all(r.get("passed") for r in reports):
    for label in ["arrival","planted","flower-bed","complete"]:
        a=Image.open(OUT/("debug-"+label+".png")).convert("RGB").resize((320,180))
        b=Image.open(OUT/("release-"+label+".png")).convert("RGB").resize((320,180))
        error=sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
        pixels.append({"phase":label,"meanRGBError":error,"passed":error<5})
with urllib.request.urlopen(args.release+"__build.json") as response:
    build=json.load(response)
passed=all(r.get("passed") for r in reports) and len(pixels)==4 and all(r["passed"] for r in pixels)
(OUT/"checks.json").write_text(json.dumps({"passed":passed,"build":build,"results":reports,"pixels":pixels,"buttonRectangles":rectangles,"scope":"Release uses actual recorded pointer input and E interaction, has no QA bridge, and is compared against the same successful debug sequence. Pixel tolerance covers ambient particles and animation timing."},ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"passed":passed,"pixels":pixels}),flush=True)
raise SystemExit(0 if passed else 1)

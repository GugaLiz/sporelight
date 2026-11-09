"""Replay visible 1-2 controls in debug/release using isolated saved progress."""
import argparse, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright
from PIL import Image, ImageChops, ImageStat

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--debug", default="http://localhost:4217/")
parser.add_argument("--release", default="http://localhost:4216/")
parser.add_argument("--output", default="docs/qa-godot-native/second-garden/release")
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)
initial = next(c["initial"]["snapshot"] for c in json.loads((ROOT / "godot/tests/fixtures/reference.json").read_text(encoding="utf-8"))["cases"] if c["name"] == "authored/1-2")
rectangles, reports, storage = {}, [], {}

def state(page):
    page.wait_for_timeout(180)
    return page.evaluate("window.__sporelightState")

def control(page, mode, key, action=None, command=None):
    if mode == "debug":
        b = next(b for b in state(page)["buttons"] if not b.get("disabled") and
                 (action is None or b.get("action") == action) and
                 (command is None or b.get("command_id") == command))
        rectangles[key] = b.get("visibleRect", [b["x"], b["y"], b["width"], b["height"]])
    r = rectangles[key]
    page.mouse.click(r[0] + r[2] / 2, r[1] + r[3] / 2)
    page.wait_for_timeout(400)

def walk(page, mode, tile):
    key = "walk:" + tile
    if mode == "debug":
        t = next(t for t in state(page)["targets"] if t["id"] == tile)
        rectangles[key] = [t["x"], t["y"]]
    page.mouse.click(*rectangles[key])
    page.wait_for_timeout(4500)
    if mode == "debug":
        page.wait_for_function("id => window.__sporelightState.snapshot.actors.luvie === id && !window.__sporelightState.moving", arg=tile, timeout=10000)

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    for mode, base in [("debug", args.debug), ("release", args.release)]:
        options = {"viewport":{"width":1280,"height":720}}
        if mode == "release":
            # Godot persists user:// in IndexedDB, not localStorage. Copy only
            # this disposable test context, remapping its preview origin.
            for origin in storage["origins"]:
                origin["origin"] = args.release.rstrip("/")
            options["storage_state"] = storage
        context = browser.new_context(**options)
        page = context.new_page()
        errors, row = [], {"mode":mode}
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" or "SCRIPT ERROR:" in m.text else None)
        try:
            page.goto(base + ("?qa=1&home=1" if mode == "debug" else ""), wait_until="networkidle", timeout=120000)
            page.wait_for_selector("#status", state="detached", timeout=120000)
            if mode == "debug":
                page.wait_for_function("window.__sporelightState?.snapshot", timeout=120000)
                page.evaluate("s=>window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot:s,time:1200}))", initial)
                page.wait_for_timeout(800)
                page.evaluate("window.__sporelightRequest(JSON.stringify({type:'action',command:'home'}))")
                page.wait_for_timeout(1000)
                storage = context.storage_state(indexed_db=True)
            else:
                assert page.evaluate("typeof window.__sporelightState === 'undefined'"), "release must not expose QA"
                page.wait_for_timeout(1000)
            control(page, mode, "continue", action="continue")
            page.wait_for_timeout(1200)
            page.screenshot(path=str(out / (mode + "-arrival.png")))
            walk(page, mode, "f:1:1")
            for index, direction in enumerate(["up","right","right","down"]):
                control(page, mode, "options" + str(index), action="primary")
                control(page, mode, "grow" + str(index), command="grow:root:" + direction)
                page.wait_for_timeout(1200)
            page.screenshot(path=str(out / (mode + "-grown.png")))
            walk(page, mode, "f:4:1")
            page.screenshot(path=str(out / (mode + "-flowerbed.png")))
            page.keyboard.press("e")
            page.wait_for_timeout(2400)
            page.screenshot(path=str(out / (mode + "-complete.png")))
            if mode == "debug":
                assert state(page)["snapshot"]["completed"], "real input completes 1-2"
            assert not errors, errors
            row["passed"] = True
        except Exception as e:
            row.update(passed=False, reason=str(e))
            page.screenshot(path=str(out / (mode + "-failure.png")))
        row["errors"] = errors
        reports.append(row)
        context.close()
        print(json.dumps(row), flush=True)
        if not row["passed"]: break
    browser.close()

pixels = []
if len(reports) == 2 and all(r["passed"] for r in reports):
    for phase in ["arrival","grown","flowerbed","complete"]:
        a = Image.open(out / ("debug-" + phase + ".png")).convert("RGB").resize((320,180))
        b = Image.open(out / ("release-" + phase + ".png")).convert("RGB").resize((320,180))
        error = sum(ImageStat.Stat(ImageChops.difference(a,b)).mean) / 3
        pixels.append({"phase":phase,"meanRGBError":error,"passed":error < 5})
passed = len(pixels) == 4 and all(p["passed"] for p in pixels)
(out / "checks.json").write_text(json.dumps({"passed":passed,"results":reports,"pixels":pixels,"scope":"Isolated saved 1-2; debug records visible controls, release replays real input without QA; all four phases compared."}, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"passed":passed,"pixels":pixels}), flush=True)
raise SystemExit(0 if passed else 1)

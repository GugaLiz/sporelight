"""Real pointer/keyboard checks for the two-direction dock at four sizes."""
import argparse
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base", default="http://localhost:4215/")
parser.add_argument("--output", default="docs/qa-godot-native/first-garden-structure/ui")
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(args.base + "__build.json") as response:
    build = json.load(response)
fixture = json.loads((ROOT / "godot/tests/fixtures/reference.json").read_text(encoding="utf-8"))
initial = next(c["initial"]["snapshot"] for c in fixture["cases"] if c["name"] == "authored/1-1")
results = []

def state(page):
    return page.evaluate("() => structuredClone(window.__sporelightState)")

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    for width, height in [(1280, 720), (390, 844), (568, 320), (320, 568)]:
        context = browser.new_context(viewport={"width": width, "height": height}, has_touch=width < 600)
        page = context.new_page()
        row = {"size": [width, height], "errors": []}
        page.on("pageerror", lambda error: row["errors"].append(str(error)))
        page.on("console", lambda m: row["errors"].append(m.text) if m.type == "error" else None)
        try:
            page.goto(args.base + "?qa=1", wait_until="networkidle", timeout=120000)
            page.wait_for_function("() => window.__sporelightState?.snapshot", timeout=90000)
            page.evaluate("snapshot => window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot,time:1200}))", initial)
            page.wait_for_function("() => window.__sporelightState?.snapshot.levelId==='1-1' && !window.__sporelightState.homeActive")
            page.wait_for_timeout(500)
            primary = next(c for c in state(page)["ui"]["controls"] if c.get("action") == "primary")
            x, y, w, h = primary["visibleRect"]
            if width < 600:
                page.touchscreen.tap(x + w/2, y + h/2)
            else:
                page.mouse.click(x + w/2, y + h/2)
            page.wait_for_timeout(500)
            choices = [c for c in state(page)["ui"]["controls"] if c.get("command_id", "").startswith("grow:root:")]
            assert len(choices) == 2, "Both legal directions are shown"
            for button in choices:
                rect = button["visibleRect"]
                assert rect[2] >= 100 and rect[3] >= 43, "Complete touchable direction: " + str(button)
                assert rect[0] >= 0 and rect[1] >= 0 and rect[0] + rect[2] <= width + 1 and rect[1] + rect[3] <= height + 1
            assert abs(choices[0]["visibleRect"][1] - choices[1]["visibleRect"][1]) <= 1, "Directions share one row"
            page.screenshot(path=str(out / f"{width}x{height}-choices.png"))
            page.keyboard.press("Escape")
            page.wait_for_timeout(250)
            assert not state(page)["snapshot"]["growth"]["root"], "Cancel does not plant"
            page.keyboard.press("e")
            page.wait_for_timeout(250)
            # Real directional selection, then confirmation through the context.
            east = next(c for c in state(page)["ui"]["controls"] if c.get("command_id") == "grow:root:right")
            x, y, w, h = east["visibleRect"]
            page.mouse.click(x + w/2, y + h/2)
            page.wait_for_function("() => window.__sporelightState.snapshot.growth.root.includes('g:root:1:0')", timeout=15000)
            page.wait_for_timeout(700)
            page.screenshot(path=str(out / f"{width}x{height}-planted.png"))
            row["keyboard"] = []
            for keys, expected in [(["Tab"], "g:root:0:1"), (["Tab", "Shift+Tab"], "g:root:1:0"), (["Tab", "Tab"], "g:root:1:0"), (["Shift+Tab"], "g:root:0:1")]:
                page.evaluate("snapshot => window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot,time:1200}))", initial)
                page.wait_for_function("() => !window.__sporelightState.moving && window.__sporelightState.snapshot.growth.root.length===0")
                page.wait_for_timeout(350)
                page.keyboard.press("e")
                page.wait_for_timeout(250)
                for key in keys:
                    page.keyboard.press(key)
                    page.wait_for_timeout(100)
                assert not state(page)["snapshot"]["growth"]["root"], "Tab changes selection without planting"
                page.keyboard.press("Enter")
                page.wait_for_function("target => window.__sporelightState.snapshot.growth.root.includes(target)", arg=expected, timeout=15000)
                page.wait_for_timeout(600)
                assert state(page)["snapshot"]["growth"]["root"] == [expected], "Enter confirms the selected direction exactly once"
                row["keyboard"].append({"keys": keys + ["Enter"], "growth": expected, "passed": True})
            assert not row["errors"], str(row["errors"][:3])
            row["passed"] = True
        except Exception as error:
            row.update(passed=False, reason=str(error))
            page.screenshot(path=str(out / f"{width}x{height}-failure.png"))
        results.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        context.close()
    browser.close()
passed = all(row["passed"] for row in results)
(out / "checks.json").write_text(json.dumps({"passed": passed, "build": build, "results": results}, ensure_ascii=False, indent=2), encoding="utf-8")
raise SystemExit(0 if passed else 1)

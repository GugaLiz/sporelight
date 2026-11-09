"""Prepare isolated garden states, then click/tap the visible seedbed choices."""
import argparse
import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument("--base", default="http://localhost:4217/")
parser.add_argument("--output", default="docs/qa-godot-native/growth-anchor-browser")
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)
fixtures = json.loads((ROOT / "godot/tests/fixtures/reference.json").read_text(encoding="utf-8"))
initial = {c["levelId"]: c["initial"]["snapshot"] for c in fixtures["cases"] if c["name"].startswith("authored/")}
results = []

def state(page):
    return page.evaluate("() => window.__sporelightState")

def settle(page):
    sequence = state(page)["qaSequence"]
    page.wait_for_function("n => window.__sporelightState.qaSequence > n+1 && !window.__sporelightState.moving", arg=sequence, timeout=20000)
    return state(page)

def prepare(page, level):
    snapshot = copy.deepcopy(initial[level])
    if level == "1-2":
        snapshot["actors"]["luvie"] = "f:1:1"
    sequence = state(page)["qaSequence"]
    page.evaluate("snapshot => window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot,time:1200}))", snapshot)
    page.wait_for_function("v => window.__sporelightState.qaSequence > v.n && !window.__sporelightState.homeActive && window.__sporelightState.snapshot.levelId === v.level", arg={"n": sequence, "level": level})
    return settle(page)

def click_choice(page, choice, touch):
    canvas = page.locator("#canvas")
    box = canvas.bounding_box()
    backing = canvas.evaluate("e => [e.width,e.height]")
    x = box["x"] + choice["x"] * box["width"] / backing[0]
    y = box["y"] + choice["y"] * box["height"] / backing[1]
    if touch:
        page.touchscreen.tap(x, y)
    else:
        page.mouse.click(x, y)

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    try:
        for width, height in [(1280, 720), (844, 390)]:
            touch = width < 1000
            context = browser.new_context(viewport={"width": width, "height": height}, has_touch=touch, device_scale_factor=1)
            page = context.new_page()
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(args.base + "?qa=1")
            page.wait_for_load_state("networkidle")
            page.wait_for_function("() => window.__sporelightState?.snapshot", timeout=120000)
            for level, routes in [("1-1", [["right"], ["down"]]), ("1-2", [["up", "right", "right", "down"], ["down", "right", "right", "up"]])]:
                for route in routes:
                    s = prepare(page, level)
                    label = f"{level}-{width}x{height}-{route[0]}"
                    assert len(s["growthChoices"]) == 2, (label, s["growthChoices"])
                    page.screenshot(path=str(out / (label + "-before.png")))
                    selected = []
                    for direction in route:
                        choice = next(c for c in s["growthChoices"] if c["id"] == "grow:root:" + direction)
                        distance = ((choice["x"]-choice["anchorX"])**2 + (choice["y"]-choice["anchorY"])**2)**0.5
                        if level == "1-1":
                            assert choice["placement"] == "seedbed" and 49.9 <= distance <= 64.1, (label, "seedbed-relative spacing", distance)
                        else:
                            assert choice["placement"] == "socket" and distance < 0.01, (label, "actual next planting socket", choice)
                            if selected:
                                last = selected[-1]
                                assert ((choice["x"]-last["x"])**2+(choice["y"]-last["y"])**2)**0.5 > 20, "successive root segments must move the next planting location"
                        before = list(s["snapshot"]["growth"]["root"])
                        click_choice(page, choice, touch)
                        page.wait_for_function("v => {const s=window.__sporelightState; return !s.moving && s.snapshot.growth.root.length===v.length && s.snapshot.growth.root.at(-1)===v.target;}", arg={"length": len(before)+1, "target": choice["target"]}, timeout=15000)
                        s = settle(page)
                        assert s["snapshot"]["growth"]["root"] == before + [choice["target"]], "one tap must commit exactly one chosen segment"
                        selected.append(choice)
                        if level == "1-2":
                            page.screenshot(path=str(out / (label + f"-segment-{len(selected)}.png")))
                    assert not s["growthChoices"], "spent seed hides choices"
                    page.screenshot(path=str(out / (label + "-after.png")))
                    results.append({"label": label, "passed": True, "touch": touch, "selected": selected, "growth": s["snapshot"]["growth"]})
                    print(label + " passed", flush=True)
            assert not errors, errors
            context.close()
    finally:
        browser.close()
        (out / "checks.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

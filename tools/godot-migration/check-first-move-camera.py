"""Enter through the real menu and verify that the first support crossing cannot reframe the map."""
import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base", default="http://localhost:4217/")
parser.add_argument("--output", default="docs/qa-godot-native/first-move-camera/browser")
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)


def state(page):
    return page.evaluate("() => structuredClone(window.__sporelightState)")


def click_button(page, **match):
    controls = state(page)["ui"]["controls"]
    item = next(c for c in controls if c["class"] == "Button" and
                all(value in str(c.get(key, "")) for key, value in match.items()))
    x, y, w, h = item["visibleRect"]
    assert w > 20 and h > 20
    page.mouse.click(x + w / 2, y + h / 2)
    page.wait_for_timeout(450)


def measure_first_move(page, label, desktop):
    page.wait_for_timeout(600)
    initial = state(page)
    page.evaluate("""() => {
        window.cameraSamples = [];
        window.cameraTimer = setInterval(() => {
            const s = window.__sporelightState;
            cameraSamples.push({sequence:s.qaSequence, origin:s.origin,
                scale:s.scale, safe:s.safeRect, actors:s.snapshot.actors,
                position:s.native.actors.luvie.position});
        }, 25);
    }""")
    page.screenshot(path=str(out / (label + "-arrival.png")))
    page.wait_for_timeout(300)
    page.keyboard.down("ArrowLeft")
    page.wait_for_timeout(400)
    page.keyboard.up("ArrowLeft")
    page.wait_for_timeout(900)
    samples = page.evaluate("() => {clearInterval(cameraTimer); return cameraSamples}")
    (out / (label + "-samples.json")).write_text(json.dumps({"initial": initial, "samples": samples, "final": state(page)}, ensure_ascii=False, indent=2), encoding="utf-8")
    page.screenshot(path=str(out / (label + "-moved.png")))
    assert samples and samples[-1]["actors"]["luvie"] != initial["snapshot"]["actors"]["luvie"], "real input crosses a tile"
    assert all(s["safe"] == initial["safeRect"] for s in samples), "movement must not change HUD safe rect"
    assert all(abs(s["scale"] - initial["scale"]) < 0.0001 for s in samples), "movement must not change zoom"
    if desktop:
        assert all(math.dist(s["origin"], initial["origin"]) < 0.1 for s in samples), "fixed desktop camera must not jump"
    else:
        assert math.dist(samples[-1]["origin"], initial["origin"]) > 5, "small-screen camera still follows the actor"
    return {"label": label, "initial": {k: initial[k] for k in ["origin", "scale", "safeRect"]}, "samples": samples}


reports = []
with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    for width, height in [(1280, 720), (390, 844), (568, 320)]:
        label = f"{width}x{height}"
        context = browser.new_context(viewport={"width": width, "height": height}, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" or "SCRIPT ERROR:" in m.text else None)
        result = {"size": label, "passed": False, "runs": []}
        try:
            page.goto(args.base + "?qa=1&home=1&unlockAll=0", wait_until="networkidle", timeout=120000)
            page.wait_for_selector("#status", state="detached", timeout=90000)
            page.wait_for_timeout(700)
            click_button(page, action="map")
            click_button(page, text="1-1  ")
            result["runs"].append(measure_first_move(page, label, width >= 650))
            # Changing the viewport must still update framing while stationary.
            new_width = width + 40
            page.set_viewport_size({"width": new_width, "height": height + 40})
            page.wait_for_timeout(700)
            assert state(page)["safeRect"] != result["runs"][0]["initial"]["safeRect"], "resize refreshes camera layout without movement"
            result["runs"].append(measure_first_move(page, label + "-resized", new_width >= 650))
            assert not errors, str(errors[:5])
            result["passed"] = True
        except Exception as e:
            result["reason"] = str(e)
            page.screenshot(path=str(out / (label + "-failure.png")))
        result["errors"] = errors
        reports.append(result)
        context.close()
        print(json.dumps({k: result[k] for k in result if k != "runs"}), flush=True)
    browser.close()
passed = all(r["passed"] for r in reports)
(out / "checks.json").write_text(json.dumps({"passed": passed, "results": reports}, ensure_ascii=False, indent=2), encoding="utf-8")
raise SystemExit(0 if passed else 1)

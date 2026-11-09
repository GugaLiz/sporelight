"""Verify held walking advances through both halves of the existing side gait."""
import json
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright
OUT = ROOT / "docs/qa-godot-native/walk-cycle/browser"
OUT.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 720})
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" or "SCRIPT ERROR:" in m.text else None)
    page.goto("http://localhost:4217/?qa=1&level=1-1", wait_until="networkidle", timeout=120000)
    page.wait_for_selector("#status", state="detached", timeout=90000)
    page.wait_for_timeout(1000)
    page.keyboard.press("e")
    page.wait_for_timeout(250)
    controls = page.evaluate("window.__sporelightState.ui.controls")
    choice = next(c for c in controls if c.get("command_id") == "grow:root:right")
    x, y, w, h = choice["visibleRect"]
    page.mouse.click(x + w / 2, y + h / 2)
    page.wait_for_timeout(900)
    page.evaluate("""() => {
        window.walkSamples=[];
        window.walkTimer=setInterval(()=>{
            const s=window.__sporelightState;
            walkSamples.push({actor:s.character.luvie, position:s.native.actors.luvie.position});
        },25);
    }""")
    for direction in ["Right", "Left"]:
        page.keyboard.down("Arrow" + direction)
        for index in range(10):
            page.wait_for_timeout(65)
            page.screenshot(path=str(OUT / f"{direction}-{index:02}.png"))
        page.keyboard.up("Arrow" + direction)
        page.wait_for_timeout(120)
    page.wait_for_timeout(300)
    samples = page.evaluate("() => {clearInterval(walkTimer);return walkSamples}")
    final = page.evaluate("window.__sporelightState.character.luvie")
    frames = {direction: sorted({s["actor"]["frame"] for s in samples if s["actor"]["clip"] == "walk_" + direction}) for direction in ["left", "right"]}
    passed = all(len(f) >= 8 and min(f) < 3 and max(f) > 8 for f in frames.values()) and final["clip"].startswith("idle_") and not errors
    (OUT / "checks.json").write_text(json.dumps({"passed":passed,"frames":frames,"final":final,"errors":errors,"samples":samples},ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"passed":passed,"frames":frames,"errors":errors}))
    browser.close()
    raise SystemExit(0 if passed else 1)

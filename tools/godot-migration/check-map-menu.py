"""Real map menu clicks, scroll bounds, focus/hover pixels and return paths."""
import argparse
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base", default="http://localhost:4201/")
parser.add_argument("--output", default="docs/qa-godot-native/map-buttons/map")
parser.add_argument("--sizes", default="1280x720,390x844,320x568,568x320,594x462,2560x1440,3440x1440")
args = parser.parse_args()
OUT = ROOT / args.output
OUT.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(args.base + "__build.json") as response:
    build = json.load(response)
results = []


def state(page):
    page.wait_for_timeout(120)
    return page.evaluate("() => structuredClone(window.__sporelightState)")


def controls(page):
    return state(page)["ui"]["controls"]


def point(page, rect):
    box = page.locator("#canvas").bounding_box()
    backing = page.locator("#canvas").evaluate("c => [c.width,c.height]")
    return [box["x"] + (rect[0] + rect[2] / 2) * box["width"] / backing[0], box["y"] + (rect[1] + rect[3] / 2) * box["height"] / backing[1]]


def pick(page, text=None, prefix=None, action=None):
    for attempt in range(40):
        entries = controls(page)
        item = next((c for c in entries if c["class"] == "Button" and (text is None or c.get("text") == text) and (prefix is None or c.get("text", "").startswith(prefix)) and (action is None or c.get("action") == action)), None)
        if item is None and action == "map" and not any(c["class"] == "ScrollContainer" for c in entries):
            item = next((c for c in entries if c["class"] == "Button" and c.get("text") == "地图"), None)
        if item and item["visibleRect"][2] > 36 and item["visibleRect"][3] >= min(40, item["height"]):
            return item
        if item and item.get("disabled") and item["visibleRect"][2] > 36 and item["visibleRect"][3] > 20:
            return item
        scroll = next(c for c in entries if c["class"] == "ScrollContainer")
        r = scroll["visibleRect"]
        direction = (-1 if item["y"] < r[1] else 1) if item else (1 if attempt % 20 < 10 else -1)
        page.mouse.move(*point(page, r))
        page.mouse.wheel(0, direction * 200)
        page.wait_for_timeout(160)
    raise AssertionError("Not reachable: " + str([text, prefix, action]))


def click(page, **query):
    item = pick(page, **query)
    assert not item.get("disabled"), str(query)
    page.mouse.click(*point(page, item["visibleRect"]))


def map_controls(page):
    return [c for c in controls(page) if "/MapFrame/" in c["path"]]


def run(browser, size, dpr=1):
    label = f"{size[0]}x{size[1]}-dpr{dpr:g}"
    folder = OUT / label
    folder.mkdir(parents=True, exist_ok=True)
    row = {"size": list(size), "dpr": dpr, "errors": []}
    context = browser.new_context(viewport={"width": size[0], "height": size[1]}, device_scale_factor=dpr)
    page = context.new_page()
    page.on("pageerror", lambda e: row["errors"].append(str(e)))
    page.on("console", lambda m: row["errors"].append(m.text) if m.type == "error" or "SCRIPT ERROR:" in m.text else None)
    try:
        page.goto(args.base + "?qa=1&home=1&unlockAll=0", wait_until="networkidle")
        page.wait_for_selector("#status", state="detached", timeout=90000)
        click(page, action="map")
        assert map_controls(page), "real map frame is visible"
        page.wait_for_function("() => window.__sporelightState?.buttons.some(b=>b.text.startsWith('1-1  ')&&b.visibleRect?.[3]>=49)", timeout=5000)
        page.screenshot(path=str(folder / "map-top.png"), scale="css")
        initial = state(page)["snapshot"]
        first = pick(page, prefix="1-1  ")
        locked = pick(page, prefix="1-2  ")
        assert not first["disabled"] and locked["disabled"], "authored unlock status"
        page.mouse.click(*point(page, locked["visibleRect"]))
        assert state(page)["snapshot"] == initial and map_controls(page), "locked click cannot enter a level or mutate the puzzle"
        before = {c["name"] + c.get("text", ""): c["visibleRect"] for c in map_controls(page) if "/MapUtilities/" in c["path"] or "/MapReturnActions/" in c["path"] or c.get("text") == "花园地图"}
        assert before
        for item in map_controls(page):
            if "/MapUtilities/" in item["path"] and item["class"] == "Button":
                assert item["width"] >= 44 and item["height"] >= 44
                assert item["visibleRect"][2] >= item["width"] - 0.1, "utility is not clipped"
        cloud = pick(page, prefix="cloud-1  ")
        assert not cloud["disabled"], "independent garden remains playable"
        page.screenshot(path=str(folder / "map-scrolled.png"), scale="css")
        after = {c["name"] + c.get("text", ""): c["visibleRect"] for c in map_controls(page) if "/MapUtilities/" in c["path"] or "/MapReturnActions/" in c["path"] or c.get("text") == "花园地图"}
        assert before == after, "title, tools and return actions remain fixed while chapters scroll"
        scroll = next(c for c in controls(page) if c["class"] == "ScrollContainer")
        sx, sy, sw, sh = scroll["visibleRect"]
        assert sw > 100 and sh >= 70 / dpr, "usable chapter viewport"
        click(page, text="设置")
        page.keyboard.press("Escape")
        assert map_controls(page), "settings returns to originating map"
        for text in ["图鉴", "花园纪事", "导入 / 导出旅程"]:
            click(page, text=text)
            page.keyboard.press("Escape")
            assert map_controls(page), text + " returns to map"
        # Open a real run, turn off cover animation through the real preference,
        # and return home. The map remains unchanged by the held-still setting.
        click(page, prefix="1-1  ")
        page.wait_for_function("() => window.__sporelightState?.worldVisible&&!window.__sporelightState.paused")
        page.keyboard.press("Escape")
        page.wait_for_function("() => window.__sporelightState?.paused")
        page.wait_for_timeout(120)
        for attempt in range(25):
            toggle = next(c for c in controls(page) if c.get("setting_id") == "lowMotion")
            if toggle["visibleRect"][3] > 25:
                page.mouse.click(*point(page, toggle["visibleRect"]))
                break
            scroll = next(c for c in controls(page) if c["class"] == "ScrollContainer")
            page.mouse.move(*point(page, scroll["visibleRect"]))
            page.mouse.wheel(0, 200)
        assert state(page)["settings"]["lowMotion"], "real reduce-motion toggle applied"
        page.keyboard.press("Escape")
        page.wait_for_function("() => !window.__sporelightState?.paused")
        page.wait_for_timeout(180)
        click(page, action="map")
        page.wait_for_timeout(180)
        # The first Enter must select a level, not the fixed toolbar.
        page.keyboard.press("Enter")
        page.wait_for_function("() => window.__sporelightState?.worldVisible&&!window.__sporelightState.paused")
        page.keyboard.press("Escape")
        page.wait_for_function("() => window.__sporelightState?.paused")
        page.keyboard.press("Escape")
        page.wait_for_function("() => !window.__sporelightState?.paused")
        click(page, action="map")
        item = pick(page, prefix="1-1  ")
        page.mouse.move(1, 1)
        page.wait_for_timeout(100)
        rect = item["visibleRect"]
        backing = page.locator("#canvas").evaluate("c => [c.width,c.height]")
        box = page.locator("#canvas").bounding_box()
        clip = {"x": rect[0] * box["width"] / backing[0], "y": rect[1] * box["height"] / backing[1], "width": rect[2] * box["width"] / backing[0], "height": rect[3] * box["height"] / backing[1]}
        focused = page.screenshot(path=str(folder / "level-focused.png"), clip=clip, scale="css")
        # Move focus to a fixed toolbar entry, outside the chapter scroller.
        # Tab can otherwise focus an offscreen enabled cloud level and scroll
        # the list, which would compare different rows at the same coordinates.
        # Shift+Tab reaches the preceding fixed utility, rather than a later
        # offscreen cloud level. The chapter scroller therefore stays still.
        page.keyboard.press("Shift+Tab")
        item = pick(page, prefix="1-1  ")
        rect = item["visibleRect"]
        page.mouse.move(*point(page, rect))
        page.wait_for_timeout(120)
        hovered = page.screenshot(path=str(folder / "level-hovered.png"), clip=clip, scale="css")
        assert focused == hovered, "real focused-level and hovered-level pixels match"
        assert state(page)["snapshot"]["growth"] == initial["growth"], "menu navigation retains seed rules and state"
        assert not row["errors"], str(row["errors"])
        row.update(passed=True, focusMatchesHover=True, fixedRegions=before)
    except Exception as e:
        import traceback
        row.update(passed=False, reason=str(e), traceback=traceback.format_exc())
        page.screenshot(path=str(folder / "failure.png"), scale="css")
    finally:
        context.close()
    (folder / "checks.json").write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding="utf-8")
    results.append(row)
    print(json.dumps({k: row.get(k) for k in ["size", "dpr", "passed", "reason"]}), flush=True)


with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    for size in args.sizes.split(","):
        run(browser, tuple(map(int, size.split("x"))))
    run(browser, (1280, 720), 1.25)
    browser.close()
passed = bool(results) and all(r["passed"] for r in results)
(OUT / "checks.json").write_text(json.dumps({"passed": passed, "build": build, "results": results, "scope": "Actual isolated browser input, fixed-region geometry and held-still focus/hover PNG equality. Authored unlock restrictions remain active. Simulated viewports/DPR are not physical-device certification."}, ensure_ascii=False, indent=2), encoding="utf-8")
raise SystemExit(0 if passed else 1)

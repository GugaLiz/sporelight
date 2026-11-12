"""Real illustrated-map selection, unlocks, chapter navigation and return paths."""
import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base", default="http://localhost:4201/")
parser.add_argument("--output", default="docs/qa-godot-native/map-buttons/map")
parser.add_argument("--sizes", default="1280x720,844x390,390x844,320x568,568x320,594x462,2560x1440,3440x1440")
parser.add_argument("--touch", action="store_true")
args = parser.parse_args()
OUT = ROOT / args.output
OUT.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(args.base.rstrip("/") + "/__build.json") as response:
    build = json.load(response)
results = []


def state(page):
    page.wait_for_timeout(120)
    return page.evaluate("() => structuredClone(window.__sporelightState)")


def controls(page):
    return state(page)["ui"]["controls"]


def css_rect(page, rect):
    box = page.locator("#canvas").bounding_box()
    backing = page.locator("#canvas").evaluate("c => [c.width,c.height]")
    return {"x": box["x"] + rect[0] * box["width"] / backing[0],
            "y": box["y"] + rect[1] * box["height"] / backing[1],
            "width": rect[2] * box["width"] / backing[0],
            "height": rect[3] * box["height"] / backing[1]}


def point(page, rect):
    r = css_rect(page, rect)
    return [r["x"] + r["width"] / 2, r["y"] + r["height"] / 2]


def pick(page, text=None, action=None, suffix=None):
    for attempt in range(30):
        entries = controls(page)
        matches = [c for c in entries if c["class"] == "Button"
                   and (text is None or c.get("text") == text)
                   and (action is None or c.get("action") == action)
                   and (suffix is None or c.get("path", "").endswith(suffix))]
        if not matches and action == "map":
            matches = [c for c in entries if c["class"] == "Button" and c.get("text") == "地图"]
        for item in sorted(matches, key=lambda c: bool(c.get("disabled"))):
            if item["visibleRect"][2] >= 20 and item["visibleRect"][3] >= 20:
                return item
        # Child pages scroll; the illustrated map has no old chapter-list row.
        scrolls = [c for c in entries if c["class"] == "ScrollContainer"
                   and c.get("visibleRect", [0, 0, 0, 0])[3] > 25]
        if scrolls:
            rect = scrolls[-1]["visibleRect"]
            direction = -1 if matches and matches[-1]["y"] < rect[1] else 1 if attempt % 20 < 10 else -1
            page.mouse.move(*point(page, rect))
            page.mouse.wheel(0, direction * 200)
        page.wait_for_timeout(100)
    raise AssertionError("Not reachable: " + str([text, action, suffix]))


def click(page, touch=False, **query):
    item = pick(page, **query)
    assert not item.get("disabled"), str(query)
    (page.touchscreen.tap if touch else page.mouse.click)(*point(page, item["visibleRect"]))
    return item


def map_controls(page):
    return [c for c in controls(page) if "/IllustratedChapterMap/" in c["path"]]


def select_chapter(page, chapter, touch=False):
    click(page, touch, action="world_overview")
    page.wait_for_function("() => window.__sporelightState?.buttons.some(b=>b.path.includes('/WorldOverview/'))")
    click(page, touch, suffix="/ChapterPreview_" + chapter)


def selected(page, level):
    return any("/MapSelectedCard/" in c["path"] and c.get("text", "").startswith(level + " ·")
               for c in map_controls(page))


def run(browser, requested_size, dpr=1):
    label = f"{requested_size[0]}x{requested_size[1]}-dpr{dpr:g}"
    folder = OUT / label
    folder.mkdir(parents=True, exist_ok=True)
    portrait = requested_size[1] > requested_size[0]
    touch = args.touch or portrait
    row = {"size": list(requested_size), "dpr": dpr, "touch": touch, "errors": []}
    context = browser.new_context(viewport={"width": requested_size[0], "height": requested_size[1]},
                                  device_scale_factor=dpr, has_touch=touch)
    page = context.new_page()
    page.on("pageerror", lambda e: row["errors"].append(str(e)))
    page.on("console", lambda m: row["errors"].append(m.text) if m.type == "error" or "SCRIPT ERROR:" in m.text else None)
    try:
        page.goto(args.base.rstrip("/") + "/?qa=1&home=1&unlockAll=0", wait_until="networkidle")
        page.wait_for_selector("#status", state="detached", timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot", timeout=120000)
        if portrait:
            page.wait_for_function("() => window.__sporelightPortraitBlocked === true")
            before = state(page)["snapshot"]
            page.screenshot(path=str(folder / "portrait-blocked.png"), scale="css")
            page.touchscreen.tap(requested_size[0] / 2, requested_size[1] / 2)
            assert state(page)["snapshot"] == before, "portrait gate prevents game input"
            page.set_viewport_size({"width": requested_size[1], "height": requested_size[0]})
            page.wait_for_function("() => window.__sporelightPortraitBlocked === false")
            row["portraitGateVerified"] = True
        row["testedViewport"] = page.viewport_size
        click(page, touch, action="map")
        assert selected(page, "1-1"), "first journey selects the actual saved first level"
        initial = state(page)["snapshot"]
        page.screenshot(path=str(folder / "map-first.png"), scale="css")
        assert len([c for c in map_controls(page) if "/MapMarker_" in c["path"] and c["class"] == "Button"]) == 4
        assert not pick(page, suffix="/MapEnterLevel")["disabled"]
        click(page, touch, suffix="/MapMarker_1-2")
        locked = pick(page, suffix="/MapEnterLevel")
        assert locked["disabled"] and selected(page, "1-2"), "locked landmark is inspectable without entering"
        (page.touchscreen.tap if touch else page.mouse.click)(*point(page, locked["visibleRect"]))
        assert state(page)["snapshot"] == initial and selected(page, "1-2"), "locked click preserves puzzle"
        page.screenshot(path=str(folder / "map-locked.png"), scale="css")
        for item in map_controls(page):
            if item["class"] == "Button":
                rect = css_rect(page, item["visibleRect"])
                assert rect["width"] >= 43.5 and rect["height"] >= 43.5, "map hit area remains 44 CSS pixels"
        click(page, touch, action="world_overview")
        assert all("/WorldOverview/" in c["path"] or c.get("disabled")
                   for c in map_controls(page) if c["class"] == "Button"), "overview owns interaction; live backdrop stays inert"
        page.screenshot(path=str(folder / "world-overview.png"), scale="css")
        page.keyboard.press("Escape")
        assert selected(page, "1-2"), "Escape closes overview without losing selection"
        select_chapter(page, "pond", touch)
        assert selected(page, "2-1") and pick(page, suffix="/MapEnterLevel")["disabled"], "chapter preview cannot bypass unlock"
        page.screenshot(path=str(folder / "pond-locked.png"), scale="css")
        select_chapter(page, "cloud", touch)
        assert selected(page, "cloud-1") and not pick(page, suffix="/MapEnterLevel")["disabled"], "independent cloud garden is playable"
        click(page, touch, suffix="/MapMarker_cloud-2")
        for action in ["settings", "gallery", "journal", "save"]:
            click(page, touch, action=action)
            page.keyboard.press("Escape")
            assert selected(page, "cloud-2"), action + " returns to the same chapter and landmark"
        story = next(c for c in map_controls(page) if c["class"] == "Button" and c.get("text", "").startswith("口袋里的小事"))
        (page.touchscreen.tap if touch else page.mouse.click)(*point(page, story["visibleRect"]))
        page.keyboard.press("Escape")
        assert selected(page, "cloud-2"), "cloud story restores selected landmark"
        click(page, touch, suffix="/MapEnterLevel")
        page.wait_for_function("() => {const s=window.__sporelightState;return s?.worldVisible&&!s.paused&&s.snapshot.levelId==='cloud-2';}")
        click(page, touch, action="map")
        assert map_controls(page), "map reopens from the actual cloud game"
        select_chapter(page, "valley", touch)
        click(page, touch, suffix="/MapMarker_1-1")
        # The map is static; compare actual focused/hovered entry pixels.
        page.mouse.move(1, 1)
        page.wait_for_timeout(250)
        item = pick(page, suffix="/MapEnterLevel")
        clip = css_rect(page, item["visibleRect"])
        focused = page.screenshot(path=str(folder / "level-focused.png"), clip=clip, scale="css")
        page.keyboard.press("Shift+Tab")
        page.mouse.move(*point(page, item["visibleRect"]))
        page.wait_for_timeout(150)
        hovered = page.screenshot(path=str(folder / "level-hovered.png"), clip=clip, scale="css")
        assert focused == hovered, "focused and hovered entry pixels match"
        previous_instance = item["instanceId"]
        previous_sequence = state(page)["qaSequence"]
        click(page, touch, suffix="/MapMarker_1-1")
        # Selection rebuilds the controls and installs keyboard focus deferred.
        # Wait for the new button, then observe focus pixels with the pointer
        # outside it. Do not send Enter to the old, queued-for-deletion widget.
        page.wait_for_function("""previous => {
            const s=window.__sporelightState;
            const button=s?.buttons.find(b=>b.path.endsWith('/MapEnterLevel'));
            return s && s.qaSequence>previous.sequence+1 && button &&
                button.instanceId!==previous.instance && !button.disabled &&
                s.ui.controls.some(c=>c.path.includes('/MapSelectedCard/')&&c.text?.startsWith('1-1 ·'));
        }""", arg={"instance": previous_instance, "sequence": previous_sequence}, timeout=10000)
        page.mouse.move(1, 1)
        deadline = time.monotonic() + 5
        while True:
            current = pick(page, suffix="/MapEnterLevel")
            ready_pixels = page.screenshot(clip=css_rect(page, current["visibleRect"]), scale="css")
            if ready_pixels == focused:
                (folder / "level-focus-before-enter.png").write_bytes(ready_pixels)
                row["enterSynchronization"] = {"previousInstance": previous_instance, "newInstance": current["instanceId"],
                                               "focusPixelsMatch": True, "qaSequence": state(page)["qaSequence"]}
                break
            if time.monotonic() >= deadline:
                raise AssertionError("New selected entry did not acquire the observed keyboard-focus appearance")
            page.wait_for_timeout(80)
        page.keyboard.press("Enter")
        page.wait_for_function("() => {const s=window.__sporelightState;return s?.worldVisible&&!s.paused&&s.snapshot.levelId==='1-1';}")
        assert state(page)["snapshot"]["growth"] == initial["growth"], "navigation retains seed rules and growth"
        page.screenshot(path=str(folder / "entered-garden.png"), scale="css")
        assert not row["errors"], str(row["errors"])
        row.update(passed=True, focusMatchesHover=True)
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
(OUT / "checks.json").write_text(json.dumps({"passed": passed, "build": build, "results": results,
    "scope": "Actual isolated pointer/touch/keyboard navigation, authored unlocks, selected-level return paths, CSS hit areas and focus/hover PNG equality. Portrait touch checks the existing rotation gate then resumes landscape. No QA state injection; screenshots require visual review."},
    ensure_ascii=False, indent=2), encoding="utf-8")
raise SystemExit(0 if passed else 1)

"""Real pointer/keyboard category switching and fixed gallery header geometry."""
import argparse
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base", default="http://localhost:4211/")
parser.add_argument("--output", default="docs/qa-godot-native/gallery-tabs/browser")
parser.add_argument("--sizes", default="1280x720,390x844,320x568,568x320,594x462")
args = parser.parse_args()
OUT = ROOT / args.output
OUT.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(args.base + "__build.json") as response:
    build = json.load(response)
rows = []


def state(page):
    page.wait_for_timeout(140)
    return page.evaluate("() => structuredClone(window.__sporelightState)")


def point(page, rect):
    box = page.locator("#canvas").bounding_box()
    backing = page.locator("#canvas").evaluate("c=>[c.width,c.height]")
    return [box["x"] + (rect[0] + rect[2]/2) * box["width"]/backing[0], box["y"] + (rect[1] + rect[3]/2) * box["height"]/backing[1]]


def choose(page, text=None, action=None):
    for attempt in range(35):
        controls = state(page)["ui"]["controls"]
        button = next((c for c in controls if c["class"] == "Button" and (text is None or c.get("text") == text) and (action is None or c.get("action") == action)), None)
        if button and button["visibleRect"][2] > 30 and button["visibleRect"][3] > 35:
            page.mouse.click(*point(page, button["visibleRect"]))
            return button
        scroll = next(c for c in controls if c["class"] == "ScrollContainer")
        page.mouse.move(*point(page, scroll["visibleRect"]))
        page.mouse.wheel(0, -200 if button and button["y"] < scroll["y"] else 200)
        page.wait_for_timeout(180)
    raise AssertionError("Unreachable " + str([text, action]))


def geometry(page):
    controls = state(page)["ui"]["controls"]
    scroll = next(c for c in controls if c["class"] == "ScrollContainer")
    body = [c for c in controls if c["class"] == "Label" and "/GalleryFrame/ModalScroll/" in c["path"]]
    assert body, "gallery has real visible content"
    first = body[0]
    fixed = {c["text"]: c["visibleRect"] for c in controls if c.get("text") == "微光图鉴" or "/GalleryCategories/" in c["path"] or "/GalleryReturnActions/" in c["path"]}
    # The body begins with a 4px separator plus the VBox's 12px gap.
    return {"scroll": scroll["visibleRect"], "firstY": first["y"], "contentOffset": scroll["y"] + 16 - first["y"], "fixed": fixed, "firstText": first["text"], "tabs": [c for c in controls if "/GalleryCategories/" in c["path"]]}


def check_top(page):
    page.wait_for_timeout(180)
    g = geometry(page)
    assert abs(g["contentOffset"]) <= 1, "new category starts at its first content row: " + str(g)
    assert len(g["tabs"]) == 5 and sum(t["pressed"] for t in g["tabs"]) == 1
    assert all(t["width"] >= 44 and t["height"] >= 44 and t["visibleRect"][2] >= 43 for t in g["tabs"])
    return g


with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    cases = [(tuple(map(int, text.split("x"))), 1) for text in args.sizes.split(",")]
    cases.append(((1280,720), 1.25))
    for size, dpr in cases:
        folder = OUT / f"{size[0]}x{size[1]}-dpr{dpr:g}"
        folder.mkdir(parents=True, exist_ok=True)
        row = {"size": size, "dpr": dpr, "errors": []}
        context = browser.new_context(viewport={"width":size[0],"height":size[1]}, device_scale_factor=dpr)
        page = context.new_page()
        page.on("pageerror", lambda e, row=row: row["errors"].append(str(e)))
        page.on("console", lambda m, row=row: row["errors"].append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
        try:
            page.goto(args.base+"?qa=1&home=1&unlockAll=0", wait_until="networkidle")
            page.wait_for_selector("#status", state="detached", timeout=90000)
            choose(page, action="map")
            page.wait_for_timeout(300)
            choose(page, text="图鉴")
            initial = check_top(page)
            page.screenshot(path=str(folder/"gallery-top.png"), scale="css")
            page.mouse.move(*point(page, initial["scroll"]))
            page.mouse.wheel(0, 400)
            page.wait_for_timeout(250)
            scrolled = geometry(page)
            assert scrolled["contentOffset"] > 20
            assert initial["fixed"] == scrolled["fixed"], "title/categories/return stay fixed"
            # Clicking the already selected category preserves the same body.
            choose(page, text="全部")
            same = geometry(page)
            assert abs(same["contentOffset"]-scrolled["contentOffset"]) < 1
            page.screenshot(path=str(folder/"gallery-scrolled.png"), scale="css")
            for category in ["植物", "生物", "建筑", "奇物", "全部"]:
                choose(page, text=category)
                g = check_top(page)
                assert next(t for t in g["tabs"] if t["pressed"])["text"] == category
                if category=="植物":
                    page.screenshot(path=str(folder/"plants-top.png"), scale="css")
            page.keyboard.press("ArrowRight")
            page.keyboard.press("Enter")
            check_top(page)
            page.keyboard.press("Escape")
            page.wait_for_timeout(250)
            assert any("/MapFrame/" in c["path"] for c in state(page)["ui"]["controls"]), "back returns to the original map"
            assert not row["errors"], str(row["errors"])
            row.update(passed=True, top=initial, scrolled=scrolled)
        except Exception as e:
            import traceback
            row.update(passed=False, reason=str(e), traceback=traceback.format_exc())
            page.screenshot(path=str(folder/"failure.png"), scale="css")
        finally:
            context.close()
        (folder/"checks.json").write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding="utf-8")
        rows.append(row)
        print(json.dumps({k:row.get(k) for k in ["size","dpr","passed","reason"]}),flush=True)
    browser.close()
passed = all(r["passed"] for r in rows)
(OUT/"checks.json").write_text(json.dumps({"passed":passed,"build":build,"results":rows,"scope":"Actual input on isolated empty-progress profiles; unlocked-item story reading offsets are checked separately by the actual native HUD suite. Browser viewport/DPR emulation is not physical-device certification."},ensure_ascii=False,indent=2),encoding="utf-8")
raise SystemExit(0 if passed else 1)

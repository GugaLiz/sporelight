"""Real-input map/HUD and restored-effect smoke checks. QA only seeds pickup state.

No unpublished scene fields or injected actions. Pixel motion is evidence for
visual review, not proof of art quality. Run separately from other GPU checkers.
"""
import argparse
import io
import json
import re
import sys
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright
from PIL import Image, ImageChops, ImageStat

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--url", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--sizes", default="1280x720,568x320")
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)

# Reuse existing input/route code without executing its browser runner.
helper = ROOT / "tools/godot-migration/check-native-browser.py"
source = helper.read_text(encoding="utf-8").split("\nwith sync_playwright() as p:")[0]
argv = sys.argv
sys.argv = [str(helper), "--base", args.url, "--output", args.output]
h = {"__file__": str(helper), "__name__": "art_restoration_helpers"}
exec(compile(source, str(helper), "exec"), h)
sys.argv = argv


def fresh(page):
    return h["fresh"](page)


def control(page, **query):
    rows = [c for c in fresh(page)["ui"]["controls"]
            if all(c.get(k) == v for k, v in query.items())]
    assert len(rows) == 1, f"Expected one visible control {query}: {rows}"
    return rows[0]


def click(page, allow_disabled=False, **query):
    entry = control(page, **query)
    assert allow_disabled or not entry.get("disabled"), str(query)
    rect = entry["visibleRect"]
    assert rect[2] > 3 and rect[3] > 3, f"Clipped input target {query}"
    h["click_rect"](page, rect)
    page.wait_for_timeout(280)
    return fresh(page)


def chapter(page, title):
    controls = fresh(page)["ui"]["controls"]
    labels = [c for c in controls if c.get("text") == title and c["class"] == "Label"]
    candidates = [c for c in controls if c["class"].endswith("Button") and not c.get("disabled")
                  and any(label["path"].startswith(c["path"] + "/") for label in labels)]
    assert len(candidates) == 1, f"Chapter card with descendant title {title}"
    h["click_rect"](page, candidates[0]["visibleRect"])
    page.wait_for_timeout(300)


def save(page, folder, name):
    raw = page.screenshot(path=str(folder / (name + ".png")))
    (folder / (name + ".json")).write_text(json.dumps(fresh(page), ensure_ascii=False, indent=2), encoding="utf-8")
    return Image.open(io.BytesIO(raw)).convert("RGB")


def difference(left, right):
    diff = ImageChops.difference(left, right)
    pixels = list(diff.getdata())
    return {"changedPixels": sum(max(p) > 3 for p in pixels),
            "meanChannelDelta": sum(ImageStat.Stat(diff).mean) / 3}


def count(page, expected=None):
    text = control(page, name="CollectionCount")["text"]
    match = re.fullmatch(r"\s*(\d+)\s*/\s*(\d+)\s*", text)
    assert match, f"Actual HUD collection counter: {text}"
    value, total = map(int, match.groups())
    state = fresh(page)
    assert value == len(state["snapshot"]["collected"]), "HUD counter matches live collection"
    if expected is not None:
        assert value == expected, (value, expected)
    return {"collected": value, "total": total}


def map_and_entry(page, folder):
    click(page, action="map")
    initial = fresh(page)
    assert any(c.get("text") == "☀ 0" for c in initial["ui"]["controls"]), "Fresh map journey total is zero"
    assert not initial["progress"].get("records"), "Isolated context starts with no completed records"
    click(page, name="MapMarker_1-2")
    assert control(page, name="MapEnterLevel")["disabled"], "Locked 1-2 still permits preview"
    save(page, folder, "locked-preview")
    snapshot = fresh(page)["snapshot"]
    click(page, name="MapEnterLevel", allow_disabled=True)
    page.keyboard.press("Enter")
    page.wait_for_timeout(250)
    locked = fresh(page)
    assert locked["homeActive"] and locked["snapshot"] == snapshot, "Pointer and Enter cannot enter locked preview"
    assert control(page, name="MapEnterLevel")["disabled"]
    click(page, action="world_overview")
    chapter(page, "雨滴池塘")
    assert control(page, name="MapEnterLevel")["disabled"], "Locked pond chapter permits preview only"
    assert control(page, name="MapMarker_2-1")
    save(page, folder, "pond-preview")
    click(page, action="world_overview")
    chapter(page, "苔藓山谷")
    click(page, name="MapMarker_1-1")
    click(page, action="world_overview")
    click(page, action="close_overview")
    assert not control(page, name="MapEnterLevel")["disabled"], "Overview return keeps unlocked selection"
    click(page, action="home")
    assert fresh(page)["homeActive"], "Map return reaches home"
    click(page, action="map")
    click(page, name="MapMarker_1-1")
    click(page, name="MapEnterLevel")
    state = h["stable"](page, "1-1")
    assert not state["homeActive"] and state["worldVisible"] and state["gameHudVisible"]
    assert not state["paused"]
    counter = count(page, 0)
    save(page, folder, "entered-first-garden")
    return {"lockedPointerAndKeyboard": True, "chapterPreviewAndReturn": True,
            "actualMapEntry": True, "counter": counter}


def live_effects(page, folder):
    # Real entry resumes visual time; a QA snapshot intentionally freezes it.
    page.mouse.move(1, 1)
    page.wait_for_timeout(1200)
    state = fresh(page)
    target = next(t for t in state["targets"] if t["id"] == "f:-2:-1")
    canvas = page.locator("#canvas")
    box = canvas.bounding_box()
    backing = canvas.evaluate("e => [e.width, e.height]")
    x = box["x"] + target["x"] * box["width"] / backing[0]
    y = box["y"] + target["y"] * box["height"] / backing[1]
    density = state["scale"] * 49.49747468 * box["height"] / backing[1]
    rect = (int(max(0, x - density * .46)), int(max(0, y - density * .98)),
            int(min(page.viewport_size["width"], x + density * .46)),
            int(min(page.viewport_size["height"], y + density * .13)))
    assert rect[2] - rect[0] > 12 and rect[3] - rect[1] > 12, "Visible collectible crop"
    images = []
    performance = []
    for index in range(4):
        page.wait_for_timeout(260)
        image = save(page, folder, f"floating-{index}").crop(rect)
        image.save(folder / f"floating-crop-{index}.png")
        images.append(image)
        performance.append(fresh(page)["performance"])
    diffs = [difference(images[0], image) for image in images[1:]]
    assert max(d["changedPixels"] for d in diffs) > 5, "Visible uncollected spore area changes across actual live frames"
    assert not fresh(page)["moving"] and count(page)["collected"] == 0
    page.keyboard.press("Escape")
    page.wait_for_function("window.__sporelightState?.paused === true")
    page.mouse.move(1, 1)
    page.wait_for_timeout(1100)
    first = save(page, folder, "paused-a")
    page.wait_for_timeout(450)
    second = save(page, folder, "paused-b")
    paused_diff = difference(first, second)
    assert paused_diff["changedPixels"] <= 4, f"Paused rendered frame stays still: {paused_diff}"
    page.keyboard.press("Escape")
    page.wait_for_function("window.__sporelightState?.paused === false")
    return {"crop": rect, "liveDifferences": diffs, "pauseDifference": paused_diff,
            "performanceSamples": performance,
            "limitation": "Crop includes spore glow and nearby terrain; inspect saved frames for bob/occlusion quality. Pause comparison includes the real settings overlay."}


def pickup_undo(page, folder):
    snapshot = json.loads(json.dumps(next(c["initial"] for c in h["cases"] if c["id"] == "1-1")))
    snapshot["actors"] = {"luvie": "f:-2:0", "buddy": "f:-2:0"}
    snapshot["follow"] = False
    snapshot["collected"] = []
    snapshot.pop("runtime", None)
    h["prepare"](page, snapshot)
    count(page, 0)
    save(page, folder, "pickup-before")
    before = fresh(page)
    result = h["move_to"](page, "f:-2:-1")
    assert "spore-0" in result["snapshot"]["collected"], "Actual pointer/keyboard travel collects spore"
    assert result["revision"] > before["revision"]
    counter = count(page, 1)
    save(page, folder, "pickup-after")
    undos = 0
    while "spore-0" in fresh(page)["snapshot"]["collected"] and undos < 4:
        page.keyboard.press("z")
        h["input_trace"].append({"kind": "key", "key": "z", "purpose": "undo actual pickup"})
        h["stable"](page, "1-1")
        undos += 1
    assert "spore-0" not in fresh(page)["snapshot"]["collected"], "Real undo restores uncollected spore state"
    count(page, 0)
    save(page, folder, "pickup-undone")
    return {"actualInputCollection": True, "counterAfterPickup": counter, "undoKeyPresses": undos,
            "visualReview": "Inspect before/after/undone: removal and restored spore, with real depth."}


url = urlsplit(args.url)
query = dict(parse_qsl(url.query))
query.update(qa="1", home="1", unlockAll="0")
start_url = urlunsplit((url.scheme, url.netloc, url.path, urlencode(query), url.fragment))
report = {"build": h["build"], "results": [], "visualReview": "pending",
          "scope": "Real pointer/keyboard map navigation, locking, HUD counter, live-frame difference, pause and pickup/undo. QA snapshot seeds pickup only."}
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel="chrome", headless=True)
    for size in args.sizes.split(","):
        width, height = map(int, size.split("x"))
        folder = out / size
        folder.mkdir(exist_ok=True)
        context = browser.new_context(viewport={"width": width, "height": height}, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda message: errors.append(message.text)
                if message.type == "error" or "SCRIPT ERROR:" in message.text else None)
        row = {"size": [width, height], "passed": False}
        h["input_trace"].clear()
        try:
            page.goto(start_url, wait_until="domcontentloaded", timeout=120000)
            page.wait_for_function("window.__sporelightState?.homeActive === true", timeout=120000)
            page.wait_for_selector("#status", state="detached", timeout=120000)
            row["map"] = map_and_entry(page, folder)
            # One full effect sequence is sufficient; small landscape verifies
            # actual navigation and counter layout without doubling GPU work.
            if width >= 1000:
                row["effects"] = live_effects(page, folder)
                row["pickup"] = pickup_undo(page, folder)
            assert not errors, str(errors)
            row["passed"] = True
        except Exception as error:
            row["reason"] = str(error)
            try:
                save(page, folder, "failure")
            except Exception:
                pass
        finally:
            row["errors"] = errors
            row["inputTrace"] = list(h["input_trace"])
            report["results"].append(row)
            context.close()
            (out / "checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({"size": size, "passed": row["passed"], "reason": row.get("reason")}), flush=True)
    browser.close()
report["passed"] = all(row["passed"] for row in report["results"])
(out / "checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
sys.exit(0 if report["passed"] else 1)

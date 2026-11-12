"""GPU state review for every authored level, separate from real-input route tests.

The QA bridge restores fixtures solely to set up screenshots. No restoration is
counted as gameplay completion. Uses a fresh browser context per viewport; never
reads or modifies the user's browser profile. Full native route checks are a
separate acceptance requirement.
"""
import argparse
import copy
import json
import math
import sys
import urllib.request
from pathlib import Path
from qa_core_approach import reached_core_approach

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright


def cloud_snapshot(s):
    return {
        "designVersion": 2, "levelId": s["levelId"], "active": "luvie",
        "actors": {"luvie": s["tile"], "buddy": "floor:10:3" if s["buddy"] == "sleep" else "floor:3:6" if s["buddy"] == "wait" else s["tile"]},
        "follow": s["buddy"] == "follow", "growth": {},
        "turns": {"bridge": int(s["bridge"] == "east"), "lift": int(s["lift"] == "high")},
        "flags": [], "items": {}, "collected": s["found"], "observations": s["found"],
        "discovered": [], "water": 0, "mode": 0, "frozen": None,
        "song": ["turn", "rise", "rest"], "beat": 0, "playing": False,
        "completed": s["repaired"], "cloudSeed": s["seed"],
        "cloudLatch": s["latch"], "cloudBuddy": s["buddy"],
    }


def cases():
    main = json.loads((ROOT / "godot/tests/fixtures/reference.json").read_text(encoding="utf-8"))
    result = [{"id": e["levelId"], "initial": e["initial"]["snapshot"], "steps": e["steps"]}
              for e in main["cases"] if e["name"].startswith("authored/")]
    cloud = json.loads((ROOT / "godot/tests/fixtures/cloud-reference.json").read_text(encoding="utf-8"))
    result += [{"id": e["id"], "initial": cloud_snapshot(e["initial"]),
                "steps": [{"command": step["command"], "snapshot": cloud_snapshot(step["snapshot"])} for step in e["steps"]]}
               for e in cloud["levels"]]
    return result


def review_states(case):
    # Mechanism samples are identified by actual fixture actions, not by new
    # hard-coded solutions or injected completion flags.
    actions = [(i, step) for i, step in enumerate(case["steps"])
               if step["command"]["kind"] == "act"
               and step["command"]["value"] not in ["repair", "switch", "follow"]]
    samples = [("arrival", case["initial"], "initial")]
    if actions:
        index, step = actions[len(actions) // 2]
        samples.append(("mechanism", step["snapshot"], f"fixture step {index}: {step['command']['value']}"))
    before = next((s["snapshot"] for s in reversed(case["steps"]) if not s["snapshot"]["completed"]), case["initial"])
    samples += [("before-completion", before, "last incomplete fixture state"),
                ("restored-completion", case["steps"][-1]["snapshot"], "completed fixture restoration; not a played route")]
    for label, snapshot, origin in samples:
        snapshot = copy.deepcopy(snapshot)
        if case["id"] == "1-1" and label in ["before-completion", "restored-completion"]:
            # Current accepted garden moved its flowerbed north. The legacy
            # fixture remains unchanged; pose setup explicitly uses today's mark.
            definitions = json.loads((ROOT / "godot/content/levels.json").read_text(encoding="utf-8"))["levels"]
            first = next(level for level in definitions if level["id"] == "1-1")
            core = next(mark["tile"] for mark in first["marks"] if mark["id"] == "core")
            snapshot["actors"] = {"luvie": core, "buddy": core}
            origin += "; current 1-1 flowerbed pose (legacy fixture unchanged)"
        yield label, snapshot, origin


def read_state(page):
    return page.evaluate("() => structuredClone(window.__sporelightState)")


def restore(page, snapshot):
    sequence = read_state(page)["qaSequence"]
    page.evaluate("snapshot => window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot,time:1200}))", snapshot)
    page.wait_for_function("""arg => {
        const s = window.__sporelightState;
        return s?.qaSequence > arg.sequence + 2 && s.snapshot.levelId === arg.id
            && !s.homeActive && !s.moving && s.snapshot.completed === arg.completed;
    }""", arg={"sequence": sequence, "id": snapshot["levelId"], "completed": snapshot["completed"]}, timeout=20000)
    page.wait_for_timeout(200)
    return read_state(page)


def verify(state, expected):
    problems = []
    for key, value in expected.items():
        if key == "actors" and set(state["snapshot"].get(key, {})) == set(value):
            for who, requested in value.items():
                if state["snapshot"][key][who] != requested and not reached_core_approach(state, requested, who):
                    problems.append("restored snapshot differs in actors/" + who)
            continue
        if state["snapshot"].get(key) != value:
            problems.append("restored snapshot differs in " + key)
    if not state.get("worldVisible") or not state.get("gameHudVisible"):
        problems.append("world/HUD not visible")
    if state["ui"]["modalOpen"]:
        problems.append("unexpected modal obscures state review")
    if not state.get("native"):
        problems.append("native movement not available")
    for who, actor in state.get("native", {}).get("actors", {}).items():
        p = actor["position"]
        if not all(math.isfinite(value) for value in p):
            problems.append(who + " non-finite position")
        if actor["support"] != state["snapshot"]["actors"][who]:
            problems.append(who + " support differs from rule state")
        if abs(p[1] - actor["floorHeight"]) >= .16:
            problems.append(who + " ground contact differs by >= .16")
    for button in state.get("buttons", []):
        if button.get("action") in ["primary", "undo", "hint"] and button.get("clipped"):
            problems.append("clipped gameplay button: " + button["action"])
    return problems


def gallery(out, rows):
    # A standalone index makes the original unmodified screenshots reviewable.
    import html
    cards = []
    for row in rows:
        if "image" in row:
            caption = f"{row['level']} / {row['size']} / {row['state']}"
            cards.append(f'<figure><a href="{row["image"]}"><img loading="lazy" src="{row["image"]}"></a><figcaption>{html.escape(caption)}</figcaption></figure>')
    (out / "index.html").write_text('<!doctype html><meta charset="utf-8"><title>Level GPU review</title>'
        '<style>body{background:#19251e;color:#ecf3e8;font:16px sans-serif;margin:24px}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px}</style>'
        '<h1>GPU state review</h1><p>Restored states; real-input routes are verified separately.</p><main>' + ''.join(cards) + '</main>', encoding="utf-8")


def comparison_sheets(out, baseline, rows):
    """Arrange entire unretouched screenshots; originals remain the evidence."""
    from PIL import Image, ImageDraw
    folder = out / "comparisons"
    folder.mkdir(exist_ok=True)
    for size in sorted({row["size"] for row in rows}):
        for chapter in ["1", "2", "3", "cloud"]:
            for state in ["arrival", "mechanism", "before-completion"]:
                selected = [row for row in rows if row["size"] == size and row["state"] == state
                            and row["level"].split("-")[0] == chapter and "image" in row]
                pairs = [(row, baseline / row["image"], out / row["image"]) for row in selected]
                pairs = [pair for pair in pairs if pair[1].is_file()]
                if not pairs:
                    continue
                width, height = map(int, size.split("x"))
                thumb_width = min(640, width)
                thumb_height = round(height * thumb_width / width)
                row_height = thumb_height + 28
                sheet = Image.new("RGB", (thumb_width * 2, row_height * len(pairs)), "#18271e")
                draw = ImageDraw.Draw(sheet)
                for i, (row, before, after) in enumerate(pairs):
                    for column, path in enumerate([before, after]):
                        with Image.open(path) as source:
                            frame = source.convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
                        x, y = column * thumb_width, i * row_height
                        draw.text((x + 8, y + 6), ("BEFORE" if column == 0 else "AFTER") + "  " + row["level"] + "  " + state + "  " + size, fill="#f5eddb")
                        sheet.paste(frame, (x, y + 28))
                sheet.save(folder / f"{size}-chapter-{chapter}-{state}.jpg", quality=92)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="http://localhost:4219/")
    parser.add_argument("--output", default="docs/qa-godot-native/all-level-adjustment/gpu")
    parser.add_argument("--levels", default="")
    parser.add_argument("--sizes", default="1280x720,844x390")
    parser.add_argument("--compare-to", default="", help="Prior screenshot folder for before/after contact sheets; original images are kept.")
    args = parser.parse_args()
    out = ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(args.base.rstrip("/") + "/__build.json") as response:
        build = json.load(response)
    selected = set(args.levels.split(",")) if args.levels else None
    rows = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome", headless=True)
        try:
            for size_text in args.sizes.split(","):
                width, height = map(int, size_text.split("x"))
                context = browser.new_context(viewport={"width": width, "height": height}, has_touch=width < 1000, device_scale_factor=1)
                page = context.new_page()
                errors = []
                page.on("pageerror", lambda error: errors.append(str(error)))
                page.on("console", lambda message: errors.append(message.text) if message.type == "error" or "SCRIPT ERROR:" in message.text else None)
                page.goto(args.base.rstrip("/") + "/?qa=1", wait_until="networkidle", timeout=120000)
                page.wait_for_function("() => typeof window.__sporelightRequest === 'function' && window.__sporelightState?.snapshot", timeout=120000)
                page.wait_for_selector("#status", state="detached", timeout=120000)
                for case in cases():
                    if selected is not None and case["id"] not in selected:
                        continue
                    for label, snapshot, origin in review_states(case):
                        relative = Path(size_text) / case["id"] / (label + ".png")
                        (out / relative).parent.mkdir(parents=True, exist_ok=True)
                        row = {"level": case["id"], "size": size_text, "state": label, "origin": origin}
                        try:
                            state = restore(page, snapshot)
                            page.screenshot(path=str(out / relative))
                            problems = verify(state, snapshot)
                            row.update(image=relative.as_posix(), passed=not problems and not errors, problems=problems, errors=list(errors),
                                       snapshot=state["snapshot"], native=state["native"], render=state["render"], buttons=state["buttons"], safeRect=state["safeRect"])
                            row["coreApproaches"] = [evidence for who, requested in snapshot.get("actors", {}).items()
                                if state["snapshot"]["actors"].get(who) != requested
                                for evidence in [reached_core_approach(state, requested, who)] if evidence]
                        except Exception as error:
                            row.update(passed=False, problems=[str(error)], errors=list(errors))
                            page.screenshot(path=str(out / relative.with_name(label + "-failure.png")))
                        rows.append(row)
                    print(json.dumps({"size": size_text, "level": case["id"], "passed": all(row["passed"] for row in rows if row["level"] == case["id"] and row["size"] == size_text)}, ensure_ascii=False), flush=True)
                context.close()
        finally:
            browser.close()
    report = {"passed": bool(rows) and all(row["passed"] for row in rows), "build": build,
              "scope": "GPU screenshots of restored states plus contact/HUD assertions; not real-input route completion", "results": rows}
    (out / "checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    gallery(out, rows)
    if args.compare_to:
        comparison_sheets(out, ROOT / args.compare_to, rows)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())

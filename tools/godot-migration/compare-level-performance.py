"""Compare matching levels, sequentially and in reversed order.

This is a headless browser diagnostic, not hardware performance certification.
Default runs omit the expensive QA bridge and use the existing --level entry.
--qa optionally diagnoses matching completed states with telemetry enabled.
"""
import argparse
import importlib.util
import json
import statistics
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("level_acceptance", Path(__file__).with_name("check-level-acceptance.py"))
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--before", default="http://localhost:4219/")
parser.add_argument("--after", default="http://localhost:4221/")
parser.add_argument("--level", default="3-4")
parser.add_argument("--qa", action="store_true")
parser.add_argument("--output", default="docs/qa-godot-native/all-level-adjustment/performance-comparison")
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)
case = next(case for case in qa.cases() if case["id"] == args.level)
snapshot = case["steps"][-1]["snapshot"]
builds = {}
for label, base in [("before", args.before), ("after", args.after)]:
    with urllib.request.urlopen(base.rstrip("/") + "/__build.json") as response:
        builds[label] = json.load(response)

rows = []
with qa.sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel="chrome", headless=True)
    try:
        for index, label in enumerate(["before", "after", "after", "before"]):
            base = args.before if label == "before" else args.after
            context = browser.new_context(viewport={"width": 1280, "height": 720}, device_scale_factor=1)
            if not args.qa:
                def bootstrap(route):
                    response = route.fetch()
                    html = response.text()
                    assert '"args":[]' in html, "known export bootstrap args"
                    html = html.replace('"args":[]', '"args":' + json.dumps(["--", "--level=" + args.level]))
                    route.fulfill(response=response, body=html)
                context.route(base.rstrip("/") + "/", bootstrap)
            page = context.new_page()
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("console", lambda message: errors.append(message.text) if message.type == "error" or "SCRIPT ERROR:" in message.text else None)
            started = time.monotonic()
            page.goto(base.rstrip("/") + ("/?qa=1" if args.qa else "/"), wait_until="networkidle", timeout=120000)
            page.wait_for_selector("#status", state="detached", timeout=120000)
            if args.qa:
                page.wait_for_function("() => typeof window.__sporelightRequest === 'function' && window.__sporelightState?.snapshot", timeout=120000)
                state = qa.restore(page, snapshot)
                assert not qa.verify(state, snapshot), "matching snapshot/contact checks"
            else:
                assert page.evaluate("() => typeof window.__sporelightState === 'undefined'"), "QA publication disabled"
            load_seconds = time.monotonic() - started
            page.wait_for_timeout(2000)
            pacing = page.evaluate("""() => new Promise(resolve => {
                const times = []; let start = null, previous = null;
                function frame(now) {
                    if (start === null) start = now;
                    if (previous !== null) times.push(now - previous);
                    previous = now;
                    if (now - start < 4000) requestAnimationFrame(frame); else resolve(times);
                }
                requestAnimationFrame(frame);
            })""")
            samples = [qa.read_state(page)["performance"]] if args.qa else []
            page.screenshot(path=str(out / f"{index}-{label}.png"))
            row = {"label": label, "order": index, "loadSeconds": load_seconds, "samples": samples,
                   "rafTimesMs": pacing, "medianFrameMs": statistics.median(pacing),
                   "p95FrameMs": sorted(pacing)[min(len(pacing)-1, int(len(pacing)*.95))],
                   "errors": errors}
            rows.append(row)
            print(json.dumps({key: row[key] for key in ["label", "order", "medianFrameMs", "p95FrameMs", "errors"]}), flush=True)
            context.close()
    finally:
        browser.close()

report = {"level": args.level, "builds": builds, "snapshot": snapshot if args.qa else None, "qa": args.qa,
          "size": [1280, 720], "runs": rows,
          "scope": "Isolated headless Chromium; reversed before/after order. rAF is browser pacing, not GPU/device certification. Default starts the level through a test-only bootstrap CLI override, without QA publication."}
(out / "checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

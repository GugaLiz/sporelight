"""Compare the HTML loader with actual native home-control geometry.

Every case holds the real PCK request while observing HTML, then releases that
same request and starts the real exported engine. The reference is sampled once
from the actual GardenHUD, not a second copy of its layout formulas.
"""
import argparse
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright

DEFAULT_SIZES = "1280x720,390x844,320x568,568x320,594x462,2560x1440,3440x1440"
TOLERANCE = 0.12  # CSS pixels, including fractional-DPR layout quantization.

LOADER_GEOMETRY = """() => {
    const rect = e => {const r=e.getBoundingClientRect();return [r.x,r.y,r.width,r.height];};
    const image=document.querySelector('.brand img'),p=document.querySelector('.brand p');
    const css=getComputedStyle(image),box=rect(image),width=parseFloat(css.width),height=parseFloat(css.height);
    // Fit in the element's pre-transform content box, then map through its
    // actual transform. X/Y scales can differ after backing-pixel flooring.
    const fit=Math.min(width/image.naturalWidth,height/image.naturalHeight);
    const paintedWidth=image.naturalWidth*fit,paintedHeight=image.naturalHeight*fit;
    const sx=box[2]/width,sy=box[3]/height;
    const painted=[box[0]+(width-paintedWidth)*sx*.5,box[1]+(height-paintedHeight)*sy*.5,paintedWidth*sx,paintedHeight*sy];
    const copy=document.querySelector('.loading-copy'),caption=getComputedStyle(p);
    return {viewport:[innerWidth,innerHeight],dpr:devicePixelRatio,
        canvasRect:rect(document.querySelector('#canvas')),logoRect:box,paintedRect:painted,
        textureSize:[image.naturalWidth,image.naturalHeight],objectFit:css.objectFit,
        brandRect:rect(document.querySelector('.brand')),taglineRect:rect(p),copyRect:rect(copy),
        taglineFontSize:parseFloat(caption.fontSize),taglineTransform:caption.transform,
        copyOverflowX:copy.scrollWidth>copy.clientWidth+1,
        pageOverflowX:document.documentElement.scrollWidth>innerWidth+1};
}"""

HOME_GEOMETRY = """() => {
    const c=document.querySelector('#canvas'),r=c.getBoundingClientRect(),s=window.__sporelightState;
    const tag=s.ui.controls.find(c=>c.name==='CoverTagline');
    return {dpr:devicePixelRatio,viewport:[innerWidth,innerHeight],
        backing:[c.width,c.height],canvasRect:[r.x,r.y,r.width,r.height],nativeViewport:s.viewport,
        taglineRect:tag?[tag.x,tag.y,tag.width,tag.height]:null,
        homeActive:s.homeActive,focus:document.activeElement.id};
}"""


def read_json_url(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)


def max_error(actual, expected):
    return max(abs(a - b) for a, b in zip(actual, expected))


def map_rect(rect, canvas_rect, backing):
    x, y, w, h = rect
    cx, cy, cw, ch = canvas_rect
    return [cx + x * cw / backing[0], cy + y * ch / backing[1], w * cw / backing[0], h * ch / backing[1]]


def overlap(a, b):
    return max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])) * max(0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))


def backing_for(size, dpr):
    return [math.floor(size[0] * dpr), math.floor(size[1] * dpr)]


def display_rect_for(initial_rect, backing, dpr):
    # Godot's SDK floors CSS*DPR for backing pixels, then floors backing/DPR
    # again when assigning the canvas CSS dimensions. Fractional DPR can make
    # the final displayed canvas one CSS pixel narrower than the initial 100%.
    return [initial_rect[0], initial_rect[1], max(1, math.floor(backing[0] / dpr)), max(1, math.floor(backing[1] / dpr))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="http://localhost:4195/")
    parser.add_argument("--variant", default="brand-candidate")
    parser.add_argument("--output", default="docs/qa-godot-native/brand-alignment")
    parser.add_argument("--sizes", default=DEFAULT_SIZES)
    parser.add_argument("--dprs", default="1,1.25,1.5,2")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--matrix-only", action="store_true", help="Omit resize/DPR transitions for a focused diagnostic run.")
    selection.add_argument("--transitions-only", action="store_true", help="Run only the two resize/DPR transition cases.")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(Path.home() / ".cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe")))
    args = parser.parse_args()
    sizes = [tuple(map(int, value.split("x"))) for value in args.sizes.split(",")]
    dprs = [float(value) for value in args.dprs.split(",")]
    assert sizes and all(len(size) == 2 and min(size) > 0 for size in sizes), "Positive width/height required"
    assert dprs and all(math.isfinite(dpr) and dpr > 0 for dpr in dprs), "Positive finite DPR required"
    base = args.base.rstrip("/") + "/"
    build_dir = (ROOT / "godot/build" / args.variant).resolve()
    assert build_dir.is_relative_to((ROOT / "godot/build").resolve()), "Build variant escapes the project"
    output = (ROOT / args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    metadata = json.loads((build_dir / "build.json").read_text(encoding="utf-8"))
    assert metadata.get("webMode") == "debug", "Exact browser control verification requires a debug candidate with the QA bridge"
    assert read_json_url(base + "__build.json") == metadata, "Served build does not match --variant metadata"
    assert (build_dir / "loader/logo.png").read_bytes() == (ROOT / "godot/assets/images/material-ready/menu-logo.png").read_bytes(), "Loader and home must use the same logo bytes"

    matrix = [] if args.transitions_only else [("matrix", [(size, dpr)]) for size in sizes for dpr in dprs]
    transitions = [] if args.matrix_only else [
        ("loading-resize", [((1280, 720), 1), ((390, 844), 1), ((568, 320), 1), ((594, 462), 1)]),
        ("loading-dpr-change", [((1280, 720), 1), ((1280, 720), 1.25), ((1280, 720), 1.5), ((1280, 720), 2)]),
    ]
    native_sizes = {tuple(backing_for(size, dpr)) for _, samples in matrix + transitions for size, dpr in samples}
    # Also observe native geometry after changing DPR on the running home.
    native_sizes.update(tuple(backing_for((1280, 720), dpr)) for dpr in [1.25, 1.5])
    size_argument = ",".join(f"{width}x{height}" for width, height in sorted(native_sizes))
    native_path = output / "native-reference.json"
    process = subprocess.run([args.godot, "--headless", "--path", str(ROOT / "godot"), "--script", "res://tests/native_brand_layout_test.gd", "--", "--sizes=" + size_argument, "--output=" + str(native_path)], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=180)
    (output / "native-reference.log").write_text(process.stdout + process.stderr, encoding="utf-8")
    assert process.returncode == 0 and "SCRIPT ERROR:" not in process.stdout + process.stderr, "Native observer failed; see native-reference.log"
    native = json.loads(native_path.read_text(encoding="utf-8"))
    assert native["passed"], str(native["failures"])
    references = {tuple(row["size"]): row for row in native["results"]}
    results = []

    def record_issue(row, condition, message):
        if not condition:
            row["issues"].append(message)

    def emulate_viewport_and_dpr(page, cdp, size, dpr, row):
        # A DPR-only CDP override changes the JS property without notifying
        # resolution queries in this Chrome. A one-pixel viewport round trip
        # causes actual browser resize/resolution events; no event is dispatched
        # from page script. This emulates zoom/viewport changes, not a monitor.
        before = page.evaluate("""() => {
            window.__brandResizeEvents ??= 0;
            window.__brandResolutionEvents ??= 0;
            if (!window.__brandProbeInstalled) {
                window.__brandProbeInstalled=true;
                window.addEventListener('resize',()=>++window.__brandResizeEvents);
            }
            const query=matchMedia('(resolution: '+devicePixelRatio+'dppx)');
            query.addEventListener('change',()=>++window.__brandResolutionEvents,{once:true});
            window.__brandProbeQuery=query;
            return {resize:window.__brandResizeEvents,resolution:window.__brandResolutionEvents};
        }""")
        for width in [size[0] + 1, size[0]]:
            cdp.send("Emulation.setDeviceMetricsOverride", {"width": width, "height": size[1], "deviceScaleFactor": dpr, "mobile": False})
            page.evaluate("() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
        after = page.evaluate("() => ({resize:window.__brandResizeEvents,resolution:window.__brandResolutionEvents,dpr:devicePixelRatio,viewport:[innerWidth,innerHeight]})")
        row["emulatedViewportAndDprChange"] = True
        row["dprEventSamples"].append({"targetDpr": dpr, "targetSize": list(size), "before": before, "after": after})
        record_issue(row, after["resize"] > before["resize"], "Emulated viewport/DPR change did not deliver an actual browser resize event")
        record_issue(row, abs(after["dpr"] - dpr) < 0.001 and after["viewport"] == list(size), "Emulated viewport/DPR metrics did not settle")

    def screenshot(page, row, file, dpr, cdp):
        if row["mode"] == "loading-dpr-change":
            # Playwright's screenshot restores context device metrics, even
            # with scale='device'. Direct CDP capture leaves the override intact.
            before = page.evaluate("devicePixelRatio")
            result = cdp.send("Page.captureScreenshot", {"format": "png", "captureBeyondViewport": False})
            file.write_bytes(base64.b64decode(result["data"]))
            after = page.evaluate("devicePixelRatio")
            row["screenshotDprChecks"].append({"file": file.name, "expected": dpr, "before": before, "after": after})
            record_issue(row, abs(before - dpr) < 0.001 and abs(after - dpr) < 0.001, "Screenshot changed the simulated DPR")
        else:
            page.screenshot(path=str(file), scale="css")

    def observe_loader(page, row, size, dpr, label, folder, cdp):
        page.wait_for_function("() => document.querySelector('.brand img')?.complete && document.querySelector('.brand img').naturalWidth>0")
        # A real resize/resolution event and the loader's animation frame must
        # settle before taking fractional-geometry measurements.
        page.evaluate("() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
        geometry = page.evaluate(LOADER_GEOMETRY)
        backing = backing_for(size, dpr)
        reference = references[tuple(backing)]
        geometry["label"] = label
        geometry["expectedBacking"] = backing
        geometry["initialCanvasRect"] = geometry["canvasRect"]
        geometry["expectedDisplayRect"] = display_rect_for(geometry["initialCanvasRect"], backing, dpr)
        geometry["expectedPaintedRect"] = map_rect(reference["paintedRect"], geometry["expectedDisplayRect"], backing)
        geometry["expectedTaglineRect"] = map_rect(reference["taglineRect"], geometry["expectedDisplayRect"], backing)
        geometry["paintedErrorCssPx"] = max_error(geometry["paintedRect"], geometry["expectedPaintedRect"])
        geometry["taglineErrorCssPx"] = max_error(geometry["taglineRect"], geometry["expectedTaglineRect"])
        geometry["logoCopyOverlap"] = overlap(geometry["paintedRect"], geometry["copyRect"])
        geometry["taglineCopyOverlap"] = overlap(geometry["taglineRect"], geometry["copyRect"])
        record_issue(row, geometry["viewport"] == list(size) and abs(geometry["dpr"] - dpr) < 0.001, label + ": browser metrics did not settle")
        record_issue(row, geometry["textureSize"] == reference["textureSize"], label + ": logo raster dimensions differ")
        record_issue(row, geometry["objectFit"] == "contain", label + ": loader image must explicitly use centered contain")
        record_issue(row, geometry["paintedErrorCssPx"] <= TOLERANCE, f"{label}: painted logo differs by {geometry['paintedErrorCssPx']:.6f} CSS px")
        record_issue(row, geometry["taglineErrorCssPx"] <= TOLERANCE, f"{label}: tagline container differs by {geometry['taglineErrorCssPx']:.6f} CSS px")
        record_issue(row, not geometry["copyOverflowX"] and not geometry["pageOverflowX"], label + ": horizontal overflow")
        record_issue(row, geometry["logoCopyOverlap"] < 1 and geometry["taglineCopyOverlap"] < 1, label + ": brand and loading text overlap")
        screenshot(page, row, folder / (label + ".png"), dpr, cdp)
        row["loadingSamples"].append(geometry)
        return geometry

    def observe_home(page, row, size, dpr, label, folder, cdp):
        expected_backing = backing_for(size, dpr)
        page.wait_for_function("value => {const s=window.__sporelightState;return s?.homeActive&&s.viewport[0]===value[0]&&s.viewport[1]===value[1];}", arg=expected_backing, timeout=20000)
        page.wait_for_timeout(100)
        geometry = page.evaluate(HOME_GEOMETRY)
        reference = references[tuple(expected_backing)]
        geometry["label"] = label
        geometry["expectedDisplayRect"] = display_rect_for(row["loadingSamples"][0]["initialCanvasRect"], expected_backing, dpr)
        geometry["expectedPaintedRect"] = map_rect(reference["paintedRect"], geometry["expectedDisplayRect"], expected_backing)
        geometry["expectedTaglineRect"] = map_rect(reference["taglineRect"], geometry["expectedDisplayRect"], expected_backing)
        geometry["actualTaglineCssRect"] = map_rect(geometry["taglineRect"], geometry["canvasRect"], geometry["backing"]) if geometry["taglineRect"] else None
        geometry["taglineErrorCssPx"] = max_error(geometry["actualTaglineCssRect"], geometry["expectedTaglineRect"]) if geometry["actualTaglineCssRect"] else None
        geometry["canvasDisplayErrorCssPx"] = max_error(geometry["canvasRect"], geometry["expectedDisplayRect"])
        record_issue(row, geometry["backing"] == expected_backing and geometry["nativeViewport"] == expected_backing, label + ": actual backing/native viewport differs from the pre-load prediction")
        record_issue(row, geometry["canvasDisplayErrorCssPx"] <= 0.001, label + ": actual displayed canvas differs from the SDK double-floor prediction")
        record_issue(row, geometry["taglineErrorCssPx"] is not None and geometry["taglineErrorCssPx"] <= TOLERANCE, label + ": actual browser native tagline differs from the observed reference")
        record_issue(row, geometry["focus"] == "canvas", label + ": keyboard focus does not reach canvas")
        screenshot(page, row, folder / (label + ".png"), dpr, cdp)
        row["homeSamples"].append(geometry)
        return geometry

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome", headless=True)
        try:
            for mode, samples in matrix + transitions:
                first_size, first_dpr = samples[0]
                name = f"{mode}-{first_size[0]}x{first_size[1]}-dpr{first_dpr:g}"
                folder = output / name
                folder.mkdir(parents=True, exist_ok=True)
                row = {"mode": mode, "size": list(first_size), "dpr": first_dpr, "issues": [], "errors": [], "loadingSamples": [], "homeSamples": [], "engineContractMock": False, "emulatedViewportAndDprChange": False, "dprEventSamples": [], "screenshotDprChecks": []}
                if mode == "loading-dpr-change":
                    row["emulationScope"] = "CDP changes DPR plus a one-CSS-pixel viewport round trip, delivering actual browser resize/resolution events. No manual event dispatch. Direct CDP screenshots preserve metrics. A DPR-only CDP override in this Chrome sends no resolution/resize event; this does not prove physical monitor transitions."
                context = browser.new_context(viewport={"width": first_size[0], "height": first_size[1]}, device_scale_factor=first_dpr)
                page = context.new_page()
                page.on("pageerror", lambda error, row=row: row["errors"].append(str(error)))
                page.on("console", lambda message, row=row: row["errors"].append(message.text) if message.type == "error" else None)
                held_requests = []
                gate = {"released": False}
                def hold_pck(route):
                    if gate["released"]:
                        route.continue_()
                    else:
                        held_requests.append(route)
                page.route("**/*.pck", hold_pck)
                try:
                    page.goto(base + "?qa=1&home=1", wait_until="domcontentloaded", timeout=90000)
                    page.wait_for_function("() => [...document.images].every(image=>image.complete&&image.naturalWidth>0)")
                    cdp = context.new_cdp_session(page)
                    for index, (size, dpr) in enumerate(samples):
                        if index:
                            if mode == "loading-dpr-change":
                                emulate_viewport_and_dpr(page, cdp, size, dpr, row)
                            else:
                                page.set_viewport_size({"width": size[0], "height": size[1]})
                        observe_loader(page, row, size, dpr, "loading" if len(samples) == 1 else f"loading-{index}", folder, cdp)
                    # This is the original PCK fetch, only delayed by automation.
                    # No mocked Engine or substituted game content is used.
                    for attempt in range(300):
                        if held_requests:
                            break
                        page.wait_for_timeout(100)
                    assert held_requests, "The actual PCK request was never observed"
                    gate["released"] = True
                    for route in held_requests:
                        route.continue_()
                    page.wait_for_selector("#status", state="detached", timeout=90000)
                    final_size, final_dpr = samples[-1]
                    home = observe_home(page, row, final_size, final_dpr, "home", folder, cdp)
                    last_loader = row["loadingSamples"][-1]
                    row["transitionPaintedErrorCssPx"] = max_error(last_loader["paintedRect"], home["expectedPaintedRect"])
                    row["transitionTaglineErrorCssPx"] = max_error(last_loader["taglineRect"], home["actualTaglineCssRect"])
                    record_issue(row, row["transitionPaintedErrorCssPx"] <= TOLERANCE, "Loading-to-home painted logo geometry changes")
                    record_issue(row, row["transitionTaglineErrorCssPx"] <= TOLERANCE, "Loading-to-home tagline container geometry changes")
                    if mode == "loading-dpr-change":
                        for dpr in [1.25, 1.5]:
                            emulate_viewport_and_dpr(page, cdp, (1280, 720), dpr, row)
                            observe_home(page, row, (1280, 720), dpr, f"home-dpr{dpr:g}", folder, cdp)
                    record_issue(row, not row["errors"], "Unexpected browser errors: " + str(row["errors"]))
                except Exception as error:
                    row["issues"].append(str(error))
                    try:
                        page.screenshot(path=str(folder / "failure.png"), scale="css")
                    except Exception:
                        pass
                finally:
                    context.close()
                row["passed"] = not row["issues"]
                results.append(row)
                (folder / "checks.json").write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding="utf-8")
                print(json.dumps({"mode": mode, "size": list(first_size), "dpr": first_dpr, "passed": row["passed"], "issues": row["issues"]}, ensure_ascii=False), flush=True)
        finally:
            browser.close()

    stable = read_json_url(base + "__build.json") == metadata
    passed = stable and bool(results) and all(row["passed"] for row in results)
    report = {"passed": passed, "stableServedBuild": stable, "base": base, "build": metadata, "logoSha256": hashlib.sha256((build_dir / "loader/logo.png").read_bytes()).hexdigest(), "toleranceCssPx": TOLERANCE, "results": results, "scope": "Real exported engine/PCK. HTML painted rect is compared against actual headless GardenHUD TextureRect geometry mapped through real browser backing/CSS dimensions. Native browser CoverTagline verifies that the backing prediction and home layout agree. Paired screenshots require visual review; this does not independently inspect the GPU logo pixels."}
    (output / "checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

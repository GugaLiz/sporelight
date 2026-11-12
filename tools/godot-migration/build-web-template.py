"""Build an isolated Godot 4.7.2 Web template; never replace installed templates.

Windows host: Python 3.9+ and Git must already be available. All downloaded
dependencies, engine sources and object files stay below --cache. The only
engine patch delays unused scene-shader defaults; no shader code is changed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import zipfile


ROOT = Path(__file__).resolve().parents[2]
ENGINE_TAG = "4.7.2-stable"
ENGINE_COMMIT = "ed1daf0bf001b61586d9930840f2f1394092c079"
SDK_VERSION = "4.0.20"
SDK_COMMIT = "e4fe26ef59168ff44f4c23c466e497bf60b3411e"
SCONS_VERSION = "4.9.1"
SCONS_SHA256 = "d2db1a22eb6039e97cbbb0106f18f435af033d0aad190299c9688378e2810a5e"
PATCH = ROOT / "tools/godot-migration/patches/godot-4.7.2-web-scene-demand.patch"
TOOLCHAIN_LOCK = ROOT / "tools/godot-migration/web-template-toolchain.lock.json"


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def run(args, *, cwd=None, env=None, capture=False):
    return subprocess.run([str(arg) for arg in args], cwd=cwd, env=env,
                          check=True, text=True, encoding="utf-8", errors="replace",
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT if capture else None).stdout


def checkout(path: Path, url: str, tag: str, commit: str):
    if not path.exists():
        run(["git", "clone", "--depth", "1", "--single-branch", "--branch", tag, url, path])
    actual = run(["git", "-C", path, "rev-parse", "HEAD"], capture=True).strip()
    if actual != commit:
        raise RuntimeError(f"Refusing source at unexpected commit: {path}: {actual}")


def prepare(cache: Path):
    source, sdk = cache / "source", cache / "emsdk"
    checkout(source, "https://github.com/godotengine/godot.git", ENGINE_TAG, ENGINE_COMMIT)
    checkout(sdk, "https://github.com/emscripten-core/emsdk.git", SDK_VERSION, SDK_COMMIT)
    if run(["git", "-C", sdk, "diff", "HEAD", "--name-only"], capture=True).strip():
        raise RuntimeError("Refusing modified SDK bootstrap sources")
    python = cache / "python-env/Scripts/python.exe"
    if not python.exists():
        run([sys.executable, "-m", "venv", python.parent.parent])
    downloads = cache / "downloads"
    downloads.mkdir(exist_ok=True)
    wheel = downloads / f"scons-{SCONS_VERSION}-py3-none-any.whl"
    if not wheel.exists():
        run([python, "-m", "pip", "download", "--no-deps", f"scons=={SCONS_VERSION}", "--dest", downloads])
    if digest(wheel) != SCONS_SHA256:
        raise RuntimeError("SCons wheel SHA256 differs from the pinned build dependency")
    run([python, "-m", "pip", "install", "--no-deps", wheel])
    run([python, sdk / "emsdk.py", "install", SDK_VERSION])
    # No --permanent or --system: no registry or global PATH modification.
    run([python, sdk / "emsdk.py", "activate", SDK_VERSION], capture=True)
    lock = json.loads(TOOLCHAIN_LOCK.read_text(encoding="utf-8"))
    if lock["engineCommit"] != ENGINE_COMMIT or lock["sdkCommit"] != SDK_COMMIT:
        raise RuntimeError("Toolchain lock does not match the pinned recipe")
    for relative, expected in lock["sha256"].items():
        if digest(cache / relative) != expected:
            raise RuntimeError(f"Installed build dependency SHA256 mismatch: {relative}")

    dirty = run(["git", "-C", source, "diff", "HEAD", "--name-only"], capture=True).splitlines()
    if dirty and dirty != ["drivers/gles3/shader_gles3.cpp"]:
        raise RuntimeError(f"Refusing unexpected engine source changes: {dirty}")
    if not dirty:
        run(["git", "-C", source, "apply", "--check", PATCH])
        run(["git", "-C", source, "apply", PATCH])
    else:
        run(["git", "-C", source, "apply", "--reverse", "--check", PATCH])
    # Check the complete tracked diff, not only whether a hunk can reverse.
    expected = PATCH.read_text(encoding="utf-8").splitlines()
    actual = run(["git", "-C", source, "diff", "HEAD", "--no-ext-diff", "--", "drivers/gles3/shader_gles3.cpp"], capture=True).splitlines()
    changes = lambda lines: [line for line in lines if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))]
    if changes(expected) != changes(actual):
        raise RuntimeError("Engine diff contains changes outside the reviewed patch")

    env = os.environ.copy()
    env.update(EMSDK=str(sdk), EM_CONFIG=str(sdk / ".emscripten"),
               EMSDK_NODE=str(sdk / "node/22.16.0_64bit/bin/node.exe"),
               EMSDK_PYTHON=str(sdk / "python/3.13.3_64bit/python.exe"),
               EMCC_CORES="4", PYTHONUNBUFFERED="1")
    env["PATH"] = os.pathsep.join([str(python.parent), str(sdk), str(sdk / "upstream/emscripten"), env["PATH"]])
    return source, sdk, python, env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache/sporelight-godot/custom-web-4.7.2")
    parser.add_argument("--target", choices=["release", "debug"], default="release")
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=4)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/qa-godot-native/custom-web-template")
    options = parser.parse_args()
    if os.name != "nt":
        parser.error("This recipe pins the Windows host toolchain; use a separate lock for another OS")
    cache = options.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source, sdk, python, env = prepare(cache)
    flags = ["platform=web", f"target=template_{options.target}", "arch=wasm32", "threads=no",
             "dlink_enabled=no", "javascript_eval=yes", "production=yes", "debug_symbols=no",
             "optimize=size", "lto=thin", "use_closure_compiler=no", "linkflags=-Wl,--thinlto-jobs=4"]
    tool_files = [sdk / "emsdk.py", sdk / "emsdk_manifest.json", sdk / "upstream/emscripten/emcc.py",
                  sdk / "upstream/bin/clang.exe", sdk / "upstream/bin/wasm-ld.exe",
                  sdk / "upstream/bin/wasm-opt.exe", sdk / "node/22.16.0_64bit/bin/node.exe",
                  sdk / "python/3.13.3_64bit/python.exe", cache / f"downloads/scons-{SCONS_VERSION}-py3-none-any.whl"]
    metadata = {"status": "prepared", "engineTag": ENGINE_TAG, "sourceCommit": ENGINE_COMMIT,
                "sdkVersion": SDK_VERSION, "sdkCommit": SDK_COMMIT, "sconsVersion": SCONS_VERSION,
                "bootstrapPython": sys.version, "cache": str(cache), "target": options.target,
                "patch": str(PATCH.relative_to(ROOT)), "patchSha256": digest(PATCH),
                "patchedSourceSha256": digest(source / "drivers/gles3/shader_gles3.cpp"),
                "flags": flags, "jobs": options.jobs,
                "toolSha256": {str(path.relative_to(cache)): digest(path) for path in tool_files},
                "scope": "Candidate template. Requires cold-start timing and same-scene pixel comparison before adoption."}
    manifest = output / f"{options.target}-build.json"
    manifest.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if options.prepare_only:
        print(f"Prepared only: {manifest}", flush=True)
        return
    print(f"Building {options.target}, {options.jobs} jobs; log: {output / (options.target + '-build.log')}", flush=True)
    start = time.monotonic()
    with (output / f"{options.target}-build.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen([str(python), "-m", "SCons", f"-j{options.jobs}", *flags],
                                   cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT)
        code = process.wait()
    metadata.update(buildSeconds=round(time.monotonic() - start, 3), exitCode=code,
                    status="built" if code == 0 else "failed")
    if code == 0:
        candidates = list((source / "bin").glob(f"godot.web.template_{options.target}.wasm32*.zip"))
        if len(candidates) != 1:
            raise RuntimeError(f"Expected one template archive, got: {candidates}")
        artifact_dir = cache / "artifacts"
        artifact_dir.mkdir(exist_ok=True)
        artifact = artifact_dir / f"godot-4.7.2-web-scene-demand-{options.target}.zip"
        shutil.copy2(candidates[0], artifact)
        metadata.update(template=str(artifact), templateSha256=digest(artifact), templateBytes=artifact.stat().st_size)
        with zipfile.ZipFile(artifact) as archive:
            metadata["members"] = [{"file": item.filename, "bytes": item.file_size,
                                     "sha256": hashlib.sha256(archive.read(item)).hexdigest()}
                                    for item in archive.infolist() if not item.is_dir()]
    manifest.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{metadata['status']}: {manifest}", flush=True)
    sys.exit(code)


if __name__ == "__main__":
    main()

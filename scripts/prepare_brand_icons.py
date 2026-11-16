"""Export code-authored brand vectors to web/native icon formats and a QA sheet."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets/branding"
SIZES = (16, 24, 32, 48, 64, 128, 256)


def pack_ico(prefix: str, target: Path) -> None:
    """Preserve the separately rendered pixel size rather than rescaling an ICO frame."""
    frames = [(size, (BRAND / f"{prefix}-{size}.png").read_bytes()) for size in SIZES]
    offset = 6 + 16 * len(frames)
    directory = bytearray(struct.pack("<HHH", 0, 1, len(frames)))
    payload = bytearray()
    for size, data in frames:
        directory.extend(struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset))
        payload.extend(data)
        offset += len(data)
    target.write_bytes(directory + payload)


def preview(target: Path) -> None:
    sheet = Image.new("RGB", (960, 440), "#f0ebd4")
    draw = ImageDraw.Draw(sheet)
    main = Image.open(BRAND / "icon-512.png").convert("RGBA")
    sheet.paste(main.resize((256, 256), Image.Resampling.LANCZOS), (32, 40), main.resize((256, 256), Image.Resampling.LANCZOS))
    draw.text((34, 314), "Sporelight / mushroom hat + mushroom companion", fill="#435a37")
    for row, (background, foreground) in enumerate((("#f8f6ef", "#435a37"), ("#222b25", "#fff4d5"))):
        top = 30 + row * 190
        draw.rounded_rectangle((332, top, 936, top + 170), radius=18, fill=background)
        draw.text((350, top + 14), "Browser tab / bookmarks: 16, 24, 32, 48 px", fill=foreground)
        for index, size in enumerate((16, 24, 32, 48)):
            icon = Image.open(BRAND / f"favicon-{size}.png").convert("RGBA")
            left = 360 + index * 110
            sheet.paste(icon, (left, top + 57), icon)
            draw.text((left, top + 120), str(size) + " px", fill=foreground)
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(Path.home() / ".cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe")))
    parser.add_argument("--preview", default="docs/qa-godot-native/mushroom-icons/preview.png")
    args = parser.parse_args()
    result = subprocess.run([args.godot, "--headless", "--path", str(ROOT / "godot"), "--script", str(ROOT / "tools/godot-migration/render-brand-icons.gd")], capture_output=True, text=True, encoding="utf-8")
    if result.returncode or any(value in result.stdout + result.stderr for value in ("SCRIPT ERROR:", "Parse Error:", "ERROR:")):
        raise RuntimeError(result.stdout + result.stderr)
    pack_ico("favicon", BRAND / "favicon.ico")
    pack_ico("desktop", BRAND / "sporelight.ico")
    shutil.copyfile(BRAND / "favicon.ico", ROOT / "assets/favicon.ico")
    native = ROOT / "godot/assets/branding"
    native.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(BRAND / "icon-512.png", native / "icon.png")
    shutil.copyfile(BRAND / "sporelight.ico", native / "sporelight.ico")
    preview(ROOT / args.preview)
    outputs = [path for path in sorted(BRAND.iterdir()) if path.suffix in (".svg", ".png", ".ico", ".webmanifest")]
    report = {"version": 2, "source": "Repository-authored SVG following the user's mushroom theme: Luvie's red pointed white-spotted cap and her round-capped mushroom companion. Existing character art is reference only and remains unchanged.", "source_files": ["assets/branding/icon.svg", "assets/branding/favicon.svg", "assets/branding/pinned.svg"], "ico_sizes": list(SIZES), "maskable_safe_zone": "Essential mushroom silhouettes fit within the central 80% diameter; square background is opaque.", "files": [{"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in outputs]}
    (BRAND / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"outputs": len(outputs), "icoSizes": list(SIZES), "preview": args.preview}))


if __name__ == "__main__":
    main()

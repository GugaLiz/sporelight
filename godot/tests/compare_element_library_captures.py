"""Compare native GPU evidence without modifying any game assets."""
import json
import pathlib
import sys
import numpy as np
from PIL import Image, ImageDraw

root = pathlib.Path(sys.argv[1])

def difference(first, second):
    a = np.asarray(Image.open(first).convert("RGBA")).astype(np.int16)
    b = np.asarray(Image.open(second).convert("RGBA")).astype(np.int16)
    assert a.shape == b.shape == (720, 1280, 4)
    delta = np.abs(a - b)
    mask = np.any(delta > 0, axis=2)
    return {"exact": not bool(delta.any()), "changedPixels": int(mask.sum()),
            "totalPixels": int(mask.size), "maxChannelDelta": int(delta.max()),
            "meanChannelDelta": float(delta.mean())}

rows = []
for path in sorted((root / "baseline").glob("*.png")):
    target = root / "current" / path.name
    if target.exists():
        rows.append({"file": path.name, **difference(path, target)})

def sheet(name, entries, columns):
    canvas = Image.new("RGB", (columns * 640, ((len(entries)+columns-1)//columns)*384), (30,30,30))
    draw = ImageDraw.Draw(canvas)
    for i, (kind, filename, label) in enumerate(entries):
        x, y = i%columns*640, i//columns*384
        image = Image.open(root/kind/filename).convert("RGB")
        image.thumbnail((640,360))
        canvas.paste(image, (x,y+24))
        draw.text((x+10,y+6),label,fill="white")
    canvas.save(root/(name+".jpg"),quality=92)

key = ["1-1","2-2","3-2","3-4"]
sheet("key-comparison",[(kind,id+"-cold.png",id+" "+kind) for id in key for kind in ["baseline","current"]],2)
ids=[f"{chapter}-{level}" for chapter in range(1,4) for level in range(1,5)]
sheet("all-cold",[("current",id+"-cold.png",id+" current") for id in ids],3)
sheet("prepared-comparison",[(kind,id+"-prepared-final.png",id+" prepared "+kind) for id in ["1-4","2-2","3-2","3-3","3-4"] for kind in ["baseline","current"]],2)
sheet("companion-skin",[("current",name+".png",label) for name,label in [("3-2-cold","Original companion"),("3-2-test-only-companion-skin","Test-only skin; same body and rules"),("3-2-companion-restored","Original companion restored")]],3)
restored=difference(root/"current/3-2-cold.png",root/"current/3-2-companion-restored.png")
swapped=difference(root/"current/3-2-cold.png",root/"current/3-2-test-only-companion-skin.png")
report={"comparisons":rows,"restoredCompanion":restored,"testOnlySkin":swapped,
        "scope":"Raw RGBA pixel differences; no threshold hides changes. Contact sheets are QA previews. No image is retouched."}
(root/"pixel-diff.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(json.dumps(report))

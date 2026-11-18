"""Regenerate small, public loading pictures from the existing home artwork.
Requires Pillow only for asset maintenance; normal Godot exports copy the saved files.
"""
import argparse, io, json
from pathlib import Path
from PIL import Image

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check",action="store_true",help="Compare the saved pictures and manifest without writing.")
args=parser.parse_args()
root=Path(__file__).resolve().parents[2];out=root/"godot/web/loader"
items=[("bg.webp","main/bg.png",1600,"WEBP"),("logo.png","material-ready/menu-logo.png",648,"PNG"),("hero.png","character-refined/idle-front.png",384,"PNG"),("orb.png","menu-fx-redrawn/orb.png",128,"PNG"),
       ("sowing.png","character-refined/sow-1.png",384,"PNG"),("moss.png","production/moss.png",384,"PNG"),("lantern.png","garden-scenery/stone-lantern.png",192,"PNG"),("flowers.png","garden-scenery/yellow-flowers.png",192,"PNG"),
       ("night-ruins.webp","home-loading-refine-20261118/masters/night-ruins.png",1600,"WEBP")]
rows=[]

# The loading shell is outside the PCK and cannot call ElementAssets. Resolve
# the same original bitmap identity before packaging its small public copies.
redraw_file=root/"godot/content/bitmap-redraw.json"
redraw=json.loads(redraw_file.read_text(encoding="utf-8")) if redraw_file.exists() else {"schema_version":1,"source_overrides":{}}
if redraw.get("schema_version")!=1 or not isinstance(redraw.get("source_overrides"),dict):
    raise SystemExit("Invalid bitmap-redraw.json")
theme=json.loads((root/"godot/content/element-theme.json").read_text(encoding="utf-8"))
visual=json.loads((root/"godot/content/visual-assets.json").read_text(encoding="utf-8"))
theme_sources={}
for entry in visual["entries"]:
    replacement=theme.get("resource_overrides",{}).get(entry["id"])
    if not replacement:continue
    source=entry["resource"]
    if source in theme_sources and theme_sources[source]!=replacement:
        raise SystemExit("Conflicting replacements for shared bitmap: "+source)
    theme_sources[source]=replacement

def effective_source(source):
    original="res://assets/images/"+source
    effective=theme_sources.get(original,redraw["source_overrides"].get(original,original))
    if effective==original:return root/"assets/images"/source
    if not isinstance(effective,str) or not effective.startswith("res://assets/images/"):
        raise SystemExit("Invalid loading bitmap replacement: "+str(effective))
    path=(root/"godot"/effective.removeprefix("res://")).resolve()
    if not path.is_relative_to((root/"godot/assets/images").resolve()) or not path.is_file():
        raise SystemExit("Loading bitmap replacement is missing: "+effective)
    with Image.open(root/"assets/images"/source) as original_image,Image.open(path) as replacement:
        if original_image.size!=replacement.size:raise SystemExit("Loading bitmap canvas differs: "+source)
    return path
def emit(name,data):
    path=out/name
    if args.check:
        saved=path.read_bytes()
        same=json.loads(saved)==json.loads(data) if name.endswith(".json") else saved==data
        if not same:raise SystemExit("Loading asset differs; regenerate: "+name)
    else:
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
for name,source,width,fmt in items:
    source_path=effective_source(source)
    image=Image.open(source_path).convert("RGBA" if fmt=="PNG" else "RGB")
    image.thumbnail((width,10000),Image.Resampling.LANCZOS)
    buffer=io.BytesIO()
    image.save(buffer,fmt,**({"quality":84,"method":6} if fmt=="WEBP" else {"optimize":True}))
    data=buffer.getvalue();emit(name,data)
    row={"file":name,"source":source_path.relative_to(root).as_posix(),"width":image.width,"height":image.height,"bytes":len(data)}
    if row["source"]!="assets/images/"+source:row["originalSource"]="assets/images/"+source
    rows.append(row)
manifest={"purpose":"Lightweight browser bootstrap artwork derived from the existing home assets; available before PCK loads.","assets":rows}
emit("manifest.json",json.dumps(manifest,indent=2).encode())
emit(".gdignore",b"")
print(json.dumps({"mode":"check" if args.check else "generate","assets":len(rows),"totalBytes":sum(r["bytes"] for r in rows)}))

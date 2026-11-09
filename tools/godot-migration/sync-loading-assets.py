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
items=[("bg.webp","main/bg.png",1600,"WEBP"),("logo.png","material-ready/menu-logo.png",648,"PNG"),("hero.png","menu-walk-redrawn/idle-front.png",384,"PNG"),("orb.png","menu-fx-redrawn/orb.png",128,"PNG")]
rows=[]
def emit(name,data):
    path=out/name
    if args.check:
        saved=path.read_bytes()
        same=json.loads(saved)==json.loads(data) if name.endswith(".json") else saved==data
        if not same:raise SystemExit("Loading asset differs; regenerate: "+name)
    else:
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
for name,source,width,fmt in items:
    image=Image.open(root/"assets/images"/source).convert("RGBA" if fmt=="PNG" else "RGB")
    image.thumbnail((width,10000),Image.Resampling.LANCZOS)
    buffer=io.BytesIO()
    image.save(buffer,fmt,**({"quality":84,"method":6} if fmt=="WEBP" else {"optimize":True}))
    data=buffer.getvalue();emit(name,data)
    rows.append({"file":name,"source":"assets/images/"+source,"width":image.width,"height":image.height,"bytes":len(data)})
manifest={"purpose":"Lightweight browser bootstrap artwork derived from the existing home assets; available before PCK loads.","assets":rows}
emit("manifest.json",json.dumps(manifest,indent=2).encode())
emit(".gdignore",b"")
print(json.dumps({"mode":"check" if args.check else "generate","assets":len(rows),"totalBytes":sum(r["bytes"] for r in rows)}))

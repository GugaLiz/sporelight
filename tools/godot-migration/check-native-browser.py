"""Real browser checks for the native game. QA prepares states and observes;
all actions under test use actual pointer/keyboard events in an isolated context."""
import argparse, base64, json, math, sys, time, traceback, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright
parser = argparse.ArgumentParser()
parser.add_argument("--base", default="http://localhost:4190/")
parser.add_argument("--output", default="docs/qa-godot-native/browser")
parser.add_argument("--mode", choices=["capture", "gameplay", "home", "cover", "motion", "mechanisms", "first-garden"], default="capture")
parser.add_argument("--levels", default="")
parser.add_argument("--sizes", default="1280x720,390x844,568x320")
parser.add_argument("--off-axis", action="store_true", help="Walk onto the water module arm before the rotation sample (3-3).")
args = parser.parse_args()
with urllib.request.urlopen(args.base.rstrip("/")+"/__build.json") as response:
    build=json.load(response)
OUT = ROOT / args.output
OUT.mkdir(parents=True, exist_ok=True)
selected = args.levels.split(",") if args.levels else []
main = json.loads((ROOT / "godot/tests/fixtures/reference.json").read_text(encoding="utf-8"))
cases = [{"id": e["levelId"], "initial": e["initial"]["snapshot"], "steps": e["steps"]} for e in main["cases"] if e["name"].startswith("authored/")]
cloud = json.loads((ROOT / "godot/tests/fixtures/cloud-reference.json").read_text(encoding="utf-8"))
def native_cloud(s):
    result={"designVersion":2,"levelId":s["levelId"],"active":"luvie","actors":{"luvie":s["tile"],"buddy":"floor:3:6" if s["buddy"]=="wait" else s["tile"]},
        "follow":s["buddy"]=="follow","growth":{},"turns":{"bridge":1 if s["bridge"]=="east" else 0,"lift":1 if s["lift"]=="high" else 0},
        "flags":[],"items":{},"collected":s["found"],"observations":s["found"],"discovered":[],"water":0,"mode":0,"frozen":None,
        "song":["turn","rise","rest"],"beat":0,"playing":False,"completed":s["repaired"],"cloudSeed":s["seed"],"cloudLatch":s["latch"],"cloudBuddy":s["buddy"]}
    if s["levelId"]=="cloud-1" and s["buddy"]=="sleep":
        result["actors"]["buddy"]="floor:10:3"
    return result
cases += [{"id":e["id"],"initial":native_cloud(e["initial"]),"steps":[{"command":step["command"],"snapshot":native_cloud(step["snapshot"])} for step in e["steps"]]} for e in cloud["levels"]]
results, errors = [], []
def state(page):
    return page.evaluate("() => structuredClone(window.__sporelightState)")
def fresh(page):
    n = state(page).get("qaSequence", 0)
    page.wait_for_function("n => window.__sporelightState?.qaSequence > n", arg=n, timeout=15000)
    return state(page)
def click_rect(page, rect, touch=False):
    # A modal can be opened before Godot's deferred container pass is drawn.
    # Let geometry settle so a tap cannot land on the following row.
    page.wait_for_timeout(180)
    canvas = page.locator("#canvas")
    box = canvas.bounding_box()
    backing = canvas.evaluate("e => [e.width, e.height]")
    x, y, w, h = rect
    point = (box["x"]+(x+w/2)*box["width"]/backing[0], box["y"]+(y+h/2)*box["height"]/backing[1])
    if touch: page.touchscreen.tap(*point)
    else: page.mouse.click(*point)
def find_button(page, query, touch=False, optional=False):
    for attempt in range(32):
        s = fresh(page)
        candidates = [b for b in s.get("buttons", []) if not b.get("disabled") and all((v in b.get("text","") if k=="contains" else b.get(k)==v) for k,v in query.items())]
        if candidates:
            b = candidates[-1]
            rect = b.get("visibleRect", [b["x"],b["y"],b["width"],b["height"]])
            if rect[2]>3 and rect[3]>3:
                click_rect(page, rect, touch)
                return b
        if attempt>2:
            scrolls = [c for c in s.get("ui",{}).get("controls",[]) if c["class"]=="ScrollContainer" and c.get("visibleRect",[0,0,0,0])[3]>20]
            if scrolls:
                r=scrolls[-1]["visibleRect"]
                targets=[c for c in s.get("ui",{}).get("controls",[]) if c.get("class","").endswith("Button") and all((v in c.get("text","") if k=="contains" else c.get(k)==v) for k,v in query.items())]
                direction=-1 if targets and targets[-1].get("y",0)<r[1] else 1 if targets else 1 if attempt%16<8 else -1
                page.mouse.move(r[0]+r[2]/2,r[1]+r[3]/2)
                page.mouse.wheel(0,direction*200)
        page.wait_for_timeout(40)
    if optional: return None
    raise AssertionError("No enabled real button "+str(query))

def open_home_child(page, caption, touch=False):
    # Follow the same visible category paths as a player; hidden controls are
    # deliberately absent from the QA bridge and must never be clicked directly.
    if caption in ["图鉴", "花园纪事", "云庭微光"]:
        s=fresh(page)
        if not any(c.get("text")=="图鉴" for c in s.get("ui",{}).get("controls",[])):
            find_button(page,{"action":"home_explore"},touch)
    elif caption=="导入 / 导出旅程":
        find_button(page,{"action":"settings"},touch)
    find_button(page,{"contains":caption},touch)
def stable(page, level=None):
    sequence=state(page).get("qaSequence",0)
    page.wait_for_function("""value => {
        const s=window.__sporelightState;
        return s && s.qaSequence>value.sequence+1 && (!value.level || s.snapshot.levelId===value.level) && !s.moving;
    }""",arg={"level":level,"sequence":sequence},timeout=20000)
    return fresh(page)
def prepare(page, snapshot):
    page.evaluate("snapshot => window.__sporelightRequest(JSON.stringify({type:'snapshot',snapshot,time:1200}))",snapshot)
    page.wait_for_function("id => window.__sporelightState?.snapshot?.levelId===id && !window.__sporelightState.homeActive",arg=snapshot["levelId"],timeout=15000)
    return stable(page,snapshot["levelId"])
def check_contacts(s, label):
    assert s.get("native"), label+": native movement active"
    for who, actor in s["native"].get("actors",{}).items():
        p=actor["position"]
        assert all(math.isfinite(v) for v in p), label+": finite "+who
        assert actor["support"]==s["snapshot"]["actors"][who], label+": support "+who
        assert abs(p[1]-actor["floorHeight"])<0.16, label+": ground contact "+who+" "+str(actor)
def open_game(page, level, touch=False):
    s=fresh(page)
    if not s.get("homeActive"):
        page.keyboard.press("Escape")
        find_button(page,{"action":"home"},touch)
    find_button(page,{"action":"map"},touch)
    find_button(page,{"contains":level+"  "},touch)
    return stable(page,level)
def move_to(page, tile):
    s=fresh(page)
    actor=s["snapshot"]["active"]
    if s["snapshot"]["actors"][actor]==tile:
        return s
    target=next((t for t in s["targets"] if t["id"]==tile),None)
    if target and 0<target["x"]<s["viewport"][0] and 0<target["y"]<s["viewport"][1]:
        click_rect(page,[target["x"]-1,target["y"]-1,2,2])
        try:
            page.wait_for_function("tile => {const s=window.__sporelightState;return s?.snapshot.actors[s.snapshot.active]===tile&&!s.moving;}",arg=tile,timeout=2500)
            return fresh(page)
        except Exception:
            pass
    # A deliberately hidden or offscreen path can be traversed by keyboard.
    # Build a path only through the current rule-authorized tile graph; every
    # segment is still executed by real held input and the in-game guard.
    s=fresh(page)
    tiles={t["id"]:t for t in s.get("tiles",[])}
    at=s["snapshot"]["actors"][actor]
    queue=[(at,[])];seen={at};path=None
    for key,route in queue:
        if key==tile: path=route;break
        a=tiles[key]
        for name,b in tiles.items():
            if name in seen or b.get("solid") or actor=="luvie" and b.get("small"):continue
            if abs(a["x"]-b["x"])+abs(a["z"]-b["z"])!=1:continue
            if abs(a["h"]-b["h"])>1:continue
            if s["snapshot"]["levelId"].startswith("cloud-") and a["h"]!=b["h"] and "stair" not in [a.get("kind"),b.get("kind")]:continue
            seen.add(name);queue.append((name,route+[name]))
    assert path is not None,"connected keyboard route "+tile
    for dest in path:
        s=fresh(page);a=tiles[s["snapshot"]["actors"][actor]];b=tiles[dest]
        key="ArrowRight" if b["x"]>a["x"] else "ArrowLeft" if b["x"]<a["x"] else "ArrowDown" if b["z"]>a["z"] else "ArrowUp"
        page.keyboard.down(key)
        try:
            page.wait_for_function("value => {const s=window.__sporelightState;return s?.snapshot.actors[value.actor]===value.tile;}",arg={"actor":actor,"tile":dest},timeout=6000)
        finally:
            page.keyboard.up(key)
        stable(page)
    return fresh(page)
def action(page, command):
    s=fresh(page)
    before_revision=s["revision"]
    if command=="switch":
        page.keyboard.press("t")
    elif command=="follow":
        find_button(page,{"action":"follow"})
    else:
        commands=[c for c in s.get("commands",[]) if c["id"] not in ["switch","follow"]]
        index=next((i for i,c in enumerate(commands) if c["id"]==command),None)
        assert index is not None, "available command "+command+"; actual "+str(commands)
        # Real numeric shortcuts remain optional; using them here verifies the
        # actual event path without relying on action injection.
        if index<9:
            page.keyboard.press(str(index+1))
        else:
            find_button(page,{"action":"primary"})
            find_button(page,{"command_id":command})
    result=stable(page)
    assert command=="pet" or result["revision"]>before_revision, "action did not commit: "+command+"; "+result.get("message","")
    return result
def run_case(browser, size, case, mode):
    folder=OUT/(str(size[0])+"x"+str(size[1]))/case["id"]
    folder.mkdir(parents=True,exist_ok=True)
    context=browser.new_context(viewport={"width":size[0],"height":size[1]},has_touch=size[0]<600,device_scale_factor=1)
    page=context.new_page()
    local_errors=[]
    page.on("pageerror",lambda e:local_errors.append(str(e)))
    page.on("console",lambda m:local_errors.append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
    row={"level":case["id"],"size":list(size),"mode":mode}
    try:
        page.goto(args.base+"?qa=1",wait_until="networkidle",timeout=120000)
        page.wait_for_function("() => typeof window.__sporelightRequest==='function' && window.__sporelightState?.snapshot",timeout=120000)
        s=prepare(page,case["initial"])
        check_contacts(s,"arrival")
        page.screenshot(path=str(folder/"arrival.png"))
        if mode=="capture":
            final=case["steps"][-1]["snapshot"]
            s=prepare(page,final)
            check_contacts(s,"restored")
            page.screenshot(path=str(folder/"restored.png"))
        else:
            expected_before=case["initial"]
            for i,step in enumerate(case["steps"]):
                c=step["command"]
                row["step"]=i
                row["command"]=c
                if c["kind"]=="move": s=move_to(page,c["value"])
                elif c["kind"]=="act":
                    active=fresh(page)["snapshot"]["active"]
                    intended=expected_before["actors"][active]
                    if fresh(page)["snapshot"]["actors"][active]!=intended:
                        move_to(page,intended)
                    s=action(page,c["value"])
                elif c["kind"]=="undo":
                    page.keyboard.press("z");s=stable(page)
                check_contacts(s,"step "+str(i))
                expected_before=step["snapshot"]
            assert s["snapshot"]["completed"],"completed through real input"
            page.screenshot(path=str(folder/"completed.png"))
        assert not local_errors, "browser/Godot errors: "+str(local_errors[:5])
        row["passed"]=True
        row["native"]=s["native"]
        row["performance"]=s.get("performance")
    except Exception as e:
        row.update(passed=False,reason=str(e),actual=state(page) if page else None)
        page.screenshot(path=str(folder/"failure.png"))
    finally:
        row["errors"]=local_errors
        (folder/"checks.json").write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding="utf-8")
        context.close()
    results.append(row)
    print(json.dumps({k:row.get(k) for k in ["level","size","mode","passed","step","command","reason"]},ensure_ascii=False),flush=True)
def run_first_garden(browser, size):
    """Story, optional exploration and both directions survive an art revision."""
    folder = OUT / (str(size[0])+"x"+str(size[1])) / "first-garden"
    folder.mkdir(parents=True, exist_ok=True)
    context = browser.new_context(viewport={"width":size[0], "height":size[1]}, device_scale_factor=1)
    page = context.new_page()
    local_errors = []
    page.on("pageerror", lambda e: local_errors.append(str(e)))
    page.on("console", lambda m: local_errors.append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
    row = {"mode":"first-garden", "size":list(size), "evidence":[]}
    initial = next(c["initial"] for c in cases if c["id"]=="1-1")
    def record(label):
        s = stable(page)
        check_contacts(s, label)
        row["evidence"].append({"phase":label, "snapshot":s["snapshot"], "native":s["native"]})
        page.screenshot(path=str(folder/(label+".png")))
        return s
    def held(key, duration):
        page.keyboard.down(key)
        page.wait_for_timeout(duration)
        page.keyboard.up(key)
        return stable(page)
    try:
        page.goto(args.base+"?qa=1", wait_until="networkidle", timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot", timeout=120000)
        prepare(page, initial)
        # A missing seed bridge must remain a real gap for walking and hopping.
        s = held("ArrowRight", 850)
        assert s["snapshot"]["actors"]["luvie"]=="f:0:0", "unplanted east gap stays closed"
        page.keyboard.press("Space"); stable(page)
        assert fresh(page)["snapshot"]["actors"]["luvie"]=="f:0:0", "jump cannot bypass east seed"
        held("ArrowLeft", 110)
        s = held("ArrowDown", 850)
        assert s["snapshot"]["actors"]["luvie"]=="f:0:0", "unplanted south gap stays closed"
        record("unplanted-gaps")
        prepare(page, initial)
        # Direct completion is legitimate without collecting any spores.
        action(page, "grow:root:right")
        record("east-road")
        for tile in ["g:root:1:0", "f:2:0", "f:3:0", "f:3:-1", "f:3:-2"]:
            move_to(page, tile)
        assert not fresh(page)["snapshot"]["collected"], "direct route requires no collectible"
        action(page, "repair")
        page.wait_for_function("() => window.__sporelightState?.snapshot.completed", timeout=15000)
        s = record("direct-complete")
        assert not s["snapshot"]["collected"], "zero-collection completion remains valid"
        prepare(page, initial)
        # Optional exploration includes the original observation and all spores.
        for tile in ["f:-1:0", "f:-2:0", "f:-2:-1"]:
            move_to(page, tile)
        move_to(page, "f:0:0")
        action(page, "grow:root:down")
        record("south-road")
        move_to(page, "g:root:0:1")
        before = fresh(page)["snapshot"]
        index = next(i for i,c in enumerate([c for c in fresh(page)["commands"] if c["id"] not in ["switch","follow"]]) if c["id"]=="retract:root")
        page.keyboard.press(str(index+1))
        s = stable(page)
        assert s["snapshot"]["growth"]==before["growth"], "cannot retract occupied bridge"
        assert s["snapshot"]["actors"]==before["actors"], "failed retract preserves actors"
        for tile in ["f:0:2", "f:0:3"]:
            move_to(page, tile)
        action(page, "observe:observe")
        s = record("optional-observation")
        assert len(s["snapshot"]["collected"])==3, "optional route retains all three original spores"
        for tile in ["f:0:2", "g:root:0:1", "f:0:0", "f:0:-1"]:
            move_to(page, tile)
        page.wait_for_timeout(900)
        action(page, "retract:root")
        assert not fresh(page)["snapshot"]["growth"]["root"], "safe return allows reclaim"
        page.keyboard.press("z"); s = stable(page)
        assert s["snapshot"]["growth"]["root"]==["g:root:0:1"], "undo restores south bridge"
        action(page, "retract:root")
        move_to(page, "f:0:0")
        action(page, "grow:root:right")
        # Same origin storage, loaded through the actual Continue button.
        page.wait_for_timeout(600)
        page.reload(wait_until="networkidle", timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot", timeout=120000)
        if fresh(page).get("homeActive"):
            find_button(page, {"action":"continue"})
        s = stable(page)
        assert s["snapshot"]["growth"]["root"]==["g:root:1:0"], "reload retains replanted direction"
        assert len(s["snapshot"]["collected"])==3, "reload retains optional discoveries"
        for tile in ["g:root:1:0", "f:2:0", "f:2:-1", "f:2:0", "f:3:0", "f:3:-1", "f:3:0", "f:4:0", "f:4:-1", "f:4:0", "f:3:0"]:
            move_to(page, tile)
            check_contacts(fresh(page), "terrace "+tile)
        record("terrace-return")
        move_to(page, "f:3:-1")
        move_to(page, "f:3:-2")
        action(page, "repair")
        page.wait_for_function("() => window.__sporelightState?.snapshot.completed", timeout=15000)
        record("exploration-complete")
        assert not local_errors, str(local_errors[:5])
        row["passed"] = True
    except Exception as e:
        row.update(passed=False, reason=str(e), actual=state(page))
        page.screenshot(path=str(folder/"failure.png"))
    finally:
        row["errors"] = local_errors
        (folder/"checks.json").write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding="utf-8")
        context.close()
    results.append(row)
    print(json.dumps({k:row.get(k) for k in ["size","mode","passed","reason"]}, ensure_ascii=False), flush=True)

def run_home(browser, size, touch):
    folder=OUT/(str(size[0])+"x"+str(size[1])+("-touch" if touch else "-mouse"))/"home"
    folder.mkdir(parents=True,exist_ok=True)
    context=browser.new_context(viewport={"width":size[0],"height":size[1]},has_touch=touch,device_scale_factor=1)
    page=context.new_page()
    local_errors=[]
    page.on("pageerror",lambda e:local_errors.append(str(e)))
    page.on("console",lambda m:local_errors.append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
    row={"size":list(size),"mode":"home","touch":touch,"evidence":[]}
    def expect_home():
        page.wait_for_function("() => {const s=window.__sporelightState;return s?.homeActive&&s.paused&&!s.worldVisible&&!s.gameHudVisible;}",timeout=15000)
        return fresh(page)
    try:
        page.goto(args.base+"?qa=1&home=1",wait_until="networkidle",timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot",timeout=120000)
        expect_home()
        for child in ["设置","图鉴","花园纪事","导入 / 导出旅程"]:
            open_home_child(page,child,touch)
            assert fresh(page)["homeActive"],"home child keeps world hidden"
            page.keyboard.press("Escape")
            if child=="导入 / 导出旅程":
                assert any(c.get("setting_id")=="bgm" for c in fresh(page)["ui"]["controls"]),"save tools return to settings"
                page.keyboard.press("Escape")
            expect_home()
        find_button(page,{"action":"map"},touch)
        page.wait_for_timeout(300)
        find_button(page,{"contains":"1-1  "},touch)
        s=stable(page,"1-1")
        assert not s["homeActive"] and not s["paused"]
        # E opens a direction choice without selecting the puzzle answer.
        before=s["revision"]
        find_button(page,{"action":"primary"},touch)
        s=fresh(page)
        assert s["revision"]==before,"opening root choice never plants a road"
        find_button(page,{"command_id":"grow:root:down"},touch)
        s=stable(page)
        assert s["snapshot"]["growth"]["root"]==["g:root:0:1"],"explicit chosen seed road"
        s=move_to(page,"g:root:0:1")
        snapshot=s["snapshot"]
        row["evidence"].append({"phase":"after-move","snapshot":snapshot,"progress":s.get("progress"),"message":s.get("message")})
        page.keyboard.press("Escape")
        find_button(page,{"action":"home"},touch)
        at_home=expect_home()
        page.screenshot(path=str(folder/"saved-home.png"))
        row["evidence"].append({"phase":"returned-home","snapshot":at_home["snapshot"],"progress":at_home.get("progress"),"message":at_home.get("message")})
        assert at_home["snapshot"]["actors"]==snapshot["actors"],"home preserves committed positions"
        page.keyboard.press("ArrowRight")
        page.keyboard.press("e")
        later=fresh(page)
        assert later["snapshot"]["actors"]==at_home["snapshot"]["actors"],"home blocks world input"
        assert later["snapshot"]["growth"]==snapshot["growth"],"home preserves planted road"
        page.wait_for_timeout(500)
        page.reload(wait_until="networkidle",timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot",timeout=120000)
        reloaded=expect_home()
        row["evidence"].append({"phase":"reloaded-home","snapshot":reloaded["snapshot"],"progress":reloaded.get("progress"),"message":reloaded.get("message")})
        find_button(page,{"action":"continue"},touch)
        s=stable(page,"1-1")
        assert s["snapshot"]["growth"]==snapshot["growth"],"Web reload continues planted road"
        assert s["snapshot"]["actors"]["luvie"]=="g:root:0:1","continue restores location"
        check_contacts(s,"continued")
        page.screenshot(path=str(folder/"continued.png"))
        assert not local_errors,str(local_errors[:5])
        row["passed"]=True
    except Exception as e:
        row.update(passed=False,reason=str(e),actual=state(page))
        page.screenshot(path=str(folder/"failure.png"))
    finally:
        row["errors"]=local_errors
        (folder/"checks.json").write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding="utf-8")
        context.close()
    results.append(row)
    print(json.dumps({k:row.get(k) for k in ["size","mode","touch","passed","reason"]},ensure_ascii=False),flush=True)

def run_cover(browser, size):
    folder=OUT/(str(size[0])+"x"+str(size[1]))/"cover"
    folder.mkdir(parents=True,exist_ok=True)
    context=browser.new_context(viewport={"width":size[0],"height":size[1]},device_scale_factor=1,has_touch=size[0]<600)
    page=context.new_page();local_errors=[]
    page.on("pageerror",lambda e:local_errors.append(str(e)))
    page.on("console",lambda m:local_errors.append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
    row={"size":list(size),"mode":"cover","frames":[]}
    def expect_cover():
        page.wait_for_selector("#status",state="detached",timeout=90000)
        page.wait_for_function("() => {const s=window.__sporelightState;return s?.homeActive&&!s.worldVisible&&s.ui.controls.some(c=>c.path.includes('/OriginalMenuCover/'));}",timeout=15000)
        return fresh(page)
    try:
        page.goto(args.base+"?qa=1&home=1&unlockAll=0",wait_until="networkidle",timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot",timeout=120000)
        s=expect_cover();before=s["snapshot"]
        # The bridge exposes interactive controls and text, not decorative sprites.
        # Logo/actor pixels are reviewed in the actual screenshots and native suite.
        taglines=[c for c in s["ui"]["controls"] if c["name"]=="CoverTagline"]
        assert taglines and taglines[0]["visibleRect"][2]>=140,"cover brand area is visible"
        buttons=[b for b in s["ui"]["controls"] if b.get("action") in ["map","continue","home_explore","settings"]]
        assert {b.get("action") for b in buttons}=={"map","continue","home_explore","settings"},"compact home exposes four categorized entry intents"
        assert not any(b.get("action")=="cloud_map" for b in s["ui"]["controls"]),"exploration is initially folded"
        assert all(b["height"]>=44 and b["width"]>=44 for b in buttons),"real controls retain minimum hit size"
        row["buttons"]=buttons;row["brandTagline"]=taglines[0]
        # Wait on the actual cover clock: no state injection or synthetic frame seek.
        start=time.monotonic()
        times=[0,4,7.5,10,14.5,20.5] if size==(1280,720) else [0]
        for index,target in enumerate(times):
            page.wait_for_timeout(max(0,target-(time.monotonic()-start))*1000)
            image_bytes=page.screenshot(path=str(folder/("animation-"+str(index)+".png")))
            row["frames"].append({"afterReadySeconds":time.monotonic()-start,"bytes":len(image_bytes)})
        for child in ["设置","图鉴","花园纪事","导入 / 导出旅程"]:
            open_home_child(page,child)
            assert fresh(page)["homeActive"],"child page keeps the level hidden"
            page.keyboard.press("Escape")
            if child=="导入 / 导出旅程":page.keyboard.press("Escape")
            s=expect_cover()
            assert s["snapshot"]==before,"cover child navigation preserves rules"
        open_home_child(page,"云庭微光")
        page.wait_for_function("() => window.__sporelightState?.buttons.some(b=>b.text.startsWith('cloud-1  ')&&b.visibleRect?.[3]>20)",timeout=5000)
        s=fresh(page)
        assert any(b.get("text","").startswith("cloud-1  ") and b.get("visibleRect",[0,0,0,0])[3]>20 for b in s["buttons"]),"cloud entry focuses its existing map section"
        page.screenshot(path=str(folder/"cloud-map.png"))
        page.keyboard.press("Escape");expect_cover()
        # Verify the reduced-motion cover through the real settings toggle.
        find_button(page,{"action":"settings"})
        for unused in range(15):
            s=fresh(page);toggle=next((c for c in s["ui"]["controls"] if c.get("setting_id")=="lowMotion"),None)
            if toggle and toggle.get("visibleRect",[0,0,0,0])[3]>25:
                click_rect(page,toggle["visibleRect"]);break
            page.mouse.move(size[0]/2,size[1]/2);page.mouse.wheel(0,180);page.wait_for_timeout(80)
        else: raise AssertionError("reduced motion setting is reachable")
        assert fresh(page)["settings"]["lowMotion"],"actual reduced-motion toggle applied"
        page.keyboard.press("Escape");expect_cover();page.mouse.move(1,1);page.wait_for_timeout(400)
        a=page.screenshot(path=str(folder/"low-motion-a.png"));page.wait_for_timeout(700)
        b=page.screenshot(path=str(folder/"low-motion-b.png"))
        assert a==b,"reduced-motion cover stays still"
        # Compare real GPU pixels with the scene held still: focus must use the
        # same surface as pointer hover, not a separate rectangular overlay.
        s=fresh(page);primary=next(c for c in s["ui"]["controls"] if c.get("action")=="map")
        r=primary["visibleRect"]
        assert r[2]>40 and r[3]>40,"primary is visible for focus/hover comparison"
        clip={"x":r[0],"y":r[1],"width":r[2],"height":r[3]}
        focused=page.screenshot(path=str(folder/"primary-focused.png"),clip=clip)
        page.keyboard.press("Tab")
        page.mouse.move(r[0]+r[2]/2,r[1]+r[3]/2);page.wait_for_timeout(120)
        hovered=page.screenshot(path=str(folder/"primary-hovered.png"),clip=clip)
        assert focused==hovered,"actual keyboard-focus and pointer-hover button pixels match"
        row["focusMatchesHover"]=True
        # Tab left focus on the collection toggle while the mouse hovered start.
        page.keyboard.press("Space");s=fresh(page)
        assert any(c.get("text")=="图鉴" for c in s["ui"]["controls"]),"keyboard can expand collections"
        page.keyboard.press("Space");s=fresh(page)
        assert not any(c.get("text")=="图鉴" for c in s["ui"]["controls"]),"keyboard can fold collections"
        assert not local_errors,str(local_errors[:5]);row["passed"]=True
    except Exception as e:
        row.update(passed=False,reason=str(e),actual=state(page))
        page.screenshot(path=str(folder/"failure.png"))
    finally:
        row["errors"]=local_errors;context.close()
        (folder/"checks.json").write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding="utf-8")
    results.append(row)
    print(json.dumps({k:row.get(k) for k in ["size","mode","passed","reason"]},ensure_ascii=False),flush=True)

def run_motion(browser, size):
    folder=OUT/(str(size[0])+"x"+str(size[1]))/"motion"
    folder.mkdir(parents=True,exist_ok=True)
    context=browser.new_context(viewport={"width":size[0],"height":size[1]},device_scale_factor=1,record_video_dir=str(folder/"video"))
    page=context.new_page()
    local_errors=[]
    page.on("pageerror",lambda e:local_errors.append(str(e)))
    page.on("console",lambda m:local_errors.append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
    row={"size":list(size),"mode":"motion"}
    try:
        page.goto(args.base+"?qa=1",wait_until="networkidle",timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot",timeout=120000)
        case=next(c for c in cases if c["id"]=="1-1")
        s=prepare(page,case["initial"])
        initial_actors=s["snapshot"]["actors"]
        page.keyboard.press("Escape")
        find_button(page,{"action":"mode"})
        page.wait_for_function("() => window.__sporelightState?.rolling && window.__sporelightState?.character?.luvie?.clip==='roll'",timeout=5000)
        page.screenshot(path=str(folder/"rolling.png"))
        s=fresh(page)
        assert s["snapshot"]["actors"]==initial_actors,"cosmetic mode preserves rule position"
        page.keyboard.press("j")
        page.wait_for_function("() => window.__sporelightState?.character?.luvie?.clip==='jump'",timeout=5000)
        page.wait_for_timeout(130)
        page.screenshot(path=str(folder/"jump.png"))
        page.wait_for_function("() => window.__sporelightState?.character?.luvie?.clip==='roll'",timeout=5000)
        page.keyboard.press("Escape")
        find_button(page,{"action":"mode"})
        page.wait_for_function("() => !window.__sporelightState?.rolling",timeout=5000)
        find_button(page,{"action":"primary"})
        find_button(page,{"command_id":"grow:root:right"})
        stable(page)
        samples=[]
        page.keyboard.down("ArrowRight")
        try:
            for threshold in [0.4,1.0,1.4,1.8,2.2,2.8,3.2]:
                page.wait_for_function("x => window.__sporelightState?.native?.actors?.luvie?.position?.[0] > x",arg=threshold,timeout=8000)
                s=fresh(page)
                check_contacts(s,"continuous slope "+str(threshold))
                samples.append(s["native"])
                page.screenshot(path=str(folder/("slope-"+str(threshold)+".png")))
        finally:
            page.keyboard.up("ArrowRight")
        s=stable(page)
        before=s["native"]["actors"]["luvie"]["position"]
        page.wait_for_timeout(200)
        after=fresh(page)["native"]["actors"]["luvie"]["position"]
        assert math.dist(before,after)<0.005,"release stops without recentering"
        assert not local_errors,str(local_errors[:5])
        row.update(passed=True,samples=samples)
    except Exception as e:
        row.update(passed=False,reason=str(e),actual=state(page))
        page.screenshot(path=str(folder/"failure.png"))
    finally:
        row["errors"]=local_errors
        context.close()
        (folder/"checks.json").write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding="utf-8")
    results.append(row)
    print(json.dumps({k:row.get(k) for k in ["size","mode","passed","reason"]},ensure_ascii=False),flush=True)

def run_mechanism(browser, size, level):
    folder=OUT/(str(size[0])+"x"+str(size[1]))/level
    folder.mkdir(parents=True,exist_ok=True)
    context=browser.new_context(viewport={"width":size[0],"height":size[1]},device_scale_factor=1)
    page=context.new_page()
    local_errors=[]
    page.on("pageerror",lambda e:local_errors.append(str(e)))
    page.on("console",lambda m:local_errors.append(m.text) if m.type=="error" or "SCRIPT ERROR:" in m.text else None)
    row={"size":list(size),"mode":"mechanisms","level":level,"offAxis":args.off_axis,"frames":[]}
    try:
        case=next(c for c in cases if c["id"]==level)
        previous=case["initial"];transition=None
        for step in case["steps"]:
            if step["command"]["kind"]=="act" and step["command"]["value"].startswith("turn:"):
                transition=(previous,step);break
            previous=step["snapshot"]
        assert transition,"rotation example exists"
        page.goto(args.base+"?qa=1",wait_until="networkidle",timeout=120000)
        page.wait_for_function("() => window.__sporelightState?.snapshot",timeout=120000)
        s=prepare(page,transition[0])
        if args.off_axis:
            assert level=="3-3","off-axis sample is authored for the water module"
            s=move_to(page,"m:water:-1:0")
            row["beforeSnapshot"]=s["snapshot"]
            check_contacts(s,"off-axis rotation starting support")
        command=transition[1]["command"]["value"]
        available=[c for c in s["commands"] if c["id"] not in ["switch","follow"]]
        index=next(i for i,c in enumerate(available) if c["id"]==command)
        page.screenshot(path=str(folder/"before.png"))
        page.evaluate("""() => {
            window.__mechanismFrames=[];
            const thresholds=[.15,.45,.75];
            function observe(){
                const s=window.__sporelightState,m=s?.motion;
                if(m?.duration>0 && window.__mechanismFrames.length<3){
                    const p=m.elapsed/m.duration;
                    if(p>=thresholds[window.__mechanismFrames.length])
                        window.__mechanismFrames.push({progress:p,motion:structuredClone(m),native:structuredClone(s.native),png:document.querySelector('#canvas').toDataURL('image/png')});
                }
                if(window.__mechanismFrames.length<3) requestAnimationFrame(observe);
            }
            requestAnimationFrame(observe);
        }""")
        page.keyboard.press(str(index+1))
        page.wait_for_function("() => window.__mechanismFrames?.length===3",timeout=10000)
        frames=page.evaluate("() => window.__mechanismFrames")
        for index,frame in enumerate(frames):
            row["frames"].append({"progress":frame["progress"],"motion":frame["motion"],"native":frame["native"]})
            (folder/("rotation-"+str(index)+".png")).write_bytes(base64.b64decode(frame["png"].split(",",1)[1]))
        s=stable(page)
        page.screenshot(path=str(folder/"after.png"))
        check_contacts(s,"rotating platform stopped")
        assert not local_errors,str(local_errors[:5])
        row["passed"]=True
    except Exception as e:
        row.update(passed=False,reason=str(e),actual=state(page))
        page.screenshot(path=str(folder/"failure.png"))
    finally:
        row["errors"]=local_errors
        context.close()
        (folder/"checks.json").write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding="utf-8")
    results.append(row)
    print(json.dumps({k:row.get(k) for k in ["size","mode","level","passed","reason"]},ensure_ascii=False),flush=True)

with sync_playwright() as p:
    browser=p.chromium.launch(channel="chrome",headless=True)
    for size_text in args.sizes.split(","):
        size=tuple(map(int,size_text.split("x")))
        if args.mode=="first-garden":
            run_first_garden(browser,size)
            continue
        if args.mode=="cover":
            run_cover(browser,size)
            continue
        if args.mode=="mechanisms":
            for level in selected or ["1-3","3-3"]:
                run_mechanism(browser,size,level)
            continue
        if args.mode=="motion":
            run_motion(browser,size)
            continue
        if args.mode=="home":
            for touch in [False,True]:
                run_home(browser,size,touch)
            continue
        for case in cases:
            if not selected or case["id"] in selected:
                run_case(browser,size,case,args.mode)
    browser.close()
report={"passed":bool(results) and all(r["passed"] for r in results),"build":build,"results":results}
(OUT/"checks.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
sys.exit(0 if report["passed"] else 1)


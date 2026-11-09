"""Exercise original HUD/navigation with the isolated four-root planning mechanic."""
import json, sys, argparse
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".cache/native-qa-python"))
from playwright.sync_api import sync_playwright
OUT = ROOT / "docs/qa-godot-native/root-weaving-playtest"
OUT.mkdir(parents=True, exist_ok=True)
reports = []
parser = argparse.ArgumentParser()
parser.add_argument("--sizes",default="1280x720,844x390")
args = parser.parse_args()

def state(page):
    return page.evaluate("() => window.__rootWeaving")

def point(page, x, y, touch):
    canvas = page.locator("#canvas")
    box = canvas.bounding_box()
    size = canvas.evaluate("e => [e.width,e.height]")
    coords = (box["x"]+x*box["width"]/size[0], box["y"]+y*box["height"]/size[1])
    if touch: page.touchscreen.tap(*coords)
    else: page.mouse.click(*coords)

def button(page, key, touch=False):
    page.wait_for_timeout(250)
    b=None
    for attempt in range(8):
        buttons=state(page)["buttons"]
        b=next((b for b in buttons if b['action']==key or b['path'].endswith('/'+key) or b['text']==key or b['text'].startswith(key+' ')),None)
        if b: break
        if not state(page)['modalOpen']: break
        box=page.locator('#canvas').bounding_box()
        x,y=box['x']+box['width']*.6,box['y']+box['height']*.65
        # Use a wheel to reveal controls in the existing settings scroller.
        # Mobile-sized gameplay and button activation still use real touch events.
        page.mouse.move(x,y)
        page.mouse.wheel(0,300)
        page.wait_for_timeout(400)
    assert b, (key,[(b['action'],b['text'],b['path']) for b in buttons])
    assert not b["disabled"], (key, state(page))
    x,y,w,h=b['visibleRect']
    point(page,x+w/2,y+h/2,touch)

def pick(page, direction, touch):
    page.wait_for_timeout(180)
    s = state(page)
    choice = next(c for c in s["choices"] if c["id"] == "grow:root:"+direction)
    point(page, choice["x"], choice["y"], touch)
    page.wait_for_function("n => window.__rootWeaving.draft.length===n", arg=len(s["draft"])+1)
    assert not state(page)["snapshot"]["growth"]["root"], "draft cannot open a walkable road"

def hint_check(page,touch):
    if state(page)['hintVisible']:
        button(page,'hint',touch)
        page.wait_for_function('!window.__rootWeaving.hintVisible')
    button(page,'hint',touch)
    page.wait_for_function('window.__rootWeaving.hintVisible')
    assert not state(page)['modalOpen']
    tier=state(page)['hintTier']
    button(page,'hint_next',touch)
    page.wait_for_function('n=>window.__rootWeaving.hintTier===n',arg=(tier+1)%3)
    button(page,'hint',touch)
    page.wait_for_function('!window.__rootWeaving.hintVisible')

def resume(page,touch):
    button(page,'resume',touch)
    page.wait_for_function('!window.__rootWeaving.paused && !window.__rootWeaving.modalOpen')

def restart(page,touch):
    if state(page)['modalOpen']:
        button(page,'留下看看',touch)
        page.wait_for_function('!window.__rootWeaving.modalOpen && !window.__rootWeaving.paused')
    button(page,'Pause',touch)
    button(page,'restart',touch)
    page.wait_for_function("window.__rootWeaving.phase==='explore' && !window.__rootWeaving.modalOpen")

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    try:
        for width,height in [tuple(map(int,s.split("x"))) for s in args.sizes.split(",")]:
            touch = width < 1000
            context = browser.new_context(viewport={"width":width,"height":height}, has_touch=touch)
            page = context.new_page()
            errors=[]
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("console", lambda msg: errors.append(msg.text) if "SCRIPT ERROR:" in msg.text else None)
            page.goto("http://localhost:4218/?playtest=root-weaving", wait_until="networkidle")
            page.wait_for_function("() => window.__rootWeaving?.snapshot", timeout=120000)
            page.wait_for_selector("#status", state="detached", timeout=120000)
            page.wait_for_timeout(700)
            assert [b['action'] for b in state(page)['buttons'] if b['action']] == ['undo','primary','hint']
            page.screenshot(path=str(OUT / f"{width}-arrival.png"))
            hint_check(page,touch)
            if touch: button(page,"primary",touch)
            else: page.keyboard.press("e")
            page.wait_for_function("window.__rootWeaving.phase==='planning'")
            assert next(b for b in state(page)['buttons'] if b['action']=='primary')['disabled']
            if touch:
                pick(page,"up",touch)
                pick(page,"right",touch)
                button(page,"undo",touch)
            else:
                page.keyboard.press("Enter")
                # Enter belongs to the focused Hint button, never a default primary.
                page.wait_for_function('window.__rootWeaving.hintVisible')
                assert not state(page)['snapshot']['growth']['root']
                page.keyboard.press("ArrowUp")
                page.keyboard.press("ArrowRight")
                page.wait_for_function("window.__rootWeaving.draft.length===2")
                page.keyboard.press("Backspace")
            page.wait_for_function("window.__rootWeaving.draft.length===1")
            # The real map and pause/settings preserve the route draft.
            for menu in ['Map','Pause']:
                button(page,menu,touch)
                page.wait_for_function('window.__rootWeaving.modalOpen && window.__rootWeaving.paused')
                resume(page,touch)
                assert len(state(page)['draft'])==1
            hint_check(page,touch)
            button(page,'undo',touch)
            button(page,'undo',touch)
            page.wait_for_function("window.__rootWeaving.phase==='explore'")
            assert not state(page)['snapshot']['growth']['root']
            for route in [["up","right","right","down"],["down","right","right","up"]]:
                button(page,"primary",touch)
                page.wait_for_function("window.__rootWeaving.phase==='planning'")
                page.screenshot(path=str(OUT / f"{width}-{route[0]}-planning.png"))
                for direction in route: pick(page,direction,touch)
                page.screenshot(path=str(OUT / f"{width}-{route[0]}-draft.png"))
                button(page,"primary",touch)
                button(page,"Pause",touch)
                page.wait_for_function("window.__rootWeaving.paused")
                snapshot=state(page)["snapshot"]
                page.wait_for_timeout(700)
                assert state(page)["snapshot"]==snapshot, "pause freezes growth transaction"
                resume(page,touch)
                page.wait_for_function("window.__rootWeaving.phase==='crossing'",timeout=20000)
                assert len(state(page)["snapshot"]["growth"]["root"])==4
                page.screenshot(path=str(OUT / f"{width}-{route[0]}-grown.png"))
                if route[0] == 'up':
                    # The former rear staircase must remain an accessible garden.
                    for tile_id in ['f:4:0','f:5:0']:
                        target=next(t for t in state(page)['targets'] if t['id']==tile_id)
                        point(page,target['x'],target['y'],touch)
                        page.wait_for_function("id=>window.__rootWeaving.snapshot.actors.luvie===id && !window.__rootWeaving.moving",arg=tile_id,timeout=30000)
                    page.screenshot(path=str(OUT / f"{width}-courtyard-walk.png"))
                # Walk using the real map click, then contextual flowerbed action.
                target=next(t for t in state(page)['targets'] if t['id']=='f:4:1')
                point(page,target['x'],target['y'],touch)
                page.wait_for_function("window.__rootWeaving.snapshot.actors.luvie==='f:4:1' && !window.__rootWeaving.moving",timeout=30000)
                button(page,"primary",touch)
                page.wait_for_function("window.__rootWeaving.phase==='won' && window.__rootWeaving.modalOpen",timeout=10000)
                assert state(page)["snapshot"]["completed"]
                page.screenshot(path=str(OUT / f"{width}-{route[0]}-complete.png"))
                reports.append({"size":[width,height],"route":route,"passed":True,"hud":"original","hintToggleCycle":True,"mapPausePreserveDraft":True})
                print(json.dumps(reports[-1]),flush=True)
                restart(page,touch)
            # Map changes scenes via original navigation, including back to prototype.
            button(page,'Map',touch)
            button(page,'1-1',touch)
            page.wait_for_function("window.__rootWeaving.snapshot.levelId==='1-1'")
            assert not state(page)['modalOpen']
            hint_check(page,touch)
            button(page,'Map',touch)
            button(page,'1-2',touch)
            page.wait_for_function("window.__rootWeaving.snapshot.levelId==='1-2'")
            assert state(page)['phase']=='explore'
            assert not errors,errors
            if touch:
                page.set_viewport_size({"width":390,"height":844})
                page.wait_for_function("window.__rootWeaving.portrait")
                page.screenshot(path=str(OUT / "portrait.png"))
                page.set_viewport_size({"width":844,"height":390})
                page.wait_for_function("!window.__rootWeaving.portrait")
            context.close()
    except Exception:
        if not page.is_closed():
            page.screenshot(path=str(OUT / "failure.png"))
            (OUT / "failure-state.json").write_text(json.dumps(state(page),ensure_ascii=False,indent=2),encoding="utf-8")
        raise
    finally:
        browser.close()
        (OUT / "checks.json").write_text(json.dumps(reports,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

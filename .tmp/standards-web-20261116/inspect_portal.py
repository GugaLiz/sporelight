import sys, json
from pathlib import Path
root=Path.cwd()
sys.path.insert(0,str(root/'.cache/native-qa-python'))
from playwright.sync_api import sync_playwright
out=root/'docs/qa-godot-native/standards-web-20261116'
with sync_playwright() as p:
    browser=p.chromium.launch(channel='msedge',headless=True)
    page=browser.new_page(viewport={'width':1440,'height':1000})
    errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('console',lambda m:errors.append(m.text) if m.type=='error' else None)
    page.goto('http://localhost:4224/__standards/',wait_until='networkidle')
    page.screenshot(path=str(out/'overview-desktop.png'),full_page=True)
    print(json.dumps({'text':page.locator('main').inner_text()[:2600],'links':page.get_by_role('link').all_text_contents(),'errors':errors},ensure_ascii=False))
    browser.close()

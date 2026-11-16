"""Headless interaction and responsive checks for the local read-only handbook."""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright, expect

parser = argparse.ArgumentParser()
parser.add_argument('--base', default='http://localhost:4222')
parser.add_argument('--vite', default='http://localhost:4188')
parser.add_argument('--output', default='docs/qa-godot-native/standards-web-20261116')
args = parser.parse_args()
OUT = ROOT / args.output
OUT.mkdir(parents=True, exist_ok=True)
results, errors = [], []
completed = False

def settled(page):
    page.evaluate('() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')

def record(name, ok):
    results.append({'name': name, 'passed': bool(ok)})
    assert ok, name

with sync_playwright() as p:
    browser = p.chromium.launch(channel='msedge', headless=True)
    context = browser.new_context(viewport={'width': 1440, 'height': 1000})
    page = context.new_page()
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
    try:
        page.goto(args.base + '/__standards/', wait_until='networkidle')
        expect(page.get_by_role('heading', name='游戏元素手册')).to_be_visible()
        record('overview uses actual 12-level inventory', '1,104' in page.locator('main').inner_text())
        page.screenshot(path=str(OUT / 'overview-desktop.png'), full_page=True)
        page.get_by_role('link', name='02 元素与规则').click()
        page.get_by_role('link', name='花坛与交互道具', exact=False).click()
        expect(page.get_by_role('heading', name='道具与布景复用合同')).to_be_visible()
        record('family page renders source markdown tables', page.locator('main table').count() > 0)
        page.screenshot(path=str(OUT / 'props-desktop.png'), full_page=True)
        page.get_by_role('link', name='03 逐关元素清单').click()
        page.locator('#level-select').select_option('3-2')
        page.locator('#category-select').select_option('carry')
        expect(page.locator('.instance-list > details')).to_have_count(2)
        page.locator('.instance-list > details > summary').first.click()
        expect(page.locator('.instance-body').first).to_be_visible()
        record('3-2 item filter exposes actual support and binding', '支撑格' in page.locator('.instance-body').first.inner_text())
        page.locator('#level-select').select_option('all')
        page.locator('#category-select').select_option('all')
        expect(page.locator('.instance-list > details')).to_have_count(18)
        first = page.locator('.instance-list > details > summary').first.inner_text()
        page.get_by_role('button', name='下一页').click()
        record('pagination changes records', page.locator('.instance-list > details > summary').first.inner_text() != first)
        page.locator('#search').fill('花坛')
        expect(page.get_by_role('heading', name='搜索手册')).to_be_visible()
        record('full-text search includes source rules', page.locator('.search-document').count() > 0)
        page.locator('.search-document').filter(has_text='花坛、道具与布景').click()
        expect(page.locator('#search')).to_have_value('')
        expect(page.get_by_role('heading', name='规则原文')).to_be_visible()
        page.locator('#search').fill('不存在的测试元素xyz123')
        expect(page.get_by_role('heading', name='没有找到相符内容')).to_be_visible()
        page.get_by_role('button', name='清空搜索').click()
        page.get_by_role('link', name='角色与蘑菇伙伴', exact=True).click()
        expect(page.locator('main pre code').first).to_be_visible()
        record('code examples rendered as preformatted text', page.locator('main pre code').count() > 0)
        for width, height in [(390, 844), (844, 390)]:
            page.set_viewport_size({'width': width, 'height': height})
            page.get_by_role('link', name='01 手册概览').click()
            expect(page.get_by_role('heading', name='游戏元素手册')).to_be_visible()
            settled(page)
            page.screenshot(path=str(OUT / f'overview-{width}.png'), full_page=True)
            record(f'{width} overview has no horizontal page overflow', page.evaluate('document.documentElement.scrollWidth <= innerWidth + 1'))
            page.get_by_role('link', name='05 规则原文').click()
            page.get_by_role('link', name='花坛、道具与布景', exact=True).click()
            expect(page.get_by_role('heading', name='道具与布景复用合同')).to_be_visible()
            settled(page)
            page.screenshot(path=str(OUT / f'props-{width}.png'), full_page=True)
            record(f'{width} markdown has no horizontal page overflow', page.evaluate('document.documentElement.scrollWidth <= innerWidth + 1'))
            back = page.locator('.mobile-back' if width == 390 else '.sidebar .back-link')
            back.scroll_into_view_if_needed()
            expect(back).to_be_in_viewport()
            record(f'{width} return-to-game link reachable', True)
        page.set_viewport_size({'width': 1440, 'height': 1000})
        page.goto(args.vite + '/__standards/', wait_until='networkidle')
        expect(page.get_by_role('heading', name='游戏元素手册')).to_be_visible()
        record('Vite dev serves same handbook without a duplicate launcher', page.locator('#sporelight-standards-entry').count() == 0)
        vite_game = context.new_page()
        vite_game.goto(args.vite + '/', wait_until='domcontentloaded')
        expect(vite_game.locator('#sporelight-standards-entry')).to_be_visible()
        record('Vite development game has local entry', True)
        vite_game.close()
        # Actual game HTML and launcher: no mock game or injected application state.
        game = context.new_page()
        game.goto(args.base + '/', wait_until='domcontentloaded')
        expect(game.locator('#sporelight-standards-entry')).to_be_visible()
        with game.expect_popup() as popup:
            game.locator('#sporelight-standards-entry').click()
        handbook = popup.value
        handbook.wait_for_load_state('networkidle')
        expect(handbook.get_by_role('heading', name='游戏元素手册')).to_be_visible()
        record('game launcher opens handbook in a separate tab', game.url.rstrip('/') == args.base.rstrip('/'))
        game.close()
        handbook.close()
        # Check recovery through a genuine HTTP failure; no persistent data touched.
        failure = context.new_page()
        failure.route('**/__standards/data.json', lambda route: route.fulfill(status=503, body='unavailable'))
        failure.goto(args.base + '/__standards/', wait_until='networkidle')
        expect(failure.get_by_role('heading', name='暂时无法读取元素手册')).to_be_visible()
        failure.unroute('**/__standards/data.json')
        failure.get_by_role('button', name='重新读取').click()
        expect(failure.get_by_role('heading', name='游戏元素手册')).to_be_visible()
        record('load failure offers working retry', True)
        failure.close()
        record('handbook has no script/CSP/resource errors', not errors)
        completed = True
    finally:
        report={'passed': completed and bool(results) and all(row['passed'] for row in results) and not errors, 'results': results, 'errors': errors, 'base': args.base, 'scope': 'Local handbook interactions, headless Edge desktop/mobile, actual game entry popup; not full game regression.'}
        (OUT / 'browser.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(report, ensure_ascii=True))
        browser.close()

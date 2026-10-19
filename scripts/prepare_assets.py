"""Non-destructive production export of the project's existing raster artwork."""
from pathlib import Path
import json
from collections import deque
from PIL import Image, ImageOps, ImageEnhance, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/images/sporelight_complete_assets_png'
OUT = ROOT / 'assets/images/production'
OUT.mkdir(parents=True, exist_ok=True)

def remove_checker(image):
    """Remove edge-connected neutral checker pixels, preserving warm illustration whites."""
    image = image.convert('RGBA')
    width, height = image.size
    pixels = list(image.getdata())
    eligible = bytearray(1 if max(p[:3]) - min(p[:3]) < 22 and min(p[:3]) > 205 else 0 for p in pixels)
    queue = deque()
    for y in range(height):
        for x in (0, width - 1):
            i = y * width + x
            if eligible[i] == 1: eligible[i] = 2; queue.append(i)
    for x in range(width):
        for y in (0, height - 1):
            i = y * width + x
            if eligible[i] == 1: eligible[i] = 2; queue.append(i)
    while queue:
        i = queue.popleft(); x, y = i % width, i // width
        for j in ((i - 1 if x else -1), (i + 1 if x + 1 < width else -1), (i - width if y else -1), (i + width if y + 1 < height else -1)):
            if j >= 0 and eligible[j] == 1: eligible[j] = 2; queue.append(j)
    image.putdata([(p[0], p[1], p[2], 0 if eligible[i] == 2 else p[3]) for i, p in enumerate(pixels)])
    return image

# Re-slice full objects from the larger source sheet; the legacy world crops cut off edges.
sheet = Image.open(ROOT / 'assets/images/material/world_01.png')
sheet2 = Image.open(ROOT / 'assets/images/material/world_02.png')
regions = {
    'flower': (35, 100, 490, 525), 'bloom': (510, 100, 950, 525),
    'moss': (960, 100, 1448, 525), 'light': (35, 590, 500, 932),
    'soil': (510, 595, 945, 925), 'soil-grown': (980, 595, 1420, 930),
    'vine': (980, 595, 1420, 930),
}
regions2 = {
    'bridge': (20, 180, 655, 515), 'arch': (685, 65, 1040, 515),
    'lily': (95, 630, 475, 940), 'lily-open': (95, 630, 475, 940),
    'puddle': (95, 630, 475, 940), 'glow-flower': (610, 620, 855, 940),
}
files = {}
for action, count in [('idle', 3), ('roll', 3), ('sow', 3), ('bow', 2)]:
    for i in range(1, count + 1):
        files[f'{action}{i}'] = f'characters/char_luvie_{action}_{i:02}.png'
files.update({
    'soil': 'world/world_soil_empty.png', 'soil-grown': 'world/world_soil_sowed.png',
    'flower': 'world/world_flowerbud_stage1.png', 'bloom': 'world/world_flowerbud_bloom.png',
    'moss': 'world/world_moss_dark.png', 'light': 'world/world_moss_bright.png',
    'vine': 'world/world_vine_seed.png', 'bridge': 'world/world_vine_bridge.png',
    'lily': 'world/world_petal_spring_closed.png', 'lily-open': 'world/world_petal_spring_open.png',
    'puddle': 'world/world_puddle.png', 'arch': 'world/world_arch_ruin.png',
    'spore': 'ui/icons/ui_icon_spore.png', 'bug': 'fx/fx_glow_critter.png',
    'ring': 'fx/fx_growth_ring.png',
    'glow-flower': 'world/world_glow_flower.png',
})
manifest = {'version': 1, 'method': 'existing-artwork-processing; no AI generation', 'assets': {}}
atlas = Image.new('RGBA', (256 * 6, 256 * ((len(files) + 5) // 6)))
preview = Image.new('RGB', (256 * 6, 288 * ((len(files) + 5) // 6)), '#e8e9dd')
draw = ImageDraw.Draw(preview)
for index, (key, source) in enumerate(files.items()):
    original = Image.open(SOURCE / source).convert('RGBA')
    if key in regions:
        original = remove_checker(sheet.crop(regions[key]))
        source = f'../material/world_01.png crop={regions[key]}'
    if key in regions2:
        original = remove_checker(sheet2.crop(regions2[key]))
        source = f'../material/world_02.png crop={regions2[key]}'
    if key in ('ring', 'bug', 'spore'):
        # These source effects contain pale checkerboard pixels inside their glow.
        # Extract colored emission and leave a genuine alpha glow for compositing.
        original.putdata([(r, g, b, min(a, max(0, min(255, (max(r,g,b)-min(r,g,b)-10)*7)))) for r,g,b,a in original.getdata()])
    if key in ('soil-grown', 'vine'):
        original.putdata([(r, g, b, min(a, max(0, min(255, (max(r,g,b)-min(r,g,b)-12)*6)))) for r,g,b,a in original.getdata()])
    bounds = original.getchannel('A').getbbox()
    if not bounds:
        raise ValueError(f'Empty sprite: {source}')
    cropped = original.crop(bounds)
    cropped.thumbnail((224, 224), Image.Resampling.LANCZOS)
    sprite = Image.new('RGBA', (256, 256))
    sprite.alpha_composite(cropped, ((256 - cropped.width) // 2, 232 - cropped.height))
    target = OUT / f'{key}.png'
    sprite.save(target, optimize=True)
    x, y = (index % 6) * 256, (index // 6) * 256
    atlas.alpha_composite(sprite, (x, y))
    py = (index // 6) * 288
    preview.paste(sprite, (x, py), sprite)
    draw.text((x + 12, py + 260), key, fill='#38483f')
    manifest['assets'][key] = {'file': target.name, 'source': source, 'size': [256, 256],
        'anchor': [0.5, 0.90625], 'alpha': True, 'bytes': target.stat().st_size,
        'frame': [x, y, 256, 256]}
atlas.save(OUT / 'sprite-atlas.png', optimize=True)
preview.save(OUT / 'contact-sheet.jpg', quality=90)
hero = remove_checker(Image.open(ROOT / 'assets/images/main/role.png'))
hero = hero.crop(hero.getchannel('A').getbbox())
hero.thumbnail((420, 660), Image.Resampling.LANCZOS)
hero.save(OUT / 'hero.png', optimize=True)
manifest['assets']['hero'] = {'file': 'hero.png', 'source': '../main/role.png', 'size': list(hero.size), 'alpha': True, 'bytes': (OUT / 'hero.png').stat().st_size, 'note': 'Neutral checker removed from existing raster artwork'}
base = ImageOps.fit(Image.open(ROOT / 'assets/images/main/bg.png').convert('RGB'), (1280, 720))
for chapter, tint, amount in [('valley', '#d4dfba', .10), ('pond', '#6aabae', .36), ('cave', '#2c315c', .65)]:
    bg = Image.blend(base, Image.new('RGB', base.size, tint), amount)
    bg = bg.filter(ImageFilter.GaussianBlur(2))
    if chapter == 'cave':
        bg = ImageEnhance.Brightness(bg).enhance(.72)
    target = OUT / f'bg-{chapter}.jpg'
    bg.save(target, quality=86, optimize=True)
    manifest['assets'][f'bg-{chapter}'] = {'file': target.name, 'source': '../main/bg.png',
        'size': [1280, 720], 'alpha': False, 'bytes': target.stat().st_size,
        'note': 'Color-graded variant of existing artwork, not a new chapter illustration'}
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
cards = ''.join(f'<figure><img src="{v["file"]}"><figcaption>{k}</figcaption></figure>' for k, v in manifest['assets'].items())
(OUT / 'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Sporelight · 素材预览</title><style>body{background:#e8e9dd;color:#38483f;font:16px system-ui;padding:40px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:16px}figure{margin:0;background:#ffffff70;border-radius:16px;padding:12px}img{width:100%;aspect-ratio:1;object-fit:contain}figcaption{text-align:center}</style><h1>Sporelight · 生产素材</h1><p>已有美术加工 · 透明 PNG · 底部锚点对齐 · 背景调色变体</p><main>'+cards+'</main></html>', encoding='utf-8')
print(f'Exported {len(manifest["assets"])} assets, atlas, manifest and preview to {OUT}')

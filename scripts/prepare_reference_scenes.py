"""Prepare supplied scene artwork and independently composited map plant states.

Requires Pillow, numpy, opencv-python-headless. Uses local image processing only.
Original reference files are never overwritten; exports are versioned by directory.
"""
from pathlib import Path
import sys, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.cache/art-tools'))
import cv2

OUT = ROOT / 'assets/images/reference-scenes'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / '设计稿_v1'

def resized(name):
    return Image.open(SOURCE / name).convert('RGB').resize((1280, 720), Image.Resampling.LANCZOS)

def restore(image, rectangles=(), ellipses=(), radius=5):
    mask = Image.new('L', image.size)
    draw = ImageDraw.Draw(mask)
    for box in rectangles: draw.rounded_rectangle(box, radius=8, fill=255)
    for box in ellipses: draw.ellipse(box, fill=255)
    result = cv2.inpaint(np.array(image), np.array(mask), radius, cv2.INPAINT_NS)
    return Image.fromarray(result)

map_image = resized('关卡选择.png')
# Remove the baked navigation, counters, lettering, selection marks and character.
# The paper panel and chapter previews are covered by independent live DOM components.
map_clean = restore(map_image,
    rectangles=[(68,451,146,504),(213,399,307,455),(309,305,392,356),
                (357,492,442,548),(520,500,604,550),(662,478,747,530),
                (668,326,752,377),(758,211,840,261),(836,167,921,218)],
    ellipses=[(76,378,145,451),(531,389,593,492),
              (690,414,724,455),(690,267,727,309),(780,163,814,199),(861,123,897,156)])
character_mask=Image.new('L',map_clean.size,0)
ImageDraw.Draw(character_mask).polygon([(237,280),(266,286),(291,317),(298,345),(281,371),(281,395),(229,403),(217,371),(222,335)],fill=255)
fixed=cv2.inpaint(np.array(map_clean),np.array(character_mask),7,cv2.INPAINT_NS)
map_clean=Image.composite(Image.fromarray(fixed).filter(ImageFilter.GaussianBlur(5)),map_clean,character_mask.filter(ImageFilter.GaussianBlur(3)))

# Restore reference's scenic character-free role area with locally matched stone/foliage.
map_clean.save(OUT / 'map-valley.jpg', quality=94, optimize=True)
map_clean.crop((0,140,910,652)).resize((640,360),Image.Resampling.LANCZOS).save(OUT/'chapter-valley.jpg',quality=92,optimize=True)
for name, color, strength, brightness in [('pond','#74b4ac',.20,.96),('cave','#394567',.48,.77)]:
    graded = Image.blend(map_clean,Image.new('RGB',map_clean.size,color),strength)
    graded = ImageEnhance.Brightness(graded).enhance(brightness)
    graded.save(OUT / f'map-{name}.jpg',quality=93,optimize=True)
    graded.crop((0,140,910,652)).resize((640,360),Image.Resampling.LANCZOS).save(OUT/f'chapter-{name}.jpg',quality=92,optimize=True)

result_image = resized('游戏结算页面.png')
# Clean the painted numbers/headings; retain the scenic flower celebration and bow.
result_clean = restore(result_image,
    rectangles=[(443,339,850,397),(513,420,757,494)], radius=7)
result_clean.save(OUT / 'result-valley.jpg',quality=94,optimize=True)
for name,color,strength in [('pond','#9ed7cd',.14),('cave','#777795',.23)]:
    Image.blend(result_clean,Image.new('RGB',result_clean.size,color),strength).save(OUT / f'result-{name}.jpg',quality=93,optimize=True)

# Preserve the source button's paper and bevel while removing painted text and icon.
button = result_image.crop((297,535,498,600))
button = restore(button,rectangles=[(23,15,175,49)],radius=5)
button.save(OUT / 'button-paper.png',optimize=True)

def foreground(source):
    image=source.convert('RGBA')
    arr=np.array(image)
    rgb=arr[:,:,:3].astype(np.int16)
    neutral=(rgb.max(axis=2)-rgb.min(axis=2)<22)&(rgb.min(axis=2)>205)
    arr[:,:,3]=np.where(neutral,0,arr[:,:,3])
    return Image.fromarray(arr)

sheet=Image.open(ROOT/'assets/images/material/world_01.png')
soil=Image.open(ROOT/'assets/images/production/soil.png').convert('RGBA')
soil=soil.crop(soil.getchannel('A').getbbox())
soil.thumbnail((218,118),Image.Resampling.LANCZOS)
petals=foreground(sheet.crop((620,145,888,345)))
bud=foreground(sheet.crop((145,150,398,340)))
def plant(upper=None, tint=None):
    canvas=Image.new('RGBA',(256,256))
    canvas.alpha_composite(soil,((256-soil.width)//2,236-soil.height))
    if upper:
        upper=upper.copy();upper.thumbnail((139,140),Image.Resampling.LANCZOS)
        canvas.alpha_composite(upper,((256-upper.width)//2,160-upper.height))
    if tint:
        rgb=Image.blend(canvas.convert('RGB'),Image.new('RGB',canvas.size,tint),.25)
        rgb.putalpha(canvas.getchannel('A'));canvas=rgb
    return canvas
plant().save(OUT/'plant-dormant.png',optimize=True)
plant(bud).save(OUT/'plant-bud.png',optimize=True)
plant(petals).save(OUT/'plant-bloom.png',optimize=True)
plant(petals,'#b2ebdf').save(OUT/'plant-pond-bloom.png',optimize=True)
plant(petals,'#bcade4').save(OUT/'plant-cave-bloom.png',optimize=True)
stone=foreground(Image.open(ROOT/'assets/images/material/world_02.png').crop((965,620,1340,950)))
stone=stone.crop(stone.getchannel('A').getbbox())
stone.thumbnail((256,256),Image.Resampling.LANCZOS)
stone.save(OUT/'terrain-steps.png',optimize=True)

manifest={'method':'local processing of existing user-provided artwork; no AI generation',
 'sources':['设计稿_v1/关卡选择.png','设计稿_v1/游戏结算页面.png','assets/images/material/world_01.png','assets/images/production/soil.png'],
 'files':{p.name:{'size':list(Image.open(p).size),'bytes':p.stat().st_size}for p in sorted(OUT.glob('*'))if p.suffix in ['.jpg','.png']}}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
preview=Image.new('RGB',(256*5,256),'#dfe5d8')
for i,name in enumerate(['plant-dormant','plant-bud','plant-bloom','plant-pond-bloom','plant-cave-bloom']):
    sprite=Image.open(OUT/f'{name}.png');preview.paste(sprite,(i*256,0),sprite)
preview.save(OUT/'plant-preview.jpg',quality=94)
print(f'Prepared reference scene assets in {OUT}')

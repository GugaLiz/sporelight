"""Slice supplied character cycles and paper UI into aligned production assets.

Python 3 + Pillow + numpy. Optional OpenCV (also found in .cache/art-tools)
removes baked lettering from button skins so the game can use actual DOM text.
Original sheets are never changed. Crop coordinates are recorded in manifest.json.
"""
from pathlib import Path
from collections import deque
import json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/images/material'
OUT=ROOT/'assets/images/material-ready'
OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'.cache/art-tools'))
import cv2

def transparent(image):
    image=image.convert('RGBA')
    pixels=np.array(image)
    rgb=pixels[:,:,:3].astype(np.int16)
    neutral=((rgb.max(2)-rgb.min(2))<22)&(rgb.min(2)>205)
    # Only erase background connected to the crop boundary, preserving white eyes.
    count,labels,_,_=cv2.connectedComponentsWithStats(neutral.astype('uint8'),8)
    edge=np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])))
    edge=edge[edge!=0]
    pixels[:,:,3][np.isin(labels,edge)]=0
    return Image.fromarray(pixels)

manifest={'source':'assets/images/material','method':'crop, background extraction, aligned animation frames and text-free UI skins','assets':{}}
previews=[]

def export(name,sheet,box,character=False,portrait=False,clear=None):
    original=Image.open(SOURCE/sheet).crop(box).convert('RGBA')
    if clear:
        rgb=np.array(original.convert('RGB'));mask=Image.new('L',original.size)
        draw=ImageDraw.Draw(mask)
        for area in clear:draw.rectangle(area,fill=255)
        original=Image.fromarray(cv2.inpaint(rgb,np.array(mask),6,cv2.INPAINT_NS)).convert('RGBA')
    cut=transparent(original)
    alpha=np.array(cut.getchannel('A'))
    count,components,stats,_=cv2.connectedComponentsWithStats((alpha>24).astype('uint8'),8)
    if count>1:
        main=1+np.argmax(stats[1:,cv2.CC_STAT_AREA])
        if character and not name.startswith('sow-') and name!='symbiosis':
            # Remove neighboring frame fragments and the source sheet's foot shadow.
            keep=cv2.dilate((components==main).astype('uint8'),np.ones((3,3),np.uint8))
            alpha[keep==0]=0
        elif not character and not name.startswith('fx-'):
            # Sheet filenames are separate components below the actual control.
            x,y,w,h,_=stats[main]
            outside=np.ones_like(alpha,dtype=bool)
            outside[max(0,y-3):y+h+3,max(0,x-3):x+w+3]=False
            alpha[outside]=0
        cut.putalpha(Image.fromarray(alpha))
    bounds=cut.getchannel('A').getbbox()
    if not bounds:raise ValueError(name)
    cut=cut.crop(bounds)
    if character:
        # Feet stay at y=236 in every pose; leave a fixed amount of headroom.
        cut.thumbnail((218,216),Image.Resampling.LANCZOS)
        target=Image.new('RGBA',(256,256))
        target.alpha_composite(cut,((256-cut.width)//2,236-cut.height))
    else:
        if portrait:cut.thumbnail((420,600),Image.Resampling.LANCZOS)
        target=Image.new('RGBA',(cut.width+12,cut.height+12))
        target.alpha_composite(cut,(6,6))
    target.save(OUT/f'{name}.png',optimize=True)
    manifest['assets'][name]={'file':f'{name}.png','sheet':sheet,'crop':box,'size':list(target.size),'alpha':True,'anchor':[.5,236/256] if character else None,'bytes':(OUT/f'{name}.png').stat().st_size}
    previews.append((name,target))

role={
 'idle-front':(25,68,201,352),'idle-side':(219,68,368,352),
 'idle-back':(386,68,548,352),'idle-quarter':(550,68,713,352),
 'jump':(730,467,875,696),'interact':(895,488,1054,700),
 'ball':(1092,555,1247,700),'lean':(1258,480,1427,700),
}
for name,box in role.items():export(name,'role.png',box,character=True)
for i,(left,right) in enumerate([(20,139),(139,253),(253,369),(369,484),(484,600),(600,719)],1):
    export(f'walk-{i}','role.png',(left,800,right,996),character=True)
for i,(left,right) in enumerate([(730,871),(871,995),(995,1128),(1128,1294),(1294,1445)],1):
    export(f'sow-{i}','role.png',(left,800,right,998),character=True)
for name,box in {'salute':(550,558,830,948),'symbiosis':(918,549,1321,952)}.items():
    export(name,'char.png',box,character=True)
export('portrait-front','char.png',(77,63,364,497),portrait=True)

# Rich large menu surfaces. Strip only baked lettering, retain paper and ornaments.
export('menu-paper','btn_01.png',(810,155,1370,380),clear=[(140,70,420,157)])
export('menu-logo','btn_01.png',(62,53,741,407))
export('button-paper','buttons.png',(82,241,237,306),clear=[(43,16,112,48)])
export('button-green','buttons.png',(80,85,329,163),clear=[(59,21,201,60)])
export('button-confirm','buttons.png',(346,85,524,164),clear=[(46,20,134,62)])
export('button-cancel','buttons.png',(545,85,723,164),clear=[(46,20,134,62)])
export('panel-paper','btn_03.png',(65,180,665,558))
export('result-next','btn_03.png',(49,678,487,912),clear=[(130,63,313,155)])
export('result-retry','btn_03.png',(515,678,949,912),clear=[(95,63,340,155)])
export('result-map','btn_03.png',(971,678,1412,912),clear=[(102,63,344,155)])

for name,box in {
 'pause':(68,101,351,354),'roll':(403,100,691,355),'roll-active':(742,85,1040,356),
 'sow':(1107,100,1394,357),'sow-active':(67,455,365,738),
 'hint':(405,466,692,742),'undo':(750,465,1038,742),
 'spore':(95,802,335,977),'leaf':(426,801,642,979),'lock':(749,800,925,980)
}.items():export(f'icon-{name}','btn_02.png',box)

for name,box in {
 'close':(302,386,378,460),'back':(414,386,486,460),'retry':(910,386,985,460),
 'settings':(478,576,580,691),'map':(730,576,844,691),'gallery':(1000,576,1111,691),
 'toggle-on':(1032,397,1129,454),'toggle-off':(1153,397,1248,454),
}.items():export(f'icon-{name}','buttons.png',box)

# Independent effects preserve colored emission rather than a baked gray checker.
for name,box in {'spore':(91,241,245,387),'trail':(350,198,603,393),'growth':(660,187,1036,408),'glow':(1065,167,1395,415)}.items():
    export(f'fx-{name}','fx.png',box)
    file=OUT/f'fx-{name}.png';im=Image.open(file).convert('RGBA');arr=np.array(im)
    rgb=arr[:,:,:3].astype(np.int16);saturation=rgb.max(2)-rgb.min(2)
    arr[:,:,3]=np.minimum(arr[:,:,3],np.clip((saturation-8)*6,0,255).astype('uint8'))
    Image.fromarray(arr).save(file,optimize=True)
    manifest['assets'][f'fx-{name}']['bytes']=file.stat().st_size

(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
columns=7;cell=180;rows=(len(previews)+columns-1)//columns
preview=Image.new('RGB',(columns*cell,rows*(cell+26)),'#dfe4d7');draw=ImageDraw.Draw(preview)
for i,(name,im) in enumerate(previews):
    im=Image.open(OUT/f'{name}.png');im.thumbnail((160,160),Image.Resampling.LANCZOS)
    x=i%columns*cell;y=i//columns*(cell+26)
    preview.paste(im,(x+(cell-im.width)//2,y+(cell-im.height)//2),im)
    draw.text((x+8,y+cell+3),name,fill='#485744')
preview.save(OUT/'contact-sheet.jpg',quality=93)
cards=''.join(f'<figure><img src="{name}.png"><figcaption>{name}</figcaption></figure>'for name,_ in previews)
(OUT/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Sporelight · 动作与 UI 素材</title><style>body{font:15px system-ui;background:#dfe4d7;color:#485744;padding:32px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:16px}figure{margin:0;padding:12px;background:#fff9;border-radius:12px;text-align:center}img{width:100%;height:170px;object-fit:contain}figcaption{margin-top:10px}</style><h1>Sporelight · 动作与 UI 切图</h1><p>真实行走6帧、播种5帧 · 透明PNG · 脚底锚点对齐 · UI文字由页面渲染</p><main>'+cards+'</main></html>',encoding='utf-8')
print(f'Exported {len(previews)} assets to {OUT}')

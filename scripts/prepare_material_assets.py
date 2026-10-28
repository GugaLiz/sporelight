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

manifest={'characterNote':'Reference-1 face, hat and leaf cape; pre-unification illustrated body motion transferred with optical-flow inbetweens; composited artwork, not AI redrawing','source':'assets/images/material','method':'crop, background extraction, aligned animation frames and text-free UI skins','assets':{}}
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

# The green leaf cape character sheet is the sole character identity source.
# These are adaptations of supplied poses, not newly drawn animation frames.
poses={
 'idle-front':(77,63,364,497),'idle-side':(440,63,660,497),
 'idle-back':(749,63,987,497),'idle-quarter':(77,63,364,497),
 'jump':(1102,112,1320,478),'interact':(128,573,460,950),
 'ball':(1102,112,1320,478),'lean':(550,558,830,948),
}
for name,box in poses.items():export(name,'char.png',box,character=True)

def polygon_mask(points):
    mask=Image.new('L',(256,256))
    ImageDraw.Draw(mask).polygon(points,fill=255)
    return np.array(mask)


def limb_layer(base,mask):
    layer=base.copy()
    layer[:,:,3]=np.minimum(layer[:,:,3],mask)
    return layer


def articulated(layer,pivot,angle,shift=(0,0),joint=None,bend=0):
    # Bend the lower segment about its own elbow/knee, then swing at the root.
    if joint is not None:
        upper=layer.copy();upper[int(joint[1])+2:,:,3]=0
        lower=layer.copy();lower[:int(joint[1])-2,:,3]=0
        matrix=cv2.getRotationMatrix2D(joint,bend,1)
        lower=cv2.warpAffine(lower,matrix,(256,256),flags=cv2.INTER_CUBIC)
        combined=Image.fromarray(lower)
        combined.alpha_composite(Image.fromarray(upper))
        layer=np.array(combined)
    matrix=cv2.getRotationMatrix2D(pivot,angle,1)
    matrix[:,2]+=shift
    return Image.fromarray(cv2.warpAffine(layer,matrix,(256,256),flags=cv2.INTER_CUBIC))


# Preserve the actual pre-unification key poses and timing. Transfer their
# illustrated body motion under the reference-1 face, mushroom hat and leaf cape;
# do not attempt to synthesize another gait by rotating a standing silhouette.
walk_boxes=[(20,800,139,996),(139,800,253,996),(253,800,369,996),(369,800,484,996),(484,800,600,996),(600,800,719,996)]
walk_views=['idle-front','idle-side','idle-side','idle-front','idle-front','idle-front']
body_keys=[]
yy,xx=np.indices((256,256))
def guide_sprite(box):
    cut=transparent(Image.open(SOURCE/'role.png').crop(box))
    pixels=np.array(cut);rgb=pixels[:,:,:3].astype('int16')
    # Remove the drawn foot shadow before alignment, retaining warm brown shoes.
    neutral=(rgb.max(2)-rgb.min(2)<22)&(np.indices(pixels.shape[:2])[0]>pixels.shape[0]-30)
    pixels[neutral,3]=0
    _,labels,stats,_=cv2.connectedComponentsWithStats((pixels[:,:,3]>24).astype('uint8'),8)
    main=1+np.argmax(stats[1:,cv2.CC_STAT_AREA]);pixels[:,:,3][labels!=main]=0
    cut=Image.fromarray(pixels);cut=cut.crop(cut.getchannel('A').getbbox());cut.thumbnail((218,216),Image.Resampling.LANCZOS)
    aligned=Image.new('RGBA',(256,256));aligned.alpha_composite(cut,((256-cut.width)//2,236-cut.height))
    return np.array(aligned)

for box in walk_boxes:
    pixels=guide_sprite(box)
    pixels[:154,:,3]=0
    rgb=pixels[:,:,:3].astype(float)
    collar=(rgb[:,:,0]>rgb[:,:,1]*1.6)&(yy<183)
    brightness=rgb[:,:,0]/255
    for channel,value in enumerate((125,145,82)):pixels[collar,channel]=(value*brightness[collar]).astype('uint8')
    body=cv2.warpAffine(pixels,np.float32([[1.25,0,-32],[0,1.16,-38.2]]),(256,256),flags=cv2.INTER_CUBIC)
    rgb=body[:,:,:3].astype('int16')
    body[:,:,3][(yy>222)&(rgb.max(2)-rgb.min(2)<25)]=0
    body_keys.append(body)


def body_inbetween(first,second,amount=.5):
    # Flow is restricted to the illustrated body; the identity layers stay sharp.
    def premultiplied(rgba):
        out=rgba.astype('float32')/255
        out[:,:,:3]*=out[:,:,3:4]
        return out
    def gray(rgba):
        a=rgba[:,:,3:4].astype('float32')/255
        rgb=rgba[:,:,:3]*a+235*(1-a)
        return cv2.cvtColor(rgb.astype('uint8'),cv2.COLOR_RGB2GRAY)
    ga,gb=gray(first),gray(second)
    forward=cv2.calcOpticalFlowFarneback(ga,gb,None,.5,5,35,5,7,1.5,0)
    reverse=cv2.calcOpticalFlowFarneback(gb,ga,None,.5,5,35,5,7,1.5,0)
    mx,my=xx.astype('float32'),yy.astype('float32')
    left=cv2.remap(premultiplied(first),mx-forward[:,:,0]*amount,my-forward[:,:,1]*amount,cv2.INTER_LINEAR)
    right=cv2.remap(premultiplied(second),mx-reverse[:,:,0]*(1-amount),my-reverse[:,:,1]*(1-amount),cv2.INTER_LINEAR)
    result=left*(1-amount)+right*amount
    result[:,:,:3]/=np.maximum(result[:,:,3:4],.001)
    return np.clip(result*255,0,255).astype('uint8')


for i in range(12):
    key=i//2
    body=body_keys[key] if i%2==0 else body_inbetween(body_keys[key],body_keys[(key+1)%6])
    head=np.array(Image.open(OUT/f'{walk_views[key]}.png').convert('RGBA'))
    rgb=head[:,:,:3].astype('int16')
    leaf=(rgb[:,:,1]>rgb[:,:,0]*.8)&(rgb[:,:,1]>rgb[:,:,2]*1.2)&(rgb[:,:,0]<190)
    fade=np.clip((181-yy)/16,0,1)
    fade=np.where(leaf&(yy<193),1,fade)
    fade=np.where(yy>=193,0,fade)
    head[:,:,3]=(head[:,:,3]*fade).astype('uint8')
    frame=Image.fromarray(body);frame.alpha_composite(Image.fromarray(head))
    name=f'walk-{i+1}'
    frame.save(OUT/f'{name}.png',optimize=True)
    manifest['assets'][name]={'file':f'{name}.png','identitySheet':'char.png','motionSheet':'role.png','motionCrop':walk_boxes[key],'size':[256,256],'alpha':True,'anchor':[.5,236/256],'method':'original illustrated motion key pose with reference-1 identity and optical-flow body inbetweens','keyPose':key+1,'inbetween':bool(i%2),'bytes':(OUT/f'{name}.png').stat().st_size}
    previews.append((name,frame))
# Restore the original exuberant jump: both hands lifted and knees tucked.
jump_guide=guide_sprite((730,467,875,696))
jump_expression_source=jump_guide.copy()
rgb=jump_guide[:,:,:3].astype(float)
old_head=(yy<146)|((yy<165)&(xx>83)&(xx<174))|((yy<165)&((xx<72)|(xx>185)))|((yy<164)&(rgb[:,:,0]>rgb[:,:,1]*1.5))
jump_guide[:,:,3][old_head]=0
collar=(rgb[:,:,0]>rgb[:,:,1]*1.6)&(yy>=164)&(yy<186)
for channel,value in enumerate((125,145,82)):jump_guide[collar,channel]=(value*rgb[:,:,0][collar]/255).astype('uint8')
jump_body=cv2.warpAffine(jump_guide,np.float32([[1.45,0,-57.6],[0,1.16,-38.2]]),(256,256),flags=cv2.INTER_CUBIC)
neutral=np.array(Image.open(OUT/'idle-front.png').convert('RGBA'));neutral[:167,:,3]=0
jump_head=np.array(Image.open(OUT/'idle-front.png').convert('RGBA'))
rgb=jump_head[:,:,:3].astype('int16')
leaf=(rgb[:,:,1]>rgb[:,:,0]*.8)&(rgb[:,:,1]>rgb[:,:,2]*1.2)&(rgb[:,:,0]<190)
fade=np.clip((181-yy)/16,0,1);fade=np.where(leaf&(yy<193),1,fade);fade=np.where(yy>=193,0,fade)
jump_head[:,:,3]=(jump_head[:,:,3]*fade).astype('uint8')
# Retain reference-1 facial identity, borrowing just the open happy mouth
# from the supplied jump-expression reference. Slightly widen the existing eyes.
happy_head=jump_head.copy()
map_x=xx.astype('float32');map_y=yy.astype('float32')
for eye_x in (110.5,143):
    eye_y=119.5
    radius=((xx-eye_x)/12)**2+((yy-eye_y)/13)**2
    weight=np.clip(1-radius,0,1).astype('float32')
    map_x+=((eye_x+(xx-eye_x)/1.045)-xx).astype('float32')*weight
    map_y+=((eye_y+(yy-eye_y)/1.10)-yy).astype('float32')*weight
happy_head=cv2.remap(happy_head,map_x,map_y,cv2.INTER_CUBIC)
# Remove the resting lip line before inserting the smiling open mouth.
lip_mask=np.zeros((256,256),dtype='uint8');cv2.ellipse(lip_mask,(128,134),(9,3),0,0,360,255,-1)
happy_head[:,:,:3]=cv2.inpaint(happy_head[:,:,:3],lip_mask,3,cv2.INPAINT_TELEA)
mouth=Image.fromarray(jump_expression_source).crop((115,147,133,160)).resize((20,14),Image.Resampling.LANCZOS)
mask=Image.new('L',(20,14));ImageDraw.Draw(mask).ellipse((1,1,19,13),fill=255);mask=mask.filter(ImageFilter.GaussianBlur(.65))
patch=np.array(mouth).copy()
source_skin=np.median(patch[:2,:,:3].reshape(-1,3),axis=0)
target_skin=np.median(happy_head[130:132,119:137,:3].reshape(-1,3),axis=0)
patch[:,:,:3]=np.clip(patch[:,:,:3].astype(float)+target_skin-source_skin,0,255).astype('uint8')
patch[:,:,3]=np.array(mask)
happy_image=Image.fromarray(happy_head);happy_image.alpha_composite(Image.fromarray(patch),(118,129));happy_head=np.array(happy_image)
for i in range(12):
    phase=i/11
    amount=min(1,max(0,(phase-.08)/.25))*min(1,max(0,(.94-phase)/.22))
    amount=amount*amount*(3-2*amount)
    if amount<.1:
        frame=Image.fromarray(neutral)
    else:
        # Keep each drawn arm, sleeve and shoulder connected. The airborne
        # silhouette is the original complete jump, with lower-body follow-through.
        my=yy.astype('float32').copy()
        lower=yy>=175
        my[lower]=175+(my[lower]-175)/(1+.045*np.sin(phase*np.pi))
        body=cv2.remap(jump_body,xx.astype('float32'),my,cv2.INTER_LINEAR)
        frame=Image.fromarray(body)
    frame.alpha_composite(Image.fromarray(happy_head if amount>=.1 else jump_head))
    name=f'jump-{i+1}'
    frame.save(OUT/f'{name}.png',optimize=True)
    manifest['assets'][name]={'file':f'{name}.png','identitySheet':'char.png','motionSheet':'role.png','motionCrop':[730,467,875,696],'size':[256,256],'alpha':True,'anchor':[.5,236/256],'method':'original raised-arm jump with reference-1 identity; body pose transition','expression':'open happy smile and widened eyes' if amount>=.1 else 'resting smile','phase':phase,'bytes':(OUT/f'{name}.png').stat().st_size}
    previews.append((name,frame))
# Rear travel needs its own moving limbs, rather than a bobbing idle sprite.
back=np.array(Image.open(OUT/'idle-back.png').convert('RGBA'))
back_masks=[
    polygon_mask([(99,166),(110,172),(94,191),(84,194),(82,187)]),
    polygon_mask([(146,172),(156,165),(174,188),(172,194),(161,190)]),
    polygon_mask([(105,210),(121,210),(122,236),(104,236)]),
    polygon_mask([(132,210),(149,210),(151,236),(132,236)]),
]
back_limbs=[limb_layer(back,mask) for mask in back_masks]
back_body=back.copy()
for mask in back_masks:back_body[:,:,3][mask>0]=0
for i in range(12):
    phase=i/12;stride=np.sin(phase*2*np.pi)
    frame=Image.new('RGBA',(256,256))
    for j,(limb,pivot) in enumerate(zip(back_limbs,[(102,169),(153,169),(113,210),(140,210)])):
        sign=1 if j%2==0 else -1
        frame.alpha_composite(articulated(limb,pivot,sign*stride*(32 if j<2 else 18),(0,-max(0,sign*stride)*13 if j>=2 else 0)))
    frame.alpha_composite(articulated(back_body,(128,215),np.sin(phase*2*np.pi)*3,(0,-abs(np.sin(phase*2*np.pi))*3)))
    name=f'walk-back-{i+1}'
    frame.save(OUT/f'{name}.png',optimize=True)
    manifest['assets'][name]={'file':f'{name}.png','sheet':'char.png','crop':poses['idle-back'],'size':[256,256],'alpha':True,'anchor':[.5,236/256],'method':'rear limb articulation','phase':phase,'bytes':(OUT/f'{name}.png').stat().st_size}
    previews.append((name,frame))
for i in range(1,6):
    export(f'sow-{i}','char.png',poses['interact'] if i<5 else poses['lean'],character=True)
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
(OUT/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Sporelight · 动作与 UI 素材</title><style>body{font:15px system-ui;background:#dfe4d7;color:#485744;padding:32px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:16px}figure{margin:0;padding:12px;background:#fff9;border-radius:12px;text-align:center}img{width:100%;height:170px;object-fit:contain}figcaption{margin-top:10px}</style><h1>Sporelight · 动作与 UI 切图</h1><p>图1绿叶披肩角色 · 已有姿态适配（非逐帧重绘） · 透明PNG · 脚底锚点对齐</p><main>'+cards+'</main></html>',encoding='utf-8')
print(f'Exported {len(previews)} assets to {OUT}')

# Review the actual sequential frames in motion, including the jump arc.
animation=[]
for i in range(24):
    preview=Image.new('RGB',(768,350),'#e0e5d8')
    draw=ImageDraw.Draw(preview)
    for column,clip in enumerate(('walk','walk-back','jump')):
        number=(i%12)+1 if clip!='jump' else min(12,1+i//2)
        im=Image.open(OUT/f'{clip}-{number}.png')
        lift=0 if clip!='jump' else int(50*np.sin(np.pi*np.clip((i/23-.14)/.72,0,1)))
        preview.paste(im,(column*256,55-lift),im)
        draw.text((column*256+90,325),clip,fill='#3c5035')
    animation.append(preview)
animation[0].save(OUT/'motion-preview.gif',save_all=True,append_images=animation[1:],duration=55,loop=0)
comparison=Image.new('RGB',(1536,828),'#e0e5d8');draw=ImageDraw.Draw(comparison)
for row,clip in enumerate(('walk','walk-back','jump')):
    for column,number in enumerate((1,3,5,7,9,11)):
        im=Image.open(OUT/f'{clip}-{number}.png')
        comparison.paste(im,(column*256,row*276),im)
        draw.text((column*256+8,row*276+256),f'{clip}-{number}',fill='#3c5035')
comparison.save(OUT/'motion-preview.jpg',quality=94)

# Close-up of the airborne expression for visual review.
expression_preview=Image.new('RGB',(512,512),'#e0e5d8')
expression_sprite=Image.open(OUT/'jump-6.png').resize((512,512),Image.Resampling.LANCZOS)
expression_preview.paste(expression_sprite,(0,0),expression_sprite)
expression_preview.save(OUT/'jump-expression-preview.png')

"""Prepare a clean journal scene from the existing gallery reference illustration.

The open book, forest, clip and decorative reading character are reused. Card and
detail contents are removed for live rendering, not baked fake collection values.
Requires Python 3, Pillow, numpy and OpenCV (also found in .cache/art-tools).
"""
from pathlib import Path
import json,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageOps
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.cache/art-tools'))
import cv2
OUT=ROOT/'assets/images/gallery-journal';OUT.mkdir(parents=True,exist_ok=True)
raw=Image.open(ROOT/'设计稿_v1/图鉴页.png').convert('RGB')
scene=raw.resize((1280,720),Image.Resampling.LANCZOS)
paper=scene.crop((477,75,623,143))
paper.save(OUT/'paper-texture.jpg',quality=96)

def patch(image,box,polygon=None,exclude=None):
    tile=paper.resize(image.size,Image.Resampling.BICUBIC)
    mask=Image.new('L',image.size);draw=ImageDraw.Draw(mask)
    if polygon:draw.polygon(polygon,fill=255)
    else:draw.rounded_rectangle(box,radius=7,fill=255)
    if exclude:draw.rectangle(exclude,fill=0)
    mask=mask.filter(ImageFilter.GaussianBlur(3))
    return Image.composite(tile,image,mask)

# Preserve the real book folds and forest, replace the dynamic card area only.
clean=patch(scene,(118,195,836,651))
clean.save(OUT/'book-scene.jpg',quality=95,optimize=True)
scene.crop((0,0,1280,38)).resize((720,1280),Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(12)).save(OUT/'forest-mobile.jpg',quality=88,optimize=True)

# Normal card frame, with the old title/illustration/stars replaced by paper grain.
card=scene.crop((301,201,472,419))
card=patch(card,(9,10,162,208)).convert('RGBA')
alpha=Image.new('L',card.size);ImageDraw.Draw(alpha).rounded_rectangle((1,1,169,216),radius=21,fill=255)
card.putalpha(alpha.filter(ImageFilter.GaussianBlur(.5)))
card.save(OUT/'card-paper.png',optimize=True)

# Inner detail page is blank, but the source edge, paper clip and floral tag remain.
note=patch(scene,None,polygon=[(884,126),(1184,142),(1160,650),(866,626)],exclude=(1080,500,1210,680))
note.crop((847,95,1207,675)).save(OUT/'detail-paper.png',optimize=True)

# Foreground reading pose is re-layered over the lower-left card, as in the reference.
mask=Image.new('L',scene.size)
polygon=[(40,432),(62,438),(85,456),(114,480),(136,508),(143,527),(135,544),(128,558),(139,580),(173,582),(157,628),(146,647),(136,652),(132,682),(115,700),(80,696),(52,695),(42,678),(26,668),(24,638),(29,610),(38,583),(25,562),(21,531),(23,495),(28,466)]
ImageDraw.Draw(mask).polygon(polygon,fill=255)
box=(16,428,180,705)
rgb=np.array(scene.crop(box));rough=np.array(mask.crop(box))
grab=np.where(rough>20,cv2.GC_PR_FGD,cv2.GC_BGD).astype('uint8')
for points in [
 [(78,0),(164,0),(164,130),(130,90),(108,55)],
 [(142,100),(164,100),(164,155),(151,147),(135,135)],
 [(0,0),(23,0),(13,30),(0,60)],
 [(150,187),(164,180),(164,277),(125,277),(125,248)],
]:cv2.fillPoly(grab,[np.array(points,dtype='int32')],cv2.GC_BGD)
for x,y in [(58,75),(77,124),(59,195),(112,177),(67,257),(95,257)]:cv2.circle(grab,(x,y),4,cv2.GC_FGD,-1)
cv2.grabCut(rgb,grab,None,np.zeros((1,65),np.float64),np.zeros((1,65),np.float64),5,cv2.GC_INIT_WITH_MASK)
alpha=Image.fromarray(np.where((grab==cv2.GC_FGD)|(grab==cv2.GC_PR_FGD),255,0).astype('uint8')).filter(ImageFilter.GaussianBlur(.4))
avatar=Image.fromarray(rgb).convert('RGBA');avatar.putalpha(alpha)
avatar.save(OUT/'reading-companion.png',optimize=True)

def illustration(name,box):
    scale=raw.width/1280
    image=raw.crop(tuple(round(v*scale)for v in box)).convert('RGBA');arr=np.array(image)
    rgb=arr[:,:,:3].astype(np.int16)
    # Erase edge-connected parchment; preserve enclosed ivory highlights.
    bg=(rgb[:,:,0]>230)&(rgb[:,:,1]>205)&(rgb[:,:,2]>140)&((rgb[:,:,0]-rgb[:,:,1])<44)&((rgb[:,:,1]-rgb[:,:,2])<76)
    _,labels,_,_=cv2.connectedComponentsWithStats(bg.astype('uint8'),8)
    ids=np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])));ids=ids[ids!=0]
    arr[:,:,3][np.isin(labels,ids)]=0
    if name=='vine':arr[:round(15*scale),round(66*scale):round(101*scale),3]=0
    image=Image.fromarray(arr);image=image.crop(image.getchannel('A').getbbox());image.save(OUT/f'{name}.png',optimize=True)
illustration('mushroom',(327,482,452,611))
illustration('vine',(482,248,648,385))

manifest={'source':'设计稿_v1/图鉴页.png','method':'local cropping, parchment reconstruction and foreground layering; original preserved','files':{p.name:{'size':list(Image.open(p).size),'bytes':p.stat().st_size}for p in sorted(OUT.iterdir())if p.suffix in ['.png','.jpg']}}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Prepared journal book, card, detail and foreground assets')

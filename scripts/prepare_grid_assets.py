"""Extract terrain and ruin props from existing material sheets for tile rendering."""
from pathlib import Path
import json,sys
import numpy as np
from PIL import Image,ImageDraw,ImageOps,ImageEnhance,ImageFilter
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.cache/art-tools'))
import cv2
OUT=ROOT/'assets/images/grid-world';OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'assets/images/material'
regions={
 'grass':('supplies.png',(20,22,281,199)),
 'stone':('supplies.png',(287,22,557,201)),
 'cliff':('supplies.png',(564,17,821,203)),
 'moss-stone':('supplies.png',(838,22,1113,202)),
 'stairs':('supplies.png',(249,205,424,370)),
 'rock':('supplies.png',(647,200,787,370)),
 'lantern':('supplies.png',(428,545,558,713)),
 'flowers':('supplies.png',(797,380,931,528)),
 'bush':('supplies.png',(10,378,195,528)),
 'lilypad':('supplies.png',(944,398,1110,528)),
 'crystal':('supplies.png',(1015,851,1114,963)),
 'bridge':('supplies.png',(1134,378,1300,548)),
}
manifest={'source':'assets/images/material','assets':{}}
for name,(sheet,box) in regions.items():
    im=Image.open(SOURCE/sheet).crop(box).convert('RGBA');arr=np.array(im);rgb=arr[:,:,:3].astype(np.int16)
    bg=((rgb.max(2)-rgb.min(2))<22)&(rgb.min(2)>205)
    _,labels,_,_=cv2.connectedComponentsWithStats(bg.astype('uint8'),8)
    ids=np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])));ids=ids[ids!=0]
    arr[:,:,3][np.isin(labels,ids)]=0;im=Image.fromarray(arr);im=im.crop(im.getchannel('A').getbbox())
    im.save(OUT/f'{name}.png',optimize=True)
    manifest['assets'][name]={'sheet':sheet,'crop':box,'size':list(im.size),'alpha':True}
# The complete arch was already extracted from world_02 without cropping its feet.
Image.open(ROOT/'assets/images/production/arch.png').save(OUT/'arch.png')
manifest['assets']['arch']={'source':'../production/arch.png','alpha':True}
cliff=np.array(Image.open(OUT/'cliff.png').convert('RGB'))
for name,points in {
 'wall-left':[(2,49),(131,86),(131,160),(2,119)],
 'wall-right':[(131,86),(230,48),(230,114),(131,160)],
}.items():
    matrix=cv2.getPerspectiveTransform(np.array(points,dtype='float32'),np.array([(0,0),(255,0),(255,159),(0,159)],dtype='float32'))
    Image.fromarray(cv2.warpPerspective(cliff,matrix,(256,160))).save(OUT/f'{name}.jpg',quality=94)
    manifest['assets'][name]={'source':'cliff.png','method':'perspective extraction of existing rock face','alpha':False}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
preview=Image.new('RGB',(5*220,3*210),'#dfe6d8');draw=ImageDraw.Draw(preview)
for i,name in enumerate(manifest['assets']):
    im=Image.open(OUT/f'{name}{".jpg" if name.startswith("wall-") else ".png"}');im.thumbnail((190,175));x=i%5*220;y=i//5*210
    preview.paste(im,(x+(220-im.width)//2,y+(175-im.height)//2),im if im.mode=='RGBA' else None);draw.text((x+12,y+185),name,fill='#485c45')
preview.save(OUT/'preview.jpg',quality=94)
source=Image.open(ROOT/'assets/images/main/bg.png').convert('RGB')
sky=ImageOps.fit(source.crop((0,0,source.width,int(source.height*.66))),(1280,720),Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(1.3))
for chapter,color,strength,brightness in [('valley','#eeddb6',.04,1),('pond','#7faeaf',.28,.96),('cave','#303c60',.60,.73)]:
    image=Image.blend(sky,Image.new('RGB',sky.size,color),strength)
    ImageEnhance.Brightness(image).enhance(brightness).save(OUT/f'sky-{chapter}.jpg',quality=91,optimize=True)
    manifest['assets'][f'sky-{chapter}']={'source':'../main/bg.png','method':'upper scenery crop and color grading','alpha':False}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Exported {len(manifest["assets"])} terrain assets')

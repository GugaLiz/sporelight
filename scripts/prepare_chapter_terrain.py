"""Chapter materials derived from the existing illustrated stone, arch and scenery."""
from pathlib import Path
import json,sys
import numpy as np
from PIL import Image,ImageDraw,ImageEnhance,ImageFilter
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'.cache/art-tools'));import cv2
OUT=ROOT/'assets/images/garden-scenery';OUT.mkdir(parents=True,exist_ok=True)
stone=Image.open(ROOT/'assets/images/grid-world/stone.png').convert('RGBA')
rgb=ImageEnhance.Color(stone.convert('RGB')).enhance(.60);a=np.asarray(rgb).astype(float)
wet=Image.fromarray(np.clip(a*np.array([.81,1.02,1.06])+[5,8,8],0,255).astype('uint8')).convert('RGBA');wet.putalpha(stone.getchannel('A'));wet.save(OUT/'pond-stone.png',optimize=True)
arch=np.array(Image.open(ROOT/'assets/images/production/arch.png').convert('RGB'))
for name,points in {'valley-wall-left':[(76,111),(101,119),(101,183),(76,174)],'valley-wall-right':[(141,124),(166,113),(166,193),(141,207)]}.items():
 matrix=cv2.getPerspectiveTransform(np.array(points,dtype='float32'),np.array([(0,0),(127,0),(127,159),(0,159)],dtype='float32'))
 Image.fromarray(cv2.warpPerspective(arch,matrix,(128,160))).save(OUT/(name+'.jpg'),quality=94)
for key,path,pts in [('paving-valley',ROOT/'assets/images/grid-world/stone.png',[(3,46),(111,1),(226,45),(117,101)]),('paving-pond',OUT/'pond-stone.png',[(3,46),(111,1),(226,45),(117,101)]),('paving-grass',ROOT/'assets/images/grid-world/grass.png',[(4,58),(118,8),(225,57),(110,108)])]:
 source=np.array(Image.open(path).convert('RGB'));matrix=cv2.getPerspectiveTransform(np.array(pts,dtype='float32'),np.array([(0,255),(0,0),(255,0),(255,255)],dtype='float32'));Image.fromarray(cv2.warpPerspective(source,matrix,(256,256))).save(OUT/(key+'.jpg'),quality=94)
moss=np.array(Image.open(ROOT/'assets/images/grid-world/moss-stone.png').convert('RGB'))
matrix=cv2.getPerspectiveTransform(np.array([(3,43),(114,3),(224,46),(112,96)],dtype='float32'),np.array([(0,255),(0,0),(255,0),(255,255)],dtype='float32'))
Image.fromarray(cv2.warpPerspective(moss,matrix,(256,256))).save(OUT/'paving-moss.jpg',quality=94)
# Continuous masonry shares a single world-aligned pattern across neighboring faces.
rng=np.random.default_rng(28)
patch=Image.open(OUT/'valley-wall-left.jpg').convert('RGB')
for chapter in ['valley','pond']:
 wall=Image.new('RGB',(288,288),'#727e65');draw=ImageDraw.Draw(wall)
 for row in range(13):
  y=row*24-12;offset=0 if row%2 else -24
  for col in range(7):
   x=col*48+offset-24;variant=patch.crop((int(rng.integers(0,40)),int(rng.integers(0,65)),120,155)).resize((46,22),Image.Resampling.LANCZOS)
   variant=ImageEnhance.Contrast(variant).enhance(.60);variant=ImageEnhance.Brightness(variant).enhance(float(rng.uniform(.94,1.18)))
   tint='#c4ac89' if chapter=='valley' else '#8ba99f';variant=Image.blend(variant,Image.new('RGB',variant.size,tint),.22 if chapter=='valley' else .48)
   wall.paste(variant,(x+1,y+1));draw.line((x+2,y+1,x+44,y+1),fill='#c8c4a0' if chapter=='valley' else '#b5ccba',width=1)
 for i in range(90):
  x=int(rng.integers(0,288));y=int(rng.integers(0,288));r=int(rng.integers(1,4));draw.ellipse((x,y,x+r*2,y+r),fill=['#829373','#a3ad79','#627a65'][i%3])
 cliff=Image.open(ROOT/'assets/images/grid-world/wall-left.jpg').convert('RGB').resize(wall.size,Image.Resampling.LANCZOS)
 Image.blend(wall,cliff,.12).filter(ImageFilter.GaussianBlur(.3)).save(OUT/f'masonry-{chapter}.jpg',quality=94)
# Fine pigment variation, rather than a flat cyan fill, beneath the lake highlights.
noise=Image.fromarray(rng.integers(0,256,(512,512),dtype='uint8')).filter(ImageFilter.GaussianBlur(8));n=np.asarray(noise).astype(float);n=(n-n.mean())*3
water=np.stack([139+n*.5,194+n*.62,197+n*.65],axis=-1)
Image.fromarray(np.clip(water,0,255).astype('uint8')).save(OUT/'water-pigment.jpg',quality=94)
bg=Image.open(ROOT/'assets/images/production/bg-pond.jpg').convert('RGB');bg=ImageEnhance.Color(bg).enhance(.65);bg=Image.blend(bg,Image.new('RGB',bg.size,'#b6d4d5'),.25);bg.filter(ImageFilter.GaussianBlur(1)).save(OUT/'pond-mist.jpg',quality=91)
(OUT/'chapter-terrain-manifest.json').write_text(json.dumps({'source':['grid-world/stone.png','grid-world/grass.png','grid-world/moss-stone.png','grid-world/wall-left.jpg','production/arch.png','production/bg-pond.jpg'],'method':'perspective-extracted paving, continuous illustrated masonry, cool grading and deterministic water pigment','seed':28,'assets':['paving-valley.jpg','paving-pond.jpg','paving-grass.jpg','paving-moss.jpg','masonry-valley.jpg','masonry-pond.jpg','water-pigment.jpg','pond-mist.jpg']},indent=2),encoding='utf-8')
print('Prepared chapter paving, continuous masonry, water pigment and mist')

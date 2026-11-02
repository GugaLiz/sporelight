"""Extract environmental props from the supplied sheets; retain their original artwork."""
from pathlib import Path
import sys, json
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.cache/art-tools'))
import cv2
OUT=ROOT/'assets/images/garden-scenery';OUT.mkdir(parents=True,exist_ok=True)
regions={
 'berry-bush':('supplies.png',(201,377,375,534)),
 'river-rock':('supplies.png',(1105,229,1253,354)),
 'pebble-cluster':('supplies.png',(953,225,1099,355)),
 'small-pebbles':('supplies.png',(1256,274,1423,355)),
 'stone-lantern':('supplies.png',(425,540,577,718)),
 'gold-lotus':('supplies.png',(982,541,1137,718)),
 'trailing-vine':('supplies.png',(1353,373,1432,612)),
 'dew-plant':('supplies.png',(1160,548,1315,716)),
 'dew-parcel':('supplies.png',(746,846,859,978)),
 'fern':('supplies.png',(374,377,519,530)),
 'blue-flowers':('supplies.png',(520,375,675,532)),
 'yellow-flowers':('supplies.png',(680,378,796,532)),
 'pink-flowers':('supplies.png',(797,378,934,533)),
 'ivory-lotus':('supplies.png',(866,852,982,970)),
 'glow-flower':('world_02.png',(638,646,850,947)),
 'red-mushroom':('supplies.png',(628,548,773,710)),
 'blue-mushroom':('supplies.png',(788,548,929,710)),
 'wood-lantern':('supplies.png',(202,542,395,717)),
 'violet-crystal':('supplies.png',(1138,850,1246,968)),
 'light-tower':('world_02.png',(1094,88,1410,505)),
 'lotus-pool':('world_02.png',(99,692,502,926)),
}
manifest={}
for key,(sheet,box) in regions.items():
 im=Image.open(ROOT/'assets/images/material'/sheet).crop(box).convert('RGBA');arr=np.array(im);rgb=arr[:,:,:3].astype('int16')
 neutral=(rgb.max(2)-rgb.min(2)<23)&(rgb.min(2)>203)
 _,labels,_,_=cv2.connectedComponentsWithStats(neutral.astype('uint8'),8)
 edges=np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])));arr[:,:,3][np.isin(labels,edges[edges!=0])]=0
 im=Image.fromarray(arr);im=im.crop(im.getchannel('A').getbbox());im.save(OUT/f'{key}.png',optimize=True)
 manifest[key]={'source':f'material/{sheet}','crop':box,'size':list(im.size)}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
# Separate the tower's crystal membranes from its original masonry and ivy.
tower=Image.open(OUT/'light-tower.png').convert('RGBA')
mask=Image.new('L',tower.size);draw=ImageDraw.Draw(mask)
draw.polygon([(83,235),(98,211),(113,203),(127,226),(128,296),(111,310),(85,302)],fill=255)
draw.polygon([(158,228),(170,212),(185,220),(192,244),(191,290),(171,306),(158,295)],fill=255)
pixels=np.array(tower);selection=np.array(mask)>0
frame=pixels.copy();frame[selection,3]=0
seal=pixels.copy();seal[~selection,3]=0
Image.fromarray(frame).save(OUT/'flower-gate-frame.png',optimize=True)
Image.fromarray(seal).save(OUT/'flower-gate-seal.png',optimize=True)
manifest['flower-gate']={'source':'world_02.png light tower','frame':'flower-gate-frame.png','seal':'flower-gate-seal.png','size':list(tower.size),'method':'original masonry frame and independently fading crystal membrane'}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Exported {len(manifest)} scenery props')

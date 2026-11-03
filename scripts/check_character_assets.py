"""Validate refined sprites and export a reproducible dark/light edge review."""
from pathlib import Path
import json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.cache/art-tools'))
import cv2
from character_matte import character_cutout, warp_rgba

out=ROOT/'docs/qa-character'
out.mkdir(parents=True,exist_ok=True)
assets=ROOT/'assets/images/character-refined'
manifest=json.loads((assets/'manifest.json').read_text(encoding='utf-8'))
expected=['idle-front','idle-side','idle-back','idle-quarter','jump','interact','ball','lean','salute','symbiosis',
          *[f'{clip}-{i}' for clip in ['walk','walk-back','jump'] for i in range(1,13)],
          *[f'sow-{i}' for i in range(1,6)],'portrait-front']
assert set(manifest['assets'])==set(expected)
checks=[]
for key in expected:
    im=Image.open(assets/f'{key}.png')
    assert im.mode=='RGBA',key
    a=np.array(im)
    if key!='portrait-front':
        assert im.size==(256,256),key
        assert manifest['assets'][key]['anchor']==[.5,236/256],key
    assert (a[:,:,3]==0).mean()>.35,key
    assert ((a[:,:,3]>0)&(a[:,:,3]<255)).any(),key
    assert a[0,:,3].max()==0 and a[-1,:,3].max()==0,key
    assert a[:,0,3].max()==0 and a[:,-1,3].max()==0,key
    assert (a[:,:,3]>240).sum()>500,key
checks.append('52 RGBA assets: expected names, clear canvas borders, real alpha, opaque interiors and unchanged sprite canvas/foot anchors')

# Edge interpolation must not import the RGB value of transparent white pixels.
pixels=np.full((9,9,4),255,dtype='uint8');pixels[:,:,3]=0;pixels[2:7,2:7]=[180,30,20,255]
warped=warp_rgba(pixels,np.float32([[1,0,.35],[0,1,.25]]),size=(9,9),flags=cv2.INTER_LINEAR)
partial=(warped[:,:,3]>1)&(warped[:,:,3]<254)
assert partial.any() and np.abs(warped[:,:,:3][partial].astype(int)-[180,30,20]).max()<=1
checks.append('Premultiplied interpolation preserves edge color even when invisible pixels contain white')

# The trimap must keep white interior details and cream spots that meet an edge.
sample=Image.new('RGB',(100,120),'#f4f4f4');d=ImageDraw.Draw(sample)
d.ellipse((20,10,80,100),fill=(210,45,35));d.ellipse((24,40,37,57),fill=(250,239,229));d.ellipse((47,30,55,38),fill='white')
matte=np.array(character_cutout(sample))
assert matte[50,31,3]>240 and matte[34,51,3]>240
assert matte[0,0,3]==0 and np.all(matte[70,50,:3]==[210,45,35])
checks.append('Matting preserves white interior detail and cream edge spots while removing the neutral background')

font_path=Path('C:/Windows/Fonts/msyh.ttc')
font=ImageFont.truetype(str(font_path),20) if font_path.exists() else ImageFont.load_default()
keys=['idle-front','idle-side','idle-back','walk-1','jump-6','sow-1','symbiosis']
review=Image.new('RGB',(7*256,4*292));draw=ImageDraw.Draw(review)
for row,(folder,bg) in enumerate([('material-ready','#253348'),('character-refined','#253348'),('material-ready','#eef1e4'),('character-refined','#eef1e4')]):
    draw.rectangle((0,row*292,review.width,(row+1)*292),fill=bg)
    for col,key in enumerate(keys):
        im=Image.open(ROOT/f'assets/images/{folder}/{key}.png')
        review.paste(im,(col*256,row*292+30),im)
        draw.text((col*256+10,row*292+5),('优化前 · ' if row%2==0 else '优化后 · ')+key,font=font,fill='white' if row<2 else '#253348')
review.save(out/'edge-comparison.png')

hero=Image.new('RGB',(1080,580));draw=ImageDraw.Draw(hero)
for col,bg in enumerate(['#253348','#eef1e4','#5e857d']):
    draw.rectangle((col*360,0,(col+1)*360,580),fill=bg)
    for i,folder in enumerate(['material-ready','character-refined']):
        im=Image.open(ROOT/f'assets/images/{folder}/portrait-front.png');im.thumbnail((165,440),Image.Resampling.LANCZOS)
        hero.paste(im,(col*360+10+i*180,100),im)
        draw.text((col*360+40+i*180,45),'优化前' if i==0 else '优化后',font=font,fill='white' if col!=1 else '#253348')
hero.save(out/'portrait-comparison.png')
(out/'checks.json').write_text(json.dumps({'checks':checks,'assetCount':len(expected),'sourceArtwork':'assets/images/material/char.png and role.png','generatedArtworkUsed':False},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'checks':checks,'assetCount':len(expected)},ensure_ascii=False,indent=2))

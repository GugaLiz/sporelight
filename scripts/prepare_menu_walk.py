"""Articulate the complete side original, with no front-body keys or blends."""
from pathlib import Path
import json, sys
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.cache/art-tools'))
import cv2
from character_matte import warp_rgba
OUT=ROOT/'assets/images/menu-walk'
OUT.mkdir(parents=True,exist_ok=True)
source=np.array(Image.open(ROOT/'assets/images/character-refined/idle-side.png'))
yy,xx=np.indices((256,256))
def mask(points):
    image=Image.new('L',(256,256));ImageDraw.Draw(image).polygon(points,fill=255)
    return np.array(image)>0
arm_mask=mask([(119,166),(130,167),(136,174),(135,184),(130,195),(119,198),(111,192),(114,181)])
arm=source.copy();arm[~arm_mask,3]=0
# Fill the sleeve opening underneath the moving arm, retaining the side dress.
torso=source.copy()
repair=(arm_mask&(source[:,:,3]>0)).astype('uint8')*255
torso[:,:,:3]=cv2.inpaint(source[:,:,:3],repair,5,cv2.INPAINT_TELEA)
torso[yy>=211,3]=0
near=source.copy();near[(yy<208)|(xx<124),3]=0
far=source.copy();far[(yy<208)|(xx>=126),3]=0
def rotate(layer,pivot,angle):
    return Image.fromarray(warp_rgba(layer,cv2.getRotationMatrix2D(pivot,angle,1)))
frames=[]
for i in range(12):
    swing=np.sin(2*np.pi*i/12)
    frame=Image.new('RGBA',(256,256))
    frame.alpha_composite(rotate(far,(123,208),-swing*23))
    frame.alpha_composite(rotate(near,(130,208),swing*23))
    frame.alpha_composite(Image.fromarray(torso))
    frame.alpha_composite(rotate(arm,(124,168),-swing*23))
    a=np.array(frame);bottom=int(np.where(a[:,:,3]>32)[0].max())
    frame=Image.fromarray(warp_rgba(a,np.float32([[1,0,0],[0,1,235-bottom]])))
    frame.save(OUT/f'step-{i+1}.png',optimize=True);frames.append(frame)
(OUT/'manifest.json').write_text(json.dumps({'source':'character-refined/idle-side.png','method':'complete side-view articulated near arm and overlapping legs; no front body, optical flow or frame blending','frameCount':12,'canvas':[256,256],'footAnchor':[.5,236/256]},indent=2),encoding='utf-8')
preview=Image.new('RGB',(1536,552),'#e6e6d7')
for i,frame in enumerate(frames):
    x,y=i%6*256,i//6*276
    preview.paste(frame,(x,y),frame);ImageDraw.Draw(preview).text((x+100,y+256),f'step {i+1}',fill='#4a5643')
review=ROOT/'docs/qa-menu-vignette';review.mkdir(parents=True,exist_ok=True)
preview.save(review/'sharp-walk-keys.jpg',quality=94)
print(f'Exported {len(frames)} complete side-view poses to {OUT}')

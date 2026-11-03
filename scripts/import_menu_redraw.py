"""Slice/align the generated RGBA sprites. Preserve generated alpha and complete poses.

This is atlas packaging only: no cutout, body-part warping, repaint or frame blending.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/images/menu-walk-redrawn'
sheet=Image.open(OUT/'source-sheet.png').convert('RGBA')
cells=[sheet.crop((i%4*384,i//4*512,(i%4+1)*384,(i//4+1)*512)) for i in range(8)]
def bounds(im):
    return Image.fromarray((np.array(im)[:,:,3]>32).astype('uint8')*255).getbbox()
heights=[bounds(im)[3]-bounds(im)[1] for im in cells]
scale=432/float(np.median(heights))
def align(im,scale):
    box=bounds(im)
    # Register the hat, not an arm or shoe that moves sideways during a step.
    alpha=np.array(im)[:,:,3]
    hat=alpha[box[1]:box[1]+int((box[3]-box[1])*.43)]>128
    hx=np.where(hat)[1]
    center=(int(hx.min())+int(hx.max()))/2
    width,height=round(im.width*scale),round(im.height*scale)
    resized=im.resize((width,height),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(512,512))
    canvas.alpha_composite(resized,(round(256-center*scale),round(472-box[3]*scale)))
    return canvas
frames=[]
for i,im in enumerate(cells):
    frame=align(im,scale)
    frame.save(OUT/f'step-{i+1}.png',optimize=True)
    frames.append(frame)
idle=Image.open(OUT/'source-idle.png').convert('RGBA')
box=bounds(idle)
idle=align(idle,432/(box[3]-box[1]))
idle.save(OUT/'idle-side.png',optimize=True)
(OUT/'manifest.json').write_text(json.dumps({'method':'imagegen complete poses; alpha-preserving atlas crop and uniform registration only','frameCount':8,'canvas':[512,512],'footAnchor':[.5,472/512],'sourceHeights':heights,'walkScale':scale},indent=2),encoding='utf-8')
review=ROOT/'docs/qa-menu-vignette'
review.mkdir(parents=True,exist_ok=True)
for name,color in [('redrawn-light','#e7e7da'),('redrawn-dark','#293b36')]:
    preview=Image.new('RGB',(1536,1024),color)
    for i,im in enumerate(frames):
        im=im.resize((384,384),Image.Resampling.LANCZOS)
        x,y=(i%4)*384,(i//4)*512
        preview.paste(im,(x,y),im)
        ImageDraw.Draw(preview).text((x+160,y+400),f'Pose {i+1}',fill='#a9aa90')
    preview.save(review/f'{name}.jpg',quality=95)
motion=[]
for im in frames:
    bg=Image.new('RGB',(512,512),'#e7e7da');bg.paste(im,(0,0),im);motion.append(bg)
motion[0].save(review/'redrawn-cycle.gif',save_all=True,append_images=motion[1:],duration=160,loop=0)
print('Packaged eight complete RGBA walking poses and one idle; generated alpha preserved.')

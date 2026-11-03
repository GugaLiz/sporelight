"""Package complete generated crouch/turn poses, preserving alpha and physical scale."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/images/menu-walk-redrawn'
sheet=Image.open(OUT/'source-poses.png').convert('RGBA')
keys=['idle-side','crouch-lower','crouch','turn-quarter','idle-front','crouch-happy']
cells=[sheet.crop((i%3*512,i//3*512,(i%3+1)*512,(i//3+1)*512)) for i in range(6)]
def bounds(im):
    return Image.fromarray((np.array(im)[:,:,3]>32).astype('uint8')*255).getbbox()
box=bounds(cells[0]);scale=432/(box[3]-box[1])
frames=[]
for key,im in zip(keys,cells):
    box=bounds(im);a=np.array(im)[:,:,3]
    # Keep feet centered under the same pivot when the torso rotates or lowers.
    feet=np.where(a[max(0,box[3]-24):box[3]]>128)[1]
    center=(int(feet.min())+int(feet.max()))/2
    resized=im.resize((round(512*scale),round(512*scale)),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(512,512))
    canvas.alpha_composite(resized,(round(256-center*scale),round(472-box[3]*scale)))
    canvas.save(OUT/f'{key}.png',optimize=True);frames.append(canvas)
(OUT/'poses-manifest.json').write_text(json.dumps({'source':'source-poses.png','keys':keys,'scale':scale,'canvas':[512,512],'footAnchor':[.5,472/512],'method':'uniform scale for all poses; foot-centered registration; original generated alpha'},indent=2),encoding='utf-8')
review=ROOT/'docs/qa-menu-vignette'
preview=Image.new('RGB',(1536,1024),'#e7e7da')
for i,im in enumerate(frames):
    x,y=i%3*512,i//3*512;preview.paste(im,(x,y),im)
    ImageDraw.Draw(preview).text((x+190,y+485),keys[i],fill='#4c6053')
preview.save(review/'crouch-turn-poses.jpg',quality=95)
# Export the exact discrete turning sequence for visual review without ghost blends.
right=frames[0].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
quarter_right=frames[3].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
sequence=[right,quarter_right,frames[4],frames[3],frames[0],frames[3],frames[4],quarter_right]
animation=[]
for im in sequence:
    bg=Image.new('RGB',(512,512),'#e7e7da');bg.paste(im,(0,0),im);animation.append(bg)
animation[0].save(review/'turn-through-front.gif',save_all=True,append_images=animation[1:],duration=[650,250,350,250,650,250,350,250],loop=0)
print('Packaged six whole-body crouch and turn poses with shared physical scale.')

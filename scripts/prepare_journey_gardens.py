"""Prepare the two supplied reference images without modifying original materials.

Python 3 + Pillow + numpy; OpenCV is available in the project's art-tools cache.
The wooden bridge retains its supplied isometric perspective and proportions.
"""
from pathlib import Path
import json, sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.cache/art-tools'))
import cv2

OUT = ROOT / 'assets/images/journey-gardens'
SOURCE = OUT / 'references'
OUT.mkdir(parents=True, exist_ok=True)

def remove_checker(image):
    pixels = np.array(image.convert('RGBA'))
    rgb = pixels[:, :, :3].astype('int16')
    neutral = (rgb.max(2) - rgb.min(2) < 23) & (rgb.min(2) > 202)
    _, labels, _, _ = cv2.connectedComponentsWithStats(neutral.astype('uint8'), 8)
    edges = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    pixels[:, :, 3][np.isin(labels, edges[edges != 0])] = 0
    return Image.fromarray(pixels)

bridge = remove_checker(Image.open(SOURCE / 'wood-vine-bridge.png'))
# Remove isolated clipboard edge artifacts while keeping the whole wooden deck and rails.
alpha = np.array(bridge.getchannel('A'))
_, components, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype('uint8'), 8)
main = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
alpha[components != main] = 0
bridge.putalpha(Image.fromarray(alpha))
bridge = bridge.crop(bridge.getchannel('A').getbbox())
bridge.save(OUT / 'vine-deck.png', optimize=True)
ball = remove_checker(Image.open(SOURCE / 'mushroom-ball.png'))
ball = ball.crop(ball.getchannel('A').getbbox())
ball.save(OUT / 'buddy-ball.png', optimize=True)
(OUT / 'manifest.json').write_text(json.dumps({
    'source': 'User-supplied wooden vine bridge and red mushroom ball references, 2026-10-28',
    'assets': {'vine-deck': {'file':'vine-deck.png','reference':'references/wood-vine-bridge.png','method':'checker removal; native isometric perspective and aspect ratio','size':list(bridge.size)},
               'buddy-ball': {'file':'buddy-ball.png','method':'boundary-connected checker removal','size':list(ball.size)}}
}, ensure_ascii=False, indent=2), encoding='utf-8')
print('Prepared vine deck and mushroom companion')

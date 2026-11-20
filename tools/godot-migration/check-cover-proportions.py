"""Compare actual painted hat/body landmarks, not just Sprite scale or canvas."""
import argparse, json
from pathlib import Path
from PIL import Image
import numpy as np

def measure(path):
    a = np.array(Image.open(path).convert('RGBA'))
    h, w = a.shape[:2]
    visible = a[:, :, 3] >= 32
    ys, xs = np.where(visible)
    factor = 512 / h
    red = ((a[:, :, 0].astype(float) > a[:, :, 1] * 1.8)
           & (a[:, :, 0] > 140) & (a[:, :, 1] < 110) & (a[:, :, 3] > 128))
    visited = np.zeros((h, w), dtype=bool)
    components = []
    for y, x in zip(*np.where(red)):
        if visited[y, x]:
            continue
        stack = [(int(x), int(y))]
        visited[y, x] = True
        points = []
        while stack:
            px, py = stack.pop()
            points.append((px, py))
            for nx, ny in ((px-1, py), (px+1, py), (px, py-1), (px, py+1)):
                if 0 <= nx < w and 0 <= ny < h and red[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    stack.append((nx, ny))
        if len(points) >= 12:
            p = np.array(points)
            components.append({'pixels': len(points), 'bounds': [int(p[:,0].min()), int(p[:,1].min()), int(p[:,0].max()), int(p[:,1].max())], 'center': p.mean(axis=0).tolist()})
    cap = max(components, key=lambda c: c['pixels'])
    berries = [c for c in components if c['pixels'] < 1000*(h/512)**2
               and .32*w < c['center'][0] < .68*w and .53*h < c['center'][1] < .72*h
               and c['bounds'][2]-c['bounds'][0] < .15*w]
    if not berries:
        raise ValueError('Berry clasp not found: ' + str(path))
    berry = max(berries, key=lambda c: c['pixels'])
    foot_y = int(ys.max())+1
    return {'path':str(path).replace('\\','/'), 'visibleHeight512':round((foot_y-int(ys.min()))*factor,2),
            'hatWidth512':round((cap['bounds'][2]-cap['bounds'][0]+1)*factor,2),
            'claspToSole512':round((foot_y-berry['center'][1])*factor,2),
            'clasp':berry['center'], 'claspCandidates':berries, 'hatBounds':cap['bounds'], 'footY':foot_y}

parser = argparse.ArgumentParser()
parser.add_argument('--frames', default='godot/assets/images/cover-attention-20261118')
parser.add_argument('--output', required=True)
args = parser.parse_args()
reference = measure(Path('godot/assets/images/home-loading-refine-20261118/idle-quarter.png'))
frames = [measure(p) for p in sorted(Path(args.frames).glob('attention-*.png'))]
failures = []
for f in frames:
    f['hatWidthRatio'] = round(f['hatWidth512']/reference['hatWidth512'],4)
    f['claspToSoleRatio'] = round(f['claspToSole512']/reference['claspToSole512'],4)
    if not .88 <= f['hatWidthRatio'] <= 1.12:
        failures.append(f['path']+': hat width departs from reference by more than 12%')
    if not .88 <= f['claspToSoleRatio'] <= 1.12:
        failures.append(f['path']+': clasp-to-sole body length departs from reference by more than 12%')
report = {'scope':'Painted cap width and clasp-to-sole length at a common 512px logical scale. Tilt/gesture envelope is 12%; this is a regression guard, not user aesthetic acceptance.', 'reference':reference,'frames':frames,'failures':failures,'passed':len(frames)==6 and not failures}
out = Path(args.output)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'reference':reference,'frames':[{k:f[k] for k in ['path','hatWidth512','claspToSole512','hatWidthRatio','claspToSoleRatio']} for f in frames],'passed':report['passed']},ensure_ascii=False))
raise SystemExit(0 if report['passed'] else 1)

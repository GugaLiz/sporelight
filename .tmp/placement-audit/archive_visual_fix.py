import hashlib
import json
import re
import shutil
from pathlib import Path

root = Path.cwd()
out = root / 'docs/qa-godot-native/scene-placement/audit/mainline-visual-fix'
out.mkdir(exist_ok=True)
files = []
for name in ['visual_candidates.gd', 'visual-candidates.json', 'visual_projection.gd', 'visual-projection.json']:
    source = root / '.tmp/placement-audit' / name
    target = out / name
    shutil.copy2(source, target)
    files.append({'source': source.relative_to(root).as_posix(), 'file': name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'bytes': target.stat().st_size})
before = json.loads((out.parent / 'mainline-static-inventory.json').read_text(encoding='utf-8'))
data = json.loads(json.dumps(before))
positions = root / 'godot/presentation/native/original_scenery_positions.gd'
points = {k: list(map(float, v.split(','))) for k, v in re.findall(r'"([^"]+)":Vector3\(([^)]+)\)', positions.read_text(encoding='utf-8'))}
changes = []
for row in data['rows']:
    point = points[row['key']]
    if point != row['finalSupportXYZ']:
        changes.append({'key': row['key'], 'before': row['finalSupportXYZ'], 'after': point})
    row['finalSupportXYZ'] = point
    row['deltaXYZ'] = [round(a-b, 6) for a,b in zip(point,row['mappedReferenceXYZ'])]
    row['movedInThisPlacementPass'] = any(abs(v) > .00001 for v in row['deltaXYZ'])
    x = point[0] - 1.4 if row['level']=='1-2' and point[0]>5.9 else point[0]
    row['support'] = f'f:{round(x)}:{round(point[2])}'
headless = json.loads((out.parent.parent / 'visual-fix-final-cpu/checks.json').read_text(encoding='utf-8'))
data['parentFrozenSource'] = headless['source']
data['method'] = 'Read-only source extraction after five position changes; CPU evidence is visual-fix-final-cpu/checks.json; GPU pending parent review.'
data['currentFileSha256'] = {p: hashlib.sha256((root/p).read_bytes()).hexdigest() for p in before['currentFileSha256']}
for level, counts in data['levelCounts'].items():
    subset = [r for r in data['rows'] if r['level']==level]
    counts['moved'] = sum(r['movedInThisPlacementPass'] for r in subset)
    counts['preserved'] = counts['total'] - counts['moved']
(out / 'inventory.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
(out / 'manifest.json').write_text(json.dumps({'date':'2026-11-11','source':headless['source'],'files':files,'positionChanges':changes,'gpuVerified':False},indent=2)+'\n',encoding='utf-8')
assert len(changes) == 5
print(json.dumps({'archived':len(files),'positionChanges':len(changes),'source':headless['source']}))

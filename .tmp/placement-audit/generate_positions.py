import json
from pathlib import Path
data=json.loads(Path('.tmp/placement-audit/placement-test.json').read_text(encoding='utf-8'))
by={}
for row in data['rows']:
    source=row['layout_reference']
    key=f"{row['level']}/{row['index']}/{row['asset']}/"+','.join(f'{v:.3f}' for v in source)
    at=(round(row['at'][0],5),round(row['at'][1]-.008,5),round(row['at'][2],5))
    if key in by:
        assert by[key]==at,(key,by[key],at)
    by[key]=at
lines=['extends RefCounted','## Placement-only reviewed CPU candidates. Source sizes/assets are unchanged.',
       '## The runtime validates these against current real support/reservations.',
       '## Generated from the 50-state placement regression, never during frames.',
       'const POINTS := {']
for key,at in sorted(by.items()):
    lines.append('\t'+json.dumps(key)+':Vector3('+','.join(f'{v:g}' for v in at)+'),')
lines.append('}\n')
Path('godot/presentation/native/original_scenery_positions.gd').write_text('\n'.join(lines),encoding='utf-8')
print('explicit stable placements',len(by))

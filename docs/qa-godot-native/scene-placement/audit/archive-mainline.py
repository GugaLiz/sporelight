"""Read current placement sources; archive diagnostics without running Godot."""
import hashlib
import json
import math
import re
import shutil
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
RAW = OUT / 'mainline-raw'
DATE = '2026-11-11'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

expected = json.loads((ROOT / 'docs/qa-godot-native/original-elements-audit/mainline-placement-freeze.json').read_text(encoding='utf-8'))['source']
assert all(sha(ROOT / path) == digest for path, digest in expected.items()), 'Historical 363c archive: source changed; create a new evidence bundle instead of overwriting this one.'
RAW.mkdir(exist_ok=True)
manifest = []
for source in sorted((ROOT / '.tmp/placement-audit').iterdir()):
    if not source.is_file():
        continue
    target = RAW / source.name
    if target.exists():
        assert sha(target) == sha(source), f'Refusing to overwrite distinct evidence: {target}'
    else:
        shutil.copy2(source, target)
    status = 'historical-diagnostic'
    if source.name in ('implementation-second.log', 'benchmark.log'):
        status = 'historical-failure-preserved'
    manifest.append({'source': source.relative_to(ROOT).as_posix(), 'archive': target.relative_to(OUT).as_posix(), 'bytes': source.stat().st_size, 'sha256': sha(source), 'status': status})
write('mainline-archive-manifest.json', {'date': DATE, 'count': len(manifest), 'files': manifest})

native = ROOT / 'godot/presentation/native'
text = (native / 'original_garden_dressing.gd').read_text(encoding='utf-8')
catalog = {}
source_section = text.split('const SOURCE_PROPS := {', 1)[1].split('\n}', 1)[0]
for level, block in re.findall(r'"([123]-[1234])": \[(.*?)\n\t\]', source_section, re.S):
    catalog[level] = json.loads('[' + re.sub(r',\s*$', '', block.strip()) + ']')
assert sum(map(len, catalog.values())) == 104

levels = {v['id']: v for v in json.loads((ROOT / 'godot/content/levels.json').read_text(encoding='utf-8'))['levels']}
rows = []
for key, raw in re.findall(r'"([^"]+)":Vector3\(([^)]+)\)', (native / 'original_scenery_positions.gd').read_text(encoding='utf-8')):
    level, index, asset, authored_raw = key.split('/')
    index = int(index)
    authored = list(map(float, authored_raw.split(',')))
    final = list(map(float, raw.split(',')))
    source = catalog[level][index] if index >= 0 else None
    assert source is None or source[0] == asset
    pixels = source[4] if source else 30
    mapped = [authored[0] + (min(1, max(0, authored[0] - 3.5)) * 1.4 if level == '1-2' else 0), authored[1] * (.45 if level == '1-2' else .65), authored[2]]
    delta = [round(a-b, 6) for a, b in zip(final, mapped)]
    logical_x = final[0] - 1.4 if level == '1-2' and final[0] > 5.9 else final[0]
    support = f'f:{round(logical_x)}:{round(final[2])}'
    source_tiles = levels[level]['tiles'] + levels[level].get('sanctuary', {}).get('tiles', [])
    tiles = {t.get('id', f"f:{t['x']}:{t['z']}"): t for t in source_tiles if abs(t['h'] - authored[1]) < .001}
    start = f'f:{round(authored[0])}:{round(authored[2])}'
    seen = set()
    pending = [start]
    while pending:
        at = pending.pop()
        if at in seen or at not in tiles:
            continue
        seen.add(at)
        t = tiles[at]
        pending.extend(f"f:{t['x']+dx}:{t['z']+dz}" for dx, dz in ((1,0),(-1,0),(0,1),(0,-1)))
    assert support in seen, (key, support, start)
    assert abs(delta[1]) < .00001, key
    rows.append({'key': key, 'level': level, 'index': index, 'asset': asset, 'originalReferenceXYZ': [source[1], source[3], source[2]] if source else authored, 'layoutReferenceXYZ': authored, 'mappedReferenceXYZ': mapped, 'finalSupportXYZ': final, 'spriteAnchorLift': .008, 'deltaXYZ': delta, 'movedInThisPlacementPass': any(abs(x) > .00001 for x in delta), 'pixels': pixels, 'nominalWidth': pixels * math.sqrt(2) / 70, 'support': support, 'sameHeightConnectedStaticIsland': True})
assert len(rows) == 102
assert len({r['key'] for r in rows}) == 102
assert sum(r['index'] >= 0 for r in rows) == 98
assert not any(r['level'] == '1-1' for r in rows)
counts = {}
for level in sorted({r['level'] for r in rows}):
    subset = [r for r in rows if r['level'] == level]
    counts[level] = {'total': len(subset), 'moved': sum(r['movedInThisPlacementPass'] for r in subset), 'preserved': sum(not r['movedInThisPlacementPass'] for r in subset)}
headless = json.loads((OUT.parent / 'headless/checks.json').read_text(encoding='utf-8'))
assert headless['source']['sha256'] == '363c9ca6569af23eff331128ff7e2734562894b15f0484bce0210277f554a783'
source_files = list(json.loads((ROOT / 'docs/qa-godot-native/original-elements-audit/mainline-placement-freeze.json').read_text(encoding='utf-8'))['source'])
write('mainline-static-inventory.json', {'date': DATE, 'method': 'read-only source extraction; no engine/browser run', 'parentFrozenSource': headless['source'], 'currentFileSha256': {f: sha(ROOT / f) for f in source_files}, 'catalogInstances': 104, 'firstGardenPreserved': 6, 'explicitPositions': 102, 'extrasInSecondGarden': 4, 'levelCounts': counts, 'rows': rows})
print(json.dumps({'archived': len(manifest), 'counts': counts, 'source': headless['source'], 'headlessSuites': len(headless['results']), 'headlessPassed': headless['passed']}))

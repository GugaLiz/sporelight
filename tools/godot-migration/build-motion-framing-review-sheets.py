"""Build labelled contact sheets from already captured QA PNGs; no browser work."""
import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'.cache/native-qa-python'))
from PIL import Image, ImageDraw


def sheet(items, output, columns=2, width=600):
    rows = math.ceil(len(items)/columns)
    height = 370
    result = Image.new('RGB', (columns*width, rows*height), '#eeeae1')
    draw = ImageDraw.Draw(result)
    for i, (path, label) in enumerate(items):
        image = Image.open(path).convert('RGB')
        image.thumbnail((width, height-24))
        x, y = i % columns*width, i // columns*height
        result.paste(image, (x, y+24))
        draw.text((x+5, y+5), label, fill='#222222')
    result.save(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    args = parser.parse_args()
    root = ROOT/args.directory
    count = 0
    for p in root.glob('*/framing/*/checks.json'):
        data = json.loads(p.read_text(encoding='utf-8'))
        names = ['arrival', 'overview', 'returned']
        if not all((p.parent/(n+'.png')).is_file() for n in names):
            continue
        items = [(p.parent/(n+'.png'), f"{data['size']} {data['level']} {n}") for n in names]
        sheet(items, p.parent/'review-sheet.png', columns=3, width=480)
        count += 1
    for p in root.glob('*/motion/*/*/frames.json'):
        data = json.loads(p.read_text(encoding='utf-8'))
        if data.get('keyframes'):
            items = [(p.parent/f['image'], f"target {f['targetProgress']:.2f}; observed {f['observedProgress']:.3f}") for f in data['keyframes']]
            if (p.parent/'999-settled.png').is_file():
                items.append((p.parent/'999-settled.png', 'settled +700ms'))
            sheet(items, p.parent/'keyframes-sheet.png')
        frames = data['samples']
        for start in range(0, len(frames), 12):
            items = [(p.parent/f['image'], f"{f['image']} observed {f['observedProgress']:.3f}") for f in frames[start:start+12]]
            sheet(items, p.parent/f'all-frames-{start//12:02d}.png', columns=3, width=480)
        count += 1
    print(json.dumps({'directoriesPrepared': count, 'visualReview': 'pending'}))


if __name__ == '__main__':
    main()

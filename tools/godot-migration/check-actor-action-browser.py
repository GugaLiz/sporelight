"""Real-input sow/stand/repair frames; reuse established route helpers, no runtime edits."""
import argparse
import base64
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/native-qa-python'))
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--sizes', default='1280x720,844x390')
args = parser.parse_args()
out = ROOT / args.output
out.mkdir(parents=True, exist_ok=True)

# Load only the existing helper definitions, without its browser runner. This
# preserves the tested real-input targeting and contact guards in one place.
helper_path = ROOT / 'tools/godot-migration/check-native-browser.py'
helper_source = helper_path.read_text(encoding='utf-8').split('\nwith sync_playwright() as p:')[0]
original_argv = sys.argv
sys.argv = [str(helper_path), '--base', args.base, '--output', args.output]
h = {'__file__': str(helper_path), '__name__': 'native_helpers'}
exec(compile(helper_source, str(helper_path), 'exec'), h)
sys.argv = original_argv

ARM = """() => {
 window.__poseSamples=[];window.__poseCropSamples=[];window.__poseCapturing=true;const seen=new Set();
 const crop=document.createElement('canvas');crop.width=240;crop.height=220;const ctx=crop.getContext('2d');
 function observe(){
  const s=window.__sporelightState,c=s?.character?.luvie;
  if(c&&window.__poseCapturing){
   if(['sow','complete'].includes(c.clip)){
    const left=Math.round(c.foot[0]-120),top=Math.round(c.foot[1]-180);
    ctx.clearRect(0,0,240,220);ctx.drawImage(document.querySelector('#canvas'),left,top,240,220,0,0,240,220);
    window.__poseCropSamples.push({at:performance.now(),observedClip:c.clip,observedFrame:c.frame,qaSequence:s.qaSequence,sourceRect:[left,top,240,220],png:crop.toDataURL('image/png')});
   }
   const key=c.clip+':'+c.frame;
   if(!seen.has(key)){
    seen.add(key);window.__poseSamples.push({at:performance.now(),character:structuredClone(c),native:structuredClone(s.native),snapshot:structuredClone(s.snapshot),motion:structuredClone(s.motion),qaSequence:s.qaSequence,png:document.querySelector('#canvas').toDataURL('image/png')});
   }
  }
  if(window.__poseCapturing)requestAnimationFrame(observe);
 }
 requestAnimationFrame(observe);
}"""


def capture_action(page, command, directory):
    directory.mkdir(exist_ok=True)
    page.screenshot(path=str(directory/'before.png'))
    before = h['fresh'](page)
    page.evaluate(ARM)
    after = h['action'](page, command)
    page.wait_for_timeout(300)
    samples = page.evaluate('() => {window.__poseCapturing=false;return window.__poseSamples;}')
    crops = page.evaluate('window.__poseCropSamples')
    for index, crop in enumerate(crops):
        name = f"crop-{index:03d}.png"
        (directory/name).write_bytes(base64.b64decode(crop.pop('png').split(',', 1)[1]))
        crop['image'] = name
    for index, sample in enumerate(samples):
        name = f"{index:02d}-{sample['character']['clip']}-{sample['character']['frame']}.png"
        (directory/name).write_bytes(base64.b64decode(sample.pop('png').split(',', 1)[1]))
        sample['image'] = name
    page.screenshot(path=str(directory/'after.png'))
    frames = sorted({s['character']['frame'] for s in samples if s['character']['clip'] == 'sow'})
    row = {'command': command, 'before': before['character'], 'after': after['character'],
           'samples': samples, 'consecutiveRenderCrops': crops, 'sowFrames': frames, 'completed': after['snapshot']['completed'],
           'visualReview': 'pending', 'frameLabels': 'Observed QA publication, up to one publication/render interval from GPU pixels; inspect adjacent image samples.'}
    (directory/'checks.json').write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding='utf-8')
    h['check_contacts'](after, command)
    if command.startswith('grow:'):
        assert frames == [0, 1, 2, 3, 4], 'Missing actual sow frames: '+str(frames)
    elif command == 'repair':
        assert any(s['character']['clip'] == 'complete' for s in samples), 'Missing actual completion pose'
    return row


report = {'build': h['build'], 'results': [], 'scope': 'QA restores initial state only. Growth, walking and repair use actual input. No frame seeking, animation slowdown or runtime edits. Pixel/art review is separate from contact assertions.'}
with sync_playwright() as p:
    browser = p.chromium.launch(channel='chrome', headless=True)
    for size_text in args.sizes.split(','):
        width, height = map(int, size_text.split('x'))
        folder = out / size_text
        folder.mkdir(exist_ok=True)
        context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('console', lambda m: errors.append(m.text) if m.type == 'error' or 'SCRIPT ERROR:' in m.text else None)
        row = {'size': [width, height], 'passed': False, 'actions': []}
        try:
            page.goto(args.base+'?qa=1', wait_until='domcontentloaded', timeout=300000)
            page.wait_for_function('() => window.__sporelightState?.snapshot', timeout=300000)
            page.wait_for_selector('#status', state='detached', timeout=300000)
            initial = next(c['initial'] for c in h['cases'] if c['id'] == '1-1')
            h['prepare'](page, initial)
            row['actions'].append(capture_action(page, 'grow:root:right', folder/'growth'))
            for tile in ['g:root:1:0', 'f:2:0', 'f:3:0', 'f:3:-1', 'f:3:-2']:
                h['move_to'](page, tile)
            row['actions'].append(capture_action(page, 'repair', folder/'repair'))
            assert h['fresh'](page)['snapshot']['completed'], 'Actual repair completes current first level'
            assert not errors, str(errors)
            row['passed'] = True
        except Exception as error:
            row['reason'] = str(error)
            page.screenshot(path=str(folder/'failure.png'), timeout=120000)
        finally:
            row['errors'] = errors
            row['inputTrace'] = list(h['input_trace'])
            h['input_trace'].clear()
            report['results'].append(row)
            context.close()
            (out/'checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
            print(json.dumps({'size': size_text, 'passed': row['passed'], 'reason': row.get('reason')}), flush=True)
    browser.close()
report['passed'] = all(r['passed'] for r in report['results'])
(out/'checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
sys.exit(0 if report['passed'] else 1)

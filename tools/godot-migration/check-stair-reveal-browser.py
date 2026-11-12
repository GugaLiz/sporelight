"""Reuse real-input motion capture for stair reveal, removal, undo and replay."""
import importlib.util
import sys
from pathlib import Path

PATH = Path(__file__).with_name('check-motion-framing-browser.py')
spec = importlib.util.spec_from_file_location('stair_reveal_motion', PATH)
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)
review.MOTIONS = [
    ('1-1', 'grow:root:down'), ('1-1', 'retract:root'),
    ('1-2', 'grow:root:up'), ('1-2', 'grow:root:down'),
    ('3-3', 'grow:root:right'), ('3-4', 'grow:root:right'),
]
capture = review.capture_motion


def capture_lifecycle(page, h, case, command, folder):
    row = capture(page, h, case, command, folder)
    before, expected = review.transitions(case, command)
    page.keyboard.press('z')
    h['input_trace'].append({'kind': 'stair-reveal-undo', 'key': 'z'})
    h['stable'](page)
    page.wait_for_timeout(700)
    undo = review.save_state(page, h, folder, 'undo')
    h['check_contacts'](undo, 'stair reveal undo')
    assert undo['snapshot']['growth'] == before['growth'], 'Real undo restores previous road topology'
    h['action'](page, command)
    page.wait_for_timeout(700)
    replay = review.save_state(page, h, folder, 'replayed')
    h['check_contacts'](replay, 'stair reveal replay')
    assert replay['snapshot']['growth'] == expected['growth'], 'Replay restores original road topology'
    row['undo'] = undo
    row['replayed'] = replay
    row['realUndoAndReplay'] = True
    review.write_json(folder/'frames.json', row)
    return row


review.capture_motion = capture_lifecycle
if '--mode' not in sys.argv:
    sys.argv += ['--mode', 'motion']
if __name__ == '__main__':
    sys.exit(review.main())

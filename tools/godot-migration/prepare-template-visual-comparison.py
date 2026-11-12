"""Isolated QA-enabled release exports for engine image comparison, never delivery.

Three QA debug guards and an opt-in snapshot physics freeze differ from game
code; both engines receive byte-identical PCKs. Normal exports are unmodified.
"""
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE = Path(os.environ.get('GODOT_BIN', str(Path.home() / '.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe')))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def runtime_files():
    return {p.relative_to(ROOT / 'godot') for p in (ROOT / 'godot').rglob('*')
            if p.is_file() and not any(part in ['.godot', 'build', 'tests'] for part in p.relative_to(ROOT / 'godot').parts)}


def run(arguments, logfile):
    result = subprocess.run([str(ENGINE), '--headless', *arguments], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    logfile.write_bytes(result.stdout)
    text = result.stdout.decode('utf-8', errors='replace')
    if result.returncode or any(word in text for word in ['SCRIPT ERROR:', 'Parse Error:', 'ERROR:']):
        raise RuntimeError('Export failed: ' + str(logfile))


def main():
    manifest = json.loads((ROOT / 'docs/qa-godot-native/custom-web-template/release-build.json').read_text(encoding='utf-8'))
    patch = (ROOT / 'tools/godot-migration/patches/godot-4.7.2-web-scene-demand.patch').read_bytes()
    assert manifest['status'] == 'built' and manifest['target'] == 'release'
    assert manifest['sourceCommit'] == 'ed1daf0bf001b61586d9930840f2f1394092c079'
    assert manifest['patchSha256'] == sha(patch)
    template = Path(manifest['template'])
    assert sha(template.read_bytes()) == manifest['templateSha256']
    destination = ROOT / '.cache/template-visual-project/godot'
    # Fixed workspace-owned copy; reject stale files instead of recursively deleting.
    source_files = runtime_files()
    if destination.exists():
        copied_files = {p.relative_to(destination) for p in destination.rglob('*') if p.is_file()
                        and '.godot' not in p.relative_to(destination).parts}
        assert not copied_files - source_files, 'Stale isolated files; use a new reviewed fixture directory'
    original_hashes = {}
    for relative in source_files:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'godot' / relative, target)
        original_hashes[str(relative).replace('\\', '/')] = sha(target.read_bytes())
    original_main_bytes = (destination / 'application/main.gd').read_bytes()
    original = original_main_bytes.decode('utf-8')
    assert original.count(' and OS.is_debug_build()') == 1
    assert original.count(' or not OS.is_debug_build()') == 2
    fixture = original.replace(' and OS.is_debug_build()', '').replace(' or not OS.is_debug_build()', '')
    # Fixed snapshots must not continue sub-pixel grounding/follow-camera motion.
    # This branch exists ONLY in the isolated verification fixture.
    line_ending = '\r\n' if '\r\n' in fixture else '\n'
    anchor = '\t\t\t_sync_hud()' + line_ending + '\t\t"action":'
    assert fixture.count(anchor) == 1
    freeze = ('\t\t\t_sync_hud()' + line_ending +
              '\t\t\tif bool(request.get("freezePhysics", false)) and native_movement != null:' + line_ending +
              '\t\t\t\tnative_movement.suspended = true' + line_ending +
              '\t\t\t\tview.reset_camera()' + line_ending + '\t\t"action":')
    fixture = fixture.replace(anchor, freeze)
    (destination / 'application/main.gd').write_bytes(fixture.encode('utf-8'))
    preset = (destination / 'export_presets.cfg').read_text(encoding='utf-8')
    assert preset.count('res://../.cache/godot-web-templates/web_release.zip') == 1
    (destination / 'export_presets.cfg').write_text(preset.replace('res://../.cache/godot-web-templates/web_release.zip', template.as_posix()), encoding='utf-8')
    evidence = ROOT / 'docs/qa-godot-native/full-performance/template-visual'
    evidence.mkdir(parents=True, exist_ok=True)
    run(['--path', str(destination), '--editor', '--import'], evidence / 'import.log')
    packs = []
    for variant, name in [('template-visual-official', 'Web'), ('template-visual-optimized', 'Web Optimized')]:
        output = ROOT / 'godot/build' / variant
        output.mkdir(parents=True, exist_ok=True)
        run(['--path', str(destination), '--export-release', name, str(output / 'index.html')], evidence / (variant + '.log'))
        shutil.copytree(ROOT / 'godot/web/loader', output / 'loader', dirs_exist_ok=True)
        packs.append(output / 'index.pck')
        metadata = {'verificationOnly': True, 'qaGuardDelta': 'Three QA debug guards removed; opt-in snapshot freezePhysics suspends movement and snaps camera in isolated main only',
                    'originalMainSha256': sha(original_main_bytes), 'fixtureMainSha256': sha(fixture.encode()),
                    'webMode': 'release', 'template': {'kind': 'official' if name == 'Web' else 'scene-demand',
                    'customTemplateSha256': None if name == 'Web' else manifest['templateSha256']},
                    'pckSha256': sha(packs[-1].read_bytes()),
                    'scope': 'Engine image comparison fixture, never delivered. Independent normal exports retain QA guards.'}
        (output / 'build.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    assert sha(packs[0].read_bytes()) == sha(packs[1].read_bytes()), 'Comparison requires byte-identical PCKs'
    assert runtime_files() == source_files, 'Runtime file set changed while preparing the engine fixture'
    files = {str(p).replace('\\', '/'): sha((ROOT / 'godot' / p).read_bytes()) for p in sorted(source_files)}
    assert files == original_hashes, 'Runtime changed while preparing the engine fixture; repeat after sources are frozen'
    (evidence / 'fixture.json').write_text(json.dumps({'runtimeFiles': files, 'mainGuardDelta': [
        'Remove one and OS.is_debug_build()', 'Remove two or not OS.is_debug_build()',
        'Only snapshot request.freezePhysics: suspend native movement and reset camera after _sync_hud'],
        'exportPresetDelta': 'Absolute verified candidate template path in isolated preset',
        'pckSha256': sha(packs[0].read_bytes()), 'templateSha256': manifest['templateSha256']}, indent=2) + '\n', encoding='utf-8')
    print('Isolated comparison exports ready; identical PCK SHA256: ' + sha(packs[0].read_bytes()), flush=True)


if __name__ == '__main__':
    main()

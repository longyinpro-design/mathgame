#!/usr/bin/env python3
"""Candidate-bound Godot checks; reject engine/script errors even when Godot exits zero."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HEADLESS = ['twenty_four_test.gd', 'route_redesign_test.gd', 'story_test.gd', 'assets_test.gd', 'boundary_test.gd', 'session_test.gd', 'p3_test.gd', 'p4_p5_test.gd', 'p6_p7_test.gd', 'p8_test.gd', 'review_repairs_test.gd', 'empty_profile_migration_test.gd', 'discovery_test.gd', 'hint_layers_test.gd', 'proof_steps_test.gd']
WINDOWS = ['fl07_playtest.gd', 'story_playtest.gd', 'story_chapter_playtest.gd', 'actors_playtest.gd', 'p2_playtest.gd', 'p3_playtest.gd', 'p4_p5_playtest.gd', 'p6_playtest.gd', 'battle_playtest.gd', 'p8_playtest.gd', 'review_repairs_playtest.gd', 'layout_fixes_playtest.gd', 'empty_profile_migration_playtest.gd', 'scene_integration_playtest.gd', 'ground_occlusion_playtest.gd', 'village_scene_playtest.gd', 'island_original_playtest.gd']

def sources() -> dict[str, str]:
    paths = [ROOT/'scripts/island_scene_preview.gd', ROOT/'启动全岛原图试玩.command', ROOT/'project.godot', ROOT/'game/forest_release.tscn', ROOT/'docs/production/forest_levels.json', ROOT/'docs/production/legacy_fl07.json', ROOT/'assets/source/terrain-textures-v1.png']
    for directory in ['scripts/core', 'scripts/content', 'scripts/persistence', 'scripts/progression', 'scripts/learning', 'scripts/mechanisms', 'scripts/ui', 'assets/runtime/forest', 'tests/forest']:
        paths += [p for p in (ROOT/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    # Existing rule/render/audio inputs are unchanged but remain part of actual execution.
    for directory in ['scripts/cargo', 'scripts/encounter', 'assets/fonts', 'assets/audio/v3']:
        paths += [p for p in (ROOT/directory).rglob('*') if p.is_file()]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}

def stop_process(process: subprocess.Popen | None) -> None:
    if process is None:
        return
    if process.poll() is None:
        process.terminate()
    try:
        process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--windows', action='store_true', help='Run actual Godot window input checks sequentially.')
    parser.add_argument('--output', default='docs/playtest/forest-release/verification.json')
    args = parser.parse_args()
    executable = shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
    output_path = ROOT/args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    before = sources()
    reports = []
    environment = os.environ.copy()
    foreground_ready = False
    if args.windows and sys.platform == 'darwin':
        try:
            foreground = subprocess.run(['osascript', '-e', 'tell application "System Events" to get unix id of (first application process whose frontmost is true)'], capture_output=True, text=True, timeout=10)
            if foreground.returncode == 0 and foreground.stdout.strip().isdigit():
                environment['PIXEL_FOREST_FOREGROUND_PID'] = foreground.stdout.strip()
                foreground_ready = True
        except subprocess.TimeoutExpired:
            pass
        if not foreground_ready:
            # System Events permission missing: run the visible NO_FOCUS windows without the
            # courtesy foreground-restore handshake instead of blocking the whole suite.
            print('Foreground app not identifiable (System Events unavailable); running window tests without foreground restore.', file=sys.stderr)
    with tempfile.TemporaryDirectory(prefix='pixel-forest-verification-') as temporary:
        checks = [(name, True) for name in HEADLESS]+([(name, False) for name in WINDOWS] if args.windows else [])
        for name, headless in checks:
            log = Path(temporary)/(Path(name).stem+'.log')
            command = [executable]+(['--headless'] if headless else [])+['--path', str(ROOT), '--script', 'tests/forest/'+name, '--log-file', str(log)]
            process = None
            stage = "Godot startup"
            try:
                signal = Path(temporary)/(name+'.ready')
                environment['PIXEL_FOREST_WINDOW_READY'] = str(signal) if not headless and sys.platform == 'darwin' and foreground_ready else ''
                process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                if environment['PIXEL_FOREST_WINDOW_READY']:
                    deadline = time.monotonic()+15
                    while not signal.exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.05)
                    if signal.exists():
                        script = 'tell application "System Events" to set frontmost of (first application process whose unix id is '+environment['PIXEL_FOREST_FOREGROUND_PID']+') to true'
                        stage = 'foreground restoration'
                        restore = subprocess.run(['osascript','-e',script],capture_output=True,text=True,timeout=10)
                        if restore.returncode == 0: Path(str(signal)+'.restored').write_text('restored')
                        else: print('Foreground restore failed: '+restore.stderr,flush=True)
                stage = 'Godot test execution'
                stdout, stderr = process.communicate(timeout=100)
                text = (log.read_text(errors='replace') if log.exists() else stdout)+stderr
                # This known macOS sandbox CA diagnostic is unrelated to the offline game and has a distinct callsite.
                filtered = re.sub(r'ERROR: Condition "ret != noErr" is true\. Returning: ""\n\s+at: get_system_ca_certificates[^\n]*\n?', '', text) if headless else text
                summary = re.findall(r'FOREST [^\n]*?(\d+)/(\d+) PASS', text)
                errors = [line for line in filtered.splitlines() if 'ERROR:' in line or 'SCRIPT ERROR' in line]
                success = process.returncode == 0 and bool(summary) and all(a == b for a, b in summary) and not errors
                passed, total = map(int, summary[-1]) if summary else (0, 0)
                result = {'test': name, 'mode': 'headless' if headless else 'macOS_window', 'status': 'PASS' if success else 'FAIL', 'passed': passed, 'total': total, 'exit_code': process.returncode, 'errors': errors, 'command': command}
                (output_path.parent/(Path(name).stem+'.log')).write_text(text)
                print(f"{result['status']} {name}: {passed}/{total}", flush=True)
                if not success: print('\n'.join(filtered.splitlines()[-35:]), flush=True)
            except subprocess.TimeoutExpired:
                stop_process(process)
                result = {'test': name, 'status': 'FAIL', 'errors': [stage+' timed out; child terminated and reaped']}
                print('FAIL '+name+': '+stage+' timeout; child reaped', flush=True)
            finally:
                stop_process(process)
            reports.append(result)
    after = sources()
    stable = before == after
    success = stable and all(r['status'] == 'PASS' for r in reports)
    result = {'status': 'PASS' if success else 'FAIL', 'source_stable_during_run': stable, 'source_sha256': after, 'results': reports, 'window_checks_included': args.windows, 'limits': ['No child playtest, learning-effect, touch-device or release acceptance.', 'Window fixtures prepare previous slices with commands; tested slice actions use viewport mouse/keyboard input.', 'All automated profiles are independent /tmp paths.', 'Known headless macOS CA diagnostics are retained in logs and excluded only by their exact callsite.']}
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    return 0 if success else 1

if __name__ == '__main__':
    sys.exit(main())

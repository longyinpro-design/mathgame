#!/usr/bin/env python3
"""Validate the workshop hub with isolated saves and explicit rendering evidence.

python3 tests/workshop/run_hub_checks.py             # rules + native window
python3 tests/workshop/run_hub_checks.py --headless  # rules + flow; no visual QA
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/playtest/workshop-chapter-hub'


def inputs():
    patterns = ('scripts/workshop/*.gd', 'scripts/market/level_host.gd',
                'scripts/persistence/*.gd', 'scripts/content/content_catalog.gd',
                'scripts/cargo/skin.gd', 'scripts/ui/presentation_layer.gd',
                'game/workshop*.tscn', 'tests/workshop/hub*.gd',
                'tests/workshop/run_hub_checks.py', '启动齿轮工坊岛.command',
                'project.godot', 'docs/production/workshop_chapter_hub.md')
    files = {path for pattern in patterns for path in ROOT.glob(pattern)}
    # Include referenced art/fonts and shared presentation scripts transitively.
    pending = list(files)
    while pending:
        path = pending.pop()
        if path.suffix not in {'.gd', '.tscn', '.json', '.tres'}:
            continue
        for resource in re.findall(r'res://([^"\s\)]+)', path.read_text()):
            dependency = ROOT / resource
            if dependency.is_file() and dependency not in files:
                files.add(dependency)
                pending.append(dependency)
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(files)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--headless', action='store_true')
    args = parser.parse_args()
    godot = os.environ.get('GODOT') or shutil.which('godot') or shutil.which('godot4')
    if not godot and Path('/Applications/Godot.app/Contents/MacOS/Godot').is_file():
        godot = '/Applications/Godot.app/Contents/MacOS/Godot'
    if not godot:
        parser.error('Godot was not found; set GODOT to the installed executable')
    OUT.mkdir(parents=True, exist_ok=True)
    candidate = inputs()
    mode = 'headless' if args.headless else 'window'
    runs = []
    with tempfile.TemporaryDirectory(prefix='workshop-hub-') as directory:
        environment = os.environ.copy()
        for name in ('CACHE', 'CONFIG', 'DATA'):
            path = Path(directory) / name.lower()
            path.mkdir()
            environment['XDG_' + name + '_HOME'] = str(path)
        version = subprocess.check_output([godot, '--version'], env=environment, text=True).strip()
        for name, script, headless in (
                ('rules', 'hub_test.gd', True),
                (mode, 'hub_playtest.gd', args.headless)):
            command = [godot, '--audio-driver', 'Dummy', *(['--headless'] if headless else []), '--path', str(ROOT),
                       '--script', 'tests/workshop/' + script]
            result = subprocess.run(command, cwd=ROOT, env=environment, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=150)
            output = result.stdout
            (OUT / (name + '.log')).write_text(output)
            summary = re.search(r'WORKSHOP HUB (?:RULES|HEADLESS FLOW|WINDOW) (\d+)/(\d+) PASS', output)
            errors = [line for line in output.splitlines() if 'ERROR:' in line]
            passed = result.returncode == 0 and summary is not None and summary[1] == summary[2] and not errors
            runs.append(dict(name=name, passed=passed, returncode=result.returncode,
                             checks=int(summary[2]) if summary else 0, errors=errors))
            print(name, 'PASS' if passed else 'FAIL', runs[-1]['checks'], flush=True)
    if candidate != inputs():
        raise RuntimeError('Source changed during validation; rerun against the final candidate')
    receipt = dict(godot=version,
                   platform=platform.system(), inputs=candidate, runs=runs,
                   native_rendering=not args.headless,
                   limitations=['Dummy audio driver; audible output not validated.',
                                'No Godot 4.7, macOS, touch or child-comprehension acceptance inferred.',
                                'Headless runs do not establish rendered appearance.' if args.headless else
                                'Native viewport-injected mouse/keyboard checks at 1280x720 and 960x540.'])
    if not args.headless:
        receipt['screenshots'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in OUT.glob('*.png')}
    (OUT / ('verification-' + mode + '.json')).write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(0 if all(run['passed'] for run in runs) else 1)


if __name__ == '__main__':
    main()

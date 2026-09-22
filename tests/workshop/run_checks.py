#!/usr/bin/env python3
"""GW01 checks against exact source/dependency hashes; player saves are never used."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/playtest/workshop-gw01'
GODOT = os.environ.get('GODOT', '/Applications/Godot.app/Contents/MacOS/Godot')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    files = set()
    for directory in ('scripts/workshop', 'assets/runtime/workshop/gw01', 'tests/workshop'):
        files.update(p for p in (ROOT / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    for path in ('game/workshop_gw01.tscn', 'docs/production/workshop_gw01_sample.md',
                 '启动齿轮工坊GW01样板.command'):
        files.add(ROOT / path)
    deps = {'project.godot'}
    # Track the resource dependency closure, including scripts, fonts, textures and manifests.
    scan = [p for p in files if p.suffix in {'.gd', '.tscn', '.tres', '.json'}]
    seen = set()
    while scan:
        path = scan.pop()
        if path in seen:
            continue
        seen.add(path)
        if path.suffix not in {'.gd', '.tscn', '.tres', '.json'}:
            continue
        for match in re.findall(r'res://([^"\s\)]+)', path.read_text()):
            target = ROOT / match
            if target.is_file():
                deps.add(match)
                scan.append(target)
    return {'candidate': {str(p.relative_to(ROOT)): digest(p) for p in sorted(files)},
            'dependencies': {p: digest(ROOT / p) for p in sorted(deps) if ROOT / p not in files}}


def run():
    OUT.mkdir(parents=True, exist_ok=True)
    candidate = inputs()
    runs = []
    with tempfile.TemporaryDirectory(prefix='gw01-checks-') as temp:
        for label, headless, script in [('rules', True, 'gw01_test.gd'), ('window', False, 'gw01_playtest.gd')]:
            command = [GODOT, *(['--headless'] if headless else []), '--path', str(ROOT),
                       '--script', 'tests/workshop/' + script, '--log-file', str(Path(temp) / (label + '.log'))]
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=120)
            (OUT / (label + '.log')).write_text(result.stdout)
            summary = re.search(r'GW01 (?:RULES|WINDOW): (\d+) checks, (\d+) failures', result.stdout)
            # Only the known macOS certificate probe can occur in sandboxed headless mode.
            errors = [line for line in result.stdout.splitlines() if 'ERROR:' in line
                      and 'Condition "ret != noErr"' not in line]
            passed = result.returncode == 0 and summary and int(summary[2]) == 0 and not errors
            runs.append({'name': label, 'command': command, 'returncode': result.returncode,
                         'checks': int(summary[1]) if summary else 0, 'passed': bool(passed),
                         'output_sha256': digest(OUT / (label + '.log')), 'errors': errors})
            print(label, 'PASS' if passed else 'FAIL', runs[-1]['checks'], flush=True)
    if inputs() != candidate:
        raise RuntimeError('Candidate or dependency changed during checks')
    (OUT / 'candidate.json').write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + '\n')
    receipt = {'candidate_sha256': digest(OUT / 'candidate.json'),
               'godot': subprocess.check_output([GODOT, '--version'], text=True).strip(),
               'runs': runs, 'screenshots': {p.name: digest(p) for p in sorted(OUT.glob('*.png'))},
               'limitations': ['macOS desktop mouse and keyboard at 1280x720 and 960x540 only',
                              'Independent GW01 profile, no cross-island journey/unlock/reward integration',
                              'No touch-device, child comprehension or learning outcome acceptance']}
    (OUT / 'verification.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(0 if all(r['passed'] for r in runs) else 1)


if __name__ == '__main__':
    run()

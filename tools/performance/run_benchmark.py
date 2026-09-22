#!/usr/bin/env python3
"""Run one bounded native presentation benchmark and bind it to source hashes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]

def hashes():
    paths = [ROOT / 'project.godot']
    for directory in ['scripts', 'game', 'tools/performance', 'tests/forest']:
        paths += [p for p in (ROOT / directory).rglob('*') if p.suffix in ['.gd', '.tscn', '.py']]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    before = hashes()
    env = dict(os.environ, NSAppSleepDisabled='YES', PIXEL_PERFORMANCE_OUTPUT=str(output))
    command = [shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot', '--path', str(ROOT), '--script', 'res://tools/performance/presentation_benchmark.gd']
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        log, _ = process.communicate(timeout=210)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            log, _ = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); log, _ = process.communicate()
        log += '\nERROR: benchmark timed out; child reaped\n'
    output.with_suffix('.log').write_text(log)
    after = hashes()
    success = process.returncode == 0 and 'BENCHMARK COMPLETE' in log and 'ERROR:' not in log and before == after
    report = json.loads(output.read_text()) if success else {}
    report.update(status='PASS' if success else 'FAIL', source_sha256=before, source_stable=before == after, command=command)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(log, end='')
    return 0 if success else 1

if __name__ == '__main__':
    raise SystemExit(main())

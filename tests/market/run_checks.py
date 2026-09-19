#!/usr/bin/env python3
"""Exact-candidate MK01 rules and native-window checks with isolated test saves."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs/playtest/market-mk01-reasoning'

def sources():
    paths = [ROOT/'game/market_mk01.tscn', ROOT/'project.godot', ROOT/'启动千灯集市样板.command', ROOT/'assets/source/market/mechanisms-source-v1.png', ROOT/'assets/runtime/cargo-props-v5.png', ROOT/'scripts/cargo/skin.gd', ROOT/'scripts/persistence/save_repository.gd', ROOT/'tests/forest/window_focus.gd']
    for folder in ['scripts/market', 'tests/market', 'scripts/content', 'assets/runtime/market', 'assets/runtime/forest/ui', 'assets/fonts']:
        paths += [p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ['.uid','.import']]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path, help='Optional original-runtime SHA256 map for this delivery audit.')
    args = parser.parse_args()
    baseline = None
    baseline_path = None
    if args.baseline:
        baseline_path = args.baseline if args.baseline.is_absolute() else ROOT/args.baseline
        if not baseline_path.is_file():
            parser.error('Explicit baseline file does not exist: '+str(baseline_path))
        baseline = json.loads(baseline_path.read_text())
    OUTPUT.mkdir(parents=True, exist_ok=True)
    before = sources()
    results = []
    executable = shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
    for name, headless in [('mk01_test.gd', True), ('mk01_playtest.gd', False)]:
        command = [executable] + (['--headless'] if headless else []) + ['--path', str(ROOT), '--script', 'tests/market/'+name, '--log-file', str(OUTPUT/(Path(name).stem+'.log'))]
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            text, _ = process.communicate(timeout=100)
        except subprocess.TimeoutExpired:
            process.terminate()
            try: text, _ = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); text, _ = process.communicate()
            text += '\nERROR: bounded runner timed out and reaped child\n'
        (OUTPUT/(Path(name).stem+'-stdout.log')).write_text(text)
        # Known offline headless macOS CA probe; all other engine errors fail.
        filtered = re.sub(r'ERROR: Condition "ret != noErr" is true\. Returning: ""\n\s+at: get_system_ca_certificates[^\n]*\n?', '', text) if headless else text
        errors = [line for line in filtered.splitlines() if 'ERROR:' in line or 'SCRIPT ERROR' in line]
        match = re.search(r'MARKET MK01 (?:RULES|WINDOW) (\d+)/(\d+) PASS', text)
        passed, total = map(int,match.groups()) if match else (0,0)
        ok = process.returncode == 0 and total > 0 and passed == total and not errors
        results.append({'name':name, 'command':command, 'mode':'headless' if headless else 'macOS_native_window', 'exit_code':process.returncode, 'passed':passed,'total':total,'errors':errors,'status':'PASS' if ok else 'FAIL'})
        print(f'{name}: {passed}/{total} '+results[-1]['status'],flush=True)
        if not ok: print('\n'.join(text.splitlines()[-25:]),flush=True)
    after = sources()
    changed_existing = [p for p,h in (baseline or {}).items() if not (ROOT/p).exists() or hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h]
    ok = before == after and not changed_existing and all(r['status']=='PASS' for r in results)
    report = {'status':'PASS' if ok else 'FAIL','source_stable_during_run':before==after,'existing_runtime_check':'checked' if baseline is not None else 'not_requested','baseline_path':str(baseline_path) if baseline_path else None,'baseline_sha256':hashlib.sha256(baseline_path.read_bytes()).hexdigest() if baseline_path else None,'existing_runtime_changed':changed_existing,'source_sha256':after,'results':results,'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.','Characters are currently painted into the stage; animation evidence covers camera, cups, fluid and seed delivery.','Independent sample profile; the forest hub adds only a narrative crossing, no forest progress or reward integration.']}
    (OUTPUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    return 0 if ok else 1

if __name__ == '__main__': sys.exit(main())

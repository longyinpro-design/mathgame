#!/usr/bin/env python3
"""Exact-candidate MK rules and native-window checks with isolated test saves."""
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
SAMPLES = {
    'mk01': {'label':'MK01', 'headless':'mk01_test.gd', 'window':'mk01_playtest.gd',
             'launcher':'启动千灯集市样板.command',
             'output':'docs/playtest/market-mk01-reasoning',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'Characters are currently painted into the stage; animation evidence covers camera, cups, fluid and seed delivery.',
                       'Independent sample profile; the forest hub adds only a narrative crossing, no forest progress or reward integration.']},
    'mk02': {'label':'MK02', 'headless':'mk02_test.gd', 'window':'mk02_playtest.gd',
             'launcher':'启动千灯集市MK02样板.command',
             'output':'docs/playtest/market-mk02-exchange',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'Goods are static kit-v1 sprites; the exchange, carry and hand-over evidence covers counts, camera and drop targets only.',
                       'Independent sample profile; MK01 hands over a one-way note, no forest progress or reward integration.']},
}
SHARED = [ROOT/'project.godot', ROOT/'assets/runtime/cargo-props-v5.png', ROOT/'scripts/cargo/skin.gd',
    ROOT/'scripts/persistence/save_repository.gd', ROOT/'tests/forest/window_focus.gd']

def sources(sample):
    paths = list(SHARED) + [ROOT/'scripts/market'/(sample+'_rules.gd'), ROOT/'scripts/market'/(sample+'_world.gd'),
        ROOT/'scripts/market'/(sample+'_scene.gd'), ROOT/('game/market_'+sample+'.tscn'), ROOT/SAMPLES[sample]['launcher']]
    for folder in ['scripts/market', 'scripts/content', 'tests/market', 'tools/market',
                   'assets/runtime/market', 'assets/source/market', 'assets/runtime/forest/ui', 'assets/fonts']:
        paths += [p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ['.uid','.import']]
    missing = [str(p.relative_to(ROOT)) for p in paths if not p.is_file()]
    if missing: raise SystemExit('Missing audited sources: '+', '.join(missing))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}

def run(command, headless, output, name, label):
    # The native window must keep ticking while another application holds the foreground.
    env = dict(os.environ, NSAppSleepDisabled='YES')
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    try:
        text, _ = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        process.terminate()
        try: text, _ = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); text, _ = process.communicate()
        text += '\nERROR: bounded runner timed out and reaped child\n'
    (output/(Path(name).stem+'-stdout.log')).write_text(text)
    # Known offline headless macOS CA probe; all other engine errors fail.
    filtered = re.sub(r'ERROR: Condition "ret != noErr" is true\. Returning: ""\n\s+at: get_system_ca_certificates[^\n]*\n?', '', text) if headless else text
    errors = [line for line in filtered.splitlines() if 'ERROR:' in line or 'SCRIPT ERROR' in line]
    match = re.search(r'MARKET '+label+r' (?:RULES|WINDOW) (\d+)/(\d+) PASS', text)
    passed, total = map(int,match.groups()) if match else (0,0)
    if not match: errors.append('no MARKET '+label+' summary line: the run stopped before reporting')
    ok = process.returncode == 0 and total > 0 and passed == total and not errors
    return {'name':name, 'command':command, 'mode':'headless' if headless else 'macOS_native_window',
        'exit_code':process.returncode, 'passed':passed, 'total':total, 'errors':errors,
        'status':'PASS' if ok else 'FAIL'}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('samples', nargs='?', default='all', choices=list(SAMPLES)+['all'], help='Market sample to audit.')
    parser.add_argument('--baseline', type=Path, help='Optional original-runtime SHA256 map for this delivery audit.')
    args = parser.parse_args()
    baseline = None
    baseline_path = None
    if args.baseline:
        baseline_path = args.baseline if args.baseline.is_absolute() else ROOT/args.baseline
        if not baseline_path.is_file():
            parser.error('Explicit baseline file does not exist: '+str(baseline_path))
        baseline = json.loads(baseline_path.read_text())
    executable = shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
    selected = list(SAMPLES) if args.samples == 'all' else [args.samples]
    overall = []
    for sample in selected:
        spec = SAMPLES[sample]
        output = ROOT/spec['output']
        output.mkdir(parents=True, exist_ok=True)
        before = sources(sample)
        results = []
        for name, headless in [(spec['headless'],True), (spec['window'],False)]:
            command = [executable] + (['--headless'] if headless else []) + ['--path', str(ROOT), '--script', 'tests/market/'+name, '--log-file', str(output/(Path(name).stem+'.log'))]
            results.append(run(command, headless, output, name, spec['label']))
            print(f"{spec['label']} {name}: {results[-1]['passed']}/{results[-1]['total']} "+results[-1]['status'],flush=True)
            if results[-1]['status'] != 'PASS': print('\n'.join((output/(Path(name).stem+'-stdout.log')).read_text().splitlines()[-25:]),flush=True)
        after = sources(sample)
        changed_existing = [p for p,h in (baseline or {}).items() if not (ROOT/p).exists() or hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h]
        ok = before == after and not changed_existing and all(r['status']=='PASS' for r in results)
        report = {'status':'PASS' if ok else 'FAIL','sample':spec['label'],'source_stable_during_run':before==after,
            'existing_runtime_check':'checked' if baseline is not None else 'not_requested',
            'baseline_path':str(baseline_path) if baseline_path else None,
            'baseline_sha256':hashlib.sha256(baseline_path.read_bytes()).hexdigest() if baseline_path else None,
            'existing_runtime_changed':changed_existing,'source_sha256':after,'results':results,'limits':spec['limits']}
        (output/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        overall.append(ok)
    return 0 if all(overall) else 1

if __name__ == '__main__': sys.exit(main())

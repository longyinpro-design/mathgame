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
                 'tests/presentation/support_test.gd',
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
        # support 是共享承重检查：它覆盖工坊托盘到升降台的接触路径，必须随本关几何一起复跑。
        cases = [('rules', True, 'tests/workshop/gw01_test.gd'),
                 ('window', False, 'tests/workshop/gw01_playtest.gd'),
                 ('support', False, 'tests/presentation/support_test.gd')]
        for label, headless, script in cases:
            command = [GODOT, *(['--headless'] if headless else []), '--path', str(ROOT),
                       '--script', script, '--log-file', str(Path(temp) / (label + '.log'))]
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=180)
            (OUT / (label + '.log')).write_text(result.stdout)
            summary = re.search(r'(?:GW01 (?:RULES|WINDOW)|SUPPORT):?\s+(\d+) checks, (\d+) failures', result.stdout)
            # 共享 support 用例会加载森林发布场景，其 Audio 节点在引擎退出时仍持有音频流播放对象，
            # Godot 会在摘要行之后报 "resources still in use at exit"。那是关闭诊断，不是用例失败；
            # 除已知 CA 探针与这一条外，其余 ERROR 一律照旧拦截。
            errors = [line for line in result.stdout.splitlines() if 'ERROR:' in line
                      and 'Condition "ret != noErr"' not in line
                      and not re.match(r'ERROR: \d+ resources still in use at exit', line)]
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

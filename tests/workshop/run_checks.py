#!/usr/bin/env python3
"""齿轮工坊逐关检查：对源码与依赖的精确哈希跑规则与实窗测试；从不读写玩家存档。

用法：
    python3 tests/workshop/run_checks.py            # 跑全部已建关卡
    python3 tests/workshop/run_checks.py GW05 GW06  # 只跑指定的几关

每一关的候选文件是这一关自己的脚本、测试、场景、契约与启动脚本；
其余被它们引用到的脚本、字体、贴图与工程设置都记在依赖里。任何一边在检查期间被改动，
脚本都会报错退出，避免回执对不上实际代码。
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get('GODOT', '/Applications/Godot.app/Contents/MacOS/Godot')
LEVELS = ['GW01', 'GW02', 'GW03', 'GW04', 'GW05', 'GW06', 'GW07']
SCANNED = {'.gd', '.tscn', '.tres', '.json'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def level_slug(level):
    return level.lower()


def candidate_files(level):
    slug = level_slug(level)
    files = set()
    for suffix in ('rules', 'world', 'scene'):
        path = ROOT / f'scripts/workshop/{slug}_{suffix}.gd'
        if path.is_file():
            files.add(path)
    for suffix in ('test', 'playtest'):
        path = ROOT / f'tests/workshop/{slug}_{suffix}.gd'
        if path.is_file():
            files.add(path)
    for relative in (f'game/workshop_{slug}.tscn',
                     f'docs/production/workshop_{slug}_sample.md',
                     f'启动齿轮工坊{level}样板.command'):
        path = ROOT / relative
        if path.is_file():
            files.add(path)
    return files


def inputs(level):
    files = candidate_files(level)
    deps = {'project.godot'}
    # 顺着 res:// 引用把资源闭包扫出来：脚本、场景、字体、贴图与清单都算依赖。
    scan = [p for p in files if p.suffix in SCANNED]
    seen = set()
    while scan:
        path = scan.pop()
        if path in seen:
            continue
        seen.add(path)
        if path.suffix not in SCANNED:
            continue
        for match in re.findall(r'res://([^"\s\)]+)', path.read_text()):
            target = ROOT / match
            if target.is_file():
                deps.add(match)
                scan.append(target)
    return {'candidate': {str(p.relative_to(ROOT)): digest(p) for p in sorted(files)},
            'dependencies': {p: digest(ROOT / p) for p in sorted(deps) if ROOT / p not in files}}


def check_level(level):
    slug = level_slug(level)
    out = ROOT / f'docs/playtest/workshop-{slug}'
    out.mkdir(parents=True, exist_ok=True)
    candidate = inputs(level)
    runs = []
    with tempfile.TemporaryDirectory(prefix=f'{slug}-checks-') as temp:
        for label, headless, script in ((f'{slug}_test.gd', True, f'{slug}_test.gd'),
                                        (f'{slug}_playtest.gd', False, f'{slug}_playtest.gd')):
            script_path = ROOT / 'tests/workshop' / script
            if not script_path.is_file():
                continue
            command = [GODOT, *(['--headless'] if headless else []), '--path', str(ROOT),
                       '--script', 'tests/workshop/' + script, '--log-file', str(Path(temp) / (script + '.log'))]
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=600)
            kind = 'RULES' if headless else 'WINDOW'
            log_name = ('rules' if headless else 'window') + '.log'
            (out / log_name).write_text(result.stdout)
            summary = re.search(rf'{level} {kind}: (\d+) checks, (\d+) failures', result.stdout)
            # 沙箱化的无头模式只可能出现 macOS 证书探测这一条已知噪音。
            errors = [line for line in result.stdout.splitlines() if 'ERROR:' in line
                      and 'Condition "ret != noErr"' not in line
                      and 'ERROR: GW' not in line]
            passed = result.returncode == 0 and summary and int(summary[2]) == 0 and not errors
            runs.append({'name': 'rules' if headless else 'window', 'command': command,
                         'returncode': result.returncode, 'checks': int(summary[1]) if summary else 0,
                         'passed': bool(passed), 'output_sha256': digest(out / log_name), 'errors': errors})
            print(f'{level} {runs[-1]["name"]:<6}', 'PASS' if passed else 'FAIL', runs[-1]['checks'], flush=True)
    if inputs(level) != candidate:
        raise RuntimeError(f'{level}: candidate or dependency changed during checks')
    (out / 'candidate.json').write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + '\n')
    receipt = {'level': level,
               'candidate_sha256': digest(out / 'candidate.json'),
               'godot': subprocess.check_output([GODOT, '--version'], text=True).strip(),
               'runs': runs,
               'screenshots': {p.name: digest(p) for p in sorted(out.glob('*.png'))},
               'limitations': ['macOS desktop mouse and keyboard at 1280x720 and 960x540 only',
                               f'Independent {level} profile, no cross-island journey/unlock/reward integration',
                               'No touch-device, child comprehension or learning outcome acceptance']}
    (out / 'verification.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    return all(run['passed'] for run in runs)


def main():
    wanted = [a for a in sys.argv[1:] if a in LEVELS] or LEVELS
    results = {level: check_level(level) for level in wanted}
    failed = [level for level, ok in results.items() if not ok]
    print('failed:', failed if failed else 'none', flush=True)
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()

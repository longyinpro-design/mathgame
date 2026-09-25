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
LEVELS = ['GW01', 'GW02', 'GW03', 'GW04', 'GW05', 'GW06', 'GW07', 'GW08', 'GW09', 'GW10', 'GW11', 'GW12']
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
    if level == 'GW01':
        # support 是共享承重检查：覆盖工坊托盘到升降台的接触路径，随本关几何一起复跑。
        files.add(ROOT / 'tests/presentation/support_test.gd')
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
    cases = [(True, f'tests/workshop/{slug}_test.gd', 'rules'),
             (False, f'tests/workshop/{slug}_playtest.gd', 'window')]
    if level == 'GW01':
        # support 是共享承重检查：它覆盖工坊托盘到升降台的接触路径，必须随本关几何一起复跑。
        cases.append((False, 'tests/presentation/support_test.gd', 'support'))
    with tempfile.TemporaryDirectory(prefix=f'{slug}-checks-') as temp:
        for headless, script, log_name in cases:
            if not (ROOT / script).is_file():
                continue
            command = [GODOT, *(['--headless'] if headless else []), '--path', str(ROOT),
                       '--script', script, '--log-file', str(Path(temp) / (log_name + '.log'))]
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=600)
            (out / (log_name + '.log')).write_text(result.stdout)
            if log_name == 'support':
                summary = re.search(r'SUPPORT\s+(\d+) checks, (\d+) failures', result.stdout)
            else:
                kind = 'RULES' if headless else 'WINDOW'
                summary = re.search(rf'{level} {kind}: (\d+) checks, (\d+) failures', result.stdout)
            # 沙箱化的无头模式只可能出现 macOS 证书探测这一条已知噪音；共享 support 用例会加载
            # 森林发布场景，其 Audio 节点在引擎退出时仍持有音频流播放对象，Godot 会在摘要行之后
            # 报 "resources still in use at exit"——那是关闭诊断，不是用例失败。
            errors = [line for line in result.stdout.splitlines() if 'ERROR:' in line
                      and 'Condition "ret != noErr"' not in line
                      and 'ERROR: GW' not in line
                      and not re.match(r'ERROR: \d+ resources still in use at exit', line)]
            passed = result.returncode == 0 and summary and int(summary[2]) == 0 and not errors
            runs.append({'name': log_name, 'command': command,
                         'returncode': result.returncode, 'checks': int(summary[1]) if summary else 0,
                         'passed': bool(passed), 'output_sha256': digest(out / (log_name + '.log')), 'errors': errors})
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

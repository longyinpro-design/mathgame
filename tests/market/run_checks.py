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
    'mk03': {'label':'MK03', 'headless':'mk03_test.gd', 'window':'mk03_playtest.gd',
             'launcher':'启动千灯集市MK03样板.command',
             'output':'docs/playtest/market-mk03-weight',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The scale stays braked while tags are hung; both readings appear only after 挂签复秤, so the counter never scores the player.',
                       'Independent sample profile; the chart reads this station\u2019s own save, no forest progress or reward integration.']},
    'mk04': {'label':'MK04', 'headless':'mk04_test.gd', 'window':'mk04_playtest.gd',
             'launcher':'启动千灯集市MK04样板.command',
             'output':'docs/playtest/market-mk04-receipt',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'Seals are engine-drawn placeholders (manifest has no stamp part) and 衡伯 appears only through dialogue, so the recantation beat has no readable face.',
                       'Independent sample profile; no forest progress or reward integration.']},
    'mk05': {'label':'MK05', 'headless':'mk05_test.gd', 'window':'mk05_playtest.gd',
             'launcher':'启动千灯集市MK05样板.command',
             'output':'docs/playtest/market-mk05-labels',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'Rain-blurred destinations are painted ink, not readable text, so a misread tag is only caught by the player.',
                       'The receipt is an engine-drawn panel and 扣扣 keeps two discrete poses; kit-v1 ships no receipt part.']},
    'mk06': {'label':'MK06', 'headless':'mk06_test.gd', 'window':'mk06_playtest.gd',
             'output':'docs/playtest/market-mk06-packs',
             'launcher':'启动千灯集市MK06样板.command',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'Only the first five-lantern string hangs and the stall stacks never deplete; tickets reuse receipt_blank until batch two ships a part.',
                       'The 19 tickets belong to this level only; no camp resource or global shop economy.']},
    'mk07': {'label':'MK07', 'headless':'mk07_test.gd', 'window':'mk07_playtest.gd',
             'launcher':'启动千灯集市MK07样板.command',
             'output':'docs/playtest/market-mk07-goods',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The street scene has no resident portrait part, so the four households read as plaque + landing socket + their usable good icon.',
                       'plan is a 4-slot one-to-one mapping; more households or multi-item demands need COUNT/ACCEPT/SOLUTION and a save schema bump.']},
    'mk08': {'label':'MK08', 'headless':'mk08_test.gd', 'window':'mk08_playtest.gd',
             'launcher':'启动千灯集市MK08样板.command',
             'output':'docs/playtest/market-mk08-oil',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'Ticket ink is engine-drawn 12x12 blocks and the summary board is a draw_rect wood band; kit-v1 ships no green crate, so 绿单 reuses parcel_medium.',
                       '衡伯 and the dockhands have no sprite parts — they stay in dialogue and on the stall boards.']},
    'mk09': {'label':'MK09', 'headless':'mk09_test.gd', 'window':'mk09_playtest.gd',
             'launcher':'启动千灯集市MK09样板.command',
             'output':'docs/playtest/market-mk09-cyclic-exchange',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The exchange lines are engine-drawn polylines on the street — kit-v1 ships no rope part, and the five stallkeepers stay in dialogue and on their plaques.',
                       'Lines are only a proposal until 提交验收 books them; the ring belongs to this level, no cross-stall balance or camp resource.']},
    'mk10': {'label':'MK10', 'headless':'mk10_test.gd', 'window':'mk10_playtest.gd',
             'launcher':'启动千灯集市MK10样板.command',
             'output':'docs/playtest/market-mk10-fare',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The six fare tiles, ten tickets and both receipts reuse receipt_blank, and the ships only translate and scale — manifest promises no rigging, so no sail turn is claimed.',
                       '折羽 reuses the forest companion sheet (idle/talk, two discrete frames) instead of a market cut, and the order branch is fixed by an in-process counter, not a weighted roll.']},
    'mk12': {'label':'MK12', 'headless':'mk12_test.gd', 'window':'mk12_playtest.gd',
             'launcher':'启动千灯集市MK12样板.command',
             'output':'docs/playtest/market-mk12-oil',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'kit-v1 has no storehouse door and no 衡伯 part, so 「打开总货栈」 lives in the dialogue and the receipt line; 扣扣 keeps two discrete poses.',
                       'The lantern string is one five-lamp part per place and LANTERN_GLASS is measured off the PNG (copied from mk06_world.gd), not a per-lamp count.']},
    'mk14': {'label':'MK14', 'headless':'mk14_test.gd', 'window':'mk14_playtest.gd',
             'launcher':'启动千灯集市MK14样板.command',
             'output':'docs/playtest/market-mk14-scale',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The scale reuses MK11\u2019s stand/beam/pan sprites and turns as one piece — no swing skeleton, and the stallkeeper stays on her plaque.',
                       'Only the two orders on the street (5 and 8) are played: the level never asks for 1..13 one by one and unlocks no new weight.']},
    'mk13': {'label':'MK13', 'headless':'mk13_test.gd', 'window':'mk13_playtest.gd',
             'launcher':'启动千灯集市MK13样板.command',
             'output':'docs/playtest/market-mk13-scarf',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'Both package sizes are one cloth_bolt sprite scaled to 5/3 段; the mended hem is mapped from the character source pixels, not a sticker.',
                       'Pick-up and return run on the world clock (0.3s) instead of the host landing lock, so the beat is shorter than MK02/MK03.']},
    'mk15': {'label':'MK15', 'headless':'mk15_test.gd', 'window':'mk15_playtest.gd',
             'launcher':'启动千灯集市MK15样板.command',
             'output':'docs/playtest/market-mk15-copper-nut',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The three contracts and the 36-slot gauge are engine-drawn plaques; kit-v1 has no contract board or exchange-ring part.',
                       'The wind-chime that replaces the signboard reuses brass_bell; 衡伯 never appears on screen.']},
    'mk16': {'label':'MK16', 'headless':'mk16_test.gd', 'window':'mk16_playtest.gd',
             'launcher':'启动千灯集市MK16样板.command',
             'output':'docs/playtest/market-mk16-gift',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The white cup is the MK01 mechanism-source sprite, not a new cut; kit-v1 ships no cup or wrapping part.',
                       'Both branches earn the identical main-line reward — the choice only changes the reply text and the charm tied outside the parcel.']},
    'mk11': {'label':'MK11', 'headless':'mk11_test.gd', 'window':'mk11_playtest.gd',
             'launcher':'启动千灯集市MK11样板.command',
             'output':'docs/playtest/market-mk11-scale',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The brass scale has no swing skeleton — the beam rotates as one sprite and the pans only translate; 陶姨 and 衡伯 have no character parts.',
                       'No drag-and-drop on purpose: one click walks a weight one cell, which is the teaching device of this level.']},
    'mk17': {'label':'MK17', 'headless':'mk17_test.gd', 'window':'mk17_playtest.gd',
             'launcher':'启动千灯集市MK17样板.command',
             'output':'docs/playtest/market-mk17-inspection',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The heron is three batch-two sprites moved by transforms (patrol / flag / platform); there is no wing or chain skeleton and 小岚 has no part.',
                       'The second station\u2019s flag is fixed when the level is created and survives a reload — the level never re-rolls it.']},
    'mk18': {'label':'MK18', 'headless':'mk18_test.gd', 'window':'mk18_playtest.gd',
             'launcher':'启动千灯集市MK18样板.command',
             'output':'docs/playtest/market-mk18-lantern',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       '万签 and the lantern ship are batch-two sprites without a walk cycle; the three stall signs and the empty letter slots are engine-drawn.',
                       'Which seal is valid is written before the letters are read, and one save only ever plays that branch.']},
    'hub': {'label':'HUB', 'headless':'hub_test.gd', 'window':'hub_playtest.gd',
             'launcher':'启动千灯集市岛.command',
             'own':['chapter_catalog.gd','chapter_progress.gd','kit_world.gd','level_host.gd','hub_world.gd','market_hub.gd','market_bridge.gd'],
             'scene':'game/market_island.tscn',
             'output':'docs/playtest/market-chapter-hub',
             'limits':['Native macOS 1280x720 and 960x540 only; no child comprehension or touch-device acceptance.',
                       'The chart reads each station\u2019s own save as completion evidence; it never writes a station profile.',
                       'All 18 stations now ship their own scene and save; the 尚未制作 branch stays only as a guard the chart can no longer reach.']},
}
SHARED = [ROOT/'project.godot', ROOT/'assets/runtime/cargo-props-v5.png', ROOT/'scripts/cargo/skin.gd',
    ROOT/'scripts/persistence/save_repository.gd', ROOT/'tests/forest/window_focus.gd']

def sources(sample):
    spec = SAMPLES[sample]
    own = spec.get('own', [sample+'_rules.gd', sample+'_world.gd', sample+'_scene.gd'])
    paths = list(SHARED) + [ROOT/'scripts/market'/name for name in own] + [ROOT/spec.get('scene', 'game/market_'+sample+'.tscn'), ROOT/spec['launcher']]
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

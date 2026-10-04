#!/usr/bin/env python3
"""Run the six-island acceptance layers. --native additionally needs a desktop.
Use --legacy-native to regenerate the36 original-island window checks; that
produces a large screenshot collection and is intentionally a separate option.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/playtest/archipelago'

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--native',action='store_true')
 parser.add_argument('--legacy-native',action='store_true')
 args=parser.parse_args()
 godot=os.environ.get('GODOT') or shutil.which('godot') or shutil.which('godot4')
 if not godot: parser.error('Set GODOT to the installed engine executable')
 OUT.mkdir(parents=True,exist_ok=True)
 scripts=[('session','tests/archipelago/session_test.gd',True,[]),
          ('restore-ui','tests/archipelago/restore_ui_test.gd',True,[]),
          ('end-to-end','tests/archipelago/end_to_end.gd',True,[]),
          ('geometry-rules','tests/geometry/test_rules.gd',True,[]),
          ('fractions-rules','tests/fractions/rules_test.gd',True,[]),
          ('observatory-rules','tests/observatory/test_rules.gd',True,[]),
          ('observatory-boundaries','tests/observatory/test_adversarial.gd',True,[]),
          ('observatory-voyage','tests/observatory/test_voyage.gd',True,[])]
 if args.native:
  scripts += [('geometry-native','tests/geometry/test_ui.gd',False,[]),
              ('fractions-native1280','tests/fractions/ui_test.gd',False,[]),
              ('fractions-native960','tests/fractions/ui_test.gd',False,['--','small']),
              ('observatory-native','tests/observatory/test_ui.gd',False,[]),
              ('campaign-native','tests/archipelago/ui_test.gd',False,[])]
 else: scripts.append(('campaign-headless','tests/archipelago/ui_test.gd',True,[]))
 results=[]
 with tempfile.TemporaryDirectory(prefix='six-island-checks-') as temporary:
  env=os.environ.copy()
  for label in ('CACHE','CONFIG','DATA'):
   path=Path(temporary)/label;path.mkdir();env['XDG_'+label+'_HOME']=str(path)
  for name,script,headless,extra in scripts:
   command=[godot,'--audio-driver','Dummy',*(['--headless'] if headless else []),'--path',str(ROOT),'--script',script,*extra]
   result=subprocess.run(command,cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
   (OUT/(name+'.log')).write_text(result.stdout)
   errors=[line for line in result.stdout.splitlines() if 'ERROR:' in line]
   record={'name':name,'returncode':result.returncode,'passed':result.returncode==0 and not errors,'errors':errors}
   results.append(record);print(name,'PASS' if record['passed'] else 'FAIL',flush=True)
   (OUT/'latest-checks.json').write_text(json.dumps(results,indent=2)+'\n')
 if args.legacy_native:
  subprocess.run(['python3','tests/archipelago/prepare_legacy_checks.py'],cwd=ROOT,check=True)
  subprocess.run(['python3','tests/archipelago/run_legacy_checks.py'],cwd=ROOT,check=True)
 raise SystemExit(0 if all(r['passed'] for r in results) else 1)

if __name__=='__main__': main()

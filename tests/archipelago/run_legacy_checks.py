from pathlib import Path
import os,subprocess,re,json,tempfile,hashlib,sys
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/playtest/archipelago/legacy'
runtime=[p for folder in ['scripts','game','tests/market','tests/workshop'] for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ['.gd','.tscn','.json']]
fingerprint=hashlib.sha256(b''.join(p.read_bytes() for p in sorted(runtime))).hexdigest()
results=json.loads((OUT/"verification.json").read_text()) if '--resume' in sys.argv and (OUT/"verification.json").exists() else []
with tempfile.TemporaryDirectory(prefix='archipelago-legacy-') as temp:
 env=os.environ.copy()
 for key in ['DATA','CACHE','CONFIG']:
  p=Path(temp)/key;p.mkdir();env['XDG_'+key+'_HOME']=str(p)
 for script in sorted((ROOT/'tests/archipelago/generated').glob('*_playtest.gd')):
  ident=script.name[:4].upper()
  if any(r['level']==ident and r['returncode']==0 and not r['errors'] and r['proof'] and r.get('source_sha256')==fingerprint for r in results):
   print('RETAIN VERIFIED '+ident,flush=True);continue
  p=subprocess.run(['godot','--audio-driver','Dummy','--path',str(ROOT),'--script',str(script)],cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
  (OUT/(ident+'.log')).write_text(p.stdout)
  errors=[l for l in p.stdout.splitlines() if 'ERROR:' in l]
  record=dict(level=ident,source_sha256=fingerprint,returncode=p.returncode,errors=errors,proof=(ROOT/f'docs/playtest/archipelago/proofs/{ident}.json').exists())
  results=[r for r in results if r['level']!=ident];results.append(record);print(json.dumps(record),flush=True)
  (OUT/'verification.json').write_text(json.dumps(results,indent=2)+'\n')
print('LEGACY NATIVE DONE', len(results),flush=True)

raise SystemExit(0 if len(results)==36 and all(r['returncode']==0 and not r['errors'] and r['proof'] for r in results) else 1)

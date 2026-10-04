import json
from oracle import ROOT,covers,gardens,toggles
out={};branches=[]
for d in json.loads((ROOT/'scripts/geometry/levels.json').read_text()):
 p=d['params'];kind=d['mechanism'];states=[]
 if kind=='mosaic':
  for poses in covers(p.get('cut_shapes',p['shapes']),p['target']):states.append(dict(pieces=poses,cells=[],cut='cut_shapes' in p,proofs=[]))
 elif kind=='garden':
  for cells in gardens(p,p['perimeter'],p.get('blocked',[])):states.append(dict(pieces=[],cells=cells,cut=False,proofs=[]))
 elif kind=='architect_boss':
  seen=set()
  for cells in gardens(p,14):
   rock=next((v for v in [(0,0),(3,0),(0,3),(3,3)] if v not in cells),(1,1))
   if rock in seen:continue
   seen.add(rock)
   for answer in gardens(p,10,[rock]):states.append(dict(pieces=[],cells=answer,cut=False,proofs=[cells]))
   branches.append(toggles(cells)+[dict(type='seal')]+toggles(gardens(p,10,[rock])[0]))
 if states:out[d['id']]=states
(ROOT/'tests/geometry/alternatives.json').write_text(json.dumps(dict(states=out,branches=branches),separators=(',',':')))
print(sum(map(len,out.values())),'alternate solved states;',len(branches),'boss branches')

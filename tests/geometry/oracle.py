"""Independent exhaustive cell-set oracle; emits executable action witnesses, never runtime answers."""
import json,itertools,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
def transforms(shape):
 out={}
 for f in range(2):
  for r in range(4):
   pts=[]
   for x,y in shape:
    if f:x=-x
    for _ in range(r):x,y=-y,x
    pts.append((x,y))
   mx=min(x for x,y in pts);my=min(y for x,y in pts)
   norm=tuple(sorted((x-mx,y-my) for x,y in pts))
   out.setdefault(norm,(r,f))
 return out

def covers(shapes,target):
 target=set(map(tuple,target)); options=[]
 for shape in shapes:
  poss=[]
  for norm,(r,f) in transforms(shape).items():
   for x in range(6):
    for y in range(5):
     cells={(a+x,b+y) for a,b in norm}
     if cells<=target:poss.append((cells,dict(x=x,y=y,r=r,f=f)))
  options.append(poss)
 def rec(i,used,poses):
  if i==len(shapes):
   if used==target:yield poses
   return
  for cells,pose in options[i]:
   if not used&cells:yield from rec(i+1,used|cells,poses+[pose])
 return list(rec(0,set(),[]))
def perimeter(c):return sum((x+dx,y+dy) not in c for x,y in c for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])
def components(c):
 todo=set(c);n=0
 while todo:
  n+=1;q=[todo.pop()]
  while q:
   x,y=q.pop()
   for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
    v=x+dx,y+dy
    if v in todo:todo.remove(v);q.append(v)
 return n
def gardens(p,edge,blocked=()):
 grid=[(x,y) for x in range(p['w']) for y in range(p['h']) if (x,y) not in set(map(tuple,blocked))]
 return [list(c) for c in itertools.combinations(grid,p['area']) if perimeter(set(c))==edge and components(c)==p.get('components',1) and set(map(tuple,p.get('required',[])))<=set(c)]
def pose_actions(poses):
 a=[]
 for i,q in enumerate(poses):
  a += [dict(type='flip',piece=i)]*q['f']+[dict(type='rotate',piece=i)]*q['r']+[dict(type='place',piece=i,x=q['x'],y=q['y'])]
 return a
def toggles(cells):return [dict(type='toggle',x=x,y=y) for x,y in cells]
def main():
 report={};witnesses={}
 for d in json.loads((ROOT/'scripts/geometry/levels.json').read_text()):
  p=d['params'];kind=d['mechanism'];a=[]
  if kind=='mosaic':
   shapes=p.get('cut_shapes',p['shapes']);sol=covers(shapes,p['target']);assert sol,d['id']
   if 'cut_shapes' in p:assert sum(map(len,shapes))==sum(map(len,p['shapes']));a=[dict(type='cut')]
   a+=pose_actions(sol[0]);report[d['id']]={'solutions':len(sol)}
  elif kind=='symmetry':
   c=set(map(tuple,p['seeds']));old=None
   while old!=c:
    old=set(c)
    for x,y in old:
     if p['mode'] in ['vertical','both']:c.add((p['w']-1-x,y))
     if p['mode']=='both':c.add((x,p['h']-1-y))
     if p['mode']=='diagonal':c.add((y,x))
     if p['mode']=='half':c.add((p['w']-1-x,p['h']-1-y))
   assert len(c)==p['area'],(d['id'],c)
   a=toggles(c-set(map(tuple,p['seeds'])));report[d['id']]={'closure_area':len(c)}
  elif kind=='garden':
   sol=gardens(p,p['perimeter'],p.get('blocked',[]));assert sol,d['id'];a=toggles(sol[0]);report[d['id']]={'solutions':len(sol)}
   if d['id']=='GV07':
    minimum=min(perimeter(set(c)) for c in itertools.combinations([(x,y) for x in range(4) for y in range(4)],6));assert minimum==10;report[d['id']]['global_minimum']=minimum
  elif kind=='mirror_boss':
   counts=[]
   for target in p['targets']:
    sol=covers(p['shapes'],target);assert sol;a+=pose_actions(sol[0])+[dict(type='seal')];counts.append(len(sol))
   report[d['id']]={'shield_solutions':counts}
  else:
   sol=gardens(p,14);branches={}
   for c in sol:
    rock=next((v for v in [(0,0),(3,0),(0,3),(3,3)] if v not in c),(1,1));branches.setdefault(rock,c)
   for rock,c in branches.items():
    replies=gardens(p,10,[rock]);assert replies
   c=sol[0];rock=next((v for v in [(0,0),(3,0),(0,3),(3,3)] if v not in c),(1,1));a=toggles(c)+[dict(type='seal')]+toggles(gardens(p,10,[rock])[0]);report[d['id']]={'foundation_solutions':len(sol),'all_derived_rock_branches':[list(x) for x in branches]}
  witnesses[d['id']]=a
 (ROOT/'tests/geometry/witnesses.json').write_text(json.dumps(witnesses,indent=2))
 (ROOT/'docs/playtest/geometry/oracle_results.json').write_text(json.dumps(report,indent=2))
 print(json.dumps(report,indent=2))
if __name__=='__main__':main()

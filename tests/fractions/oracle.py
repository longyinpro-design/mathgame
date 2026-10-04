"""Independent finite-state water/partition oracle. Runtime files contain no solutions."""
from itertools import product
from collections import deque
import json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
D=json.loads((ROOT/'scripts/fractions/levels.json').read_text())
def mosaic(d):
 p=d['params']; start=tuple((u,a,-1) for u,a in p['tiles']); q=deque([(start,[])]); seen={start}
 while q:
  s,path=q.popleft()
  if all(o>=0 for _,_,o in s):
   good=True
   for j,(unit,amount) in enumerate(p['targets']):
    pieces=[(u,a) for u,a,o in s if o==j]
    good &= sum(a for _,a in pieces)==amount and all(unit<0 or u==unit for u,_ in pieces) and (p['counts'][j]<0 or len(pieces)==p['counts'][j])
   if good:return path
  # Assign by exhaustive product only once partition count feasible; no need enumerate placement transitions.
  if len(s)<=12:
   for owners in product(range(len(p['targets'])),repeat=len(s)):
    sums=[0]*len(p['targets']); counts=[0]*len(s); valid=True
    for (u,a,_),o in zip(s,owners):
     if p['targets'][o][0] not in [-1,u]: valid=False;break
     sums[o]+=a
    if not valid or sums!=[x[1] for x in p['targets']]:continue
    if any(c>=0 and owners.count(j)!=c for j,c in enumerate(p['counts'])):continue
    return path+[dict(type='place',tile=i,owner=o) for i,o in enumerate(owners)]
  for i,(u,a,o) in enumerate(s):
   for n in p['splits']:
    if a%n or len(s)+n-1>12:continue
    t=s[:i]+s[i+1:]+((u,a//n,o),)*n
    if t not in seen:seen.add(t);q.append((t,path+[dict(type='split',tile=i,parts=n)]))
 raise AssertionError(d['id'])
def reverse(d):
 from fractions import Fraction
 p=d['params']; n=len(p['initial']); total=sum(p['initial'])
 def compositions(t,k):
  if k==1:yield (t,);return
  for a in range(t+1):
   for tail in compositions(t-a,k-1):yield (a,)+tail
 found=[]
 for allocation in compositions(total,n):
  w=list(allocation)
  for x,y,num,den in p['gifts']:
   amt=Fraction(w[x]*num,den)
   if amt.denominator!=1: break
   w[x]-=int(amt);w[y]+=int(amt)
  else:
   if w==p['goal']: found.append(allocation)
 assert found,d['id']
 w=p['initial'][:]; path=[]
 for j in range(n):
  while w[j]>found[0][j]:
   k=next(k for k in range(n) if w[k]<found[0][k]);w[j]-=1;w[k]+=1;path.append(dict(type='shift',source=j,target=k))
 return path+[dict(type='release')],len(found)
def flow(d):
 p=d['params']; goals=p.get('goals',[p['goal']]); start=(tuple(p['initial']),0); q=deque([(start,[],0)]); seen={start}
 while q:
  (w,stage),path,depth=q.popleft()
  if list(w)==goals[stage]:
   if stage==len(goals)-1:return path,depth,len(seen)
   nxt=(w,stage+1)
   if nxt not in seen:seen.add(nxt);q.appendleft((nxt,path+[dict(type='checkpoint')],depth))
  if depth>=p['max_pulses']:continue
  block=p.get('blocked',[[]])[stage if 'blocked'in p else 0]
  for bits in product([0,1],repeat=len(p['edges'])):
   if not any(bits) or any(bits[e] for e in block):continue
   delta=[0]*len(w);out=[0]*len(w)
   for bit,(x,y,amount) in zip(bits,p['edges']):
    if bit:out[x]+=amount;delta[x]-=amount;delta[y]+=amount
   if any(o>v for o,v in zip(out,w)):continue
   z=tuple(v+ch for v,ch in zip(w,delta))
   if any(v>cap for v,cap in zip(z,p['capacity'])):continue
   nxt=(z,stage)
   if nxt in seen:continue
   seen.add(nxt)
   actions=[dict(type='gate',edge=i) for i,b in enumerate(bits) if b]
   actions += [dict(type='pulse')]
   actions += [dict(type='gate',edge=i) for i,b in enumerate(bits) if b]
   q.append((nxt,path+actions,depth+1))
 raise AssertionError(d['id'])
if __name__=='__main__':
 solutions={};report=[]
 for id,d in sorted(D.items()):
  if d['mechanism']=='mosaic':path=mosaic(d);report.append(f'{id}: exact partition feasible ({len(path)} actions)')
  elif d['mechanism']=='reverse':path,count=reverse(d);report.append(f'{id}: {count} legal initial allocations, exact rational gifts')
  else:path,depth,count=flow(d);report.append(f'{id}: minimum {depth} pulses, {count} reservoir states explored')
  assert len(path)<=120
  solutions[id]=path
 (ROOT/'tests/fractions/solutions.json').write_text(json.dumps(solutions,ensure_ascii=False,indent=2))
 (ROOT/'docs/playtest/fractions/oracle_results.txt').write_text('\n'.join(report)+'\n')
 print('\n'.join(report))

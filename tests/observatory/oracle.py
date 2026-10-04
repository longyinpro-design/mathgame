"""Independent exhaustive integer oracle. Produces test-only action witnesses.
No runtime rule imports and no answers embedded in runtime definitions.
"""
import itertools as it,json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
levels=json.loads((ROOT/'scripts/observatory/levels.json').read_text())
fixtures={}; summaries=[]
def subsets(n):
    for bits in range(1<<n): yield [i for i in range(n) if bits>>i&1]
def distances(p,es,weighted=True):
    n=len(p['nodes']); d=[[0 if i==j else 999 for j in range(n)] for i in range(n)]
    for idx in es:
        a,b,c,t=p['edges'][idx]; d[a][b]=d[b][a]=t if weighted else 1
    for k in range(n):
        for i in range(n):
            for j in range(n): d[i][j]=min(d[i][j],d[i][k]+d[k][j])
    return d
def cost(p,es):return sum(p['edges'][i][2] for i in es)
def connected(p,es): return max(distances(p,es)[0])<999
def robust(p,es): return connected(p,es) and all(connected(p,[x for x in es if x!=e]) for e in es)
for d in levels:
    p=d['params']; f=d['mechanism']; actions=[]; alternates=[]; count=0; networks=[]
    if f=='scale':
        for i,point in enumerate(p['source']):
            options=[q for q in it.product(range(9),repeat=2) if all((q[a]-p['origin'][a])*p['den']==(point[a]-p['source_origin'][a])*p['num'] for a in [0,1])]
            assert len(options)==1
            x,y=options[0]; actions.append(dict(type='place',piece=i,x=x,y=y))
        count=1
    elif f=='shutters':
        options=[]
        for w,size in enumerate(p['sizes']):
            whole=size-(len(p['blocked'][w]) if p['basis'][w]=='remaining' else 0)
            k=whole*p['targets'][w]//100; assert k*100==whole*p['targets'][w]
            legal=[]
            for a in it.combinations([v for v in range(size) if v not in p['blocked'][w]],k):
                if p['contiguous'] and max(a)-min(a)+1!=k: continue
                legal.append(a)
            options.append(legal)
        count=1
        for opts in options:count*=len(opts)
        all_opts=list(it.islice(it.product(*options),2))
        if p['min_changes']>=0:
            all_opts=list(it.product(*options))
            costs=[sum(len(set(row)^set(p['initial'][i])) for i,row in enumerate(rows)) for rows in all_opts]
            optimum=min(costs)
            assert optimum==p['min_changes']; all_opts=[x for x,c in zip(all_opts,costs) if c==optimum]
            count=len(all_opts)
        for rows in all_opts[:2]:
            seq=[]
            for w,row in enumerate(rows):
                for cell in sorted(set(row)^set(p['initial'][w])): seq.append(dict(type='toggle',window=w,cell=cell))
            alternates.append(seq)
        actions=alternates[0]
    elif f=='routes':
        routes=[]
        lengths=[p['length']] if p['length'] else range(1,len(p['nodes'])+1)
        for length in lengths:
            for route in it.permutations(range(len(p['nodes'])),length):
                if route[0] not in p['starts'] or route[-1] not in p['ends']:continue
                if any([a,b] not in p['edges'] for a,b in zip(route,route[1:])): continue
                if not p['length'] and any(v in p['ends'] for v in route[:-1]):continue
                if not set(p['required'])<=set(route):continue
                routes.append(route)
        assert routes
        for route in routes:
            actions.extend(dict(type='append',node=v) for v in route); actions.append(dict(type='record'))
        count=len(routes)
    elif f=='schedule':
        choices=[]
        for j in p['jobs']:
            choices.append([(t,start) for t in range(p['tracks']) for start in range(j['release'],j['deadline']-j['durations'][t]+1)])
        legal=[]
        for slots in it.product(*choices):
            good=True
            for i,(track,start) in enumerate(slots):
                for k,(tr,st) in enumerate(slots[:i]):
                    if track==tr and start<st+p['jobs'][k]['durations'][tr] and st<start+p['jobs'][i]['durations'][track]:good=False
                    if track!=tr and p['cross'] and start+p['cross'][track]==st+p['cross'][tr]:good=False
            if good:
                c=sum(j['costs'][t] for j,(t,s) in zip(p['jobs'],slots)); end=max(s+j['durations'][t] for j,(t,s) in zip(p['jobs'],slots));legal.append((c,end,slots))
        assert legal
        if p['max_cost']>=0: assert min(c for c,e,s in legal)==p['max_cost']
        if p['max_end']>=0: assert min(e for c,e,s in legal)==p['max_end']
        legal=[x for x in legal if (p['max_cost']<0 or x[0]<=p['max_cost']) and (p['max_end']<0 or x[1]<=p['max_end'])]
        count=len(legal)
        for c,e,slots in legal[:2]: alternates.append([dict(type='schedule',job=i,track=t,start=s) for i,(t,s) in enumerate(slots)])
        actions=alternates[0]
    elif f=='storm':
        for es in subsets(len(p['edges'])):
            if cost(p,es)>p['budget'] or not robust(p,es):continue
            remaining=[e for e in es if e!=min(es)]; repairs=[]
            for candidate in subsets(len(p['edges'])):
                if min(es) in candidate or cost(p,candidate)>p['budget'] or len(set(candidate)-set(es))>p['repair_limit']:continue
                if max(map(max,distances(p,candidate,False)))<=2:repairs.append(candidate)
            assert repairs,('dead boss branch',es)
            final=repairs[0];seq=[dict(type='cable',edge=e) for e in es]+[dict(type='storm')]+[dict(type='cable',edge=e) for e in sorted(set(remaining)^set(final))]
            alternates.append(seq)
        count=len(alternates);actions=alternates[0]
    else:
        for es in subsets(len(p['edges'])):
            if cost(p,es)>p['budget'] or not connected(p,es): continue
            dist=distances(p,es)[0]; durations=[max(1,v) for v in dist]
            if sum(durations)>p['max_end']:continue
            starts=[];now=0
            for dur in durations:starts.append(now);now+=dur
            networks.append(dict(edges=es,durations=durations,starts=starts))
            seq=[dict(type='cable',edge=e) for e in es]+[dict(type='depart',job=i,start=s) for i,s in enumerate(starts)]
            alternates.append(seq)
        count=len(alternates);actions=alternates[0]
    assert count>0
    fixtures[d['id']]=dict(actions=actions,alternates=alternates if f=='storm' else alternates[:2],count=count,networks=networks)
    summaries.append(f"{d['id']} {f}: {count} {'paths' if f=='routes' else 'legal configurations'}")
ids={x['id'] for x in levels};seen=set()
for d in levels:
    assert set(d['prerequisites'])<=seen
    if not d['side']:assert all(not levels[int(v[2:])-1]['side'] for v in d['prerequisites'])
    assert not {'solution','answer'}&d.keys();seen.add(d['id'])
assert len(ids)==18
(ROOT/'tests/observatory/witnesses.json').write_text(json.dumps(fixtures,ensure_ascii=False,indent=2)+'\n')
print('\n'.join(summaries));print('PASS: feasibility, alternates, optimization, all storm branches, DAG, no side gating')

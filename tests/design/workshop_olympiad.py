#!/usr/bin/env python3
"""Finite model checks for the workshop design, not Godot or difficulty acceptance."""
from itertools import permutations, product
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
RESULTS = {}

def record(level, solutions, **evidence):
    RESULTS[level] = dict(solution_count=len(solutions), examples=solutions[:6], **evidence)

def schedules(order, durations, horizon, releases=None, offset=0, result=()):
    if not order:
        yield dict(result)
        return
    name, *rest = order
    first = max(offset, (releases or {}).get(name, 0))
    last = horizon - sum(durations[x] for x in order)
    for start in range(first, last + 1):
        yield from schedules(rest, durations, horizon, releases,
                             start + durations[name], result + ((name, start),))

def queues_ok(produced, consumed, horizon):
    return all(sum(produced[x] <= t < consumed[x] for x in produced) <= 1
               for t in range(horizon + 1))

def main():
    choices = [p for p in product((4, 7), repeat=8)
               if 4 in p and 7 in p and sum(p)-4-7 == 27]
    assert len(choices) == 28 and all(p.count(4) == 6 for p in choices)
    record('GW02', choices, quantities={'small': 6, 'large': 2}, produced=38, reserved=11)

    pair = [t for t in range(1,41) if t >= 2 and (t-2)%3 == 0 and t >= 3 and (t-3)%4 == 0]
    triple = [t for t in pair if (t-3)%5 == 0]
    assert pair == [11,23,35] and triple == [23]
    record('GW03', triple, two_machine_meetings=pair, horizon=40)

    meets = {d: [t for t in range(1,17) if t >= 2+d and (t-2-d)%6 == 0 and t%4 == 0]
             for d in range(3)}
    assert meets == {0:[8], 1:[], 2:[4,16]}
    record('GW04', [dict(delay=d, transfers=v) for d,v in meets.items() if len(v) >= 2], all_delays=meets)

    drill = dict(A=3,B=2,C=1); polish = dict(A=1,B=3,C=2)
    plans = []
    for do in permutations(drill):
        for ds in schedules(do,drill,7):
            ends = {x:ds[x]+drill[x] for x in ds}
            for po in permutations(polish):
                for ps in schedules(po,polish,7,ends):
                    plans.append(dict(drill=ds, polish=ps))
    assert len(plans) == 1 and plans[0] == dict(drill=dict(C=0,B=1,A=3),polish=dict(C=1,B=3,A=6))
    record('GW05', plans, lower_bound=7, rationale='earliest polish 1 plus six polish beats')

    sequences = [p for n in range(1,11) for p in product((3,5),repeat=n) if sum(p) == 31]
    good = [p for p in sequences if len(p)+sum(a!=b for a,b in zip(p,p[1:])) <= 8]
    assert set(good) == {(3,3,5,5,5,5,5),(5,5,5,5,5,3,3)}
    record('GW06',good,quantity_combinations=sorted(set((p.count(3),p.count(5)) for p in sequences)), deadline=8)

    goods = tuple('ABCD'); pd = {x:1 for x in goods}; cd = {x:2 for x in goods}
    plans = []
    for ps in schedules(goods,pd,11):
        pe = {x:ps[x]+1 for x in goods}
        for cs in schedules(goods,cd,11,pe):
            if any(cs[x] < 5 and cs[x]+2 > 4 for x in goods): continue
            if queues_ok(pe,cs,11): plans.append(dict(press=ps,cool=cs))
    assert plans and min(max(p['cool'][x]+2 for x in goods) for p in plans) == 11
    assert dict(press=dict(A=0,B=1,C=4,D=6),cool=dict(A=1,B=5,C=7,D=9)) in plans
    record('GW07',plans,minimum_finish=11,maintenance=[4,5],buffer_capacity=1)

    cap1 = [p for p in range(5,17) if 35%p == 3]
    cap2 = [p for p in range(5,17) if 47%p == 7]
    caps = sorted(set(cap1)&set(cap2))
    assert cap1 == [8,16] and cap2 == [8,10] and caps == [8]
    record('GW08',caps,first_record_candidates=cap1,second_record_candidates=cap2)

    tracks = {}
    for step in range(2,9):
        visited = [0]; cursor = step%12
        while cursor not in visited:
            visited.append(cursor); cursor=(cursor+step)%12
        tracks[step] = visited+[cursor]
    good = [k for k,v in tracks.items() if len(v) == 13 and (3*k)%12 == 9]
    assert good == [7]
    record('GW09',good,tracks=tracks,coverage_only=[k for k,v in tracks.items() if len(v)==13])

    durations = dict(A=2,B=3,C=1,D=2); deadline=dict(A=5,B=8,C=3,D=6)
    plans = [s for order in permutations(durations) for s in schedules(order,durations,8,dict(C=1))
             if all(s[x]+durations[x] <= deadline[x] for x in s)]
    assert len(plans) == 2
    record('GW10',plans,total_work=8)

    plans = []; conflicts = []
    for ticket in (13,14):
        for a,b in product(range(16),repeat=2):
            if a < 6 or b < 6: continue
            if a+2+3 != 12 or b+3+2 != ticket: continue
            plan=dict(A_assembly=a,A_cool=a+2,A_load=12,B_assembly=b,B_cool=b+3,B_load=ticket)
            if not (a+2 <= b or b+3 <= a): conflicts.append(plan); continue
            plans.append(plan)
    assert len(plans) == 1 and plans[0]['A_assembly'] == 7 and plans[0]['B_assembly'] == 9
    assert len(conflicts) == 1 and conflicts[0]['B_load'] == 13 and conflicts[0]['B_assembly'] == 8
    record('GW11',plans,material_arrival=6,rejected_shared_table_conflicts=conflicts)

    batches = []
    for cap in range(3,13):
        first, carry = divmod(23,cap); second, last = divmod(carry+24,cap)
        if first+second == 9 and last == 2:
            batches.append(dict(capacity=cap,first=first,carry=carry,second=second,last=last))
    assert batches == [dict(capacity=5,first=4,carry=3,second=5,last=2)]
    record('GW12',batches)

    a=set(range(0,25,4)); b=set(range(0,25,6))
    assert len(a|b)==9 and len(a^b)==6 and a&b=={0,12,24}
    record('GW13',[dict(heard=9,solo=6)],first_bird=sorted(a),second_bird=sorted(b),together=sorted(a&b))

    pair=[n for n in range(20,81) if n%4==3 and n%6==5]
    single=[n for n in pair if n%5==2]
    assert pair == [23,35,47,59,71] and single == [47]
    record('GW14',single,two_record_candidates=pair)

    signatures = {t: [t//p for p in (3,4,5)] for t in range(1,13)}
    choices=[t for t,v in signatures.items() if len(set(v))==3]
    assert choices == [9,12]
    record('GW15',[min(choices)],all_distinguishing_times=choices,observation_signatures=signatures)

    tunes=[p for p in product((2,3,4),repeat=4) if sum(p)==12 and p.count(3)==2
           and all(p[i]!=p[(i+1)%4] for i in range(4))]
    assert len(tunes)==4
    record('GW16',tunes,rotations_count_as_different=True)

    durations=dict(A=3,B=2,C=1,D=2); release=dict(A=0,B=1,C=3,D=6); deadline=dict(A=7,B=4,C=5,D=9)
    plans=[s for order in permutations(durations) for s in schedules(order,durations,9,release)
           if all(s[x]+durations[x]<=deadline[x] for x in s)]
    assert plans == [dict(B=1,C=3,A=4,D=7)]
    record('GW17',plans)

    pd=dict(F=1,V=2,M=1); cd=dict(F=2,V=2,M=2)
    branches={6:[],8:[]}; robust=[]
    for order in permutations(pd):
        for ps in schedules(order,pd,10):
            pe={x:ps[x]+pd[x] for x in ps}
            for cs in schedules(order,cd,10,pe):
                if not queues_ok(pe,cs,10): continue
                ce={x:cs[x]+2 for x in cs}
                valid=[]
                for slot in (6,8):
                    load=dict(F=3,V=slot,M=9)
                    if all(ce[x]<=load[x] for x in ce) and queues_ok(ce,load,10):
                        branches[slot].append(dict(press=ps,cool=cs)); valid.append(slot)
                if len(valid)==2: robust.append(dict(press=ps,cool=cs))
    sample=dict(press=dict(F=0,V=1,M=3),cool=dict(F=1,V=3,M=6))
    risky=dict(press=dict(F=0,V=1,M=3),cool=dict(F=1,V=3,M=5))
    assert sample in robust and risky in branches[6] and risky not in branches[8]
    record('GW18',robust,branch_solution_counts={k:len(v) for k,v in branches.items()},sample=sample,rejected_late_example=risky)

    files=[Path(__file__),ROOT/'docs/production/workshop_chapter_olympiad.md']
    receipt=dict(scope='Design-model evidence only; no Godot or child difficulty acceptance',
                 inputs={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
                 levels=RESULTS,passed=len(RESULTS)==17)
    output=ROOT/'docs/playtest/workshop-olympiad/verification.json'
    output.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v['solution_count'] for k,v in RESULTS.items()},ensure_ascii=False))
    print('WORKSHOP DESIGN: 17/17 PASS')

if __name__=='__main__': main()

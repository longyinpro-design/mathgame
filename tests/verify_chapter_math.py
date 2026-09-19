"""Independent exhaustive oracle for the authored two-phase forest mechanism."""
import itertools
import json


def sums(a):
    return [a[0] + a[1] + a[2], a[2] + a[3] + a[4], a[4] + a[5] + a[0]]


def exchange(a, i, j):
    out = list(a)
    out[i], out[j] = out[j], out[i]
    return out


pairs = list(itertools.combinations(range(6), 2))
origins = [list(a) for a in itertools.permutations(range(1, 7)) if sums(a) == [10, 10, 10]]
assert len(origins) == 6
results = []
for origin in origins:
    target = sums(exchange(exchange(origin, 0, 1), 3, 5))
    assert len(set(target)) == 3
    assert sums(origin) != target
    assert all(sums(exchange(origin, *pair)) != target for pair in pairs)
    routes = [
        [list(first), list(second)]
        for first in pairs
        for second in pairs
        if sums(exchange(exchange(origin, *first), *second)) == target
    ]
    assert routes
    results.append({"origin": origin, "targets": target, "minimum_exchanges": 2, "two_exchange_routes": len(routes)})
print(json.dumps({"status": "PASS", "permutations": 720, "first_phase_solutions": 6, "cases": results}, ensure_ascii=False, indent=2))

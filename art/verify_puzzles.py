"""Reproduce the mathematics checks for the design packet; no Godot code."""

import hashlib
import itertools
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/首章关卡-v1.json"
OUTPUT = ROOT / "docs/关卡验算-v1.json"


def triangle_solutions(numbers, side_sum):
    return [list(v) for v in itertools.permutations(numbers)
            if v[0] + v[1] + v[2] == side_sum
            and v[2] + v[3] + v[4] == side_sum
            and v[4] + v[5] + v[0] == side_sum]


def game_table(stones, max_take):
    winning = [False] * (stones + 1)
    moves = {}
    for n in range(1, stones + 1):
        moves[n] = [k for k in range(1, min(n, max_take) + 1)
                    if not winning[n-k]]
        winning[n] = bool(moves[n])
    return {"winning_first_moves": moves[stones],
            "losing_positions": [n for n in range(stones + 1) if not winning[n]],
            "block_size": max_take + 1,
            "strategy_covers_all_replies": all(
                1 <= (max_take + 1 - k) <= max_take
                for k in range(1, max_take + 1))}


def solve(level):
    p = level["params"]
    family = level["family"]
    if family == "subset_sum":
        return {"solutions": [list(c) for c in itertools.combinations(p["numbers"], p["choose"])
                              if sum(c) == p["target"]
                              and ("span" not in p or max(c) - min(c) == p["span"])]}
    if family == "transfer_balance":
        solutions = [{"left": a, "right": p["total"] - a}
                     for a in range(1, p["total"])
                     if a >= p["transfer"]
                     and a - p["transfer"] == p["total"] - a + p["transfer"]]
        assert len(solutions) == 1
        return solutions[0]
    if family == "pair_weights":
        solutions = [{"a": a, "b": b, "c": c}
                     for a, b, c in itertools.product(
                         range(p["weight_min"], p["weight_max"] + 1), repeat=3)
                     if a + b == p["ab"] and b + c == p["bc"] and a + c == p["ac"]]
        assert len(solutions) == 1
        return solutions[0]
    if family == "reverse_machine":
        solutions = []
        for start in range(p["input_min"], p["input_max"] + 1):
            value, trace, legal = start, [start], True
            for op, number in p["operations"]:
                if op == "add":
                    value += number
                elif op == "sub":
                    value -= number
                elif op == "mul":
                    value *= number
                elif op == "div":
                    if value % number:
                        legal = False
                        break
                    value //= number
                else:
                    raise ValueError(op)
                if value < 0:
                    legal = False
                    break
                trace.append(value)
            if legal and value == p["output"]:
                solutions.append({"input": start, "forward": trace})
        assert len(solutions) == 1
        return solutions[0]
    if family == "grid_paths":
        steps = p["right"] + p["up"]
        avoid = set(map(tuple, p["avoid"]))
        via = set(map(tuple, p["via"]))
        paths = []
        for right_indices in itertools.combinations(range(steps), p["right"]):
            right_indices = set(right_indices)
            x, y, visited, path = 0, 0, {(0, 0)}, ""
            for i in range(steps):
                if i in right_indices:
                    x += 1
                    path += "R"
                else:
                    y += 1
                    path += "U"
                visited.add((x, y))
            if not visited & avoid and via <= visited:
                paths.append(path)
        return {"count": len(paths), "paths": sorted(paths)}
    if family == "triangle_sum":
        solutions = triangle_solutions(p["numbers"], p["side_sum"])
        vertex_sums = {s[0] + s[2] + s[4] for s in solutions}
        assert len(vertex_sums) == 1
        assert level["expected"]["example"] in solutions
        return {"raw_solution_count": len(solutions), "vertex_sum": vertex_sums.pop(),
                "example": level["expected"]["example"], "solutions": solutions}
    if family == "reachability":
        positions = {p["start"]}
        trace = [sorted(positions)]
        for _ in range(p["steps"]):
            positions = {x + delta for x in positions for delta in p["moves"]
                         if p["minimum"] <= x + delta <= p["maximum"]}
            trace.append(sorted(positions))
        return {"reachable": p["target"] in positions,
                "final_positions": sorted(positions), "positions_by_step": trace}
    if family == "pigeonhole":
        allocations = list(itertools.product(*(range(c + 1) for c in p["capacities"])))
        for k in range(1, sum(p["capacities"]) + 1):
            draws = [a for a in allocations if sum(a) == k]
            if draws and all(max(a) >= p["matching"] for a in draws):
                counterexamples = [list(a) for a in allocations
                                   if sum(a) == k - 1 and max(a) < p["matching"]]
                assert counterexamples
                return {"guaranteed_draws": k,
                        "counterexamples_with_one_fewer": counterexamples,
                        "allocations_checked_at_threshold": len(draws)}
        raise ValueError("A guarantee is impossible with these capacities")
    if family == "cycles":
        i = p["index"] - 1
        colors, shapes = p["colors"], p["shapes"]
        bound = len(colors) * len(shapes)
        sequence = [(colors[k % len(colors)], shapes[k % len(shapes)])
                    for k in range(2 * bound)]
        period = next(d for d in range(1, bound + 1)
                      if all(sequence[k] == sequence[k + d] for k in range(bound)))
        return {"color": colors[i % len(colors)], "shape": shapes[i % len(shapes)],
                "period": period, "repeat_block": sequence[:period]}
    if family == "rectangle_perimeter":
        rectangles = [{"dimensions": [a, p["area"] // a],
                       "perimeter": 2 * (a + p["area"] // a)}
                      for a in range(1, math.isqrt(p["area"]) + 1)
                      if p["area"] % a == 0]
        best = min(rectangles, key=lambda r: r["perimeter"])
        return {"minimum_perimeter": best["perimeter"],
                "dimensions": best["dimensions"], "all_rectangles": rectangles}
    if family == "takeaway":
        return game_table(p["stones"], p["max_take"])
    if family == "combined_boss":
        solutions = triangle_solutions(p["numbers"], p["side_sum"])
        vertex_sums = {s[0] + s[2] + s[4] for s in solutions}
        assert len(vertex_sums) == 1
        vertex_sum = vertex_sums.pop()
        stones = vertex_sum + p["offset"]
        return {"triangle_raw_solution_count": len(solutions), "vertex_sum": vertex_sum,
                "stones": stones, "triangle_solutions": solutions,
                **game_table(stones, p["max_take"])}
    raise ValueError(f"Unknown family: {family}")


def main():
    source_bytes = SOURCE.read_bytes()
    data = json.loads(source_bytes)
    levels = data["levels"]
    assert len(levels) == 18
    assert len({l["id"] for l in levels}) == len(levels)
    results = []
    for level in levels:
        actual = solve(level)
        for key, expected in level["expected"].items():
            assert actual[key] == expected, (level["id"], key, actual[key], expected)
        results.append({"id": level["id"], "status": "PASS", "computed": actual})
    result = {"status": "PASS", "passed": len(results), "total": len(levels),
              "input_sha256": hashlib.sha256(source_bytes).hexdigest(),
              "command": "python3 art/verify_puzzles.py",
              "scope": "Discrete rules and reference answers only; no Godot or child playtesting.",
              "results": results}
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "results"}, ensure_ascii=False))


if __name__ == "__main__":
    main()

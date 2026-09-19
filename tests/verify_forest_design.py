"""Verify authored forest design mathematics; this does not execute Godot scenes."""

import argparse
import hashlib
import heapq
import importlib.util
import itertools
import json
import math
from fractions import Fraction
from functools import lru_cache
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/production/forest_levels.json"
LEGACY = ROOT / "art/verify_puzzles.py"
spec = importlib.util.spec_from_file_location("legacy_design_math", LEGACY)
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)


def cargo(params, start_override=None):
    """Shortest lift count over all legal layouts, including empty return trips."""
    weights = params['weights']
    goal = params.get('goal_items', 3)
    capacity = params.get('max_items_per_basket', 6)
    load_limit = params.get('max_basket_weight', sum(weights))
    locked = params.get('lock_delivered', False)
    start = tuple(start_override) if start_override else (*params['initial_places'], params['left_low'])
    distances, parents, queue, endings = {start: 0}, {}, [(0, start)], []

    def edges(state):
        places, left_low = state[:len(weights)], state[len(weights)]
        for item, source in enumerate(places):
            if locked and item < goal and source == 3:
                continue
            for target in range(4):
                if source in (0, 3) and target in (1, 2):
                    dock = 0 if (target == 1) == left_low else 3
                    mass = sum(w for w, loc in zip(weights, places) if loc == target)
                    allowed = source == dock and places.count(target) < capacity and mass + weights[item] <= load_limit
                elif source in (1, 2) and target in (0, 3):
                    allowed = target == (0 if (source == 1) == left_low else 3)
                else:
                    allowed = False
                if allowed:
                    changed = list(places)
                    changed[item] = target
                    yield (*changed, left_low), 0, ['move', item, target]
        totals = [sum(w for w, loc in zip(weights, places) if loc == side) for side in (1, 2)]
        if totals[0] != totals[1] and (totals[0] > totals[1]) != left_low:
            new_low, arrived = not left_low, list(places)
            for item in range(goal):
                if arrived[item] in (1, 2) and (arrived[item] == 1) != new_low:
                    arrived[item] = 3
            yield (*arrived, new_low), 1, ['travel']

    target_state = (3,) * goal
    while queue:
        trips, state = heapq.heappop(queue)
        if trips != distances[state]:
            continue
        if state[:goal] == target_state:
            endings.append(state)
            continue
        for changed, cost, action in edges(state):
            if changed not in distances or trips + cost < distances[changed]:
                distances[changed] = trips + cost
                parents[changed] = (state, action)
                heapq.heappush(queue, (trips + cost, changed))
    result = {'solvable': bool(endings), 'reachable_layouts': len(distances), 'terminal_layouts': len(endings)}
    if endings:
        best = min(endings, key=lambda state: distances[state])
        path, current = [], best
        while current != start:
            previous, action = parents[current]
            path.append(action)
            current = previous
        result.update(minimum_trips=distances[best], optimal_actions=list(reversed(path)))
        if capacity < goal:
            result['lower_bound_trips'] = math.ceil(goal / capacity)
    if start_override is None and 'greedy_state' in params:
        greedy = tuple(params['greedy_state'])
        assert greedy in distances, 'The claimed greedy counterexample must be reachable'
        result['greedy_can_finish'] = cargo(params, greedy)['solvable']
        assert result['greedy_can_finish'] is False
    return result


def cargo_manifests(params):
    """All distinct ride manifests at the minimum trip count, plus the structural
    claims behind the FL11 redesign: with four up-items and three counterweights,
    no one-person-one-stone plan exists and no two-trip plan exists."""
    weights = params['weights']
    goal = params.get('goal_items', 3)
    capacity = params.get('max_items_per_basket', 6)
    load_limit = params.get('max_basket_weight', sum(weights))
    locked = params.get('lock_delivered', False)
    start = (*params['initial_places'], params['left_low'])

    def move_edges(state):
        places, left_low = state[:len(weights)], state[len(weights)]
        for item, source in enumerate(places):
            if locked and item < goal and source == 3:
                continue
            for target in range(4):
                if source in (0, 3) and target in (1, 2):
                    dock = 0 if (target == 1) == left_low else 3
                    mass = sum(w for w, loc in zip(weights, places) if loc == target)
                    if source == dock and places.count(target) < capacity and mass + weights[item] <= load_limit:
                        changed = list(places)
                        changed[item] = target
                        yield (*changed, left_low)
                elif source in (1, 2) and target in (0, 3):
                    if target == (0 if (source == 1) == left_low else 3):
                        changed = list(places)
                        changed[item] = target
                        yield (*changed, left_low)

    def travel_edge(state):
        places, left_low = state[:len(weights)], state[len(weights)]
        totals = [sum(w for w, loc in zip(weights, places) if loc == side) for side in (1, 2)]
        if totals[0] == totals[1] or (totals[0] > totals[1]) == left_low:
            return None
        rising, falling = (1, 2) if totals[0] < totals[1] else (2, 1)
        new_low, arrived = not left_low, list(places)
        for item in range(goal):
            if arrived[item] in (1, 2) and (arrived[item] == 1) != new_low:
                arrived[item] = 3
        lifted = tuple(sorted(i for i in range(goal) if places[i] == rising))
        dropped = tuple(sorted(i for i in range(goal, len(weights)) if places[i] == falling))
        return (*arrived, new_low), lifted, dropped

    layers = {start: {()}}
    manifests, min_trips = {}, None
    for trips in range(1, 8):
        stack = list(layers)
        while stack:
            state = stack.pop()
            known = layers[state]
            for moved in move_edges(state):
                if moved not in layers:
                    layers[moved] = set()
                    stack.append(moved)
                before = len(layers[moved])
                layers[moved] |= known
                if len(layers[moved]) != before:
                    stack.append(moved)
        nxt = {}
        for state, marks in layers.items():
            travel = travel_edge(state)
            if travel is None:
                continue
            after, lifted, dropped = travel
            nxt.setdefault(after, set())
            for manifest in marks:
                nxt[after].add(tuple(sorted(manifest + ((lifted, dropped),))))
        layers = nxt
        if not layers:
            break
        done = [state for state in layers if state[:goal] == (3,) * goal]
        if done:
            min_trips = trips
            for state in done:
                for manifest in layers[state]:
                    manifests[manifest] = True
            break
    assert min_trips is not None, 'manifest sweep must reach delivery'
    single_rider = sum(1 for m in manifests
                       if all(len(up) == 1 and len(down) == 1 for up, down in m))
    two_trip = sum(1 for m in manifests if len(m) <= 2)
    return {'minimal_manifests': len(manifests),
            'single_rider_manifests': single_rider, 'two_trip_solutions': two_trip}


def allocations(total, minimum):
    for a in range(minimum, total + 1):
        for b in range(minimum, total - a + 1):
            c = total - a - b
            if c >= minimum:
                yield [a, b, c]


def transfer_trace(initial, moves, doubling=False, equal_after=None):
    state, trace = initial[:], [initial[:]]
    for index, move in enumerate(moves):
        source, target = move[:2]
        amount = state[target] if doubling else move[2]
        if amount < 0 or state[source] < amount:
            return None
        state[source] -= amount
        state[target] += amount
        assert sum(state) == sum(initial) and min(state) >= 0
        trace.append(state[:])
        if equal_after:
            a, b = equal_after[index]
            if state[a] != state[b]:
                return None
    return trace


def transfer_problem(p, doubling):
    matches = []
    for initial in allocations(p['total'], p['minimum']):
        trace = transfer_trace(initial, p['moves'], doubling, p.get('equal_after'))
        if trace and (not doubling or trace[-1] == p['target']):
            matches.append(trace)
    assert len(matches) == 1, ('transfer solution count', len(matches))
    result = {'initial': matches[0][0], 'trace': matches[0], 'solution_count': len(matches)}
    if doubling:
        state, reverse = p['target'][:], [p['target'][:]]
        for source, target in reversed(p['moves']):
            assert state[target] % 2 == 0
            returned = state[target] // 2
            state[target] -= returned
            state[source] += returned
            reverse.append(state[:])
        assert reverse == list(reversed(matches[0]))
        flat = transfer_trace(p['target'], p['moves'], True)
        assert flat is None or flat[-1] != p['target']
        result.update(reverse_trace=reverse, final_layout_as_initial_rejected=True)
    else:
        only_first = [s for s in allocations(p['total'], p['minimum'])
                      if transfer_trace(s, p['moves'][:1], False, p['equal_after'][:1])]
        assert len(only_first) > 1
        result['first_condition_only_candidates'] = len(only_first)
    return result


def evaluate(operations, value):
    trace = [value]
    for op, number in operations:
        if op == 'add':
            value += number
        elif op == 'sub':
            value -= number
        elif op == 'mul':
            value *= number
        else:
            raise ValueError(op)
        if value < 0:
            return None
        trace.append(value)
    return trace


def machine_candidates(p, records):
    modules = {m['id']: m['op'] for m in p['modules']}
    candidates = []
    for order in itertools.permutations(modules, p['slots']):
        operations = [modules[id] for id in order]
        if all((trace := evaluate(operations, x)) is not None and trace[-1] == y for x, y in records):
            candidates.append(list(order))
    return candidates, modules


def machine_problem(p, ambiguity=False):
    orders, modules = machine_candidates(p, p['records'])
    if not ambiguity:
        assert len(orders) == 1
        single = [len(machine_candidates(p, [record])[0]) for record in p['records']]
        assert all(n > 1 for n in single), 'Both records must rule out real alternatives'
        predicted = evaluate([modules[id] for id in orders[0]], p['predict_input'])[-1]
        return {'orders': orders, 'single_record_counts': single, 'predicted_output': predicted}
    assert len(orders) > 1
    outputs = [[evaluate([modules[id] for id in order], x)[-1]
                for x in range(p['input_domain'][0], p['input_domain'][1] + 1)] for order in orders]
    same = all(values == outputs[0] for values in outputs)
    checkpoint = p['checkpoint']
    after = [order for order in orders if evaluate([modules[id] for id in order], checkpoint['input'])[checkpoint['after_step']] == checkpoint['value']]
    assert same and len(after) == 1
    return {'orders_before': orders, 'orders_after': after, 'externally_indistinguishable': same,
            'verified_input_domain': p['input_domain']}


def probe_problem(p):
    columns = {x: {id: evaluate(ops, x)[-1] for id, ops in p['candidates'].items()} for x in p['probe_inputs']}
    valid = [x for x, column in columns.items() if len(set(column.values())) == len(column)]
    assert len(valid) == 1
    return {'distinguishing_inputs': valid, 'outputs_at_solution': columns[valid[0]],
            'ambiguous_inputs': [x for x in columns if x not in valid], 'all_prediction_columns': columns}


def paths(p):
    return legacy.solve({'family': 'grid_paths', 'params': p})['paths']


def visited(path):
    x = y = 0
    result = [(0, 0)]
    for step in path:
        x += step == 'R'
        y += step == 'U'
        result.append((x, y))
    return result


def route_problem(p, family):
    if family == 'route_block_choice':
        base = paths({'right': p['right'], 'up': p['up'], 'avoid': [], 'via': []})
        remaining = []
        for block in p['candidate_blocks']:
            direct = paths({'right': p['right'], 'up': p['up'], 'avoid': [block], 'via': []})
            through = [path for path in base if tuple(block) in visited(path)]
            assert set(direct).isdisjoint(through) and set(direct) | set(through) == set(base)
            remaining.append(len(direct))
        maximum = max(remaining)
        return {'total_paths': len(base), 'survivors': remaining, 'maximum_paths': maximum,
                'best_blocks': [b for b, count in zip(p['candidate_blocks'], remaining) if count == maximum]}
    base = paths(p)
    if family == 'route_partition':
        assert p['partition'] == 'height_of_first_R'
        groups = {str(height): [] for height in range(p['up'] + 1)}
        for path in base:
            groups[str(path.index('R'))].append(path)
        assert sum(map(len, groups.values())) == len(base)
        # The redesign seeds one misfiled card and one omitted route, and expects
        # the player to state the per-bag counts that expose the omission.
        # Mirror the engine seed exactly: the last route of the first bag is
        # omitted, and the last route of the second bag is filed into bag 0.
        missing = groups['0'][-1]
        misfiled = groups['1'][-1] if len(groups['1']) else ''
        assert missing not in groups['1'], 'seed must omit a route from bag 0'
        filing = [(path, path.index('R'))
                  for height in range(p['up'] + 1) for path in groups[str(height)]
                  if path != missing and path != misfiled]
        filing.append((misfiled, 0))
        assert len(filing) == len(base) - 1
        misfiled_cards = [path for path, bag in filing if bag != path.index('R')]
        assert misfiled_cards == [misfiled] and missing not in [path for path, _ in filing]
        counts = [len(groups[str(h)]) for h in range(p['up'] + 1)]
        assert math.comb(4, 2) == counts[0] and math.comb(3, 2) == counts[1] and math.comb(2, 2) == counts[2]
        return {'count': len(base), 'group_counts': {k: len(v) for k, v in groups.items()},
                'seed_filing_size': len(filing), 'misplaced': misfiled,
                'missing': missing, 'corrected_counts': counts}
    assert p['shared_endpoints_only'] is True
    pairs = [[a, b] for a, b in itertools.combinations(base, 2)
             if not set(visited(a)[1:-1]) & set(visited(b)[1:-1])]
    invalid = [[a, b] for a, b in itertools.combinations(base, 2) if [a, b] not in pairs]
    assert invalid and len(pairs) + len(invalid) == math.comb(len(base), 2)
    # Upper bound: every right-first route visits (1,0) and every up-first route
    # visits (0,1), so two of the same kind always collide -> at most one of each.
    right_first = [path for path in base if path[0] == 'R']
    up_first = [path for path in base if path[0] == 'U']
    assert all((1, 0) in visited(path) for path in right_first)
    assert all((0, 1) in visited(path) for path in up_first)
    assert all([a, b] not in pairs for a, b in itertools.combinations(right_first, 2))
    assert all([a, b] not in pairs for a, b in itertools.combinations(up_first, 2))
    maximum = 2 if any([a, b] in pairs for a in right_first for b in up_first) else 1
    witness = next([a, b] for a in right_first for b in up_first if [a, b] in pairs)
    return {'route_count': len(base), 'pair_count': len(pairs), 'pairs': pairs,
            'max_simultaneous': maximum, 'witness': witness,
            'reason': '先向右的必过(1,0)、先向上的必过(0,1)，三封中必有两封同向相撞',
            'individually_legal_but_colliding_example': invalid[0]}


def game_table(total, maximum, last_taker):
    assert last_taker in ('wins', 'loses')
    # For misere play, a move to zero loses immediately, represented by win[0].
    wins, moves = [last_taker == 'loses'] + [False] * total, [[] for _ in range(total + 1)]
    for n in range(1, total + 1):
        moves[n] = [k for k in range(1, min(n, maximum) + 1) if not wins[n - k]]
        wins[n] = bool(moves[n])

    @lru_cache(None)
    def hero_guarantee(n, hero_turn):
        branches = []
        for k in range(1, min(n, maximum) + 1):
            if k == n:
                branches.append(hero_turn if last_taker == 'wins' else not hero_turn)
            else:
                branches.append(hero_guarantee(n - k, not hero_turn))
        return any(branches) if hero_turn else all(branches)

    for n in range(1, total + 1):
        assert hero_guarantee(n, True) == wins[n]
        assert hero_guarantee(n, False) == (not wins[n])
    return wins, moves


def fixed_policy_counterexample(n, maximum, moves, first_take, repeat_take):
    def search(remaining, first, trace):
        take = first_take if first else repeat_take
        if take > remaining:
            return trace + [['illegal_player_take', take, remaining]]
        remaining -= take
        trace = trace + [['player', take, remaining]]
        if remaining == 0:
            return None
        replies = moves[remaining] or list(range(1, min(remaining, maximum) + 1))
        for reply in replies:
            left = remaining - reply
            next_trace = trace + [['opponent', reply, left]]
            if left == 0:
                return next_trace
            losing = search(left, False, next_trace)
            if losing:
                return losing
        return None
    return search(n, True, [])


def strategy_problem(p):
    wins, moves = game_table(max(p['start_positions']), p['max_take'], p['last_taker'])
    openings = [moves[n] for n in p['start_positions']]
    replies = [moves[p['response_position'] - k] for k in range(1, p['max_take'] + 1)]
    witnesses = [fixed_policy_counterexample(n, p['max_take'], moves, p['shortcut_first'], p['shortcut_repeat']) for n in p['start_positions']]
    assert all(openings) and all(replies) and all(witnesses)
    return {'winning_openings': openings, 'response_moves': replies,
            'constant_shortcut_guaranteed': False, 'shortcut_counterexamples': witnesses,
            'all_opponent_replies_checked': True}


def seal_step(energy, cards, locked, move):
    amount, source, target = move
    if source == target or locked in (source, target) or amount not in cards or energy[source] < amount:
        return None
    next_energy = list(energy)
    next_energy[source] -= amount
    next_energy[target] += amount
    assert sum(next_energy) == sum(energy) and min(next_energy) >= 0
    return tuple(next_energy), tuple(n for n in cards if n != amount)


def seal_moves(energy, cards, locked):
    unlocked = [i for i in range(3) if i != locked]
    for amount in cards:
        for source, target in (unlocked, list(reversed(unlocked))):
            move = [amount, source, target]
            result = seal_step(energy, cards, locked, move)
            if result is not None:
                yield move, *result


def seal_problem(p):
    assert p['boss_response_after_turn'] == 1
    assert len(set(p['transfer_cards'])) == len(p['transfer_cards']) == 3
    assert sorted(p['locked_core_by_turn']) == [0, 1, 2]
    assert sum(p['initial_energy']) == sum(p['target_energy'])
    responses = p['boss_responses']
    assert len({r['id'] for r in responses}) == len(responses)
    for response in responses:
        assert sorted(response['permutation']) == [0, 1, 2]
    outcomes = []
    for opening, energy, cards in seal_moves(tuple(p['initial_energy']), tuple(p['transfer_cards']), p['locked_core_by_turn'][0]):
        branches = {}
        for response in responses:
            changed = tuple(energy[i] for i in response['permutation'])
            solutions = []
            for second, middle, remaining in seal_moves(changed, cards, p['locked_core_by_turn'][1]):
                for third, end, empty in seal_moves(middle, remaining, p['locked_core_by_turn'][2]):
                    if list(end) == p['target_energy'] and not empty:
                        solutions.append([second, third])
            branches[response['id']] = solutions
        outcomes.append({'opening': opening, 'branches': branches})
    robust = [item for item in outcomes if all(item['branches'].values())]
    assert len(robust) == 1
    witness = robust[0]
    tails = {}
    for id, solutions in witness['branches'].items():
        assert len(solutions) == 1
        tails[id] = solutions[0]
    greedy = next(item for item in outcomes if item['opening'] == p['greedy_opening'])
    assert not any(greedy['branches'].values())
    energy, cards = seal_step(tuple(p['initial_energy']), tuple(p['transfer_cards']), p['locked_core_by_turn'][0], witness['opening'])
    swapped = tuple(energy[i] for i in next(r for r in responses if r['id'] == 'leaf_swap')['permutation'])
    traces = {}
    for response in responses:
        state = tuple(energy[i] for i in response['permutation'])
        hand = cards
        trace = [p['initial_energy'], list(energy), list(state)]
        for turn, move in enumerate(tails[response['id']], 1):
            state, hand = seal_step(state, hand, p['locked_core_by_turn'][turn], move)
            trace.append(list(state))
        assert list(state) == p['target_energy'] and not hand
        traces[response['id']] = trace
    state, hand = swapped, cards
    for turn, move in enumerate(tails['stomp'], 1):
        result = seal_step(state, hand, p['locked_core_by_turn'][turn], move)
        if result is None:
            break
        state, hand = result
    fixed_survives = list(state) == p['target_energy'] and not hand
    assert not fixed_survives
    return {'robust_openings': [item['opening'] for item in robust], 'winning_tail_by_response': tails,
            'greedy_opening_can_win': False, 'fixed_stomp_tail_survives_swap': fixed_survives,
            'legal_opening_count': len(outcomes), 'all_openings_and_responses': outcomes,
            'witness_traces': traces}


def probe_battle_problem(p):
    assert p['finisher_requires_identified_form'] is True and p['probes_consume_seeds'] is True
    assert p['analysis_scopes'] == {
        'continuous_plan': {'prior_case_observations': False, 'undo': False},
        'replanning': {'full_probe_refund': True, 'prior_observations_available': True}}
    forms = p['forms']
    ids = tuple(forms)
    def output(id, value):
        trace = evaluate(forms[id]['operations'], value)
        assert trace is not None
        return trace[-1]
    costs = {}
    for id in ids:
        choices = [n for n in p['finisher_inputs'] if output(id, n) == p['target_response']]
        assert len(choices) == 1
        costs[id] = choices[0]
    def partitions(candidates, probe):
        groups = {}
        for id in candidates:
            groups.setdefault(output(id, probe), []).append(id)
        return {value: tuple(group) for value, group in groups.items()}

    @lru_cache(None)
    def viable_probes(candidates, budget, left):
        if len(candidates) == 1 or left == 0:
            return ()
        return tuple(probe for probe in p['probe_inputs'] if probe <= budget
                     and all(can_win(group, budget - probe, left - 1)
                             for group in partitions(candidates, probe).values()))

    @lru_cache(None)
    def can_win(candidates, budget, left):
        if len(candidates) == 1:
            return costs[candidates[0]] <= budget
        return bool(viable_probes(candidates, budget, left))

    first = viable_probes(ids, p['seed_budget'], p['max_probes'])
    assert first and p['greedy_probe'] not in first
    minimum = next(budget for budget in range(p['seed_budget'] + 1) if can_win(ids, budget, p['max_probes']))
    def policy(candidates, budget, left, forced=None):
        if len(candidates) == 1:
            assert costs[candidates[0]] <= budget
            return {'kind': 'finish', 'input': costs[candidates[0]], 'form': candidates[0]}
        probe = forced if forced is not None else viable_probes(candidates, budget, left)[0]
        assert probe in viable_probes(candidates, budget, left)
        return {'kind': 'probe', 'input': probe,
                'branches': {str(value): policy(group, budget - probe, left - 1)
                             for value, group in partitions(candidates, probe).items()}}

    def replay(hidden_form, actions):
        candidates, budget, probes = ids, p['seed_budget'], 0
        for index, action in enumerate(actions):
            kind, value = action
            if value > budget:
                return False
            budget -= value
            if kind == 'probe':
                if value not in p['probe_inputs'] or probes >= p['max_probes'] or len(candidates) == 1:
                    return False
                probes += 1
                candidates = partitions(candidates, value)[output(hidden_form, value)]
            elif kind == 'finish':
                return index == len(actions) - 1 and len(candidates) == 1 and value in p['finisher_inputs'] and output(hidden_form, value) == p['target_response']
            else:
                return False
        return False

    plans, ledgers = {}, {}
    for probe in first:
        plan = policy(ids, p['seed_budget'], p['max_probes'], probe)
        plans[str(probe)] = plan
        cases = {}
        for hidden in ids:
            node, actions = plan, []
            while node['kind'] == 'probe':
                value = node['input']
                actions.append(['probe', value])
                node = node['branches'][str(output(hidden, value))]
            actions.append(['finish', node['input']])
            assert replay(hidden, actions)
            cases[hidden] = {'actions': actions, 'seed_spent': sum(a[1] for a in actions),
                             'seed_left': p['seed_budget'] - sum(a[1] for a in actions)}
        ledgers[str(probe)] = cases
    assert output('B', 6) == p['target_response'] and not replay('B', [['probe', 6]])
    assert not replay('A', [['finish', costs['A']]])
    failures = [list(group) for group in partitions(ids, p['greedy_probe']).values()
                if not can_win(group, p['seed_budget'] - p['greedy_probe'], p['max_probes'] - 1)]
    # A player remembers earlier observations after refunding a probe. Enumerate
    # cheapest NEW active evidence for each already-known case, then demonstrate
    # that such knowledge can be acquired within the same smaller budget.
    known_case_plans = {}
    for hidden in ids:
        valid = []
        for length in range(1, p['max_probes'] + 1):
            for sequence in itertools.product(p['probe_inputs'], repeat=length):
                candidates = ids
                for value in sequence:
                    if len(candidates) == 1:
                        break
                    candidates = partitions(candidates, value)[output(hidden, value)]
                else:
                    if len(candidates) == 1:
                        valid.append((sum(sequence) + costs[hidden], sequence))
        assert valid
        spent, sequence = min(valid)
        known_case_plans[hidden] = {'cost': spent, 'probes': list(sequence)}
    refund_minimum = max(plan['cost'] for plan in known_case_plans.values())

    def replay_refunds(hidden, actions, initial_budget):
        active, candidates, budget, history = [], ids, initial_budget, []
        for index, (kind, value) in enumerate(actions):
            if kind == 'undo_probe':
                if not active:
                    return False
                budget += active.pop()
                candidates = ids
                for probe in active:
                    candidates = partitions(candidates, probe)[output(hidden, probe)]
                continue
            if value > budget:
                return False
            if kind == 'probe':
                if value not in p['probe_inputs'] or len(active) >= p['max_probes'] or len(candidates) == 1:
                    return False
                budget -= value
                active.append(value)
                history.append([value, output(hidden, value)])
                candidates = partitions(candidates, value)[output(hidden, value)]
            elif kind == 'finish':
                return index == len(actions) - 1 and len(candidates) == 1 and value in p['finisher_inputs'] and output(hidden, value) == p['target_response']
            else:
                return False
        return False

    refund_witnesses = {}
    for hidden in ids:
        # Probe 6 first. If its result is ambiguous, probe 2. Choose later steps
        # only after this observable prefix has identified the case.
        prefix = [['probe', 6]]
        observed_candidates = partitions(ids, 6)[output(hidden, 6)]
        if len(observed_candidates) > 1:
            prefix.append(['probe', 2])
            observed_candidates = partitions(observed_candidates, 2)[output(hidden, 2)]
        assert len(observed_candidates) == 1
        identified = observed_candidates[0]
        used = sum(action[1] for action in prefix)
        if refund_minimum - used >= costs[identified]:
            actions = prefix + [['finish', costs[identified]]]
        else:
            actions = prefix + [['undo_probe', 0] for _ in prefix]
            actions += [['probe', n] for n in known_case_plans[identified]['probes']]
            actions.append(['finish', costs[identified]])
        assert replay_refunds(hidden, actions, refund_minimum)
        refund_witnesses[hidden] = actions
    return {'guaranteed_first_probes_without_undo': list(first), 'finisher_costs': costs,
            'minimum_guaranteed_budget_without_undo': minimum, 'greedy_probe_guaranteed_without_undo': False,
            'minimum_budget_with_probe_refund_and_prior_observations': refund_minimum,
            'known_case_active_evidence_costs': known_case_plans, 'refund_replanning_witnesses': refund_witnesses,
            'analysis_scopes': p['analysis_scopes'],
            'probe_columns': {str(x): {id: output(id, x) for id in ids} for x in p['probe_inputs']},
            'witness_policies_without_undo': plans, 'case_ledgers_without_undo': ledgers,
            'greedy_failing_groups_without_undo': failures,
            'probe_response_is_not_victory': True, 'unidentified_finisher_rejected': True}



def parity_problem(p):
    base = legacy.solve({'family': 'reachability', 'params': {**p, 'target': p['repair_target']}})
    endpoint_set = set(base['final_positions'])
    assert p['repair_target'] not in endpoint_set
    repairs = []
    for changed_index in range(p['steps']):
        for replacement in p['repair_moves']:
            for ordinary in itertools.product(p['moves'], repeat=p['steps'] - 1):
                sequence = list(ordinary)
                sequence.insert(changed_index, replacement)
                state, trace = p['start'], [p['start']]
                for delta in sequence:
                    state += delta
                    if not p['minimum'] <= state <= p['maximum']:
                        break
                    trace.append(state)
                else:
                    if state == p['repair_target']:
                        repairs.append({'moves': sequence, 'trace': trace})
    assert repairs
    return {'reachable_targets': [n in endpoint_set for n in p['targets']],
            'final_positions': base['final_positions'], 'minimum_replacements': 1,
            'repair_witness': repairs[0], 'even_unreachable_targets': [n for n in p['targets'] if n % 2 == 0 and n not in endpoint_set]}


def weighing_problem(p):
    assert p['heavy_weight'] > p['normal_weight'] > 0
    def trace(node, heavy, depth):
        if isinstance(node, int):
            return node, depth
        left, right = node['left'], node['right']
        assert len(left) == len(right) and len(set(left + right)) == len(left + right)
        assert all(0 <= i < p['coin_count'] for i in left + right)
        masses = [sum(p['heavy_weight'] if i == heavy else p['normal_weight'] for i in side) for side in (left, right)]
        branch = 'left' if masses[0] > masses[1] else 'right' if masses[1] > masses[0] else 'equal'
        return trace(node['branches'][branch], heavy, depth + 1)
    depths = []
    for heavy in range(p['coin_count']):
        identified, depth = trace(p['reference_plan'], heavy, 0)
        assert identified == heavy and depth <= p['max_weighings']
        depths.append(depth)
    return {'identified_cases': p['coin_count'], 'maximum_depth': max(depths),
            'one_weighing_sufficient': p['coin_count'] <= 3, 'single_weighing_outcome_bound': 3}


def wall_problem(p):
    cases = [{'width': width, 'length': p['fence_units'] - 2 * width,
              'area': width * (p['fence_units'] - 2 * width)}
             for width in range(p['minimum_side'], p['fence_units'])
             if p['fence_units'] - 2 * width >= p['minimum_side']]
    maximum = max(c['area'] for c in cases)
    sweep = (p['fence_units'] - 1) // 2
    assert sweep == len(cases), 'completion requires trying every candidate width'
    return {'maximum_area': maximum, 'best_dimensions': [[c['width'], c['length']] for c in cases if c['area'] == maximum],
            'candidate_count': len(cases), 'completion_sweep_count': sweep, 'all_cases': cases}


def solve(level):
    p, family = level['params'], level['family']
    if family == 'twenty_four':
        def all_solutions(cards):
            found = set()

            def rec(items):
                if len(items) == 1:
                    if items[0][0] == p['target']:
                        found.add(items[0][1])
                    return
                for i, (a, expr_a) in enumerate(items):
                    for k, (b, expr_b) in enumerate(items):
                        if i == k:
                            continue
                        rest = [item for j, item in enumerate(items) if j not in (i, k)]
                        outcomes = [('+', a + b), ('-', a - b), ('*', a * b)]
                        if b:
                            outcomes.append(('/', a / b))
                        for symbol, value in outcomes:
                            if symbol in '+*' and i > k:
                                continue
                            rec(rest + [(value, "(%s %s %s)" % (expr_a, symbol, expr_b))])
            rec([(Fraction(card), str(card)) for card in cards])
            return found

        sols = all_solutions(p['cards'])
        direct = [(a, b) for a, b in itertools.combinations_with_replacement(p['cards'], 2) if a * b == p['target']]
        return {'solvable': bool(sols), 'solution_count': len(sols),
                'direct_product_pairs': len(direct),
                'integer_only_solutions': sum(1 for expr in sols if '/' not in expr)}
    if family in ('cargo', 'cargo_optimal', 'cargo_planning'):
        result = cargo(p)
        if family == 'cargo_planning' and p.get('goal_items', 3) > 3:
            result.update(cargo_manifests(p))
        return result
    if family in ('doubling_transfer', 'temporal_transfer'):
        return transfer_problem(p, family == 'doubling_transfer')
    if family in ('machine_records', 'machine_ambiguity'):
        return machine_problem(p, family == 'machine_ambiguity')
    if family == 'diagnostic_probe':
        return probe_problem(p)
    if family in ('route_partition', 'route_block_choice', 'disjoint_route_pairs'):
        return route_problem(p, family)
    if family == 'takeaway_policy':
        return strategy_problem(p)
    if family == 'boss_seal_duel':
        return seal_problem(p)
    if family == 'boss_probe_reserve':
        return probe_battle_problem(p)
    if family == 'parity_repair':
        return parity_problem(p)
    if family == 'heavy_coin_plan':
        return weighing_problem(p)
    if family == 'wall_fence':
        return wall_problem(p)
    if family == 'pair_weights':
        return legacy.solve(level)
    raise ValueError(family)


def check_progression(data):
    assert data["revision"] == "forest-design-4"
    levels = {level["id"]: level for level in data["levels"]}
    assert len(levels) == len(data["levels"]) == 18
    assert set(levels) == {f"FL{i:02}" for i in range(1, 19)}
    tiers = {tier: sum(x["tier"] == tier for x in levels.values())
             for tier in ("intro", "main", "side", "boss")}
    assert tiers == {"intro": 2, "main": 10, "side": 4, "boss": 2}, tiers
    done, order = set(), []
    while len(done) < len(levels):
        ready = [id for id, level in levels.items() if id not in done
                 and set(level["prerequisites_all"]) <= done]
        assert ready, ("unknown prerequisite or cycle", sorted(set(levels) - done))
        done.update(ready)
        order.extend(ready)
    for level in levels.values():
        assert len(level["hints"]) == 3 and all(level["hints"])
        thought = level["thinking_contract"]
        assert thought["insight"] and thought["shortcut_to_check"] and thought["required_evidence"]
        if level["tier"] != "side":
            assert all(levels[p]["tier"] != "side" for p in level["prerequisites_all"])
    rewards = [level["reward"] for level in levels.values()]
    assert len({reward["id"] for reward in rewards}) == 18
    assert all(isinstance(r[k], int) and r[k] >= 0
               for r in rewards for k in ("journey_exp", "camp_wood"))
    progression = data["progression"]
    for dependency in [*progression["recruit_at"].values(),
                       *progression["acheng_growth_requires_all"],
                       *filter(None, progression["skill_unlocks"].values())]:
        assert dependency in levels and levels[dependency]["tier"] != "side"
    main = [l for l in levels.values() if l["tier"] != "side"]
    main_xp = sum(l["reward"]["journey_exp"] for l in main)
    main_wood = sum(l["reward"]["camp_wood"] for l in main)
    buildings = progression["buildings"]
    assert len({b["id"] for b in buildings}) == len(buildings)
    assert all(b["requires"] in levels and levels[b["requires"]]["tier"] != "side"
               and isinstance(b["cost"], int) and b["cost"] > 0 for b in buildings)
    cost = sum(b["cost"] for b in buildings)
    assert progression["xp_thresholds"] == [0, 40, 100, 180, 280]
    assert main_xp == 300 and main_xp >= progression["xp_thresholds"][-1]
    assert main_wood == cost == 120
    assert sum(r["journey_exp"] for r in rewards) == 340
    assert sum(r["camp_wood"] for r in rewards) == 136
    return {"topological_order": order, "tier_counts": tiers,
            "mainline_exp": main_xp, "mainline_wood": main_wood,
            "all_buildings_cost": cost, "side_required_for_story": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write candidate-bound evidence JSON")
    args = parser.parse_args()
    source_bytes = SOURCE.read_bytes()
    data = json.loads(source_bytes)
    progression = check_progression(data)
    results = []
    for level in data["levels"]:
        actual = solve(level)
        assert level["expected"], (level["id"], "missing reference result")
        for key, expected in level["expected"].items():
            assert actual[key] == expected, (level["id"], key, actual[key], expected)
        results.append({"id": level["id"], "status": "PASS", "computed": actual})
    sources = [SOURCE, Path(__file__).resolve(), LEGACY]
    report = {"status": "PASS", "passed": len(results), "total": len(data["levels"]),
              "command": "python3 tests/verify_forest_design.py --output docs/production/math_verification.json",
              "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sources},
              "scope": "V2 ordinary levels and V3 boss mathematics, enemy-response/hidden-form policies with explicit no-undo versus refunded-replanning scopes, specified counterexamples, dependency DAG and economy. No Godot combat feel, runtime transcript validation or measured difficulty evidence.",
              "progression": progression, "results": results}
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("results", "source_sha256")},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()

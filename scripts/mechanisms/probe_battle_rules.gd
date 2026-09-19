extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")

static func fresh(params: Dictionary) -> Dictionary:
	return {"secret_form_id":params.forms.keys()[0],"seed_balance":params.seed_budget,"active_observations":[],"probe_count":0,"battle_phase":"probing","finisher":[],"won":false}

static func output(params: Dictionary, id: String, input_value: int) -> int:
	return int(Machine.evaluate(params.forms[id].operations,input_value).back())

static func candidates(params: Dictionary, state: Dictionary) -> Array:
	var result = []
	for id in params.forms:
		var fits = true
		for observation in state.active_observations:
			if output(params,id,int(observation[0])) != observation[1]: fits = false
		if fits: result.append(id)
	return result

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["secret_form_id","seed_balance","active_observations","probe_count","battle_phase","finisher","won"]): return false
	if not state.secret_form_id is String or not state.battle_phase is String: return false
	if not params.forms.has(state.secret_form_id) or not Numbers.integer(state.seed_balance,0,params.seed_budget) or not state.active_observations is Array or state.active_observations.size() > params.max_probes or not Numbers.integer(state.probe_count,0,params.max_probes) or not state.finisher is Array or not state.won is bool: return false
	if state.probe_count != state.active_observations.size(): return false
	var spent = 0; var replay = fresh(params); replay.secret_form_id = state.secret_form_id
	for observation in state.active_observations:
		if candidates(params,replay).size() == 1 or not observation is Array or observation.size() != 2 or observation[0] not in params.probe_inputs: return false
		if not Numbers.integer(observation[1],-100,200): return false
		if observation[1] != output(params,state.secret_form_id,int(observation[0])): return false
		spent += int(observation[0]); replay.active_observations.append(observation)
	var identified = candidates(params,state).size() == 1
	var phase = "identified" if identified else "probing"
	if not state.finisher.is_empty():
		if not identified or state.finisher.size() != 2 or state.finisher[0] not in params.finisher_inputs or state.finisher[1] != output(params,state.secret_form_id,int(state.finisher[0])): return false
		spent += int(state.finisher[0]); phase = "victory" if state.finisher[1] == params.target_response else "missed"
	if spent > params.seed_budget or state.seed_balance != params.seed_budget-spent or state.battle_phase != phase: return false
	return state.won == (phase == "victory")

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	if action.get("kind") == "probe":
		if state.battle_phase != "probing" or state.probe_count >= params.max_probes or action.get("value") not in params.probe_inputs or action.value > state.seed_balance: return {"accepted":false,"feedback":"侦察最多两次，且必须保留足够的现有种子。已辨明时请准备合击。"}
		var value = int(action.value); var echo = output(params,state.secret_form_id,value)
		next.seed_balance -= value; next.probe_count += 1; next.active_observations.append([value,echo])
		var count = candidates(params,next).size()
		if count == 1: next.battle_phase = "identified"
		return {"accepted":true,"state":next,"feedback":"投送%d颗，回响%d；还剩%d种可能，种子余%d颗。"%[value,echo,count,next.seed_balance]}
	if action.get("kind") == "finish":
		if state.battle_phase != "identified" or candidates(params,state).size() != 1: return {"accepted":false,"feedback":"先弄清树心的真身是哪一种，才能蓄力合击。"}
		if action.get("value") not in params.finisher_inputs or action.value > state.seed_balance: return {"accepted":false,"feedback":"合击需要2至8颗，也不能超过手里的种子；不够时可以撤销重选。"}
		var value = int(action.value); var echo = output(params,state.secret_form_id,value)
		next.seed_balance -= value; next.finisher = [value,echo]; next.won = echo == params.target_response
		next.battle_phase = "victory" if next.won else "missed"
		return {"accepted":true,"state":next,"feedback":"回响恰好20！雾壳化成新叶，森林迎回春天。" if next.won else "回响是%d，还不是20；对照上面的算式，撤销这次合击再试。"%echo}
	return {"accepted":false,"feedback":"未知树心动作。"}

static func complete(_params: Dictionary, state: Dictionary) -> bool:
	return state.won

static func guaranteed_probe(params: Dictionary, possibilities: Array, budget: int, remaining: int) -> int:
	if remaining <= 0: return -1
	for value in params.probe_inputs:
		if value > budget: continue
		var partitions = {}
		for id in possibilities:
			var echo = output(params,id,int(value))
			if not partitions.has(echo): partitions[echo] = []
			partitions[echo].append(id)
		var safe = true
		for group in partitions.values():
			if group.size() == 1:
				var cost = finisher_cost(params,group[0])
				safe = safe and cost > 0 and cost <= budget-value
			else: safe = safe and guaranteed_probe(params,group,budget-value,remaining-1) >= 0
		if safe: return int(value)
	return -1

static func finisher_cost(params: Dictionary, id: String) -> int:
	for value in params.finisher_inputs:
		if output(params,id,int(value)) == params.target_response: return int(value)
	return -1

static func hint(params: Dictionary, state: Dictionary) -> String:
	var possibilities = candidates(params,state)
	if state.battle_phase == "missed": return "先撤销这次合击，按已经看清的回声规律再算一遍；侦察到的信息会保留。"
	if possibilities.size() == 1:
		var cost = finisher_cost(params,possibilities[0])
		if cost > state.seed_balance: return "真身已经辨明，但剩下的种子不够合击。回退一步侦察，少花一点种子。"
		return "已辨明的回声方式，用%d颗可以得到20；当前库存足够。"%cost
	var value = guaranteed_probe(params,possibilities,int(state.seed_balance),int(params.max_probes-state.probe_count))
	if value < 0: return "现在的种子不够应付所有可能；可以撤销或重摆，用已经看到的回响重新安排。"
	return "对目前仍可能的形态，试探%d颗可以继续区分，并为每一种后续情况保留合击储备。"%value

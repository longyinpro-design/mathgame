extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")

static func fresh(params: Dictionary) -> Dictionary:
	var total = int(params.total)
	return {"initial":[total / 3,total / 3,total - 2 * (total / 3)],"trace":[],"reverse":[],"links":[]}

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["initial","trace","reverse","links"]): return false
	if not vector(state.initial,params.total,params.minimum): return false
	if not state.trace is Array or not state.reverse is Array or not state.links is Array: return false
	if state.reverse.size() not in [0,2] or state.links.size() not in [0,2]: return false
	for link in state.links:
		if not Numbers.integer(link,-1,2): return false
	for row in state.reverse:
		if not vector(row,params.total,0): return false
	if not state.trace.is_empty() and state.trace != trace(params,state.initial): return false
	return true

static func vector(value: Variant, total: int, minimum: int) -> bool:
	if not value is Array or value.size() != 3: return false
	var sum = 0
	for n in value:
		if not Numbers.integer(n,minimum,total): return false
		sum += int(n)
	return sum == total

static func trace(params: Dictionary, initial: Array) -> Array:
	var states = [initial.duplicate()]; var current = initial.duplicate()
	for move in params.moves:
		var amount = int(current[int(move[1])]) if move.size() == 2 else int(move[2])
		if current[int(move[0])] < amount: return []
		current = current.duplicate(); current[int(move[0])] -= amount; current[int(move[1])] += amount
		states.append(current)
	return states

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match action.get("kind"):
		"shift":
			if not Numbers.integer(action.get("from"),0,2) or not Numbers.integer(action.get("to"),0,2) or action.from == action.to: return {"accepted":false,"feedback":"选择不同的两座台。"}
			if next.initial[int(action.from)] <= params.minimum: return {"accepted":false,"feedback":"每座台至少保留一枚。"}
			next.initial[int(action.from)] -= 1; next.initial[int(action.to)] += 1; next.trace = []
		"try": next.trace = trace(params,next.initial)
		"reverse":
			if not action.get("value") is Array: return {"accepted":false,"feedback":"倒放板缺少状态卡。"}
			next.reverse = action.value.duplicate(true)
		"links": next.links = action.get("value",[]).duplicate(true)
		_: return {"accepted":false,"feedback":"未知借光动作。"}
	if not valid(params,next): return {"accepted":false,"feedback":"状态卡必须保持总数守恒。"}
	var feedback = "已摆放。"
	if action.kind == "try":
		feedback = "回响对上了！" if board_complete(params,next) else "回响尚不符合条件；观察哪一步数量不足或相等的时刻不对。"
	return {"accepted":true,"state":next,"feedback":feedback}

static func board_complete(params: Dictionary, state: Dictionary) -> bool:
	if state.trace.size() != params.moves.size()+1: return false
	if params.has("target"): return state.trace.back() == params.target
	for i in params.equal_after.size():
		var pair = params.equal_after[i]; var moment = state.trace[i+1]
		if moment[int(pair[0])] != moment[int(pair[1])]: return false
	return true

static func complete(params: Dictionary, state: Dictionary) -> bool:
	return board_complete(params,state)

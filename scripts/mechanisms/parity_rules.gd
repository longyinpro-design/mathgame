extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")

static func fresh(_params: Dictionary) -> Dictionary:
	return {"path":[],"repair":[],"classifications":[-1,-1,-1],"flip_loss":0,"endpoints":[],"tested":false}

static func path_valid(params: Dictionary, path: Variant, repair: bool) -> bool:
	if not path is Array or path.size() > params.steps: return false
	var location = int(params.start)
	for move in path:
		if move not in params.moves and (not repair or move not in params.repair_moves): return false
		location += int(move)
		if location < params.minimum or location > params.maximum: return false
	return true

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["path","repair","classifications","flip_loss","endpoints","tested"]): return false
	if not path_valid(params,state.path,false) or not path_valid(params,state.repair,true) or not state.classifications is Array or state.classifications.size() != 3 or not state.endpoints is Array or not state.tested is bool: return false
	for choice in state.classifications:
		if not Numbers.integer(choice,-1,2): return false
	var seen = []
	for point in state.endpoints:
		if not Numbers.integer(point,params.minimum,params.maximum) or point in seen: return false
		seen.append(point)
	return Numbers.integer(state.flip_loss,0,10)

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match action.get("kind"):
		"step":
			var field = "repair" if action.get("repair",false) else "path"
			var path: Array = next[field]+[action.get("value")]
			if not path_valid(params,path,field == "repair"): return {"accepted":false,"feedback":"每段恰好五步，不能走出0至10；原路只允许±2。"}
			next[field] = path
		"clear": next["repair" if action.get("repair",false) else "path"] = []
		"classify":
			if not Numbers.integer(action.get("index"),0,2) or not Numbers.integer(action.get("reason"),0,2): return {"accepted":false,"feedback":"把目标连到可达或不可达的具体原因。"}
			next.classifications[int(action.index)] = int(action.reason)
		"loss":
			if not Numbers.integer(action.get("value"),0,10): return {"accepted":false,"feedback":"填入反转一步导致的终点变化。"}
			next.flip_loss = int(action.value)
		"endpoint":
			if not Numbers.integer(action.get("value"),params.minimum,params.maximum): return {"accepted":false,"feedback":"终点在0至10之间。"}
			if action.value in next.endpoints: next.endpoints.erase(action.value)
			else: next.endpoints.append(int(action.value))
		"try": next.tested = true
		_: return {"accepted":false,"feedback":"未知石径操作。"}
	if action.kind != "try": next.tested = false
	var feedback = "轨迹已留下；比较奇偶和恰好五步这两条不同约束。"
	if action.kind == "try":
		if next.path.size() != params.steps or sum_moves(next.path) != 10:
			feedback = "原路还没走到10：需要恰好%d步、每步±2。"%params.steps
		elif next.repair.size() != params.steps or sum_moves(next.repair) != params.repair_target:
			feedback = "修路还没到9：保留原来的步数，只替换其中一步的长度。"
		else:
			var replacements = 0
			for step in next.repair:
				if step in params.repair_moves: replacements += 1
			if replacements != 1: feedback = "修路只能替换一步：现在有%d步换了长度。"%replacements
			else: feedback = "两条石径都走通了！"
	return {"accepted":true,"state":next,"feedback":feedback}

static func sum_moves(path: Array) -> int:
	var sum = 0
	for step in path: sum += int(step)
	return sum

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if not state.tested or state.path.size() != params.steps or sum_moves(state.path) != 10: return false
	if state.repair.size() != params.steps or sum_moves(state.repair) != params.repair_target: return false
	var replacements = 0
	for step in state.repair:
		if step in params.repair_moves: replacements += 1
	return replacements == 1

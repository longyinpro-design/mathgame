extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")
const OCCURRENCES = [0,1,1,2,0,2]

static func fresh(_params: Dictionary) -> Dictionary:
	return {"weights":[1,1,1],"bands":[-1,-1,-1,-1,-1,-1],"total":0,"tested":false,"weighed":[]}

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["weights","bands","total","tested"]): return false
	var weighed = state.get("weighed",[])
	if not weighed is Array or weighed.size() > 3: return false
	for pair_id in weighed:
		if pair_id not in ["ab","bc","ac"]: return false
		if weighed.count(pair_id) > 1: return false
	if not state.weights is Array or state.weights.size() != 3 or not state.bands is Array or state.bands.size() != 6 or not state.tested is bool: return false
	for weight in state.weights:
		if not Numbers.integer(weight,params.weight_min,params.weight_max): return false
	for band in state.bands:
		if not Numbers.integer(band,-1,1): return false
	return Numbers.integer(state.total,0,60)

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match action.get("kind"):
		"weight":
			if not Numbers.integer(action.get("index"),0,2) or not Numbers.integer(action.get("value"),params.weight_min,params.weight_max): return {"accepted":false,"feedback":"灯架重量须在范围内。"}
			next.weights[int(action.index)] = int(action.value); next.tested = false
		"weigh":
			var first = action.get("first"); var second = action.get("second")
			if not Numbers.integer(first,0,2) or not Numbers.integer(second,0,2) or first == second: return {"accepted":false,"feedback":"选两架不同的灯来合称。"}
			if not next.has("weighed"): next.weighed = []
			var pair_id = ("ab" if first+second == 1 else ("bc" if first+second == 3 else "ac"))
			var total = int(params.ab) if pair_id == "ab" else (int(params.bc) if pair_id == "bc" else int(params.ac))
			if pair_id not in next.weighed: next.weighed.append(pair_id)
			var light_name = {"ab":"A与B","bc":"B与C","ac":"A与C"}[pair_id]
			return {"accepted":true,"state":next,"feedback":"把%s架上合称台：光带卷起 %d 格，这就是它们的合重。"%[light_name,total]}
		"band":
			if not Numbers.integer(action.get("index"),0,5) or not Numbers.integer(action.get("copy"),0,1): return {"accepted":false,"feedback":"选择一张光带和它所属的一套灯架。"}
			next.bands[int(action.index)] = int(action.copy)
		"total":
			if not Numbers.integer(action.get("value"),0,60): return {"accepted":false,"feedback":"请摆出一套灯架的总重。"}
			next.total = int(action.value)
		"try": next.tested = true
		_: return {"accepted":false,"feedback":"未知灯架动作。"}
	return {"accepted":true,"state":next,"feedback":"三对合重都吻合，灯全亮了！" if board_complete(params,next) else "每次调整会影响两场合重；先合称几对，看看目标是多少。"}

static func board_complete(params: Dictionary, state: Dictionary) -> bool:
	var w: Array = state.weights
	return state.tested and w[0]+w[1] == params.ab and w[1]+w[2] == params.bc and w[0]+w[2] == params.ac

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if not board_complete(params,state): return false
	# Saves from before the weighing step existed have no field and stay completable.
	if state.has("weighed") and state.weighed.size() < 3: return false
	return true

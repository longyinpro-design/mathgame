extends RefCounted
const Base = preload("res://scripts/cargo/rules.gd")

static func fresh(params: Dictionary) -> Dictionary:
	var state = Base.fresh(); state.certificate = []
	if params.has("goal_items"):
		state.places = []
		for place in params.initial_places: state.places.append(int(place))
		state.weights = params.weights.duplicate()
		state.names = params.item_names.duplicate()
		state.goal_count = int(params.goal_items)
	return state

static func valid(params: Dictionary, state: Variant) -> bool:
	if not Base.valid(state) or not state.get("certificate") is Array: return false
	if not state.certificate.is_empty():
		if state.certificate.size() != 3: return false
		for value in state.certificate:
			if not Base.integer(value,0,6): return false
	var goal: int = params.get("goal_items",3)
	for basket in [1,2]:
		if state.places.count(basket) > params.get("max_items_per_basket",6): return false
		if Base.weight(state,basket) > params.get("max_basket_weight",15): return false
	if state.has("weights") and (not state.weights is Array or state.weights.size() != state.places.size()): return false
	if state.has("names") and not state.names is Array: return false
	if state.has("goal_count") and (not state.goal_count is int or int(state.goal_count) != goal): return false
	return true

static func can_move(params: Dictionary, state: Dictionary, item: int, target: int) -> bool:
	if not Base.can_move(state,item,target): return false
	var goal: int = params.get("goal_items",3)
	if params.get("lock_delivered",false) and item < goal and state.places[item] == 3: return false
	var next = Base.moved(state,item,target)
	return valid(params,next)

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match action.get("kind"):
		"move":
			if not Base.integer(action.get("item"),0,state.places.size()-1) or not Base.integer(action.get("target"),0,3) or not can_move(params,state,int(action.item),int(action.target)):
				return {"accepted":false,"feedback":"只能在靠站的篮子装卸；请检查容量、载重和到站退出规则。"}
			next = Base.moved(state,int(action.item),int(action.target))
		"travel":
			if Base.direction(state) == 0: return {"accepted":false,"feedback":"两侧相等，或重篮已经在下面；先调整载重。"}
			next = Base.travel(state)
		"certificate":
			if not action.get("value") is Array: return {"accepted":false,"feedback":"运输手记缺少比较卡。"}
			next.certificate = action.value.duplicate(true)
		_: return {"accepted":false,"feedback":"未知货运动作。"}
	if not valid(params,next): return {"accepted":false,"feedback":"运输手记中的数量不合法。"}
	var arrival = "到站的旅客和邮包已下篮。" if params.has("goal_items") else "到站的旅客已下篮。"
	return {"accepted":true,"state":next,"feedback":arrival if action.kind == "travel" else "摆放已记下。"}

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if not Base.delivered(state): return false
	if params.get("lock_delivered",false): return state.trips == 3
	if params.has("max_items_per_basket"): return state.trips == 2
	return true

static func hint(params: Dictionary, state: Dictionary) -> Dictionary:
	if Base.delivered(state): return {"kind":"replan"}
	var count: int = state.places.size()
	var queue = [{"state":state,"first":{}}]; var seen = {Base.layout_key(state):true}; var cursor = 0
	while cursor < queue.size():
		var entry: Dictionary = queue[cursor]; cursor += 1
		var current: Dictionary = entry.state
		var actions = []
		if Base.direction(current) != 0: actions.append({"kind":"travel"})
		for item in count:
			for target in range(4):
				if can_move(params,current,item,target): actions.append({"kind":"move","item":item,"target":target})
		for action in actions:
			var next: Dictionary = apply(params,current,action).state
			var first: Dictionary = action if entry.first.is_empty() else entry.first
			if Base.delivered(next): return first
			var key = Base.layout_key(next)
			if not seen.has(key): seen[key] = true; queue.append({"state":next,"first":first})
	return {"kind":"recover"}

extends RefCounted
# Locations: forest floor, left basket, right basket, treetop landing.
# The demo identity (six objects, three passengers) stays the default; FL11's
# seven-object manifest is carried by the state fields written at fresh().
const NAMES = ["阿橙", "小岚", "种子", "小配重", "中配重", "大配重"]
const WEIGHTS = [2, 3, 1, 2, 3, 4]
static func fresh() -> Dictionary:
	return {"places":[0,0,0,3,3,3], "left_low":true, "trips":0, "hints":0, "complete":false}
static func item_weights(s: Dictionary) -> Array:
	var value = s.get("weights", WEIGHTS)
	return value if value is Array else WEIGHTS
static func item_names(s: Dictionary) -> Array:
	var value = s.get("names", NAMES)
	return value if value is Array else NAMES
static func goal_count(s: Dictionary) -> int:
	var value = s.get("goal_count", 3)
	return value if value is int else 3
static func weight(s: Dictionary, basket: int) -> int:
	var weights = item_weights(s); var total = 0
	for i in weights.size():
		if s.places[i] == basket: total += weights[i]
	return total
static func landing(s: Dictionary, basket: int) -> int:
	return 0 if (basket == 1) == s.left_low else 3
static func can_move(s: Dictionary, item: int, target: int) -> bool:
	var count = item_weights(s).size()
	if s.complete or item < 0 or item >= count or target < 0 or target > 3: return false
	var source = int(s.places[item])
	if source == target: return false
	if source in [0,3] and target in [1,2]: return landing(s,target) == source
	if source in [1,2] and target in [0,3]: return landing(s,source) == target
	return false
static func moved(s: Dictionary, item: int, target: int) -> Dictionary:
	var next = s.duplicate(true)
	if can_move(s,item,target): next.places[item] = target
	return next
static func direction(s: Dictionary) -> int:
	var difference = weight(s,1)-weight(s,2)
	if difference == 0: return 0
	var target_low = difference > 0
	if target_low == s.left_low: return 0
	return 1 if target_low else -1
static func travel(s: Dictionary) -> Dictionary:
	var next = s.duplicate(true)
	if s.complete or direction(s) == 0: return next
	next.left_low = not s.left_low
	next.trips = mini(1000000,next.trips+1)
	# Passengers step onto the upper landing; weights stay in their baskets.
	var goal = goal_count(s)
	for i in goal:
		if next.places[i] in [1,2] and landing(next,int(next.places[i])) == 3: next.places[i] = 3
	next.complete = delivered(next)
	return next
static func delivered(s: Dictionary) -> bool:
	for i in goal_count(s):
		if s.places[i] != 3: return false
	return true
static func valid(s: Variant) -> bool:
	if not s is Dictionary or not s.has_all(["places","left_low","trips","hints","complete"]): return false
	if not s.left_low is bool or not s.complete is bool or not s.places is Array or s.places.size() != item_weights(s).size(): return false
	for n in s.places:
		if not integer(n,0,3): return false
	if not integer(s.trips,0,1000000) or not integer(s.hints,0,3): return false
	return s.complete == delivered(s)
static func integer(n: Variant, low: int, high: int) -> bool:
	return (n is int or n is float) and is_finite(n) and n >= low and n <= high and n == int(n)
static func normalize(s: Dictionary) -> Dictionary:
	var next = s.duplicate(true)
	for i in next.places.size(): next.places[i] = int(next.places[i])
	next.trips = int(next.trips); next.hints = int(next.hints)
	return next

# Asked-for hints search only this authored, finite mechanism; no AI or rule changes.
static func next_step(start: Dictionary) -> Dictionary:
	if start.complete: return {"kind":"done"}
	var count = item_weights(start).size()
	var queue = [{"state":start,"first":{}}]
	var visited = {layout_key(start):true}
	var cursor = 0
	while cursor < queue.size():
		var entry: Dictionary = queue[cursor]; cursor += 1
		var s: Dictionary = entry.state
		var actions: Array[Dictionary] = []
		if direction(s) != 0: actions.append({"kind":"travel"})
		for item in count:
			for loc in range(4):
				if can_move(s,item,loc): actions.append({"kind":"move","item":item,"target":loc})
		for action in actions:
			var next = travel(s) if action.kind == "travel" else moved(s,action.item,action.target)
			var first: Dictionary = action if entry.first.is_empty() else entry.first
			if next.complete: return first
			var key = layout_key(next)
			if not visited.has(key): visited[key] = true; queue.append({"state":next,"first":first})
	return {"kind":"recover"}
static func layout_key(s: Dictionary) -> String:
	return str(s.places)+str(s.left_low)

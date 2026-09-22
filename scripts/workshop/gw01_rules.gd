extends RefCounted
# GW01: one stock of 23 finished spindles, five configurable three/five-slot trays, one repair box.
const TOTAL = 23
const TRAYS = 5
const CAPACITIES = [3,5]
const STAGES = ["arrival", "approach", "ready", "puzzle", "delivery", "aftermath", "complete"]
const ANIMATIONS = ["approach", "delivery"]
const FIELDS = ["sample", "stage", "beat", "trays", "capacities", "box", "hint", "attempts"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw01-2", "stage":"arrival", "beat":0,
		"trays":[0,0,0,0,0], "capacities":[3,3,3,3,3], "box":0, "hint":0, "attempts":0}

static func stock(s: Dictionary) -> int:
	var amount = TOTAL - s.box
	for count in s.trays: amount -= count
	return amount

static func solved(s: Dictionary) -> bool:
	return s.trays == s.capacities and s.box >= 1 and s.box <= 2 and stock(s) == 0

static func shortfalls(s: Dictionary) -> Array:
	var result = []
	for i in range(TRAYS):
		if s.trays[i] != s.capacities[i]:
			result.append("第 %d 托有 %d 根，当前是 %d 槽衬板；每托都要装满。" % [i+1,s.trays[i],s.capacities[i]])
	if stock(s) > 0: result.append("地上还有 %d 根灯轴没有归位。" % stock(s))
	if s.box < 1: result.append("维修必须预留至少 1 根，盒子最多装 2 根。试着换一块衬板。")
	return result

static func move(s: Dictionary, target: int, amount: int) -> Dictionary:
	if s.stage != "puzzle" or target < 0 or target > TRAYS or amount == 0: return {}
	var held: int = s.box if target == TRAYS else s.trays[target]
	var limit = 2 if target == TRAYS else s.capacities[target]
	if held + amount < 0 or held + amount > limit or (amount > 0 and amount > stock(s)): return {}
	var n = s.duplicate(true)
	if target == TRAYS: n.box += amount
	else: n.trays[target] += amount
	return n

static func resize(s: Dictionary, target: int) -> Dictionary:
	if s.stage != "puzzle" or target < 0 or target >= TRAYS or s.trays[target] != 0: return {}
	var n = s.duplicate(true)
	n.capacities[target] = 5 if s.capacities[target] == 3 else 3
	return n

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has_all(["trays","capacities","box"]): return {}
	var n = s.duplicate(true)
	n.capacities = snapshot.capacities.duplicate(true)
	n.trays = snapshot.trays.duplicate(true); n.box = snapshot.box
	return n if validate(n) else {}

static func advance(s: Dictionary) -> Dictionary:
	var n = s.duplicate(true)
	match s.stage:
		"arrival":
			if s.beat < 2: n.beat += 1
			else: n.stage = "approach"
		"approach": n.stage = "ready"
		"ready": n.stage = "puzzle"
		"puzzle":
			if not solved(s): return {}
			n.attempts = mini(1000000,n.attempts+1); n.stage = "delivery"
		"delivery": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != "workshop-gw01-2" or v.stage not in STAGES: return false
	for key in ["beat","box","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.box < 0 or v.box > 2: return false
	if v.hint < 0 or v.hint > 4 or v.attempts < 0 or v.attempts > 1000000: return false
	if not v.trays is Array or v.trays.size() != TRAYS: return false
	if not v.capacities is Array or v.capacities.size() != TRAYS: return false
	for i in range(TRAYS):
		if not v.capacities[i] is int or v.capacities[i] not in CAPACITIES: return false
		if not v.trays[i] is int or v.trays[i] < 0 or v.trays[i] > v.capacities[i]: return false
	if stock(v) < 0: return false
	if v.stage in ["arrival","approach","ready"]:
		if v.capacities != [3,3,3,3,3] or stock(v) != TOTAL or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and (not solved(v) or v.attempts < 1): return false
	return true

extends RefCounted
# GW01: one stock of 23 finished spindles, five four-slot trays, one repair box.
const TOTAL = 23
const TRAYS = 5
const CAPACITY = 4
const STAGES = ["arrival", "approach", "ready", "puzzle", "delivery", "aftermath", "complete"]
const ANIMATIONS = ["approach", "delivery"]
const FIELDS = ["sample", "stage", "beat", "trays", "box", "hint", "attempts"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw01-1", "stage":"arrival", "beat":0,
		"trays":[0,0,0,0,0], "box":0, "hint":0, "attempts":0}

static func stock(s: Dictionary) -> int:
	var amount = TOTAL - s.box
	for count in s.trays: amount -= count
	return amount

static func solved(s: Dictionary) -> bool:
	return s.trays == [4,4,4,4,4] and s.box == 3 and stock(s) == 0

static func shortfalls(s: Dictionary) -> Array:
	var result = []
	for i in range(TRAYS):
		if s.trays[i] != CAPACITY:
			result.append("第 %d 托只有 %d 根；本班只接每托 4 根的满托。" % [i+1,s.trays[i]])
	if stock(s) > 0: result.append("地上还有 %d 根灯轴没有归位。" % stock(s))
	if s.box != 3: result.append("维修盒里放的是整托之外留下的灯轴，再核对一次。")
	return result

static func move(s: Dictionary, target: int, amount: int) -> Dictionary:
	if s.stage != "puzzle" or target < 0 or target > TRAYS or amount == 0: return {}
	var held: int = s.box if target == TRAYS else s.trays[target]
	var limit = TOTAL if target == TRAYS else CAPACITY
	if held + amount < 0 or held + amount > limit or (amount > 0 and amount > stock(s)): return {}
	var n = s.duplicate(true)
	if target == TRAYS: n.box += amount
	else: n.trays[target] += amount
	return n

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has_all(["trays","box"]): return {}
	var n = s.duplicate(true)
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
	if v.sample != "workshop-gw01-1" or v.stage not in STAGES: return false
	for key in ["beat","box","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.box < 0 or v.box > TOTAL: return false
	if v.hint < 0 or v.hint > 4 or v.attempts < 0 or v.attempts > 1000000: return false
	if not v.trays is Array or v.trays.size() != TRAYS: return false
	for count in v.trays:
		if not count is int or count < 0 or count > CAPACITY: return false
	if stock(v) < 0: return false
	if v.stage in ["arrival","approach","ready"]:
		if stock(v) != TOTAL or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and (not solved(v) or v.attempts < 1): return false
	return true

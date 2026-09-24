extends RefCounted
# Reconstruct a loading manifest from three receiver-doubling transfers.
const TOTAL = 24
const TRAYS = 3
const NAMES = ["甲", "乙", "丙"]
const STAGES = ["arrival", "approach", "ready", "puzzle", "trial", "delivery", "aftermath", "complete"]
const ANIMATIONS = ["approach", "delivery"]
const FIELDS = ["sample", "stage", "beat", "trays", "round", "hint", "attempts"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw01-3", "stage":"arrival", "beat":0,
		"trays":[0,0,0], "round":0, "hint":0, "attempts":0}

static func stock(s: Dictionary) -> int:
	var amount = TOTAL
	for count in s.trays: amount -= count
	return amount

# Both gifts are measured before the round, against the recipients' current counts.
static func transfer(trays: Array, donor: int) -> Array:
	if donor < 0 or donor >= TRAYS: return []
	var needed = 0
	for i in range(TRAYS):
		if i != donor: needed += trays[i]
	if trays[donor] < needed: return []
	var next = trays.duplicate()
	for i in range(TRAYS):
		if i != donor: next[i] *= 2
	next[donor] -= needed
	return next

static func after_rounds(trays: Array, rounds: int) -> Array:
	var current = trays.duplicate()
	for i in range(rounds):
		current = transfer(current,i)
		if current.is_empty(): return []
	return current

static func displayed(s: Dictionary) -> Array:
	return after_rounds(s.trays,s.round)

static func solved(s: Dictionary) -> bool:
	return stock(s) == 0 and after_rounds(s.trays,3) == [8,8,8]

static func shortfalls(s: Dictionary) -> Array:
	if stock(s) > 0: return ["先把 24 根都摆进三托，还原出发时的数量；现在还剩 %d 根。"%stock(s)]
	var current = s.trays.duplicate()
	for i in range(3):
		var next = transfer(current,i)
		if next.is_empty():
			return ["第 %d 轮：%s托只有 %d 根，却要给出 %d 根。回到起始摆法，再想一想。"%[i+1,NAMES[i],current[i],TOTAL-current[i]]]
		current = next
	if current != [8,8,8]: return ["三轮后是 %d、%d、%d 根，记录却是各 8 根。试着从最后一轮往回想。"%current]
	return []

static func move(s: Dictionary, target: int, amount: int) -> Dictionary:
	if s.stage != "puzzle" or target < 0 or target >= TRAYS or amount == 0: return {}
	if s.trays[target]+amount < 0 or (amount > 0 and amount > stock(s)): return {}
	var n = s.duplicate(true); n.trays[target] += amount
	return n

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("trays"): return {}
	var n = s.duplicate(true); n.trays = snapshot.trays.duplicate(true)
	return n if validate(n) else {}

static func back_to_plan(s: Dictionary) -> Dictionary:
	if s.stage != "trial": return {}
	var n = s.duplicate(true); n.stage = "puzzle"; n.round = 0
	return n

static func advance(s: Dictionary) -> Dictionary:
	var n = s.duplicate(true)
	match s.stage:
		"arrival":
			if s.beat < 2: n.beat += 1
			else: n.stage = "approach"
		"approach": n.stage = "ready"
		"ready": n.stage = "puzzle"
		"puzzle":
			if stock(s) != 0: return {}
			n.attempts = mini(1000000,n.attempts+1); n.stage = "trial"
		"trial":
			if s.round < 3:
				if transfer(displayed(s),s.round).is_empty(): return back_to_plan(s)
				n.round += 1
			elif solved(s): n.stage = "delivery"
			else: return back_to_plan(s)
		"delivery": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != "workshop-gw01-3" or v.stage not in STAGES: return false
	for key in ["beat","round","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.round < 0 or v.round > 3: return false
	if v.hint < 0 or v.hint > 4 or v.attempts < 0 or v.attempts > 1000000: return false
	if not v.trays is Array or v.trays.size() != TRAYS: return false
	for count in v.trays:
		if not count is int or count < 0 or count > TOTAL: return false
	if stock(v) < 0: return false
	if v.stage in ["arrival","approach","ready"]:
		if stock(v) != TOTAL or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","trial","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["arrival","approach","ready","puzzle"] and v.round != 0: return false
	if v.stage == "trial":
		if stock(v) != 0 or v.attempts < 1 or displayed(v).is_empty(): return false
	if v.stage in ["delivery","aftermath","complete"]:
		if v.round != 3 or not solved(v) or v.attempts < 1: return false
	return true

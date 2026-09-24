extends RefCounted
# GW06 装配间「产量一样，工时不同」：小模每炉 3 枚、大模每炉 5 枚，每炉 1 拍，换模另用 1 拍。
# 首次装模免费，所以第一炉不占换模拍；同类的炉次排在一起才只换一次模。
# 产量与拍数都按工单现算，画面不替玩家记数。
const SMALL = 3
const LARGE = 5
const MOULDS = [SMALL,LARGE]
const MAX_BATCHES = 10
const NEED = 31
const DEADLINE = 8
const STAGES = ["arrival","approach","ready","puzzle","trial","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","trial","delivery"]
const FIELDS = ["sample","stage","beat","order","hint","attempts"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw06-1","stage":"arrival","beat":0,"order":[],"hint":0,"attempts":0}

static func legal_order(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_BATCHES: return false
	for mould in value:
		if not mould is int or not MOULDS.has(mould): return false
	return true

static func output(s: Dictionary) -> int:
	var total = 0
	for mould in s.order: total += mould
	return total

# 每炉占一拍；相邻两炉不同模时，先插一拍换模。首次装模免费。
static func schedule(s: Dictionary) -> Dictionary:
	var batches = []; var changes = []; var at = 0
	for index in range(s.order.size()):
		var mould = s.order[index]
		if index > 0 and s.order[index-1] != mould:
			changes.append({"start":at,"end":at+1}); at += 1
		batches.append({"mould":mould,"start":at,"end":at+1}); at += 1
	return {"batches":batches,"changes":changes,"makespan":at}

static func firing(s: Dictionary) -> int: return s.order.size()
static func changes_count(s: Dictionary) -> int: return schedule(s).changes.size()
static func makespan(s: Dictionary) -> int: return schedule(s).makespan
static func ready(s: Dictionary) -> bool: return not s.order.is_empty()

static func solved(s: Dictionary) -> bool:
	return ready(s) and output(s) == NEED and makespan(s) <= DEADLINE

# 只说明真实违反的条件：工单空着、产量不对，或者这套排法要到第几拍才做完。
static func shortfalls(s: Dictionary) -> Array:
	if not ready(s):
		return ["工单上还没有炉次：先排几炉再试运行。"]
	var produced = output(s)
	if produced != NEED:
		if produced < NEED:
			return ["这套排法只出 %d 枚，离 %d 枚还差 %d 枚。"%[produced,NEED,NEED-produced]]
		return ["这套排法出 %d 枚，比 %d 枚多了 %d 枚。"%[produced,NEED,produced-NEED]]
	if makespan(s) > DEADLINE:
		return ["这套排法到第 %d 拍才做完，赶不上第 %d 拍结束。"%[makespan(s),DEADLINE]]
	return []

static func place(s: Dictionary, mould: int) -> Dictionary:
	if s.stage != "puzzle" or not MOULDS.has(mould) or s.order.size() >= MAX_BATCHES: return {}
	var n = s.duplicate(true); n.order.append(mould)
	return n if validate(n) else {}

static func remove_at(s: Dictionary, index: int) -> Dictionary:
	if s.stage != "puzzle" or index < 0 or index >= s.order.size(): return {}
	var n = s.duplicate(true); n.order.remove_at(index)
	return n if validate(n) else {}

static func clear_order(s: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or s.order.is_empty(): return {}
	var n = s.duplicate(true); n.order = []
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("order"): return {}
	var n = s.duplicate(true); n.order = snapshot.order.duplicate()
	return n if validate(n) else {}

static func back_to_plan(s: Dictionary) -> Dictionary:
	if s.stage != "trial": return {}
	var n = s.duplicate(true); n.stage = "puzzle"
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
			if not ready(s): return {}
			n.attempts = mini(1000000,n.attempts+1); n.stage = "trial"
		"trial":
			if solved(s): n.stage = "delivery"
			else: n.stage = "puzzle"
		"delivery": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != "workshop-gw06-1" or v.stage not in STAGES: return false
	for key in ["beat","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.attempts < 0 or v.attempts > 1000000: return false
	if not legal_order(v.order): return false
	if v.stage in ["arrival","approach","ready"]:
		if not v.order.is_empty() or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","trial","delivery","complete"] and v.beat != 2: return false
	if v.stage == "trial":
		if not ready(v) or v.attempts < 1: return false
	if v.stage in ["delivery","aftermath","complete"]:
		if not solved(v) or v.attempts < 1: return false
	return true

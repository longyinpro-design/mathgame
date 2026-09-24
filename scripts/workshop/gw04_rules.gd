extends RefCounted
# GW04 错拍码头「两班船，都要赶上」：小车第 4、8、12、16 拍到，每次接走一托；
# 吊台原在第 2、8、14 拍到（周期 6 拍），开工前可以整体延后 0、1 或 2 拍。
# GW03 之后余下的两托在新班次第 0 拍已经备好，必须在第 16 拍结束前通过两次真实相遇送完。
# 相遇表由延后量现算，画面不另存时刻表。
const HORIZON = 16
const CARTS = [4,8,12,16]
const DELAYS = [0,1,2]
const STAGES = ["arrival","approach","ready","puzzle","trial","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","trial","delivery"]
const FIELDS = ["sample","stage","beat","delay","picks","hint","attempts"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw04-1","stage":"arrival","beat":0,"delay":0,"picks":[],"hint":0,"attempts":0}

static func cart_at(t: int) -> bool: return CARTS.has(t)

static func lift_times(delay: int) -> Array:
	var out = []; var t = 2+delay
	while t <= HORIZON: out.append(t); t += 6
	return out

# 只有吊台和小车同时到达的那一拍才接得走一托。本关没有放行灯，换成了独立直通轨。
static func meetings(delay: int) -> Array:
	var out = []
	for t in lift_times(delay):
		if cart_at(t): out.append(t)
	return out

static func solved(s: Dictionary) -> bool:
	return shortfalls(s).is_empty()

# 只说明真实违反的条件：这一档延后够不够碰上两次，以及哪一次没碰上。
static func shortfalls(s: Dictionary) -> Array:
	var meets = meetings(s.delay)
	if meets.size() < 2:
		return ["延后 %d 拍时，两机在 1～16 拍里只碰上 %d 次，送不完两托。"%[s.delay,meets.size()]]
	if s.picks.size() != 2:
		return ["要在第 16 拍结束前送完两托：现在只选了 %d 次交接。"%s.picks.size()]
	for tick in s.picks:
		if not meets.has(tick):
			return ["第 %d 拍吊台和小车没有相遇，交接不成。"%tick]
	return []

# 开工前才调得了起点：换档就把已经选的交接时刻清掉，免得留下对不上新时刻表的旧选择。
static func set_delay(s: Dictionary, delay: int) -> Dictionary:
	if s.stage != "puzzle" or not DELAYS.has(delay) or delay == s.delay: return {}
	var n = s.duplicate(true); n.delay = delay; n.picks = []
	return n if validate(n) else {}

# 任意 1～16 拍都能选：选到碰不上的那一拍由提交时的说明来指出。
static func toggle_pick(s: Dictionary, tick: int) -> Dictionary:
	if s.stage != "puzzle" or tick < 1 or tick > HORIZON: return {}
	var n = s.duplicate(true)
	if n.picks.has(tick): n.picks.erase(tick)
	else:
		if n.picks.size() >= 2: return {}
		n.picks.append(tick); n.picks.sort()
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("delay") or not snapshot.has("picks"): return {}
	var n = s.duplicate(true); n.delay = snapshot.delay; n.picks = snapshot.picks.duplicate()
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
			if s.picks.size() != 2: return {}
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

static func legal_picks(value: Variant) -> bool:
	if not value is Array or value.size() > 2: return false
	var seen = {}
	for tick in value:
		if not tick is int or tick < 1 or tick > HORIZON: return false
		if seen.has(tick): return false
		seen[tick] = true
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != "workshop-gw04-1" or v.stage not in STAGES: return false
	for key in ["beat","delay","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.attempts < 0 or v.attempts > 1000000: return false
	if not DELAYS.has(v.delay) or not legal_picks(v.picks): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.delay != 0 or not v.picks.is_empty() or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","trial","delivery","complete"] and v.beat != 2: return false
	if v.stage == "trial":
		if v.picks.size() != 2 or v.attempts < 1: return false
	if v.stage in ["delivery","aftermath","complete"]:
		if not solved(v) or v.attempts < 1: return false
	return true

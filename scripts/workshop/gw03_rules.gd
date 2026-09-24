extends RefCounted
# GW03 错拍码头「相遇了，还不能交接」：吊台每 3 拍到一次、小车每 4 拍、放行灯每 5 拍亮一次，
# 只有三者同一拍成立才接得上货。1～40 拍里只有第 23 拍同时成立。
# 三条节拍表与「看过哪几拍」都由这里算；画面不另存事件表，改拍号不会留下旧标记。
const HORIZON = 40
# 运行一拍时，把这一拍前后各两拍一起摊开：设计说的是「选定时刻附近的实际事件」，
# 41 格逐个点一遍太碎，±2 的窗口既保住了「必须真的运行过才看得到」，也让人跑得动。
const REVEAL = 2
const TRACKS = ["lift","cart","lamp"]
const TRACK_NAMES = ["吊台","小车","放行灯"]
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","probe","watched","hint"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw03-1","stage":"arrival","beat":0,"probe":0,"watched":[],"hint":0}

static func lift_at(t: int) -> bool: return t >= 2 and (t-2)%3 == 0
static func cart_at(t: int) -> bool: return t >= 3 and (t-3)%4 == 0
static func lamp_at(t: int) -> bool: return t >= 3 and (t-3)%5 == 0

static func arrives(track: int, t: int) -> bool:
	match track:
		0: return lift_at(t)
		1: return cart_at(t)
		2: return lamp_at(t)
	return false

static func handover_at(t: int) -> bool:
	return lift_at(t) and cart_at(t) and lamp_at(t)

# 只列到 HORIZON 为止；节拍表本身是无限的，这里给出的是本关看得见的一段。
static func arrivals(track: int) -> Array:
	var out = []
	for t in range(1,HORIZON+1):
		if arrives(track,t): out.append(t)
	return out

static func meetings() -> Array:
	var out = []
	for t in range(1,HORIZON+1):
		if handover_at(t): out.append(t)
	return out

static func earliest() -> int:
	var ticks = meetings()
	return ticks[0] if not ticks.is_empty() else -1

static func solved(s: Dictionary) -> bool:
	return s.watched.has(s.probe) and s.probe == earliest()

# 只说明真实违反的条件：哪一条没成立，或者更早的哪一拍已经成立。
static func shortfalls(s: Dictionary) -> Array:
	if not s.watched.has(s.probe):
		return ["第 %d 拍还没运行过：先跑一遍，看看那一拍到底发生了什么。"%s.probe]
	if not handover_at(s.probe):
		var missing = []
		if not lift_at(s.probe): missing.append("吊台没到")
		if not cart_at(s.probe): missing.append("小车没到")
		if not lamp_at(s.probe): missing.append("放行灯没亮")
		return ["第 %d 拍还不能交接：%s。"%[s.probe,"、".join(missing)]]
	if s.probe > earliest():
		return ["第 %d 拍三者确实同时，可是第 %d 拍更早，也已经同时成立。"%[s.probe,earliest()]]
	return []

# 把拍号移到某一拍并记下「这一拍附近看过了」。看过的记录是唯一的证据来源。
static func reveal_window(tick: int) -> Array:
	var out = []
	for t in range(maxi(0,tick-REVEAL),mini(HORIZON,tick+REVEAL)+1): out.append(t)
	return out

static func watch(s: Dictionary, tick: int) -> Dictionary:
	if s.stage != "puzzle" or tick < 0 or tick > HORIZON: return {}
	var n = s.duplicate(true); n.probe = tick
	for t in reveal_window(tick):
		if not n.watched.has(t): n.watched.append(t)
	n.watched.sort()
	return n if validate(n) else {}

static func move_probe(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle": return {}
	var tick = clampi(s.probe+delta,0,HORIZON)
	if tick == s.probe: return {}
	var n = s.duplicate(true); n.probe = tick
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("probe") or not snapshot.has("watched"): return {}
	var n = s.duplicate(true); n.probe = snapshot.probe; n.watched = snapshot.watched.duplicate()
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
			if not shortfalls(s).is_empty(): return {}
			n.stage = "delivery"
		"delivery": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

static func legal_watched(value: Variant) -> bool:
	if not value is Array or value.size() > HORIZON+1: return false
	var seen = {}
	for tick in value:
		if not tick is int or tick < 0 or tick > HORIZON: return false
		if seen.has(tick): return false
		seen[tick] = true
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != "workshop-gw03-1" or v.stage not in STAGES: return false
	for key in ["beat","probe","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.probe < 0 or v.probe > HORIZON: return false
	if not legal_watched(v.watched): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.probe != 0 or not v.watched.is_empty() or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	# 当前拍可以不看过（刚进来就停在第 0 拍）；能不能提交由 solved() 判定。
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

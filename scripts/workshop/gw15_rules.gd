extends RefCounted
# GW15 装配间「最早的一次观察」：机器周期可能是 3、4、5 拍之一，开局 0 件，
# 第一件在第一个周期结束时出现（第 p 拍出第 1 件、第 2p 拍出第 2 件……）。
# 机器身份开局固定：fresh() 定下 4 拍并写进存档，重试与重载都不重抽。
# 出料窗只能开一次，要在第 1～12 拍里选最早的一个时刻，使三种周期在那里的累计数互不相同。
# 三份累计数、可区分时刻、开窗读数与判定全部由这里现算，画面不另存数量表。
const SAMPLE = "workshop-gw15-1"
const PERIODS = [3,4,5]
const PERIOD_MIN = 3
const PERIOD_MAX = 5
# 固定的隐藏身份：这台机器实际每 4 拍出一件。
const HIDDEN = 4
const TIME_MIN = 1
const TIME_MAX = 12
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","period","observe","opened","assigned","tried","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"period":HIDDEN,
		"observe":0,"opened":false,"assigned":0,"tried":[],"hint":0}

# 三种周期在第 t 拍各自累计多少件：第 p 拍出第 1 件，之后每 p 拍再出一件。
static func counts(t: int) -> Array:
	var out = []
	for period in PERIODS: out.append(t/period)
	return out

# 这一拍的三份累计数摊成一句话，画面与判定共用。
static func count_text(t: int) -> String:
	var parts = []
	var values = counts(t)
	for i in range(PERIODS.size()): parts.append("%d 拍 %d 件"%[PERIODS[i],values[i]])
	return " · ".join(parts)

# 三份数量只报数：2、2、1。
static func counts_text(t: int) -> String:
	var parts = []
	for value in counts(t): parts.append(str(value))
	return "、".join(parts)

# 只有三份数量互不相同，一次观察才能确定周期；1～8 拍每次都至少两份相同。
static func distinguishing(t: int) -> bool:
	if t < TIME_MIN or t > TIME_MAX: return false
	var values = counts(t)
	return values[0] != values[1] and values[1] != values[2] and values[0] != values[2]

static func distinguishing_times() -> Array:
	var out = []
	for t in range(TIME_MIN,TIME_MAX+1):
		if distinguishing(t): out.append(t)
	return out

# 最早能分清三种机器的观察时刻：本题是第 9 拍（第 12 拍也行，但不是最早）。
static func earliest() -> int:
	var times = distinguishing_times()
	return times[0] if not times.is_empty() else -1

# 三份里哪几份撞在一起：只说明真实的混淆，不透露机器身份。
static func collision_note(t: int) -> String:
	var values = counts(t)
	var groups = {}
	for i in range(PERIODS.size()):
		var key = str(values[i])
		if not groups.has(key): groups[key] = []
		groups[key].append(PERIODS[i])
	var parts = []
	for key in groups:
		if groups[key].size() < 2: continue
		var names = []
		for period in groups[key]: names.append("%d 拍"%period)
		parts.append("%s都是 %s 件"%[("和 " if names.size() == 2 else "、").join(names),key])
	return "；".join(parts)

# 开窗实际看到的累计数：隐藏周期到这一拍为止出了几件。
static func observed(s: Dictionary) -> int:
	if s.observe < TIME_MIN or s.observe > TIME_MAX: return 0
	return s.observe/s.period

# 开窗看到 count 件时对应哪个周期：可区分的时刻只会有一个答案。
static func period_for(t: int, count: int) -> int:
	for period in PERIODS:
		if t/period == count: return period
	return 0

# 通过要同时成立：真的开过窗、这一拍三份数量互不相同、它是最早的可区分时刻、周期牌与实际身份一致。
static func solved(s: Dictionary) -> bool:
	return s.opened and distinguishing(s.observe) and s.observe == earliest() \
		and s.assigned == s.period

# 只说明真实违反的条件：还没锁时刻、还没开窗、三份撞在哪、不是最早、牌挂错了。
static func shortfalls(s: Dictionary) -> Array:
	if s.observe < TIME_MIN or s.observe > TIME_MAX:
		return ["先从第 1～12 拍里锁定一个观察时刻。"]
	if not s.opened:
		return ["第 %d 拍还没开窗：先打开出料窗，看这一拍实际累计多少件。"%s.observe]
	if not distinguishing(s.observe):
		return ["第 %d 拍是 %s：%s，分不清周期。"%[
			s.observe,counts_text(s.observe),collision_note(s.observe)]]
	if s.observe > earliest():
		return ["第 %d 拍的三份数量确实互不相同，可第 %d 拍更早，也已经能分清三种机器。"%[s.observe,earliest()]]
	if s.assigned == 0:
		return ["第 %d 拍已经开窗：累计 %d 件。还没挂周期牌。"%[s.observe,observed(s)]]
	if s.assigned != s.period:
		return ["第 %d 拍开窗看到累计 %d 件，对应的是 %d 拍；挂的是 %d 拍。"%[
			s.observe,observed(s),s.period,s.assigned]]
	return []

# 锁一个观察时刻：每锁过的时刻都记进比较表，重复锁同一拍不留第二条。
static func select_time(s: Dictionary, t: int) -> Dictionary:
	if s.stage != "puzzle" or s.opened or t < TIME_MIN or t > TIME_MAX or t == s.observe: return {}
	var n = s.duplicate(true); n.observe = t
	if not n.tried.has(t):
		n.tried.append(t); n.tried.sort()
	return n if validate(n) else {}

# 还没锁时刻时，左右一步先落在第 1 拍上；之后在 1～12 之间移动。
static func move_time(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle" or s.opened: return {}
	var current = s.observe if s.observe >= TIME_MIN else TIME_MIN-1
	return select_time(s,clampi(current+delta,TIME_MIN,TIME_MAX))

# 开窗：这一下就是玩家花掉的那一次观察，时刻从此锁死，只能重摆后再选。
static func open_window(s: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or s.opened or s.observe < TIME_MIN or s.observe > TIME_MAX: return {}
	var n = s.duplicate(true); n.opened = true
	return n if validate(n) else {}

# 挂周期牌：开窗之后才能挂，可以改挂，改挂不留旧牌。
static func hang(s: Dictionary, period: int) -> Dictionary:
	if s.stage != "puzzle" or not s.opened or not PERIODS.has(period) or period == s.assigned: return {}
	var n = s.duplicate(true); n.assigned = period
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("observe") or not snapshot.has("opened") \
		or not snapshot.has("assigned") or not snapshot.has("tried"): return {}
	var n = s.duplicate(true)
	n.observe = snapshot.observe
	n.opened = snapshot.opened
	n.assigned = snapshot.assigned
	n.tried = snapshot.tried.duplicate()
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
			n.stage = "delivery"
		"delivery": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

# 比较过的时刻：从小到大、不重复；越界或重复都算损坏。
static func legal_tried(value: Variant) -> bool:
	if not value is Array or value.size() > TIME_MAX-TIME_MIN+1: return false
	var last = 0
	for t in value:
		if not t is int or t < TIME_MIN or t > TIME_MAX: return false
		if t <= last: return false
		last = t
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","period","observe","assigned","hint"]:
		if not v[key] is int: return false
	if not v.opened is bool: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if not PERIODS.has(v.period): return false
	if v.observe != 0 and (v.observe < TIME_MIN or v.observe > TIME_MAX): return false
	if v.assigned != 0 and not PERIODS.has(v.assigned): return false
	if v.opened and v.observe == 0: return false
	if v.assigned != 0 and not v.opened: return false
	if not legal_tried(v.tried): return false
	if v.observe == 0 and not v.tried.is_empty(): return false
	if v.observe != 0 and not v.tried.has(v.observe): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.observe != 0 or v.opened or v.assigned != 0 or not v.tried.is_empty() or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

extends RefCounted
# GW17 总机船坞「巡轨兽 · 空出第一拍」：四辆工具车共用一段承重轨道，一次一辆，开工后不能中断。
# 第 0 拍开始规划，全部最晚第 9 拍驶离，另各有独立期限：
# 最早可发 A0 B1 C3 D6；占轨 A3 B2 C1 D2；最晚驶离 A≤7 B≤4 C≤5 D≤9。
# 总占轨 8 拍、台面 9 拍，空出的那一拍不是额外口令，是期限逼出来的：
# 唯一整拍计划是等 0–1、B 1–3、C 3–4、A 4–7、D 7–9。
# 玩家给每辆车排开工拍；巡轨兽按开工拍逐段放行，逐辆检查上轨许可、轨道占用与最晚驶离，
# 第一次说不通就念出真实原因，不替玩家填中间量。
const SAMPLE = "workshop-gw17-1"
const ITEMS = ["A","B","C","D"]
const COUNT = 4
const DURATIONS = {"A":3,"B":2,"C":1,"D":2}
const RELEASES = {"A":0,"B":1,"C":3,"D":6}
const DEADLINES = {"A":7,"B":4,"C":5,"D":9}
const WORK = 8
const HORIZON = 9
const START_MAX = 9
# 开局草稿就是「A 先走、其余依次尽早」：第一次提交就能听见 B 被卡到第 5 拍、超过最晚 4 拍。
const DEFAULT_STARTS = [0,3,5,6]
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","starts","order","hint"]

static func fresh() -> Dictionary:
	var starts: Array = DEFAULT_STARTS.duplicate()
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"starts":starts,
		"order":sequence(starts),"hint":0}

static func start_of(s: Dictionary, id: String) -> int:
	return s.starts[ITEMS.find(id)]

static func finish_of(s: Dictionary, id: String) -> int:
	return start_of(s,id)+DURATIONS[id]

# 放行顺序：开工拍从早到晚；同一拍按 A、B、C、D 定，判定与画面都只看这一份。
static func sequence(starts: Array) -> Array:
	var ids: Array = []
	var taken: Array = []
	for _slot in range(COUNT):
		var best = -1
		for index in range(COUNT):
			if taken.has(index): continue
			if best < 0 or starts[index] < starts[best]: best = index
		taken.append(best)
		ids.append(ITEMS[best])
	return ids

# 四辆车的占轨区间：全部按当前开工拍现算，画面不另存一份会走样的表。
static func plan(s: Dictionary) -> Array:
	var rows: Array = []
	for index in range(COUNT):
		var id = ITEMS[index]
		rows.append({"item":id,"start":s.starts[index],"end":s.starts[index]+DURATIONS[id]})
	return rows

# 某一拍轨上有谁：画面用它画共用轨道，判定仍走 problems() 的逐辆检查。
static func holders(s: Dictionary, tick: int) -> Array:
	var out: Array = []
	for index in range(COUNT):
		if s.starts[index] <= tick and tick < s.starts[index]+DURATIONS[ITEMS[index]]:
			out.append(ITEMS[index])
	return out

# 逐段放行时，这辆车和排在它前面的车是否抢同一拍；返回第一处重叠，没有就返回空。
static func collision(s: Dictionary, index: int) -> Dictionary:
	if index < 0 or index >= COUNT: return {}
	var id = s.order[index]
	var start = start_of(s,id)
	var finish = start+DURATIONS[id]
	for earlier in range(index):
		var other = s.order[earlier]
		var other_start = start_of(s,other)
		var other_finish = other_start+DURATIONS[other]
		var tick = maxi(start,other_start)
		if tick < mini(finish,other_finish):
			return {"tick":tick,"other":other,"other_start":other_start,"other_finish":other_finish}
	return {}

# 逐段放行：上轨许可、轨道占用、最晚驶离，按放行顺序说第一处真实违反的条件。
static func problems(s: Dictionary) -> Array:
	var out: Array = []
	for index in range(COUNT):
		var id = s.order[index]
		var start = start_of(s,id)
		if start < RELEASES[id]:
			out.append("%s 第 %d 拍才准上轨，第 %d 拍还发不了。"%[id,RELEASES[id],start])
		var hit = collision(s,index)
		if not hit.is_empty():
			out.append("第 %d 拍轨上还压着：%s 的 %d–%d 还没走完，%s 就要发。"%[
				hit.tick,hit.other,hit.other_start,hit.other_finish,id])
		if start+DURATIONS[id] > DEADLINES[id]:
			out.append("%s 到第 %d 拍才驶离，超过最晚 %d 拍。"%[id,start+DURATIONS[id],DEADLINES[id]])
	return out

static func solved(s: Dictionary) -> bool:
	return problems(s).is_empty()

static func shortfalls(s: Dictionary) -> Array:
	return problems(s)

static func legal_starts(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	for start in value:
		if not start is int or start < 0 or start > START_MAX: return false
	return true

static func legal_order(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	var seen = {}
	for id in value:
		if not id is String or not ITEMS.has(id): return false
		if seen.has(id): return false
		seen[id] = true
	return true

# 改某一辆车的开工拍：放行顺序跟着重算，越界、非整数与规划中的状态一律不改。
static func set_start(s: Dictionary, index: int, value: int) -> Dictionary:
	if s.stage != "puzzle" or index < 0 or index >= COUNT: return {}
	if not value is int or value < 0 or value > START_MAX or value == s.starts[index]: return {}
	var n = s.duplicate(true)
	n.starts[index] = value
	n.order = sequence(n.starts)
	return n if validate(n) else {}

static func nudge(s: Dictionary, index: int, delta: int) -> Dictionary:
	if index < 0 or index >= COUNT: return {}
	return set_start(s,index,s.starts[index]+delta)

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("starts") or not snapshot.has("order"): return {}
	var n = s.duplicate(true)
	n.starts = snapshot.starts.duplicate()
	n.order = snapshot.order.duplicate()
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

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if not legal_starts(v.starts) or not legal_order(v.order): return false
	if v.order != sequence(v.starts): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.starts != DEFAULT_STARTS or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

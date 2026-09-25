extends RefCounted
# GW10 装配间「最急的那单，为什么不能先开」：一张维修台一次一单，开工后不能中断。
# A、B、D 第 0 拍就绪，C 第 1 拍才送到；用时 A2、B3、C1、D2，四单最晚第 8 拍完成，
# 另各有自己的期限：A≤5、B≤8、C≤3、D≤6。总工作量正好 8 拍，中间没有空等的余地。
# 玩家把每单排到某一拍开工；验收顺序由开工拍自然定出（同拍时按 A、B、C、D 排），
# 逐单检查到料、撞台与逾期，只说真实违反的那一条，不替玩家填中间量。
const SAMPLE = "workshop-gw10-1"
const ITEMS = ["A","B","C","D"]
const COUNT = 4
const DURATIONS = {"A":2,"B":3,"C":1,"D":2}
const RELEASES = {"A":0,"B":0,"C":1,"D":0}
const DEADLINES = {"A":5,"B":8,"C":3,"D":6}
const WORK = 8
const HORIZON = 8
const START_MAX = 8
# 开局草稿把最急的 C 排在第 0 拍：它第 1 拍才送到，先按一下验收就能听见真实原因。
const DEFAULT_STARTS = [1,5,0,3]
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

# 验收顺序：开工拍从早到晚；同一拍按 A、B、C、D 定，判定与画面都只看这一份。
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

# 四单的占台区间：全部按当前开工拍现算，画面不另存一份会走样的表。
static func plan(s: Dictionary) -> Array:
	var rows: Array = []
	for index in range(COUNT):
		var id = ITEMS[index]
		rows.append({"item":id,"start":s.starts[index],"end":s.starts[index]+DURATIONS[id]})
	return rows

# 逐单验收时，这一单和排在它前面的单是否抢同一拍；返回第一处重叠，没有就返回空。
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

# 逐单验收：到料、撞台、逾期，按验收顺序说第一处真实违反的条件。
static func problems(s: Dictionary) -> Array:
	var out: Array = []
	for index in range(COUNT):
		var id = s.order[index]
		var start = start_of(s,id)
		if start < RELEASES[id]:
			out.append("%s 第 %d 拍才送来，第 %d 拍还开不了工。"%[id,RELEASES[id],start])
		var hit = collision(s,index)
		if not hit.is_empty():
			out.append("第 %d 拍还占着台：%s 的 %d–%d 还没走完，%s 就要开工。"%[
				hit.tick,hit.other,hit.other_start,hit.other_finish,id])
		if start+DURATIONS[id] > DEADLINES[id]:
			out.append("%s 到第 %d 拍才完，超过最晚 %d 拍。"%[id,start+DURATIONS[id],DEADLINES[id]])
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

# 改某一单的开工拍：顺序跟着重算，越界、非整数与开工中的状态一律不改。
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

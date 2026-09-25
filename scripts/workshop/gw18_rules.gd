extends RefCounted
# GW18 百臂总机「两种船期，一套准备」：全岛终局关。
# 库存 7 件分三批：森林 F 2 件、山谷 V 3 件、集市 M 2 件，不拆批、不超量。
# 压机一次一批、不能中断：2 件批次 1 拍、3 件批次 2 拍，本台没有换模成本。
# 冷却每批 2 拍、一次一批，依出压机的顺序处理；压机到冷却间、冷却到吊机间各只有
# 1 批暂存位，两台机器都不能当额外仓库。吊机每批 1 拍：F 固定第 3 拍、M 固定第 9 拍
# 开始吊；V 的身份开局固定，实际吊运点只可能是第 6 拍（早班）或第 8 拍（晚班），
# 第 3 拍收到确认，重试不重抽。第 10 拍开船。
# 玩家交的是同一份压制、冷却计划：早班与晚班两条推演都走得通才算解。
# 两页推演的判定、逐拍暂存链与吊运比对全部由这里现算，画面不另存会走样的表。
const SAMPLE = "workshop-gw18-1"
const BATCHES = ["F","V","M"]
const COUNT = 3
const ITEM_COUNT = [2,3,2]
const PRESS_TIME = [1,2,1]
const COOL_TIME = 2
const LOAD_TIME = 1
const F_LOAD = 3
const M_LOAD = 9
const BRANCHES = [6,8]
const BRANCH = 8
const HORIZON = 10
const START_MAX = 10
const DEFAULT_PRESS = [0,1,3]
const DEFAULT_COOL = [1,3,5]
const STAGES = ["arrival","approach","ready","puzzle","trial","delivery","notice","launch",
	"handover","aftermath","complete"]
const ANIMATIONS = ["approach","delivery","launch"]
const FIELDS = ["sample","stage","beat","press","cool","branch","confirmed","hint"]
const PAGE_NAMES = {6:"早班",8:"晚班"}

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,
		"press":DEFAULT_PRESS.duplicate(),"cool":DEFAULT_COOL.duplicate(),
		"branch":BRANCH,"confirmed":false,"hint":0}

static func page_name(slot: int) -> String:
	return PAGE_NAMES.get(slot,"")

# 一批的压制、冷却区间：[开工, 完工)，持续 d 拍、从 s 开始就占 s～s+d。
static func press_span(s: Dictionary, index: int) -> Array:
	return [s.press[index],s.press[index]+PRESS_TIME[index]]

static func cool_span(s: Dictionary, index: int) -> Array:
	return [s.cool[index],s.cool[index]+COOL_TIME]

# 吊机开工拍：F 第 3 拍、M 第 9 拍钉死；V 按这一班取第 6 或第 8 拍。
static func load_start(slot: int, index: int) -> int:
	if index == 1: return slot
	return F_LOAD if index == 0 else M_LOAD

# 开工拍从早到晚的排位：同拍时按 F、V、M 定，判定与画面都只看这一份。
static func rank(starts: Array) -> Array:
	var out: Array = []
	var taken: Array = []
	for _slot in range(COUNT):
		var best = -1
		for index in range(COUNT):
			if taken.has(index): continue
			if best < 0 or starts[index] < starts[best]: best = index
		taken.append(best); out.append(best)
	return out

static func press_order(s: Dictionary) -> Array:
	return rank(s.press)

static func cool_order(s: Dictionary) -> Array:
	return rank(s.cool)

# 同一台机器上两批抢同一拍：返回第一处重叠。
static func clash(spans: Array) -> Dictionary:
	for first in range(spans.size()):
		for second in range(first+1,spans.size()):
			var tick = maxi(spans[first][0],spans[second][0])
			if tick < mini(spans[first][1],spans[second][1]):
				return {"tick":tick,"first":first,"second":second}
	return {}

# 暂存链：produced 拍下线、consumed 拍被取走，任何时刻最多 1 批。
static func rack_overflow(produced: Array, consumed: Array) -> Dictionary:
	for tick in range(HORIZON+1):
		var held: Array = []
		for index in range(COUNT):
			if produced[index] <= tick and tick < consumed[index]: held.append(index)
		if held.size() >= 2: return {"tick":tick,"first":held[0],"second":held[1]}
	return {}

# 一页推演从第 0 拍跑到第 10 拍，第一处真实说不通的地方。
# 机器问题（压机、冷却、压机到冷却暂存）两页共用，不挂页名；
# 吊运点与冷却到吊机暂存只跟这一班有关，说原因时先报出是早班还是晚班。
static func run_conflict(s: Dictionary, slot: int) -> Dictionary:
	var spans: Array = []
	for index in range(COUNT): spans.append(press_span(s,index))
	var hit = clash(spans)
	if not hit.is_empty():
		return {"kind":"press_overlap","tick":hit.tick,"row":0,"first":hit.first,"second":hit.second,
			"text":"第 %d 拍压机还占着：%s 的 %d–%d 还没走完，%s 就要开工。"%[hit.tick,BATCHES[hit.first],
				spans[hit.first][0],spans[hit.first][1],BATCHES[hit.second]]}
	var order_press = rank(s.press)
	for index in order_press:
		if s.press[index]+PRESS_TIME[index] > HORIZON:
			return {"kind":"press_late","tick":s.press[index]+PRESS_TIME[index],"row":0,"first":index,"second":-1,
				"text":"%s 到第 %d 拍才下压机，第 %d 拍就要开船了。"%[BATCHES[index],
					s.press[index]+PRESS_TIME[index],HORIZON]}
	var order_cool = rank(s.cool)
	for index in range(COUNT):
		if order_cool[index] != order_press[index]:
			var wrong = order_cool[index]
			return {"kind":"cool_order","tick":s.cool[wrong],"row":2,"first":order_press[index],"second":wrong,
				"text":"冷却要按出压机的顺序：%s 先下压机，冷却间却先接了 %s。"%[BATCHES[order_press[index]],BATCHES[wrong]]}
	for index in order_press:
		if s.cool[index] < s.press[index]+PRESS_TIME[index]:
			return {"kind":"cool_early","tick":s.cool[index],"row":2,"first":index,"second":-1,
				"text":"%s 到第 %d 拍才下压机，冷却不能排在第 %d 拍开工。"%[BATCHES[index],
					s.press[index]+PRESS_TIME[index],s.cool[index]]}
	var cool_spans: Array = []
	for index in range(COUNT): cool_spans.append(cool_span(s,index))
	hit = clash(cool_spans)
	if not hit.is_empty():
		return {"kind":"cool_overlap","tick":hit.tick,"row":2,"first":hit.first,"second":hit.second,
			"text":"第 %d 拍冷却间还占着：%s 的 %d–%d 还没走完，%s 就要开工。"%[hit.tick,BATCHES[hit.first],
				cool_spans[hit.first][0],cool_spans[hit.first][1],BATCHES[hit.second]]}
	for index in order_cool:
		if s.cool[index]+COOL_TIME > HORIZON:
			return {"kind":"cool_late","tick":s.cool[index]+COOL_TIME,"row":2,"first":index,"second":-1,
				"text":"%s 到第 %d 拍才冷却完，赶不上第 %d 拍开船。"%[BATCHES[index],s.cool[index]+COOL_TIME,HORIZON]}
	var produced: Array = []
	var finished: Array = []
	for index in range(COUNT):
		produced.append(s.press[index]+PRESS_TIME[index])
		finished.append(s.cool[index]+COOL_TIME)
	hit = rack_overflow(produced,s.cool)
	if not hit.is_empty():
		return {"kind":"press_rack","tick":hit.tick,"row":1,"first":hit.first,"second":hit.second,
			"text":"第 %d 拍压机到冷却间挤了两批：%s 还在等冷却，%s 又下了压机——暂存位只有一批。"%[
				hit.tick,BATCHES[hit.first],BATCHES[hit.second]]}
	var loads: Array = []
	for index in range(COUNT): loads.append(load_start(slot,index))
	for index in range(COUNT):
		if finished[index] > loads[index]:
			return {"kind":"load_late","tick":loads[index],"row":4,"first":index,"second":-1,
				"text":"%s：%s 到第 %d 拍才冷却完，赶不上第 %d 拍开始的吊运。"%[page_name(slot),
					BATCHES[index],finished[index],loads[index]]}
	hit = rack_overflow(finished,loads)
	if not hit.is_empty():
		return {"kind":"cool_rack","tick":hit.tick,"row":3,"first":hit.first,"second":hit.second,
			"text":"%s：第 %d 拍冷却到吊机间挤了两批：%s 还在等吊机，%s 又冷却完了——暂存位只有一批。"%[
				page_name(slot),hit.tick,BATCHES[hit.first],BATCHES[hit.second]]}
	return {}

# 这一页走得通吗：两页都走得通才是解。
static func page_ok(s: Dictionary, slot: int) -> bool:
	return run_conflict(s,slot).is_empty()

static func solved(s: Dictionary) -> bool:
	if not page_ok(s,BRANCHES[0]): return false
	return page_ok(s,BRANCHES[1])

# 提交时逐页验收：机器问题两页共用只念一次，两页各自的真实原因按早班、晚班顺序说。
static func problems(s: Dictionary) -> Array:
	var out: Array = []
	for slot in BRANCHES:
		var hit = run_conflict(s,slot)
		if hit.is_empty(): continue
		if not out.has(hit.text): out.append(hit.text)
	return out

static func shortfalls(s: Dictionary) -> Array:
	return problems(s)

static func legal_starts(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	for start in value:
		if not start is int or start < 0 or start > START_MAX: return false
	return true

# 改某一批的压制开工拍：越界、非整数与规划之外的状态一律不改。
static func set_press(s: Dictionary, index: int, value: int) -> Dictionary:
	if s.stage != "puzzle" or index < 0 or index >= COUNT: return {}
	if not value is int or value < 0 or value > START_MAX or value == s.press[index]: return {}
	var n = s.duplicate(true)
	n.press[index] = value
	return n if validate(n) else {}

static func set_cool(s: Dictionary, index: int, value: int) -> Dictionary:
	if s.stage != "puzzle" or index < 0 or index >= COUNT: return {}
	if not value is int or value < 0 or value > START_MAX or value == s.cool[index]: return {}
	var n = s.duplicate(true)
	n.cool[index] = value
	return n if validate(n) else {}

static func nudge_press(s: Dictionary, index: int, delta: int) -> Dictionary:
	if index < 0 or index >= COUNT: return {}
	return set_press(s,index,s.press[index]+delta)

static func nudge_cool(s: Dictionary, index: int, delta: int) -> Dictionary:
	if index < 0 or index >= COUNT: return {}
	return set_cool(s,index,s.cool[index]+delta)

# 进「试演本页」：草稿一动不动，只是换到逐拍试验那一格；试完回规划。
static func begin_trial(s: Dictionary) -> Dictionary:
	if s.stage != "puzzle": return {}
	var n = s.duplicate(true)
	n.stage = "trial"
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("press") or not snapshot.has("cool"): return {}
	if not snapshot.press is Array or not snapshot.cool is Array: return {}
	var n = s.duplicate(true)
	n.press = snapshot.press.duplicate()
	n.cool = snapshot.cool.duplicate()
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
		"trial": n.stage = "puzzle"
		"delivery": n.stage = "notice"
		"notice": n.stage = "launch"; n.confirmed = true
		"launch": n.stage = "handover"
		"handover": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	if not v.branch is int or v.branch != BRANCH: return false
	if not v.confirmed is bool: return false
	for key in ["beat","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if not legal_starts(v.press) or not legal_starts(v.cool): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.press != DEFAULT_PRESS or v.cool != DEFAULT_COOL: return false
		if v.hint != 0 or v.confirmed: return false
	if v.stage in ["approach","ready","puzzle","trial","delivery","notice","launch","handover","complete"]:
		if v.beat != 2: return false
	var confirmed_stage = v.stage in ["launch","handover","aftermath","complete"]
	if v.confirmed != confirmed_stage: return false
	if v.stage in ["delivery","notice","launch","handover","aftermath","complete"] and not solved(v): return false
	return true

extends RefCounted

# MK12 千灯集市「不一样多，也都够用」：三处街口各自确认了 4、5、6 单位灯油的需要。
# 货栈只有三壶 2 单位与三壶 3 单位的封油：不能拆封，每处最多接两壶，六壶必须一壶不剩，
# 而且每一处都要不多不少刚好按自己的需求单接满。可行的装法只有 2+2→4、2+3→5、3+3→6。
# 设计上的陷阱是「三处都给 5」：它按封装确实交得出去，却违背了桥头与西坡各自确认过的需要，
# 提交时如实拒绝，并说出是哪一处的需求单没有被满足——少接不是罚，多接也不算赚。
# `plan` 只是装车草稿：壶有没有交出去，要等提交通过之后由 `handed` 记账，
# 之后所有演出都从 `handed` 读回。
# 台面上还剩哪几壶、每辆车上是多少单位，一律由这里现算，画面不另存计数，
# 所以把壶点回台面不会留下幻影货物，也不会凭空多出一壶。
# 规则层是纯函数：不 preload 场景、不碰 Node、不用随机，同一个输入永远得到同一个输出。
const JUGS = 6
# 下标就是壶的身份：0..2 是三壶 2 单位的圆封油壶，3..5 是三壶 3 单位的长封油壶。
const JUG_UNITS = [2, 2, 2, 3, 3, 3]
const JUG_KITS = ["oil_jug_round", "oil_jug_round", "oil_jug_round", "oil_jug_tall", "oil_jug_tall", "oil_jug_tall"]
const PLACES = ["桥头", "中街", "西坡"]
# 三处已经确认的需要，顺序就是需求单摆在板上的顺序，永远不按多少重排。
const NEEDS = [4, 5, 6]
const MAX_PER_PLACE = 2
const BEATS = 4
# 三级主动提示：提醒关系 → 缩小关键选择 → 示范一个步骤。提示不减奖励。
const HINT_TIERS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "handing", "delivery", "complete"]
const ANIMATIONS = ["approach", "handing", "delivery"]

# 空车与满台面：三辆车都还没接油，六壶都躺在货栈台面上。
static func empty_plan() -> Array:
	var rows := []
	for _place in range(PLACES.size()): rows.append([])
	return rows

static func fresh() -> Dictionary:
	return {"sample": "market-mk12-1", "stage": "arrival", "beat": 0, "hint": 0,
		"plan": empty_plan(), "handed": empty_plan()}

# plan[处] = 这一处接下的壶下标，最多 MAX_PER_PLACE 壶，且一壶只在一辆车上。
# 越界壶号、非整数、处数不对、同一壶上两辆车、一处超过两壶，都算存档损坏。
static func legal_plan(value: Variant) -> bool:
	if not value is Array or value.size() != PLACES.size(): return false
	var seen := []
	for row in value:
		if not row is Array or row.size() > MAX_PER_PLACE: return false
		for jug in row:
			if not jug is int or jug < 0 or jug >= JUGS: return false
			if seen.has(jug): return false
			seen.append(jug)
	return true

# ---- 派生读数：全部由 plan 现算，没有任何一份计数被存进现场 ----
static func units_of(row: Array) -> int:
	var total = 0
	for jug in row: total += JUG_UNITS[jug]
	return total

static func totals(plan: Array) -> Array:
	var result := []
	for row in plan: result.append(units_of(row))
	return result

# 还在台面上的壶：不在任何一辆车上就算没交出去，放回时不需要「归还」什么。
static func stock_of(plan: Array) -> Array:
	var idle := []
	for jug in range(JUGS):
		if place_of(plan, jug) < 0: idle.append(jug)
	return idle

static func stock_units(plan: Array) -> int: return units_of(stock_of(plan))

static func assigned(plan: Array) -> int: return JUGS - stock_of(plan).size()

static func place_of(plan: Array, jug: int) -> int:
	for place in range(plan.size()):
		if plan[place].has(jug): return place
	return -1

static func slot_of(plan: Array, jug: int) -> int:
	var place := place_of(plan, jug)
	return -1 if place < 0 else plan[place].find(jug)

static func room(plan: Array, place: int) -> int:
	if place < 0 or place >= plan.size(): return 0
	return MAX_PER_PLACE - plan[place].size()

static func need_total() -> int:
	var total = 0
	for need in NEEDS: total += need
	return total

# 六壶封油的总量：与三处需要之和相等，这正是「一壶不剩」能成立的原因。
static func jug_total() -> int:
	var total = 0
	for units in JUG_UNITS: total += units
	return total

# 一壶不剩、且每一处都恰好按自己的需求单接满，才算分完。
static func whole_and_exact(plan: Array) -> bool:
	return legal_plan(plan) and stock_of(plan).is_empty() and totals(plan) == NEEDS

# ---- 玩家动作：只改草稿，交出去的记录永远是空的 ----
static func can_load(state: Dictionary, jug: int, place: int) -> bool:
	return state.stage == "puzzle" and jug >= 0 and jug < JUGS and place >= 0 and place < PLACES.size() \
		and place_of(state.plan, jug) < 0 and room(state.plan, place) > 0

# 把一壶封油装上某一处的车。装到哪一处都不预设对错，缺口留到提交时如实说明。
static func load(state: Dictionary, jug: int, place: int) -> Dictionary:
	if not can_load(state, jug, place): return {}
	var next = state.duplicate(true)
	next.plan[place].append(jug)
	next.plan[place].sort()
	return next if validate(next) else {}

static func can_unload(state: Dictionary, place: int, slot: int) -> bool:
	return state.stage == "puzzle" and place >= 0 and place < PLACES.size() \
		and slot >= 0 and slot < state.plan[place].size()

# 把车上的那一壶点回台面：草稿少一壶，台面由 stock_of() 重新数出来。
static func unload(state: Dictionary, place: int, slot: int) -> Dictionary:
	if not can_unload(state, place, slot): return {}
	var next = state.duplicate(true)
	next.plan[place].remove_at(slot)
	return next if validate(next) else {}

# ---- 提交闸口：只说真实的缺口，不说答案 ----
static func plan_shortfalls(plan: Array) -> Array:
	var missing := []
	var idle = stock_of(plan)
	if not idle.is_empty():
		missing.append("货栈台面上还剩 %d 壶封油：六壶都要交出去，一壶不剩。" % idle.size())
	for place in range(PLACES.size()):
		var got = units_of(plan[place])
		if got == NEEDS[place]: continue
		if got < NEEDS[place]:
			missing.append("%s的需求单要 %d 单位，车上是 %d 单位，还差 %d 单位。" %
				[PLACES[place], NEEDS[place], got, NEEDS[place] - got])
		else:
			missing.append("%s的需求单要 %d 单位，车上是 %d 单位，多了 %d 单位。" %
				[PLACES[place], NEEDS[place], got, got - NEEDS[place]])
	return missing

static func shortfalls(state: Dictionary) -> Array: return plan_shortfalls(state.plan)

static func solved(state: Dictionary) -> bool: return plan_shortfalls(state.plan).is_empty()

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < BEATS - 1: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			# 一次交货：先记账（哪一壶真的交给了哪一处），再演出三辆车各自离场。
			next.handed = state.plan.duplicate(true)
			next.stage = "handing"
		"handing": next.stage = "delivery"
		"delivery": next.stage = "complete"
		_: return {}
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	if not snapshot.has("plan") or not snapshot.has("handed"): return {}
	if not legal_plan(snapshot["plan"]) or not legal_plan(snapshot["handed"]): return {}
	var next = state.duplicate(true)
	next.plan = snapshot["plan"].duplicate(true)
	next.handed = snapshot["handed"].duplicate(true)
	return next if validate(next) else {}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	# 六个字段是冻结的：多一个本关没有的字段（比如自定的奖励分）也算档被改过。
	for key in value.keys():
		if key not in ["sample", "stage", "beat", "hint", "plan", "handed"]: return false
	if not value.get("sample") is String or value.sample != "market-mk12-1": return false
	if value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINT_TIERS: return false
	# 开场四句说完才走到庭院前，之后的阶段都停在同一个最后一拍上。
	if value.stage != "arrival" and value.beat != BEATS - 1: return false
	if not legal_plan(value.get("plan")) or not legal_plan(value.get("handed")): return false
	match value.stage:
		"arrival", "approach", "ready":
			# 还没走到庭子前：一壶都没动，也没问过提示。
			if value.plan != empty_plan() or value.handed != empty_plan(): return false
			if value.hint != 0: return false
		"puzzle":
			# 摆放中途不存在「先交出去再改草稿」。
			if value.handed != empty_plan(): return false
		"handing", "delivery", "complete":
			# 交出去的就是那份草稿，而且这一单当时确实一壶不剩、恰好满足三处。
			if value.plan != value.handed: return false
			if not plan_shortfalls(value.handed).is_empty(): return false
		_: return false
	return true

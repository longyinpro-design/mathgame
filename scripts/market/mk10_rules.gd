extends RefCounted

# MK10 千灯集市「无论回哪封信」：两张还在等回信的订单，只可能要求运 3 箱或 6 箱，
# 两个可能开局就公开；两条运输约定也开局贴在码头上——红船每箱 2 票，蓝船开船 4 票、每箱再 1 票。
# 这次任务的筹票上限是 10 张。
#
# `written` 是写在两张订单格上的票额预测，`boat` 是选定的那条约定：这两样都在纸上，
# 一张筹票都还没花。只有提交通过「两格都按选定约定算对 + 两种可能都不超过 10 票」之后，
# 剧情才确认本局实际是哪一张订单（`branch`），`paid` 才记下真正付掉的票。
# 红船分别要 6/12 票，蓝船分别要 7/10 票：盖不住 6 箱那单的红船在任何分支下都交不出去，
# 通关判据与「本局恰好抽到哪一张」无关。
# 分支在关卡创建时就固定并写进存档：读档只会读回它，绝不会重抽。
# 票额与判定一律由这里现算，画面不另存计数，所以换一条约定不会留下幻影花费。
const CASES = [3, 6]
const SLOTS = 2
const BUDGET = 10
const BOATS = 2
const BOAT_NAMES = ["红船", "蓝船"]
const SAIL = [0, 4]
const PER_BOX = [2, 1]
const UNWRITTEN = -1
# 票额签盘上只有这五个数：两条约定的四个真值（红船 6/12、蓝船 7/10）加一个常见误算
# （4 票＝只算蓝船的开船票、漏了每箱）。玩家要在纸上摆出的正是这几个数本身。
const CANDIDATES = [4, 6, 7, 10, 12]
# 签盘另加一张空签（把订单格擦回空白），所以盘上是 6 张。
const TILE_VALUES = [UNWRITTEN, 4, 6, 7, 10, 12]
const TILES = 6
const ARRIVAL_BEATS = 3
const CLARIFY_BEATS = 3
const HINT_TIERS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "confirming", "clarify", "delivery", "complete"]
const ANIMATIONS = ["approach", "confirming", "delivery"]
# 提交之后、真正结算完成的阶段：这些阶段里 `paid` 必须等于本局那一张订单的票额。
const SETTLED = ["confirming", "clarify", "delivery", "complete"]
const BEAT_CAP = ARRIVAL_BEATS if ARRIVAL_BEATS > CLARIFY_BEATS else CLARIFY_BEATS
# 新开这一幕时两种可能轮流固定（检查里两条都要走一遍）；读档永远沿用存档里的那一个。
static var branch_roll = 0

static func empty_written() -> Array:
	var cells = []
	for slot in range(SLOTS): cells.append(UNWRITTEN)
	return cells

static func roll_branch() -> int:
	var boxes: int = CASES[branch_roll % CASES.size()]
	branch_roll += 1
	return boxes

# 宿主只会以 no-arg 方式调用：分支自己轮流固定。测试可以显式点名要哪一种。
static func fresh(boxes: int = UNWRITTEN) -> Dictionary:
	return {"sample": "market-mk10-1", "stage": "arrival", "beat": 0,
		"branch": roll_branch() if boxes == UNWRITTEN else boxes,
		"written": empty_written(), "boat": -1, "paid": 0, "hint": 0}

# ---- 纸面账：票额全部现算 ----
static func legal_boat(value: Variant) -> bool:
	return value is int and value >= -1 and value < BOATS

static func legal_written(value: Variant) -> bool:
	if not value is Array or value.size() != SLOTS: return false
	for one in value:
		if not one is int or (one != UNWRITTEN and one not in CANDIDATES): return false
	return true

static func fare(boat: int, boxes: int) -> int:
	if boat < 0 or boat >= BOATS: return 0
	return SAIL[boat] + PER_BOX[boat] * boxes

# 一条约定在两种可能下的票额，顺序与 CASES 一致。
static func fares(boat: int) -> Array:
	var values = []
	for index in range(SLOTS): values.append(fare(boat, CASES[index]))
	return values

static func tariff_text(boat: int) -> String:
	if boat < 0 or boat >= BOATS: return "未贴约定"
	var per_box = "每箱 %d 票" % PER_BOX[boat]
	return per_box if SAIL[boat] == 0 else "开船 %d 票 + %s" % [SAIL[boat], per_box]

# 码头上挂在各自船底的三条牌：约定全部公开，玩家自己按它算两种可能。
static func tariff_lines(boat: int) -> Array:
	if boat < 0 or boat >= BOATS: return ["未贴约定"]
	return [BOAT_NAMES[boat], "没有开船票" if SAIL[boat] == 0 else "开船 %d 票" % SAIL[boat],
		"每箱 %d 票" % PER_BOX[boat]]

# 订单格与签盘上写的那个数：空白就是空白，不标注对错。
static func slip_text(value: int) -> String:
	return "还没写" if value == UNWRITTEN else "%d 票" % value

# 签盘只有巴掌宽：牌上写数字，「票」字与「空白」的意思留给提示条说。
static func tile_text(value: int) -> String:
	return "空" if value == UNWRITTEN else str(value)

# 盖得住两种可能：这条约定在 3 箱与 6 箱下都不超过 10 票。与分支无关。
static func covers(boat: int) -> bool:
	if boat < 0 or boat >= BOATS: return false
	for value in fares(boat):
		if value > BUDGET: return false
	return true

# 第一个把预算顶穿的可能是第几格；-1 表示这条约定两种都盖得住。
static func uncovered_case(boat: int) -> int:
	if boat < 0 or boat >= BOATS: return -1
	var values = fares(boat)
	for index in range(SLOTS):
		if values[index] > BUDGET: return index
	return -1

static func written_matches(state: Dictionary) -> bool:
	if state.boat < 0: return false
	var values = fares(state.boat)
	for slot in range(SLOTS):
		if state.written[slot] != values[slot]: return false
	return true

# 纸面这一单成不成立：选了船、两格都写满、两格都照这条约定算对、这条约定还盖得住两种可能。
static func plan_ok(state: Dictionary) -> bool:
	if not legal_boat(state.get("boat")) or not legal_written(state.get("written")): return false
	if state.boat < 0 or state.written == empty_written(): return false
	return written_matches(state) and covers(state.boat)

# 真正付掉的票：只有成立的那一条约定与本局那一张订单同时确定之后才有数。
static func paid_for(state: Dictionary) -> int:
	return fare(state.boat, state.branch) if plan_ok(state) else 0

static func can_choose(state: Dictionary, boat: int) -> bool:
	return state.stage == "puzzle" and boat >= 0 and boat < BOATS

static func can_clear_boat(state: Dictionary) -> bool:
	return state.stage == "puzzle" and state.boat >= 0

# 选船＝纸上改主意：只改 `boat`，两格的预测留着让玩家自己重算，一张票都不动。
static func choose_boat(state: Dictionary, boat: int) -> Dictionary:
	if not can_choose(state, boat): return {}
	if state.boat == boat: return clear_boat(state)
	var next = state.duplicate(true)
	next.boat = boat
	return next if validate(next) else {}

static func clear_boat(state: Dictionary) -> Dictionary:
	if not can_clear_boat(state): return {}
	var next = state.duplicate(true)
	next.boat = -1
	return next if validate(next) else {}

static func can_mark(state: Dictionary, slot: int, value: int) -> bool:
	if state.stage != "puzzle" or slot < 0 or slot >= SLOTS: return false
	if value != UNWRITTEN and value not in CANDIDATES: return false
	return state.written[slot] != value

# 往订单格里摆一个票额签（空签＝把这一格擦回空白）。
static func mark_case(state: Dictionary, slot: int, value: int) -> Dictionary:
	if not can_mark(state, slot, value): return {}
	var next = state.duplicate(true)
	next.written[slot] = value
	return next if validate(next) else {}

# ---- 提交反馈：一次只说一条没兑现的职责，并点名是哪一种可能 ----
# 白板内框 798×56，宿主还会在句尾补一句「（还有 N 处没有归位）」，
# 所以每条都得压在一行里，且给那句尾巴留出位置。
static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	if state.boat < 0:
		missing.append("还没选定运输约定：红船与蓝船的收费都贴在码头上。")
		return missing
	for slot in range(SLOTS):
		if state.written[slot] == UNWRITTEN:
			missing.append("「运 %d 箱」那一格还空着：两种可能都要写在纸上。" % CASES[slot])
	var values = fares(state.boat)
	for slot in range(SLOTS):
		if state.written[slot] != UNWRITTEN and state.written[slot] != values[slot]:
			missing.append("%d 箱那格写 %d 票，%s按约定是 %d 票。" % [
				CASES[slot], state.written[slot], BOAT_NAMES[state.boat], values[slot]])
	var over = uncovered_case(state.boat)
	if over >= 0:
		missing.append("%s运 %d 箱要 %d 票，比 %d 票多 %d 票：盖不住两种可能。" % [
			BOAT_NAMES[state.boat], CASES[over], values[over], BUDGET, values[over] - BUDGET])
	return missing

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < ARRIVAL_BEATS - 1: next.beat += 1
			else:
				next.stage = "approach"; next.beat = 0
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			# 交单之后剧情才确认本局实际是哪一张订单，票按那条约定一次性结清。
			next.paid = fare(state.boat, state.branch)
			next.stage = "confirming"
		"confirming":
			if not plan_ok(state) or state.paid != fare(state.boat, state.branch): return {}
			next.stage = "clarify"
		"clarify":
			if state.beat < CLARIFY_BEATS - 1: next.beat += 1
			else:
				next.stage = "delivery"; next.beat = 0
		"delivery":
			if not plan_ok(state) or state.paid != fare(state.boat, state.branch): return {}
			next.stage = "complete"
		_: return {}
	return next

# 撤销只回纸面：预测、选定与「已经付掉的票」一起退回，分支永远不属于快照。
static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	for key in ["written", "boat", "paid"]:
		if not snapshot.has(key): return {}
	if snapshot.has("branch"): return {}
	var next = state.duplicate(true)
	next.written = snapshot.written
	next.boat = snapshot.boat
	next.paid = snapshot.paid
	return next if validate(next) else {}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk10-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEAT_CAP - 1: return false
	if value.stage == "arrival" and value.beat > ARRIVAL_BEATS - 1: return false
	if value.stage != "arrival" and value.stage != "clarify" and value.beat != 0: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINT_TIERS: return false
	if not value.get("branch") is int or value.branch not in CASES: return false
	if not legal_written(value.get("written")) or not legal_boat(value.get("boat")): return false
	if not value.get("paid") is int or value.paid < 0 or value.paid > BUDGET: return false
	# 还没走到预测板：纸上什么都不能有。
	if value.stage in ["arrival", "approach", "ready"]:
		if not value.written == empty_written() or value.boat != -1: return false
		if value.paid != 0: return false
	# 摆放阶段一张票都还没花：不存在「先付了再改主意」。
	if value.stage == "puzzle" and value.paid != 0: return false
	# 结算之后：这条约定必须真的盖得住两种可能，付的就是本局那一张订单的票额。
	if value.stage in SETTLED:
		if not plan_ok(value): return false
		if value.paid != fare(value.boat, value.branch): return false
	return true

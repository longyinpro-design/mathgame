extends RefCounted

# MK06 灯芯摊「十根灯芯怎么凑」：整包采购，一次付清。
# 三种封装（4 根 7 票 / 3 根 6 票 / 单根 3 票）、预算 19 票、订单恰好 10 根，包不拆卖。
# `order` 只是订单上的选择，一张筹票都还没花；只有提交通过数量与预算检查后，
# `bought` 才记下真正买下的包，之后所有演出都从 `bought` 读回。
# 数量与票数的合计一律由这里算，画面不另存计数，所以放回包不会留下幻影花费。
const KINDS = 3
const STICKS = [4, 3, 1]
const PRICES = [7, 6, 3]
const BUDGET = 19
const ORDER_STICKS = 10
# 每类在订单板上最多摆 6 包（柜面只有 6 个位置）。预算内最多只需要 3 包，
# 所以这条上限从不剪掉任何可行方案，只是把纸面摊得太开时提醒玩家先放回。
const MAX_PER_KIND = 6
# 三级主动提示：提醒关系 → 缩小关键选择 → 示范一个步骤。提示不减奖励。
const HINT_TIERS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "purchasing", "delivery", "complete"]
const ANIMATIONS = ["approach", "purchasing", "delivery"]

static func empty_order() -> Array:
	var counts = []
	for kind in range(KINDS): counts.append(0)
	return counts

static func fresh() -> Dictionary:
	return {"sample": "market-mk06-1", "stage": "arrival", "beat": 0, "order": empty_order(),
		"bought": empty_order(), "hint": 0}

# 存档里的越界值、非整数、错长度都算损坏。
static func legal_order(value: Variant) -> bool:
	if not value is Array or value.size() != KINDS: return false
	for count in value:
		if not count is int or count < 0 or count > MAX_PER_KIND: return false
	return true

static func sticks_of(order: Array) -> int:
	var total = 0
	for kind in range(KINDS): total += STICKS[kind] * order[kind]
	return total

static func tickets_of(order: Array) -> int:
	var total = 0
	for kind in range(KINDS): total += PRICES[kind] * order[kind]
	return total

static func packs_of(order: Array) -> int:
	var total = 0
	for kind in range(KINDS): total += order[kind]
	return total

# 一份订单能不能付：恰好 10 根，且总价不超过手里的 19 张筹票。
static func paid_ok(order: Array) -> bool:
	return legal_order(order) and sticks_of(order) == ORDER_STICKS and tickets_of(order) <= BUDGET

static func can_take(state: Dictionary, kind: int) -> bool:
	return state.stage == "puzzle" and kind >= 0 and kind < KINDS and state.order[kind] < MAX_PER_KIND

static func can_return(state: Dictionary, kind: int, slot: int) -> bool:
	return state.stage == "puzzle" and kind >= 0 and kind < KINDS and slot >= 0 and slot < state.order[kind]

# 拿一整包上订单：不做预算判断，超票的组合照样能摆出来，交给提交时如实说明。
static func take_package(state: Dictionary, kind: int) -> Dictionary:
	if not can_take(state, kind): return {}
	var next = state.duplicate(true)
	next.order[kind] += 1
	return next if validate(next) else {}

# 放回一整包：筹票还在匣子里，之前没有任何花费需要退回。
static func return_package(state: Dictionary, kind: int, slot: int) -> Dictionary:
	if not can_return(state, kind, slot): return {}
	var next = state.duplicate(true)
	next.order[kind] -= 1
	return next if validate(next) else {}

static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	var order = state.order
	var sticks = sticks_of(order)
	var tickets = tickets_of(order)
	if sticks < ORDER_STICKS:
		missing.append("面包铺要恰好 %d 根灯芯：订单上只有 %d 根，还差 %d 根。" % [ORDER_STICKS, sticks, ORDER_STICKS - sticks])
	if sticks > ORDER_STICKS:
		missing.append("面包铺要恰好 %d 根灯芯：订单上有 %d 根，多了 %d 根。" % [ORDER_STICKS, sticks, sticks - ORDER_STICKS])
	if tickets > BUDGET:
		missing.append("这单要 %d 票，手里只有 %d 票。" % [tickets, BUDGET])
	return missing

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < 2: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			# 一次购买：先入账（记下真正买下的包），再演出搬运。
			next.bought = state.order.duplicate(true)
			next.stage = "purchasing"
		"purchasing": next.stage = "delivery"
		"delivery": next.stage = "complete"
		_: return {}
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	if not snapshot.has("order") or not snapshot.has("bought"): return {}
	var next = state.duplicate(true)
	next.order = snapshot.order
	next.bought = snapshot.bought
	return next if validate(next) else {}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk06-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > 2: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINT_TIERS: return false
	if not legal_order(value.get("order")) or not legal_order(value.get("bought")): return false
	# 走到摊位前还没拿过货：订单与已买都必须是空的。
	if value.stage in ["arrival", "approach", "ready"] and not value.order == empty_order(): return false
	# 摆放阶段一张票都还没花：不存在「先买好再改单」。
	if value.stage == "puzzle" and not value.bought == empty_order(): return false
	# 购买之后：付的就是订单上那一单，而且这一单当时确实付得起、也确实凑满 10 根。
	if value.stage in ["purchasing", "delivery", "complete"]:
		if not value.order == value.bought: return false
		if not paid_ok(value.bought): return false
	return true

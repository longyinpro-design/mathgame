extends RefCounted

# MK14 三枚砝码的小摊（可选支线，开放于 MK11 之后）：老货栈把摊子上唯一的三枚砝码 1、3、9
# 借给油庭院的小摊，两盘都能站砝码，每枚最多上一次秤。街上接连送来两单真货：5 单位与 8 单位，
# 货压在指定的货盘上，玩家只挪砝码、不解锁新砝码：5+3+1=9、8+1=9。
# 记法沿用第五幕那具双向秤的约定（一盘一个 0/1 数组，同一枚在两盘都记 1 就是把它用了第二遍），
# 但本关自己实现判秤：这里不 preload、也不依赖 MK11 的任何文件。
# 两盘按带符号的差来记：difference() = 对面那盘的砝码 −（货盘的砝码 + 这一单的货）。
# 1、3、9 是一组三进制砝码，每枚有「架上／货盘／对面」三个去处，27 种摆法与 −13..+13 的整数差
# 一一对应：1 至 13 的每一单都只有一种摆法配得平。本关只走 5 与 8 两单，不要求逐个摆一遍。
# 盘面合计、倾斜、读数全部在这里现算，画面不另存任何秤上的状态；提交之前秤始终锁着制动，
# 摆放时只看得到砝码站到哪一头，永远不预告这一式平不平。规则层是纯函数：不 preload 场景、
# 不碰 Node、不用随机，同一个输入永远得到同一个输出。
const WEIGHTS = [1, 3, 9]
# 三枚砝码各自的造型与第五幕那具秤上的是同一套：1 用扁圆码、3 用六角码、9 用最高那只阶梯码。
const WEIGHT_KITS = ["weight_small", "weight_hex", "weight_stepped"]
const COUNT = 3
const WEIGHT_TOTAL = 13
# 一枚砝码的三个去处：还在砝码架上、站在这一单的货所在的货盘（左盘）、站在对面那盘（右盘）。
const OFF = 0
const GOODS = 1
const FAR = 2
const SIDES = [OFF, GOODS, FAR]
# 点一下就往前走一格：架 → 对面那盘 → 货盘 → 架。
# 从架上先落到对面，正是所有人都默认的那一步；再点一次才是 MK11 教过的那一下。
const NEXT = [FAR, OFF, GOODS]
# 接连送来的两单真货：先 5 单位、再 8 单位。数字是订单上写好的，玩家不填、也不选。
const ORDERS = [5, 8]
const ORDER_NAMES = ["订单一", "订单二"]
# 两单的货各是一只封好的油纸包：8 单位那一单明显比 5 单位的大一号。
const ORDER_KITS = ["parcel_medium", "parcel_large"]
const ORDER_TAGS = ["桥头灯行", "中街油铺"]
# 三辆车就是两单的去处：等着上秤的两辆车，加上那一单交完之后停靠的车。
const CARTS = ["cart_left", "cart_middle", "cart_right"]
# 差多少个单位时秤杆完全沉到底：只决定演出的幅度，从不参与判分。
const FULL_TILT = 3
const BEATS = 3
const HINT_TIERS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "weighing", "result", "delivery", "complete"]
const ANIMATIONS = ["approach", "weighing", "delivery"]

static func empty_pan() -> Array:
	var pan := []
	for _index in range(COUNT): pan.append(0)
	return pan

static func empty_records() -> Array:
	var out := []
	for _order in range(ORDERS.size()): out.append(empty_pan())
	return out

static func fresh() -> Dictionary:
	return {"sample": "market-mk14-1", "stage": "arrival", "beat": 0, "order": 0,
		"goods": empty_pan(), "far": empty_pan(), "built_goods": empty_records(),
		"built_far": empty_records(), "delivered": 0, "weighs": 0, "hint": 0}

# ---- 读盘：唯一的真相来源 ----
# 一盘用一个长度为 3 的 0/1 数组记「哪几枚砝码站在这盘上」。
static func legal_pan(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	for flag in value:
		if not flag is int or flag < 0 or flag > 1: return false
	return true

# 一单的记账摆法：每单一条 0/1 数组，条数必须与订单数一样多。
static func legal_records(value: Variant) -> bool:
	if not value is Array or value.size() != ORDERS.size(): return false
	for entry in value:
		if not legal_pan(entry): return false
	return true

static func legal_index(index: int) -> bool:
	return index >= 0 and index < COUNT

static func legal_side(side: int) -> bool:
	return side == GOODS or side == FAR

static func on_pan(state: Dictionary, side: int, index: int) -> bool:
	if not legal_index(index): return false
	if side == GOODS: return state.goods[index] == 1
	if side == FAR: return state.far[index] == 1
	return false

static func side_of(state: Dictionary, index: int) -> int:
	if on_pan(state, GOODS, index): return GOODS
	if on_pan(state, FAR, index): return FAR
	return OFF

static func side_of_record(goods: Array, far: Array, index: int) -> int:
	if goods[index] == 1: return GOODS
	if far[index] == 1: return FAR
	return OFF

# 这一盘上站着哪几枚（按 9、3、1 的大到小读，与柜面说法一致）。
static func on_list(goods: Array, far: Array, side: int) -> Array:
	var list := []
	var pan := goods if side == GOODS else far
	for index in range(COUNT - 1, -1, -1):
		if pan[index] == 1: list.append(index)
	return list

static func on_list_state(state: Dictionary, side: int) -> Array:
	return on_list(state.goods, state.far, side)

static func pan_count(state: Dictionary, side: int) -> int:
	return on_list_state(state, side).size()

static func weights_on_scale(state: Dictionary) -> int:
	return pan_count(state, GOODS) + pan_count(state, FAR)

# 只有砝码的重量；这一单的货另算。
static func weight_total(state: Dictionary, side: int) -> int:
	var total := 0
	for index in range(COUNT):
		if on_pan(state, side, index): total += WEIGHTS[index]
	return total

static func signed_sum(goods: Array, far: Array) -> int:
	var total := 0
	for index in range(COUNT): total += (far[index] - goods[index]) * WEIGHTS[index]
	return total

# ---- 这一单的货：真货，压在指定的货盘上，不是玩家填进去的数 ----
static func order_units(index: int) -> int:
	if index < 0 or index >= ORDERS.size(): return 0
	return ORDERS[index]

static func order_name(index: int) -> String:
	if index < 0 or index >= ORDERS.size(): return "订单"
	return ORDER_NAMES[index]

# 走到秤前货才在盘上；交完最后一单收摊，货已经跟着车走了。
static func cargo_on_pan(state: Dictionary) -> bool:
	return state.stage not in ["arrival", "approach", "complete"]

static func cargo_units(state: Dictionary) -> int:
	return order_units(state.order) if cargo_on_pan(state) else 0

static func order_of(state: Dictionary) -> int: return state.order

static func pan_total(state: Dictionary, side: int) -> int:
	return weight_total(state, side) + (cargo_units(state) if side == GOODS else 0)

# 带符号的差：正数表示对面那盘更沉，负数表示货盘这头更沉，0 才是平的。
static func difference(state: Dictionary) -> int:
	return pan_total(state, FAR) - pan_total(state, GOODS)

static func heavier(state: Dictionary) -> int:
	var gap := difference(state)
	if gap > 0: return FAR
	if gap < 0: return GOODS
	return OFF

static func heavier_word(state: Dictionary) -> String:
	return pan_word(heavier(state))

static func balanced(state: Dictionary) -> bool:
	return difference(state) == 0

# 抬起秤之后这一单能不能走：货是真的、两盘一样重，就只这一条。
static func solved(state: Dictionary) -> bool:
	return cargo_on_pan(state) and balanced(state)

# 秤杆静止时的倾角比例：−1 货盘沉到底，0 平，+1 对面沉到底。角度由画面按同一符号换算。
static func tilt(state: Dictionary) -> float:
	return clampf(float(difference(state)) / float(FULL_TILT), -1.0, 1.0)

static func pan_name(side: int) -> String:
	if side == GOODS: return "货盘"
	if side == FAR: return "对面那盘"
	return "砝码架"

static func pan_word(side: int) -> String:
	if side == GOODS: return "货盘这一头"
	if side == FAR: return "对面那盘"
	return "两边"

static func weight_name(index: int) -> String:
	return "%d 单位" % WEIGHTS[index]

# ---- 摆法的说法：只复述玩家自己摆出来的东西，不下判断 ----
static func side_terms(goods: Array, far: Array, units: int, side: int) -> Array:
	var parts := []
	if side == GOODS and units > 0: parts.append("货 %d" % units)
	for index in range(COUNT - 1, -1, -1):
		if (goods if side == GOODS else far)[index] == 1: parts.append("砝码 %d" % WEIGHTS[index])
	if parts.is_empty(): parts.append("空盘")
	return parts

static func equation_of(goods: Array, far: Array, units: int) -> String:
	return " + ".join(side_terms(goods, far, units, GOODS)) + " = " + " + ".join(side_terms(goods, far, units, FAR))

static func equation(state: Dictionary) -> String:
	return equation_of(state.goods, state.far, cargo_units(state))

static func built_equation(state: Dictionary, index: int) -> String:
	if index < 0 or index >= ORDERS.size(): return ""
	return equation_of(state.built_goods[index], state.built_far[index], ORDERS[index])

static func pan_caption(state: Dictionary, side: int) -> String:
	var parts := []
	if side == GOODS and cargo_units(state) > 0: parts.append("货 %d" % cargo_units(state))
	for index in range(COUNT - 1, -1, -1):
		if on_pan(state, side, index): parts.append("砝码 %d" % WEIGHTS[index])
	return "%s：%s = %d 单位" % [pan_name(side), " + ".join(parts), pan_total(state, side)]

# 货单上写着的数：公开信息，永远不提该怎么摆。
static func order_caption(index: int) -> String:
	return "%s · %d 单位 · %s" % [ORDER_NAMES[index], order_units(index), ORDER_TAGS[index]]

# ---- 提交之后的如实回话：先说秤沉到哪一头，再说这一单还没走 ----
static func beam_line(state: Dictionary) -> String:
	return "%s沉下去了：货盘 %d 单位，对面那盘 %d 单位。" % [heavier_word(state),
		pan_total(state, GOODS), pan_total(state, FAR)]

static func promise_line(state: Dictionary) -> String:
	return "%d 单位的货还压在盘上：两盘差 %d 单位，秤没平，这一单就走不了。" % [
		cargo_units(state), absi(difference(state))]

# 抬起秤之后要说的话。没配平的现场必然踩中至少一条；配平了就不再回话，直接交付。
static func result_lines(state: Dictionary) -> Array:
	var lines := []
	if balanced(state): return lines
	lines.append(beam_line(state))
	lines.append(promise_line(state))
	return lines

static func result_line(state: Dictionary) -> String:
	return "\n".join(result_lines(state))

# 跨订单迁移：从两单的记账摆法现算，不写死答案。逐枚一条说法，回执与柜面都按行排版。
static func migration_parts(state: Dictionary) -> Array:
	if state.delivered < ORDERS.size(): return []
	var parts := []
	for index in range(COUNT):
		var from := side_of_record(state.built_goods[0], state.built_far[0], index)
		var to := side_of_record(state.built_goods[1], state.built_far[1], index)
		var weight: int = WEIGHTS[index]
		if from == to: parts.append("%d 留在%s" % [weight, pan_name(to)])
		else: parts.append("%d 从%s挪到%s" % [weight, pan_name(from), pan_name(to)])
	return parts

static func migration_caption(state: Dictionary) -> String:
	return " · ".join(migration_parts(state))

# ---- 数学事实：作者验算用，运行时只在回执那一行文字里出现 ----
# 27 种摆法（每枚三个去处）全部列出来，供检查逐一对账。
static func placements() -> Array:
	var out := []
	for step in range(int(pow(COUNT, COUNT))):
		var goods := empty_pan(); var far := empty_pan(); var rest := step
		for index in range(COUNT):
			var side: int = rest % COUNT
			rest = int(rest / float(COUNT))
			if side == GOODS: goods[index] = 1
			elif side == FAR: far[index] = 1
		out.append({"goods": goods, "far": far})
	return out

static func balances(goods: Array, far: Array, units: int) -> bool:
	for index in range(COUNT):
		if goods[index] == 1 and far[index] == 1: return false
	return signed_sum(goods, far) == units

static func arrangements_for(units: int) -> Array:
	var found := []
	for spot in placements():
		if balances(spot.goods, spot.far, units): found.append(spot)
	return found

# 第三级提示用的说法：这一单配得平的那一式。1 至 13 每一单都只有一种摆法（见 spans_all 检查），
# 所以这句话复述的是数学事实，不是作者另写的一份答案。
static func arrangement_caption(units: int) -> String:
	var found := arrangements_for(units)
	if found.is_empty(): return "%d 单位这一式配不出来" % units
	return equation_of(found[0].goods, found[0].far, units)

# 只把砝码放在对面那一盘时，能配出的量：1、3、9 的子集和，5 与 8 都不在其中。
static func one_pan_sums() -> Array:
	var sums := []
	for spot in placements():
		var only_far := true
		for index in range(COUNT):
			if spot.goods[index] == 1: only_far = false
		if not only_far: continue
		var total: int = signed_sum(spot.goods, spot.far)
		if not sums.has(total): sums.append(total)
	sums.sort()
	return sums

static func span_units() -> Array:
	var found := []
	for spot in placements():
		var total: int = signed_sum(spot.goods, spot.far)
		if total > 0 and not found.has(total): found.append(total)
	found.sort()
	return found

# 回执上那句「1 至 13 都配得出来」是不是真话，由这条检查兜住。
static func spans_all() -> bool:
	var span := span_units()
	if span.size() != WEIGHT_TOTAL: return false
	for step in range(WEIGHT_TOTAL):
		if span[step] != step + 1: return false
		if arrangements_for(step + 1).size() != 1: return false
	return true

# ---- 玩家动作 ----
static func can_cycle(state: Dictionary, index: int) -> bool:
	return state.stage == "puzzle" and legal_index(index)

# 把一枚砝码请上某一盘；它原本站在另一盘时就是「挪过来」，两盘永远不同时记下同一枚。
static func place_weight(state: Dictionary, index: int, side: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_index(index) or not legal_side(side): return {}
	if side_of(state, index) == side: return {}
	var next = state.duplicate(true)
	next.goods[index] = 1 if side == GOODS else 0
	next.far[index] = 1 if side == FAR else 0
	return next if validate(next) else {}

static func return_weight(state: Dictionary, index: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_index(index) or side_of(state, index) == OFF: return {}
	var next = state.duplicate(true)
	next.goods[index] = 0
	next.far[index] = 0
	return next if validate(next) else {}

static func cycle(state: Dictionary, index: int) -> Dictionary:
	if not can_cycle(state, index): return {}
	var onward: int = NEXT[side_of(state, index)]
	return return_weight(state, index) if onward == OFF else place_weight(state, index, onward)

# 这一枚下一步会站到哪儿：热点文字与提示都从这里取，画面不自己猜。
static func next_side(state: Dictionary, index: int) -> int:
	if not legal_index(index): return OFF
	return NEXT[side_of(state, index)]

# ---- 提交闸口：只管「手底下还没动手」，不判数学 ----
static func shortfalls(state: Dictionary) -> Array:
	var missing := []
	if weights_on_scale(state) == 0:
		missing.append("三枚砝码都还在架上：先请一枚上秤，空盘配不出这一单的货。")
	return missing

static func ready_to_weigh(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

# 交付那一刻把这单的摆法记进账里：之后的回执与纪念物只复述这两笔真账。
static func booked(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	next.built_goods[state.order] = state.goods.duplicate(true)
	next.built_far[state.order] = state.far.duplicate(true)
	next.delivered = state.order + 1
	return next

static func advance(state: Dictionary) -> Dictionary:
	# 只往前一幕：残缺字典一律不推进，避免把不存在的步骤当成走过。
	if not state.has("stage") or not state.has("beat"): return {}
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < BEATS - 1: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			# 提秤不看对错：只要请了砝码上秤，秤就抬。平不平由演出如实给出。
			if not ready_to_weigh(state): return {}
			next.weighs += 1
			next.stage = "weighing"
		"weighing": next.stage = "delivery" if balanced(state) else "result"
		"result":
			# 记下这一次的结果就回到秤前：摆法原样保留，一枚砝码都不扣。
			next.stage = "puzzle"
		"delivery":
			if not balanced(state): return {}
			next = booked(state)
			if next.order < ORDERS.size() - 1:
				# 上一单交完，下一单推上秤：三枚砝码留在原地，玩家只需要挪。
				next.order += 1
				next.stage = "puzzle"
			else:
				next.stage = "complete"
		_: return {}
	return next if validate(next) else {}

# 重摆：三枚砝码回到架上。已经配好交出去的那一单是街上发生过的事，不清零。
static func cleared(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	var next = state.duplicate(true)
	next.goods = empty_pan()
	next.far = empty_pan()
	return next if validate(next) else {}

static func legal_snapshot(snapshot: Dictionary) -> bool:
	return snapshot.get("goods") is Array and snapshot.get("far") is Array

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or not legal_snapshot(snapshot): return {}
	if not legal_pan(snapshot.goods) or not legal_pan(snapshot.far): return {}
	var next = state.duplicate(true)
	next.goods = snapshot.goods.duplicate(true)
	next.far = snapshot.far.duplicate(true)
	# 抬秤次数与已交付的那一单都是发生过的事，快照里没有它们，也就改不动。
	return next if validate(next) else {}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk14-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINT_TIERS: return false
	if not value.get("order") is int or value.order < 0 or value.order >= ORDERS.size(): return false
	if not value.get("weighs") is int or value.weighs < 0: return false
	if not value.get("delivered") is int or value.delivered < 0 or value.delivered > ORDERS.size(): return false
	if not legal_pan(value.get("goods")) or not legal_pan(value.get("far")): return false
	if not legal_records(value.get("built_goods")) or not legal_records(value.get("built_far")): return false
	# 每枚砝码最多用一次：同一枚同时站在两个盘上，就是把它偷偷用了第二遍。
	for index in range(COUNT):
		if value.goods[index] == 1 and value.far[index] == 1: return false
	# 台词没走完就写成后面的幕，是凭空跳步。
	if value.stage != "arrival" and value.beat != BEATS - 1: return false
	# 还没走到秤前：三枚砝码都在架上，一单也没交出去，账上两格都是空的。
	if value.stage in ["arrival", "approach", "ready"]:
		if value.order != 0 or value.delivered != 0 or value.weighs != 0: return false
		if not value.goods == empty_pan() or not value.far == empty_pan(): return false
		if not value.built_goods == empty_records() or not value.built_far == empty_records(): return false
	# 站在秤前的每一幕：正在配的这一单就是下一单，前面几单都已经交出去。
	if value.stage in ["puzzle", "weighing", "result", "delivery"] and value.delivered != value.order: return false
	# 秤已经抬起来过的每一幕都必须真的抬过至少一次秤。
	if value.stage in ["weighing", "result", "delivery", "complete"] and value.weighs < 1: return false
	# 「结果牌还立着」与「这一单其实已经配平了」不能同时成立。
	if value.stage == "result" and balanced(value): return false
	# 交付那一幕只认两盘真的平了。
	if value.stage == "delivery" and not balanced(value): return false
	if value.stage == "complete":
		if value.delivered != ORDERS.size(): return false
		# 账上每一单都要真的把那单的货配平：没配平却写成交货，是凭空跳步。
		for index in range(ORDERS.size()):
			if not balances(value.built_goods[index], value.built_far[index], ORDERS[index]): return false
		# 收摊之后砝码不再动：完成时的现场就是最后一单记下的那一式。
		if not value.goods == value.built_goods[ORDERS.size() - 1]: return false
		if not value.far == value.built_far[ORDERS.size() - 1]: return false
	return true

extends RefCounted

# MK14 千灯集市「三枚砝码的小摊」（可选支线，MK11 之后开放）：老货栈把摊子上唯一的三枚砝码
# 1、3、9 借给油庭院的小摊，两盘都能站，每枚最多上一次秤。街上送来三单真货——桥头灯行 4 单位、
# 中街油铺 7 单位、河下米行 13 单位，哪一单先上秤由玩家点车挑。
# 这一关的规矩只有一条新的：头一单的摆法随便摆，往后每一单只能从上一单记进账里的那一摆法
# 挪一枚砝码，第二枚一碰就被当场拦下（拦的时候点名已经挪过的那一枚，不让人猜规则）。
# 为什么这条规矩有得想：1、3、9 是一组三进制砝码，每枚有「架上／对面那盘／货盘」三个去处，
# 27 种摆法与 −13..+13 的整数差一一对应，所以 1 至 13 的每一单都只有一种摆法配得平。
# 三单的摆法——4：1、3 在对面；13：三枚全在对面；7：9、1 在对面、3 站到货物这头——
# 4 与 13 只差一枚 9，13 与 7 只差一枚 3（那枚 3 从对面挪到货盘，两盘一下差出 6 个单位），
# 可 4 与 7 看着只差 3 个单位，动的却是两枚。于是三单走得完的顺序只有 4→13→7 与 7→13→4 两条：
# 13 那一单必须走在中间，从它开局最多只交得出两单，剩下的那一单怎么挪都挪不动。
# 记法沿用第五幕那具双向秤的约定（一盘一个 0/1 数组，同一枚在两盘都记 1 就是把它用了第二遍），
# 但本关自己实现判秤：这里不 preload、也不依赖 MK11 的任何文件。
# 盘面合计、倾斜、读数全部在这里现算，画面不另存任何秤上的状态；提交之前秤始终锁着制动，
# 摆放时只看得到砝码站到哪一头，永远不预告该接哪一单、这一式平不平。规则层是纯函数：
# 不 preload 场景、不碰 Node、不用随机，同一个输入永远得到同一个输出。
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
# 点一下就往前走一格：架 → 对面那盘 → 货盘 → 架。三个去处两两相邻，
# 所以「只许挪一枚」这一条只约束同一时间能动几枚，不限制那一枚挪到哪儿。
const NEXT = [FAR, OFF, GOODS]
# 街上送来的三单真货：数字是订单上写好的，玩家不填；谁先上秤由玩家点车挑。
const ORDERS = [4, 7, 13]
const ORDER_NAMES = ["订单一", "订单二", "订单三"]
# 三单从小到大各配一只封好的油纸包：13 单位那一单最大，一眼看得出压下去的是最沉的一只。
const ORDER_KITS = ["parcel_small", "parcel_medium", "parcel_large"]
const ORDER_TAGS = ["桥头灯行", "中街油铺", "河下米行"]
# 三辆车就是三单的去处：每一单的货停在属于自己的那一辆上，交完就跟着车走。
const CARTS = ["cart_left", "cart_middle", "cart_right"]
# 还没接单时 state.order 的值：三辆车都还在街上，货盘是空的。
const NONE = -1
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
	return {"sample": "market-mk14-1", "stage": "arrival", "beat": 0, "order": NONE,
		"goods": empty_pan(), "far": empty_pan(), "served": [], "built_goods": empty_records(),
		"built_far": empty_records(), "weighs": 0, "hint": 0}

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

static func legal_order(index: Variant) -> bool:
	return index is int and index >= NONE and index < ORDERS.size()

static func on_pan(state: Dictionary, side: int, index: int) -> bool:
	if not legal_index(index): return false
	if side == GOODS: return state.goods[index] == 1
	if side == FAR: return state.far[index] == 1
	return false

static func side_of(state: Dictionary, index: int) -> int:
	return side_of_record(state.goods, state.far, index)

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

static func order_tag(index: int) -> String:
	if index < 0 or index >= ORDERS.size(): return "街上"
	return ORDER_TAGS[index]

# 走到秤前、接单之后货才在盘上；交完跟着车走、收摊，盘上就只剩砝码。
static func cargo_on_pan(state: Dictionary) -> bool:
	return state.order >= 0 and state.stage not in ["arrival", "approach", "complete"]

static func cargo_units(state: Dictionary) -> int:
	return order_units(state.order) if cargo_on_pan(state) else 0

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

# 货是真的、两盘一样重，就只这一条：平的不一定是这一单该平的那一式，
# 但 1 至 13 每一单只有一种摆法配得平，平了也就只能是那一式。
static func solved(state: Dictionary) -> bool:
	return cargo_on_pan(state) and balanced(state)

# 秤杆静止时的倾角比例：−1 货盘沉到底，0 平，+1 对面沉到底。角度由画面按同一符号换算。
static func tilt(state: Dictionary) -> float:
	return clampf(float(difference(state)) / float(FULL_TILT), -1.0, 1.0)

static func pan_name(side: int) -> String:
	if side == GOODS: return "货盘"
	if side == FAR: return "对面那盘"
	return "砝码架"

# 迁移那一行要挤在 276 像素宽的回执纸里，所以同一头给一个短说法。
static func pan_short(side: int) -> String:
	if side == GOODS: return "货盘"
	if side == FAR: return "对面"
	return "架上"

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
	if index < 0 or index >= ORDERS.size(): return ""
	return "%s · %d 单位 · %s" % [ORDER_NAMES[index], order_units(index), ORDER_TAGS[index]]

# 一辆车的说法：这一单写着几单位、此刻在不在自己那辆车上。
static func is_served(state: Dictionary, index: int) -> bool:
	return state.served.has(index)

static func cart_caption(state: Dictionary, index: int) -> String:
	if index < 0 or index >= ORDERS.size(): return ""
	var text := "%s %d 单位" % [ORDER_TAGS[index], ORDERS[index]]
	if state.order == index: return text + " · 上秤了"
	if is_served(state, index): return text + " · 已交货"
	return text + " · 在车上"

# 一摆法的简述：只说每一枚站在哪儿，供柜面牌与回执引用。
static func pan_list(goods: Array, far: Array, side: int) -> String:
	var names := []
	for index in range(COUNT - 1, -1, -1):
		if (goods if side == GOODS else far)[index] == 1: names.append(str(WEIGHTS[index]))
	return "、".join(names)

static func brief_of(goods: Array, far: Array) -> String:
	var parts := []
	for side in [FAR, GOODS, OFF]:
		var list := pan_list(goods, far, side)
		if side == OFF:
			var on_rack := []
			for index in range(COUNT - 1, -1, -1):
				if side_of_record(goods, far, index) == OFF: on_rack.append(str(WEIGHTS[index]))
			list = "、".join(on_rack)
		if list.is_empty(): continue
		parts.append("%s %s" % [pan_short(side), list])
	return " · ".join(parts)

static func built_brief(state: Dictionary, index: int) -> String:
	if index < 0 or index >= ORDERS.size(): return ""
	return brief_of(state.built_goods[index], state.built_far[index])

# 上一单记进账里的那一摆法：柜面牌说的就是它，画面不另立一套说法。
static func baseline_caption(state: Dictionary) -> String:
	if state.served.is_empty(): return ""
	return "%d 单位的摆法：%s" % [ORDERS[state.served[state.served.size() - 1]],
		brief_of(state.built_goods[state.served[state.served.size() - 1]],
			state.built_far[state.served[state.served.size() - 1]])]

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

# 交付那一刻的说法：账上还没记这一单，所以「还剩几单」说的是交完这一单之后的街上。
# 最后一单没有「下一单」可提醒，就老实说这三枚一枚也没添。
static func delivery_line(state: Dictionary) -> String:
	var head := "衡伯画押：%s的 %d 单位当场配平。" % [order_tag(state.order), order_units(state.order)]
	if state.served.size() < ORDERS.size() - 1:
		return head + "\n还有 %d 单在街上，下一单只许挪一枚砝码。" % (ORDERS.size() - 1 - state.served.size())
	return head + "\n三单都兑完了，砝码一枚也没有再添。"

# ---- 迁移账：回执上那几行，全部从记账的摆法现算 ----
static func delivered(state: Dictionary) -> int: return state.served.size()

static func remaining(state: Dictionary) -> Array:
	var out := []
	for index in range(ORDERS.size()):
		if not state.served.has(index): out.append(index)
	return out

static func remaining_units(state: Dictionary) -> Array:
	var out := []
	for index in remaining(state): out.append(ORDERS[index])
	return out

# 两式之间差几枚：同一枚站在不同两头就算一处。
static func diff_sides(a: Array, b: Array) -> Array:
	var hit := []
	for index in range(COUNT):
		if side_of_record(a[0], a[1], index) != side_of_record(b[0], b[1], index): hit.append(index)
	return hit

static func record_of(goods: Array, far: Array) -> Array:
	return [goods, far]

static func moved_indices(units_from: int, units_to: int) -> Array:
	var a := arrangements_for(units_from)
	var b := arrangements_for(units_to)
	if a.is_empty() or b.is_empty(): return [0, 1, 2]
	return diff_sides(record_of(a[0].goods, a[0].far), record_of(b[0].goods, b[0].far))

static func one_move(units_from: int, units_to: int) -> bool:
	return moved_indices(units_from, units_to).size() == 1

# 每一单的摆法都只有一种（见 spans_all 检查），所以「上一单到这一单挪动的是哪几枚」是确定的事。
static func step_indices(state: Dictionary, step: int) -> Array:
	if step <= 0 or step >= state.served.size(): return []
	return moved_indices(ORDERS[state.served[step - 1]], ORDERS[state.served[step]])

# 上一单的记账摆法：头一单还没记下来的时候返回空，意思是「还没上锁，随便摆」。
static func baseline(state: Dictionary) -> Array:
	if state.served.is_empty(): return []
	var last: int = state.served[state.served.size() - 1]
	return [state.built_goods[last], state.built_far[last]]

# 此刻与上一单的摆法相比挪了哪几枚：这一条是本关的账，也是 validate 的硬约束。
static func moved(state: Dictionary) -> Array:
	var base := baseline(state)
	if base.is_empty(): return []
	return diff_sides([state.goods, state.far], base)

static func moved_count(state: Dictionary) -> int: return moved(state).size()

# 还能不能碰这一枚：要么一枚都没挪，要么只碰已经挪过的那一枚（挪回原处也算）。
static func can_touch(state: Dictionary, index: int) -> bool:
	if not legal_index(index): return false
	var hit := moved(state)
	return hit.is_empty() or (hit.size() == 1 and hit[0] == index)

static func within_one_move(state: Dictionary) -> bool:
	return moved_count(state) <= 1

# 拦下的时候点名已经挪过的那一枚：规则说得清，玩家才不用猜是哪一步越了界。
static func touch_refusal(state: Dictionary, index: int) -> String:
	var hit := moved(state)
	if hit.is_empty() or (hit.size() == 1 and hit[0] == index): return ""
	if not legal_index(index): return ""
	return "%d 单位那一枚已经挪过了：一单只许挪一枚，先把它挪回原处。" % WEIGHTS[hit[0]]

# 下一单接不接得动：还有哪一单的摆法与上一单只差一枚。
static func reachable_units(state: Dictionary) -> Array:
	var out := []
	var base := baseline(state)
	if base.is_empty(): return remaining_units(state)
	for index in remaining(state):
		var found := arrangements_for(ORDERS[index])
		if found.is_empty(): continue
		if diff_sides(record_of(found[0].goods, found[0].far), base).size() <= 1: out.append(ORDERS[index])
	return out

# 走死了：秤上还摆着上一单记下的那一式，剩下的每一单都得动两枚以上。
# 这一条不藏：柜面那一幕的说法与「重摆」那句提示都从它取，跟 MK02、MK17 同一套诚实写法。
static func stuck(state: Dictionary) -> bool:
	if state.served.is_empty() or not remaining(state).size(): return false
	return reachable_units(state).is_empty()

static func stuck_line(state: Dictionary) -> String:
	var units := remaining_units(state)
	return "三单里只剩 %s 单位那一单，可从 %d 单位记下的摆法起，两枚砝码都得动。\n要接着走下去，就按「重摆」把三枚放回架上，从头挑一单。" % [
		"、".join(str_array(units)), ORDERS[state.served[state.served.size() - 1]]]

# 回执上逐单迁移的那几行：起手一式，然后每走一步只说挪了哪一枚、从哪儿到哪儿。
static func migration_parts(state: Dictionary) -> Array:
	var parts := []
	for step in range(state.served.size()):
		var here: int = state.served[step]
		var goods: Array = state.built_goods[here]
		var far: Array = state.built_far[here]
		if step == 0:
			parts.append("起手 %d 单位：%s" % [ORDERS[here], brief_of(goods, far)])
			continue
		var hit := step_indices(state, step)
		var from: int = state.served[step - 1]
		var label := "两枚都动"
		if hit.size() == 1:
			var index: int = hit[0]
			label = "只挪 %d（%s→%s）" % [WEIGHTS[index],
				pan_short(side_of_record(state.built_goods[from], state.built_far[from], index)),
				pan_short(side_of_record(goods, far, index))]
		parts.append("%d → %d：%s" % [ORDERS[from], ORDERS[here], label])
	return parts

static func migration_caption(state: Dictionary) -> String:
	return "\n".join(migration_parts(state))

# 三单里「看着最近、其实要动两枚」的那一对：回执最后一行的数学事实，现算不写死。
static func distant_pair() -> Array:
	var best := []
	var best_gap := 0
	for a in range(ORDERS.size()):
		for b in range(a + 1, ORDERS.size()):
			if one_move(ORDERS[a], ORDERS[b]) or moved_indices(ORDERS[a], ORDERS[b]).size() <= 1: continue
			var gap := absi(ORDERS[a] - ORDERS[b])
			if best.is_empty() or gap < best_gap:
				best = [ORDERS[a], ORDERS[b], moved_indices(ORDERS[a], ORDERS[b]).size()]
				best_gap = gap
	return best

static func distant_line() -> String:
	var pair := distant_pair()
	if pair.is_empty(): return "三单两两之间都只挪一枚"
	return "%d 与 %d 只差 %d 单位，却要动两枚砝码" % [pair[0], pair[1], absi(pair[0] - pair[1])]

# ---- 数学事实：作者验算用，运行时只在回执与提示那一行文字里出现 ----
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

# 只把砝码放在对面那一盘时，能配出的量：1、3、9 的子集和。13 是它的最大者，也就是那一式。
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

# 回执上那句「1 至 13 都配得出来、而且各只一种」是不是真话，由这条检查兜住。
static func spans_all() -> bool:
	var span := span_units()
	if span.size() != WEIGHT_TOTAL: return false
	for step in range(WEIGHT_TOTAL):
		if span[step] != step + 1: return false
		if arrangements_for(step + 1).size() != 1: return false
	return true

static func str_array(values: Array) -> Array:
	var out := []
	for value in values: out.append(str(value))
	return out

# 三单走到底的那两条顺序：本关的答案其实只有「谁走在中间」这一件事，由检查逐条对账。
static func serve_orders(sequence: Array) -> Dictionary:
	var next = fresh()
	# 台词三句必须算走完：不这么做，choose/arrange 里的 validate 会把这些中间现场一律判成跳步。
	next.stage = "puzzle"; next.beat = BEATS - 1
	for index in sequence:
		if index < 0 or index >= ORDERS.size(): return {}
		next = choose(next, index)
		if next.is_empty(): return {}
		var spot := arrangements_for(ORDERS[index])
		if spot.is_empty(): return {}
		next = arrange(next, spot[0].goods, spot[0].far)
		if next.is_empty(): return {}
		next = advance(next)
		if next.is_empty() or next.stage != "weighing": return {}
		next = advance(next)
		if next.is_empty() or next.stage != "delivery": return {}
		next = advance(next)
		if next.is_empty(): return {}
	return next

# 把一式直接摆到盘上（检查与「挑单」用的辅助，绕开逐枚挪动，但不绕开 validate）。
static func arrange(state: Dictionary, goods: Array, far: Array) -> Dictionary:
	if state.stage != "puzzle": return {}
	var next = state.duplicate(true)
	for index in range(COUNT):
		next.goods[index] = goods[index]
		next.far[index] = far[index]
	return next if validate(next) else {}

# ---- 玩家动作 ----
static func can_cycle(state: Dictionary, index: int) -> bool:
	return state.stage == "puzzle" and legal_index(index)

# 把一枚砝码请上某一盘；它原本站在另一盘时就是「挪过来」，两盘永远不同时记下同一枚。
# 只许挪一枚：要动第二枚，这里就返回空，画面与台词都去问 touch_refusal。
static func place_weight(state: Dictionary, index: int, side: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_index(index) or not legal_side(side): return {}
	if side_of(state, index) == side or not can_touch(state, index): return {}
	var next = state.duplicate(true)
	next.goods[index] = 1 if side == GOODS else 0
	next.far[index] = 1 if side == FAR else 0
	return next if validate(next) else {}

static func return_weight(state: Dictionary, index: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_index(index) or side_of(state, index) == OFF: return {}
	if not can_touch(state, index): return {}
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

# 挑哪一单先上秤：车上的货被搬到指定的货盘上，数字本身不许改。
static func can_choose(state: Dictionary, index: int) -> bool:
	if state.stage != "puzzle" or index < 0 or index >= ORDERS.size(): return false
	return not state.served.has(index)

static func choose(state: Dictionary, index: int) -> Dictionary:
	if not can_choose(state, index): return {}
	var next = state.duplicate(true)
	next.order = index
	return next if validate(next) else {}

# ---- 提交闸口：只管「手底下还没动手」，不判数学 ----
static func shortfalls(state: Dictionary) -> Array:
	var missing := []
	if state.order < 0:
		missing.append("街上三辆车还没有一辆被你点中：先挑一单，衡伯才把货搬上货盘。")
	if weights_on_scale(state) == 0:
		missing.append("三枚砝码都还在架上：先请一枚上秤，空盘配不出这一单的货。")
	return missing

static func ready_to_weigh(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

# 交付那一刻把这单的摆法记进账里：之后的回执与纪念物只复述这些真账。
static func booked(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	next.built_goods[next.order] = next.goods.duplicate(true)
	next.built_far[next.order] = next.far.duplicate(true)
	next.served.append(next.order)
	next.order = NONE
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
			# 提秤不看对错：接了单、请了砝码上秤，秤就抬。平不平由演出如实给出。
			if not ready_to_weigh(state): return {}
			next.weighs += 1
			next.stage = "weighing"
		"weighing": next.stage = "delivery" if balanced(state) else "result"
		"result":
			# 记下这一次的结果就回到秤前：摆法原样保留，一枚砝码都不扣。
			next.stage = "puzzle"
		"delivery":
			if not balanced(state) or state.order < 0: return {}
			next = booked(state)
			next.stage = "complete" if next.served.size() == ORDERS.size() else "puzzle"
		_: return {}
	return next if validate(next) else {}

# 重摆：三枚砝码回到架上，三单货都退回各自的车，已经签了收的那几单也重新排过。
# 抬过几次秤是街上已经发生过的事，不清零。
static func cleared(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	var next = state.duplicate(true)
	next.goods = empty_pan()
	next.far = empty_pan()
	next.order = NONE
	next.served = []
	next.built_goods = empty_records()
	next.built_far = empty_records()
	return next if validate(next) else {}

static func legal_served(value: Variant) -> bool:
	if not value is Array or value.size() > ORDERS.size(): return false
	for index in value:
		if not index is int or index < 0 or index >= ORDERS.size(): return false
		if value.count(index) > 1: return false
	return true

static func legal_snapshot(snapshot: Dictionary) -> bool:
	return snapshot.get("goods") is Array and snapshot.get("far") is Array and snapshot.get("order") is int

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or not legal_snapshot(snapshot): return {}
	if not legal_pan(snapshot.goods) or not legal_pan(snapshot.far): return {}
	if not legal_order(snapshot.order): return {}
	var next = state.duplicate(true)
	next.goods = snapshot.goods.duplicate(true)
	next.far = snapshot.far.duplicate(true)
	next.order = int(snapshot.order)
	# 抬秤次数与已经签了收的那几单都是发生过的事，快照里没有它们，也就改不动。
	return next if validate(next) else {}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk14-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINT_TIERS: return false
	if not legal_order(value.get("order")): return false
	if not value.get("weighs") is int or value.weighs < 0: return false
	if not legal_pan(value.get("goods")) or not legal_pan(value.get("far")): return false
	if not legal_served(value.get("served")): return false
	if not legal_records(value.get("built_goods")) or not legal_records(value.get("built_far")): return false
	# 每枚砝码最多用一次：同一枚同时站在两个盘上，就是把它偷偷用了第二遍。
	for index in range(COUNT):
		if value.goods[index] == 1 and value.far[index] == 1: return false
	# 正在配的这一单不能是已经签了收的那一单：交出去的货不会再压回盘上。
	if value.order >= 0 and value.served.has(value.order): return false
	# 台词没走完就写成后面的幕，是凭空跳步。
	if value.stage != "arrival" and value.beat != BEATS - 1: return false
	# 还没走到秤前：三枚砝码都在架上，一单也没交出去，账上三格都是空的。
	if value.stage in ["arrival", "approach", "ready"]:
		if value.order != NONE or not value.served.is_empty() or value.weighs != 0: return false
		if not value.goods == empty_pan() or not value.far == empty_pan(): return false
		if not value.built_goods == empty_records() or not value.built_far == empty_records(): return false
	# 站在秤前的每一幕：没接单就是还没挑，挑了就必须是还没交出去的那一单。
	if value.stage in ["weighing", "result", "delivery"] and value.order < 0: return false
	# 秤已经抬起来过的每一幕都必须真的抬过至少一次秤。
	if value.stage in ["weighing", "result", "delivery", "complete"] and value.weighs < 1: return false
	# 「结果牌还立着」与「这一单其实已经配平了」不能同时成立。
	if value.stage == "result" and balanced(value): return false
	# 交付那一幕只认两盘真的平了。
	if value.stage == "delivery" and not balanced(value): return false
	# 记进账里的每一单都要真的把那单的货配平；没交出去的单一律留空。
	for index in range(ORDERS.size()):
		if value.served.has(index):
			if not balances(value.built_goods[index], value.built_far[index], ORDERS[index]): return false
		elif not value.built_goods[index] == empty_pan() or not value.built_far[index] == empty_pan(): return false
	# 已经交出去的每一单，都得是从上一单的摆法里挪一枚砝码挪出来的：这是本关的规矩本身。
	for step in range(1, value.served.size()):
		var here: int = value.served[step]
		var there: int = value.served[step - 1]
		if diff_sides([value.built_goods[there], value.built_far[there]],
			[value.built_goods[here], value.built_far[here]]).size() > 1: return false
	# 此刻盘上的摆法也不能越过这条线：没接单时也必须离上一单的账不超过一枚。
	if not within_one_move(value): return false
	if value.stage == "complete":
		if value.served.size() != ORDERS.size(): return false
		# 收摊之后砝码不再动：完成时的现场就是最后一单记下的那一式。
		var last: int = value.served[ORDERS.size() - 1]
		if not value.goods == value.built_goods[last]: return false
		if not value.far == value.built_far[last]: return false
	return true

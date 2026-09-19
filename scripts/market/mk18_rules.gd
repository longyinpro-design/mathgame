extends RefCounted

# MK18 万签守约兽「让每一盏灯都有回信」：全章的联合履约，三阶段共用一台机关。
#
# 第一阶段 · 共同订单：三街与船员当场确认新单位——桥头 3油1芯、中街 4油2芯、西坡 5油3芯，
# 领航灯另留 2油1芯，总计 14 油 7 芯，没有任何隐藏收费。采购台只卖三种封装
# A=3油+1芯 5票、B=1油+2芯 4票、C=2油 3票；库存 A4/B4/C5，预算 29 票，必须恰好凑齐总量。
# 库存内的 150 种摆法里只有一行同时满足 14 油、7 芯、29 票：A1 · B3 · C4（测试逐行枚举核对）。
# 玩家按包种一次选数量、提交整单，不演成八次重复点击购物。
#
# 第二阶段 · 一封更正信：桥头街真的交完之后，中街/西坡的最终安排才公开。
# 分支甲维持 4/2、5/3；分支乙改为 5/1、4/4。两种安排与各自适用的确认印记开局都读得到，
# 实际分支在关卡创建时固定并写进存档——读档、反复读信都不会重抽。
# 两街加领航灯仍是 11 油 6 芯，但旧的逐街分装不能直接沿用。封装在这一阶段允许拆开分配，
# 不再购买；界面只显当前摆了多少，不替玩家算该挪哪一组。整单预览在实际交货前可以撤回。
#
# 第三阶段 · 把最后的灯送出去：玩家亲手把预留的 2 油 1 芯装进领航灯，
# 万签胸前一直转动的空信槽收到三张真实回执才合拢，灯架展开成一艘明亮的灯船。
#
# 胜利三件缺一不可：本局正确采购、按实际分支完成三街交付、领航灯足额点亮。
# 只凑出一个总数、或者只点亮三条街，都不算过关。
# 规则层是纯函数：不 preload 场景、不碰 Node、不用随机，同一个输入永远得到同一个输出。
const OIL = 0
const WICK = 1
# 四线共同订单的固定顺序：桥头、中街、西坡、领航灯。永远不按多少重排。
const LINES = ["桥头街", "中街", "西坡街", "领航灯"]
# 第一阶段当场确认的安排，也是分支甲（维持）；分支乙把中街/西坡改成 5/1、4/4。
const NEEDS_A = [[3, 1], [4, 2], [5, 3], [2, 1]]
const NEEDS_B = [[3, 1], [5, 1], [4, 4], [2, 1]]
const BRANCH_SEALS = ["甲印 · 维持原安排", "乙印 · 更正安排"]
# 第二阶段还能接货的三处：中街、西坡、领航灯（桥头已经交完，货台不再动它）。
const SLOTS = 3
const FIRST_STREET = 0
# 采购台的三种封装、单价与库存。
const KINDS = 3
const PACKS = [[3, 1], [1, 2], [2, 0]]
const PACK_NAMES = ["A", "B", "C"]
const PRICES = [5, 4, 3]
const STOCK = [4, 4, 5]
const BUDGET = 29
# 共同订单总量与领航灯预留：14 油 7 芯，桥头交完后货台上还剩 11 油 6 芯。
const TOTAL_OIL = 14
const TOTAL_WICK = 7
const RESERVED = [2, 1]
const ARRIVAL_BEATS = 4
const CLARIFY_BEATS = 3
const HINT_TIERS = 3
const NO_BRANCH = -1
const STAGES = ["arrival", "approach", "ready", "puzzle", "stocking", "clarify",
	"delivering", "lighting", "voyage", "complete"]
const ANIMATIONS = ["approach", "stocking", "delivering", "lighting", "voyage"]
# clarify 是读信的停点，不是动画：只有会自己走完的幕才算演出。
const BEAT_CAP = ARRIVAL_BEATS if ARRIVAL_BEATS > CLARIFY_BEATS else CLARIFY_BEATS
# 新开这一幕时两种回信轮流固定（检查里两条都要走一遍）；读档永远沿用存档里的那一个。
static var branch_roll = 0

static func empty_order() -> Array:
	var counts = []
	for kind in range(KINDS): counts.append(0)
	return counts

static func empty_alloc() -> Array:
	var rows = []
	for slot in range(SLOTS): rows.append([0, 0])
	return rows

static func empty_sealed() -> Array:
	var rows = []
	for _street in range(3): rows.append(0)
	return rows

static func roll_branch() -> int:
	var branch: int = branch_roll % 2
	branch_roll += 1
	return branch

# 宿主只会以 no-arg 方式调用：分支自己轮流固定。检查可以显式点名要哪一封回信。
static func fresh(branch: int = NO_BRANCH) -> Dictionary:
	return {"sample": "market-mk18-1", "stage": "arrival", "beat": 0, "hint": 0,
		"branch": roll_branch() if branch == NO_BRANCH else branch,
		"order": empty_order(), "bought": empty_order(),
		"alloc": empty_alloc(), "handed": empty_alloc(),
		"preview": 0, "lamp": 0, "sealed": empty_sealed()}

# ---- 本局公开的共同订单 ----
static func legal_branch(branch: Variant) -> bool:
	return branch is int and (branch == 0 or branch == 1)

static func needs(branch: int) -> Array:
	return NEEDS_B.duplicate(true) if branch == 1 else NEEDS_A.duplicate(true)

# 第二阶段还要兑现的三线：中街、西坡、领航灯。
static func slot_needs(branch: int) -> Array:
	var rows = needs(branch)
	var result = []
	for slot in range(SLOTS): result.append(rows[slot + 1])
	return result

static func total_of(branch: int) -> Array:
	var oil := 0
	var wick := 0
	for row in needs(branch):
		oil += row[OIL]; wick += row[WICK]
	return [oil, wick]

# 桥头交完、领航灯还没点亮时，货台上真正能动用的货。
static func pool() -> Array:
	var total = total_of(0)
	return [total[OIL] - NEEDS_A[FIRST_STREET][OIL], total[WICK] - NEEDS_A[FIRST_STREET][WICK]]

static func branch_word(branch: int) -> String:
	return BRANCH_SEALS[1] if branch == 1 else BRANCH_SEALS[0]

static func goods(oil: int, wick: int) -> String:
	return "%d 提油 %d 束芯" % [oil, wick]

# ---- 派生读数：一律现算，画面不另存计数 ----
static func legal_order(value: Variant) -> bool:
	if not value is Array or value.size() != KINDS: return false
	for kind in range(KINDS):
		var count: Variant = value[kind]
		if not count is int or count < 0 or count > STOCK[kind]: return false
	return true

static func legal_alloc(value: Variant) -> bool:
	if not value is Array or value.size() != SLOTS: return false
	for row in value:
		if not row is Array or row.size() != 2: return false
		for cell in row:
			if not cell is int or cell < 0: return false
		if row[OIL] > 20 or row[WICK] > 20: return false
	return true

static func legal_sealed(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for one in value:
		if not one is int or (one != 0 and one != 1): return false
	return true

static func oil_of(order: Array) -> int:
	var total := 0
	for kind in range(KINDS): total += PACKS[kind][OIL] * order[kind]
	return total

static func wick_of(order: Array) -> int:
	var total := 0
	for kind in range(KINDS): total += PACKS[kind][WICK] * order[kind]
	return total

static func cost_of(order: Array) -> int:
	var total := 0
	for kind in range(KINDS): total += PRICES[kind] * order[kind]
	return total

static func packs_of(order: Array) -> int:
	var total := 0
	for kind in range(KINDS): total += order[kind]
	return total

static func alloc_total(alloc: Array) -> Array:
	var oil := 0
	var wick := 0
	for row in alloc:
		oil += row[OIL]; wick += row[WICK]
	return [oil, wick]

# 货台上还剩多少：负数就是凭空多出来的货，永远不该出现。
static func alloc_left(alloc: Array) -> Array:
	var used = alloc_total(alloc)
	var room = pool()
	return [room[OIL] - used[OIL], room[WICK] - used[WICK]]

static func within_pool(alloc: Array) -> bool:
	var left = alloc_left(alloc)
	return left[OIL] >= 0 and left[WICK] >= 0

# 这一单买不买得成：恰好 14 油 7 芯、不超库存、总价不超过 29 票。
static func paid_ok(order: Array) -> bool:
	if not legal_order(order): return false
	return oil_of(order) == TOTAL_OIL and wick_of(order) == TOTAL_WICK and cost_of(order) <= BUDGET

static func handed_ok(handed: Array, branch: int) -> bool:
	return legal_alloc(handed) and handed == slot_needs(branch)

# 阶段是从账上推出来的，不是玩家能改的第三个字段：
# 没买过货＝第一阶段，买了还没交＝第二阶段，交出去＝第三阶段。
static func phase_of(state: Dictionary) -> int:
	if not state.has("bought") or not state.has("handed"): return 1
	if state.bought == empty_order(): return 1
	if state.handed == empty_alloc(): return 2
	return 3

# ---- 库存内全部摆法：唯一解与近 miss 都靠它逐行核对 ----
static func enumerate() -> Array:
	var rows = []
	for a in range(STOCK[0] + 1):
		for b in range(STOCK[1] + 1):
			for c in range(STOCK[2] + 1):
				var order = [a, b, c]
				rows.append({"order": order, "oil": oil_of(order), "wick": wick_of(order),
					"cost": cost_of(order)})
	return rows

static func exact_rows() -> Array:
	var rows = []
	for row in enumerate():
		if row.oil == TOTAL_OIL and row.wick == TOTAL_WICK and row.cost <= BUDGET: rows.append(row)
	return rows

# ---- 提交闸口：一次只说一条没兑现的承诺，用玩家自己的说法 ----
static func purchase_shortfalls(order: Array) -> Array:
	var missing = []
	var oil = oil_of(order)
	var wick = wick_of(order)
	var cost = cost_of(order)
	if packs_of(order) == 0:
		return ["采购台上三种封装都还在：先把这一晚要买的整包选出来。"]
	if oil != TOTAL_OIL:
		missing.append("共同订单要 %d 提油，订单上是 %d 提，%s %d 提。" % [
			TOTAL_OIL, oil, "还差" if oil < TOTAL_OIL else "多了", abs(TOTAL_OIL - oil)])
	if wick != TOTAL_WICK:
		missing.append("共同订单要 %d 束芯，订单上是 %d 束，%s %d 束。" % [
			TOTAL_WICK, wick, "还差" if wick < TOTAL_WICK else "多了", abs(TOTAL_WICK - wick)])
	if cost > BUDGET:
		missing.append("这一单要 %d 票，货栈今晚只肯给 %d 票，超了 %d 票。" % [cost, BUDGET, cost - BUDGET])
	return missing

static func purchase_ok(order: Array) -> bool:
	return purchase_shortfalls(order).is_empty()

static func alloc_shortfalls(alloc: Array, branch: int) -> Array:
	var missing = []
	var left = alloc_left(alloc)
	# 先说凭空多出来的货：这不是哪一街没接满，而是货台上根本没有这些货。
	if left[OIL] < 0 or left[WICK] < 0:
		missing.append("货台上只有 %s：现在摆出了 %s，多出来的 %s不是货栈给的。" % [
			goods(pool()[OIL], pool()[WICK]), goods(alloc_total(alloc)[OIL], alloc_total(alloc)[WICK]),
			"灯油" if left[OIL] < 0 else "灯芯"])
		return missing
	var rows = slot_needs(branch)
	for slot in range(SLOTS):
		if alloc[slot] == rows[slot]: continue
		var name = LINES[slot + 1]
		if slot == SLOTS - 1:
			missing.append("%s要留 %s：今晚这盏灯要送到海上，现在只留了 %s。" % [
				name, goods(rows[slot][OIL], rows[slot][WICK]), goods(alloc[slot][OIL], alloc[slot][WICK])])
		else:
			missing.append("%s的%s要 %s，现在摆的是 %s。" % [
				name, "更正回执" if branch == 1 else "回执",
				goods(rows[slot][OIL], rows[slot][WICK]), goods(alloc[slot][OIL], alloc[slot][WICK])])
	return missing

static func lamp_shortfalls(state: Dictionary) -> Array:
	var missing = []
	if state.lamp == 0:
		missing.append("领航灯还空着：预留的 %s 还没亲手装进灯里。" % goods(RESERVED[OIL], RESERVED[WICK]))
	for street in range(3):
		if state.sealed[street] == 0:
			missing.append("万签胸前的空信槽还张着：%s的回执还没投进去。" % LINES[street])
	return missing

static func shortfalls(state: Dictionary) -> Array:
	match phase_of(state):
		1: return purchase_shortfalls(state.order)
		2: return alloc_shortfalls(state.alloc, state.branch)
		3: return lamp_shortfalls(state)
	return []

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

# 三件胜利条件各自成立与否——只凑出总数或只点亮三条街都不算。
static func win_parts(state: Dictionary) -> Dictionary:
	return {"bought": paid_ok(state.bought),
		"streets": handed_ok(state.handed, state.branch),
		"lamp": state.lamp == 1 and state.sealed == [1, 1, 1]}

static func win_ok(state: Dictionary) -> bool:
	var parts = win_parts(state)
	return parts.bought and parts.streets and parts.lamp

# ---- 玩家动作 ----
static func can_set_count(state: Dictionary, kind: int, count: int) -> bool:
	if state.stage != "puzzle" or phase_of(state) != 1: return false
	if kind < 0 or kind >= KINDS or count < 0 or count > STOCK[kind]: return false
	return state.order[kind] != count

# 按包种一次选数量：点到第几包就订到第几包，点回已经订着的最前面那一包就退一格。
static func set_count(state: Dictionary, kind: int, count: int) -> Dictionary:
	if not can_set_count(state, kind, count): return {}
	var next = state.duplicate(true)
	next.order[kind] = count
	return next if validate(next) else {}

static func can_put(state: Dictionary, slot: int, kind: int) -> bool:
	if state.stage != "puzzle" or phase_of(state) != 2: return false
	if slot < 0 or slot >= SLOTS or (kind != OIL and kind != WICK): return false
	return alloc_left(state.alloc)[kind] > 0

static func put(state: Dictionary, slot: int, kind: int) -> Dictionary:
	if not can_put(state, slot, kind): return {}
	var next = state.duplicate(true)
	next.alloc[slot][kind] += 1
	# 摆动了货物，之前那份整单预览就作废了——预览说的必须是眼前这一份。
	if next.preview == 1: next.preview = 0
	return next if validate(next) else {}

static func can_take_back(state: Dictionary, slot: int, kind: int) -> bool:
	if state.stage != "puzzle" or phase_of(state) != 2: return false
	if slot < 0 or slot >= SLOTS or (kind != OIL and kind != WICK): return false
	return state.alloc[slot][kind] > 0

static func take_back(state: Dictionary, slot: int, kind: int) -> Dictionary:
	if not can_take_back(state, slot, kind): return {}
	var next = state.duplicate(true)
	next.alloc[slot][kind] -= 1
	# 摆动了货物，之前那份整单预览就作废了——预览说的必须是眼前这一份。
	if next.preview == 1: next.preview = 0
	return next if validate(next) else {}

static func make_preview(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or phase_of(state) != 2 or state.preview == 1: return {}
	if not alloc_shortfalls(state.alloc, state.branch).is_empty(): return {}
	var next = state.duplicate(true)
	next.preview = 1
	return next if validate(next) else {}

static func cancel_preview(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or phase_of(state) != 2 or state.preview == 0: return {}
	var next = state.duplicate(true)
	next.preview = 0
	return next if validate(next) else {}

static func load_lamp(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or phase_of(state) != 3 or state.lamp == 1: return {}
	if state.handed[SLOTS - 1] != RESERVED: return {}
	var next = state.duplicate(true)
	next.lamp = 1
	return next if validate(next) else {}

static func unload_lamp(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or phase_of(state) != 3 or state.lamp == 0: return {}
	var next = state.duplicate(true)
	next.lamp = 0
	return next if validate(next) else {}

static func seal_receipt(state: Dictionary, street: int) -> Dictionary:
	if state.stage != "puzzle" or phase_of(state) != 3: return {}
	if street < 0 or street > 2 or state.sealed[street] == 1: return {}
	var next = state.duplicate(true)
	next.sealed[street] = 1
	return next if validate(next) else {}

static func unseal_receipt(state: Dictionary, street: int) -> Dictionary:
	if state.stage != "puzzle" or phase_of(state) != 3: return {}
	if street < 0 or street > 2 or state.sealed[street] == 0: return {}
	var next = state.duplicate(true)
	next.sealed[street] = 0
	return next if validate(next) else {}

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	if snapshot.has("branch") or snapshot.has("bought") or snapshot.has("handed"): return {}
	for key in ["phase", "order", "alloc", "preview", "lamp", "sealed"]:
		if not snapshot.has(key): return {}
	if snapshot.phase != phase_of(state): return {}
	var next = state.duplicate(true)
	next.order = snapshot.order.duplicate(true)
	next.alloc = snapshot.alloc.duplicate(true)
	next.preview = snapshot.preview
	next.lamp = snapshot.lamp
	next.sealed = snapshot.sealed.duplicate(true)
	return next if validate(next) else {}

static func advance(state: Dictionary) -> Dictionary:
	# 只往前一幕：残缺字典一律不推进，避免把不存在的步骤当成走过。
	if not state.has("stage") or not state.has("beat"): return {}
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < ARRIVAL_BEATS - 1: next.beat += 1
			else:
				next.stage = "approach"; next.beat = 0
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			match phase_of(state):
				1:
					if not purchase_ok(state.order): return {}
					# 一次付清：先入账（记下真正买下的整包），再演搬运。
					next.bought = state.order.duplicate(true)
					next.stage = "stocking"
				2:
					if not alloc_shortfalls(state.alloc, state.branch).is_empty(): return {}
					if state.preview == 0:
						next.preview = 1
					else:
						next.handed = state.alloc.duplicate(true)
						next.stage = "delivering"
				3:
					if not win_ok(state): return {}
					next.stage = "lighting"
				_: return {}
			# 每一阶段都有自己三级提示：跨阶段推进才把计数归零，同一阶段内不重置。
			if next.stage != "puzzle": next.hint = 0
		"stocking": next.stage = "clarify"
		"clarify":
			if state.beat < CLARIFY_BEATS - 1: next.beat += 1
			else:
				next.stage = "puzzle"; next.beat = 0
		"delivering": next.stage = "puzzle"
		"lighting": next.stage = "voyage"
		"voyage": next.stage = "complete"
		_: return {}
	return next

# ---- 柜面与回执文字：只复述玩家真正做过的事 ----
static func pack_caption(kind: int) -> String:
	var pack = PACKS[kind]
	return "%s · %d油+%d芯 · %d票" % [PACK_NAMES[kind], pack[OIL], pack[WICK], PRICES[kind]]

static func order_caption(order: Array) -> String:
	return "订单 %s · %d 票" % [goods(oil_of(order), wick_of(order)), cost_of(order)]

static func need_caption(branch: int, line: int) -> String:
	var row = needs(branch)[line]
	return "%s %d油%d芯" % [LINES[line], row[OIL], row[WICK]]

# 信纸上的短行：给一张表（NEEDS_A 或 needs(branch)）和第几行，回一句最紧凑的「桥头 3/1」。
static func line_caption(rows: Array, line: int) -> String:
	var row = rows[line]
	return "%s %d/%d" % [LINES[line], row[OIL], row[WICK]]

static func total_caption() -> String:
	return "合计 %s · 没有隐藏收费" % goods(TOTAL_OIL, TOTAL_WICK)

# 三街实际拿到多少，全部从 bought/handed 读回，绝不写死「标准答案」。
static func delivery_lines(state: Dictionary) -> Array:
	var rows = needs(state.branch)
	var lines = ["%s %s · 更正前已交" % [LINES[0], goods(rows[0][OIL], rows[0][WICK])]]
	for slot in range(SLOTS - 1):
		lines.append("%s %s · 按%s交货" % [LINES[slot + 1], goods(state.handed[slot][OIL], state.handed[slot][WICK]),
			"更正回执" if state.branch == 1 else "原回执"])
	lines.append("领航灯 %s · %s" % [goods(RESERVED[OIL], RESERVED[WICK]),
		"已点亮" if state.lamp == 1 else "还空着"])
	return lines

static func purchase_line(order: Array) -> String:
	var parts = []
	for kind in range(KINDS):
		if order[kind] > 0: parts.append("%s×%d" % [PACK_NAMES[kind], order[kind]])
	return " · ".join(parts) if not parts.is_empty() else "没买整包"

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk18-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEAT_CAP - 1: return false
	# 开场四句与读信三句各自走完，其余幕不留半截台词。
	if value.stage == "arrival" and value.beat > ARRIVAL_BEATS - 1: return false
	if value.stage == "clarify" and value.beat > CLARIFY_BEATS - 1: return false
	if value.stage != "arrival" and value.stage != "clarify" and value.beat != 0: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINT_TIERS: return false
	if not legal_branch(value.get("branch")): return false
	if not legal_order(value.get("order")) or not legal_order(value.get("bought")): return false
	if not legal_alloc(value.get("alloc")) or not legal_alloc(value.get("handed")): return false
	if not legal_sealed(value.get("sealed")): return false
	if not value.get("preview") is int or (value.preview != 0 and value.preview != 1): return false
	if not value.get("lamp") is int or (value.lamp != 0 and value.lamp != 1): return false
	# 领航灯的预留份额永远不能被人挪走：交出去的第三线必须还是 2 油 1 芯。
	if value.handed[SLOTS - 1] != RESERVED and value.handed != empty_alloc(): return false
	# 凭空多出来的货不是货栈给的：任何一份分配都不能超过桥头交货后剩下的 11 油 6 芯。
	if not within_pool(value.alloc) or not within_pool(value.handed): return false
	match value.stage:
		"arrival", "approach", "ready":
			if value.order != empty_order() or value.bought != empty_order(): return false
			if value.alloc != empty_alloc() or value.handed != empty_alloc(): return false
			if value.preview != 0 or value.lamp != 0 or value.sealed != empty_sealed(): return false
			if value.hint != 0: return false
		"puzzle":
			match phase_of(value):
				1:
					# 还没付清：货台上不该有任何分配，也不该有回执。
					if value.alloc != empty_alloc() or value.handed != empty_alloc(): return false
					if value.preview != 0 or value.lamp != 0 or value.sealed != empty_sealed(): return false
				2:
					# 买了货就必须是那一单买得成的整包；这一阶段不再购买，订单不许再动。
					if not paid_ok(value.bought): return false
					if value.order != value.bought: return false
					if value.handed != empty_alloc() or value.lamp != 0: return false
					if value.sealed != empty_sealed(): return false
					# 预览说的必须就是眼前这一份：摆坏了还留着预览，是凭空记账。
					if value.preview == 1 and not alloc_shortfalls(value.alloc, value.branch).is_empty(): return false
				3:
					if not paid_ok(value.bought) or value.order != value.bought: return false
					if value.alloc != value.handed: return false
					if not handed_ok(value.handed, value.branch): return false
					if value.preview != 1: return false
				_: return false
		"stocking", "clarify":
			# 桥头正在交货、更正信正在读：货台上还没开始摆。
			if not paid_ok(value.bought) or value.order != value.bought: return false
			if value.alloc != empty_alloc() or value.handed != empty_alloc(): return false
			if value.preview != 0 or value.lamp != 0 or value.sealed != empty_sealed(): return false
		"delivering":
			if not paid_ok(value.bought): return false
			if value.handed != value.alloc or not handed_ok(value.handed, value.branch): return false
			if value.preview != 1 or value.lamp != 0 or value.sealed != empty_sealed(): return false
		"lighting", "voyage", "complete":
			# 点亮之后的每一幕都必须以三件事实同时成立作证据。
			if not win_ok(value): return false
		_: return false
	return true

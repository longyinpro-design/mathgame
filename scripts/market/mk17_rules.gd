extends RefCounted

# MK17 铜鹭巡守 · 三次验货（千灯集市第一场首领）。契约：docs/production/market_chapter.md 197-211。
# 封装：大包=3 单位、中包=2、小包=1；开局 6 只大包共 18 单位，重新封装机会 3 次。
# 合法操作只有两条规则的两端：1大 ↔ 1中+1小、2大 ↔ 3中。每应用一条就算 1 次机会，
# 反着走同一条规则同样要再花 1 次——绝不存在「把机会退回来、变出的货却留着」。
# 三站依次要 5 / 7 / 6 单位，最多 2 / 4 / 3 包，三站需求之和正好等于总量 18，
# 所以一单位都不能浪费；已交货不回收，三张货单开局就钉在栏上随时可读。
# 二站的验货旗在关卡创建时固定并写进存档（重新读档绝不重掷）：旗A 全收，旗B 不接大包，
# 第一站交完才翻面。参考应对：旗A 用 2 次机会、旗B 用满 3 次，浪费一次就会把旗B 走死。
const LARGE = 0
const MEDIUM = 1
const SMALL = 2
const KINDS = 3
const UNITS = [3, 2, 1]
const PACK_NAMES = ["大包", "中包", "小包"]
const START_STOCK = [6, 0, 0]
const TOTAL_UNITS = 18
const CHANCES = 3
const MAX_EACH = 9
const SUPPLY_CAPS = [6, 9, 3]
const FLAG_A = 1
const FLAG_B = 2
const FLAG_SHORT = {1: "旗A", 2: "旗B"}
const FLAG_RULE = {1: "大小包都收", 2: "不接大包"}
# 三站约定：单位需求、最多几包、以及站名（三站固定不接大包，二站看旗）。
const DEMAND = [5, 7, 6]
const MAX_PACKS = [2, 4, 3]
const STATION_NAMES = ["一站", "二站", "三站"]
const STATION_PLACES = ["灯铺的栈位", "油行的栈位", "灯会船"]
const HINTS = 3
# 托盘最多摆 6 包：三站里最宽的一站只收 4 包，多出来的两格只用来把错摆法摆出来给人看。
const MAX_TRAY = 6
const STAGES = ["arrival", "approach", "ready", "puzzle", "flag", "lift", "carrying", "delivery", "complete"]
const ANIMATIONS = ["approach", "flag", "lift", "carrying", "delivery"]
# 四条重新封装走法：前两条是同一条规则的两端，后两条也是。每条都恰好花 1 次机会。
const OPS = [
	{"from": [1, 0, 0], "to": [0, 1, 1], "name": "大包 → 中包+小包"},
	{"from": [0, 1, 1], "to": [1, 0, 0], "name": "中包+小包 → 大包"},
	{"from": [2, 0, 0], "to": [0, 3, 0], "name": "两大包 → 三中包"},
	{"from": [0, 3, 0], "to": [2, 0, 0], "name": "三中包 → 两大包"},
]

static func empty_packs() -> Array:
	return [0, 0, 0]

static func empty_deliveries() -> Array:
	var rows = []
	for row in range(KINDS): rows.append(empty_packs())
	return rows

# 验货旗在关卡创建的那一刻固定，之后只随存档走：重读不会换旗。
static func fresh() -> Dictionary:
	return {"sample": "market-mk17-1", "stage": "arrival", "beat": 0,
		"flag": FLAG_A if randi() % 2 == 0 else FLAG_B, "shown": 0, "station": 1,
		"stock": START_STOCK.duplicate(), "tray": empty_packs(), "delivered": empty_deliveries(),
		"chances": CHANCES, "hint": 0}

# ---- 计数：画面与回执都从这里读，自己不留第二份账 ----
static func units_of(packs: Array) -> int:
	var total = 0
	for kind in range(KINDS): total += UNITS[kind] * packs[kind]
	return total

static func packs_of(packs: Array) -> int:
	var total = 0
	for kind in range(KINDS): total += packs[kind]
	return total

static func sum_packs(left: Array, right: Array) -> Array:
	var out = []
	for kind in range(KINDS): out.append(left[kind] + right[kind])
	return out

# 这堆货拿不拿得出一组交货，以及拿出去之后还剩多少：推演只问这两句。
static func fits_packs(pool: Array, packs: Array) -> bool:
	for kind in range(KINDS):
		if pool[kind] < packs[kind]: return false
	return true

static func without_packs(pool: Array, packs: Array) -> Array:
	var out = []
	for kind in range(KINDS): out.append(pool[kind] - packs[kind])
	return out

static func delivered_units(state: Dictionary) -> int:
	var total = 0
	for row in state.delivered: total += units_of(row)
	return total

static func delivered_packs(state: Dictionary) -> int:
	var total = 0
	for row in state.delivered: total += packs_of(row)
	return total

static func held_units(state: Dictionary) -> int:
	return units_of(state.stock) + units_of(state.tray)

static func held_packs(state: Dictionary) -> int:
	return packs_of(state.stock) + packs_of(state.tray)

# 全部在册的包（台面 + 托盘 + 已交出去的），用来核对「三次机会变不出来的那种存量」。
static func total_packs(state: Dictionary) -> Array:
	var out = empty_packs()
	for kind in range(KINDS):
		out[kind] = state.stock[kind] + state.tray[kind]
		for row in state.delivered: out[kind] += row[kind]
	return out

static func legal_packs(value: Variant) -> bool:
	if not value is Array or value.size() != KINDS: return false
	for count in value:
		if not count is int or count < 0 or count > MAX_EACH: return false
	return true

# 三次机会之内的存量上限：大包不会自己变多（6），2大→3中连走三次最多 9 个中包，
# 小包只能由「1大→1中1小」变出来，最多 3 个。超出这个上限的存档就是凭空造货。
static func within_supply(packs: Array) -> bool:
	for kind in range(KINDS):
		if packs[kind] > SUPPLY_CAPS[kind]: return false
	return true

static func legal_deliveries(value: Variant) -> bool:
	if not value is Array or value.size() != KINDS: return false
	for row in value:
		if not legal_packs(row): return false
	return true

# ---- 约定 ----
static func station_of(state: Dictionary) -> int:
	return state.station - 1

# 二站收不收大包由开局固定的那面旗决定；玩家看到旗之前，这条约定其实已经成立。
static func large_ok(flag: int, index: int) -> bool:
	if index == 2: return false
	if index == 1: return flag == FLAG_A
	return true

static func accepts_large(state: Dictionary, index: int) -> bool:
	return large_ok(state.flag, index)

# 每一站的合法交货组合只有这么几组：先按约定枚出来，判交货与往前推演都只看这一份表。
static func delivery_options(index: int, allows_large: bool) -> Array:
	var options: Array = []
	if index < 0 or index >= KINDS: return options
	for a in range(MAX_PACKS[index] + 1):
		if not allows_large and a > 0: continue
		for b in range(MAX_PACKS[index] - a + 1):
			for c in range(MAX_PACKS[index] - a - b + 1):
				if a + b + c == 0: continue
				if units_of([a, b, c]) == DEMAND[index]: options.append([a, b, c])
	return options

static func rule_met(state: Dictionary, index: int, packs: Array) -> bool:
	return delivery_options(index, accepts_large(state, index)).has(packs)

# 柜面上钉着的货单文字：翻旗之前二站把两种可能一并写出来，不藏。
static func rule_caption(state: Dictionary, index: int) -> String:
	var line = "%s · %d 单位 · 最多 %d 包" % [STATION_NAMES[index], DEMAND[index], MAX_PACKS[index]]
	if index == 2: return line + " · 不接大包"
	if index == 1:
		return line + (" · " + FLAG_SHORT[state.flag] + " " + FLAG_RULE[state.flag] if state.shown == 1 else " · 旗A全收 / 旗B不接大包")
	return line + " · 全收"

# 已交出去的那一站实际收了几包什么，回执与栈位牌都从这里读。
static func delivery_caption(state: Dictionary, index: int) -> String:
	var row: Array = state.delivered[index]
	var parts = []
	for kind in range(KINDS):
		if row[kind] > 0: parts.append("%d%s" % [row[kind], PACK_NAMES[kind]])
	if parts.is_empty(): parts.append("空")
	return "%s %s = %d 单位 · %d 包" % [STATION_NAMES[index], " ".join(parts),
		units_of(row), packs_of(row)]

# ---- 玩家动作：重新封装 ----
static func can_apply(state: Dictionary, index: int) -> bool:
	if not state.has("stage") or state.stage != "puzzle" or index < 0 or index >= OPS.size(): return false
	if state.chances <= 0: return false
	var op: Dictionary = OPS[index]
	for kind in range(KINDS):
		if state.stock[kind] < op.from[kind]: return false
	return true

static func apply_op(state: Dictionary, index: int) -> Dictionary:
	if not can_apply(state, index): return {}
	var op: Dictionary = OPS[index]
	var next = state.duplicate(true)
	for kind in range(KINDS): next.stock[kind] = next.stock[kind] - op.from[kind] + op.to[kind]
	next.chances -= 1
	return next if validate(next) else {}

# 机会不够 / 台上没有那种包：一律不动，交给场景如实说。
static func refusal(state: Dictionary, index: int) -> String:
	if index < 0 or index >= OPS.size(): return "没有这条封装走法。"
	var op: Dictionary = OPS[index]
	for kind in range(KINDS):
		if state.stock[kind] < op.from[kind]:
			return "台上只剩 %d 个%s，凑不出「%s」要的那 %d 个%s。" % [state.stock[kind], PACK_NAMES[kind],
				op.name, op.from[kind], PACK_NAMES[kind]]
	if state.chances <= 0:
		return "3 次重新封装的机会都用完了：「%s」不能再走。\n要重新规划请按「回到关前规划」。" % op.name
	return "「%s」这一步现在走不了。" % op.name

# ---- 玩家动作：装托盘（还没离手，随时放回） ----
static func can_load(state: Dictionary, kind: int) -> bool:
	return state.has("stage") and state.stage == "puzzle" and kind >= 0 and kind < KINDS \
		and state.stock[kind] > 0 and packs_of(state.tray) < MAX_TRAY

static func load_refusal(state: Dictionary, kind: int) -> String:
	if not state.has("stage") or state.stage != "puzzle": return "现在不在码头上，摆不了货。"
	if packs_of(state.tray) >= MAX_TRAY:
		return "托盘最多摆 %d 包：先点托盘上的货，把它放回台面。" % MAX_TRAY
	if kind >= 0 and kind < KINDS and state.stock[kind] == 0:
		return "台上已经没有%s了：先重新封装，变出要用的那种包。" % PACK_NAMES[kind]
	return "那一类包现在拿不上托盘。"

static func load_pack(state: Dictionary, kind: int) -> Dictionary:
	if not can_load(state, kind): return {}
	var next = state.duplicate(true)
	next.stock[kind] -= 1
	next.tray[kind] += 1
	return next if validate(next) else {}

static func tray_kinds(state: Dictionary) -> Array:
	var order = []
	for kind in range(KINDS):
		for step in range(state.tray[kind]): order.append(kind)
	return order

static func can_unload(state: Dictionary, kind: int) -> bool:
	return state.stage == "puzzle" and kind >= 0 and kind < KINDS and state.tray[kind] > 0

static func unload_pack(state: Dictionary, kind: int) -> Dictionary:
	if not can_unload(state, kind): return {}
	var next = state.duplicate(true)
	next.tray[kind] -= 1
	next.stock[kind] += 1
	return next if validate(next) else {}

static func can_unload_slot(state: Dictionary, slot: int) -> bool:
	return state.stage == "puzzle" and slot >= 0 and slot < tray_kinds(state).size()

static func unload_slot(state: Dictionary, slot: int) -> Dictionary:
	if not can_unload_slot(state, slot): return {}
	return unload_pack(state, tray_kinds(state)[slot])

# ---- 撤销整站交货：货和幕一起退回，绝不只把封装机会退回来却留着变出的货 ----
# 上一站确实收过货：这条只回答「有没有得退」，与托盘上摆没摆货无关。
static func has_previous_delivery(state: Dictionary) -> bool:
	if state.stage != "puzzle" or state.station < 3: return false
	return units_of(state.delivered[state.station - 2]) > 0

# 退整站要把那一站的货原样搬回托盘：托盘上还没交出去的货必须先放回台面，
# 否则两批货叠在一起，退回时就有一批会凭空蒸发。
static func can_undeliver(state: Dictionary) -> bool:
	return has_previous_delivery(state) and packs_of(state.tray) == 0

# 一站的货已经上船、旗也已经翻过：那一站退不回来，只能「回到关前规划」。
static func undeliver_refusal(state: Dictionary) -> String:
	if state.stage != "puzzle": return "现在不在码头上，退不了货。"
	if state.station <= 2:
		return "一站的货已经吊上船、验货旗也翻过了，这一站退不回来。\n要重新规划只能「回到关前规划」，本关重摆。"
	if packs_of(state.tray) > 0:
		return "退回整站要把那一站的货原样搬回托盘：先点托盘上的每一包，把 %d 包放回台面。" % packs_of(state.tray)
	return "上一站的货没有可以退回台面的部分。"

static func undeliver(state: Dictionary) -> Dictionary:
	if not can_undeliver(state): return {}
	var next = state.duplicate(true)
	var index = next.station - 2
	next.tray = next.delivered[index].duplicate(true)
	next.delivered[index] = empty_packs()
	next.station -= 1
	return next if validate(next) else {}

# ---- 提交这一站 ----
static func shortfalls(state: Dictionary) -> Array:
	var index = station_of(state)
	var missing = []
	if index < 0 or index >= KINDS: return missing
	var tray = state.tray
	if packs_of(tray) == 0:
		missing.append("%s要 %d 单位、最多 %d 包：托盘上还什么都没放。" % [STATION_NAMES[index], DEMAND[index], MAX_PACKS[index]])
		return missing
	if units_of(tray) != DEMAND[index]:
		missing.append("%s要的是恰好 %d 单位：托盘上现在是 %d 单位，%s %d 单位。" % [STATION_NAMES[index],
			DEMAND[index], units_of(tray), "多" if units_of(tray) > DEMAND[index] else "差",
			absi(units_of(tray) - DEMAND[index])])
	if packs_of(tray) > MAX_PACKS[index]:
		missing.append("%s最多只收 %d 包：托盘上摆了 %d 包。" % [STATION_NAMES[index], MAX_PACKS[index], packs_of(tray)])
	if tray[LARGE] > 0 and not accepts_large(state, index):
		var why = "三站固定不接大包" if index == 2 else "翻出来的是%s（%s）" % [FLAG_SHORT[state.flag], FLAG_RULE[state.flag]]
		missing.append("%s：%s。托盘上有 %d 个大包，铜鹭不接。" % [STATION_NAMES[index], why, tray[LARGE]])
	return missing

static func solved(state: Dictionary) -> bool:
	var index = station_of(state)
	if index < 0 or index >= KINDS: return false
	return shortfalls(state).is_empty()

# ---- 还能不能办成：只回答有解／无解，不指出解法、不高亮 ----
# 从这堆货出发能得到的每一堆，连着「最少花几次机会」一起给出来：同一堆在更少的次数里
# 已经出现过就不再记第二次，往前推演时剩下的机会才算得准。
static func pools_by_cost(pool: Array, chances: int) -> Array:
	var rows = [[pool, 0]]
	var frontier = [pool]
	for cost in range(1, chances + 1):
		var next_frontier: Array = []
		for source in frontier:
			for op in OPS:
				var out = []
				var ok = true
				for kind in range(KINDS):
					if source[kind] < op.from[kind]: ok = false
					out.append(source[kind] - op.from[kind] + op.to[kind])
				if not ok or packs_of(out) > MAX_EACH * KINDS: continue
				if pool_cost(rows, out) >= 0: continue
				rows.append([out, cost]); next_frontier.append(out)
		frontier = next_frontier
		if frontier.is_empty(): break
	return rows

static func pool_cost(rows: Array, pool: Array) -> int:
	for row in rows:
		if row[0] == pool: return row[1]
	return -1

# 脚前这一站：只问这一站的货还凑不凑得出来，不管交完之后还剩几站。
static func can_serve(state: Dictionary) -> bool:
	var index = station_of(state)
	if index < 0 or index >= KINDS: return false
	var options = delivery_options(index, accepts_large(state, index))
	for row in pools_by_cost(sum_packs(state.stock, state.tray), state.chances):
		for packs in options:
			if fits_packs(row[0], packs): return true
	return false

# 剩下的每一站一起往前推演。只看脚前这一站会把「这一站照样交得出去、后面再也凑不齐」
# 当成活路，玩家要走到下一站才听得见自己已经走死——首领的三次验货恰恰是连着的三站。
static func plan_ok(flag: int, pool: Array, chances: int, index: int) -> bool:
	if index < 0: return false
	if index >= KINDS: return true
	var options = delivery_options(index, large_ok(flag, index))
	for row in pools_by_cost(pool, chances):
		var left = chances - row[1]
		for packs in options:
			if not fits_packs(row[0], packs): continue
			if plan_ok(flag, without_packs(row[0], packs), left, index + 1): return true
	return false

static func can_finish(state: Dictionary) -> bool:
	return plan_ok(state.flag, sum_packs(state.stock, state.tray), state.chances, station_of(state))

static func dead_end(state: Dictionary) -> bool:
	return state.stage == "puzzle" and not can_finish(state)

# ---- 幕的推进 ----
static func book_delivery(state: Dictionary) -> Dictionary:
	var index = station_of(state)
	var next = state.duplicate(true)
	next.delivered[index] = next.tray.duplicate(true)
	next.tray = empty_packs()
	next.station += 1
	match index:
		0:
			next.shown = 1
			next.stage = "flag"
		1: next.stage = "lift"
		2: next.stage = "carrying"
		_: return {}
	return next if validate(next) else {}

static func advance(state: Dictionary) -> Dictionary:
	# 只往前一幕：残缺字典一律不推进，避免把没走过的步骤当成走过。
	if not state.has("stage") or not state.has("beat") or state.stage not in STAGES: return {}
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < 2: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			return book_delivery(state)
		"flag": next.stage = "puzzle"
		"lift": next.stage = "puzzle"
		"carrying": next.stage = "delivery"
		"delivery": next.stage = "complete"
		_: return {}
	return next if validate(next) else {}

# ---- 撤销（本站内的摆法） ----
static func can_restore(state: Dictionary, snapshot: Dictionary) -> bool:
	if state.stage != "puzzle": return false
	if not snapshot.has("stock") or not snapshot.has("tray") or not snapshot.has("chances"): return false
	if not snapshot.has("station") or not snapshot.has("delivered"): return false
	# 只退本站的摆法：上一站的货、已经花掉的机会都不在退让范围内。
	if snapshot.station != state.station: return false
	return true

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not can_restore(state, snapshot): return {}
	var next = state.duplicate(true)
	next.stock = snapshot.stock.duplicate(true)
	next.tray = snapshot.tray.duplicate(true)
	next.chances = snapshot.chances
	return next if validate(next) else {}

# ---- 存档校验 ----
static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk17-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > 2: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	# 旗只有两面：0（还没定）与重掷出来的第三种都不许进存档。
	if not value.get("flag") is int or value.flag not in [FLAG_A, FLAG_B]: return false
	if not value.get("shown") is int or value.shown not in [0, 1]: return false
	if not value.get("station") is int or value.station < 1 or value.station > KINDS + 1: return false
	if not value.get("chances") is int or value.chances < 0 or value.chances > CHANCES: return false
	if not legal_packs(value.get("stock")) or not legal_packs(value.get("tray")): return false
	if not legal_deliveries(value.get("delivered")): return false
	# 托盘摆不下第六包以上：柜面上没有那么多位置，摆满就是满了。
	if packs_of(value.tray) > MAX_TRAY: return false
	# 存量上限：三次机会变不出第六个大包，也变不出第四个小包。
	if not within_supply(total_packs(value)): return false
	# 一单位都不能凭空多、也不能凭空少：台面 + 托盘 + 已交 = 开局的 18 单位。
	if units_of(value.stock) + units_of(value.tray) + delivered_units(value) != TOTAL_UNITS: return false
	# 包数的增减只能来自用掉的机会：每一次封装恰好让在册包数 ±1，
	# 所以「在册包数 - 开局包数」与「用掉的次数」必须同奇偶、且不超过次数本身（负差也按同一条算）。
	var delta = held_packs(value) + delivered_packs(value) - packs_of(START_STOCK)
	var spent = CHANCES - value.chances
	if absi(delta) > spent or (delta - spent) % 2 != 0: return false
	# 台词没走完就写成后面的幕，是凭空跳步。
	if value.stage != "arrival" and value.beat != 2: return false
	# 站序与旗：旗翻过 ⇔ 第一站已收货；每一站的交货都得按当时代上成立的约定收，
	# 已交出去的货还要从一站往后连着摆，中间不能空出一站。
	var done = 0
	for index in range(KINDS):
		if units_of(value.delivered[index]) > 0:
			if index != done: return false
			if not rule_met(value, index, value.delivered[index]): return false
			done += 1
	if value.station - 1 != done: return false
	if value.shown != int(value.station >= 2): return false
	match value.stage:
		"arrival", "approach", "ready":
			if value.station != 1 or value.shown != 0 or value.chances != CHANCES: return false
			if value.stock != START_STOCK or not value.tray == empty_packs(): return false
		"puzzle":
			if value.station > KINDS: return false
		"flag":
			if value.station != 2 or not value.tray == empty_packs(): return false
		"lift":
			if value.station != 3 or not value.tray == empty_packs(): return false
		"carrying", "delivery", "complete":
			if value.station != KINDS + 1 or not value.tray == empty_packs(): return false
			if not value.stock == empty_packs(): return false
	return true

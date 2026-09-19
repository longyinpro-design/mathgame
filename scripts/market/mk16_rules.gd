extends RefCounted

# MK16 给森林寄回一份礼物（第五幕之后的可选支线）：灯会前最后一班红船要开回森林，
# 扣扣想把回礼寄出去——当初森林把种子寄来时，集市连一份回礼都凑不齐。
# 契约（docs/production/market_chapter.md:240）：选恰好 3 种不同纪念物，重量上限 7 斤；
# 绿叶章 2、信纸 1、杯 4、铃 3；礼物必须含代表森林的绿叶章与可写回信的信纸，
# 最后可选杯或铃：2+1+4=7 与 2+1+3=6 都成立，两解都是有效礼物。
# 偏好只改变森林回信的说法（reply_line），绝不改变主线奖励（REWARD 与分支无关）。
# 柜面不判分：只有按下「封箱上红船」之后才由 shortfalls() 按玩家自己的数字说明差在哪。
const LEAF = 0
const PAPER = 1
const CUP = 2
const BELL = 3
const KINDS = [LEAF, PAPER, CUP, BELL]
const NAMES = ["绿叶章", "信纸", "杯", "铃"]
const WEIGHTS = [2, 1, 4, 3]
# 必带的两样各有各的理由：绿叶章代表森林，信纸用来写回信；第三样才是玩家的偏好。
const MANDATORY = [LEAF, PAPER]
const CHOOSABLE = [CUP, BELL]
const LIMIT = 7
const PICKS = 3
# 两条都成立的礼物（按编号升序），也是 validate 认的两份有效包裹。
const SOLUTIONS = [[LEAF, PAPER, CUP], [LEAF, PAPER, BELL]]
# 集成方要读的键：present 只有两个取值，未提交时是空串。
const PRESENT_KEYS = ["", "", "cup", "bell"]
const PRESENT_NAMES = ["", "", "白杯", "铜铃"]
# 森林的老规矩：礼物里带什么，回信头一句就说什么。两句都短到能画进一张回执。
const REPLY_RULE = "森林有个老规矩：带什么，回什么。"
const REPLY_LEAD = "回信会先说："
const REPLY_LINES = {
	CUP: ["那只白杯我们认得，", "量过春雨的那一只。"],
	BELL: ["铃一响我们就知道，", "集市的灯船开了。"],
}
const REPLY_TAIL = ["种子已经抽枝，", "灯会那晚留一盏给集市。"]
# 离岸那一句也跟着偏好走：两条分支看到的船、听到的说法都不一样。
const SAIL_LINES = {
	CUP: "红船离岸。森林收到那只白杯，就会照白杯回话。",
	BELL: "红船离岸。森林听见那串铜铃，就会照铜铃回话。",
}
# 主线奖励与分支无关：两条礼物路径读到的完全是这一句。
const REWARD = "主线奖励不变：群岛回执册 +1 页"
const HINTS = 3
const BEATS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "loading", "delivery", "complete"]
const ANIMATIONS = ["approach", "loading", "delivery"]
# 包裹已经封好、离开打包台的几幕：台面上不该再有货，礼物改由 gift 记账。
const PACKED = ["loading", "delivery", "complete"]
# 红船已经把包裹带走的两幕：sent 只在这里是 1，且不可能被记两次。
const SAILED = ["delivery", "complete"]

static func fresh() -> Dictionary:
	return {"sample": "market-mk16-1", "stage": "arrival", "beat": 0, "table": [],
		"gift": [], "present": "", "sent": 0, "hint": 0}

# ---- 货名与重量：画面与文字都从这里取，不另立第二套说法 ----
static func known(id: Variant) -> bool:
	return id is int and id >= LEAF and id <= BELL

static func name_of(id: Variant) -> String:
	return NAMES[id] if known(id) else "unknown"

static func weight_of(id: Variant) -> int:
	return WEIGHTS[id] if known(id) else 0

static func short_caption(id: Variant) -> String:
	return "%s%d" % [name_of(id), weight_of(id)] if known(id) else "?"

static func long_caption(id: Variant) -> String:
	return "%s %d 斤" % [name_of(id), weight_of(id)] if known(id) else "?"

static func total(ids: Variant) -> int:
	var sum = 0
	if ids is Array:
		for id in ids: sum += weight_of(id)
	return sum

static func sum_text(ids: Variant) -> String:
	if not ids is Array or ids.is_empty(): return "空台面"
	var parts = []
	for id in ids: parts.append(short_caption(id))
	return " + ".join(parts)

static func detail_text(ids: Variant) -> String:
	if not ids is Array or ids.is_empty(): return "空台面"
	var parts = []
	for id in ids: parts.append(long_caption(id))
	return " + ".join(parts)

static func on_table(state: Dictionary, id: Variant) -> bool:
	return state.table is Array and state.table.has(id)

static func slot_of(state: Dictionary, id: Variant) -> int:
	return state.table.find(id) if state.table is Array else -1

# 一份礼物里那一样「可选的」：它就是系在包裹外面的吊牌，也是回信的说法来源。
static func chosen(gift: Variant) -> int:
	if not gift is Array: return -1
	for id in CHOOSABLE:
		if gift.has(id): return id
	return -1

static func present_of(gift: Variant) -> String:
	var id = chosen(gift)
	return PRESENT_KEYS[id] if id >= 0 else ""

static func present_name(gift: Variant) -> String:
	var id = chosen(gift)
	return PRESENT_NAMES[id] if id >= 0 else ""

static func reply_lines(gift: Variant) -> Array:
	var id = chosen(gift)
	return (REPLY_LINES[id] if id >= 0 else []) + REPLY_TAIL

static func sail_line(gift: Variant) -> String:
	var id = chosen(gift)
	return SAIL_LINES[id] if id >= 0 else "红船离岸。"

static func gift_line(gift: Variant) -> String:
	return "%s = %d 斤" % [detail_text(gift), total(gift)]

# ---- 玩家动作 ----
# 为什么这一样放不上台面：空串表示放得上去。超重那条要说玩家自己摆的数字。
static func refusal(state: Dictionary, id: Variant) -> String:
	if not known(id): return "货架上没有这一样纪念物。"
	if on_table(state, id):
		return "%s 已经在打包台上了：同一样纪念物不会有第二份。" % name_of(id)
	var candidate = total(state.table) + weight_of(id)
	if candidate > LIMIT:
		return "%s 放不上去：%s + %s 合起来 %d 斤。\n红船只在 %d 斤以内接单。" % [
			name_of(id), sum_text(state.table), short_caption(id), candidate, LIMIT]
	if state.table.size() >= PICKS:
		return "打包台上已经有 %d 样：先把一样放回货架，再放 %s。" % [PICKS, name_of(id)]
	return ""

static func place(state: Dictionary, id: Variant) -> Dictionary:
	if state.stage != "puzzle" or not known(id): return {}
	if not refusal(state, id).is_empty(): return {}
	var next = state.duplicate(true)
	next.table = state.table.duplicate(true)
	next.table.append(id)
	return next

static func lift(state: Dictionary, id: Variant) -> Dictionary:
	if state.stage != "puzzle" or not known(id) or not on_table(state, id): return {}
	var next = state.duplicate(true)
	var kept: Array = []
	for held in state.table:
		if held != id: kept.append(held)
	next.table = kept
	return next

static func toggle(state: Dictionary, id: Variant) -> Dictionary:
	if not known(id): return {}
	return lift(state, id) if on_table(state, id) else place(state, id)

# ---- 验收：一次只讲第一条没兑现的承诺，用玩家自己的数字 ----
static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	var table: Array = state.table
	var weight = total(table)
	# 招牌只显示第一条差处，所以最要紧那一句得自己带齐玩家摆下的数字与还缺的名字。
	var gaps: Array = []
	for id in MANDATORY:
		if not table.has(id): gaps.append(name_of(id))
	if table.size() > PICKS or weight > LIMIT:
		var said = "杯 4 斤和铃 3 斤只能带一样上船。" if gaps.is_empty() \
			else "杯 4 斤和铃 3 斤只能带一样，%s也非带不可。" % "、".join(gaps)
		if table.size() > PICKS:
			missing.append("台面上 %d 样合起来 %d 斤：%s。\n超过 %d 斤的上限，红船只在 %d 斤以内接单。" % [
				table.size(), weight, sum_text(table), LIMIT, LIMIT])
		else:
			missing.append("%s 合起来 %d 斤，超过 %d 斤的上限。\n%s" % [sum_text(table), weight, LIMIT, said])
	elif table.size() != PICKS:
		var next_step = "绿叶章和信纸非带不可" if gaps.is_empty() else "先把%s放上台面" % "、".join(gaps)
		missing.append("纪念物要恰好 %d 种：台面上只有 %d 样（%s %d 斤）。\n再从货架点一样：%s。" % [
			PICKS, table.size(), sum_text(table), weight, next_step])
	if not table.has(LEAF):
		missing.append("包裹里没有绿叶章：那是森林的东西，得让他们知道种子是谁种的。")
	if not table.has(PAPER):
		missing.append("包裹里没有信纸：没有能写字的纸，森林收到礼物也没法回信。")
	return missing

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not state.has("stage") or state.stage != "puzzle": return {}
	if not snapshot.has("table") or not snapshot.table is Array: return {}
	var next = state.duplicate(true)
	next.table = snapshot.table.duplicate(true)
	return next if validate(next) else {}

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
			if not solved(state): return {}
			var packed: Array = state.table.duplicate(true)
			packed.sort()
			next.table = []
			next.gift = packed
			next.present = present_of(packed)
			next.stage = "loading"
		"loading":
			next.stage = "delivery"
			next.sent = 1
		"delivery": next.stage = "complete"
		_: return {}
	return next

# ---- 存档 schema ----
static func legal_list(ids: Variant) -> bool:
	if not ids is Array or ids.size() > PICKS: return false
	for id in ids:
		if not known(id) or ids.count(id) > 1: return false
	return true

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk16-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not legal_list(value.get("table")) or not legal_list(value.get("gift")): return false
	if not value.get("present") is String or not value.get("sent") is int: return false
	if value.sent not in [0, 1]: return false
	# 台面上的货不论如何不能超上限：这条与 shortfalls 同源，损坏存档休想蒙过去。
	if total(value.table) > LIMIT or total(value.gift) > LIMIT: return false
	# 台词没走完就走到码头，是凭空跳步。
	if value.stage != "arrival" and value.beat != BEATS - 1: return false
	# 还没上打包台，台面上不该已经有货。
	if value.stage in ["arrival", "approach", "ready"] and not value.table.is_empty(): return false
	# 封好之后货在包裹里，不在台面上；没封好就没有包裹。
	if value.stage == "puzzle" and not value.gift.is_empty(): return false
	if value.stage in PACKED:
		if not value.table.is_empty(): return false
		if value.gift.size() != PICKS or not SOLUTIONS.has(value.gift): return false
		if value.present != present_of(value.gift): return false
	elif not value.gift.is_empty() or value.present != "": return false
	# 只有红船真的离岸了才算寄出，而且寄不出第二次。
	if (value.stage in SAILED) != (value.sent == 1): return false
	return true

extends RefCounted

# MK03 育苗铺「封箱里的重量」：两类封箱不能拆开，只能把两份公开称量叠合、消去相同的一组，
# 再为红箱、蓝箱各挂一枚重签复秤。公开的独立称量是 2红+1蓝=14、1红+2蓝=13，
# 同类封箱重量相同且为正整数，两条同时成立才只有 红 5、蓝 4 一种挂法。
# 柜面不判分：挂到哪一枚、哪条条件已经成立，只有玩家按下「挂签复秤」之后才会知道。
const RED = 0
const BLUE = 1
# 公开的独立称量：[红箱数, 蓝箱数, 合计斤数]。
const RECORDS = [[2, 1, 14], [1, 2, 13]]
# 两份记录里都出现的那一组：叠合时一起消去；14-13 就是红箱比蓝箱重的那 1 斤。
const CANCELLED = [1, 1]
const DIFFERENCE = 1
# 货栈的封箱重签只有 1-7 号，这是柜面上的实物存量，不是提示：两条记录都成立时仍是唯一解。
const TAG_MIN = 1
const TAG_MAX = 7
const HINTS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "reweigh", "delivery", "complete"]
const ANIMATIONS = ["approach", "reweigh", "delivery"]

static func fresh() -> Dictionary:
	return {"sample": "market-mk03-1", "stage": "arrival", "beat": 0, "stacked": 0,
		"red": 0, "blue": 0, "hint": 0}

static func kind_name(kind: int) -> String:
	return "红箱" if kind == RED else "蓝箱"

# 0 表示钩子还空着：没挂签的箱子不参与判分，也就不会被当成 0 斤蒙过一条记录。
static func hung(state: Dictionary, kind: int) -> int:
	return state.red if kind == RED else state.blue

static func legal_kind(kind: int) -> bool:
	return kind == RED or kind == BLUE

static func legal_tag(tag: int) -> bool:
	return tag >= TAG_MIN and tag <= TAG_MAX

static func folded(state: Dictionary) -> bool:
	return state.stacked == 1

# 玩家挂的重签按第 index 条记录实际合出多少斤。
static func reading(state: Dictionary, index: int) -> int:
	var record: Array = RECORDS[index]
	return record[0] * state.red + record[1] * state.blue

static func published(index: int) -> int:
	return RECORDS[index][2]

static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	if not folded(state):
		missing.append("两份称量还各摆各的：把记录二叠到记录一上，消去相同的 1 红 1 蓝。")
	if state.red == 0: missing.append("红箱的钩子还空着：左边那排重签里挑一枚挂上去。")
	if state.blue == 0: missing.append("蓝箱的钩子还空着：右边那排重签里挑一枚挂上去。")
	# 两条记录都要兑现；只说玩家挂的数与公开数差在哪，不指出该怎么改。
	if state.red > 0 and state.blue > 0:
		if reading(state, 0) != published(0):
			missing.append("记录一没兑现：2 红 + 1 蓝 应是 14 斤，挂 %d 与 %d 只合出 %d 斤。" % [state.red, state.blue, reading(state, 0)])
		if reading(state, 1) != published(1):
			missing.append("记录二没兑现：1 红 + 2 蓝 应是 13 斤，挂 %d 与 %d 只合出 %d 斤。" % [state.red, state.blue, reading(state, 1)])
	return missing

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

# ---- player actions ----
static func fold(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or folded(state): return {}
	var next = state.duplicate(true); next.stacked = 1
	return next

static func unfold(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or not folded(state): return {}
	var next = state.duplicate(true); next.stacked = 0
	return next

static func hang(state: Dictionary, kind: int, tag: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_kind(kind) or not legal_tag(tag): return {}
	if hung(state, kind) == tag: return {}
	var next = state.duplicate(true)
	if kind == RED: next.red = tag
	else: next.blue = tag
	return next

static func unhang(state: Dictionary, kind: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_kind(kind) or hung(state, kind) == 0: return {}
	var next = state.duplicate(true)
	if kind == RED: next.red = 0
	else: next.blue = 0
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not state.has("stage") or state.stage != "puzzle": return {}
	if not snapshot.has("stacked") or not snapshot.has("red") or not snapshot.has("blue"): return {}
	var next = state.duplicate(true)
	for key in ["stacked", "red", "blue"]:
		next[key] = snapshot[key]
	return next if validate(next) else {}

static func advance(state: Dictionary) -> Dictionary:
	# 只往前一幕：残缺字典一律不推进，避免把不存在的步骤当成走过。
	if not state.has("stage") or not state.has("beat"): return {}
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < 2: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			next.stage = "reweigh"
		"reweigh": next.stage = "delivery"
		"delivery": next.stage = "complete"
		_: return {}
	return next

# ---- 柜面文字：只复述公开记录，永远不含玩家挂上的数字 ----
static func record_caption(index: int) -> String:
	var record: Array = RECORDS[index]
	var ordinal = "一" if index == 0 else "二"
	return "记录%s · %d红+%d蓝 = %d 斤" % [ordinal, record[0], record[1], record[2]]

static func difference_caption() -> String:
	return "消去 1红1蓝 · 红比蓝重 %d 斤" % DIFFERENCE

static func cancelled_caption() -> String:
	return "%d - %d = %d 斤" % [published(0), published(1), DIFFERENCE]

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk03-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > 2: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not value.get("stacked") is int or value.stacked not in [0, 1]: return false
	if not value.get("red") is int or value.red < 0 or value.red > TAG_MAX: return false
	if not value.get("blue") is int or value.blue < 0 or value.blue > TAG_MAX: return false
	# 台词没走完就写成交货之后的幕，是凭空跳步。
	if value.stage != "arrival" and value.beat != 2: return false
	# 还没走到柜面前，现场不该已经有叠好的记录或挂上的重签。
	if value.stage in ["arrival", "approach", "ready"]:
		if value.stacked != 0 or value.red != 0 or value.blue != 0: return false
	# 复秤之后的每一幕都必须以两条同时兑现的记录作证据：没解开就写好的原单一律拒读。
	if value.stage in ["reweigh", "delivery", "complete"] and not solved(value): return false
	return true

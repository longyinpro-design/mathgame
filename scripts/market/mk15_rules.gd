extends RefCounted

# MK15 灯芯街铜果摊「不会越换越多的铜果」：可选支线，MK09 之后开门，办完回到原停点，不挡主线。
# 这一摊门口贴着三条合同：2 果 = 3 线、2 线 = 1 芯、3 芯 = 4 果；台面上只有 12 颗铜果这一批货。
# 街尾那张招揽牌写「绕一圈，凭空多一颗」，玩家把这一批货真的按三条合同换一遍，看它回不回得到 13 颗。
# 整数验算（本关的 rules 检查逐条复算，不采信这里的结论）：
#   同一把尺：果 3 格、线 2 格、芯 4 格 → 2×3 = 3×2、2×2 = 1×4、3×4 = 4×3，三条合同彼此不打架；
#   一圈倍率：(3/2)×(1/2)×(4/3) = 12/12 = 1，倒着走 (2/3)×(2/1)×(3/4) 也是 12/12；
#   整批走完：12 果 → 18 线 → 9 芯 → 12 果，每一步都除得尽，一颗也不多、一颗也不少；
#   最小闭环：2 组合同一 + 3 组合同二 + 1 组合同三 = 4 颗果绕一圈；这一批 12 颗货能绕的圈长
#   只有 6、12、18 组三种（绕 1、2、3 圈），三种都正好回到 12 颗，没有一种回到 13 颗。
# 这些兑换率只属于这一摊：它们是下面的局部常量，不写进任何全局兑换表，别的关卡也读不到。
const FRUIT = 0
const THREAD = 1
const CORE = 2
const KINDS = 3
const GOODS = ["fruit", "thread", "core"]
const NAMES = ["铜果", "线卷", "灯芯"]
const SHORT = ["果", "线", "芯"]
const MEASURE = ["颗", "卷", "根"]
const KIT_GOODS = ["copper_fruit", "rope_spool", "wick_bundle"]
const ORDINAL = ["一", "二", "三"]
# 本摊自己的折算尺：任何一次合法兑换都不改变台面上的总格数，这正是招牌那句谎话的照妖镜。
const UNIT_OF = [3, 2, 4]
const STOCK = 12
const START = [12, 0, 0]
const VALUE = STOCK * UNIT_OF[FRUIT]
# 三条合同：[付出编号, 每组付出, 得到编号, 每组得到]，只贴在这一摊的三块摊板上。
const LINES = [[FRUIT, 2, THREAD, 3], [THREAD, 2, CORE, 1], [CORE, 3, FRUIT, 4]]
# 一次只记这一批 12 颗货：每条合同最多走「整批货过一遍」的次数，再多就是同一批货被凭空第二份。
const LINE_CAP = [6, 9, 3]
const MAX_PILE = [12, 18, 9]
# 最小闭环各走几组（2 组果换线、3 组线换芯、1 组芯换果 = 4 颗果绕一圈）。
const SMALLEST_RING = [2, 3, 1]
# 招牌自己下的那一笔账：绕一圈之后要本摊按 13 颗结账。
const SIGN_CLAIM = STOCK + 1
const HINTS = 3
const BEATS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "ringing", "delivery", "complete"]
const ANIMATIONS = ["approach", "ringing", "delivery"]

static func fresh() -> Dictionary:
	return {"sample": "market-mk15-1", "stage": "arrival", "beat": 0, "hint": 0,
		"fruit": STOCK, "thread": 0, "core": 0, "used": [0, 0, 0]}

# ---- 台面读数：三堆货永远由台账算出来，画面与文字不另存第二份归属 ----
static func pile(state: Dictionary, kind: int) -> int:
	return state[GOODS[kind]]

static func stock(state: Dictionary) -> Array:
	return [state.fruit, state.thread, state.core]

static func value_of(items: Array) -> int:
	var total := 0
	for kind in range(KINDS): total += UNIT_OF[kind] * items[kind]
	return total

# 台账 used 是唯一发生过的事实：把每条合同的组数依次作用到开摊那 12 颗果上。
static func derived(used: Array) -> Array:
	var items := [STOCK, 0, 0]
	for line in range(KINDS):
		var spec: Array = LINES[line]
		items[spec[0]] -= spec[1] * used[line]
		items[spec[2]] += spec[3] * used[line]
	return items

# 把 groups 组第 line 条合同作用到一堆裸货上；付不出整组就返回空，绝不许半组。
static func walk(items: Array, line: int, groups: int) -> Array:
	if line < 0 or line >= KINDS or groups < 1: return []
	var spec: Array = LINES[line]
	if items[spec[0]] < spec[1] * groups: return []
	var next = items.duplicate(true)
	next[spec[0]] -= spec[1] * groups
	next[spec[2]] += spec[3] * groups
	return next

static func is_used(value: Variant) -> bool:
	if not value is Array or value.size() != KINDS: return false
	for line in range(KINDS):
		if not value[line] is int or value[line] < 0 or value[line] > LINE_CAP[line]: return false
	return true

# 绕一圈的倍率，按整数分子/分母给出：正着走 3×1×4 / 2×2×3，倒着走把三条读反，仍是 12/12。
static func ring_ratio(reverse: bool) -> Array:
	var num := 1
	var den := 1
	for line in range(KINDS):
		var spec: Array = LINES[line]
		num *= spec[1] if reverse else spec[3]
		den *= spec[3] if reverse else spec[1]
	return [num, den]

static func affordable(state: Dictionary, line: int) -> int:
	if line < 0 or line >= KINDS or not is_used(state.get("used")): return 0
	var spec: Array = LINES[line]
	var room: int = LINE_CAP[line] - state.used[line]
	var groups: int = int(pile(state, spec[0]) / float(spec[1]))
	return mini(groups, room)

static func moved(state: Dictionary) -> int:
	return state.used[FRUIT] + state.used[THREAD] + state.used[CORE]

# 每走一组合同三（3 芯 → 4 果）就有一批果真的高速完这一圈。
static func rings(state: Dictionary) -> int:
	return state.used[CORE]

# 招牌要的那一句「回到 12 果」：三堆货与开摊一模一样，而且这一批货确实绕完过一圈。
static func closed(state: Dictionary) -> bool:
	return stock(state) == START and state.used[CORE] > 0

static func solved(state: Dictionary) -> bool:
	return closed(state)

# ---- 玩家动作：一次点击真的换一组货，看得见也退得回 ----
static func can_trade(state: Dictionary, line: int, times: int) -> bool:
	if state.get("stage") != "puzzle": return false
	if line < 0 or line >= KINDS: return false
	if not times is int or times < 1 or times > affordable(state, line): return false
	return true

static func trade(state: Dictionary, line: int, times: int) -> Dictionary:
	if not can_trade(state, line, times): return {}
	var next = state.duplicate(true)
	next.used[line] += times
	var items = derived(next.used)
	for kind in range(KINDS): next[GOODS[kind]] = items[kind]
	return next if validate(next) else {}

static func trade_all(state: Dictionary, line: int) -> Dictionary:
	return trade(state, line, affordable(state, line))

# 招牌那一笔「多出来的果」：台面上没有的那一颗，哪条合同都记不进台账。
static func payout(state: Dictionary, fruits: int) -> Dictionary:
	if state.get("stage") != "puzzle" or not fruits is int or fruits < 0: return {}
	var next = state.duplicate(true)
	next.fruit = fruits
	return next if validate(next) else {}

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not state.has("stage") or state.stage != "puzzle": return {}
	for key in GOODS:
		if not snapshot.has(key): return {}
	if not snapshot.has("used") or not is_used(snapshot.get("used")): return {}
	var next = state.duplicate(true)
	next.used = (snapshot.used as Array).duplicate(true)
	for kind in range(KINDS):
		if not snapshot.get(GOODS[kind]) is int: return {}
		next[GOODS[kind]] = snapshot[GOODS[kind]]
	return next if validate(next) else {}

# ---- 提交闸口：只说哪一条承诺还没兑现，用玩家自己数出来的货讲 ----
static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	if moved(state) == 0:
		return ["台面上还是开摊那 12 颗果：招牌说的是「绕一圈」，一颗都没换出去就不算演出闭环。"]
	if state.used[FRUIT] == 0:
		missing.append("合同一还没走过：2 颗果换 3 卷线，先照它把果换出去。")
	if state.used[THREAD] == 0:
		missing.append("合同二还没走过：换到的线卷得 2 卷换 1 根芯，才接得上合同三。")
	if state.thread > 0:
		missing.append("台面上还压着 %d 卷线：合同二没走完，这一批果就回不到台面。" % state.thread)
	if state.core > 0:
		missing.append("台面上还压着 %d 根芯：合同三是 3 根换 4 颗果，这一条一走完圈才闭合。" % state.core)
	if state.fruit != STOCK:
		missing.append("果只回到 %d 颗，跟开摊的 %d 颗对不上。" % [state.fruit, STOCK])
	return missing

static func advance(state: Dictionary) -> Dictionary:
	# 只往前一幕：残缺字典一律不推进，避免把不存在的步骤当成走过。
	if not state.has("stage") or not state.has("beat") or not state.has("used"): return {}
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < BEATS - 1: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			next.stage = "ringing"
		"ringing":
			if not closed(state): return {}
			next.stage = "delivery"
		"delivery":
			if not closed(state): return {}
			next.stage = "complete"
		_: return {}
	return next

# ---- 摊板文字：只复述本摊贴着的合同与玩家自己换出的数，永远不含判断 ----
# 三座摊位只隔 152 逻辑像素，一条摊板容不下「合同几 + 兑换率」整句，
# 于是牌名与兑换率分成两块小牌：汉字不自动折行，宁可两块也不能超框。
static func name_caption(line: int) -> String:
	return "合同" + ORDINAL[line]

static func rate_caption(line: int) -> String:
	var spec: Array = LINES[line]
	return "%d %s → %d %s" % [spec[1], SHORT[spec[0]], spec[3], SHORT[spec[2]]]

static func line_caption(line: int) -> String:
	return "%s · %s" % [name_caption(line), rate_caption(line)]

static func bulk_caption(state: Dictionary, line: int) -> String:
	return "整批 %d 组" % affordable(state, line)

static func ruler_caption() -> String:
	return "本摊的尺 · 果%d 线%d 芯%d 格" % UNIT_OF

static func pile_caption(kind: int, count: int) -> String:
	return "%s %d %s" % [NAMES[kind], count, MEASURE[kind]]

static func total_caption(state: Dictionary) -> String:
	return "台面共 %d 格 · 与开摊一样" % value_of(stock(state))

static func ring_caption(state: Dictionary) -> String:
	return "已绕 %d 圈 · 一圈 4 颗" % rings(state)

static func local_caption() -> String:
	return "这三条只在本摊算数"

static func sign_caption() -> String:
	return "绕一圈，凭空多一颗"

static func honest_caption() -> String:
	return "不会越换越多"

static func chime_caption() -> String:
	return "会绕圈的交换风铃"

# 招牌被点破时的回答：把玩家自己走的那一遍念给他听，再点名第 13 颗。
static func refusal(fruits: int) -> String:
	return "绕一圈是 12 果 → 18 线 → 9 芯 → 12 果。\n%d 颗这一笔，本摊哪条合同都记不进去。" % fruits

# 回执只复述台账上真发生过的那几组兑换。
static func receipt(state: Dictionary) -> String:
	var lines = ["回执 · 铜果摊绕圈"]
	for line in range(KINDS):
		var spec: Array = LINES[line]
		var groups: int = state.used[line]
		lines.append("合同%s ×%d：%d %s → %d %s" % [ORDINAL[line], groups,
			spec[1] * groups, SHORT[spec[0]], spec[3] * groups, SHORT[spec[2]]])
	lines.append("台面回到 %d %s · %d 格 · 招牌已拆" % [state.fruit, MEASURE[FRUIT], value_of(stock(state))])
	return "\n".join(lines)

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk15-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not is_used(value.get("used")): return false
	for kind in range(KINDS):
		var count = value.get(GOODS[kind])
		# 负数、小数、比这批货还多的一堆，都在这里当损坏挡下。
		if not count is int or count < 0 or count > MAX_PILE[kind]: return false
	# 台面上的三堆货必须正好是台账上那几笔合同换出来的：合同外的一次换法记不进这张台面。
	if stock(value) != derived(value.used): return false
	# 按本摊的尺折算，这批货永远是 36 格：多一颗、少一颗都不再是同一批货。
	if value_of(stock(value)) != VALUE: return false
	# 台词没走完就写到柜面之后的幕，是凭空跳步。
	if value.stage != "arrival" and value.beat != BEATS - 1: return false
	# 还没走到柜面前，台面上不该已经有换出去的货。
	if value.stage in ["arrival", "approach", "ready"]:
		if value.used != [0, 0, 0] or value.fruit != STOCK: return false
	# 绕圈演出之后的每一幕都必须以「台面回到 12 果」作证据：没绕成写好的存档一律拒读。
	if value.stage in ["ringing", "delivery", "complete"] and not closed(value): return false
	return true

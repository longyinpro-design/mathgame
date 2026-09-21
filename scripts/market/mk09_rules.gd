extends RefCounted

# MK09 千灯集市「不必两个人就换成」：五摊各持一件货，五件货必须一次换完，每摊拿到自己肯收的那一件。
# 数学真值是一张整体对应（置换）：`lines[收货摊] = 出货摊`。它必须拆成一个三摊循环 + 一个两摊对换，
# 而不是把五摊硬塞进一条大环，也不是把同一卷布同时许给两家。120 种完整牵法里只有 1 种成立，检查逐条枚举。
# `lines` 只是街面上牵着的线，一件货都还没挪；只有提交通过验收之后，`booked` 才记下真正换出去的那一批。
# 每摊最后拿着什么、谁把货许给了谁，永远由这两个数组现算，画面与按钮文案不另存归属，
# 所以把一条线拉回不会留下幻影货权。规则层是纯函数：不 preload 场景、不碰 Node、不用随机。
const ACTORS = ["甲", "乙", "丙", "丁", "戊"]
const GOODS = ["布", "油", "纸", "铃", "绳"]
const GOODS_FULL = ["布卷", "灯油", "纸卷", "铜铃", "捆货绳"]
# 下标即货物编号，也即出货的那一摊（甲摊出货编号 0……）；画面与规则共用同一套下标。
const KIT_GOODS = ["cloth_bolt", "oil_bottle", "paper_roll", "brass_bell", "rope_spool"]
# 每摊肯收的货：甲收油或铃，乙只认纸，丙要布，丁能收布或绳，戊只认铃。
const ACCEPT = [[1, 3], [2], [0], [0, 4], [3]]
const COUNT = 5
# 唯一可行结构：甲←乙、乙←丙、丙←甲 转成三摊一圈，丁←戊、戊←丁 对换一次。
const SOLUTION = [1, 2, 0, 4, 3]
const BEATS = 3
const HINTS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "exchanging", "delivery", "complete"]
const ANIMATIONS = ["approach", "exchanging", "delivery"]
# 三摊一圈 + 两摊对换＝通关形状；五摊一个大环与「只换了两摊」都是规格点名的错法。
const SHAPE_CYCLE = "三摊转一圈，两摊对换"
const SHAPE_RING = "五摊挤进一个大环"

static func empty_lines() -> Array:
	var lines = []
	for _receiver in range(COUNT): lines.append(-1)
	return lines

static func fresh() -> Dictionary:
	return {"sample": "market-mk09-1", "stage": "arrival", "beat": 0, "hint": 0,
		"lines": empty_lines(), "booked": empty_lines(), "hand": -1}

# 街面上的草图：-1 = 这一摊还没接到线；0..4 = 第几摊把货许给了它。
# 草稿允许重复与自环——玩家要能把「同一卷布许两家」「货绕回自己」这两种错法真的牵出来，
# 才能在提交那一刻听到规则点名拒绝；但已入账的那一批（booked）绝不许这样。
static func is_lines(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	for item in value:
		if not item is int or item < -1 or item > COUNT - 1: return false
	return true

static func is_booked(value: Variant) -> bool:
	if not is_lines(value): return false
	var seen = []
	for receiver in range(COUNT):
		var giver: int = value[receiver]
		# 一件货不能许两家，一摊也不能收自己原本那件。
		if giver < 0 or giver == receiver or seen.has(giver): return false
		seen.append(giver)
		if not ACCEPT[receiver].has(giver): return false
	return true

static func drawn(lines: Array) -> int:
	var count = 0
	for item in lines:
		if item >= 0: count += 1
	return count

static func double_promised(lines: Array) -> Array:
	var doubled = []
	for giver in range(COUNT):
		if lines.count(giver) > 1: doubled.append(giver)
	return doubled

static func self_lines(lines: Array) -> Array:
	var kept = []
	for receiver in range(COUNT):
		if lines[receiver] == receiver: kept.append(receiver)
	return kept

static func unlined(lines: Array) -> Array:
	var open = []
	for receiver in range(COUNT):
		if lines[receiver] < 0: open.append(receiver)
	return open

static func unmoved(lines: Array) -> Array:
	var resting = []
	for giver in range(COUNT):
		if not lines.has(giver): resting.append(giver)
	return resting

static func unaccepted(lines: Array) -> Array:
	var unhappy = []
	for receiver in range(COUNT):
		var giver: int = lines[receiver]
		if giver < 0 or giver == receiver: continue
		if not ACCEPT[receiver].has(giver): unhappy.append(receiver)
	return unhappy

static func satisfied(lines: Array) -> Array:
	var glad = []
	for receiver in range(COUNT):
		var giver: int = lines[receiver]
		if giver >= 0 and giver != receiver and ACCEPT[receiver].has(giver): glad.append(receiver)
	return glad

static func complete_plan(lines: Array) -> bool:
	return unlined(lines).is_empty() and double_promised(lines).is_empty()

# 收货摊指向出货摊，正好是「谁的货去了谁家」的置换；把它拆成环，环长就是有几摊连在一起。
static func cycle_lengths(lines: Array) -> Array:
	var lengths = []
	var seen = []
	for start in range(COUNT):
		if seen.has(start): continue
		var length = 0
		var cursor = start
		while not seen.has(cursor):
			seen.append(cursor); length += 1
			if lines[cursor] < 0: break
			cursor = lines[cursor]
		lengths.append(length)
	lengths.sort()
	lengths.reverse()
	return lengths

static func shape(lines: Array) -> String:
	if not complete_plan(lines): return "还差 %d 条线" % unlined(lines).size()
	if double_promised(lines).is_empty() and self_lines(lines).is_empty() and cycle_lengths(lines) == [3, 2]:
		return SHAPE_CYCLE
	if cycle_lengths(lines) == [5]: return SHAPE_RING
	return "圈数不对"

# 换完之后每摊手上是哪件货：还没牵线的那一格，货仍留在自己摊上。归属只由这一处算出来。
static func goods_after(plan: Array) -> Array:
	var held = []
	for receiver in range(COUNT): held.append(plan[receiver] if plan[receiver] >= 0 else receiver)
	return held

static func solved(state: Dictionary) -> bool:
	return is_booked(state.lines)

# 提交闸口：只说结构上还没成立的地方，点名是哪一摊、哪一件货。
static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	var lines = state.lines
	for giver in double_promised(lines):
		var homes = []
		for receiver in range(COUNT):
			if lines[receiver] == giver: homes.append(ACTORS[receiver] + "摊")
		# 缺口那句要说得进扣扣正在说的那块板：全称「捆货绳」加上两家摊名会把这一句顶到 798 的
		# 内框之外，而街上五块门面上写的本来就是短名。
		missing.append("%s同时许给了%s：一件货只能有一个新主人。" % [GOODS[giver], "、".join(homes)])
	for receiver in self_lines(lines):
		missing.append("%s摊的线绕回了自己：%s留在原摊，不算换出去。" % [ACTORS[receiver], GOODS[receiver]])
	# 五摊挤成一条大环是规格点名的错法：结构先说，再逐摊说清谁拿到的不是自己要的那件。
	if complete_plan(lines) and cycle_lengths(lines) == [5]: missing.append("%s：先想想哪两摊能自己对上。" % SHAPE_RING)
	for receiver in unlined(lines):
		missing.append("%s摊还没有接到线：它%s。" % [ACTORS[receiver], accepts_text(receiver)])
	for receiver in unaccepted(lines):
		missing.append("%s摊接到的是%s，可它%s。" % [ACTORS[receiver], GOODS[lines[receiver]], accepts_text(receiver)])
	return missing

# 一摊肯收的那几件货，按中文的说法用「或」连：一件货都不能同时许两家。
static func accepts_text(receiver: int) -> String:
	var names = []
	for giver in ACCEPT[receiver]: names.append(GOODS[giver])
	return ("只认" if ACCEPT[receiver].size() == 1 else "能收") + "或".join(names)

# ---- 玩家动作：拿起某一摊要出的货、把线按到收货的那一摊、把线拉回来 ----
static func holding(state: Dictionary) -> bool: return state.hand >= 0

static func can_pick(state: Dictionary, giver: int) -> bool:
	return state.stage == "puzzle" and giver >= 0 and giver < COUNT

# 再点一次同一摊就是放手；已经牵好的线不阻止玩家重新拿起那件货（要看清自己许给了谁）。
static func pick(state: Dictionary, giver: int) -> Dictionary:
	if not can_pick(state, giver): return {}
	var next = state.duplicate(true)
	next.hand = -1 if state.hand == giver else giver
	return next

static func can_connect(state: Dictionary, receiver: int) -> bool:
	return state.stage == "puzzle" and state.hand >= 0 and receiver >= 0 and receiver < COUNT

# 一条线只挂一件货：这一摊原来那条线自动回到街上，不留下第二次归属。
# （名字避开 Node.connect，免得解析器把它当成信号连接。）
static func connect_line(state: Dictionary, receiver: int) -> Dictionary:
	if not can_connect(state, receiver): return {}
	var next = state.duplicate(true)
	next.lines[receiver] = next.hand
	next.hand = -1
	return next if validate(next) else {}

static func can_cut(state: Dictionary, receiver: int) -> bool:
	return state.stage == "puzzle" and receiver >= 0 and receiver < COUNT and state.lines[receiver] >= 0

static func cut_line(state: Dictionary, receiver: int) -> Dictionary:
	if not can_cut(state, receiver): return {}
	var next = state.duplicate(true)
	next.lines[receiver] = -1
	return next

static func clear_street(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	var next = state.duplicate(true)
	next.lines = empty_lines(); next.hand = -1
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	if not snapshot.has("lines") or not snapshot.has("hand"): return {}
	if not is_lines(snapshot.get("lines")): return {}
	if not snapshot.get("hand") is int: return {}
	var next = state.duplicate(true)
	next.lines = (snapshot.lines as Array).duplicate(true)
	next.hand = snapshot.hand
	return next if validate(next) else {}

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < BEATS - 1: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			# 一次交上整条街的线：通不过就一件都不挪，通过了才整批入账。
			if not solved(state): return {}
			next.booked = state.lines.duplicate(true)
			next.hand = -1
			next.stage = "exchanging"
		"exchanging":
			if not is_booked(state.booked) or state.lines != state.booked: return {}
			next.stage = "delivery"
		"delivery":
			if not is_booked(state.booked) or state.lines != state.booked: return {}
			next.stage = "complete"
		_: return {}
	return next

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk09-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not is_lines(value.get("lines")): return false
	if not is_lines(value.get("booked")): return false
	if not value.get("hand") is int or value.hand < -1 or value.hand >= COUNT: return false
	# 草稿里的手不能穿过任何阶段：走到别的阶段就不该有人正攥着一件货。
	if value.stage != "puzzle" and value.hand != -1: return false
	match value.stage:
		"arrival", "approach", "ready":
			if value.lines != empty_lines() or value.booked != empty_lines(): return false
			if value.hint != 0: return false
		"puzzle":
			# 摆在街上的线还没入账：不存在「先换好再改线」。
			if value.booked != empty_lines(): return false
		"exchanging", "delivery", "complete":
			# 已经开换：入账的那一批必须自己站得住，而且街上的线就是它。
			if not is_booked(value.booked) or value.lines != value.booked: return false
		_: return false
	return true

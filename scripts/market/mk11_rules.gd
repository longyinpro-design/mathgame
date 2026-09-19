extends RefCounted

# MK11 千灯集市「砝码也能站在货物旁」：育苗铺陶姨要分装恰好 7 单位灯油，老货栈只借出 1、3、9
# 三枚砝码，每枚最多上一次秤；两边盘面都能站砝码，灯油只进指定的货盘，空容器的皮重已经归零。
# 两盘按带符号的差来记：difference() = 对面那盘的砝码 −（货盘的砝码 + 货盘里的灯油）。
# 1、3、9 是一组三进制砝码，每枚有「台面／货盘／对面」三个去处，27 种摆法正好与 −13..+13 的
# 整数差一一对应：0..13 每一个整数量都只有唯一一种摆法称得出来，7 的那一种是「油 + 3 对 9 + 1」，
# 也就是必须把一枚砝码站到灯油这一头来——突破「砝码只能放在对面」。
# 盘面合计、倾斜、读数全部在这里现算，画面不另存任何秤上的状态；提交之前秤始终锁着，
# 摆放时只看得到砝码站到哪一边，永远不预告该接多少油。规则层是纯函数：不 preload 场景、
# 不碰 Node、不用随机，同一个输入永远得到同一个输出。
const WEIGHTS = [1, 3, 9]
const COUNT = 3
# 一枚砝码的三个去处：还在台面上、站在灯油所在的货盘（左盘）、站在对面那盘（右盘）。
const OFF = 0
const GOODS = 1
const FAR = 2
const SIDES = [OFF, GOODS, FAR]
# 点一下就往前走一格：台面 → 对面那盘 → 货盘 → 台面。
# 从台面先落到对面，正是所有人都默认的那一步；再点一次才是本关要教的那一下。
const NEXT = [FAR, OFF, GOODS]
# 陶姨许下的数：这一坛要恰好 7 单位，多一滴少一滴都不算兑现。
const PROMISE = 7
# 油壶一格一格地接，最多接到三枚砝码的总重：再多的油已经不是这具秤能兑现的约定。
const OIL_MAX = 13
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

static func fresh() -> Dictionary:
	return {"sample": "market-mk11-1", "stage": "arrival", "beat": 0, "goods": empty_pan(),
		"far": empty_pan(), "oil": 0, "weighs": 0, "hint": 0}

# ---- 读盘：唯一的真相来源 ----
# 一盘用一个长度为 3 的 0/1 数组记「哪几枚砝码站在这盘上」；同一枚在两盘都记 1 就是把它用了两次。
static func legal_pan(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	for flag in value:
		if not flag is int or flag < 0 or flag > 1: return false
	return true

static func on_pan(state: Dictionary, side: int, index: int) -> bool:
	if index < 0 or index >= COUNT: return false
	if side == GOODS: return state.goods[index] == 1
	if side == FAR: return state.far[index] == 1
	return false

static func side_of(state: Dictionary, index: int) -> int:
	if on_pan(state, GOODS, index): return GOODS
	if on_pan(state, FAR, index): return FAR
	return OFF

# 这一盘上站了几枚砝码（灯油另算）。
static func pan_count(state: Dictionary, side: int) -> int:
	var count := 0
	for index in range(COUNT):
		if on_pan(state, side, index): count += 1
	return count

static func weights_on_scale(state: Dictionary) -> int:
	return pan_count(state, GOODS) + pan_count(state, FAR)

# 只有砝码的重量；货盘里的灯油另加。
static func weight_total(state: Dictionary, side: int) -> int:
	var total := 0
	for index in range(COUNT):
		if on_pan(state, side, index): total += WEIGHTS[index]
	return total

# 这一盘实际压下去多少单位：货盘那头还要算上接出来的灯油。
static func pan_total(state: Dictionary, side: int) -> int:
	return weight_total(state, side) + (state.oil if side == GOODS else 0)

# 带符号的差：正数表示对面那盘更沉，负数表示货盘这头更沉，0 才是平的。
static func difference(state: Dictionary) -> int:
	return pan_total(state, FAR) - pan_total(state, GOODS)

# 同一枚砝码站在两边时的纯砝码差，第五幕的配秤支线（MK14）按同一套记法复用。
static func signed_sum(goods: Array, far: Array) -> int:
	var total := 0
	for index in range(COUNT): total += (far[index] - goods[index]) * WEIGHTS[index]
	return total

# 更沉的那一盘：平了就用 OFF 表示，画面与台词都从那里取名字，不自己判断。
static func heavier(state: Dictionary) -> int:
	var gap := difference(state)
	if gap > 0: return FAR
	if gap < 0: return GOODS
	return OFF

static func heavier_word(state: Dictionary) -> String:
	return pan_word(heavier(state))

static func balanced(state: Dictionary) -> bool:
	return difference(state) == 0

# 秤杆静止时的倾角比例：−1 货盘沉到底，0 平，+1 对面沉到底。角度由画面按同一符号换算。
static func tilt(state: Dictionary) -> float:
	return clampf(float(difference(state)) / float(FULL_TILT), -1.0, 1.0)

static func promise_kept(state: Dictionary) -> bool:
	return state.oil == PROMISE

# 接出来的正好是答应的那 7 单位，且两头一样重。
# 7 + 货盘砝码 = 对面砝码 本身就要求对面至少站着一枚砝码，所以不必再单独问「有没有上秤」。
static func solved(state: Dictionary) -> bool:
	return promise_kept(state) and balanced(state)

static func weight_name(index: int) -> String:
	return "%d 单位"%WEIGHTS[index]

static func pan_name(side: int) -> String:
	if side == GOODS: return "货盘"
	if side == FAR: return "对面那盘"
	return "台面"

static func pan_word(side: int) -> String:
	if side == GOODS: return "货盘这一头"
	if side == FAR: return "对面那盘"
	return "两边"

# 摆出来的这一式子：灯油 7 + 砝码 3 = 砝码 9 + 砝码 1
static func terms(state: Dictionary, side: int) -> Array:
	var parts := []
	if side == GOODS and state.oil > 0: parts.append("灯油 %d"%state.oil)
	for index in range(COUNT):
		if on_pan(state, side, index): parts.append("砝码 %d"%WEIGHTS[index])
	if parts.is_empty(): parts.append("空盘")
	return parts

static func equation(state: Dictionary) -> String:
	return " + ".join(terms(state, GOODS)) + " = " + " + ".join(terms(state, FAR))

# ---- 提交之后的如实回话：先说秤、再说约定，各是各的职责 ----
static func beam_line(state: Dictionary) -> String:
	return "%s沉下去了：货盘 %d 单位，对面 %d 单位。"%[heavier_word(state),
		pan_total(state, GOODS), pan_total(state, FAR)]

static func promise_line(state: Dictionary) -> String:
	if state.oil > PROMISE:
		return "陶姨要的是恰好 %d 单位：这一盘接进了 %d 单位，多了 %d 单位。"%[PROMISE, state.oil, state.oil - PROMISE]
	return "陶姨要的是恰好 %d 单位：这一盘接进了 %d 单位，还差 %d 单位。"%[PROMISE, state.oil, PROMISE - state.oil]

# 抬起秤之后要说的话。没解开的现场必然至少踩中一条；解开了就交给交付台词。
static func result_lines(state: Dictionary) -> Array:
	var lines := []
	if not balanced(state): lines.append(beam_line(state))
	if not promise_kept(state): lines.append(promise_line(state))
	return lines

static func result_line(state: Dictionary) -> String:
	return "\n".join(result_lines(state))

# ---- 玩家动作 ----
static func legal_index(index: int) -> bool:
	return index >= 0 and index < COUNT

static func legal_side(side: int) -> bool:
	return side == GOODS or side == FAR

static func can_place(state: Dictionary, index: int, side: int) -> bool:
	if state.stage != "puzzle" or not legal_index(index) or not legal_side(side): return false
	return side_of(state, index) != side

# 把一枚砝码请上某一盘；它原本站在另一盘时就是「挪过来」，两盘永远不同时记下同一枚。
static func place(state: Dictionary, index: int, side: int) -> Dictionary:
	if not can_place(state, index, side): return {}
	var next = state.duplicate(true)
	next.goods[index] = 1 if side == GOODS else 0
	next.far[index] = 1 if side == FAR else 0
	return next if validate(next) else {}

static func can_return(state: Dictionary, index: int) -> bool:
	return state.stage == "puzzle" and legal_index(index) and side_of(state, index) != OFF

# 放回台面：两盘的记录一起清零，不留幻影砝码。
static func return_weight(state: Dictionary, index: int) -> Dictionary:
	if not can_return(state, index): return {}
	var next = state.duplicate(true)
	next.goods[index] = 0
	next.far[index] = 0
	return next if validate(next) else {}

static func cycle(state: Dictionary, index: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_index(index): return {}
	var onward: int = NEXT[side_of(state, index)]
	return return_weight(state, index) if onward == OFF else place(state, index, onward)

static func can_draw(state: Dictionary) -> bool:
	return state.stage == "puzzle" and state.oil < OIL_MAX

# 拧一格油壶：接进去的就是货盘里那只皮重已归零的接油罐，一格一个单位。
static func draw_oil(state: Dictionary) -> Dictionary:
	if not can_draw(state): return {}
	var next = state.duplicate(true)
	next.oil += 1
	return next if validate(next) else {}

static func can_pour_back(state: Dictionary) -> bool:
	return state.stage == "puzzle" and state.oil > 0

static func pour_back(state: Dictionary) -> Dictionary:
	if not can_pour_back(state): return {}
	var next = state.duplicate(true)
	next.oil -= 1
	return next if validate(next) else {}

# ---- 提交闸口：只管「手底下还没动手」，不判数学 ----
static func shortfalls(state: Dictionary) -> Array:
	var missing := []
	if state.oil == 0: missing.append("接油罐还空着：先拧开油壶，一格一格往货盘里接。")
	if weights_on_scale(state) == 0: missing.append("三枚砝码都还在台面上：至少请一枚上秤，空秤称不出任何约定。")
	return missing

static func ready_to_weigh(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

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
			# 提秤不看对错：接了油、请了砝码上秤，秤就抬。结果由演出如实给出。
			if not ready_to_weigh(state): return {}
			next.weighs += 1
			next.stage = "weighing"
		"weighing": next.stage = "delivery" if solved(state) else "result"
		"result":
			# 记下这一次的结果就回到台面：摆法原样保留，一枚砝码一滴油都不扣。
			next.stage = "puzzle"
		"delivery": next.stage = "complete"
		_: return {}
	return next

# 重摆：砝码全部回到台面，接油罐里的油倒回油壶。抬过几次秤是街上已经发生过的事，不清零。
static func cleared(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	next.goods = empty_pan()
	next.far = empty_pan()
	next.oil = 0
	return next

static func legal_snapshot(snapshot: Dictionary) -> bool:
	return snapshot.get("goods") is Array and snapshot.get("far") is Array and snapshot.get("oil") is int

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or not legal_snapshot(snapshot): return {}
	var next = state.duplicate(true)
	next.goods = snapshot.goods.duplicate(true)
	next.far = snapshot.far.duplicate(true)
	next.oil = int(snapshot.oil)
	# 抬秤次数是已经发生过的事，撤销摆放不把它抹掉；快照里没有它，也就改不动它。
	return next if validate(next) else {}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk11-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINT_TIERS: return false
	if not legal_pan(value.get("goods")) or not legal_pan(value.get("far")): return false
	if not value.get("oil") is int or value.oil < 0 or value.oil > OIL_MAX: return false
	if not value.get("weighs") is int or value.weighs < 0: return false
	# 每枚砝码最多用一次：同一枚同时站在两个盘上，就是把它偷偷用了第二遍。
	for index in range(COUNT):
		if value.goods[index] == 1 and value.far[index] == 1: return false
	# 台词没走完就写成后面的幕，是凭空跳步。
	if value.stage != "arrival" and value.beat != BEATS - 1: return false
	# 还没走到秤前：三枚砝码都在台面上，接油罐没动过，秤也没抬起来过。
	if value.stage in ["arrival", "approach", "ready"]:
		if value.oil != 0 or value.weighs != 0: return false
		if not value.goods == empty_pan() or not value.far == empty_pan(): return false
	# 秤已经抬起来过的每一幕都必须真的抬过至少一次秤。
	if value.stage in ["weighing", "result", "delivery", "complete"] and value.weighs < 1: return false
	# 「结果牌还立着」与「这一秤其实已经兑了约」不能同时成立：解开了就该走交付。
	if value.stage == "result" and solved(value): return false
	# 交付与完成只认那份真的平了、也确实接够 7 单位的现场。
	if value.stage in ["delivery", "complete"] and not solved(value): return false
	return true

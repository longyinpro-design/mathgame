extends RefCounted

# MK04 不可能兑现的收据：柜面上只有两条「双方都留有原章」的约定可以执行，
# 第三条是扣扣的转抄件，它是被核对的对象，不是一条规则。
# 结果只在提交后呈现；a/b 记录已经生效的整组次数，exchange 与 proposed 记录正在演出的那一次。
const CLOTH = 3
# 原约一：1 卷布换 2 瓶油。原约二：3 瓶油换 1 只铜铃。
const OIL_PER_CLOTH = 2
const OIL_PER_BELL = 3
const BELLS_PER_GROUP = 1
# 3 卷布全部沿原约换完是 6 瓶油，6 瓶油正好分 2 组，得 2 只铜铃。
const OIL = CLOTH * OIL_PER_CLOTH
const BELL_GROUPS = int(OIL / float(OIL_PER_BELL))
# 扣抄的那张写着 3 卷布换 3 只铜铃；改签候选只有 2、3、4 三个数。
const WRITTEN_BELLS = 3
const CORRECT_BELLS = int(CLOTH * OIL_PER_CLOTH / float(OIL_PER_BELL))
const CANDIDATES = [2, 3, 4]
# 可执行约定的条数：第三条永远不进这个范围，所以任何路径都刷不出货。
const RULE_COUNT = 2
const ARRIVAL_BEATS = 3
const CLARIFY_BEATS = 4
const HINTS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "exchanging", "correcting", "delivery", "clarify", "complete"]
const ANIMATIONS = ["approach", "exchanging", "correcting", "delivery"]

static func fresh() -> Dictionary:
	return {"sample": "market-mk04-1", "stage": "arrival", "beat": 0, "a": 0, "b": 0,
		"exchange": [], "proposed": 0, "correction": 0, "hint": 0}

# ---- 货物账：每件货物只有一个归属，全部由已生效的组数算出，画面不另存计数 ----
static func cloth_left(state: Dictionary) -> int:
	return CLOTH - state.a

static func oil_loose(state: Dictionary) -> int:
	return OIL_PER_CLOTH * state.a - OIL_PER_BELL * state.b

static func bells_loose(state: Dictionary) -> int:
	return BELLS_PER_GROUP * state.b

# 转抄件上此刻写着几只铃：没改签之前，一直是扣扣抄来的 3。
static func bell_claim(state: Dictionary) -> int:
	return WRITTEN_BELLS if state.correction == 0 else state.correction

static func affordable(state: Dictionary, rule: int) -> int:
	if rule == 0: return cloth_left(state)
	return int(oil_loose(state) / float(OIL_PER_BELL))

static func group_limit(rule: int) -> int:
	return CLOTH if rule == 0 else BELL_GROUPS

# 整组进行：一条 1 卷布，一条 3 瓶油；越界、拆组、不认识的编号一律不做。
static func legal_exchange(state: Dictionary, rule: int, times: int) -> bool:
	if rule < 0 or rule >= RULE_COUNT or times < 1 or times > affordable(state, rule): return false
	if rule == 1 and state.b + times > BELL_GROUPS: return false
	return true

# 改签只在 3 卷布真的沿第一条原约换完之后再开：先有实换，再谈数量。
static func can_propose(state: Dictionary, value: int) -> bool:
	if state.stage != "puzzle" or state.a != CLOTH: return false
	return value in CANDIDATES and value != state.correction

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

# 缺口按玩家自己的话说明「哪一句承诺还没兑现」，一次只报第一条。
static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	if cloth_left(state) > 0:
		missing.append("柜面上还剩 %d 卷布没换：3 卷布要沿两条原约换到底。" % cloth_left(state))
	elif oil_loose(state) >= OIL_PER_BELL:
		missing.append("台面上还有 %d 瓶油：%d 瓶油还能再换 1 只铜铃，先换完。" % [oil_loose(state), OIL_PER_BELL])
	elif bells_loose(state) != CORRECT_BELLS:
		missing.append("两条原约走到这里只剩 %d 只铜铃，柜面上不该有别的数。" % bells_loose(state))
	elif state.correction == 0:
		missing.append("转抄件上还写着 %d 只铃：按你实换出的 %d 只改签，再提交。" % [WRITTEN_BELLS, bells_loose(state)])
	elif bell_claim(state) != bells_loose(state):
		missing.append("改签写的是 %d 只，可你刚换出来的是 %d 只：%d 卷布 → %d 瓶油 → %d 只铃。" % [
			bell_claim(state), bells_loose(state), CLOTH, OIL_PER_CLOTH * state.a, bells_loose(state)])
	return missing

# ---- 玩家动作 ----
# 演出前只把「要做哪几条、做几组」写进存档，组数在动画结束才入账。
static func exchange(state: Dictionary, rule: int, times: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_exchange(state, rule, times): return {}
	var next = state.duplicate(true)
	next.exchange = [rule, times]
	next.stage = "exchanging"
	return next

# 把 3 卷布实换出来的只数写回第三张：先进入演出，落点由 advance() 记账。
static func propose(state: Dictionary, value: int) -> Dictionary:
	if not can_propose(state, value): return {}
	var next = state.duplicate(true)
	next.proposed = value
	next.stage = "correcting"
	return next

# 改签可以撤回，回到「还没核对」的 3 只；已换出的货物不受影响。
static func clear_correction(state: Dictionary) -> Dictionary:
	if state.stage != "puzzle" or state.correction == 0: return {}
	var next = state.duplicate(true)
	next.correction = 0
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	var next = state.duplicate(true)
	for key in ["a", "b", "correction"]:
		if not snapshot.has(key): return {}
		next[key] = snapshot[key]
	next.exchange = []
	next.proposed = 0
	return next if validate(next) else {}

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < ARRIVAL_BEATS - 1: next.beat += 1
			else:
				next.stage = "approach"; next.beat = 0
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			next.stage = "delivery"
		"exchanging":
			if state.exchange.size() != 2 or not legal_exchange(state, state.exchange[0], state.exchange[1]): return {}
			if state.exchange[0] == 0: next.a += state.exchange[1]
			else: next.b += BELLS_PER_GROUP * state.exchange[1]
			next.exchange = []
			next.stage = "puzzle"
		"correcting":
			if state.a != CLOTH or not (state.proposed in CANDIDATES): return {}
			next.correction = state.proposed
			next.proposed = 0
			next.stage = "puzzle"
		"delivery": next.stage = "clarify"
		"clarify":
			if state.beat < CLARIFY_BEATS - 1: next.beat += 1
			else:
				next.stage = "complete"; next.beat = 0
		_: return {}
	return next

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk04-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > CLARIFY_BEATS - 1: return false
	if value.stage == "arrival" and value.beat > ARRIVAL_BEATS - 1: return false
	if value.stage != "arrival" and value.stage != "clarify" and value.beat != 0: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not value.get("a") is int or value.a < 0 or value.a > CLOTH: return false
	if not value.get("b") is int or value.b < 0 or value.b > BELL_GROUPS: return false
	if not value.get("correction") is int or (value.correction != 0 and value.correction not in CANDIDATES): return false
	if not value.get("proposed") is int or (value.proposed != 0 and value.proposed not in CANDIDATES): return false
	# 油不能是负的：换出去的铃不能比换进来的油还多。
	if OIL_PER_BELL * value.b > OIL_PER_CLOTH * value.a: return false
	# 待生效的那一次只装得下 [约定编号, 组数]。
	if not value.get("exchange") is Array or value.exchange.size() > 2: return false
	if value.stage in ["arrival", "approach", "ready"]:
		if value.a != 0 or value.b != 0: return false
		if value.correction != 0 or value.proposed != 0 or not value.exchange.is_empty(): return false
	if value.stage == "puzzle":
		if not value.exchange.is_empty() or value.proposed != 0: return false
	if value.stage == "exchanging":
		if value.exchange.size() != 2 or not legal_exchange(value, value.exchange[0], value.exchange[1]): return false
		if value.proposed != 0: return false
	if value.stage == "correcting":
		if value.a != CLOTH or not (value.proposed in CANDIDATES): return false
		if not value.exchange.is_empty(): return false
	if value.stage in ["delivery", "clarify", "complete"]:
		if not value.exchange.is_empty() or value.proposed != 0: return false
		# 走到交货之后，实换与改签都必须已经真的发生过。
		if not solved(value): return false
	return true

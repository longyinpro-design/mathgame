extends RefCounted

# MK02 育苗铺「回礼要留下一段线」：兑换只能整组进行，货物只有一个归属。
# 结果只在提交后呈现；a/b 记录已生效的整组次数，exchange 记录正在演出、尚未入账的一次兑换。
const FRUITS = 8
const WICK_ORDER = 5
const SPOOL_ORDER = 2
const RACK_SLOTS = 5
const HOOK_SLOTS = 2
# 兑换只能整组进行：每组投入 GROUP 个同种货物，产出写死在集市公示的约定里。
const GROUP = 2
const SPOOL_PER_GROUP = 3
const WICK_PER_GROUP = 1
# 8 颗铜果最多 12 卷线，因此第二轮兑换最多 6 组；存档里的越界值一律视为损坏。
const MAX_WICK_GROUPS = 6
const STAGES = ["arrival", "approach", "ready", "puzzle", "exchanging", "delivery", "complete"]
const ANIMATIONS = ["approach", "exchanging", "delivery"]

static func rack_empty() -> Array:
	var flags = []
	for slot in range(RACK_SLOTS): flags.append(0)
	return flags

static func hook_empty() -> Array:
	var flags = []
	for slot in range(HOOK_SLOTS): flags.append(0)
	return flags

static func fresh() -> Dictionary:
	return {"sample": "market-mk02-1", "stage": "arrival", "beat": 0, "a": 0, "b": 0,
		"exchange": [], "rack": rack_empty(), "hook": hook_empty(), "hint": 0}

static func valid_flags(value: Variant, slots: int) -> bool:
	if not value is Array or value.size() != slots: return false
	for flag in value:
		if not flag is int or (flag != 0 and flag != 1): return false
	return true

static func fruits_left(state: Dictionary) -> int:
	return FRUITS - GROUP * state.a

static func spools_loose(state: Dictionary) -> int:
	return SPOOL_PER_GROUP * state.a - GROUP * state.b - state.hook.count(1)

static func wicks_loose(state: Dictionary) -> int:
	return WICK_PER_GROUP * state.b - state.rack.count(1)

static func affordable(state: Dictionary, rule: int) -> int:
	var pool = fruits_left(state) if rule == 0 else spools_loose(state)
	return int(pool / float(GROUP))

static func group_limit(rule: int) -> int:
	return int(FRUITS / float(GROUP)) if rule == 0 else MAX_WICK_GROUPS

static func legal_exchange(state: Dictionary, rule: int, times: int) -> bool:
	if rule not in [0, 1] or times < 1 or times > affordable(state, rule): return false
	if rule == 1 and state.b + times > MAX_WICK_GROUPS: return false
	return true

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

static func shortfalls(state: Dictionary) -> Array:
	var missing = []
	var on_rack = state.rack.count(1)
	if on_rack < WICK_ORDER: missing.append("码头要 %d 根灯芯：交付架上只有 %d 根。" % [WICK_ORDER, on_rack])
	if state.hook.count(1) < SPOOL_ORDER: missing.append("扣扣的捆货绳还差 %d 卷线。" % (SPOOL_ORDER - state.hook.count(1)))
	if wicks_loose(state) > 0: missing.append("台面上还有 %d 根灯芯没放上交付架。" % wicks_loose(state))
	if spools_loose(state) > 0: missing.append("台面上还有 %d 卷线没归位：挂上修补台，或者换成灯芯。" % spools_loose(state))
	if fruits_left(state) > 0: missing.append("货筐里还剩 %d 颗铜果没用：%d 颗才能换 %d 卷线。" % [fruits_left(state), GROUP, SPOOL_PER_GROUP])
	return missing

static func exchange(state: Dictionary, rule: int, times: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_exchange(state, rule, times): return {}
	var next = state.duplicate(true)
	next.exchange = [rule, times]
	next.stage = "exchanging"
	return next

static func put_rack(state: Dictionary, slot: int) -> Dictionary:
	if state.stage != "puzzle" or slot < 0 or slot >= RACK_SLOTS or state.rack[slot] == 1: return {}
	if wicks_loose(state) < 1: return {}
	var next = state.duplicate(true)
	next.rack[slot] = 1
	return next

static func take_rack(state: Dictionary, slot: int) -> Dictionary:
	if state.stage != "puzzle" or slot < 0 or slot >= RACK_SLOTS or state.rack[slot] == 0: return {}
	var next = state.duplicate(true)
	next.rack[slot] = 0
	return next

static func put_hook(state: Dictionary, slot: int) -> Dictionary:
	if state.stage != "puzzle" or slot < 0 or slot >= HOOK_SLOTS or state.hook[slot] == 1: return {}
	if spools_loose(state) < 1: return {}
	var next = state.duplicate(true)
	next.hook[slot] = 1
	return next

static func take_hook(state: Dictionary, slot: int) -> Dictionary:
	if state.stage != "puzzle" or slot < 0 or slot >= HOOK_SLOTS or state.hook[slot] == 0: return {}
	var next = state.duplicate(true)
	next.hook[slot] = 0
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	var next = state.duplicate(true)
	for key in ["a", "b", "rack", "hook"]:
		if not snapshot.has(key): return {}
		next[key] = snapshot[key]
	return next if validate(next) else {}

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < 2: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			next.stage = "delivery"
		"exchanging":
			if state.exchange.size() != 2 or not legal_exchange(state, state.exchange[0], state.exchange[1]): return {}
			if state.exchange[0] == 0: next.a += state.exchange[1]
			else: next.b += state.exchange[1]
			next.exchange = []
			next.stage = "puzzle"
		"delivery": next.stage = "complete"
		_: return {}
	return next

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk02-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > 2: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > 3: return false
	if not value.get("a") is int or value.a < 0 or value.a > group_limit(0): return false
	if not value.get("b") is int or value.b < 0 or value.b > MAX_WICK_GROUPS: return false
	if not valid_flags(value.get("rack"), RACK_SLOTS) or not valid_flags(value.get("hook"), HOOK_SLOTS): return false
	if GROUP * value.b + value.hook.count(1) > SPOOL_PER_GROUP * value.a: return false
	if value.rack.count(1) > value.b: return false
	if not value.get("exchange") is Array or value.exchange.size() > 2: return false
	if value.stage in ["arrival", "approach", "ready"]:
		if value.a != 0 or value.b != 0 or not value.exchange.is_empty(): return false
		if value.rack.count(1) != 0 or value.hook.count(1) != 0: return false
	if value.stage == "puzzle" and not value.exchange.is_empty(): return false
	if value.stage == "exchanging":
		if value.exchange.size() != 2 or not legal_exchange(value, value.exchange[0], value.exchange[1]): return false
	if value.stage in ["delivery", "complete"] and not solved(value): return false
	return true

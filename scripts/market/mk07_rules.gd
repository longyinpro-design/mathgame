extends RefCounted

# MK07 千灯集市「先别把东西平均分」：四件援助货对四位居民，可替代需求与不可替代需求互相牵制。
# 数学真值是一张二部图的完美匹配：乐手只能用铃、医护只能用布（不可替代）；布被医护占走之后，
# 帆匠只剩绳可拿，修桥人得钉。24 种完整分配里只有一个解，测试用枚举逐条核对。
# 结果只在玩家主动「整批试交」之后呈现：试交失败保留方案、不扣任何货物，只把这一次记成街上的回执。
# 规则层是纯函数：不 preload 场景、不碰 Node、不用随机，同一个输入永远得到同一个输出。
const PERSONS = ["帆匠","修桥人","乐手","医护"]
const GOODS = ["绳","钉","布","铃"]
# 四件货在 kit-v1 拆件包里的名字，画面与规则共用同一套下标。
const KIT_GOODS = ["rope_spool","nail_pouch","cloth_bolt","brass_bell"]
# 每位居民用得上的货（下标对应 GOODS）：帆匠、修桥人可替代；乐手、医护不可替代。
const ACCEPT = [[0,2],[0,1],[3],[2]]
# 唯一完整分配：帆匠收绳、修桥人收钉、乐手收铃、医护收布。
const SOLUTION = [0,1,3,2]
const COUNT = 4
# 完整分配一共 4! = 24 种，其中不满足的只有 23 种；上限取 24，第一次试交永远是 failed[0]。
const MAX_FAILED = 24
const BEATS = 4
const HINTS = 3
const STAGES = ["arrival","approach","ready","puzzle","handover","delivery","complete"]
const ANIMATIONS = ["approach","handover","delivery"]

static func empty_plan() -> Array:
	var plan := []
	for _person in range(COUNT): plan.append(-1)
	return plan

static func fresh() -> Dictionary:
	return {"sample":"market-mk07-1","stage":"arrival","beat":0,"hint":0,
		"plan":empty_plan(),"failed":[]}

# 一件货只能有一个归属：-1 表示还在柜台上，0..3 表示分给了第几户。
static func is_plan(value: Variant, complete: bool) -> bool:
	if not value is Array or value.size() != COUNT: return false
	var seen := []
	for item in value:
		if not item is int or item < -1 or item > COUNT - 1: return false
		if item < 0:
			if complete: return false
			continue
		if seen.has(item): return false
		seen.append(item)
	return true

static func assigned(state: Dictionary) -> int:
	var count := 0
	for item in state.plan:
		if item >= 0: count += 1
	return count

static func free_goods(state: Dictionary) -> Array:
	var result := []
	for good in range(COUNT):
		if not state.plan.has(good): result.append(good)
	return result

# 这一件货现在在谁手里；-1 表示还躺在柜台上。
static func holder_of(plan: Array, good: int) -> int:
	return plan.find(good)

static func usable_text(person: int) -> String:
	var names := ""
	for index in range(ACCEPT[person].size()):
		if index > 0: names += "或"
		names += GOODS[ACCEPT[person][index]]
	return ("只能用" if ACCEPT[person].size() == 1 else "能用") + names

static func complete_plan(state: Dictionary) -> bool:
	return is_plan(state.plan, true)

# 真实缺口：谁没有拿到自己用得上的那一件，以及他用得上的那件现在在谁手里。
static func unmet_of(plan: Array) -> Array:
	var result := []
	if not is_plan(plan, true): return result
	for person in range(COUNT):
		if ACCEPT[person].has(plan[person]): continue
		for good in ACCEPT[person]:
			if holder_of(plan, good) != person: result.append([person, good])
	return result

# 替代空间：这位居民手上这件货之外，他还能用哪一件。只有可替代需求才有第二个去处。
static func other_usable(person: int, good: int) -> int:
	if not ACCEPT[person].has(good) or ACCEPT[person].size() < 2: return -1
	for candidate in ACCEPT[person]:
		if candidate != good: return candidate
	return -1

static func trial_report(plan: Array) -> Array:
	var lines := []
	for entry in unmet_of(plan):
		var person: int = entry[0]
		var good: int = entry[1]
		var line = "%s还没有能用的%s"%[PERSONS[person], GOODS[good]]
		var holder := holder_of(plan, good)
		if holder >= 0:
			line += "：%s在%s手里"%[GOODS[good], PERSONS[holder]]
			var spare := other_usable(holder, good)
			if spare >= 0: line += "，他也能用%s"%GOODS[spare]
		lines.append(line + "。")
	return lines

static func solved(state: Dictionary) -> bool:
	return complete_plan(state) and unmet_of(state.plan).is_empty()

# 提交闸口只看结构：四户各有一件就可以试交。能不能用得上要交了才知道，这里不提前判卷。
static func shortfalls(state: Dictionary) -> Array:
	var missing := []
	for person in range(COUNT):
		if state.plan[person] < 0:
			missing.append("%s还没有分到东西：%s。"%[PERSONS[person], usable_text(person)])
	return missing

# 把一件货预定给一位居民；该居民原先那件自动回到柜台。用不上也允许，由试交来说话。
static func give(state: Dictionary, person: int, good: int) -> Dictionary:
	if state.stage != "puzzle": return {}
	if person < 0 or person >= COUNT or good < 0 or good >= COUNT: return {}
	if holder_of(state.plan, good) >= 0: return {}
	if state.plan[person] == good: return {}
	var next = state.duplicate(true)
	next.plan[person] = good
	return next

static func take_back(state: Dictionary, person: int) -> Dictionary:
	if state.stage != "puzzle": return {}
	if person < 0 or person >= COUNT or state.plan[person] < 0: return {}
	var next = state.duplicate(true)
	next.plan[person] = -1
	return next

# 撤销只回退摆放：试交过的回执是已经发生过的事，不跟着撤销一起抹掉。
static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	if not snapshot.has("plan") or not is_plan(snapshot["plan"], false): return {}
	var next = state.duplicate(true)
	next.plan = snapshot["plan"].duplicate(true)
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
			if not complete_plan(state): return {}
			next.stage = "handover"
		"handover":
			# 演出结束才结账：记下这一次没交齐的方案，货物与方案都原样留在街上。
			if not is_plan(state.plan, true): return {}
			if unmet_of(state.plan).is_empty(): next.stage = "delivery"
			else:
				if state.failed.size() >= MAX_FAILED: return {}
				if not state.failed.has(state.plan): next.failed = state.failed + [state.plan.duplicate(true)]
				next.stage = "puzzle"
		"delivery": next.stage = "complete"
		_: return {}
	return next

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk07-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not is_plan(value.get("plan"), false): return false
	if not value.get("failed") is Array or value.failed.size() > MAX_FAILED: return false
	for entry in value.failed:
		# 记进回执的必须是一次真的没交齐的完整方案，也不能重复记账。
		if not is_plan(entry, true) or unmet_of(entry).is_empty(): return false
		if value.failed.count(entry) > 1: return false
	match value.stage:
		"arrival","approach","ready":
			if value.plan != empty_plan() or not value.failed.is_empty(): return false
			if value.hint != 0: return false
		"puzzle": pass
		"handover":
			if not is_plan(value.plan, true): return false
		"delivery","complete":
			# 交付与完成只认那张唯一匹配：方案不是它，就说明有人在伪造入账记录。
			if value.plan != SOLUTION or value.failed.count(SOLUTION) > 0: return false
		_: return false
	return true

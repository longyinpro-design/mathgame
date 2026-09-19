extends RefCounted

# MK05 灯芯街「四张被雨打湿的货签」：四箱货与四个去处一一对应。
# 雨里只留下三句话，玩家把货签按上订单板；不逐箱开箱，也不靠点击揭示箱里是什么。
# assign[去处] = 货签编号（-1 表示这一家还空着），一张货签不能同时按在两家。
const GOODS = ["cloth", "oil", "bell", "paper"]
const GOODS_CN = ["布", "油", "铃", "纸"]
const GOODS_FULL = ["布卷", "灯油", "铜铃", "纸卷"]
const KIT_GOODS = ["cloth_bolt", "oil_bottle", "brass_bell", "paper_roll"]
# 去处按街上从左到右排：面包铺的炉子在画面最左，邮亭在右边那排挂木牌的货架前。
const PLACES = ["bakery", "nursery", "bridge", "post"]
const PLACE_CN = ["面包铺", "育苗铺", "桥头", "邮亭"]
# 每张订单在雨里剩下的那半句，由世界层画在纸面上；桥头那句全糊了。
const KEPT = ["不收 铜铃", "收 布卷", "被雨冲开了", "收 纸卷"]
# 三条留下的话：mode 0 = 这一家收这一箱，mode 1 = 这一家不收这一箱。
# 三条合起来只逼出唯一对应；任何一条被抹掉都会多出第二种配法（见无头检查）。
const CLUES = [
	{"mode": 0, "good": 0, "place": 1, "kept": "布去育苗铺"},
	{"mode": 0, "good": 3, "place": 3, "kept": "纸去邮亭"},
	{"mode": 1, "good": 2, "place": 0, "kept": "面包铺不收铃"},
]
const HINTS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "delivery", "complete"]
const ANIMATIONS = ["approach", "delivery"]

static func empty_assign() -> Array:
	var slots = []
	for place in range(PLACES.size()): slots.append(-1)
	return slots

static func fresh() -> Dictionary:
	return {"sample": "market-mk05-1", "stage": "arrival", "beat": 0,
		"assign": empty_assign(), "hand": -1, "hint": 0}

# ---- 计数全部由 assign 现算，画面与提示都不另存一份 ----
static func placed_count(state: Dictionary) -> int:
	return PLACES.size() - state.assign.count(-1)

static func loose(state: Dictionary) -> Array:
	var free = []
	for good in range(GOODS.size()):
		if not state.assign.has(good): free.append(good)
	return free

static func holding(state: Dictionary) -> bool: return state.hand >= 0

static func at(state: Dictionary, good: int) -> int: return state.assign.find(good)

# 一条线索是否已经被摆坏：摆一半也能判，玩家越早看见越好。
static func clue_broken(clue: Dictionary, assign: Array) -> bool:
	var worn = assign.find(clue.good)
	if clue.mode == 1: return worn == clue.place
	if worn >= 0 and worn != clue.place: return true
	var held = assign[clue.place]
	return held >= 0 and held != clue.good

static func broken_clues(state: Dictionary) -> Array:
	var broken = []
	for index in range(CLUES.size()):
		if clue_broken(CLUES[index], state.assign): broken.append(index)
	return broken

# 一张货签按在两家：正常点击做不到，坏档或改档才会出现，但它也必须被当面点出来。
static func conflict_messages(assign: Array) -> Array:
	var out = []
	var seen = []
	for place in range(PLACES.size()):
		var good = assign[place]
		if not good is int or good < 0: continue
		if seen.has(good):
			var homes = []
			for other in range(PLACES.size()):
				if assign[other] == good: homes.append(PLACE_CN[other])
			out.append("%s同时按在了%s：一张货签只能对应一家。" % [GOODS_FULL[good], "、".join(homes)])
			continue
		seen.append(good)
	return out

# 缺口必须点名是哪一句留下的话对不上，不能说成「答案错误」。
static func clue_message(clue: Dictionary, assign: Array) -> String:
	var good = GOODS_FULL[clue.good]
	if clue.mode == 1:
		return "留下的话：%s。%s按在了%s。" % [clue.kept, good, PLACE_CN[clue.place]]
	var worn = assign.find(clue.good)
	if worn >= 0:
		return "留下的话：%s。%s现在按在%s。" % [clue.kept, good, PLACE_CN[worn]]
	return "留下的话：%s。%s现在按的是%s。" % [clue.kept, PLACE_CN[clue.place], GOODS_FULL[assign[clue.place]]]

static func shortfalls(state: Dictionary) -> Array:
	var missing = conflict_messages(state.assign)
	for index in broken_clues(state): missing.append(clue_message(CLUES[index], state.assign))
	var open_places = []
	for place in range(PLACES.size()):
		if state.assign[place] < 0: open_places.append(PLACE_CN[place])
	if not open_places.is_empty():
		missing.append("订单板上还有 %d 家没按货签：%s。" % [open_places.size(), "、".join(open_places)])
	return missing

# 交货的前提：板上没有冲突（一张签不能同时按在两家），三条留下的话都对得上，四家都按满。
static func solved(state: Dictionary) -> bool:
	return valid_assign(state.assign) and shortfalls(state).is_empty()

# ---- 玩家动作：拿起一张货签、按到某一家、从某一家取回 ----
static func pick(state: Dictionary, good: int) -> Dictionary:
	if state.stage != "puzzle" or good < 0 or good >= GOODS.size(): return {}
	if state.assign.has(good): return {}
	var next = state.duplicate(true)
	next.hand = -1 if state.hand == good else good
	return next

static func drop(state: Dictionary, place: int) -> Dictionary:
	if state.stage != "puzzle" or place < 0 or place >= PLACES.size() or state.hand < 0: return {}
	if state.assign.has(state.hand): return {}
	var next = state.duplicate(true)
	# 原来那张退回柜台：一次点击只搬一张，撤销也只需要退一步。
	next.assign[place] = next.hand
	next.hand = -1
	return next

static func take(state: Dictionary, place: int) -> Dictionary:
	if state.stage != "puzzle" or place < 0 or place >= PLACES.size(): return {}
	if state.assign[place] < 0 or state.hand >= 0: return {}
	var next = state.duplicate(true)
	next.assign[place] = -1
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	if not snapshot.has("assign") or not snapshot.has("hand"): return {}
	if not snapshot.get("assign") is Array: return {}
	var next = state.duplicate(true)
	next.assign = (snapshot.assign as Array).duplicate(true)
	next.hand = snapshot.hand
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
			# 空着的格子与摆坏的线索都留在机关上，不进交货演出。
			if not solved(state): return {}
			next.stage = "delivery"
		"delivery": next.stage = "complete"
		_: return {}
	return next

static func valid_assign(value: Variant) -> bool:
	if not value is Array or value.size() != PLACES.size(): return false
	var seen = []
	for good in value:
		if not good is int or good < -1 or good >= GOODS.size(): return false
		if good < 0: continue
		# 一张货签不能同时按在两家。
		if seen.has(good): return false
		seen.append(good)
	return true

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk05-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > 2: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not valid_assign(value.get("assign")): return false
	if not value.get("hand") is int or value.hand < -1 or value.hand >= GOODS.size(): return false
	# 手里的签和板上的签是同一张：不能既在柜台上又在订单上。
	if value.hand >= 0 and value.assign.has(value.hand): return false
	if value.stage != "puzzle" and value.hand != -1: return false
	if value.stage in ["arrival", "approach", "ready"]:
		# 靠近与讲解阶段没人动过货签。
		if value.assign.count(-1) != PLACES.size(): return false
	if value.stage in ["delivery", "complete"] and not solved(value): return false
	return true

extends RefCounted

# MK13 扣扣的旧围巾（可选支线，MK04 之后开门）：
# 围巾的边磨开了，扣扣一段一段数出来正好缺 11 段补边布。育苗铺只按整包卖补边布——
# 一包 3 段、一包 5 段，包不能剪开、也不退半包；她攒的钱一次最多拿三包。
# 柜上的实物库存是「两包 5 段 + 三包 3 段」，凑够 11 段的重数解只有 5+3+3 一种；
# 而她最先看中的偏偏是那两包 5 段——两包 10 段，第三包没有 1 段的。
# 柜面不判分：样边尺只如实数玩家摊上去的段数，够不够只有按下「交给扣扣补边」之后才知道。
const NEED = 11
const FIVE = 5
const THREE = 3
# 柜面上的货：0、1 号是两包 5 段（扣扣最先看中的那两包），2、3、4 号是三包 3 段。
const SEGS = [5, 5, 3, 3, 3]
const MAX_PACKAGES = 3
const HINTS = 3
const STAGES = ["arrival", "approach", "ready", "puzzle", "delivery", "story", "complete"]
const ANIMATIONS = ["approach", "delivery"]

static func fresh() -> Dictionary:
	return {"sample": "market-mk13-1", "stage": "arrival", "beat": 0, "hand": [], "worn": 0, "hint": 0}

# ---- 货与手 ----
static func packages() -> int: return SEGS.size()
static func segs(id: int) -> int: return SEGS[id] if legal_package(id) else 0
static func legal_package(id: int) -> bool: return id >= 0 and id < SEGS.size()
static func in_hand(state: Dictionary, id: int) -> bool: return state.hand.has(id)
static func carried(state: Dictionary) -> int: return state.hand.size()
static func room(state: Dictionary) -> bool: return state.hand.size() < MAX_PACKAGES
static func wearing(state: Dictionary) -> bool: return state.worn == 1

static func total(state: Dictionary) -> int:
	var sum := 0
	for id in state.hand: sum += SEGS[id]
	return sum

static func valid_hand(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_PACKAGES: return false
	for id in value:
		if not id is int or not legal_package(id): return false
		if value.count(id) > 1: return false
	return true

# 第 slot 包摊在样边尺的哪一格起，占几格：按拿起来的先后从左往右排。
static func run_start(state: Dictionary, slot: int) -> int:
	var at := 0
	for index in range(mini(slot, state.hand.size())): at += SEGS[state.hand[index]]
	return at

static func run_segs(state: Dictionary, slot: int) -> int:
	if slot < 0 or slot >= state.hand.size(): return 0
	return SEGS[state.hand[slot]]

static func run_package(state: Dictionary, slot: int) -> int:
	if slot < 0 or slot >= state.hand.size(): return -1
	return state.hand[slot]

# ---- 柜面文字：只复述玩家真正拿了的包，永远不说够不够 ----
static func packages_line(state: Dictionary) -> String:
	if state.hand.is_empty(): return "还没拿包"
	var parts = []
	for id in state.hand: parts.append("%d 段" % SEGS[id])
	return " + ".join(parts)

static func shelf_count(state: Dictionary, size: int) -> int:
	var n := 0
	for id in range(SEGS.size()):
		if SEGS[id] == size and not in_hand(state, id): n += 1
	return n

static func shelf_total(size: int) -> int:
	var n := 0
	for id in range(SEGS.size()):
		if SEGS[id] == size: n += 1
	return n

static func shelf_caption(state: Dictionary, size: int) -> String:
	return "%d 段整包 · 柜上还有 %d 包" % [size, shelf_count(state, size)]

static func left_line(state: Dictionary) -> String:
	return "5 段 %d 包 · 3 段 %d 包" % [shelf_count(state, FIVE), shelf_count(state, THREE)]

static func gauge_caption(state: Dictionary) -> String:
	return "围巾的边 · 要 %d 段 · 已配 %d 段" % [NEED, total(state)]

# ---- 验收：缺多少、多多少，全部用玩家自己拿的段数说话 ----
static func solved(state: Dictionary) -> bool:
	return valid_hand(state.hand) and total(state) == NEED

static func shortfalls(state: Dictionary) -> Array:
	var count = carried(state)
	var got = total(state)
	if count == 0:
		return ["手里还空着：柜上的补边布只按整包卖，最多拿 3 包，凑够围巾的 %d 段。" % NEED]
	if got == NEED: return []
	var line = packages_line(state)
	if got > NEED:
		return ["%s 是 %d 段，比围巾的边多出 %d 段：多出来的不能从包里掰下来退回去。" % [line, got, got - NEED]]
	if count == 2 and got == 10:
		# 这一关的招牌陷阱：最先看中的两包 5 段。合同里的原话照说，不另加训斥。
		return ["两包 5 段已经 10 段，可是第三包只能整包拿，没有 1 段的。"]
	if count == MAX_PACKAGES:
		return ["%s 是 %d 段，还差 %d 段：柜上没有 %d 段的整包，包也不能剪开。" % [line, got, NEED - got, NEED - got]]
	return ["%s 是 %d 段，围巾的边要 %d 段：还差 %d 段，手上还能再拿 %d 包。" % [line, got, NEED, NEED - got, MAX_PACKAGES - count]]

# ---- 玩家动作 ----
static func take(state: Dictionary, id: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_package(id): return {}
	if in_hand(state, id) or not room(state): return {}
	var next = state.duplicate(true)
	next.hand.append(id)
	return next

static func give_back(state: Dictionary, id: int) -> Dictionary:
	if state.stage != "puzzle" or not in_hand(state, id): return {}
	var next = state.duplicate(true)
	next.hand.erase(id)
	return next

# 点空了要说清点空了什么：只讲柜规与手上的包，不评价玩家。
static func refusal(state: Dictionary, id: int) -> String:
	if state.stage != "puzzle" or not legal_package(id): return ""
	if in_hand(state, id):
		return "这一包已经摊在样边尺上了：点它那一截，或者再点柜面这个空位，就退回柜面。"
	if not room(state):
		return "柜上写着一次最多拿 3 包，扣扣的钱也只够 3 包：要这一包，先把一包退回柜面。"
	return ""

static func returned_line(state: Dictionary, id: int) -> String:
	return "把 %d 段那一包退回柜面了：样边尺上现在 %d 段，围巾的边还差 %d 段。" % [SEGS[id], total(state), NEED - total(state)]

# 补好的边戴不戴，是玩家自愿的选择，只写进本关自己的存档。
static func wear(state: Dictionary) -> Dictionary:
	if state.stage not in ["story", "complete"] or state.worn == 1: return {}
	var next = state.duplicate(true); next.worn = 1
	return next

static func tuck(state: Dictionary) -> Dictionary:
	if state.stage not in ["story", "complete"] or state.worn == 0: return {}
	var next = state.duplicate(true); next.worn = 0
	return next

static func wear_line(state: Dictionary) -> String:
	return "扣扣把补好的边戴在外面：11 段，两种颜色一段挨着一段。" if wearing(state) else \
		"扣扣把补好的边藏回领子里：边已经补上了，戴不戴都行。"

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not state.has("stage") or state.stage != "puzzle": return {}
	if not snapshot.has("hand") or not snapshot.has("worn"): return {}
	var next = state.duplicate(true)
	next.hand = snapshot.hand.duplicate(true)
	next.worn = snapshot.worn
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
			next.stage = "delivery"
		"delivery":
			next.stage = "story"; next.beat = 0
		"story":
			if state.beat < 2: next.beat += 1
			else: next.stage = "complete"
		_: return {}
	return next

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk13-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > 2: return false
	# 台词只有开场和故事两处能停在半句上，其余每一幕都必须已经听完。
	if value.stage not in ["arrival", "story"] and value.beat != 2: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not valid_hand(value.get("hand")): return false
	if not value.get("worn") is int or value.worn not in [0, 1]: return false
	# 还没走到柜面前，包都还在柜上，边也没补。
	if value.stage in ["arrival", "approach", "ready"]:
		if not value.hand.is_empty() or value.worn != 0: return false
	# 边缝上围巾、故事讲起来之前没有「换外观」这回事：柜面上与缝边中都还是原来的样子。
	if value.stage in ["puzzle", "delivery"] and value.worn != 0: return false
	# 交货、故事与回执都必须以恰好 11 段作证据：没凑够就写好的完成档一律拒读。
	if value.stage in ["delivery", "story", "complete"] and not solved(value): return false
	return true

extends RefCounted

# MK13 扣扣的旧围巾（可选支线，MK04 之后开门）：
# 围巾的边磨开了，扣扣一段一段数出来正好缺 11 段补边布。育苗铺只按整包卖——一包 3 段、一包 5 段，
# 包不能剪开、也不退半包。补法是把围巾**对折**着缝：11 段两两叠在一起，中间第 6 段压在折痕上，
# 所以摊上样边尺的布除了凑够 11 段，还得左右照得齐——对折过来两头一段挨着一段，扣扣才肯收钱。
# 柜上的货是「两包 5 段 + 三包 3 段」。只看段数，11 段有三条摊法（5+3+3、3+5+3、3+3+5），
# 只看包号更多；加上「对折要齐」这一条，活口就只剩 3+5+3 那一种：5 段那一包正好压住折痕，
# 左右各余 3 格、各摊一包 3 段。玩家最先看中的偏偏是那两包 5 段——10 段，尺上只剩 1 格，
# 柜上没有 1 段的包，多出来的也掰不下来。
# 尺面只有 11 格，摊不下的那一包根本拿不起来：段数永远不会超过 11，也就没有「多出几段」这一说。
# 柜面不判分：样边尺只如实数玩家摊上去的段数，齐不齐只有按下「交给扣扣补边」之后才知道。
const NEED = 11
# 折痕落在第 6 格（1 起算）：画面按这一格画折线，规则层按整个段数序列照不齐说话。
const CREASE = 6
const FIVE = 5
const THREE = 3
# 柜面上的货：0、1 号是两包 5 段（扣扣最先看中的那两包），2、3、4 号是三包 3 段。
const SEGS = [5, 5, 3, 3, 3]
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
static func wearing(state: Dictionary) -> bool: return state.worn == 1

static func total(state: Dictionary) -> int:
	var sum := 0
	for id in state.hand: sum += SEGS[id]
	return sum

# 尺面只剩 NEED - total 格：装得下才算拿得起来，装不下就是摊不下。
static func free_slots(state: Dictionary) -> int: return NEED - total(state)
static func fits(state: Dictionary, id: int) -> bool: return legal_package(id) and segs(id) <= free_slots(state)
static func on_shelf(state: Dictionary) -> Array:
	var out := []
	for id in range(SEGS.size()):
		if not in_hand(state, id): out.append(id)
	return out

# 柜上剩下最小的整包是几段：底栏那句「摊不进空位」按它说话，不写死 3 段或 5 段。
static func smallest_left(state: Dictionary) -> int:
	var least := 0
	for id in on_shelf(state):
		if least == 0 or SEGS[id] < least: least = SEGS[id]
	return least

static func valid_hand(value: Variant) -> bool:
	if not value is Array: return false
	var sum := 0
	for id in value:
		if not id is int or not legal_package(id): return false
		if value.count(id) > 1: return false
		sum += SEGS[id]
	# 摊过尺面就没有格子可数了：这一条同时兜住存档与玩家动作。
	if sum > NEED: return false
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

# 尺上每一格摊的是几段包：一格一个数，这就是「对折之后能不能照上」的那一条序列。
static func cells(state: Dictionary) -> Array:
	var laid := []
	for id in state.hand:
		for _step in range(SEGS[id]): laid.append(SEGS[id])
	return laid

# 对折之后两头齐不齐：第 i 格与第 11-i 格压着同样长的布才算齐。
static func folds_even(state: Dictionary) -> bool:
	var laid := cells(state)
	var at := 0
	while at < laid.size() / 2:
		if laid[at] != laid[laid.size() - 1 - at]: return false
		at += 1
	return true

# 最外面那一对没照上的格子（1 起算的两格）：5+3+3 与 3+3+5 都错在第 1 格与第 11 格。
static func mismatch_pair(state: Dictionary) -> Array:
	var laid := cells(state)
	for at in range(laid.size() / 2):
		if laid[at] != laid[laid.size() - 1 - at]: return [at + 1, laid.size() - at]
	return []

# ---- 柜面文字：只复述玩家真正拿了的包，永远不说够不够、齐不齐 ----
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
	return "样边尺 · %d 格 · 已摊 %d 段" % [NEED, total(state)]

# ---- 验收：段数与对折两样都得以玩家自己摊的格子说话 ----
static func solved(state: Dictionary) -> bool:
	return valid_hand(state.hand) and total(state) == NEED and folds_even(state)

static func shortfalls(state: Dictionary) -> Array:
	var got = total(state)
	if carried(state) == 0:
		return ["尺上还空着一格没摊：包不能剪开，摊满 %d 格、对折两头齐，扣扣才收钱。" % NEED]
	if got == NEED:
		if folds_even(state): return []
		var pair := mismatch_pair(state)
		var laid := cells(state)
		return ["11 段摊满了：对折过来第 %d 格是 %d 段包，第 %d 格是 %d 段包，两头不齐。" % [
			pair[0], laid[pair[0] - 1], pair[1], laid[pair[1] - 1]]]
	# 还差几段，可是柜上最小的整包已经塞不进剩下的空位：这一句是本关真正的死口。
	if smallest_left(state) > free_slots(state):
		if got == NEED - 1:
			# 这一关的招牌陷阱：最先看中的那两包 5 段。合同里的原话照说，不另加训斥。
			return ["两包 5 段已经 10 段，尺上只剩 1 格：柜上没有 1 段的整包。"]
		return ["%s 是 %d 段，还差 %d 段：柜上最小的整包 %d 段，摊不进这 %d 格空位。" % [
			packages_line(state), got, NEED - got, smallest_left(state), free_slots(state)]]
	if carried(state) == 1:
		# 只摊了一包时，「5 段 是 5 段」是同一句话说两遍。
		return ["一包 %d 段，还差 %d 段：对折要两头齐，先想好哪一包压住折痕。" % [got, NEED - got]]
	return ["%s 是 %d 段，还差 %d 段：%d 格空位摊得下 3 段，也摊得下 5 段。" % [
		packages_line(state), got, NEED - got, free_slots(state)]]

# ---- 玩家动作 ----
static func take(state: Dictionary, id: int) -> Dictionary:
	if state.stage != "puzzle" or not legal_package(id): return {}
	if in_hand(state, id) or not fits(state, id): return {}
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
	if not fits(state, id):
		return "样边尺只剩 %d 格：%d 段的整包摊不进去，包不能剪开。" % [free_slots(state), segs(id)]
	return ""

static func returned_line(state: Dictionary, id: int) -> String:
	return "把 %d 段那一包退回柜面了：样边尺上现在摊了 %d 段，还差 %d 格。" % [SEGS[id], total(state), free_slots(state)]

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
	return "扣扣把补好的边戴在外面：对折过去，两头一段挨着一段。" if wearing(state) else \
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
	# 交货、故事与回执都必须以「摊满 11 格且对折两头齐」作证据：
	# 段数凑够就对折照不上的那一摊，一律不算补好了边。
	if value.stage in ["delivery", "story", "complete"] and not solved(value): return false
	return true

extends RefCounted
# GW12 装配间「两班合起来，槽数才找得到」：第一班 23 枚、第二班 24 枚同型标准件，
# 托盘容量牌丢失，已知每托 3～12 枚整数，两班用同一种托。每班结束只交走所有满托，
# 余料完整留到下一班；交接册写着两班一共交 9 个满托、最后还剩 2 枚。
# 满托数、余料与两班合计全部由这里现算，画面不另存除法结果，换槽数不会留下旧判定。
const SAMPLE = "workshop-gw12-1"
const CAP_MIN = 3
const CAP_MAX = 12
const FIRST = 23
const SECOND = 24
const BOOK_TRAYS = 9
const BOOK_LEFT = 2
const BOX = 11
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","capacity","first_keep","second_keep","tried","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"capacity":0,
		"first_keep":-1,"second_keep":-1,"tried":[],"hint":0}

# 一次除法就够：满托数与零散数。余数天然小于容量（容量 3～12 都是正整数）。
static func division(total: int, capacity: int) -> Array:
	return [total/capacity,total%capacity]

# 留下的余料必须让交走的正好是整托，而且不够再装一托：满托要全部交走。
static func keep_legal(total: int, capacity: int, keep: int) -> bool:
	if capacity < CAP_MIN or capacity > CAP_MAX: return false
	if keep < 0 or keep > BOX or keep >= capacity: return false
	return (total-keep) % capacity == 0

# 一个槽数的完整执行：第一班交几托、留几枚，第二班接入后交几托、最后剩几枚。
static func plan(capacity: int) -> Array:
	if capacity < CAP_MIN or capacity > CAP_MAX: return []
	var first = division(FIRST,capacity)
	var second = division(first[1]+SECOND,capacity)
	return [first[0],first[1],second[0],second[1]]

# 让交接册成立（9 个满托、最后 2 枚）的槽数：本题只有 5，规则仍按枚举算。
static func solution() -> Array:
	var out = []
	for capacity in range(CAP_MIN,CAP_MAX+1):
		var parts = plan(capacity)
		if parts[0]+parts[2] == BOOK_TRAYS and parts[3] == BOOK_LEFT: out.append(capacity)
	return out

# 两班都真的执行过、而且每一步都装成整托，才算执行完。
static func executed(s: Dictionary) -> bool:
	return keep_legal(FIRST,s.capacity,s.first_keep) \
		and keep_legal(s.first_keep+SECOND,s.capacity,s.second_keep)

static func first_trays(s: Dictionary) -> int:
	if not keep_legal(FIRST,s.capacity,s.first_keep): return 0
	return (FIRST-s.first_keep)/s.capacity

static func second_total(s: Dictionary) -> int:
	return s.first_keep+SECOND if s.first_keep >= 0 else SECOND

static func second_trays(s: Dictionary) -> int:
	if not executed(s): return 0
	return (s.first_keep+SECOND-s.second_keep)/s.capacity

static func total_trays(s: Dictionary) -> int:
	return first_trays(s)+second_trays(s)

static func solved(s: Dictionary) -> bool:
	return executed(s) and total_trays(s) == BOOK_TRAYS and s.second_keep == BOOK_LEFT

# 只说明真实违反的条件：还没提槽数、哪一班还没执行、合计与交接册差多少。
static func shortfalls(s: Dictionary) -> Array:
	if s.capacity < CAP_MIN or s.capacity > CAP_MAX:
		return ["先从 3～12 里提出一个槽数：两班用同一种托。"]
	if s.first_keep < 0:
		return ["第一班还没交班：23 枚按 %d 枚一托，先定留几枚。"%s.capacity]
	if s.second_keep < 0:
		return ["第二班还没收工：接入 %d 枚后共 %d 枚，先定最后留几枚。"%[s.first_keep,s.first_keep+SECOND]]
	if solved(s): return []
	var trays = total_trays(s)
	if s.second_keep == BOOK_LEFT:
		return ["最后确实剩 %d 枚，可两班一共交了 %d 个满托（%d＋%d），交接册写的是 %d 个。"%[BOOK_LEFT,trays,first_trays(s),second_trays(s),BOOK_TRAYS]]
	return ["两班一共交 %d 个满托（%d＋%d）、最后剩 %d 枚；交接册写的是 %d 个满托、剩 %d 枚。"%[trays,first_trays(s),second_trays(s),s.second_keep,BOOK_TRAYS,BOOK_LEFT]]

# 玩家点了一个交班余料：说明为什么这个留法装不成整托。
static func keep_reason(total: int, capacity: int, keep: int) -> String:
	if capacity < CAP_MIN or capacity > CAP_MAX: return "先提出槽数，再定余料。"
	if keep >= capacity:
		return "留 %d 枚已经够再装一个满托：满托要全部交走，余料只能少于一托。"%keep
	var sent = total-keep
	return "交走 %d 枚，装不成 %d 枚一托的整托（%d = %d × %d + %d）：满托要全部交走。"%[sent,capacity,sent,sent/capacity,capacity,sent%capacity]

static func select(s: Dictionary, capacity: int) -> Dictionary:
	if s.stage != "puzzle" or capacity < CAP_MIN or capacity > CAP_MAX or capacity == s.capacity: return {}
	var n = s.duplicate(true)
	n.capacity = capacity; n.first_keep = -1; n.second_keep = -1
	return n if validate(n) else {}

# 还没提出槽数时，左右一步先落在 3 槽上；之后在 3～12 之间移动。
static func move_capacity(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle": return {}
	var current = s.capacity if s.capacity >= CAP_MIN else CAP_MIN-1
	return select(s,clampi(current+delta,CAP_MIN,CAP_MAX))

# 第一班交班：余料要正好让 23 枚交成整托。按下这一下就是玩家确认的切班。
static func set_first_keep(s: Dictionary, keep: int) -> Dictionary:
	if s.stage != "puzzle" or s.first_keep >= 0: return {}
	if not keep_legal(FIRST,s.capacity,keep): return {}
	var n = s.duplicate(true); n.first_keep = keep
	return n if validate(n) else {}

# 第二班收工：接入第一班余料后，最后留下的也要让交走的是整托。
static func set_second_keep(s: Dictionary, keep: int) -> Dictionary:
	if s.stage != "puzzle" or s.first_keep < 0 or s.second_keep >= 0: return {}
	if not keep_legal(s.first_keep+SECOND,s.capacity,keep): return {}
	var n = s.duplicate(true); n.second_keep = keep
	if not n.tried.has(n.capacity):
		n.tried.append(n.capacity); n.tried.sort()
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("capacity") or not snapshot.has("first_keep") \
		or not snapshot.has("second_keep") or not snapshot.has("tried"): return {}
	var n = s.duplicate(true)
	n.capacity = snapshot.capacity
	n.first_keep = snapshot.first_keep
	n.second_keep = snapshot.second_keep
	n.tried = snapshot.tried.duplicate()
	return n if validate(n) else {}

static func advance(s: Dictionary) -> Dictionary:
	var n = s.duplicate(true)
	match s.stage:
		"arrival":
			if s.beat < 2: n.beat += 1
			else: n.stage = "approach"
		"approach": n.stage = "ready"
		"ready": n.stage = "puzzle"
		"puzzle":
			if not solved(s): return {}
			n.stage = "delivery"
		"delivery": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

# 试过的槽数：从小到大、不重复；越界或重复都算损坏。
static func legal_tried(value: Variant) -> bool:
	if not value is Array or value.size() > CAP_MAX-CAP_MIN+1: return false
	var last = 0
	for capacity in value:
		if not capacity is int or capacity < CAP_MIN or capacity > CAP_MAX: return false
		if capacity <= last: return false
		last = capacity
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","capacity","first_keep","second_keep","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.capacity != 0 and (v.capacity < CAP_MIN or v.capacity > CAP_MAX): return false
	if v.first_keep != -1 and not keep_legal(FIRST,v.capacity,v.first_keep): return false
	if v.second_keep != -1:
		if v.first_keep < 0 or not keep_legal(v.first_keep+SECOND,v.capacity,v.second_keep): return false
	if not legal_tried(v.tried): return false
	if v.capacity == 0 and not v.tried.is_empty(): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.capacity != 0 or v.first_keep != -1 or v.second_keep != -1 or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

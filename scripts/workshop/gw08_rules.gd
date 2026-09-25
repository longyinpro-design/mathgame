extends RefCounted
# GW08 旧报时廊「两张旧单，锁定一块槽板」：同型旧托盘每托装 5～16 根整数灯轴。
# 记录一：35 根装完满托后剩 3 根；记录二：47 根装完满托后剩 7 根。没有损耗，余数必须小于每托容量。
# 两张记录各自的候选都多于一个（8、16 与 8、10），合起来才只剩 8 槽。
# 候选、重演记录与排除表全部由这里算；画面不另存除法结果，换槽数不会留下旧判定。
const SAMPLE = "workshop-gw08-1"
const CAP_MIN = 5
const CAP_MAX = 16
const RECORDS = [35,47]
const REMAINDERS = [3,7]
const RECORD_NAMES = ["记录一","记录二"]
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","capacity","tested_first","tested_second","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"capacity":0,
		"tested_first":[],"tested_second":[],"hint":0}

# 一次除法就够：满托数与零散数。余数天然小于容量（容量 5～16 都是正整数）。
static func division(total: int, capacity: int) -> Array:
	return [total/capacity,total%capacity]

# 一张记录是否认这个槽数：余数必须正好等于记录写下的零散数。
static func matches(record: int, capacity: int) -> bool:
	if capacity < CAP_MIN or capacity > CAP_MAX: return false
	return division(RECORDS[record],capacity)[1] == REMAINDERS[record]

static func candidates(record: int) -> Array:
	var out = []
	for capacity in range(CAP_MIN,CAP_MAX+1):
		if matches(record,capacity): out.append(capacity)
	return out

# 两张记录都认的槽数：本题只有 8，规则仍然按交集算。
static func solution() -> Array:
	var out = []
	for capacity in range(CAP_MIN,CAP_MAX+1):
		if matches(0,capacity) and matches(1,capacity): out.append(capacity)
	return out

static func tested(s: Dictionary, record: int) -> Array:
	return s.tested_first if record == 0 else s.tested_second

# 画面与状态栏共用的一句判定：未提出 / 未重演 / 相符 / 不符。
static func mark(s: Dictionary, record: int) -> String:
	if s.capacity < CAP_MIN or s.capacity > CAP_MAX: return "未提出"
	if not tested(s,record).has(s.capacity): return "未重演"
	return "相符" if matches(record,s.capacity) else "不符"

static func solved(s: Dictionary) -> bool:
	return s.capacity >= CAP_MIN and s.capacity <= CAP_MAX \
		and tested(s,0).has(s.capacity) and tested(s,1).has(s.capacity) \
		and matches(0,s.capacity) and matches(1,s.capacity)

# 只说明真实违反的条件：还没提出槽数、哪张记录没重演、重演出来的余数是多少。
static func shortfalls(s: Dictionary) -> Array:
	if s.capacity < CAP_MIN or s.capacity > CAP_MAX:
		return ["先从旧槽板里提出一个槽数：每托装 5～16 根整数。"]
	var out = []
	for record in range(2):
		var parts = division(RECORDS[record],s.capacity)
		if not tested(s,record).has(s.capacity):
			out.append("%s还没重演过：按 %d 槽跑一遍，看 %d 根装完满托后剩几根。"%[RECORD_NAMES[record],s.capacity,RECORDS[record]])
		elif parts[1] != REMAINDERS[record]:
			out.append("%d 根按 %d 一托：%d 个满托、剩 %d 根；%s写的是剩 %d 根。"%[RECORDS[record],s.capacity,parts[0],parts[1],RECORD_NAMES[record],REMAINDERS[record]])
	return out

static func select(s: Dictionary, capacity: int) -> Dictionary:
	if s.stage != "puzzle" or capacity < CAP_MIN or capacity > CAP_MAX or capacity == s.capacity: return {}
	var n = s.duplicate(true); n.capacity = capacity
	return n if validate(n) else {}

# 还没提出槽数时，左右一步先落在 5 槽上；之后在 5～16 之间移动。
static func move_capacity(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle": return {}
	var current = s.capacity if s.capacity >= CAP_MIN else CAP_MIN-1
	var capacity = clampi(current+delta,CAP_MIN,CAP_MAX)
	if capacity == s.capacity: return {}
	var n = s.duplicate(true); n.capacity = capacity
	return n if validate(n) else {}

# 重演一张记录：把当前槽数记进这张记录的重演表，重复重演不会留下第二条。
static func replay(s: Dictionary, record: int) -> Dictionary:
	if s.stage != "puzzle" or record < 0 or record > 1 or s.capacity < CAP_MIN: return {}
	var n = s.duplicate(true)
	var list = n.tested_first if record == 0 else n.tested_second
	if not list.has(n.capacity):
		list.append(n.capacity); list.sort()
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("capacity") or not snapshot.has("tested_first") or not snapshot.has("tested_second"): return {}
	var n = s.duplicate(true)
	n.capacity = snapshot.capacity
	n.tested_first = snapshot.tested_first.duplicate()
	n.tested_second = snapshot.tested_second.duplicate()
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

static func legal_tested(value: Variant) -> bool:
	if not value is Array or value.size() > CAP_MAX-CAP_MIN+1: return false
	var seen = {}
	for capacity in value:
		if not capacity is int or capacity < CAP_MIN or capacity > CAP_MAX: return false
		if seen.has(capacity): return false
		seen[capacity] = true
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","capacity","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.capacity != 0 and (v.capacity < CAP_MIN or v.capacity > CAP_MAX): return false
	if not legal_tested(v.tested_first) or not legal_tested(v.tested_second): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.capacity != 0 or not v.tested_first.is_empty() or not v.tested_second.is_empty() or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

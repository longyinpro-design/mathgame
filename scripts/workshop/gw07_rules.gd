extends RefCounted
# GW07 装配间「检修前，先留好位置」：A、B、C、D 依次经过压机与冷却机，压制各 1 拍、冷却各 2 拍。
# 冷却机在第 4～5 拍检修，冷却工序不能与检修区间重叠，也不能暂停后接着冷却。
# 两台机各一次一件；中间只有一个暂存位，先来先冷却，所以压机不能当仓库。
# 开局给一张「压完就冷」的顺排草稿，玩家要改的是压在检修段上的那一段和顶住的暂存位。
const ITEMS = ["A","B","C","D"]
const COUNT = 4
const PRESS_TIME = 1
const COOL_TIME = 2
const MAINT_START = 4
const MAINT_END = 5
const DEADLINE = 11
const RANGE_MAX = 11
const HORIZON = 14
const DEFAULT_PRESS = [0,1,2,3]
const DEFAULT_COOL = [1,3,5,7]
const STAGES = ["arrival","approach","ready","puzzle","trial","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","trial","delivery"]
const FIELDS = ["sample","stage","beat","press","cool","hint","attempts"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw07-1","stage":"arrival","beat":0,
		"press":DEFAULT_PRESS.duplicate(),"cool":DEFAULT_COOL.duplicate(),"hint":0,"attempts":0}

static func legal_starts(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	for start in value:
		if not start is int or start < 0 or start > RANGE_MAX: return false
	return true

static func makespan(s: Dictionary) -> int:
	var last = 0
	for start in s.cool: last = maxi(last,start+COOL_TIME)
	return last

# 每件货的压制区间、冷却区间与等待暂存位的区间：全部按开局时刻现算。
static func plan(s: Dictionary) -> Array:
	var rows = []
	for index in range(COUNT):
		rows.append({"item":ITEMS[index],"press_start":s.press[index],"press_end":s.press[index]+PRESS_TIME,
			"cool_start":s.cool[index],"cool_end":s.cool[index]+COOL_TIME,
			"wait_start":s.press[index]+PRESS_TIME,"wait_end":s.cool[index]})
	return rows

static func ordered(value: Array) -> bool:
	for index in range(1,value.size()):
		if value[index-1] >= value[index]: return false
	return true

# 逐拍检查两机、暂存位与检修段；返回第一处说不通的地方。
static func scan(s: Dictionary) -> Dictionary:
	for t in range(HORIZON):
		var pressing = []
		var cooling = []
		var waiting = []
		for index in range(COUNT):
			if s.press[index] <= t and t < s.press[index]+PRESS_TIME: pressing.append(index)
			if s.cool[index] <= t and t < s.cool[index]+COOL_TIME: cooling.append(index)
			if s.press[index]+PRESS_TIME <= t and t < s.cool[index]: waiting.append(index)
		if pressing.size() > 1:
			return {"tick":t,"text":"第 %d 拍：%s 和 %s 同时占着压机——压机一次只压一件。"%[t,ITEMS[pressing[0]],ITEMS[pressing[1]]]}
		if cooling.size() > 1:
			return {"tick":t,"text":"第 %d 拍：%s 和 %s 同时占着冷却机——冷却机一次只冷却一件。"%[t,ITEMS[cooling[0]],ITEMS[cooling[1]]]}
		if not cooling.is_empty() and t >= MAINT_START and t < MAINT_END:
			var held = cooling[0]
			return {"tick":t,"text":"第 %d 拍：%s 的冷却 %d–%d 压在检修段上——冷却不能中断，整段都得避开第 %d～%d 拍。"%[t,ITEMS[held],s.cool[held],s.cool[held]+COOL_TIME,MAINT_START,MAINT_END]}
		if waiting.size() > 1:
			return {"tick":t,"text":"第 %d 拍：%s 和 %s 都停在暂存位上——中间只有一个位置。"%[t,ITEMS[waiting[0]],ITEMS[waiting[1]]]}
	return {}

# 只说明真实违反的条件，顺序问题排在逐拍问题前面：先后没理顺，逐拍表就先不用看。
static func problems(s: Dictionary) -> Array:
	var out = []
	if not ordered(s.press):
		out.append("压制要按 A、B、C、D 的先后排：现在是 A 第 %d 拍、B 第 %d 拍、C 第 %d 拍、D 第 %d 拍。"%[s.press[0],s.press[1],s.press[2],s.press[3]])
	if not ordered(s.cool):
		out.append("冷却要按 A、B、C、D 的先后排：现在是 A 第 %d 拍、B 第 %d 拍、C 第 %d 拍、D 第 %d 拍。"%[s.cool[0],s.cool[1],s.cool[2],s.cool[3]])
	for index in range(COUNT):
		if s.cool[index] < s.press[index]+PRESS_TIME:
			out.append("%s 的冷却排在第 %d 拍，可它到第 %d 拍才压完。"%[ITEMS[index],s.cool[index],s.press[index]+PRESS_TIME])
	if not out.is_empty(): return out
	var found = scan(s)
	if not found.is_empty(): out.append(found.text)
	elif makespan(s) > DEADLINE:
		out.append("这套排法到第 %d 拍才做完，赶不上第 %d 拍结束。"%[makespan(s),DEADLINE])
	return out

static func ready(_s: Dictionary) -> bool: return true
static func solved(s: Dictionary) -> bool: return problems(s).is_empty()
static func shortfalls(s: Dictionary) -> Array: return problems(s)

# 同一台机上的一件只能出现在一个时刻：点某件把它推到别的拍就是改这一格。
static func set_start(s: Dictionary, row: int, index: int, value: int) -> Dictionary:
	if s.stage != "puzzle" or row < 0 or row > 1 or index < 0 or index >= COUNT: return {}
	if value < 0 or value > RANGE_MAX: return {}
	var n = s.duplicate(true)
	n["press" if row == 0 else "cool"][index] = value
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("press") or not snapshot.has("cool"): return {}
	var n = s.duplicate(true); n.press = snapshot.press.duplicate(); n.cool = snapshot.cool.duplicate()
	return n if validate(n) else {}

static func back_to_plan(s: Dictionary) -> Dictionary:
	if s.stage != "trial": return {}
	var n = s.duplicate(true); n.stage = "puzzle"
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
			n.attempts = mini(1000000,n.attempts+1); n.stage = "trial"
		"trial":
			if solved(s): n.stage = "delivery"
			else: n.stage = "puzzle"
		"delivery": n.stage = "aftermath"; n.beat = 0
		"aftermath":
			if s.beat < 2: n.beat += 1
			else: n.stage = "complete"
		_: return {}
	return n

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != "workshop-gw07-1" or v.stage not in STAGES: return false
	for key in ["beat","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.attempts < 0 or v.attempts > 1000000: return false
	if not legal_starts(v.press) or not legal_starts(v.cool): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.press != DEFAULT_PRESS or v.cool != DEFAULT_COOL or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","trial","delivery","complete"] and v.beat != 2: return false
	if v.stage == "trial" and v.attempts < 1: return false
	if v.stage in ["delivery","aftermath","complete"]:
		if not solved(v) or v.attempts < 1: return false
	return true

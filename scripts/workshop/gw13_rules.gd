extends RefCounted
# GW13 休息桌「两只鸟，到底叫了几次」：两只旧玩具鸟第 0 拍一起叫，
# 此后甲每 4 拍叫一次、乙每 6 拍叫一次；观察 0～24 拍，两端都算。
# 同一拍两只一起叫，只算一个「听到叫声的时刻」。
# 问：总共几个时刻听到叫声，其中几个只有一只鸟叫。
# 甲 7 次（0、4、8、12、16、20、24）、乙 5 次（0、6、12、18、24），
# 0、12、24 三拍重合：不同时刻 7+5−3=9，独鸣 9−3=6。
# 叫点表、重合表、逐拍对照与两个数量都由这里算；画面不另存叫点，改标记不会留下旧判定。
const SAMPLE = "workshop-gw13-1"
const HORIZON = 24
const PERIODS = [4,6]
const BIRD_NAMES = ["甲","乙"]
const COUNT_MIN = 0
# 两个数量都从 0 起，上界是两只鸟的叫声总数：听到的时刻与独鸣都不可能超过它。
const COUNT_MAX = 12
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","marks","heard","solo","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"marks":[],"heard":-1,"solo":-1,"hint":0}

# 一只鸟的叫点：从第 0 拍起按自己的周期走到观察结束，两端都算。
static func calls(bird: int) -> Array:
	var out = []
	if bird < 0 or bird >= PERIODS.size(): return out
	var tick = 0
	while tick <= HORIZON:
		out.append(tick); tick += PERIODS[bird]
	return out

# 某一拍有谁在叫：0 = 甲、1 = 乙；没鸟叫就是空表。
static func callers(tick: int) -> Array:
	var out = []
	if tick < 0 or tick > HORIZON: return out
	for bird in range(PERIODS.size()):
		if tick % PERIODS[bird] == 0: out.append(bird)
	return out

# 两只同拍：这一拍只能算一个时刻，也是「7+5」重复数的那部分。
static func together() -> Array:
	var out = []
	for tick in range(HORIZON+1):
		if callers(tick).size() > 1: out.append(tick)
	return out

# 听到叫声的时刻：两只鸟叫点的并集。
static func heard() -> Array:
	var out = []
	for tick in range(HORIZON+1):
		if not callers(tick).is_empty(): out.append(tick)
	return out

# 独鸣时刻：只有一只鸟叫的那些拍。
static func solo() -> Array:
	var out = []
	for tick in range(HORIZON+1):
		if callers(tick).size() == 1: out.append(tick)
	return out

static func count_of(s: Dictionary, row: int) -> int:
	return s.heard if row == 0 else s.solo

static func count_name(row: int) -> String:
	return "总共几个时刻听到叫声" if row == 0 else "其中几个只有一只鸟叫"

static func value_text(value: int) -> String:
	return "未填" if value < 0 else str(value)

static func tick_list(ticks: Array) -> String:
	var parts = []
	for tick in ticks: parts.append(str(tick))
	return "、".join(parts)

static func marks_text(s: Dictionary) -> String:
	if s.marks.is_empty(): return "还没圈重合：点时间尺上的一列，圈出两只鸟同拍的时刻"
	return "你圈的重合：%s（%d 处）"%[tick_list(s.marks),s.marks.size()]

# 三个子答案同时成立才算解：圈出的重合正好是三拍同拍，两个数量各自对上逐拍结果。
static func solved(s: Dictionary) -> bool:
	if s.marks.size() != together().size(): return false
	for tick in together():
		if not s.marks.has(tick): return false
	return s.heard == heard().size() and s.solo == solo().size()

# 只说明最要紧的一处真实违反：还没圈重合、圈错哪一拍、两个数量还没填、哪个数量对不上逐拍。
static func shortfalls(s: Dictionary) -> Array:
	if s.stage != "puzzle": return []
	if s.marks.is_empty():
		return ["先在时间尺上圈出两只鸟同拍的时刻：同一拍只算一个「听到叫声的时刻」。"]
	for tick in range(HORIZON+1):
		if not s.marks.has(tick): continue
		var who = callers(tick)
		if who.size() < 2:
			var what = "两只鸟都没叫" if who.is_empty() else "只有%s在叫"%BIRD_NAMES[who[0]]
			return ["第 %d 拍%s，不是两只同拍，你把它圈上了。"%[tick,what]]
	for tick in together():
		if not s.marks.has(tick):
			return ["第 %d 拍两只鸟一起叫，是重合，你还没圈上。"%tick]
	if s.heard < 0:
		return ["重合圈好了。再提交「总共几个时刻听到叫声」。"]
	if s.solo < 0:
		return ["再提交「其中几个只有一只鸟叫」。"]
	if s.heard != heard().size():
		return ["总共几个时刻听到叫声，你写的是 %d；0 到 %d 拍两端都算，甲叫 %d 次、乙叫 %d 次，%s 三拍两只一起叫，只算一个时刻。"%[
			s.heard,HORIZON,calls(0).size(),calls(1).size(),tick_list(together())]]
	if s.solo != solo().size():
		return ["只有一只鸟叫的时刻，你写的是 %d；总共 %d 个时刻里，%s 三拍两只一起叫，不算独鸣。"%[
			s.solo,s.heard,tick_list(together())]]
	return []

# 圈一拍 / 取消这一拍：重合是玩家的判断，点错一下就是收回。
static func mark(s: Dictionary, tick: int) -> Dictionary:
	if s.stage != "puzzle" or tick < 0 or tick > HORIZON: return {}
	var n = s.duplicate(true)
	var marks = n.marks.duplicate()
	if marks.has(tick): marks.erase(tick)
	else: marks.append(tick)
	marks.sort()
	n.marks = marks
	return n if validate(n) else {}

# 两个数量各自独立：先填哪一个都行，重复点同一个值等于没动。
static func set_count(s: Dictionary, row: int, value: int) -> Dictionary:
	if s.stage != "puzzle" or row < 0 or row > 1: return {}
	if value < COUNT_MIN or value > COUNT_MAX or value == count_of(s,row): return {}
	var n = s.duplicate(true)
	if row == 0: n.heard = value
	else: n.solo = value
	return n if validate(n) else {}

# 还没填过的数量，第一步先落在 0；之后在 0～12 之间走。
static func step_count(s: Dictionary, row: int, delta: int) -> Dictionary:
	if s.stage != "puzzle" or row < 0 or row > 1: return {}
	var current = count_of(s,row)
	var from = current if current >= COUNT_MIN else COUNT_MIN-1
	return set_count(s,row,clampi(from+delta,COUNT_MIN,COUNT_MAX))

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("marks") or not snapshot.has("heard") or not snapshot.has("solo"): return {}
	var n = s.duplicate(true)
	n.marks = snapshot.marks.duplicate(); n.heard = snapshot.heard; n.solo = snapshot.solo
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

static func legal_marks(value: Variant) -> bool:
	if not value is Array or value.size() > HORIZON+1: return false
	var seen = {}
	for tick in value:
		if not tick is int or tick < 0 or tick > HORIZON: return false
		if seen.has(tick): return false
		seen[tick] = true
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","heard","solo","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if not legal_marks(v.marks): return false
	for value in [v.heard,v.solo]:
		if value != -1 and (value < COUNT_MIN or value > COUNT_MAX): return false
	if v.stage in ["arrival","approach","ready"]:
		if not v.marks.is_empty() or v.heard != -1 or v.solo != -1 or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

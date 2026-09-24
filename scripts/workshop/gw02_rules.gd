extends RefCounted
# GW02 装配间「留样之后，还缺多少」：给 8 片铜料各选四孔模或七孔模，两种模都要用；
# 每种模第一次加工的那一整批要封存留样、不能拿去安装。
# 产量、留样与安装数一律由 molds 现算，画面不另存计数，所以改一片铜料不会留下幻影产量。
const SHEETS = 8
const SMALL = 4
const LARGE = 7
const NEED = 27
const MOULDS = [SMALL, LARGE]
const STAGES = ["arrival","approach","ready","puzzle","pressing","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","pressing","delivery"]
const FIELDS = ["sample","stage","beat","molds","hint","attempts"]

static func empty() -> Array:
	var values = []
	for i in range(SHEETS): values.append(0)
	return values

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw02-1","stage":"arrival","beat":0,"molds":empty(),"hint":0,"attempts":0}

# 存档里的越界模具、非整数、错长度都算损坏；0 表示这一片还没选模。
static func legal_moulds(value: Variant) -> bool:
	if not value is Array or value.size() != SHEETS: return false
	for mould in value:
		if not mould is int: return false
		if mould != 0 and not MOULDS.has(mould): return false
	return true

static func assigned(s: Dictionary) -> int:
	var count = 0
	for mould in s.molds:
		if mould != 0: count += 1
	return count

static func produced(s: Dictionary) -> int:
	var total = 0
	for mould in s.molds: total += mould
	return total

# 每种模第一次加工的那一整批封存检测：取该模在排产顺序里最靠前的一片。
static func sealed(s: Dictionary) -> Array:
	var out = []
	for mould in MOULDS:
		for index in range(SHEETS):
			if s.molds[index] == mould:
				out.append(index); break
	return out

static func installed(s: Dictionary) -> int:
	var total = produced(s)
	for index in sealed(s): total -= s.molds[index]
	return total

static func both_used(s: Dictionary) -> bool:
	return s.molds.has(SMALL) and s.molds.has(LARGE)

static func solved(s: Dictionary) -> bool:
	return assigned(s) == SHEETS and both_used(s) and installed(s) == NEED

# 8 片都选满就允许试压：错答案也能看到自己这一台出了什么，判定留给结果。
static func ready_to_press(s: Dictionary) -> bool:
	return assigned(s) == SHEETS

# 只说明真实违反的条件：缺哪几片、哪种模没开、安装数差多少。
static func shortfalls(s: Dictionary) -> Array:
	var missing = []
	if assigned(s) < SHEETS:
		missing.append("还有 %d 片铜料没选模具：8 片都要用上。"%(SHEETS-assigned(s)))
		return missing
	if not both_used(s):
		missing.append("四孔模和七孔模都要用上：只开一种模，另一种的留样盒就空着。")
		return missing
	var made = produced(s)
	var kept = made-installed(s)
	if installed(s) < NEED:
		missing.append("8 片一共出了 %d 枚，两盒留样封存 %d 枚，能安装 %d 枚，还差 %d 枚。"%[made,kept,installed(s),NEED-installed(s)])
	elif installed(s) > NEED:
		missing.append("8 片一共出了 %d 枚，两盒留样封存 %d 枚，能安装 %d 枚，多了 %d 枚。"%[made,kept,installed(s),installed(s)-NEED])
	return missing

# 盖章：把某一片铜料的模具定下来。0 表示还没选。
static func set_mould(s: Dictionary, index: int, mould: int) -> Dictionary:
	if s.stage != "puzzle" or index < 0 or index >= SHEETS: return {}
	if mould != 0 and not MOULDS.has(mould): return {}
	var n = s.duplicate(true); n.molds[index] = mould
	return n if validate(n) else {}

static func clear_sheet(s: Dictionary, index: int) -> Dictionary:
	return set_mould(s,index,0)

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("molds"): return {}
	var n = s.duplicate(true); n.molds = snapshot.molds.duplicate(true)
	return n if validate(n) else {}

static func back_to_plan(s: Dictionary) -> Dictionary:
	if s.stage != "pressing": return {}
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
			if not ready_to_press(s): return {}
			n.attempts = mini(1000000,n.attempts+1); n.stage = "pressing"
		"pressing":
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
	if v.sample != "workshop-gw02-1" or v.stage not in STAGES: return false
	for key in ["beat","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.attempts < 0 or v.attempts > 1000000: return false
	if not legal_moulds(v.molds): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.molds != empty() or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","pressing","delivery","complete"] and v.beat != 2: return false
	if v.stage == "pressing":
		if assigned(v) != SHEETS or v.attempts < 1: return false
	if v.stage in ["delivery","aftermath","complete"]:
		if not solved(v) or v.attempts < 1: return false
	return true

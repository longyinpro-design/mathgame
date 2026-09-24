extends RefCounted
# GW05 装配间「七拍能做完吗」：三件工具都要先钻孔再抛光，一台钻机一台抛光机各一次一件。
# 玩家排的是两条工序带上的先后顺序；工序带按最早可行时刻贴紧排列，所以顺序决定整张时刻表。
# 完成时刻由顺序现算，画面不另存时间格。
const TOOLS = 3
const NAMES = ["A","B","C"]
const DRILL = [3,2,1]
const POLISH = [1,3,2]
const DEADLINE = 7
const STAGES = ["arrival","approach","ready","puzzle","trial","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","trial","delivery"]
const FIELDS = ["sample","stage","beat","drill","polish","hint","attempts"]

static func fresh() -> Dictionary:
	return {"sample":"workshop-gw05-1","stage":"arrival","beat":0,"drill":[],"polish":[],"hint":0,"attempts":0}

static func legal_order(value: Variant) -> bool:
	if not value is Array or value.size() > TOOLS: return false
	var seen = {}
	for tool in value:
		if not tool is int or tool < 0 or tool >= TOOLS: return false
		if seen.has(tool): return false
		seen[tool] = true
	return true

# 两条工序带：钻孔带从第 0 拍起贴紧排，抛光带等前一件抛光完、且这一件钻完才开始。
static func timeline(s: Dictionary) -> Dictionary:
	var at = 0; var drill_rows = []; var ends = {}
	for tool in s.drill:
		drill_rows.append({"tool":tool,"start":at,"end":at+DRILL[tool]})
		ends[tool] = at+DRILL[tool]; at += DRILL[tool]
	at = 0; var polish_rows = []
	for tool in s.polish:
		var start = maxi(at,ends.get(tool,0))
		polish_rows.append({"tool":tool,"start":start,"end":start+POLISH[tool]})
		at = start+POLISH[tool]
	return {"drill":drill_rows,"polish":polish_rows}

static func makespan(s: Dictionary) -> int:
	var rows = timeline(s).polish
	return rows[-1].end if not rows.is_empty() else 0

static func ready(s: Dictionary) -> bool:
	return s.drill.size() == TOOLS and s.polish.size() == TOOLS

static func solved(s: Dictionary) -> bool:
	return ready(s) and makespan(s) <= DEADLINE

# 只说明真实违反的条件：哪条带还没排满，或者这套排法要到第几拍才做完。
static func shortfalls(s: Dictionary) -> Array:
	if not ready(s):
		return ["两条工序带都要排满 3 件才能试运行：现在钻孔带 %d 件、抛光带 %d 件。"%[s.drill.size(),s.polish.size()]]
	if makespan(s) > DEADLINE:
		return ["这套排法到第 %d 拍才全部做完，赶不上第 %d 拍结束。"%[makespan(s),DEADLINE]]
	return []

# 同一件工具在一条带上只能出现一次：点已经排上去的那一件就是把它取下来。
static func place_tool(s: Dictionary, track: int, tool: int) -> Dictionary:
	if s.stage != "puzzle" or track < 0 or track > 1 or tool < 0 or tool >= TOOLS: return {}
	var key = "drill" if track == 0 else "polish"
	if s[key].has(tool) or s[key].size() >= TOOLS: return {}
	var n = s.duplicate(true); n[key].append(tool)
	return n if validate(n) else {}

static func remove_tool(s: Dictionary, track: int, tool: int) -> Dictionary:
	if s.stage != "puzzle" or track < 0 or track > 1 or tool < 0 or tool >= TOOLS: return {}
	var key = "drill" if track == 0 else "polish"
	if not s[key].has(tool): return {}
	var n = s.duplicate(true); n[key].erase(tool)
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("drill") or not snapshot.has("polish"): return {}
	var n = s.duplicate(true); n.drill = snapshot.drill.duplicate(); n.polish = snapshot.polish.duplicate()
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
			if not ready(s): return {}
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
	if v.sample != "workshop-gw05-1" or v.stage not in STAGES: return false
	for key in ["beat","hint","attempts"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.attempts < 0 or v.attempts > 1000000: return false
	if not legal_order(v.drill) or not legal_order(v.polish): return false
	if v.stage in ["arrival","approach","ready"]:
		if not v.drill.is_empty() or not v.polish.is_empty() or v.hint != 0 or v.attempts != 0: return false
	if v.stage in ["approach","ready","puzzle","trial","delivery","complete"] and v.beat != 2: return false
	if v.stage == "trial":
		if not ready(v) or v.attempts < 1: return false
	if v.stage in ["delivery","aftermath","complete"]:
		if not solved(v) or v.attempts < 1: return false
	return true

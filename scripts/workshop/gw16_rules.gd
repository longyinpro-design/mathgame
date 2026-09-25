extends RefCounted
# GW16 屋顶修理街「找全四种午休曲」：午休铃每首恰好 4 段，每段长 2、3 或 4 拍，
# 整首正好 12 拍且恰好两段是 3 拍。曲子循环播放，相邻两段长度不能相同，末段与首段也相邻。
# 固定起拍点；旋转后的段序只要不同就算另一首——合法的段序一共只有 4 首。
# 玩家在铃架上排段、试听、保存互不相同的合法段序；重存同一首不算新的，收齐后任选一首留用。
# 合法段序、试听判定与收集板全部由这里现算，画面不另存判定结果。
const SAMPLE = "workshop-gw16-1"
const SEGMENTS = 4
const LENGTH_MIN = 2
const LENGTH_MAX = 4
const TOTAL_BEATS = 12
const THREES = 2
const TUNES = 4
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","segments","heard","saved","chosen","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"segments":[],
		"heard":false,"saved":[],"chosen":-1,"hint":0}

static func beats(order: Array) -> int:
	var total = 0
	for value in order: total += value
	return total

static func threes(order: Array) -> int:
	var count = 0
	for value in order:
		if value == 3: count += 1
	return count

static func order_text(order: Array) -> String:
	var parts = []
	for value in order: parts.append(str(value))
	return "/".join(parts)

# 完整判定：四段、每段 2～4 拍、合计 12 拍、恰好两个 3，且循环相邻两段都不同（末段与首段也相邻）。
static func legal(order: Variant) -> bool:
	if not order is Array or order.size() != SEGMENTS: return false
	for value in order:
		if not value is int or value < LENGTH_MIN or value > LENGTH_MAX: return false
	if beats(order) != TOTAL_BEATS or threes(order) != THREES: return false
	for index in range(SEGMENTS):
		if order[index] == order[(index+1)%SEGMENTS]: return false
	return true

# 只说明真实违反的条件。循环首尾相邻是这一关的关键，先报；其余按 3 的段数、总拍数、段内相邻依次说。
static func phrase_problems(order: Variant) -> Array:
	if not order is Array or order.size() != SEGMENTS:
		return ["铃架要排满 4 段才能成一首曲子。"]
	for value in order:
		if not value is int or value < LENGTH_MIN or value > LENGTH_MAX:
			return ["每段只能是 2、3 或 4 拍。"]
	var out = []
	if order[0] == order[SEGMENTS-1]:
		out.append("末段和首段都是 %d 拍：曲子循环播放，末段与首段也相邻，不能相同。"%order[0])
	if threes(order) != THREES:
		out.append("3 拍的段有 %d 段：每首恰好要有两段 3 拍。"%threes(order))
	if beats(order) != TOTAL_BEATS:
		out.append("四段合计 %d 拍：每首要正好 %d 拍。"%[beats(order),TOTAL_BEATS])
	for index in range(SEGMENTS-1):
		if order[index] == order[index+1]:
			out.append("第 %d 段和第 %d 段都是 %d 拍：相邻两段不能相同。"%[index+1,index+2,order[index]])
	return out

# 用最笨的办法枚举 3^4 种段序：只有 4 种合法（规则测试另有独立 oracle 对照）。
static func solution() -> Array:
	var out = []
	for a in range(LENGTH_MIN,LENGTH_MAX+1):
		for b in range(LENGTH_MIN,LENGTH_MAX+1):
			for c in range(LENGTH_MIN,LENGTH_MAX+1):
				for d in range(LENGTH_MIN,LENGTH_MAX+1):
					var order = [a,b,c,d]
					if legal(order): out.append(order)
	return out

static func collected(s: Dictionary) -> bool:
	return s.saved.size() == TUNES

# 收齐四首只是收齐；还要任选一首留作章末午休曲才算办完。
static func solved(s: Dictionary) -> bool:
	return collected(s) and s.chosen >= 0 and s.chosen < s.saved.size()

# 只说明真实缺的条件：铃架上这一首自己的毛病、还没保存，或者收集板还差几首、还没留曲。
static func shortfalls(s: Dictionary) -> Array:
	var out = []
	if s.segments.size() == SEGMENTS:
		var problems = phrase_problems(s.segments)
		if not problems.is_empty():
			out.append(problems[0])
		elif not s.saved.has(s.segments):
			out.append("铃架上这首 %s 还没保存：先试听，再按「保存这首」。"%order_text(s.segments))
	if not collected(s):
		out.append("四首还没收齐：已收 %d 首，还差 %d 首。"%[s.saved.size(),TUNES-s.saved.size()])
	elif s.chosen < 0:
		out.append("四首都收齐了：点收集板上的一首，留作章末午休曲。")
	return out

# 往铃架末尾排一段：还没排满 4 段时才能加。
static func put(s: Dictionary, length: int) -> Dictionary:
	if s.stage != "puzzle" or length < LENGTH_MIN or length > LENGTH_MAX: return {}
	if s.segments.size() >= SEGMENTS: return {}
	var n = s.duplicate(true)
	n.segments.append(length); n.heard = false
	return n if validate(n) else {}

# 点铃架上的一段就把它取下来，后面的段跟着前移。
static func take(s: Dictionary, slot: int) -> Dictionary:
	if s.stage != "puzzle" or slot < 0 or slot >= s.segments.size(): return {}
	var n = s.duplicate(true)
	n.segments.remove_at(slot); n.heard = false
	return n if validate(n) else {}

# 试听：整段循环放一遍，之后才允许保存。改段或取段都会清掉这次试听。
static func listen(s: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or s.segments.size() != SEGMENTS: return {}
	var n = s.duplicate(true); n.heard = true
	return n if validate(n) else {}

# 保存这一首：必须排满 4 段、试听过、合法，而且没存过。
static func save_tune(s: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or s.segments.size() != SEGMENTS: return {}
	if not s.heard or not legal(s.segments): return {}
	if s.saved.has(s.segments) or s.saved.size() >= TUNES: return {}
	var n = s.duplicate(true); n.saved.append(n.segments.duplicate())
	return n if validate(n) else {}

# 为什么这一首存不下：先说不合法在哪，再说没试听，最后说重存或已经收齐。
static func save_reason(s: Dictionary) -> String:
	if s.segments.size() != SEGMENTS:
		return "铃架还差 %d 段才能保存：每首正好 4 段。"%(SEGMENTS-s.segments.size())
	var problems = phrase_problems(s.segments)
	if not problems.is_empty(): return problems[0]
	if not s.heard: return "先按「试听」听一遍这段循环，再保存。"
	if s.saved.has(s.segments): return "这首 %s 已经在收集板上了：重存同一首不算新的一首。"%order_text(s.segments)
	if s.saved.size() >= TUNES: return "四首都收齐了，不用再保存。"
	return ""

# 收齐四首后任选一首留作章末午休曲。
static func choose(s: Dictionary, index: int) -> Dictionary:
	if s.stage != "puzzle" or not collected(s) or index < 0 or index >= s.saved.size(): return {}
	var n = s.duplicate(true); n.chosen = index
	return n if validate(n) else {}

# 键盘换一首：还没选过时先落在头一首（往前）或末一首（往后）。
static func cycle_chosen(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle" or not collected(s) or delta == 0: return {}
	var index = s.chosen
	if index < 0: index = 0 if delta > 0 else s.saved.size()-1
	else: index = clampi(index+delta,0,s.saved.size()-1)
	if index == s.chosen: return {}
	var n = s.duplicate(true); n.chosen = index
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("segments") or not snapshot.has("heard") \
		or not snapshot.has("saved") or not snapshot.has("chosen"): return {}
	var n = s.duplicate(true)
	n.segments = snapshot.segments.duplicate()
	n.heard = snapshot.heard
	n.saved = snapshot.saved.duplicate(true)
	n.chosen = snapshot.chosen
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

# 铃架上的段序：最多 4 段、每段 2～4 拍；非法组合可以留在架上慢慢改。
static func legal_segments(value: Variant) -> bool:
	if not value is Array or value.size() > SEGMENTS: return false
	for length in value:
		if not length is int or length < LENGTH_MIN or length > LENGTH_MAX: return false
	return true

# 收集板：最多 4 首、每首都必须合法，而且两两不同——重复的记录算坏档。
static func legal_saved(value: Variant) -> bool:
	if not value is Array or value.size() > TUNES: return false
	var seen = []
	for order in value:
		if not legal(order): return false
		for other in seen:
			if other == order: return false
		seen.append(order)
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","chosen","hint"]:
		if not v[key] is int: return false
	if not v.heard is bool: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if not legal_segments(v.segments) or not legal_saved(v.saved): return false
	if v.heard and v.segments.size() != SEGMENTS: return false
	if v.chosen < -1 or v.chosen >= v.saved.size(): return false
	if v.chosen >= 0 and v.saved.size() != TUNES: return false
	if v.stage in ["arrival","approach","ready"]:
		if not v.segments.is_empty() or v.heard or not v.saved.is_empty() or v.chosen != -1 or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

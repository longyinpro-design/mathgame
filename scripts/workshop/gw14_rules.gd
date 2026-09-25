extends RefCounted
# GW14 装配间「第三张记录才有用」：维修盒里有 20～80 枚标准件，
# 三张复测记录都来自同一盒、不取走物件：按 4 一托剩 3 枚、按 6 一托剩 5 枚、按 5 一托剩 2 枚。
# 前两张只留下 23、35、47、59、71 五个共同候选，第三张才把其余四个排除，只剩 47。
# 候选、三种托的复演与排除表全部由这里现算；画面不另存除法结果，换候选不会留下旧判定。
const SAMPLE = "workshop-gw14-1"
const BOX_MIN = 20
const BOX_MAX = 80
const TRAYS = [4,6,5]
const REMAINDERS = [3,5,2]
const RECORD_NAMES = ["记录一","记录二","记录三"]
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","count","listed","tested_first","tested_second","tested_third","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"count":0,"listed":[],
		"tested_first":[],"tested_second":[],"tested_third":[],"hint":0}

# 一次除法就够：满托数与零散数。余数天然小于托的枚数（4、6、5 都是正整数）。
static func division(count: int, tray: int) -> Array:
	return [count/tray,count%tray]

# 一张记录是否认这个枚数：余数正好等于记录写下的零散数。
# 三条记录的零散数本来就小于托的枚数（3<4、5<6、2<5），所以「余数必须比托小」自动成立，
# 这里仍然显式检查一遍：记录本身不合规就永远不认任何枚数。
static func matches(record: int, count: int) -> bool:
	if record < 0 or record > 2: return false
	if count < BOX_MIN or count > BOX_MAX: return false
	if REMAINDERS[record] >= TRAYS[record]: return false
	return count % TRAYS[record] == REMAINDERS[record]

# 一张记录在 20～80 里说得通的全部枚数。边界也是候选的一部分：
# 3、7、11、15、19 虽然同余，盒里却装不下，不能算候选。
static func candidates(record: int) -> Array:
	var out = []
	if record < 0 or record > 2: return out
	for count in range(BOX_MIN,BOX_MAX+1):
		if matches(record,count): out.append(count)
	return out

# 三张记录都认的枚数：本题只有 47，规则仍然按枚举算。
static func solution() -> Array:
	var out = []
	for count in range(BOX_MIN,BOX_MAX+1):
		var ok = true
		for record in range(3):
			if not matches(record,count): ok = false; break
		if ok: out.append(count)
	return out

static func tested(s: Dictionary, record: int) -> Array:
	if record == 0: return s.tested_first
	if record == 1: return s.tested_second
	return s.tested_third

# 画面与状态栏共用的一句判定：未提出 / 未复演 / 相符 / 不符。
static func mark(s: Dictionary, record: int) -> String:
	if s.count < BOX_MIN or s.count > BOX_MAX: return "未提出"
	if not tested(s,record).has(s.count): return "未复演"
	return "相符" if matches(record,s.count) else "不符"

# 排除表里任意一个候选在某张记录下的判定。
static func verdict(s: Dictionary, record: int, count: int) -> String:
	if not tested(s,record).has(count): return "未复演"
	return "相符" if matches(record,count) else "不符"

# 试过的候选：三张复演表合起来，从小到大、不重复。
static func tried_counts(s: Dictionary) -> Array:
	var seen = {}
	for record in range(3):
		for count in tested(s,record): seen[count] = true
	var out = seen.keys(); out.sort()
	return out

# 一个候选在整张排除表里的状态：任一记录不符就是被排除，三条都相符才算定下。
static func chip_state(s: Dictionary, count: int) -> String:
	var done = 0
	for record in range(3):
		if tested(s,record).has(count):
			if not matches(record,count): return "排除"
			done += 1
	return "定下" if done == 3 else ("部分" if done > 0 else "未试")

# 三张记录都真的复演过、而且都对得上，才算找到盒中枚数。
# 只满足两条不能验收：第三张没复演过就还差一条，复演过但对不上就还有一条不符。
static func solved(s: Dictionary) -> bool:
	if s.count < BOX_MIN or s.count > BOX_MAX: return false
	for record in range(3):
		if not tested(s,record).has(s.count): return false
		if not matches(record,s.count): return false
	return true

# 只说明真实违反的条件：还没提出枚数、哪张记录没复演、复演出来的余数是多少。
static func shortfalls(s: Dictionary) -> Array:
	if s.count < BOX_MIN or s.count > BOX_MAX:
		return ["先从 20～80 里提出一个候选枚数：三张记录都是同一盒的复测。"]
	var out = []
	for record in range(3):
		if not tested(s,record).has(s.count):
			out.append("%s还没复演过：按 %d 一托跑一遍 %d 枚，看满托之外剩几枚。"%[RECORD_NAMES[record],TRAYS[record],s.count])
		elif not matches(record,s.count):
			var parts = division(s.count,TRAYS[record])
			out.append("%d 枚按 %d 一托：%d 个满托、剩 %d 枚；%s写的是剩 %d 枚。"%[s.count,TRAYS[record],parts[0],parts[1],RECORD_NAMES[record],REMAINDERS[record]])
	return out

# 列候选：把一张记录在 20～80 里说得通的枚数摆上台面。列过的记录不会重复列。
static func list(s: Dictionary, record: int) -> Dictionary:
	if s.stage != "puzzle" or record < 0 or record > 2 or s.listed.has(record): return {}
	var n = s.duplicate(true); n.listed.append(record); n.listed.sort()
	return n if validate(n) else {}

static func select(s: Dictionary, count: int) -> Dictionary:
	if s.stage != "puzzle" or count < BOX_MIN or count > BOX_MAX or count == s.count: return {}
	var n = s.duplicate(true); n.count = count
	return n if validate(n) else {}

# 还没提出枚数时，左右一步先落在 20 枚上；之后在 20～80 之间移动。
static func move_count(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle": return {}
	var current = s.count if s.count >= BOX_MIN else BOX_MIN-1
	var count = clampi(current+delta,BOX_MIN,BOX_MAX)
	if count == s.count: return {}
	var n = s.duplicate(true); n.count = count
	return n if validate(n) else {}

# 复演一张记录：把当前候选记进这张记录的重演表，重复复演不会留下第二条。
static func replay(s: Dictionary, record: int) -> Dictionary:
	if s.stage != "puzzle" or record < 0 or record > 2 or s.count < BOX_MIN: return {}
	var n = s.duplicate(true)
	var rows = tested(n,record)
	if not rows.has(n.count):
		rows.append(n.count); rows.sort()
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("count") or not snapshot.has("listed") \
		or not snapshot.has("tested_first") or not snapshot.has("tested_second") \
		or not snapshot.has("tested_third"): return {}
	var n = s.duplicate(true)
	n.count = snapshot.count
	n.listed = snapshot.listed.duplicate()
	n.tested_first = snapshot.tested_first.duplicate()
	n.tested_second = snapshot.tested_second.duplicate()
	n.tested_third = snapshot.tested_third.duplicate()
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

# 试过的候选：从小到大、不重复；越界或重复都算损坏。
static func legal_tested(value: Variant) -> bool:
	if not value is Array or value.size() > BOX_MAX-BOX_MIN+1: return false
	var last = 0
	for count in value:
		if not count is int or count < BOX_MIN or count > BOX_MAX: return false
		if count <= last: return false
		last = count
	return true

# 已列出的记录：0～2、从小到大、不重复。
static func legal_listed(value: Variant) -> bool:
	if not value is Array or value.size() > 3: return false
	var last = -1
	for record in value:
		if not record is int or record < 0 or record > 2: return false
		if record <= last: return false
		last = record
	return true

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","count","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.count != 0 and (v.count < BOX_MIN or v.count > BOX_MAX): return false
	if not legal_listed(v.listed): return false
	if not legal_tested(v.tested_first) or not legal_tested(v.tested_second) or not legal_tested(v.tested_third): return false
	# 没有提出枚数就没有复演记录：复演表只能来自玩家按下过的复演。
	if v.count == 0 and not (v.tested_first.is_empty() and v.tested_second.is_empty() and v.tested_third.is_empty()): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.count != 0 or not v.listed.is_empty() or v.hint != 0 \
			or not v.tested_first.is_empty() or not v.tested_second.is_empty() or not v.tested_third.is_empty(): return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

extends RefCounted
# GW11 装卸码头「两张船票，倒排到同一张台」：A、B 两批材料都在第 6 拍到，
# 每批三道工序（装配、冷却、装船）首尾相接，中间不能等待。
# A 的船票钉死在第 12 拍开船；B 的船票要在第 13、14 拍里先选定一班。
# 装配台一次一批、冷却架可容两批、吊机一次一批：单批排得再顺，
# 两批合到同一张台上也可能撞车，所以判定必须两批一起看。
# 时刻表、船票比对与三条共用带全部由这里现算，画面不另存会走样的表。
const SAMPLE = "workshop-gw11-1"
const BATCHES = ["A","B"]
const COUNT = 2
const STAGE_NAMES = ["装配","冷却","装船"]
const KEYS = ["assembly","cool","load"]
const ASSEMBLY_TIME = [2,3]
const COOL_TIME = [3,2]
const LOAD_TIME = 1
const ARRIVAL_BEAT = 6
const A_LOAD = 12
const TICKETS = [13,14]
const HORIZON = 16
const RANGE_MAX = 15
const DEFAULT_ASSEMBLY = [6,6]
const DEFAULT_COOL = [8,9]
const DEFAULT_LOAD = [11,11]
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","ticket","assembly","cool","load","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"ticket":0,
		"assembly":DEFAULT_ASSEMBLY.duplicate(),"cool":DEFAULT_COOL.duplicate(),
		"load":DEFAULT_LOAD.duplicate(),"hint":0}

static func legal_starts(value: Variant) -> bool:
	if not value is Array or value.size() != COUNT: return false
	for start in value:
		if not start is int or start < 0 or start > RANGE_MAX: return false
	return true

static func duration(batch: int, row: int) -> int:
	if row == 0: return ASSEMBLY_TIME[batch]
	if row == 1: return COOL_TIME[batch]
	return LOAD_TIME

# 六个开工拍：0/1/2 是 A 批的装配、冷却、装船，3/4/5 是 B 批的同一道工序。
static func start_of(s: Dictionary, batch: int, row: int) -> int:
	if row == 0: return s.assembly[batch]
	if row == 1: return s.cool[batch]
	return s.load[batch]

# 一道工序占 [开工, 完工)：持续 d 拍、从 s 开始就占 s～s+d。
static func interval(s: Dictionary, batch: int, row: int) -> Array:
	var start = start_of(s,batch,row)
	return [start,start+duration(batch,row)]

# 第 tick 拍上，第 row 条共用带被哪几批占着：0=装配台 1=冷却架 2=吊机。
static func holders(s: Dictionary, row: int, tick: int) -> Array:
	var out = []
	for batch in range(COUNT):
		var span = interval(s,batch,row)
		if span[0] <= tick and tick < span[1]: out.append(batch)
	return out

# 一次一批的带子上第一批撞车的时刻与重叠区间；冷却架可容两批，不走这里。
static func clash(s: Dictionary, row: int) -> Dictionary:
	for tick in range(HORIZON):
		var held = holders(s,row,tick)
		if held.size() < 2: continue
		var first = held[0]; var second = held[1]
		var from = maxi(start_of(s,first,row),start_of(s,second,row))
		var to = mini(start_of(s,first,row)+duration(first,row),start_of(s,second,row)+duration(second,row))
		return {"row":row,"first":first,"second":second,"from":from,"to":to}
	return {}

# 只说明真实违反的条件：先选票、再到料、首尾相接、各自船票，最后才是三条共用带。
static func problems(s: Dictionary) -> Array:
	var out = []
	if not TICKETS.has(s.ticket):
		out.append("先在两张船票里选一班：B 走第 %d 拍或第 %d 拍开船，选定后再倒着排。"%[TICKETS[0],TICKETS[1]])
	for batch in range(COUNT):
		for row in range(3):
			var start = start_of(s,batch,row)
			if start < ARRIVAL_BEAT:
				out.append("%s 批的%s排在第 %d 拍开工，可两批材料第 %d 拍才送到。"%[BATCHES[batch],STAGE_NAMES[row],start,ARRIVAL_BEAT])
		if s.cool[batch] != s.assembly[batch]+ASSEMBLY_TIME[batch]:
			out.append("%s 批的冷却排在第 %d 拍开工，可 %s 批到第 %d 拍才装配完——三段要首尾相接。"%[BATCHES[batch],s.cool[batch],BATCHES[batch],s.assembly[batch]+ASSEMBLY_TIME[batch]])
		if s.load[batch] != s.cool[batch]+COOL_TIME[batch]:
			out.append("%s 批的装船排在第 %d 拍开工，可 %s 批到第 %d 拍才冷却完——三段要首尾相接。"%[BATCHES[batch],s.load[batch],BATCHES[batch],s.cool[batch]+COOL_TIME[batch]])
	if s.load[0] != A_LOAD:
		out.append("A 只能第 %d 拍开始装船：现在 A 批的装船排在第 %d 拍。"%[A_LOAD,s.load[0]])
	if TICKETS.has(s.ticket) and s.load[1] != s.ticket:
		out.append("B 的船票写的是第 %d 拍开船：现在 B 批的装船排在第 %d 拍。"%[s.ticket,s.load[1]])
	var table = clash(s,0)
	if not table.is_empty():
		out.append("装配台一次只装一批：%s 批占着第 %d～%d 拍、%s 批占着第 %d～%d 拍，第 %d～%d 拍重叠。"%[
			BATCHES[table.first],start_of(s,table.first,0),start_of(s,table.first,0)+duration(table.first,0),
			BATCHES[table.second],start_of(s,table.second,0),start_of(s,table.second,0)+duration(table.second,0),
			table.from,table.to])
	var crane = clash(s,2)
	if not crane.is_empty():
		out.append("吊机一次只吊一批：%s 批占着第 %d～%d 拍、%s 批占着第 %d～%d 拍，第 %d～%d 拍重叠。"%[
			BATCHES[crane.first],start_of(s,crane.first,2),start_of(s,crane.first,2)+duration(crane.first,2),
			BATCHES[crane.second],start_of(s,crane.second,2),start_of(s,crane.second,2)+duration(crane.second,2),
			crane.from,crane.to])
	for tick in range(HORIZON):
		var cooling = holders(s,1,tick)
		if cooling.size() > 2:
			out.append("冷却架最多同时放两批：第 %d 拍上有 %d 批在冷却。"%[tick,cooling.size()])
			break
	for batch in range(COUNT):
		for row in range(3):
			var finish = start_of(s,batch,row)+duration(batch,row)
			if finish > HORIZON:
				out.append("%s 批的%s排到第 %d 拍，超出了第 0～%d 拍的台面。"%[BATCHES[batch],STAGE_NAMES[row],finish,HORIZON-1])
	return out

static func solved(s: Dictionary) -> bool: return problems(s).is_empty()
static func shortfalls(s: Dictionary) -> Array: return problems(s)

# 选 B 的船票：第 13 拍或第 14 拍，选定一班才能往下排。
static func choose_ticket(s: Dictionary, ticket: int) -> Dictionary:
	if s.stage != "puzzle" or not TICKETS.has(ticket) or s.ticket == ticket: return {}
	var n = s.duplicate(true); n.ticket = ticket
	return n if validate(n) else {}

# 改一格开工拍：六个开工拍各自独立，三段是不是首尾相接由 problems() 现算。
static func set_start(s: Dictionary, batch: int, row: int, value: int) -> Dictionary:
	if s.stage != "puzzle" or batch < 0 or batch >= COUNT or row < 0 or row > 2: return {}
	if value < 0 or value > RANGE_MAX: return {}
	var n = s.duplicate(true)
	var key = KEYS[row]
	if n[key][batch] == value: return {}
	n[key][batch] = value
	return n if validate(n) else {}

static func step_start(s: Dictionary, batch: int, row: int, delta: int) -> Dictionary:
	if s.stage != "puzzle" or batch < 0 or batch >= COUNT or row < 0 or row > 2: return {}
	var current = start_of(s,batch,row)
	var value = clampi(current+delta,0,RANGE_MAX)
	if value == current: return {}
	return set_start(s,batch,row,value)

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle": return {}
	for key in ["ticket","assembly","cool","load"]:
		if not snapshot.has(key): return {}
	if not snapshot.ticket is int or not snapshot.assembly is Array \
			or not snapshot.cool is Array or not snapshot.load is Array: return {}
	var n = s.duplicate(true)
	n.ticket = snapshot.ticket
	n.assembly = snapshot.assembly.duplicate()
	n.cool = snapshot.cool.duplicate()
	n.load = snapshot.load.duplicate()
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

static func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != FIELDS.size() or not v.has_all(FIELDS): return false
	if v.sample != SAMPLE or v.stage not in STAGES: return false
	for key in ["beat","ticket","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.ticket != 0 and not TICKETS.has(v.ticket): return false
	if not legal_starts(v.assembly) or not legal_starts(v.cool) or not legal_starts(v.load): return false
	if v.stage in ["arrival","approach","ready"]:
		if v.ticket != 0 or v.assembly != DEFAULT_ASSEMBLY or v.cool != DEFAULT_COOL or v.load != DEFAULT_LOAD: return false
		if v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

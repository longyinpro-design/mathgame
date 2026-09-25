extends RefCounted
# GW09 旧报时廊「既不漏灯，也不错站」：环上 12 盏灯编号 0～11，从 0 出发，
# 每次固定走 2～8 格，顺时针且途中不改步长。第一次回到 0 之前要停遍 1～11 每一盏；
# 旧报时记录还写着「第 3 次跳动后停在 9 号灯」。只跨过而未停下的灯不算访问。
# 走满一圈要几跳、第 3 站落在哪、停站记录与判定全部由这里现算；
# 画面不另存轨迹，换步长不会留下旧判定。
const SAMPLE = "workshop-gw09-1"
const LAMPS = 12
const STEP_MIN = 2
const STEP_MAX = 8
const RECORD_JUMP = 3
const RECORD_STOP = 9
const STAGES = ["arrival","approach","ready","puzzle","delivery","aftermath","complete"]
const ANIMATIONS = ["approach","delivery"]
const FIELDS = ["sample","stage","beat","step","third","jumps","visited","hint"]

static func fresh() -> Dictionary:
	return {"sample":SAMPLE,"stage":"arrival","beat":0,"step":0,"third":-1,"jumps":0,"visited":[],"hint":0}

# 回到 0 要跳几次：12 与步长的最大公约数。GDScript 没有 gcd，自己辗转相除。
static func gcd(a: int, b: int) -> int:
	while b != 0:
		var next = a % b
		a = b
		b = next
	return a

static func cycle(step: int) -> int:
	if step < STEP_MIN or step > STEP_MAX: return 0
	return LAMPS/gcd(step,LAMPS)

# 第 3 次跳动落在哪一盏：步长 4、8 时那一跳正好回到 0。
static func third_stop(step: int) -> int:
	return (RECORD_JUMP*step) % LAMPS

# 回 0 前能停遍每一盏的步长：要走满 12 跳才回到 0。
static func covers(step: int) -> bool:
	return step >= STEP_MIN and step <= STEP_MAX and cycle(step) == LAMPS

# 完整轨迹：起点、每次停下的灯、最后回到 0。规则现算，画面与测试都拿它对照。
static func track(step: int) -> Array:
	var out = [0]
	if step < STEP_MIN or step > STEP_MAX: return out
	var cursor = 0
	for i in range(cycle(step)):
		cursor = (cursor+step) % LAMPS
		out.append(cursor)
	return out

static func returned(s: Dictionary) -> bool:
	return s.step >= STEP_MIN and s.step <= STEP_MAX and s.jumps > 0 and (s.jumps*s.step) % LAMPS == 0

static func cursor(s: Dictionary) -> int:
	return (s.jumps*s.step) % LAMPS if s.step >= STEP_MIN else 0

static func covered(s: Dictionary) -> bool:
	return returned(s) and s.jumps == LAMPS

# 两条同时成立才算过：回 0 前停遍每一盏，且第 3 站正是旧记录写的 9 号灯。
static func solved(s: Dictionary) -> bool:
	return covered(s) and s.third == RECORD_STOP and third_stop(s.step) == RECORD_STOP

# 只说最要紧的一处真实违反：还没设步长、这一圈跑到哪、回 0 时漏了几盏、预测与第 3 站。
static func shortfalls(s: Dictionary) -> Array:
	if s.stage != "puzzle": return []
	if s.step < STEP_MIN:
		return ["先设一个步长：每次固定走 2～8 格，途中不能改。"]
	if not returned(s):
		return ["这一圈还没跑完：已经跳了 %d 次，现在停在 %d 号灯。"%[s.jumps,cursor(s)]]
	if s.jumps < LAMPS:
		return ["第 %d 次跳动就回到了 0 号灯，只停过 %d 盏；回 0 前要停遍 1～11 每一盏。"%[s.jumps,s.visited.size()]]
	if s.third < 0:
		return ["先预测第 3 次跳动会停在哪一盏：在环上点一盏灯。"]
	if s.third != RECORD_STOP:
		return ["你预测第 3 站是 %d 号灯；旧报时记录写的是 %d 号灯。"%[s.third,RECORD_STOP]]
	if third_stop(s.step) != RECORD_STOP:
		return ["这一圈第 3 站实际停在 %d 号灯，不是 %d 号灯。"%[third_stop(s.step),RECORD_STOP]]
	return []

# 换步长会清空这一圈；换到别的步长时，原来的第 3 站预测也不再作数。
# 点回同一个步长等于重跑：停站清空，预测保留。
static func choose_step(s: Dictionary, step: int) -> Dictionary:
	if s.stage != "puzzle" or step < STEP_MIN or step > STEP_MAX: return {}
	if s.step == step and s.jumps == 0: return {}
	var n = s.duplicate(true)
	if step != s.step: n.third = -1
	n.step = step; n.jumps = 0; n.visited = []
	return n if validate(n) else {}

static func move_step(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle": return {}
	var current = s.step if s.step >= STEP_MIN else STEP_MIN-1
	var step = clampi(current+delta,STEP_MIN,STEP_MAX)
	if step == s.step: return {}
	return choose_step(s,step)

# 预测只能写在第 3 次跳动落地之前：跑过第 3 站之后要重跑这一圈才能改口。
static func predict(s: Dictionary, lamp: int) -> Dictionary:
	if s.stage != "puzzle" or s.step < STEP_MIN: return {}
	if lamp < 0 or lamp >= LAMPS or lamp == s.third: return {}
	if s.jumps >= RECORD_JUMP: return {}
	var n = s.duplicate(true); n.third = lamp
	return n if validate(n) else {}

static func move_predict(s: Dictionary, delta: int) -> Dictionary:
	if s.stage != "puzzle" or s.step < STEP_MIN: return {}
	var current = s.third if s.third >= 0 else -1
	var lamp = clampi(current+delta,0,LAMPS-1)
	if lamp == s.third: return {}
	return predict(s,lamp)

# 跳一格：落在 0 就是这一圈跑完，0 不进停站记录；其他落点按顺序记下来。
static func jump(s: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or s.step < STEP_MIN or returned(s): return {}
	var n = s.duplicate(true)
	n.jumps += 1
	var landing = (n.jumps*n.step) % LAMPS
	if landing != 0: n.visited.append(landing)
	return n if validate(n) else {}

static func restore(s: Dictionary, snapshot: Dictionary) -> Dictionary:
	if s.stage != "puzzle" or not snapshot.has("step") or not snapshot.has("third") \
		or not snapshot.has("jumps") or not snapshot.has("visited"): return {}
	var n = s.duplicate(true)
	n.step = snapshot.step; n.third = snapshot.third
	n.jumps = snapshot.jumps; n.visited = snapshot.visited.duplicate()
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
	for key in ["beat","step","third","jumps","hint"]:
		if not v[key] is int: return false
	if v.beat < 0 or v.beat > 2 or v.hint < 0 or v.hint > 4: return false
	if v.step != 0 and (v.step < STEP_MIN or v.step > STEP_MAX): return false
	if v.third < -1 or v.third >= LAMPS: return false
	if v.jumps < 0 or v.jumps > LAMPS: return false
	if not v.visited is Array: return false
	if v.step == 0:
		if v.third != -1 or v.jumps != 0 or not v.visited.is_empty(): return false
	else:
		if v.jumps > cycle(v.step): return false
		# 停站必须正好是这一圈的前几跳：回 0 的那一跳不进记录。
		var stops = v.jumps - (1 if returned(v) else 0)
		if v.visited.size() != stops: return false
		for i in range(stops):
			if not v.visited[i] is int: return false
			if v.visited[i] != ((i+1)*v.step) % LAMPS: return false
	if v.stage in ["arrival","approach","ready"]:
		if v.step != 0 or v.third != -1 or v.jumps != 0 or not v.visited.is_empty() or v.hint != 0: return false
	if v.stage in ["approach","ready","puzzle","delivery","complete"] and v.beat != 2: return false
	if v.stage in ["delivery","aftermath","complete"] and not solved(v): return false
	return true

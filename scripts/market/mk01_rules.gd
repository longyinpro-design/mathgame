extends RefCounted

# Ground truth is used only by the sealed measuring chamber and validation.
const CAPACITIES = [6,6,4,4,4,1,1,1]
const TARGET = 11
const STAGES = ["arrival","approach","ready","puzzle","measuring","result","deduction","delivery","complete"]
const ANIMATIONS = ["approach","measuring","delivery"]

static func fresh() -> Dictionary:
	return {"sample":"market-mk01-2","stage":"arrival","beat":0,"slots":[-1,-1,-1],"hint":0,"observations":[],"guesses":[0,0],"calibrated":false}

static func valid_slots(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	var seen = []
	for id in value:
		if not id is int or id < -1 or id >= CAPACITIES.size(): return false
		if id >= 0:
			if id in seen: return false
			seen.append(id)
	return true

static func volume(slots: Array) -> int:
	var total = 0
	for id in slots:
		if id >= 0: total += CAPACITIES[id]
	return total

static func count(slots: Array) -> int:
	return 3-slots.count(-1)

static func composition(slots: Array) -> Array:
	var counts = [0,0,0]
	for id in slots:
		if id >= 0: counts[0 if id < 2 else (1 if id < 5 else 2)] += 1
	return counts

static func solved(slots: Array) -> bool:
	return count(slots) == 3 and volume(slots) == TARGET

static func candidates(observations: Array) -> Array:
	var possible = []
	for blue in range(2,9):
		for white in range(2,9):
			var fits = true
			for record in observations:
				if record.counts[0]*blue+record.counts[1]*white != record.total: fits = false
			if fits: possible.append([blue,white])
	return possible

static func knowledge_ready(state: Dictionary) -> bool:
	return candidates(state.observations).size() == 1

static func delivered(state: Dictionary) -> bool:
	return state.calibrated and solved(state.slots)

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk01-2" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > 2: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > 3: return false
	if not valid_slots(value.get("slots")) or not value.get("calibrated") is bool: return false
	if not value.get("guesses") is Array or value.guesses.size() != 2: return false
	for guess in value.guesses:
		if not guess is int or (guess != 0 and (guess < 2 or guess > 8)): return false
	if not value.get("observations") is Array or value.observations.size() > 2: return false
	var forms = []
	for record in value.observations:
		if not record is Dictionary or not record.get("counts") is Array: return false
		if record.counts not in [[2,1,0],[1,2,0]] or record.counts in forms: return false
		for amount in record.counts:
			if not amount is int: return false
		if not record.get("total") is int or record.total != record.counts[0]*6+record.counts[1]*4: return false
		forms.append(record.counts)
	if value.stage in ["arrival","approach","ready"]:
		if count(value.slots) != 0 or not value.observations.is_empty() or value.guesses != [0,0] or value.calibrated: return false
	if value.calibrated and (not knowledge_ready(value) or value.guesses != [6,4]): return false
	if value.calibrated and value.stage in ["measuring","result"] and count(value.slots) != 3: return false
	if not value.calibrated:
		if value.stage == "puzzle" and knowledge_ready(value): return false
		if value.stage == "measuring" and not measurement_error(value).is_empty(): return false
		if value.stage == "result":
			if value.observations.is_empty() or value.observations.back().counts != composition(value.slots): return false
		if value.stage == "deduction" and not knowledge_ready(value): return false
	if value.stage == "deduction" and value.calibrated: return false
	if value.stage in ["delivery","complete"] and not delivered(value): return false
	return true

static func measurement_error(state: Dictionary) -> String:
	if state.calibrated: return "" if count(state.slots) == 3 else "交货需要恰好三只满杯。"
	var form = composition(state.slots)
	if form not in [[2,1,0],[1,2,0]]:
		return "复核盘要放 3 只满杯，蓝白两家都要有；小杯留作交货用。"
	for record in state.observations:
		if record.counts == form: return "这种装法已经测过，回执还挂在左边。换一种蓝白组合再测。"
	return ""

static func place(state: Dictionary, cup: int, slot: int) -> Dictionary:
	if state.stage != "puzzle" or cup < 0 or cup >= 8 or slot < 0 or slot >= 3: return {}
	var next = state.duplicate(true)
	var old = next.slots.find(cup)
	if old == slot: return {}
	if old >= 0: next.slots[old] = -1
	next.slots[slot] = cup
	return next

static func remove(state: Dictionary, slot: int) -> Dictionary:
	if state.stage != "puzzle" or slot < 0 or slot >= 3 or state.slots[slot] < 0: return {}
	var next = state.duplicate(true); next.slots[slot] = -1
	return next

static func set_guess(state: Dictionary, kind: int, value: int) -> Dictionary:
	if state.stage != "deduction" or kind not in [0,1] or value < 2 or value > 8: return {}
	var next = state.duplicate(true); next.guesses[kind] = value
	return next

static func confirm_capacity(state: Dictionary) -> Dictionary:
	if state.stage != "deduction" or not knowledge_ready(state) or state.guesses != [6,4]: return {}
	var next = state.duplicate(true)
	next.calibrated = true; next.stage = "puzzle"; next.slots = [-1,-1,-1]; next.hint = 0
	return next

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < 2: next.beat += 1
			else: next.stage = "approach"
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not measurement_error(state).is_empty(): return {}
			next.stage = "measuring"
		"measuring":
			if not state.calibrated:
				next.observations.append({"counts":composition(state.slots),"total":volume(state.slots)})
			next.stage = "result"
		"result":
			if state.calibrated: next.stage = "delivery" if delivered(state) else "puzzle"
			else: next.stage = "deduction" if knowledge_ready(state) else "puzzle"
		"delivery": next.stage = "complete"
		_: return {}
	return next

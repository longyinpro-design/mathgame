extends RefCounted
const OLD = preload("res://scripts/puzzle.gd")

static func fresh() -> Dictionary:
	return {"stage":0,"intro":false,"clues":[],"slots":[0,0,0,0,0,0],"origin":[],"swaps":[],"hints":[0,0],"attempts":[0,0],"x":170}

static func targets(s: Dictionary) -> Array:
	if s.stage == 0: return [10,10,10]
	var a = s.origin.duplicate()
	var n = a[0]; a[0] = a[1]; a[1] = n
	n = a[3]; a[3] = a[5]; a[5] = n
	return edge_sums(a)

static func powered(s: Dictionary) -> bool:
	return not s.slots.has(0) and edge_sums(s.slots) == targets(s)

static func unlocked(s: Dictionary) -> bool:
	return s.clues.has("stele") and s.clues.has("keeper") and s.clues.has("bridge")

static func whole(n: Variant, lo: int, hi: int) -> bool:
	return (n is int or n is float) and is_finite(n) and n == int(n) and n >= lo and n <= hi

static func stones(a: Variant, full: bool = false) -> bool:
	if not a is Array or a.size() != 6: return false
	var used = []
	for n in a:
		if not whole(n,1 if full else 0,6) or (n != 0 and used.has(n)): return false
		if n != 0: used.append(n)
	return true

static func valid(s: Variant) -> bool:
	if not s is Dictionary or not s.has_all(["stage","intro","clues","slots","origin","swaps","hints","attempts","x"]): return false
	if not whole(s.stage,0,3) or not s.intro is bool or not whole(s.x,90,1150): return false
	if not s.clues is Array or s.clues.size() > 3: return false
	var seen = []
	for clue in s.clues:
		if clue not in ["stele","keeper","bridge"] or seen.has(clue): return false
		seen.append(clue)
	for key in ["hints","attempts"]:
		if not s[key] is Array or s[key].size() != 2: return false
		for n in s[key]:
			if not whole(n,0,3 if key == "hints" else 1000000): return false
	if not stones(s.slots) or not s.origin is Array or not s.swaps is Array: return false
	if s.stage == 0: return s.origin.is_empty() and s.swaps.is_empty() and s.x <= 700
	if not unlocked(s) or not stones(s.origin,true) or edge_sums(s.origin) != [10,10,10]: return false
	if s.swaps.size() > 2: return false
	var replay = s.origin.duplicate()
	for pair in s.swaps:
		if not pair is Array or pair.size() != 2 or not whole(pair[0],0,5) or not whole(pair[1],0,5) or pair[0] == pair[1]: return false
		var a = int(pair[0]); var b = int(pair[1]); var n = replay[a]
		replay[a] = replay[b]; replay[b] = n
	if replay != s.slots: return false
	if s.stage == 1 and s.x > 700: return false
	return s.stage < 2 or powered(s)

static func normalize(s: Dictionary) -> Dictionary:
	for key in ["stage","x"]: s[key] = int(s[key])
	for key in ["slots","origin","hints","attempts"]:
		for i in range(s[key].size()): s[key][i] = int(s[key][i])
	for pair in s.swaps:
		pair[0] = int(pair[0]); pair[1] = int(pair[1])
	return s

static func edge_sums(a: Array) -> Array:
	var totals = OLD.sums(a)
	return [int(totals[0]),int(totals[1]),int(totals[2])]

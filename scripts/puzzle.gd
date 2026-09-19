extends RefCounted

static func fresh(id: String) -> Dictionary:
	return {"id": id, "slots": [0,0,0,0,0,0], "input": 0, "reverse": [], "ran": false, "hint": 0}

static func sums(slots: Array) -> Array:
	return [slots[0]+slots[1]+slots[2], slots[2]+slots[3]+slots[4], slots[4]+slots[5]+slots[0]]

static func forward(value: int) -> Array:
	return [value, value+5, (value+5)*2, (value+5)*2-4]

static func solved(s: Dictionary) -> bool:
	if s.id == "F12":
		return not s.slots.has(0) and sums(s.slots) == [10,10,10]
	return s.reverse == ["add4", "div2", "sub5"] and s.input == 6 and s.ran

static func valid(s: Variant) -> bool:
	if not s is Dictionary or not s.has_all(["id","slots","input","reverse","ran","hint"]):
		return false
	if s.id not in ["F12","F07"] or not s.slots is Array or s.slots.size() != 6:
		return false
	var used: Array = []
	for n in s.slots:
		if not n is float and not n is int: return false
		if n != int(n) or n < 0 or n > 6 or (n != 0 and used.has(n)): return false
		if n != 0: used.append(n)
	if not s.input is float and not s.input is int: return false
	if s.input != int(s.input) or s.input < 0 or s.input > 20: return false
	if not s.hint is float and not s.hint is int: return false
	if s.hint != int(s.hint) or s.hint < 0 or s.hint > 3: return false
	if not s.ran is bool or not s.reverse is Array or s.reverse.size() > 3: return false
	return s.reverse == ["add4","div2","sub5"].slice(0, s.reverse.size())

extends RefCounted
static func ids() -> Array:
	var out: Array = []
	for i in range(1,19): out.append("FW%02d" % i)
	return out
static func definition(id: String) -> Dictionary:
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/fractions/levels.json"))
	return normalize(all.get(id,{}))

static func normalize(value: Variant) -> Variant:
	if value is float: return int(value)
	if value is Array:
		var out: Array = []
		for item in value: out.append(normalize(item))
		return out
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value: out[key] = normalize(value[key])
		return out
	return value

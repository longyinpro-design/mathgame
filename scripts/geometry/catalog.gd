extends RefCounted
static func ids() -> Array:
	var result: Array = []
	for n in range(1, 19): result.append("GV%02d" % n)
	return result
static func definition(id: String) -> Dictionary:
	var all = preload("res://scripts/content/content_catalog.gd").normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://scripts/geometry/levels.json")))
	for d in all:
		if d.id == id: return d.duplicate(true)
	return {}

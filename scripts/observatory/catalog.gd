extends RefCounted
static var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/observatory/levels.json"))
static func ids() -> Array:
	var result: Array = []
	for d in data: result.append(d.id)
	return result
static func definition(id: String) -> Dictionary:
	for d in data:
		if d.id == id: return normalize(d)
	return {}
static func normalize(v: Variant) -> Variant:
	if v is float and is_finite(v) and v==floor(v): return int(v)
	if v is Array:
		var a=[]
		for item in v:a.append(normalize(item))
		return a
	if v is Dictionary:
		var d={}
		for k in v:d[k]=normalize(v[k])
		return d
	return v

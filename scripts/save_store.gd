extends RefCounted
const Rules = preload("res://scripts/puzzle.gd")
var path: String = "user://progress-v1.json"
var error: String = ""
var read_blocked: bool = false

func read_save() -> Dictionary:
	error = ""
	read_blocked = false
	if not FileAccess.file_exists(path): return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		read_blocked = true
		error = "无法读取进度；原存档已保留。"
		return {}
	var parser = JSON.new()
	var parse_error = parser.parse(file.get_as_text())
	var data = parser.data if parse_error == OK else null
	if not data is Dictionary or data.get("version") != 1 or not data.get("levels") is Dictionary:
		read_blocked = true
		error = "存档格式不受支持；原存档已保留。"
		return {}
	for id in data.levels:
		if id not in ["F12","F07"] or not Rules.valid(data.levels[id]) or data.levels[id].id != id:
			read_blocked = true
			error = "存档内容异常；原存档已保留。"
			return {}
		# JSON numbers decode as floats; canonicalize discrete runtime state.
		for i in range(6): data.levels[id].slots[i] = int(data.levels[id].slots[i])
		data.levels[id].input = int(data.levels[id].input)
		data.levels[id].hint = int(data.levels[id].hint)
	return data.levels

func write_save(levels: Dictionary) -> bool:
	# Invalid existing saves are never silently replaced.
	if read_blocked: return false
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "进度保存失败，请保留游戏窗口。"
		return false
	file.store_string(JSON.stringify({"version": 1, "levels": levels}))
	file.flush()
	var result = file.get_error()
	file.close()
	if result != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "进度保存失败，请保留游戏窗口。"
		return false
	error = ""
	return true

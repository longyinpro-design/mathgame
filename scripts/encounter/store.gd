extends RefCounted
const Rules = preload("res://scripts/encounter/rules.gd")
var path = "user://guardian-sample-v3.json"
var error = ""
var protected = false
func read_save() -> Dictionary:
	error = ""; protected = false
	if not FileAccess.file_exists(path): return Rules.fresh()
	var file = FileAccess.open(path,FileAccess.READ)
	var parser = JSON.new()
	if file == null or parser.parse(file.get_as_text()) != OK:
		protected = true; error = "记录读取失败，原文件已保留。"; return Rules.fresh()
	var data = parser.data
	if not data is Dictionary or data.get("version") != 3 or not Rules.valid(data.get("state")):
		protected = true; error = "记录格式异常，原文件已保留。"; return Rules.fresh()
	for key in ["left","attempts","hint"]: data.state[key] = int(data.state[key])
	return data.state
func write_save(state: Dictionary) -> bool:
	if protected: return false
	if not Rules.valid(state): error = "状态异常，未覆盖记录。"; return false
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: error = "暂时无法保存，下次操作将重试。"; return false
	file.store_string(JSON.stringify({"version":3,"state":state})); file.flush()
	var code = file.get_error(); file.close()
	if code != OK or DirAccess.rename_absolute(path+".tmp",path) != OK:
		error = "暂时无法保存，下次操作将重试。"; return false
	error = ""; return true

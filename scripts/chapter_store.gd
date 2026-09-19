extends RefCounted
const Rules = preload("res://scripts/chapter_rules.gd")
var path: String = "user://forest-chapter-v2.json"
var error: String = ""
var read_blocked: bool = false

func read_save() -> Dictionary:
	error = ""
	read_blocked = false
	if not FileAccess.file_exists(path): return Rules.fresh()
	var f = FileAccess.open(path,FileAccess.READ)
	var parser = JSON.new()
	if f == null or parser.parse(f.get_as_text()) != OK:
		read_blocked = true
		error = "旧记录读取失败，已保留原文件。本次探索暂不能保存。"
		return Rules.fresh()
	var data = parser.data
	# Normalize only after shape validation; validation compares numeric arrays via sums below.
	if not data is Dictionary or data.get("version") != 2 or not Rules.valid(data.get("chapter")):
		read_blocked = true
		error = "探索记录不完整，已保留原文件。本次探索暂不能保存。"
		return Rules.fresh()
	return Rules.normalize(data.chapter)

func write_save(state: Dictionary) -> bool:
	if read_blocked: return false
	if not Rules.valid(state):
		error = "探索状态校验失败，未覆盖保存记录。"
		return false
	var f = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f == null:
		error = "暂时无法保存；请保留窗口，下次操作将重试。"
		return false
	f.store_string(JSON.stringify({"version":2,"chapter":state}))
	f.flush()
	var result = f.get_error()
	f.close()
	if result != OK or DirAccess.rename_absolute(path+".tmp",path) != OK:
		error = "暂时无法保存；请保留窗口，下次操作将重试。"
		return false
	error = ""
	return true

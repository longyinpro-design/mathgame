extends RefCounted

const Chapter = preload("res://scripts/chapter_rules.gd")
const Encounter = preload("res://scripts/encounter/rules.gd")
var path = "user://forest-journey-v4.json"
var error = ""
var protected = false
var state: Dictionary

# Both existing scenes write into one journey record through their existing store seam.
class SectionStore extends RefCounted:
	var owner_store: RefCounted
	var section: String
	var error: String:
		get: return owner_store.error
	var protected: bool:
		get: return owner_store.protected
	var read_blocked: bool:
		get: return owner_store.protected

	func read_save() -> Dictionary:
		return owner_store.state[section].duplicate(true)

	func write_save(value: Dictionary) -> bool:
		owner_store.state[section] = value.duplicate(true)
		return owner_store.save()

static func fresh() -> Dictionary:
	return {"chapter":Chapter.fresh(), "encounter":Encounter.fresh(),
		"returned":false, "volume":0.7, "muted":false}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["chapter","encounter","returned","volume","muted"]): return false
	if not Chapter.valid(value.chapter) or not Encounter.valid(value.encounter): return false
	if not value.returned is bool or not value.muted is bool: return false
	if not (value.volume is int or value.volume is float) or not is_finite(value.volume) or value.volume < 0 or value.volume > 1: return false
	# JSON decodes numbers as floats; compare validated numeric values, not typed dictionaries.
	var encounter = value.encounter
	var untouched = encounter.left == 7 and encounter.attempts == 0 and encounter.hint == 0 and not encounter.introduced and not encounter.won and not encounter.reward
	if value.chapter.stage < 3 and not untouched: return false
	if not encounter.introduced and not untouched: return false
	return not value.returned or value.encounter.reward

func read_save() -> Dictionary:
	error = ""; protected = false; state = fresh()
	if not FileAccess.file_exists(path): return state
	var file = FileAccess.open(path,FileAccess.READ)
	var parser = JSON.new()
	if file == null or parser.parse(file.get_as_text()) != OK:
		protected = true; error = "旅程记录无法读取，原文件已保留。"; return state
	var data = parser.data
	if not data is Dictionary or data.get("version") != 4 or not valid(data.get("state")):
		protected = true; error = "旅程记录格式异常，原文件已保留。"; return state
	state = data.state
	state.chapter = Chapter.normalize(state.chapter)
	for key in ["left","hint","attempts"]: state.encounter[key] = int(state.encounter[key])
	return state

func section_store(section: String) -> RefCounted:
	var adapter = SectionStore.new()
	adapter.owner_store = self; adapter.section = section
	return adapter

func save() -> bool:
	if protected: return false
	if not valid(state): error = "旅程状态校验失败，未覆盖记录。"; return false
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: error = "暂时无法保存，请重试。进度仍保留在当前窗口。"; return false
	file.store_string(JSON.stringify({"version":4,"state":state})); file.flush()
	var code = file.get_error(); file.close()
	if code != OK or DirAccess.rename_absolute(path+".tmp",path) != OK:
		error = "暂时无法保存，请重试。进度仍保留在当前窗口。"; return false
	error = ""; return true

func milestone() -> int:
	return int(state.chapter.stage == 3)+int(state.encounter.reward)

func next_stop() -> String:
	return "chapter" if state.chapter.stage < 3 else "encounter"

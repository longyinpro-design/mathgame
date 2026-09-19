extends RefCounted
const Rules = preload("res://scripts/cargo/rules.gd")
const Encounter = preload("res://scripts/encounter/rules.gd")
var path = "user://treetop-journey-v5.json"
var error = ""
var protected = false
var state = fresh()
class EncounterStore extends RefCounted:
	var owner_store: RefCounted
	var error: String:
		get: return owner_store.error
	var protected: bool:
		get: return owner_store.protected
	func read_save() -> Dictionary: return owner_store.state.encounter.duplicate(true)
	func write_save(value: Dictionary) -> bool:
		owner_store.state.encounter = value.duplicate(true)
		return owner_store.save()
static func fresh() -> Dictionary:
	return {"cargo":Rules.fresh(),"encounter":Encounter.fresh(),"muted":false,"volume":0.7,"returned":false}
static func valid(s: Variant) -> bool:
	if not s is Dictionary or not s.has_all(["cargo","encounter","muted","volume","returned"]): return false
	if not Rules.valid(s.cargo) or not Encounter.valid(s.encounter): return false
	if not s.muted is bool or not s.returned is bool: return false
	if not (s.volume is int or s.volume is float) or not is_finite(s.volume) or s.volume < 0 or s.volume > 1: return false
	var e = s.encounter
	var untouched = e.left == 7 and e.attempts == 0 and e.hint == 0 and not e.introduced and not e.won and not e.reward
	if not s.cargo.complete and not untouched: return false
	if not e.introduced and not untouched: return false
	return not s.returned or e.reward
func read_save() -> Dictionary:
	state = fresh(); error = ""; protected = false
	if not FileAccess.file_exists(path): return state
	var file = FileAccess.open(path,FileAccess.READ)
	var parser = JSON.new()
	if file == null or parser.parse(file.get_as_text()) != OK:
		protected = true; error = "记录无法读取，原文件已保留。"; return state
	var data = parser.data
	if not data is Dictionary or data.get("version") != 5 or not valid(data.get("state")):
		protected = true; error = "记录格式异常，原文件已保留。"; return state
	state = data.state; state.cargo = Rules.normalize(state.cargo)
	for key in ["left","attempts","hint"]: state.encounter[key] = int(state.encounter[key])
	return state
func save() -> bool:
	if protected: return false
	if not valid(state): error = "状态异常，未覆盖记录。"; return false
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: error = "暂时无法保存。现场仍保留，请重试。"; return false
	file.store_string(JSON.stringify({"version":5,"state":state})); file.flush()
	var code = file.get_error(); file.close()
	if code != OK or DirAccess.rename_absolute(path+".tmp",path) != OK:
		error = "暂时无法保存。现场仍保留，请重试。"; return false
	error = ""; return true
func encounter_store() -> RefCounted:
	var adapter = EncounterStore.new(); adapter.owner_store = self; return adapter

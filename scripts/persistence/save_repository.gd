extends RefCounted
const Catalog = preload("res://scripts/content/content_catalog.gd")

var path = "user://profiles/local-1/save-v1.json"
var error = ""
var protected = false
# Fault injection belongs to the repository boundary; it never modifies a player file.
var fail_at = ""
var migration_backup = ""
var migration_source_hash = ""

func read_profile(validate: Callable, upgrade: Callable = Callable()) -> Dictionary:
	error = ""; protected = false; migration_backup = ""; migration_source_hash = ""
	if not FileAccess.file_exists(path): return {"status":"new"}
	var file = FileAccess.open(path, FileAccess.READ)
	var parser = JSON.new()
	if file == null:
		return _protect("记录无法读取，原文件已保留。")
	var raw = file.get_buffer(file.get_length()); file.close()
	var code = parser.parse(raw.get_string_from_utf8())
	var decoded = Catalog.normalize_numbers(parser.data)
	if code != OK:
		return _protect("记录损坏、版本不兼容或状态不一致，原文件已保留。")
	if not validate.call(decoded):
		var upgraded = upgrade_empty_development_profile(decoded,validate)
		if upgraded.is_empty() and upgrade.is_valid(): upgraded = upgrade.call(decoded)
		if upgraded.is_empty(): return _protect("记录损坏、版本不兼容或状态不一致，原文件已保留。")
		var hash = HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(raw)
		migration_source_hash = hash.finish().hex_encode()
		if FileAccess.get_sha256(path) != migration_source_hash: return _protect("记录在读取期间发生变化，未覆盖；请重新读取。")
		migration_backup = ProjectSettings.globalize_path(path)+".before-upgrade-"+str(Time.get_ticks_usec())
		if FileAccess.file_exists(migration_backup): return _protect("备份名称已存在，原记录未改动；请重新读取。")
		var backup = FileAccess.open(migration_backup,FileAccess.WRITE)
		if backup == null: return _protect("无法备份旧手记，原文件未改动。")
		backup.store_buffer(raw); backup.flush(); var backup_error = backup.get_error(); backup.close()
		if backup_error != OK or FileAccess.get_sha256(migration_backup) != migration_source_hash: return _protect("手记备份未完成，原文件未改动。")
		return {"status":"migration", "profile":upgraded}
	return {"status":"loaded", "profile":decoded}

func _protect(message: String) -> Dictionary:
	protected = true; error = message
	return {"status":"protected", "error":error}

func write_profile(candidate: Dictionary, validate: Callable) -> bool:
	if protected: return false
	if not validate.call(candidate):
		error = "状态校验失败，未覆盖记录。"; return false
	if not migration_source_hash.is_empty() and FileAccess.get_sha256(path) != migration_source_hash:
		protected = true; error = "原记录在升级期间发生变化，未覆盖；请重新读取。"; return false
	var absolute = ProjectSettings.globalize_path(path)
	if fail_at == "open" or DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		error = "未保存，无法创建记录，请重试。"; return false
	var temporary = absolute + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = "未保存，无法写入记录，请重试。"; return false
	file.store_string(JSON.stringify(candidate)); file.flush()
	var code = file.get_error(); file.close()
	if code != OK or fail_at == "flush" or fail_at == "replace":
		error = "未保存，现场已保留，请重试。"; return false
	if not migration_source_hash.is_empty() and FileAccess.get_sha256(path) != migration_source_hash:
		protected = true; error = "原记录在升级期间发生变化，未覆盖；请重新读取。"; return false
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		error = "未保存，无法替换记录，请重试。"; return false
	error = ""; migration_source_hash = ""; return true

func upgrade_empty_development_profile(value: Variant, validate: Callable) -> Dictionary:
	# Exact observed pre-release shape only. Never infer missing fields for a played or unknown profile.
	if not value is Dictionary or not value.get("schema_version") is int or not value.get("content_revision") is String: return {}
	if value.schema_version != 1 or value.content_revision != Catalog.REVISION or value.get("active_run") != null: return {}
	if not value.get("suspended_runs") is Dictionary or not value.suspended_runs.is_empty() or not value.get("world") is Dictionary or not value.get("progress") is Dictionary or not value.get("learning") is Dictionary: return {}
	if not value.progress.get("completed_levels") is Array or not value.progress.completed_levels.is_empty() or not value.learning.get("observations") is Array or not value.learning.observations.is_empty(): return {}
	if not value.get("revision") is int or value.revision < 0 or value.revision >= 2147483647: return {}
	var keys = value.world.keys(); keys.sort()
	if keys != ["dialogues","dismissed_recommendations","events","location_id","tracked_level"]: return {}
	var next = value.duplicate(true); next.world.region_positions = {}; next.world.region_dialogues = []; next.revision += 1
	return next if validate.call(next) else {}

func preserve_protected_file() -> String:
	if not protected or not FileAccess.file_exists(path): return ""
	var absolute = ProjectSettings.globalize_path(path)
	var backup = absolute+".protected-"+str(Time.get_ticks_usec())
	if FileAccess.file_exists(backup) or DirAccess.rename_absolute(absolute,backup) != OK:
		error = "无法保留原记录，未开始新的旅程。"; return ""
	protected = false; migration_source_hash = ""
	return backup

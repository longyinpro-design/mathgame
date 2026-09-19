extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func old_profile() -> Dictionary:
	var value = Session.fresh(); value.world.erase("region_positions"); value.world.erase("region_dialogues"); value.revision = 1; value.settings.volume = 0.45; value.settings.muted = true
	return value
func write(path: String, value: Variant) -> String:
	var raw = JSON.stringify(value)+"\n"; var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(raw); file.close(); return raw
func _initialize() -> void:
	var path = "/tmp/pixel-forest-empty-migration-"+str(Time.get_ticks_usec())+".json"
	var raw = write(path,old_profile()); var s = Session.new()
	check(s.open(path),"known empty intermediate profile upgrades")
	check(s.profile.revision == 2 and s.profile.settings.volume == 0.45 and s.profile.settings.muted,"settings and revision preserved correctly")
	check(s.profile.world.region_positions.is_empty() and s.profile.world.region_dialogues.is_empty(),"only absent unused world records initialized")
	check(FileAccess.get_file_as_string(s.repository.migration_backup) == raw,"original bytes backed up before replacement")
	var loaded = Session.new(); check(loaded.open(path) and loaded.profile == s.profile and loaded.repository.migration_backup == "","upgraded format does not migrate again")
	path += ".failure"; raw = write(path,old_profile()); s = Session.new(); s.repository.fail_at = "replace"
	check(not s.open(path) and s.profile.is_empty() and not s.pending.is_empty(),"failed upgrade keeps candidate uninstalled")
	check(FileAccess.get_file_as_string(path) == raw,"failed upgrade keeps original file")
	s.repository.fail_at = ""; check(s.retry() and s.profile.settings.volume == 0.45,"retry commits exact upgraded candidate")
	path += ".changed"; raw = write(path,old_profile()); s = Session.new(); s.repository.fail_at = "replace"; s.open(path)
	var changed = old_profile(); changed.settings.volume = 0.2; raw = write(path,changed)
	s.repository.fail_at = ""; check(not s.retry() and s.repository.protected and FileAccess.get_file_as_string(path) == raw,"concurrent source change is never overwritten")
	check(s.open(path) and s.profile.settings.volume == 0.2 and s.pending.is_empty(),"explicit reread uses changed source safely")
	path += ".new-choice"; raw = write(path,old_profile()); s = Session.new(); s.repository.fail_at = "replace"; s.open(path)
	changed = old_profile(); changed.settings.volume = 0.15; raw = write(path,changed); s.repository.fail_at = ""
	check(not s.retry() and s.repository.protected,"changed source enters protection before new-journey choice")
	check(s.new_after_protected(true) and s.pending.is_empty() and not s.repository.protected,"confirmed new journey clears abandoned migration guard")
	check(s.profile.revision == 0 and s.profile.progress.completed_levels.is_empty(),"new choice creates normal fresh profile")
	var original_preserved = false
	for name in DirAccess.get_files_at(path.get_base_dir()):
		if name.begins_with(path.get_file()+".protected-") and FileAccess.get_file_as_string(path.get_base_dir().path_join(name)) == raw: original_preserved = true
	check(original_preserved,"new-journey choice preserves changed source bytes")
	path += ".unknown"; var unknown = old_profile(); unknown.active_run = {"level_id":"FL01"}; raw = write(path,unknown); s = Session.new()
	check(not s.open(path) and s.repository.protected and FileAccess.get_file_as_string(path) == raw,"played or unknown shape is protected rather than fabricated")
	print("FOREST EMPTY MIGRATION ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

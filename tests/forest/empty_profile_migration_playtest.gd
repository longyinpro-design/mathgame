extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
const Session = preload("res://scripts/core/game_session.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")
func run() -> void:
	var path = "/tmp/pixel-forest-migration-ui-"+str(Time.get_ticks_usec())+".json"
	var value = Session.fresh(); value.world.erase("region_positions"); value.world.erase("region_dialogues"); value.revision = 1; value.settings.muted = true; value.settings.volume = 0.45
	var raw = JSON.stringify(value); var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(raw); file.close()
	var game = Scene.instantiate(); game.story_enabled = false; game.save_path = path; game.session.repository.fail_at = "replace"; root.add_child(game)
	await create_timer(0.25).timeout
	check(game.modal and game.session.profile.is_empty() and not game.session.pending.is_empty(),"migration write failure blocks game startup visibly")
	check(FileAccess.get_file_as_string(path) == raw,"failed startup keeps original bytes")
	game.session.repository.fail_at = ""
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	var retry = game.overlay.get_node("retry"); var point = retry.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.pressed = pressed; event.button_index = MOUSE_BUTTON_LEFT; root.push_input(event)
	await create_timer(0.15).timeout
	check(not game.modal and game.page == "camp" and game.session.profile.revision == 2,"real retry opens migrated empty camp")
	check(game.session.profile.settings.muted and is_equal_approx(game.session.profile.settings.volume,0.45) and game.sound.music.volume_db <= -80,"existing settings retained in actual audio/UI")
	check(FileAccess.get_file_as_string(game.session.repository.migration_backup) == raw,"startup backup is exact original")
	game.queue_free(); await create_timer(0.15).timeout
	print("FOREST EMPTY MIGRATION UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

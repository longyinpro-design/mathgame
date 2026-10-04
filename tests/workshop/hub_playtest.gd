extends SceneTree
# Real-window chapter flow; all save paths stay in this run's private temporary directory.
const Scene = preload("res://game/workshop_island.tscn")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const Bridge = preload("res://scripts/workshop/workshop_bridge.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const MarketBridge = preload("res://scripts/market/market_bridge.gd")
const CAPTURE = "res://docs/playtest/workshop-chapter-hub"
var checks = 0
var failures = 0
var dir = ""
var hub: Control
var headless = DisplayServer.get_name() == "headless"
func _initialize() -> void:
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)
func write_json(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
func finished(id: String) -> Dictionary:
	var rules = load("res://scripts/workshop/" + id.to_lower() + "_rules.gd")
	var state = rules.fresh()
	while state.stage != "puzzle": state = rules.advance(state)
	match id:
		"GW01": state.trays = [13,7,4]
		"GW02": state.molds = [4,4,4,4,4,4,7,7]
		"GW18": state.press = [0,1,3]; state.cool = [1,3,6]
	var guard = 0
	while state.stage != "complete" and guard < 30:
		state = rules.advance(state); guard += 1
		if state.is_empty(): break
	check(rules.validate(state) and state.get("stage") == "complete", id + " valid completion fixture")
	return state
func frame_settle() -> void:
	await process_frame; await process_frame; await process_frame
func mount() -> void:
	hub = Scene.instantiate(); root.add_child(hub); current_scene = hub
	await frame_settle()
func unmount() -> void:
	if is_instance_valid(current_scene): current_scene.queue_free()
	await frame_settle()
func input_ready() -> bool:
	if headless:
		for child in root.get_children(): child.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		await process_frame
		return true
	return await Focus.ready(root)
func tap(control: Control) -> void:
	if not await input_ready(): check(false,"native window ready"); return
	var point = control.get_global_transform_with_canvas() * (control.size / 2) * Vector2(root.size) / Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event)
	await frame_settle()
func key(code: int) -> void:
	if not await input_ready(): check(false,"native window ready"); return
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await frame_settle()
func capture(name: String) -> void:
	if headless: return # Headless flow checks deliberately produce no screenshot evidence.
	await frame_settle(); RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(CAPTURE + "/" + name + ".png") == OK, "screenshot " + name)
func check_layout() -> void:
	for button in hub.buttons.values():
		check(button.size.x >= 48 and button.size.y >= 46, "usable target " + button.name)
		check(Rect2(0,0,1280,720).encloses(button.get_global_rect()), "visible target " + button.name)
	var overflow = 0
	for child in hub.ui.get_children():
		if child is Label:
			if child.get_combined_minimum_size().x > child.size.x + 1: overflow += 1
			if child.get_visible_line_count() < child.get_line_count(): overflow += 1
	check(overflow == 0, "all chapter labels fit their boxes")
func return_from_level(id: String, complete_now: bool) -> void:
	var game = current_scene
	check(game != null and game.get("level_id") == id, "chapter opened " + id)
	if game == null or game.get("level_id") != id: return
	check(game.save_path == Bridge.level_paths[id], id + " uses isolated level path")
	check(game.buttons.has("back_hub") and not game.buttons.back_hub.disabled, id + " provides chapter return")
	if complete_now: check(game.commit(finished(id)), id + " writes a genuine completion receipt")
	await frame_settle()
	await tap(game.buttons.back_hub)
	hub = current_scene
	check(hub != null and hub.has_method("next_id"), id + " returns to workshop chapter")
	if hub == null or not hub.has_method("next_id"): return
	check(hub.progress.path == Bridge.progress_path and hub.progress.is_done(id), id + " return settles completion in the isolated chapter")
	check(MarketBridge.origin == "workshop-test-sentinel", id + " never consumes the market bridge")
func run() -> void:
	create_timer(100).timeout.connect(func(): push_error("workshop hub window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for viewport in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = viewport
		dir = "/tmp/workshop-hub-ui-%d" % Time.get_ticks_usec()
		Bridge.progress_path = dir + "/chapter/save-v1.json"; Bridge.level_paths = {}; Bridge.origin = ""
		for id in Catalog.order(): Bridge.level_paths[id] = dir + "/" + id + ".json"
		MarketBridge.origin = "workshop-test-sentinel"
		await mount()
		check(await input_ready(), "viewport input ready" if headless else "native minimized window ready")
		check(hub.buttons.size() == 19 and hub.next_id() == "GW01", "fresh hub offers GW01 and eighteen cards")
		check_layout(); await capture(str(viewport.x) + "-01-new-chapter")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() != null, "Tab reaches a chapter control")
		await tap(hub.buttons.card_GW04)
		check(current_scene == hub and Bridge.origin.is_empty(), "locked card cannot navigate")
		hub.show_modal("检查用遮罩")
		check(hub.buttons.card_GW01.disabled and hub.buttons.next_station.disabled, "modal disables every navigation action")
		hub.close_modal()
		hub.buttons.card_GW01.grab_focus(); await key(KEY_ENTER)
		await return_from_level("GW01", true)
		check(hub.next_id() == "GW02" and not hub.buttons.card_GW02.disabled, "GW01 return unlocks GW02")
		await tap(hub.buttons.next_station)
		await return_from_level("GW02", true)
		check(hub.next_id() == "GW03" and hub.summary().contains("2 / 18"), "GW02 return advances chapter to GW03")
		await capture(str(viewport.x) + "-02-two-complete")
		# Directly loaded GW18 receipts are credited without inventing its missing prerequisites.
		write_json(Bridge.level_paths.GW18, finished("GW18"))
		await unmount(); await mount()
		check(not hub.buttons.card_GW18.disabled and hub.buttons.card_GW17.disabled, "completed boss is replayable while its prerequisite remains locked")
		await tap(hub.buttons.card_GW18)
		await return_from_level("GW18", false)
		await tap(hub.buttons.card_GW01)
		var replay = current_scene
		check(replay.state.stage == "complete", "replay opens the saved completed level")
		check(replay.commit(load("res://scripts/workshop/gw01_rules.gd").fresh()), "replay can restart its own level record")
		await tap(replay.buttons.back_hub); hub = current_scene
		check(hub.progress.is_done("GW01") and hub.progress.is_done("GW02"), "restarting a level preserves earned chapter completion")
		await unmount()
		write_json(Bridge.progress_path, {"chapter":"workshop-v1","completed":Catalog.order()})
		await mount()
		check(hub.buttons.size() == 18 and not hub.buttons.has("next_station"), "finished chapter removes next-station action")
		check(hub.summary().contains("18 / 18") and hub.summary().contains("14 / 14"), "finished chapter counts main and side separately")
		for id in Catalog.order(): check(not hub.buttons["card_" + id].disabled, id + " remains replayable")
		check_layout(); await capture(str(viewport.x) + "-03-complete-chapter")
		await unmount()
	# Complete and replay before the first return: restart must checkpoint first.
	Bridge.progress_path = dir + "/before-first-hub/save-v1.json"
	Bridge.origin = "workshop_hub"
	var direct = load(Catalog.scene("GW01")).instantiate()
	direct.save_path = Bridge.level_paths.GW01
	root.add_child(direct); current_scene = direct; await frame_settle()
	check(direct.commit(finished("GW01")), "direct entry completes before visiting the hub")
	write_json(Bridge.progress_path, {"chapter":"workshop-v1","completed":["GW99"]})
	var protected_bytes = FileAccess.get_file_as_string(Bridge.progress_path)
	direct.restart(); await frame_settle()
	check(direct.modal and direct.state.stage == "complete", "protected chapter prevents replay from erasing completion")
	check(FileAccess.get_file_as_string(Bridge.progress_path) == protected_bytes, "replay preserves corrupted chapter bytes")
	direct.close_modal()
	# A fixture file blocks the chapter directory, exercising the real write boundary.
	var blocker = dir + "/checkpoint-write-blocker"
	write_json(blocker, {"fixture":"temporary write obstruction"})
	Bridge.progress_path = blocker + "/save-v1.json"
	var receipt_hash = FileAccess.get_sha256(direct.save_path)
	direct.restart(); await frame_settle()
	check(direct.modal and direct.state.stage == "complete", "failed chapter checkpoint preserves completed level state")
	check(FileAccess.get_sha256(direct.save_path) == receipt_hash, "failed checkpoint leaves completion receipt byte-for-byte unchanged")
	check(direct.buttons.has("retry_restart") and not direct.buttons.retry_restart.disabled, "failed checkpoint offers an enabled replay retry")
	check(DirAccess.remove_absolute(blocker) == OK, "only the temporary write-blocker fixture is removed")
	await tap(direct.buttons.retry_restart)
	check(not direct.modal and direct.state.stage == "arrival", "checkpoint retry clears modal and restarts only after saving")
	check(FileAccess.file_exists(Bridge.progress_path), "checkpoint retry writes chapter progress")
	await tap(direct.buttons.back_hub); hub = current_scene
	check(hub.progress.is_done("GW01"), "replay before first hub visit preserves earned completion")
	await unmount()
	Bridge.progress_path = ""; Bridge.level_paths = {}; Bridge.origin = ""; MarketBridge.origin = ""
	print("WORKSHOP HUB HEADLESS FLOW " if headless else "WORKSHOP HUB WINDOW ", checks-failures, "/", checks, " PASS")
	quit(1 if failures else 0)

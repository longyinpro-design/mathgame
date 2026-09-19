extends SceneTree
const SCENE = preload("res://game/treetop.tscn")
const Store = preload("res://scripts/cargo/store.gd")
var checks = 0
var failures = 0
var game: Control
var path = "/tmp/pixel-cargo-ui-%d.json" % OS.get_process_id()
func _initialize() -> void: call_deferred("run")
func check(value: bool, title: String) -> void:
	checks += 1
	if value: print("PASS ",title)
	else: failures += 1; push_error(title)
func mouse(point: Vector2, pressed: bool) -> void:
	var e = InputEventMouseButton.new(); e.position = point; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; root.push_input(e)
func click(point: Vector2) -> void:
	mouse(point,true); mouse(point,false)
	await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var e = InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = pressed; root.push_input(e)
	await process_frame
func move(item: int, loc: int) -> void:
	await click(game.world.item_position(item)-Vector2(0,22))
	check(game.selected == item,"select item %d with real mouse" % item)
	var point = game.world.zone_rect(loc).get_center()
	await click(point)
	while game.busy: await process_frame
	check(game.store.state.cargo.places[item] == loc,"place item %d at dock/basket %d" % [item,loc])
func capture(name: String) -> void:
	await create_timer(0.12).timeout; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://docs/playtest/v52/"+name+".png")
func new_game() -> void:
	game = SCENE.instantiate(); game.store.path = path; game.time_scale = 0.05; root.add_child(game)
	await create_timer(0.2).timeout
func lift() -> void:
	await click(game.action_button.get_global_rect().get_center())
	# Presentation has wall-clock durations; fast rendering may emit 90 frames before arrival.
	var deadline = Time.get_ticks_msec()+2000
	while game.busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
	check(not game.busy,"lift reaches stable arrival within timeout")
func run() -> void:
	create_timer(55).timeout.connect(func(): push_error("cargo UI watchdog"); quit(1))
	await new_game()
	check(game.page == "camp","fresh v5 opens camp")
	check(game.theme.default_font.has_char("远".unicode_at(0)) and game.theme.default_font.has_char("橙".unicode_at(0)),"bundled Chinese font covers previous missing glyphs")
	await capture("camp")
	game.dialogue_left = 0; await process_frame; await capture("camp-quiet")
	await click(game.world.item_position(0)-Vector2(0,25))
	check(game.dialogue_left > 0 and game.page == "camp","scene fox hotspot opens companion dialogue")
	await click(Vector2(1100,220)); check(game.page == "cargo","treehouse itself is a clickable scene entrance")
	game.leave_cargo()

	game.open_encounter(); check(not is_instance_valid(game.active),"cannot skip delivery")
	game.controls[1].grab_focus(); await key(KEY_SPACE)
	check(game.page == "settings","camp button retains standard keyboard Space activation")
	var volume_slider: HSlider
	for c in game.ui.get_children():
		if c is HSlider: volume_slider = c
	var old_volume = volume_slider.value; volume_slider.grab_focus(); await key(KEY_RIGHT)
	check(volume_slider.value > old_volume and is_equal_approx(game.store.state.volume,volume_slider.value),"settings slider receives arrow keys and saves volume")
	await key(KEY_ESCAPE); check(game.page == "camp","settings Escape returns to camp")

	await click(game.camp_start.get_global_rect().get_center()); check(game.page == "cargo","real start button enters cargo scene")
	await capture("cargo-start")
	game.dialogue_left = 0; await process_frame; await capture("cargo-quiet")
	# Cancelling or an inaccessible drop must not alter the scene.
	await click(game.world.item_position(0)-Vector2(0,22)); game.place(2)
	check(game.store.state.cargo.places[0] == 0,"inaccessible upper basket rejects drop")
	var drag_start = game.world.item_position(0)-Vector2(0,22); mouse(drag_start,true)
	var drag_motion = InputEventMouseMotion.new(); drag_motion.position = Vector2(1160,632); drag_motion.button_mask = MOUSE_BUTTON_MASK_LEFT; root.push_input(drag_motion)
	await process_frame; mouse(drag_motion.position,false); await process_frame
	check(game.selected == -1 and game.store.state.cargo.places[0] == 0,"dropping over toolbar cancels without activating its button")
	await click(game.world.item_position(0)-Vector2(0,22)); game.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.selected == -1 and not game.world.dragging,"focus loss releases held item")
	# Recovery is a visible confirmed action; hints survive reset and undo.
	game.store.state.cargo.places = [0,0,0,0,0,0]; game.store.state.cargo.hints = 2; game.refresh_cargo(); game.hint()
	check(game.message.text.contains("重新摆放"),"stranded layout offers recovery through current-state hint")
	await click(game.reset_button.get_global_rect().get_center()); check(game.modal and game.controls[0].disabled,"reset confirmation disables underlying navigation")
	game.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var locked = true
	for control in game.controls: locked = locked and control.disabled
	check(locked and game.retry_button.disabled,"focus notification keeps every background control disabled under modal")
	var hints_before = game.store.state.cargo.hints
	game.leave_cargo(); game.hint()
	check(game.page == "cargo" and game.modal and game.store.state.cargo.hints == hints_before,"modal blocks background navigation and hint callbacks")

	await key(KEY_ESCAPE); check(not game.modal and game.store.state.cargo.places == [0,0,0,0,0,0],"Escape dismisses confirmation without resetting")
	await click(game.reset_button.get_global_rect().get_center())
	await click(Vector2(726,414)); check(not game.modal and game.store.state.cargo.places == [0,0,0,3,3,3] and game.store.state.cargo.hints == 3,"confirmed reset recovers solvable layout and retains assistance")
	root.size = Vector2i(960,540); await create_timer(0.12).timeout
	await click((game.world.item_position(0)-Vector2(0,22))*0.75)
	check(game.selected == 0,"960x540 native coordinates select actual cargo")
	await capture("small-cargo")
	await key(KEY_ESCAPE); root.size = Vector2i(1280,720); await create_timer(0.12).timeout

	await move(0,1); await move(2,1)
	await click(game.world.item_position(5)-Vector2(0,22)); await capture("pickup-preview")
	await click(game.world.zone_rect(2).get_center())
	while game.busy: await process_frame
	check(game.store.state.cargo.places[5] == 2,"counterweight loaded through real click")
	await lift(); check(game.store.state.cargo.places[0] == 3 and game.store.state.cargo.places[2] == 3,"first trip automatically unloads fox and seeds")
	await capture("first-arrival")
	game.store.path = path+"/missing/state.json"; game.leave_cargo()
	check(game.page == "cargo" and not game.store.error.is_empty(),"failed save keeps current scene")
	game.store.path = path; await click(game.retry_button.get_global_rect().get_center())
	check(game.store.error.is_empty(),"retry writes preserved state")
	game.queue_free(); await create_timer(0.1).timeout; await new_game(); game.show_cargo()
	check(game.store.state.cargo.places[0] == 3 and not game.store.state.cargo.left_low,"partial delivery survives new instance")
	await move(3,1); await move(4,1)
	game.time_scale = 0.3
	await click(game.action_button.get_global_rect().get_center())
	var during = game.store.state.cargo.duplicate(true); game.leave_cargo(); game.select_item(1); game.undo()
	check(game.busy and game.page == "cargo" and game.selected == -1 and game.store.state.cargo == during,"lift animation locks leave, pickup and undo")
	while game.busy: await process_frame
	game.time_scale = 0.05
	await move(3,0); await move(4,0)
	await key(KEY_2); await key(KEY_LEFT)
	while game.busy: await process_frame
	check(game.store.state.cargo.places[1] == 1,"keyboard selects hero and boards basket")
	await key(KEY_Z); check(game.store.state.cargo.places[1] == 0,"keyboard undo restores layout")
	# Actual drag, including motion through the viewport.
	var start = game.world.item_position(1)-Vector2(0,22); mouse(start,true)
	var motion = InputEventMouseMotion.new(); motion.position = game.world.zone_rect(1).get_center(); motion.button_mask = MOUSE_BUTTON_MASK_LEFT; root.push_input(motion)
	await process_frame; mouse(motion.position,false); await process_frame
	while game.busy: await process_frame
	check(game.store.state.cargo.places[1] == 1,"real drag boards hero")
	await lift(); check(game.store.state.cargo.complete,"whole cargo chapter completes")
	await capture("cargo-complete")
	await click(game.journal_button.get_global_rect().get_center()); check(game.page == "journal","journal opens from finished chapter")
	await capture("journal"); await key(KEY_ESCAPE)
	check(game.page == "cargo" and game.store.state.cargo.complete,"journal returns to preserved scene")
	await key(KEY_SPACE)
	check(game.active.phase == "approach","transition key does not activate the newly mounted encounter")
	check(is_instance_valid(game.active) and game.active.journey_mode,"cargo completion continues into guardian")
	check(game.sound.volume == 0,"camp music muted under guardian")
	var e = game.active; await e.awaken()
	await e.transfer(0,1); await e.transfer(0,1); await e.cast_spell(); await e.claim_reward()
	check(e.state.reward,"existing encounter reward completes within v5")
	await capture("guardian")
	game.return_encounter(); check(game.page == "camp" and game.store.state.returned,"reward returns to camp with milestone")
	await capture("homecoming")
	await click(game.settings_button.get_global_rect().get_center()); check(game.page == "settings","settings opens")
	await click(Vector2(850,284)); check(game.store.state.muted and game.sound.music.volume_db <= -80,"mute actually silences music")
	await capture("settings"); await key(KEY_ESCAPE)
	root.size = Vector2i(960,540); await create_timer(0.15).timeout
	await click(game.journal_button.get_global_rect().get_center()*0.75); check(game.page == "journal","960x540 scaled native input")
	await capture("small-journal")
	game.queue_free(); await create_timer(0.3).timeout
	DirAccess.remove_absolute(path)
	print("CARGO UI: %d/%d PASS" % [checks-failures,checks]); quit(1 if failures else 0)

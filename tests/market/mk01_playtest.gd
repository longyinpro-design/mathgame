extends SceneTree
const Scene = preload("res://game/market_mk01.tscn")
const Sample = preload("res://scripts/market/mk01_scene.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk01-reasoning"
func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
func click(id: String) -> void:
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false,"button unavailable "+id); return
	var b: Control = game.buttons[id]
	var logical = b.get_global_transform_with_canvas()*(b.size/2)
	var point = logical*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame
func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame
func place(id: int, slot: int) -> void:
	await click("cup_%d"%id); await click("slot_%d"%slot)
func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK01 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk01-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival","opens at harbor dialogue")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused narrative action")
		await click("next")
		check(game.state.beat == 2,"dialogue waits for explicit advances")
		await click("next"); await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes motion")
		await click("skip")
		check(game.state.stage == "ready","approach stops before player control")
		await click("next")
		check("未知" in game.world.cup_description(0),"tooltip keeps capacity unknown")
		await key(KEY_1); await key(KEY_Q); await key(KEY_Z)
		check(game.state.slots == [-1,-1,-1],"keyboard placement and undo")
		await place(0,0); await place(1,1); await place(2,2)
		await click("measure")
		game.elapsed = 2.1; await process_frame; await click("pause")
		check(game.world.poured_volume() == 0,"shutter reveals no intermediate cup volume")
		await capture(prefix+"02-shutter")
		await click("skip")
		check(game.state.observations.size() == 1 and not game.state.calibrated,"old shortcut yields only first receipt")
		await capture(prefix+"03-first-receipt")
		await click("next"); await click("measure")
		check(game.state.stage == "puzzle" and game.state.observations.size() == 1,"same mixture cannot count twice")
		await place(5,1); await click("measure")
		check(game.state.stage == "puzzle","calibration requires both blue and white and no small cup")
		await place(3,1); await click("measure")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes measurement")
		await click("skip"); await click("next")
		check(game.state.stage == "deduction" and game.state.guesses == [0,0],"two receipts do not automatically solve capacity")
		await capture(prefix+"04-inference")
		await click("guess_up_0"); await click("guess_up_1"); await click("confirm_capacity")
		check(game.state.stage == "deduction" and game.state.guesses == [2,2],"wrong claim remains editable")
		for n in range(4): await click("guess_up_0")
		for n in range(2): await click("guess_up_1")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state.stage == "deduction" and game.state.guesses == [6,4] and game.state.observations.size() == 2,"reload retains evidence and player's tags")
		await click("confirm_capacity")
		check(game.state.calibrated and game.state.slots == [-1,-1,-1],"correct inference unlocks fresh delivery order")
		await place(0,0); await place(1,1); await place(2,2)
		await click("measure"); await click("skip")
		check(game.state.stage == "result" and game.world.poured_volume() == 16,"old arrangement fails new delivery order")
		await click("next"); await click("reset"); await click("cancel")
		check(game.state.slots == [0,1,2],"cancel reset preserves cups")
		await click("reset"); await click("confirm")
		await place(0,0); await place(2,1); await place(5,2)
		await capture(prefix+"05-final-load")
		await click("measure")
		if small: await click("skip")
		else:
			while game.state.stage == "measuring": await process_frame
		check(game.state.stage == "result" and game.world.poured_volume() == 11,"final actual measurement reaches eleven")
		await click("next")
		game.elapsed = 2.5; await process_frame; await click("pause")
		check(game.world.seed_position() != Vector2(423,411),"seed sack visibly in flight")
		await capture(prefix+"06-delivery")
		if small: await click("skip")
		else:
			await click("pause")
			while game.state.stage == "delivery": await process_frame
		check(game.state.stage == "complete","three measurements and inference deliver seeds")
		check(not game.buttons.has("back_forest"),"standalone dock offers no camp return")
		await capture(prefix+"07-complete")
		if not small:
			# Reopening through the forest camp hub lands back on the delivered dock with a way home.
			game.queue_free(); await process_frame
			Sample.entry = "camp"
			game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
			check(game.state.stage == "complete" and game.from_camp and Sample.entry == "","camp arrival is consumed once at the delivered dock")
			check(game.buttons.has("back_forest") and not game.buttons.back_forest.disabled,"delivered dock offers the return to camp")
			await capture("08-return-to-camp")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK01 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

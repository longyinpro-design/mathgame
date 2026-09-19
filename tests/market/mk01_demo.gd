extends SceneTree
# Normal-speed scene recording; actual button input, no state/time jumps.
const Scene = preload("res://game/market_mk01.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var path = "/tmp/pixel-mk01-demo-"+str(Time.get_ticks_usec())+".json"
func _initialize() -> void: Focus.configure(root); call_deferred("run")
func delay(seconds: float) -> void: await create_timer(seconds).timeout
func click(id: String) -> void:
	if not game.buttons.has(id) or game.buttons[id].disabled: push_error("demo missing button "+id); quit(1); return
	var b: Control = game.buttons[id]
	var point = b.get_global_transform_with_canvas()*(b.size/2)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame
func stage_done() -> void:
	while game.state.stage in game.Rules.ANIMATIONS: await process_frame
func run() -> void:
	create_timer(75).timeout.connect(func(): push_error("demo watchdog"); quit(1))
	root.size = Vector2i(1280,720)
	game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	if not await Focus.ready(root): quit(1); return
	await delay(1.7); await click("next"); await delay(1.7); await click("next"); await delay(2)
	await click("next"); await stage_done(); await delay(1)
	await click("next"); await delay(1.5)
	for pair in [[0,0],[1,1],[2,2]]:
		await click("cup_%d"%pair[0]); await delay(0.35); await click("slot_%d"%pair[1]); await delay(0.6)
	await click("measure"); await stage_done(); await delay(2)
	await click("next"); await click("cup_3"); await delay(0.35); await click("slot_1"); await delay(1)
	await click("measure"); await stage_done(); await delay(2); await click("next"); await delay(2)
	for n in range(5): await click("guess_up_0"); await delay(0.3)
	for n in range(3): await click("guess_up_1"); await delay(0.3)
	await delay(1); await click("confirm_capacity"); await delay(1)
	for pair in [[0,0],[2,1],[5,2]]:
		await click("cup_%d"%pair[0]); await delay(0.35); await click("slot_%d"%pair[1]); await delay(0.6)
	await click("measure"); await stage_done(); await delay(2); await click("next"); await stage_done(); await delay(2)
	var ok = game.state.stage == "complete" and game.state.observations.size() == 2
	print("MARKET MK01 DEMO ",1 if ok else 0,"/1 PASS")
	game.queue_free(); await process_frame; DirAccess.remove_absolute(path); quit(0 if ok else 1)

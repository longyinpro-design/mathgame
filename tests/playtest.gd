extends SceneTree
const Rules = preload("res://scripts/puzzle.gd")
const Store = preload("res://scripts/save_store.gd")
var failures: int = 0
func check(value: bool, title: String) -> void:
	if not value:
		push_error(title)
		failures += 1
	else: print("PASS ",title)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://game/main.tscn").instantiate()
	game.store.path = "/tmp/pixel-math-test-%d.json" % OS.get_process_id()
	root.add_child(game)
	await process_frame
	game.enter("F12")
	game.choose(1)
	game.change_slot(0)
	game.undo()
	check(game.state.slots == [0,0,0,0,0,0],"triangle undo restores board")
	var answer = [1,6,3,2,5,4]
	for i in range(6):
		game.choose(answer[i])
		game.change_slot(i)
	check(Rules.solved(game.state),"F12 complete through scene actions")
	game.hint()
	check(game.state.hint == 0,"post-completion hint cannot downgrade independent result")
	var reload_store = Store.new()
	reload_store.path = game.store.path
	check(Rules.solved(reload_store.read_save().F12),"completed triangle persists to disk")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/pixel-math-triangle.png")
	game.reset_level()
	check(not Rules.solved(game.state),"reset reopens puzzle")
	game.undo()
	check(Rules.solved(game.state),"reset can be undone")
	game.enter("F07")
	game.reverse_step("sub5")
	check(game.state.reverse.is_empty(),"wrong inverse operation rejected")
	game.reverse_step("add4")
	game.hint()
	game.undo()
	check(game.state.hint == 1 and game.state.reverse.is_empty(),"undo preserves hint assistance")
	game.reverse_step("add4")
	game.reverse_step("div2")
	game.reverse_step("sub5")
	game.adjust(5)
	game.run_machine()
	check(not Rules.solved(game.state),"incorrect forward output does not pass")
	game.adjust(1)
	game.run_machine()
	check(Rules.solved(game.state),"F07 inverse construction and forward run complete")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/pixel-math-machine.png")
	var restored = reload_store.read_save()
	check(restored.F07.hint == 1 and Rules.solved(restored.F07),"both levels and assistance survive reload")
	game.levels = restored
	game.enter("F07")
	check(Rules.solved(game.state),"scene resumes saved machine state")
	game.show_map()
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/pixel-math-map.png")
	game.enter("F12")
	game.reset_level()
	await process_frame
	click(Vector2(142,620))
	await process_frame
	click(Vector2(380,220))
	await process_frame
	check(game.state.slots[0] == 1,"viewport mouse events select and place stone")
	var fits = true
	for child in game.screen.get_children():
		if child is Label and child.position.x == 815:
			fits = fits and child.position.x + child.size.x <= 1246
	check(fits,"right-panel Chinese labels fit panel width")
	var bad = Rules.fresh("F12")
	bad.slots = [1,1,0,0,0,0]
	check(not Rules.valid(bad),"duplicate stones rejected at persistence boundary")
	bad = Rules.fresh("F07")
	bad.reverse = ["sub5"]
	check(not Rules.valid(bad),"invalid inverse history rejected")
	var retry_store = Store.new()
	retry_store.path = game.store.path + "/missing/save.json"
	check(not retry_store.write_save(restored),"write failure is explicit")
	retry_store.path = game.store.path
	check(retry_store.write_save(restored) and retry_store.error.is_empty(),"write retries successfully after storage recovers")
	var f = FileAccess.open(game.store.path,FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	check(reload_store.read_save().is_empty() and not reload_store.error.is_empty(),"corrupt save gives explicit error")
	check(not reload_store.write_save(restored) and FileAccess.get_file_as_string(game.store.path) == "{broken","corrupt save preserved")
	DirAccess.remove_absolute(game.store.path)
	game.queue_free()
	await process_frame
	print("RESULT failures=",failures)
	quit(1 if failures else 0)

func click(pos: Vector2) -> void:
	for down in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)

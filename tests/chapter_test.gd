extends SceneTree
const Rules = preload("res://scripts/chapter_rules.gd")
const Store = preload("res://scripts/chapter_store.gd")
var failures = 0
var checks = 0
func check(ok: bool, name: String) -> void:
	checks += 1
	if ok: print("PASS ",name)
	else: failures += 1; push_error(name)
func _initialize() -> void: call_deferred("run")
func drain(game: Control) -> void:
	while game.mode == "dialogue": game.next_dialogue()
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.15).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("/tmp/forest-v2-"+name+".png")
func click(pos: Vector2) -> void:
	for pressed in [true,false]:
		var e = InputEventMouseButton.new(); e.position = pos; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; root.push_input(e)
func run() -> void:
	var game = load("res://game/chapter.tscn").instantiate()
	var test_path = "/tmp/forest-chapter-test-%d.json" % OS.get_process_id()
	game.store.path = test_path
	game.animation_seconds = 0.025
	root.add_child(game)
	await process_frame
	check(game.mode == "dialogue","new chapter begins with story")
	drain(game)
	check(game.state.intro,"intro progress saved")
	check(game.theme.default_font.has_char("远".unicode_at(0)),"Chinese font covers chapter text")
	await capture("world")
	var start_x = game.world.hero_x
	click(Vector2(480,380)); await create_timer(0.15).timeout
	check(game.world.hero_x > start_x and game.target_x == 480,"real ground click moves player")
	click(Vector2(1100,440)); await process_frame
	check(game.target_x == 700,"unrepaired bridge clamps ground-click destination")
	game.target_x = game.world.hero_x
	game.store.path = test_path+"/missing/save.json"
	game.finish_intro()
	check(not game.save_warning.text.is_empty(),"save failure immediately visible without rebuilding UI")
	game.store.path = test_path; game.save()
	check(game.save_warning.text.is_empty(),"save recovery immediately clears warning")
	game.interact("core")
	check(game.mode == "dialogue","puzzle requires world clues")
	drain(game)
	for id in ["bridge","stele","keeper"]:
		game.interact(id); drain(game)
	check(Rules.unlocked(game.state),"three distinct exploration clues unlock mechanism")
	game.interact("stele"); drain(game)
	check(game.state.clues.size() == 3,"re-reading clue does not duplicate")
	game.go_to("core"); game.show_journal(); game.show_world()
	check(game.pending.is_empty(),"opening journal cancels pending walk interaction")
	game.open_puzzle()
	await process_frame
	click(Vector2(155,630)); await process_frame
	click(Vector2(354,230)); await create_timer(0.1).timeout
	check(game.state.slots[0] == 1,"real viewport mouse places stone")
	game.undo()
	check(game.state.slots == [0,0,0,0,0,0],"stone placement undo")
	var first = [1,6,3,2,5,4]
	for i in range(6):
		game.select_stone(first[i]); await game.select_slot(i)
	check(not game.checked,"placement does not reveal automatic sums")
	await capture("puzzle1")
	await game.run_power()
	check(game.state.stage == 1 and game.world.bridge == 0.5,"first power animates half bridge and advances stage")
	drain(game)
	check(game.state.slots == first,"second stage preserves player's first solution")
	var store = Store.new(); store.path = test_path
	var disk = store.read_save()
	check(store.error.is_empty() and disk.stage == 1,"phase transition survives JSON disk reload")
	await capture("half-bridge")
	game.open_puzzle()
	check(Rules.targets(game.state) == [10,12,13],"new independent route demands")
	game.run_power()
	await create_timer(0.005).timeout
	var during = game.state.slots.duplicate()
	game.reset_board(); game.leave_puzzle(); game.give_hint()
	check(game.busy and game.mode == "puzzle" and game.state.slots == during and game.state.hints[1] == 0,"power animation locks mutation and navigation")
	await create_timer(0.2).timeout
	check(game.state.stage == 1 and not game.busy,"unchanged layout cannot solve second phase")
	await game.select_slot(0); await game.select_slot(1)
	await game.select_slot(2); await game.select_slot(4)
	var before = game.state.slots.duplicate()
	await game.select_slot(3); await game.select_slot(5)
	check(game.state.slots == before and game.state.swaps.size() == 2,"third swap cannot bypass two-swap budget")
	game.give_hint(); game.undo()
	check(game.state.swaps.size() == 1 and game.state.hints[1] == 1,"undo restores swap budget and retains assistance")
	await game.select_slot(3); await game.select_slot(5)
	check(Rules.powered(game.state),"two planned exchanges satisfy all route demands")
	await capture("puzzle2")
	await game.run_power(); drain(game)
	check(game.state.stage == 2 and game.world.bridge == 1,"second power animates full bridge")
	game.go_to("gate")
	await create_timer(5.2).timeout
	check(game.world.hero_x > 990,"player can cross only after bridge repair")
	if game.mode == "dialogue": drain(game)
	check(game.state.stage == 3 and game.mode == "ending","seed delivery produces chapter ending")
	await capture("ending")
	game.show_world(); await capture("restored-world")
	disk = store.read_save()
	var resumed = load("res://game/chapter.tscn").instantiate()
	resumed.store.path = test_path
	root.add_child(resumed)
	check(resumed.state.stage == 3 and resumed.world.bridge == 1 and resumed.mode == "world","fresh scene instance resumes repaired world")
	resumed.queue_free(); await process_frame
	check(disk.stage == 3 and Rules.valid(disk),"completed chapter survives disk reload")
	var bad = disk.duplicate(true); bad.slots[0] = bad.slots[1]
	check(not Rules.valid(bad),"corrupt duplicate stone rejected")
	bad = disk.duplicate(true); bad.swaps = []
	check(not Rules.valid(bad),"saved swap history must replay to saved layout")
	var f = FileAccess.open(test_path,FileAccess.WRITE); f.store_string("broken"); f.close()
	store.read_save()
	check(store.read_blocked and not store.write_save(disk) and FileAccess.get_file_as_string(test_path) == "broken","corrupt save preserved")
	var retry = Store.new(); retry.path = test_path+"/missing/save.json"
	check(not retry.write_save(disk),"write failure visible")
	retry.path = test_path
	check(retry.write_save(disk) and retry.error.is_empty(),"write retries when storage recovers")
	DirAccess.remove_absolute(test_path)
	game.queue_free(); await process_frame
	print("RESULT ",checks," checks; failures=",failures)
	quit(1 if failures else 0)

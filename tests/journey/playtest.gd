extends SceneTree

const Store = preload("res://scripts/journey/store.gd")
const SCENE = preload("res://game/journey.tscn")

class FaultStore extends Store:
	var saves_before_failure = -1
	var saves = 0
	func save() -> bool:
		saves += 1
		if saves_before_failure == 0:
			error = "模拟临时保存故障"; return false
		if saves_before_failure > 0: saves_before_failure -= 1
		return super.save()
var checks = 0
var failures = 0
var test_path = "/tmp/pixel-journey-v4-%d.json" % OS.get_process_id()
var game: Control

func _initialize() -> void: call_deferred("run")

func check(value: bool, title: String) -> void:
	checks += 1
	if value: print("PASS ",title)
	else: failures += 1; push_error(title)

func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
		event.position = point; event.pressed = pressed; root.push_input(event)

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code
		event.pressed = pressed; root.push_input(event)

func drain(chapter: Control) -> void:
	while chapter.mode == "dialogue": chapter.next_dialogue()

func wait_transition() -> void:
	for i in range(120):
		await process_frame
		if not game.transition: return

func wait_ready(encounter: Control) -> void:
	for i in range(200):
		if encounter.phase == "ready" and not encounter.busy: return
		await create_timer(0.01).timeout

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.15).timeout; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("/tmp/pixel-journey-v4-"+name+".png")

func new_game() -> void:
	game = SCENE.instantiate(); game.store = FaultStore.new(); game.store.path = test_path; game.animation_scale = 0.035
	root.add_child(game); await process_frame

func recreate() -> void:
	game.queue_free(); await process_frame
	await new_game()

func run() -> void:
	create_timer(55).timeout.connect(func(): push_error("Journey test exceeded 55-second watchdog"); quit(1))
	await new_game()
	check(game.page == "camp" and not is_instance_valid(game.active),"default journey opens at the camp map")
	check(game.store.state.chapter.stage == 0 and game.store.milestone() == 0,"new journey has its own fresh progress")
	await capture("camp")
	game.open_stage("encounter")
	check(not is_instance_valid(game.active),"guardian route cannot bypass seed delivery")
	click(Vector2(957,42)); await process_frame
	check(game.page == "journal","real map toolbar opens companion journal")
	await capture("journal-new")
	click(Vector2(1120,42)); await process_frame
	check(game.page == "settings","real toolbar opens settings")
	var slider = game.ui.get_node("Volume"); slider.value = 0.4
	click(Vector2(884,266)); await process_frame
	check(game.store.state.muted and game.sound.music.volume_db <= -80,"actual mute control silences camp audio")
	await capture("settings")
	await recreate()
	check(game.store.state.muted and is_equal_approx(game.store.state.volume,0.4),"volume and mute persist across a new journey instance")
	game.store.state.muted = false; game.store.save(); game.apply_audio()
	click(Vector2(216,620)); await wait_transition()
	check(game.active_kind == "chapter" and game.active.journey_mode,"actual continue button enters embedded forest story")
	var chapter = game.active; drain(chapter)
	chapter.interact("stele"); drain(chapter)
	chapter.interact("bridge"); drain(chapter)
	var home = game.home_button.get_global_rect().get_center()
	click(home); await process_frame
	check(not is_instance_valid(game.active) and game.store.state.chapter.clues.size() == 2,"return to camp preserves partial exploration")
	await recreate()
	click(Vector2(216,620)); await wait_transition(); chapter = game.active
	check(chapter.state.clues.size() == 2 and chapter.state.intro,"new instance resumes clues without repeating the intro")
	chapter.interact("keeper"); drain(chapter); chapter.open_puzzle()
	var first = [1,6,3,2,5,4]
	for i in range(6): chapter.select_stone(first[i]); await chapter.select_slot(i)
	chapter.run_power(); await create_timer(0.005).timeout
	game.return_to_camp()
	check(is_instance_valid(game.active) and chapter.busy,"camp navigation cannot interrupt a power animation")
	for i in range(200):
		if not chapter.busy: break
		await create_timer(0.01).timeout
	drain(chapter)
	check(chapter.state.stage == 1,"first triangle stage remains intact inside the journey")
	chapter.open_puzzle(); await chapter.select_slot(0); await chapter.select_slot(1)
	game.store.path = test_path+"/missing/state.json"
	game.return_to_camp(); await process_frame
	check(is_instance_valid(game.active) and game.error_panel.visible,"failed departure save keeps the playable scene and exposes retry")
	game.store.path = test_path
	click(game.retry_button.get_global_rect().get_center()); await process_frame
	check(game.store.error.is_empty() and game.store.state.chapter.swaps.size() == 1,"real retry saves the exact intermediate swap")
	game.return_to_camp(); await process_frame
	click(Vector2(216,620)); await wait_transition(); chapter = game.active; chapter.open_puzzle()
	check(chapter.state.swaps.size() == 1,"re-entering the forest preserves the swap budget")
	await chapter.select_slot(3); await chapter.select_slot(5)
	await chapter.run_power(); drain(chapter)
	await chapter.finish_chapter(); drain(chapter)
	check(game.store.state.chapter.stage == 3 and game.store.milestone() == 1,"seed delivery earns exactly one companion milestone")
	await capture("forest-complete")
	game.store.saves_before_failure = 0
	click(Vector2(779,547)); await process_frame
	check(game.active == chapter and game.error_panel.visible,"direct continuation save failure preserves the forest ending")
	game.store.saves_before_failure = 1
	var saves_before = game.store.saves
	click(Vector2(779,547)); await wait_transition()
	check(game.active_kind == "encounter" and game.active.journey_mode,"forest ending button continues directly to the guardian")
	check(game.store.saves == saves_before+1 and game.store.error.is_empty(),"continuation performs one departure save with no second fallible write")
	game.store.saves_before_failure = -1
	var encounter = game.active
	check(is_equal_approx(encounter.sound.volume,0.4) and game.sound.music.volume_db <= -80,"encounter inherits settings without overlapping camp music")
	click(Vector2(311,490)); await wait_ready(encounter)
	check(encounter.phase == "ready","embedded encounter accepts actual ground input")
	await capture("guardian")
	encounter.hint()
	await encounter.transfer(0,1)
	game.return_to_camp(); await process_frame
	await recreate()
	click(Vector2(216,620)); await wait_transition(); encounter = game.active
	check(encounter.state.left == 6 and encounter.state.hint == 1 and encounter.phase == "ready","encounter layout and assistance survive camp and full reload")
	await encounter.transfer(0,1); await encounter.cast_spell()
	check(encounter.phase == "reward" and not encounter.state.reward,"successful casting still requires deliberate reward claim")
	await capture("guardian-reward")
	game.store.path = test_path+"/missing/state.json"
	await encounter.claim_reward(); game.return_to_camp(); await process_frame
	check(is_instance_valid(game.active) and not game.store.state.returned,"failed final reward save prevents discarding the scene")
	game.store.path = test_path
	click(game.retry_button.get_global_rect().get_center()); await process_frame
	check(game.store.error.is_empty() and game.store.state.encounter.reward,"real retry persists claimed reward across the complete journey")
	click(encounter.cast_button.get_global_rect().get_center()); await process_frame
	check(not is_instance_valid(game.active) and game.store.state.returned,"actual reward continuation returns to a restored camp")
	check(game.store.milestone() == 2 and game.scenery.returned,"companion and seedling visibly reach their final milestone")
	await capture("homecoming")
	await recreate()
	check(game.store.state.returned and game.store.milestone() == 2,"completed journey restores atomically from one file")
	game.show_journal(); await capture("journal-complete")
	game.show_camp(); await game.open_stage("chapter"); chapter = game.active
	chapter.restart()
	check(chapter.state.stage == 3,"journey revisits cannot erase the completed forest")
	game.return_to_camp(); await process_frame; await game.open_stage("encounter"); encounter = game.active
	encounter.claim_reward(); encounter.confirm_replay(); encounter.restart()
	check(encounter.phase == "done" and encounter.state.reward and game.store.milestone() == 2,"revisiting guardian cannot duplicate rewards or reset journey state")
	click(encounter.mute_button.get_global_rect().get_center()); await process_frame
	check(game.store.state.muted,"encounter audio changes also save into the journey")
	key(KEY_M); await process_frame
	check(not game.store.state.muted and encounter.sound.enabled,"real M shortcut updates the same persisted audio setting")
	key(KEY_M); await process_frame
	game.return_to_camp(); await process_frame
	check(game.sound.music.volume_db <= -80,"returning to camp preserves encounter mute")
	await recreate()
	check(game.store.state.muted and game.sound.music.volume_db <= -80,"keyboard mute survives both camp return and a fresh instance")
	var good = game.store.state.duplicate(true)
	var bad = good.duplicate(true); bad.chapter = Store.Chapter.fresh()
	check(not Store.valid(bad),"cross-scene validation rejects rewards before the forest is complete")
	bad = Store.fresh(); bad.returned = true
	check(not Store.valid(bad),"homecoming requires the actual claimed reward")
	bad = good.duplicate(true); bad.volume = "0.7"
	check(not Store.valid(bad),"settings are validated at the persistence boundary")
	var file = FileAccess.open(test_path,FileAccess.WRITE); file.store_string("broken"); file.close()
	await recreate()
	check(game.store.protected and game.error_panel.visible,"damaged save visibly enters protected mode")
	click(Vector2(216,620)); game.open_stage("chapter"); game.retry_save()
	check(not is_instance_valid(game.active) and FileAccess.get_file_as_string(test_path) == "broken","protected save cannot be overwritten through entry or retry")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(test_path)
	print("RESULT ",checks," checks; failures=",failures)
	quit(1 if failures else 0)

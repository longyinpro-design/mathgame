extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var game: Control
var checks = 0
var failures = 0
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func point_click(point: Vector2) -> void:
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point*Vector2(root.size)/Vector2(1280,720); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
	await process_frame
func click(id: String) -> void:
	check(game.buttons.has(id) and not game.buttons[id].disabled,"usable "+id)
	if game.buttons.has(id): await point_click(game.buttons[id].get_global_rect().get_center())
	while game.busy: await create_timer(0.01).timeout
func combine(a: int, b: int, operator_index: int) -> void:
	await click("number_card_"+str(a)); await click("number_card_"+str(b)); await click("operator_"+str(operator_index))
func capture(name: String) -> void:
	await process_frame; RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://docs/playtest/fl07-24/"+name+".png")
func run() -> void:
	create_timer(70).timeout.connect(func(): push_error("24-point UI watchdog"); quit(1))
	for small in [false,true]:
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-24-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; game.time_scale = 0.02; root.add_child(game)
		for id in ["FL01","FL02","FL03","FL04","FL05","FL06"]: check(Scenarios.play(game.session,id),"prerequisite "+id)
		game.session.profile.story.node = "pre_FL07"
		check(Scenarios.send(game.session,{"kind":"start","level_id":"FL07","narrative":true,"node":"pre_FL07"}),"24-point starts at narrative puzzle")
		game.resume_story(); await process_frame; await capture("small-start" if small else "start")
		check(not game.buttons.has("final_order_0") and not game.buttons.has("test_candidate_0"),"old guessing and archive UI removed")
		await click("number_card_0"); await click("number_card_0")
		check(game.twenty_selection.is_empty(),"same card toggles selection rather than being used twice")
		await click("number_card_2"); await click("number_card_3"); await click("swap_operands"); await click("operator_3")
		var tokens = game.Session.Rules.TwentyFour.replay(game.session.catalog.levels.FL07.params,game.session.profile.active_run.state)
		check(tokens.back().n == 9 and tokens.back().d == 5,"real reversed division displays exact 9/5")
		await capture("fraction"); await click("undo")
		check(game.session.profile.active_run.state.steps.is_empty(),"undo returns consumed cards")
		await combine(0,1,0); await combine(0,1,0); await combine(0,1,0)
		check(game.session.profile.active_run.outcome == "active" and game.session.profile.active_run.state.steps.size() == 3,"wrong final value remains unsolved and recoverable")
		await capture("not-24"); await click("reset")
		await point_click(game.overlay.get_node("confirm").get_global_rect().get_center())
		check(game.session.profile.active_run.state.steps.is_empty(),"confirmed reset restores four cards")
		await combine(3,1,1); await combine(1,2,2)
		var saved_id: String = game.session.profile.active_run.run_id
		game.queue_free(); await create_timer(0.25).timeout
		game = Scene.instantiate(); game.save_path = path; game.time_scale = 0.02; root.add_child(game); await process_frame
		check(game.page == "challenge" and game.session.profile.active_run.run_id == saved_id and game.session.profile.active_run.state.steps.size() == 2,"reload resumes the same arithmetic and story run")
		game.session.repository.fail_at = "replace"
		await combine(1,0,1)
		check(game.modal and game.session.profile.active_run.outcome == "active" and "FL07" not in game.session.profile.progress.completed_levels,"save failure withholds victory and reward")
		game.session.repository.fail_at = ""
		await point_click(game.overlay.get_node("retry").get_global_rect().get_center())
		check(not game.modal and game.page == "story" and game.session.profile.story.node == "post_FL07" and game.session.profile.progress.journey_exp == 140,"retry commits 24-point victory once and continues story")
		if not game.story_stage.done: await click("story_skip")
		check(game.story_stage.result.has("steps"),"mill consequence uses actual 24-point expression")
		await capture("small-complete" if small else "complete")
		game.queue_free(); await create_timer(0.25).timeout; DirAccess.remove_absolute(path)
	# Legacy records historically allowed extra fields; presentation must use the
	# same legacy-first discriminator as GameSession.result_definition.
	var old = preload("res://tests/forest/twenty_four_test.gd").LegacySession.new()
	var legacy_path = "/tmp/pixel-24-ui-legacy-"+str(Time.get_ticks_usec())+".json"
	old.open(legacy_path)
	for id in ["FL01","FL02","FL03","FL04","FL05","FL06"]: Scenarios.play(old,id)
	old.profile.story.node = "pre_FL07"
	Scenarios.send(old,{"kind":"start","level_id":"FL07","narrative":true,"node":"pre_FL07"})
	Scenarios.rule(old,{"kind":"reveal","step":0}); Scenarios.rule(old,{"kind":"final_order","value":["minus1","plus3","double"]})
	old.profile.story.results.FL07.steps = []
	check(old.repository.write_profile(old.profile,old.validate),"legacy extra-field fixture remains valid")
	game = Scene.instantiate(); game.save_path = legacy_path; game.time_scale = 0.02; root.add_child(game)
	await create_timer(0.15).timeout
	check(not game.modal and game.page == "story" and game.story_stage.result.has("final_order"),"legacy result with steps still renders as legacy history")
	await capture("legacy-result")
	game.queue_free(); await create_timer(0.25).timeout; DirAccess.remove_absolute(legacy_path)
	print("FOREST FL07 UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

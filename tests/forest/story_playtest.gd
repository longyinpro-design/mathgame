extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
var game: Control
var checks = 0
var failures = 0
var path = "/tmp/pixel-story-window-"+str(Time.get_ticks_usec())+".json"
const CAPTURE = "res://docs/playtest/narrative"
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func click(point: Vector2) -> void:
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point*Vector2(root.size)/Vector2(1280,720); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; root.push_input(event)
	await process_frame
func press(id: String) -> void:
	check(game.buttons.has(id),"button "+id)
	if game.buttons.has(id):
		check(not game.buttons[id].disabled,"enabled "+id)
		await click(game.buttons[id].get_global_rect().get_center())
	while game.busy: await create_timer(0.005).timeout
func capture(name: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
func finish_scene(skip: bool) -> void:
	if not game.story_stage.done:
		if skip: await press("story_skip")
		else:
			while not game.story_stage.done: await create_timer(0.01).timeout
	check(game.page == "story" and game.story_stage.done,"scene reaches stable final frame")
func next(skip: bool) -> void:
	await finish_scene(skip); await press("story_continue")
func run() -> void:
	create_timer(80).timeout.connect(func(): push_error("story window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for skip in [false,true]:
		root.size = Vector2i(960,540) if skip else Vector2i(1280,720)
		game = Scene.instantiate(); game.save_path = path+(".skip" if skip else ""); game.time_scale = 0.12; root.add_child(game)
		await create_timer(0.1).timeout
		if skip:
			game.session.command({"kind":"settings","values":{"muted":true}},int(game.session.profile.revision)); game.refresh()
			check(not game.sound.enabled,"small-window whole sample is muted")
		check(game.page == "story" and game.session.profile.story.node == "pre_FL01","new journey opens story without camp/map")
		if not skip:
			game.story_stage.speed = 1.0
			await press("story_pause"); var before: float = game.story_stage.elapsed
			await create_timer(0.15).timeout; check(game.story_stage.elapsed == before,"pause freezes presentation")
			await press("story_pause")
			game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT); before = game.story_stage.elapsed
			await create_timer(0.15).timeout; check(game.story_stage.elapsed == before,"focus loss freezes presentation")
			game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
			await finish_scene(false); await capture("01-opening")
		if not skip:
			var stable = game.session.profile.story.node
			await create_timer(0.3).timeout; check(game.session.profile.story.node == stable,"finished action never auto-advances unread dialogue")
		await next(skip)
		check(game.page == "challenge" and game.session.profile.active_run.level_id == "FL01" and not game.walking,"story hands over real FL01 without walking")
		for i in range(6):
			await click(game.cargo_world.item_position(i)-Vector2(0,23))
			await click(game.cargo_world.zone_rect(1 if i < 3 else 2).get_center()+Vector2(0,37))
		if not skip: game.session.repository.fail_at = "replace"
		await press("travel")
		if not skip:
			check(game.modal and game.session.profile.story.node == "puzzle_FL01","UI failure holds old puzzle before reward")
			game.session.repository.fail_at = ""
			var retry = game.overlay.get_node("retry")
			await click(retry.get_global_rect().get_center())
			check(not game.modal and game.page == "story","retry closes modal and resumes committed delivery")
		check(game.page == "story" and game.session.profile.story.node == "post_FL01","FL01 success automatically continues delivery")
		await finish_scene(skip); await capture("02-delivery" if not skip else "skip-delivery")
		if not skip: game.session.repository.fail_at = "flush"
		await press("story_continue")
		if not skip:
			check(game.modal and game.session.profile.story.node == "post_FL01","UI failed scene confirmation keeps stop")
			game.session.repository.fail_at = ""
			await click(game.overlay.get_node("retry").get_global_rect().get_center())
			check(not game.modal and game.session.profile.story.node == "letter","scene retry opens next committed beat")
		await finish_scene(skip); await capture("03-letter")
		check(game.session.profile.story.node == "letter" and "seed_letter" in game.session.profile.inventory.unique_items,"letter follows actual seed reward")
		# Reopen in the middle of the letter; no reward/action repetition.
		var exp = game.session.profile.progress.journey_exp
		var save_path: String = game.save_path
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = save_path; game.time_scale = 0.12; root.add_child(game); await create_timer(0.1).timeout
		check(game.page == "story" and game.session.profile.story.node == "letter" and game.session.profile.progress.journey_exp == exp,"reopen retains letter stable stop")
		await next(skip); await next(skip)
		check(game.session.profile.story.node == "pre_FL02" and "mossling" not in game.session.profile.roster.owned,"mossling meets party before recruitment")
		await finish_scene(skip); await capture("04-meeting")
		await press("story_continue")
		if not skip:
			var main_run: String = game.session.profile.active_run.run_id
			# A side's mathematical actions already have a dedicated real-input suite.
			# This checks the new invitation and return UI using a solved side fixture.
			game.story_excursion("FL13"); await next(true)
			check(preload("res://tests/forest/scenarios.gd").play(game.session,"FL13"),"solve side fixture during active main")
			game.resume_story(); await next(true)
			check(game.page == "challenge" and game.session.profile.active_run.run_id == main_run,"completed side main button resumes original FL02 board")
		for source in [1,2,2]: await press("pile_"+str(source)); await press("pile_0")
		await press("try")
		check(game.page == "story" and game.session.profile.story.node == "post_FL02","real borrowing animation leads to consequence")
		await finish_scene(skip); await capture("05-three-gates")
		await press("story_continue"); await finish_scene(skip); await capture("06-mossling-joins")
		check(game.session.profile.story.node == "joined" and "mossling" in game.session.profile.roster.owned and game.story_stage.cast.mossling.position == Vector2(540,520),"mossling joins both durable roster and visible group")
		if not skip:
			root.size = Vector2i(960,540); await create_timer(0.1).timeout; await capture("07-small-join")
			root.size = Vector2i(1280,720)
		await press("story_continue"); await finish_scene(skip); await capture("08-village")
		await press("story_continue"); await next(skip)
		check(game.page == "challenge" and game.session.profile.active_run.level_id == "FL03","sample hands off to second act")
		game.queue_free(); await create_timer(0.1).timeout
		DirAccess.remove_absolute(save_path)
	print("FOREST STORY UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

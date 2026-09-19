extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
const MarketSample = preload("res://scripts/market/mk01_scene.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var game: Control
var checks = 0
var failures = 0
var replay_checked = false
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func click(id: String) -> void:
	var point = game.buttons[id].get_global_rect().get_center()
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.pressed = down; event.button_index = MOUSE_BUTTON_LEFT; root.push_input(event)
	await process_frame
func press(id: String) -> void:
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	check(game.buttons.has(id) and not game.buttons[id].disabled,"chapter choice "+id)
	if not game.buttons.has(id): return
	await click(id)
func capture(id: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://docs/playtest/narrative/chapter-"+id+".png")
func skip_beat() -> void:
	check(game.buttons.has("story_skip"),"skip offered for the current beat")
	# A beat can finish during the focus handshake, so the click only applies while it still runs.
	if not game.buttons.story_skip.disabled: await click("story_skip")
	check(game.story_stage.done,"beat settles before the next choice")
func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("chapter story UI watchdog"); quit(1))
	game = Scene.instantiate(); game.save_path = "/tmp/pixel-story-chapter-"+str(Time.get_ticks_usec())+".json"; game.time_scale = 0.02; root.add_child(game)
	await create_timer(0.1).timeout
	var counter = 0
	while game.session.profile.story.node != "end" and counter < 100:
		counter += 1
		var node: String = game.session.profile.story.node
		if node.begins_with("puzzle_"):
			# Existing mechanism window suites test every board with actual input.
			# Here fixture commands solve the board to verify each new narrative handoff/render.
			check(Scenarios.play(game.session,node.trim_prefix("puzzle_")),"chapter solution fixture "+node)
			game.resume_story()
		else:
			await skip_beat()
			if node == "post_branch": await press("choose_FL10" if "FL10" not in game.session.profile.progress.completed_levels else "choose_FL09")
			else:
				if node.begins_with("post_") or node in ["rest_growth","finale"]: await capture(node)
				if node == "post_FL09":
					check(game.story_stage.result.choice == game.session.profile.story.results.FL09.choice,"rock effect uses committed choice")
					if not replay_checked:
						replay_checked = true
						var original: Dictionary = game.session.profile.story.results.FL09.duplicate(true)
						game.story_excursion("FL09")
						await skip_beat()
						await press("story_continue")
						Scenarios.rule(game.session,{"kind":"guess","block":2})
						for block in range(4): Scenarios.rule(game.session,{"kind":"predict_block","block":block,"value":[8,11,11,8][block]})
						for block in range(4): Scenarios.rule(game.session,{"kind":"view_block","block":block})
						Scenarios.rule(game.session,{"kind":"choose","block":2}); Scenarios.rule(game.session,{"kind":"try"}); game.resume_story()
						check(game.story_stage.result.choice == 2 and game.session.profile.story.results.FL09 == original,"replay uses its own result without changing main receipt")
						await skip_beat()
						await press("story_continue")
						check(game.session.profile.story.node == "post_FL09" and game.story_stage.result == original,"return to same node restores original main visual")
						await skip_beat()
				if node == "post_FL10": check(game.story_stage.result.pairs == game.session.profile.story.results.FL10.pairs,"letters effect uses committed pairs")
				if node == "rest_growth":
					await press("story_grow"); check(game.session.profile.roster.grown,"growth at natural camp invitation")
					var reopened = game.Session.new(); check(reopened.open(game.save_path) and reopened.profile.roster.grown,"growth persists across reopen")
				await press("story_continue")
	check(game.session.profile.story.node == "end" and game.session.profile.progress.completed_levels.size() == 14,"chapter UI reaches finale without map movement")
	await skip_beat()
	await press("story_continue"); check(game.page == "camp","ending returns to camp")
	check(game.buttons.has("market") and game.buttons.market.text == "千灯集市 · 新的航路","finale camp offers the market crossing")
	await capture("market-camp")
	await press("market")
	check(game.session.profile.story.node == "voyage" and game.page == "story","crossing opens at the dock invitation")
	await skip_beat()
	await capture("voyage")
	check(game.buttons.story_continue.text == "启航 · 前往千灯集市","voyage action launches the market sample")
	await press("story_rest"); check(game.page == "camp" and game.buttons.market.text == "千灯集市 · 接货台","camp keeps the crossing after the invitation")
	# Back from the market dock the hub reopens at the camp instead of replaying the crossing.
	MarketSample.entry = "return"
	var back = Scene.instantiate(); back.save_path = game.save_path; root.add_child(back); await process_frame
	check(back.page == "camp" and back.session.profile.story.node == "voyage","returning from the market reopens at the camp")
	check(MarketSample.entry == "","market handshake is consumed once")
	back.queue_free(); await process_frame
	var path: String = game.save_path; game.queue_free(); await create_timer(0.25).timeout; DirAccess.remove_absolute(path)
	print("FOREST STORY CHAPTER UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

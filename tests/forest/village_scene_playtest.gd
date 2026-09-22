extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Session = preload("res://scripts/core/game_session.gd")
const OUT = "res://docs/playtest/village-integration/"
var game: Control
var checks = 0
var failures = 0
var path = "/tmp/pixel-village-scene-"+str(Time.get_ticks_usec())+".json"
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func capture(label: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OUT+label+".png")
func click(id: String, wait: bool = true) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var control = game.buttons[id]
	var point: Vector2 = control.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point*Vector2(root.size)/Vector2(1280,720); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; root.push_input(event)
	await process_frame
	if wait:
		while game.busy: await create_timer(0.005).timeout
func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("village watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	game = Scene.instantiate(); game.story_enabled = false; game.save_path = path; game.time_scale = 0.03; root.add_child(game)
	await process_frame
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for id in ["FL01","FL02"]: check(Scenarios.play(game.session,id),"prepare earlier chapter "+id)
	game.begin_challenge("FL03"); await process_frame
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size; await create_timer(0.2).timeout
		check(not game.world.ground.visible,"original road stays uncovered")
		check(game.world.actors.hero.pixel_scale == 0.42,"hero scale matches village doors")
		for i in range(3):
			check(game.buttons["pile_"+str(i)].get_rect().has_point(game.TransferStage.DOORS[i].get_center()),"click target belongs to painted door")
		await capture("initial-"+str(size.x))
		await click("pile_1"); await click("pile_0")
		check(game.session.profile.active_run.state.initial == [11,9,10],"viewport move at %s: actual %s" % [str(size),str(game.session.profile.active_run.state.initial)])
		await click("undo")
		check(game.session.profile.active_run.state.initial == [10,10,10],"undo restores real bag counts")
	root.size = Vector2i(1280,720); await create_timer(0.2).timeout
	await click("try")
	check(game.session.profile.active_run.outcome == "active","incorrect temporal equality stays active")
	await capture("not-equal")
	await click("trace_1"); await click("undo")
	check(game.session.profile.active_run.state.trace.is_empty(),"undo removes attempted trace")
	var stale_caption = false
	for label in game.ui.find_children("*","Label",true,false):
		if label.text.begins_with("粮账回看"): stale_caption = true
	check(not stale_caption,"undo returns to initial planning instead of a stale moment caption")
	for source in [1,1,2,2,2,2]: await click("pile_"+str(source)); await click("pile_0")
	game.time_scale = 1.0
	await click("try",false)
	while game.transfer_stage.flight < 0.25: await process_frame
	var tweens = get_processed_tweens()
	for tween in tweens: tween.pause()
	check(game.busy and game.world.grain_moving,"live cart and walking actor share the road")
	var counts = game.transfer_stage.visible_values()
	check(int(counts[0])+int(counts[1])+int(counts[2])+game.transfer_stage.quantity == 30,"warehouse and cart counts conserve grain")
	check(game.world.actors.hero.position.y >= 530 and game.world.actors.hero.position.y <= 540,"moving feet stay on original stone road")
	await capture("moving")
	var reopened = Session.new(); reopened.open(path)
	check(reopened.profile.active_run.outcome == "complete" and reopened.profile.active_run.state.trace == [[16,8,6],[12,12,6],[12,9,9]],"settlement is persisted before playback")
	for tween in tweens: tween.set_speed_scale(30); tween.play()
	game.time_scale = 0.03
	while game.busy: await create_timer(0.005).timeout
	check(game.transfer_stage.values == [12,9,9],"final door counts match actual result")
	await capture("complete")
	for i in range(3):
		await click("trace_"+str(i))
		check(game.transfer_stage.values == game.session.profile.active_run.state.trace[i],"each rewind uses its own trace row")
	await capture("rewind-second")
	# Use a copy of the actual completed receipt for presentation at the story boundary.
	var profile = game.session.profile.duplicate(true)
	profile.story.node = "post_FL03"; profile.story.results.FL03 = profile.active_run.state.duplicate(true)
	game.session.profile = profile; game.story_enabled = true; game.page = "story"; game.refresh()
	await process_frame
	game.story_stage.skip(); game.refresh(); await process_frame
	check(not game.story_stage.backdrop.ground.visible and game.story_stage.gates.scale == Vector2.ONE,"story keeps original village geometry")
	check(game.story_stage.gates.values == [12,9,9],"skip keeps the actual final grain result")
	await capture("story-result")
	root.size = Vector2i(960,540); await capture("story-result-960")
	for player in game.sound.get_children():
		if player is AudioStreamPlayer: player.stop()
	await create_timer(0.15).timeout
	game.queue_free(); await process_frame; DirAccess.remove_absolute(path)
	print("FOREST VILLAGE SCENE ",checks-failures,"/",checks," PASS")
	quit(1 if failures else 0)

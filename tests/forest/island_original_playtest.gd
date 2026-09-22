extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const OUT = "res://docs/playtest/island-original/"
var game: Control
var checks = 0
var failures = 0
var path = "/tmp/island-original-"+str(Time.get_ticks_usec())+".json"
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OUT+name+".png")
func click(id: String) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var b = game.buttons[id]
	var point = b.get_global_rect().get_center()*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var e = InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.position = point; e.pressed = down; root.push_input(e)
	await process_frame; await process_frame
func run() -> void:
	create_timer(95).timeout.connect(func(): push_error("original scenes watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	game = Scene.instantiate(); game.story_enabled = false; game.save_path = path; game.time_scale = 0.03; root.add_child(game)
	await process_frame
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for n in range(1,19): check(Scenarios.play(game.session,"FL%02d"%n),"fixture FL%02d"%n)
	for n in range(1,19):
		var id = "FL%02d"%n
		game.show_region(game.session.catalog.region_for(id)); await process_frame
		await click("object_"+id)
		while game.busy: await process_frame
		if game.page == "region" and game.session.feedback.contains("先停在这里"):
			await click("object_"+id)
			while game.busy: await process_frame
		check(game.page == "visit" and game.visit_id == id,id+" actual original prop enters its own revisit")
		if not game.buttons.has("practice"): quit(1); return
		await click("practice")
		while game.busy: await process_frame
		check(game.page == "challenge" and game.session.profile.active_run.level_id == id,id+" actual replay enters with valid persisted road coordinates: "+game.page+" / "+game.session.feedback)
		await capture(id+"-interaction")
		if id in game.Layout.DETAIL_LEVELS:
			var saved = JSON.stringify(game.session.profile)
			await click("scene_view")
			check(not game.scene_detail and not game.world.inspecting and not game.twenty_console.visible,id+" close inspection returns to original scene")
			for actor in game.world.actors.values():
				if not actor.visible: continue
				var y: float = actor.position.y
				var ranges = {"mill":[478,546],"post":[335,377],"heart":[460,574]}
				check(y >= ranges[game.region][0] and y <= ranges[game.region][1],id+" feet align with independently read original art")
				if game.region == "post": check(actor.position.x < 710,id+" party stays on near ledge")
				var point = game.Layout.point(game.region,game.REGIONS[game.region].levels.find(id))
				check(not Rect2(actor.position-Vector2(45,105),Vector2(90,105)).intersects(Rect2(point-Vector2(9,39),Vector2(18,18))),id+" scene marker is clear of the party")
			await capture(id+"-scene")
			root.size = Vector2i(960,540); await create_timer(0.2).timeout
			await click("inspect_mechanism")
			check(game.scene_detail and game.world.inspecting,id+" original prop reopens inspection at 960")
			check(JSON.stringify(game.session.profile) == saved,id+" changing camera does not change puzzle or save")
			root.size = Vector2i(1280,720); await create_timer(0.2).timeout
		check(Scenarios.play(game.session,id),"settle "+id)
		game.refresh()
		if id in ["FL04","FL07","FL17","FL18"]: await capture(id+"-complete")
	game.show_region("post"); game.go_camp(); await process_frame
	var before_walk: Vector2 = game.world.hero_position
	for down in [true,false]:
		var e = InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.position = Vector2(760,592); e.pressed = down; root.push_input(e)
	await create_timer(0.25).timeout
	check(game.world.hero_position.distance_to(before_walk) > 20 and game.world.destination.y == 592,"returning from post keeps camp ground walking active")
	# Story result images consume actual receipts, not invented winning numbers.
	for id in ["pre_FL02","joined","pre_FL04","post_FL04","pre_FL05","post_FL07","post_FL08","post_FL10","bridge","post_FL17","post_FL18","finale"]:
		game.session.profile.story.node = id
		var level: String = game.Story.scene(id).level
		if level != "":
			check(Scenarios.play(game.session,level),"story fixture "+level)
			game.session.profile.story.results[level] = game.session.profile.active_run.state.duplicate(true)
		game.page = "story"; game.refresh(); game.story_stage.skip(); game.refresh()
		await capture("story-"+id)
		if id == "bridge":
			check(game.story_stage.cast.hero.position.y >= 345 and game.story_stage.cast.hero.position.y <= 377,"bridge ends on original rock ledges")
			game.story_stage.elapsed = game.story_stage.duration*0.4; game.story_stage._update_pose(); await capture("story-bridge-growing")
	check(game.cargo_world.item_position(0).y < 620,"cargo staging stays inside original lower bridge")
	for player in game.sound.get_children():
		if player is AudioStreamPlayer:
			for connection in player.finished.get_connections(): player.finished.disconnect(connection.callable)
			player.stop(); player.stream = null
	await create_timer(0.15).timeout
	game.queue_free(); await process_frame; DirAccess.remove_absolute(path)
	print("FOREST ORIGINAL ISLAND ",checks-failures,"/",checks," PASS")
	quit(1 if failures else 0)

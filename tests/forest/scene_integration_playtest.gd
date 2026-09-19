extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var game: Control
var checks = 0
var failures = 0
var save_path = "/tmp/pixel-scene-integration-"+str(Time.get_ticks_usec())+".json"
const CAPTURE = "res://docs/playtest/scene-integration"

func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
	else: print("PASS ",label)

func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")

func story(id: String, progress: float = 1.0) -> void:
	game.session.profile.story.node = id; game.page = "story"; game.refresh()
	game.story_stage.paused = true; game.story_stage.elapsed = game.story_stage.duration*progress
	game.story_stage._update_pose(); game.story_stage.queue_redraw()
	await process_frame

func dispose_game() -> void:
	# Audio playback is released on the mixer thread. Drain it before this fast
	# fixture destroys/replaces the scene or quits the engine.
	for player in game.sound.get_children():
		if player is AudioStreamPlayer:
			# Disconnect automatic replay before draining the mixer, then release its
			# stream explicitly; stop alone leaves a pending startup/replay reference.
			for connection in player.finished.get_connections(): player.finished.disconnect(connection.callable)
			player.stop(); player.stream = null
	await create_timer(0.15).timeout
	game.queue_free(); await process_frame

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("scene integration watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	game = Scene.instantiate(); game.save_path = save_path; root.add_child(game)
	await process_frame
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	await story("pre_FL01")
	check(game.story_stage.cargo.visible,"opening uses actual cargo docks")
	check(not game.story_stage.cargo.render_people,"cargo story actors have one visual owner")
	check(game.story_stage.cast.hero.position.distance_to(game.story_stage.cargo.position+game.story_stage.cargo.item_position(1)*game.story_stage.cargo.scale) < 1.5,"hero stands at actual lower dock item anchor")
	await capture("01-opening")
	check(Scenarios.play(game.session,"FL01"),"fixture transports real cargo")
	game.session.profile.story.results["FL01"] = game.session.profile.active_run.state.duplicate(true)
	await story("post_FL01",0.48); await capture("02-handoff-mid")
	await story("post_FL01",1.0)
	check(game.story_stage.letter_owner == "hero","finished handoff belongs to hero")
	check(game.story_stage.handoff.distance_to(game.story_stage.cast.hero.hand_position()) < 0.01,"letter ends in actual receiving hand")
	check(game.story_stage.cargo.state == game.session.profile.story.results.FL01,"delivery uses durable real cargo result")
	await capture("03-delivery")
	await story("letter"); await capture("04-letter")
	await story("pre_FL02"); await capture("05-gates-story")
	check(Scenarios.play(game.session,"FL02"),"fixture restores three gates")
	game.session.profile.story.results["FL02"] = game.session.profile.active_run.state.duplicate(true)
	await story("joined"); await capture("06-joined")
	check(game.story_stage.gates.visible and game.story_stage.gates.values == game.session.profile.story.results.FL02.trace.back(),"joining preserves the actual restored gates")
	check(game.story_stage.cast.mossling.position == Vector2(540,520),"joined companion reaches stable grounded mark")
	var actor = game.story_stage.cast.hero
	actor.place_at(Vector2(250,461),false,true)
	var before: float = actor.stride_distance
	actor.place_at(Vector2(298,461),true)
	check(is_equal_approx(actor.stride_distance-before,48.0),"walk phase advances with distance")
	actor.place_at(Vector2(298,461),false)
	check(actor.action == "idle","zero movement stops walking")
	for id in ["FL03","FL04","FL05","FL06"]:
		check(Scenarios.play(game.session,id),"fixture "+id)
		game.session.profile.story.results[id] = game.session.profile.active_run.state.duplicate(true)
	await story("post_FL04"); await capture("07-village-restored")
	check("FL04" in game.story_stage.backdrop.completed,"story retains actual restored village")
	await story("pre_FL07"); await capture("08-mill-story")
	Scenarios.send(game.session,{"kind":"start","level_id":"FL07"})
	game.page = "challenge"; game.region = "mill"; game.refresh(); await capture("09-mill-console")
	Scenarios.rule(game.session,{"kind":"combine","left":3,"right":1,"op":"-"})
	game.refresh(); await capture("10-mill-mid")
	root.size = Vector2i(960,540); await capture("11-small-console")
	await story("letter"); await capture("12-small-letter")
	root.size = Vector2i(1280,720)
	await story("bridge",0.4)
	check(game.story_stage.cast.hero.action != "walk","party waits while root bridge grows")
	await capture("13-bridge-growing")
	await story("bridge",0.8); await capture("14-bridge-crossing")
	for id in ["story_skip","story_pause"]:
		check(game.ui.get_node(id).position.y < 160,"bridge control stays above the crossing: "+id)
	await story("bridge",1.0)
	check(game.story_stage.cast.hero.position.x > 1030,"party reaches the far bank after bridge growth")
	await dispose_game()
	game = Scene.instantiate(); game.save_path = save_path+".cargo"; game.story_enabled = false; root.add_child(game)
	await process_frame
	check(Scenarios.send(game.session,{"kind":"start","level_id":"FL01"}),"independent cargo fixture starts")
	if game.session.profile.active_run == null or game.session.profile.active_run.level_id != "FL01": quit(1); return
	for i in [0,1,2]: Scenarios.rule(game.session,{"kind":"move","item":i,"target":1})
	for i in [3,4,5]: Scenarios.rule(game.session,{"kind":"move","item":i,"target":2})
	game.page = "challenge"; game.region = "treetop"; game.refresh()
	var old_places: Array = game.session.profile.active_run.state.places.duplicate()
	game.rule({"kind":"travel"})
	await create_timer(0.15).timeout
	check(game.busy and game.cargo_world.state.places == old_places,"in-flight visuals keep people inside their real basket")
	check(game.session.profile.active_run.outcome == "complete","successful trip is durable before its presentation")
	await capture("15-cargo-moving")
	while game.busy: await create_timer(0.03).timeout
	check(game.cargo_world.offsets.is_empty() and not game.cargo_world.moving,"arrival clears transient offsets")
	await capture("16-cargo-landed")
	var legacy = game.session.profile.duplicate(true)
	legacy.erase("story"); legacy.active_run = null
	var old_path = save_path+".legacy"
	var file = FileAccess.open(old_path,FileAccess.WRITE); file.store_string(JSON.stringify(legacy)); file.close()
	await dispose_game()
	game = Scene.instantiate(); game.save_path = old_path; root.add_child(game)
	await process_frame; await process_frame
	check(game.page == "story" and game.session.profile.story.node == "post_FL01","real old-save migration resumes completed delivery")
	check(game.story_stage.legacy_cargo_recap and not game.story_stage.cargo.visible,"old completion without receipt never shows a fresh load")
	check(game.session.profile.progress == legacy.progress and game.session.profile.inventory == legacy.inventory,"legacy recap preserves progression and inventory")
	await capture("17-legacy-delivery")
	var backup: String = game.session.repository.migration_backup
	await dispose_game()
	DirAccess.remove_absolute(old_path)
	if not backup.is_empty(): DirAccess.remove_absolute(backup)
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_path+".cargo")
	print("FOREST SCENE INTEGRATION ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

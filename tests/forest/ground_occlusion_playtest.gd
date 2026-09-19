extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const OUTPUT = "res://docs/playtest/ground-occlusion"
var game: Control
var checks = 0
var failures = 0
var save_path = "/tmp/pixel-ground-occlusion-"+str(Time.get_ticks_usec())+".json"

func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func body(actor: Node2D) -> Rect2:
	# Include every supplied animation frame, so a talking/celebrating head cannot
	# enter the controls even when idle happens to fit. Metadata is the draw input.
	var result = Rect2()
	var first = true
	for frame in actor.metadata[actor.identity].frames:
		var r: Array = frame.region; var pivot: Array = frame.pivot
		var local = Rect2(-Vector2(pivot[0],pivot[1])*actor.pixel_scale,Vector2(r[2],r[3])*actor.pixel_scale)
		if actor.facing_left: local.position.x = -local.end.x
		var rect = actor.get_global_transform()*local
		result = rect if first else result.merge(rect); first = false
	return result

func inspect(id: String, state: String) -> void:
	# Stress every owned companion in the view without altering the saved party.
	game.world.party = game.session.profile.roster.owned.duplicate()
	await process_frame; await process_frame
	if not game.world.visible and not game.battle_world.visible: return # Cargo keeps its actual in-basket actors.
	var stage = game.world if game.world.visible else game.battle_world
	var feedback_hits = []
	for node in game.ui.find_children("*","Control",true,false):
		if node == game.message or not node.is_visible_in_tree() or not (node is Label or node is BaseButton or node is LineEdit): continue
		if node is Label and node.text.is_empty(): continue
		if game.message.get_global_rect().intersects(node.get_global_rect()): feedback_hits.append(str(node.name))
	check(feedback_hits.is_empty(),id+" "+state+" feedback avoids board controls: "+str(feedback_hits))
	for actor in stage.actors.values():
		if not actor.visible: continue
		var rect = body(actor)
		var hits = []
		for node in game.ui.find_children("*","Control",true,false):
			if not node.is_visible_in_tree() or not (node is Label or node is BaseButton or node is LineEdit): continue
			if node is Label and node.text.is_empty(): continue
			if str(node.name).begins_with("pile_"): continue # Transparent door hotspot is part of the world, not an occluding control.
			if rect.intersects(node.get_global_rect()): hits.append(str(node.name))
		check(hits.is_empty(),id+" "+state+" "+actor.identity+" is clear of text/controls: "+str(hits))
		check(rect.end.y < 645 and rect.position.y > 250,id+" "+actor.identity+" animation fits on the visible scene")
		check((actor.position.y >= 530 and actor.position.y <= 545 and not stage.ground.visible) if id == "FL03" else (actor.position.y >= 345 and actor.position.y <= 605),id+" feet stay on painted terrain")

func capture(name: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")

func run() -> void:
	create_timer(95).timeout.connect(func(): push_error("ground occlusion watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = Scene.instantiate(); game.story_enabled = false; game.save_path = save_path; game.time_scale = 0.03; root.add_child(game)
	await process_frame
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for i in range(1,19): check(Scenarios.play(game.session,"FL%02d"%i),"prepare FL%02d"%i)
	for i in range(2,19):
		var id = "FL%02d"%i
		check(Scenarios.send(game.session,{"kind":"start","level_id":id}),"start "+id)
		game.page = "challenge"; game.region = game.session.catalog.region_for(id); game.refresh()
		for size in [Vector2i(1280,720),Vector2i(960,540)]:
			root.size = size; await inspect(id,"initial "+str(size.x))
			if id in ["FL03","FL04","FL07","FL08","FL15","FL17","FL18"]: await capture(id+"-initial-"+str(size.x))
		check(Scenarios.play(game.session,id),"solve "+id)
		game.refresh()
		for size in [Vector2i(1280,720),Vector2i(960,540)]:
			root.size = size; await inspect(id,"result "+str(size.x))
			if id == "FL03": await capture(id+"-result-"+str(size.x))
	# Exercise actual failed battle actions, not invented presentation states.
	check(Scenarios.send(game.session,{"kind":"start","level_id":"FL17"}),"start exhausted battle fixture")
	for action in [{"kind":"transfer","card":1,"from":1,"to":2},{"kind":"transfer","card":2,"from":2,"to":0},{"kind":"transfer","card":3,"from":0,"to":1}]:
		check(Scenarios.rule(game.session,action),"exhaustion action accepted")
	check(game.session.profile.active_run.state.battle_phase == "exhausted","real exhausted state")
	game.region = "heart"; game.refresh()
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size; await inspect("FL17","exhausted"); await capture("FL17-exhausted-"+str(size.x))
	check(Scenarios.send(game.session,{"kind":"reset","confirmed":true}) and Scenarios.play(game.session,"FL17"),"restore solved battle after failure fixture")
	check(Scenarios.send(game.session,{"kind":"start","level_id":"FL18"}),"start missed battle fixture")
	check(Scenarios.rule(game.session,{"kind":"probe","value":6}),"real first probe")
	if game.session.profile.active_run.state.battle_phase == "probing":
		check(Scenarios.rule(game.session,{"kind":"probe","value":2}),"real second distinguishing probe")
	check(Scenarios.rule(game.session,{"kind":"finish","value":2}),"real missed finisher")
	check(game.session.profile.active_run.state.battle_phase == "missed","real missed state")
	game.refresh()
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size; await inspect("FL18","missed"); await capture("FL18-missed-"+str(size.x))
	# Catch draw-order regressions in the actual opening of a moving seed flight.
	check(Scenarios.send(game.session,{"kind":"reset","confirmed":true}),"reset for live flight")
	game.time_scale = 1.0; game.refresh(); game.rule({"kind":"probe","value":6})
	await create_timer(0.03).timeout
	var tweens = get_processed_tweens()
	for tween in tweens: tween.pause()
	var world = game.battle_world
	var point: Vector2 = world.actors.hero.hand_position().lerp(Vector2(686,265),world.flight)-Vector2(0,sin(world.flight*PI)*123)
	check(game.busy and world.flight >= 0 and point.y > 390 and point.y < 470,"live flight begins at the grounded hero hand")
	await capture("FL18-seed-flight-"+str(root.size.x))
	var pixels = root.get_texture().get_image()
	var sample = Vector2i(point*Vector2(pixels.get_size())/Vector2(1280,720))
	var visible_seed = false
	for dx in range(-2,3):
		for dy in range(-2,3):
			var color = pixels.get_pixel(sample.x+dx,sample.y+dy)
			if color.r > 0.97 and color.g > 0.9 and color.b > 0.65: visible_seed = true
	check(visible_seed,"seed highlights are visible over the original arena during flight")
	for tween in tweens: tween.set_speed_scale(20); tween.play()
	while game.busy: await create_timer(0.01).timeout
	for player in game.sound.get_children():
		if player is AudioStreamPlayer: player.stop()
	await create_timer(0.15).timeout
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(save_path)
	print("FOREST GROUND OCCLUSION ",checks-failures,"/",checks," PASS")
	quit(1 if failures else 0)

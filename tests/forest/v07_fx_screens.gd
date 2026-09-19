extends SceneTree
const Scene = preload("res://game/forest_release.tscn")
var game: Control
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root); call_deferred("run")
func capture(name: String) -> void:
	for i in range(3): await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://docs/playtest/v07-presentation/"+name+".png")
func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("fx watchdog"); quit(1))
	game = Scene.instantiate(); game.save_path = "/tmp/pixel-v07-fx.json"; game.time_scale = 0.02; root.add_child(game)
	for id in ["FL01","FL02","FL03","FL04","FL05","FL06","FL07","FL08","FL09","FL10","FL11","FL12","FL17"]: 
		if not preload("res://tests/forest/scenarios.gd").play(game.session,id): print("seed fail ",id)
	await process_frame
	game.session.profile.story.results["FL17"] = {"energy":[7,7,7]}
	game.session.profile.story.results["FL18"] = {"finisher":[7,20],"seed_balance":0}
	game.session.profile.story.node = "post_FL17"
	game.resume_story(); await capture("story-fl17-result")
	await create_timer(1.2).timeout; await capture("story-fl17-done")
	game.session.profile.story.node = "post_FL18"
	game.resume_story(); await create_timer(0.9).timeout; await capture("story-fl18-sprout")
	await create_timer(1.5).timeout; await capture("story-fl18-done")
	print("V07 FX DONE"); quit(0)

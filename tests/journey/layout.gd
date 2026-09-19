extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://game/journey.tscn").instantiate()
	var path = "/tmp/pixel-journey-layout-%d.json" % OS.get_process_id()
	game.store.path = path; root.add_child(game)
	root.size = Vector2i(960,540)
	await create_timer(0.25).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("/tmp/pixel-journey-v4-small-window.png")
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
		# Native window coordinates at 75%, exercising the configured canvas stretch.
		event.position = Vector2(951,44)*0.75; event.pressed = pressed; root.push_input(event)
	await process_frame
	var okay = game.page == "journal"
	print("PASS scaled 960x540 window input" if okay else "FAIL scaled 960x540 window input")
	await create_timer(0.15).timeout; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("/tmp/pixel-journey-v4-small-journal.png")
	game.queue_free(); await create_timer(0.2).timeout
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	quit(0 if okay else 1)

extends SceneTree
var checks = 0
var failures = 0
var redraws = 0

func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)

func hold() -> void: await create_timer(0.12).timeout

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("market presentation watchdog"); quit(1))
	for id in ["mk01","mk13","mk14","mk18"]:
		var game: Control = load("res://game/market_"+id+".tscn").instantiate()
		game.save_path = "/tmp/pixel-market-presentation-"+id+"-"+str(Time.get_ticks_usec())+".json"; root.add_child(game)
		if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
		await hold()
		var state = game.state.duplicate(true)
		var saved = FileAccess.get_file_as_bytes(game.save_path) if FileAccess.file_exists(game.save_path) else PackedByteArray()
		game.world.draw.connect(func(): redraws += 1)
		for reason in ["paused","modal","focused","hidden"]:
			# Establish focus before testing each independent freeze condition.
			root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			match reason:
				"paused": game.paused = true
				"modal": game.modal = true
				"focused": game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
				"hidden": game.hide()
			await hold(); RenderingServer.force_draw(false)
			var clock: float = game.world.clock; var elapsed: float = game.elapsed
			redraws = 0; await hold(); RenderingServer.force_draw(false)
			check(game.world.clock == clock and game.elapsed == elapsed,id+" freezes world and host during "+reason)
			check(redraws == 0,id+" retains draw commands during "+reason)
			match reason:
				"paused": game.paused = false
				"modal": game.modal = false
				"focused": game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
				"hidden": game.show()
			await hold()
			check(game.world.clock > clock,id+" resumes after "+reason)
		check(game.state == state,id+" presentation controls do not mutate rules")
		var after = FileAccess.get_file_as_bytes(game.save_path) if FileAccess.file_exists(game.save_path) else PackedByteArray()
		check(after == saved,id+" presentation controls do not rewrite save")
		game.queue_free(); await process_frame; await process_frame
	print("MARKET HUB WINDOW ",checks-failures,"/",checks," PASS")
	quit(1 if failures else 0)

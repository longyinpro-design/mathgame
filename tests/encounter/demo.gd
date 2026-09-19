# Normal-speed authored input trace: observe, fail, adjust, succeed, claim.
# Dedicated temporary progress; deliberately contains solutions.
extends SceneTree
func _initialize() -> void: call_deferred("run")
func pause(value: float) -> void: await create_timer(value).timeout
func mouse(point: Vector2, down: bool) -> void:
	var e = InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.position = point; e.pressed = down; root.push_input(e)
func drag(game: Node) -> void:
	var start = game.scene.crystal_position(0,0)
	mouse(start,true)
	for i in range(45):
		var e = InputEventMouseMotion.new(); e.position = start.lerp(Vector2(1050,340),i/44.0); root.push_input(e)
		await pause(1.0/30.0)
	mouse(Vector2(1050,340),false)
	await pause(0.8)
func run() -> void:
	var game = load("res://game/encounter.tscn").instantiate()
	game.store.path = "/tmp/encounter-v3-demo-%d.json" % OS.get_process_id()
	root.add_child(game)
	await pause(2)
	mouse(Vector2(315,480),true); mouse(Vector2(315,480),false)
	while game.phase != "ready": await pause(0.1)
	await pause(5)
	await game.cast_spell()
	await pause(4)
	game.hint()
	await pause(5)
	await drag(game)
	await pause(4)
	await game.cast_spell()
	await pause(4)
	await drag(game)
	await pause(4)
	await game.cast_spell()
	await pause(5)
	await game.claim_reward()
	await pause(5)
	print("DEMO complete, events=",game.demo_events)
	DirAccess.remove_absolute(game.store.path)
	game.queue_free(); await process_frame
	quit()

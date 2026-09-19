# Engine-rendered animation showcase. Uses a dedicated temporary save, never player progress.
extends SceneTree
func _initialize() -> void: call_deferred("run")
func pause(seconds: float) -> void: await create_timer(seconds).timeout
func run() -> void:
	var game = load("res://game/chapter.tscn").instantiate()
	game.store.path = "/tmp/forest-chapter-demo-%d.json" % OS.get_process_id()
	root.add_child(game)
	await pause(1)
	while game.mode == "dialogue": game.next_dialogue()
	game.go_to("stele")
	await pause(2)
	while game.mode == "dialogue": game.next_dialogue()
	for id in ["bridge","keeper"]:
		game.interact(id)
		while game.mode == "dialogue": game.next_dialogue()
	game.go_to("core")
	await pause(2)
	var answer = [1,6,3,2,5,4]
	for i in range(6):
		game.select_stone(answer[i]); await game.select_slot(i)
	await pause(1)
	await game.run_power()
	await pause(1)
	while game.mode == "dialogue": game.next_dialogue()
	await pause(1)
	game.open_puzzle()
	await game.select_slot(0); await game.select_slot(1)
	await game.select_slot(3); await game.select_slot(5)
	await pause(1)
	await game.run_power()
	while game.mode == "dialogue": game.next_dialogue()
	game.go_to("gate")
	await pause(6)
	while game.mode == "dialogue": game.next_dialogue()
	await pause(2)
	DirAccess.remove_absolute(game.store.path)
	quit()

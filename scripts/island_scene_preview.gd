extends SceneTree
# Isolated art-review profile; unlock through real commands without touching the player's save.
const Scenarios = preload("res://tests/forest/scenarios.gd")
func _initialize() -> void: call_deferred("open_preview")
func open_preview() -> void:
	var game = preload("res://game/forest_release.tscn").instantiate()
	game.story_enabled = false
	game.save_path = "user://profiles/island-original-1/save-v1.json"
	root.add_child(game)
	if game.session.profile.is_empty(): return
	for n in range(1,19):
		var id = "FL%02d"%n
		if id not in game.session.profile.progress.completed_levels and not Scenarios.play(game.session,id):
			push_error("Island preview setup failed at "+id); quit(1); return
	game.show_region("mill")
	root.title = "数字群岛 · 全岛原图试玩（独立存档）"

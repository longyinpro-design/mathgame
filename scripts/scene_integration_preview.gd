extends SceneTree
# Separate playable profile: the official journey and previous story sample stay intact.
func _initialize() -> void:
	call_deferred("open_preview")

func open_preview() -> void:
	var game = preload("res://game/forest_release.tscn").instantiate()
	game.save_path = "user://profiles/scene-integration-1/save-v1.json"
	root.add_child(game)
	root.title = "数字群岛 · 森林岛场景融合试玩"

extends SceneTree
# A separate, persistent sample profile leaves the player's official journey intact.
func _initialize() -> void:
	call_deferred("open_sample")

func open_sample() -> void:
	var game = preload("res://game/forest_release.tscn").instantiate()
	game.save_path = "user://profiles/story-sample-1/save-v1.json"
	root.add_child(game)
	root.title = "数字群岛 · 森林来信样板"

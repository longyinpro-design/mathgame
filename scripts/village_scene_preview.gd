extends SceneTree
# Development entry only: prepare the first two quests through real session commands.
# This separate profile never reads or overwrites the player's official journey.
const Scenarios = preload("res://tests/forest/scenarios.gd")
func _initialize() -> void: call_deferred("open_preview")
func open_preview() -> void:
	var game = preload("res://game/forest_release.tscn").instantiate()
	game.save_path = "user://profiles/village-original-1/save-v1.json"
	root.add_child(game)
	var session = game.session
	if session.profile.is_empty(): return
	if session.profile.progress.completed_levels.is_empty():
		for step in range(16):
			var node: String = session.profile.story.node
			if node == "village_arrive": break
			var beat = game.Story.scene(node)
			var ok: bool
			if beat.kind == "puzzle": ok = Scenarios.play(session,beat.level)
			elif beat.get("next","").begins_with("puzzle_"):
				ok = Scenarios.send(session,{"kind":"start","level_id":beat.next.trim_prefix("puzzle_"),"narrative":true,"node":node})
			else: ok = Scenarios.send(session,{"kind":"story_advance","node":node})
			if not ok: push_error("Village preview setup failed at "+node); quit(1); return
	game.resume_story()
	root.title = "数字群岛 · 三粮仓原图融合样板"

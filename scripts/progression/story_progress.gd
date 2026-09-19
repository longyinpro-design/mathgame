extends RefCounted
const Story = preload("res://scripts/content/story_catalog.gd")
const SIDES = ["FL13","FL14","FL15","FL16"]

static func fresh() -> Dictionary:
	return {"version":1,"node":"pre_FL01","seen":[],"choices":[],"return_node":"","run_id":"","excursion":"","return_run_id":"","results":{}}

static func next_main(completed: Array) -> String:
	for id in Story.MAIN:
		if id not in completed: return "pre_"+id
	return "end"

static func migrate(profile: Dictionary) -> Dictionary:
	var value = fresh()
	var completed: Array = profile.progress.completed_levels
	if profile.active_run != null and profile.active_run.outcome == "complete": value.results[profile.active_run.level_id] = profile.active_run.state.duplicate(true)
	value.node = next_main(completed)
	# An unfinished active challenge takes priority, including a side quest or replay.
	var run = profile.active_run
	if run == null or run.outcome != "active":
		run = profile.suspended_runs.get(value.node.trim_prefix("pre_"),run)
	if run != null and run.outcome == "active":
		if run.level_id in SIDES or run.level_id in completed:
			value.return_node = value.node; value.excursion = run.level_id
		value.node = "puzzle_"+run.level_id; value.run_id = run.run_id
	elif value.node != "end" and not completed.is_empty():
		# An old receipt proves completion, never that the new scene was watched.
		for id in Story.MAIN:
			if id in completed: value.node = "post_"+id
	if value.node == "end": value.node = "legacy_recap"
	return value

static func valid_node(id: Variant, profile: Dictionary, catalog: RefCounted) -> bool:
	if not id is String: return false
	var scene = Story.scene(id)
	if scene.is_empty(): return false
	var completed: Array = profile.progress.completed_levels
	if not scene.level.is_empty():
		if not catalog.available(scene.level,completed): return false
		if id.begins_with("post_") and scene.level not in completed: return false
	var gate: String = {"letter":"FL01","light_path":"FL01","joined":"FL02","village_arrive":"FL02","rest_village":"FL04","post_branch":"FL08","rest_post":"FL11","rest_growth":"FL12","bridge":"FL17","finale":"FL18","end":"FL18","legacy_recap":"FL18","voyage":"FL18"}.get(id,"")
	if id == "rest_post": return "FL09" in completed and "FL10" in completed
	return gate == "" or gate in completed

static func valid(value: Variant, profile: Dictionary, catalog: RefCounted) -> bool:
	if not value is Dictionary or not value.has_all(["version","node","seen","choices","return_node","run_id","excursion","return_run_id","results"]): return false
	if not value.version is int or value.version != 1 or not valid_node(value.node,profile,catalog): return false
	if not value.seen is Array or not value.choices is Array or not value.return_node is String or not value.run_id is String or not value.excursion is String or not value.return_run_id is String: return false
	var seen = []
	for id in value.seen:
		if not valid_node(id,profile,catalog) or id in seen or Story.scene(id).kind != "scene": return false
		seen.append(id)
	for id in value.choices:
		if id not in ["FL09","FL10"]: return false
	if value.choices.size() > 2 or (value.choices.size() == 2 and value.choices[0] == value.choices[1]): return false
	if value.return_node != "":
		if not valid_node(value.return_node,profile,catalog) or value.excursion not in catalog.levels: return false
		if Story.scene(value.node).level != value.excursion: return false
		if Story.scene(value.return_node).kind == "puzzle":
			if not matches_run(profile,Story.scene(value.return_node).level,value.return_run_id): return false
		elif value.return_run_id != "": return false
	elif value.excursion != "" or value.return_run_id != "": return false
	if Story.scene(value.node).kind == "puzzle":
		var level: String = Story.scene(value.node).level
		if not matches_run(profile,level,value.run_id): return false
	elif value.run_id != "": return false
	return true

static func advance(profile: Dictionary) -> String:
	var state: Dictionary = profile.story
	var node: String = state.node
	if node == "end" or node == "post_branch" or Story.scene(node).kind != "scene": return ""
	if state.excursion != "" and node == "post_"+state.excursion:
		var result: String = state.return_node
		state.return_node = ""; state.excursion = ""; state.run_id = state.return_run_id; state.return_run_id = ""
		return result
	var next: String = Story.scene(node).next
	if next != "": return next
	var id = node.trim_prefix("post_")
	match id:
		"FL03": return "pre_FL04"
		"FL04": return "rest_village"
		"FL05": return "pre_FL06"
		"FL06": return "pre_FL07"
		"FL07": return "pre_FL08"
		"FL08": return "post_branch"
		"FL09","FL10": return "rest_post" if "FL09" in profile.progress.completed_levels and "FL10" in profile.progress.completed_levels else "post_branch"
		"FL11": return "pre_FL12"
		"FL12": return "rest_growth"
		"FL17": return "bridge"
		"FL18": return "finale"
	return ""

static func settle(profile: Dictionary, level: String) -> void:
	if profile.story.run_id != profile.active_run.run_id: return
	if profile.story.excursion == "" or not profile.story.results.has(level): profile.story.results[level] = profile.active_run.state.duplicate(true)
	profile.story.node = "post_"+level; profile.story.run_id = ""

static func matches_run(profile: Dictionary, level: String, run_id: String) -> bool:
	var run = profile.active_run
	if run == null or run.run_id != run_id: run = profile.suspended_runs.get(level)
	return run != null and run.run_id == run_id and run.level_id == level and run.outcome == "active"

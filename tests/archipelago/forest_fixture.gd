extends SceneTree
const Forest = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Legacy = preload("res://scripts/archipelago/legacy_evidence.gd")
func _initialize() -> void:
	var session = Forest.new()
	var path = "res://docs/playtest/archipelago/proofs/forest.json"
	assert(session.open(path))
	for n in range(1,19):
		var id = "FL%02d"%n
		if id not in session.profile.progress.completed_levels: assert(Scenarios.play(session,id),id)
		assert(session.validate(session.profile),id+" saved profile valid")
	var found = Legacy.collect({"forest":path})
	for n in range(1,19): assert(found.has("FL%02d"%n),"actual forest proof exists")
	print("FOREST CAMPAIGN FIXTURE 18 actual rule completions")
	quit()

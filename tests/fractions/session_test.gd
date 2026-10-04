extends SceneTree
const Catalog=preload("res://scripts/fractions/catalog.gd")
const Campaign=preload("res://scripts/archipelago/session.gd")
func _init():
	var paths:Dictionary=Catalog.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fractions/solutions.json")))
	for id in Catalog.ids():
		var s=Campaign.new();s.allow_locked=true
		var path="/tmp/fractions-session-%s-%d/save.json"%[id,Time.get_ticks_usec()]
		assert(s.open(path));assert(s.start(id))
		for beat in Catalog.definition(id).intro: assert(s.advance())
		for action in paths[id]:assert(s.edit_board(action))
		assert(s.submit())
		var loaded=Campaign.new();loaded.allow_locked=true
		assert(loaded.open(path));assert(id in loaded.profile.completed)
		assert(loaded.profile.claimed_rewards.count(Catalog.definition(id).reward.id)==1)
		assert(loaded.profile.runs[id].board==s.profile.runs[id].board)
		print(id," REPOSITORY PASS")
	print("FRACTIONS ALL18 REPOSITORY PASS")
	quit()

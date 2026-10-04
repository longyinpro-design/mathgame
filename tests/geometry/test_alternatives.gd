extends SceneTree
const C=preload("res://scripts/geometry/catalog.gd")
const R=preload("res://scripts/geometry/rules.gd")
const N=preload("res://scripts/content/content_catalog.gd")
func _initialize():
	var data=N.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/geometry/alternatives.json")))
	var count=0;var failures=0
	for id in data.states:
		var r=R.new(C.definition(id))
		for s in data.states[id]:
			count+=1
			if not r.validate(s) or not r.solved(s):failures+=1;push_error("Rejected legal alternative "+id)
	var r=R.new(C.definition("GV18"))
	for actions in data.branches:
		var s=r.fresh()
		for a in actions:s=r.apply(s,a)
		if not r.solved(s):failures+=1;push_error("Boss branch failed")
	# The authored dependency graph is acyclic; optional content never gates a main.
	var visited: Array=[]
	for id in C.ids():
		var d=C.definition(id)
		for before in d.prerequisites:
			if before not in visited or (not d.side and C.definition(before).side):failures+=1
		visited.append(id)
	print("Geometry independent alternatives: %d accepted; %d derived boss branches; %d failures"%[count,data.branches.size(),failures])
	quit(1 if failures else 0)

extends SceneTree
const Rules = preload("res://scripts/cargo/rules.gd")
const Store = preload("res://scripts/cargo/store.gd")
var checks = 0
var failures = 0
func check(value: bool, title: String) -> void:
	checks += 1
	if value: print("PASS ",title)
	else: failures += 1; push_error(title)
func identity(s: Dictionary) -> String: return str(s.places)+str(s.left_low)
func _initialize() -> void:
	var first = Rules.fresh()
	check(Rules.valid(first),"fresh cargo is valid")
	check(not Rules.can_move(first,0,2) and not Rules.can_move(first,5,1),"loading across different heights is forbidden")
	var equal = first.duplicate(true); equal.places = [1,0,0,2,3,3]
	check(Rules.direction(equal) == 0 and Rules.travel(equal) == equal,"equal weight does not move")
	var states = [first]; var known = {identity(first):true}; var reverse = {}; var goals: Array[String] = []
	var cursor = 0; var safe = true; var conserving = true
	while cursor < states.size():
		var s: Dictionary = states[cursor]; cursor += 1
		var from = identity(s)
		if s.complete: goals.append(from); continue
		var nexts = []
		for item in range(6):
			for loc in range(4):
				if Rules.can_move(s,item,loc): nexts.append(Rules.moved(s,item,loc))
		if Rules.direction(s) != 0: nexts.append(Rules.travel(s))
		for n in nexts:
			safe = safe and Rules.valid(n)
			var weight = 0
			for item in range(6): weight += Rules.WEIGHTS[item]
			conserving = conserving and weight == 15 and n.places.size() == 6
			var key = identity(n)
			if not reverse.has(key): reverse[key] = []
			reverse[key].append(from)
			if not known.has(key): known[key] = true; states.append(n)
	check(safe and conserving,"all reachable transitions retain six items and valid completion states")
	check(goals.size() > 1,"multiple final arrangements are reachable")
	var reachable = {}; var queue = goals.duplicate(); cursor = 0
	for g in goals: reachable[g] = true
	while cursor < queue.size():
		var key = queue[cursor]; cursor += 1
		for parent in reverse.get(key,[]):
			if not reachable.has(parent): reachable[parent] = true; queue.append(parent)
	print("Reachability: %d arrangements, %d endings, %d can finish directly, %d need undo/reset" % [known.size(),goals.size(),reachable.size(),known.size()-reachable.size()])
	check(reachable.has(identity(first)),"fresh layout remains solvable after a reset; dead-end layouts require visible undo/reset")
	var s = first
	for step in [[0,1],[2,1],[5,2]]: s = Rules.moved(s,step[0],step[1])
	s = Rules.travel(s)
	check(s.places[0] == 3 and s.places[2] == 3 and Rules.weight(s,1) == 0 and Rules.weight(s,2) == 4,"passengers unload, counterweight stays aboard")
	for step in [[3,1],[4,1]]: s = Rules.moved(s,step[0],step[1])
	s = Rules.travel(s)
	for step in [[3,0],[4,0],[1,1]]: s = Rules.moved(s,step[0],step[1])
	s = Rules.travel(s)
	check(s.complete and s.trips == 3,"three-trip plan delivers fox, seed and hero")
	check(Rules.travel(s) == s and not Rules.can_move(s,0,1),"completed visit does not replay rewards or mutate cargo")
	var hinted = first
	var hint_actions = 0
	while not hinted.complete and hint_actions < 24:
		var step = Rules.next_step(hinted); hint_actions += 1
		if step.kind == "move": hinted = Rules.moved(hinted,step.item,step.target)
		elif step.kind == "travel": hinted = Rules.travel(hinted)
		else: break
	check(hinted.complete,"state-aware hint steps form a legal complete solution")
	var stranded = first.duplicate(true); stranded.places = [0,0,0,0,0,0]
	check(Rules.next_step(stranded).kind == "recover","stranded layout requests recovery instead of an impossible hint")
	var bad = first.duplicate(true); bad.places[0] = 1.5
	check(not Rules.valid(bad),"fractional locations rejected")
	bad = first.duplicate(true); bad.complete = true
	check(not Rules.valid(bad),"forged completion rejected")
	var store = Store.new(); store.path = "/tmp/cargo-rules-%d.json" % OS.get_process_id(); store.state.cargo = s
	check(store.save(),"v5 atomic save succeeds")
	var restored = Store.new(); restored.path = store.path; restored.read_save()
	check(restored.state.cargo == s and not restored.protected,"completed JSON reload normalizes numbers")
	var disk = FileAccess.get_file_as_string(store.path)
	store.state.cargo.places[0] = -1
	check(not store.save() and FileAccess.get_file_as_string(store.path) == disk,"invalid state preserves stored bytes")
	var file = FileAccess.open(store.path,FileAccess.WRITE); file.store_string("{broken"); file.close()
	restored.read_save(); check(restored.protected and not restored.save() and FileAccess.get_file_as_string(store.path) == "{broken","malformed record protected from overwrite")
	DirAccess.remove_absolute(store.path)
	var forged = Store.fresh(); forged.encounter.introduced = true
	check(not Store.valid(forged),"guardian progress requires completed delivery")
	print("CARGO RULES: %d/%d PASS" % [checks-failures,checks]); quit(1 if failures else 0)

extends SceneTree
const R = preload("res://scripts/workshop/gw01_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func puzzle() -> Dictionary:
	var s = R.fresh()
	while s.stage != "puzzle": s = R.advance(s)
	return s
func run() -> void:
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.move(R.fresh(),0,1).is_empty(),"no moving during dialogue")
	check(R.move(s,0,25).is_empty(),"cannot invent goods")
	check(R.move(s,3,1).is_empty(),"no fourth tray")
	check(R.move(s,0,-1).is_empty(),"cannot remove from empty")
	check(R.advance(s).is_empty(),"cannot start with loose goods")
	var solutions = []
	# All 325 complete partitions, using a separate scalar oracle for each round.
	for a in range(25):
		for b in range(25-a):
			var c = 24-a-b
			var candidate = puzzle(); candidate.trays = [a,b,c]
			var expected = a >= b+c
			var x = a-b-c; var y = b*2; var z = c*2
			expected = expected and y >= x+z
			var u = x*2; var v = y-x-z; var w = z*2
			expected = expected and w >= u+v and u*2 == 8 and v*2 == 8 and w-u-v == 8
			check(R.validate(candidate),"legal partition")
			check(R.solved(candidate) == expected,"exhaustive independent forward oracle")
			var trial = R.advance(candidate)
			check(R.validate(trial) and trial.stage == "trial","full wrong boards may be explored")
			for step in range(4):
				if trial.stage != "trial": break
				trial = R.advance(trial)
				check(R.validate(trial),"every simulated prefix validates")
			check((trial.stage == "delivery") == expected,"only verified result enters delivery")
			if expected: solutions.append([a,b,c])
	check(solutions == [[13,7,4]],"unique recovered manifest")
	s.trays = [13,7,4]
	check(R.after_rounds(s.trays,1) == [2,14,8],"golden first round")
	check(R.after_rounds(s.trays,2) == [4,4,16],"golden second round")
	check(R.after_rounds(s.trays,3) == [8,8,8],"golden third round")
	var trial = R.advance(s)
	for i in range(3): trial = R.advance(trial)
	check(trial.stage == "trial" and trial.round == 3,"result requires manual confirmation")
	var delivery = R.advance(trial)
	check(delivery.stage == "delivery" and R.validate(delivery),"confirmed result saved before delivery")
	check(R.move(delivery,0,-1).is_empty(),"no editing result")
	var aftermath = R.advance(delivery)
	for i in range(3): aftermath = R.advance(aftermath)
	check(aftermath.stage == "complete" and R.validate(aftermath),"manual discovery completes")
	for stage in ["trial","delivery","aftermath","complete"]:
		var forged = puzzle(); forged.stage = stage; forged.attempts = 1; forged.round = 3
		check(not R.validate(forged),"forged trial or completion rejected")
	for bad in [-1,25,2.5,"4",true]:
		var c = puzzle(); c.trays[0] = bad
		check(not R.validate(c),"invalid count rejected")
	for bad_round in [-1,4,2.0,true]:
		var c = trial.duplicate(true); c.round = bad_round
		check(not R.validate(c),"invalid round rejected")
	var bad = trial.duplicate(true); bad.trays = [8,8,8]
	check(not R.validate(bad),"impossible saved replay prefix rejected")
	bad = s.duplicate(true); bad.extra = true
	check(not R.validate(bad),"closed schema")
	bad = s.duplicate(true); bad.sample = "workshop-gw01-2"
	check(not R.validate(bad),"old version not interpreted as new progress")
	var helped = s.duplicate(true); helped.hint = 4; helped.attempts = 2
	var restored = R.restore(helped,{"trays":[0,0,0]})
	check(restored.hint == 4 and restored.attempts == 2,"undo retains help and attempts")
	var repo = Repo.new(); repo.path = "/tmp/gw01-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(delivery,R.validate),"save accepted board")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(aftermath,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == delivery,"restart restores saved animation stage")
	check(repo.write_profile(aftermath,R.validate),"retry exact completion")
	var file = FileAccess.open(repo.path,FileAccess.WRITE); file.store_string('{"broken":true}'); file.close()
	hash = FileAccess.get_sha256(repo.path)
	check(repo.read_profile(R.validate).status == "protected","bad save protected")
	check(not repo.write_profile(R.fresh(),R.validate) and FileAccess.get_sha256(repo.path) == hash,"protected file never overwritten")
	var backup = repo.preserve_protected_file()
	check(not backup.is_empty() and FileAccess.get_sha256(backup) == hash,"explicit recovery preserves backup")
	for p in [repo.path,repo.path+".tmp",backup]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(repo.path.get_base_dir())
	print("GW01 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

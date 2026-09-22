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
	check(R.move(s,5,24).is_empty(),"cannot invent a 24th spindle")
	check(R.move(s,6,1).is_empty(),"no sixth tray")
	check(R.move(s,0,5).is_empty(),"cannot overfill a tray")
	check(R.move(s,0,-1).is_empty(),"cannot remove from empty")
	check(R.advance(s).is_empty(),"cannot complete empty board")
	var solutions = 0
	# Independent enumeration of all 32 insert layouts and every allocation.
	for mask in range(32):
		var caps = []
		var combinations = 1
		for i in range(5):
			caps.append(5 if mask & (1 << i) else 3)
			combinations *= caps[i]+1
		for encoded in range(combinations):
			var digits = encoded; var sum = 0; var trays = []
			for cap in caps:
				var n = digits%(cap+1); digits = int(digits/(cap+1)); trays.append(n); sum += n
			for box in range(3):
				var c = s.duplicate(true); c.capacities = caps.duplicate(); c.trays = trays.duplicate(); c.box = box
				check(R.validate(c) == (sum+box <= 23),"allocation conservation boundary")
				var expected = trays == caps and sum == 21 and box == 2
				check(R.solved(c) == expected,"only three large and two small full trays with reserve")
				if R.solved(c): solutions += 1
	check(solutions == 10,"all ten permutations accepted")
	for i in [4,2,0]: s = R.resize(s,i)
	for i in [4,2,0,3,1]: s = R.move(s,i,s.capacities[i])
	s = R.move(s,5,2)
	check(R.solved(s) and R.stock(s) == 0,"batch actions conserve 23")
	check(R.resize(s,0).is_empty(),"occupied insert cannot change")
	check(R.resize(R.fresh(),0).is_empty(),"no insert changes during dialogue")
	check(R.resize(puzzle(),5).is_empty(),"repair box has no insert")
	var no_reserve = puzzle(); no_reserve.capacities = [5,5,5,5,3]; no_reserve.trays = [5,5,5,5,3]
	check(R.validate(no_reserve) and not R.solved(no_reserve),"four large trays leave no repair reserve and cannot pass")
	for bad_caps in [[3,3,3,3], [4,3,3,3,3], [true,3,3,3,3], [3.0,3,3,3,3]]:
		var c = puzzle(); c.capacities = bad_caps
		check(not R.validate(c),"malformed insert configuration rejected")
	var legacy = puzzle(); legacy.sample = "workshop-gw01-1"; legacy.erase("capacities")
	check(not R.validate(legacy),"legacy schema is not interpreted as new game")
	var delivery = R.advance(s)
	check(delivery.stage == "delivery" and R.validate(delivery),"verified board saved before animation")
	check(R.move(delivery,0,-1).is_empty(),"cannot remove goods after acceptance")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"animation ends at player-controlled story stop")
	for i in range(3): aftermath = R.advance(aftermath)
	check(aftermath.stage == "complete" and R.validate(aftermath),"completion after discovery dialogue")
	for stage in ["delivery","aftermath","complete"]:
		var forged = puzzle(); forged.stage = stage; forged.attempts = 1
		check(not R.validate(forged),"forged completion rejected")
	for bad in [-1,5,2.5,"4",true]:
		var c = puzzle(); c.trays[0] = bad
		check(not R.validate(c),"invalid tray JSON rejected")
	var bad = s.duplicate(true); bad.box = 4
	check(not R.validate(bad),"overallocated save rejected")
	bad = s.duplicate(true); bad.extra = true
	check(not R.validate(bad),"unknown schema field rejected")
	var helped = s.duplicate(true); helped.hint = 4; helped.attempts = 2
	var restored = R.restore(helped,{"trays":[0,0,0,0,0],"capacities":[3,3,3,3,3],"box":0})
	check(restored.hint == 4 and restored.attempts == 2,"undo retains assistance and attempts")
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

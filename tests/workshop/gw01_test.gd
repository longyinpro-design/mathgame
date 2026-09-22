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
	# Independent exhaustive allocations: every legal tray combination and repair-box amount.
	for encoded in range(3125):
		var digits = encoded; var sum = 0; var trays = []
		for i in range(5):
			var n = digits%5; digits = int(digits/5); trays.append(n); sum += n
		for box in range(24-sum):
			var c = s.duplicate(true); c.trays = trays.duplicate(); c.box = box
			check(R.validate(c),"legal allocation")
			var expected = sum == 20 and box == 3
			check(R.solved(c) == expected,"only five full trays plus remainder completes")
			if R.solved(c): solutions += 1
	check(solutions == 1,"unique allocation, independent of action order")
	for i in [4,2,0,3,1]: s = R.move(s,i,4)
	s = R.move(s,5,3)
	check(R.solved(s) and R.stock(s) == 0,"batch actions conserve 23")
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
	var restored = R.restore(helped,{"trays":[0,0,0,0,0],"box":0})
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

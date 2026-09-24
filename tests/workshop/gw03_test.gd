extends SceneTree
const R = preload("res://scripts/workshop/gw03_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW03 rules watchdog fired")
		print("GW03 RULES: ",checks," checks, ",failures+1," failures")
		quit(1)
		return true
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func puzzle() -> Dictionary:
	var s = R.fresh()
	while s.stage != "puzzle": s = R.advance(s)
	return s
# 用最笨的办法各排一遍三条节拍表，不复用被测代码里的公式。
func series(first: int, step: int) -> Array:
	var out = []; var t = first
	while t <= R.HORIZON: out.append(t); t += step
	return out
func oracle_meetings() -> Array:
	var lifts = {}; var carts = {}; var lamps = {}
	for t in series(2,3): lifts[t] = true
	for t in series(3,4): carts[t] = true
	for t in series(3,5): lamps[t] = true
	var out = []
	for t in range(1,R.HORIZON+1):
		if lifts.has(t) and carts.has(t) and lamps.has(t): out.append(t)
	return out
func run() -> void:
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.watch(R.fresh(),5).is_empty(),"no watching during dialogue")
	check(R.watch(s,-1).is_empty(),"no negative tick")
	check(R.watch(s,R.HORIZON+1).is_empty(),"no tick past the horizon")
	check(R.move_probe(s,0).is_empty(),"moving to the same tick is a no-op")
	check(R.move_probe(s,-1).is_empty(),"cannot step before zero")
	check(R.move_probe(s,R.HORIZON).probe == R.HORIZON,"cannot step past the horizon")
	check(R.advance(s).is_empty(),"cannot hand over an unwatched tick")
	# 三条节拍表逐拍对照，并用独立排表验证第一次同时。
	check(R.arrivals(0) == series(2,3),"lift arrivals")
	check(R.arrivals(1) == series(3,4),"cart arrivals")
	check(R.arrivals(2) == series(3,5),"lamp arrivals")
	var meetings = oracle_meetings()
	check(meetings == [23],"independent oracle finds a single legal tick")
	check(R.meetings() == meetings,"meetings agree with the oracle")
	check(R.earliest() == 23,"earliest legal handover is 23")
	for track in range(3):
		for t in range(0,R.HORIZON+1):
			var expected = series([2,3,3][track],[3,4,5][track]).has(t)
			check(R.arrives(track,t) == expected,"arrival table matches the oracle")
	for t in range(0,R.HORIZON+1):
		check(R.handover_at(t) == meetings.has(t),"handover table matches the oracle")
	# 逐拍检查判定与说明：看过的合法拍才通过，没看过的、条件不全的、更晚的都要说清。
	for t in range(0,R.HORIZON+1):
		var probed = puzzle(); probed = R.watch(probed,t)
		check(R.validate(probed),"watching any tick stays legal")
		check(probed.watched == R.reveal_window(t),"watching records the window around the tick")
		check(R.solved(probed) == (t == 23),"only tick 23 solves")
		check(R.shortfalls(probed).is_empty() == (t == 23),"shortfalls agree with solved")
		check(R.advance(probed).is_empty() == (t != 23),"only the legal tick advances")
	var blind = puzzle(); blind = R.move_probe(blind,23)
	check(blind.probe == 23 and blind.watched.is_empty(),"stepping alone is not watching")
	check(not R.solved(blind) and R.shortfalls(blind)[0].begins_with("第 23 拍还没运行过"),"unwatched tick is named")
	check(R.advance(blind).is_empty(),"unwatched tick cannot be claimed")
	var eleven = R.watch(puzzle(),11)
	check("放行灯没亮" in R.shortfalls(eleven)[0] and "吊台没到" not in R.shortfalls(eleven)[0],"partial meeting names only the missing condition")
	var five = R.watch(puzzle(),5)
	check("吊台没到" not in R.shortfalls(five)[0] and "小车没到" in R.shortfalls(five)[0],"single arrival names the rest")
	var thirty_five = R.watch(puzzle(),35)
	check(not R.handover_at(35) and "放行灯没亮" in R.shortfalls(thirty_five)[0],"the second pair meeting still lacks the lamp")
	# 1～40 拍里合法交接只有第 23 拍一处，所以「更晚的合法拍」那条分支在本题里够不到；
	# 规则仍然保留它，换 HORIZON 时判定不用重写。
	check(R.meetings().size() == 1,"only one legal handover exists inside the horizon")
	# 撤销与重摆：看过的记录跟着快照走。
	var watched = R.watch(puzzle(),23)
	var more = R.watch(watched,35)
	check(more.watched == [21,22,23,24,25,33,34,35,36,37],"windows merge into one sorted record")
	check(R.reveal_window(0) == [0,1,2] and R.reveal_window(R.HORIZON) == [38,39,40],"window clamps at both ends")
	check(R.restore(more,{"probe":23,"watched":[23]}).watched == [23],"undo restores the record")
	check(R.restore(R.watch(puzzle(),23),{"probe":0,"watched":[]}).watched.is_empty(),"reset clears the record")
	# 完整走一遍。
	var trial = R.watch(puzzle(),23)
	check(R.validate(trial),"claimed tick is legal")
	var delivery = R.advance(trial)
	check(delivery.stage == "delivery" and R.validate(delivery),"verified handover enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 伪造与坏档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = R.watch(puzzle(),23); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = R.watch(puzzle(),35); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
		var unwatched = puzzle(); unwatched.stage = stage
		check(not R.validate(unwatched),"unwatched %s rejected"%stage)
	for bad_probe in [-1,R.HORIZON+1,1.5,true]:
		var c = puzzle(); c.probe = bad_probe
		check(not R.validate(c),"invalid probe rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = R.watch(puzzle(),23); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	var dupes = R.watch(puzzle(),23); dupes.watched = [23,23]
	check(not R.validate(dupes),"duplicate record rejected")
	var unsorted_bad = R.watch(puzzle(),23); unsorted_bad.watched = [23,99]
	check(not R.validate(unsorted_bad),"out-of-range record rejected")
	var extra = R.watch(puzzle(),23); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = R.watch(puzzle(),23); old.sample = "workshop-gw03-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var helped = R.watch(puzzle(),5); helped.hint = 4
	check(R.restore(helped,{"probe":0,"watched":[]}).hint == 4,"undo retains help")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw03-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(trial,R.validate),"save accepted record")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(delivery,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == trial,"restart restores saved record")
	check(repo.write_profile(done,R.validate),"retry exact completion")
	var file = FileAccess.open(repo.path,FileAccess.WRITE); file.store_string('{"broken":true}'); file.close()
	hash = FileAccess.get_sha256(repo.path)
	check(repo.read_profile(R.validate).status == "protected","bad save protected")
	check(not repo.write_profile(R.fresh(),R.validate) and FileAccess.get_sha256(repo.path) == hash,"protected file never overwritten")
	var backup = repo.preserve_protected_file()
	check(not backup.is_empty() and FileAccess.get_sha256(backup) == hash,"explicit recovery preserves backup")
	for p in [repo.path,repo.path+".tmp",backup]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(repo.path.get_base_dir())
	print("GW03 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

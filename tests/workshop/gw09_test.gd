extends SceneTree
const R = preload("res://scripts/workshop/gw09_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW09 rules watchdog fired")
		print("GW09 RULES: ",checks," checks, ",failures+1," failures")
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
# 独立 oracle：不复用被测代码的 cycle/gcd，用最笨的办法一格一格走环。
func oracle_track(step: int) -> Array:
	var stops = [0]
	var cursor = step % R.LAMPS
	while cursor != 0 and not stops.has(cursor):
		stops.append(cursor)
		cursor = (cursor+step) % R.LAMPS
	stops.append(cursor)
	return stops
func run_step(step: int, claim: int) -> Dictionary:
	var s = R.choose_step(puzzle(),step)
	if claim >= 0: s = R.predict(s,claim)
	for i in range(R.cycle(step)): s = R.jump(s)
	return s
func run() -> void:
	# 独立 oracle：2～8 每个步长的轨迹、跳数、覆盖率与第 3 站。
	var full = []
	var thirds = {}
	for step in range(R.STEP_MIN,R.STEP_MAX+1):
		var track = oracle_track(step)
		var third = track[3] if track.size() > 3 else -1
		thirds[step] = third
		if track.size() == R.LAMPS+1: full.append(step)
		check(R.track(step) == track,"step %d track matches the oracle"%step)
		check(R.cycle(step) == track.size()-1,"step %d cycle matches the oracle"%step)
		check(R.covers(step) == (track.size() == R.LAMPS+1),"step %d coverage matches the oracle"%step)
		if track.size() > 3:
			check(R.third_stop(step) == third,"step %d third stop matches the oracle"%step)
	check(full == [5,7],"the oracle finds only 5 and 7 covering every lamp")
	check(thirds[3] == 9 and thirds[5] == 3 and thirds[7] == 9,"the key third stops are 9, 3 and 9")
	check(R.track(7) == [0,7,2,9,4,11,6,1,8,3,10,5,0],"seven follows the authored track")
	check(R.track(5) == [0,5,10,3,8,1,6,11,4,9,2,7,0],"five follows the authored track")
	check(R.cycle(6) == 2 and R.third_stop(4) == 0,"six returns in two jumps; four returns on the third")
	# 逐跳运行：每个步长都走到回 0，停站与落点逐格对照 oracle。
	for step in range(R.STEP_MIN,R.STEP_MAX+1):
		var track = oracle_track(step)
		var s = R.choose_step(puzzle(),step)
		check(R.validate(s),"step %d starts legal"%step)
		for jump in range(track.size()-1):
			s = R.jump(s)
			check(R.validate(s),"step %d jump %d stays legal"%[step,jump+1])
			check(R.cursor(s) == track[jump+1],"step %d jump %d lands on %d"%[step,jump+1,track[jump+1]])
		check(s.jumps == track.size()-1,"step %d ends after %d jumps"%[step,track.size()-1])
		check(s.visited == track.slice(1,track.size()-1),"step %d records the oracle stops"%step)
		check(R.returned(s),"step %d returns to zero"%step)
		check(R.covered(s) == (step in [5,7]),"step %d coverage agrees with the oracle"%step)
		check(not s.visited.has(0),"step %d never records the start as a stop"%step)
		check(R.jump(s).is_empty(),"step %d cannot jump after returning"%step)
	# 逐格 solved 与 shortfalls：2～8 每个步长，三种预测。
	var solution = []
	for step in range(R.STEP_MIN,R.STEP_MAX+1):
		for claim in [-1,3,9]:
			var s = run_step(step,claim)
			var want = (step in [5,7]) and thirds[step] == 9 and claim == 9
			check(R.solved(s) == want,"solved %d claim %d agrees with the oracle"%[step,claim])
			check(R.shortfalls(s).is_empty() == want,"shortfalls %d claim %d agree"%[step,claim])
			check(R.validate(s),"finished %d claim %d stays legal"%[step,claim])
			if want: solution.append(step)
	check(solution == [7],"only step seven with claim nine solves")
	# 反例要能说清：3 回早了、5 第 3 站不对、7 缺预测、跑一半。
	var five = run_step(5,9)
	check(R.shortfalls(five).size() == 1 and "实际停在 3" in R.shortfalls(five)[0],"five names its real third stop")
	var three = run_step(3,9)
	check("第 4 次跳动就回到了 0" in R.shortfalls(three)[0],"three names the early return")
	var five_wrong = run_step(5,3)
	check("你预测第 3 站是 3" in R.shortfalls(five_wrong)[0],"a wrong claim is named")
	var seven_no_claim = run_step(7,-1)
	check(R.shortfalls(seven_no_claim)[0].begins_with("先预测"),"a missing claim is named first")
	var mid = R.jump(R.jump(R.jump(R.jump(R.predict(R.choose_step(puzzle(),7),9)))))
	check("还没跑完" in R.shortfalls(mid)[0],"an unfinished circle is named")
	check(R.shortfalls(puzzle())[0].begins_with("先设一个步长"),"no step is named first")
	check(R.shortfalls(run_step(7,9)).is_empty(),"the real answer has no shortfall")
	# 提交只在解上通过；完整流程。
	check(R.advance(five).is_empty() and R.advance(three).is_empty(),"wrong circles cannot be claimed")
	check(R.advance(seven_no_claim).is_empty(),"a missing claim cannot be claimed")
	check(R.advance(mid).is_empty(),"an unfinished circle cannot be claimed")
	var delivery = R.advance(run_step(7,9))
	check(delivery.stage == "delivery" and R.validate(delivery),"seven enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 阶段推进与操作守卫。
	var s = R.fresh()
	check(s.stage == "arrival" and R.validate(s),"fresh starts at arrival")
	for i in range(3):
		s = R.advance(s)
		check(R.validate(s),"arrival beat %d legal"%s.beat)
	check(s.stage == "approach","three beats reach approach")
	s = R.advance(s); check(s.stage == "ready" and R.validate(s),"approach reaches ready")
	s = R.advance(s); check(s.stage == "puzzle" and R.validate(s),"ready reaches puzzle")
	check(R.choose_step(R.fresh(),5).is_empty(),"no choosing a step during dialogue")
	check(R.move_step(R.fresh(),1).is_empty(),"no moving a step during dialogue")
	check(R.predict(R.fresh(),9).is_empty(),"no predicting during dialogue")
	check(R.jump(R.fresh()).is_empty(),"no jumping during dialogue")
	check(R.choose_step(puzzle(),1).is_empty() and R.choose_step(puzzle(),9).is_empty(),"steps outside 2..8 are refused")
	check(R.jump(puzzle()).is_empty(),"no jumping before a step is set")
	check(R.predict(puzzle(),9).is_empty(),"prediction needs a step first")
	var seven = R.choose_step(puzzle(),7)
	check(seven.step == 7 and seven.third == -1 and R.validate(seven),"choosing seven is legal")
	check(R.predict(seven,-1).is_empty() and R.predict(seven,12).is_empty(),"lamps outside 0..11 are refused")
	check(R.predict(seven,7).third == 7,"predicting a lamp")
	check(R.predict(R.predict(seven,7),7).is_empty(),"re-predicting the same lamp is a no-op")
	check(R.choose_step(seven,7).is_empty(),"re-choosing the same step with no run is a no-op")
	check(R.move_step(puzzle(),1).step == 2,"the first step lands on two")
	check(R.move_step(R.choose_step(puzzle(),2),-1).is_empty(),"stepping clamps at two without clearing")
	check(R.move_step(R.choose_step(puzzle(),8),1).is_empty(),"stepping clamps at eight without clearing")
	check(R.move_step(R.choose_step(puzzle(),5),1).step == 6,"stepping moves one step at a time")
	# 换步长清空这一圈；重跑保留预测；第 3 站落地后预测锁住。
	var mid7 = R.jump(R.predict(R.choose_step(puzzle(),7),9))
	var changed = R.choose_step(mid7,5)
	check(changed.step == 5 and changed.jumps == 0 and changed.visited.is_empty() and changed.third == -1,"a new step clears the run and the claim")
	var full7 = run_step(7,9)
	var rerun = R.choose_step(full7,7)
	check(rerun.step == 7 and rerun.jumps == 0 and rerun.visited.is_empty() and rerun.third == 9,"re-running the same step keeps the claim")
	check(R.predict(rerun,3).third == 3,"re-running unlocks the claim")
	check(R.predict(full7,3).is_empty(),"the claim locks after the third jump")
	var two = R.jump(R.jump(R.predict(R.choose_step(puzzle(),7),9)))
	check(R.predict(two,3).third == 3,"the claim can change before the third jump")
	var three_jumps = R.jump(two)
	check(R.predict(three_jumps,3).is_empty(),"the claim locks once the third stop is seen")
	check(R.move_predict(R.choose_step(puzzle(),7),1).third == 0,"the first prediction step lands on zero")
	# 撤销与重摆：步长、预测、跳数与停站都跟着快照走。
	var back = R.restore(full7,{"step":5,"third":9,"jumps":12,"visited":[5,10,3,8,1,6,11,4,9,2,7]})
	check(back.step == 5 and back.jumps == 12 and R.validate(back),"undo restores another circle")
	check(R.restore(full7,{"step":7,"third":9,"jumps":0,"visited":[]}).jumps == 0,"undo restores the start of the circle")
	check(R.restore(full7,{"step":7,"third":-1}).is_empty(),"an incomplete snapshot is refused")
	check(R.restore(R.fresh(),{"step":7,"third":-1,"jumps":0,"visited":[]}).is_empty(),"no undo outside the puzzle")
	var helped = R.predict(R.choose_step(puzzle(),7),9); helped.hint = 3
	check(R.restore(R.jump(helped),{"step":7,"third":-1,"jumps":0,"visited":[]}).hint == 3,"undo keeps the hint level")
	var cleared = R.restore(full7,{"step":0,"third":-1,"jumps":0,"visited":[]})
	check(cleared.step == 0 and cleared.third == -1 and cleared.visited.is_empty(),"reset clears step, claim and stops")
	# 伪造与坏档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = run_step(7,9); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = run_step(5,9); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
		var half = R.jump(R.choose_step(puzzle(),7)); half.stage = stage
		check(not R.validate(half),"unfinished %s rejected"%stage)
	for bad_step in [-1,1,9,2.5,true]:
		var c = puzzle(); c.step = bad_step
		check(not R.validate(c),"invalid step rejected")
	for bad_third in [-2,12,1.5,true]:
		var c = R.choose_step(puzzle(),7); c.third = bad_third
		check(not R.validate(c),"invalid third stop rejected")
	for bad_jumps in [-1,13,1.5,true]:
		var c = R.choose_step(puzzle(),7); c.jumps = bad_jumps
		check(not R.validate(c),"invalid jump count rejected")
	for bad_visited in [[0],[7,7],[2,7],[7,2,3],[7.0],[7,2,9,4,11,6,1,8,3,10,5,0]]:
		var c = R.choose_step(puzzle(),7); c.jumps = bad_visited.size(); c.visited = bad_visited
		check(not R.validate(c),"invalid stop record rejected")
	var mismatched = R.choose_step(puzzle(),7); mismatched.jumps = 5; mismatched.visited = [7,2]
	check(not R.validate(mismatched),"a stop record shorter than the jump count is rejected")
	var early = R.choose_step(puzzle(),7); early.stage = "arrival"
	check(not R.validate(early),"a step cannot appear during dialogue")
	var no_step_claim = puzzle(); no_step_claim.third = 9
	check(not R.validate(no_step_claim),"a claim needs a step")
	var no_step_run = puzzle(); no_step_run.jumps = 1; no_step_run.visited = [7]
	check(not R.validate(no_step_run),"stops need a step")
	var extra = run_step(7,9); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = run_step(7,9); old.sample = "workshop-gw09-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	for bad_hint in [-1,5,1.0,true]:
		var c = run_step(7,9); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = run_step(7,9); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw09-rules-%d/save.json"%OS.get_process_id()
	var partial = R.jump(R.predict(R.choose_step(puzzle(),7),9))
	check(repo.write_profile(partial,R.validate),"save accepted the partial run")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(run_step(7,9),R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == partial,"restart restores the saved run")
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
	print("GW09 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

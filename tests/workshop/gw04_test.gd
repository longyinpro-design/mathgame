extends SceneTree
const R = preload("res://scripts/workshop/gw04_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW04 rules watchdog fired")
		print("GW04 RULES: ",checks," checks, ",failures+1," failures")
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
func plan(delay: int, picks: Array) -> Dictionary:
	var s = puzzle(); s.delay = delay; s.picks = picks.duplicate()
	return s
# 用最笨的办法各排一遍时刻表，不复用被测代码里的公式。
func oracle_lifts(delay: int) -> Array:
	var out = []; var t = 2+delay
	while t <= R.HORIZON: out.append(t); t += 6
	return out
func oracle_meets(delay: int) -> Array:
	var carts = [4,8,12,16]
	var out = []
	for t in oracle_lifts(delay):
		if carts.has(t): out.append(t)
	return out
func subsets(maximum: int, size: int) -> Array:
	var out = []
	if size == 0: return [[]]
	for a in range(1,maximum+1):
		if size == 1: out.append([a])
		else:
			for b in range(a+1,maximum+1): out.append([a,b])
	return out
func run() -> void:
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.set_delay(R.fresh(),2).is_empty(),"no delay change during dialogue")
	check(R.set_delay(s,3).is_empty(),"no fourth delay option")
	check(R.set_delay(s,0).is_empty(),"setting the same delay is a no-op")
	check(R.toggle_pick(s,0).is_empty() and R.toggle_pick(s,17).is_empty(),"picks stay inside 1..16")
	check(R.advance(s).is_empty(),"cannot sail without two handovers")
	# 三档延后量逐档对照，并用独立排表验证相遇时刻。
	for delay in R.DELAYS:
		check(R.lift_times(delay) == oracle_lifts(delay),"lift table matches the oracle for delay %d"%delay)
		check(R.meetings(delay) == oracle_meets(delay),"meeting table matches the oracle for delay %d"%delay)
	check(R.meetings(0) == [8] and R.meetings(1).is_empty() and R.meetings(2) == [4,16],"the three shifts differ")
	for tick in range(1,R.HORIZON+1):
		check(R.cart_at(tick) == [4,8,12,16].has(tick),"cart table matches the oracle")
	# 全部「延后 × 至多两次交接」组合枚举：只有延后 2 拍、选 4 与 16 才成立。
	var solutions = []
	for delay in R.DELAYS:
		for size in [0,1,2]:
			for picks in subsets(R.HORIZON,size):
				var candidate = plan(delay,picks)
				var expected = delay == 2 and picks == [4,16]
				check(R.validate(candidate),"legal plan")
				check(R.solved(candidate) == expected,"exhaustive independent oracle")
				if expected: solutions.append([delay,picks])
	check(solutions == [[2,[4,16]]],"unique recovered plan")
	# 说明只指出真实违反的那一条。
	check(R.shortfalls(plan(0,[]))[0].begins_with("延后 0 拍"),"delay zero is judged before the picks")
	check(R.shortfalls(plan(1,[]))[0].begins_with("延后 1 拍"),"delay one is judged before the picks")
	check(R.shortfalls(plan(2,[]))[0].begins_with("要在第 16 拍"),"delay two only lacks picks")
	check(R.shortfalls(plan(2,[4]))[0].begins_with("要在第 16 拍"),"one pick is named")
	check("第 10 拍" in R.shortfalls(plan(2,[4,10]))[0],"a non-meeting pick is named")
	check(R.shortfalls(plan(2,[4,16])).is_empty(),"the author plan has nothing to explain")
	# 换档会把旧选择清掉：新时刻表上的旧时刻不能留着冒充计划。
	var picked = R.toggle_pick(R.toggle_pick(puzzle(),4),16)
	check(picked.picks == [4,16],"two picks recorded in order")
	check(R.toggle_pick(picked,4).picks == [16],"clicking a chosen tick takes it back")
	check(R.set_delay(plan(2,[4,16]),2).is_empty(),"setting the same delay keeps the picks")
	check(R.set_delay(picked,1).picks.is_empty(),"changing the delay clears the picks")
	check(R.toggle_pick(picked,10).is_empty(),"a third pick is refused")
	# 完整走一遍：错的计划退回排班，对的计划才进交货。
	var trial = R.advance(plan(2,[4,10]))
	check(trial.stage == "trial" and trial.attempts == 1,"two picks may be sailed")
	check(R.validate(trial),"trial state is legal")
	var back = R.advance(trial)
	check(back.stage == "puzzle" and R.validate(back),"a wrong shift returns to planning")
	check(R.back_to_plan(trial).stage == "puzzle","trial can be abandoned")
	var good = R.advance(plan(2,[4,16]))
	check(good.stage == "trial","the author plan may be sailed")
	var delivery = R.advance(good)
	check(delivery.stage == "delivery" and R.validate(delivery),"verified shift enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 伪造与坏档一律拒绝：试演那一格允许错计划（本来就该看得到失败），
	# 但没选够两次不能进试演，交货之后的每一格都必须是真解出来的。
	var sailable = plan(2,[4,16]); sailable.stage = "trial"; sailable.attempts = 1
	check(R.validate(sailable),"a two-pick shift may be sailed")
	var wrong_sail = plan(0,[8,16]); wrong_sail.stage = "trial"; wrong_sail.attempts = 1
	check(R.validate(wrong_sail),"a wrong shift may still be sailed and watched")
	var half_sail = plan(2,[4]); half_sail.stage = "trial"; half_sail.attempts = 1
	check(not R.validate(half_sail),"trial without two picks rejected")
	for stage in ["delivery","aftermath","complete"]:
		var legal = plan(2,[4,16]); legal.stage = stage; legal.attempts = 1
		check(R.validate(legal),"completed %s is legal"%stage)
		var forged = plan(0,[8,16]); forged.stage = stage; forged.attempts = 1
		check(not R.validate(forged),"forged %s rejected"%stage)
	var unpicked = plan(2,[]); unpicked.stage = "trial"; unpicked.attempts = 1
	check(not R.validate(unpicked),"trial without two picks rejected")
	var no_attempt = plan(2,[4,16]); no_attempt.stage = "trial"
	check(not R.validate(no_attempt),"trial without an attempt rejected")
	for bad_delay in [-1,3,1.5,true]:
		var c = plan(2,[4,16]); c.delay = bad_delay
		check(not R.validate(c),"invalid delay rejected")
	var dupes = plan(2,[4,4])
	check(not R.validate(dupes),"duplicate picks rejected")
	var three = plan(2,[4,10,16])
	check(not R.validate(three),"three picks rejected")
	var extra = plan(2,[4,16]); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = plan(2,[4,16]); old.sample = "workshop-gw04-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var helped = R.toggle_pick(puzzle(),4); helped.hint = 4; helped.attempts = 2
	check(R.restore(helped,{"delay":0,"picks":[]}).hint == 4,"undo retains help and attempts")
	check(R.restore(helped,{"delay":2,"picks":[4,16]}).picks == [4,16],"undo restores the plan")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw04-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(plan(2,[4,16]),R.validate),"save accepted plan")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(trial,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == plan(2,[4,16]),"restart restores saved plan")
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
	print("GW04 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

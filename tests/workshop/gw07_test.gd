extends SceneTree
const R = preload("res://scripts/workshop/gw07_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 180.0:
		push_error("GW07 rules watchdog fired")
		print("GW07 RULES: ",checks," checks, ",failures+1," failures")
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
func plan(press: Array, cool: Array) -> Dictionary:
	var s = puzzle(); s.press = press.duplicate(); s.cool = cool.duplicate()
	return s
# 从 0..top 里取四个递增的数：解一定落在这个范围里（冷却机 8 拍加检修那 1 拍，最早也要到第 11 拍）。
func quadruples(top: int) -> Array:
	var out = []
	for a in range(top+1):
		for b in range(a+1,top+1):
			for c in range(b+1,top+1):
				for d in range(c+1,top+1):
					out.append([a,b,c,d])
	return out
# 独立逐拍模拟：压机、冷却机、暂存位、检修段各查一遍，与被测的 scan() 写法完全不同。
func oracle_problem(press: Array, cool: Array) -> String:
	if not _rising(press): return "press-order"
	if not _rising(cool): return "cool-order"
	for i in range(R.COUNT):
		if cool[i] < press[i]+R.PRESS_TIME: return "cool-before-press"
	for t in range(R.HORIZON):
		var pressing = 0
		var cooling = 0
		var waiting = 0
		for i in range(R.COUNT):
			if press[i] <= t and t < press[i]+R.PRESS_TIME: pressing += 1
			if cool[i] <= t and t < cool[i]+R.COOL_TIME: cooling += 1
			if press[i]+R.PRESS_TIME <= t and t < cool[i]: waiting += 1
		if pressing > 1: return "press-clash"
		if cooling > 1: return "cool-clash"
		if cooling == 1 and t >= R.MAINT_START and t < R.MAINT_END: return "maintenance"
		if waiting > 1: return "buffer"
	return ""
func _rising(value: Array) -> bool:
	for index in range(1,value.size()):
		if value[index-1] >= value[index]: return false
	return true
func oracle_solved(press: Array, cool: Array) -> bool:
	if not oracle_problem(press,cool).is_empty(): return false
	var last = 0
	for start in cool: last = maxi(last,start+R.COOL_TIME)
	return last <= R.DEADLINE
func run() -> void:
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.set_start(R.fresh(),0,0,0).is_empty(),"no editing during dialogue")
	check(R.makespan(plan([0,1,2,3],[1,3,5,7])) == 9,"the opening draft alone would finish in nine")
	check(s.press == R.DEFAULT_PRESS and s.cool == R.DEFAULT_COOL,"the opening draft is the back-to-back plan")
	# 开局的顺排草稿正好压在检修段上：第一处问题就是它。
	var opening = R.problems(s)
	check(opening.size() == 1,"the opening draft has exactly one thing wrong")
	check("第 4 拍" in opening[0] and "检修" in opening[0],"the maintenance clash is named at tick four")
	check("B" in opening[0],"the item held over the maintenance is named")
	check(R.scan(s).tick == 4,"the run stops at tick four")
	check(not R.solved(s),"the opening draft is not a solution")
	# 作者解与它的一族近亲都成立；检修前后各留一段是唯一可行的冷却排法。
	var author = plan([0,1,4,6],[1,5,7,9])
	check(R.solved(author) and R.makespan(author) == 11,"the author plan finishes in eleven")
	check(R.problems(author).is_empty(),"the author plan has nothing to explain")
	check(R.solved(plan([0,4,6,8],[1,5,7,9])),"pressing right before each cooling also works")
	check(R.solved(plan([1,2,4,6],[2,5,7,9])),"a second cooling start also works")
	check(not R.solved(plan([0,1,4,6],[3,7,9,11])),"cooling into the maintenance is refused")
	check(not R.solved(plan([0,1,2,3],[1,5,7,9])),"pressing ahead of the buffer is refused")
	check(not R.solved(plan([1,0,4,6],[1,5,7,9])),"pressing out of line is refused")
	check(not R.solved(plan([0,1,4,6],[1,5,9,7])),"cooling out of line is refused")
	check(not R.solved(plan([0,1,4,6],[0,5,7,9])),"cooling before pressing finishes is refused")
	# 说明只指出真实违反的那一条，并且按「顺序 → 逐拍 → 期限」的次序给出。
	check(R.problems(plan([1,0,4,6],[1,5,7,9]))[0].begins_with("压制要按 A、B、C、D"),"out-of-line pressing is named first")
	check(R.problems(plan([0,1,4,6],[1,5,9,7]))[0].begins_with("冷却要按 A、B、C、D"),"out-of-line cooling is named first")
	check(R.problems(plan([0,1,4,6],[0,5,7,9]))[0].begins_with("A 的冷却排在第 0 拍"),"cooling before pressing is named")
	check(R.problems(plan([0,1,4,6],[1,2,5,7]))[0].begins_with("第 2 拍：A 和 B 同时占着冷却机"),"a cooling clash names both items")
	check(R.problems(plan([0,1,2,3],[1,5,7,9]))[0].begins_with("第 3 拍：B 和 C 都停在暂存位上"),"a buffer clash names both items and its tick")
	check(R.problems(plan([0,1,4,6],[1,5,7,11]))[0].begins_with("这套排法到第 13 拍"),"a late plan names its finish")
	# 全部可能成为解的排法逐对枚举：与独立模拟逐对对照，并找全部合法解。
	# 冷却机一共要忙 8 拍、还要跳过检修那 1 拍，最早也要第 11 拍完工，所以压制不会晚于第 8 拍。
	var probe = puzzle()
	var solutions = []
	var schedules = []
	var presses = quadruples(8)
	var cools = quadruples(9)
	for press in presses:
		for cool in cools:
			probe.press = press.duplicate()
			probe.cool = cool.duplicate()
			var mine = R.problems(probe).is_empty()
			check(mine == oracle_solved(press,cool),"solver agrees with the tick simulator")
			if mine:
				solutions.append([press,cool])
				if not schedules.has(cool): schedules.append(cool)
	check(solutions.size() == 79,"seventy-nine arrangements clear the deadline")
	check(schedules == [[1,5,7,9],[2,5,7,9]],"only two cooling schedules can clear it")
	for entry in solutions:
		check(R.makespan(plan(entry[0],entry[1])) == R.DEADLINE,"every solution finishes exactly on the lower bound")
	check(solutions[0] == [[0,1,4,6],[1,5,7,9]],"the author plan is the first solution found")
	# 界限之外也照判：超范围的取值一律不是解。
	check(not R.solved(plan([0,1,2,3],[9,10,11,12])),"starting past the deadline is refused")
	check(not R.solved(plan([4,5,6,7],[9,10,11,12])),"pressing late cannot meet the deadline")
	# 改一格就是改一拍的开工时间。
	var moved = R.set_start(puzzle(),1,0,2)
	check(moved.cool == [2,3,5,7],"one cooling start moves by itself")
	check(R.set_start(puzzle(),0,1,9).press == [0,9,2,3],"one press start moves by itself")
	check(R.set_start(puzzle(),0,0,-1).is_empty(),"no negative start")
	check(R.set_start(puzzle(),1,3,R.RANGE_MAX+1).is_empty(),"no start past the range")
	check(R.set_start(puzzle(),2,0,1).is_empty(),"only two belts exist")
	check(R.set_start(puzzle(),0,4,1).is_empty(),"only four items exist")
	check(R.set_start(R.fresh(),0,0,1).is_empty(),"no editing during dialogue")
	# 撤销恢复两条带，求助与尝试次数留着。
	var helped = R.set_start(puzzle(),0,2,5); helped.hint = 3; helped.attempts = 2
	check(R.restore(helped,{"press":[0,1,2,3],"cool":[1,3,5,7]}).press == [0,1,2,3],"undo restores the pressing")
	check(R.restore(helped,{"press":[0,1,2,3],"cool":[1,5,7,9]}).cool == [1,5,7,9],"undo restores the cooling")
	check(R.restore(helped,{"press":[0,1,2,3],"cool":[1,3,5,7]}).hint == 3,"undo retains help and attempts")
	check(R.restore(puzzle(),{"press":[0,1,2,3]}).is_empty(),"a half snapshot is refused")
	# 完整走一遍：跑不通的排法退回改排，跑通的才进交货。
	var trial = R.advance(s)
	check(trial.stage == "trial" and trial.attempts == 1,"the opening draft may be run")
	check(R.validate(trial),"trial state is legal")
	var back = R.advance(trial)
	check(back.stage == "puzzle" and R.validate(back),"a failing plan returns to planning")
	check(R.back_to_plan(trial).stage == "puzzle","trial can be abandoned")
	var good = R.advance(author)
	check(good.stage == "trial","the author plan may be run")
	var delivery = R.advance(good)
	check(delivery.stage == "delivery" and R.validate(delivery),"verified plan enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 伪造与坏档一律拒绝：试演那一格允许跑不通的排法（本来就该看得到停在哪一拍），
	# 交货之后的每一格都必须是真解出来的。
	var bad_sail = plan([0,1,2,3],[1,3,5,7]); bad_sail.stage = "trial"; bad_sail.attempts = 1
	check(R.validate(bad_sail),"a failing plan may still be run and watched")
	for stage in ["delivery","aftermath","complete"]:
		var legal = plan([0,1,4,6],[1,5,7,9]); legal.stage = stage; legal.attempts = 1
		check(R.validate(legal),"completed %s is legal"%stage)
		var forged = plan([0,1,2,3],[1,3,5,7]); forged.stage = stage; forged.attempts = 1
		check(not R.validate(forged),"forged %s rejected"%stage)
	var no_attempt = plan([0,1,4,6],[1,5,7,9]); no_attempt.stage = "trial"
	check(not R.validate(no_attempt),"trial without an attempt rejected")
	for bad in [[0,1,2],[0,1,2,3,4],[0,1,2,-1],[0,1,2,R.RANGE_MAX+1]]:
		var c = plan([0,1,4,6],[1,5,7,9]); c.cool = bad
		check(not R.validate(c),"invalid belt rejected")
	var extra = plan([0,1,4,6],[1,5,7,9]); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = plan([0,1,4,6],[1,5,7,9]); old.sample = "workshop-gw07-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var early = plan([0,1,4,6],[1,5,7,9]); early.stage = "ready"
	check(not R.validate(early),"ready cannot already carry a plan")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw07-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(author,R.validate),"save accepted plan")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(trial,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == author,"restart restores saved plan")
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
	print("GW07 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

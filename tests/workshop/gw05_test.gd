extends SceneTree
const R = preload("res://scripts/workshop/gw05_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW05 rules watchdog fired")
		print("GW05 RULES: ",checks," checks, ",failures+1," failures")
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
func plan(drill: Array, polish: Array) -> Dictionary:
	var s = puzzle(); s.drill = drill.duplicate(); s.polish = polish.duplicate()
	return s
func perms() -> Array:
	var out = []
	for a in range(3):
		for b in range(3):
			for c in range(3):
				if a == b or b == c or a == c: continue
				out.append([a,b,c])
	return out
# 独立逐拍模拟：钻机一件接一件按钻孔带顺序做，抛光机空闲且这一件已钻完才接下一件。
# 与被测的 timeline() 走的是完全不同的写法，用来交叉核对时刻表。
func simulate(drill_order: Array, polish_order: Array) -> Dictionary:
	var drill_done = {}
	var drill_rows = []
	var polish_rows = []
	var drill_i = 0
	var polish_i = 0
	var d_busy_until = 0
	var p_busy_until = 0
	var t = 0
	while polish_i < polish_order.size():
		if drill_i < drill_order.size() and t >= d_busy_until:
			var tool = drill_order[drill_i]
			drill_rows.append({"tool":tool,"start":t,"end":t+R.DRILL[tool]})
			d_busy_until = t+R.DRILL[tool]
			drill_done[tool] = d_busy_until
			drill_i += 1
		if polish_i < polish_order.size() and t >= p_busy_until:
			var tool = polish_order[polish_i]
			if drill_done.has(tool) and drill_done[tool] <= t:
				polish_rows.append({"tool":tool,"start":t,"end":t+R.POLISH[tool]})
				p_busy_until = t+R.POLISH[tool]
				polish_i += 1
		t += 1
	return {"drill":drill_rows,"polish":polish_rows,"makespan":p_busy_until}
func run() -> void:
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.place_tool(R.fresh(),0,0).is_empty(),"no placing during dialogue")
	check(R.advance(s).is_empty(),"cannot trial an empty pair of belts")
	check(R.makespan(plan([],[1])) == R.POLISH[1],"polish alone still reports its own finish")
	check(R.makespan(plan([],[])) == 0,"nothing placed finishes at zero")
	check(not R.ready(plan([0,1,2],[])),"one belt alone is not ready")
	check(R.ready(plan([0,1,2],[2,1,0])),"both belts full is ready")
	# 工时表本身就是题面，改动它会改掉整道题，先钉住。
	check(R.DRILL == [3,2,1] and R.POLISH == [1,3,2] and R.DEADLINE == 7,"author times unchanged")
	# 36 种「钻孔顺序 × 抛光顺序」全部走一遍：时刻表与被测实现逐块对照，并找唯一解。
	var solutions = []
	var best = 999
	for drill in perms():
		for polish in perms():
			var candidate = plan(drill,polish)
			check(R.validate(candidate),"legal plan")
			var mine = R.timeline(candidate)
			var oracle = simulate(drill,polish)
			check(mine.drill == oracle.drill,"drill rows match the tick simulator")
			check(mine.polish == oracle.polish,"polish rows match the tick simulator")
			check(R.makespan(candidate) == oracle.makespan,"makespan matches the tick simulator")
			# 每一件抛光都必须等它自己钻完：这是题面里唯一不能违反的先后关系。
			for row in mine.polish:
				var drilled = 0
				for done_row in oracle.drill:
					if done_row.tool == row.tool: drilled = done_row.end
				check(row.start >= drilled,"polish waits for its own drilling on %s"%str(drill))
			best = mini(best,oracle.makespan)
			check(R.solved(candidate) == (oracle.makespan <= R.DEADLINE),"solved follows the simulated finish")
			if oracle.makespan <= R.DEADLINE: solutions.append([drill,polish])
	check(best == 7,"seven beats is the real lower bound")
	check(solutions == [[[2,1,0],[2,1,0]]],"unique seven-beat plan is C then B then A on both belts")
	# 先做钻得最久的 A 会让抛光机干等，达不到下限；这是设计里点名的反例。
	check(R.makespan(plan([0,1,2],[0,1,2])) == 10,"longest-drill-first is ten beats")
	check(not R.solved(plan([0,1,2],[0,1,2])),"longest-drill-first fails")
	check(R.makespan(plan([0,1,2],[2,1,0])) == 12,"worst pairing is twelve beats")
	# 抛光不能先于钻完：A 抛光最早也只能在第 3 拍开工（A 钻完是第 3 拍）。
	var held = R.timeline(plan([0,1,2],[0,1,2]))
	check(held.polish[0].tool == 0 and held.polish[0].start == 3,"polish waits for its own drilling")
	# 说明只指出真实违反的那一条。
	check(R.shortfalls(plan([2],[2]))[0].begins_with("两条工序带都要排满"),"an unfinished pair names the belts")
	check("钻孔带 1 件" in R.shortfalls(plan([2],[2]))[0],"the drill count is reported")
	check(R.shortfalls(plan([0,1,2],[0,1,2]))[0].begins_with("这套排法到第 10 拍"),"a slow plan names its finish")
	check(R.shortfalls(plan([2,1,0],[2,1,0])).is_empty(),"the author plan has nothing to explain")
	# 排件与取下：同一带上不能重复，满了不能再排。
	var one = R.place_tool(puzzle(),0,2)
	check(one.drill == [2],"first tool lands at the end of the drill belt")
	check(R.place_tool(one,0,2).is_empty(),"the same tool cannot sit twice on one belt")
	var same = R.place_tool(one,1,2)
	check(same.drill == [2] and same.polish == [2],"the same tool may sit on both belts")
	check(R.place_tool(one,-1,0).is_empty() and R.place_tool(one,2,0).is_empty(),"only two belts exist")
	check(R.place_tool(one,0,3).is_empty() and R.place_tool(one,0,-1).is_empty(),"only three tools exist")
	var full = plan([0,1,2],[0,1,2])
	check(R.place_tool(full,0,0).is_empty(),"a full belt takes no more tools")
	check(R.remove_tool(one,0,1).is_empty(),"removing something absent is refused")
	check(R.remove_tool(full,0,1).drill == [0,2],"removing keeps the remaining order")
	check(R.remove_tool(full,1,0).polish == [1,2],"removing keeps the polish order")
	# 换带只动画面上的高亮，不动存档里的两条带。
	check(R.place_tool(one,1,0).polish == [0],"placing goes to the named belt, not the selected one")
	# 撤销恢复两条带，求助与尝试次数留着。
	var helped = R.place_tool(puzzle(),0,2); helped.hint = 3; helped.attempts = 2
	check(R.restore(helped,{"drill":[],"polish":[]}).drill.is_empty(),"undo restores the drill belt")
	check(R.restore(helped,{"drill":[2,1],"polish":[2]}).drill == [2,1],"undo restores both belts")
	check(R.restore(helped,{"drill":[],"polish":[]}).hint == 3,"undo retains help and attempts")
	check(R.restore(puzzle(),{"drill":[]}).is_empty(),"a partial snapshot is refused")
	# 完整走一遍：错的计划退回排工序，对的计划才进交货。
	var trial = R.advance(plan([0,1,2],[0,1,2]))
	check(trial.stage == "trial" and trial.attempts == 1,"a full but slow plan may be run")
	check(R.validate(trial),"trial state is legal")
	var back = R.advance(trial)
	check(back.stage == "puzzle" and R.validate(back),"a slow plan returns to planning")
	check(R.back_to_plan(trial).stage == "puzzle","trial can be abandoned")
	var good = R.advance(plan([2,1,0],[2,1,0]))
	check(good.stage == "trial","the author plan may be run")
	var delivery = R.advance(good)
	check(delivery.stage == "delivery" and R.validate(delivery),"verified plan enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 伪造与坏档一律拒绝：试演那一格允许慢计划（本来就该看得到失败），
	# 但两条带没排满不能进试演，交货之后的每一格都必须是真解出来的。
	var slow_sail = plan([0,1,2],[0,1,2]); slow_sail.stage = "trial"; slow_sail.attempts = 1
	check(R.validate(slow_sail),"a slow plan may still be run and watched")
	var half_sail = plan([2,1],[2]); half_sail.stage = "trial"; half_sail.attempts = 1
	check(not R.validate(half_sail),"trial without two full belts rejected")
	for stage in ["delivery","aftermath","complete"]:
		var legal = plan([2,1,0],[2,1,0]); legal.stage = stage; legal.attempts = 1
		check(R.validate(legal),"completed %s is legal"%stage)
		var forged = plan([0,1,2],[0,1,2]); forged.stage = stage; forged.attempts = 1
		check(not R.validate(forged),"forged %s rejected"%stage)
	var no_attempt = plan([2,1,0],[2,1,0]); no_attempt.stage = "trial"
	check(not R.validate(no_attempt),"trial without an attempt rejected")
	# 一条带可以只排了一半（那只是还没排完），但不能重复、越界或超过三件。
	for bad in [[0,0,1],[0,1,3],[0,1,2,0],[-1,1,2],[1,2,3]]:
		var c = plan(bad,[]); check(not R.validate(c),"invalid belt order rejected")
	check(R.validate(plan([0,1],[])),"a half-ordered belt is legal while still being planned")
	var extra = plan([2,1,0],[2,1,0]); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = plan([2,1,0],[2,1,0]); old.sample = "workshop-gw05-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var early = plan([2,1,0],[2,1,0]); early.stage = "ready"
	check(not R.validate(early),"ready cannot already carry a plan")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw05-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(plan([2,1,0],[2,1,0]),R.validate),"save accepted plan")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(trial,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == plan([2,1,0],[2,1,0]),"restart restores saved plan")
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
	print("GW05 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

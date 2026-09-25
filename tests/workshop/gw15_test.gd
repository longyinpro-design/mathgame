extends SceneTree
const R = preload("res://scripts/workshop/gw15_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW15 rules watchdog fired")
		print("GW15 RULES: ",checks," checks, ",failures+1," failures")
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
func puzzle_for(period: int) -> Dictionary:
	var s = puzzle(); s.period = period
	return s
# 独立 oracle：从第 1 拍起一拍一拍地数，数到第 t 拍为止各周期出了几件；
# 不复用被测代码的除法、counts() 或判定。
func oracle_counts(t: int) -> Array:
	var out = []
	for period in [3,4,5]:
		var made = 0
		var beat = period
		while beat <= t:
			made += 1
			beat += period
		out.append(made)
	return out
func oracle_distinguishing(t: int) -> bool:
	var values = oracle_counts(t)
	return values[0] != values[1] and values[1] != values[2] and values[0] != values[2]
# 隐藏 period 的机器走到第 t 拍、开过窗、挂好牌的状态；assigned 为 0 表示还没挂。
func observed_at(t: int, period: int, assigned: int) -> Dictionary:
	var s = R.select_time(puzzle_for(period),t)
	if s.is_empty(): return {}
	s = R.open_window(s)
	if s.is_empty() or assigned == 0: return s
	return R.hang(s,assigned)
func run() -> void:
	# 一、独立枚举 1～12 拍：三种周期的累计数、可区分时刻与最早时刻全部对照 oracle。
	var distinguishing = []
	for t in range(1,13):
		check(R.counts(t) == oracle_counts(t),"counts match the oracle at %d"%t)
		check(R.distinguishing(t) == oracle_distinguishing(t),"distinguishing matches the oracle at %d"%t)
		if oracle_distinguishing(t): distinguishing.append(t)
	check(distinguishing == [9,12],"only nine and twelve tell all three machines apart")
	check(R.distinguishing_times() == distinguishing,"distinguishing times match the oracle")
	check(R.earliest() == 9,"nine is the earliest distinguishing observation")
	check(R.counts(9) == [3,2,1],"nine shows three, two, one")
	check(R.counts(8) == [2,2,1],"eight shows two, two, one")
	check(R.counts(10) == [3,2,2],"ten shows three, two, two")
	check(R.counts(12) == [4,3,2],"twelve shows four, three, two")
	check(R.counts(0) == [0,0,0],"nothing has been made at beat zero")
	check(not R.distinguishing(0) and not R.distinguishing(13),"times outside 1..12 never distinguish")
	check(R.earliest() == distinguishing[0],"earliest is the first distinguishing time")
	# 二、三份撞在哪：每一拍都要说出真实的混淆，可区分的时刻没有混淆。
	for t in range(1,13):
		if oracle_distinguishing(t):
			check(R.collision_note(t) == "","distinguishing %d has no collision"%t)
		else:
			check(not R.collision_note(t).is_empty(),"confusing %d names the collision"%t)
	check("3 拍和 4 拍都是 2 件" in R.collision_note(8),"eight blames the three/four collision")
	check("4 拍和 5 拍都是 2 件" in R.collision_note(10),"ten blames the four/five collision")
	check("4 拍和 5 拍都是 1 件" in R.collision_note(6),"six blames the four/five collision")
	check("3 拍和 4 拍都是 1 件" in R.collision_note(4),"four blames the three/four collision")
	check("3 拍、4 拍、5 拍都是 0 件" in R.collision_note(1),"one blames all three")
	check(R.count_text(9) == "3 拍 3 件 · 4 拍 2 件 · 5 拍 1 件","nine reads back the three counts")
	# 三、开窗读数与反查周期：每个时刻、每个隐藏身份都对得上 oracle。
	for t in range(1,13):
		for period in R.PERIODS:
			var s = R.select_time(puzzle_for(period),t)
			check(R.validate(s),"a locked time at %d stays legal"%t)
			s = R.open_window(s)
			check(R.observed(s) == oracle_counts(t)[period-R.PERIOD_MIN],
				"the window shows the oracle count at %d for period %d"%[t,period])
			if R.distinguishing(t):
				check(R.period_for(t,R.observed(s)) == period,"the window count maps back to period %d at %d"%[period,t])
	# 四、逐格判定：12 个时刻 × 3 个隐藏身份 × 4 种挂法，只有第 9 拍挂对牌才成立。
	for t in range(1,13):
		for period in R.PERIODS:
			for assigned in [0] + R.PERIODS:
				var s = observed_at(t,period,assigned)
				check(R.validate(s),"the state at %d/%d/%d stays legal"%[t,period,assigned])
				var expect = t == 9 and assigned == period
				check(R.solved(s) == expect,"solved exactly at nine with the right plaque, %d/%d/%d"%[t,period,assigned])
				check(R.shortfalls(s).is_empty() == expect,"shortfalls empty exactly on the answer, %d/%d/%d"%[t,period,assigned])
		var locked = R.select_time(puzzle(),t)
		check(not R.solved(locked),"a locked time without an open window never solves")
		check("还没开窗" in R.shortfalls(locked)[0],"time %d asks for the window"%t)
	# 五、阶段推进与操作守卫。
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.fresh().period == R.HIDDEN and R.HIDDEN == 4,"fresh fixes the machine identity at four")
	check(R.validate(R.fresh()),"the fresh state is legal")
	check(R.select_time(R.fresh(),9).is_empty(),"no locking a time during dialogue")
	check(R.move_time(R.fresh(),1).is_empty(),"no moving the time during dialogue")
	check(R.open_window(R.fresh()).is_empty(),"no opening the window during dialogue")
	check(R.hang(R.fresh(),4).is_empty(),"no hanging a plaque during dialogue")
	var walk = R.fresh()
	for i in range(3): walk = R.advance(walk)
	check(walk.stage == "approach" and walk.beat == 2,"dialogue hands over to the walk-in")
	for i in range(2): walk = R.advance(walk)
	check(walk.stage == "puzzle","player starts the puzzle by hand")
	check(R.open_window(s).is_empty(),"the window needs a locked time first")
	check(R.hang(s,4).is_empty(),"a plaque needs an open window first")
	check(R.select_time(s,0).is_empty() and R.select_time(s,13).is_empty(),"times outside 1..12 are refused")
	var nine = R.select_time(s,9)
	check(nine.observe == 9 and R.validate(nine),"locking nine is legal")
	check(nine.tried == [9],"the locked time is recorded once")
	check(R.select_time(nine,9).is_empty(),"re-locking the same time is a no-op")
	check(R.select_time(nine,8).tried == [8,9],"a second time is appended in order")
	check(R.move_time(s,-1).observe == 1,"stepping before any lock lands on the first time")
	check(R.move_time(nine,-1).observe == 8 and R.move_time(nine,1).observe == 10,"stepping one time at a time")
	check(R.move_time(R.select_time(s,12),1).is_empty(),"stepping clamps at twelve")
	check(R.move_time(s,-2).observe == 1,"stepping back before any lock clamps at one")
	var opened = R.open_window(nine)
	check(opened.opened and R.validate(opened),"opening the window at nine is legal")
	check(R.open_window(opened).is_empty(),"the window opens only once")
	check(R.select_time(opened,12).is_empty() and R.move_time(opened,1).is_empty(),"the time is frozen once the window is open")
	check(R.hang(opened,3).assigned == 3,"a plaque can be hung after the window opens")
	check(R.hang(R.hang(opened,3),3).is_empty(),"re-hanging the same plaque is a no-op")
	check(R.hang(R.hang(opened,3),5).assigned == 5,"the plaque can be changed")
	check(R.hang(opened,2).is_empty() and R.hang(opened,6).is_empty(),"periods outside 3..5 are refused")
	check(nine.opened == false and nine.assigned == 0,"locking never opens the window by itself")
	# 六、关键反例：晚一拍、混淆的一拍、碰巧猜中、挂错牌。
	var twelve = observed_at(12,4,4)
	check(R.distinguishing(12) and not R.solved(twelve),"twelve distinguishes but is not the earliest")
	check("第 9 拍更早" in R.shortfalls(twelve)[0],"twelve is refused because nine is earlier")
	check(R.advance(twelve).is_empty(),"twelve cannot be claimed")
	var eight = observed_at(8,4,4)
	check(eight.assigned == R.HIDDEN and not R.solved(eight),"guessing the hidden machine is not enough at eight")
	check("分不清" in R.shortfalls(eight)[0] and "3 拍和 4 拍都是 2 件" in R.shortfalls(eight)[0],"eight names the real confusion")
	check(R.advance(eight).is_empty(),"eight cannot be claimed")
	var ten = observed_at(10,4,4)
	check(not R.solved(ten) and "4 拍和 5 拍都是 2 件" in R.shortfalls(ten)[0],"ten is still confused")
	var wrong = observed_at(9,4,5)
	check(not R.solved(wrong),"a wrong plaque at nine is refused")
	check("对应的是 4 拍" in R.shortfalls(wrong)[0] and "挂的是 5 拍" in R.shortfalls(wrong)[0],"the wrong plaque names the real mapping")
	check(R.solved(R.hang(wrong,4)),"the plaque can be corrected in place")
	var bare = R.open_window(R.select_time(puzzle(),9))
	check("还没挂周期牌" in R.shortfalls(bare)[0],"an open window without a plaque is named")
	check("先从第 1～12 拍里锁定" in R.shortfalls(puzzle())[0],"an unlocked time is named first")
	# 七、提交只在解上通过，交付后仍留着这一次观察。
	check(R.advance(puzzle()).is_empty(),"an unstarted puzzle cannot be claimed")
	check(R.advance(R.select_time(puzzle(),9)).is_empty(),"a locked time alone cannot be claimed")
	check(R.advance(bare).is_empty(),"an open window without a plaque cannot be claimed")
	var answer = observed_at(9,4,4)
	check(R.solved(answer) and R.shortfalls(answer).is_empty(),"nine with the four-beat plaque is the answer")
	var delivery = R.advance(answer)
	check(delivery.stage == "delivery" and R.validate(delivery),"the real answer enters delivery")
	check(delivery.period == 4 and delivery.observe == 9 and delivery.assigned == 4,"delivery keeps the observation")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	check(answer.period == 4 and delivery.period == 4 and done.period == 4,"actions never redraw the machine identity")
	# 八、撤销与重摆：时刻、开窗、周期牌与比较表都跟着快照走。
	var more = R.select_time(R.select_time(puzzle(),8),12)
	check(more.tried == [8,12],"compared times stay in order")
	check(R.restore(more,{"observe":9,"opened":false,"assigned":0,"tried":[9]}).observe == 9,"undo restores the locked time")
	var undone = R.restore(answer,{"observe":9,"opened":true,"assigned":5,"tried":[8,9]})
	check(undone.observe == 9 and undone.opened and undone.assigned == 5 and undone.tried == [8,9],"undo restores the window and plaque")
	check(undone.period == 4,"undo keeps the machine identity")
	var restored = R.restore(answer,{"observe":0,"opened":false,"assigned":0,"tried":[]})
	check(restored.observe == 0 and not restored.opened and restored.assigned == 0 and restored.tried.is_empty(),"reset clears the observation")
	check(restored.period == 4 and R.validate(restored),"reset keeps the identity and stays legal")
	check(R.restore(puzzle(),{"observe":0}).is_empty(),"an incomplete snapshot is refused")
	check(R.restore(puzzle(),{"observe":9,"opened":false,"assigned":4,"tried":[9]}).is_empty(),"an illegal snapshot is refused")
	var helped = R.select_time(puzzle(),9); helped.hint = 4
	check(R.restore(helped,{"observe":0,"opened":false,"assigned":0,"tried":[]}).hint == 4,"undo retains help")
	# 九、伪造与坏档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = answer.duplicate(true); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var late = twelve.duplicate(true); late.stage = stage
		check(not R.validate(late),"forged %s from twelve is rejected"%stage)
		var confused = eight.duplicate(true); confused.stage = stage
		check(not R.validate(confused),"forged %s from eight is rejected"%stage)
		var half = bare.duplicate(true); half.stage = stage
		check(not R.validate(half),"half-done %s is rejected"%stage)
	check(R.validate(puzzle()),"an unstarted puzzle is legal")
	for bad_period in [0,2,6,4.0,true,"4"]:
		var c = puzzle(); c.period = bad_period
		check(not R.validate(c),"invalid period rejected")
	for bad_observe in [-1,13,9.0,true]:
		var c = R.select_time(puzzle(),9); c.observe = bad_observe
		check(not R.validate(c),"invalid observation time rejected")
	var stray = puzzle(); stray.tried = [9]
	check(not R.validate(stray),"compared times without a locked time are rejected")
	var missing = R.select_time(puzzle(),9); missing.tried = []
	check(not R.validate(missing),"a locked time missing from the comparison list is rejected")
	for bad_tried in [[9,9],[12,9],[0],[13],[8,8,9],[9.0],["9"]]:
		var c = R.select_time(puzzle(),9); c.tried = bad_tried
		check(not R.validate(c),"invalid comparison list rejected")
	var full = R.select_time(puzzle(),12); full.tried = range(1,14)
	check(not R.validate(full),"an oversized comparison list is rejected")
	var orphan = R.hang(R.open_window(R.select_time(puzzle(),9)),4); orphan.opened = false
	check(not R.validate(orphan),"a plaque without an open window is rejected")
	var headless = R.open_window(R.select_time(puzzle(),9)); headless.observe = 0; headless.tried = []
	check(not R.validate(headless),"an open window without a locked time is rejected")
	for bad_opened in [1,0,"true",null]:
		var c = R.select_time(puzzle(),9); c.opened = bad_opened
		check(not R.validate(c),"invalid window flag rejected")
	for bad_assigned in [1,2,6,4.0,true]:
		var c = R.open_window(R.select_time(puzzle(),9)); c.assigned = bad_assigned
		check(not R.validate(c),"invalid plaque rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = answer.duplicate(true); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = answer.duplicate(true); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early = R.select_time(puzzle(),9); early.stage = "ready"
	check(not R.validate(early),"a locked time cannot appear during dialogue")
	var chatty = puzzle(); chatty.hint = 2; chatty.stage = "ready"
	check(not R.validate(chatty),"help cannot appear during dialogue")
	var extra = answer.duplicate(true); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = answer.duplicate(true); old.sample = "workshop-gw15-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	check(not R.validate(null) and not R.validate({}) and not R.validate([]),"non-states are rejected")
	# 十、存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw15-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(nine,R.validate),"save accepted a locked time")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(answer,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == nine,"restart restores the locked time")
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
	print("GW15 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

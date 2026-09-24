extends SceneTree
const R = preload("res://scripts/workshop/gw06_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 120.0:
		push_error("GW06 rules watchdog fired")
		print("GW06 RULES: ",checks," checks, ",failures+1," failures")
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
func plan(order: Array) -> Dictionary:
	var s = puzzle(); s.order = order.duplicate()
	return s
# 长度 1 到 10 的全部工单：每一炉要么小模、要么大模。
func all_orders() -> Array:
	var out = []
	for length in range(1,R.MAX_BATCHES+1):
		for code in range(1<<length):
			var order = []
			for bit in range(length): order.append(R.SMALL if (code>>bit)&1 else R.LARGE)
			out.append(order)
	return out
# 独立把工单摊成一拍一拍的流水：先换模、再开炉，首次装模不占换模拍。
# 与被测的 schedule() 走的是完全不同的写法，用来交叉核对。
func oracle_ticks(order: Array) -> Array:
	var ticks = []
	for index in range(order.size()):
		if index > 0 and order[index-1] != order[index]:
			ticks.append({"kind":"change","mould":0})
		ticks.append({"kind":"fire","mould":order[index]})
	return ticks
func run() -> void:
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.place(R.fresh(),R.SMALL).is_empty(),"no firing during dialogue")
	check(R.advance(s).is_empty(),"cannot trial an empty work order")
	check(R.makespan(plan([])) == 0 and R.output(plan([])) == 0,"an empty order makes nothing")
	check(not R.ready(plan([])),"an empty order is not ready")
	check(R.ready(plan([R.SMALL])),"one batch is enough to run")
	# 题面数字改动会改掉整道题，先钉住。
	check(R.SMALL == 3 and R.LARGE == 5 and R.NEED == 31 and R.DEADLINE == 8,"author numbers unchanged")
	check(R.MAX_BATCHES == 10,"the work order holds ten batches")
	# 全部 2046 张工单逐张走一遍：时刻表与独立流水逐拍对照，并找全部合法解。
	var solutions = []
	var with_target = 0
	for order in all_orders():
		var candidate = plan(order)
		check(R.validate(candidate),"legal work order")
		var mine = R.schedule(candidate)
		var ticks = oracle_ticks(order)
		var flat = []
		for tick in ticks: flat.append([tick.kind,tick.mould])
		var rows = []
		for change in mine.changes: rows.append({"kind":"change","start":change.start,"end":change.end,"mould":0})
		for batch in mine.batches: rows.append({"kind":"fire","start":batch.start,"end":batch.end,"mould":batch.mould})
		rows.sort_custom(func(a,b): return a.start < b.start)
		var mine_flat = []
		for row in rows: mine_flat.append([row.kind,row.mould])
		check(mine_flat == flat,"tick-by-tick schedule matches the flat oracle")
		var fired = 0
		var changed = 0
		for tick in ticks:
			if tick.kind == "fire": fired += 1
			else: changed += 1
		check(R.firing(candidate) == fired and R.changes_count(candidate) == changed,"counts match the flat oracle")
		check(R.makespan(candidate) == ticks.size(),"makespan matches the flat oracle")
		# 同一拍不能既换模又开炉：两排格子首尾相接，从不重叠。
		var overlap = false
		for i in range(1,rows.size()):
			if rows[i].start < rows[i-1].end: overlap = true
		check(not overlap,"no tick is both change and fire")
		check(R.output(candidate) == 3*order.count(R.SMALL)+5*order.count(R.LARGE),"output matches a direct count")
		var wanted = R.output(candidate) == R.NEED
		if wanted: with_target += 1
		check(R.solved(candidate) == (wanted and ticks.size() <= R.DEADLINE),"solved follows output and the flat schedule")
		if R.solved(candidate): solutions.append(order)
	check(solutions == [[3,3,5,5,5,5,5],[5,5,5,5,5,3,3]],"only the two grouped seven-batch orders pass")
	check(with_target == 57,"fifty-seven orders hit thirty-one rings but only two also make the deadline")
	# 设计点名的反例：产量对、时间不够。
	var nine = plan([3,3,3,3,3,3,3,5,5])
	check(R.output(nine) == R.NEED and R.firing(nine) == 9,"nine batches alone already cost nine beats")
	check(R.makespan(nine) == 10,"nine batches with one mould change cost ten")
	check(not R.solved(nine),"nine batches fail on time")
	var mixed = plan([3,5,3,5,5,5,5])
	check(R.output(mixed) == R.NEED and R.makespan(mixed) == 10,"interleaved seven batches cost ten beats")
	check(not R.solved(mixed),"interleaving fails on time")
	check(R.makespan(plan([5,5,5,5,5,3,3])) == 8,"large-first grouping finishes in eight")
	check(R.changes_count(plan([3,3,5,5,5,5,5])) == 1,"one mould change is enough when grouped")
	# 说明只指出真实违反的那一条。
	check(R.shortfalls(plan([]))[0].begins_with("工单上还没有炉次"),"an empty order names itself")
	check(R.shortfalls(plan([3]))[0].begins_with("这套排法只出 3 枚"),"a short order names the missing rings")
	check("差 28 枚" in R.shortfalls(plan([3]))[0],"the gap is spelled out")
	check(R.shortfalls(plan([5,5,5,5,5,5,5]))[0].begins_with("这套排法出 35 枚"),"too many rings are named")
	check("多了 4 枚" in R.shortfalls(plan([5,5,5,5,5,5,5]))[0],"the surplus is spelled out")
	check(R.shortfalls(plan([3,5,3,5,5,5,5]))[0].begins_with("这套排法到第 10 拍"),"a slow order names its finish")
	check(R.shortfalls(plan([3,3,5,5,5,5,5])).is_empty(),"the author order has nothing to explain")
	# 排炉与撤炉：满十炉不能再加，撤掉中间一炉不影响其余顺序。
	var one = R.place(puzzle(),R.SMALL)
	check(one.order == [3],"first batch lands at the end of the work order")
	var two = R.place(one,R.LARGE)
	check(two.order == [3,5],"the next batch appends")
	check(R.remove_at(two,0).order == [5],"removing the head keeps the rest")
	check(R.remove_at(two,5).is_empty(),"removing something absent is refused")
	var ten = puzzle(); ten.order = [3,5,3,5,3,5,3,5,3,5]
	check(R.place(ten,R.SMALL).is_empty(),"a full work order takes no more batches")
	check(R.place(puzzle(),7).is_empty(),"only the two moulds exist")
	check(R.clear_order(two).order.is_empty(),"the order can be cleared")
	check(R.clear_order(puzzle()).is_empty(),"clearing an empty order is a no-op")
	check(R.remove_at(R.fresh(),0).is_empty(),"no removing during dialogue")
	# 撤销恢复工单，求助与尝试次数留着。
	var helped = R.place(puzzle(),R.SMALL); helped.hint = 2; helped.attempts = 3
	check(R.restore(helped,{"order":[]}).order.is_empty(),"undo clears the work order")
	check(R.restore(helped,{"order":[5,5,3]}).order == [5,5,3],"undo restores the work order")
	check(R.restore(helped,{"order":[]}).hint == 2,"undo retains help and attempts")
	check(R.restore(puzzle(),{}).is_empty(),"a snapshot without an order is refused")
	# 完整走一遍：产量不对或超时的工单退回排炉，对的才进交货。
	var trial = R.advance(plan([3]))
	check(trial.stage == "trial" and trial.attempts == 1,"a short order may still be run")
	check(R.validate(trial),"trial state is legal")
	var back = R.advance(trial)
	check(back.stage == "puzzle" and R.validate(back),"a short order returns to planning")
	check(R.back_to_plan(trial).stage == "puzzle","trial can be abandoned")
	var slow = R.advance(plan([3,5,3,5,5,5,5]))
	check(slow.stage == "trial","a slow order may be run")
	check(R.advance(slow).stage == "puzzle","a slow order returns to planning")
	var good = R.advance(plan([3,3,5,5,5,5,5]))
	check(good.stage == "trial","the author order may be run")
	var delivery = R.advance(good)
	check(delivery.stage == "delivery" and R.validate(delivery),"verified order enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 伪造与坏档一律拒绝：试演那一格允许错工单（本来就该看得到失败），
	# 但空工单不能进试演，交货之后的每一格都必须是真解出来的。
	var slow_sail = plan([3,5,3,5,5,5,5]); slow_sail.stage = "trial"; slow_sail.attempts = 1
	check(R.validate(slow_sail),"a slow order may still be run and watched")
	var short_sail = plan([3]); short_sail.stage = "trial"; short_sail.attempts = 1
	check(R.validate(short_sail),"a short order may still be run and watched")
	var empty_sail = plan([]); empty_sail.stage = "trial"; empty_sail.attempts = 1
	check(not R.validate(empty_sail),"trial without a work order rejected")
	for stage in ["delivery","aftermath","complete"]:
		var legal = plan([3,3,5,5,5,5,5]); legal.stage = stage; legal.attempts = 1
		check(R.validate(legal),"completed %s is legal"%stage)
		var forged = plan([3,5,3,5,5,5,5]); forged.stage = stage; forged.attempts = 1
		check(not R.validate(forged),"forged %s rejected"%stage)
	var no_attempt = plan([3,3,5,5,5,5,5]); no_attempt.stage = "trial"
	check(not R.validate(no_attempt),"trial without an attempt rejected")
	for bad in [[7],[3,7],[0],[-3],[3,3,3,3,3,3,3,3,3,3,3]]:
		var c = plan(bad); check(not R.validate(c),"invalid work order rejected")
	var extra = plan([3,3,5,5,5,5,5]); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = plan([3,3,5,5,5,5,5]); old.sample = "workshop-gw06-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var early = plan([3]); early.stage = "ready"
	check(not R.validate(early),"ready cannot already carry an order")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw06-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(plan([3,3,5,5,5,5,5]),R.validate),"save accepted order")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(trial,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == plan([3,3,5,5,5,5,5]),"restart restores saved order")
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
	print("GW06 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

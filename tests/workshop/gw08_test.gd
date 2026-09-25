extends SceneTree
const R = preload("res://scripts/workshop/gw08_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW08 rules watchdog fired")
		print("GW08 RULES: ",checks," checks, ",failures+1," failures")
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
# 用最笨的办法各除一遍两张记录，不复用被测代码里的判定。
func oracle_candidates(total: int, remainder: int) -> Array:
	var out = []
	for capacity in range(R.CAP_MIN,R.CAP_MAX+1):
		if total % capacity == remainder: out.append(capacity)
	return out
func tested_both(capacity: int) -> Dictionary:
	var s = R.select(puzzle(),capacity)
	s = R.replay(s,0)
	return R.replay(s,1)
func run() -> void:
	# 两张记录各自的候选与交集，独立除一遍对照。
	var first = oracle_candidates(R.RECORDS[0],R.REMAINDERS[0])
	var second = oracle_candidates(R.RECORDS[1],R.REMAINDERS[1])
	check(first == [8,16],"record one leaves 8 and 16")
	check(second == [8,10],"record two leaves 8 and 10")
	check(R.candidates(0) == first,"record one candidates match the oracle")
	check(R.candidates(1) == second,"record two candidates match the oracle")
	check(R.solution() == [8],"only 8 satisfies both records")
	# 除法与逐格判定。
	for capacity in range(R.CAP_MIN,R.CAP_MAX+1):
		for record in range(2):
			var total = R.RECORDS[record]
			var parts = R.division(total,capacity)
			check(parts[0] == total/capacity and parts[1] == total%capacity,"division matches the oracle")
			check(R.matches(record,capacity) == (total%capacity == R.REMAINDERS[record]),"match agrees with the oracle")
	check(not R.matches(0,4) and not R.matches(0,17),"capacities outside 5..16 never match")
	# 阶段推进与操作守卫。
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.select(R.fresh(),8).is_empty(),"no choosing a capacity during dialogue")
	check(R.move_capacity(R.fresh(),1).is_empty(),"no moving a capacity during dialogue")
	check(R.replay(s,0).is_empty(),"no replay before a capacity is proposed")
	var eight = R.select(s,8)
	check(eight.capacity == 8 and R.validate(eight),"choosing 8 is legal")
	check(R.select(eight,8).is_empty(),"re-choosing the same capacity is a no-op")
	check(R.select(eight,4).is_empty() and R.select(eight,17).is_empty(),"capacities outside 5..16 are refused")
	check(R.move_capacity(eight,-1).capacity == 7 and R.move_capacity(eight,1).capacity == 9,"stepping one slot at a time")
	var bottom = R.select(puzzle(),R.CAP_MIN)
	var top = R.select(puzzle(),R.CAP_MAX)
	check(R.move_capacity(bottom,-1).is_empty() and R.move_capacity(top,1).is_empty(),"stepping clamps at both ends")
	var start = R.move_capacity(puzzle(),1)
	check(start.capacity == R.CAP_MIN,"the first step lands on the lowest capacity")
	check(R.replay(eight,-1).is_empty() and R.replay(eight,2).is_empty(),"only two records exist")
	check(R.replay(s,0).is_empty(),"replay requires a proposed capacity")
	var one = R.replay(eight,0)
	check(one.tested_first == [8] and one.tested_second.is_empty(),"replaying record one records 8")
	check(R.replay(one,0).tested_first == [8],"replaying the same record twice keeps one entry")
	check(R.replay(R.replay(one,1),0).tested_first == [8],"record one is not affected by record two")
	# 判定：两张都重演且都相符才算解。
	for capacity in range(R.CAP_MIN,R.CAP_MAX+1):
		var both = tested_both(capacity)
		check(R.solved(both) == (capacity == 8),"only 8 solves, %d does not"%capacity)
		check(R.validate(both),"tested state stays legal")
	var half = R.replay(eight,0)
	check(not R.solved(half),"one matching record alone is not enough")
	check(R.shortfalls(half).size() == 1 and "记录二还没重演过" in R.shortfalls(half)[0],"the missing replay is named")
	check(R.shortfalls(puzzle())[0].begins_with("先从旧槽板里"),"no capacity is called out first")
	var ten = tested_both(10)
	var ten_gaps = R.shortfalls(ten)
	check(ten_gaps.size() == 1 and "剩 5 根" in ten_gaps[0] and "记录一写的是剩 3 根" in ten_gaps[0],"a mismatch names the real remainder")
	check(R.shortfalls(tested_both(8)).is_empty(),"the real answer has no shortfall")
	# 提交与完整流程。
	check(R.advance(ten).is_empty(),"a mismatching capacity cannot be claimed")
	check(R.advance(half).is_empty(),"an untested record cannot be claimed")
	var delivery = R.advance(tested_both(8))
	check(delivery.stage == "delivery" and R.validate(delivery),"both records verified enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 撤销与重摆：候选、两张重演表都跟着快照走。
	var more = R.replay(R.replay(tested_both(8),0),1)
	check(more.tested_first == [8] and more.tested_second == [8],"replaying again keeps the tables clean")
	check(R.restore(more,{"capacity":10,"tested_first":[10],"tested_second":[10]}).capacity == 10,"undo restores the candidate")
	check(R.restore(more,{"capacity":10,"tested_first":[10],"tested_second":[10]}).tested_first == [10],"undo restores the replay tables")
	var cleared = R.restore(more,{"capacity":0,"tested_first":[],"tested_second":[]})
	check(cleared.capacity == 0 and cleared.tested_first.is_empty() and cleared.tested_second.is_empty(),"reset clears the record")
	# 伪造与坏档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = tested_both(8); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = tested_both(10); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
		var partial = R.replay(R.select(puzzle(),8),0); partial.stage = stage
		check(not R.validate(partial),"half-tested %s rejected"%stage)
	check(R.validate(puzzle()),"zero capacity means not yet proposed")
	for bad_capacity in [-1,4,17,1.5,true]:
		var c = puzzle(); c.capacity = bad_capacity
		check(not R.validate(c),"invalid capacity rejected")
	for bad_tested in [[4],[17],[8,8],[8,1.5],[true],range(R.CAP_MIN,R.CAP_MAX+2)]:
		var c = tested_both(8); c.tested_first = bad_tested
		check(not R.validate(c),"invalid replay table rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = tested_both(8); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = tested_both(8); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early = R.select(puzzle(),8); early.stage = "arrival"
	check(not R.validate(early),"a capacity cannot appear during dialogue")
	var extra = tested_both(8); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = tested_both(8); old.sample = "workshop-gw08-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var helped = R.select(puzzle(),8); helped.hint = 4
	check(R.restore(helped,{"capacity":0,"tested_first":[],"tested_second":[]}).hint == 4,"undo retains help")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw08-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(one,R.validate),"save accepted the partial record")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(tested_both(8),R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == one,"restart restores the saved record")
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
	print("GW08 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

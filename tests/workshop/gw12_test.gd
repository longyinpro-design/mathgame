extends SceneTree
const R = preload("res://scripts/workshop/gw12_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW12 rules watchdog fired")
		print("GW12 RULES: ",checks," checks, ",failures+1," failures")
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
# 独立 oracle：最笨的枚举，一枚一枚地数满托，不复用被测代码的除法与判定。
func oracle(capacity: int) -> Array:
	var rest = 23
	var first = 0
	while rest >= capacity:
		rest -= capacity; first += 1
	var carry = rest
	rest += 24
	var second = 0
	while rest >= capacity:
		rest -= capacity; second += 1
	return [first,carry,second,rest]
# 按 oracle 的执行把两班真的走一遍，用来逐格对照被测代码。
func execute(capacity: int) -> Dictionary:
	var parts = oracle(capacity)
	var s = R.select(puzzle(),capacity)
	s = R.set_first_keep(s,parts[1])
	return R.set_second_keep(s,parts[3])
func run() -> void:
	# 一、独立枚举 3～12 槽的两班分配：只有 5 槽让交接册（9 托、剩 2 枚）成立。
	var solutions = []
	var distractors = []
	for capacity in range(R.CAP_MIN,R.CAP_MAX+1):
		var parts = oracle(capacity)
		check(R.plan(capacity) == parts,"plan matches the oracle at %d"%capacity)
		check(parts[0]*capacity+parts[1] == 23,"first shift keeps 23 whole at %d"%capacity)
		check(parts[1]+24 == parts[2]*capacity+parts[3],"second shift keeps the carry whole at %d"%capacity)
		check((parts[0]+parts[2])*capacity+parts[3] == 47,"both shifts keep 47 whole at %d"%capacity)
		check(parts[1] < capacity and parts[3] < capacity,"leftovers are under one tray at %d"%capacity)
		if parts[0]+parts[2] == 9 and parts[3] == 2: solutions.append(capacity)
		elif parts[3] == 2: distractors.append(capacity)
	check(solutions == [5],"only five slots fills the handover book")
	check(distractors == [3,9],"three and nine slots also end at two but miss the tray count")
	check(R.solution() == solutions,"solution matches the oracle")
	check(R.plan(2).is_empty() and R.plan(13).is_empty(),"capacities outside 3..12 have no plan")
	check(oracle(5) == [4,3,5,2],"five slots: four trays keep three, five trays keep two")
	# 每一格的合法余料只有 oracle 的那一个，别的留法都装不成整托。
	for capacity in range(R.CAP_MIN,R.CAP_MAX+1):
		var parts = oracle(capacity)
		for keep in range(0,R.BOX+1):
			check(R.keep_legal(23,capacity,keep) == (keep == parts[1]),"first leftover %d is legal only at %d" % [keep,parts[1]])
			check(R.keep_legal(parts[1]+24,capacity,keep) == (keep == parts[3]),"final leftover %d is legal only at %d" % [keep,parts[3]])
	check(not R.keep_legal(23,5,5) and not R.keep_legal(23,5,12),"a leftover of a whole tray is refused")
	check(not R.keep_legal(23,2,1) and not R.keep_legal(23,13,1),"capacities outside 3..12 are refused")
	# 二、逐格执行：只有 5 槽解得开，其余都差在满托数或最后余料。
	for capacity in range(R.CAP_MIN,R.CAP_MAX+1):
		var s = execute(capacity)
		var parts = oracle(capacity)
		check(not s.is_empty() and R.validate(s),"executing %d slots stays legal"%capacity)
		check(R.solved(s) == (capacity == 5),"only five slots solves, %d does not"%capacity)
		check(R.first_trays(s) == parts[0] and R.second_trays(s) == parts[2],"tray counts match the oracle at %d"%capacity)
		check(R.total_trays(s) == parts[0]+parts[2] and s.second_keep == parts[3],"tally matches the oracle at %d"%capacity)
		check(s.tried == [capacity],"a finished run is written into the trial list")
		check(R.shortfalls(s).is_empty() == (capacity == 5),"shortfalls are empty exactly on the answer")
	check(R.shortfalls(execute(9))[0].begins_with("最后确实剩 2 枚"),"nine slots ends at two but the tray count is named")
	check("5 个满托" in R.shortfalls(execute(9))[0],"the wrong tray count is spoken")
	check("15 个满托" in R.shortfalls(execute(3))[0],"three slots keeps two twice but overfills the book")
	check("11 个满托" in R.shortfalls(execute(4))[0],"four slots overfills the book")
	# 三、阶段推进与操作守卫。
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.select(R.fresh(),5).is_empty(),"no choosing a capacity during dialogue")
	check(R.move_capacity(R.fresh(),1).is_empty(),"no moving a capacity during dialogue")
	check(R.set_first_keep(R.fresh(),3).is_empty(),"no leftover during dialogue")
	var walk = R.fresh()
	for i in range(3): walk = R.advance(walk)
	check(walk.stage == "approach" and walk.beat == 2,"dialogue hands over to the walk-in")
	for i in range(2): walk = R.advance(walk)
	check(walk.stage == "puzzle","player starts the puzzle by hand")
	check(R.set_first_keep(s,3).is_empty(),"no leftover before a capacity is proposed")
	var nine = R.select(s,9)
	check(nine.capacity == 9 and R.validate(nine),"choosing nine is legal")
	check(R.select(nine,9).is_empty(),"re-choosing the same capacity is a no-op")
	check(R.select(nine,2).is_empty() and R.select(nine,13).is_empty(),"capacities outside 3..12 are refused")
	check(R.move_capacity(nine,-1).capacity == 8 and R.move_capacity(nine,1).capacity == 10,"stepping one slot at a time")
	var bottom = R.select(puzzle(),R.CAP_MIN)
	var top = R.select(puzzle(),R.CAP_MAX)
	check(R.move_capacity(bottom,-1).is_empty() and R.move_capacity(top,1).is_empty(),"stepping clamps at both ends")
	check(R.move_capacity(puzzle(),1).capacity == R.CAP_MIN,"the first step lands on the lowest capacity")
	# 典型反例：把最后剩的 2 枚当成第一班余料，9 槽下第一班就装不成整托。
	check(R.set_first_keep(nine,2).is_empty(),"nine slots cannot keep the final two after the first shift")
	check("装不成 9 枚一托的整托" in R.keep_reason(23,9,2),"the refusal names the broken division")
	check("够再装一个满托" in R.keep_reason(23,5,7),"a leftover of a whole tray is refused with its own reason")
	var kept = R.set_first_keep(nine,5)
	check(kept.first_keep == 5 and kept.tried.is_empty(),"five is a legal first leftover at nine slots")
	check(R.set_first_keep(kept,5).is_empty(),"the first shift cannot be handed over twice")
	check(R.set_second_keep(kept,2).second_keep == 2,"two is a legal final leftover at nine slots")
	check(R.set_second_keep(kept,3).is_empty(),"the final leftover is judged against the carry")
	var switched = R.select(kept,5)
	check(switched.capacity == 5 and switched.first_keep == -1 and switched.second_keep == -1,"changing the capacity clears the run")
	# 四、提交只在解上通过。
	check(R.advance(puzzle()).is_empty(),"an unstarted puzzle cannot be claimed")
	check(R.advance(kept).is_empty(),"an unfinished second shift cannot be claimed")
	check(R.advance(execute(9)).is_empty(),"a mismatching run cannot be claimed")
	var delivery = R.advance(execute(5))
	check(delivery.stage == "delivery" and R.validate(delivery),"the real answer enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 五、撤销与重摆：槽数、两班执行与试过记录都跟着快照走。
	var both = R.set_second_keep(R.set_first_keep(R.select(execute(5),9),5),2)
	check(both.tried == [5,9],"a second slot is appended to the trial list")
	check(R.restore(both,{"capacity":5,"first_keep":-1,"second_keep":-1,"tried":[]}).capacity == 5,"undo restores the capacity")
	var back = R.restore(both,{"capacity":9,"first_keep":5,"second_keep":-1,"tried":[5]})
	check(back.first_keep == 5 and back.second_keep == -1,"undo restores a half-done run")
	check(back.tried == [5],"undo restores the trial list")
	var cleared = R.restore(both,{"capacity":0,"first_keep":-1,"second_keep":-1,"tried":[]})
	check(cleared.capacity == 0 and cleared.first_keep == -1 and cleared.tried.is_empty(),"reset clears the run")
	check(R.restore(puzzle(),{"capacity":0}).is_empty(),"an incomplete snapshot is refused")
	var helped = R.select(puzzle(),5); helped.hint = 4
	check(R.restore(helped,{"capacity":0,"first_keep":-1,"second_keep":-1,"tried":[]}).hint == 4,"undo retains help")
	# 六、伪造与坏档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = execute(5); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = execute(9); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
		var partial = R.set_first_keep(R.select(puzzle(),5),3); partial.stage = stage
		check(not R.validate(partial),"half-done %s rejected"%stage)
	check(R.validate(puzzle()),"zero capacity means not yet proposed")
	for bad_capacity in [-1,2,13,5.0,true]:
		var c = puzzle(); c.capacity = bad_capacity
		check(not R.validate(c),"invalid capacity rejected")
	for bad_keep in [-2,12,3.5,true]:
		var c = execute(5); c.first_keep = bad_keep
		check(not R.validate(c),"invalid first leftover rejected")
	for bad_keep in [-2,12,2.5,true]:
		var c = execute(5); c.second_keep = bad_keep
		check(not R.validate(c),"invalid final leftover rejected")
	var orphan = execute(5); orphan.first_keep = -1
	check(not R.validate(orphan),"a final leftover without the first shift is rejected")
	var crossed = execute(5); crossed.first_keep = 4
	check(not R.validate(crossed),"a first leftover that does not divide is rejected")
	for bad_tried in [[5,5],[9,5],[2],[13],[5,4],[5,3],["5"],[5.0],[5,5,5,5,5,5,5,5,5,5,5]]:
		var c = execute(5); c.tried = bad_tried
		check(not R.validate(c),"invalid trial list rejected")
	var stray = puzzle(); stray.tried = [5]
	check(not R.validate(stray),"trials without a capacity are rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = execute(5); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = execute(5); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early = R.set_first_keep(R.select(puzzle(),5),3); early.stage = "ready"
	check(not R.validate(early),"a run cannot appear during dialogue")
	var extra = execute(5); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = execute(5); old.sample = "workshop-gw12-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	# 七、存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw12-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(both,R.validate),"save accepted the trial list")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(execute(5),R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == both,"restart restores the saved record")
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
	print("GW12 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

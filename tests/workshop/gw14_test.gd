extends SceneTree
const R = preload("res://scripts/workshop/gw14_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW14 rules watchdog fired")
		print("GW14 RULES: ",checks," checks, ",failures+1," failures")
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
# 用最笨的办法一枚一枚除 20～80，不复用被测代码里的判定。
func oracle_candidates(tray: int, remainder: int) -> Array:
	var out = []
	for count in range(20,81):
		if count % tray == remainder: out.append(count)
	return out
func intersect(first: Array, second: Array) -> Array:
	var out = []
	for count in first:
		if second.has(count): out.append(count)
	return out
func all_tested(count: int) -> Dictionary:
	var s = R.select(puzzle(),count)
	for record in range(3): s = R.replay(s,record)
	return s
func run() -> void:
	# 三张记录各自的候选、前两张的交集与三张的交集，全部独立枚举对照。
	var first = oracle_candidates(R.TRAYS[0],R.REMAINDERS[0])
	var second = oracle_candidates(R.TRAYS[1],R.REMAINDERS[1])
	var third = oracle_candidates(R.TRAYS[2],R.REMAINDERS[2])
	var pair = intersect(first,second)
	var triple = intersect(pair,third)
	check(first == [23,27,31,35,39,43,47,51,55,59,63,67,71,75,79],"record one allows fifteen counts")
	check(second == [23,29,35,41,47,53,59,65,71,77],"record two allows ten counts")
	check(third == [22,27,32,37,42,47,52,57,62,67,72,77],"record three allows twelve counts")
	check(pair == [23,35,47,59,71],"the first two records leave five candidates")
	check(triple == [47],"the third record leaves only 47")
	check(R.candidates(0) == first,"record one candidates match the oracle")
	check(R.candidates(1) == second,"record two candidates match the oracle")
	check(R.candidates(2) == third,"record three candidates match the oracle")
	check(R.solution() == [47],"only 47 satisfies all three records")
	# 边界：20 与 80 都在盒里；同余但装不下的枚数不算候选。
	check(R.matches(0,R.BOX_MIN-1) == false and R.matches(0,R.BOX_MIN+3),"19 is outside the box, 23 is inside")
	check(R.matches(2,R.BOX_MAX) == false and R.matches(2,R.BOX_MAX-3),"80 does not fit record three, 77 does")
	for outside in [3,7,11,15,19,83,87,91,95,99]:
		check(not R.matches(0,outside) and not R.candidates(0).has(outside),"record one excludes %d"%outside)
	for outside in [5,11,17,83,89,95]:
		check(not R.matches(1,outside) and not R.candidates(1).has(outside),"record two excludes %d"%outside)
	for outside in [2,7,12,17,82,87,92,97]:
		check(not R.matches(2,outside) and not R.candidates(2).has(outside),"record three excludes %d"%outside)
	# 逐格除法与判定：20～80 的每一枚、三张记录都对照 oracle。
	for count in range(R.BOX_MIN,R.BOX_MAX+1):
		for record in range(3):
			var tray = R.TRAYS[record]
			var parts = R.division(count,tray)
			check(parts[0] == count/tray and parts[1] == count%tray,"division matches the oracle")
			check(R.matches(record,count) == (count%tray == R.REMAINDERS[record]),"match agrees with the oracle")
			if R.matches(record,count):
				check(parts[1] < tray,"a matching remainder is smaller than the tray")
	# 只满足两条的候选：三条记录两两配对都各有反例。
	for count in [23,35,59,71]:
		check(R.matches(0,count) and R.matches(1,count) and not R.matches(2,count),"%d satisfies only the first two"%count)
	check(R.matches(0,27) and R.matches(2,27) and not R.matches(1,27),"27 satisfies records one and three")
	check(R.matches(1,77) and R.matches(2,77) and not R.matches(0,77),"77 satisfies records two and three")
	# 阶段推进与操作守卫。
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.select(R.fresh(),47).is_empty(),"no choosing a count during dialogue")
	check(R.move_count(R.fresh(),1).is_empty(),"no moving a count during dialogue")
	check(R.list(R.fresh(),0).is_empty(),"no listing candidates during dialogue")
	check(R.replay(s,0).is_empty(),"no replay before a count is proposed")
	check(R.list(s,0).listed == [0] and R.validate(R.list(s,0)),"listing record one is legal")
	check(R.list(R.list(s,0),0).is_empty(),"listing the same record twice is a no-op")
	check(R.list(s,3).is_empty() and R.list(s,-1).is_empty(),"only three records exist")
	var all_listed = R.list(R.list(R.list(s,2),0),1)
	check(all_listed.listed == [0,1,2] and R.validate(all_listed),"listing all three records keeps them sorted")
	var selected = R.select(s,47)
	check(selected.count == 47 and R.validate(selected),"choosing 47 is legal")
	check(R.select(selected,47).is_empty(),"re-choosing the same count is a no-op")
	check(R.select(selected,19).is_empty() and R.select(selected,81).is_empty(),"counts outside 20..80 are refused")
	check(R.select(selected,20).count == 20 and R.select(selected,80).count == 80,"both box ends are choosable")
	check(R.move_count(selected,-1).count == 46 and R.move_count(selected,1).count == 48,"stepping one piece at a time")
	var bottom = R.select(s,R.BOX_MIN)
	var top = R.select(s,R.BOX_MAX)
	check(R.move_count(bottom,-1).is_empty() and R.move_count(top,1).is_empty(),"stepping clamps at both ends")
	check(R.move_count(s,1).count == R.BOX_MIN and R.move_count(s,-1).count == R.BOX_MIN,"the first step lands on the lowest count")
	check(R.replay(selected,-1).is_empty() and R.replay(selected,3).is_empty(),"only three records exist")
	var one = R.replay(selected,0)
	check(one.tested_first == [47] and one.tested_second.is_empty() and one.tested_third.is_empty(),"replaying record one records 47")
	check(R.replay(one,0).tested_first == [47],"replaying the same record twice keeps one entry")
	check(R.replay(R.replay(one,1),0).tested_first == [47],"record one is not affected by record two")
	# 判定：三张都复演且都相符才算解。
	for count in range(R.BOX_MIN,R.BOX_MAX+1):
		var all = all_tested(count)
		check(R.solved(all) == (count == 47),"only 47 solves, %d does not"%count)
		check(R.validate(all),"tested state stays legal")
	var half = R.replay(R.select(puzzle(),47),0)
	check(not R.solved(half),"one matching record alone is not enough")
	check(R.shortfalls(half).size() == 2 and "记录二还没复演过" in R.shortfalls(half)[0],"the missing replay is named")
	var two = R.replay(R.replay(R.select(puzzle(),47),0),1)
	check(not R.solved(two),"two matching records alone are not enough")
	check("记录三还没复演过" in R.shortfalls(two)[0],"the third record is the missing one")
	check(R.shortfalls(puzzle())[0].begins_with("先从 20～80 里"),"no count is called out first")
	var twenty_three = all_tested(23)
	var gaps = R.shortfalls(twenty_three)
	check(gaps.size() == 1 and "剩 3 枚" in gaps[0] and "记录三写的是剩 2 枚" in gaps[0],"a mismatch names the real remainder")
	var twenty_seven = R.shortfalls(all_tested(27))
	check(twenty_seven.size() == 1 and "剩 3 枚" in twenty_seven[0] and "记录二写的是剩 5 枚" in twenty_seven[0],"27 fails record two with the real remainder")
	var seventy_seven = R.shortfalls(all_tested(77))
	check(seventy_seven.size() == 1 and "剩 1 枚" in seventy_seven[0] and "记录一写的是剩 3 枚" in seventy_seven[0],"77 fails record one with the real remainder")
	check(R.shortfalls(all_tested(47)).is_empty(),"the real answer has no shortfall")
	# 判定、标记与排除表。
	check(R.mark(puzzle(),0) == "未提出","no count means no verdict")
	check(R.mark(selected,0) == "未复演","a chosen count is not yet replayed")
	check(R.mark(R.replay(selected,0),0) == "相符" and R.mark(R.replay(selected,1),0) == "未复演","only replayed records report")
	check(R.mark(R.replay(R.select(puzzle(),20),0),0) == "不符","20 does not match record one")
	check(R.tried_counts(one) == [47],"one tried count")
	check(R.tried_counts(all_tested(23)) == [23],"a mismatching candidate still counts as tried")
	var mixed = R.replay(R.replay(R.select(puzzle(),23),0),1)
	check(R.tried_counts(R.replay(mixed,2)) == [23],"three records on one count stay one row")
	check(R.chip_state(selected,47) == "未试","an untested candidate is open")
	check(R.chip_state(one,47) == "部分","a partly tested candidate is open")
	check(R.chip_state(all_tested(47),47) == "定下","three matching records settle it")
	check(R.chip_state(all_tested(23),23) == "排除","one mismatch eliminates it")
	check(R.verdict(all_tested(23),2,23) == "不符" and R.verdict(all_tested(23),0,23) == "相符","the table keeps each record apart")
	check(R.verdict(one,1,47) == "未复演","an unplayed record stays open in the table")
	# 提交与完整流程。
	check(R.advance(all_tested(23)).is_empty(),"a mismatching count cannot be claimed")
	check(R.advance(half).is_empty(),"an untested record cannot be claimed")
	check(R.advance(two).is_empty(),"only the third record is missing")
	var delivery = R.advance(all_tested(47))
	check(delivery.stage == "delivery" and R.validate(delivery),"all three records verified enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 撤销与重摆：候选、已列记录与三张复演表都跟着快照走。
	var more = R.list(all_tested(47),2)
	check(R.restore(more,{"count":23,"listed":[0],"tested_first":[23],"tested_second":[23],"tested_third":[]}).count == 23,"undo restores the candidate")
	var back = R.restore(more,{"count":23,"listed":[0],"tested_first":[23],"tested_second":[23],"tested_third":[]})
	check(back.listed == [0] and back.tested_first == [23] and back.tested_second == [23] and back.tested_third.is_empty(),"undo restores listing and replays")
	var cleared = R.restore(more,{"count":0,"listed":[],"tested_first":[],"tested_second":[],"tested_third":[]})
	check(cleared.count == 0 and cleared.listed.is_empty() and cleared.tested_first.is_empty(),"reset clears the search")
	check(R.restore(R.fresh(),{"count":0,"listed":[],"tested_first":[],"tested_second":[],"tested_third":[]}).is_empty(),"nothing to undo during dialogue")
	check(R.restore(puzzle(),{"count":0,"listed":[]}).is_empty(),"an incomplete snapshot is refused")
	var helped = R.list(R.select(puzzle(),47),0); helped.hint = 4
	check(R.restore(helped,{"count":0,"listed":[],"tested_first":[],"tested_second":[],"tested_third":[]}).hint == 4,"undo retains help")
	# 伪造与坏档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = all_tested(47); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = all_tested(23); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
		var partial = R.replay(R.select(puzzle(),47),0); partial.stage = stage
		check(not R.validate(partial),"half-tested %s rejected"%stage)
	check(R.validate(puzzle()),"zero count means not yet proposed")
	var listed_only = R.list(puzzle(),0)
	check(R.validate(listed_only),"candidates can be listed before a count is proposed")
	for bad_count in [-1,19,81,1.5,true]:
		var c = puzzle(); c.count = bad_count
		check(not R.validate(c),"invalid count rejected")
	for bad_tested in [[19],[81],[23,23],[47,23],[1.5],[true],range(R.BOX_MIN,R.BOX_MAX+2)]:
		var c = all_tested(47); c.tested_first = bad_tested
		check(not R.validate(c),"invalid replay table rejected")
	for bad_listed in [[-1],[3],[0,0],[1,0],[1.5],[true],[0,1,2,0]]:
		var c = puzzle(); c.listed = bad_listed
		check(not R.validate(c),"invalid listing rejected")
	var stray = puzzle(); stray.tested_first = [47]
	check(not R.validate(stray),"a replay without a count is rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = all_tested(47); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = all_tested(47); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early = R.select(puzzle(),47); early.stage = "arrival"
	check(not R.validate(early),"a count cannot appear during dialogue")
	var early_listed = R.list(puzzle(),0); early_listed.stage = "ready"
	check(not R.validate(early_listed),"a listing cannot appear before the puzzle")
	var extra = all_tested(47); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var missing = all_tested(47); missing.erase("listed")
	check(not R.validate(missing),"a missing field is refused")
	var old = all_tested(47); old.sample = "workshop-gw14-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw14-rules-%d/save.json"%OS.get_process_id()
	var partial_save = R.list(R.select(puzzle(),23),0)
	partial_save = R.replay(partial_save,0)
	check(repo.write_profile(partial_save,R.validate),"save accepted the partial record")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(all_tested(47),R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == partial_save,"restart restores the saved record")
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
	print("GW14 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

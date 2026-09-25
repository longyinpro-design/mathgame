extends SceneTree
const R = preload("res://scripts/workshop/gw13_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW13 rules watchdog fired")
		print("GW13 RULES: ",checks," checks, ",failures+1," failures")
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
# 独立 oracle：一拍一拍地走过去记下叫点，再用集合运算拼出并集、交集与对称差，不复用被测代码。
func oracle_calls(period: int) -> Array:
	var out = []
	var tick = 0
	while tick <= R.HORIZON:
		out.append(tick); tick += period
	return out
func oracle_union(a: Array, b: Array) -> Array:
	var out = []
	for tick in range(R.HORIZON+1):
		if a.has(tick) or b.has(tick): out.append(tick)
	return out
func oracle_intersect(a: Array, b: Array) -> Array:
	var out = []
	for tick in range(R.HORIZON+1):
		if a.has(tick) and b.has(tick): out.append(tick)
	return out
func oracle_symdiff(a: Array, b: Array) -> Array:
	var out = []
	for tick in range(R.HORIZON+1):
		if a.has(tick) != b.has(tick): out.append(tick)
	return out
func oracle_callers(a: Array, b: Array, tick: int) -> Array:
	var out = []
	if a.has(tick): out.append(0)
	if b.has(tick): out.append(1)
	return out
func marked(ticks: Array) -> Dictionary:
	var s = puzzle()
	for tick in ticks: s = R.mark(s,tick)
	return s
func counted(heard: int, solo: int) -> Dictionary:
	var s = marked(R.together())
	if heard >= 0: s = R.set_count(s,0,heard)
	if solo >= 0: s = R.set_count(s,1,solo)
	return s
func run() -> void:
	# 一、独立 oracle：两只鸟各自的叫点、并集、交集与对称差。
	var first = oracle_calls(4)
	var second = oracle_calls(6)
	var union = oracle_union(first,second)
	var both = oracle_intersect(first,second)
	var single = oracle_symdiff(first,second)
	check(first == [0,4,8,12,16,20,24],"甲 calls every four beats from zero")
	check(second == [0,6,12,18,24],"乙 calls every six beats from zero")
	check(R.calls(0) == first and R.calls(1) == second,"call tables match the oracle")
	check(R.calls(-1).is_empty() and R.calls(2).is_empty(),"only two birds exist")
	check(union == [0,4,6,8,12,16,18,20,24],"nine distinct moments are heard")
	check(both == [0,12,24],"three moments are called together")
	check(single == [4,6,8,16,18,20],"six moments are solo")
	check(R.heard() == union and R.together() == both and R.solo() == single,"rules agree with the oracle")
	check(first.size() == 7 and second.size() == 5,"seven plus five calls")
	check(union.size() == 9 and single.size() == 6 and both.size() == 3,"nine heard, six solo, three together")
	check(first.size()+second.size()-both.size() == union.size(),"the overlap is counted once")
	check(first.size()-both.size() == 4 and second.size()-both.size() == 2,"solo is not one bird minus the overlap")
	check(union.size()-both.size() == single.size(),"solo is the heard moments minus the overlap")
	check(union.slice(1).size() == 8,"missing beat zero leaves only eight")
	check(both.has(0) and both.has(12) and both.has(24),"both ends and the middle are together")
	check(R.COUNT_MAX == first.size()+second.size(),"the count chips cover every call")
	# 二、逐拍对照：谁在叫、能不能听到、是不是独鸣，全部按 oracle 对一遍。
	for tick in range(R.HORIZON+1):
		check(R.callers(tick) == oracle_callers(first,second,tick),"callers at beat %d"%tick)
		check(R.heard().has(tick) == union.has(tick),"heard at beat %d"%tick)
		check(R.solo().has(tick) == single.has(tick),"solo at beat %d"%tick)
		check(R.together().has(tick) == both.has(tick),"together at beat %d"%tick)
	check(R.callers(-1).is_empty() and R.callers(R.HORIZON+1).is_empty(),"beats outside 0..24 have no callers")
	# 三、阶段推进与操作守卫。
	var p = puzzle()
	check(R.validate(R.fresh()),"fresh is legal")
	check(R.advance(R.fresh()).stage == "arrival" and R.advance(R.fresh()).beat == 1,"first line of dialogue")
	var walk = R.fresh()
	for i in range(3): walk = R.advance(walk)
	check(walk.stage == "approach" and walk.beat == 2,"dialogue hands over to the walk-in")
	check(R.advance(R.advance(walk)).stage == "puzzle","player starts the puzzle by hand")
	check(R.validate(p),"fresh progression reaches legal puzzle")
	check(R.mark(R.fresh(),0).is_empty(),"no marking during dialogue")
	check(R.set_count(R.fresh(),0,9).is_empty(),"no total during dialogue")
	check(R.set_count(R.fresh(),1,6).is_empty(),"no solo during dialogue")
	check(R.step_count(R.fresh(),0,1).is_empty(),"no stepping during dialogue")
	check(R.mark(p,-1).is_empty() and R.mark(p,R.HORIZON+1).is_empty(),"marks stay on the ruler")
	check(R.set_count(p,0,-1).is_empty() and R.set_count(p,0,R.COUNT_MAX+1).is_empty(),"totals stay in 0..12")
	check(R.set_count(p,1,-2).is_empty() and R.set_count(p,1,R.COUNT_MAX+1).is_empty(),"solo stays in 0..12")
	check(R.set_count(p,2,3).is_empty() and R.step_count(p,2,1).is_empty(),"only two counts exist")
	var one = R.mark(p,0)
	check(one.marks == [0] and R.validate(one),"marking beat zero")
	check(R.mark(one,0).marks.is_empty(),"marking the same beat again takes it back")
	check(R.mark(R.mark(p,12),0).marks == [0,12],"marks stay sorted")
	check(R.set_count(p,0,9).heard == 9 and R.validate(R.set_count(p,0,9)),"setting the total")
	check(R.set_count(R.set_count(p,0,9),0,9).is_empty(),"re-setting the same total is a no-op")
	check(R.set_count(R.set_count(p,1,6),1,6).is_empty(),"re-setting the same solo is a no-op")
	check(R.step_count(p,0,1).heard == R.COUNT_MIN,"the first step lands on zero")
	check(R.step_count(R.set_count(p,0,0),0,-1).is_empty(),"stepping clamps at zero")
	check(R.step_count(R.set_count(p,0,R.COUNT_MAX),0,1).is_empty(),"stepping clamps at twelve")
	check(R.step_count(R.set_count(p,0,11),0,1).heard == 12,"stepping one at a time")
	check(R.step_count(R.set_count(p,1,1),1,-1).solo == 0,"the solo row steps on its own")
	check(R.set_count(p,0,9).solo == -1 and R.set_count(p,1,6).heard == -1,"the two counts are independent")
	# 四、逐格判定：只有圈出三拍同拍、两个数量都对才算解。
	check(R.solved(counted(9,6)),"the real answer solves")
	check(R.shortfalls(counted(9,6)).is_empty(),"the real answer has no shortfall")
	for tick in range(R.HORIZON+1):
		check(not R.solved(marked([tick])),"one mark never solves")
		check(not R.shortfalls(marked([tick])).is_empty(),"one mark always has a real gap")
		var off = counted(9,6)
		var marks = R.together().duplicate()
		if marks.has(tick): marks.erase(tick)
		else: marks.append(tick)
		marks.sort()
		off.marks = marks
		check(R.validate(off),"a mark set off by beat %d stays legal"%tick)
		check(not R.solved(off),"a mark set off by beat %d never solves"%tick)
	for value in range(R.COUNT_MAX+1):
		check(R.solved(counted(value,6)) == (value == 9),"only nine heard moments solve, %d does not"%value)
		check(R.solved(counted(9,value)) == (value == 6),"only six solo moments solve, %d does not"%value)
	# 五、提交被拒时念出真实原因，反例逐条对上。
	check(R.shortfalls(p)[0].begins_with("先在时间尺上"),"no marks is called out first")
	check("只有甲在叫" in R.shortfalls(marked([4]))[0],"a solo beat cannot be circled as together")
	check("只有乙在叫" in R.shortfalls(marked([6]))[0],"the other bird is named too")
	check("两只鸟都没叫" in R.shortfalls(marked([2]))[0],"a silent beat cannot be circled")
	check("第 12 拍两只鸟一起叫，是重合，你还没圈上" in R.shortfalls(marked([0]))[0],"the first missing together beat is named")
	check("再提交「总共几个时刻听到叫声」" in R.shortfalls(marked(R.together()))[0],"the total is asked for next")
	check("再提交「其中几个只有一只鸟叫」" in R.shortfalls(counted(9,-1))[0],"the solo count is asked for next")
	var twelve = R.shortfalls(counted(12,6))
	check(twelve.size() == 1,"one reason at a time")
	check("你写的是 12" in twelve[0] and "只算一个时刻" in twelve[0],"seven plus five is refused as a double count")
	check("0、12、24" in twelve[0],"the together beats are named in the refusal")
	check("甲叫 7 次、乙叫 5 次" in twelve[0],"the real call counts are spoken")
	var eight = R.shortfalls(counted(8,6))
	check("0 到 24 拍两端都算" in eight[0],"missing beat zero is answered with the real range")
	var four = R.shortfalls(counted(9,4))
	check("你写的是 4" in four[0] and "不算独鸣" in four[0],"subtracting the overlap from one bird is refused")
	check("总共 9 个时刻里" in four[0],"the refusal quotes the total the player already got right")
	# 六、提交只在解上通过，完整流程走一遍。
	check(R.advance(p).is_empty(),"an unmarked puzzle cannot be claimed")
	check(R.advance(marked(R.together())).is_empty(),"a puzzle without the two counts cannot be claimed")
	check(R.advance(counted(12,6)).is_empty(),"the double count cannot be claimed")
	check(R.advance(counted(9,4)).is_empty(),"the one-bird subtraction cannot be claimed")
	var delivery = R.advance(counted(9,6))
	check(delivery.stage == "delivery" and R.validate(delivery),"the real answer enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 七、撤销与重摆：标记与两个数量都跟着快照走。
	var more = R.set_count(R.mark(counted(9,6),4),1,4)
	check(more.marks == [0,4,12,24],"an extra circle is kept while it is there")
	check(R.restore(more,{"marks":[0,12],"heard":9,"solo":-1}).marks == [0,12],"undo restores the circles")
	check(R.restore(more,{"marks":[0,12],"heard":9,"solo":-1}).solo == -1,"undo restores an unfilled count")
	check(R.restore(more,{"marks":[0,12,24],"heard":9,"solo":6}).solo == 6,"undo restores the counts")
	var cleared = R.restore(more,{"marks":[],"heard":-1,"solo":-1})
	check(cleared.marks.is_empty() and cleared.heard == -1 and cleared.solo == -1,"reset clears the record")
	check(R.restore(p,{"marks":[]}).is_empty(),"an incomplete snapshot is refused")
	var helped = R.mark(p,0); helped.hint = 4
	check(R.restore(helped,{"marks":[],"heard":-1,"solo":-1}).hint == 4,"undo retains help")
	# 八、伪造与坏档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = counted(9,6); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = counted(12,6); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
		var partial = marked(R.together()); partial.stage = stage
		check(not R.validate(partial),"half-answered %s rejected"%stage)
	check(R.validate(p),"an empty mark list and two unfilled counts are legal")
	for bad_marks in [[-1],[25],[0,0],[0,1.5],[true],["0"],range(0,R.HORIZON+2)]:
		var c = counted(9,6); c.marks = bad_marks
		check(not R.validate(c),"invalid mark list rejected")
	for bad_count in [-2,R.COUNT_MAX+1,1.5,true]:
		var c = counted(9,6); c.heard = bad_count
		check(not R.validate(c),"invalid total rejected")
		var d = counted(9,6); d.solo = bad_count
		check(not R.validate(d),"invalid solo rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = counted(9,6); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = counted(9,6); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early = counted(9,6); early.stage = "ready"
	check(not R.validate(early),"circles and counts cannot appear during dialogue")
	var stray = p.duplicate(true); stray.marks = [0]
	check(R.validate(stray),"a circle without the counts is still legal in puzzle")
	var extra = counted(9,6); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = counted(9,6); old.sample = "workshop-gw13-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	# 九、存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw13-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(marked([0,12]),R.validate),"save accepted the half-marked record")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(counted(9,6),R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == marked([0,12]),"restart restores the saved record")
	check(repo.write_profile(done,R.validate),"retry exact completion")
	var file = FileAccess.open(repo.path,FileAccess.WRITE); file.store_string('{"broken":true}'); file.close()
	hash = FileAccess.get_sha256(repo.path)
	check(repo.read_profile(R.validate).status == "protected","bad save protected")
	check(not repo.write_profile(R.fresh(),R.validate) and FileAccess.get_sha256(repo.path) == hash,"protected file never overwritten")
	var backup = repo.preserve_protected_file()
	check(not backup.is_empty() and FileAccess.get_sha256(backup) == hash,"explicit recovery preserves backup")
	for p2 in [repo.path,repo.path+".tmp",backup]:
		if FileAccess.file_exists(p2): DirAccess.remove_absolute(p2)
	DirAccess.remove_absolute(repo.path.get_base_dir())
	print("GW13 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

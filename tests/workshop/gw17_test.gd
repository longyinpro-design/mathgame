extends SceneTree
const R = preload("res://scripts/workshop/gw17_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
# 独立 oracle 只认设计文档里的数字：最早可发、占轨、最晚驶离各抄一份，判定用逐拍扫描重写。
const REL = {"A":0,"B":1,"C":3,"D":6}
const DUR = {"A":3,"B":2,"C":1,"D":2}
const DL = {"A":7,"B":4,"C":5,"D":9}
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW17 rules watchdog fired")
		print("GW17 RULES: ",checks," checks, ",failures+1," failures")
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

# ---- 独立 oracle：最笨的枚举，不复用被测代码的判定 ----
# 24 种放行顺序逐一试开工拍（允许空等），只收在第 9 拍前全部驶离、且逐辆不逾期的表。
func oracle_plans() -> Array:
	var out = []
	for order in permutations(R.ITEMS):
		walk(order,0,0,{},out)
	return out
func permutations(items: Array) -> Array:
	if items.size() <= 1: return [items.duplicate()]
	var out = []
	for index in range(items.size()):
		var rest = items.duplicate(); rest.remove_at(index)
		for tail in permutations(rest):
			var head = [items[index]]; head.append_array(tail); out.append(head)
	return out
func walk(order: Array, index: int, earliest: int, plan: Dictionary, out: Array) -> void:
	if index == order.size():
		for id in plan:
			if plan[id]+DUR[id] > DL[id]: return
		out.append(plan.duplicate())
		return
	var id = order[index]
	var remaining = 0
	for later in range(index+1,order.size()): remaining += DUR[order[later]]
	for start in range(maxi(earliest,REL[id]),R.HORIZON+1):
		if start+DUR[id]+remaining > R.HORIZON: break
		var next = plan.duplicate(); next[id] = start
		walk(order,index+1,start+DUR[id],next,out)
# 逐拍扫描：每一拍轨上最多一辆；每辆不早于上轨许可、不晚于最晚驶离。
func oracle_ok(starts: Array) -> bool:
	for t in range(R.HORIZON):
		var busy = 0
		for index in range(4):
			var id = R.ITEMS[index]
			if starts[index] <= t and t < starts[index]+DUR[id]: busy += 1
		if busy > 1: return false
	for index in range(4):
		var id = R.ITEMS[index]
		if starts[index] < REL[id] or starts[index]+DUR[id] > DL[id]: return false
	return true
# 放行顺序的最笨算法：插入排序，开工拍小的在前，同拍按 A、B、C、D。
func oracle_order(starts: Array) -> Array:
	var ids = R.ITEMS.duplicate()
	for i in range(1,ids.size()):
		var j = i
		while j > 0 and starts[R.ITEMS.find(ids[j])] < starts[R.ITEMS.find(ids[j-1])]:
			var held = ids[j]; ids[j] = ids[j-1]; ids[j-1] = held
			j -= 1
	return ids
func state_for(starts: Array) -> Dictionary:
	return {"sample":R.SAMPLE,"stage":"puzzle","beat":2,"starts":starts.duplicate(),
		"order":oracle_order(starts),"hint":0}
func has_plan(plans: Array, plan: Dictionary) -> bool:
	for candidate in plans:
		if candidate.size() != plan.size(): continue
		var same = true
		for key in plan:
			if candidate.get(key) != plan[key]: same = false
		if same: return true
	return false
func all_starts() -> Array:
	var out = []
	for a in range(R.START_MAX+1):
		for b in range(R.START_MAX+1):
			for c in range(R.START_MAX+1):
				for d in range(R.START_MAX+1): out.append([a,b,c,d])
	return out

func run() -> void:
	# 设计数字与规则模块的常量逐项对照。
	check(R.ITEMS == ["A","B","C","D"],"four cars A B C D")
	check(R.WORK == 8 and R.HORIZON == 9 and R.START_MAX == 9,"eight beats of work on a nine-beat table")
	for id in R.ITEMS:
		check(R.DURATIONS[id] == DUR[id] and R.RELEASES[id] == REL[id] and R.DEADLINES[id] == DL[id],
			"design numbers for "+id)
	check(R.DEFAULT_STARTS == [0,3,5,6],"the opening draft sends A first and the rest as early as possible")
	check(R.sequence(R.DEFAULT_STARTS) == ["A","B","C","D"],"the draft reads A then B then C then D")
	# 独立枚举：可行计划只有一套——空出第 0 拍，B 1–3、C 3–4、A 4–7、D 7–9。
	var plans = oracle_plans()
	check(plans.size() == 1,"the oracle finds exactly one feasible plan")
	var answer = {"A":4,"B":1,"C":3,"D":7}
	check(has_plan(plans,answer),"the only plan is B 1-3, C 3-4, A 4-7, D 7-9")
	if plans.size() == 1:
		var only = plans[0]
		check(only.get("A") == 4 and only.get("B") == 1 and only.get("C") == 3 and only.get("D") == 7,
			"the oracle plan reads A=4 B=1 C=3 D=7")
	# 全表逐格：10000 张开工拍表，solved 必须与 oracle 完全一致。
	var tables = all_starts()
	var solved_tables = []
	var cell_bad = ""
	var reason_bad = ""
	var order_bad = ""
	var advance_bad = ""
	for starts in tables:
		var s = state_for(starts)
		var good = oracle_ok(starts)
		if R.solved(s) != good and cell_bad.is_empty(): cell_bad = str(starts)
		if R.sequence(starts) != oracle_order(starts) and order_bad.is_empty(): order_bad = str(starts)
		if good: solved_tables.append(starts)
		var next = R.advance(s)
		if good and (next.is_empty() or next.stage != "delivery") and advance_bad.is_empty(): advance_bad = str(starts)
		if not good and not next.is_empty() and advance_bad.is_empty(): advance_bad = str(starts)
		var gaps = R.shortfalls(s)
		if gaps.is_empty() == good:
			pass
		elif not (("才准上轨" in gaps[0]) or ("轨上还压着" in gaps[0]) or ("才驶离" in gaps[0])):
			if reason_bad.is_empty(): reason_bad = str(starts)+" -> "+gaps[0]
	check(cell_bad.is_empty(),"solved agrees with the oracle on all 10000 tables, first bad "+cell_bad)
	check(order_bad.is_empty(),"release order agrees with the oracle, first bad "+order_bad)
	check(reason_bad.is_empty(),"every first reason names the gate, the rail or the deadline, first bad "+reason_bad)
	check(advance_bad.is_empty(),"advance only passes the one solved table, first bad "+advance_bad)
	check(solved_tables.size() == 1,"exactly one table solves")
	check(solved_tables.has([4,1,3,7]),"the solved table is A=4 B=1 C=3 D=7")
	check(R.sequence([4,1,3,7]) == ["B","C","A","D"],"the answer reads B-C-A-D")
	check(R.sequence([1,1,0,0]) == ["C","D","A","B"],"ties keep A B C D order")
	# 逐辆区间：按当前开工拍现算，四辆首尾相接，空出的正是第 0 拍。
	var solved_state = state_for([4,1,3,7])
	var rows = R.plan(solved_state)
	check(rows[0] == {"item":"A","start":4,"end":7},"A occupies 4 to 7")
	check(rows[1] == {"item":"B","start":1,"end":3},"B occupies 1 to 3")
	check(rows[2] == {"item":"C","start":3,"end":4},"C occupies 3 to 4")
	check(rows[3] == {"item":"D","start":7,"end":9},"D occupies 7 to 9")
	check(R.finish_of(solved_state,"B") == 3 and R.start_of(solved_state,"D") == 7,"start and finish read off the table")
	# 共用轨道逐拍：第 0 拍空着，其余每一拍恰好一辆。
	var held = []
	for t in range(R.HORIZON): held.append(R.holders(solved_state,t))
	check(held == [[],["B"],["B"],["C"],["A"],["A"],["A"],["D"],["D"]],"the rail holds one car per beat and beat 0 stays empty")
	# 关键反例：A 先走卡住 B、B 后先 A 让 C 迟到、为等 D 挪后 A、留空留错位置。
	var draft = puzzle()
	check(R.shortfalls(draft)[0] == "B 到第 5 拍才驶离，超过最晚 4 拍。","the draft is refused because A first blocks B")
	check(R.advance(draft).is_empty(),"the draft cannot be released")
	var blocked = R.shortfalls(state_for([0,1,3,6]))
	check(blocked[0].begins_with("第 1 拍轨上还压着：A 的 0–3 还没走完，B 就要发。"),
		"sending B at 1 behind A names the occupied beat: "+blocked[0])
	var early = R.shortfalls(state_for([4,1,2,7]))
	check(early[0] == "C 第 3 拍才准上轨，第 2 拍还发不了。","sending C at 2 names its gate: "+early[0])
	var c_late = R.shortfalls(state_for([3,1,6,7]))
	check(c_late[0] == "C 到第 7 拍才驶离，超过最晚 5 拍。","B then A makes C late: "+c_late[0])
	var wait_d = R.shortfalls(state_for([9,1,3,6]))
	check(wait_d[0] == "A 到第 12 拍才驶离，超过最晚 7 拍。","waiting for D pushes A past its deadline: "+wait_d[0])
	var b_two = R.shortfalls(state_for([4,2,3,7]))
	check(b_two[0].begins_with("第 3 拍轨上还压着：B 的 2–4 还没走完，C 就要发。"),"sending B at 2 blocks C: "+b_two[0])
	var wrong_gap = R.shortfalls(state_for([4,1,5,7]))
	check(wrong_gap[0].begins_with("第 5 拍轨上还压着：A 的 4–7 还没走完，C 就要发。"),
		"leaving beat 3 empty instead of beat 0 is refused: "+wrong_gap[0])
	check(R.shortfalls(solved_state).is_empty(),"the real answer has no shortfall")
	# 阶段推进与操作守卫。
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.validate(R.fresh()) and R.fresh().stage == "arrival","fresh opens at arrival")
	check(R.nudge(R.fresh(),0,1).is_empty(),"no moving a start during dialogue")
	check(R.nudge(R.advance(R.fresh()),0,1).is_empty(),"no moving a start during the walk-in")
	check(R.restore(R.fresh(),{"starts":[4,1,3,7],"order":["B","C","A","D"]}).is_empty(),"no undo during dialogue")
	check(R.set_start(s,0,10).is_empty() and R.set_start(s,0,-1).is_empty(),"starts stay between 0 and 9")
	check(R.set_start(s,4,1).is_empty() and R.set_start(s,-1,1).is_empty(),"only four cars exist")
	check(R.set_start(s,0,0).is_empty(),"setting the same beat is a no-op")
	check(R.nudge(s,0,-1).is_empty(),"A cannot start before beat 0")
	check(R.set_start(s,0,9).starts[0] == 9 and R.validate(R.set_start(s,0,9)),"a start of 9 is representable")
	var moved = R.set_start(s,0,4)
	check(moved.starts == [4,3,5,6] and moved.order == ["B","A","C","D"],"moving A reorders the release")
	check(R.nudge(moved,0,-1).starts == [3,3,5,6],"moving A back one beat lands next to B")
	check(R.validate(R.nudge(moved,0,-1)),"the neighbouring table is a legal state")
	# 提交只在解上通过，演出逐级收尾。
	check(R.advance(state_for([0,1,3,6])).is_empty(),"an occupied rail cannot be released")
	check(R.advance(state_for([9,1,3,6])).is_empty(),"a late plan cannot be released")
	var delivery = R.advance(solved_state)
	check(delivery.stage == "delivery" and R.validate(delivery),"the one solved plan enters delivery")
	check(R.advance(delivery).stage == "aftermath" and R.advance(delivery).beat == 0,"delivery stops for dialogue")
	var done = delivery
	for i in range(4): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 撤销与重摆：开工拍表与放行顺序一起回退。
	var second_state = state_for([0,1,3,6])
	var back = R.restore(second_state,{"starts":[4,1,3,7],"order":["B","C","A","D"]})
	check(back.starts == [4,1,3,7] and back.order == ["B","C","A","D"],"undo restores both the starts and the order")
	var cleared = R.restore(second_state,{"starts":R.DEFAULT_STARTS.duplicate(),"order":R.sequence(R.DEFAULT_STARTS)})
	check(cleared.starts == [0,3,5,6] and cleared.order == ["A","B","C","D"],"reset returns the opening draft")
	check(R.restore(second_state,{"starts":[4,1,3,7]}).is_empty(),"undo needs the whole snapshot")
	check(R.restore(second_state,{"starts":[10,1,3,7],"order":["B","C","A","D"]}).is_empty(),"undo refuses out-of-range starts")
	var helped = R.nudge(solved_state,0,1); helped.hint = 3
	check(R.restore(helped,{"starts":R.DEFAULT_STARTS.duplicate(),"order":R.sequence(R.DEFAULT_STARTS)}).hint == 3,
		"undo retains the help level")
	# 伪造、越界与旧版一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = state_for([4,1,3,7]); good.stage = stage
		check(R.validate(good),"solved %s is legal"%stage)
		var forged = state_for([0,1,3,6]); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
	check(R.validate(puzzle()),"the opening draft is a legal puzzle state")
	for bad_stage in ["trial","complete ","",5,true]:
		var c = state_for([4,1,3,7]); c.stage = bad_stage
		check(not R.validate(c),"invalid stage rejected")
	var old = state_for([4,1,3,7]); old.sample = "workshop-gw17-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var extra = state_for([4,1,3,7]); extra.attempts = 1
	check(not R.validate(extra),"closed schema")
	for bad_starts in [[4,1,3],[-1,1,3,7],[10,1,3,7],[4,1,3,7,9],[4,1,3.0,7],[4,1,true,7],"4137",{}]:
		var c = state_for([4,1,3,7]); c.starts = bad_starts
		check(not R.validate(c),"invalid start table rejected")
	for bad_order in [["B","B","C","D"],["B","C","A"],["B","C","A","E"],["A","B","C","D"],
		["C","B","A","D"],[0,1,2,3],["B","C","A","D","B"]]:
		var c = state_for([4,1,3,7]); c.order = bad_order
		check(not R.validate(c),"invalid or forged order rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = state_for([4,1,3,7]); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = state_for([4,1,3,7]); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early_stage = state_for([4,1,3,7]); early_stage.stage = "ready"
	check(not R.validate(early_stage),"a solved table cannot appear during dialogue")
	var short_beat = state_for([4,1,3,7]); short_beat.beat = 1
	check(not R.validate(short_beat),"puzzle needs the dialogue to be finished")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw17-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(draft,R.validate),"save accepted the opening draft")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(solved_state,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == draft,"restart restores the saved draft")
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
	print("GW17 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

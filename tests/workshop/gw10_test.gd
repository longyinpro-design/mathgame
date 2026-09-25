extends SceneTree
const R = preload("res://scripts/workshop/gw10_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
# 独立 oracle 只认设计文档里的数字：用时、到料、期限各抄一份，判定用逐拍扫描重写。
const DUR = {"A":2,"B":3,"C":1,"D":2}
const REL = {"A":0,"B":0,"C":1,"D":0}
const DL = {"A":5,"B":8,"C":3,"D":6}
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW10 rules watchdog fired")
		print("GW10 RULES: ",checks," checks, ",failures+1," failures")
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
# 24 种执行顺序逐一试开工拍（允许空等），只枚举能在第 8 拍前收工的表，最后逐单核对期限。
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
# 逐拍扫描：每一拍台上最多一单；每单不早于到料、不晚于期限。
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
# 验收顺序的最笨算法：插入排序，开工拍小的在前，同拍按 A、B、C、D。
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
	check(R.ITEMS == ["A","B","C","D"],"four orders A B C D")
	check(R.WORK == 8 and R.HORIZON == 8 and R.START_MAX == 8,"eight beats of work")
	for id in R.ITEMS:
		check(R.DURATIONS[id] == DUR[id] and R.RELEASES[id] == REL[id] and R.DEADLINES[id] == DL[id],
			"design numbers for "+id)
	check(R.DEFAULT_STARTS == [1,5,0,3],"the opening draft starts C at beat 0")
	check(R.sequence(R.DEFAULT_STARTS) == ["C","A","D","B"],"the draft reads C then A then D then B")
	# 独立枚举：可行计划只有两套，都是 A/D 先上、C 接在第 2 拍。
	var plans = oracle_plans()
	check(plans.size() == 2,"the oracle finds exactly two feasible plans")
	var first = {"A":0,"B":5,"C":2,"D":3}
	var second = {"A":3,"B":5,"C":2,"D":0}
	check(has_plan(plans,first) and has_plan(plans,second),"the two plans are A-C-D-B and D-C-A-B from beat 0")
	# 全表逐格：6561 张开工拍表，solved 必须与 oracle 完全一致。
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
		elif not (("才送来" in gaps[0]) or ("还占着台" in gaps[0]) or ("才完" in gaps[0])):
			if reason_bad.is_empty(): reason_bad = str(starts)+" -> "+gaps[0]
	check(cell_bad.is_empty(),"solved agrees with the oracle on all 6561 tables, first bad "+cell_bad)
	check(order_bad.is_empty(),"acceptance order agrees with the oracle, first bad "+order_bad)
	check(reason_bad.is_empty(),"every first reason names arrival, bench or deadline, first bad "+reason_bad)
	check(advance_bad.is_empty(),"advance only passes the two solved tables, first bad "+advance_bad)
	check(solved_tables.size() == 2,"exactly two tables solve")
	check(solved_tables.has([0,5,2,3]) and solved_tables.has([3,5,2,0]),"the solved tables are the two plans")
	check(R.sequence([0,5,2,3]) == ["A","C","D","B"] and R.sequence([3,5,2,0]) == ["D","C","A","B"],
		"the two plans read A-C-D-B and D-C-A-B")
	check(R.sequence([1,1,0,0]) == ["C","D","A","B"],"ties keep A B C D order")
	# 逐单区间：按当前开工拍现算，四单首尾相接。
	var solved_state = state_for([0,5,2,3])
	var rows = R.plan(solved_state)
	check(rows[0] == {"item":"A","start":0,"end":2},"A occupies 0 to 2")
	check(rows[1] == {"item":"B","start":5,"end":8},"B occupies 5 to 8")
	check(rows[2] == {"item":"C","start":2,"end":3},"C occupies 2 to 3")
	check(rows[3] == {"item":"D","start":3,"end":5},"D occupies 3 to 5")
	check(R.finish_of(solved_state,"B") == 8 and R.start_of(solved_state,"C") == 2,"start and finish read off the table")
	# 关键反例：等料、撞台、逾期，各自念出真实原因。
	var draft = puzzle()
	check(R.shortfalls(draft)[0] == "C 第 1 拍才送来，第 0 拍还开不了工。","the draft is refused for waiting on C")
	check(R.advance(draft).is_empty(),"the draft cannot be claimed")
	var clash = R.shortfalls(state_for([3,5,2,3]))
	check(clash[0].begins_with("第 3 拍还占着台：A 的 3–5 还没走完，D 就要开工。"),"a bench clash names the tick and the order: "+clash[0])
	var late = R.shortfalls(state_for([4,8,1,2]))
	check(late[0] == "A 到第 6 拍才完，超过最晚 5 拍。","a late order names its real finish: "+late[0])
	var b_first = R.shortfalls(state_for([6,0,3,4]))
	check(b_first[0] == "C 到第 4 拍才完，超过最晚 3 拍。","doing B first makes C late: "+b_first[0])
	var waited = R.shortfalls(state_for([2,6,1,4]))
	check(waited[0] == "B 到第 9 拍才完，超过最晚 8 拍。","waiting for C loses the last beat: "+waited[0])
	check(not R.solved(state_for([1,5,1,3])),"overlapping A and C is not solved")
	check(R.shortfalls(state_for([1,5,1,3]))[0].begins_with("第 1 拍还占着台"),"the overlap is named at beat 1")
	check(R.shortfalls(solved_state).is_empty(),"the real answer has no shortfall")
	# 阶段推进与操作守卫。
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.validate(R.fresh()) and R.fresh().stage == "arrival","fresh opens at arrival")
	check(R.nudge(R.fresh(),0,1).is_empty(),"no moving a start during dialogue")
	check(R.nudge(R.advance(R.fresh()),0,1).is_empty(),"no moving a start during the walk-in")
	check(R.restore(R.fresh(),{"starts":[0,5,2,3],"order":["A","C","D","B"]}).is_empty(),"no undo during dialogue")
	check(R.set_start(s,0,9).is_empty() and R.set_start(s,0,-1).is_empty(),"starts stay between 0 and 8")
	check(R.set_start(s,4,1).is_empty() and R.set_start(s,-1,1).is_empty(),"only four orders exist")
	check(R.set_start(s,0,1).is_empty(),"setting the same beat is a no-op")
	check(R.nudge(s,2,-1).is_empty(),"C cannot start before beat 0")
	check(R.set_start(s,0,8).starts[0] == 8 and R.validate(R.set_start(s,0,8)),"a start of 8 is representable")
	var moved = R.nudge(s,2,2)
	check(moved.starts == [1,5,2,3] and moved.order == ["A","C","D","B"],"moving C reorders the acceptance")
	check(R.nudge(moved,0,-1).starts == [0,5,2,3],"moving A back lands on the first plan")
	check(R.validate(R.nudge(moved,0,-1)),"the first plan is a legal state")
	# 提交只在解上通过，演出逐级收尾。
	check(R.advance(state_for([3,5,2,3])).is_empty(),"a bench clash cannot be claimed")
	check(R.advance(state_for([4,8,1,2])).is_empty(),"a late plan cannot be claimed")
	var delivery = R.advance(solved_state)
	check(delivery.stage == "delivery" and R.validate(delivery),"a solved plan enters delivery")
	check(R.advance(delivery).stage == "aftermath" and R.advance(delivery).beat == 0,"delivery stops for dialogue")
	var done = delivery
	for i in range(4): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 撤销与重摆：开工拍表与验收顺序一起回退。
	var second_state = state_for([3,5,2,0])
	var back = R.restore(second_state,{"starts":[0,5,2,3],"order":["A","C","D","B"]})
	check(back.starts == [0,5,2,3] and back.order == ["A","C","D","B"],"undo restores both the starts and the order")
	var cleared = R.restore(second_state,{"starts":R.DEFAULT_STARTS.duplicate(),"order":R.sequence(R.DEFAULT_STARTS)})
	check(cleared.starts == [1,5,0,3] and cleared.order == ["C","A","D","B"],"reset returns the opening draft")
	check(R.restore(second_state,{"starts":[0,5,2,3]}).is_empty(),"undo needs the whole snapshot")
	check(R.restore(second_state,{"starts":[9,5,2,3],"order":["A","C","D","B"]}).is_empty(),"undo refuses out-of-range starts")
	var helped = R.nudge(solved_state,0,1); helped.hint = 3
	check(R.restore(helped,{"starts":R.DEFAULT_STARTS.duplicate(),"order":R.sequence(R.DEFAULT_STARTS)}).hint == 3,
		"undo retains the help level")
	# 伪造、越界与旧版一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = state_for([0,5,2,3]); good.stage = stage
		check(R.validate(good),"solved %s is legal"%stage)
		var forged = state_for([4,8,1,2]); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
	check(R.validate(puzzle()),"the opening draft is a legal puzzle state")
	for bad_stage in ["trial","complete ","",5,true]:
		var c = state_for([0,5,2,3]); c.stage = bad_stage
		check(not R.validate(c),"invalid stage rejected")
	var old = state_for([0,5,2,3]); old.sample = "workshop-gw10-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var extra = state_for([0,5,2,3]); extra.attempts = 1
	check(not R.validate(extra),"closed schema")
	for bad_starts in [[0,5,2],[-1,5,2,3],[9,5,2,3],[0,5,2,3,4],[0,5,2.0,3],[0,5,true,3],"0523",{}]:
		var c = state_for([0,5,2,3]); c.starts = bad_starts
		check(not R.validate(c),"invalid start table rejected")
	for bad_order in [["A","A","C","D"],["A","B","C"],["A","B","C","E"],["A","B","C","D"],
		["C","A","D","B"],[0,1,2,3],["A","B","C","D","A"]]:
		var c = state_for([0,5,2,3]); c.order = bad_order
		check(not R.validate(c),"invalid or forged order rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = state_for([0,5,2,3]); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = state_for([0,5,2,3]); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early = state_for([0,5,2,3]); early.stage = "ready"
	check(not R.validate(early),"a solved table cannot appear during dialogue")
	var short_beat = state_for([0,5,2,3]); short_beat.beat = 1
	check(not R.validate(short_beat),"puzzle needs the dialogue to be finished")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw10-rules-%d/save.json"%OS.get_process_id()
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
	print("GW10 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

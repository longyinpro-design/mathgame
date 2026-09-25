extends SceneTree
const R = preload("res://scripts/workshop/gw18_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
# 独立 oracle 只认设计文档里的数字：批次件数、压制/冷却拍数、吊运点各抄一份，
# 用最笨的枚举独立排压制与冷却表、独立逐拍模拟两条暂存链与吊机，不复用被测代码的判定。
const DUR = [1,2,1]
const SLOTS = [6,8]
const F_LOAD = 3
const M_LOAD = 9
const MAX = 10
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW18 rules watchdog fired")
		print("GW18 RULES: ",checks," checks, ",failures+1," failures")
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

# ---- 独立 oracle：6 种压制顺序，压制与冷却都允许空等，冷却按出压机的顺序 ----
func permutations(items: Array) -> Array:
	if items.size() <= 1: return [items.duplicate()]
	var out = []
	for index in range(items.size()):
		var rest = items.duplicate(); rest.remove_at(index)
		for tail in permutations(rest):
			var head = [items[index]]; head.append_array(tail); out.append(head)
	return out
func key_of(press: Array, cool: Array) -> String:
	return "%d%d%d/%d%d%d"%[press[0],press[1],press[2],cool[0],cool[1],cool[2]]
func state_for(press: Array, cool: Array) -> Dictionary:
	return {"sample":R.SAMPLE,"stage":"puzzle","beat":2,"press":press.duplicate(),"cool":cool.duplicate(),
		"branch":R.BRANCH,"confirmed":false,"hint":0}
func oracle_sets() -> Dictionary:
	var early = {}; var late = {}; var robust = {}
	for order in permutations([0,1,2]):
		walk_press(order,0,0,{},early,late,robust)
	return {"early":early,"late":late,"robust":robust}
func walk_press(order: Array, index: int, earliest: int, plan: Dictionary,
		early: Dictionary, late: Dictionary, robust: Dictionary) -> void:
	if index == order.size():
		walk_cool(order,0,{},plan,early,late,robust)
		return
	var id = order[index]
	var remaining = 0
	for later in range(index+1,order.size()): remaining += DUR[order[later]]
	for start in range(earliest,R.HORIZON+1):
		if start+DUR[id]+remaining > R.HORIZON: break
		var next = plan.duplicate(); next[id] = start
		walk_press(order,index+1,start+DUR[id],next,early,late,robust)
func walk_cool(order: Array, index: int, plan: Dictionary, press: Dictionary,
		early: Dictionary, late: Dictionary, robust: Dictionary) -> void:
	if index == order.size():
		oracle_score(press,plan,early,late,robust)
		return
	var id = order[index]
	var remaining = 0
	for later in range(index+1,order.size()): remaining += 2
	var first = maxi(0,press[id]+DUR[id])
	if index > 0:
		var prev = order[index-1]
		first = maxi(first,plan[prev]+2)
	for start in range(first,R.HORIZON+1):
		if start+2+remaining > R.HORIZON: break
		var next = plan.duplicate(); next[id] = start
		walk_cool(order,index+1,next,press,early,late,robust)
# 逐拍扫描两条暂存链；吊机按固定开工拍；两页分别判，两页都过才是 robust。
func rack_ok(produced: Array, consumed: Array) -> bool:
	for tick in range(R.HORIZON+1):
		var held = 0
		for id in range(3):
			if produced[id] <= tick and tick < consumed[id]: held += 1
		if held >= 2: return false
	return true
func oracle_score(press: Dictionary, cool: Dictionary, early: Dictionary, late: Dictionary, robust: Dictionary) -> void:
	var produced = []; var finished = []
	var order = [0,1,2]
	var press_list = []; var cool_list = []
	for id in order:
		press_list.append(press[id]); cool_list.append(cool[id])
		produced.append(press[id]+DUR[id]); finished.append(cool[id]+2)
	if not rack_ok(produced,cool_list): return
	var key = key_of(press_list,cool_list)
	var good = 0
	for slot in SLOTS:
		var loads = [F_LOAD,slot,M_LOAD]
		var ok = true
		for id in range(3):
			if finished[id] > loads[id]: ok = false
		if ok and not rack_ok(finished,loads): ok = false
		if ok:
			good += 1
			if slot == 6: early[key] = true
			else: late[key] = true
	if good == 2: robust[key] = true
func has_key(plans: Dictionary, press: Array, cool: Array) -> bool:
	return plans.has(key_of(press,cool))
func reason_known(text: String) -> bool:
	return ("还占着" in text) or ("才下压机" in text) or ("才冷却完" in text) \
		or ("挤了两批" in text) or ("赶不上" in text) or ("先接了" in text) or ("要开船" in text)

func run() -> void:
	# 设计数字与规则模块的常量逐项对照。
	check(R.BATCHES == ["F","V","M"],"three batches F V M")
	check(R.ITEM_COUNT == [2,3,2] and R.PRESS_TIME == [1,2,1],"7 items: F2/V3/M2 and press 1/2/1")
	check(R.COOL_TIME == 2 and R.LOAD_TIME == 1 and R.HORIZON == 10 and R.START_MAX == 10,
		"cooling 2, loading 1, ship at beat 10, starts 0 to 10")
	check(R.F_LOAD == 3 and R.M_LOAD == 9,"F loads at beat 3, M loads at beat 9")
	check(R.BRANCHES == [6,8] and R.BRANCH == 8,"V loads at beat 6 or 8; the actual shift is the late one")
	check(R.DEFAULT_PRESS == [0,1,3] and R.DEFAULT_COOL == [1,3,5],"the opening draft is the risky plan")
	check(R.FIELDS == ["sample","stage","beat","press","cool","branch","confirmed","hint"],"closed schema")
	# 独立枚举：robust 19、满足早班 21、满足晚班 38。
	var sets = oracle_sets()
	check(sets.robust.size() == 19,"the oracle finds exactly 19 plans for both shifts")
	check(sets.early.size() == 21,"21 plans run on the early shift")
	check(sets.late.size() == 38,"38 plans run on the late shift")
	var sample_press = [0,1,3]; var sample_cool = [1,3,6]
	var risky_press = [0,1,3]; var risky_cool = [1,3,5]
	check(has_key(sets.robust,sample_press,sample_cool),"the author sample is robust")
	check(has_key(sets.early,risky_press,risky_cool) and not has_key(sets.late,risky_press,risky_cool),
		"the opening draft passes the early shift only")
	var sample_state = state_for(sample_press,sample_cool)
	var risky_state = state_for(risky_press,risky_cool)
	check(R.solved(sample_state) and R.shortfalls(sample_state).is_empty(),"the author sample is solved")
	check(R.page_ok(risky_state,6) and not R.page_ok(risky_state,8),"the draft disagrees between the two pages")
	check(not R.solved(risky_state),"the draft is not solved")
	# 全表逐格：11^6 张压制、冷却开工拍表，solved 与两页判定必须与 oracle 完全一致。
	var cell_bad = ""
	var early_bad = ""
	var late_bad = ""
	var solved_cells = 0
	var reason_bad = ""
	for a in range(MAX+1):
		for b in range(MAX+1):
			for c in range(MAX+1):
				for d in range(MAX+1):
					for e in range(MAX+1):
						for f in range(MAX+1):
							var press = [a,b,c]; var cool = [d,e,f]
							var s = state_for(press,cool)
							var key = key_of(press,cool)
							var want_early = sets.early.has(key)
							var want_late = sets.late.has(key)
							if R.page_ok(s,6) != want_early and early_bad.is_empty(): early_bad = key
							if R.page_ok(s,8) != want_late and late_bad.is_empty(): late_bad = key
							var good = want_early and want_late
							if R.solved(s) != good and cell_bad.is_empty(): cell_bad = key
							if good:
								solved_cells += 1
								if not R.shortfalls(s).is_empty() and reason_bad.is_empty():
									reason_bad = key+" -> solved but refused"
							elif R.shortfalls(s).is_empty() and reason_bad.is_empty():
								reason_bad = key+" -> refused without a reason"
	check(cell_bad.is_empty(),"solved agrees with the oracle on all 1771561 tables, first bad "+cell_bad)
	check(early_bad.is_empty(),"the early page agrees with the oracle, first bad "+early_bad)
	check(late_bad.is_empty(),"the late page agrees with the oracle, first bad "+late_bad)
	check(reason_bad.is_empty(),"every table is either solved or refused, first bad "+reason_bad)
	check(solved_cells == 19,"exactly 19 tables solve")
	check(R.solved(state_for([0,1,4],[1,3,6])) and R.solved(state_for([0,2,4],[1,4,6])),
		"the other robust shapes solve too")
	check(not R.solved(state_for([0,1,4],[1,3,5])),"an early-only plan is refused")
	check(not R.solved(state_for([0,1,4],[1,5,7])),"a late-only plan is refused")
	# 第一处真实原因：草稿是晚班第 7 拍暂存超限，早班反例与机器反例各念各的。
	var draft_gaps = R.shortfalls(puzzle())
	check(draft_gaps.size() == 1 and draft_gaps[0] ==
		"晚班：第 7 拍冷却到吊机间挤了两批：V 还在等吊机，M 又冷却完了——暂存位只有一批。",
		"the draft is refused for the late rack: "+str(draft_gaps))
	check(R.advance(puzzle()).is_empty(),"the draft cannot be claimed")
	var late_only = R.shortfalls(state_for([0,1,4],[1,5,7]))
	check(late_only.size() == 1 and "早班" in late_only[0] and "冷却完" in late_only[0],
		"a late-only plan is refused on the early page: "+str(late_only))
	check(R.run_conflict(state_for([0,1,4],[1,5,7]),6).row == 4,"the early page fails at the crane")
	var press_clash = R.run_conflict(state_for([0,1,1],[1,3,6]),6)
	check(press_clash.kind == "press_overlap" and press_clash.row == 0 and press_clash.tick == 1,
		"two presses in one beat: "+str(press_clash))
	check(R.shortfalls(state_for([0,1,1],[1,3,6]))[0].begins_with("第 1 拍压机还占着：V 的 1–3"),
		"the press clash names the tick and the batch")
	var cool_early = R.run_conflict(state_for([0,1,3],[0,3,6]),6)
	check(cool_early.kind == "cool_early" and cool_early.tick == 0,
		"cooling cannot start before the press ends: "+str(cool_early))
	check(R.shortfalls(state_for([0,1,3],[0,3,6]))[0].begins_with("F 到第 1 拍才下压机"),
		"cooling before the press names the real finish")
	var cool_out_of_turn = R.run_conflict(state_for([0,1,3],[3,1,6]),6)
	check(cool_out_of_turn.kind == "cool_order" and cool_out_of_turn.row == 2,
		"cooling must follow the press order: "+str(cool_out_of_turn))
	check(R.shortfalls(state_for([0,1,3],[3,1,6]))[0] == "冷却要按出压机的顺序：F 先下压机，冷却间却先接了 V。",
		"the out-of-turn cooling names both batches")
	var cool_clash = R.run_conflict(state_for([0,1,3],[1,3,4]),6)
	check(cool_clash.kind == "cool_overlap" and cool_clash.row == 2 and cool_clash.tick == 4,
		"two coolings in one beat: "+str(cool_clash))
	var press_rack = R.run_conflict(state_for([0,1,3],[1,5,7]),6)
	check(press_rack.kind == "press_rack" and press_rack.row == 1 and press_rack.tick == 4,
		"the press to cooling rack holds one batch: "+str(press_rack))
	check(R.shortfalls(state_for([0,1,3],[1,5,7]))[0].begins_with("第 4 拍压机到冷却间挤了两批"),
		"the press rack overflow names the tick")
	var press_late = R.run_conflict(state_for([10,1,3],[1,3,6]),6)
	check(press_late.kind == "press_late" and press_late.tick == 11,
		"a press that finishes after beat 10 is refused: "+str(press_late))
	check(R.shortfalls(state_for([10,1,3],[1,3,6]))[0] == "F 到第 11 拍才下压机，第 10 拍就要开船了。",
		"the late press names its real finish")
	var cool_late = R.run_conflict(state_for([0,1,3],[1,3,9]),6)
	check(cool_late.kind == "cool_late" and cool_late.tick == 11,"a cooling after beat 10 is refused: "+str(cool_late))
	check(R.shortfalls(state_for([0,1,3],[1,3,9]))[0] == "M 到第 11 拍才冷却完，赶不上第 10 拍开船。",
		"the late cooling names its real finish")
	var m_early_only = R.run_conflict(state_for([0,1,3],[1,3,5]),6)
	check(m_early_only.is_empty(),"the draft runs on the early page")
	var m_late = R.run_conflict(state_for([0,1,3],[1,3,5]),8)
	check(m_late.kind == "cool_rack" and m_late.tick == 7 and m_late.row == 3,
		"the draft is stopped at beat 7 on the late page: "+str(m_late))
	var fixed = R.run_conflict(state_for([0,1,3],[1,3,7]),8)
	check(fixed.is_empty(),"moving M cooling to 7–9 fixes the late page")
	check(R.solved(state_for([0,1,3],[1,3,7])),"7–9 cooling is also robust")
	check(R.solved(state_for([0,1,3],[1,3,6])),"6–8 cooling is the author sample")
	# 两页共用同一份草稿：判定只读状态，不改状态；两页的差别只在 V 的吊运点。
	var shared = state_for([0,1,3],[1,3,5])
	var before = shared.duplicate(true)
	R.page_ok(shared,6); R.page_ok(shared,8); R.solved(shared); R.shortfalls(shared)
	check(shared == before,"both pages read the same draft without touching it")
	check(R.load_start(6,0) == 3 and R.load_start(6,1) == 6 and R.load_start(6,2) == 9,
		"the early page loads F 3, V 6, M 9")
	check(R.load_start(8,0) == 3 and R.load_start(8,1) == 8 and R.load_start(8,2) == 9,
		"the late page moves only V to beat 8")
	# 阶段推进与操作守卫。
	var s = puzzle()
	check(R.validate(s) and s.press == [0,1,3] and s.cool == [1,3,5],"fresh progression reaches legal puzzle")
	check(R.validate(R.fresh()) and R.fresh().stage == "arrival","fresh opens at arrival")
	check(R.fresh().branch == 8 and not R.fresh().confirmed,"the actual shift is fixed in the save")
	check(R.set_press(R.fresh(),0,1).is_empty(),"no editing during dialogue")
	check(R.set_cool(R.advance(R.fresh()),0,2).is_empty(),"no editing during the walk-in")
	check(R.begin_trial(R.fresh()).is_empty(),"no trial during dialogue")
	check(R.restore(R.fresh(),{"press":[0,1,3],"cool":[1,3,6]}).is_empty(),"no undo during dialogue")
	check(R.set_press(s,0,11).is_empty() and R.set_press(s,0,-1).is_empty(),"press starts stay between 0 and 10")
	check(R.set_cool(s,0,11).is_empty(),"cooling starts stay between 0 and 10")
	check(R.set_press(s,3,1).is_empty() and R.set_press(s,-1,1).is_empty(),"only three batches exist")
	check(R.set_cool(s,3,1).is_empty(),"only three coolings exist")
	check(R.set_press(s,0,0).is_empty() and R.set_cool(s,0,1).is_empty(),"setting the same beat is a no-op")
	check(R.nudge_press(s,0,-1).is_empty(),"F cannot start before beat 0")
	check(R.set_press(s,0,10).press[0] == 10 and R.validate(R.set_press(s,0,10)),"a start of 10 is representable")
	var moved = R.nudge_press(s,2,2)
	check(moved.press == [0,1,5] and R.validate(moved),"moving M later is a legal draft")
	check(R.nudge_cool(moved,2,1).cool == [1,3,6],"M cooling can follow it")
	check(R.nudge_press(moved,2,-2).press == [0,1,3],"M moves back")
	check(R.begin_trial(moved).stage == "trial" and R.advance(R.begin_trial(moved)).stage == "puzzle",
		"the trial page returns to planning")
	check(R.validate(R.begin_trial(s)),"a trial state is legal")
	check(R.begin_trial(R.begin_trial(s)).is_empty(),"no trial inside a trial")
	check(R.set_press(R.begin_trial(s),0,2).is_empty(),"the trial page cannot edit the draft")
	# 提交只在两页都过的解上通过，演出逐级收尾。
	check(R.advance(risky_state).is_empty(),"the draft cannot be claimed")
	check(R.advance(state_for([0,1,4],[1,5,7])).is_empty(),"a late-only plan cannot be claimed")
	check(R.advance(state_for([0,0,3],[1,3,6])).is_empty(),"a press clash cannot be claimed")
	var delivery = R.advance(sample_state)
	check(delivery.stage == "delivery" and R.validate(delivery),"a solved plan enters delivery")
	var notice = R.advance(delivery)
	check(notice.stage == "notice" and not notice.confirmed and R.validate(notice),"delivery stops at beat 3 for the notice")
	check(notice.beat == 2,"the notice keeps the dialogue beat finished")
	var launch = R.advance(notice)
	check(launch.stage == "launch" and launch.confirmed and R.validate(launch),"confirming the notice starts the rest of the run")
	var handover = R.advance(launch)
	check(handover.stage == "handover" and handover.confirmed and R.validate(handover),"the run stops at the handover lever")
	var done = R.advance(handover)
	check(done.stage == "aftermath" and done.beat == 0 and R.validate(done),"the lever pull hands over to the dialogue")
	check(R.advance(done).beat == 1 and R.advance(R.advance(done)).beat == 2,"the ending dialogue steps by hand")
	var complete = R.advance(R.advance(R.advance(done)))
	check(complete.stage == "complete" and R.validate(complete),"manual discovery completes the level")
	check(R.advance(complete).is_empty(),"nothing follows complete")
	var walk_in = R.fresh(); walk_in.stage = "approach"
	check(not R.validate(walk_in),"a walk-in with the wrong beat is refused")
	# 撤销与重摆：六个开工拍一起回退，求助级别保留。
	var second_state = state_for([0,1,3],[1,3,6])
	var back = R.restore(second_state,{"press":[0,1,3],"cool":[1,3,5]})
	check(back.cool == [1,3,5] and R.validate(back),"undo restores both press and cool")
	var cleared = R.restore(second_state,{"press":R.DEFAULT_PRESS.duplicate(),"cool":R.DEFAULT_COOL.duplicate()})
	check(cleared.press == [0,1,3] and cleared.cool == [1,3,5],"reset returns the opening draft")
	check(R.restore(second_state,{"press":[0,1,3]}).is_empty(),"undo needs the whole snapshot")
	check(R.restore(second_state,{"press":[11,1,3],"cool":[1,3,6]}).is_empty(),"undo refuses out-of-range starts")
	check(R.restore(second_state,{"press":"013","cool":[1,3,6]}).is_empty(),"undo refuses a broken snapshot")
	var helped = R.nudge_cool(second_state,2,1); helped.hint = 3
	check(R.restore(helped,{"press":R.DEFAULT_PRESS.duplicate(),"cool":R.DEFAULT_COOL.duplicate()}).hint == 3,
		"undo retains the help level")
	# 伪造、越界与旧版一律拒绝。
	for stage in ["delivery","notice","launch","handover","aftermath","complete"]:
		var good = state_for([0,1,3],[1,3,6]); good.stage = stage
		good.confirmed = stage in ["launch","handover","aftermath","complete"]
		check(R.validate(good),"solved %s is legal"%stage)
		var forged = state_for([0,1,4],[1,5,7]); forged.stage = stage
		forged.confirmed = good.confirmed
		check(not R.validate(forged),"forged %s rejected"%stage)
	check(R.validate(puzzle()),"the opening draft is a legal puzzle state")
	for bad_stage in ["trial ","complete ","",5,true]:
		var c = state_for([0,1,3],[1,3,6]); c.stage = bad_stage
		check(not R.validate(c),"invalid stage rejected")
	var old = state_for([0,1,3],[1,3,6]); old.sample = "workshop-gw18-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var extra = state_for([0,1,3],[1,3,6]); extra.attempts = 1
	check(not R.validate(extra),"closed schema")
	var missing = state_for([0,1,3],[1,3,6]); missing.erase("branch")
	check(not R.validate(missing),"missing field rejected")
	for bad_branch in [6,0,7,9,"8",true]:
		var c = state_for([0,1,3],[1,3,6]); c.branch = bad_branch
		check(not R.validate(c),"forged shift rejected")
	for bad_confirmed in [0,1,"true",{}]:
		var c = state_for([0,1,3],[1,3,6]); c.confirmed = bad_confirmed
		check(not R.validate(c),"non-boolean confirmed rejected")
	var lying = state_for([0,1,3],[1,3,6]); lying.stage = "launch"
	check(not R.validate(lying),"launch without the notice confirmation is refused")
	var unconfirmed = state_for([0,1,3],[1,3,6]); unconfirmed.stage = "notice"; unconfirmed.confirmed = true
	check(not R.validate(unconfirmed),"a confirmed notice is not a notice any more")
	for bad_press in [[0,1],[-1,1,3],[11,1,3],[0,1,3,4],[0,1,2.0],[0,1,true],"013",{}]:
		var c = state_for([0,1,3],[1,3,6]); c.press = bad_press
		check(not R.validate(c),"invalid press table rejected")
	for bad_cool in [[1,3],[-1,3,6],[1,3,11],[1,3,6,7],[1,3,null]]:
		var c = state_for([0,1,3],[1,3,6]); c.cool = bad_cool
		check(not R.validate(c),"invalid cooling table rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = state_for([0,1,3],[1,3,6]); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = state_for([0,1,3],[1,3,6]); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early_solved = state_for([0,1,3],[1,3,6]); early_solved.stage = "ready"
	check(not R.validate(early_solved),"a solved table cannot appear during dialogue")
	var short_beat = state_for([0,1,3],[1,3,6]); short_beat.beat = 1
	check(not R.validate(short_beat),"planning needs the dialogue to be finished")
	var edited_draft = R.fresh(); edited_draft.press = [0,1,4]
	check(not R.validate(edited_draft),"the opening draft cannot be pre-edited")
	# 正式运行按实际班次走：晚班 V 第 8 拍，三处接收记录齐全，逐拍暂存不挤。
	var run_state = delivery
	var finished = []; var loads = []
	for index in range(3):
		finished.append(run_state.cool[index]+R.COOL_TIME)
		loads.append(R.load_start(run_state.branch,index))
	check(loads == [3,8,9],"the actual run lifts F 3, V 8, M 9")
	check(finished[0] <= 3 and finished[1] <= 8 and finished[2] <= 9,"every cooling finishes before its crane slot")
	check(rack_ok(finished,loads),"the actual run never crowds the crane rack")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw18-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(puzzle(),R.validate),"save accepted the opening draft")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(sample_state,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == puzzle(),"restart restores the saved draft")
	check(repo.write_profile(complete,R.validate),"retry exact completion")
	var file = FileAccess.open(repo.path,FileAccess.WRITE); file.store_string('{"broken":true}'); file.close()
	hash = FileAccess.get_sha256(repo.path)
	check(repo.read_profile(R.validate).status == "protected","bad save protected")
	check(not repo.write_profile(R.fresh(),R.validate) and FileAccess.get_sha256(repo.path) == hash,
		"protected file never overwritten")
	var backup = repo.preserve_protected_file()
	check(not backup.is_empty() and FileAccess.get_sha256(backup) == hash,"explicit recovery preserves backup")
	for p in [repo.path,repo.path+".tmp",backup]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(repo.path.get_base_dir())
	print("GW18 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

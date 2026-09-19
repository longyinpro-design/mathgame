extends SceneTree
# MK07 无头检查：分配真值、整批试交的入账时机、存档契约与真实场景的按钮可用性。
# 运行：godot --headless --path . --script tests/market/mk07_test.gd
const Rules = preload("res://scripts/market/mk07_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk07.tscn")
const TRAP = [2,0,3,1]
const SWAP = [0,1,2,3]
const EMPTY = [-1,-1,-1,-1]
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk07-rules-"+str(Time.get_ticks_usec())+".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)

func table(plan: Array, failed: Array = [], stage: String = "puzzle") -> Dictionary:
	var state = Rules.fresh()
	state.stage = stage
	state.plan = plan.duplicate(true)
	state.failed = failed.duplicate(true)
	return state

func permutations(pool: Array, held: Array, out: Array) -> void:
	if pool.is_empty():
		out.append(held.duplicate(true))
		return
	for index in range(pool.size()):
		var rest: Array = pool.duplicate(true)
		var taken: int = rest.pop_at(index)
		permutations(rest, held + [taken], out)

# 预定影的下坠只影响手感：清掉宿主的落地锁再重画，热点的可用状态才与实窗一致。
func settle(game: Node) -> void:
	game.transient = 0.0
	game.refresh()

func ui_text(game: Node) -> String:
	# 完成后的分配单是 UI 层的 Label，逐个取出来比对文案。
	var text := ""
	for child in game.ui.get_children():
		if child is Label: text += child.text + "\n"
	return text

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("MK07 rule watchdog"); quit(1))
	# ---- 开局与阶段表 ----
	check(Rules.validate(Rules.fresh()),"fresh model valid")
	check(Rules.fresh().sample == "market-mk07-1","fresh carries the mk07 sample id")
	check(Rules.fresh().plan == EMPTY and Rules.fresh().failed == [],
		"fresh opens with four goods on the counter and no trials")
	var animated := 0
	for stage in Rules.ANIMATIONS:
		if stage in Rules.STAGES: animated += 1
	check(animated == Rules.ANIMATIONS.size() and "puzzle" in Rules.STAGES and "complete" in Rules.STAGES,
		"every animation stage is a real stage")
	check(Rules.ANIMATIONS == ["approach","handover","delivery"],"walk-in, batch hand-over and delivery animate")
	# ---- 数学真值：唯一完美匹配 ----
	check(Rules.ACCEPT[2] == [3] and Rules.ACCEPT[3] == [2],"乐手只能用铃、医护只能用布")
	check(Rules.ACCEPT[0] == [0,2] and Rules.ACCEPT[1] == [0,1],"帆匠能用绳或布、修桥人能用绳或钉")
	check(Rules.SOLUTION == [0,1,3,2],"the accepted allocation is 绳/钉/铃/布")
	check(Rules.is_plan(Rules.SOLUTION,true) and Rules.unmet_of(Rules.SOLUTION).is_empty(),
		"the accepted allocation is a complete matching nobody objects to")
	var all: Array = []
	permutations([0,1,2,3],[],all)
	check(all.size() == 24,"24 complete assignments of four goods to four residents")
	var winners: Array = []
	var silent := 0
	for plan in all:
		if Rules.unmet_of(plan).is_empty(): winners.append(plan)
		elif plan == Rules.SOLUTION: silent += 1
	check(winners.size() == 1 and winners[0] == Rules.SOLUTION,"enumeration: exactly one complete assignment satisfies everyone")
	check(silent == 0,"no complete assignment is wrong without a named shortfall")
	# ---- 贪心陷阱：先把布交给帆匠 ----
	check(Rules.is_plan(TRAP,true) and Rules.unmet_of(TRAP) == [[3,2]],"布给帆匠满足眼前请求却让医护无物可用")
	check(Rules.trial_report(TRAP).size() == 1,"the trap names exactly one unmet household")
	check("医护还没有能用的布" in Rules.trial_report(TRAP)[0],"the shortfall text names the person and the good")
	check("布在帆匠手里" in Rules.trial_report(TRAP)[0] and "他也能用绳" in Rules.trial_report(TRAP)[0],
		"the report shows the good sits with a household that could use something else")
	var clothed := 0
	var stranded := 0
	for plan in all:
		if plan[0] == 2:
			clothed += 1
			if Rules.unmet_of(plan).has([3,2]): stranded += 1
	check(clothed == 6 and stranded == 6,"every plan that gives 帆匠 the cloth strands 医护")
	check(Rules.unmet_of(SWAP) == [[2,3],[3,2]],"swapping 铃 and 布 leaves two households without a usable good")
	check(Rules.trial_report(SWAP).size() == 2,"a two-household shortfall reports both")
	check("他也能用" not in Rules.trial_report(SWAP)[0],"a holder with no second option is not called substitutable")
	# ---- 缺口说明：只讲结构，不提前判卷 ----
	var fresh = Rules.fresh()
	check(Rules.shortfalls(fresh).size() == 4,"an empty table reports four missing residents")
	check("医护" in Rules.shortfalls(fresh)[3] and "只能用布" in Rules.shortfalls(fresh)[3],
		"each shortfall names the resident and what they can use")
	check(Rules.shortfalls(table([2,-1,-1,-1])) == ["修桥人还没有分到东西：能用绳或钉。","乐手还没有分到东西：只能用铃。",
		"医护还没有分到东西：只能用布。"],"a partly set table lists the remaining duties in resident order")
	check(Rules.shortfalls(table(TRAP)).is_empty(),"a complete but wrong plan is never blocked before the trial")
	check(Rules.assigned(table([2,0,-1,-1])) == 2 and Rules.free_goods(table([2,0,-1,-1])) == [1,3],
		"the counter keeps exactly the goods nobody reserved")
	check(Rules.usable_text(0) == "能用绳或布" and Rules.usable_text(3) == "只能用布",
		"substitutable and fixed demands are worded differently")
	# ---- 玩家动作 ----
	check(Rules.give(fresh,0,0).is_empty() and Rules.take_back(fresh,0).is_empty(),
		"nothing can be arranged before the street opens")
	var first = Rules.give(table(EMPTY),0,0)
	check(first.plan == [0,-1,-1,-1] and Rules.validate(first),"one good reserved for one resident")
	check(Rules.give(first,1,0).is_empty(),"a reserved good cannot be promised to a second resident")
	check(Rules.give(first,0,0).is_empty(),"reserving the same good twice changes nothing")
	var replaced = Rules.give(first,0,2)
	check(replaced.plan == [2,-1,-1,-1] and Rules.free_goods(replaced) == [0,1,3],
		"replacing a reservation returns the older good to the counter")
	check(Rules.give(first,4,0).is_empty() and Rules.give(first,0,4).is_empty() and Rules.give(first,-1,0).is_empty(),
		"resident and good indices stay inside the street")
	var taken = Rules.take_back(first,0)
	check(taken.plan == EMPTY and Rules.validate(taken),"a reserved good goes back to the counter")
	check(Rules.take_back(taken,0).is_empty(),"an empty resident cannot give anything back")
	# ---- 撤销：只回退摆放，不抹掉已经发生过的试交 ----
	var evidence: Array = [TRAP]
	var edited = Rules.give(table([-1,0,3,2]),0,1)
	check(Rules.restore(edited,{"plan":[-1,0,3,2]}).plan == [-1,0,3,2],"undo puts the good back on the counter")
	check(Rules.restore(Rules.take_back(edited,1),{"plan":[1,0,3,2]}).plan == [1,0,3,2],
		"undo puts a taken-back good back in hand")
	check(Rules.restore(edited,{"plan":[0,0,3,2]}).is_empty(),"undo refuses a snapshot that double-books a good")
	check(Rules.restore(edited,{}).is_empty(),"undo refuses a snapshot without a plan")
	var kept = Rules.restore(table([1,0,3,2],evidence),{"plan":EMPTY})
	check(kept.plan == EMPTY and kept.failed == evidence,"undo rewinds the arrangement but keeps the trial record")
	check(Rules.restore(table(Rules.SOLUTION,[],"delivery"),{"plan":EMPTY}).is_empty(),
		"undo only works at the assignment table")
	# ---- 阶段推进 ----
	var walk = Rules.fresh()
	check(Rules.advance(walk).beat == 1 and Rules.advance(walk).stage == "arrival","arrival plays its lines in order")
	walk = Rules.advance(Rules.advance(Rules.advance(walk)))
	check(walk.beat == Rules.BEATS - 1 and walk.stage == "arrival","the last arrival line is still dialogue")
	walk = Rules.advance(walk)
	check(walk.stage == "approach" and Rules.advance(walk).stage == "ready","the walk-in hands over to the briefing")
	var opened = Rules.advance(Rules.advance(walk))
	check(opened.stage == "puzzle" and opened.plan == EMPTY,"the street opens with nothing arranged")
	check(Rules.advance(opened).is_empty(),"an empty table cannot be handed over")
	check(Rules.advance(table([0,1,3,-1])).is_empty(),"three of four residents is not a batch")
	var staged = Rules.advance(table(TRAP))
	check(staged.stage == "handover" and staged.plan == TRAP,"a complete plan leaves for the hand-over exactly as arranged")
	var bounced = Rules.advance(staged)
	check(bounced.stage == "puzzle" and bounced.plan == TRAP,"a failed trial keeps the player's plan on the table")
	check(bounced.failed == [TRAP],"the failed trial is recorded as evidence")
	check(Rules.assigned(bounced) == 4 and Rules.free_goods(bounced).is_empty(),"the failed trial consumed no goods")
	check(Rules.validate(bounced),"the state after a failed trial is a legal save")
	check(Rules.advance(Rules.advance(table(TRAP))).failed == [TRAP],
		"repeating the same failed trial does not duplicate the record")
	var second = Rules.advance(Rules.advance(table(SWAP,evidence)))
	check(second.failed == [TRAP,SWAP] and second.plan == SWAP,"a different failed plan is appended after the first")
	check(Rules.advance(table(Rules.SOLUTION,evidence)).stage == "handover","an already-recorded table may be tried again")
	var won = Rules.advance(table(Rules.SOLUTION))
	var accepted = Rules.advance(won)
	check(won.stage == "handover" and accepted.stage == "delivery","the accepted batch releases the street delivery")
	check(accepted.plan == Rules.SOLUTION and Rules.advance(accepted).stage == "complete",
		"the delivery ends in the finished street scene")
	check(Rules.advance(table(Rules.SOLUTION,evidence,"complete")).is_empty(),"the complete stage is terminal")
	# ---- 存档校验：伪造与半成品 ----
	for bad in [null,{},[],"x",5.0,[0,0]]: check(not Rules.validate(bad),"reject record "+str(bad))
	var forged = table(TRAP); forged.sample = "market-mk06-1"
	check(not Rules.validate(forged),"another level's sample id is corruption")
	forged = table(TRAP); forged.stage = "market"
	check(not Rules.validate(forged),"unknown stage rejected")
	check(not Rules.validate(table([0,0,3,2])),"one good cannot be promised to two residents")
	check(not Rules.validate(table([0,1,3,4])),"a fifth good is out of range")
	check(not Rules.validate(table([0,1,3,-2])),"-2 is not an empty slot")
	check(not Rules.validate(table([0,1,3.5,2])),"fractional goods are corruption")
	check(not Rules.validate(table([0,1,3,2,0])),"a five-slot plan is corruption")
	forged = table(TRAP); forged.hint = Rules.HINTS + 1
	check(not Rules.validate(forged),"hint level is capped by the shipped hints")
	forged = table(TRAP); forged.hint = -1
	check(not Rules.validate(forged),"hint cannot go negative")
	forged = Rules.fresh(); forged.beat = Rules.BEATS
	check(not Rules.validate(forged),"arrival cannot claim an unseen line")
	forged = table(TRAP); forged.erase("plan")
	check(not Rules.validate(forged),"a missing field is corruption, not a default")
	forged = table(TRAP); forged.failed = [Rules.SOLUTION]
	check(not Rules.validate(forged),"a satisfied plan cannot be filed as a failed trial")
	forged = table(TRAP); forged.failed = [[0,1,-1,2]]
	check(not Rules.validate(forged),"only a complete plan may be recorded as a trial")
	forged = table(TRAP); forged.failed = [TRAP,TRAP]
	check(not Rules.validate(forged),"the same trial is not booked twice")
	forged = table(TRAP); forged.failed = TRAP
	check(not Rules.validate(forged),"the trial record is a list of plans")
	check(not Rules.validate(table(TRAP,evidence,"complete")),"a complete whose plan is not the accepted matching is rejected")
	forged = table(TRAP,[],"delivery")
	check(not Rules.validate(forged),"a hand-over that never satisfied anyone cannot be delivered")
	forged = table([0,1,3,-1],[],"handover")
	check(not Rules.validate(forged),"a batch hand-over with a missing resident is corruption")
	check(not Rules.validate(table(TRAP,[],"arrival")),"the street cannot open already arranged")
	check(Rules.validate(table(Rules.SOLUTION,evidence,"complete")),"an honest save keeps plan and trial record together")
	check(Rules.validate(table(EMPTY,evidence)),"重摆之后回执仍然留在街上")
	# ---- 关卡身份与目录一致 ----
	var probe = Scene.instantiate()
	probe.configure()
	check(probe.save_path == Catalog.save_path("MK07"),"the level's default save is the market-mk07-1 profile")
	check(probe.scene_id == Catalog.LEVELS.MK07.kit and probe.level_id == "MK07",
		"the street kit and the MK07 identity agree with the catalogue")
	check(probe.title == Catalog.title("MK07"),"the title matches the catalogue entry")
	check(probe.rules == Rules and probe.world_script.resource_path.ends_with("mk07_world.gd"),
		"the scene wires its own rules and world")
	probe.free()
	var entry: Dictionary = Catalog.LEVELS["MK07"]
	check(entry.scene == "res://game/market_mk07.tscn" and entry.after == "MK06" and entry.act == 3,
		"the catalogue points at this scene after MK06 in act three")
	check(ResourceLoader.exists("res://game/market_mk07.tscn") and Catalog.built("MK07"),
		"the chart can light MK07 because the scene file exists")
	# ---- 真实场景：台词、按钮与热点 ----
	var game = Scene.instantiate()
	game.save_path = path
	root.add_child(game)
	await process_frame
	check(game.save_path == path,"configure() only fills an empty save path")
	check(game.state.stage == "arrival" and game.buttons.has("next") and not game.buttons.has("deliver"),
		"arrival offers the next line, not the hand-over")
	check(game.buttons.next.text == "继续听他们说","the first arrival line keeps talking")
	for step in range(Rules.BEATS - 1): game.advance(); await process_frame
	check(game.state.beat == Rules.BEATS - 1 and game.buttons.next.text == "走上前去","the last line walks the player in")
	game.advance(); await process_frame
	check(game.state.stage == "approach" and game.buttons.has("skip") and game.buttons.has("pause"),
		"the walk-in can be paused or skipped")
	game.skip_animation(); await process_frame
	check(game.state.stage == "ready" and game.buttons.next.text == "开始分配","the briefing explains the click order")
	game.advance(); await process_frame
	check(game.state.stage == "puzzle" and game.goal_line().contains("四位居民"),"the street opens with the goal on screen")
	check(game.hint_texts().size() == Rules.HINTS,"three hints shipped, no more")
	var live := 0
	for good in range(Rules.COUNT):
		var rect = game.world.good_rect(good)
		if game.buttons.has("good_%d"%good) and rect.size.x >= 48 and rect.size.y >= 48: live += 1
	for person in range(Rules.COUNT):
		var stall_rect = game.world.person_rect(person)
		if game.buttons.has("person_%d"%person) and stall_rect.size.x >= 48 and stall_rect.size.y >= 48: live += 1
	check(live == 8,"eight hit targets of at least 48 logical pixels are live on the street")
	check(game.buttons.deliver.text == "整批试交" and not game.buttons.deliver.disabled,
		"the batch hand-over button is labelled and ready")
	check(game.buttons.undo.disabled and not game.buttons.hint.disabled,"undo waits for the first move")
	check(game.world.stations.has("counter") and game.world.stations.has("stall_midright"),
		"the stations come from the manifest, not invented coordinates")
	game.advance()
	check(game.state.stage == "puzzle" and "还没有分到东西" in game.message,
		"submitting an empty table explains what is missing instead of trying")
	game.commit(table(EMPTY))
	check(game.state.plan == EMPTY and game.history.is_empty(),"a saved table opens without history")
	game.choose_person(3)
	check("先在柜台上点一件货" in game.message and game.history.is_empty(),
		"an empty hand without a picked good is explained, not committed")
	game.choose_good(2)
	check(game.picked == 2 and game.state.plan == EMPTY,"picking a good moves no goods")
	game.choose_person(0); settle(game)
	check(game.state.plan == [2,-1,-1,-1] and game.picked == -1,"the picked good is reserved for 帆匠")
	var snap: Dictionary = game.snapshot(game.state)
	check(snap.plan == [2,-1,-1,-1],"the undo snapshot records the arrangement")
	snap.plan[0] = 3
	check(game.state.plan[0] == 2,"snapshots are copied, never aliased")
	game.choose_good(2)
	check(game.state.plan == EMPTY,"clicking the reserved good on the counter puts it back")
	game.undo(); settle(game)
	check(game.state.plan == [2,-1,-1,-1] and game.history.size() == 1,"undo puts the reservation back in hand")
	game.do_reset()
	check(game.state.plan == EMPTY and game.cleared_state().failed == [],"重摆 clears the table for a fresh arrangement")
	for person in range(Rules.COUNT):
		game.choose_good(Rules.SOLUTION[person]); game.choose_person(person); settle(game)
	check(game.state.plan == Rules.SOLUTION and Rules.solved(game.state),
		"the four residents can each be handed their accepted good")
	game.choose_good(0)
	check(game.state.plan == [-1,1,3,2] and Rules.free_goods(game.state) == [0],
		"clicking a promised good takes it back from its resident")
	game.choose_good(0); game.choose_person(2); settle(game)
	check(game.state.plan == [-1,1,0,2] and Rules.free_goods(game.state) == [3],
		"a new good handed over puts the older one back on the counter")
	game.commit(table(EMPTY))
	for person in range(Rules.COUNT):
		game.choose_good(TRAP[person]); game.choose_person(person); settle(game)
	check(game.state.plan == TRAP,"the greedy trap is reachable by ordinary clicks")
	game.confirm_reset()
	check(game.modal,"重摆 asks before clearing the street")
	game.advance()
	check(game.modal and game.state.stage == "puzzle","an open modal never starts the hand-over")
	game.close_modal()
	check(game.state.stage == "puzzle" and game.state.plan == TRAP,"leaving the dialog keeps the arrangement")
	game.advance()
	check(game.state.stage == "handover" and game.state.plan == TRAP,"the complete plan leaves as one batch")
	game.skip_animation()
	check(game.state.stage == "puzzle" and game.state.plan == TRAP and game.state.failed == [TRAP],
		"the failed trial leaves the plan on the table and records itself")
	check(game.has_report() and "苔团" in game.line() and "医护还没有能用的布" in game.line(),
		"the report names the real unmet need with 苔团's framing")
	check(game.state.hint == 0,"a failed trial costs no hints and no goods")
	game.undo()
	check(game.state.plan == [2,0,3,-1] and game.state.failed == [TRAP],
		"undo rewinds the placement without erasing the failure on record")
	game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINTS and "布已经归医护" in game.message,"the third hint gives the last step")
	check(Rules.validate(game.state),"a used-up hint level still saves")
	game.do_reset()
	check(game.state.plan == EMPTY and game.state.failed == [TRAP],"重摆 keeps the failed trial on record")
	for person in range(Rules.COUNT):
		game.choose_good(Rules.SOLUTION[person]); game.choose_person(person); settle(game)
	check(game.state.plan == Rules.SOLUTION,"the accepted plan is still reachable after the failure")
	game.advance()
	check(game.state.stage == "handover" and game.state.plan == Rules.SOLUTION,"the corrected plan goes to the hand-over")
	game.queue_free()
	await process_frame
	# ---- 重载：现场与回执都从存档里回来 ----
	game = Scene.instantiate()
	game.save_path = path
	game.paused = true
	root.add_child(game)
	await process_frame
	check(game.state.stage == "handover" and game.state.plan == Rules.SOLUTION,"reload resumes an unfinished hand-over")
	game.skip_animation()
	check(game.state.stage == "delivery","the accepted batch is delivered once the animation is booked")
	game.skip_animation()
	check(game.state.stage == "complete" and game.state.failed == [TRAP],
		"the street finishes with the trial record intact")
	check(game.buttons.has("next") and game.buttons.next.text == "重新体验","the complete stage offers a replay")
	check(game.buttons.has("open_hub"),"a standalone run still has a way back to the chart")
	var receipt := ui_text(game)
	check("分配单" in receipt and "医护 ← 布" in receipt and "乐手 ← 铃" in receipt,
		"the receipt restates who received what")
	check("第一次试交：布给了帆匠" in receipt and "医护那时还没有能用的布" in receipt,
		"the receipt keeps the failed first trial in the open")
	game.queue_free()
	await process_frame
	Bridge.origin = "hub"
	game = Scene.instantiate()
	game.save_path = path
	root.add_child(game)
	await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
	check(game.state.stage == "complete" and game.buttons.has("back_hub"),"a finished visit returns to the chart")
	check(not game.buttons.has("leave_hub"),"the chart button is not doubled on the complete stage")
	game.repository.fail_at = "open"
	game.commit(table(TRAP))
	check(game.modal and game.state.stage == "complete","a failed write cannot publish a new arrangement")
	game.repository.fail_at = ""
	game.retry_save()
	check(game.state.plan == TRAP and game.state.stage == "puzzle","retry publishes the same plan once the disk works")
	check(game.buttons.has("leave_hub"),"arriving from the chart keeps a way out mid-arrangement")
	game.queue_free()
	await process_frame
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate()
	game.save_path = path
	root.add_child(game)
	await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK07 RULES ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

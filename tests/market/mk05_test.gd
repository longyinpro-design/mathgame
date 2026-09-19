extends SceneTree
const Rules = preload("res://scripts/market/mk05_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk05.tscn")
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk05-rules-"+str(Time.get_ticks_usec())+".json"
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)

# 去处按街上从左到右：面包铺、育苗铺、桥头、邮亭。设计里唯一的那一对是 [1,0,2,3]。
func board(a: int, b: int, c: int, d: int, stage: String = "puzzle") -> Dictionary:
	var state = Rules.fresh(); state.stage = stage
	state.assign = [a, b, c, d]
	return state

func permutations() -> Array:
	var out = []
	for a in range(4):
		for b in range(4):
			if b == a: continue
			for c in range(4):
				if c == a or c == b: continue
				for d in range(4):
					if d == a or d == b or d == c: continue
					out.append([a,b,c,d])
	return out

func matches(assign: Array, skip: int) -> bool:
	for index in range(Rules.CLUES.size()):
		if index == skip: continue
		if Rules.clue_broken(Rules.CLUES[index], assign): return false
	return true

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("MK05 rule watchdog"); quit(1))
	# ---- 模型与唯一解 ----
	check(Rules.validate(Rules.fresh()),"fresh model valid")
	check(Rules.fresh().assign == [-1,-1,-1,-1] and Rules.fresh().hand == -1,"fresh board is empty and nothing is in hand")
	check(Rules.fresh().sample == "market-mk05-1","the level keeps its own sample id")
	var mismatches = 0
	var winners = 0
	var legal = 0
	for a in range(-1,4):
		for b in range(-1,4):
			for c in range(-1,4):
				for d in range(-1,4):
					var state = board(a,b,c,d)
					var doubled = (a >= 0 and [b,c,d].has(a)) or (b >= 0 and [c,d].has(b)) or (c >= 0 and d == c)
					if Rules.validate(state) == doubled: mismatches += 1
					if not doubled: legal += 1
					if Rules.solved(state):
						winners += 1
						if [a,b,c,d] != [1,0,2,3]: mismatches += 1
	check(mismatches == 0,"625 board states agree with one tag, one place")
	check(legal == 209,"the schema admits exactly the 209 boards that use a tag at most once")
	check(winners == 1,"the three surviving clues force a single matching")
	# 同一张签按在两家：三句话都读得通，但它是坏档，不能当成配好了。
	var conflict = board(1,0,0,3)
	check(not Rules.validate(conflict),"a tag pressed in two shops is a corrupt board")
	check(not Rules.solved(conflict) and Rules.advance(conflict).is_empty(),
		"a self-conflicting board never releases the delivery")
	var agree = 0
	for order in permutations():
		if Rules.solved(board(order[0],order[1],order[2],order[3])) == matches(order,-1): agree += 1
	check(agree == 24,"the shortfall list and the clue model read the same 24 pairings")
	# 三条线索一条都不能少：抹掉任何一条都会多出第二种配法。
	for index in range(Rules.CLUES.size()):
		var widened = 0
		for order in permutations():
			if matches(order,index): widened += 1
		check(widened > 1,"dropping clue %d admits a second matching"%index)
	# ---- 缺口点名：说清是哪一句留下的话被摆坏了 ----
	check(Rules.shortfalls(board(-1,-1,-1,-1)) == ["订单板上还有 4 家没按货签：面包铺、育苗铺、桥头、邮亭。"],"an empty board lists every open place")
	check(Rules.shortfalls(board(1,0,-1,-1)) == ["订单板上还有 2 家没按货签：桥头、邮亭。"],"a half board counts what is still open")
	var trap = board(2,0,1,3)
	check(Rules.validate(trap) and not Rules.solved(trap),"the guess that ignores the third clue is legal but wrong")
	check(Rules.shortfalls(trap) == ["留下的话：面包铺不收铃。铜铃按在了面包铺。"],"the trap is stopped by the clue it breaks")
	check(Rules.shortfalls(board(1,0,3,2)) == ["留下的话：纸去邮亭。纸卷现在按在桥头。"],"a misplaced 纸 names its own clue")
	check(Rules.shortfalls(board(1,3,2,0))[0] == "留下的话：布去育苗铺。布卷现在按在邮亭。","a misplaced 布 names its own clue")
	var doubled = Rules.shortfalls(board(1,3,2,0))
	check(doubled.size() == 2 and doubled[1].find("纸去邮亭") >= 0,"a board breaking two clues reports both")
	check(Rules.shortfalls(board(-1,3,-1,-1)) == ["留下的话：布去育苗铺。育苗铺现在按的是纸卷。","留下的话：纸去邮亭。纸卷现在按在育苗铺。","订单板上还有 3 家没按货签：面包铺、桥头、邮亭。"],"an occupied place can break a clue while its own tag is still loose")
	# ---- 阶段机 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival","arrival plays its lines in order")
	arriving = Rules.advance(arriving)
	arriving = Rules.advance(arriving)
	check(arriving.stage == "approach" and arriving.beat == 2,"the third line walks the player into the street")
	check(Rules.advance(arriving).stage == "ready","the walk-in lands on the order board")
	check(Rules.advance(Rules.advance(arriving)).stage == "puzzle","the board opens one stage later")
	var opened = Rules.advance(Rules.advance(arriving))
	check(opened.assign == [-1,-1,-1,-1] and opened.stage == "puzzle","the walk-in never touches the tags")
	check(Rules.advance(opened).is_empty(),"an empty board cannot be handed over")
	check(Rules.advance(board(1,0,2,-1)).is_empty(),"one open place still blocks the delivery")
	check(Rules.advance(trap).is_empty(),"a board that breaks a clue cannot be handed over")
	var ready = Rules.advance(board(1,0,2,3))
	check(ready.stage == "delivery" and ready.assign == [1,0,2,3],"the matching board releases the delivery")
	check(Rules.advance(ready).stage == "complete","the delivery ends on the receipt")
	check(Rules.advance(Rules.advance(ready)).is_empty(),"the receipt only offers to replay")
	# ---- 拿起、按下、取回 ----
	var table = board(-1,-1,-1,-1)
	check(Rules.pick(table,0).hand == 0,"a loose tag can be picked up")
	check(Rules.pick(Rules.pick(table,0),0).hand == -1,"picking it again puts it back on the counter")
	check(Rules.pick(Rules.pick(table,0),1).hand == 1,"switching hands keeps exactly one tag in the air")
	check(Rules.pick(board(1,0,2,3),0).is_empty(),"a tag already pinned cannot be picked off the counter")
	check(Rules.pick(table,4).is_empty() and Rules.pick(table,-1).is_empty(),"tags outside the four are refused")
	var held = Rules.pick(table,2)
	check(Rules.drop(held,0).assign == [2,-1,-1,-1],"the held tag lands on the place you press")
	check(Rules.drop(held,4).is_empty() and Rules.drop(held,-1).is_empty(),"places outside the four are refused")
	check(Rules.drop(table,0).is_empty(),"nothing lands while the hand is empty")
	var pinned = Rules.drop(held,1)
	check(Rules.take(pinned,1).assign == [-1,-1,-1,-1],"pressing a filled place takes its tag back")
	check(Rules.take(pinned,0).is_empty(),"an empty place has nothing to take back")
	check(Rules.take(Rules.pick(pinned,3),1).is_empty(),"a filled place cannot be emptied while another tag is in hand")
	var cloth_on = Rules.drop(Rules.pick(table,0),0)
	var swapped = Rules.drop(Rules.pick(cloth_on,3),0)
	check(swapped.assign == [3,-1,-1,-1] and Rules.loose(swapped) == [0,1,2],"pressing a filled place sends its tag back to the counter")
	for stage in Rules.STAGES:
		if stage == "puzzle": continue
		var elsewhere = board(1,0,2,3,stage)
		var refused = Rules.pick(elsewhere,0).is_empty() and Rules.drop(elsewhere,0).is_empty() and Rules.take(elsewhere,0).is_empty()
		check(refused,"tags only move at the order board, not at "+stage)
	# ---- 撤销 ----
	var snapshot = {"assign":[1,0,2,3],"hand":-1}
	check(Rules.restore(Rules.take(board(1,0,2,3),2),snapshot).assign == [1,0,2,3],"undo puts the taken tag back")
	check(Rules.restore(board(1,0,2,-1),{"assign":[1,0,-1,3],"hand":2}).hand == 2,"undo returns the tag that was in hand")
	check(Rules.restore(board(1,0,2,3),{"assign":[1,1,2,3],"hand":-1}).is_empty(),"undo refuses a board with one tag in two places")
	check(Rules.restore(board(1,0,2,3),{"assign":[1,0,2,3]}).is_empty(),"undo refuses a record without the hand")
	check(Rules.restore(board(1,0,2,3),{"assign":[-1,-1,-1,-1],"hand":-1}).assign == [-1,-1,-1,-1],"undo can clear the whole board")
	check(Rules.restore(board(1,0,2,3,"delivery"),snapshot).is_empty(),"undo only works while the board is open")
	check(Rules.restore(board(1,0,2,3,"arrival"),snapshot).is_empty(),"undo never rewinds the walk-in")
	# ---- 存档 schema ----
	for bad in [null,{},[],"x",5.0,[0,0]]: check(not Rules.validate(bad),"reject record "+str(bad))
	var forged = Rules.fresh(); forged.sample = "market-mk02-1"
	check(not Rules.validate(forged),"another level's sample is refused")
	forged = Rules.fresh(); forged.stage = "measuring"
	check(not Rules.validate(forged),"an unknown stage is refused")
	forged = board(1,0,2,3); forged.assign[0] = 1.0
	check(not Rules.validate(forged),"a float board entry is corruption, not a number")
	forged = board(1,0,2,3); forged.assign[1] = 1
	check(not Rules.validate(forged),"布 cannot sit on two places at once")
	forged = board(1,0,2,3); forged.assign.resize(3)
	check(not Rules.validate(forged),"a short board is refused")
	forged = board(1,0,2,3); forged.assign[3] = 4
	check(not Rules.validate(forged),"a tag outside the four is refused")
	forged = board(1,0,2,3,"complete"); forged.assign[1] = 2
	check(not Rules.validate(forged),"a receipt cannot claim a matching that breaks a clue")
	forged = board(1,0,2,-1,"delivery")
	check(not Rules.validate(forged),"a delivery with an open place never happened")
	forged = board(-1,0,-1,-1,"complete")
	check(not Rules.validate(forged),"a complete with loose tags is refused")
	forged = Rules.fresh(); forged.assign[0] = 1
	check(not Rules.validate(forged),"the walk-in cannot already carry a placed tag")
	forged = board(1,0,2,3); forged.hand = 2
	check(not Rules.validate(forged),"a tag cannot be in hand and pinned at the same time")
	forged = board(1,0,-1,-1); forged.hand = 3
	check(Rules.validate(forged),"a loose tag may be held while the board is open")
	forged = board(1,0,-1,-1,"ready"); forged.hand = 3
	check(not Rules.validate(forged),"the hand only exists at the open board")
	forged = board(1,0,2,3); forged.hand = -2
	check(not Rules.validate(forged),"the hand has a floor")
	forged = board(1,0,2,3); forged.hint = 4
	check(not Rules.validate(forged),"hint level is capped")
	forged = board(1,0,2,3); forged.hint = -1
	check(not Rules.validate(forged),"hints cannot go negative")
	forged = board(1,0,2,3); forged.beat = 3
	check(not Rules.validate(forged),"the arrival lines are bounded")
	forged = board(1,0,2,3); forged.erase("assign")
	check(not Rules.validate(forged),"a missing field is corruption, not a default")
	check(Rules.validate(board(1,0,2,3,"complete")),"the shipped matching reads back as a finished level")
	# ---- 章节目录与关卡身份 ----
	var entry = Catalog.LEVELS["MK05"]
	check(entry.scene == "res://game/market_mk05.tscn" and ResourceLoader.exists(entry.scene),"the chart's MK05 door leads to a real scene")
	check(Catalog.built("MK05"),"MK05 is no longer marked as unmade on the chart")
	check(entry.save == "user://profiles/market-mk05-1/save-v1.json" and Catalog.save_path("MK05") == entry.save,"MK05 keeps its own profile")
	check(entry.kit == "street" and entry.act == 3 and entry.after == "MK04","the chart's act, kit and gate still describe MK05")
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == entry.save and probe.scene_id == entry.kit and probe.level_id == "MK05","the level ships what the chart announces")
	check(probe.title.length() <= 6,"the sign keeps the title short enough for its board")
	check(probe.durations.has("approach") and probe.durations.has("delivery"),"both animations carry their own length")
	var keep = Scene.instantiate(); keep.save_path = "/tmp/pixel-mk05-injected.json"; keep.configure()
	check(keep.save_path == "/tmp/pixel-mk05-injected.json","configure() never overwrites an injected save path")
	keep.queue_free(); probe.queue_free()
	check(Rules.HINTS == 3 and Rules.ANIMATIONS == ["approach","delivery"],"two short animations and three reminders are the whole scaffolding")
	# ---- 真实场景 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"),"the street opens on the arrival lines")
	check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),"nothing can be handed over before the walk-in")
	game.advance(); game.advance(); game.advance()
	check(game.state.stage == "approach","the third line starts the camera walk")
	check(game.buttons.has("pause") and game.buttons.has("skip"),"the walk-in can be paused or skipped")
	game.skip_animation(); game.advance()
	check(game.state.stage == "puzzle" and game.buttons.deliver.text == "验货交货","the order board opens with its own submit button")
	check(game.buttons.undo.disabled and not game.buttons.reset.disabled,"an untouched board has nothing to undo")
	var small = 0
	var offstage = 0
	for index in range(4):
		for rect in [game.world.label_rect(index), game.world.card_rect(index)]:
			if rect.size.x < 48 or rect.size.y < 48: small += 1
			var zoomed = Rect2(rect.position * Vector2(1.1,1.1) + Vector2(-64,-43), rect.size * Vector2(1.1,1.1))
			if zoomed.position.x < 0 or zoomed.position.y < 166 or zoomed.end.x > 1280 or zoomed.end.y > 646: offstage += 1
	check(small == 0,"all eight hit targets clear the 48 pixel floor")
	check(offstage == 0,"every hit target stays on stage under the puzzle zoom")
	game.choose_good(0)
	check(game.state.hand == 0 and game.history.is_empty(),"picking up a tag is not an undo step")
	check(not game.buttons.good_0.disabled,"the tag in hand can still be put back from the counter")
	game.choose_place(1)
	await create_timer(0.4).timeout
	check(game.state.assign == [-1,0,-1,-1] and game.state.hand == -1 and game.history.size() == 1,"布 lands on 育苗铺 and costs one undo step")
	check(game.buttons.good_0.disabled and not game.buttons.good_1.disabled,"a pinned tag leaves its place on the counter")
	game.choose_place(1)
	await create_timer(0.4).timeout
	check(game.state.assign == [-1,-1,-1,-1] and game.history.size() == 2,"an empty-handed press takes the tag back")
	game.undo()
	await create_timer(0.4).timeout
	check(game.state.assign == [-1,0,-1,-1] and game.history.size() == 1,"undo puts 布 back on 育苗铺")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.choose_good(3)
	check(game.modal and game.state.hand == -1 and FileAccess.get_file_as_bytes(path) == bytes,"a failed pick-up save keeps the counter as it was")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.hand == 3 and game.history.size() == 1,"retrying the pick-up still costs no undo step")
	game.choose_place(1)
	await create_timer(0.4).timeout
	check(game.state.assign == [-1,3,-1,-1] and Rules.loose(game.state) == [0,1,2],"pressing a filled place sends 布 back to the counter")
	game.advance()
	check(game.state.stage == "puzzle" and game.message.find("布去育苗铺") >= 0,"the submit names the clue that is broken")
	game.choose_place(1)
	await create_timer(0.4).timeout
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == 3 and game.hint_texts().size() == Rules.HINTS,"the third reminder is the last one")
	check(game.message.find("不收 铜铃") >= 0,"the last reminder demonstrates the elimination step")
	# 直接改写板面时保留读过的提示数：提示只由玩家自己点掉，换板子不清零。
	var shown = game.state.duplicate(true); shown.assign = [2,0,1,3]; shown.hand = -1
	game.commit(shown); await create_timer(0.4).timeout
	game.advance()
	check(game.state.stage == "puzzle" and game.message == "留下的话：面包铺不收铃。铜铃按在了面包铺。","the ignored clue stops the hand-over by name")
	var twin = game.state.duplicate(true); twin.assign = [1,3,2,0]
	game.commit(twin); await create_timer(0.4).timeout
	game.advance()
	check(game.state.stage == "puzzle" and "还有 1 处" in game.message,"a board breaking two clues says how many are left")
	game.do_reset()
	check(game.state.assign == [-1,-1,-1,-1] and game.state.hint == 3,"clearing the board keeps the reminders already read")
	game.commit(board(1,0,2,3)); await create_timer(0.4).timeout
	check(Rules.solved(game.state),"the four pairings the design promises")
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle","a failed hand-over save cannot start the delivery")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "delivery" and game.buttons.has("skip"),"retry releases the delivery as an animation")
	game.paused = true; game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true
	await process_frame
	check(game.state.stage == "delivery" and game.state.assign == [1,0,2,3],"reload preserves an unfinished delivery")
	game.skip_animation()
	check(game.state.stage == "complete" and game.buttons.has("next"),"the delivery ends on the receipt")
	check(game.buttons.next.text == "重新体验" and game.buttons.has("open_hub"),"a standalone launch is offered the way back to the chart")
	check(not game.buttons.has("back_hub"),"the chart's own return button only appears for the chart")
	game.queue_free(); await process_frame
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),"arriving from the chart goes back to the chart")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "complete" and game.snapshot(board(1,0,2,3)) == {"assign":[1,0,2,3],"hand":-1},"the finished receipt reads back and snapshots itself")
	check(entry.save.split("/")[-2] == "market-mk05-1","the level writes inside its own profile folder")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken","a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK05 RULES ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

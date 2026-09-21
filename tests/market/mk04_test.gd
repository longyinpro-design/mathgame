extends SceneTree
const Rules = preload("res://scripts/market/mk04_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const GameScript = preload("res://scripts/market/mk04_scene.gd")
const Scene = preload("res://game/market_mk04.tscn")
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk04-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 中文标签不靠自动折行：每一行都得当场量得下，行数也不能撑破板子的高度。
func fit(text: String, px: int, box: float, allowed: int, tag: String) -> void:
	var lines = text.split("\n")
	check(lines.size() <= allowed, tag + " 的行数撑得住这块板子")
	for piece in lines:
		var run = UIStyle.face().get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		check(run <= box, "%s 的每一行量得下 %d 像素（%d）：%s" % [tag, int(box), int(run), piece])

func label_in(node: Node, needle: String) -> Label:
	for child in node.get_children():
		if child is Label and needle in child.text: return child
		var found = label_in(child, needle)
		if found != null: return found
	return null

func has_label(node: Node, needle: String) -> bool:
	for child in node.get_children():
		if child is Label and needle in child.text: return true
		if has_label(child, needle): return true
	return false

func build(a: int, b: int, correction: int, stage: String = "puzzle") -> Dictionary:
	var state = Rules.fresh()
	state.stage = stage
	state.a = a; state.b = b; state.correction = correction
	return state

# 一份份亲手写坏的存档：每一条都必须被 validate() 拒掉。
func corrupt_cases() -> Array:
	var cases: Array = []
	var done = build(3, 2, 2, "complete")
	var bad = done.duplicate(true); bad.sample = "market-mk02-1"; cases.append([bad, "another sample's record"])
	bad = done.duplicate(true); bad.erase("sample"); cases.append([bad, "a record without a sample tag"])
	bad = done.duplicate(true); bad.stage = "shipping"; cases.append([bad, "unknown stage"])
	bad = done.duplicate(true); bad.a = 4; cases.append([bad, "more cloth than the counter held"])
	bad = done.duplicate(true); bad.a = -1; cases.append([bad, "negative cloth"])
	bad = done.duplicate(true); bad.a = 2.0; cases.append([bad, "a float group count"])
	bad = done.duplicate(true); bad.b = 3; cases.append([bad, "three bell groups from six bottles"])
	bad = done.duplicate(true); bad.a = 1; bad.b = 1; cases.append([bad, "more oil spent than ever exchanged"])
	bad = done.duplicate(true); bad.hint = 4; cases.append([bad, "hint level past the hints shipped"])
	bad = done.duplicate(true); bad.hint = -1; cases.append([bad, "a negative hint counter"])
	bad = done.duplicate(true); bad.beat = 1; cases.append([bad, "a beat left over outside the spoken stages"])
	bad = build(0, 0, 0, "arrival"); bad.beat = 3; cases.append([bad, "arrival plays only three lines"])
	bad = build(3, 2, 2, "clarify"); bad.beat = 4; cases.append([bad, "the clarification has four lines"])
	bad = done.duplicate(true); bad.correction = 5; cases.append([bad, "a correction outside the candidates"])
	bad = done.duplicate(true); bad.correction = 1; cases.append([bad, "one bell is not a candidate"])
	bad = done.duplicate(true); bad.correction = "3"; cases.append([bad, "a written number instead of a count"])
	bad = done.duplicate(true); bad.proposed = 2; cases.append([bad, "a staged correction after the delivery"])
	bad = build(3, 2, 0, "puzzle"); bad.proposed = 2; cases.append([bad, "puzzle must not carry a staged correction"])
	bad = build(3, 2, 0, "puzzle"); bad.exchange = [0, 1]; cases.append([bad, "puzzle must not carry a pending exchange"])
	bad = build(3, 2, 0, "puzzle"); bad.exchange = []; bad.stage = "exchanging"; cases.append([bad, "an empty pending exchange is corruption"])
	bad = build(3, 2, 0, "puzzle"); bad.exchange = [0, 4]; bad.stage = "exchanging"; cases.append([bad, "a batch bigger than the cloth on the counter"])
	bad = build(0, 0, 0, "puzzle"); bad.exchange = [1, 1]; bad.stage = "exchanging"; cases.append([bad, "a pending exchange must be affordable where it is staged"])
	bad = build(3, 2, 0, "puzzle"); bad.exchange = [2, 1]; bad.stage = "exchanging"; cases.append([bad, "the transcribed card is not an executable rule"])
	bad = build(3, 2, 0, "puzzle"); bad.exchange = [3, 1]; bad.stage = "exchanging"; cases.append([bad, "the corrected quantity cannot be exchanged either"])
	bad = build(3, 2, 0, "puzzle"); bad.exchange = [0, 1, 2]; bad.stage = "exchanging"; cases.append([bad, "a pending exchange of the wrong length"])
	bad = build(3, 2, 0, "puzzle"); bad.stage = "correcting"; cases.append([bad, "a correction animation with nothing to write"])
	bad = build(3, 2, 0, "puzzle"); bad.proposed = 5; bad.stage = "correcting"; cases.append([bad, "a staged correction outside the candidates"])
	bad = build(2, 0, 0, "puzzle"); bad.proposed = 2; bad.stage = "correcting"; cases.append([bad, "a correction staged before the run finished"])
	bad = build(3, 2, 0, "delivery"); cases.append([bad, "a delivery whose receipt was never corrected"])
	bad = build(3, 2, 3, "delivery"); cases.append([bad, "a delivery that hands over an impossible count"])
	bad = build(3, 2, 4, "complete"); cases.append([bad, "a complete whose four bells never existed"])
	bad = build(2, 2, 2, "complete"); cases.append([bad, "a complete that skipped part of the run"])
	bad = build(3, 1, 2, "complete"); cases.append([bad, "a complete with oil still on the table"])
	bad = build(3, 2, 2, "complete"); bad.a = 1; cases.append([bad, "a complete claiming fewer bolts than the chain needs"])
	bad = build(1, 0, 0, "arrival"); cases.append([bad, "goods moved before the player reached the counter"])
	bad = build(0, 0, 2, "ready"); cases.append([bad, "a correction chosen during the walk-in"])
	bad = done.duplicate(true); bad.erase("correction"); cases.append([bad, "a missing field is corruption, not a default"])
	bad = done.duplicate(true); bad.erase("exchange"); cases.append([bad, "a missing pending record is corruption"])
	bad = done.duplicate(true); bad.erase("stage"); cases.append([bad, "a record that never says where it is"])
	return cases

func run() -> void:
	create_timer(40).timeout.connect(func(): push_error("MK04 rule watchdog"); quit(1))
	# ---- 开局存档 ----
	check(Rules.validate(Rules.fresh()), "fresh model valid")
	var keys = Rules.fresh().keys(); keys.sort()
	check(keys == ["a", "b", "beat", "correction", "exchange", "hint", "proposed", "sample", "stage"],
		"the save carries exactly the fields the level reads")
	check(Rules.fresh().sample == "market-mk04-1" and Rules.fresh().stage == "arrival", "fresh opens at the arrival beat")
	check(Rules.fresh().exchange == [] and Rules.fresh().proposed == 0 and Rules.fresh().correction == 0,
		"nothing is staged, proposed or corrected at the start")
	check(Rules.ANIMATIONS == ["approach", "exchanging", "correcting", "delivery"], "the four transients are the animations")
	check(not Rules.ANIMATIONS.has("puzzle") and not Rules.ANIMATIONS.has("clarify"), "thinking and listening are not animations")
	check(Rules.STAGES[0] == "arrival" and Rules.STAGES[Rules.STAGES.size() - 1] == "complete", "the stage list runs arrival to complete")
	# ---- 链条数学：3 卷布 → 6 瓶油 → 2 只铃 ----
	check(Rules.OIL == 6 and Rules.BELL_GROUPS == 2 and Rules.CORRECT_BELLS == 2, "the two promises chain to two bells")
	check(Rules.WRITTEN_BELLS == 3 and Rules.CANDIDATES == [2, 3, 4], "the transcribed three bells and the three candidates")
	check(Rules.OIL_PER_BELL * Rules.WRITTEN_BELLS == 9 and 9 % Rules.OIL != 0, "three bells would ask for nine bottles")
	var mismatches = 0
	var swept = 0
	var winners = 0
	var farthest = 0
	for a in range(0, Rules.CLOTH + 1):
		for b in range(0, Rules.BELL_GROUPS + 1):
			for correction in [0, 2, 3, 4]:
				swept += 1
				var state = build(a, b, correction)
				var oil = Rules.OIL_PER_CLOTH * a - Rules.OIL_PER_BELL * b
				var reachable = oil >= 0
				if Rules.validate(state) != reachable: mismatches += 1
				if not reachable: continue
				if Rules.oil_loose(state) != oil: mismatches += 1
				if Rules.bells_loose(state) != b: mismatches += 1
				farthest = maxi(farthest, Rules.bells_loose(state))
				var promised = a == Rules.CLOTH and b == Rules.BELL_GROUPS and correction == Rules.CORRECT_BELLS
				if Rules.solved(state) != promised: mismatches += 1
				if promised: winners += 1
	check(mismatches == 0, "%d hand-built states agree with the goods account" % swept)
	check(winners == 1, "only the run ending in two corrected bells satisfies the receipt")
	check(farthest == Rules.CORRECT_BELLS, "three and four bells are unreachable through the two promises")
	# ---- 整组入账：一次一条约定，做完就记上 ----
	var empty = Rules.fresh(); empty.stage = "puzzle"
	check(Rules.affordable(empty, 0) == Rules.CLOTH and Rules.affordable(empty, 1) == 0,
		"the counter opens with three cloth groups and no oil")
	check(Rules.exchange(empty, 0, 4).is_empty() and Rules.exchange(empty, 0, 0).is_empty(),
		"group counts outside the pile are refused")
	check(Rules.exchange(empty, 1, 1).is_empty(), "no oil-to-bell exchange before there is oil")
	check(Rules.group_limit(0) == Rules.CLOTH and Rules.group_limit(1) == Rules.BELL_GROUPS, "each promise has its own ceiling")
	var trapped = build(3, 0, 0)
	check(Rules.affordable(trapped, 1) == Rules.BELL_GROUPS and Rules.exchange(trapped, 1, 3).is_empty(),
		"six bottles buy two bell groups, never three")
	var finished = build(3, 2, 2)
	check(Rules.exchange(finished, 0, 1).is_empty() and Rules.exchange(finished, 1, 1).is_empty(),
		"a finished chain cannot be run again to farm goods")
	var refused = 0
	for stage in Rules.STAGES:
		for rule in [2, 3, 4, -1, 9]:
			for times in range(0, 4):
				var probed = build(3, 0, 0, stage)
				if not Rules.exchange(probed, rule, times).is_empty(): refused += 1
	check(refused == 0 and Rules.RULE_COUNT == 2, "no stage or index lets the transcribed card exchange goods")
	# ---- 阶段机 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "arrival plays its lines in order")
	arriving = Rules.advance(arriving)
	check(Rules.advance(arriving).stage == "approach" and arriving.beat == Rules.ARRIVAL_BEATS - 1,
		"the third line walks the player to the counter")
	arriving = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(arriving.stage == "puzzle" and arriving.beat == 0 and arriving.a == 0, "approach and ready never touch the goods")
	check(Rules.advance(empty).is_empty(), "an untouched counter cannot be handed over")
	check(Rules.advance(build(0, 0, 2)).is_empty(), "a correction chosen without the run cannot be submitted")
	check(Rules.advance(build(3, 1, 2)).is_empty(), "oil still on the table blocks the submission")
	check(Rules.advance(build(3, 2, 0)).is_empty(), "an uncorrected receipt blocks the submission")
	check(Rules.advance(build(3, 2, 3)).is_empty(), "the transcribed three bells cannot be submitted")
	check(Rules.advance(build(3, 2, 4)).is_empty(), "four bells cannot be submitted either")
	var pending = Rules.exchange(empty, 0, Rules.CLOTH)
	check(pending.stage == "exchanging" and pending.exchange == [0, 3] and pending.a == 0, "a batch is staged, not booked")
	var booked = Rules.advance(pending)
	check(booked.a == Rules.CLOTH and booked.b == 0 and booked.exchange.is_empty() and booked.stage == "puzzle",
		"advance books exactly the staged group count")
	check(Rules.advance(booked).is_empty(), "a booked batch cannot be booked a second time")
	var belled = Rules.advance(Rules.exchange(booked, 1, Rules.BELL_GROUPS))
	check(belled.b == Rules.BELL_GROUPS and Rules.oil_loose(belled) == 0, "two bell groups drink all six bottles")
	var corrected = Rules.advance(Rules.propose(belled, Rules.CORRECT_BELLS))
	check(corrected.correction == Rules.CORRECT_BELLS and corrected.proposed == 0 and corrected.stage == "puzzle",
		"the correction is written back once the animation lands")
	check(Rules.propose(belled, Rules.CORRECT_BELLS).stage == "correcting", "a candidate is staged before it is written")
	check(Rules.propose(belled, 0).is_empty() and Rules.propose(belled, 9).is_empty(), "only the three candidates can be staged")
	check(Rules.propose(build(2, 0, 0), 2).is_empty(), "the candidates stay shut until the cloth is used up")
	check(Rules.propose(build(3, 2, 2), 2).is_empty(), "re-picking the number already written does nothing")
	check(Rules.advance(Rules.propose(build(3, 2, 3), Rules.CORRECT_BELLS)).correction == Rules.CORRECT_BELLS,
		"a wrong pick can be picked again")
	check(Rules.clear_correction(build(3, 2, 3)).correction == 0, "a pick can be taken back off the receipt")
	check(Rules.clear_correction(build(3, 2, 0)).is_empty(), "nothing to clear while the receipt still reads three")
	var staged = Rules.propose(belled, Rules.CORRECT_BELLS)
	check(staged.a == Rules.CLOTH and staged.b == Rules.BELL_GROUPS, "改签不动任何货物")
	check(Rules.advance(staged).stage == "puzzle" and Rules.advance(corrected).stage == "delivery",
		"the corrected receipt releases the clarification")
	var told = Rules.advance(Rules.advance(corrected))
	check(told.stage == "clarify" and told.beat == 0, "the delivery hands over to 扣扣 and 衡伯")
	for beat in range(Rules.CLARIFY_BEATS):
		told = Rules.advance(told)
	check(told.stage == "complete" and told.beat == 0, "the clarification ends on the receipt")
	check(Rules.advance(told).is_empty(), "complete has no stage after it")
	# ---- 缺口说明的是没兑现的那句话 ----
	check(Rules.shortfalls(empty)[0] == "柜面上还剩 3 卷布没换：3 卷布要沿两条原约换到底。", "the opening shortfall names the unspent cloth")
	check(Rules.shortfalls(build(3, 0, 0))[0] == "台面上还有 6 瓶油：3 瓶油还能再换 1 只铜铃，先换完。",
		"the half run says the oil is still owed to the bells")
	check(Rules.shortfalls(build(3, 1, 0))[0] == "台面上还有 3 瓶油：3 瓶油还能再换 1 只铜铃，先换完。",
		"one bell group short still reports the leftover oil")
	check("转抄件上还写着 3 只铃" in Rules.shortfalls(build(3, 2, 0))[0], "a finished run asks for the receipt to be corrected")
	var wrong = Rules.shortfalls(build(3, 2, 3))[0]
	check("改签写的是 3 只" in wrong and "3 卷布 → 6 瓶油 → 2 只铃" in wrong, "a wrong pick points back at the run just made")
	check("改签写的是 4 只" in Rules.shortfalls(build(3, 2, 4))[0], "four bells are refused in the player's own terms")
	check(Rules.shortfalls(build(0, 0, 0)).size() == 1, "one unmet promise is said once, not scored item by item")
	check(Rules.solved(build(3, 2, 2)) and Rules.shortfalls(build(3, 2, 2)).is_empty(), "two corrected bells close the level")
	# ---- 坏档一律拒读 ----
	for junk in [null, {}, [], "x", 5.0, [0, 0]]:
		check(not Rules.validate(junk), "reject record " + str(junk))
	for case in corrupt_cases():
		check(not Rules.validate(case[0]), "reject " + case[1])
	var hinted = build(3, 2, 2, "puzzle"); hinted.hint = Rules.HINTS
	check(Rules.validate(hinted), "the deepest hint tier is still a legal save")
	check(Rules.validate(build(3, 2, 2, "complete")), "the honest finished record reads back")
	# ---- 撤销只回到做过的那一步 ----
	var snapshot = {"a": Rules.CLOTH, "b": Rules.BELL_GROUPS, "correction": Rules.CORRECT_BELLS}
	var trail = Rules.clear_correction(build(3, 2, 3))
	check(Rules.restore(trail, snapshot).correction == Rules.CORRECT_BELLS, "undo restores the corrected number")
	check(Rules.restore(Rules.advance(pending), snapshot).a == Rules.CLOTH, "undo returns the cloth a batch consumed")
	check(Rules.restore(trail, {"a": 0, "b": Rules.BELL_GROUPS, "correction": 2}).is_empty(),
		"undo refuses a state that breaks the goods account")
	check(Rules.restore(trail, {"a": Rules.CLOTH, "b": Rules.BELL_GROUPS}).is_empty(), "a snapshot missing a field cannot be restored")
	check(Rules.restore(build(3, 2, 2, "delivery"), snapshot).is_empty(), "undo only works at the counter")
	check(Rules.restore(build(3, 2, 0, "exchanging"), snapshot).is_empty(), "undo cannot cut into a running animation")
	var rewound = Rules.restore(empty, snapshot)
	check(rewound.correction == Rules.CORRECT_BELLS and Rules.validate(rewound), "restoring a correction keeps the record valid")
	check(Rules.HINTS == 3, "the level ships three hint tiers")
	# ---- 关卡身份与章节目录一致 ----
	check(Catalog.LEVELS.MK04.scene == "res://game/market_mk04.tscn", "the catalogue points at this scene file")
	check(Catalog.LEVELS.MK04.save == "user://profiles/market-mk04-1/save-v1.json", "the catalogue owns this level's save path")
	check(Catalog.LEVELS.MK04.kit == "nursery" and Catalog.LEVELS.MK04.after == "MK03" and Catalog.LEVELS.MK04.act == 2,
		"MK04 is act two in the nursery, after MK03")
	check(Catalog.LEVELS.MK04.title == "不可能兑现的收据", "the catalogue keeps the level's name")
	check(ResourceLoader.exists("res://game/market_mk04.tscn") and Catalog.built("MK04"), "the hub can light this lamp")
	for file in ["scripts/market/mk04_rules.gd", "scripts/market/mk04_world.gd", "scripts/market/mk04_scene.gd",
		"启动千灯集市MK04样板.command", "docs/production/market_mk04_sample.md"]:
		check(FileAccess.file_exists("res://" + file), "shipped file " + file)
	var probe = Scene.instantiate()
	probe.configure()
	check(probe.save_path == Catalog.save_path("MK04") and probe.level_id == "MK04" and probe.scene_id == "nursery",
		"the scene defaults to the market-mk04-1 profile")
	check(probe.rules == Rules and probe.world_script != null, "the scene wires its own rules and world")
	probe.free()
	var injected = Scene.instantiate(); injected.save_path = "/tmp/pixel-mk04-injected.json"; injected.configure()
	check(injected.save_path == "/tmp/pixel-mk04-injected.json", "configure never overwrites an injected test path")
	injected.free()
	# ---- 真实场景：按钮、存档事务与镜头 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "the level opens on the argument")
	check("收据" in game.line() and game.buttons.next.text == "继续听他们说", "the first line is spoken, the player advances it")
	game.commit(build(0, 0, 0))
	check(game.state.stage == "puzzle" and game.history.is_empty(), "a saved counter opens without history")
	var missing = []
	for id in ["single_0", "batch_0", "single_1", "batch_1", "card_0", "card_1", "card_third", "third_try",
		"cand_0", "cand_1", "cand_2", "undo", "reset", "hint", "deliver"]:
		if not game.buttons.has(id): missing.append(id)
	check(missing.is_empty(), "the counter ships every control " + str(missing))
	var small = []
	for id in ["card_0", "card_1", "card_third", "cand_0", "cand_1", "cand_2"]:
		var size = game.buttons[id].size
		if size.x < 48 or size.y < 48: small.append(id)
	check(small.is_empty(), "every receipt hotspot is at least 48 logical pixels")
	check(game.buttons.deliver.text == "核对收据" and not game.buttons.deliver.disabled, "the submit button asks for a check, not a guess")
	check(game.world.card_foot(0).x == game.world.station("counter_left").x
		and game.world.card_foot(1).x == game.world.station("counter_right").x, "the two promises stand on the manifest counters")
	check(game.world.cloth_spots()[0].y > game.world.card_foot(0).y, "goods sit below the pinned receipts")
	check(game.world.cand_rect(0).end.y < game.world.cand_rect(1).position.y, "the three candidates never share a hit target")
	check(game.world.card_rect(2).position.x >= 0 and game.world.card_rect(2).position.y >= 0,
		"the transcribed card sits fully on the counter")
	check(game.world.cand_rect(2).end.x * 1.1 - 64 <= 1280 and game.world.cand_rect(0).end.y * 1.1 - 43 <= 720,
		"the candidate column stays on screen under the counter zoom")
	# ---- 每一块中文文案都当场量过：不靠自动折行，也不撑破板子 ----
	var scratch = Scene.instantiate()
	for stage in Rules.STAGES:
		var beats = Rules.ARRIVAL_BEATS if stage == "arrival" else (Rules.CLARIFY_BEATS if stage == "clarify" else 1)
		for beat in range(beats):
			scratch.state = build(3, 2, 2, stage); scratch.state.beat = beat
			fit(scratch.line(), UIStyle.text_size(20), 798.0, 2, "台词 " + stage)
		for key in scratch.stage_labels().keys():
			fit(scratch.stage_labels()[key], 20, 274.0, 1, "按钮 " + key)
	scratch.state = build(3, 2, 0)
	fit(scratch.status_line(), UIStyle.text_size(20), 300.0, 1, "台面状态")
	scratch.state = build(3, 2, 2)
	fit(scratch.status_line(), UIStyle.text_size(20), 300.0, 1, "台面状态")
	fit(scratch.goal_line(), UIStyle.text_size(22), 762.0, 1, "题面板")
	fit("千灯集市  /  " + scratch.title, UIStyle.text_size(24), 366.0, 1, "标题板")
	fit(scratch.submit_label(), 20, 235.0, 1, "提交按钮")
	fit(GameScript.REFUSAL, UIStyle.text_size(20), 798.0, 2, "转抄件的拒绝理由")
	for note in GameScript.RULE_NOTES:
		fit(note, UIStyle.text_size(20), 798.0, 2, "原约备注")
	for tier in scratch.hint_texts():
		fit(tier, UIStyle.text_size(20), 798.0, 2, "提示")
	for account in [build(0, 0, 0), build(3, 0, 0), build(3, 2, 0), build(3, 2, 3), build(3, 2, 4)]:
		for owed in Rules.shortfalls(account):
			fit(owed, UIStyle.text_size(20), 798.0, 2, "缺口说明")
	# 中途也能回航图，重摆/撤销/提示的按钮宽度都写在自己那一格里
	for plate in ["按转抄件换", "换 1 组", "全换完"]:
		fit(plate, 20, 140.0, 1, "柜台按钮")
	scratch.free()
	game.choose_candidate(0)
	check(game.state.stage == "puzzle" and "先按两条原约" in game.message, "the candidates stay shut before the run")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.do_exchange(0, Rules.CLOTH)
	check(game.modal and game.state.a == 0 and FileAccess.get_file_as_bytes(path) == bytes,
		"a failed exchange save keeps the counter untouched")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "exchanging" and game.state.exchange == [0, 3] and game.state.a == 0,
		"retry stages the exchange without booking it")
	game.paused = true; game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true
	await process_frame
	check(game.state.exchange == [0, 3], "reload resumes the staged exchange")
	game.repository.fail_at = "flush"; game.skip_animation()
	check(game.modal and game.state.a == 0, "a failed booking save never publishes new goods")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.a == Rules.CLOTH and game.state.b == 0, "retry books the whole batch as one move")
	game.paused = false; await create_timer(0.4).timeout
	game.do_exchange(1, 3)
	check(not game.modal and game.state.b == 0 and "凑不成" in game.message, "a batch beyond the oil is refused without a modal")
	game.do_exchange(1, Rules.BELL_GROUPS); game.skip_animation(); await create_timer(0.4).timeout
	check(game.state.b == Rules.BELL_GROUPS and Rules.oil_loose(game.state) == 0, "two bell groups empty the oil")
	game.try_third()
	check(game.state.stage == "puzzle" and "刷货" in game.message, "the transcribed card refuses with the reason that teaches")
	game.read_rule(0)
	check("1 卷布换 2 瓶油" in game.message, "tapping an original promise reads it back")
	game.choose_candidate(2)
	check(game.state.stage == "correcting" and game.state.proposed == 4 and game.state.correction == 0,
		"candidate four is reachable")
	game.skip_animation()
	check(game.state.correction == 4, "four bells can be written onto the receipt")
	game.advance()
	check(game.state.stage == "puzzle" and "改签写的是 4 只" in game.message, "the submission points back at the run")
	game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINTS and "换不出来" in game.message, "the third hint walks the whole chain")
	check(game.hint_texts().size() == Rules.HINTS, "the hint bound matches the hints shipped")
	game.choose_candidate(0); game.skip_animation()
	check(game.state.correction == Rules.CORRECT_BELLS, "picking two again is the fix")
	game.undo()
	check(game.state.correction == 4 and game.history.size() == 2, "undo rewinds the last correction only")
	game.choose_candidate(0); game.skip_animation()
	check(game.state.correction == Rules.CORRECT_BELLS and Rules.solved(game.state), "redoing the pick solves the receipt")
	var cleared = game.cleared_state()
	check(Rules.validate(cleared) and cleared.a == 0 and cleared.correction == 0, "重摆 sends every good back to its owner")
	var counter_line = game.status_line()
	check(counter_line.split("\n").size() == 1 and "布 0" in counter_line and "油 0" in counter_line
		and "铃 2" in counter_line and "订正 2" in counter_line,
		"one authored line still reads back cloth, oil, bells and the receipt")
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle", "a failed hand-over save cannot start the clarification")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "delivery", "the retry releases the clarification once the save recovers")
	game.paused = true; game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "delivery", "reload preserves an unfinished clarification")
	game.paused = false; game.skip_animation()
	check(game.state.stage == "clarify" and game.state.beat == 0, "the delivery hands over to 扣扣 and 衡伯")
	check(game.buttons.next.text == "继续听他们说", "the key scene is advanced by the player")
	for beat in range(Rules.CLARIFY_BEATS):
		game.advance()
	check(game.state.stage == "complete" and game.buttons.has("next"), "the key scene ends on the receipt")
	check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"), "a standalone sample still has a way to the chart")
	check(has_label(game.ui, "转抄件改签：3 卷布换 2 只铜铃"), "the receipt restates the run the player performed")
	check(has_label(game.ui, "抄错不是偷货：原单 2、转抄 3"), "the receipt keeps the two kinds of evidence apart")
	var receipt = label_in(game.ui, "回执 · 育苗铺")
	check(receipt != null and receipt.text.split("\n").size() == 6, "the receipt is six authored lines")
	if receipt != null:
		for paper_line in receipt.text.split("\n"):
			var wide = UIStyle.face().get_string_size(paper_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(18)).x
			check(wide <= 456.0, "receipt line fits the paper at %d px: %s" % [int(wide), paper_line])
	var kept = game.snapshot(game.state)
	check(kept.a == Rules.CLOTH and kept.b == Rules.BELL_GROUPS and kept.correction == Rules.CORRECT_BELLS,
		"the snapshot records the run the player performed")
	game.queue_free(); await process_frame
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.state.stage == "complete" and game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
		"arriving from the chart offers only the way back")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.correction == Rules.CORRECT_BELLS and Rules.validate(game.state), "the finished receipt reads back from disk")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK04 RULES ", checks - failures, "/", checks, " PASS"); quit(1 if failures else 0)

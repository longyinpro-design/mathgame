extends SceneTree
# MK03 封箱里的重量：无头规则、存档与真实场景检查。
# 运行：godot --headless --path . --script tests/market/mk03_test.gd
const Rules = preload("res://scripts/market/mk03_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk03.tscn")
const SAVE_DEFAULT = "user://profiles/market-mk03-1/save-v1.json"
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk03-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 手工拼一份现场；非 arrival 幕必须已经听完三句台词，和 advance 的走位一致。
func pose(stacked: int, red: int, blue: int, stage: String = "puzzle") -> Dictionary:
	var value = Rules.fresh()
	value.stage = stage; value.stacked = stacked; value.red = red; value.blue = blue
	if stage != "arrival": value.beat = 2
	return value

func named(missing: Array, ordinal: String) -> bool:
	for line in missing:
		if ("记录" + ordinal) in line: return true
	return false

func run() -> void:
	create_timer(40).timeout.connect(func(): push_error("MK03 rule watchdog"); quit(1))
	# ---- 开局存档 ----
	check(Rules.validate(Rules.fresh()), "fresh model valid")
	check(Rules.fresh().sample == "market-mk03-1", "fresh carries the mk03 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens at the harbour mouth")
	check(Rules.fresh().stacked == 0 and Rules.fresh().red == 0 and Rules.fresh().blue == 0, "fresh table is unfolded and untagged")
	check(Rules.fresh().hint == 0, "fresh opens without a used hint")
	check(Rules.RECORDS == [[2, 1, 14], [1, 2, 13]], "the two published weighings are 2红+1蓝=14 and 1红+2蓝=13")
	check(Rules.CANCELLED == [1, 1], "the shared group folded away is 1红+1蓝")
	check(Rules.DIFFERENCE == Rules.published(0) - Rules.published(1) and Rules.DIFFERENCE == 1, "the difference card says 1 斤")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "reweigh", "delivery", "complete"], "stage list is the four beats plus the walk-in")
	check(Rules.ANIMATIONS == ["approach", "reweigh", "delivery"], "only the three transitions are animations")
	# ---- 数学：唯一解与单条件近miss ----
	var winners = 0
	var only_first = 0
	var only_second = 0
	var neither = 0
	var mismatches = 0
	for red in range(Rules.TAG_MIN, Rules.TAG_MAX + 1):
		for blue in range(Rules.TAG_MIN, Rules.TAG_MAX + 1):
			var probe = pose(1, red, blue)
			var first_ok = Rules.reading(probe, 0) == Rules.published(0)
			var second_ok = Rules.reading(probe, 1) == Rules.published(1)
			var missing = Rules.shortfalls(probe)
			if first_ok and second_ok:
				winners += 1
				if not missing.is_empty() or not Rules.solved(probe): mismatches += 1
			else:
				if Rules.solved(probe) or missing.is_empty(): mismatches += 1
				if first_ok and (not named(missing, "二") or named(missing, "一")): mismatches += 1
				if second_ok and (not named(missing, "一") or named(missing, "二")): mismatches += 1
				if first_ok and not second_ok: only_first += 1
				elif second_ok and not first_ok: only_second += 1
				else:
					neither += 1
					if not named(missing, "一") or not named(missing, "二"): mismatches += 1
	check(mismatches == 0, "all 49 tag pairs agree with the two published records")
	check(winners == 1, "exactly one hanging satisfies both weighings at once")
	check(Rules.solved(pose(1, 5, 4)) and not Rules.solved(pose(1, 4, 5)), "the answer is 红 5 · 蓝 4, and swapping it fails")
	check(only_first == 2 and only_second == 3 and neither == 43, "the single-condition near misses are counted as authored")
	check(Rules.shortfalls(pose(1, 6, 2)) == ["记录二没兑现：1 红 + 2 蓝 应是 13 斤，挂 6 与 2 只合出 10 斤。"], "R=6 B=2 names only the failing record")
	check(Rules.shortfalls(pose(1, 3, 5)) == ["记录一没兑现：2 红 + 1 蓝 应是 14 斤，挂 3 与 5 只合出 11 斤。"], "R=3 B=5 names the other failing record")
	check(named(Rules.shortfalls(pose(1, 2, 2)), "一") and named(Rules.shortfalls(pose(1, 2, 2)), "二"), "a pair matching neither record is told both")
	check(Rules.reading(pose(1, 5, 4), 0) == 14 and Rules.reading(pose(1, 5, 4), 1) == 13, "the winning hang reads back 14 and 13")
	# ---- 叠合/消去：真实操作、幂等、不发明证据 ----
	var table = pose(0, 0, 0)
	var folded = Rules.fold(table)
	check(folded.stacked == 1 and table.stacked == 0, "folding is a real action on the counter")
	check(Rules.fold(folded).is_empty(), "the fold cannot be booked a second time")
	check(Rules.unfold(folded).stacked == 0, "the two records can be lifted apart again")
	check(Rules.unfold(table).is_empty(), "unfolding an unfolded pair invents nothing")
	check(Rules.fold(pose(0, 0, 0, "arrival")).is_empty(), "nothing can be folded before the player walks in")
	check(Rules.fold(pose(0, 0, 0, "delivery")).is_empty(), "the fold is not available during the delivery")
	check(Rules.reading(folded, 0) == 0 and Rules.reading(folded, 1) == 0, "folding alone hangs no weight")
	check(not Rules.solved(table) and "叠" in Rules.shortfalls(table)[0], "an unfolded table blocks the reweigh and says so")
	check(not Rules.solved(pose(0, 5, 4)) and Rules.shortfalls(pose(0, 5, 4))[0] == Rules.shortfalls(table)[0],
		"the fold is still demanded even when the tags already work")
	check(Rules.shortfalls(pose(0, 5, 4)).size() == 1, "a right answer without the fold reports only the missing evidence")
	# ---- 挂签 ----
	var hung_red = Rules.hang(table, Rules.RED, 5)
	check(hung_red.red == 5 and hung_red.blue == 0, "a red tag hangs on the red crate only")
	check(Rules.hang(hung_red, Rules.RED, 6).red == 6, "a second tag replaces the first instead of adding weight")
	check(Rules.hang(hung_red, Rules.RED, 5).is_empty(), "the same tag cannot be booked twice")
	check(Rules.hang(hung_red, Rules.BLUE, 4).blue == 4, "the blue crate takes its own tag")
	check(Rules.hang(table, Rules.RED, 0).is_empty() and Rules.hang(table, Rules.RED, 8).is_empty(), "tags outside 1-7 are refused")
	check(Rules.hang(table, Rules.RED, -3).is_empty() and Rules.hang(table, Rules.RED, 99).is_empty(), "negative and absurd tags are refused")
	check(Rules.hang(table, 5, 3).is_empty() and Rules.hang(table, -1, 3).is_empty(), "unknown crate kinds are refused")
	check(Rules.hang(pose(1, 0, 0, "arrival"), Rules.RED, 5).is_empty(), "no tag can be hung before the puzzle opens")
	check(Rules.hang(pose(1, 0, 0, "complete"), Rules.RED, 5).is_empty(), "no tag can be hung after the receipt")
	check(Rules.unhang(hung_red, Rules.RED).red == 0, "a hung tag returns to the rack")
	check(Rules.unhang(table, Rules.RED).is_empty(), "an empty hook cannot give anything back")
	check(not Rules.solved(pose(1, 5, 0)) and not named(Rules.shortfalls(pose(1, 5, 0)), "二"), "an empty hook is not scored as zero weight")
	check(Rules.shortfalls(table).size() == 3, "an untouched table lists the fold and both empty hooks")
	# ---- 幕的推进 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "the first line hands over to the second")
	arriving = Rules.advance(arriving)
	arriving = Rules.advance(arriving)
	check(arriving.beat == 2 and arriving.stage == "approach", "the third line walks the player to the counter")
	check(Rules.advance(arriving).stage == "ready" and Rules.advance(Rules.advance(arriving)).stage == "puzzle", "approach then ready then the table")
	var opened = Rules.advance(Rules.advance(arriving))
	check(opened.stage == "puzzle", "the walk-in ends on the counter")
	check(opened.red == 0 and opened.stacked == 0, "the walk-in never touches the goods")
	check(Rules.advance(opened).is_empty(), "an unsolved counter cannot be reweighed")
	check(Rules.advance(pose(1, 5, 4)).stage == "reweigh", "a satisfied pair of records releases the reweigh")
	check(Rules.advance(Rules.advance(pose(1, 5, 4))).stage == "delivery", "the reweigh leads to the delivery")
	check(Rules.advance(Rules.advance(Rules.advance(pose(1, 5, 4)))).stage == "complete", "the delivery ends the scene")
	check(Rules.advance(pose(1, 5, 4, "complete")).is_empty(), "complete has no next stage to invent")
	check(Rules.advance(pose(1, 5, 4, "elsewhere")).is_empty(), "an unknown stage advances nowhere")
	# ---- 撤销快照 ----
	var solved_pose = pose(1, 5, 4)
	check(Rules.restore(Rules.fold(pose(0, 5, 4)), {"stacked": 0, "red": 5, "blue": 4}).stacked == 0, "undo lifts the folded records apart")
	check(Rules.restore(Rules.hang(solved_pose, Rules.BLUE, 3), {"stacked": 1, "red": 5, "blue": 4}).blue == 4, "undo returns a swapped tag to the rack")
	check(Rules.restore(Rules.unhang(solved_pose, Rules.RED), {"stacked": 1, "red": 5, "blue": 4}).red == 5, "undo re-hangs a taken tag")
	check(Rules.restore(pose(0, 0, 0, "arrival"), {"stacked": 1, "red": 5, "blue": 4}).is_empty(), "undo only works at the counter")
	check(Rules.restore(pose(0, 0, 0, "reweigh"), {"stacked": 1, "red": 5, "blue": 4}).is_empty(), "undo cannot reach into the reweigh")
	check(Rules.restore(solved_pose, {"stacked": 1, "red": 5}).is_empty(), "a snapshot missing a field is refused")
	check(Rules.restore(solved_pose, {"stacked": 1, "red": 9, "blue": 4}).is_empty(), "undo refuses a tag out of the rack")
	check(Rules.restore(solved_pose, {"stacked": 3, "red": 5, "blue": 4}).is_empty(), "undo refuses a second fold")
	var kept = Rules.restore(solved_pose, {"stacked": 0, "red": 2, "blue": 2})
	check(kept.stage == "puzzle" and kept.hint == 0 and kept.sample == "market-mk03-1", "undo only rewinds the counter, never the scene")
	# ---- 存档 schema ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record " + str(bad))
	var forged = pose(1, 5, 4); forged.sample = "market-mk02-1"
	check(not Rules.validate(forged), "another level's save is rejected")
	forged = pose(1, 5, 4); forged.stage = "checking"
	check(not Rules.validate(forged), "unknown stage rejected")
	forged = pose(1, 5, 4); forged.hint = 4
	check(not Rules.validate(forged), "hint level is capped by the shipped hints")
	forged = pose(1, 5, 4); forged.hint = -1
	check(not Rules.validate(forged), "a negative hint count is corruption")
	forged = pose(1, 5, 4); forged.red = 8
	check(not Rules.validate(forged), "a tag above the rack is rejected")
	forged = pose(1, 5, 4); forged.blue = -2
	check(not Rules.validate(forged), "a negative tag is rejected")
	forged = pose(1, 5, 4); forged.red = 5.5
	check(not Rules.validate(forged), "a fractional tag is rejected")
	forged = pose(1, 5, 4); forged.red = 5.0
	check(not Rules.validate(forged) and Rules.validate(Content.normalize_numbers(forged)), "a whole number stored as a float is normalized back")
	forged = pose(1, 5, 4); forged.blue = "4"
	check(not Rules.validate(forged), "a written tag is not a hung tag")
	forged = pose(1, 5, 4); forged.stacked = 2
	check(not Rules.validate(forged), "a folded stack is still one stack")
	forged = pose(1, 5, 4); forged.erase("red")
	check(not Rules.validate(forged), "a missing field is corruption, not a default")
	forged = pose(1, 5, 4, "arrival"); forged.beat = 1
	check(not Rules.validate(forged), "a stage past the walk-in cannot claim an unfinished dialogue")
	forged = pose(1, 5, 4, "delivery"); forged.beat = 1
	check(not Rules.validate(forged), "the delivery cannot skip the dialogue either")
	forged = Rules.fresh(); forged.red = 5
	check(not Rules.validate(forged), "nothing is hung before the player reaches the counter")
	forged = pose(1, 5, 4, "ready"); forged.stacked = 1
	check(not Rules.validate(forged), "the records cannot be folded before the table opens")
	forged = pose(1, 6, 2, "reweigh")
	check(not Rules.validate(forged), "a reweigh of a failing pair is rejected")
	forged = pose(0, 5, 4, "delivery")
	check(not Rules.validate(forged), "a delivery whose records were never folded is corruption")
	forged = pose(1, 0, 0, "complete")
	check(not Rules.validate(forged), "an untagged complete is rejected")
	check(Rules.validate(pose(1, 5, 4, "complete")), "the shipped solution reloads at the last stage")
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(pose(1, 5, 4, "delivery"))))
	check(round_trip == pose(1, 5, 4, "delivery") and Rules.validate(round_trip), "the solved record survives a JSON round trip")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh())))), "the opening record survives a JSON round trip")
	# ---- 柜面不判分 ----
	var faces = {}
	for red in range(0, Rules.TAG_MAX + 1):
		for blue in range(0, Rules.TAG_MAX + 1):
			var probe = pose(1, red, blue)
			faces[Rules.record_caption(0) + "|" + Rules.record_caption(1) + "|" + Rules.difference_caption()] = true
	check(faces.size() == 1, "the counter text never changes with what the player hung")
	check(Rules.record_caption(0) == "记录一 · 2红+1蓝 = 14 斤", "record one is published verbatim")
	check(Rules.record_caption(1) == "记录二 · 1红+2蓝 = 13 斤", "record two is published verbatim")
	check(not "成立" in Rules.record_caption(0) and not "对" in Rules.record_caption(1), "no record card marks itself as met")
	check(Rules.difference_caption() == "消去 1红1蓝 · 红比蓝重 1 斤", "the folded card states the difference, not the answer")
	check(not "5" in Rules.difference_caption() and not "4" in Rules.difference_caption(), "the folded card never hands out the tags")
	# ---- 提示与文案（离树探针，用完即释） ----
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == SAVE_DEFAULT, "the level defaults to the market-mk03-1 profile")
	probe.free()
	probe = Scene.instantiate(); probe.save_path = path; probe.configure()
	check(probe.save_path == path, "configure never overwrites an injected test path")
	check(probe.scene_id == "nursery" and probe.level_id == "MK03", "the level declares its kit scene and id")
	check(probe.title == Catalog.title("MK03"), "the sign title matches the chapter catalogue")
	check(probe.rules == Rules and probe.world_script != null, "the host is wired to the mk03 rules and world")
	check(probe.durations.has("reweigh") and probe.zoom_stages.has("reweigh"), "the reweigh keeps the camera at the counter")
	check(probe.hint_texts().size() == Rules.HINTS, "three hints ship and no more")
	check(probe.submit_label() == "挂签复秤", "the submit button asks for the reweigh")
	for spoken in probe.hint_texts(): check(not spoken.is_empty() and spoken.count("\n") <= 1, "hint %s stays inside the sign board" % spoken.left(4))
	check("\n" not in probe.goal_line(), "the goal line fits one unbroken line")
	probe.state = pose(0, 0, 0)
	check("\n" not in probe.status_line(), "the status line fits one unbroken line")
	check("未挂" in probe.status_line() and "未叠" in probe.status_line(), "the status counts the table in the player's words")
	probe.state = pose(1, 5, 4)
	check("5" in probe.status_line() and "已叠" in probe.status_line(), "the status follows the hung tags")
	for beat in range(3):
		var opening = pose(0, 0, 0, "arrival"); opening.beat = beat
		probe.state = opening
		var text = probe.line()
		check(not text.is_empty() and text.count("\n") <= 1, "arrival line %d stays inside the two-line board" % (beat + 1))
	for stage in Rules.STAGES:
		probe.state = pose(1, 5, 4, stage)
		check(not probe.line().is_empty(), "stage %s always has a spoken line" % stage)
	for stage in ["arrival", "ready", "complete"]:
		probe.state = pose(1, 5, 4, stage)
		if stage == "arrival": probe.state.beat = 0
		check(not probe.stage_labels().has(stage) or not probe.stage_labels()[stage].is_empty(), "stage %s names its own next step" % stage)
	probe.free()
	# ---- 真实场景：按钮、命中区、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "a fresh scene opens on the dialogue")
	check(game.buttons.has("next") and not game.buttons.has("deliver"), "the reweigh button waits for the counter")
	check(game.world.scene_id == "nursery" and game.world.stations.has("counter_left"), "the counter is drawn from the nursery stations")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	game.commit(pose(0, 0, 0))
	check(game.state.stage == "puzzle" and game.history.is_empty(), "a saved table opens without history")
	var hotspots = ["fold", "crate_0", "crate_1"]
	for kind in range(2):
		for tag in range(Rules.TAG_MIN, Rules.TAG_MAX + 1): hotspots.append("tag_%d_%d" % [kind, tag])
	var present = true
	var sized = true
	var framed = true
	for id in hotspots:
		if not game.buttons.has(id): present = false; continue
		var button: Button = game.buttons[id]
		if button.size.x < 48 or button.size.y < 48: sized = false
		var rect = button.get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
	check(present, "all 17 counter hotspots are registered")
	check(sized, "every hotspot is at least 48 logical pixels wide and tall")
	check(framed, "every hotspot stays inside the frame and clear of the bottom bar")
	check(game.buttons.has("deliver") and not game.buttons.deliver.disabled, "the reweigh button is live on an empty table")
	check(game.buttons.has("undo") and game.buttons.undo.disabled, "nothing to undo on a fresh table")
	check(game.buttons.has("reset") and game.buttons.has("hint"), "the table offers 重摆 and 请扣扣提醒")
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	for stage in Rules.STAGES:
		var looks = [pose(0, 0, 0, stage)]
		if stage == "puzzle": looks.append(pose(1, 5, 0, stage))
		if stage in ["puzzle", "reweigh", "delivery", "complete"]: looks.append(pose(1, 5, 4, stage))
		for look in looks:
			game.apply_committed(look, [])
			for at in [0.0, 0.5, 1.0]:
				game.paused = true; game.world.progress = at; await process_frame
	check(is_instance_valid(game.world) and not game.modal, "every stage repaints without breaking the counter")
	game.paused = false
	game.apply_committed(pose(0, 0, 0, "puzzle"), [])
	game.do_fold()
	check(game.state.stacked == 1 and game.history.size() == 1, "folding the records is saved and recorded")
	game.choose_tag(Rules.RED, 6)
	check(game.state.red == 6 and game.modal == false, "hanging a red tag lands in the save")
	game.choose_tag(Rules.RED, 6)
	check(game.state.red == 0, "the same tag clicked again returns to the rack")
	game.choose_tag(Rules.RED, 6); game.choose_tag(Rules.BLUE, 2)
	check(game.state.red == 6 and game.state.blue == 2, "both hooks can hold one tag each")
	game.advance()
	check(game.state.stage == "puzzle" and not game.modal and "记录二" in game.message, "a one-record pair is refused with the failing promise")
	check("记录一" not in game.message and "13" in game.message, "the refusal never blames the record that already holds")
	game.choose_tag(Rules.RED, 5); game.choose_tag(Rules.BLUE, 4)
	check(game.state.red == 5 and game.state.blue == 4 and Rules.solved(game.state), "hanging 5 and 4 makes both records come true at once")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.choose_tag(Rules.BLUE, 3)
	check(game.modal and game.state.blue == 4 and FileAccess.get_file_as_bytes(path) == bytes, "a failed tag save keeps the counter as it was")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.blue == 3 and not game.modal, "retry publishes the tag as one move")
	game.choose_tag(Rules.BLUE, 4)
	game.undo(); check(game.state.blue == 3, "undo rewinds the last tag")
	game.undo(); check(game.state.red == 5 and game.state.blue == 4, "a retried save rewinds as exactly one move")
	game.take_tag(Rules.RED)
	check(game.state.red == 0, "the crate's own hook gives its tag back")
	for step in range(12):
		if game.history.is_empty(): break
		game.undo()
	check(game.state.stacked == 0 and game.state.red == 0 and game.state.blue == 0, "undo walks the whole table back to the published pair")
	check(game.history.is_empty(), "the rewind consumes every recorded step")
	game.do_fold(); game.choose_tag(Rules.RED, 5); game.choose_tag(Rules.BLUE, 4)
	game.do_reset()
	check(game.state.red == 0 and game.state.blue == 0 and game.state.stacked == 1, "重摆 returns the tags but keeps the folded evidence")
	game.choose_tag(Rules.RED, 5); game.choose_tag(Rules.BLUE, 4)
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == 3 and "蓝 4" in game.message, "the third hint gives the whole split and stops there")
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle", "a failed reweigh save cannot start the animation")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "reweigh" and game.buttons.has("pause") and game.buttons.has("skip"), "the reweigh animates with pause and skip")
	check(not game.buttons.has("fold"), "the counter hotspots are gone during the reweigh")
	game.skip_animation()
	check(game.state.stage == "delivery", "the reweigh hands over to the delivery")
	game.skip_animation()
	check(game.state.stage == "complete" and Rules.validate(game.state), "the delivery ends on the receipt")
	check(game.buttons.has("next") and game.buttons.next.text == "再查一次", "the last board offers to replay the scene")
	check(game.ui.get_child_count() > 2, "the receipt panel is drawn at the end")
	game.paused = true; game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "complete" and game.state.red == 5 and game.state.blue == 4, "the finished scene reloads with the player's own tags")
	game.queue_free(); await process_frame
	var mid = pose(1, 5, 4, "reweigh")
	var writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(mid)); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "reweigh" and not game.modal, "an unfinished reweigh resumes instead of vanishing")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the resumed reweigh can be paused or skipped again")
	check(Rules.validate(game.state), "the resumed stage is still a legal save")
	check(not game.buttons.has("open_hub") and not game.buttons.has("back_hub"), "a running reweigh keeps the way out for later")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose(1, 5, 4, "complete"))); writer.close()
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("back_hub"), "arriving from the chart offers the way back")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin != "hub" and game.buttons.has("open_hub"), "a standalone sample still finds a way back to the chart")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken", "a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	# ---- 目录一致性 ----
	check(Catalog.scene("MK03") == "res://game/market_mk03.tscn", "the catalogue points at the shipped scene")
	check(Catalog.save_path("MK03") == SAVE_DEFAULT, "the catalogue save path is the one this level writes")
	check(Catalog.LEVELS["MK03"].kit == "nursery", "the catalogue keeps mk03 on the nursery kit scene")
	check(Catalog.opens_after("MK03") == "MK02" and Catalog.act("MK03") == 2, "mk03 is the second act's second table")
	check(ResourceLoader.exists(Catalog.scene("MK03")), "the chart can now light mk03 instead of 尚未制作")
	check(Catalog.built("MK03") and Catalog.available("MK03", ["MK02"]), "mk03 opens once mk02 is lit")
	DirAccess.remove_absolute(path)
	print("MARKET MK03 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

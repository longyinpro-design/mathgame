extends SceneTree
const Scene = preload("res://game/workshop_gw15.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw15_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw15"
var test_path = "/tmp/gw15-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW15 window watchdog fired")
		print("GW15 WINDOW: ",checks," checks, ",failures+1," failures")
		quit(1)
		return true
	return false
func _initialize() -> void:
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	Focus.configure(root)
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func settle() -> void:
	await process_frame
	var deadline = Time.get_ticks_msec()+2000
	while game.transient > 0 and Time.get_ticks_msec() < deadline: await process_frame
	check(game.transient <= 0,"landing completes")
func click(id: String) -> void:
	await click_at(id,Vector2(-1,-1))
# local 为 (-1,-1) 时点控件中心，否则点控件内的这一处。
func click_at(id: String, local: Vector2) -> void:
	if not await Focus.ready(root): check(false,"native window ready"); return
	if not game.buttons.has(id) or game.buttons[id].disabled: check(false,"available button "+id); return
	var b: Control = game.buttons[id]
	var spot = local if local.x >= 0 else b.size/2
	var point = b.get_global_transform_with_canvas()*spot*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var e = InputEventMouseButton.new(); e.position = point; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; root.push_input(e)
	await settle()
func key(code: int) -> void:
	if not await Focus.ready(root): check(false,"native window ready"); return
	for down in [true,false]:
		var e = InputEventKey.new(); e.keycode = code; e.pressed = down; root.push_input(e)
	await settle()
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(capture_dir+"/"+name+".png") == OK,"screenshot "+name)
func mount() -> void:
	game = Scene.instantiate(); game.save_path = test_path; root.add_child(game)
	game.durations = {"approach":0.15,"delivery":0.15}
	check(await Focus.ready(root),"native window uses isolated viewport input")
	await process_frame
func unmount() -> void:
	root.remove_child(game); game.queue_free(); await process_frame
func check_layout() -> void:
	for b in game.buttons.values():
		check(b.size.x >= 44 and b.size.y >= 44,"target size "+b.name)
		check(Rect2(0,0,1280,720).encloses(b.get_global_rect()),"button on screen "+b.name)
	for parent in [game.ui,game.overlay]:
		for child in parent.get_children():
			if child is Label:
				check(child.get_visible_line_count() == child.get_line_count(),"label lines fit "+child.text.left(12))
	# 顶栏两块牌子只有一行的高度：折行会压出板底，单看行数看不出来，这里直接量。
	for child in game.ui.get_children():
		if child is Label and child.text.begins_with("齿轮工坊 · "):
			check(child.get_line_count() == 1,"chapter title fits one line")
		if child is Label and child.text.begins_with("周期 3/4/5 拍之一"):
			check(child.get_line_count() == 1,"goal fits one line")
# 观察记录模态里的正文 Label：用来断言提示阶梯前后的记录内容。
func journal_text() -> String:
	for child in game.overlay.get_children():
		if child is Label and child.text.begins_with("出料观察记录"): return child.text
	return ""
func reset_attempt() -> void:
	await click("reset"); await click("confirm")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size
		if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)
		await mount()
		var prefix = str(size.x)+"-"
		check(game.state.stage == "arrival","opens at arrival")
		await capture(prefix+"01-arrival")
		await click("journal"); check(game.modal,"journal opens without progressing story"); await click("close_journal")
		await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
		check(game.state.stage == "approach","manual approach start")
		await click("skip"); check(game.state.stage == "ready","skip stops at ready")
		await key(KEY_SPACE); check(game.state.stage == "puzzle","player starts puzzle")
		await capture(prefix+"02-puzzle")
		check_layout()
		check(not game.world.comparison_open(),"the comparison table stays hidden before the second hint")
		# 还没锁时刻就想提交：被拒并念出真实原因。
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "先从第 1～12 拍里锁定" in game.message,"submit without a locked time is refused")
		# 反例一：第 8 拍 2、2、1，3 拍和 4 拍都是 2 件；就算碰巧挂对 4 拍牌也不算。
		await click("time_8"); check(game.state.observe == 8 and game.state.tried == [8],"locking eight")
		check(not game.world.comparison_open(),"locking a time alone does not unfold the table")
		await click("open")
		check(game.state.opened and game.state.observe == 8 and game.state.assigned == 0,"opening the window at eight")
		check("第 8 拍累计 2 件" in game.message,"the window reads back the real count")
		await click("period_4"); check(game.state.assigned == 4,"hanging the four-beat plaque")
		await click("deliver")
		check(game.state.stage == "puzzle" and "分不清" in game.message and "3 拍和 4 拍都是 2 件" in game.message,
			"eight is refused with the real confusion")
		check(game.message.length() <= 40,"the refusal stays short enough for one line")
		await capture(prefix+"03-wrong-observation")
		check_layout()
		# 重摆与撤销：时刻、开窗、周期牌与比较表都跟着走。
		await reset_attempt()
		check(game.state.observe == 0 and not game.state.opened and game.state.assigned == 0 and game.state.tried.is_empty(),
			"reset clears the attempt")
		await click("undo")
		check(game.state.observe == 8 and game.state.opened and game.state.assigned == 4 and game.state.tried == [8],
			"undo restores the eight-beat attempt")
		await reset_attempt()
		# 反例二：第 12 拍也能分，但不是最早。
		await click("time_12"); await click("open")
		check(game.state.observe == 12 and game.state.opened,"opening the window at twelve")
		check("第 12 拍累计 3 件" in game.message,"twelve reads back three items")
		await click("period_4"); await click("deliver")
		check(game.state.stage == "puzzle" and "第 9 拍更早" in game.message,"twelve is refused because nine is earlier")
		await reset_attempt()
		# 键盘选时刻：还没锁过时，右一步先落在第 1 拍。
		await key(KEY_RIGHT); check(game.state.observe == 1,"right arrow locks the first time")
		await key(KEY_RIGHT); check(game.state.observe == 2 and game.state.tried == [1,2],"right arrow moves one beat at a time")
		await reset_attempt()
		# 正解：第 9 拍 3、2、1；键盘开窗，先挂错牌再改对。
		await click("time_9"); check(game.state.observe == 9,"locking nine")
		await key(KEY_O); check(game.state.opened and "第 9 拍累计 2 件" in game.message,"O opens the window")
		await click("period_5"); await click("deliver")
		check(game.state.stage == "puzzle" and "对应的是 4 拍" in game.message and "挂的是 5 拍" in game.message,
			"the wrong plaque names the real mapping")
		await key(KEY_4); check(game.state.assigned == 4 and R.solved(game.state),"the four key hangs the right plaque")
		await capture(prefix+"03-solved")
		# 半途续档：时刻、开窗、周期牌与比较表都从独立存档里回来。
		await unmount(); await mount()
		check(game.state.stage == "puzzle" and game.state.observe == 9 and game.state.opened,"a half-solved puzzle survives reload")
		check(game.state.assigned == 4 and game.state.tried == [9],"the plaque and the comparison list survive reload")
		# 提示第 2 档之前：对照表不摊开，观察记录也只列锁过的时刻。
		await click("journal")
		check("第 9 拍\n" in journal_text() and "3 拍 3 件" not in journal_text(),"the journal lists locked times without the counts")
		check("本次观察：第 9 拍 · 累计 2 件" in journal_text(),"the journal keeps the real observation")
		check_layout()
		await click("close_journal")
		# 提示与保存失败重试。
		await click("hint"); check(game.state.hint == 1 and game.message == game.hint_texts()[0],"first hint is optional")
		check(not game.world.comparison_open(),"the first hint still keeps the table hidden")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores hint text")
		check(game.world.comparison_open(),"the second hint unfolds the comparison table")
		await click("journal")
		check("第 9 拍：3 拍 3 件 · 4 拍 2 件 · 5 拍 1 件" in journal_text(),"the second hint also unfolds the counts in the journal")
		await click("close_journal")
		await capture(prefix+"03-compare")
		# 提交失败重试后正好进入一次交付。
		game.repository.fail_at = "replace"; var saved = game.state.duplicate(true)
		await click("deliver"); check(game.modal and game.state == saved,"claim save failure preserves the observation")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "delivery" and game.pending.is_empty(),"retry installs the claim exactly once")
		await capture(prefix+"04-delivery")
		await click("skip"); check(game.state.stage == "aftermath" and game.state.beat == 0,"result stops for dialogue")
		await create_timer(0.1).timeout; check(game.state.beat == 0,"story never auto-advances")
		await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
		check(game.state.stage == "complete","explicit discovery completes level")
		await capture(prefix+"05-complete")
		await click("journal"); check_layout(); await capture(prefix+"06-discovery"); await click("close_journal")
		await unmount(); await mount(); check(game.state.stage == "complete","completion survives reload")
		await click("next"); await click("cancel"); check(game.state.stage == "complete","restart is confirmed")
		await unmount()
	# 坏档保护也走一次真实界面。
	var f = FileAccess.open(test_path,FileAccess.WRITE); f.store_string("broken JSON"); f.close()
	var hash = FileAccess.get_sha256(test_path)
	await mount(); check(game.modal and game.repository.protected,"damaged profile blocks interaction")
	await click("protect_confirm")
	check(not game.modal and game.state == R.fresh(),"explicit recovery starts fresh")
	var backup_found = false
	for name in DirAccess.get_files_at(test_path.get_base_dir()):
		var path = test_path.get_base_dir()+"/"+name
		if ".protected-" in name: backup_found = FileAccess.get_sha256(path) == hash
		DirAccess.remove_absolute(path)
	check(backup_found,"original damaged bytes preserved")
	await unmount(); DirAccess.remove_absolute(test_path.get_base_dir())
	print("GW15 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

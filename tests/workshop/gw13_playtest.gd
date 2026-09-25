extends SceneTree
const Scene = preload("res://game/workshop_gw13.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw13_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw13"
var test_path = "/tmp/gw13-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW13 window watchdog fired")
		print("GW13 WINDOW: ",checks," checks, ",failures+1," failures")
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
		if child is Label and child.text.begins_with("0～24 拍"):
			check(child.get_line_count() == 1,"goal fits one line")
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
		# 还没圈重合就想提交：被拒并念出真实原因。
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "先在时间尺上圈出" in game.message,"submit without circles is refused")
		# 第 4 拍只有甲在叫，圈上它当场被念出真实原因。
		await click("tick_4")
		check(game.state.marks == [4] and game.cursor == 4,"clicking a beat circles it")
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "只有甲在叫" in game.message,"a solo beat is refused with its own reason")
		await click("tick_4")
		check(game.state.marks.is_empty(),"clicking again takes the circle back")
		await click("tick_0"); await click("tick_12"); await click("tick_24")
		check(game.state.marks == [0,12,24],"the three together beats are circled")
		await key(KEY_SPACE)
		check("再提交「总共几个时刻听到叫声」" in game.message,"the total is asked for next")
		# 典型反例一：把 7+5=12 当成总共听到的时刻。
		await click("heard_12"); await click("solo_6")
		check(game.state.heard == 12 and game.state.solo == 6,"the double count is committed")
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "只算一个时刻" in game.message,"seven plus five is refused as a double count")
		await capture(prefix+"03-refused-double-count")
		# 典型反例二：独鸣只从一只鸟的次数里扣。
		await click("heard_9"); await click("solo_4")
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "不算独鸣" in game.message,"one-bird subtraction is refused")
		await click("solo_6")
		check(R.solved(game.state),"nine and six solve the puzzle")
		# 重摆与撤销：圈过的拍和两个数量都跟着快照走。
		await click("reset"); await click("confirm")
		check(game.state.marks.is_empty() and game.state.heard == -1 and game.state.solo == -1,"reset clears the record")
		await click("undo")
		check(game.state.marks == [0,12,24] and game.state.heard == 9 and game.state.solo == 6,"undo restores the circles and counts")
		# 键盘与按钮同一条判据：同一拍先点后按。
		await click("tick_12"); check(not game.state.marks.has(12),"a click takes the circle back")
		await key(KEY_M); check(game.state.marks.has(12) and game.cursor == 12,"M circles the same beat")
		await key(KEY_LEFT); check(game.cursor == 11,"left arrow moves the ruler pointer")
		await key(KEY_RIGHT); check(game.cursor == 12,"right arrow moves it back")
		await key(KEY_DOWN); check(game.count_row == 1,"down arrow picks the solo row")
		await key(KEY_Q); check(game.state.solo == 5,"Q lowers the active count")
		await key(KEY_E); check(game.state.solo == 6,"E raises it back")
		await key(KEY_UP); check(game.count_row == 0,"up arrow picks the total row")
		await key(KEY_E); check(game.state.heard == 10,"E raises the total")
		await key(KEY_Q); check(game.state.heard == 9,"Q lowers it back")
		# 半途续档：圈过的拍和两个数量都从独立存档里回来。
		await unmount(); await mount()
		check(game.state.stage == "puzzle" and game.state.marks == [0,12,24],"a half-solved puzzle survives reload")
		check(game.state.heard == 9 and game.state.solo == 6,"the two counts survive reload")
		# 提示与保存失败重试。
		await click("hint"); check(game.state.hint == 1 and game.message == game.hint_texts()[0],"first hint is optional")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores hint text")
		# 提交失败重试后正好进入一次交付。
		game.repository.fail_at = "replace"; var saved = game.state.duplicate(true)
		await click("deliver"); check(game.modal and game.state == saved,"claim save failure preserves the record")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "delivery","retry installs the claim exactly once")
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
	print("GW13 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

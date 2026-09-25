extends SceneTree
const Scene = preload("res://game/workshop_gw12.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw12_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw12"
var test_path = "/tmp/gw12-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW12 window watchdog fired")
		print("GW12 WINDOW: ",checks," checks, ",failures+1," failures")
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
		if child is Label and child.text.begins_with("两班同一种托"):
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
		# 还没提槽数就想提交：被拒并念出真实原因。
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "先从 3～12 里提出一个槽数" in game.message,"submit without a capacity is refused")
		await key(KEY_RIGHT); check(game.state.capacity == 3,"right arrow proposes the lowest capacity")
		# 典型反例：把最后剩的 2 枚当成第一班余料。3 槽下两次都合法，两班却一共交了 15 托。
		await click("keep1_2")
		check(game.state.first_keep == 2 and "交走 7 个满托" in game.message,"three slots can keep the final two after the first shift")
		await click("keep2_2")
		check(game.state.second_keep == 2 and "15 个满托" in game.message,"three slots ends at two but hands over fifteen trays")
		await click("deliver")
		check(game.state.stage == "puzzle" and "15 个满托" in game.message,"fifteen trays are refused against the book")
		# 9 槽：最后也剩 2 枚，可 2 枚已经装不成第一班的整托。
		await click("cap_9")
		check(game.state.capacity == 9 and game.state.first_keep == -1 and game.state.second_keep == -1,"changing the capacity clears the run")
		await click("keep1_2")
		check(game.state.first_keep == -1 and "装不成 9 枚一托的整托" in game.message,"the final two are refused as a first leftover")
		await click("keep1_5"); await click("keep2_2")
		check(game.state.second_keep == 2 and "5 个满托" in game.message,"nine slots also ends at two with only five trays")
		await click("deliver")
		check(game.state.stage == "puzzle" and "交接册写的是 9 个" in game.message,"nine slots is refused with the real difference")
		await capture(prefix+"03-wrong-run")
		# 重摆与撤销：槽数、两班执行与试过记录都跟着走。
		await click("reset"); await click("confirm")
		check(game.state.capacity == 0 and game.state.first_keep == -1 and game.state.second_keep == -1 and game.state.tried.is_empty(),"reset clears the run")
		await click("undo")
		check(game.state.capacity == 9 and game.state.first_keep == 5 and game.state.second_keep == 2,"undo restores the nine-slot run")
		check(game.state.tried == [3,9],"both finished slots stay in the trial list")
		# 5 槽：键盘一步一步走，非法的留法被拒，走到 3 才交班。
		await click("cap_5"); check(game.state.capacity == 5,"choosing five")
		await key(KEY_RIGHT); check(game.state.first_keep == -1 and "装不成 5 枚一托的整托" in game.message,"a stray leftover is refused")
		await key(KEY_RIGHT); check(game.state.first_keep == -1,"two is still not a whole tray at five slots")
		await key(KEY_RIGHT); check(game.state.first_keep == 3 and "交走 4 个满托" in game.message,"three hands over four trays")
		await capture(prefix+"03-first-shift")
		await key(KEY_RIGHT); check(game.state.second_keep == -1 and "装不成 5 枚一托的整托" in game.message,"the final leftover is judged the same way")
		await key(KEY_RIGHT); check(game.state.second_keep == 2 and R.solved(game.state),"two leaves nine trays and matches the book")
		await capture(prefix+"03-executed")
		# 半途续档：槽数、两班执行与试过记录都从独立存档里回来。
		await unmount(); await mount()
		check(game.state.stage == "puzzle" and game.state.capacity == 5,"a half-solved puzzle survives reload")
		check(game.state.first_keep == 3 and game.state.second_keep == 2,"the two leftovers survive reload")
		check(game.state.tried == [3,5,9],"the trial list survives reload")
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
	print("GW12 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

extends SceneTree
const Scene = preload("res://game/workshop_gw17.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw17_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw17"
var test_path = "/tmp/gw17-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW17 window watchdog fired")
		print("GW17 WINDOW: ",checks," checks, ",failures+1," failures")
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
	game.durations = {"approach":0.5,"delivery":0.6}
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
# 把某一辆车往后挪 n 拍：每挪一拍都是一次真实的排法改动。
func push(id: String, n: int) -> void:
	await click(id)
	for i in range(n): await click("later")
# 把某一辆车往前挪 n 拍。
func pull(id: String, n: int) -> void:
	await click(id)
	for i in range(n): await click("earlier")
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
		await key(KEY_SPACE); check(game.state.stage == "puzzle","player starts planning")
		check(game.state.starts == [0,3,5,6] and game.state.order == ["A","B","C","D"],
			"opens on the draft that sends A first")
		await capture(prefix+"02-puzzle")
		# A 先走卡住 B：草稿里 B 排在第 3 拍，第 5 拍才驶离，超过最晚 4 拍。
		await click("deliver")
		check(game.state.stage == "puzzle" and "B 到第 5 拍才驶离，超过最晚 4 拍。" in game.message,
			"the draft is refused because A first blocks B")
		# 抢轨：把 B 提到第 1 拍，和 A 的 0–3 压在同一拍上。
		await click("row_1"); await click("earlier"); await click("earlier")
		check(game.state.starts == [0,1,5,6],"B is pulled to beat 1")
		await click("deliver")
		check(game.state.stage == "puzzle" and "第 1 拍轨上还压着" in game.message,"the shared rail is refused at beat 1")
		# 上轨许可：把 C 提到第 2 拍，它第 3 拍才准上轨。
		await click("reset"); await click("confirm")
		await pull("row_2",3)
		check(game.state.starts == [0,3,2,6],"C is pulled to beat 2")
		await click("deliver")
		check(game.state.stage == "puzzle" and "C 第 3 拍才准上轨，第 2 拍还发不了。" in game.message,
			"the gate is refused with its real reason")
		# 重摆与撤销：四辆车和放行顺序一起回退。
		await click("reset"); await click("cancel"); check(game.state.starts == [0,3,2,6],"cancel keeps the plan")
		await click("reset"); await click("confirm")
		check(game.state.starts == [0,3,5,6] and game.state.order == ["A","B","C","D"],"reset returns the opening draft")
		await click("undo"); check(game.state.starts == [0,3,2,6],"undo restores the moved car")
		var steps = 0
		while not game.history.is_empty() and steps < 12:
			await click("undo"); steps += 1
		check(game.state.starts == [0,3,5,6] and game.history.is_empty(),"undo steps back through every move")
		# 键盘：←/→ 选车，Q/W 提前推后，到头的发车拍会念出来。
		await click("row_0"); check(game.focus_item == 0,"clicking a row selects its car")
		await key(KEY_RIGHT); check(game.focus_item == 1,"right arrow selects the next car")
		await key(KEY_LEFT); check(game.focus_item == 0,"left arrow selects the previous car")
		await key(KEY_W); check(game.state.starts == [1,3,5,6],"W pushes the selected car later")
		await key(KEY_Q); check(game.state.starts == [0,3,5,6],"Q pulls it back")
		await key(KEY_Q); check(game.message.begins_with("已经到头了"),"A stops at beat 0 and says so")
		# 排成唯一整拍计划：等 0–1，B 1–3、C 3–4、A 4–7、D 7–9。
		await pull("row_1",2); await pull("row_2",2); await push("row_0",4); await push("row_3",1)
		check(game.state.starts == [4,1,3,7] and game.state.order == ["B","C","A","D"],"the one timetable is arranged")
		check(R.solved(game.state),"the timetable passes every release")
		await capture(prefix+"03-solved")
		# 提示与保存失败重试。
		await click("hint"); check(game.state.hint == 1 and game.message == game.hint_texts()[0],"first hint is optional")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores hint text")
		# 提交失败重试后正好进入一次放行。
		game.repository.fail_at = "replace"; var saved = game.state.duplicate(true)
		await click("deliver"); check(game.modal and game.state == saved,"claim save failure preserves the plan")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "delivery","retry installs the release exactly once")
		# 放行演到中段：扫到第 5 拍，A 车在轨上。
		game.elapsed = 0.3
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
	print("GW17 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

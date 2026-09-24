extends SceneTree
const Scene = preload("res://game/workshop_gw02.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw02_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw02"
var test_path = "/tmp/gw02-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW02 window watchdog fired")
		print("GW02 WINDOW: ",checks," checks, ",failures+1," failures")
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
# 返回按下那一瞬间所在的格：提交是同步落定的，而试压只有 0.15 秒，
# 等过一帧就可能已经演完退回排模，所以「刚进哪一格」只能在这里读。
func click(id: String) -> String:
	if not await Focus.ready(root): check(false,"native window ready"); return ""
	if not game.buttons.has(id) or game.buttons[id].disabled: check(false,"available button "+id); return ""
	var b: Control = game.buttons[id]
	var point = b.get_global_transform_with_canvas()*(b.size/2)*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var e = InputEventMouseButton.new(); e.position = point; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; root.push_input(e)
	var stage = game.state.stage
	await settle()
	return stage
func key(code: int) -> void:
	if not await Focus.ready(root): check(false,"native window ready"); return
	for down in [true,false]:
		var e = InputEventKey.new(); e.keycode = code; e.pressed = down; root.push_input(e)
	await settle()
func wait_until(stage: String, limit_ms: int) -> void:
	var deadline = Time.get_ticks_msec()+limit_ms
	while game.state.stage != stage and Time.get_ticks_msec() < deadline: await process_frame
	check(game.state.stage == stage,"reached "+stage+" without pressing skip")
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(capture_dir+"/"+name+".png") == OK,"screenshot "+name)
func mount() -> void:
	game = Scene.instantiate(); game.save_path = test_path; root.add_child(game)
	# 演出时长默认压到 0.15 秒：实窗仍然真的跑完每一格，只是不等四秒。
	game.durations = {"approach":0.15,"pressing":0.15,"delivery":0.15}
	check(await Focus.ready(root),"native window uses isolated viewport input")
	await process_frame
func unmount() -> void:
	root.remove_child(game); game.queue_free(); await process_frame
func check_layout() -> void:
	for b in game.buttons.values():
		# 共用底栏的撤销/重摆是 46 高；按 48 会把宿主自己的按钮算成不合格，这里用 44 的触控下限量。
		check(b.size.x >= 44 and b.size.y >= 44,"target size "+b.name)
		check(Rect2(0,0,1280,720).encloses(b.get_global_rect()),"button on screen "+b.name)
	for parent in [game.ui,game.overlay]:
		for child in parent.get_children():
			if child is Label:
				check(child.get_visible_line_count() == child.get_line_count(),"label lines fit "+child.text.left(12))
func stamp_all(mould_key: int) -> void:
	await key(mould_key)
	for code in [KEY_Q,KEY_W,KEY_E,KEY_R,KEY_T,KEY_Y,KEY_U,KEY_I]: await key(code)
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
		# 没选满时按试压只念缺口，不进演出。
		await click("deliver")
		check(game.state.stage == "puzzle" and game.state.attempts == 1,"incomplete bench stays on the bench")
		check(game.message.begins_with("还有"),"incomplete bench reports how many sheets are left")
		await key(KEY_1); await key(KEY_Q)
		check(game.selected == R.SMALL and game.state.molds[0] == R.SMALL,"keyboard stamps a four-hole mould")
		await key(KEY_2); await key(KEY_W)
		check(game.selected == R.LARGE and game.state.molds[1] == R.LARGE,"keyboard switches to seven-hole")
		await key(KEY_1); await key(KEY_W)
		check(game.state.molds[1] == R.SMALL,"restamping replaces the mould")
		await key(KEY_Z); check(game.state.molds[1] == R.LARGE,"undo restores the previous stamp")
		await click("reset"); await click("cancel"); check(game.state.molds[1] == R.LARGE,"cancel reset")
		await click("reset"); await click("confirm"); check(R.assigned(game.state) == 0,"reset clears the bench")
		await click("undo"); check(game.state.molds[1] == R.LARGE,"undo reset")
		await stamp_all(KEY_1)
		check(R.assigned(game.state) == R.SHEETS,"eight sheets all stamped")
		await click("hint"); check(game.state.hint == 1,"first hint is optional")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores hint text")
		await capture(prefix+"02-puzzle")
		var saved = game.state.duplicate(true)
		await unmount(); await mount()
		check(game.state == saved and game.history.is_empty(),"reload exact bench")
		# 全四孔：试压看得到留样，但安装数不够，退回台面并说明。
		check(await click("deliver") == "pressing","complete bench may be pressed")
		await capture(prefix+"03-pressing")
		await wait_until("puzzle",3000)
		check(game.message.begins_with("四孔模和七孔模"),"single-mould trial returns with reason")
		# 换成正确的一台：6 片四孔 + 2 片七孔。
		await key(KEY_2); await key(KEY_E); await key(KEY_U)
		check(game.state.molds == [4,4,7,4,4,4,7,4],"six fours and two sevens")
		check(R.solved(game.state),"board solves")
		game.durations["pressing"] = 6.0
		game.repository.fail_at = "replace"; saved = game.state.duplicate(true)
		await click("deliver")
		check(game.modal and game.state == saved,"trial save failure preserves the bench")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "pressing" and game.state.attempts >= 2,"retry installs the trial exactly once")
		await unmount(); await mount()
		game.durations["pressing"] = 6.0
		check(game.state.stage == "pressing" and R.solved(game.state),"reload mid-trial")
		await click("skip"); check(game.state.stage == "delivery","verified result accepted")
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
	print("GW02 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

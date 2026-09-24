extends SceneTree
const Scene = preload("res://game/workshop_gw04.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw04_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw04"
var test_path = "/tmp/gw04-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW04 window watchdog fired")
		print("GW04 WINDOW: ",checks," checks, ",failures+1," failures")
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
# 返回按下那一瞬间所在的格：提交是同步落定的，而试演只有 0.15 秒，
# 等过一帧就可能已经演完退回排法，所以「刚进哪一格」只能在这里读。
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
	game.durations = {"approach":0.15,"trial":0.15,"delivery":0.15}
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
		check(game.state.delay == 0 and game.state.picks.is_empty(),"opens with no delay and no handovers")
		await click("delay_1"); check(game.state.delay == 1,"clicking a delay option shifts the lift")
		await key(KEY_1); check(game.state.delay == 0,"number keys shift the lift")
		await click("deliver")
		check(game.state.stage == "puzzle" and game.state.attempts == 1,"an unfinished plan cannot sail")
		check(game.message.begins_with("延后 0 拍"),"an unfinished plan reports the real reason first")
		await click("pick_8"); check(game.state.picks == [8],"clicking the timetable sets a handover")
		await click("pick_16"); check(game.state.picks == [8,16],"two handovers recorded")
		await click("pick_16"); check(game.state.picks == [8],"clicking a chosen tick takes it back")
		await click("pick_16")
		await capture(prefix+"02-puzzle")
		check(await click("deliver") == "trial","two handovers may be sailed")
		await wait_until("puzzle",3000)
		check(game.message.begins_with("延后 0 拍"),"the wrong shift returns with the real reason")
		# 换档会把旧选择清掉；再用键盘重新选成 4 与 16。
		await key(KEY_3); check(game.state.delay == 2 and game.state.picks.is_empty(),"changing the delay clears the picks")
		await key(KEY_R); check(game.state.picks == [1],"R sets the handover under the cursor")
		for i in range(3): await key(KEY_D)
		check(game.cursor == 4,"right arrow moves the cursor")
		await key(KEY_R); check(game.state.picks == [1,4],"second handover set from the keyboard")
		await key(KEY_A); check(game.cursor == 3,"A moves the cursor back")
		await click("pick_1"); check(game.state.picks == [4],"clicking takes the first one back")
		await click("pick_16"); check(game.state.picks == [4,16],"the author plan is set")
		check(R.solved(game.state),"delay two with 4 and 16 solves")
		await click("undo"); check(game.state.picks == [4],"undo drops the second handover")
		await click("pick_16")
		await click("hint"); check(game.state.hint == 1,"first hint is optional")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores hint text")
		var saved = game.state.duplicate(true)
		await unmount(); await mount()
		check(game.state == saved and game.history.is_empty(),"reload exact plan")
		await click("reset"); await click("cancel"); check(game.state.picks == [4,16],"cancel reset")
		await click("reset"); await click("confirm")
		check(game.state.delay == 0 and game.state.picks.is_empty() and game.state.hint == 2,"reset clears the plan and keeps help")
		await click("undo"); check(game.state.picks == [4,16] and game.state.delay == 2,"undo reset")
		game.durations["trial"] = 6.0
		game.repository.fail_at = "replace"; saved = game.state.duplicate(true)
		await click("deliver")
		check(game.modal and game.state == saved,"trial save failure preserves the plan")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "trial" and game.state.attempts >= 2,"retry installs the trial exactly once")
		await unmount(); await mount()
		game.durations["trial"] = 6.0
		check(game.state.stage == "trial" and R.solved(game.state),"reload mid-trial")
		await click("skip"); check(game.state.stage == "delivery","verified shift accepted")
		await capture(prefix+"03-delivery")
		await click("skip"); check(game.state.stage == "aftermath" and game.state.beat == 0,"result stops for dialogue")
		await create_timer(0.1).timeout; check(game.state.beat == 0,"story never auto-advances")
		await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
		check(game.state.stage == "complete","explicit discovery completes level")
		await capture(prefix+"04-complete")
		await click("journal"); check_layout(); await capture(prefix+"05-discovery"); await click("close_journal")
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
	print("GW04 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

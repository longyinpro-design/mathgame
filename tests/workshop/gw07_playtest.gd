extends SceneTree
const Scene = preload("res://game/workshop_gw07.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw07_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw07"
var test_path = "/tmp/gw07-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW07 window watchdog fired")
		print("GW07 WINDOW: ",checks," checks, ",failures+1," failures")
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
# 把选中的那一格往后挪 n 拍：每挪一拍都是一次真实的排法改动。
func push(n: int) -> void:
	for i in range(n): await click("forward")
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
		check(game.state.press == R.DEFAULT_PRESS and game.state.cool == R.DEFAULT_COOL,"opens on the back-to-back draft")
		check(not R.solved(game.state),"the opening draft does not pass")
		await capture(prefix+"02-draft")
		# 顺排草稿的 B 冷却 3–5 正压在检修段上：试演跑到第 4 拍就停。
		check(await click("deliver") == "trial","any arrangement may be run")
		await wait_until("puzzle",3000)
		check(game.message.begins_with("第 4 拍"),"the run stops at the maintenance tick")
		check("检修" in game.message,"the maintenance is named")
		# 把冷却推到检修之后：B 5–7、C 7–9、D 9–11。
		await click("cool_1"); check(game.focus_row == 1 and game.focus_item == 1,"clicking a cell selects it")
		await push(2); check(game.state.cool == [1,5,5,7],"B waits out the maintenance")
		await click("cool_2"); await push(2)
		check(game.state.cool == [1,5,7,7],"C follows B")
		await click("cool_3"); await push(2)
		check(game.state.cool == [1,5,7,9],"cooling now sits clear of the maintenance")
		check(not R.solved(game.state),"pressing is still ahead of the buffer")
		await click("deliver"); await wait_until("puzzle",3000)
		check(game.message.begins_with("第 3 拍"),"the run stops at the buffer clash")
		check("暂存位" in game.message,"the buffer is named")
		# 把 C、D 的压制也往后放，暂存位就一次只停一件。
		await click("press_2"); await push(2)
		check(game.state.press == [0,1,4,3],"C is pressed later")
		await click("press_3"); await push(3)
		check(game.state.press == [0,1,4,6],"D is pressed later")
		check(R.solved(game.state) and R.makespan(game.state) == 11,"the author plan clears the deadline")
		await capture(prefix+"03-solved")
		# 键盘：上下换带、左右换货、Q/W 提前推后。
		await click("press_0"); check(game.focus_row == 0 and game.focus_item == 0,"focus back on A")
		await key(KEY_DOWN); check(game.focus_row == 1,"down picks the cooling belt")
		await key(KEY_UP); check(game.focus_row == 0,"up picks the pressing belt")
		await key(KEY_RIGHT); check(game.focus_item == 1,"right moves to the next item")
		await key(KEY_W); check(game.state.press == [0,2,4,6],"W pushes the focused start back")
		await key(KEY_Q); check(game.state.press == [0,1,4,6],"Q pulls it forward")
		await key(KEY_LEFT); check(game.focus_item == 0,"left moves back")
		await key(KEY_Q); check(game.message.begins_with("已经到头了"),"the start cannot go below zero")
		await click("undo"); check(game.state.press == [0,2,4,6],"undo steps back one edit")
		await click("undo"); check(game.state.press == [0,1,4,6],"undo again returns the author plan")
		# 退回开局草稿：两排都回到顺排，撤销能整张拿回来。
		await click("reset"); await click("cancel"); check(game.state.press == [0,1,4,6],"cancel reset")
		await click("reset"); await click("confirm")
		check(game.state.press == R.DEFAULT_PRESS and game.state.cool == R.DEFAULT_COOL,"reset returns the draft")
		await click("undo"); check(game.state.press == [0,1,4,6] and game.state.cool == [1,5,7,9],"undo reset")
		await click("hint"); check(game.state.hint == 1,"first hint is optional")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores hint text")
		var saved = game.state.duplicate(true)
		await unmount(); await mount()
		check(game.state == saved and game.history.is_empty(),"reload exact plan")
		game.durations["trial"] = 6.0
		game.repository.fail_at = "replace"; saved = game.state.duplicate(true)
		await click("deliver")
		check(game.modal and game.state == saved,"trial save failure preserves the plan")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "trial" and game.state.attempts >= 2,"retry installs the trial exactly once")
		await unmount(); await mount()
		game.durations["trial"] = 6.0
		check(game.state.stage == "trial" and R.solved(game.state),"reload mid-trial")
		await click("skip"); check(game.state.stage == "delivery","verified plan accepted")
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
	print("GW07 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

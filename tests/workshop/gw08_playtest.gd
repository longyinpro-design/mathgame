extends SceneTree
const Scene = preload("res://game/workshop_gw08.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw08_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw08"
var test_path = "/tmp/gw08-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW08 window watchdog fired")
		print("GW08 WINDOW: ",checks," checks, ",failures+1," failures")
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
		check(game.state.capacity == 0,"no capacity proposed yet")
		await key(KEY_R)
		check(game.state.capacity == 0 and game.message == "先提出一个槽数，再重演记录。","replay without a capacity is refused")
		# 10 槽：记录二相符、记录一对不上，提交被拒并念出真实余数。
		await click("cap_10"); check(game.state.capacity == 10,"choosing a capacity")
		await click("replay_1"); check(game.state.tested_second == [10] and "相符" in game.message,"record two matches ten")
		await click("replay_0"); check(game.state.tested_first == [10] and "对不上" in game.message,"record one fails ten")
		await click("deliver")
		check(game.state.stage == "puzzle" and "剩 5 根" in game.message,"ten is refused with the real remainder")
		# 重摆与撤销：候选和重演表都跟着走。
		await click("reset"); await click("confirm")
		check(game.state.capacity == 0 and game.state.tested_first.is_empty() and game.state.tested_second.is_empty(),"reset clears the record")
		await click("undo")
		check(game.state.capacity == 10 and game.state.tested_first == [10],"undo restores the tested candidate")
		# 8 槽：两张都相符。
		await click("cap_8"); await click("replay_0"); await click("replay_1")
		check(R.solved(game.state),"eight satisfies both records")
		await capture(prefix+"03-tested")
		# 键盘：左右移候选，R/T 重演两张记录。
		await key(KEY_RIGHT); check(game.state.capacity == 9,"right arrow moves the capacity")
		await key(KEY_LEFT); check(game.state.capacity == 8,"left arrow moves back")
		await key(KEY_R); check(game.state.tested_first == [8,10],"R replays record one without duplicating")
		await key(KEY_T); check(game.state.tested_second == [8,10],"T replays record two")
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
	print("GW08 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

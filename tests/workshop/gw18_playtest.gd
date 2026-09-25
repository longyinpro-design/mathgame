extends SceneTree
const Scene = preload("res://game/workshop_gw18.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw18_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw18"
var test_path = "/tmp/gw18-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW18 window watchdog fired")
		print("GW18 WINDOW: ",checks," checks, ",failures+1," failures")
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
	game.durations = {"approach":0.5,"delivery":0.5,"launch":0.6}
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
		if child is Label and child.text.begins_with("库存 7 件"):
			check(child.get_line_count() == 1,"goal line fits one line")
# 选中某一格工序再挪 n 拍：每一次挪动都是一次真实的排法改动。
func nudge(slot: int, delta: int) -> void:
	var id = "press_%d"%slot if slot < R.COUNT else "cool_%d"%(slot-R.COUNT)
	await click(id)
	for i in range(absi(delta)): await click("later" if delta > 0 else "earlier")
func wait_trial() -> void:
	var deadline = Time.get_ticks_msec()+6000
	while game.world.trial_active and Time.get_ticks_msec() < deadline: await process_frame
	check(not game.world.trial_active,"trial animation finishes")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size
		if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)
		await mount()
		var prefix = str(size.x)+"-"
		check(game.state.stage == "arrival","opens at arrival")
		await capture(prefix+"01-arrival")
		await click("journal"); check(game.modal and game.state.stage == "arrival","journal opens without progressing story")
		await click("close_journal")
		await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
		check(game.state.stage == "approach","manual approach start")
		await click("skip"); check(game.state.stage == "ready","skip stops at ready")
		await key(KEY_SPACE); check(game.state.stage == "puzzle","player starts planning")
		check(game.state.press == [0,1,3] and game.state.cool == [1,3,5],"opens on the risky draft")
		check(game.page == 6,"the workbench opens on the early page")
		await capture(prefix+"02-puzzle")
		# 两页推演：同一份草稿，早班页走得通、晚班页说不通。
		check(R.page_ok(game.state,6) and not R.page_ok(game.state,8),"the draft splits the two pages")
		await click("deliver")
		check(game.state.stage == "puzzle" and "晚班：第 7 拍冷却到吊机间挤了两批" in game.message,
			"the draft is refused with the late rack overflow")
		check("暂存位只有一批" in game.message,"the refusal names the one-slot rack")
		# 切到晚班页：冲突那一格当场标出来。
		await click("page_late")
		check(game.page == 8 and game.state.cool == [1,3,5],"switching pages keeps the same draft")
		await process_frame
		check(game.world.page_hit.kind == "cool_rack" and game.world.page_hit.tick == 7,"the late page marks beat 7")
		await capture(prefix+"03b-late-conflict")
		# 试演本页：逐拍跑到第 7 拍停下，草稿一动不动。
		await click("trial"); check(game.state.stage == "trial","the trial page opens")
		await wait_trial()
		check(game.world.trial_conflict.kind == "cool_rack" and game.world.trial_tick == 7,"the trial stops at beat 7")
		await click("next"); check(game.state.stage == "puzzle","the trial returns to planning")
		check(game.state.cool == [1,3,5],"the trial leaves the draft untouched")
		# 切回早班页：同一份草稿在这一页走得通。
		await click("page_early")
		check(game.page == 6 and R.page_ok(game.state,6),"the early page accepts the same draft")
		await capture(prefix+"03-early-branch")
		# 修好 M 的冷却：5–7 改成 6–8，两页都过。
		await nudge(5,1)
		check(game.state.cool == [1,3,6],"M cooling moves to 6–8")
		check(R.solved(game.state) and R.page_ok(game.state,8),"the fixed plan passes both pages")
		await capture(prefix+"03c-robust")
		# 撤销与重摆：六个开工拍一起回退，重摆退回开局草稿，撤销能把重摆前的计划找回来。
		await click("undo"); check(game.state.cool == [1,3,5],"undo steps back to the risky cooling")
		await click("later"); check(game.state.cool == [1,3,6],"the fix can be re-applied")
		await click("reset"); await click("cancel"); check(game.state.cool == [1,3,6],"cancel keeps the plan")
		await click("reset"); await click("confirm")
		check(game.state.press == [0,1,3] and game.state.cool == [1,3,5],"reset returns the opening draft")
		check(game.page == 6,"reset keeps the preview page")
		await click("undo"); check(game.state.cool == [1,3,6],"undo restores the fixed cooling")
		# 键盘：←/→ 换批次，↑/↓ 换机器，Q/E 挪 1 拍，1/2 换推演页。
		await click("press_0"); check(game.focus_slot == 0,"clicking a press bar selects it")
		await key(KEY_RIGHT); check(game.focus_slot == 1,"right arrow moves to the next batch")
		await key(KEY_DOWN); check(game.focus_slot == 4,"down arrow moves to the cooling row")
		await key(KEY_LEFT); check(game.focus_slot == 3,"left arrow moves back")
		await key(KEY_UP); check(game.focus_slot == 0,"up arrow returns to the press row")
		await key(KEY_E); check(game.state.press == [1,1,3],"E pushes the selected press later")
		await key(KEY_Q); check(game.state.press == [0,1,3],"Q pulls it back")
		await key(KEY_Q)
		check(game.state.press == [0,1,3] and game.message.begins_with("已经到头了"),"F stops at beat 0 and says so")
		await key(KEY_2); check(game.page == 8,"the 2 key switches to the late page")
		await key(KEY_1); check(game.page == 6,"the 1 key switches back")
		# 提示与保存失败重试。
		await click("hint"); check(game.state.hint == 1 and game.message == game.hint_texts()[0],"first hint is optional")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores the hint text")
		# 提交保存失败重试后正好进入一次正式运行。
		game.repository.fail_at = "replace"; var saved = game.state.duplicate(true)
		await click("deliver"); check(game.modal and game.state == saved,"claim save failure preserves the plan")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "delivery","retry installs the claim exactly once")
		game.elapsed = 0.2
		await capture(prefix+"04-delivery")
		# 正式运行自己跑到第 3 拍停下读通知：不确认就不往下走，确认后还是同一份计划。
		var deadline = Time.get_ticks_msec()+3000
		while game.state.stage == "delivery" and Time.get_ticks_msec() < deadline: await process_frame
		check(game.state.stage == "notice" and not game.state.confirmed,"the run stops at beat 3 for the notice")
		check("第 3 拍确认" in game.line() and "晚班" in game.line(),"the notice names the real shift")
		await create_timer(0.1).timeout
		check(game.state.stage == "notice","the notice never auto-advances")
		await click("next")
		check(game.state.stage == "launch" and game.state.confirmed,"confirming continues the same plan")
		check(game.state.press == [0,1,3] and game.state.cool == [1,3,6],"the confirmed run keeps the plan")
		deadline = Time.get_ticks_msec()+3000
		while game.state.stage == "launch" and Time.get_ticks_msec() < deadline: await process_frame
		check(game.state.stage == "handover","the confirmed run reaches the handover lever")
		await capture(prefix+"04b-handover")
		check(R.load_start(game.state.branch,1) == 8,"the actual run lifts V at beat 8")
		await click("lever"); check(game.state.stage == "aftermath" and game.state.beat == 0,"the lever opens the ending")
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
	print("GW18 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

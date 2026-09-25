extends SceneTree
const Scene = preload("res://game/workshop_gw11.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw11_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw11"
var test_path = "/tmp/gw11-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW11 window watchdog fired")
		print("GW11 WINDOW: ",checks," checks, ",failures+1," failures")
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
# 选中一格工序，再用底栏的「提前／推后 1 拍」把它挪到目标拍。
func move_to(batch: int, row: int, target: int) -> void:
	await click("cell_%d_%d"%[batch,row])
	var current = R.start_of(game.state,batch,row)
	for i in range(absi(target-current)):
		await click("later" if target > current else "earlier")
func play_round(prefix: String) -> void:
	await mount()
	check(game.state.stage == "arrival","opens at arrival")
	await capture(prefix+"01-arrival")
	await click("journal"); check(game.modal,"journal opens without progressing story"); await click("close_journal")
	await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
	check(game.state.stage == "approach","manual approach start")
	await click("skip"); check(game.state.stage == "ready","skip stops at ready")
	await key(KEY_SPACE); check(game.state.stage == "puzzle","player starts puzzle")
	await capture(prefix+"02-puzzle")
	check(game.state.ticket == 0,"no ticket chosen yet")
	check(game.state.assembly == [6,6] and game.state.cool == [8,9] and game.state.load == [11,11],"the opening draft is on the table")
	# 还没选票就提交：被拒，并念出真实原因。
	await click("deliver")
	check(game.state.stage == "puzzle" and "船票" in game.message,"submitting without a ticket is refused")
	# 键盘：↑↓ 换批、←→ 换工序、Q/E 挪拍。
	await key(KEY_DOWN); check(game.world.focus_batch == 1,"down arrow switches to batch B")
	await key(KEY_UP); check(game.world.focus_batch == 0,"up arrow switches back to batch A")
	await key(KEY_RIGHT); check(game.world.focus_row == 1,"right arrow moves to the next stage")
	await key(KEY_LEFT); check(game.world.focus_row == 0,"left arrow moves back")
	# 13 拍票：单批无缝、票也对，只在装配台上与 A 撞车。
	await click("ticket_13"); check(game.state.ticket == 13,"choosing the 13-beat ticket")
	await move_to(0,0,7); await move_to(0,1,9); await move_to(0,2,12)
	await move_to(1,0,8); await move_to(1,1,11); await move_to(1,2,13)
	check(game.state.assembly == [7,8] and game.state.cool == [9,11] and game.state.load == [12,13],"the 13-beat plan is arranged")
	# 到料时刻与台面边界：两条守卫也从底栏按钮走一遍。
	await move_to(0,0,5)
	await click("deliver")
	check(game.state.stage == "puzzle" and "第 6 拍才送到" in game.message,"work before the material lands is refused")
	await move_to(0,0,0)
	await click("earlier")
	check(game.state.assembly[0] == 0 and "到边上" in game.message,"stepping past the first beat is refused")
	await move_to(0,0,7)
	check(R.shortfalls(game.state).size() == 1 and "装配台" in R.shortfalls(game.state)[0],"the 13-beat plan only collides on the shared table")
	check_layout()
	# 台面边界：开工拍拉到最右，工序条仍留在台面上、按钮也够大。
	var far = R.set_start(game.state,0,0,R.RANGE_MAX)
	game.world.state = far
	var far_rect = game.world.span_rect(0,0)
	check(far_rect.size.x >= 44 and far_rect.size.y >= 44,"an outlying bar keeps a 44px target")
	check(Rect2(0,0,1280,720).encloses(far_rect),"an outlying bar stays on the table")
	game.world.state = game.state
	await capture(prefix+"03-conflict")
	await click("deliver")
	check(game.state.stage == "puzzle" and "装配台" in game.message and "重叠" in game.message,"the 13-beat plan is refused with the real clash")
	# 撤销与重摆：最后一步改动原样退回，重摆回到开局草稿。
	var arranged = game.state.duplicate(true)
	await click("undo")
	check(game.state != arranged and game.state.assembly[0] == 6,"undo steps the last change back")
	var rewound = game.state.duplicate(true)
	await click("reset"); await click("confirm")
	check(game.state.ticket == 0 and game.state.assembly == [6,6] and game.state.cool == [8,9] and game.state.load == [11,11],"reset returns the opening draft")
	await click("undo"); check(game.state == rewound,"undo restores the plan that was reset away")
	# 换成 14 拍票：三格各挪到位就是唯一解。
	await move_to(0,0,7)
	await click("ticket_14"); check(game.state.ticket == 14,"switching to the 14-beat ticket")
	await move_to(1,0,9); await move_to(1,1,12); await move_to(1,2,14)
	check(R.solved(game.state),"the 14-beat plan is the only solution")
	check(game.state.assembly == [7,9] and game.state.cool == [9,12] and game.state.load == [12,14],"the solution is A 7/9/12 with B 9/12/14")
	check("A 批 装配 7–9" in game.world.plan_text(),"the world prints the same plan")
	# 提示与保存失败重试。
	await click("hint"); check(game.state.hint == 1 and game.message == game.hint_texts()[0],"first hint is optional")
	game.repository.fail_at = "replace"
	await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
	game.repository.fail_at = ""; await click("retry")
	check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores hint text")
	await capture(prefix+"03b-plan")
	# 提交保存失败重试后正好进入一次交付。
	game.repository.fail_at = "replace"; var saved = game.state.duplicate(true)
	await click("deliver"); check(game.modal and game.state == saved,"claim save failure preserves the plan")
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
	await click("next"); await click("confirm"); check(game.state == R.fresh(),"confirmed restart starts over")
	await unmount()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size
		if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)
		await play_round(str(size.x)+"-")
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
	print("GW11 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

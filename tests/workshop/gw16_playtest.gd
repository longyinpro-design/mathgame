extends SceneTree
const Scene = preload("res://game/workshop_gw16.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw16_rules.gd")
var game: Control
var checks = 0
var failures = 0
var elapsed = 0.0
var capture_dir = "res://docs/playtest/workshop-gw16"
var test_path = "/tmp/gw16-window-%d/save.json"%OS.get_process_id()
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 240.0:
		push_error("GW16 window watchdog fired")
		print("GW16 WINDOW: ",checks," checks, ",failures+1," failures")
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
		if child is Label and child.text.begins_with("四段 12 拍"):
			check(child.get_line_count() == 1,"goal fits one line")
# 清空铃架、按顺序排一首、试听、保存；每一步都走界面按钮或键盘。
func save_order(order: Array) -> void:
	await click("reset"); await click("confirm")
	for length in order: await key(KEY_2+length-2)
	await key(KEY_T)
	await click("save")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size
		if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)
		await mount()
		var prefix = str(size.x)+"-"
		check(game.state.stage == "arrival","opens at arrival")
		await capture(prefix+"01-arrival")
		await click("journal"); check(game.modal,"journal opens without progressing the story"); await click("close_journal")
		await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
		check(game.state.stage == "approach","manual approach start")
		await click("skip"); check(game.state.stage == "ready","skip stops at ready")
		await key(KEY_SPACE); check(game.state.stage == "puzzle","player starts the puzzle")
		await capture(prefix+"02-puzzle")
		check(game.state.segments.is_empty() and game.state.saved.is_empty(),"the rack and board start empty")
		check(not game.buttons.has("pick_0"),"the four arrangements are never prefilled")
		check_layout()
		# 空收集板提交：被拒并念出真实原因。
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "四首还没收齐" in game.message,"an empty collection is refused")
		# 首尾反例 3/2/4/3：段内两两不同，只有末段与首段相同。
		await key(KEY_3); await key(KEY_2); await key(KEY_4); await key(KEY_3)
		check(game.state.segments == [3,2,4,3],"keyboard arranges 3/2/4/3")
		await key(KEY_T)
		check(game.state.heard and "末段和首段都是 3 拍" in game.message,"the wrap conflict is spoken")
		await click("save")
		check(game.state.saved.is_empty() and "末段和首段都是 3 拍" in game.message,"the wrap phrase cannot be saved")
		await key(KEY_SPACE)
		check(game.state.stage == "puzzle" and "末段和首段都是 3 拍" in game.message,"submit names the wrap conflict")
		await capture(prefix+"03-refused")
		# 重摆与撤销：铃架跟着快照走。
		await click("reset"); await click("confirm")
		check(game.state.segments.is_empty(),"reset clears the rack")
		await click("undo")
		check(game.state.segments == [3,2,4,3],"undo restores the rack")
		# 取下重排：R 取最后一段，点铃架上的一段取那一段。
		await key(KEY_R); check(game.state.segments == [3,2,4],"R takes back the last segment")
		await click("slot_0"); check(game.state.segments == [2,4],"clicking a slot takes that segment back")
		await key(KEY_R); check(game.state.segments == [2],"the rack empties one segment at a time")
		await key(KEY_3); await key(KEY_4); await key(KEY_3)
		check(game.state.segments == [2,3,4,3],"keyboard rebuilds 2/3/4/3")
		await key(KEY_T); check(game.state.heard and "可以保存" in game.message,"a legal phrase auditions cleanly")
		await click("save")
		check(game.state.saved == [[2,3,4,3]] and "1 / 4" in game.message,"the first tune is saved")
		# 其余三首：每首都清空重排、试听、保存。
		await save_order([4,3,2,3])
		check(game.state.saved.size() == 2,"the second tune is saved")
		# 中途续档：收集板与铃架都从独立存档回来。
		await unmount(); await mount()
		check(game.state.stage == "puzzle" and game.state.saved.size() == 2,"a half-finished collection survives reload")
		check(game.state.segments == [4,3,2,3],"the rack survives reload")
		await save_order([3,2,3,4])
		check(game.state.saved.size() == 3,"the third tune is saved")
		await save_order([3,4,3,2])
		check(game.state.saved.size() == 4,"all four tunes are saved")
		check(game.world.tune_rect(2) != game.world.tune_rect(3),"same first segment tunes get separate chips")
		await click("save")
		check(game.state.saved.size() == 4 and "重存同一首不算新的一首" in game.message,"re-saving the same tune is refused")
		check(game.buttons.has("pick_0"),"the collection offers the lunch choice")
		await capture(prefix+"03-collected")
		# 提示与保存失败重试。
		await click("hint"); check(game.state.hint == 1 and game.message == game.hint_texts()[0],"first hint is optional")
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 1,"failed hint uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 2 and game.message == game.hint_texts()[1],"retry restores the hint text")
		# 收齐后任选一首留作章末午休曲。
		await click("pick_2")
		check(game.state.chosen == 2 and "留作章末午休曲" in game.message,"clicking a collected tune picks the lunch tune")
		# 提交保存失败重试后正好进入一次交付。
		game.repository.fail_at = "replace"; var saved_state = game.state.duplicate(true)
		await click("deliver"); check(game.modal and game.state == saved_state,"claim save failure preserves the record")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.stage == "delivery","retry installs the claim exactly once")
		await capture(prefix+"04-delivery")
		await click("skip"); check(game.state.stage == "aftermath" and game.state.beat == 0,"the result stops for dialogue")
		await create_timer(0.1).timeout; check(game.state.beat == 0,"story never auto-advances")
		await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
		check(game.state.stage == "complete","explicit discovery completes the level")
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
	print("GW16 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

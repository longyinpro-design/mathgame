extends SceneTree
const Scene = preload("res://game/workshop_gw01.tscn")
const Focus = preload("res://tests/forest/window_focus.gd")
const R = preload("res://scripts/workshop/gw01_rules.gd")
var game: Control
var checks = 0
var failures = 0
var capture_dir = "res://docs/playtest/workshop-gw01"
var test_path = "/tmp/gw01-window-%d/save.json"%OS.get_process_id()
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
	if not await Focus.ready(root): check(false,"native window ready"); return
	if not game.buttons.has(id) or game.buttons[id].disabled: check(false,"available button "+id); return
	var b: Control = game.buttons[id]
	var point = b.get_global_transform_with_canvas()*(b.size/2)*Vector2(root.size)/Vector2(1280,720)
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
	game.time_scale = 0.3
	check(await Focus.ready(root),"native window uses isolated viewport input")
	await process_frame
func unmount() -> void:
	root.remove_child(game); game.queue_free(); await process_frame
func check_layout() -> void:
	for b in game.buttons.values():
		check(b.size.x >= 48 and b.size.y >= 48,"target size "+b.name)
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
		await click("pause"); var progress = game.world.progress
		await create_timer(0.12).timeout
		check(game.world.progress == progress,"pause freezes presentation")
		await click("skip"); check(game.state.stage == "ready","skip stops at ready")
		await key(KEY_SPACE); check(game.state.stage == "puzzle","player starts puzzle")
		await click("deliver"); check(game.state.stage == "puzzle" and game.state.attempts == 1,"empty submission retained with reason")
		await click("target_0"); check_layout()
		await key(KEY_SPACE); check(game.state.attempts == 2,"Space inspects immediately after selection")
		await click("target_0"); await key(KEY_TAB); await key(KEY_ENTER)
		check(game.selected == 1,"Tab and Enter select the next physical tray")
		await key(KEY_1)
		await click("one"); check(game.state.trays[0] == 1,"mouse single placement")
		await key(KEY_B); check(game.state.trays[0] == 3,"batch tops up partial tray")
		await key(KEY_C); check(game.state.capacities[0] == 3,"occupied tray rejects insert switch")
		await key(KEY_D); check(game.state.trays[0] == 2,"return one")
		await key(KEY_Z); check(game.state.trays[0] == 3,"undo return")
		# Feedback must survive a failed write and retry, not merely its counter.
		game.repository.fail_at = "replace"
		await click("hint"); check(game.modal and game.state.hint == 0,"failed hint leaves assistance uncommitted")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.hint == 1 and game.message == game.hint_texts()[0],"retry shows the first hint instead of silently skipping it")
		for tier in range(2,5):
			await click("hint"); check(game.state.hint == tier,"voluntary hint tier persisted")
		check(game.message.begins_with("示范下一步"),"fourth tier explicitly marked demonstration")
		game.repository.fail_at = "replace"; await click("deliver")
		check(game.modal,"failed inspection waits for save retry")
		game.repository.fail_at = ""; await click("retry")
		check(game.message == R.shortfalls(game.state)[0],"retry restores failed inspection reason")
		await capture(prefix+"02-puzzle")
		var saved = game.state.duplicate(true)
		await unmount(); await mount()
		check(game.state == saved and game.history.is_empty(),"reload exact board without stale undo")
		await click("reset"); await click("cancel"); check(game.state == saved,"cancel reset preserves board")
		await click("reset"); await click("confirm")
		check(R.stock(game.state) == 23 and game.state.hint == 4 and game.state.attempts == 3,"reset conserves inventory and support")
		await click("undo"); check(game.state == saved,"reset is undoable")
		await key(KEY_6); await key(KEY_B)
		check(game.state.box == 2,"repair box batch respects capacity")
		await click("deliver"); check(game.state.stage == "puzzle","wrong allocation cannot complete")
		await click("undo"); check(game.state.box == 0,"recover from wrong allocation")
		# Real save failure leaves both visible state and history untouched until retry.
		await key(KEY_2); await click("resize")
		check(game.state.capacities[1] == 5,"mouse switches empty tray insert")
		await key(KEY_Z); check(game.state.capacities[1] == 3,"undo restores insert")
		game.repository.fail_at = "replace"
		await key(KEY_C); check(game.modal and game.state.capacities[1] == 3,"insert save failure retains old capacity")
		game.repository.fail_at = ""; await click("retry")
		check(game.state.capacities[1] == 5,"retry installs changed insert")
		game.repository.fail_at = "replace"; saved = game.state.duplicate(true)
		await key(KEY_B)
		check(game.modal and game.state == saved and not game.pending.is_empty(),"failed save blocks state installation")
		game.repository.fail_at = ""; await click("retry")
		check(not game.modal and game.state.trays[1] == 5,"retry installs exact candidate once")
		for k in [KEY_3,KEY_4]: await key(k); await key(KEY_C); await key(KEY_B)
		await key(KEY_5); await key(KEY_B)
		await key(KEY_6); await key(KEY_B)
		check(R.solved(game.state),"all 23 in five trays and repair box")
		await capture(prefix+"03-ready-to-inspect")
		await click("reset"); await click("confirm")
		var destinations = {}
		for item in game.world.moving: destinations[str(item.target)+":"+str(item.index)] = true
		check(destinations.size() == 23 and R.stock(game.state) == 23,"reset animation returns each of 23 items to a distinct position")
		await click("undo"); check(R.solved(game.state) and game.state.hint == 4,"undo reset restores solved board without erasing help")
		await click("deliver"); check(game.state.stage == "delivery","inspection starts result animation")
		game.paused = true; game.elapsed = 2.5; game.world.progress = 0.625; game.world.queue_redraw()
		await capture(prefix+"04-mistimed-lift")
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		progress = game.world.progress; await create_timer(0.08).timeout
		check(game.paused and game.world.progress == progress,"focus loss pauses scene")
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await unmount(); await mount()
		check(game.state.stage == "delivery" and R.solved(game.state),"reload accepted inventory during animation")
		await click("skip"); check(game.state.stage == "aftermath" and game.state.beat == 0,"result stops for dialogue")
		await create_timer(0.1).timeout; check(game.state.beat == 0,"story never auto-advances")
		await key(KEY_SPACE); await key(KEY_SPACE); await key(KEY_SPACE)
		check(game.state.stage == "complete","explicit discovery completes level")
		await capture(prefix+"05-complete")
		await click("journal"); check_layout(); await capture(prefix+"06-discovery"); await click("close_journal")
		await unmount(); await mount(); check(game.state.stage == "complete","completion survives reload")
		await click("next"); await click("cancel"); check(game.state.stage == "complete","restart is confirmed")
		await unmount()
	# Damaged file preservation is also exercised through actual modal UI.
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
	print("GW01 WINDOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

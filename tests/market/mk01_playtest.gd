extends SceneTree
const Scene = preload("res://game/market_mk01.tscn")
const Sample = preload("res://scripts/market/mk01_scene.gd")
const World = preload("res://scripts/market/mk01_world.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk01-reasoning"
func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
func click(id: String) -> void:
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false,"button unavailable "+id); return
	var b: Control = game.buttons[id]
	var logical = b.get_global_transform_with_canvas()*(b.size/2)
	var point = logical*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame
func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame
func place(id: int, slot: int) -> void:
	await click("cup_%d"%id); await click("slot_%d"%slot)
const UIStyle = preload("res://scripts/cargo/skin.gd")
const FRAME = Rect2(0,0,1280,720)
# 镜头由场景自己算（贴脸那一段 1.16 倍、往下让 40 像素），检查不重抄这条换算式：
# 直接从世界层拿它此刻真实的画布变换，量玩家真正看到的那一块。
func on_screen(rect: Rect2) -> Rect2:
	var at: Transform2D = game.world.get_global_transform_with_canvas()
	return Rect2(at*rect.position, rect.size*at.get_scale())
# 八只货架杯与三个托盘位：每一个都得点得着（48 逻辑像素），也都得整块留在画面里。
func hotspots_sized() -> int:
	var over = 0
	for id in range(8):
		var rect = on_screen(game.world.cup_rect(id))
		if rect.size.x < 48.0 or rect.size.y < 48.0:
			over += 1; print("SMALL cup_%d "%id,rect)
		if not FRAME.encloses(rect):
			over += 1; print("OFFSCREEN cup_%d "%id,rect)
	for slot in range(3):
		var rect = on_screen(game.world.slot_rect(slot))
		if rect.size.x < 48.0 or rect.size.y < 48.0:
			over += 1; print("SMALL slot_%d "%slot,rect)
		if not FRAME.encloses(rect):
			over += 1; print("OFFSCREEN slot_%d "%slot,rect)
	return over
# 两只杯子不能共用一个点击点：同一排里相邻两格的框一旦相接，点中间那一下归属说不清。
# 挨着算不算重叠留 1 像素余量：牌子底边与下一排框顶本来就是设计成同一条线的，
# 镜头换算那点浮点误差不该被当成缺陷。
func crossed(a: Rect2, b: Rect2) -> bool:
	var hit = a.intersection(b)
	return hit.size.x > 1.0 and hit.size.y > 1.0
func hotspots_apart() -> int:
	var over = 0
	for a in range(8):
		for b in range(a+1,8):
			if crossed(on_screen(game.world.cup_rect(a)),on_screen(game.world.cup_rect(b))):
				over += 1; print("OVERLAP cup_%d cup_%d"%[a,b])
	var trays = [on_screen(game.world.slot_rect(0)), on_screen(game.world.slot_rect(1)),
		on_screen(game.world.slot_rect(2))]
	for a in range(2):
		if crossed(trays[a],trays[a+1]):
			over += 1; print("OVERLAP tray slots ",a," ",trays[a]," ",trays[a+1])
	return over
# 容量签钉在货架前沿，正压在自家那排杯子的脚点下：一只杯子的框盖住自己那一排的牌是设计，
# 爬到别排的牌上就是缺陷——那块牌的下半截会同时够到两只不同的杯子。
func plaques_claimed() -> int:
	var over = 0
	for sign in game.world.lip_plaques():
		for id in range(8):
			if game.world.cup_kind(id) == sign["kind"]: continue
			if crossed(on_screen(game.world.cup_rect(id)),on_screen(sign["rect"])):
				over += 1
				print("PLAQUE ",sign["text"]," claimed by cup ",id," (",["蓝","白","小"][game.world.cup_kind(id)],"排)")
	return over
# 抬头那两块板由 sign_text 画：Label 的框按板子内框写死，汉字又从不折行，
# 一句超长的话会直接爬出板子外面。这里按真实字号量每一句，超框就算缺陷。
func spilled_labels() -> int:
	var over = 0
	for child in game.ui.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = 0.0
		for line in child.text.split("\n"):
			needed = maxf(needed,UIStyle.face().get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,
				-1,child.get_theme_font_size("font_size")).x)
		if needed > child.size.x+0.5:
			over += 1; print("LABEL ",child.text," needs ",needed," in ",child.size.x)
	return over
func label_at(at: Vector2) -> String:
	for child in game.ui.get_children():
		if child is Label and child.position == at: return child.text
	return ""
# 整盘回执上的杯样按 RECEIPT_SCALE 等比缩、一只挨一只排过去：
# 排到「= 16」那一格之前必须停住，顶端也不能顶到「第 N 盘」那一行。
func receipt_icons_fit() -> int:
	var over = 0
	for index in range(game.state.observations.size()):
		var record: Dictionary = game.state.observations[index]
		var reach = 12.0
		var tallest = 0.0
		for kind in range(2):
			var dims = game.world.kind_size(kind)*World.RECEIPT_SCALE
			tallest = maxf(tallest,dims.y)
			for n in range(record.counts[kind]): reach += dims.x+World.RECEIPT_GAP
		if reach-World.RECEIPT_GAP > 151.0:
			over += 1; print("RECEIPT ",index," icons reach ",reach," past the total at 151")
		if 62.0-tallest < 22.0:
			over += 1; print("RECEIPT ",index," icon top ",62.0-tallest," climbs into the title line")
	return over
func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK01 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk01-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival","opens at harbor dialogue")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused narrative action")
		await click("next")
		check(game.state.beat == 2,"dialogue waits for explicit advances")
		await click("next"); await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes motion")
		await click("skip")
		check(game.state.stage == "ready","approach stops before player control")
		await click("next")
		check("未知" in game.world.cup_description(0),"tooltip keeps capacity unknown")
		await key(KEY_1); await key(KEY_Q); await key(KEY_Z)
		check(game.state.slots == [-1,-1,-1],"keyboard placement and undo")
		check(hotspots_sized() == 0,"every cup and tray hotspot is 48 pixels or bigger and stays inside the frame")
		check(hotspots_apart() == 0,"no two cups on the shelf share a click point")
		check(plaques_claimed() == 0,"a cup's click box only ever reaches the capacity sign of its own row")
		check("托盘 Q 位" in game.buttons.slot_0.tooltip_text
			and "键盘 1" in game.buttons.cup_0.tooltip_text,
			"tray positions and shelf cups each name the key that really reaches them")
		check(spilled_labels() == 0,"nothing written on a board climbs out of it")
		await place(0,0); await place(1,1); await place(2,2)
		await click("measure")
		game.elapsed = 2.1; await process_frame; await click("pause")
		check(game.world.poured_volume() == 0,"shutter reveals no intermediate cup volume")
		await capture(prefix+"02-shutter")
		await click("skip")
		check(game.state.observations.size() == 1 and not game.state.calibrated,"old shortcut yields only first receipt")
		check(receipt_icons_fit() == 0,"the first receipt's cup icons stop short of its total")
		await capture(prefix+"03-first-receipt")
		await click("next"); await click("measure")
		check(game.state.stage == "puzzle" and game.state.observations.size() == 1,"same mixture cannot count twice")
		await place(5,1); await click("measure")
		check(game.state.stage == "puzzle","calibration requires both blue and white and no small cup")
		await place(3,1); await click("measure")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes measurement")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip"); await click("next")
		check(game.state.stage == "deduction" and game.state.guesses == [0,0],"two receipts do not automatically solve capacity")
		check("容量签" in label_at(Vector2(456,28)) and "先复核" not in label_at(Vector2(456,28)),
			"the goal board switches to what this stage actually asks for")
		check(receipt_icons_fit() == 0,"both receipts' cup icons stop short of their totals")
		check(spilled_labels() == 0,"inference boards and two receipts keep every line inside their own board")
		await capture(prefix+"04-inference")
		await click("guess_up_0"); await click("guess_up_1"); await click("confirm_capacity")
		check(game.state.stage == "deduction" and game.state.guesses == [2,2],"wrong claim remains editable")
		for n in range(4): await click("guess_up_0")
		for n in range(2): await click("guess_up_1")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state.stage == "deduction" and game.state.guesses == [6,4] and game.state.observations.size() == 2,"reload retains evidence and player's tags")
		await click("confirm_capacity")
		check(game.state.calibrated and game.state.slots == [-1,-1,-1],"correct inference unlocks fresh delivery order")
		await place(0,0); await place(1,1); await place(2,2)
		await click("measure"); await click("skip")
		check(game.state.stage == "result" and game.world.poured_volume() == 16,"old arrangement fails new delivery order")
		await click("next"); await click("reset"); await click("cancel")
		check(game.state.slots == [0,1,2],"cancel reset preserves cups")
		await key(KEY_X)
		check(game.modal and game.buttons.reset.text == "重摆 X" and game.state.slots == [0,1,2],
			"X opens the same reset question the button label advertises")
		await click("cancel")
		await click("reset"); await click("confirm")
		await place(0,0); await place(2,1); await place(5,2)
		await capture(prefix+"05-final-load")
		await click("measure")
		if small: await click("skip")
		else:
			while game.state.stage == "measuring": await process_frame
		check(game.state.stage == "result" and game.world.poured_volume() == 11,"final actual measurement reaches eleven")
		await click("next")
		game.elapsed = 2.5; await process_frame; await click("pause")
		check(game.world.seed_position() != Vector2(423,411),"seed sack visibly in flight")
		await capture(prefix+"06-delivery")
		if small: await click("skip")
		else:
			await click("pause")
			while game.state.stage == "delivery": await process_frame
		check(game.state.stage == "complete","three measurements and inference deliver seeds")
		check(not game.buttons.has("back_forest"),"standalone dock offers no camp return")
		await capture(prefix+"07-complete")
		if not small:
			# Reopening through the forest camp hub lands back on the delivered dock with a way home.
			game.queue_free(); await process_frame
			Sample.entry = "camp"
			game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
			check(game.state.stage == "complete" and game.from_camp and Sample.entry == "","camp arrival is consumed once at the delivered dock")
			check(game.buttons.has("back_forest") and not game.buttons.back_forest.disabled,"delivered dock offers the return to camp")
			await capture("08-return-to-camp")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK01 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

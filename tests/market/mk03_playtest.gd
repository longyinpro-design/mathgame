extends SceneTree
# MK03 实窗审计：真实窗口里走一遍「叠合记录 → 挂两枚重签 → 挂签复秤 → 翻出原单」，
# 在 1280×720 与 960×540 各拍一次，并检查台面上的文字有没有爬出自己的边框。
const Scene = preload("res://game/market_mk03.tscn")
const Rules = preload("res://scripts/market/mk03_rules.gd")
const World = preload("res://scripts/market/mk03_world.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk03-weight"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
func click(id: String) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
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
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame
func hold(seconds: float) -> void:
	game.paused = true; game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	game.world.queue_redraw() # explicit fixture pose while presentation is paused
	await process_frame
func fits(text: String, size_px: int, width: float) -> bool:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(size_px)).x)
	return widest <= width
# 汉字不会自动断行：一行最短的连续文字比盒子还宽，就会横着画到旁边的货上。
func spilled(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = child.get_combined_minimum_size()
		if needed.x > child.size.x + 1 or needed.y > child.size.y + 1:
			over += 1; print("SPILL ", child.text, " needs ", needed, " in ", child.size)
	return over
# 柜面上钉着的牌由世界直接 draw_string：字号不抬、汉字不折行，也没有任何 Label 可以问。
# 所以牌上的文字、框与字号由世界自己交出来，这里按真实字号量每一句。
func plaque_overflow() -> int:
	var over = 0
	for board in game.world.sign_boards():
		var needed = UIStyle.face().get_string_size(board["text"], HORIZONTAL_ALIGNMENT_LEFT,
			-1, board["size"]).x
		if needed > board["rect"].size.x - 10.0:
			over += 1; print("PLAQUE ", board["text"], " needs ", needed, " of ", board["rect"].size.x)
	return over
# 热点该压在玩家看得见的那张纸、那一枚牌上。纸心从美术脚点算起，不去借热点自己的框，
# 这样「谁点得着」才是独立的一问；两边都换算到屏上再比。
func covers(id: String, at_world: Vector2) -> bool:
	var canvas: Transform2D = game.world.get_global_transform_with_canvas()
	return game.buttons[id].get_global_rect().has_point(canvas * at_world)
func paper_centre(foot: Vector2) -> Vector2:
	return foot + Vector2(0, -World.PAPER_LIFT / 2.0)
# 纸面就是美术脚点左右各 50、往上 130 的那一块，跟热点框无关：叠上来的那张纸不能压住
# 下层纸的牌头，量出「记录一」实际多宽再比，剩下的才是一眼看得清的两张纸。
func caption_strip(foot: Vector2) -> Rect2:
	var width: float = game.world.font.get_string_size("记录一", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	return Rect2(foot + Vector2(-40, World.CARD_TITLE_Y - 14), Vector2(width, 18))

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK03 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk03-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival" and "封箱交来却没人称过" in game.line(),"opens on the sealed crates, not on a puzzle")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		await click("next"); await click("next")
		check(game.state.stage == "approach","the third line walks the player to the counter")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		await click("skip")
		check(game.state.stage == "ready","approach stops before player control")
		await click("next")
		check(game.state.stage == "puzzle","the counter is handed to the player")
		var small_target = 0
		for id in game.buttons:
			var b: Control = game.buttons[id]
			if not id.begins_with("tag_") and not id.begins_with("crate_") and id != "fold": continue
			if b.size.x < 48 or b.size.y < 48: small_target += 1
		check(small_target == 0,"every crate, hook and tag is a 48 pixel target or bigger")
		check(spilled(game.ui) == 0,"no counter text spills out of its box on the empty table")
		check(plaque_overflow() == 0,"every board nailed to the counter holds its own words")
		check(covers("fold", paper_centre(game.world.record_foot(1)))
			and not covers("fold", paper_centre(game.world.record_foot(0))),
			"the fold target sits on record two, the very paper its tooltip names")
		check(covers("crate_0", game.world.pan_cargo(0) + Vector2(0,-74))
			and covers("crate_1", game.world.pan_cargo(1) + Vector2(0,-74)),
			"an empty hook answers a click on the top of its own plaque")
		check(covers("tag_0_1", game.world.tag_foot(0,1) + Vector2(0,-3))
			and covers("tag_1_7", game.world.tag_foot(1,7) + Vector2(0,-3)),
			"a tag hotspot is where that weight is actually drawn")
		# 16 号字的笔锋在基线之上约 12 像素：牌头的基线再往上抬，字就要骑出纸边。
		check(World.CARD_TITLE_Y - 12.0 >= -World.PAPER_LIFT,
			"the record label is written on the paper, not riding over its top edge")
		# 牌夹那一横黄铜压在纸顶往下 100：最后一笔「一」落在夹子上就读不出来了。
		check(World.CARD_TITLE_Y - 12.0 >= World.CLIP_BOTTOM,
			"the record caption clears the brass clip instead of being written across it")
		check(World.CARD_TITLE_Y + 3.0 <= World.CARD_CRATE_Y - 24.0,
			"the record caption leaves the top of the crate row clear")
		var sheet := Rect2(game.world.folded_foot() + Vector2(-World.CARD_WIDTH / 2.0, -World.PAPER_LIFT),
			Vector2(World.CARD_WIDTH, World.PAPER_LIFT + 3.0))
		check(not sheet.intersects(caption_strip(game.world.record_foot(0))),
			"the sheet folded on top leaves the caption of the record underneath in the clear")
		await capture(prefix+"02-table")
		await key(KEY_A)
		check(game.state.stacked == 1,"A folds record two onto record one")
		await key(KEY_A)
		check(game.state.stacked == 0,"folding again separates the two records instead of stacking a second copy")
		await key(KEY_A)
		await create_timer(0.4).timeout
		check(game.world.fold_progress() == 1.0,"the folded pair has come to rest before the stack is measured")
		check(game.buttons.fold.size.x >= 124 and game.buttons.fold.size.y >= 124,
			"a folded pair of records stays one clickable stack, not a sliver of paper")
		check(covers("fold", paper_centre(game.world.record_foot(0)))
			and covers("fold", paper_centre(game.world.fold_foot())),
			"the folded stack answers a click on either corner of it")
		check(not covers("fold", paper_centre(game.world.record_foot(1))),
			"the difference card that took record two's place is not a control")
		check(plaque_overflow() == 0,"the difference board holds its own words")
		await key(KEY_1)
		check(game.state.red == 1,"number keys hang the tag the player named")
		await key(KEY_Q)
		check(game.state.blue == 1,"the blue row answers its own keys")
		await click("deliver")
		check(game.state.stage == "puzzle" and "记录一没兑现" in game.message,
			"the scale answers only after 挂签复秤, and names the record that failed")
		check(Rules.equation(0) in game.message,
			"a record that failed is quoted in the very spelling the counter board uses")
		await capture(prefix+"03-first-reading")
		await key(KEY_Z); await key(KEY_Z)
		check(game.state.red == 0 and game.state.blue == 0,"two undos hand both tags back to the rack")
		await click("deliver")
		check(game.state.stage == "puzzle" and "红箱的钩子还空着" in game.message,"an empty hook is its own reason")
		for n in range(3): await click("hint")
		check(game.state.hint == 3 and "蓝 4、红 5" in game.message,"the third hint states the whole hanging")
		await key(KEY_5); await key(KEY_R)
		check(game.state.red == 5 and game.state.blue == 4 and Rules.solved(game.state),
			"red five and blue four are the only hanging that fits both records")
		await capture(prefix+"04-solved-table")
		await click("deliver")
		check(game.state.stage == "reweigh","the accepted hanging unlocks the scale")
		await hold(1.3)
		check(game.world.progress > 0.4 and game.world.progress < 0.6,"both readings are weighed in one continuous motion")
		check(plaque_overflow() == 0,"the board that names the current reading holds its own words")
		await capture(prefix+"05-reweigh")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the reweigh")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "delivery","the reweigh hands over to 衡伯")
		await hold(2.6); check(plaque_overflow() == 0,"the hand-over leaves no board wider than itself")
		await capture(prefix+"06-delivery")
		await click("skip")
		check(game.state.stage == "complete","the original receipt is turned over")
		check(spilled(game.ui) == 0,"the receipt adds no spilled text")
		check(game.world.sign_boards().is_empty(),
			"the finished counter keeps no board about records the receipt has taken away")
		var paper: Label = null
		for child in game.ui.get_children():
			if child is Label and "回执 · 育苗铺封箱重签" in child.text: paper = child
		check(paper != null and paper.text.contains("红箱挂 5 号 · 蓝箱挂 4 号"),
			"the receipt restates the two tags the player actually hung")
		check(paper != null and fits(paper.text, 18, paper.size.x), "the receipt holds its own paper")
		check(paper != null and Rules.equation(0) in paper.text and Rules.equation(1) in paper.text,
			"the receipt repeats both public records without restyling them")
		check(Rules.equation(0) in game.goal_line() and Rules.equation(1) in game.goal_line(),
			"the goal board, the counter plaques and the receipt spell one equation one way")
		await capture(prefix+"07-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the finished hanging reloads from disk exactly as booked")
		check(not game.buttons.has("reset"),"a finished scene is not reset by an accidental click")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub"),"a standalone launch still finds its way back to the chart")
		await click("next")
		check(game.modal and game.state.stage == "complete","replaying the scene asks first")
		await click("cancel")
		check(game.state.red == 5 and game.state.blue == 4,"cancelling keeps the receipt the player earned")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.red == 0,"replaying the scene rewinds only this station")
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","the same three lines carry the player back to the counter")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","the walk-in still stops before player control")
		await click("fold"); await click("tag_0_5"); await click("tag_1_4")
		check(Rules.solved(game.state),"the mouse path hangs the same two tags")
		await click("reset"); await click("confirm")
		check(game.state.red == 0 and game.state.blue == 0 and game.state.stacked == 1,
			"重摆 puts both tags back on the rack and keeps the folding already done")
		await click("deliver")
		check(game.state.stage == "puzzle" and "红箱的钩子还空着" in game.message,"the cleared table names its own gap")
		await key(KEY_Z)
		check(game.state.red == 5 and game.state.blue == 4,"one undo takes the whole hanging back")
		await capture(prefix+"08-reset-table")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK03 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

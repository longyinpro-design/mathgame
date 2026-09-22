extends SceneTree
# MK06 实窗审计：真实窗口里走一遍「听三段话 → 走到灯芯摊 → 整包上订单 → 越界那一单被如实拒掉
# → 放回摊位（没有幻影花费）→ 凑准 10 根再一次付清 → 抱货与付票 → 挂第一段灯串 → 回执」。
# 在 1280×720 与 960×540 各拍一遍，并检查摊板、订单牌与回执上的汉字有没有爬出自己的边框。
const Scene = preload("res://game/market_mk06.tscn")
const Rules = preload("res://scripts/market/mk06_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk06-packs"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")

# 一次真实的按下-抬起：不等帧，所以看得见宿主 0.28 秒的落下锁。
func tap(id: String) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false,"button unavailable "+id); return
	var b: Control = game.buttons[id]
	var logical = b.get_global_transform_with_canvas()*(b.size/2)
	var point = logical*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
func send(code: int) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
func settle() -> void:
	while game.transient > 0: await process_frame
func click(id: String) -> void:
	tap(id); await process_frame; await settle()
func key(code: int) -> void:
	send(code); await process_frame; await settle()
# 摆好一个动画帧但不暂停，用来拍「抱货中途」那一格。
# 一帧要等两次：process_frame 在节点自己的 _process 之后才发，只等一次就会拿着旧的镜头读数。
func pose(seconds: float) -> void:
	game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	game.world.queue_redraw() # explicit fixture pose while presentation is paused
	# 镜头是 world.progress 的派生值，宿主在自己的 _process 里才换算：先叫它按新进度算一次，
	# 否则个别帧序下读到的是上一帧的旧镜头（整表 pass 里 MK09／MK11 各撞见过一次）。
	game.update_camera()
	await process_frame; await process_frame
func hold(seconds: float) -> void:
	game.paused = true; await pose(seconds)
func fits(text: String, size_px: int, width: float) -> bool:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(size_px)).x)
	return widest <= width
# 汉字不会自动断行：plaque 又从不换行，一行比牌子还宽就直接画到旁边的货上。
func spilled_boards() -> int:
	var over = 0
	for board in game.world.signs():
		var needed := 0.0
		for line in str(board["text"]).split("\n"):
			needed = maxf(needed, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
		if needed > board["rect"].size.x - 20:
			over += 1; print("BOARD ", board["text"], " needs ", needed, " in ", board["rect"].size.x)
	return over
# 摊板、订单牌与货品都画在同一个 1280×720 平面上：谁压住谁只由绘制顺序决定。
func kit_rect(id: String, foot: Vector2, width: float) -> Rect2:
	var item: Dictionary = game.world.parts[id]
	var atlas: Texture2D = game.world.atlases[id]
	var scale = width / atlas.get_width()
	var dims = Vector2(atlas.get_width(), atlas.get_height()) * scale
	return Rect2(foot - Vector2(item.anchor_px[0], item.anchor_px[1]) * scale, dims)
func covered() -> int:
	var over = 0
	var slip = kit_rect("receipt_blank", game.world.paid_slip_foot(), game.world.PAID_SLIP_WIDTH)
	for board in game.world.signs():
		if slip.intersects(board["rect"]): over += 1; print("PAID SLIP covers board ", board["text"])
		if game.receipt_rect().intersects(board["rect"]): over += 1; print("RECEIPT PANEL covers board ", board["text"])
	var sheet = game.receipt_rect()
	if sheet.intersects(slip): over += 1; print("receipt panel covers the paid slip")
	for index in range(Rules.packs_of(game.state.bought)):
		var goods = Rect2(game.world.bakery_foot(index) - Vector2(30,52), Vector2(62,56))
		if sheet.intersects(goods): over += 1; print("receipt panel covers a delivered pack")
	if sheet.intersects(Rect2(game.world.paid_foot() - Vector2(34,34), Vector2(68,38))):
		over += 1; print("receipt panel covers the 收讫 pile")
	for spot in game.world.ticket_spots():
		if sheet.intersects(kit_rect("receipt_blank", spot, game.world.TICKET_WIDTH)):
			over += 1; print("receipt panel covers the ticket box")
	return over
# 汉字不会自动断行，plaque 也不换行；柜台只有一条木板台面，货必须落在里面。
func off_counter() -> int:
	var over = 0
	for kind in range(Rules.KINDS):
		for slot in range(Rules.MAX_PER_KIND):
			var foot = game.world.order_foot(kind, slot)
			if foot.y > game.world.BOARD_FRONT or foot.y < game.world.BOARD_BACK - 6:
				over += 1; print("ROW ", kind, "/", slot, " foot ", foot, " off the counter band")
		var label = game.world.label_rect(kind)
		if label.intersects(Rect2(288, 396, 190, 28)): over += 1; print("row label collides with the order header")
	for index in range(game.world.ticket_spots().size()):
		var spot: Vector2 = game.world.ticket_spots()[index]
		var paper = kit_rect("receipt_blank", spot, game.world.TICKET_WIDTH)
		if paper.position.y < game.world.BOARD_BACK - 2 or paper.end.y > game.world.BOARD_FRONT + 2:
			over += 1; print("TICKET ", index, " at ", paper, " hangs off the counter band")
	return over
func board_with(needle: String) -> String:
	for board in game.world.signs():
		if str(board["text"]).contains(needle): return str(board["text"])
	return ""
func hotspots() -> Array:
	var found: Array = []
	for id in game.buttons:
		if id.begins_with("take_") or id.begins_with("row_"): found.append(id)
	return found
func hotspot_floor() -> int:
	var over = 0
	for id in hotspots():
		var b: Control = game.buttons[id]
		if b.size.x < 48 or b.size.y < 48: over += 1
	return over
func ui_text(needle: String) -> Label:
	for child in game.ui.get_children():
		if child is Label and str(child.text).contains(needle): return child
	return null
# 汉字不会自动断行：一行最短的连续文字比盒子还宽，就会横着画到旁边的货上。
func spilled(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = child.get_combined_minimum_size()
		if needed.x > child.size.x + 1 or needed.y > child.size.y + 1:
			over += 1; print("SPILL ", child.text, " needs ", needed, " in ", child.size)
	return over

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK06 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk06-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.world.scene_id == "street" and game.world.has_part("parcel_large"),
			"the wick stall opens on the shared street kit")
		check(game.state.stage == "arrival" and game.state.order == [0,0,0],
			"opens on the bakery's order, not on a filled board")
		check(game.buttons.next.text == "继续听他们说", "the first beat only asks to keep listening")
		check(spilled(game.ui) == 0,"the opening line fits its own board")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		await click("next"); await click("next")
		check(game.state.stage == "approach","the third line walks the player up to the stall")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		await hold(0.9)
		check(game.world.scale.x > 1.02 and game.world.scale.x < 1.09,"the stall grows on the way over")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready","approach stops before player control")
		await click("next")
		check(game.state.stage == "puzzle","the order board is handed to the player")
		check(game.world.scale.x > 1.09 and game.world.position == Vector2(-64,-43),
			"the sheet is read with the camera closed on the counter")
		var misshapen = 0
		for id in hotspots():
			var want = 96.0 if String(id).begins_with("take_") else 48.0
			if game.buttons[id].size != Vector2(want,want): misshapen += 1; print("HOTSPOT ",id," is ",game.buttons[id].size)
		check(misshapen == 0 and hotspots().size() == Rules.KINDS,
			"the three stall stacks are 96 pixel targets before anything is ordered")
		check(spilled(game.ui) == 0 and spilled_boards() == 0,
			"the empty board's tally and rule boards hold their own text")
		await capture(prefix+"03-board")
		# ---- 落下动画：基类先把已提交的现场交给世界，再问谁落下来 ----
		tap("take_0")
		check(game.transient > 0 and game.world.land_place == "row" and game.world.land_slot == 0,
			"a pack onto the sheet owns the host's landing lock")
		check(game.world.landing("row",0) > 0.0 and game.state.order == [1,0,0],
			"the new pack is caught mid-air while the sheet already lists it")
		await capture(prefix+"04-pack-landing")
		await settle(); await process_frame
		check(game.world.landing("row",0) == 0.0,"the pack comes down onto its row slot")
		await key(KEY_1)
		check(game.state.order == [2,0,0] and game.history.size() == 2,"number keys lay the second four-wick pack")
		await key(KEY_3); await key(KEY_3)
		check(game.state.order == [2,0,2] and game.world.tickets_left() == Rules.BUDGET,
			"the 10-wick trap is writable on paper and still spends nothing")
		check(game.status_line() == "订单 10 根 · 20 / 19 票","the running tally states the overspend")
		check(board_with("合计 10 根 · 20 票") != "","the stall board repeats the over-budget total")
		check(game.buttons.has("row_2_1") and game.buttons.has("row_0_1"),
			"every ordered pack is its own return target")
		check(hotspot_floor() == 0 and spilled_boards() == 0,
			"a full sheet keeps 48 pixel targets and every word inside its own board")
		check(off_counter() == 0,"every pack foot and every ticket lie inside the one wooden counter")
		await capture(prefix+"05-over-budget")
		await click("deliver")
		check(game.state.stage == "puzzle" and game.message == "这单要 20 票，手里只有 19 票。",
			"the stall refuses the over-budget order with the honest reason")
		check(game.state.bought == [0,0,0] and game.world.shown_order() == [2,0,2],
			"a refused submission leaves the sheet as it was and nothing bought")
		await send(KEY_SPACE); await process_frame
		check(game.state.stage == "puzzle" and game.message == "这单要 20 票，手里只有 19 票。",
			"the space-bar submit refuses for the same reason")
		await capture(prefix+"06-refused")
		await click("row_2_1")
		check(game.state.order == [2,0,1] and Rules.tickets_of(game.state.order) == 17,
			"putting a pack back takes it off the bill")
		await key(KEY_E)
		check(game.state.order == [2,0,0] and game.world.tickets_left() == Rules.BUDGET,
			"adding then removing leaves no phantom spend")
		await click("undo")
		check(game.state.order == [2,0,1],"undo takes the loose pack back onto the sheet")
		for n in range(3): await click("hint")
		check(game.state.hint == Rules.HINT_TIERS and "局部便宜" in game.message,
			"the third hint names the 20-ticket trap without giving the plan")
		check(spilled(game.ui) == 0,"the longest hint stays inside its spoken board")
		await click("hint")
		check(game.state.hint == Rules.HINT_TIERS,"hints stop at the shipped tier count")
		await capture(prefix+"07-hints")
		await click("reset")
		check(game.modal and game.state.order == [2,0,1],"重摆 asks before clearing the sheet")
		await capture(prefix+"08-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.order == [2,0,1],"cancelling the reset keeps every pack")
		await click("reset"); await click("confirm")
		check(game.state.order == [0,0,0] and game.state.stage == "puzzle" and game.state.hint == Rules.HINT_TIERS,
			"全部放回摊位 clears the board without spending a ticket or dropping the hints")
		await click("undo")
		check(game.state.order == [2,0,1],"one undo takes the whole clear back")
		await click("reset"); await click("confirm")
		check(game.state.order == [0,0,0],"the sheet is empty again for a fresh plan")
		# ---- 预算内唯一解：1 包四根 + 2 包三根 = 19 票 ----
		await click("take_0"); await key(KEY_2); await key(KEY_2)
		check(game.state.order == [1,2,0] and Rules.solved(game.state)
			and Rules.tickets_of(game.state.order) == Rules.BUDGET,
			"one four-wick pack and two three-wick packs hit 10 for exactly 19")
		await click("row_1_1"); check(game.state.order == [1,1,0],"a click on an ordered pack returns it")
		await key(KEY_2); check(Rules.solved(game.state),"re-taking the pack closes the order again")
		check(spilled_boards() == 0,"the filled board still holds every word inside its own board")
		await capture(prefix+"09-solved-board")
		await click("deliver")
		check(game.state.stage == "purchasing" and game.state.bought == [1,2,0],
			"一次付清 books the whole order as one purchase")
		check(game.buttons.has("pause") and game.buttons.has("skip") and not game.buttons.has("take_0"),
			"the paid sheet switches to the carry")
		await hold(1.1)
		check(game.world.carry_plan(game.world.progress).size() == 3
			and game.world.ticket_plan(game.world.progress).is_empty(),
			"all three packs fly to the bakery before a single ticket moves")
		await capture(prefix+"10-carry")
		await hold(2.3)
		var flying = game.world.ticket_plan(game.world.progress).size()
		check(flying > 0 and flying < Rules.BUDGET
			and game.world.tickets_left() == Rules.BUDGET - flying,
			"the tickets only leave the box after the goods land")
		check(game.world.ticket_plan(game.world.progress)[0]["at"].distance_to(
			game.world.ticket_plan(game.world.progress)[0]["home"]) > 4.0,
			"the paid tickets are on their way to the stall owner, not still in the box")
		check(board_with("筹票匣 · 剩 %d 张" % (Rules.BUDGET - flying)) != "" and flying > 0,
			"the ticket box board counts down with the tickets already in the air")
		check(off_counter() == 0,"the half-empty ticket box still lies on the wooden counter")
		await capture(prefix+"11-tickets")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the purchase mid-flight")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "delivery" and game.world.tickets_left() == 0,
			"the string goes up with an empty ticket box")
		await hold(1.4); await capture(prefix+"12-string-rise")
		await hold(2.6)
		check(game.world.state == game.state,"the world draws the committed state it was handed")
		await capture(prefix+"13-string-lit")
		await click("skip")
		check(game.state.stage == "complete" and game.state.bought == [1,2,0],
			"the first warm string closes the scene")
		check(game.buttons.next.text == "重新体验" and game.buttons.has("open_hub"),
			"a standalone sample offers its own way back to the chart")
		var receipt = ui_text("灯芯订单已付清")
		check(receipt != null and receipt.text.contains("4 根一包 ×1 → 4 根 · 7 票")
			and receipt.text.contains("3 根一包 ×2 → 6 根 · 12 票"),
			"the receipt restates the packs the player actually bought")
		check(receipt != null and receipt.text.contains("合计 10 根 · 用去 19 票")
			and receipt.text.contains("手里筹票 0 张"),"the receipt closes the account to the last ticket")
		check(receipt != null and fits(receipt.text, 16, receipt.size.x),"the receipt holds its own paper")
		var stacked := 0.0
		for row in range(receipt.get_line_count()): stacked += receipt.get_line_height(row)
		check(receipt.get_line_count() == game.receipt_lines().size()
			and receipt.position.y + stacked <= game.receipt_rect().end.y,
			"every receipt line is written on the paper, none hangs off its bottom edge")
		check(spilled(game.ui) == 0,"the receipt adds no spilled text")
		check(spilled_boards() == 0,"the closed street holds every board's own text")
		check(covered() == 0,"the paid slip and the receipt panel cover no board, pack or pile")
		await capture(prefix+"14-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the paid order reloads from disk exactly as booked")
		check(game.state.stage == "complete" and not game.buttons.has("reset"),
			"a finished scene is not reset by an accidental click")
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
		check(game.state.bought == [1,2,0],"cancelling keeps the paid receipt the player earned")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.order == [0,0,0] and game.state.hint == 0,
			"replaying the scene rewinds only this stall")
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","the same three lines carry the player back to the stall")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","the walk-in still stops before player control")
		await click("take_0"); await click("take_1"); await click("take_1")
		check(Rules.solved(game.state),"the mouse path builds the same 19-ticket order")
		await click("reset"); await click("confirm")
		check(game.state.order == [0,0,0],"全部放回摊位 clears the mouse-built sheet too")
		check(spilled(game.ui) == 0 and spilled_boards() == 0,"the replayed board adds no spilled text")
		await capture(prefix+"15-replay-board")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK06 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

extends SceneTree
# MK08 实窗审计：真实窗口里走一遍「听四段话 → 走上老货栈门前 → 把合计拨到 13 却被逐条点名
# → 请扣扣提醒 → 撤下重复抄件、钉上漏掉的绿单、换算箱与瓶 → 整块板一次归档 → 一行一行盖讫
# → 归档回执」。在 1280×720 与 960×540 各拍一遍，并检查木牌、回执与台词板上的汉字有没有爬出自己的边框。
const Scene = preload("res://game/market_mk08.tscn")
const Rules = preload("res://scripts/market/mk08_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
# 衡伯那块有毛病的板：红单的抄件钉了两回，绿单一次都没上板。
const START = [[0, 6, 1], [1, 4, 1], [0, 6, 1]]
# 假修法：只把重复那一行拨到 3 瓶，合计照样是 13 瓶。
const TRAP = [[0, 6, 1], [1, 4, 1], [0, 3, 1]]
# 钉上绿单却还没换算箱与瓶的样子：数目已经对上，写法还没有。
const BOXED = [[0, 6, 1], [1, 4, 1], [2, 1, 0]]
const SOLVED = [[0, 6, 1], [1, 4, 1], [2, 3, 1]]
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk08-oil"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
# 一次真实的按下-抬起：不等帧，所以能看见宿主 0.28 秒的落纸锁。
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
# 摆好一个动画帧但不暂停：filing 与 delivery 的中间格只有在这里才拍得到。
func pose(seconds: float) -> void:
	game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	game.world.queue_redraw() # explicit fixture pose while presentation is paused
	# 镜头是 world.progress 的派生值，宿主在自己的 _process 里才换算：先叫它按新进度算一次，
	# 否则个别帧序下读到的是上一帧的旧镜头（整表 pass 里 MK09／MK11 各撞见过一次）。
	game.update_camera()
	await process_frame
func hold(seconds: float) -> void:
	game.paused = true; await pose(seconds)
# 镜头是 smoothstep 插值出来的，实窗只要求停在设计位上（浮点相等不作数）。
func at_camera(scale_x: float, at: Vector2) -> bool:
	return absf(game.world.scale.x - scale_x) < 0.002 and game.world.position.distance_to(at) < 0.1
func widest_line(text: String, size_px: int) -> float:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(size_px)).x)
	return widest
func fits(text: String, size_px: int, width: float) -> bool:
	return widest_line(text, size_px) <= width
# 街面上的木牌由 plaque 直接画字，从不换行：一行比牌子还宽就爬到旁边的货上。
func spilled_boards() -> int:
	var over = 0
	for board in game.world.signs():
		var px := UIStyle.text_size(int(board["size_px"]) if board.has("size_px") else 16)
		var needed := 0.0
		for line in str(board["text"]).split("\n"):
			needed = maxf(needed, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
			if px > board["rect"].size.y:
				over += 1; print("BOARD too short for ", px, "px: ", board["text"], " in ", board["rect"].size.y)
		if needed > board["rect"].size.x - 20:
			over += 1; print("BOARD ", board["text"], " needs ", needed, " in ", board["rect"].size.x)
	return over
func board_with(needle: String) -> String:
	for board in game.world.signs():
		if str(board["text"]).contains(needle): return str(board["text"])
	return ""
func hotspots() -> int:
	var live = 0
	for id in game.buttons:
		if not id.begins_with("pin_") and not id.begins_with("chip_") \
			and not id.begins_with("less_") and not id.begins_with("more_") \
			and not id.begins_with("unit_"): continue
		var b: Control = game.buttons[id]
		if b.size.x < 48 or b.size.y < 48: print("SMALL target ", id, " ", b.size)
		else: live += 1
	return live
func ui_text(needle: String) -> Label:
	for child in game.ui.get_children():
		if child is Label and str(child.text).contains(needle): return child
	return null
# 盒子挡不住溢出：Godot 会把 Control.size 抬到内容的最低尺寸，字照样长在纸外。
# 所以拿标签的实际方框去比它脚下那块板（台词板也算），板边之外一个字都不许有。
func off_board() -> int:
	var over = 0
	for child in game.ui.get_children():
		if not child is Label or child.text.is_empty(): continue
		var box = Rect2(child.position, child.size)
		for other in game.ui.get_children():
			if not other is Panel: continue
			var board = Rect2(other.position, other.size)
			if not board.has_point(box.position): continue
			if box.end.y > board.end.y + 3 or box.end.x > board.end.x + 3:
				over += 1
				print("OFFBOARD ", child.text.replace("\n"," / "), " box ", box,
					" min ", child.get_combined_minimum_size(), " board ", board)
	return over
# 归档回执与街面实物、木牌、出口按钮都在同一个逻辑平面上：谁压住谁只由矩形相交决定。
# 木牌要按当前镜头换算到屏幕坐标——puzzle/filing 把街景抬到 1.10，牌子会整体下压，
# 只看未放大坐标就会漏掉「木牌钻进口述板底下」这一类真机才看得见的遮挡。
func on_screen(rect: Rect2) -> Rect2:
	var xf: Transform2D = game.world.get_global_transform_with_canvas()
	var a = xf*rect.position
	var b = xf*(rect.position+rect.size)
	return Rect2(a, b-a)
func papers() -> Array:
	var list := []
	for child in game.ui.get_children():
		if child is Panel: list.append(Rect2(child.position, child.size))
	return list
func covered() -> int:
	var over = 0
	for board in game.world.signs():
		var shown: Rect2 = on_screen(board["rect"])
		for paper in papers():
			if paper.intersects(shown):
				over += 1; print("COVERED board ", board["text"], " by paper ", paper, " at ", shown)
	if game.state.stage != "complete": return over
	# 回执只在收单那一格摊开：它压到原单、板行、收货台或出口按钮，就是收尾画面被自己挡住。
	var sheet: Rect2 = game.receipt_rect()
	for order in range(Rules.ORDERS):
		var ticket: Rect2 = on_screen(game.world.ticket_rect(order))
		if ticket.intersects(sheet):
			over += 1; print("COVERED ticket ", Rules.NAMES[order], " by receipt ", sheet)
	# 板上的三行连货样带背景条：回执压到任何一行都算。
	for row in range(Rules.LINES):
		var strip: Rect2 = on_screen(Rect2(game.world.row_foot(row) - Vector2(40, 34), Vector2(730, 48)))
		if strip.intersects(sheet):
			over += 1; print("COVERED board row ", row + 1, " by receipt ", sheet)
	var dock: Rect2 = on_screen(Rect2(game.world.dock_foot() - Vector2(120, 96), Vector2(240, 136)))
	if dock.intersects(sheet):
		over += 1; print("COVERED dock goods by receipt ", sheet)
	for id in ["next","open_hub","back_hub"]:
		if not game.buttons.has(id): continue
		if sheet.intersects(Rect2(game.buttons[id].position, game.buttons[id].size)):
			over += 1; print("COVERED exit ", id, " by receipt ", sheet)
	return over
# 「讫」是这一关的收尾画面：任何一块常驻木牌都不许盖在它头上。
func stamp_covered() -> int:
	var over = 0
	for row in game.world.stamped(game.world.progress):
		var mark := Rect2(game.world.row_foot(row) + Vector2(76, -30), Vector2(38, 32))
		for board in game.world.signs():
			if board["rect"].intersects(mark):
				over += 1; print("COVERED 讫 row ", row + 1, " by ", board["text"], " ", board["rect"])
	return over

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK08 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk08-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.world.scene_id == "street" and game.world.has_part("oil_bottle")
			and game.world.has_part("crate_red"),"the old warehouse opens on the shared street kit")
		check(game.state.stage == "arrival" and game.state.lines == START
			and game.state.filed == Rules.empty_lines(),
			"the scene opens on 衡伯's own board: 红 6 · 蓝 4 · 红 6, nothing filed yet")
		check(Rules.total_of(game.state.lines) == Rules.BOOKED and Rules.RECEIVED == 13,
			"the board adds up to 16 while the dock received 13, and the two numbers are separate")
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"the first beat only asks to keep listening")
		check(off_board() == 0,"the two-line opening dialogue stays inside its own board")
		check(spilled_boards() == 0,"the warehouse holds every board's own text")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1 and "红 6、蓝 4、红 6" in game.line()
			and "一张一张也对不平" in game.line(),
			"the second line names the duplicated copy and the missing ticket before the counter opens")
		await click("next")
		check("同一只手" in game.line() and "又写漏了一张" in game.line(),
			"扣扣 asks whether the extra three and the missing three are one mistake")
		await click("next")
		check(game.state.beat == Rules.BEATS - 1 and game.buttons.next.text == "走到柜台前",
			"the fourth line is the one that walks the player in")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"the walk-in animates the rack, the board and the dock")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		await hold(0.9)
		check(game.world.scale.x > 1.0 and game.world.scale.x < 1.10,"the street closes in on the way over")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready","the walk-in stops before player control")
		check(game.buttons.next.text == "开始归档","the briefing explains the click order")
		await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"the board is handed to the player under the closed camera")
		check(hotspots() == Rules.ORDERS * 5,
			"three tickets and three rows of four targets, each 48 pixels or bigger, are live")
		check(game.status_line() == "板上 16 瓶 · 码头实收 13 瓶",
			"the running tally shows the two sides of the argument, not a verdict")
		check(board_with("点收 13 瓶") != "" and board_with("本板按瓶记") != ""
			and board_with("单号顺序 红 蓝 绿") != "",
			"the dock count, the unit and the ticket order are carved in the street, not only in dialogue")
		check(board_with("红单 · 2 箱 × 每箱 3 瓶") != "" and board_with("蓝单 · 4 散瓶") != ""
			and board_with("绿单 · 1 箱 × 每箱 3 瓶") != "","each original ticket states its own goods")
		check(game.state.hint == 0 and off_board() == 0 and spilled_boards() == 0,
			"the open board holds every line inside its own wood")
		check(covered() == 0,"the closed camera keeps every street board clear of the dialogue and goal boards")
		await capture(prefix+"03-board")
		# ---- 假修法：把重复那一行拨到 3 瓶，合计正好 13，仍然一块板都归不了档 ----
		for _n in range(3): await click("less_2")
		check(game.state.lines == TRAP and Rules.total_of(game.state.lines) == Rules.RECEIVED,
			"the player can make the total read 13 by rewriting the duplicate row")
		check(game.status_line() == "板上 13 瓶 · 码头实收 13 瓶","both sides now say 13 bottles")
		check(not Rules.solved(game.state),"and the board is still wrong")
		await capture(prefix+"04-total-fixed")
		await click("deliver")
		var complaints = Rules.shortfalls(game.state)
		check(complaints.size() == 3 and game.state.stage == "puzzle",
			"the matching total is refused with one named complaint per row")
		check("第 3 行" in game.message and "重复抄件" in game.message and "还有 2 处" in game.message,
			"the first complaint names the duplicated copy and says how many are left")
		check(game.state.lines == TRAP,"a refused filing changes nothing on the board")
		check(off_board() == 0,"the three-complaint report stays inside the dialogue board")
		await capture(prefix+"05-refused")
		for _n in range(3): await key(KEY_Z)
		check(game.state.lines == START,"undo takes the padded total back row by row")
		await click("deliver")
		var rows_left = Rules.shortfalls(game.state)
		check(rows_left.size() == 2 and "重复抄件" in game.message and "还有 1 处" in game.message,
			"the first complaint names the duplicate and says one more row is out of place")
		check("绿单" in rows_left[1] and "一次都没上板" in rows_left[1],
			"the very next complaint names the ticket that never reached the board")
		for _n in range(4): await click("hint")
		check(game.state.hint == Rules.HINTS,"hints stop at the shipped tier count")
		check(game.state.lines == START and Rules.total_of(game.state.lines) == Rules.BOOKED,
			"a hint explains the board without moving a single copy")
		await capture(prefix+"06-hints")
		# ---- 真修法：撤下重复抄件 → 从架上钉上漏掉的绿单 → 换算箱与瓶 ----
		await key(KEY_E)
		check(game.state.lines == [[0, 6, 1], [1, 4, 1], [-1, 0, 1]],"撤下 leaves row 3 empty")
		check(Rules.free_rows(game.state.lines) == [2],"the freed row is the drop target now")
		tap("pin_2")
		check(game.transient > 0 and game.world.land_place == "line" and game.world.land_slot == 2,
			"the new copy owns the host's landing lock")
		check(game.world.landing("line",2) > 0.5,"the copy is caught mid-air above the row")
		check(game.buttons.pin_0.disabled and game.buttons.unit_2.disabled,
			"the board cannot be edited while a copy lands")
		await capture(prefix+"07-copy-landing")
		await settle()
		check(game.state.lines == BOXED and game.world.landing("line",2) == 0.0,
			"the copy seats itself: 绿单 written as its ticket says, 1 箱")
		check(not game.buttons.chip_2.disabled,"the board opens again the frame it lands")
		check(Rules.total_of(game.state.lines) == Rules.RECEIVED and not Rules.solved(game.state),
			"13 bottles by value, and the board still cannot be filed")
		await click("deliver")
		check("箱不是瓶" in game.message and game.state.stage == "puzzle",
			"the unit is the last thing standing between the board and the dock")
		await capture(prefix+"08-unit-boxes")
		await key(KEY_D)
		check(game.state.lines == SOLVED and Rules.solved(game.state),
			"换算 writes the same goods as 3 瓶 and the three tickets are each on the board once")
		check(Rules.total_of(game.state.lines) == Rules.RECEIVED,
			"the conversion changes the writing, never the count")
		check(game.status_line() == "板上 13 瓶 · 码头实收 13 瓶","the tally reads 13 for the right reason")
		await click("reset")
		check(game.modal and game.state.lines == SOLVED,"全部撤下 asks before clearing the board")
		await capture(prefix+"09-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.lines == SOLVED,"cancelling keeps the filed-ready board")
		await click("reset"); await click("confirm")
		check(game.state.lines == Rules.empty_lines() and game.state.filed == Rules.empty_lines(),
			"clearing the board pins nothing and files nothing")
		check(not game.buttons.undo.disabled,"an emptied board still has one step to take back")
		await key(KEY_Z)
		check(game.state.lines == SOLVED,"one undo puts the whole board back")
		check(game.world.state == game.state,"the world reads the committed board it was handed")
		await capture(prefix+"10-solved")
		await click("deliver")
		check(game.state.stage == "filing" and game.state.filed == SOLVED and game.state.lines == SOLVED,
			"the whole board is filed in one commit, not one row at a time")
		check(game.buttons.has("skip") and not game.buttons.has("chip_0"),
			"the filing takes the board away and keeps its own controls")
		await hold(1.2)
		var plan = game.world.filing_plan(game.world.progress)
		check(plan.size() == 2 and plan[0]["mode"] == "out" and plan[0]["order"] == 0,
			"the duplicate copy leaves row 3 for the paper basket")
		check(plan[1]["mode"] == "in" and plan[1]["order"] == 2,
			"the missing ticket flies back onto the board in the same beat")
		check(game.world.hide_while_moving(plan).size() == 2,
			"the row being rewritten is hidden while its copies are in the air")
		check(game.world.stamped(game.world.progress).is_empty(),
			"nothing is stamped off at the dock before the hand-over starts")
		await capture(prefix+"11-filing")
		# 两半张抄件在前半程就落位了：后半程还把它们当在飞的件，`draw_board()` 会为让位把整行藏掉，
		# 归档动画有一半时长板面上是缺货的——11-filing 拍到的就是这个空档。
		# `hold()` 的秒数是这一格的绝对时刻，从 1.2 再往前走到 1.7（归档共 2.8 秒，进度已过 0.5）。
		await hold(1.7)
		var settled = game.world.filing_plan(game.world.progress)
		check(settled.is_empty() and game.world.hide_while_moving(settled).is_empty()
			and not game.world.line_goods(2, game.world.board()).is_empty()
			and covered() == 0,
			"the rewrite has landed: the row keeps its own goods and no street board hides them")
		await capture(prefix+"11b-filing-settled")
		await click("skip")
		check(game.state.stage == "delivery" and game.state.filed == SOLVED,
			"the filed board goes out to the dock as one record")
		await hold(1.6)
		check(game.world.stamped(game.world.progress).size() == 2
			and game.world.dock_count() == 10,
			"two rows are stamped off and the dock counts those rows, not the old 16")
		check(board_with("点收中 10/13 瓶") != "" and spilled_boards() == 0,
			"the dock board reads 已点收 / 实收 while the stamps are still landing, inside its own wood")
		check(stamp_covered() == 0,"the two rows signed off at the dock are not hidden by any street board")
		check(board_with("换算") == "","the frozen board stops advertising controls it can no longer take")
		check(game.state.stage == "delivery","the scene is still mid-hand-over")
		await capture(prefix+"12-stamping")
		game.paused = false; await create_timer(0.12).timeout
		paused_at = game.elapsed
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(0.12).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the stamps mid-row")
		check(game.buttons.pause.text == "继续动画","the frozen hand-off offers to resume")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "complete" and game.world.dock_count() == Rules.RECEIVED,
			"the stamped board closes with all 13 bottles handed over")
		check(game.world.stamped(0.0) == [0,1,2] and board_with("点收 13 瓶") != "",
			"the dock board reads 13 once every row is signed")
		check(stamp_covered() == 0,"all three 讫 stamps stay visible on the closed board")
		check(board_with("红单 · 2 箱") == "","the receipt takes over the three ticket boards, not doubles them")
		var paper = ui_text("归档回执")
		check(paper != null and "红单 2 箱 = 6 瓶" in paper.text and "蓝单 4 散瓶 = 4 瓶"
			and "绿单 1 箱 = 3 瓶" in paper.text,"the receipt restates the three tickets, not the copies")
		check(paper != null and "合计 13 瓶 · 码头实收 13 瓶" in paper.text,
			"the receipt totals what the player filed")
		check(paper != null and "撤下重复抄件 1 张" in paper.text
			and "补回漏掉的单号 1 个" in paper.text,"the receipt counts what actually changed on the board")
		check(paper != null and fits(paper.text, 16, paper.size.x),"the filing receipt holds its own paper")
		if paper != null and not fits(paper.text, 16, paper.size.x):
			print("DIAG sheet needs ", paper.get_combined_minimum_size(), " in ", paper.size,
				" widest ", widest_line(paper.text, 16))
		check(paper != null and paper.get_theme_font_size("font_size") >= 18,
			"the receipt keeps the house minimum type size")
		check(off_board() == 0 and spilled_boards() == 0,"the receipt adds no text outside its own board")
		check(covered() == 0,"the receipt covers no ticket, board, goods or button")
		await capture(prefix+"13-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the filed board reloads from disk exactly as filed")
		check(game.state.filed == SOLVED and not game.buttons.has("reset"),
			"a reload keeps the filing record and cannot be reset by an accidental click")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		var back: Control = game.buttons.back_hub
		check(back.size.x >= 48 and back.size.y >= 48,"the way back to the chart is a 48 pixel target or bigger")
		if not small: await capture("14-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"a standalone launch still finds its own way back to the chart")
		await click("next")
		check(game.modal and game.state.stage == "complete","replaying the scene asks first")
		await click("cancel")
		check(game.state.lines == SOLVED,"cancelling keeps the receipt the player filed")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.lines == START
			and game.state.filed == Rules.empty_lines() and game.state.hint == 0,
			"重新体验 rewinds this board, 衡伯's original rows included")
		await click("next"); await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","the same four lines carry the player back to the board")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","the walk-in still stops before player control")
		await click("chip_2"); await click("pin_2"); await click("unit_2")
		check(game.state.lines == SOLVED and Rules.solved(game.state),
			"撤下、钉单、换算 in mouse order refile the same three rows")
		await click("deliver"); await click("skip"); await click("skip")
		check(game.state.stage == "complete" and game.world.dock_count() == Rules.RECEIVED,
			"the replayed board closes with the same 13 bottles handed over")
		check("撤下重复抄件 1 张" in ui_text("归档回执").text,
			"and the receipt restates the one copy the player actually removed")
		check(off_board() == 0 and spilled_boards() == 0 and covered() == 0,
			"the replayed receipt adds no spilled or covered text")
		await capture(prefix+"15-replay-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK08 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

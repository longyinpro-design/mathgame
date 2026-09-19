extends SceneTree
# MK07 实窗审计：真实窗口里走一遍「听四段话 → 走上街头 → 一件一件预定 → 整批试交被如实拒掉
# → 请扣扣提醒 → 全部收回柜台与撤销 → 排准唯一那份匹配 → 交货与入户 → 分配单」。
# 在 1280×720 与 960×540 各拍一遍，并检查摊板、分配单与台词板上的汉字有没有爬出自己的边框。
const Scene = preload("res://game/market_mk07.tscn")
const Rules = preload("res://scripts/market/mk07_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const EMPTY = [-1, -1, -1, -1]
# 贪心陷阱：把布先给当面开口要的帆匠，医护就再没有东西可用。
const TRAP = [2, 0, 3, 1]
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk07-goods"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
# 一次真实的按下-抬起：不等帧，所以能看见宿主 0.28 秒的落下锁。
func tap(id: String) -> void:
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false,"button unavailable "+id); return
	var b: Control = game.buttons[id]
	var logical = b.get_global_transform_with_canvas()*(b.size/2)
	var point = logical*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
func send(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
func settle() -> void:
	while game.transient > 0: await process_frame
func click(id: String) -> void:
	tap(id); await process_frame; await settle()
func key(code: int) -> void:
	send(code); await process_frame; await settle()
func promise(good: int, person: int) -> void:
	await click("good_%d"%good); await click("person_%d"%person)
# 摆好一个动画帧但不暂停，用来拍「四件货在半空」这一格。
func pose(seconds: float) -> void:
	game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
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
# 汉字不会自动断行：plaque 又从不换行，一行比木牌还宽就直接画到旁边的货上。
func spilled_boards() -> int:
	var over = 0
	for board in game.world.signs():
		var px := UIStyle.text_size(int(board["size_px"]))
		var needed := 0.0
		for line in str(board["text"]).split("\n"):
			needed = maxf(needed, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
			if px > board["rect"].size.y:
				over += 1; print("BOARD too short for ", px, "px: ", board["text"], " in ", board["rect"].size.y)
		if needed > board["rect"].size.x - 20:
			over += 1; print("BOARD ", board["text"], " needs ", needed, " in ", board["rect"].size.x)
	return over
# 街面上的木牌、货物与出口按钮都在同一个 1280×720 平面上：谁压住谁只由矩形相交决定。
func paper_rects() -> Array:
	var papers := []
	for child in game.ui.get_children():
		if child is Panel and child.position.y > 170: papers.append(Rect2(child.position, child.size))
	return papers
func covered_boards() -> int:
	var over = 0
	for board in game.world.signs():
		for paper in paper_rects():
			if paper.intersects(board["rect"]):
				over += 1; print("COVERED board ", board["text"], " by paper ", paper)
	for good in range(Rules.COUNT):
		for paper in paper_rects():
			if paper.intersects(game.world.good_rect(good)):
				over += 1; print("COVERED good ", good, " by paper ", paper)
	for id in ["next","open_hub","back_hub","leave_hub"]:
		if not game.buttons.has(id): continue
		for paper in paper_rects():
			if paper.intersects(Rect2(game.buttons[id].position, game.buttons[id].size)):
				over += 1; print("COVERED exit ", id, " by paper ", paper)
	return over
func board_with(needle: String) -> String:
	for board in game.world.signs():
		if str(board["text"]).contains(needle): return str(board["text"])
	return ""
# 一件货在同一时刻只能出现在一个地方：落位之前只在演出里，落位之后只在居民手里。
func in_hands() -> int:
	var landed = 0
	for person in range(Rules.COUNT):
		if game.world.at_hand(person): landed += 1
	return landed
func in_air() -> int:
	var flying = 0
	for entry in game.world.carry_plan(game.world.progress):
		if float(entry["phase"]) < 1.0: flying += 1
	return flying
func hotspots() -> int:
	var live = 0
	for id in game.buttons:
		if not id.begins_with("good_") and not id.begins_with("person_"): continue
		var b: Control = game.buttons[id]
		if b.size.x < 48 or b.size.y < 48: print("SMALL target ", id, " ", b.size)
		else: live += 1
	return live
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
# 盒子挡不住溢出：Godot 会把 Control.size 抬到内容的最低尺寸，字照样长在纸上。
# 所以只能拿标签的实际方框去比它脚下那张纸，纸边之外一个字都不许有。
# 顶部那三条台词板归宿主 level_host 排版（y<170），这里只量关卡自己摊开的单据。
func off_paper() -> int:
	var papers := []
	for child in game.ui.get_children():
		if child is Panel and child.position.y > 170: papers.append(Rect2(child.position, child.size))
	var over = 0
	for child in game.ui.get_children():
		if not child is Label or child.text.is_empty(): continue
		var box = Rect2(child.position, child.size)
		for paper in papers:
			if not paper.has_point(box.position): continue
			if not paper.grow(-2.0).encloses(box):
				over += 1
				print("OFFPAPER ", child.text.replace("\n"," / "), " box ", box,
					" min ", child.get_combined_minimum_size(), " paper ", paper)
	return over

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK07 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk07-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.world.scene_id == "street" and game.world.has_part("brass_bell"),
			"the aid street opens on the shared street kit")
		check(game.state.stage == "arrival" and game.state.plan == EMPTY and game.state.failed == [],
			"opens on four unassigned goods, with no trial booked yet")
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"the first beat only asks to keep listening")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		await click("next")
		check("只有铃" in game.line() and "只有布" in game.line(),
			"the two households that can use only one thing say so before the counter opens")
		await click("next")
		check(game.state.beat == Rules.BEATS - 1 and game.buttons.next.text == "走上前去",
			"the fourth line is the one that walks the player in")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"the walk-in animates the four stalls")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		await hold(0.9)
		check(game.world.scale.x > 1.0 and game.world.scale.x < 1.10,"the street closes in on the way over")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready","the walk-in stops before player control")
		check(game.buttons.next.text == "开始分配","the briefing explains the click order")
		await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"the counter is handed to the player under the closed camera")
		check(hotspots() == Rules.COUNT * 2,"eight goods-and-stalls targets of 48 pixels or bigger are live")
		check(spilled(game.ui) == 0 and spilled_boards() == 0,
			"the empty street holds every board's own text")
		check(board_with("只能用布") != "" and board_with("能用绳或钉") != "",
			"each household's own limits are carved on its board, not only in the dialogue")
		await capture(prefix+"03-counter")
		# ---- 落下动画：宿主先把已提交的现场交给世界，再问谁落下来 ----
		await click("good_2")
		check(game.picked == 2 and game.state.plan == EMPTY,"picking the cloth moves no goods")
		check(game.transient == 0.0,"picking a good does not take the landing lock")
		tap("person_0")
		check(game.state.plan == [2,-1,-1,-1] and game.picked == -1,"the cloth is promised to 帆匠")
		check(game.transient > 0 and game.world.land_place == "hand" and game.world.land_slot == 0,
			"a promise owns the host's landing lock")
		check(game.world.landing("hand",0) > 0.5,"the promised shadow is caught mid-air above the stall")
		check(game.buttons.good_0.disabled and game.buttons.person_0.disabled,"the street cannot be edited while it lands")
		await capture(prefix+"04-first-drop")
		await settle()
		check(game.world.landing("hand",0) == 0.0 and game.world.landing("hand",1) == 0.0,
			"the shadow seats itself and only that one stall glows")
		check(not game.buttons.person_0.disabled,"the counter opens again the frame it lands")
		await key(KEY_4); await key(KEY_E)
		check(game.state.plan == [2,-1,3,-1],"number and letter keys hand the bell to 乐手")
		await key(KEY_1); await key(KEY_W)
		await key(KEY_2); await key(KEY_R)
		check(game.state.plan == TRAP and Rules.complete_plan(game.state) and not Rules.solved(game.state),
			"the greedy plan fills all four households and still strands 医护")
		check(game.status_line() == "已分 4/4 · 台面 0 件","the running tally counts promises, not deliveries")
		check(spilled_boards() == 0,"four promised goods keep every board inside its own wood")
		await capture(prefix+"05-trap-set")
		await click("deliver")
		check(game.state.stage == "handover","a complete-but-wrong plan is still tried as one batch")
		check(game.buttons.has("skip") and not game.buttons.has("good_0"),
			"the hand-over takes the counter away and keeps its own controls")
		await hold(1.12)
		var flown = game.world.carry_plan(game.world.progress)
		var closest := 9999.0
		for i in range(flown.size()):
			for j in range(i + 1, flown.size()): closest = minf(closest, flown[i]["at"].distance_to(flown[j]["at"]))
		check(flown.size() == Rules.COUNT and closest >= 20.0 and in_hands() == 0,
			"all four goods leave the counter together, a piece apart, none of them home yet")
		await capture(prefix+"06-handover-flight")
		await hold(1.88)
		check(in_hands() == 3 and in_air() == 1,
			"the batch arrives household by household, the last one still on its way")
		await capture(prefix+"07-handover-landing")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the hand-over mid-flight")
		await click("skip")
		check(game.state.stage == "puzzle" and game.state.plan == TRAP and game.state.failed == [TRAP],
			"the failed trial keeps the plan on the street and books itself as evidence")
		check(game.state.hint == 0 and Rules.assigned(game.state) == Rules.COUNT,
			"a refused batch costs no goods and no hints")
		check(game.has_report() and "医护还没有能用的布" in game.line() and "布在帆匠手里" in game.line(),
			"the stall answers a wrong batch with the real gap, not with the answer")
		await capture(prefix+"08-shortfall")
		check(board_with("还缺：布") != "" and board_with("预定：布") != "",
			"医护's board names what is missing while 帆匠's keeps what he was promised")
		check(spilled(game.ui) == 0 and spilled_boards() == 0,
			"the shortfall report adds no text outside its own box")
		# 台词板归宿主排版（Rect2(338,98,826,68) 只装得下一行 22 号字），关卡能负责的只有横向：
		# 两行回执的每一行都必须留在板子宽度之内，否则汉字会直接爬到旁边的货上。
		check(fits(game.line(), 20, 798.0),"the honest report stays inside the width of the line board")
		await key(KEY_Z)
		check(game.state.plan == [2,0,3,-1] and game.state.failed == [TRAP],
			"undo rewinds the last promise but keeps the failed trial on record")
		await click("deliver")
		check(game.state.stage == "puzzle" and game.message == "医护还没有分到东西：只能用布。",
			"an incomplete batch is refused in 扣扣's own words while the street stays editable")
		await send(KEY_SPACE); await process_frame
		check(game.state.stage == "puzzle" and game.message == "医护还没有分到东西：只能用布。",
			"the space-bar hand-over refuses for the same reason")
		await capture(prefix+"09-refused")
		for n in range(3): await click("hint")
		check(game.state.hint == Rules.HINTS and "布已经归医护" in game.message,
			"the third hint states the whole ordering without touching the goods")
		await click("hint")
		check(game.state.hint == Rules.HINTS,"hints stop at the shipped tier count")
		await capture(prefix+"10-hints")
		# ---- 鼠标路径：把贪心的方案一件件改回唯一那份匹配 ----
		await click("person_0")
		check(game.state.plan == [-1,0,3,-1],"clicking a promised resident takes his good back to the counter")
		await click("good_2"); await click("person_3")
		check(game.state.plan == [-1,0,3,2],"the cloth goes to the household that can only use it")
		await click("good_1"); await click("person_1")
		check(game.state.plan == [-1,1,3,2],"the nails take the bridge mender's place")
		await click("good_0"); await click("person_1")
		check(game.state.plan == [-1,0,3,2] and Rules.free_goods(game.state) == [1],
			"handing a resident a second good sends the first back without a word")
		await click("good_1"); await click("person_1"); await click("good_0"); await click("person_0")
		check(game.state.plan == Rules.SOLUTION and Rules.solved(game.state),
			"the mouse path closes the only matching that satisfies all four")
		await click("reset")
		check(game.modal and game.state.plan == Rules.SOLUTION,"全部收回柜台 asks before clearing the street")
		await capture(prefix+"11-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.plan == Rules.SOLUTION and game.state.failed == [TRAP],
			"cancelling keeps the plan and the failed trial that earned it")
		await click("reset"); await click("confirm")
		check(game.state.plan == EMPTY and game.state.failed == [TRAP],
			"clearing the table never clears the record")
		check(not game.buttons.undo.disabled,"an emptied street still has one step to take back")
		await key(KEY_Z)
		check(game.state.plan == Rules.SOLUTION,"one undo puts the whole matching back")
		check(game.world.state == game.state,"the world reads the committed state it was handed")
		check(spilled_boards() == 0,"the corrected street still holds its boards")
		await capture(prefix+"12-solved")
		await click("deliver")
		check(game.state.stage == "handover" and game.state.plan == Rules.SOLUTION,
			"the corrected batch goes out as one hand-over")
		await hold(1.12); await click("skip")
		check(game.state.stage == "delivery" and game.state.failed == [TRAP],
			"the accepted batch is booked and the trial record stays")
		await hold(1.2)
		check(game.world.scale.x > 1.05 and board_with("已收：绳") != "",
			"the delivery starts at the counter with the goods in hand")
		await capture(prefix+"13-delivery-counter")
		await hold(4.0)
		check(at_camera(1.0, Vector2.ZERO) and in_hands() == Rules.COUNT,
			"the street widens back to all four households once the goods are settled")
		await capture(prefix+"14-delivery-street")
		await click("skip")
		check(game.state.stage == "complete" and game.state.plan == Rules.SOLUTION and game.state.failed == [TRAP],
			"the finished street still carries the trial it made")
		check(game.buttons.next.text == "重新体验" and game.buttons.has("open_hub"),
			"a standalone sample offers its own way back to the chart")
		var paper = ui_text("分配单")
		check(paper != null and paper.text.contains("帆匠 ← 绳") and paper.text.contains("医护 ← 布")
			and paper.text.contains("乐手 ← 铃"),"the sheet restates the four promises actually kept")
		check(paper != null and "第一次试交：布给了帆匠" in paper.text
			and "医护那时还没有能用的布" in paper.text,
			"the finished sheet names the failed first trial instead of rewriting history")
		check(paper != null and fits(paper.text, 16, paper.size.x),"the allocation sheet holds its own paper")
		if paper != null and not fits(paper.text, 16, paper.size.x):
			print("DIAG sheet needs ", paper.get_combined_minimum_size(), " in ", paper.size,
				" widest ", widest_line(paper.text, 16))
		check(spilled(game.ui) == 0 and spilled_boards() == 0,"the receipt adds no spilled text")
		check(off_paper() == 0,"the allocation sheet is tall enough for every line it prints")
		# 单据可以压到屋里的最低字号（18），但不能再小：再小就是拿可读性换版面。
		check(paper != null and paper.get_theme_font_size("font_size") >= 18,
			"the allocation sheet keeps the house minimum type size")
		check(covered_boards() == 0,"the allocation sheet covers no good, board or exit button")
		await capture(prefix+"15-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the finished street reloads from disk exactly as booked")
		check(game.state.failed == [TRAP] and not game.buttons.has("reset"),
			"a reload keeps the trial record and cannot be reset by an accidental click")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		var back: Control = game.buttons.back_hub
		check(back.size.x >= 48 and back.size.y >= 48,"the way back to the chart is a 48 pixel target or bigger")
		if not small: await capture("16-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"a standalone launch still finds its own way back to the chart")
		await click("next")
		check(game.modal and game.state.stage == "complete","replaying the scene asks first")
		await click("cancel")
		check(game.state.plan == Rules.SOLUTION,"cancelling keeps the receipt the player earned")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.plan == EMPTY and game.state.failed == []
			and game.state.hint == 0,"重新体验 rewinds this street, the trial record included")
		await click("next"); await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","the same four lines carry the player back to the counter")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","the walk-in still stops before player control")
		await promise(3,2); await promise(2,3); await promise(0,0); await promise(1,1)
		check(game.state.plan == Rules.SOLUTION and Rules.solved(game.state),
			"settling 乐手 and 医护 first leaves exactly one place for the other two")
		await click("deliver"); await click("skip")
		check(game.state.stage == "delivery" and game.state.failed == [],"a clean second run books nothing")
		await click("skip")
		check(game.state.stage == "complete" and "第一次试交就齐了" in ui_text("分配单").text,
			"and the sheet says it went smoothly instead of inventing a gap")
		check(spilled(game.ui) == 0 and spilled_boards() == 0 and covered_boards() == 0,
			"the replayed receipt adds no spilled or covered text")
		check(off_paper() == 0,"the shorter replay sheet still ends inside its own paper")
		await capture(prefix+"17-replay-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK07 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

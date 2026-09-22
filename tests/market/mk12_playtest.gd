extends SceneTree
# MK12 实窗审计：真实窗口里走一遍「三处需求单 4/5/6 → 六壶封油装三辆车 → 把三处都拨成 5 单位
# 却被逐处点名 → 请扣扣提醒 → 装满才交 → 三辆车各自载两壶离场 → 三处各自接油点灯 → 联合回执」。
# 在 1280×720 与 960×540 各拍一遍，并检查庭院木牌、车上读数与回执板上的汉字有没有爬出自己的边框。
const Scene = preload("res://game/market_mk12.tscn")
const Rules = preload("res://scripts/market/mk12_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
# 契约里指定的陷阱：每处都给 5 单位——封装确实交得出去（两壶一组、六壶全交完），
# 却违背桥头与西坡各自确认过的需要，只能在提交那一刻被如实拒绝。
const TRAP = [[0, 3], [1, 4], [2, 5]]
# 正解：2+2→4、2+3→5、3+3→6。load() 会 sort()，所以草稿里壶下标永远升序。
const SOLVED = [[0, 1], [2, 3], [4, 5]]
# 只装了三个位置不到位的草稿：用来验「台面还剩几壶」这一条缺口先于差额被说出来。
const PARTIAL = [[0, 1], [2], []]
# 联合回执的面板位置写在 mk12_scene.gd::extra() 里，本关的审计按它认这块纸。
const SHEET_PANEL = Rect2(984, 198, 284, 296)
# 台词板是全章最宽的一块常驻板（level_host 画在 338,98,826,86）：任何侧栏压进它的右下角，
# 收尾那句「三家一起签」就会被自己新摊开的纸啃掉一角。
const DIALOGUE = Rect2(338, 98, 826, 86)
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk12-oil"

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
# 摆好一个动画帧但不暂停：handing 与 delivery 的中间格只有在这里才拍得到。
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
# 庭院里的木牌由 plaque 直接画字，从不换行：一行比牌子还宽就爬到旁边的车或壶上。
# plaque 左右各留 10 像素木边，mark（车上读数）是把字居中画在框里，所以两者的余量不一样。
func board_size(board: Dictionary) -> int:
	return int(board["size_px"]) if board.has("size_px") else int(board["size"]) if board.has("size") else 16
func is_plaque(board: Dictionary) -> bool:
	return bool(board["plaque"]) if board.has("plaque") else bool(board["board"])
func spilled_boards() -> int:
	var over = 0
	for board in game.world.signs():
		var px := UIStyle.text_size(board_size(board))
		var room: float = float(board["rect"].size.x) - (20.0 if is_plaque(board) else 8.0)
		var needed := 0.0
		for line in str(board["text"]).split("\n"):
			needed = maxf(needed, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
			if px > board["rect"].size.y:
				over += 1; print("BOARD too short for ", px, "px: ", board["text"], " in ", board["rect"].size.y)
		if needed > room:
			over += 1; print("BOARD ", board["text"], " needs ", needed, " in ", room)
	return over
func board_with(needle: String) -> String:
	for board in game.world.signs():
		if str(board["text"]).contains(needle): return str(board["text"])
	return ""
func hotspots() -> int:
	var live = 0
	for id in game.buttons:
		if not id.begins_with("stock_") and not id.begins_with("cart_") and not id.begins_with("slot_"): continue
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
# 回执栏与庭院实物、木牌、出口按钮都在同一个逻辑平面上：谁压住谁只由矩形相交决定。
# 木牌要按当前镜头换算到屏幕坐标——puzzle 与 delivery 的前半程把庭院抬到 1.10，牌子会整体下压，
# 只看未放大坐标就会漏掉「需求单钻进口述板底下」这一类真机才看得见的遮挡。
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
func panel_named(rect: Rect2) -> bool:
	for child in game.ui.get_children():
		if child is Panel and Rect2(child.position, child.size) == rect: return true
	return false
func covered() -> int:
	var over = 0
	for board in game.world.signs():
		var shown: Rect2 = on_screen(board["rect"])
		for paper in papers():
			if paper.intersects(shown):
				over += 1; print("COVERED board ", board["text"], " by paper ", paper, " at ", shown)
	if game.state.stage != "complete": return over
	# 回执只在交货完成那一格摊开：它压到需求单、灯串、车帮上的那一纸，或底部出口按钮，就是收尾被自己挡住。
	if not panel_named(SHEET_PANEL):
		over += 1; print("COVERED receipt panel missing at ", SHEET_PANEL)
	if DIALOGUE.intersects(SHEET_PANEL):
		over += 1; print("COVERED 台词板 ", DIALOGUE, " by receipt ", SHEET_PANEL)
	# 面板自己那圈投影（skin.gd::panel_style：shadow_size 7、向下 4）是画在矩形外面的，
	# 只按矩形量就等于放过「板子的木边被纸的影子啃掉一角」这一类真缺陷。
	var shadow: Rect2 = SHEET_PANEL.grow(7.0)
	shadow.position += Vector2(0, 4)
	for board in game.world.signs():
		if shadow.intersects(on_screen(board["rect"])):
			over += 1; print("COVERED board ", board["text"], " by receipt shadow ", shadow)
	for place in range(Rules.PLACES.size()):
		var cart: Rect2 = on_screen(game.world.cart_rect(place))
		if SHEET_PANEL.intersects(cart):
			over += 1; print("COVERED cart ", Rules.PLACES[place], " by receipt ", SHEET_PANEL)
	# 六壶已经全部交出去，收尾不该再有台面热点被回执压住；这里改压真正在画的东西：台面上的壶位。
	for jug in range(Rules.JUGS):
		var spot: Rect2 = on_screen(game.world.stock_rect(jug))
		if SHEET_PANEL.intersects(spot):
			over += 1; print("COVERED 台面壶位 ", jug, " by receipt ", SHEET_PANEL)
	for id in ["next","open_hub","back_hub"]:
		if not game.buttons.has(id): continue
		if SHEET_PANEL.intersects(Rect2(game.buttons[id].position, game.buttons[id].size)):
			over += 1; print("COVERED exit ", id, " by receipt ", SHEET_PANEL)
	return over
# 拆件的真实绘制方框只由 manifest 的 anchor_px 与裁剪图尺寸决定：画面与审计共用同一条换算，
# 才不会出现「检查以为躲开了、屏幕上的灯罩其实压在台词板底下」。
func drawn_rect(id: String, foot: Vector2, width: float) -> Rect2:
	var item: Dictionary = game.world.parts[id]
	var tex: Texture2D = game.world.atlases[id]
	var scale = width / tex.get_width()
	return Rect2(foot - Vector2(item.anchor_px[0], item.anchor_px[1])*scale,
		Vector2(tex.get_width(), tex.get_height())*scale)
# 收尾那三张压在车帮上的回执，与车脚上方 90 像素的车斗，都不许被任何一块常驻木牌压住：
# 这是这一关真正「交出去」的凭证，看不见就等于没收单。
func payoff_covered() -> int:
	var over = 0
	for place in range(Rules.PLACES.size()):
		var sheet := drawn_rect("receipt_blank", game.world.sheet_foot(place), 44.0)
		var paper := Rect2(sheet.position + Vector2(0, 14), sheet.size - Vector2(14, 18))
		for board in game.world.signs():
			if board["rect"].intersects(paper):
				over += 1; print("COVERED 车帮回执 ", place + 1, " by ", board["text"], " ", board["rect"])
		var bed := Rect2(game.world.cart_foot(place) - Vector2(80, 96), Vector2(160, 96))
		for board in game.world.signs():
			if is_plaque(board) and board["rect"].intersects(bed):
				over += 1; print("COVERED 车斗 ", place + 1, " by ", board["text"], " ", board["rect"])
	return over
# 车上每一壶的单位读数写在壶脚下（mk12_world::jug_mark_rect）：两壶的读数不许互相叠，
# 也不许压到车帮那一行合计——一叠，玩家就分不清哪个数属于哪一壶。
func cart_labels() -> int:
	var bad = 0
	for place in range(Rules.PLACES.size()):
		var rects: Array = []
		for slot in range(game.state.plan[place].size()):
			rects.append(game.world.jug_mark_rect(place, slot))
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				if rects[i].intersects(rects[j]):
					bad += 1; print("OVERLAP 车上的读数 ", place, " ", rects[i], " ", rects[j])
		var at: Vector2 = game.world.cart_foot(place)
		var sum := Rect2(at.x - 100, at.y - 26, 200, 20)
		for r in rects:
			if r.intersects(sum):
				bad += 1; print("OVERLAP 车上的读数压到车帮合计 ", place, " ", r, " ", sum)
	return bad
# 五盏灯罩的亮心是这一关的收尾信号：镜头抬到 1.10 时它们要是整个钻进台词板底下，
# 玩家就看不见「都够用了」。灯罩亮心按真实发光点半径 11 的一半来量，光晕被板边蹭到不算藏灯。
func glass_clear() -> int:
	var hidden = 0
	for place in range(Rules.PLACES.size()):
		var foot = game.world.string_foot(place)
		for glass in game.world.LANTERN_GLASS:
			var at = game.world.kit_point("lantern_string", foot, 150.0, glass)
			var bulb = on_screen(Rect2(at - Vector2(6, 6), Vector2(12, 12)))
			for paper in papers():
				if paper.intersects(bulb):
					hidden += 1; print("COVERED 灯罩 ", place + 1, " at ", at, " by paper ", paper, " shown ", bulb)
	return hidden

# 镜头把庭院抬到 1.10 并左移 64：贴着画面两侧的那两块规则板会被窗框切掉首字，
# 实窗拍出来就是「每处最多两壶」少了个头。整块板（连它自己的字）都必须留在逻辑画面里。
func offscreen_boards() -> int:
	var cut = 0
	for board in game.world.signs():
		var shown: Rect2 = on_screen(board["rect"])
		if shown.position.x < 0 or shown.position.y < 0 or shown.end.x > 1280 or shown.end.y > 720:
			cut += 1; print("OFFSCREEN board ", board["text"], " at ", shown)
	return cut

# 装一壶：点台面上的壶，再点接它的那辆车——完全走玩家的手。
func fill(jug: int, place: int) -> void:
	await click("stock_%d" % jug); await click("cart_%d" % place)

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK12 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk12-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.world.scene_id == "oil" and game.world.has_part("oil_jug_round")
			and game.world.has_part("delivery_cart"),"分油庭院开在共用的 kit-v1 油庭院上")
		check(game.state.stage == "arrival" and game.state.plan == Rules.empty_plan()
			and game.state.handed == Rules.empty_plan() and game.state.hint == 0,
			"开场就是三辆空车与台面六壶：一壶都没交，草稿也是空的")
		check(Rules.jug_total() == 15 and Rules.need_total() == 15 and Rules.NEEDS == [4, 5, 6],
			"六壶共 15 单位、三处共要 15 单位：一壶不剩与刚好接满能同时成立")
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"第一拍只请玩家继续听，装车与交货都还没开")
		check(off_board() == 0,"开场台词两行都待在自己那块板里")
		check(spilled_boards() == 0 and offscreen_boards() == 0 and board_with("桥头 · 需求单 4 单位") != ""
			and board_with("西坡 · 需求单 6 单位") != "",
			"三张已确认的需求单刻在庭院里，不是只写在台词里")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab 把焦点交给开场那枚按钮")
		await key(KEY_ENTER)
		check(game.state.beat == 1 and "封油不能拆" in game.line() and "一共六壶" in game.line(),
			"第二句说清柜上只有三壶 2 单位与三壶 3 单位")
		await click("next")
		check("每一处最多接两壶" in game.line() and "六壶都要交出去" in game.line(),
			"第三句给出两条边界：每处最多两壶、六壶都要交出去")
		await click("next")
		check(game.state.beat == Rules.BEATS - 1 and game.buttons.next.text == "走向分油庭院",
			"第四句才把玩家送到庭院前")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"走位是一段带控件的真动画")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"暂停真的把走位冻住")
		await hold(0.9)
		check(game.world.scale.x > 1.0 and game.world.scale.x < 1.10,"走近的过程里镜头一路收拢")
		check(glass_clear() == 0 and offscreen_boards() == 0,"收拢的镜头没有把任何一盏灯罩推进台词板底下，也没有把牌子推出画面")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready","走位停下来才交给玩家")
		check(game.buttons.next.text == "开始装车","简报先说清点壶再点车的顺序")
		await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"装车时镜头贴着台面与三辆车")
		check(hotspots() == Rules.JUGS + Rules.PLACES.size(),
			"开局九个目标（六壶加三辆车）都活着，且每个不小于 48 像素")
		check(game.status_line() == "三车已装 0/6 壶 · 台面 6 壶","计数说的就是眼前摆着的东西")
		check(board_with("货栈封油 · 六壶都不能拆") != ""
			and board_with("封油共 15 单位 · 三处共要 15 单位") != ""
			and "每处最多两壶" in game.goal_line() and "4、5、6" in game.goal_line(),
			"两条边界刻在庭院牌上、最多两壶与三个需求数挂在抬头板：侧板原先画在扣扣身上，已删掉")
		check(game.state.hint == 0 and off_board() == 0 and spilled_boards() == 0,"摊开的庭院里没有一个字爬出自己的框")
		check(covered() == 0 and glass_clear() == 0 and offscreen_boards() == 0,"贴紧的镜头没有把牌子或灯罩推进板底，也没有推出画面")
		await capture(prefix+"03-courtyard")
		# ---- 边界：一辆车最多两壶，被拒的那一壶留在手里，台面计数不变 ----
		await fill(0, 0); await fill(1, 0)
		await click("stock_2"); await click("cart_0")
		check(game.state.plan == [[0, 1], [], []] and game.message == "桥头那辆车最多接两壶：先点车上的壶放回台面，再装新的。",
			"第三壶被明说拒收，用的就是契约里那句话")
		check(Rules.stock_of(game.state.plan).size() == 4 and Rules.assigned(game.state.plan) == 2,
			"被拒的那一壶既没上车也没消失：台面加车上永远六壶")
		check(game.picked == 2,"拒绝不抢走玩家手里的壶")
		for _n in range(2): await key(KEY_Z)
		check(game.state.plan == Rules.empty_plan(),"撤销两步回到空车")
		# ---- 缺口先报台面，再按需求单顺序报差额 ----
		await fill(0, 0); await fill(1, 0); await fill(2, 1)
		await click("deliver")
		check(game.message == "货栈台面上还剩 3 壶封油：六壶都要交出去，一壶不剩。（还有 2 处没有归位）",
			"没交完就先把剩几壶说清楚，再点名还有几处没归位")
		check(game.state.stage == "puzzle" and game.state.handed == Rules.empty_plan(),
			"半交的草稿一壶都没交出去：handed 仍然空着")
		for _n in range(3): await key(KEY_Z)
		check(game.state.plan == Rules.empty_plan(),"撤销三步回到空车")
		# ---- 契约指定的陷阱：三处都给 5 单位 ----
		await fill(0, 0); await fill(3, 0)
		await fill(1, 1); await fill(4, 1)
		await fill(2, 2); await fill(5, 2)
		check(game.state.plan == TRAP and game.status_line() == "三车已装 6/6 壶 · 台面 0 壶",
			"三处各两壶、每处 5 单位：按封装这是一份交得出去的摆法")
		check(board_with("车上 5 单位") != "" and Rules.totals(game.state.plan) == [5, 5, 5],
			"车帮上的读数由草稿现算，一处一个")
		check(game.state.handed == Rules.empty_plan(),"装得再满，没提交就一壶都没交")
		await capture(prefix+"04-all-five")
		await click("deliver")
		var complaints = Rules.shortfalls(game.state)
		check(complaints.size() == 2 and game.state.stage == "puzzle",
			"合计对得上的摆法照样被拒：桥头多了 1、西坡还差 1")
		check(game.message == "桥头的需求单要 4 单位，车上是 5 单位，多了 1 单位。（还有 1 处没有归位）",
			"第一条缺口就是契约里那句原话：点名是哪张需求单没被满足")
		check(not "中街" in game.message,"刚好接到 5 单位的中街不被牵连")
		check("还差" in complaints[1] and "西坡" in complaints[1],"少接只说还差几单位，不说谁被罚")
		check(game.state.plan == TRAP and game.state.handed == Rules.empty_plan(),
			"被拒的交货不改草稿，也不留下任何幻影交货")
		await capture(prefix+"05-refused")
		await key(KEY_Z)
		check(game.state.plan == [[0, 3], [1, 4], [2]],
			"撤销一步只取回最后一壶：西坡还剩一壶在车上（实为 %s，history %d，transient %.2f）"
				% [str(game.state.plan), game.history.size(), game.transient])
		check(game.message == "","撤销之后上一句拒绝的话跟着旧现场一起消失（实为「%s」）" % game.message)
		for _n in range(5): await key(KEY_Z)
		check(game.state.plan == Rules.empty_plan(),"撤销回到一辆空车")
		await click("hint"); await click("hint"); await click("hint"); await click("hint")
		check(game.state.hint == Rules.HINT_TIERS,"提示停在出货的那一档，不再往下要")
		check(game.message == game.hint_texts()[Rules.HINT_TIERS-1],
			"顶档之后台词板复述的还是第三级那一句")
		var named := 0
		for name in Rules.PLACES:
			for one in game.hint_texts():
				if str(one).contains(name): named += 1
		check(named == 1,"三级提示只点名一个街口，另两处都用「要 N 单位的那处」指代")
		check(game.state.plan == Rules.empty_plan() and game.state.hint == 3,
			"提示只说话：不动一壶，也不扣奖励")
		check(off_board() == 0 and fits(game.message, 20, 798.0),"两行的提示装得进口述板的内框")
		await capture(prefix+"06-hints")
		# ---- 正解：2+2→4、2+3→5、3+3→6，全程用鼠标 ----
		await click("stock_0")
		tap("cart_0")
		check(game.transient > 0 and game.world.land_place == "jug" and game.world.land_slot == 0,
			"刚装上的那一壶占住宿主的落纸锁")
		check(game.world.landing("jug",0) > 0.5,"那一壶正悬在车格上方")
		check(game.buttons.cart_0.disabled and game.buttons.undo.disabled,
			"落纸期间车与撤销都点不动，玩家抢不到第二次")
		await capture(prefix+"07-jug-landing")
		await settle()
		check(game.state.plan == [[0], [], []] and game.world.landing("jug",0) == 0.0,
			"落纸结束，草稿里多出桥头的那一壶")
		check(hotspots() == Rules.JUGS + Rules.PLACES.size(),
			"装走一壶之后仍然九个目标活着：台面上少一壶，车上就多一个放回点，每个不小于 48 像素")
		await click("stock_1"); await click("cart_0")
		await click("stock_2"); await click("cart_1")
		await click("stock_3"); await click("cart_1")
		await click("stock_4"); await click("cart_2")
		await click("stock_5"); await click("cart_2")
		check(game.state.plan == SOLVED and Rules.solved(game.state),
			"六壶一壶不剩，三处各自 4、5、6 单位")
		check(Rules.totals(game.state.plan) == Rules.NEEDS and Rules.stock_of(game.state.plan).is_empty(),
			"合计与需求单逐处对上，台面上确实一壶不剩")
		check(game.status_line() == "三车已装 6/6 壶 · 台面 0 壶","计数读的就是这一份草稿")
		await click("reset")
		check(game.modal and game.state.plan == SOLVED,"重摆先问一句，不直接清车")
		await capture(prefix+"08-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.plan == SOLVED,"留在现场时草稿一壶不动")
		await click("reset"); await click("confirm")
		check(game.state.plan == Rules.empty_plan() and game.state.handed == Rules.empty_plan()
			and game.picked == -1 and Rules.stock_of(game.state.plan).size() == Rules.JUGS,
			"全部放回台面：壶没拆过，也一壶没交出去")
		check(not game.buttons.undo.disabled,"清空之后还能把那一步撤回来")
		await key(KEY_Z)
		check(game.state.plan == SOLVED,"撤销一步就把六壶重新装回三辆车")
		check(game.world.state == game.state,"画面读的是提交之后的那一份草稿")
		check(covered() == 0 and spilled_boards() == 0 and off_board() == 0 and glass_clear() == 0
			and offscreen_boards() == 0 and cart_labels() == 0,
			"装满的庭院里没有牌子、读数或壶爬出边框，也没被板子压住；车上的六行单位读数各占各的脚下")
		await capture(prefix+"09-loaded")
		await click("deliver")
		check(game.state.stage == "handing" and game.state.handed == SOLVED and game.state.plan == SOLVED,
			"一次交货同时记账：三辆车一起走，不是一壶一壶地交")
		check(game.buttons.has("skip") and not game.buttons.has("stock_0")
			and not game.buttons.has("deliver"),"交货之后台面热点与提交按钮都退场，只留动画控件")
		await hold(1.2)
		check(game.world.cart_foot(0).x < game.world.cart_station(0).x - 20
			and game.world.cart_foot(2).x > game.world.cart_station(2).x + 20,
			"整辆车各自朝自己的街口平移：桥头向左、西坡向右")
		check((game.world.slot_foot(2,1)-game.world.cart_foot(2)).x > 0.0
			and (game.world.slot_foot(2,1)-game.world.cart_foot(2)).x < 60.0,
			"车上的壶跟着车脚走：落点永远从当前车脚算，没有一壶掉回台面")
		check(board_with("抱着 2+2=4 单位上路") != "" and board_with("抱着 3+3=6 单位上路") != "",
			"车帮读数在离场这一段改说路上带着哪两壶、共多少单位")
		check(Rules.stock_of(game.world.state.plan).is_empty(),"世界自己数的台面上也剩 0 壶")
		await capture(prefix+"10-carts-leaving")
		await click("skip")
		check(game.state.stage == "delivery" and game.state.handed == SOLVED,
			"交出去的这一单进入接油点灯那一段")
		await hold(1.6)
		check(at_camera(1.0, Vector2.ZERO) and game.world.progress > 0.45,
			"点灯这一段一开始就把庭院收回到全景：贴着柜台会把挂在庭院上方的灯串顶边切掉")
		check(game.world.state.stage == "delivery" and Rules.totals(game.world.state.plan) == Rules.NEEDS,
			"三处接到的单位数是从世界的账上读出来的，不是标签里的字")
		check(board_with("2+2=4 · 正好够用") != "" and board_with("3+3=6 · 正好够用") != "",
			"车帮读数换成算式加「正好够用」：不够用的那一处不会被写出来")
		check(game.world.progress > 0.4,"三处按各自的顺序亮起来，此刻至少亮起一处")
		await capture(prefix+"11-lighting")
		game.paused = false; await create_timer(0.12).timeout
		paused_at = game.elapsed
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(0.12).timeout
		check(game.paused and game.elapsed == paused_at,"失焦把点灯冻在当下这一帧")
		check(game.buttons.pause.text == "继续动画","冻住的动画提供继续")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "complete" and at_camera(1.0, Vector2.ZERO),
			"灯点完退回整座庭院：车离场与点灯都要看得到全景")
		check(game.world.state == game.state and game.world.state.handed == SOLVED,
			"收尾画面读的还是账上那一单")
		check(payoff_covered() == 0,"三张压在车帮上的回执没有被任何庭院木牌压住")
		check(glass_clear() == 0,"十五盏灯罩都在板子外面")
		var paper = ui_text("三家联合回执")
		check(paper != null and "桥头 2+2=4 · 需求单 4" in paper.text
			and "中街 2+3=5 · 需求单 5" in paper.text and "西坡 3+3=6 · 需求单 6" in paper.text,
			"回执按玩家真正交出去的那一单复述 2+2 / 2+3 / 3+3")
		check(paper != null and "台面剩 0 壶 · 封油没拆过" in paper.text,
			"回执说明六壶都交了、一壶没拆")
		check(paper != null and "六壶共 15 单位" in paper.text and "三处共要 15 单位" in paper.text,
			"回执把两个总数并排放：不一样多，也都够用")
		check(paper != null and "不一样多，也都够用" in paper.text and "三家一起签 · 衡伯开总货栈" in paper.text,
			"总货栈重新开门只写在收尾页上")
		check(paper != null and fits(paper.text, 16, 254.0),"九行回执都贴得进自己那张纸")
		if paper != null and not fits(paper.text, 16, 254.0):
			print("DIAG sheet needs ", paper.get_combined_minimum_size(), " in ", paper.size,
				" widest ", widest_line(paper.text, 16))
		check(paper != null and paper.get_theme_font_size("font_size") >= 18,"回执不低于全章最小字号")
		check(panel_named(SHEET_PANEL) and off_board() == 0 and spilled_boards() == 0,
			"回执板就停在契约写明的位置上，新增的文字没有一个爬出自己的框")
		check(covered() == 0 and offscreen_boards() == 0,"回执不压需求单、灯串、车斗或出口按钮，也没有牌子被推出画面")
		await capture(prefix+"12-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"重新打开就是交出去的那一单，一位不差")
		check(game.state.handed == SOLVED and not game.buttons.has("reset"),
			"读档保住交货记录：误点也清不掉已经交出去的那一单")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"航图是谁送来的只读一次")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"从航图进来只给回去的那一条路")
		var back: Control = game.buttons.back_hub
		check(back.size.x >= 48 and back.size.y >= 48,"回航图那枚按钮不小于 48 像素")
		if not small: await capture("13-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"单独启动这一幕也自己长出回航图的路")
		await click("next")
		check(game.modal and game.state.stage == "complete","重新体验先问一句")
		await click("cancel")
		check(game.state.handed == SOLVED,"取消就留在已经交货的那张回执上")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.plan == Rules.empty_plan()
			and game.state.handed == Rules.empty_plan() and game.state.hint == 0,
			"重新体验把这幕的草稿、交货记录与提示一起倒回")
		await click("next"); await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","同样四句把玩家带回庭院前")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","走位仍然在交给玩家之前停住")
		await key(KEY_1); await key(KEY_Q)
		await key(KEY_2); await key(KEY_Q)
		await key(KEY_3); await key(KEY_W)
		await key(KEY_4); await key(KEY_W)
		await key(KEY_5); await key(KEY_E)
		await key(KEY_6); await key(KEY_E)
		check(game.state.plan == SOLVED and Rules.solved(game.state),
			"键盘 1-6 与 Q/W/E 走的是鼠标同一条路：装完还是这一单")
		await click("deliver"); await click("skip"); await click("skip")
		check(game.state.stage == "complete" and Rules.stock_of(game.world.state.handed).is_empty(),
			"重放的这一单同样以六壶全交收尾")
		check("桥头 2+2=4" in ui_text("三家联合回执").text,
			"重放的回执复述的还是玩家真正交出去的那一单")
		check(off_board() == 0 and spilled_boards() == 0 and covered() == 0 and payoff_covered() == 0 and offscreen_boards() == 0,
			"重放的收尾没有溢出、越框或被压住的字")
		await capture(prefix+"14-replay-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK12 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

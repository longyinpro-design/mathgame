extends SceneTree
# MK14 实窗审计：真实窗口里走一遍「听完三句 → 走到摊前 → 把 1 与 3 全站到对面那盘、抬秤被
# 如实判下沉 → 回到秤前挪一挪 → 5+3+1=9 交出去 → 同一具秤接着配 8+1=9 → 迷你铜秤与迁移回执」。
# 在 1280×720 与 960×540 各拍一遍，并检查柜面木牌、抬秤读数与回执板上的汉字有没有爬出自己的边框。
const Scene = preload("res://game/market_mk14.tscn")
const Rules = preload("res://scripts/market/mk14_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
# 两单的参考摆法（下标 0/1/2 对应 1、3、9 三枚）：5 = 货 + 3 + 1 对 9；8 = 货 + 1 对 9。
const FIVE_GOODS = [1, 1, 0]
const FIVE_FAR = [0, 0, 1]
const EIGHT_GOODS = [1, 0, 0]
const EIGHT_FAR = [0, 0, 1]
# 这一关自己的陷阱：把砝码统统放到对面那盘（人人都以为货只能孤零零压在左盘）。
const NAIVE_FAR = [1, 1, 0]
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk14-scale"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
# 一次真实的按下-抬起：不等帧，所以能看见宿主 0.28 秒的落纸锁与本关自己的下落帧。
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
# 摆好一个动画帧但不暂停：抬秤的倾杆与交付的抛物线只有在这里才拍得到中间格。
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
# 柜面木牌由 plaque 直接画字，从不换行：一行比牌子还宽就爬到秤盘或旁边的货上。
# plaque/words 用的就是牌上写的那号字（13、14、15），不像 UIStyle.text 会被抬到 18，
# 所以这里按渲染真正用的字号量，量出来的才是屏幕上那一行。
func board_size(board: Dictionary) -> int:
	return int(board["size_px"]) if board.has("size_px") else int(board["size"])
func is_plaque(board: Dictionary) -> bool:
	return bool(board["plaque"]) if board.has("plaque") else bool(board["board"])
func spilled_boards() -> int:
	var over = 0
	for board in game.world.signs():
		var px: int = board_size(board)
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
		if not id.begins_with("rack_") and not id.begins_with("pan_") and not id.begins_with("cart_"): continue
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
# 两块纸互相压角也是真机才看得见的缺陷：台词板的位置是宿主定的（动不得），
# 关卡自己的回执就得躲开它，否则回执会把台词的首字糊在纸底下。
func boards_clear() -> int:
	var list := []
	for child in game.ui.get_children():
		if child is Panel: list.append(Rect2(child.position, child.size))
	var hit = 0
	for a in range(list.size()):
		for b in range(a+1, list.size()):
			if list[a].grow(-2.0).intersects(list[b].grow(-2.0)):
				hit += 1; print("COVERED paper ", list[a], " with ", list[b])
	return hit
# 回执与柜面实物、木牌、出口按钮都在同一个逻辑平面上：谁压住谁只由矩形相交决定。
# 木牌要按当前镜头换算到屏幕坐标——puzzle/weighing/result 把摊子抬到 1.10，牌子会整体下压，
# 只看未放大坐标就会漏掉「车顶板钻进口述板底下」这一类真机才看得见的遮挡。
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
	# 回执只在两单都记完账那一格摊开：它压到秤、砝码架、签收的两包货、纪念物或出口按钮，就是收尾被自己挡住。
	var sheet: Rect2 = game.receipt_rect()
	for thing in [on_screen(game.world.pan_rect(Rules.GOODS)), on_screen(game.world.pan_rect(Rules.FAR)),
			on_screen(game.world.cart_rect(2))]:
		if sheet.intersects(thing):
			over += 1; print("COVERED 秤盘或交货车 by receipt ", sheet, " at ", thing)
	# 左边那两辆车此刻是空的（热点只在配秤那一幕建），真正要护住的是车上画出来的那两包货。
	for index in range(Rules.ORDERS.size()):
		var bed: Vector2 = game.world.parcel_foot(index)
		var wide: float = game.world.parcel_width(index)
		var cargo := on_screen(Rect2(bed.x - wide/2.0, bed.y - wide*0.9, wide, wide*0.9))
		if sheet.intersects(cargo):
			over += 1; print("COVERED 车上那包 ", Rules.ORDERS[index], " 单位 by receipt ", sheet, " at ", cargo)
	for index in range(Rules.COUNT):
		var seat: Rect2 = on_screen(game.world.rack_rect(index))
		if sheet.intersects(seat):
			over += 1; print("COVERED 砝码架 ", index + 1, " by receipt ", sheet)
	for id in ["next","open_hub","back_hub"]:
		if not game.buttons.has(id): continue
		if sheet.intersects(Rect2(game.buttons[id].position, game.buttons[id].size)):
			over += 1; print("COVERED exit ", id, " by receipt ", sheet)
	return over
# 纪念物与读数板是这一关真正的收尾画面：常驻木牌不许盖住它们，也不许被盖住。
# 这一条按世界坐标量（镜头只平移整块画面，谁盖住谁与镜头无关）。
func payoff_covered() -> int:
	var over = 0
	var boards: Array = game.world.signs()
	# 抬秤读数板压在秤座下方：它盖住盘里的砝码就等于把玩家摆的那一式藏起来。
	for board in boards:
		if not is_plaque(board): continue
		for side in [Rules.GOODS, Rules.FAR]:
			if board["rect"].intersects(game.world.pan_rect(side)):
				over += 1; print("COVERED 秤盘 ", side, " by ", board["text"], " ", board["rect"])
		for index in range(Rules.COUNT):
			if board["rect"].intersects(game.world.rack_rect(index)):
				over += 1; print("COVERED 砝码架 ", index + 1, " by ", board["text"], " ", board["rect"])
	if game.state.stage != "complete": return over
	# 迷你铜秤与它上面重演的那两式：纪念物本体（含小盘里那一横排）不能被任何牌子压住。
	var foot: Vector2 = game.world.souvenir_foot()
	var base: Vector2 = foot + game.world.SOUVENIR_BASE
	var factor: float = game.world.unit_scale() * game.world.SOUVENIR_SCALE
	var mini_half: float = game.world.part_width("scale_pan", factor) / 2.0
	for side in [Rules.GOODS, Rules.FAR]:
		var centre: Vector2 = game.world.cargo_at(base, factor, side, 0.0)
		var row: Array = game.world.souvenir_row(side)
		var items: Array = game.world.souvenir_items(side)
		for slot in range(items.size()):
			var wide: float = game.world.parcel_width(Rules.ORDERS.size() - 1) * game.world.SOUVENIR_SCALE \
				if items[slot] == game.world.PARCEL_SLOT else game.world.weight_width(items[slot]) * game.world.SOUVENIR_SCALE
			var seat := Rect2(row[slot].x - wide/2.0, centre.y - 20.0, wide, 40.0)
			for board in boards:
				if board["rect"].intersects(seat):
					over += 1; print("COVERED 纪念物 ", side, " 第 ", slot + 1, " 格 by ", board["text"], " ", board["rect"])
	return over
# 每一块牌子（连它自己的字）都必须留在 1280×720 的逻辑画面里：镜头抬到 1.10 时
# 屏幕横坐标 = 世界 × 1.1 − 64，贴着画面两侧的牌会被窗框切掉首字。
func offscreen_boards() -> int:
	var cut = 0
	for board in game.world.signs():
		var shown: Rect2 = on_screen(board["rect"])
		if shown.position.x < 0 or shown.position.y < 0 or shown.end.x > 1280 or shown.end.y > 720:
			cut += 1; print("OFFSCREEN board ", board["text"], " at ", shown)
	return cut
# 扣扣是画在摊子上的人，不是牌子：贴脸镜头下她整只都得留在画面里；
# 她排在砝码架之后落笔，框一压过架格，玩家要点的那枚砝码就藏在她身子底下。
# 两块几何都按当前镜头换算到屏幕上再比，1.10 那一档才量得准。
func keeper_off() -> int:
	var shown: Rect2 = on_screen(game.world.keeper_rect())
	var cut = 0
	if shown.position.x < 0 or shown.position.y < 0 or shown.end.x > 1280 or shown.end.y > 720:
		cut += 1; print("OFFSCREEN 扣扣 ", shown)
	for index in range(Rules.COUNT):
		if shown.intersects(on_screen(game.world.rack_rect(index))):
			cut += 1; print("COVERED 砝码架 ", index + 1, " by 扣扣 ", shown)
	return cut

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK14 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk14-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.world.scene_id == "oil" and game.world.stations.has("scale_foot")
			and game.world.has_part("scale_beam") and game.world.has_part("weight_hex"),
			"小摊开在共用油庭院里那具货栈铜秤前")
		check(game.state.stage == "arrival" and game.state.goods == Rules.empty_pan()
			and game.state.far == Rules.empty_pan() and game.state.delivered == 0
			and game.state.weighs == 0 and game.state.hint == 0,
			"开场三枚砝码都在架上：没抬过秤，也没交过一单")
		check(Rules.ORDERS == [5, 8] and Rules.WEIGHTS == [1, 3, 9] and Rules.spans_all(),
			"两单是街上送来的 5 与 8，三枚是 1、3、9：回执那句「1 至 13 每单只一解」是真话")
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"第一拍只请玩家继续听，抬秤的按钮还没出现")
		check(off_board() == 0 and boards_clear() == 0,"开场两行台词待在自己的板里，两块纸也不互相压角")
		check(spilled_boards() == 0 and offscreen_boards() == 0,"摊子上没有一块牌爬出自己的框或画面")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab 把焦点交给开场那枚按钮")
		await key(KEY_ENTER)
		check(game.state.beat == 1 and "哪头沉哪头轻" in game.line(),"第二句先把「砝码只放对面」那个想当然摆出来")
		await click("next")
		check(game.state.beat == Rules.BEATS - 1 and game.buttons.next.text == "走到摊前",
			"第三句说清货压在左盘、一枚最多上一次秤")
		check("一枚最多上一次秤" in game.line() and "秤也不提前说话" in game.line(),
			"抬秤之前不预告平不平，这句话在开场就讲定")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"走位是一段带控件的真动画")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"暂停真的把走位冻住")
		await hold(0.9)
		check(game.world.scale.x > 1.0 and game.world.scale.x < 1.10,"走近的过程里镜头一路收拢到铜秤")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready","走位停下来才交给玩家")
		check(game.buttons.next.text == "开始配秤","简报先说清点架上那一格就是挪砝码")
		check(off_board() == 0 and "Q、W、E" in game.line(),
			"简报两行都装在自己的板里，顺手把「放回架上」的快捷键交给玩家")
		await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"配秤时镜头贴着铜秤与砝码架")
		check(hotspots() == Rules.COUNT + 2 + Rules.CARTS.size(),
			"三格架、两只盘、三辆车都是不小于 48 像素的真目标")
		check(game.status_line() == "上秤 0 枚 · 抬 0 次","状态板只说玩家做过的事，一个判分数字都没有")
		check(board_with("货 5 = 空盘") != "" and board_with("三枚砝码 · 点一下挪地方") != "",
			"读数板此刻只写「货 5 对空盘」：没摆之前不猜答案")
		check(not "平" in board_with("货 5 = 空盘") and not "差" in board_with("货 5 = 空盘"),
			"读数板从不判分：既不说平也不说差")
		check(board_with("订单一 · 5 单位 · 上秤了") != "" and board_with("订单二 · 8 单位 · 在车上") != "",
			"这一单的货已经站上秤盘，下一单还压在自己的车上：两块牌各说各的")
		check(game.world.state == game.state,"画面读的就是提交之后的那一份账")
		check(covered() == 0 and payoff_covered() == 0 and offscreen_boards() == 0,
			"贴紧的镜头下没有牌被压住，也没有牌被推出画面")
		check(keeper_off() == 0,"贴脸镜头下扣扣整只都在画面里，也没压住架上那三枚砝码")
		await capture(prefix+"03-scale")
		# ---- 只念不动：点盘与点车都把玩家自己摆出来的东西照念一遍 ----
		await click("pan_2")
		check(game.message.contains("抬了秤才知道") and game.state.far == Rules.empty_pan(),
			"点对面那盘只把盘面念一遍，不改现场也不预告哪头沉")
		check(game.message.contains("这一盘不装货，只站砝码"),"空着的那盘被念成空盘，不是 0 单位")
		await click("cart_1")
		check("订单二 · 8 单位 · 中街油铺" in game.message,"点第二辆车让扣扣把这单原样再念一遍")
		# ---- 本关的陷阱：把 1 与 3 统统放到对面那盘，抬秤被如实判下沉 ----
		await click("rack_0")
		check(game.state.far == [1, 0, 0] and game.world.drop(0) < 1.0,
			"第一下把 1 请上对面那盘：它正从架上落进盘里")
		check(game.world.drop_at[0] > -99.0,
			"这一枚的下落由世界自己的时钟记下时刻：不占宿主那 0.28 秒的落地锁")
		await create_timer(0.12).timeout
		check(game.world.drop(0) > 0.0 and game.world.drop(0) < 1.0,
			"下落走到半路：既没贴着架，也没坐进盘")
		await capture(prefix+"04-weight-dropping")
		await create_timer(0.3).timeout
		check(game.world.drop(0) == 1.0,"下落走完，砝码稳稳站在盘里")
		await click("rack_1")
		check(game.state.far == NAIVE_FAR and game.state.goods == Rules.empty_pan(),
			"再点一下把 3 也请上对面那盘：货还孤零零压在左盘")
		check(game.status_line() == "上秤 2 枚 · 抬 0 次","计数跟着玩家摆的两枚走")
		check(board_with("货 5 = 砝码 3 + 砝码 1") != "","读数板复述的就是玩家摆的那一式，不判对错")
		await capture(prefix+"05-naive")
		await click("deliver")
		check(game.state.stage == "weighing" and game.state.weighs == 1,
			"提秤不看对错：请了砝码上秤，秤就抬，并且老实记一次抬秤")
		check(not game.buttons.has("rack_0"),"抬秤期间挪不动任何一枚")
		await hold(1.2)
		check(Rules.heavier(game.state) == Rules.GOODS and game.world.beam_angle() < 0.0,
			"梁真的往货盘这一头沉：画面与规则读的是同一个符号")
		check(absf(game.world.beam_angle()) > 0.02,"这一格秤杆已经抬离静止位，不是画了个平秤")
		await capture(prefix+"06-tilting")
		await click("skip")
		check(game.state.stage == "result" and game.state.delivered == 0
			and game.state.built_goods[0] == Rules.empty_pan(),
			"没配平就只回话不记账：一单都没交出去")
		check(game.line() == "货盘这一头沉下去了：货盘 5 单位，对面那盘 4 单位。\n5 单位的货还压在盘上：两盘差 1 单位，秤没平，这一单就走不了。",
			"结果牌说的是真数：哪头沉、差几单位、这一单还没走")
		check(board_with("两盘差 1 单位 · 这一单还不能走") != "","柜面木牌与台词板报同一个差")
		check(off_board() == 0 and covered() == 0,"两行的结果牌装得进口述板，也没压住任何东西")
		check(game.buttons.next.text == "回到秤前再摆" and not game.buttons.has("deliver"),
			"结果牌之后仍由 next 交还给秤前：这一刻没有第二座「抬秤」可点")
		await capture(prefix+"07-result")
		await click("next")
		check(game.state.stage == "puzzle" and game.state.far == NAIVE_FAR and game.state.weighs == 1,
			"回到秤前摆法原样保留：抬过一次不扣任何东西")
		# ---- 三级提示：只提醒关系与示范一步 ----
		await click("hint"); await click("hint"); await click("hint"); await click("hint")
		check(game.state.hint == Rules.HINT_TIERS,"提示停在出货的那一档，不再往下要")
		check(game.message == game.hint_texts()[Rules.HINT_TIERS-1],"顶档之后台词板复述的还是第三级那一句")
		var tiers: Array = game.hint_texts()
		check(tiers.size() == Rules.HINT_TIERS and "货 5 + 砝码 3" in tiers[2],
			"第三级示范的是这一单唯一那一式，前两级只讲关系")
		var talk := true
		for one in tiers:
			if str(one).count("\n") != 1 or not fits(str(one), 20, 798.0): talk = false
		check(talk,"每一级提示都刚好两行、装得进口述板的内框")
		check(game.state.far == NAIVE_FAR and game.state.goods == Rules.empty_pan(),
			"提示只多说话：一枚砝码都没替玩家挪")
		check(off_board() == 0,"两行提示没有爬出自己的板")
		await capture(prefix+"08-hints")
		# ---- 真摆法：1 与 3 站到货物这头，9 留在对面 ----
		await click("rack_0")
		check(game.state.goods == [1, 0, 0] and game.state.far == [0, 1, 0],
			"再点一下就是下一格：1 从对面那盘跨过秤梁站到货物这头来")
		await click("rack_1")
		check(game.state.goods == [1, 1, 0] and game.state.far == [0, 0, 0],
			"3 也跨过梁来：这一式的两头都站在货这头")
		await click("rack_2")
		check(game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR and Rules.solved(game.state),
			"最后把 9 请上对面那盘：5+3+1=9，两盘一样重")
		check(board_with("货 5 + 砝码 3 + 砝码 1 = 砝码 9") != "","读数板复述玩家自己摆出来的那一式")
		check(game.status_line() == "上秤 3 枚 · 抬 1 次","计数说的是三枚上秤、抬过一次")
		await click("reset")
		check(game.modal and game.state.goods == FIVE_GOODS,"砝码放回架上之前先问一句")
		await capture(prefix+"09-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR,
			"留在小摊时三枚还站在原处")
		await click("reset"); await click("confirm")
		check(game.state.goods == Rules.empty_pan() and game.state.far == Rules.empty_pan()
			and game.state.delivered == 0 and game.state.weighs == 1,
			"重摆只把三枚放回架上：抬过几次秤是发生过的事，不清零")
		check(not game.buttons.undo.disabled,"放回之后还能把那一步撤回来")
		await key(KEY_Z)
		check(game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR,
			"撤销一步就把三枚请回它们原来的盘")
		check(game.world.state == game.state and game.message == "","撤销之后画面读的是新账，旧台词也跟着消失")
		await capture(prefix+"10-balanced")
		await click("deliver")
		check(game.state.stage == "weighing" and game.state.weighs == 2,"第二次抬秤照样如实计数")
		await hold(1.2)
		check(absf(game.world.beam_angle()) < 0.09,"配平的这一式只是轻轻晃一下，不会一头沉到底")
		await capture(prefix+"11-lifted")
		await click("skip")
		check(game.state.stage == "delivery" and game.state.delivered == 0
			and game.state.built_goods[0] == Rules.empty_pan(),
			"平了的这一单直接进交付：账要等货真的落上车的斗那一格才记")
		check(Rules.balanced(game.state) and Rules.solved(game.state),
			"交付这一格读的还是那两盘真数：差 0，货还压在盘上")
		await hold(1.9)
		check(game.world.parcel_foot(0).x > game.world.cart_station(0).x,
			"这一单的货正被搬去交货车：落点跟着车走，不会掉回盘里")
		check(game.world.next_parcel_foot() != Vector2.INF,
			"下一单的货同时被推上同一具秤：迁移就是这么演出来的")
		check(board_with("订单一 签了收 · 砝码一枚没换") != "","柜面木牌说的是「砝码一枚没换」")
		check(Rules.pan_total(game.world.state, Rules.GOODS) == 9
			and Rules.difference(game.world.state) == 0,
			"两盘的数是从世界的账上读出来的：9 对 9，差 0")
		await capture(prefix+"12-migration")
		await hold(3.6)
		check(game.world.parcel_spot(0) == game.world.SPOT_DONE
			and game.world.parcel_spot(1) == game.world.SPOT_PAN
			and board_with("订单一 · 5 单位 · 已交货") != ""
			and board_with("订单二 · 8 单位 · 上秤了") != "" and keeper_off() == 0,
			"交付收势：两单都落定了，两块车顶板跟着改口，扣扣也没被窗框切掉")
		await capture(prefix+"12b-handover-settled")
		game.paused = false; await create_timer(0.12).timeout
		paused_at = game.elapsed
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(0.12).timeout
		check(game.paused and game.elapsed == paused_at,"失焦把交付冻在当下这一帧")
		check(game.buttons.pause.text == "继续动画","冻住的交付提供继续")
		await click("skip")
		check(game.state.stage == "puzzle" and game.state.order == 1 and game.state.delivered == 1
			and game.state.built_goods[0] == FIVE_GOODS and game.state.built_far[0] == FIVE_FAR
			and game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR,
			"货落上车的斗那一格才记账：第二单开局时三枚砝码还留在原地，玩家只需要挪")
		check(game.status_line() == "上秤 3 枚 · 抬 2 次","计数跨单继续累加")
		check(board_with("货 8 + 砝码 3 + 砝码 1 = 砝码 9") != "",
			"换了这一单的货，读数板跟着改口：砝码那一横排没动，货从 5 变成 8")
		await click("rack_1")
		check(game.state.goods == EIGHT_GOODS and game.state.far == EIGHT_FAR and Rules.solved(game.state),
			"把 3 放回架上：8+1=9，同一组砝码又兑了一单")
		check(board_with("货 8 + 砝码 1 = 砝码 9") != "","读数板复述第二单真正摆出来的那一式")
		await key(KEY_H)
		check(game.state.hint == Rules.HINT_TIERS and game.message == game.hint_texts()[Rules.HINT_TIERS-1],
			"键盘 H 与鼠标走的是同一档提示：到了顶档也不再往下要")
		check("货 8 + 砝码 1 = 砝码 9" in game.message,
			"顶档示范的是这一单唯一那一式：换了订单，提示跟着换")
		await capture(prefix+"13-second-order")
		await click("deliver")
		await click("skip")
		check(game.state.stage == "delivery" and game.state.delivered == 1
			and game.state.built_goods[1] == Rules.empty_pan(),
			"第二单也进了交付：这一刻账上还只有第一单")
		await click("skip")
		check(game.state.stage == "complete" and game.state.delivered == 2
			and game.state.built_goods[1] == EIGHT_GOODS and game.state.built_far[1] == EIGHT_FAR
			and at_camera(1.0, Vector2.ZERO),
			"两单交完退回整座庭院：第二笔记的正是玩家真摆过的那一式")
		check(game.world.state == game.state and game.world.state.built_far[1] == EIGHT_FAR,
			"收尾画面读的还是账上那两笔真记录")
		var paper = ui_text("回执 · 砝码一枚没添")
		check(paper != null and "1 留在货盘" in paper.text and "3 从货盘挪到砝码架" in paper.text
			and "9 留在对面那盘" in paper.text,"回执逐枚说清谁留在原地、谁挪了地方")
		check(paper != null and "同一组 1、3、9" in paper.text and "1 至 13 每单只一解" in paper.text,
			"最后一行是这一组砝码的数学事实，不是作者的夸奖")
		check(paper != null and not "罚" in paper.text and not "失败" in paper.text,
			"回执里没有惩罚式措辞")
		check(paper != null and fits(paper.text, 16, game.receipt_rect().size.x - 30),
			"回执六行都贴得进自己那张纸的内框（不靠 Godot 抬起来的盒子）")
		if paper != null:
			print("DIAG receipt widest ", widest_line(paper.text, 16), " min ",
				paper.get_combined_minimum_size(), " box ", Rect2(paper.position, paper.size),
				" panel ", game.receipt_rect(), " dialogue ", Rect2(338, 98, 826, 86))
		check(paper != null and paper.get_theme_font_size("font_size") >= 18,"回执不低于全章最小字号")
		check(board_with("迷你铜秤 · 两单的摆法") != ""
			and board_with("货 5 + 砝码 3 + 砝码 1 = 砝码 9") != ""
			and board_with("货 8 + 砝码 1 = 砝码 9") != "",
			"纪念物上重演的是玩家记进账里的那两式")
		check(game.world.souvenir_items(Rules.GOODS).size() == 2
			and game.world.souvenir_items(Rules.FAR) == [2],"纪念物摆的就是最后一单那一式，不是写死的答案")
		check(off_board() == 0 and spilled_boards() == 0 and boards_clear() == 0,"收尾没有越框的字，两块纸也不互相压角")
		check(covered() == 0 and payoff_covered() == 0 and offscreen_boards() == 0,
			"回执不压秤盘、砝码架或出口，纪念物也没被任何牌子盖住")
		check(keeper_off() == 0,"收尾镜头拉回整院时，挥手的扣扣照样在画面里、也没站上架格")
		await capture(prefix+"14-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"重新打开就是记完两单的现场，一枚不差")
		check(game.state.built_goods[1] == EIGHT_GOODS and not game.buttons.has("reset"),
			"读档保住两笔记录：误点也清不掉已经交出去的那两单")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"航图是谁送来的只读一次")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"从航图进来只给回去的那一条路")
		var back: Control = game.buttons.back_hub
		check(back.size.x >= 48 and back.size.y >= 48,"回航图那枚按钮不小于 48 像素")
		if not small: await capture("15-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"单独启动这一幕也自己长出回航图的路")
		await click("next")
		check(game.modal and game.state.stage == "complete","再配一次先问一句")
		await click("cancel")
		check(game.state.delivered == 2,"取消就留在已经交完两单的现场")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.goods == Rules.empty_pan()
			and game.state.delivered == 0 and game.state.weighs == 0 and game.state.hint == 0,
			"重新体验把这一摊的账整个倒回：两单、两次抬秤与三档提示一起清空")
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","同样三句把玩家带回摊前")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","走位仍然在交给玩家之前停住")
		await key(KEY_1); await key(KEY_1)
		await key(KEY_2); await key(KEY_2)
		await key(KEY_3)
		check(game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR,
			"键盘 1/2/3 与鼠标走的是同一条路：一站一站挪，绝不一步跨过秤梁")
		await key(KEY_Q)
		check(game.state.goods == [0, 1, 0] and game.state.far == FIVE_FAR,
			"Q 把 1 请回架上：现场少一枚，读数板跟着改口")
		await key(KEY_1)
		check(game.state.goods == [0, 1, 0] and game.state.far == [1, 0, 1],
			"再按 1 只是先站到对面那盘：架上与货盘之间还隔着一格")
		await key(KEY_1)
		check(game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR,
			"再按一次才跨过秤梁：键盘补回来的是同一式")
		await click("deliver"); await click("skip")
		check(game.state.stage == "delivery" and game.state.order == 0 and game.state.delivered == 0,
			"第一单进了交付：账要落在车上那一格才记")
		await click("skip")
		await click("rack_1")
		check(game.state.goods == EIGHT_GOODS and game.state.order == 1
			and game.state.delivered == 1 and game.state.built_goods[0] == FIVE_GOODS,
			"第二单只挪一枚：第一单那笔真账已经落在账上")
		await click("deliver"); await click("skip"); await click("skip")
		check(game.state.stage == "complete" and game.state.delivered == 2,
			"重放的两单同样以铜秤纪念物收尾")
		var again = ui_text("回执 · 砝码一枚没添")
		check(again != null and "3 从货盘挪到砝码架" in again.text,
			"重放的回执复述的还是玩家真正挪过的那一枚")
		check(off_board() == 0 and spilled_boards() == 0 and covered() == 0
			and payoff_covered() == 0 and boards_clear() == 0 and offscreen_boards() == 0
			and keeper_off() == 0,
			"重放的收尾没有溢出、越框、被压住或两块纸互相压角")
		await capture(prefix+"16-replay-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK14 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

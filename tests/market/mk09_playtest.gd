extends SceneTree
# MK09 实窗审计：真实窗口里走一遍「听三段话 → 五摊当众叫齐 → 在贴近的镜头前牵线 →
# 把货绕回自己摊、把同一卷布许给两家、把五摊挤成一个大环这三种错法真的交上去被逐条点名 →
# 请扣扣提醒、撤销、重摆模态 → 一次交上五摊 → 整批换货与点灯演出 → 回执」。
# 在 1280×720 与 960×540 各拍一遍，并检查木牌、灯串、交换线、货物与回执上的汉字有没有爬出自己的边框，
# 有没有被台词板、回执板或街面木牌压在下面。
const Scene = preload("res://game/market_mk09.tscn")
const Rules = preload("res://scripts/market/mk09_rules.gd")
const World = preload("res://scripts/market/mk09_world.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
# 规格点名的错法：五摊挤进一条大环，看着漂亮却一摊都没拿到自己要的那件。
const RING = [4, 0, 3, 1, 2]
const EMPTY = [-1, -1, -1, -1, -1]
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk09-cyclic-exchange"

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
# 摆好一个动画帧但不暂停：换货与点灯的中间格只有在这里才拍得到。
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
func plan(a: int, b: int, c: int, d: int, e: int) -> Array: return [a, b, c, d, e]
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
# 五摊门前挂的货与收货盘都是可点目标：不到 48 像素在真机上就是点不准。
func hotspots() -> int:
	var live = 0
	for id in game.buttons:
		if not id.begins_with("good_") and not id.begins_with("tray_"): continue
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
func on_screen(rect: Rect2) -> Rect2:
	var xf: Transform2D = game.world.get_global_transform_with_canvas()
	var a = xf*rect.position
	var b = xf*(rect.position+rect.size)
	return Rect2(a, b-a)
# 世界层自己怎么画拆件，审计就怎么量：同一个 anchor_px、同一个 scale，只乘一次。
func kit_rect(id: String, foot: Vector2, width: float) -> Rect2:
	var texture: Texture2D = game.world.atlases[id]
	var item: Dictionary = game.world.parts[id]
	var scale = width / texture.get_width()
	return Rect2(foot - Vector2(item.anchor_px[0], item.anchor_px[1])*scale,
		Vector2(texture.get_width(), texture.get_height())*scale)
func lit_spots() -> Array:
	var spots := []
	for glass in World.LANTERN_GLASS:
		var one = game.world.kit_point("lantern_string", game.world.string_foot(), World.STRING_WIDTH, glass)
		spots.append(Rect2(one - Vector2(20, 20), Vector2(40, 40)))
	return spots
# 街面上所有会被看见的东西：五摊的货（挂着的或落在盘里的）、五只收货盘、檐口灯串。
func stage_props() -> Array:
	var items := []
	var carried = game.world.carry_by_giver(game.world.carry_plan(game.world.progress))
	for index in range(Rules.COUNT):
		items.append({"what": "tray "+str(index),
			"rect": kit_rect("receiving_tray", game.world.tray_spot(index), World.TRAY_WIDTH)})
		var where: Dictionary = game.world.good_position(index, carried)
		items.append({"what": "good "+Rules.GOODS[index],
			"rect": kit_rect(Rules.KIT_GOODS[index], where["at"], World.GOOD_WIDTH[index])})
	# 灯串只在世界真的把它画出来的那一格里参与遮挡检查：delivery 要 progress 过 0.1 才亮，
	# 提前把它算进来就等于在检查一张街上根本不存在的画。
	var lit: float = 1.0 if game.state.stage == "complete" else (
		smoothstep(0.1,1.0,game.world.progress) if game.state.stage == "delivery" else 0.0)
	if lit > 0.0:
		for glass in lit_spots(): items.append({"what": "lantern glass", "rect": glass})
	return items
func papers() -> Array:
	var list := []
	for child in game.ui.get_children():
		if child is Panel: list.append(Rect2(child.position, child.size))
	return list
func panel_of(needle: String) -> Rect2:
	for child in game.ui.get_children():
		if not child is Label or not str(child.text).contains(needle): continue
		var box = Rect2(child.position, child.size)
		for other in game.ui.get_children():
			if other is Panel and Rect2(other.position, other.size).has_point(box.position):
				return Rect2(other.position, other.size)
	return Rect2()
# 交换线走的是拱形：峰顶一旦被台词板吃掉，玩家就看不懂这条线究竟牵给了谁。
# 把每条线的每个采样点（含段中点）换算到屏幕坐标，逐点比台词板。
func arc_points() -> Array:
	var pts := []
	for entry in game.world.line_paths():
		var one: PackedVector2Array = entry["points"]
		for index in range(one.size()):
			pts.append(one[index])
			if index + 1 < one.size(): pts.append((one[index]+one[index+1])*0.5)
	return pts
# 台词板的位置是宿主与关卡共用的约定（(338,98)）：审计按这一块认它，不去猜现在说的是哪句。
func dialogue_panel() -> Rect2:
	for child in game.ui.get_children():
		if child is Panel and child.position == Vector2(338,98): return Rect2(child.position, child.size)
	return Rect2()
# 街面上看得见的东西（木牌、货样、收货盘、灯串）全在世界层，UI 板一律压在它们之上。
# 比较之前必须按当前镜头换算：puzzle/exchanging 把街景抬到 1.10 并整体下压 43 像素，
# 只看未放大坐标就会漏掉「街名牌整块钻进台词板底下」这一类实窗才看得见的遮挡。
func covered() -> int:
	var over = 0
	# 唯一被允许的例外：complete 那张回执正好接管甲摊门前的两块木牌，因为它把同样的话复述了一遍。
	# 例外写死成「这一格、这张纸、这两块牌」，别的牌子被压住仍然是缺陷；
	# 到底接管了哪几块由 receipt_overlaps() 单独钉住，这里只负责放行。
	var sheet: Rect2 = game.receipt_rect() if game.state.stage == "complete" else Rect2()
	var restated = [game.world.name_rect(0), game.world.want_rect(0)]
	for board in game.world.signs():
		var shown: Rect2 = on_screen(board["rect"])
		for paper in papers():
			if not paper.intersects(shown): continue
			if paper == sheet and board["rect"] in restated: continue
			over += 1; print("COVERED board ", board["text"], " by paper ", paper, " at ", shown)
	for item in stage_props():
		var where: Rect2 = on_screen(item["rect"])
		for paper in papers():
			if paper.intersects(where):
				over += 1; print("COVERED prop ", item["what"], " at ", where, " by paper ", paper)
	# 交换线是本关的全部讲法：峰顶被台词板吃掉，玩家就看不出这条线究竟牵给了谁。
	var spoken = dialogue_panel()
	for entry in arc_points():
		var at = game.world.get_global_transform_with_canvas()*entry
		if spoken.has_point(at):
			over += 1; print("COVERED 交换线 ", at, " by dialogue ", spoken)
	if game.state.stage != "complete": return over
	for id in ["next","open_hub","back_hub"]:
		if not game.buttons.has(id): continue
		if sheet.intersects(Rect2(game.buttons[id].position, game.buttons[id].size)):
			over += 1; print("COVERED exit ", id, " by receipt ", sheet)
	return over
# 甲摊门口那两块木牌是例外：回执把同一条街的事复述了一遍，所以允许它正好接管这两块。
# 例外必须是「恰好这两块、且回执真的写着同样的话」，否则就是又一次牌子被压住。
func receipt_overlaps() -> Array:
	var names := []
	var sheet = panel_of("件货各走一次")
	for board in game.world.signs():
		if sheet.intersects(on_screen(board["rect"])): names.append(str(board["text"]))
	return names
# 灯串是本关的收尾画面：它和木牌同在世界层，木牌最后才画，所以谁盖住谁与镜头无关。
# 这里刻意不做镜头换算，正因为如此它才能当作物体之间遮挡的不变式。
func string_covered() -> int:
	var over = 0
	for glass in lit_spots():
		for board in game.world.signs():
			if board["rect"].intersects(glass):
				over += 1; print("COVERED 灯串 by ", board["text"], " ", board["rect"])
	return over
# 货样上方那一截本来就是绳子和空处：面板压住顶端不算错。真正的底线两条——
# 看得见的货与盘由 covered() 保证完全露在外面，这里再保证扣掉面板之后
# 剩下的可点高度仍有 48 像素，真机上才点得着。
func hotspots_clear() -> int:
	var over = 0
	for index in range(Rules.COUNT):
		for kind in ["good","tray"]:
			var rect = on_screen(game.world.good_rect(index) if kind == "good" else game.world.tray_rect(index))
			for paper in papers():
				if not paper.intersects(rect): continue
				var below = rect.end.y - maxf(rect.position.y, paper.end.y)
				var above = minf(rect.end.y, paper.position.y) - rect.position.y
				if maxf(below, above) < 48.0:
					over += 1
					print("HOTSPOT ", kind, index, " ", rect, " keeps only ", maxf(below,above), " free at ", paper)
	return over
# 换货、交货之后玩家还能看见街面：动画期间绝不允许任何可点热点活着。
# 「一次交上整条街」是无条件提交的，漏掉这一条就等于给了玩家一张已经入账之后的街。
func clicks_off() -> int:
	var live = 0
	for id in game.buttons:
		if not id.begins_with("good_") and not id.begins_with("tray_"): continue
		if not game.buttons[id].disabled:
			live += 1; print("LIVE hotspot ", id, " at stage ", game.state.stage)
	return live

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK09 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk09-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		# ---- 1. 开局：五摊各挂自己那件货，一件都还没换 ----
		check(game.world.scene_id == "street" and game.world.has_part("cloth_bolt")
			and game.world.has_part("receiving_tray") and game.world.has_part("lantern_string"),
			"the street opens on the shared kit with five goods, five trays and the lantern string")
		check(game.state.stage == "arrival" and game.state.beat == 0
			and game.state.lines == EMPTY and game.state.booked == EMPTY and game.state.hand == -1,
			"the scene opens before the stalls are convened: no line drawn, nothing booked, nobody holding")
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"the first line only asks to keep listening")
		check(off_board() == 0,"the two-line opening dialogue stays inside its own board")
		check(spilled_boards() == 0,"the street holds every board's own text")
		check(covered() == 0,"the arrival view hides nothing")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1 and "两个人当面换" in game.line() and "五摊一起换" in game.line(),
			"the second line asks the real question: must five stalls still be paired two by two")
		await key(KEY_SPACE)
		check(game.state.beat == Rules.BEATS - 1 and game.buttons.next.text == "当众叫齐五摊",
			"the third line is the one that convenes the five stalls, and Space walks the story too")
		check("需求都写在自家门面上" in game.line() and "一次换完" in game.line(),
			"the promise is stated before the player is handed the street")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"the walk-in animates the five stalls and offers its own controls")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		# 下一条量的是「路上」的镜头，前提是这一刻确实还走在路上：整表 pass 里撞见过一次量到 1.00，
		# 光看那条报错分不清是环境把走位走完了还是镜头没跟上，所以先把幕次钉住（与 MK11 同形）。
		check(game.state.stage == "approach","the walk-in is still on its way when it gets frozen")
		await hold(0.9)
		check(game.world.scale.x > 1.0 and game.world.scale.x < 1.10,"the street closes in on the way over")
		check(covered() == 0 and hotspots_clear() == 0,"the walk-in keeps every board clear of the dialogue board")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready","the walk-in stops before player control")
		check(game.buttons.next.text == "开始牵线","the briefing explains the click order")
		# 走位收尾已经把镜头推到 1.10：这一格讲的是「先点哪件货、再点哪只盘」，
		# 画面得还贴着同一张台面，不许先弹回整条街再随「开始牵线」跳回来。
		check(at_camera(1.10, Vector2(-64,-43)),
			"the briefing cell keeps the closed camera it walked in with")
		await click("next")
		# ---- 2. 贴近的街面：五摊、五只盘、需求写在门面上 ----
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"the street is handed to the player under the closed camera")
		check(hotspots() == Rules.COUNT*2,"five goods and five trays, each 48 pixels or bigger, are live")
		check(game.buttons.undo.disabled and game.state.hint == 0,
			"an untouched street has nothing to take back")
		check(game.status_line() == "线 0 / 5 · 满意 0 / 5",
			"the running tally reports lines drawn and stalls pleased, never a verdict")
		check(game.world.signs().size() == Rules.COUNT*2 + 2
			and board_with("灯芯街 · 五摊当众换货") != "" and board_with("线 0 / 5") != "",
			"the street names itself and counts the lines in the world, not only in the panels")
		var wants_seen = 0
		for receiver in range(Rules.COUNT):
			if board_with(Rules.accepts_text(receiver)) != "": wants_seen += 1
		check(wants_seen == Rules.COUNT,"every stall's own want is carved above its tray, not only spoken")
		var names_seen = 0
		for index in range(Rules.COUNT):
			if board_with("%s摊 · 有%s" % [Rules.ACTORS[index], Rules.GOODS[index]]) != "": names_seen += 1
		check(names_seen == Rules.COUNT,"each stall advertises the one good it is handing over")
		check(off_board() == 0 and spilled_boards() == 0,"the open street holds every line inside its own wood")
		check(covered() == 0 and hotspots_clear() == 0,
			"the closed camera keeps every board, good and tray clear of the dialogue board")
		await capture(prefix+"03-street")
		# ---- 3. 错法一：货绕回自己摊（提交被逐条点名）----
		tap("good_0")
		check(game.state.hand == 0 and game.history.is_empty(),
			"picking up a good is feel, not a step: it costs nothing to take back")
		tap("tray_0"); await process_frame; await settle()
		check(game.state.lines == plan(0,-1,-1,-1,-1) and Rules.self_lines(game.state.lines) == [0],
			"the player can really loop a stall's own good back onto its own tray")
		await click("deliver")
		check(game.state.stage == "puzzle" and game.message.begins_with("甲摊的线绕回了自己：布留在原摊")
			and "还有 4 处没有归位" in game.message,
			"the kept-at-home line is refused by name and says how many are still open")
		check(game.state.booked == EMPTY,"a refused submit moves nothing at all")
		check(off_board() == 0,"the five-complaint report stays inside the dialogue board")
		await capture(prefix+"04-kept-at-home")
		tap("tray_0"); await process_frame; await settle()
		check(game.state.lines == EMPTY and game.world.line_paths().is_empty(),
			"tapping the filled tray pulls that line back and leaves no phantom ownership")
		await key(KEY_Z)
		check(game.state.lines == plan(0,-1,-1,-1,-1),"undo brings the pulled-back line onto the street again")
		await key(KEY_Z)
		check(game.state.lines == EMPTY and game.history.is_empty() and game.buttons.undo.disabled
			and game.state.hand == 0,"the rewind consumes every step and hands the good back, then goes idle")
		tap("good_0"); await settle()
		check(game.state.hand == -1,"tapping the held good once more lets it go")
		# ---- 4. 落线手感：宿主 0.28 秒的落纸锁归这一条线 ----
		tap("good_0")
		tap("tray_2")
		check(game.transient > 0 and game.world.land_place == "tray" and game.world.land_slot == 2,
			"the new line owns the host's landing lock")
		check(game.world.landing("tray",2) > 0.5,"the tray is caught mid-flash under the arriving line")
		check(game.buttons.good_0.disabled and game.buttons.tray_0.disabled,
			"the street cannot be edited while a line is landing")
		await capture(prefix+"05-line-drawn")
		await settle()
		check(game.state.lines == plan(-1,-1,0,-1,-1) and game.world.landing("tray",2) == 0.0,
			"the line seats itself: 丙 is promised 布, nothing else changed")
		check(game.world.line_paths().size() == 1 and game.world.draft().has(0),
			"the world draws exactly the one line the player committed, and the cloth is promised, not moved")
		check(game.world.goods_held() == [0,1,2,3,4],
			"drafting leaves every good hanging at its own stall: ownership is only computed from booked")
		check(game.status_line() == "线 1 / 5 · 满意 1 / 5" and game.world.state == game.state,
			"the tally is computed from the street the world was handed")
		tap("tray_2"); await process_frame; await settle()
		# ---- 5. 错法二：同一卷布许给两家 ----
		await click("good_0"); await click("tray_2"); await click("good_0"); await click("tray_3")
		check(game.state.lines == plan(-1,-1,0,0,-1) and Rules.double_promised(game.state.lines) == [0],
			"one bolt of cloth can be drafted onto two trays at once")
		await click("deliver")
		check(game.message.begins_with("布同时许给了丙摊、丁摊：一件货只能有一个新主人"),
			"the double promise is refused by naming the good and both stalls it was promised to")
		check(game.state.stage == "puzzle" and game.state.booked == EMPTY
			and game.state.lines == plan(-1,-1,0,0,-1),"the refusal changes nothing on the street")
		check(off_board() == 0,"the complaint reads inside its own board")
		await capture(prefix+"06-double-promise")
		# ---- 6. 重摆模态：先问，再清，还能撤销回来 ----
		# 底栏那枚按钮写着「重摆 X」：写了键就要按得到，鼠标不去底栏也能开同一张问句。
		await key(KEY_X)
		check(game.modal and game.state.lines == plan(-1,-1,0,0,-1),
			"X opens the same 重摆 question the button advertises")
		await click("cancel")
		await click("reset")
		check(game.modal and game.state.lines == plan(-1,-1,0,0,-1),"重摆 asks before wiping the street")
		await capture(prefix+"07-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.lines == plan(-1,-1,0,0,-1),"cancelling keeps the drafted street")
		await click("reset"); await click("confirm")
		check(game.state.lines == EMPTY and game.state.stage == "puzzle" and game.state.booked == EMPTY,
			"重摆 pulls every line back at once without leaving the street or booking anything")
		await key(KEY_Z)
		check(game.state.lines == plan(-1,-1,0,0,-1),"one undo puts the whole wiped street back")
		await click("reset"); await click("confirm")
		check(game.state.lines == EMPTY and game.world.goods_held() == [0,1,2,3,4],
			"and wiping again moves no good either")
		# ---- 7. 错法三：五摊挤进一个大环（规格点名的错法）----
		for pair in [[KEY_5,KEY_Q],[KEY_1,KEY_W],[KEY_4,KEY_E],[KEY_2,KEY_R],[KEY_3,KEY_T]]:
			await key(pair[0])
			await key(pair[1])
		check(game.state.lines == RING and Rules.cycle_lengths(game.state.lines) == [5],
			"five lines can be drawn into one big ring that touches all five stalls")
		check(Rules.satisfied(game.state.lines).is_empty(),
			"and that ring pleases not a single stall, however tidy it looks")
		await click("deliver")
		check(game.message.begins_with(Rules.SHAPE_RING) and "还有 5 处没有归位" in game.message
			and game.state.stage == "puzzle" and game.state.booked == EMPTY,
			"the five-ring is refused as a five-ring first, then stall by stall")
		check(hotspots_clear() == 0 and covered() == 0,
			"with all five arcs on the street nothing hides under the dialogue board")
		await capture(prefix+"08-five-ring")
		# ---- 8. 提示：三档封顶，只解释不动手 ----
		for _n in range(4): await click("hint")
		check(game.state.hint == Rules.HINTS and Rules.validate(game.state),
			"hints stop at the shipped tier count")
		check("三摊就转成了一圈" in game.message,"the top tier demonstrates one step of the three-stall ring")
		check(game.state.lines == RING,"a hint explains the street without moving a single line")
		check(off_board() == 0 and covered() == 0,"the hint text holds its own board over the ring")
		await capture(prefix+"09-hints")
		# ---- 9. 真修法：三摊一圈 + 两摊对换，一次交上 ----
		await click("reset"); await click("confirm")
		for receiver in range(Rules.COUNT):
			await click("good_%d" % Rules.SOLUTION[receiver])
			await click("tray_%d" % receiver)
		check(game.state.lines == Rules.SOLUTION and Rules.solved(game.state),
			"the unique plan is drawn stall by stall with nothing but clicks")
		check(game.status_line() == "线 5 / 5 · 满意 5 / 5"
			and game.world.line_paths().size() == Rules.COUNT,
			"all five stalls nod before a single good has left its own stall")
		check(hotspots_clear() == 0 and covered() == 0,"the shipped shape reads clear of every panel")
		await capture(prefix+"10-street-full")
		await click("deliver")
		check(game.state.stage == "exchanging" and game.state.booked == Rules.SOLUTION
			and game.state.lines == Rules.SOLUTION and game.state.hand == -1,
			"one commit books the whole street: the booked batch is exactly the drafted lines")
		check(game.world.line_paths().size() == Rules.COUNT
			and not game.buttons.has("good_0") and game.buttons.has("skip"),
			"the exchange keeps the performed lines and its own controls, and the street is no longer drawable")
		check(clicks_off() == 0,"the booked street cannot be edited mid-exchange")
		var batch = game.world.in_flight(game.world.carry_plan(0.0))
		var first = game.world.carry_plan(0.0)
		var resting = 0
		for lifted in first:
			if lifted["at"].distance_to(lifted["home"]) < 0.5: resting += 1
		check(batch["flying"].size() == Rules.COUNT and batch["landed"].is_empty() and resting == Rules.COUNT,
			"before the batch lifts every good still hangs at its own stall: no good vanishes into the air")
		await hold(2.2)
		var mid = game.world.carry_plan(game.world.progress)
		var moving = game.world.in_flight(mid)
		check(mid.size() == Rules.COUNT and moving["landed"].size() == 2 and moving["flying"].size() == 3,
			"the world's own carry plan says two goods have landed and three are still in the air")
		check(game.status_line() == "已落定 %d / 5" % moving["landed"].size(),
			"the running count quotes that world state, not a label of its own")
		# 门面那块牌跟着货落地：三件还在空中时不能改口，最后一件落进盘子那一刻才一起改。
		check(board_with("%s摊 · 有%s" % [Rules.ACTORS[0], Rules.GOODS[0]]) != "",
			"the shopfront still names the good hanging at it while three of five are in the air")
		var keep_progress: float = game.world.progress
		game.world.progress = 0.95
		game.world.queue_redraw() # explicit fixture pose while presentation is paused
		var landed_at = game.world.goods_held()[0]
		check(board_with("%s摊 · 有%s" % [Rules.ACTORS[0], Rules.GOODS[landed_at]]) != ""
			and board_with("%s摊 · 有%s" % [Rules.ACTORS[0], Rules.GOODS[0]]) == "",
			"the shopfronts change wording once the last good has landed in its tray")
		game.world.progress = keep_progress
		game.world.queue_redraw() # explicit fixture pose while presentation is paused
		var legible = 0
		for lifted in mid:
			if lifted["phase"] <= 0.1 or lifted["phase"] >= 0.9: continue
			var chord = lifted["home"].lerp(lifted["dest"], smoothstep(0.0,1.0,lifted["phase"]))
			if lifted["at"].distance_to(chord) > 4.0: legible += 1
		check(legible == 2,"every good in the air rides its own arc instead of sliding along a straight line")
		# 货既然说好了「沿着自己那条线走」，就把整条线逐点扫一遍：
		# 线本身、以及吊在线上那件货的货顶，全程都不许碰扣扣正在说的这块板。
		var spoken = dialogue_panel()
		check(spoken.get_area() > 0.0,"the exchange keeps its own dialogue board up, so the sweep has a target")
		var scraped = 0
		for entry in game.world.line_paths():
			for step in range(21):
				var at: Vector2 = game.world.arc_at(entry["giver"], entry["receiver"], step / 20.0)
				var thread = on_screen(Rect2(at - Vector2(2, 2), Vector2(4, 4)))
				var cargo = on_screen(kit_rect(Rules.KIT_GOODS[entry["giver"]], at, World.GOOD_WIDTH[entry["giver"]]))
				if spoken.intersects(thread) or spoken.intersects(cargo): scraped += 1
		check(scraped == 0,"no thread and no good scrapes the dialogue board anywhere along its own route")
		check(covered() == 0,"the goods in flight pass clear of the dialogue board and every other panel")
		await capture(prefix+"11-exchanging")
		game.paused = false; await create_timer(0.12).timeout
		paused_at = game.elapsed
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(0.12).timeout
		check(game.paused and game.elapsed == paused_at,"losing focus freezes the batch mid-air")
		check(game.buttons.pause.text == "继续动画","the frozen exchange offers to resume")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "delivery" and game.state.booked == Rules.SOLUTION,
			"the booked batch lands as one record")
		check(game.world.goods_held() == Rules.SOLUTION and game.world.shown_lines() == Rules.SOLUTION,
			"the world counts the hand-over itself: each stall now holds the good it accepted")
		check(game.world.line_paths().size() == Rules.COUNT,"the same five lines are what got booked")
		check(game.status_line() == "满意 5 / 5" and board_with("满意 5 / 5") != "",
			"the nodding stage reports five pleased stalls in the street and on the tally board")
		var on_screen_lights = 0
		for glass in lit_spots():
			var shown = on_screen(glass)
			if shown.position.x >= 0 and shown.position.y >= 0 and shown.end.x <= 1280.0 and shown.end.y <= 720.0: on_screen_lights += 1
		check(on_screen_lights == Rules.COUNT,"the first lit string stays inside the frame while the camera pulls back")
		check(string_covered() == 0,"no street board covers the lantern glass the scene lights up")
		await pose(2.06)
		check(covered() == 0 and hotspots_clear() == 0,"the nodding view hides nothing under its boards")
		await capture(prefix+"12-delivery")
		await click("skip")
		# ---- 10. 回执：只复述真的发生过的事 ----
		check(game.state.stage == "complete" and game.state.booked == Rules.SOLUTION
			and game.world.goods_held() == Rules.SOLUTION,
			"the lit string closes the scene with the same booked exchange")
		var paper = ui_text("件货各走一次")
		check(paper != null and "5 件货各走一次 · 5 摊点头" in paper.text,
			"the receipt header counts the goods that moved and the stalls that nodded")
		var restated = 0
		for giver in range(Rules.COUNT):
			var moved = "%s摊的%s → %s摊" % [Rules.ACTORS[giver], Rules.GOODS[giver], Rules.ACTORS[Rules.SOLUTION.find(giver)]]
			if paper != null and moved in paper.text: restated += 1
		check(restated == Rules.COUNT,"the receipt quotes the five lines the player actually booked")
		check(paper != null and Rules.SHAPE_CYCLE in paper.text,
			"and it names the shape that made the street work")
		check(paper != null and not ("还差" in paper.text or Rules.SHAPE_RING in paper.text
			or "圈数不对" in paper.text),"the receipt says nothing that did not happen")
		check(paper != null and fits(paper.text, 16, paper.size.x),"the exchange receipt holds its own paper")
		check(paper != null and paper.get_theme_font_size("font_size") >= 18,
			"the receipt keeps the house minimum type size")
		check(game.world.signs().size() == Rules.COUNT*2 + 2,
			"the closed street keeps its own boards: the receipt does not double them")
		# 甲摊门口那两块：交货之后门面牌念的是它换到手的那件（SOLUTION 把 乙 的油给了甲），
		# 需求牌不变；回执把同样的话复述一遍，所以只许接管这两块。
		check(receipt_overlaps() == ["%s摊 · 有%s" % [Rules.ACTORS[0], Rules.GOODS[Rules.SOLUTION[0]]],
				Rules.accepts_text(0)],
			"the only boards the receipt takes over are 甲's two, whose text it restates")
		check(off_board() == 0 and spilled_boards() == 0,"the receipt adds no text outside its own board")
		check(covered() == 0,"the receipt covers no tray, good, lantern or button")
		check(string_covered() == 0,"and no board covers the lit string either")
		check(game.world.state == game.state,"the world reads the committed street it was handed")
		await capture(prefix+"13-receipt")
		# ---- 11. 落盘与重进 ----
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the booked exchange reloads from disk exactly as booked")
		check(game.state.stage == "complete" and game.state.booked == Rules.SOLUTION
			and game.state.hint == Rules.HINTS,"a reload keeps the whole record, used hints included")
		check(not game.buttons.has("reset") and game.buttons["next"].text == "重新体验"
			and game.buttons.has("open_hub"),"a finished street cannot be wiped by an accidental click")
		check(off_board() == 0 and spilled_boards() == 0 and covered() == 0,
			"the reloaded closing view lays out the same as the one that was booked")
		await capture(prefix+"14-reload")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		var back: Control = game.buttons.back_hub
		check(back.size.x >= 48 and back.size.y >= 48,"the way back to the chart is a 48 pixel target or bigger")
		if not small: await capture("15-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"a standalone launch still finds its own way back to the chart")
		check(game.buttons.open_hub.size.x >= 48 and game.buttons.open_hub.size.y >= 48,
			"the standalone way out is a 48 pixel target or bigger")
		# ---- 12. 重新体验：先问，再从头走一遍，全程只用鼠标 ----
		await click("next")
		check(game.modal and game.state.stage == "complete","replaying the scene asks first")
		await click("cancel")
		check(game.state.booked == Rules.SOLUTION and ui_text("件货各走一次") != null,
			"cancelling keeps the receipt the player booked")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.beat == 0 and game.state.lines == EMPTY
			and game.state.booked == EMPTY and game.state.hint == 0,
			"重新体验 rewinds this street, lines, booking and used hints included")
		await click("next"); await click("next")
		check(game.state.beat == Rules.BEATS - 1 and game.state.stage == "arrival",
			"the same three lines carry the player back to the last beat")
		await click("next")
		check(game.state.stage == "approach","the third line convenes the five stalls again")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"the walk-in still stops before player control, under the same closed camera")
		for receiver in range(Rules.COUNT):
			await click("good_%d" % Rules.SOLUTION[receiver])
			await click("tray_%d" % receiver)
		check(game.state.lines == Rules.SOLUTION and Rules.solved(game.state),
			"the mouse-only replay draws the same unique plan")
		await click("deliver")
		check(game.state.stage == "exchanging" and game.state.booked == Rules.SOLUTION,
			"and books the whole street in one commit again")
		await click("skip"); await click("skip")
		check(game.state.stage == "complete" and game.world.goods_held() == Rules.SOLUTION,
			"the replayed street closes with all five goods handed over")
		check(ui_text("件货各走一次") != null and Rules.SHAPE_CYCLE in ui_text("件货各走一次").text,
			"and the receipt restates the shape the player replayed")
		check(off_board() == 0 and spilled_boards() == 0 and covered() == 0
			and string_covered() == 0 and clicks_off() == 0,
			"the replayed closing view adds no spilled, covered or live text")
		await capture(prefix+"16-replay-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK09 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

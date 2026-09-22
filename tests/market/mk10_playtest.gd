extends SceneTree
# MK10 实窗审计：真实窗口里走一遍「听三句话 → 走到预测板前 → 红船这条付得起却盖不住的约定被
# 逐条点名 → 换成蓝船一格一格重算 → 请扣扣提醒 → 空签擦格与撤销 → 重摆确认 → 全键盘重摆这张纸
# → 空格交单（本局是哪一单到这一刻才确认）→ 筹票离匣 → 三句订正 → 装船与离岸 → 回执」。
# 在 1280×720 与 960×540 各拍一遍，并检查木牌、回执、状态条与台词板上的汉字有没有爬出自己的边框。
const Scene = preload("res://game/market_mk10.tscn")
const Rules = preload("res://scripts/market/mk10_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
# 宿主三块板的内框：826 与 790 的板减去左右各 14 的内缩，关卡只能把文案压进这个宽度。
const BOARD = 798.0
const GOAL_BOARD = 762.0
const STATUS_BOARD = 300.0
const MODAL_BOARD = 560.0
# 陷阱这张纸：红船的两个真值算术全对，只是盖不住 6 箱那一单。
const TRAP = [6, 12]
# 唯一交得出去的纸面：蓝船 3 箱 7 票、6 箱 10 票。
const PAPER = [7, 10]
const BLANK = [-1, -1]
var game: Control
var checks = 0
var failures = 0
# 刚拍下的一帧留在这里：谁压住谁不能只信绘制顺序的口头约定，要拿两帧真像素比。
var shot: Image
var shots: Dictionary = {}
# 分支按新开一幕在 3 箱／6 箱之间轮流固定（读档绝不重抽），两条结算路径都得被真走过才算数。
var seen: Array = []
const CAPTURE = "res://docs/playtest/market-mk10-fare"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	shot = root.get_texture().get_image(); shot.save_png(CAPTURE+"/"+name+".png"); shots[name] = shot
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
# 摆好一个动画帧但不暂停：筹票在半空、封箱刚离开订单格这些中帧只有这里拍得到。
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
# 街面上的木牌由 plaque 直接画字，从不换行：一行比牌子还宽就爬到旁边的船与封箱上。
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
func targets() -> Array:
	var found := []
	for id in game.buttons:
		if str(id).begins_with("boat_") or str(id).begins_with("case_") or str(id).begins_with("tile_"):
			found.append([id, Rect2(game.buttons[id].position, game.buttons[id].size)])
	return found
# 十枚热点是这一关唯一能点的东西：小于 48 像素孩子点不准，越界或互压就点不到想要的那一格。
func hotspots() -> int:
	var live = 0
	for entry in targets():
		if entry[1].size.x < 48 or entry[1].size.y < 48: print("SMALL target ", entry[0], " ", entry[1])
		else: live += 1
	return live
func crowding() -> int:
	var trouble = 0
	var walked: Array = []
	for entry in targets():
		var rect: Rect2 = entry[1]
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 720:
			trouble += 1; print("OFFFRAME ", entry[0], " ", rect)
		for other in walked:
			if other[1].intersects(rect):
				trouble += 1; print("OVERLAP ", entry[0], " and ", other[0])
		walked.append(entry)
	return trouble
func label_with(parent: Node, needle: String) -> Label:
	for child in parent.get_children():
		if child is Label and str(child.text).contains(needle): return child
	return null
func ui_text(needle: String) -> Label:
	return label_with(game.ui, needle)
# 盒子挡不住溢出：Godot 会把 Control.size 抬到内容的最低尺寸，字照样长在板外。
# 所以拿标签的实际方框去比它脚下那块板（三块台词板与回执都算），板边之外一个字都不许有。
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
# 回执与街面实物、木牌、宿主三块板、出口按钮都在同一个 1280×720 平面上：谁压住谁只由矩形相交决定。
# 宿主那三块板的方框从这里现读，不照抄常量——它正被别的关一起调宽。
func covered() -> int:
	var over = 0
	var paper: Rect2 = game.receipt_rect()
	for board in game.world.signs():
		if paper.intersects(board["rect"]):
			over += 1; print("COVERED board ", board["text"], " by receipt ", paper)
	for slot in range(Rules.SLOTS):
		if paper.intersects(game.world.cell_rect(slot)):
			over += 1; print("COVERED order cell ", slot, " by receipt ", paper)
	for boat in range(Rules.BOATS):
		if paper.intersects(game.world.boat_rect(boat)):
			over += 1; print("COVERED boat ", boat, " by receipt ", paper)
	for index in range(Rules.TILES):
		if paper.intersects(game.world.tile_rect(index)):
			over += 1; print("COVERED slip ", index, " by receipt ", paper)
	for child in game.ui.get_children():
		if not child is Panel: continue
		var board = Rect2(child.position, child.size)
		if board == paper: continue
		if paper.intersects(board):
			over += 1; print("COVERED host board ", board, " by receipt ", paper)
	for id in ["next","open_hub","back_hub","leave_hub"]:
		if not game.buttons.has(id): continue
		if paper.intersects(Rect2(game.buttons[id].position, game.buttons[id].size)):
			over += 1; print("COVERED exit ", id, " by receipt ", paper)
	return over
# 按钮的字由 style_button 定在 20 号，但最低字号那套规则照样会把请求抬上去：
# 长标签（跳过当前动画、全部擦回空白）挤不出按钮就会断在木头外面，这里按抬升后的字号量一遍。
func cramped_buttons() -> int:
	var over = 0
	for id in game.buttons:
		var b: Button = game.buttons[id]
		if b.text.is_empty(): continue
		if not fits(b.text, 20, b.size.x - 14.0):
			over += 1; print("CRAMPED ", id, " '", b.text, "' needs ", widest_line(b.text, 20), " in ", b.size)
	return over
# 街面木牌各占一块木头：两块牌之间留不满 8 像素就会互相咬边。
# 离岸那句「随船」原来钉在 sail_point 左 100，正好压掉红船牌的右端和蓝船牌那两个字的上半。
func crossed_boards() -> int:
	var rects: Array = []
	for board in game.world.signs(): rects.append(board["rect"])
	var trouble = 0
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].grow(-4.0).intersects(rects[j].grow(-4.0)):
				trouble += 1
				print("CROSSED ", rects[i], " and ", rects[j])
	return trouble
# 木牌画在世界层，宿主的标题板、目标板、对白板和出口按钮都盖在它上面：
# 牌面爬到白板底下，那半句话就永远读不到——挪「随船」这块牌时最先撞的就是它。
# 比的是投影到屏幕之后的方框：delivery 前半程镜头还收在 1.10，世界坐标会整体往左上偏一截。
func crowded_boards() -> int:
	var trouble = 0
	var boards: Array = []
	for child in game.ui.get_children():
		if child is Panel: boards.append(Rect2(child.position, child.size))
	for id in ["next","open_hub","back_hub","leave_hub","pause","skip","undo","hint","deliver","reset"]:
		if game.buttons.has(id): boards.append(Rect2(game.buttons[id].position, game.buttons[id].size))
	for board in game.world.signs():
		var shown: Rect2 = on_screen(board["rect"])
		for panel in boards:
			var cut: Rect2 = shown.intersection(panel)
			if cut.size.x >= 1.0 and cut.size.y >= 1.0:
				trouble += 1
				print("UNDER ", board["text"], " ", shown, " under ", panel)
	return trouble
# 镜头是缩放+平移，世界的方框要换算到屏幕像素上才比得了截图与宿主的板（与 tap() 用的是同一套变换）。
func on_screen(rect: Rect2) -> Rect2:
	var t: Transform2D = game.world.get_global_transform_with_canvas()
	return Rect2(t * rect.position, rect.size * t.get_scale())
func ticket_board(foot: Vector2) -> Rect2: return Rect2(foot - Vector2(14, 36), Vector2(28, 38))
func crate_board(foot: Vector2) -> Rect2: return Rect2(foot - Vector2(18, 42), Vector2(36, 44))
# 两件姿态下这批货各自占的方框，与脚下某块木牌真正相交的那一小片——只有这一小片能作证。
# 牌子往里缩 6 像素再取交集：贴着牌边那一圈本来就在和背后的船身做抗锯齿混合，
# 而且货总有半截露在牌外，那几行像素即使货被埋着也会随姿态变——负控就是这么漏过去的。
func flight_over(first: Array, second: Array, shape: Callable) -> Array:
	var boxes: Array = []
	var planks: Array = []
	for board in game.world.signs(): planks.append(on_screen(board["rect"]).grow(-6.0))
	for plan in [first, second]:
		for entry in plan:
			var box: Rect2 = on_screen(shape.call(entry["at"]))
			for plank in planks:
				var cut: Rect2 = box.intersection(plank)
				if cut.size.x >= 3.0 and cut.size.y >= 3.0: boxes.append(cut)
	return boxes
# 演出的货还躲不躲得起宿主的板：flight_over 只跟街面木牌比，那块对白板是不透明的，
# 落在它底下就等于没演。原来七张筹票与抬上船的封箱正是整批藏在那块板后面（实窗两张中帧可证）。
# shrink 是这批货此刻按多大比例画出来：封箱跟着离岸那条船一起缩，量它的人也得一起缩，
# 不然一条缩到四成的船上会量出一排「比箱子还大一圈」的假埋没。
func under_boards(plan: Array, shape: Callable, shrink: float = 1.0) -> int:
	var planks: Array = []
	for child in game.ui.get_children():
		if child is Panel: planks.append(Rect2(child.position, child.size))
	var buried = 0
	for entry in plan:
		var drawn: Rect2 = shape.call(entry["at"])
		var box: Rect2 = on_screen(Rect2(entry["at"] + (drawn.position - entry["at"]) * shrink,
			drawn.size * shrink))
		for plank in planks:
			if box.intersection(plank).get_area() > box.get_area() * 0.25:
				buried += 1
				print("BURIED ", box, " under ", plank)
	return buried
# 把两件姿态的真像素逐点比一遍：货如果画在木头前面，它离开之后那块牌面必然留下变化；
# 一个像素都不差，就说明这批货从头到尾被木牌盖着，玩家根本看不见它被抬上船。
func changed_pixels(earlier: String, later: String, boxes: Array) -> int:
	var a: Image = shots[earlier]; var b: Image = shots[later]
	var scale = Vector2(a.get_width(), a.get_height()) / Vector2(1280, 720)
	var changed = 0
	var area = 0
	for rect in boxes:
		var r: Rect2 = Rect2(rect.position * scale, rect.size * scale)
		for y in range(maxi(0, int(r.position.y)), mini(a.get_height(), int(ceil(r.end.y)))):
			for x in range(maxi(0, int(r.position.x)), mini(a.get_width(), int(ceil(r.end.x)))):
				area += 1
				if a.get_pixel(x, y) != b.get_pixel(x, y): changed += 1
	print("DIAG flight ", earlier, "/", later, " area ", area, " changed ", changed)
	return changed
# 每一屏都要过的四件事：木牌不爬框、标签不压板、按钮字不挤、台词与目标一行放得下。
# 玩家按下的那一句（message）此刻正占着台词板，所以量的是屏幕上真显示的那段。
func clean_screens(label: String) -> void:
	var shown = game.message if not game.message.is_empty() else game.line()
	check(spilled_boards() == 0 and off_board() == 0 and cramped_buttons() == 0 and covered() == 0
		and crossed_boards() == 0 and crowded_boards() == 0
		and fits(shown, 20, BOARD) and fits(game.goal_line(), 22, GOAL_BOARD)
		and fits(game.status_line(), 20, STATUS_BOARD), label)

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK10 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk10-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.save_path == path,"试玩注入的落点没被 configure 的默认值盖掉，玩家档案不会被写坏")
		check(game.world.scene_id == "dock" and game.world.has_part("transport_boat_red")
			and game.world.has_part("transport_boat_blue") and game.world.has_part("crate_blue")
			and game.world.has_part("receipt_blank") and game.world.has_part("navigation_lantern"),
			"大码头用的是共享拆件包，不是关卡自己另画一套")
		check(game.world.actor_sheets.has("feather"),"折羽取的是森林岛共享伙伴表的离散帧，不是新裁的美术")
		check(game.state.stage == "arrival" and game.state.beat == 0 and game.state.written == BLANK
			and game.state.boat == -1 and game.state.paid == 0 and game.state.hint == 0,
			"开局两格空白、没选约定、一张筹票都没花")
		check(game.state.branch in Rules.CASES and game.state.keys().size() == 8,
			"本局是哪一张订单在开局就固定，存档只有那八个字段")
		seen.append(game.state.branch)
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"第一句只让玩家继续听，交单按钮还不存在")
		check(not game.buttons.has("boat_0") and not game.buttons.has("tile_0"),
			"剧情没走完，码头上什么都还点不了")
		check(board_with("本局确认") == "","开局绝不透露本局箱数：那块牌要到结算才出现")
		clean_screens("开场三句之前，码头上每块牌都待在自己那块木头里")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab 把键盘焦点交给第一句剧情")
		await key(KEY_ENTER)
		check(game.state.beat == 1 and "两个可能现在就摆上预测板" in game.line(),
			"Enter 在焦点上推进第二句：两种可能在剧情里就摆明")
		await click("next")
		check(game.state.beat == Rules.ARRIVAL_BEATS - 1 and "上限 10 张" in game.line()
			and "船底" in game.line() and game.buttons.next.text == "到预测板前看看",
			"第三句公开筹票上限与两条收费，末句才把玩家带过去")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"走位是一段真动画，能暂停也能跳过")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"暂停真的停住了走位时钟，镜头不会自己溜到板前")
		await hold(0.9)
		check(game.world.scale.x > 1.0 and game.world.scale.x < 1.10,"走近的过程里镜头一路收向预测板")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready" and game.buttons.next.text == "开始摆票额",
			"跳过把控制权交还给玩家，而不是直接开板")
		await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"板子交到玩家手上时镜头正贴在预测板前")
		check(hotspots() == Rules.BOATS + Rules.SLOTS + Rules.TILES and crowding() == 0,
			"两条船、两张订单格、六枚票额签共 10 枚热点：都不小于 48 像素、互不重叠、都在画面里")
		check(game.buttons.deliver.text == "按这条约定交单" and game.buttons.undo.disabled
			and not game.buttons.reset.disabled,"提交按钮说的就是这条约定，落第一笔之前撤销是灰的")
		check(game.status_line() == "未选约定 · 上限 %d 票" % Rules.BUDGET,
			"状态板只公开上限，没替玩家选约定")
		check(board_with("红船") == "红船" and board_with("没有开船票") == "没有开船票"
			and board_with("开船 4 票") == "开船 4 票" and board_with("每箱 2 票") == "每箱 2 票"
			and board_with("每箱 1 票") == "每箱 1 票",
			"两条约定三条牌全钉在各自船底，玩家不必回头翻台词")
		check(board_with("甲单 · 或运 3 箱") != "" and board_with("乙单 · 或运 6 箱") != ""
			and board_with("筹票匣 · 上限 10 张") != "","两种可能与匣子上限都写在街面上")
		check(board_with("还没写") == "还没写" and board_with("正在写这一格") == "正在写这一格",
			"空白格读作还没写，当前要写的那格有牌子跟着")
		check(game.world.tickets_left() == Rules.BUDGET and game.world.paid_tickets() == 0,
			"开板时十张筹票全在匣里：牌面上没有任何幻影花费")
		clean_screens("空板交付给玩家时，牌面与状态条都还在自己框里")
		await capture(prefix+"03-dock")
		# ---- 什么都没选就交单：只报这一条，不去数空格 ----
		await click("deliver")
		check(game.state.stage == "puzzle" and game.message == "还没选定运输约定：红船与蓝船的收费都贴在码头上。",
			"没选约定时只说这一条：空格与算法都还没到能判的时候")
		check("还有" not in game.message and game.state.paid == 0,"这条一出现就不再报别的缺口")
		clean_screens("第一条拒收没把台词板撑破")
		await capture(prefix+"04-no-bargain")
		# ---- 陷阱：红船。本局就算恰好付得起，这条约定也盖不住两种可能 ----
		tap("boat_0")
		check(game.transient > 0 and game.world.land_place == "boat" and game.world.land_slot == 0,
			"选定约定占用宿主 0.28 秒落下锁，关卡自己不另开时钟")
		check(game.world.landing("boat",0) > 0.5,"约定被选中的这一格还在落下")
		check(game.buttons.tile_0.disabled and game.buttons.deliver.disabled,
			"落下途中板子不能被改：连点两下不会写出没人看见的票额")
		await capture(prefix+"05-bargain-landing")
		await settle()
		check(game.state.boat == 0 and game.state.paid == 0 and is_equal_approx(game.transient, 0.0)
			and not game.buttons.tile_0.disabled,"落定之后纸面解禁，一条票都没花")
		check(game.status_line() == "红船 6/12 票 · 限 10","状态板现算红船两种可能的票额，不存第二计数")
		check(board_with("已选") == "红船 · 已选" and board_with("蓝船 · 已选") == "",
			"只有选中的那条船挂上已选，牌面不标对错")
		await click("case_0")
		check(game.world.picked == 0 and game.message == "现在写的是「运 3 箱」那一格：点一边的票额签。",
			"点订单格只是指定往哪一格写，一个票额都不动")
		check(game.buttons.has("tile_2") and "键盘 Q" in game.buttons.tile_0.tooltip_text
			and "键盘 S" in game.buttons.boat_1.tooltip_text,"每枚热点的无障碍标签都写着自己的键盘键")
		tap("tile_2")
		check(game.state.written == [6, -1] and game.world.land_place == "slip" and game.world.land_slot == 0,
			"票额签落在它被写进的那一格")
		check(game.world.landing("slip",0) > 0.5,"那一格的票额牌还悬在半空，没提前钉死")
		await capture(prefix+"06-slip-landing")
		await settle()
		check(game.world.landing("slip",0) == 0.0,"落下结束，那块牌回到订单格原位")
		await click("deliver")
		check(game.state.stage == "puzzle" and game.message.begins_with("「运 6 箱」那一格还空着：两种可能都要写在纸上。")
			and "（还有 1 处没有归位）" in game.message,
			"两格里还空着一格：先点名空格，再说还剩几处，一条一条来")
		await click("case_1"); await click("tile_5")
		check(game.state.written == TRAP and game.world.picked == 1,"换格再写：红船的两个真值都上了纸")
		check(game.world.tickets_left() == Rules.BUDGET and game.state.paid == 0,
			"算术全对的陷阱纸面照样一张票都没花")
		await click("deliver")
		check(game.message == "红船运 6 箱要 12 票，比 10 票多 2 票：盖不住两种可能。",
			"规格点名的陷阱被拒的正是「盖不住」，不是「本局付不起」")
		check(game.state.stage == "puzzle" and game.world.state == game.state,
			"拒收不改状态：世界读到的就是宿主已经落盘的那份纸")
		clean_screens("拒收红船这一刻没有回执、牌面也没溢出")
		await capture(prefix+"07-red-trap")
		await click("tile_5")
		check("已经写着" in game.message and game.state.written == TRAP,"同一枚签不能在格子里写两次")
		await click("boat_1")
		check(game.state.boat == 1 and game.state.written == TRAP and game.state.paid == 0,
			"换约定只换算法：纸上两格留着让玩家自己重算")
		check(game.message == "换成了蓝船：两格的票额得照这条约定重算。"
			and game.status_line() == "蓝船 7/10 票 · 限 10","换完约定状态板立刻改成蓝船那两个真值")
		await click("deliver")
		check(game.message.begins_with("3 箱那格写 6 票，蓝船按约定是 7 票。")
			and "（还有 1 处没有归位）" in game.message,"把红船纸面原样搬到蓝船上会一次点出两处算法")
		await click("case_0"); await click("tile_1")
		check(game.state.written == [4, 12],"常见误算：只算蓝船的开船票、漏了每箱那枚 4")
		await click("deliver")
		check(game.message.begins_with("3 箱那格写 4 票，蓝船按约定是 7 票。")
			and "还有 1 处" in game.message,"签盘上那枚 4 被点名的是漏掉的每箱 1 票")
		clean_screens("点名 4 票这一刻台词仍然一行放得下")
		await capture(prefix+"08-slip-miscount")
		await click("tile_3")
		check(game.state.written == [7, 12] and not Rules.solved(game.state),"改对一格，另一格还差着")
		await click("deliver")
		check(game.message == "6 箱那格写 12 票，蓝船按约定是 10 票。" and "还有" not in game.message,
			"最后一处算法单独点名，不再拖尾巴")
		await click("case_1"); await click("tile_4")
		check(game.state.written == PAPER and Rules.solved(game.state)
			and game.status_line() == "蓝船 7/10 票 · 限 10","唯一那份纸面由鼠标摆齐")
		check(game.world.tickets_left() == Rules.BUDGET,"摆齐纸面也还没交单：匣里还是十张")
		await click("boat_1")
		check(game.state.boat == -1 and game.state.written == PAPER and game.state.paid == 0,
			"再点已选那条船退回未选：纸上写过的不会被偷偷擦掉")
		await click("deliver")
		check(game.state.stage == "puzzle" and "还没选定运输约定" in game.message,
			"退回未选之后仍然交不出去，玩家得自己再选一次")
		await click("boat_1")
		check(game.state.boat == 1 and game.state.paid == 0,"重新选定这条约定照样不动账")
		# ---- 三档提示：主动索取、封顶、只动 hint ----
		var paper_snapshot = game.snapshot(game.state)
		for tier in range(4):
			await click("hint")
			check(game.state.hint == mini(Rules.HINT_TIERS, tier + 1),"第 %d 次索取停在第 %d 档" % [tier+1, tier+1])
		check("顶穿上限" in game.message and game.state.hint == Rules.HINT_TIERS,
			"第三档算清两个票额并点名红船先顶穿上限，第四次不再往前")
		check(game.snapshot(game.state) == paper_snapshot and game.state.written == PAPER
			and game.state.paid == 0 and game.world.tickets_left() == Rules.BUDGET,
			"提示只动 hint：纸面、结清与匣中张数一律不变")
		clean_screens("三档提示满打满算两行，也不出台词板")
		await capture(prefix+"09-hints")
		# ---- 空签把这一格擦回空白，撤销再按历史栈退回来 ----
		await click("case_0"); await click("tile_0")
		check(game.state.written == [-1, 10] and board_with("还没写") != "",
			"点空签就是把这一格擦回空白，牌面重新读作还没写")
		await click("undo")
		check(game.state.written == PAPER and game.world.state == game.state,
			"撤销走的是与落笔同一条历史栈，纸面回到擦掉之前")
		# ---- 重摆：先问、能取消、只退纸面 ----
		await click("reset")
		check(game.modal and game.state.written == PAPER and game.state.boat == 1,
			"重摆先弹确认，没确认之前纸面原样留着")
		check(label_with(game.overlay, "不会变") != null,"弹窗里就写明本局是哪一张订单不会变")
		check(fits(game.reset_prompt()[0], 22, MODAL_BOARD),"重摆那句确认放得进弹窗内框")
		clean_screens("弹窗浮在码头上时，底下的牌面依旧整齐")
		await capture(prefix+"10-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.written == PAPER and game.state.boat == 1,
			"取消之后回到同一张纸，什么都没擦")
		await click("reset"); await click("confirm")
		var branch_before = game.state.branch
		check(game.state.written == BLANK and game.state.boat == -1 and game.state.paid == 0
			and game.state.stage == "puzzle" and game.state.branch == branch_before,
			"重摆只退纸面：约定退回未选、格擦回空白，本局那一单不会被重抽")
		check(game.state.hint == Rules.HINT_TIERS and not game.buttons.undo.disabled,
			"提示次数不会被重摆洗掉，擦空的板子也还有一步可退")
		# ---- 纯键盘把这张纸重新摆出来，并用空格交单 ----
		await key(KEY_S)
		check(game.state.boat == 1,"S 选定蓝船这条约定")
		await key(KEY_1); await key(KEY_R)
		check(game.state.written == [7, -1],"1 选格、R 写 7 票")
		await key(KEY_2); await key(KEY_T)
		check(game.state.written == PAPER and Rules.solved(game.state),"2 选格、T 写 10 票：全键盘也能摆齐")
		await key(KEY_U)
		check(game.state.written == PAPER,"盘上没有的键不碰纸面，交回宿主")
		clean_screens("键盘摆齐的这份纸面上每块牌都在框里")
		await capture(prefix+"11-solved")
		check(root.gui_get_focus_owner() == null,
			"这一刻没有按钮占着键盘焦点，空格才真是宿主的提交键，而不是重按上一个按钮")
		var hint_before = game.state.hint
		send(KEY_SPACE); await process_frame; await process_frame
		check(game.state.stage == "confirming" and game.state.hint == hint_before,
			"空格交单通过：本局是哪一单到这一刻才确认，提示数也没被顺手改掉")
		var boxes = game.state.branch
		var paid_now = game.state.paid
		check(paid_now == Rules.fare(1, boxes) and paid_now in [7, 10],
			"一次性结清的只能是本局那一张订单的票额")
		check(game.world.paid_tickets() == paid_now
			and game.world.tickets_left() == Rules.BUDGET - game.world.ticket_plan(game.world.progress).size(),
			"匣子里的张数是现算的：承诺付掉 %d 张一分不少，剩下几张跟着它们离匣一张张走，画面不另存计数" % paid_now)
		check(not game.buttons.has("tile_0") and not game.buttons.has("deliver")
			and not game.buttons.has("reset") and game.buttons.has("skip"),
			"交单之后热点全部收起：不存在先付一半再改主意")
		check(game.state.written == PAPER and game.world.state == game.state,
			"结算阶段纸面冻结，世界读的就是宿主那份")
		for strayed in [KEY_A, KEY_S, KEY_Q, KEY_R, KEY_T, KEY_Y]:
			await send(strayed); await process_frame
		check(game.state.written == PAPER and game.state.boat == 1 and game.state.paid == paid_now,
			"结算动画里再敲摆票键也改不动这张纸")
		await process_frame
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await process_frame
		check(game.paused and game.buttons.pause.text == "继续动画","失焦自动暂停并把按钮换成继续")
		var frozen: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == frozen,"失焦冻结的是结票时钟，筹票不会偷偷飞完")
		await hold(0.9)
		var flying = game.world.ticket_plan(game.world.progress)
		check(flying.size() == paid_now,"半空里的筹票数正好是本局付掉的那 %d 张" % paid_now)
		var from_box_end = 0
		for step in range(flying.size()):
			if flying[step]["home"] == game.world.box_spot(Rules.BUDGET - 1 - step): from_box_end += 1
		check(from_box_end == paid_now,"筹票是从票匣末尾一张张被抽走的，不是在船头凭空长出来")
		var airborne = 0
		for entry in flying:
			if float(entry["phase"]) > 0.0 and float(entry["phase"]) < 1.0: airborne += 1
		check(airborne == paid_now and game.world.tickets_left() == Rules.BUDGET - flying.size(),
			"这一刻它们还在空中：匣子按离匣的张数现减，船头也还没收到")
		check(under_boards(flying, Callable(self,"ticket_board")) == 0,
			"半空里的筹票一张都不在宿主那块板底下：它们离匣是看得见的")
		var paying = game.world.paid_landed()
		check(paying < paid_now and board_with("付讫 %d 票" % paid_now) == "",
			"还有票在半空：付讫牌这一刻不能先把整单报满")
		check(game.world.confirmed_slot() == Rules.CASES.find(boxes)
			and board_with("本局确认：运 %d 箱" % boxes) != ""
			and board_with("付讫 %d/%d 票" % [paying, paid_now]) != "",
			"确认牌念的是本局真正的箱数，付讫牌念的是此刻已经落定的那几张，不是把整单一次报清")
		clean_screens("结票演出里两块新牌子也不越框")
		await capture(prefix+"12-ticket-flight")
		var flight_pose = prefix+"12-ticket-flight"
		await hold(1.5)
		var landed = game.world.ticket_plan(game.world.progress)
		await capture(prefix+"12b-ticket-crossing")
		check(game.world.paid_landed() > paying and under_boards(landed, Callable(self,"ticket_board")) == 0,
			"过半程已经有票落到收费牌上：付讫那个数跟着往前走，还在飞的那几张也没一张躲进板里")
		check(changed_pixels(flight_pose, prefix+"12b-ticket-crossing",
			flight_over(flying, landed, Callable(self,"ticket_board"))) > 0,
			"筹票飞过船底那两排收费牌时画在木头前面：两帧在牌面上确实留下了变化")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "clarify" and game.state.written == PAPER and game.state.paid == paid_now,
			"跳过把演出收尾，纸面与结清都留在承诺过的那份上")
		check(at_camera(1.10, Vector2(-64,-43)),"三句订正仍然在预测板前说完")
		check("不是货没送到，是回信没送到" in game.line(),"第一句订正的是回信，不是这批货")
		await click("next")
		check("单号我已经订正过" in game.line() and "无论最后回哪封信" in game.line(),
			"第二句把这一单接回第四幕那条寄出去没人回的线")
		await click("next")
		check(game.state.beat == Rules.CLARIFY_BEATS - 1 and "查询信" in game.line()
			and game.buttons.next.text == "看这一单的回执","第三句把查询信交给这条船，末句才放船离岸")
		check(game.world.crate_alpha(game.world.confirmed_slot()) > 0.9
			and game.world.crate_alpha(1 - game.world.confirmed_slot()) < 0.5,
			"没被确认那一单的封箱退成背景，两种可能的对照留在画面上")
		check(board_with("随船 · 一封查询信") == "","货还没离岸，随船那句牌先不出现")
		clean_screens("三句订正说完，牌面与船底都没被演出挤歪")
		await capture(prefix+"13-clarify")
		await click("next")
		check(game.state.stage == "delivery" and Rules.BUDGET - game.world.tickets_left() == paid_now,
			"离岸这一段匣子里就少那么多张")
		await hold(1.05)
		var carried = game.world.carry_plan(game.world.progress)
		check(carried.size() == boxes,"抬上船的封箱数就是本局那一单的 %d 箱" % boxes)
		check(game.world.hide_while_moving(carried).size() == boxes
			and game.world.deck_load(game.state.boat).is_empty(),
			"前半程格子里那份被遮住：板上还有一份＋船上又一份的双影是要不得的")
		check(under_boards(carried, Callable(self,"crate_board")) == 0,
			"刚离开订单格的封箱还在看得见的那一段路上：一头栽进台词板底下的装船不算装船")
		clean_screens("装船中帧上订单格与船底牌都还各就各位")
		await capture(prefix+"14-crating")
		var crate_pose = prefix+"14-crating"
		await hold(1.6)
		var lifted = game.world.carry_plan(game.world.progress)
		await capture(prefix+"14b-crate-high")
		check(under_boards(lifted, Callable(self,"crate_board")) == 0,
			"快落到甲板上的封箱还整只露着：落在船帮上而不是落在台词板里")
		check(changed_pixels(crate_pose, prefix+"14b-crate-high",
			flight_over(carried, lifted, Callable(self,"crate_board"))) > 0,
			"封箱被抬过船底那两排收费牌时画在木头前面，不是藏在牌子底下")
		await hold(3.8)
		check(game.world.sailing() and game.world.sail_amount() > 0.5,
			"后半程这条船朝海一侧离岸，缩的正是被选中的那条")
		check(game.world.boat_alpha(1 - game.state.boat) == 1.0
			and game.world.boat_foot(1 - game.state.boat) == game.world.boat_spot(1 - game.state.boat),
			"另一条船一动不动：离岸的是一条约定撑起的这一单")
		check(game.world.deck_load(game.state.boat).size() == boxes
			and game.world.deck_spot(game.state.boat, 0, boxes).distance_to(
				game.world.carry_plan(game.world.progress)[0]["at"]) < 1.0,
			"后半程甲板上的箱数与演出落点重合，同一份货不画两遍")
		check(under_boards(game.world.deck_load(game.state.boat), Callable(self,"crate_board"),
			game.world.boat_scale(game.state.boat)) == 0,
			"落在甲板上的那一横排整只都在台词板下面：这一单的货看得见才叫装上船")
		check(board_with("随船 · 一封查询信") == "随船 · 一封查询信",
			"离岸的船上钉着那句查询信，与章末欠着的几封回信对上")
		clean_screens("离岸与查询信那块牌都留在自己位置上")
		await capture(prefix+"15-sailing")
		await click("skip")
		check(game.state.stage == "complete" and at_camera(1.0, Vector2.ZERO),
			"回执阶段镜头拉回整个大码头，离岸那条船还在画面里")
		check(game.buttons.next.text == "重新体验" and game.buttons.has("open_hub")
			and not game.buttons.has("reset") and not game.buttons.has("deliver"),
			"单独启动这一幕有自己的回航图路，结算之后不能重摆")
		check(game.buttons.open_hub.position == Vector2(690, 646)
			and game.buttons.open_hub.size.x >= 48 and game.buttons.open_hub.size.y >= 48,
			"回千灯航图用右下角那块共用位置，尺寸够孩子点")
		check("无论最后回哪封信" in game.line() and "齿轮工坊" in game.line(),
			"收尾那句把这一单接回工坊那几封没人回的信")
		var sheet = ui_text("大码头 · 无论回哪封信")
		check(sheet != null and sheet.text == "\n".join(game.receipt_lines()),
			"屏幕上那张回执就是规则现算出来的六行，没有第二套措辞")
		check(sheet != null and "蓝船 %d 票" % Rules.fares(1)[0] in sheet.text
			and "蓝船 %d 票" % Rules.fares(1)[1] in sheet.text,
			"回执复述两种可能各自的票额：这一单不管回哪张都算得清")
		check(sheet != null and "上限 %d 票 · 两种都没顶穿" % Rules.BUDGET in sheet.text,
			"回执写的是这条约定盖得住两种可能，不是哪一种更便宜")
		check(sheet != null and "本局运 %d 箱 · 付讫 %d 票 · 余 %d 张" % [boxes, paid_now, Rules.BUDGET - paid_now]
			in sheet.text,"回执念的箱数、付讫与余票就是这一局真发生的三个数")
		check(sheet != null and "查询信" in sheet.text and "齿轮工坊" in sheet.text,
			"随船那封查询信进了回执，为章末那几封回信开路")
		check(sheet != null and "红船" not in sheet.text,"没被选中的那条约定不会被写成结果")
		check(sheet != null and fits(sheet.text, 16, game.receipt_text_rect().size.x),
			"回执六行每行都留在纸的宽度里")
		if sheet != null and not fits(sheet.text, 16, game.receipt_text_rect().size.x):
			print("DIAG receipt needs ", widest_line(sheet.text, 16), " in ", game.receipt_text_rect().size.x)
		check(sheet != null and sheet.get_theme_font_size("font_size") >= 18,"回执不低于屋里最小字号")
		check(game.world.deck_load(game.state.boat).size() == boxes
			and game.world.tickets_left() == Rules.BUDGET - paid_now,
			"读完回执这一刻，船上的箱数与匣里的余票仍然对得上这一单")
		clean_screens("回执摊开之后没有任何字爬到板外，也没有任何纸压住别的东西")
		await capture(prefix+"16-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"从磁盘重开就是结完这一单的那份状态，本局那一单不会被重抽")
		check(game.state.stage == "complete" and game.state.paid == paid_now and game.state.branch == boxes,
			"读档保留阶段、结清与本局那一单")
		check(not game.buttons.has("reset") and not game.buttons.has("deliver"),
			"重开这一幕不会被一次误点改回摆票阶段")
		check(ui_text("大码头 · 无论回哪封信") != null and covered() == 0,
			"重开之后回执照样摊在同一块海面上，不压任何东西")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"航图送过来的这一趟只被消费一次")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"从航图进来只给回去那一条路，不留第二条出口")
		var back: Control = game.buttons.back_hub
		check(back.size.x >= 48 and back.size.y >= 48,"返回千灯航图那颗不小于 48 像素")
		if not small: await capture("17-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"单独启动这一幕仍然找得回自己的航图")
		await click("next")
		check(game.modal and game.state.stage == "complete","重新体验先问一句，不会一按就把回执洗掉")
		check(fits(game.restart_prompt()[0] + "\n只重置本关，不改变其他关卡与森林岛进度。", 22, MODAL_BOARD),
			"重开那句确认连同宿主补的那句放得进弹窗内框")
		await click("cancel")
		check(game.state.written == PAPER and game.state.stage == "complete","取消留在已经结清的这一单上")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.beat == 0 and game.state.written == BLANK
			and game.state.boat == -1 and game.state.paid == 0 and game.state.hint == 0,
			"重新体验把这一幕洗回开局：纸面、约定、结清与提示全部归零")
		if game.state.branch != boxes: seen.append(game.state.branch)
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","还是那三句话把玩家带回预测板前")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"走位照样停在交出控制权之前，镜头回到板前")
		await click("boat_1"); await click("case_0"); await click("tile_3")
		await click("case_1"); await click("tile_4")
		check(game.state.written == PAPER and game.state.boat == 1 and Rules.solved(game.state),
			"纯鼠标这条路重新摆出同一份纸面")
		await click("deliver")
		check(game.state.stage == "confirming" and game.state.paid == Rules.fare(1, game.state.branch),
			"重演的这一局结的是它自己那一单的票")
		if game.state.branch != boxes: seen.append(game.state.branch)
		await click("skip")
		check(game.state.stage == "clarify","跳过结票之后照样听那三句订正")
		await click("next"); await click("next")
		check(game.state.beat == Rules.CLARIFY_BEATS - 1,"三句订正一句都没被重演吞掉")
		await click("next")
		check(game.state.stage == "delivery","最后一句才放这条船离岸")
		await click("skip")
		check(game.state.stage == "complete"
			and game.world.deck_load(game.state.boat).size() == game.state.branch
			and game.world.tickets_left() == Rules.BUDGET - game.state.paid,
			"重演收在同样的账上：船装本局那一单的箱数，匣里剩下没花的票")
		var again = ui_text("大码头 · 无论回哪封信")
		check(again != null and "本局运 %d 箱 · 付讫 %d 票" % [game.state.branch, game.state.paid] in again.text,
			"重演那张回执说的是这一局真发生的数，不抄上一局")
		clean_screens("重演之后没有任何字爬到板外，也没有任何纸压住别的东西")
		await capture(prefix+"18-replay-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	check(seen.has(3) and seen.has(6),"两条分支在实窗里都被真走过：结的清分别是 7 票与 10 票")
	print("MARKET MK10 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

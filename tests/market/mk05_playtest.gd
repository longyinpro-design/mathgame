extends SceneTree
# MK05 实窗审计：真实窗口里走一遍「雨里三句话 → 拿起货签 → 按上订单板 → 一家一箱送过去」，
# 在 1280×720 与 960×540 各拍一次，并检查街面上的木牌、柜台上的纸与回执有没有互相压住。
const Scene = preload("res://game/market_mk05.tscn")
const Rules = preload("res://scripts/market/mk05_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
# 上一次点击之后剩下的落纸锁定，以及世界层认定「刚落下」的那一处：锁定没退干净就点下一张会点空。
var lock_left = 0.0
var land_seen = ""
const CAPTURE = "res://docs/playtest/market-mk05-labels"
# 板面：去处按街上从左到右（面包铺、育苗铺、桥头、邮亭），值是货签编号。
const EMPTY := [-1, -1, -1, -1]
const SOLUTION := [1, 0, 2, 3]
const TRAP := [2, 0, -1, 3]
const DOUBLED := [1, 1, 2, 3]
# 街面上的字是 plaque()/words() 手画的，汉字不会自动断行：牌面宽度由 mk05_world 自己写死。
const CARVED = 16
const KEPT_BOARD = 110.0 # 128 宽的残句牌，字从左缘里 10 像素起画，留 8 像素刀口
const NAME_BOARD = 162.0 # 180 宽的店名牌与牌头，同上
const TAG_BOARD = 46.0 # 76 宽的货签纸，字从 foot.x-16 起画，只许用到右缘里 8 像素

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
	lock_left = game.transient; land_seen = game.world.land_place
	while game.transient > 0: await process_frame
func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame
	lock_left = game.transient; land_seen = game.world.land_place
	while game.transient > 0: await process_frame
# 演出停在指定秒数上好拍照：先把时钟冻住，再顺手把按钮文案改成真值，免得拍到一个说谎的「暂停动画」。
func hold(seconds: float) -> void:
	game.paused = true; game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	await process_frame; game.refresh()
func landed(what: String) -> bool: return lock_left > 0.0 and land_seen == what
func text_w(value: String, px: int) -> float:
	var widest := 0.0
	for line in value.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return widest
func fits(text: String, px: int, width: float) -> bool:
	return text_w(text, px) <= width
func hits(moved: Dictionary, group: String, index: int) -> bool:
	return moved.has(group) and (moved[group] as Dictionary).has(index)
# 共用宿主的三块牌子：目标 (442,20,790,48)、台词 (338,98,826,68)、状态 (470,656,300,42)，
# 木牌本身归 level_host，这里只保证本关写进去的句子装得下（text_size() 会抬到 18/22/28）。
# 台词牌此刻显示的是拒绝理由还是台词，由 message 决定，量的一直是屏幕上真正那一句。
func said() -> String:
	return game.message if not game.message.is_empty() else game.line()
func boards_fit() -> int:
	var over = 0
	for row in [[game.goal_line(), UIStyle.text_size(22), 762.0],
			[said(), UIStyle.text_size(20), 798.0],
			[game.status_line(), UIStyle.text_size(20), 300.0],
			["千灯集市  /  "+game.title, UIStyle.text_size(24), 366.0]]:
		if not fits(row[0], row[1], row[2]):
			over += 1; print("SPILL board ", row[0], " needs ", text_w(row[0], row[1]), " in ", row[2])
	return over
func carved(text: String, board: float, where: String) -> bool:
	var need = text_w(text, CARVED)
	if need <= board: return false
	print("SPILL street ", where, " ", text, " needs ", need, " in ", board); return true
# 街面上此刻画着的每一句：残句牌、店名/「收 X」牌、订单板牌头、柜台牌、摊着的货签名。
func carved_over() -> int:
	var over = 0
	for place in range(Rules.PLACES.size()):
		over += 1 if carved(Rules.KEPT[place], KEPT_BOARD, "kept") else 0
		var held: int = game.state.assign[place]
		var caption = Rules.PLACE_CN[place] if held < 0 else "%s · 收 %s" % [Rules.PLACE_CN[place], Rules.GOODS_FULL[held]]
		over += 1 if carved(caption, NAME_BOARD, "caption") else 0
	over += 1 if carved("订单板 · 三句留下的话", NAME_BOARD, "board head") else 0
	over += 1 if carved("柜台 · 四张货签", NAME_BOARD, "counter") else 0
	for good in range(Rules.GOODS.size()):
		if game.state.assign.has(good): continue
		over += 1 if carved(Rules.GOODS_FULL[good], TAG_BOARD, "tag face") else 0
	return over
# 汉字不会自动断行：一行最短的连续文字比盒子还宽，就会横着画到旁边的货上。
func spilled(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = child.get_combined_minimum_size()
		if needed.x > child.size.x + 1 or needed.y > child.size.y + 1:
			over += 1; print("SPILL ", child.text, " needs ", needed, " in ", child.size)
	return over
# 自动断行的标签只会把 min size 报成一行的样子：22 像素的字一行 33、行距 3，
# 三行就要 105 像素，画在 74 像素高的台词牌内框里第三行直接掉出牌外。这里按真字体量再核一次高度。
func cramped(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var px: int = child.get_theme_font_size("font_size")
		var pitch: float = UIStyle.face().get_height(px) + child.get_theme_constant("line_spacing")
		var lines: int = child.text.count("\n") + 1
		var need: float = pitch * (lines - 1) + UIStyle.face().get_string_size("国", HORIZONTAL_ALIGNMENT_LEFT, -1, px).y
		if need > child.size.y + 1:
			over += 1; print("CRAMP ", lines, " lines of ", px, "px need ", need, " in ", child.size, " ", child.text)
	return over
# 回执之类的纸面板不能盖住它正在复述的那四张订单（含残句牌与店名牌）。
func covering() -> int:
	var over = 0
	var xform: Transform2D = game.world.get_global_transform_with_canvas()
	var zoom: Vector2 = Vector2(xform.x.x, xform.y.y)
	for child in game.ui.get_children():
		if not child is Panel: continue
		var box = Rect2(child.get_global_position(), child.size)
		for place in range(Rules.PLACES.size()):
			for paper in [game.world.card_rect(place), game.world.kept_rect(place), game.world.name_rect(place)]:
				var on_screen = Rect2(xform * paper.position, paper.size * zoom)
				if box.intersects(on_screen):
					over += 1; print("COVER ", box, " over ", on_screen)
	return over
# 热点在镜头缩放之后仍要整块留在窗口里，否则玩家点到的只是半个格子。
func clipped() -> int:
	var over = 0
	for id in game.buttons:
		var b: Control = game.buttons[id]
		var xform: Transform2D = b.get_global_transform_with_canvas()
		var box = Rect2(xform * Vector2.ZERO, b.size * Vector2(xform.x.x, xform.y.y))
		if box.position.x < 0 or box.position.y < 0 or box.end.x > 1280.0 or box.end.y > 720.0:
			over += 1; print("CLIP ", id, " ", box)
	return over
# 四只箱子各走各的：同一帧里两件货的脚点挨得太近，屏幕上就是两张糊在一起的图。
func closest_flight() -> float:
	var nearest := 9999.0
	var probe := 0.0
	while probe <= 1.0001:
		var carried = game.world.carry_plan(probe)
		for i in range(carried.size()):
			for j in range(i + 1, carried.size()):
				nearest = minf(nearest, carried[i]["at"].distance_to(carried[j]["at"]))
		probe += 0.01
	return nearest

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK05 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk05-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival" and "被雨糊成了一片" in game.line(),
			"opens on the rain-soaked labels, not on a puzzle")
		check(not game.modal and game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"nothing can be handed over before the walk-in")
		check(spilled(game.ui) == 0 and cramped(game.ui) == 0 and boards_fit() == 0,
			"the first line keeps to its wooden board")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next, "Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1, "Enter advances the focused line")
		await click("next")
		check(game.buttons.next.text == "走进灯芯街", "the last line names the walk-in")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"the third line walks the player into the street")
		await click("pause")
		var frozen_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == frozen_at, "camera pause freezes the walk-in")
		await hold(0.5)
		check(game.world.progress > 0.3 and game.world.progress < 0.4, "the walk-in holds a mid-motion frame")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready", "approach stops before player control")
		await click("next")
		check(game.state.stage == "puzzle", "the order board is handed to the player")
		var small_target = 0
		for id in game.buttons:
			if not id.begins_with("good_") and not id.begins_with("place_"): continue
			var b: Control = game.buttons[id]
			if b.size.x < 48 or b.size.y < 48: small_target += 1
		check(small_target == 0, "all four labels and four order cards are 48 pixel targets or bigger")
		check(clipped() == 0 and covering() == 0, "no target hides behind the dialogue board or the button row")
		check(spilled(game.ui) == 0 and cramped(game.ui) == 0 and carved_over() == 0 and boards_fit() == 0,
			"the empty street keeps every carved line inside its board")
		check(game.state.assign == EMPTY and game.buttons.undo.disabled,
			"the board opens empty and has nothing to undo yet")
		await capture(prefix+"03-empty-board")
		# ---- 键盘：1-4 拿起货签，Q/W/E/R 按上那一家 ----
		await key(KEY_2)
		check(game.state.hand == 1 and game.history.is_empty(),
			"a number key lifts a label and costs no undo step")
		await key(KEY_Q)
		check(game.state.assign == [1,-1,-1,-1] and game.state.hand == -1,
			"Q presses the held label onto 面包铺")
		check(landed("card"), "the new label drops onto its paper with a landing bounce")
		await key(KEY_1); await key(KEY_Q)
		check(game.state.assign == [0,-1,-1,-1] and game.buttons.good_1.disabled == false
			and game.buttons.good_0.disabled, "pressing a filled shop sends the last label back to the counter")
		await key(KEY_3); await key(KEY_Q)
		await key(KEY_1); await key(KEY_W)
		await key(KEY_4); await key(KEY_R)
		check(game.state.assign == TRAP, "布与纸按读得清的那两句各就各位，铜铃还糊在面包铺")
		await click("deliver")
		check(game.state.stage == "puzzle" and "面包铺不收铃" in game.message
			and "铜铃按在了面包铺" in game.message and "还有 1 处" in game.message,
			"the refused hand-over names the sentence the board breaks and how many are left")
		check(spilled(game.ui) == 0 and cramped(game.ui) == 0 and boards_fit() == 0, "the refusal still fits inside its dialogue board")
		await capture(prefix+"04-refused")
		for n in range(4): await click("hint")
		check(game.state.hint == Rules.HINTS and "不收 铜铃" in game.message,
			"the third reminder shows the elimination step and the fourth changes nothing")
		check(spilled(game.ui) == 0 and cramped(game.ui) == 0 and boards_fit() == 0, "the longest reminder keeps to its board")
		await capture(prefix+"05-reminders")
		await click("reset"); await click("cancel")
		check(game.state.assign == TRAP, "cancelling 重摆 leaves every label where the player pressed it")
		await key(KEY_Z)
		check(game.state.assign == [2,0,-1,-1] and game.state.hand == 3,
			"撤销 Z hands the last label back into the player's hand")
		await click("place_3")
		check(game.state.assign == TRAP, "pressing that shop again puts it back without picking twice")
		# ---- 鼠标：把板子摆成唯一的那一对 ----
		await click("good_1"); await click("place_0")
		await click("good_2"); await click("place_2")
		check(game.state.assign == SOLUTION and Rules.solved(game.state),
			"the mouse path closes the only matching the three sentences allow")
		check(clipped() == 0 and covering() == 0 and carved_over() == 0, "a full board crowds nothing")
		await capture(prefix+"06-solved-board")
		# ---- 演出：一家一箱，路上不许叠成一团，也没人提前到货 ----
		await click("deliver")
		check(game.state.stage == "delivery" and game.buttons.has("skip"),
			"the accepted board releases the hand-over")
		await hold(0.2)
		var moved = game.world.in_flight(game.world.carry_plan(game.world.progress))
		check(hits(moved,"flying",1) and hits(moved,"still",0) and hits(moved,"waiting",1),
			"the second box is still on the counter while the first is already away")
		await hold(0.9)
		check(closest_flight() >= 30.0, "the four parcels keep a hand's width apart for the whole walk")
		await capture(prefix+"07-hand-over")
		await hold(2.4)
		moved = game.world.in_flight(game.world.carry_plan(game.world.progress))
		check(not hits(moved,"waiting",0) and hits(moved,"waiting",1) and hits(moved,"waiting",3),
			"only the shop the box really reached shows its goods")
		await capture(prefix+"08-nearly-there")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		frozen_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == frozen_at, "focus loss freezes the hand-over mid-flight")
		if small:
			await click("skip")
		else:
			await click("pause")
			check(not game.paused, "the same button hands the clock back to the animation")
			var frames = 0
			while game.state.stage == "delivery" and frames < 900:
				await process_frame; frames += 1
		check(game.state.stage == "complete", "the hand-over ends on the receipt")
		check(spilled(game.ui) == 0 and cramped(game.ui) == 0 and carved_over() == 0 and covering() == 0 and boards_fit() == 0,
			"the finished street adds no spilled, covered or clipped text")
		var paper: Label = null
		for child in game.ui.get_children():
			if child is Label and "验货回执 · 灯芯街" in child.text: paper = child
		check(paper != null, "the street hands out a receipt")
		var rows = 0
		for place in range(Rules.PLACES.size()):
			if paper != null and paper.text.contains("%s 收 %s" % [Rules.PLACE_CN[place], Rules.GOODS_FULL[SOLUTION[place]]]):
				rows += 1
		check(rows == 4, "the receipt restates all four pairings the player actually pressed")
		check(paper != null and fits(paper.text, paper.get_theme_font_size("font_size"), paper.size.x),
			"the receipt holds its own paper")
		check(game.buttons.has("open_hub") and game.buttons.open_hub.text == "回千灯航图",
			"a standalone launch is offered the way back to the chart")
		check(not game.buttons.has("back_hub"), "the chart's own return button waits for the chart")
		await capture(prefix+"09-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk, "the finished matching reloads from disk exactly as booked")
		check(not game.buttons.has("reset"), "a finished scene is not reset by an accidental click")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		await capture(prefix+"10-back-to-chart")
		await click("next")
		check(game.modal and game.state.stage == "complete", "replaying the scene asks first")
		check(spilled(game.overlay) == 0 and cramped(game.overlay) == 0, "the restart question keeps to its own board")
		await capture(prefix+"11-restart-asked")
		await click("cancel")
		check(game.state.assign == SOLUTION, "cancelling keeps the receipt the player earned")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.assign == EMPTY and game.state.hint == 0,
			"重新体验 rewinds only this station")
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach", "the same three lines carry the player back to the street")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle" and game.buttons.has("leave_hub"),
			"the board reopens and the chart stays one click away")
		await click("hint")
		check(game.state.hint == 1, "the reminders are readable again after a replay")
		# 一张签同时按两家：正常点击做不到（柜台那一张已被按走），只有坏档才会出现，但它也必须被当面拒绝。
		game.state.assign = DOUBLED.duplicate(true); game.state.hand = -1; game.refresh()
		await click("deliver")
		check(game.state.stage == "puzzle" and "灯油同时按在了面包铺、育苗铺" in game.message
			and "一张货签只能对应一家" in game.message,
			"a label pinned onto two shops is refused out loud, not swallowed silently")
		check(spilled(game.ui) == 0 and cramped(game.ui) == 0 and boards_fit() == 0, "the doubled refusal is short enough to read")
		await capture(prefix+"12-double-refused")
		await click("reset"); await click("confirm")
		check(game.state.assign == EMPTY and game.state.hint == 1,
			"全部取回 clears the board and keeps the reminder already read")
		await key(KEY_Z)
		check(game.state.assign == EMPTY and game.state.stage == "puzzle",
			"undo refuses to put the doubled board back")
		await click("deliver")
		check("还有 4 家没按货签" in game.message and "面包铺、育苗铺、桥头、邮亭" in game.message,
			"an empty board counts every shop still waiting")
		await click("good_1"); await click("place_0")
		await click("good_0"); await click("place_1")
		await click("good_2"); await click("place_2")
		await click("good_3"); await click("place_3")
		check(game.state.assign == SOLUTION and Rules.solved(game.state),
			"the same eight clicks match the four shops again")
		await click("undo")
		check(game.state.assign == [1,0,2,-1] and game.state.hand == 3 and game.buttons.good_3.disabled == false,
			"撤销把最后按上的那张又放回手里")
		await key(KEY_Z)
		check(game.state.assign == [1,0,-1,-1] and game.state.hand == 2, "the keyboard undoes the same step")
		await click("place_2")
		await click("good_3"); await click("place_3")
		check(game.state.assign == SOLUTION and game.state.hand == -1, "and pressing again puts the pair back")
		check(clipped() == 0 and carved_over() == 0 and covering() == 0, "the restacked board still fits")
		await capture(prefix+"13-board-restacked")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK05 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

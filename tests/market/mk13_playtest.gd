extends SceneTree
# MK13 实窗审计：真实窗口里走一遍「听她说清对折这件事 → 走到柜前 → 把整包摊上 11 格样边尺
# → 先撞招牌陷阱（两包 5 段只剩 1 格，第三包根本拿不起来）→ 再撞 v2 新加的那一条
# （5+3+3 摊得满、对折照不齐）→ 退回一包改摊 3+5+3 → 交给扣扣补边 → 看边一段一段缝上围巾
# → 听她学徒第一次送货 → 自愿换上补好的边」，在 1280×720 与 960×540 各拍一遍。
# 量的是这一关在屏幕上真实说出口的话：柜面木牌、底栏读数、回执与台词板的字宽，
# 尺框与回执有没有压住围巾或爬出纸边，尺面画的折线有没有落在规则层折过去的那一格正中，
# 以及一条 v2 才有的界外事实——样边尺只有 11 格，摊不下的那一包拿不起来，屏上永远不会出现「多出几段」。
const Scene = preload("res://game/market_mk13.tscn")
const Level = preload("res://scripts/market/mk13_scene.gd")
const Rules = preload("res://scripts/market/mk13_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 两条 11 段摊法：陷阱是 5 段先上尺（拿的先后决定摊在哪几格），活路是 5 段那一包跨过折线。
const TRAP = [0, 2, 3]
const WIN = [2, 0, 3]
const TENS = [0, 1]
# 对折两头齐只放过这一串格子：左三格 3 段、中间五格 5 段压住折线、右三格 3 段。
const EVEN_CELLS = [3, 3, 3, 5, 5, 5, 5, 5, 3, 3, 3]
# 底栏那一条的设计宽度是宿主给的 300：拿设计宽度量，才不会自己抬自己。
const STATUS_ROOM = 300.0
const CAPTURE = "res://docs/playtest/market-mk13-scarf"
var game: Control
var checks = 0
var failures = 0

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
# 演出只推进、不暂停：先让宿主按新进度换算一次镜头，读到的才不是上一帧的旧镜头。
func pose(seconds: float) -> void:
	game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	game.update_camera()
	await process_frame
func hold(seconds: float) -> void:
	game.paused = true; await pose(seconds)

func widest(text: String, px: int) -> float:
	var span := 0.0
	for line in text.split("\n"):
		span = maxf(span, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return span
# 底栏、台词板与回执走 UIStyle.text：20 抬到 22、18 抬到 22，量的是抬起之后的那一号。
func fits(text: String, requested: int, width: float) -> bool:
	return widest(text, UIStyle.text_size(requested)) <= width
# 汉字不会自动断行：一行最短的连续文字比盒子还宽，就会横着画到旁边的货上。
func spilled(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = child.get_combined_minimum_size()
		if needed.x > child.size.x + 1 or needed.y > child.size.y + 1:
			over += 1; print("SPILL ", child.text, " needs ", needed, " in ", child.size)
	return over
# 盒子挡不住溢出：Godot 会把 Control.size 抬到内容的最低尺寸，字照样长在纸外。
# 所以拿标签的实际方框去比它脚下那块板（台词板、目标牌、回执纸都算），板边之外一个字都不许有。
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
# 柜面木牌由 plaque 直接画字、从不换行：量的是牌上真正用的那一号字（14、15），
# 不像 UIStyle.text 会被抬到 22。一行比牌子内宽还长，字就横着爬到尺面或旁边的货上。
func plaque_ok(text: String, rect: Rect2, px: int) -> bool:
	if widest(text, px) > rect.size.x - 20.0:
		print("PLAQUE ", text, " needs ", widest(text, px), " in ", rect.size.x - 20.0); return false
	if px > rect.size.y:
		print("PLAQUE too short for ", px, "px: ", text, " in ", rect.size.y); return false
	return true
# 牌上的字面全部取自世界自己画的那几行：改字之后审计量的仍是新字面，不会量到旧话。
func plaques_all_fit() -> bool:
	var all := plaque_ok(Rules.shelf_caption(game.state, Rules.FIVE), game.world.shelf_plaque(Rules.FIVE), 15)
	all = plaque_ok(Rules.shelf_caption(game.state, Rules.THREE), game.world.shelf_plaque(Rules.THREE), 15) and all
	if game.state.stage == "puzzle":
		all = plaque_ok(Rules.gauge_caption(game.state), game.world.board_plaque(), 15) and all
		all = plaque_ok("包不能剪开 · 对折要两头齐", game.world.rule_plaque(), 14) and all
	if game.state.stage == "delivery":
		all = plaque_ok("扣扣在缝边 · 已缝 %d 段" % game.world.sewn(), game.world.board_plaque(), 15) and all
	if game.state.stage in ["story", "complete"]:
		all = plaque_ok("围巾的边 · %d 段全缝上了" % Rules.NEED, game.world.board_plaque(), 15) and all
		all = plaque_ok(game.world.look_caption(), game.world.look_plaque(), 14) and all
	return all
func laid_runs() -> int:
	var n := 0
	for id in game.buttons:
		if id.begins_with("run_"): n += 1
	return n
# 底栏读数与回执都是宿主画在 ui 上的 Label：按内容认出它，才能量它说的是哪一边。
func label_with(needle: String) -> Label:
	for child in game.ui.get_children():
		if child is Label and str(child.text).contains(needle): return child
	return null
func status_bar() -> Label:
	return label_with(game.status_line())

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("MK13 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk13-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival" and "11 段" in game.line(),"opens on 扣扣 counting her scarf, not on a puzzle")
		check("一包 3 段，或者一包 5 段" in game.line(),"the first line states the two pack sizes the counter sells by")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		check("对折" in game.line() and "两头要一样长" in game.line(),
			"the second line tells the folding condition before the counter")
		await click("next")
		check(game.state.beat == 2,"the last of the three lines is still hers")
		check("折线正压在第 6 格上" in game.line(),"the third line names the crease cell the gauge is built with")
		await click("next")
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
		var labelled = 0
		for id in game.buttons:
			if not id.begins_with("stock_") and not id.begins_with("run_"): continue
			var b: Control = game.buttons[id]
			if b.size.x < 48 or b.size.y < 48: small_target += 1
			if not b.tooltip_text.is_empty(): labelled += 1
		check(small_target == 0,"every package on the counter and on the gauge is a 48 pixel target or bigger")
		check(labelled == Rules.packages(),"every package carries its own tooltip")
		check(game.buttons.deliver.text == "交给扣扣补边","the submit button asks for the hem, not for a score")
		check(game.goal_line() == "整包摊满 11 格 · 对折过来两头要一段对一段",
			"both conditions stay on the board the whole time, never hidden until the submit")
		check(spilled(game.ui) == 0 and off_board() == 0,
			"no counter text spills out of its box on an untouched gauge")
		check(game.world.board_frame().position.y > 184 and game.world.board_frame().end.x < 1281,
			"the gauge stands clear of the dialogue board and inside the frame")
		check(not game.world.board_frame().intersects(game.world.scarf_hem(KOUKOU_WAVE)),
			"the gauge does not lean on 扣扣's scarf")
		# 折线是尺面自己画的：它必须落在第 6 格正中，玩家拿它比对两头时才数得对。
		check(absf(game.world.crease_x() - game.world.cell_rect(Rules.CREASE - 1).get_center().x) < 0.01,
			"the crease the world draws is the middle of cell 6, the cell the rules fold on")
		check(game.world.crease_x() > game.world.board_frame().position.x
			and game.world.crease_x() < game.world.board_frame().end.x,
			"the crease stands on the gauge face, not off either end of it")
		check(plaques_all_fit(),"the shelf tags, the gauge tag and the house-rule tag hold their own words")
		await capture(prefix+"02-counter")
		# --- 招牌陷阱：最先看中的那两包 5 段，加上「摊不下的那一包根本拿不起来」 ---
		await key(KEY_1); await key(KEY_2)
		check(game.state.hand == TENS and Rules.total(game.state) == 10,"the two tempting 5-段 packages lie on the gauge")
		await key(KEY_3)
		check(game.state.hand == TENS and game.message == "样边尺只剩 1 格：3 段的整包摊不进去，包不能剪开。",
			"the third package is refused at the counter, with the gauge's own free cells named")
		check(not game.modal and game.world.laid() == 10,"a package that cannot fit never reaches the gauge")
		await click("stock_3")
		check(game.state.hand == TENS and Rules.total(game.state) <= Rules.NEED,
			"pointing at a second refused pack keeps the gauge inside its 11 cells")
		await click("deliver")
		check(game.state.stage == "puzzle"
			and game.message == "两包 5 段已经 10 段，尺上只剩 1 格：柜上没有 1 段的整包。",
			"the near miss is answered in the contract's own words, not as a scolding")
		check(not game.modal and Rules.validate(game.state),"a wrong count never opens a modal")
		var bar = status_bar()
		check(bar != null and bar.text == "2 包 · 10 段摊在尺上" and "-" not in bar.text and "多出" not in bar.text,
			"the bottom bar only counts what is on the gauge, so a minus can never be printed")
		check(bar != null and fits(bar.text, 20, STATUS_ROOM) and spilled(game.ui) == 0 and off_board() == 0,
			"the reading stays inside its own strip of the bottom bar")
		check(plaques_all_fit(),
			"the shelf tag still holds its own words once both 5-段 packages are off the counter")
		await capture(prefix+"03-two-fives")
		await key(KEY_Z)
		check(game.state.hand == [0] and game.message.is_empty(),"undo takes the second package back and withdraws that sentence")
		# --- v2 新加的那一条：摊得满不等于对折齐 ---
		await key(KEY_3); await key(KEY_4)
		check(game.state.hand == TRAP and Rules.total(game.state) == Rules.NEED,
			"5 + 3 + 3 fills every one of the 11 cells")
		check(not Rules.folds_even(game.state) and Rules.cells(game.state) != EVEN_CELLS,
			"that same split is the one the fold refuses")
		await click("deliver")
		check(game.state.stage == "puzzle" and game.message == Rules.shortfalls(game.state)[0]
			and game.message == "11 段摊满了：对折过来第 1 格是 5 段包，第 11 格是 3 段包，两头不齐。",
			"a full but uneven gauge is refused by naming the two cells that miss each other")
		check(not game.modal and game.world.laid() == Rules.NEED,
			"the cloth stays on the gauge: the fold is what she checks, not the count")
		await capture(prefix+"04-full-but-uneven")
		await key(KEY_4)
		check(game.state.hand == [0, 2]
			and game.message == "把 3 段那一包退回柜面了：样边尺上现在摊了 8 段，还差 3 格。",
			"returning a package re-reads the gauge in the cells that are open again")
		await click("deliver")
		check(game.message == "5 段 + 3 段 是 8 段，还差 3 段：3 格空位摊得下 3 段，也摊得下 5 段。",
			"a short count is named in the segments laid and the pack sizes that still fit")
		var lone = game.state.duplicate(true)
		lone.hand = [0]
		check(Rules.shortfalls(lone)[0] == "一包 5 段，还差 6 段：对折要两头齐，先想好哪一包压住折痕。",
			"one package on the gauge is named once, not twice over")
		await key(KEY_1)
		check(game.state.hand == [2]
			and game.message == "把 5 段那一包退回柜面了：样边尺上现在摊了 3 段，还差 8 格。",
			"clicking the pack still marked on the counter returns the whole 5-段 run")
		# --- 三级提示：只提点，不代劳，也不判分 ---
		var asked = game.state.duplicate(true)
		for n in range(3): await click("hint")
		check(game.state.hint == 3 and "跨过折线" in game.message,
			"the third hint points at the pack that has to straddle the crease")
		check(spilled(game.ui) == 0 and off_board() == 0 and fits(game.message, 20, 798),"a hint stays inside its own board")
		for word in ["重做","错了","笨"]: check(not word in game.message,"the third hint never grades the player")
		check(game.state.hand == asked.hand and game.world.laid() == Rules.total(asked),
			"asking never carries a package for the player")
		await key(KEY_1); await key(KEY_4)
		check(game.state.hand == WIN and Rules.solved(game.state),"moving the 5-段 pack onto the crease is the player's own move")
		check(Rules.cells(game.state) == EVEN_CELLS,"the one pattern the gauge accepts is three, five on the crease, three")
		var middle = game.world.run_rect(game.state, 1)
		check(absf(middle.get_center().x - game.world.crease_x()) < 0.01,
			"the world lays that 5-段 run squarely across the crease it draws")
		check(laid_runs() == 3,"each package keeps its own stretch on the gauge")
		bar = status_bar()
		check(bar != null and bar.text == "3 包 · 11 段摊在尺上","the full gauge reads eleven 段 in three packages")
		check(fits(bar.text, 20, STATUS_ROOM) and plaques_all_fit(),
			"a full gauge still keeps every reading inside its own board")
		await capture(prefix+"05-solved-gauge")
		await click("deliver")
		check(game.state.stage == "delivery","an exact, evenly folded 11 段 releases the sewing")
		await hold(2.1)
		check(game.world.progress > 0.4 and game.world.progress < 0.6,"the sewing runs in one continuous motion")
		check(game.world.sewn() > 3 and game.world.sewn() < Rules.NEED,"only part of the edge is on her scarf mid-sewing")
		check(game.world.laid() == Rules.NEED - game.world.sewn(),
			"every segment sewn onto her scarf leaves the gauge: the two counts add up to 11")
		check(plaques_all_fit(),"the sewing tag holds its own words")
		await capture(prefix+"06-sewing")
		game.paused = false
		var running = game.elapsed
		await process_frame; await process_frame; await process_frame
		check(game.elapsed > running,"the sewing starts again on its own")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed
		await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at and game.buttons.pause.text == "继续动画",
			"focus loss freezes the sewing and says so on the button")
		await click("skip")
		check(game.state.stage == "story" and game.state.beat == 0,"the sewing hands over to her own story")
		check(game.world.sewn() == Rules.NEED,"the whole edge is on her scarf by the time she talks")
		check(game.buttons.has("wear") and game.buttons.wear.text == "换上补好的围巾","the mended look is offered, not applied")
		check(game.goal_line().is_empty() and spilled(game.ui) == 0,"her story is not captioned as a task")
		check(Rules.solved(game.state) and game.state.worn == 0,"the scarf is mended by the split the player laid")
		await capture(prefix+"07-story")
		await click("next")
		check(game.state.beat == 1,"the story keeps its own beats")
		await click("wear")
		check(game.state.worn == 1 and not game.modal and game.buttons.wear.text == "换回原来的样子",
			"wearing the mended edge is one saved, reversible choice")
		check(game.world.look_caption() == "补好的边 · 戴在外面" and plaques_all_fit(),
			"the look tag says what she is wearing and holds its own words")
		await click("wear")
		check(game.state.worn == 0 and game.world.look_caption() == "补好的边 · 藏在领子里","hiding it again is the same one click")
		await click("wear")
		await capture(prefix+"08-wearing-it")
		await click("next"); await click("next")
		check(game.state.stage == "complete" and Rules.validate(game.state),"the last line ends on the receipt")
		var paper = label_with("回执 · 育苗铺补边布")
		check(paper != null and paper.text.contains("拿的包：3 段 + 5 段 + 3 段 = 11 段"),
			"the receipt restates the packages the player carried, in the order she laid them")
		check(paper != null and paper.text.contains("对折过来：两头一段挨着一段，正好齐")
			and paper.text.contains("柜上还剩：5 段 1 包 · 3 段 1 包"),
			"the receipt states the fold that was checked and what the counter lost")
		var stacked := 0.0
		if paper != null:
			for row in range(paper.get_line_count()): stacked += paper.get_line_height(row)
		check(paper != null and paper.get_line_count() == game.receipt_text().split("\n").size()
			and paper.position.y + stacked <= Level.RECEIPT_TEXT.end.y + 1,
			"every receipt line is written on the paper, none hangs off its bottom edge")
		check(paper != null and fits(paper.text, 18, Level.RECEIPT_TEXT.size.x)
			and spilled(game.ui) == 0 and off_board() == 0,"the receipt holds its own paper")
		check(Rect2(Level.RECEIPT_TEXT.position, Level.RECEIPT_TEXT.size).encloses(Rect2(paper.position, paper.size))
			and not Level.RECEIPT.intersects(game.world.scarf_hem(KOUKOU_WAVE))
			and not Level.RECEIPT.intersects(game.world.board_frame()),
			"the receipt paper lies on its panel, off her scarf and off the gauge")
		var rects = [game.buttons.wear.get_global_rect(), game.buttons.next.get_global_rect()]
		if game.buttons.has("open_hub"): rects.append(game.buttons.open_hub.get_global_rect())
		var clear = true
		for a in range(rects.size()):
			for b in range(a+1, rects.size()):
				if rects[a].intersects(rects[b]): clear = false
		check(clear,"the offer, the receipt and the way out never overlap each other")
		await capture(prefix+"09-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the finished errand reloads with the look the player chose")
		check(game.state.worn == 1,"the voluntary appearance flag survives a reload")
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
		check(game.state.hand == WIN and game.state.worn == 1,"cancelling keeps the scarf the player mended")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.hand.is_empty() and game.state.worn == 0,
			"replaying the scene rewinds only this station")
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","the same three lines carry the player back to the counter")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","the walk-in still stops before player control")
		# 鼠标路径必须给出与键位路径同一个拿法：先 3 段、再 5 段压折线、最后 3 段。
		await click("stock_2"); await click("stock_0"); await click("stock_3")
		check(game.state.hand == WIN and Rules.solved(game.state),"the mouse path carries the same three packages")
		await click("run_2")
		check(game.state.hand == [2, 0] and "8 段" in game.message,"clicking the laid run returns that package to the shelf")
		await click("stock_3")
		check(game.state.hand == WIN,"the same package comes off the shelf again")
		await click("hint")
		await click("reset"); await click("confirm")
		check(game.state.hand.is_empty() and game.state.hint == 1,"重摆 puts every package back and keeps the hint already asked for")
		check(not game.buttons.has("run_0") and game.message.is_empty(),"the gauge is empty and silent after 重摆")
		check(game.world.laid() == 0 and game.world.sewn() == 0,"every cell of the gauge is open again")
		await click("deliver")
		check(game.state.stage == "puzzle"
			and game.message == "尺上还空着一格没摊：包不能剪开，摊满 11 格、对折两头齐，扣扣才收钱。",
			"an empty gauge names its own gap and repeats both conditions")
		await capture(prefix+"10-reset-counter")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK13 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

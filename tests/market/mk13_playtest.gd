extends SceneTree
# MK13 实窗审计：真实窗口里走一遍「听她说 → 走到柜前 → 把整包摊上样边尺 → 交给扣扣补边
# → 看边一段一段缝上围巾 → 听她学徒第一次送货 → 自愿换上补好的边」，
# 在 1280×720 与 960×540 各拍一次，并检查柜面与围巾上的文字有没有爬出自己的牌子。
const Scene = preload("res://game/market_mk13.tscn")
const Level = preload("res://scripts/market/mk13_scene.gd")
const Rules = preload("res://scripts/market/mk13_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const WIN = [0, 2, 3]
const TENS = [0, 1]
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
func hold(seconds: float) -> void:
	game.paused = true; game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
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
# 柜面上的木牌是画上去的，不是 Label：只能按牌子的内宽量一遍字宽。
func plaque_fits(text: String, rect: Rect2, size_px: int) -> bool:
	return fits(text, size_px, rect.size.x - 20.0)
func laid_runs() -> int:
	var n := 0
	for id in game.buttons:
		if id.begins_with("run_"): n += 1
	return n
# 底栏那条读数是宿主直接画在 ui 上的 Label：按内容认出它，才能量它说的是哪一边。
func status_bar() -> Label:
	var said = game.status_line()
	for child in game.ui.get_children():
		if child is Label and child.text == said: return child
	return null

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
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		check("只够拿三包" in game.line(),"the second line tells the money limit before the counter")
		await click("next")
		check(game.state.beat == 2,"the last of the three lines is still hers")
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
		check(spilled(game.ui) == 0,"no counter text spills out of its box on an untouched gauge")
		check(game.world.board_frame().position.y > 184 and game.world.board_frame().end.x < 1281,
			"the gauge stands clear of the dialogue board and inside the frame")
		check(not game.world.board_frame().intersects(game.world.scarf_hem(KOUKOU_WAVE)),
			"the gauge does not lean on 扣扣's scarf")
		check(plaque_fits(Rules.shelf_caption(game.state, Rules.FIVE), game.world.shelf_plaque(Rules.FIVE), 15)
			and plaque_fits(Rules.gauge_caption(game.state), game.world.board_plaque(), 15),
			"the shelf tags and the gauge tag hold their own words")
		await capture(prefix+"02-counter")
		# --- 招牌陷阱：最先看中的那两包 5 段 ---
		await key(KEY_1); await key(KEY_2)
		check(game.state.hand == TENS and Rules.total(game.state) == 10,"the two tempting 5-段 packages lie on the gauge")
		check(plaque_fits(Rules.shelf_caption(game.state, Rules.FIVE), game.world.shelf_plaque(Rules.FIVE), 15),
			"the shelf tag still holds its own words once both 5-段 packages are off the counter")
		await capture(prefix+"03-two-fives")
		await click("deliver")
		check(game.state.stage == "puzzle" and game.message == "两包 5 段已经 10 段，可是第三包只能整包拿，没有 1 段的。",
			"the near miss is answered in the contract's own words, not as a scolding")
		check(not game.modal,"a wrong count never opens a modal")
		await key(KEY_Z)
		check(game.state.hand == [0] and game.message.is_empty(),"undo takes the second package back and withdraws that sentence")
		await key(KEY_3)
		check(game.state.hand == [0, 2],"a 5-段 package with a 3-段 one lays 8 段 on the gauge")
		await click("deliver")
		check("8 段" in game.message and "还差 3 段" in game.message,"the short count is named in the segments the player laid")
		var lone = game.state.duplicate(true)
		lone.hand = [0]
		check(Rules.shortfalls(lone)[0] == "一包 5 段，围巾的边要 11 段：还差 6 段，手上还能再拿 2 包。",
			"one package on the gauge is named once, not as 「5 段 是 5 段」")
		await capture(prefix+"04-eight-on-the-gauge")
		# --- 摊多了：底栏要跟着换成「多出」，负号永远不该出现在屏上 ---
		await key(KEY_2)
		check(game.state.hand == [0, 2, 1] and Rules.total(game.state) == 13,"a third package can overshoot the gauge")
		var bar = status_bar()
		check(bar != null and "3 包 · 13 段 · 多出 2 段" in bar.text and "-" not in bar.text,
			"the bottom bar reads the overshoot as 2 段 too many, never as a minus")
		check(bar != null and fits(bar.text, 20, bar.size.x) and spilled(game.ui) == 0,
			"the overshoot reading stays inside its own strip of the bottom bar")
		await click("deliver")
		check(game.state.stage == "puzzle" and "多出 2 段" in game.message
			and spilled(game.ui) == 0 and fits(game.message, 20, 798),
			"13 段 is refused in one line the dialogue board holds whole")
		await key(KEY_2)
		check(game.state.hand == [0, 2] and Rules.total(game.state) == 8,"taking the extra package back leaves 8 段 on the gauge")
		# --- 三级提示：只提点，不代劳，也不判分 ---
		for n in range(3): await click("hint")
		check(game.state.hint == 3 and "5 + 3 + 3 = 11" in game.message,"the third hint states the whole split and stops there")
		check(spilled(game.ui) == 0 and fits(game.message, 20, 798),"a hint stays inside its own board")
		for word in ["重做","错了","笨"]: check(not word in game.message,"the third hint never grades the player")
		await key(KEY_4)
		check(game.state.hand == WIN and Rules.solved(game.state),"adding the second small package is the player's own move")
		check(laid_runs() == 3,"each package keeps its own stretch on the gauge")
		await capture(prefix+"05-solved-gauge")
		await click("deliver")
		check(game.state.stage == "delivery","an exact 11 段 releases the sewing")
		await hold(2.1)
		check(game.world.progress > 0.4 and game.world.progress < 0.6,"the sewing runs in one continuous motion")
		check(game.world.sewn() > 3 and game.world.sewn() < Rules.NEED,"only part of the edge is on her scarf mid-sewing")
		await capture(prefix+"06-sewing")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the sewing")
		await click("skip")
		check(game.state.stage == "story" and game.state.beat == 0,"the sewing hands over to her own story")
		check(game.world.sewn() == Rules.NEED,"the whole edge is on her scarf by the time she talks")
		check(game.buttons.has("wear") and game.buttons.wear.text == "换上补好的围巾","the mended look is offered, not applied")
		check(game.goal_line().is_empty() and spilled(game.ui) == 0,"her story is not captioned as a task")
		await capture(prefix+"07-story")
		await click("next")
		check(game.state.beat == 1,"the story keeps its own beats")
		await click("wear")
		check(game.state.worn == 1 and not game.modal and game.buttons.wear.text == "换回原来的样子",
			"wearing the mended edge is one saved, reversible choice")
		check(plaque_fits("补好的边 · 戴在外面", game.world.look_plaque(), 14),"the look tag holds its own words")
		await capture(prefix+"08-wearing-it")
		await click("next"); await click("next")
		check(game.state.stage == "complete" and Rules.validate(game.state),"the last line ends on the receipt")
		var paper: Label = null
		for child in game.ui.get_children():
			if child is Label and "回执 · 育苗铺补边布" in child.text: paper = child
		check(paper != null and paper.text.contains("拿的包：5 段 + 3 段 + 3 段 = 11 段"),
			"the receipt restates the packages the player actually carried")
		check(paper != null and paper.text.contains("柜上还剩：5 段 1 包 · 3 段 1 包"),
			"the receipt states what the counter lost")
		check(paper != null and fits(paper.text, 18, paper.size.x) and spilled(game.ui) == 0,"the receipt holds its own paper")
		check(Rect2(Level.RECEIPT_TEXT.position, Level.RECEIPT_TEXT.size).encloses(Rect2(paper.position, paper.size))
			and not Level.RECEIPT.intersects(game.world.scarf_hem(KOUKOU_WAVE)),
			"the receipt paper lies on its panel and off her scarf")
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
		await click("stock_0"); await click("stock_2"); await click("stock_3")
		check(Rules.solved(game.state),"the mouse path carries the same three packages")
		await click("run_2")
		check(game.state.hand == [0, 2] and "8 段" in game.message,"clicking the laid run returns that package to the shelf")
		await click("stock_3")
		check(game.state.hand == WIN,"the same package comes off the shelf again")
		await click("hint")
		await click("reset"); await click("confirm")
		check(game.state.hand.is_empty() and game.state.hint == 1,"重摆 puts every package back and keeps the hint already asked for")
		check(not game.buttons.has("run_0") and game.message.is_empty(),"the gauge is empty and silent after 重摆")
		await click("deliver")
		check(game.state.stage == "puzzle" and "手里还空着" in game.message,"an empty gauge names its own gap")
		await capture(prefix+"10-reset-counter")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK13 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

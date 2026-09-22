extends SceneTree
# MK04 实窗审计：真实窗口里走一遍「听完争吵 → 沿两条原约实换 → 给转抄件改签 → 核对收据 → 翻出回执」，
# 在 1280×720 与 960×540 各拍一次，并检查柜面上的单纸、文字与落地动画有没有各就各位。
const Scene = preload("res://game/market_mk04.tscn")
const Rules = preload("res://scripts/market/mk04_rules.gd")
const World = preload("res://scripts/market/mk04_world.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
# 最近一次点击之后观察到的落地锁：>0 才说明货物真的当着玩家的面落下。
var lock = 0.0
const CAPTURE = "res://docs/playtest/market-mk04-receipt"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
# 一次真实点击：按下、抬起、等一帧，但不排掉落地锁，让调用方能看见货物在半空的那一帧。
func press(id: String) -> void:
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false,"button unavailable "+id); return
	var b: Control = game.buttons[id]
	var logical = b.get_global_transform_with_canvas()*(b.size/2)
	var point = logical*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
	await process_frame
func click(id: String) -> void:
	await press(id)
	lock = game.transient
	while game.transient > 0: await process_frame
func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame
	lock = game.transient
	while game.transient > 0: await process_frame
func drain() -> void:
	while game.transient > 0: await process_frame
func hold(seconds: float) -> void:
	game.paused = true; game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	game.world.queue_redraw() # explicit fixture pose while presentation is paused
	await process_frame
func label_with(needle: String) -> Label:
	for child in game.ui.get_children():
		if child is Label and needle in child.text: return child
	return null
func panel_over(rect: Rect2) -> Panel:
	for child in game.ui.get_children():
		if child is Panel and Rect2(child.position,child.size).encloses(rect): return child
	return null
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
# 白板只有 sign 那么大：文字长高了就会从板子下沿爬出去，压住柜面上的货与单纸。
func off_board(parent: Node) -> int:
	var out = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var box = Rect2(child.position, child.size)
		for other in parent.get_children():
			if not other is Panel: continue
			var board = Rect2(other.position, other.size)
			if not board.has_point(box.position): continue
			if box.end.y > board.end.y + 3 or box.end.x > board.end.x + 3:
				out += 1; print("OFFBOARD ", child.text.replace("\n","\\n"), " ", box, " past ", board)
	return out
# 引擎画在柜面上的每一行字都得当场量得下它那块板子。
func drawn(text: String, size_px: int, room: float, tag: String) -> void:
	for line in text.split("\n"):
		var run = UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(size_px)).x
		check(run <= room, "%s 的「%s」量得下 %.0f 像素（%d）" % [tag, line, room, int(run)])
# 单纸真正的占位：裁剪图 237×316、anchor (118.5,308)，脚点之上才是纸面。
func paper(foot: Vector2, width: float) -> Rect2:
	return Rect2(foot - Vector2(width/2, width*World.PAPER_TOP), Vector2(width, width*World.PAPER_TALL))
func on_board(rect: Rect2) -> Rect2:
	var xf: Transform2D = game.world.get_global_transform_with_canvas()
	var a = xf*rect.position; var b = xf*(rect.position+rect.size)
	return Rect2(a,b-a).abs()
func card_paper(index: int) -> Rect2: return on_board(paper(game.world.card_foot(index), World.CARD_WIDTH))
func cand_paper(index: int) -> Rect2: return on_board(paper(game.world.cand_foot(index), World.CAND_WIDTH))
# 抬起来的货物与小纸片都是脚点朝下的裁剪图：按 manifest 的锚点算出真正占地的方框。
func carried_box(entry: Dictionary) -> Rect2:
	var claim: bool = entry["what"] == "claim"
	var id: String = "receipt_blank" if claim else World.GOODS[entry["what"]][0]
	var width: float = World.CAND_WIDTH if claim else World.GOODS[entry["what"]][1]
	var tex: Texture2D = game.world.atlases[id]
	var scale = width / tex.get_width()
	var anchor: Array = game.world.parts[id].anchor_px
	return Rect2(entry["at"] - Vector2(anchor[0], anchor[1]) * scale,
		Vector2(tex.get_width(), tex.get_height()) * scale)
# 扣扣的头与耳朵：脚点往上 122 像素，头占上半截。货物不许横着盖住这一格。
func koukou_head() -> Rect2:
	var dims = World.KOUKOU_TIE.get_size() * 0.5
	var box = Rect2(game.world.station("resident") - Vector2(dims.x / 2, dims.y), dims)
	return Rect2(box.position, Vector2(box.size.x, box.size.y * 0.55))
func over_face(flight: Array) -> int:
	var hits = 0
	for entry in flight:
		if carried_box(entry).intersects(koukou_head()): hits += 1
	return hits
# 回执这块纸压住了几块台面牌：牌面是引擎画的，只能按同一份矩形清单来量。
func plates_under(sheet: Rect2) -> int:
	var crossed = 0
	for plate in game.world.sign_plates(game.world.shown_state()):
		if sheet.intersects(on_board(plate["rect"])): crossed += 1
	return crossed
func plate_texts() -> Array:
	var list: Array = []
	for plate in game.world.sign_plates(game.world.shown_state()): list.append(plate["text"])
	return list
# 台词条那块板钉在屏上，柜面上的牌钉在世界里：两者一交叠，牌的上半截就被板子吃掉。
# 宿主把 message 排在台词之前，量板子要按同一份优先级找，否则有拒绝语的那一刻会量空。
func spoken_text() -> String:
	return game.line() if game.message.is_empty() else game.message
func line_board() -> Rect2:
	if spoken_text().is_empty(): return Rect2()
	var spoken: Label = label_with(spoken_text())
	if spoken == null: return Rect2()
	for child in game.ui.get_children():
		if child is Panel and Rect2(child.position, child.size).has_point(spoken.position):
			return Rect2(child.position, child.size)
	return Rect2()
func plates_behind_board() -> int:
	var board = line_board()
	if board.size == Vector2.ZERO: return 0
	var eaten = 0
	for plate in game.world.sign_plates(game.world.shown_state()):
		if on_board(plate["rect"]).intersects(board):
			eaten += 1; print("BEHIND ", plate["text"], " ", on_board(plate["rect"]), " vs ", board)
	return eaten
# 起飞的那张纸有 75 高：拱顶抬得太高，纸尖就钻进台词条后面，数字看着像被吞了半截。
func flight_behind_board(flight: Array) -> int:
	var board = line_board()
	if board.size == Vector2.ZERO: return 0
	var eaten = 0
	for entry in flight:
		if on_board(carried_box(entry)).intersects(board): eaten += 1
	return eaten
# 热点必须罩得住玩家看得见的那张纸：纸尖点不着，玩家照着纸去点就落空。
func hotspot_of(id: String) -> Rect2:
	return game.buttons[id].get_global_rect()
func covers_sheet(hot: Rect2, sheet: Rect2) -> bool:
	return (hot.position.x <= sheet.position.x + 0.5 and hot.position.y <= sheet.position.y + 0.5
		and hot.end.x >= sheet.end.x - 0.5 and hot.end.y >= sheet.end.y - 0.5)

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK04 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk04-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		# ---- 开场三句：玩家一句句把争吵听完 ----
		check(game.state.stage == "arrival" and "收据对不上" in game.line(),"opens on the argument about the receipt, not on a puzzle")
		check(game.buttons.next.text == "继续听他们说","the first line only asks to keep listening")
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"the opening line stays inside its board")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"the rebuilt line can be focused again")
		await key(KEY_ENTER)
		check(game.state.beat == 2 and game.buttons.next.text == "到柜面前看看","the last line invites the player to the counter")
		await click("next")
		check(game.state.stage == "approach","the third line walks the player to the counter")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		check(game.buttons.pause.text == "继续动画","the pause button names its own way back")
		await hold(0.8)
		check(game.world.progress > 0.4 and game.world.progress < 0.6,"the walk-in holds a mid-zoom frame")
		await capture(prefix+"02-approach")
		await click("skip")
		check(game.state.stage == "ready","approach stops before player control")
		check(not game.paused and game.buttons.has("next") and not game.buttons.has("deliver"),"the counter is not the player's yet")
		await capture(prefix+"03-ready")
		await click("next")
		check(game.state.stage == "puzzle","the counter is handed to the player")
		# ---- 台面守卫：目标尺寸、屏内、文字、站位 ----
		var hot = 0
		var tiny = 0
		var clipped = 0
		for id in game.buttons:
			var b: Control = game.buttons[id]
			if b.get_parent() != game.world: continue
			hot += 1
			if b.size.x < 48 or b.size.y < 48: tiny += 1
			if not Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(b.get_global_rect()): clipped += 1
		check(hot == 6,"the counter exposes three receipts and three candidate tags as hotspots")
		check(tiny == 0,"every receipt and candidate is a 48 pixel target or bigger")
		check(clipped == 0,"no hotspot falls outside the logical board")
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"no counter text leaves its board on the empty table")
		check(game.world.land_place == "" and game.transient == 0,"nothing is mid-air before the first exchange")
		check(not game.buttons.single_0.disabled and not game.buttons.batch_0.disabled
			and game.buttons.single_1.disabled and game.buttons.batch_1.disabled,
			"only the cloth promise is clickable while the oil is still inside the cloth")
		check(label_with("布 3 卷 · 可换 3 组") != null and label_with("油 0 瓶 · 可换 0 组") != null,
			"the counter states both pools in the player's own units")
		drawn("扣扣的转抄件 · 待核对", 16, 216.0, "转抄件台面牌")
		drawn("原约一 · 1 布 → 2 油", 16, 230.0, "左柜台面牌")
		check(line_board().size != Vector2.ZERO,"the dialogue board the counter is measured against is on screen")
		check(plates_behind_board() == 0,"no counter plaque hides behind the pinned dialogue board")
		# 热点就是玩家看得见的那张纸：纸尖、纸尾落进死区，照着纸点就会落空。
		for spec in [["card_0",0],["card_1",1],["card_third",2]]:
			check(covers_sheet(hotspot_of(spec[0]), card_paper(spec[1])),
				"the clickable frame of %s covers the whole sheet the player sees" % spec[0])
		for index in range(Rules.CANDIDATES.size()):
			check(covers_sheet(hotspot_of("cand_%d" % index), cand_paper(index)),
				"the clickable frame of candidate %d covers the whole tag the player sees" % index)
		var stacked = 0
		for index in range(1, Rules.CANDIDATES.size()):
			if paper(game.world.cand_foot(index - 1), World.CAND_WIDTH).intersects(
					paper(game.world.cand_foot(index), World.CAND_WIDTH)): stacked += 1
		check(stacked == 0,"the three candidate tags leave each other's gold frame whole")
		check(game.buttons.undo.disabled,"an untouched counter has nothing to undo")
		await capture(prefix+"04-empty-table")
		# ---- 三条单都要问得动：两张原约念条款，转抄件念它为什么不算 ----
		await key(KEY_1)
		check(game.state.correction == 0 and "先按两条原约" in game.message,"the candidates stay shut before the run")
		await click("card_0")
		check("1 卷布换 2 瓶油" in game.message,"tapping the first promise reads it back")
		await click("card_1")
		check("3 瓶油换 1 只铜铃" in game.message,"tapping the second promise reads it back")
		await click("card_third")
		check(game.state.stage == "puzzle" and game.state.a == 0 and "刷货" in game.message,
			"the transcribed card refuses with the reason that teaches")
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"the refusal about the copy stays inside the dialogue board")
		await click("third_try")
		check("凭空多出铃" in game.message,"the button path is refused by the same sentence")
		await key(KEY_T)
		check(game.state.stage == "puzzle" and "抄来的" in game.message,"the keyboard path is refused too")
		await capture(prefix+"05-third-card-refused")
		await click("deliver")
		check(game.state.stage == "puzzle" and "还剩 3 卷布没换" in game.message,
			"an untouched counter is refused with the promise it still owes")
		# ---- 三级提示 ----
		for n in range(3): await click("hint")
		check(game.state.hint == Rules.HINTS and "换不出来" in game.message,"the third hint states the whole chain")
		check(game.buttons.undo.disabled,"a hint is not a move the player has to undo")
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"the deepest hint still fits its board")
		await capture(prefix+"06-hint")
		# ---- 第一次实换：键盘把 3 卷布全按原约一换掉 ----
		await key(KEY_A)
		check(game.state.stage == "exchanging" and game.state.exchange == [0,Rules.CLOTH] and game.state.a == 0,
			"A stages the whole cloth pile as one group, booked only when it lands")
		check(absf(game.duration()-(0.8+0.24*Rules.CLOTH)) < 0.001,"the bigger the batch the longer the carry")
		await hold(0.6)
		var flight = game.world.carry_plan(game.world.progress)
		check(flight.size() == Rules.CLOTH,"the whole cloth pile leaves the counter as one flight")
		check(over_face(flight) == 0,"the cloth is carried to 扣扣's claws, not across his face")
		await capture(prefix+"07-cloth-flight")
		await press("skip")
		check(game.transient > 0 and game.world.land_place == "oil" and game.world.land_slot == Rules.OIL-1,
			"the booked oil drops in front of the player behind the landing lock")
		check(game.state.a == Rules.CLOTH and game.state.b == 0 and Rules.oil_loose(game.state) == Rules.OIL,
			"three groups of cloth become exactly six bottles")
		await capture(prefix+"08-oil-landing")
		await drain()
		check(game.transient == 0 and game.world.land_progress == 1,"the landing settles and hands the counter back")
		check(not game.buttons.deliver.disabled and not game.buttons.single_1.disabled,
			"the oil promise opens where the oil appeared")
		check(game.buttons.single_0.disabled and game.buttons.batch_0.disabled,
			"spent cloth cannot be exchanged a second time to farm goods")
		await key(KEY_Q)
		check(game.state.stage == "puzzle" and "全部换过了" in game.message,"the dead promise says why it is dead")
		await capture(prefix+"09-oil-table")
		# ---- 第二次实换：键盘把 6 瓶油全按原约二换掉 ----
		await key(KEY_S)
		check(game.state.stage == "exchanging" and game.state.exchange == [1,Rules.BELL_GROUPS],"S stages both bell groups")
		await hold(0.35)
		check(over_face(game.world.carry_plan(game.world.progress)) == 0,
			"the oil leaves the tray toward 扣扣's claws without crossing his face")
		await press("skip")
		check(game.transient > 0 and game.world.land_place == "bell" and game.world.land_slot == Rules.BELL_GROUPS-1,
			"the last bell lands on the right counter, not the oil row")
		check(game.state.b == Rules.BELL_GROUPS and Rules.oil_loose(game.state) == 0 and Rules.bells_loose(game.state) == 2,
			"six bottles buy two bells and leave no oil on the table")
		await drain()
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"a full counter adds no spilled text")
		await capture(prefix+"10-bells-landed")
		# ---- 故意改错：把抄来的 3 只写上去，再交一次 ----
		await click("cand_1")
		check(game.state.stage == "correcting" and game.state.proposed == Rules.WRITTEN_BELLS and game.state.correction == 0,
			"candidate three is reachable and only staged until the pen lands")
		await hold(0.25)
		var pen = game.world.carry_plan(game.world.progress)
		check(pen.size() == 1,"the correction carries one number, not a crate of goods")
		check(over_face(pen) == 0,"the flying number arcs over 扣扣's head instead of smearing past his face")
		var swept = 0
		var eaten = 0
		check(line_board().size != Vector2.ZERO,"the dialogue board is on screen while the number is in the air")
		for index in range(Rules.CANDIDATES.size()):
			var scratch = game.state.duplicate(true)
			scratch.stage = "correcting"; scratch.proposed = Rules.CANDIDATES[index]
			game.world.state = scratch
			for step in range(11):
				if over_face(game.world.carry_plan(step / 20.0)) > 0: swept += 1
				eaten += flight_behind_board(game.world.carry_plan(step / 20.0))
		game.world.state = game.state
		check(swept == 0,"every candidate number, from the lowest tag too, clears 扣扣's head on the way to the copy")
		check(eaten == 0,"every candidate number stays out from behind the pinned dialogue board in flight")
		check(flight_behind_board(pen) == 0,"the number in front of the camera is fully readable against the board")
		await hold(0.5)
		await capture(prefix+"11-correcting-flight")
		await press("skip")
		check(game.world.land_place == "" and game.transient == 0,"改签 lands no good, so nothing bounces on the counter")
		await drain()
		check(game.state.correction == Rules.WRITTEN_BELLS,"the receipt now reads the copied three bells")
		await click("deliver")
		check(game.state.stage == "puzzle" and "改签写的是 3 只" in game.message
			and "3 卷布 → 6 瓶油 → 2 只铃" in game.message,
			"the impossible receipt is refused in the terms of the run the player just made")
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"the refusal fits the same board as the dialogue")
		await capture(prefix+"12-wrong-receipt")
		# ---- 撤回改签、撤销、再改对 ----
		await click("cand_1")
		check(game.state.correction == 0,"tapping the number already written takes it back off the receipt")
		await key(KEY_Z)
		check(game.state.correction == Rules.WRITTEN_BELLS,"one undo puts the withdrawn pick back on the paper")
		await key(KEY_Z)
		check(game.state.correction == 0 and game.state.b == Rules.BELL_GROUPS,
			"the second undo rewinds only the pick, never the goods")
		await click("cand_0")
		await click("skip")
		check(game.state.correction == Rules.CORRECT_BELLS and Rules.solved(game.state),
			"two bells, counted and not guessed, close the receipt")
		# ---- 重摆先问一句 ----
		await click("reset")
		check(game.modal and game.state.stage == "puzzle","重摆 asks before it touches the counter")
		check(game.buttons.has("cancel") and game.buttons.has("confirm"),"the question offers both answers")
		await capture(prefix+"13-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.a == Rules.CLOTH and game.state.b == Rules.BELL_GROUPS
			and game.state.correction == Rules.CORRECT_BELLS and game.state.hint == Rules.HINTS,
			"cancelling keeps every good and every hint the player earned")
		# ---- 正确提交：空格键走宿主与关卡自己的快捷键 ----
		check(root.gui_get_focus_owner() == null,"no stale button steals the keyboard")
		await key(KEY_SPACE)
		check(game.state.stage == "delivery","the honest receipt is accepted by the spacebar too")
		await hold(2.8)
		check(game.world.progress > 0.55 and game.world.progress < 0.7,"the hand-over holds a mid-walk frame")
		await capture(prefix+"14-delivery")
		await click("pause")
		check(not game.paused and game.buttons.pause.text == "暂停动画","the player can hand the street back to itself")
		paused_at = game.elapsed
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(game.paused and game.buttons.pause.text == "继续动画","leaving the window pauses the hand-over")
		await create_timer(0.1).timeout
		check(game.elapsed == paused_at,"focus loss freezes the hand-over")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "clarify" and game.state.beat == 0,"the hand-over hands the street back to 扣扣")
		check(game.buttons.next.text == "继续听他们说","the clarification is advanced by the player")
		await click("next"); await click("next")
		check(game.state.beat == 2,"the two sides say their halves of the same sentence")
		await capture(prefix+"15-clarify")
		await click("next")
		check(game.buttons.next.text == "看这次的回执","the last line turns the receipt over")
		await click("next")
		check(game.state.stage == "complete","the receipt closes the scene")
		# ---- 回执：文字量得下、纸盖不住货、出口只有一个 ----
		var paper_label = label_with("回执 · 育苗铺")
		check(paper_label != null and paper_label.text.split("\n").size() == 6,"the receipt is six authored lines")
		if paper_label == null: check(false,"the receipt is missing from the counter")
		else:
			check(fits(paper_label.text, 18, paper_label.size.x),"the receipt holds its own paper")
			check("原约一 ×3：3 卷布 → 6 瓶油" in paper_label.text
				and "原约二 ×2：6 瓶油 → 2 只铜铃" in paper_label.text,
				"the receipt restates the two promises the player actually ran")
			check("转抄件改签：3 卷布换 2 只铜铃" in paper_label.text
				and "抄错不是偷货：原单 2、转抄 3" in paper_label.text,
				"the receipt keeps a wrong copy and a stolen bell apart")
			var sheet = panel_over(Rect2(paper_label.position,paper_label.size))
			check(sheet != null and not Rect2(sheet.position,sheet.size).intersects(card_paper(0)),
				"the receipt leaves 原约一 standing on the counter")
			check(sheet != null and not Rect2(sheet.position,sheet.size).intersects(card_paper(1)),
				"the receipt leaves 原约二 standing on the counter")
			check(sheet != null and not Rect2(sheet.position,sheet.size).intersects(card_paper(2)),
				"the receipt sits beside the card it corrects, not on top of it")
			check(sheet != null and not Rect2(sheet.position,sheet.size).intersects(cand_paper(2)),
				"the receipt leaves the three candidate tags readable")
			var dims = World.KOUKOU_WAVE.get_size()*0.5
			var koukou = on_board(Rect2(game.world.station("resident")-Vector2(dims.x/2,dims.y),dims))
			check(sheet != null and not Rect2(sheet.position,sheet.size).intersects(koukou),
				"the receipt does not bury 扣扣 where he stands")
			var covered = 0
			for foot in game.world.bell_spots():
				var bell = on_board(Rect2(foot-Vector2(24,54),Vector2(48,54)))
				if sheet != null and Rect2(sheet.position,sheet.size).intersects(bell): covered += 1
			check(covered == 0,"the two bells the receipt counts are still on the counter")
			check(sheet != null and plates_under(Rect2(sheet.position,sheet.size)) == 0,
				"the receipt paper also leaves every counter plaque readable")
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"the receipt adds no text outside its board")
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"a standalone launch shows 回千灯航图 and no chart back-door")
		check(not game.buttons.has("deliver") and not game.buttons.has("reset"),
			"a finished scene is not reset by an accidental click")
		var plates = plate_texts()
		check(not ("原约一 · 1 布 → 2 油" in plates) and not ("扣扣的转抄件 · 已订正 %d 只" % Rules.CORRECT_BELLS in plates),
			"the receipt takes the two promises over instead of printing on top of them")
		drawn("原约二 · 3 油 → 1 铃", 16, 230.0, "右柜台面牌")
		drawn("实换 %d 只 · 单上 %d 只" % [Rules.CORRECT_BELLS, Rules.CORRECT_BELLS], 16, 212.0, "对照台面牌")
		drawn("空货签 · 当众重写", 16, 180.0, "空货签台面牌")
		drawn("换 %d 只铜铃" % Rules.CORRECT_BELLS, 15, 110.0, "转抄件单纸正文")
		drawn("双方有章", 12, 110.0, "原约章印旁注")
		await capture(prefix+"16-receipt")
		# ---- 存档：这一幕记得玩家真的做过什么 ----
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the finished receipt reloads from disk exactly as booked")
		check(game.state.correction == Rules.CORRECT_BELLS and Rules.solved(game.state),
			"the reload is still the run the player performed")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		if not small: await capture("17-back-to-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub"),"a standalone launch still finds its way back to the chart")
		# ---- 重新体验只 rewind 这一站 ----
		await click("next")
		check(game.modal and game.state.stage == "complete","replaying the scene asks first")
		await click("cancel")
		check(game.state.correction == Rules.CORRECT_BELLS and not game.modal,
			"cancelling keeps the receipt the player earned")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.a == 0 and game.state.hint == 0,
			"replaying the scene rewinds only this station")
		# ---- 纯鼠标重走一遍：每一步都点给玩家看 ----
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","the same three lines carry the player back to the counter")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","the walk-in still stops before player control")
		await click("batch_0"); await click("skip")
		check(game.state.a == Rules.CLOTH and Rules.oil_loose(game.state) == Rules.OIL,
			"全换完 books the whole pile as one landing")
		await click("single_1"); await click("skip")
		check(game.state.b == 1 and Rules.oil_loose(game.state) == Rules.OIL_PER_BELL,"换 1 组 leaves one group of oil")
		await click("deliver")
		check(game.state.stage == "puzzle" and "还有 3 瓶油" in game.message,"the half run names the oil it still owes")
		await click("batch_1"); await click("skip")
		check(game.state.b == Rules.BELL_GROUPS and Rules.bells_loose(game.state) == 2,"the mouse path empties the oil too")
		await click("cand_0"); await click("skip")
		check(Rules.solved(game.state),"the mouse path writes the same two bells")
		await capture(prefix+"18-mouse-replay")
		await click("reset"); await click("confirm")
		check(game.state.a == 0 and game.state.b == 0 and game.state.correction == 0,
			"重摆 sends every good home and the card back to the copied three")
		check(game.world.land_place == "" and game.transient == 0,"a reset unwinds without dropping goods from the air")
		check(label_with("布 3 卷 · 可换 3 组") != null,"the cleared counter offers the cloth pile again")
		await key(KEY_Z)
		check(Rules.solved(game.state),"one undo takes the whole run back")
		check(spilled(game.ui) == 0 and off_board(game.ui) == 0,"the solved counter keeps its text inside its boards")
		await capture(prefix+"19-undone-table")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK04 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

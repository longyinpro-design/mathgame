extends SceneTree
# MK11 实窗审计：真实窗口里走一遍「听三句话 → 走到铜秤前 → 先按默认的想法定一下秤 → 一格一格
# 接油接满 13 单位被明说上限 → 抬秤看秤如实报「对面那盘沉下去了」→ 请扣扣提醒 → 重摆弹窗（先看
# 文案、取消、确认、再撤销回来）→ 纯键盘把 3 请到货盘这一头 → 再抬一次秤看秤杆放平 → 封坛交付 →
# 衡伯的验看单」。在 1280×720 与 960×540 各拍一遍，并检查三块木牌、八个描边读数、回执与台词板上
# 的汉字有没有爬出自己的边框，有没有被口述板压住。
const Scene = preload("res://game/market_mk11.tscn")
const Rules = preload("res://scripts/market/mk11_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const EMPTY = [0, 0, 0]
# 玩家最自然会先试的那一步：三枚砝码全站到对面那盘。
const NAIVE_FAR = [1, 1, 1]
# 唯一的解：货盘「灯油 7 + 砝码 3」对对面「砝码 1 + 砝码 9」，两头各压 10 单位。
const GOOD = [0, 1, 0]
const FAR = [1, 0, 1]
# 本关的 12 枚热点：油壶、提斗、罐口、台面三格、每盘三格。
const TARGETS = ["valve", "ladle", "pot", "bench_0", "bench_1", "bench_2",
	"pan_1_0", "pan_2_0", "pan_1_1", "pan_2_1", "pan_1_2", "pan_2_2"]
# 摆放途中任何一句话都不许预告该接多少、哪头沉：契约里逐词钉死的话术泄漏表。
const LEAK = ["差", "多", "沉", "不平", "答案", "7 单位"]
var game: Control
var checks = 0
var failures = 0
var face: FontFile
const CAPTURE = "res://docs/playtest/market-mk11-scale"

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
# 一次真实的按下-抬起：不等帧，所以能看见宿主 0.28 秒的落秤锁。
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
# 摆好一个动画帧但不暂停：秤杆沉到底与封坛在半空只有在这里才拍得到。
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
# Label 侧：UIStyle.text_size 会把 16/20/24 抬到 18/22/28，量之前先按同一条规则取整。
func fits(text: String, size_px: int, width: float) -> bool:
	return widest_line(text, size_px) <= width
func rows(text: String) -> int: return text.split("\n").size()
# 世界侧：plaque/words 走 draw_string，字号原样生效，从不抬升也从不换行。
func font() -> FontFile:
	if face == null: face = UIStyle.face()
	return face
func line_width(text: String, size_px: int) -> float:
	var needed := 0.0
	for line in text.split("\n"):
		needed = maxf(needed, font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
	return needed
# 本关的街面文字分两种：有底的木牌 boards()（plaque 画在 rect 里）与没有底的描边读数
# notes()（words 画在基线 at 上，可用宽度写在 width 里）。审计只看这一份合并清单。
# 量「有没有被别人压住」只能用字面**实测**宽度：预算宽度是给检查量上限用的，拿它当方框
# 就会把「对面 10 单位」这种短读数虚报成压到封坛上。
func planks() -> Array:
	var list: Array = []
	for board in game.world.boards():
		var rect: Rect2 = board["rect"]
		list.append({"text": str(board["text"]), "px": int(board["px"]), "kind": "plaque",
			"rect": rect, "budget": rect.size.x - 16})
	for note in game.world.notes():
		var px: int = int(note["px"])
		var ascent: float = font().get_ascent(px)
		var descent: float = font().get_descent(px)
		# words() 的 at 是基线：字面真正占的方框是 [基线-上伸, 基线下伸]，按这个算才不会被镜头糊过去。
		list.append({"text": str(note["text"]), "px": px, "kind": "note",
			"rect": Rect2(note["at"].x, note["at"].y - ascent, line_width(str(note["text"]), px) + 2.0,
				ascent + descent),
			"budget": float(note["width"])})
	return list
func board_with(needle: String) -> String:
	for plank in planks():
		if str(plank["text"]).contains(needle): return str(plank["text"])
	return ""
# 中文在 Godot 里是一个不断词：plaque 从不换行，一行比木牌还宽就直接画到旁边的货上。
func spilled_boards() -> int:
	var over = 0
	for plank in planks():
		var px: int = int(plank["px"])
		var rect: Rect2 = plank["rect"]
		var budget: float = float(plank["budget"])
		if line_width(str(plank["text"]), px) > budget:
			over += 1; print("BOARD ", plank["text"], " over ", budget, " at ", px, "px in ", rect.size.x)
		if plank["kind"] == "plaque" and px > rect.size.y:
			over += 1; print("BOARD too short for ", px, "px: ", plank["text"], " in ", rect.size.y)
	return over
# 12 枚热点在**当前镜头**下再量一遍：贴近之后仍然 ≥48×48，且不进口述板也不压按钮行。
func hotspots() -> int:
	var live = 0
	for id in TARGETS:
		if not game.buttons.has(id): print("MISSING target ", id); continue
		var rect: Rect2 = game.buttons[id].get_global_rect()
		if rect.size.x < 48 or rect.size.y < 48: print("SMALL target ", id, " ", rect.size)
		elif rect.position.x < 0 or rect.position.y < 166 or rect.end.x > 1280 or rect.end.y > 646:
			print("OUTDOOR target ", id, " ", rect)
		else: live += 1
	return live
func ui_text(needle: String) -> Label:
	for child in game.ui.get_children():
		if child is Label and str(child.text).contains(needle): return child
	return null
# 确认弹窗的文案在 overlay 上：重摆与重新体验到底问了什么，只能从这里读。
func overlay_text(needle: String) -> Label:
	for child in game.overlay.get_children():
		if child is Label and str(child.text).contains(needle): return child
	return null
func panel_at(pos: Vector2) -> Panel:
	for child in game.ui.get_children():
		if child is Panel and child.position == pos: return child
	return null
# 盒子挡不住溢出：Godot 会把 Control.size 抬到内容的最低尺寸，字照样长在纸外。
# 所以拿标签的实际方框去比它脚下那块板（台词板也算），板边之外一个字都不许有。
# 弹窗自己是一层：它的三行问句也必须留在自己的木板上。
func spill_of(container: Node) -> int:
	var over = 0
	for child in container.get_children():
		if not child is Label or child.text.is_empty(): continue
		var box = Rect2(child.position, child.size)
		for other in container.get_children():
			if not other is Panel: continue
			var board = Rect2(other.position, other.size)
			if not board.has_point(box.position): continue
			if box.end.y > board.end.y + 3 or box.end.x > board.end.x + 3:
				over += 1
				print("OFFBOARD ", child.text.replace("\n"," / "), " box ", box,
					" min ", child.get_combined_minimum_size(), " board ", board)
	return over
func off_board() -> int:
	return spill_of(game.ui) + spill_of(game.overlay)
# 街面与 UI 在同一个逻辑平面上：先按当前镜头换算（puzzle/weighing 把整座庭院抬到 1.10，
# 木牌会整体压向上方，只看未放大坐标就会漏掉「描边读数钻进口述板底下」这一类真机才看得见的遮挡）。
func on_screen(rect: Rect2) -> Rect2:
	var xf: Transform2D = game.world.get_global_transform_with_canvas()
	var a = xf*rect.position
	var b = xf*(rect.position+rect.size)
	return Rect2(a, b-a)
# kit() 的落点公式：画出来的矩形 = 脚点 − 挂点×缩放，尺寸 = 原图像素×缩放。
# 油车与车上的货都是带大片透明边缘的裁剪图，量遮挡只能按真正落笔的那一块算。
func kit_rect(id: String, foot: Vector2, width: float) -> Rect2:
	var tex: Texture2D = game.world.atlases[id]
	var item: Dictionary = game.world.parts[id]
	var scale = width / float(tex.get_width())
	return Rect2(foot - Vector2(float(item.anchor_px[0]), float(item.anchor_px[1])) * scale,
		Vector2(float(tex.get_width()), float(tex.get_height())) * scale)
func papers() -> Array:
	var list := []
	for child in game.ui.get_children():
		if child is Panel: list.append(Rect2(child.position, child.size))
	return list
func covered() -> int:
	var over = 0
	for plank in planks():
		var shown: Rect2 = on_screen(plank["rect"])
		for paper in papers():
			if paper.intersects(shown):
				over += 1; print("COVERED ", plank["kind"], " ", plank["text"], " by paper ", paper, " at ", shown)
	# 这一关的结果就画在秤上：口述板、目标板、回执都不许把秤杆、盘面、油罐或封坛压在底下。
	for payoff in payoff_rects():
		var shown: Rect2 = on_screen(payoff["rect"])
		for paper in papers():
			if paper.intersects(shown):
				over += 1; print("COVERED payoff ", payoff["at"], " by paper ", paper, " at ", shown)
	if game.state.stage != "complete": return over
	# 验看单只在收单那一格摊开：它压到秤、油车、封坛或出口按钮，就是收尾画面被自己挡住。
	var sheet: Rect2 = game.receipt_rect()
	for id in ["next","open_hub","back_hub"]:
		if not game.buttons.has(id): continue
		if sheet.intersects(Rect2(game.buttons[id].position, game.buttons[id].size)):
			over += 1; print("COVERED exit ", id, " by receipt ", sheet)
	# 验看单是最后摊开的一层，压到别的板上就是别的板没了半张：台词板尤其要说得出话。
	for paper in papers():
		if paper == sheet: continue
		if sheet.intersects(paper):
			over += 1; print("COVERED paper ", paper, " by receipt ", sheet)
	for rect in payoff_rects(true):
		if sheet.intersects(on_screen(rect["rect"])):
			over += 1; print("COVERED payoff ", rect["at"], " by receipt ", sheet)
	return over
# 这一关的「结果」全在街面上：秤杆、两只盘、接油罐、台面三格、封坛落点。
# 它们由世界自己画，没有任何一块木牌可以盖在上面——这一条按世界坐标量，与镜头无关，
# 贴近与拉远两遍都必须干净。
func payoff_rects(wide: bool = false) -> Array:
	var rects: Array = []
	var angle: float = game.world.beam_angle()
	var left: Vector2 = game.world.pan_hook(Rules.GOODS, angle)
	var right: Vector2 = game.world.pan_hook(Rules.FAR, angle)
	# 秤杆整条随倾角平移：上下各留 22 像素，把杆身与两端的挂勾一起算进来。
	rects.append({"at": "秤杆", "rect": Rect2(left.x - 14, minf(left.y, right.y) - 22,
		right.x - left.x + 28, absf(right.y - left.y) + 44)})
	for side in [Rules.GOODS, Rules.FAR]:
		var cargo: Vector2 = game.world.pan_cargo(side, angle)
		var span := 106.0 if side == Rules.GOODS else 82.0
		# 盘上的「结果」是站着的砝码与它们头顶的数字：从最高那只的数字顶（cargo−98）量到盘面
		# （cargo+6）。整张 scale_pan 贴图的外框包含大片透明边缘，拿它当遮挡判定就会把
		# 「木牌挨着秤链」这种正常排版误报成真缺陷。
		rects.append({"at": Rules.pan_name(side),
			"rect": Rect2(cargo.x - span, cargo.y - 98, span * 2.0, 104.0)})
	rects.append({"at": "接油罐", "rect": game.world.pot_rect()})
	for index in range(Rules.COUNT):
		rects.append({"at": "台面第 %d 格"%(index+1), "rect": game.world.bench_rect(index)})
	if game.state.stage in ["delivery", "complete"]:
		# 封坛与接货盘落在铜秤右边的台面上：只量真正画出来的那一段，不吞掉左边那行读数。
		rects.append({"at": "封坛落点", "rect": Rect2(game.world.shelf_foot() + Vector2(-56, -64), Vector2(112, 80))})
	# 车上的高油壶与油瓶也是这一关的「货」：钉在车帮上的木牌一拦腰就会把壶切成两截。
	# 44.0／34.0 与 draw_carts 同源，改造型要一起改。
	rects.append({"at": "车上的高油壶",
		"rect": kit_rect("oil_jug_tall", game.world.cart_cargo(0, "cargo_left"), 44.0)})
	rects.append({"at": "车上的油瓶",
		"rect": kit_rect("oil_bottle", game.world.cart_cargo(0, "cargo_right"), 34.0)})
	if wide:
		# 收尾那一格摊开的验看单：三辆车实实在在画出来的那一片都不许被纸压住。
		for index in range(3):
			rects.append({"at": "油车 %d" % (index + 1),
				"rect": kit_rect("delivery_cart", game.world.cart_foot(index), game.world.cart_width(index))})
	return rects
func payoff_covered() -> int:
	var over = 0
	for payoff in payoff_rects():
		for plank in planks():
			if plank["rect"].intersects(payoff["rect"]):
				over += 1; print("COVERED payoff ", payoff["at"], " by ", plank["kind"], " ", plank["text"])
	return over
# 每个阶段都要守的三条文字底线，集中一次，免得后面漏掉某一幕。
func guards(tag: String) -> void:
	check(off_board() == 0 and spilled_boards() == 0 and covered() == 0 and payoff_covered() == 0,
		"every board, readout and payoff drawing keeps its own room: " + tag)
func leaks(text: String) -> bool:
	for word in LEAK:
		if word in text: return true
	return false
# 抬秤之前，街面上任何一处都不许出现「某盘压了多少单位」这种读数。
func speaks_a_total() -> bool:
	for plank in planks():
		if plank["kind"] == "note" and (" 单位" in str(plank["text"])): return true
	return false

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK11 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk11-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		# 落地锁与演出照常跑完，只是不等满真实帧时：后台窗口的帧率不由审计决定，
		# 这里量的是「按下之后锁是否落下、是否自己走完」，不是墙钟。
		game.time_scale = 3.0
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.world.scene_id == "oil" and game.world.has_part("scale_beam")
			and game.world.has_part("scale_pan") and game.world.has_part("oil_jug_round"),
			"the oil courtyard opens on the shared kit parts the brass scale is built from")
		check(game.state.stage == "arrival" and game.state.beat == 0 and game.state.goods == EMPTY
			and game.state.far == EMPTY and game.state.oil == 0 and game.state.weighs == 0
			and game.state.hint == 0,
			"the scene opens with three weights on the bench, the pot empty and the beam braked")
		check(absf(game.world.beam_angle()) < 0.0001 and game.world.braked(),
			"the beam is braked level before the player ever lifts it")
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"the first beat only asks to keep listening")
		check("恰好 7 单位灯油" in game.line() and "每枚只能用一次" in game.line()
			and "我的罐子没有刻度" in game.line(),
			"the first line states the promise, the unmarked pot and the one-use bound")
		check(game.world.boards().size() == 2 and board_with("空盘") == "",
			"no equation board stands while the three lines are still being spoken")
		guards("arrival")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1 and "砝码摆在对面那盘不就行了" in game.line(),
			"Enter walks one beat and 扣扣 says out loud the default idea this level measures")
		await click("next")
		check(game.state.beat == Rules.BEATS - 1 and "两边都能站砝码" in game.line()
			and "摆法我不给，秤也不提前说话" in game.line() and game.buttons.next.text == "走向铜秤",
			"衡伯 draws the boundary and the last line is the one that walks the player in")
		send(KEY_A); await process_frame
		check(game.state.oil == 0 and game.state.stage == "arrival",
			"the keyboard is idle while the three lines are still being spoken")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"the walk-in animates the courtyard toward the scale")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		# 这一段量的是「走位途中镜头确实收进来」。`world.scale` 不是存档字段，是宿主每帧从
		# `world.progress` 现算的派生值（`level_host.gd:95`），所以只断言一个区间会把两件不同的事
		# 混成一条报错：整表 pass 里出现过一次 `251/252`——采样的那一刻其实已经不在走位中段，
		# 量到的 1.00 是「这一幕走完了／镜头还没跟上」的哪一种，看报错分不出来。
		# 现在先把采样那一刻钉住（走位仍在进行、进度落在中段），再量镜头有没有按设计映射跟着它，
		# 最后才是原来那条区间断言。三条都是把断言收紧，没有一条放宽。
		check(game.state.stage == "approach","the walk-in is still on its way when it gets frozen")
		await hold(0.9)
		await process_frame
		var walking: float = game.world.progress
		var closed: float = game.world.scale.x
		check(game.state.stage == "approach" and walking > 0.3 and walking < 0.7,
			"the camera is sampled mid-walk-in, not at either end (stage %s, progress %.3f)" % [game.state.stage, walking])
		check(absf(closed - (1.0 + 0.10 * smoothstep(0.0, 1.0, walking))) < 0.0005,
			"the camera tracks the walk-in clock (scale %.4f at progress %.3f)" % [closed, walking])
		check(closed > 1.0 and closed < 1.10,"the courtyard closes in on the way over")
		guards("approach")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready" and game.state.beat == Rules.BEATS - 1,
			"skipping hands the scene to the player without cutting a beat short")
		check(game.buttons.next.text == "开始分油","the briefing explains the click order")
		await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"the scale is handed to the player under the closed camera")
		check(hotspots() == 12,"twelve scale targets, each 48 pixels or bigger under the zoom, are live")
		check(game.world.targets().size() == 12 and game.buttons.size() == 12 + 4,
			"the world registers exactly those twelve targets and the host adds its own four")
		var title_board := panel_at(Vector2(24,20))
		var title_sign := ui_text("千灯集市")
		check(title_board != null and title_board.size == Vector2(410,48) and title_sign != null
			and title_sign.get_theme_font_size("font_size") == 22
			and fits(title_sign.text, title_sign.get_theme_font_size("font_size"), title_sign.size.x),
			"the compact title stays readable and fits its actual text area")
		check(game.state.weighs == 0 and not speaks_a_total(),
			"before the first lift no readout anywhere on the street says what a pan weighs")
		check(game.status_line() == "接油 0 · 上秤 0 枚 · 抬 0 次",
			"the running tally only reports what the player already did")
		check(board_with("油压在这头") != "" and board_with("只站砝码") != "",
			"the two pans are named, never weighed, while the beam is locked")
		check(board_with("秤已锁 · 提交之后才抬秤") != "",
			"the lock is carved into the courtyard, not only in the dialogue")
		check(game.buttons.undo.disabled and game.world.boards().size() == 3,
			"nothing can be taken back yet and the equation board now stands empty on both sides")
		guards("puzzle")
		await capture(prefix+"03-scale-table")
		# ---- 提交闸口：什么都没动手时，两句实话一起说，且不漏一个答案词 ----
		await click("deliver")
		check(game.state.stage == "puzzle" and game.state.weighs == 0,
			"an untouched scale refuses to be lifted and books no weighing")
		check("接油罐还空着：先拧开油壶，一格一格往货盘里接。" in game.message
			and "（还有 1 处没有归位）" in game.message,
			"the refusal quotes the two gate lines verbatim and says how many are left")
		check(not leaks(game.message),"the gate never previews how much oil is wanted")
		guards("gate")
		await key(KEY_Q)
		check(game.message == "1 单位 本来就还在台面上。" and game.state.goods == EMPTY,
			"putting an untouched weight back is refused in its own words")
		await click("hint")
		check(game.state.hint == 1 and "不是至少 7 单位" in game.message,
			"the first hint re-reads the promise without moving a single thing")
		# ---- 默认想法：第一下点击真的把 1 请去对面那盘 ----
		tap("bench_0")
		check(game.message == "","a committed move clears the line that described the old scene")
		check(game.transient > 0 and game.world.land_place == "pan" and game.world.land_slot == 20,
			"the first click owns the host's landing lock and names which pan caught it")
		check(game.world.landing("pan",20) > 0.5,"the weight is caught mid-air over the far pan")
		check(game.buttons.bench_1.disabled and game.buttons.valve.disabled,
			"the courtyard cannot be edited while it lands")
		await capture(prefix+"04-default-idea")
		await settle()
		check(game.state.far == [1, 0, 0] and game.state.goods == EMPTY,
			"NEXT starts at the far pan: the naive idea is the first click, exactly as speced")
		check(not game.buttons.pan_1_0.disabled,"the table opens again the frame it lands")
		await click("pan_2_0")
		check(game.state.goods == [1, 0, 0] and game.state.far == EMPTY
			and game.world.land_slot == 10,
			"the very next click moves the same weight beside the oil: the lesson of this level")
		check(board_with("砝码 1 = 空盘") != "","the equation board is written from what is on the pans")
		await click("pot")
		check(game.message == "接油罐已经空了：先点油壶接一格。" and game.state.oil == 0,
			"the pot itself answers an empty pour")
		await key(KEY_Q)
		check(game.state.goods == EMPTY,"putting it back on the bench leaves a clean table")
		# ---- 三枚全压对面，再一格一格接油接到上限 ----
		for code in [KEY_1, KEY_2, KEY_3]: await key(code)
		check(game.state.far == NAIVE_FAR and Rules.difference(game.state) == 13,
			"all three weights on the far pan tip the difference to the far side")
		for _n in range(13): await key(KEY_A)
		check(game.state.oil == Rules.OIL_MAX and game.transient == 0.0,
			"the pot fills one unit per click up to the three weights' own total")
		await key(KEY_A)
		check(game.state.oil == Rules.OIL_MAX and "最多接满 13 单位" in game.message,
			"hitting the oil ceiling is stated out loud, with the reason")
		for _n in range(6): await key(KEY_S)
		check(game.state.oil == 7 and game.transient == 0.0,
			"the ladle takes the pot back to exactly the promised seven")
		check(game.status_line() == "接油 7 · 上秤 3 枚 · 抬 0 次",
			"the tally counts what the player did, never what the scale would say")
		check(not speaks_a_total(),"still no pan total is spoken before the lift")
		guards("naive set")
		await capture(prefix+"05-naive-set")
		await send(KEY_SPACE); await process_frame
		check(game.state.stage == "weighing" and game.state.weighs == 1,
			"the space bar lifts the beam and books this weighing")
		check(game.buttons.has("skip") and not game.buttons.has("bench_0")
			and not game.buttons.has("valve"),
			"the lift takes the table away and keeps its own controls")
		await hold(1.2)
		var angle: float = game.world.beam_angle()
		check(angle > 0.05 and Rules.heavier(game.state) == Rules.FAR,
			"the beam is caught mid-swing sinking toward the far pan, the real imbalance")
		check(absf(game.world.pan_hook(Rules.FAR, angle).y - game.world.pan_hook(Rules.GOODS, angle).y) > 20.0,
			"the two hooks are drawn apart by the same rotation the rules report")
		check(board_with("对面 13 单位") != "" and board_with("货盘 7 单位") != "",
			"the readouts appear only now, and they read the pans the rules compute")
		guards("weighing")
		await capture(prefix+"06-beam-sinks")
		await click("skip")
		check(game.state.stage == "result" and game.state.oil == 7 and game.state.far == NAIVE_FAR,
			"the verdict costs no oil and moves no weight")
		check(game.line() == "对面那盘沉下去了：货盘 7 单位，对面 13 单位。",
			"the scale names the pan that sank and reads both totals back, the honest near miss")
		check(fits(game.line(), 20, 798.0) and rows(game.line()) == 1,
			"the verdict is one line inside the spoken board")
		check(board_with("灯油 7 = 砝码 1 + 砝码 3 + 砝码 9") != "",
			"the courtyard's own equation board says the same thing the paper does")
		guards("result")
		await capture(prefix+"07-verdict")
		var before_weighs: int = game.state.weighs
		await click("next")
		check(game.state.stage == "puzzle" and game.state.weighs == before_weighs
			and game.state.oil == 7,
			"the verdict's only way out is back to the table, reading it costs nothing")
		check(game.world.state == game.state,"the world reads the committed scene it was handed")
		for _n in range(4): await click("hint")
		check(game.state.hint == Rules.HINT_TIERS and game.hint_texts().size() == Rules.HINT_TIERS,
			"hints stop at the shipped tier count and the tier bound matches the texts")
		check("把 9 单独留在对面" in game.message and "再把 1 补到对面" in game.message,
			"the third hint points at the sign choice without pressing it for the player")
		check(game.state.far == NAIVE_FAR and game.state.oil == 7 and game.state.goods == EMPTY,
			"a hint explains the scale without moving a single weight")
		check(fits(game.message, 20, 798.0) and rows(game.message) <= 2,
			"the longest hint still stays inside the spoken board")
		guards("hints")
		await capture(prefix+"08-hints")
		await click("reset")
		check(game.modal and game.state.far == NAIVE_FAR,
			"重摆 asks before wiping the table")
		var asked = overlay_text("已经抬过的次数留着")
		check(asked != null and "全部放回台面、罐里的油倒回油壶" in asked.text
			and rows(asked.text) == 2,
			"the ask says what it wipes and what it keeps: the lift count stays, the beam stays locked")
		guards("reset asked")
		await capture(prefix+"09-reset-asked")
		await click("cancel")
		check(not game.modal and game.state.far == NAIVE_FAR and game.state.oil == 7,
			"cancelling keeps the naive arrangement the player made")
		await click("reset"); await click("confirm")
		check(game.state.goods == EMPTY and game.state.far == EMPTY and game.state.oil == 0
			and game.state.stage == "puzzle" and game.state.weighs == 1,
			"重摆 wipes the scene only: the stage and the lifts already spent stay")
		check(game.buttons.undo.disabled == false,"an emptied table still has one step to take back")
		await key(KEY_Z)
		check(game.state.far == NAIVE_FAR and game.state.oil == 7 and game.state.weighs == 1,
			"one undo brings the whole wiped table back and cannot rewind the lifts")
		check(not speaks_a_total(),"back at the table the pans go mute again")
		# ---- 纯键盘把这一秤改成唯一的解：3 站到灯油这头 ----
		await key(KEY_2)
		check(game.state.goods == GOOD and game.state.far == FAR and Rules.solved(game.state)
			and Rules.difference(game.state) == 0,
			"the keyboard route lands the only arrangement that keeps the promise: 7 + 3 = 9 + 1")
		check(game.status_line() == "接油 7 · 上秤 3 枚 · 抬 1 次",
			"the tally still counts the lift that already happened")
		await click("pan_2_0")
		check(game.state.goods == [1, 1, 0] and game.state.far == [0, 0, 1]
			and not Rules.solved(game.state),
			"clicking the free slot calls the 1 unit over here, and the scale says so when asked")
		await click("pan_1_0")
		check(game.state.goods == [0, 1, 0] and game.state.far == [0, 0, 1],
			"one more click on the goods side walks it back onto the bench, the ring closes")
		await click("bench_0")
		check(game.state.goods == GOOD and game.state.far == FAR and Rules.solved(game.state),
			"and the bench slot calls that same weight straight back onto the far pan")
		guards("solved")
		await capture(prefix+"10-solved")
		await send(KEY_SPACE); await process_frame
		check(game.state.stage == "weighing" and game.state.weighs == 2,
			"the second lift is the player's own look at the fix")
		await hold(1.2)
		check(absf(game.world.beam_angle()) < 0.0001 and Rules.balanced(game.state),
			"a level beam is drawn for a balanced difference, mid-swing included")
		check(board_with("货盘 10 单位") != "" and board_with("对面 10 单位") != "",
			"both pans read ten units, taken from the rules and not from a second label")
		await capture(prefix+"11-beam-level")
		await click("skip")
		check(game.state.stage == "delivery" and Rules.solved(game.state),
			"a level beam with the promise kept goes straight to the sealing")
		check(at_camera(1.10, Vector2(-64,-43)),
			"the sealing opens still leaning in on the scale, where the player was just looking")
		await hold(1.9)
		check(game.world.shown_oil() == 0 and game.state.oil == 7,
			"past half the pour the pot reads empty while the booked seven stays on record")
		var flight: Array = game.world.delivery_plan(game.world.progress)
		check(flight.size() == 1 and flight[0]["at"].distance_to(game.world.pot_foot()) > 30.0,
			"the sealed jar has left the goods pan and is on its way to the bench")
		# 宿主的交货镜头从第一格就往回收，四成五的时长回到整院：坛子还在天上飞时，
		# 整条街（上方的灯串、右边的封坛台）就已经给玩家看全了。
		check(at_camera(1.0, Vector2.ZERO) and game.world.progress < 1.0,
			"the courtyard is already back to the whole scene while the jar is still in the air")
		guards("pour")
		await capture(prefix+"12-pour")
		await create_timer(0.12).timeout
		paused_at = game.elapsed
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(0.12).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the jar mid-flight")
		check(game.buttons.pause.text == "继续动画","the frozen delivery offers to resume")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "complete" and at_camera(1.0, Vector2.ZERO),
			"the courtyard pulls back to the whole scene when the jar is handed over")
		check(game.world.shown_oil() == 7 and game.buttons.has("next")
			and game.buttons.next.text == "重新体验" and not game.buttons.has("reset"),
			"a closed scene can only be replayed on purpose, never wiped by an accidental click")
		check(game.state.weighs == 2 and game.receipt_lines().size() == 6,
			"衡伯's slip is the six lines the level promised")
		var paper = ui_text("验看单")
		check(paper != null and "约定：恰好 7 单位灯油" in paper.text,
			"the slip re-reads the promise before anything else")
		check(paper != null and "货盘：灯油 7 + 砝码 3 = 10 单位" in paper.text
			and "对面：砝码 1 + 砝码 9 = 10 单位" in paper.text,
			"the slip restates the two pans exactly as the player pressed them")
		check(paper != null and "这一坛抬过 2 次秤" in paper.text,
			"the slip counts the lifts that really happened, the refused one included")
		check(paper != null and "13" not in paper.text and "1 + 3 + 9" not in paper.text,
			"the slip invents nothing: the naive totals are not written into the record")
		check(board_with("灯油 7 + 砝码 3 = 砝码 1 + 砝码 9") != "",
			"the street board and the paper are the same sentence, not two vocabularies")
		check(paper != null and fits(paper.text, 16, game.receipt_text_rect().size.x),
			"the slip holds its own paper at the width the panel was cut for")
		check(paper != null and paper.get_theme_font_size("font_size") >= 18,
			"the slip keeps the house minimum type size")
		check(game.buttons["open_hub"].get_global_rect().size.x >= 48,
			"the way back to the chart sits on its own row at 48 pixels or bigger")
		guards("complete")
		await capture(prefix+"13-receipt")
		var on_disk = game.state.duplicate(true)
		check(game.world.state == game.state and Rules.validate(game.state),
			"the world and the booked record say the same thing")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the kept scale reloads from disk exactly as booked")
		check(game.state.goods == GOOD and game.state.far == FAR and game.state.weighs == 2
			and not game.buttons.has("deliver"),
			"a reload keeps the two pans and the lift count and cannot be re-submitted")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		var back: Control = game.buttons.back_hub
		check(back.get_global_rect().size.x >= 48 and back.get_global_rect().size.y >= 48,
			"the way back to the chart is a 48 pixel target or bigger")
		guards("from chart")
		if not small: await capture("14-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"a standalone launch still finds its own way back to the chart")
		await click("next")
		check(game.modal and game.state.stage == "complete","replaying the scene asks first")
		check(overlay_text("重新体验分油这一秤") != null and "不改变其他关卡与森林岛进度" in overlay_text("重新体验").text,
			"the replay ask names its own scope: this level only, the chart and the forest untouched")
		await click("cancel")
		check(game.state.goods == GOOD and game.state.oil == 7,
			"cancelling keeps the receipt the player just earned")
		# ---- 完整重玩一遍：这次全程只用鼠标 ----
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.goods == EMPTY and game.state.far == EMPTY
			and game.state.oil == 0 and game.state.weighs == 0 and game.state.hint == 0
			and game.state.beat == 0,"重新体验 opens a fresh scene, the lift count and hints included")
		for _n in range(3): await click("next")
		check(game.state.stage == "approach","the same three lines carry the player back to the scale")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"the walk-in still stops before player control")
		await click("bench_2"); await click("bench_1")
		await click("pan_1_1")
		check(game.state.goods == [0, 1, 0] and game.state.far == [0, 0, 1],
			"the free goods slot calls the 3 unit straight over in one click")
		await click("bench_0")
		check(game.state.far == FAR and game.state.goods == GOOD,
			"the mouse path ends on the same two pans the keyboard path wrote")
		for _n in range(7): await click("valve")
		check(game.state.oil == 7,"seven clicks at the jug fill the pot with the promised seven")
		await click("deliver")
		check(game.state.stage == "weighing" and game.state.weighs == 1,
			"a replayed scene counts its own lifts from zero")
		await click("skip"); await click("skip")
		check(game.state.stage == "complete" and Rules.solved(game.state)
			and game.world.shown_oil() == 7,
			"the replayed table closes with the same seven units handed over")
		check("这一坛抬过 1 次秤" in ui_text("验看单").text,
			"and the slip counts the one lift this run actually made")
		guards("replay")
		await capture(prefix+"15-replay-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK11 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

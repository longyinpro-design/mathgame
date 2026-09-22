extends SceneTree
# MK18 实窗审计：真实窗口里走完「共同订单 → 更正信 → 点亮领航灯」三阶段，
# 在 1280×720 与 960×540、两封回信各拍一遍，并核对台面上的文字有没有爬出自己的边框。
# 运行：godot --path . --script tests/market/mk18_playtest.gd
const Scene = preload("res://game/market_mk18.tscn")
const Level = preload("res://scripts/market/mk18_scene.gd")
const World = preload("res://scripts/market/mk18_world.gd")
const Rules = preload("res://scripts/market/mk18_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk18-lantern"
const SOLUTION = [1, 3, 4]
# 1280×720 的分支甲拍全程；其余三档只拍会随分支或分辨率变化的关键帧。
const KEY_FRAMES = ["01-arrival", "07-letters-stamped", "09-alloc-full", "10-preview",
	"13-lit", "15-voyage", "16-ending"]

func _initialize() -> void: Focus.configure(root); call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

func keep(name: String, branch: int, small: bool) -> bool:
	return (not small and branch == 0) or KEY_FRAMES.has(name)

func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE + "/" + name + ".png")

# 只有该拍的一帧才走渲染：等两帧、截图，其余直接跳过。
func shot(prefix: String, name: String, branch: int, small: bool) -> void:
	if keep(name, branch, small): await capture(prefix + "-" + name)

func click(id: String) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false, "button unavailable " + id); return
	var b: Control = game.buttons[id]
	var logical = b.get_global_transform_with_canvas() * (b.size / 2)
	var point = logical * Vector2(root.size) / Vector2(1280, 720)
	for down in [true, false]:
		var event = InputEventMouseButton.new(); event.position = point
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame

func key(code: int) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for down in [true, false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down
		root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame

func hold(seconds: float) -> void:
	game.paused = true; game.elapsed = seconds
	game.world.progress = minf(1.0, seconds / game.duration())
	game.world.queue_redraw() # explicit fixture pose while presentation is paused
	await process_frame

func fits(text: String, size_px: int, width: float) -> bool:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UIStyle.text_size(size_px)).x)
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

# 世界层里的牌子是 draw_string 画的，不会被 Label 的盒子拦住，只能按字号量一遍。
func plaque_audit(label: String) -> void:
	var packs := 0.0
	for kind in range(Rules.KINDS):
		packs = maxf(packs, UIStyle.face().get_string_size(Rules.pack_caption(kind),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	check(packs <= World.CAPTION_WIDTH - 12.0, "%s: pack captions hold their own plaque" % label)
	var boards := 0.0
	for slot in range(3):
		for branch in range(2):
			for row in [Rules.NEEDS_A[slot], Rules.NEEDS_B[slot]]:
				var text = "%s %d/%d·需 %d/%d" % [Rules.LINES[slot], row[Rules.OIL], row[Rules.WICK],
					Rules.needs(branch)[slot][Rules.OIL], Rules.needs(branch)[slot][Rules.WICK]]
				boards = maxf(boards, UIStyle.face().get_string_size(text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	check(boards <= World.PLAQUE_WIDTH - 12.0, "%s: street plaques hold their own board" % label)
	var lamp = UIStyle.face().get_string_size("领航灯 2/1·留 2/1", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	check(lamp <= 180.0 - 12.0, "%s: the lamp plaque holds its own board" % label)
	var preview = UIStyle.face().get_string_size("整单预览中 · 点货台撤回", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	check(preview <= 202.0 - 12.0, "%s: the revoke caption holds its own board" % label)
	var chest = UIStyle.face().get_string_size("空信槽 3/3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	check(chest <= 104.0, "%s: the chest slot reads inside the boss" % label)

# ---- 台面上的每一句话：两行以内、绝不越出自家的板子 ----
func text_audit(label: String) -> void:
	check(not game.line().is_empty() and game.line().count("\n") <= 1,
		"%s: the scene speaks in two lines at most" % label)
	check(fits(game.line(), 20, 798.0), "%s: the dialogue stays inside the sign" % label)
	var goal = game.goal_line()
	check(goal.is_empty() or fits(goal, 22, 762.0), "%s: the goal line holds the goal board" % label)
	var status = game.status_line()
	check(status.is_empty() or fits(status, 20, 300.0), "%s: the status line holds the counter" % label)
	for spoken in game.hint_texts():
		check(spoken.count("\n") <= 1 and fits(spoken, 20, 798.0),
			"%s: a hint fits the sign (%s)" % [label, spoken.left(6)])

# ---- 信纸上的字压在那颗烤死的蓝蜡上：取色验一次托底 ----
# 共同订单的四行是 draw_string 直接落在信纸原图上的，纸的右下角烤着一颗蓝蜡，
# 第四行「领航灯 2/1」的尾巴正好压上去。蜡是暗的，浅字加暗描边落在蜡上就分不出笔画，
# 所以纸上的字改成深墨配浅纸光晕。蜡的位置从原图现算（蓝得比红多就是它），
# 再按脚点、缩放和宿主镜头换算到屏幕——以后换图或挪纸都还是这一条。
const PAPER_ART = "res://assets/runtime/market/kit-v1/sprites/receipt_blank.png"

func patch_lumen(image: Image, rect: Rect2) -> float:
	var total = 0.0
	var seen = 0
	for y in range(roundi(rect.position.y), roundi(rect.end.y)):
		for x in range(roundi(rect.position.x), roundi(rect.end.x)):
			var c = image.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0; seen += 1
	return total * 255.0 / seen if seen > 0 else 0.0

func paper_audit(label: String) -> void:
	# Some branches skip shot(); sample this committed frame, not the prior screen.
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	var sprite = Image.load_from_file(ProjectSettings.globalize_path(PAPER_ART))
	check(sprite != null, "%s: the letter paper art can be read back" % label)
	if sprite == null: return
	var wax := Rect2()
	for y in range(150, sprite.get_height()):
		for x in range(100, sprite.get_width()):
			var c = sprite.get_pixel(x, y)
			if c.a < 0.5 or c.b <= c.r + 0.078 or c.b <= 0.196: continue
			wax = wax.merge(Rect2(x, y, 1, 1)) if wax.size.x > 0 else Rect2(x, y, 1, 1)
	var scale = World.PAPER_WIDTH / float(sprite.get_width())
	var anchor: Array = game.world.parts["receipt_blank"].anchor_px
	var origin: Vector2 = game.world.order_foot() - Vector2(anchor[0], anchor[1]) * scale
	game.update_camera()
	var to_screen = func(box: Rect2) -> Rect2:
		return Rect2(game.world.position + game.world.scale * box.position,
			game.world.scale * box.size)
	var wax_screen = to_screen.call(Rect2(origin + wax.position * scale, wax.size * scale))
	var top: Vector2 = game.world.order_foot() \
		+ Vector2(-World.PAPER_WIDTH / 2.0 + 9.0, -World.PAPER_WIDTH * 1.33 + 26.0)
	var caption = str(Rules.line_caption(Rules.NEEDS_A, 3))
	var wide = UIStyle.face().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var ink_screen = to_screen.call(Rect2(top.x, top.y + 19.0 * 4 - 12.0, wide, 15.0))
	var cross = wax_screen.intersection(ink_screen)
	check(cross.size.x >= 4.0 and cross.size.y >= 8.0,
		"%s: 第四行确实压在蓝蜡上（压到 %.0f×%.0f 像素）" % [label, cross.size.x, cross.size.y])
	var image = root.get_texture().get_image()
	var control = Rect2(to_screen.call(Rect2(
		origin + (wax.position + wax.size * 0.5) * scale, Vector2.ZERO)).position - Vector2(4, 4),
		Vector2(8, 8))
	var wax_only = patch_lumen(image, control)
	var lifted = patch_lumen(image, cross)
	check(wax_only <= 90.0,
		"%s: 取样点确实在蜡上（蜡心亮度 %.1f，还是一片暗）" % [label, wax_only])
	check(lifted >= 118.0,
		"%s: 蜡上那一小块被浅纸光晕托亮，实测 %.1f（改之前只有 %.1f）" % [label, lifted, 103.4])

func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("MK18 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for branch in range(2):
		for small in [false, true]:
			var prefix = "b%d-%s" % [branch, "960x540" if small else "1280x720"]
			root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
			var path = "/tmp/pixel-mk18-ui-" + str(Time.get_ticks_usec()) + ".json"
			# 分支在关卡创建时就固定：实窗只认这份写好的开局记录，反复读信也不会换成另一张。
			var seed = FileAccess.open(path, FileAccess.WRITE)
			seed.store_string(JSON.stringify(Rules.fresh(branch))); seed.close()
			game = Scene.instantiate(); game.save_path = path; root.add_child(game)
			await process_frame
			if not await Focus.ready(root): quit(1); return
			check(game.state.branch == branch and game.state.stage == "arrival",
				"%s: opens on the harbour with its own reply fixed" % prefix)
			check(game.line() == Level.LINES[0],
				"%s: opens on the three streets' shared report" % prefix)
			if not small: plaque_audit(prefix)
			await shot(prefix, "01-arrival", branch, small)
			await key(KEY_TAB)
			check(root.gui_get_focus_owner() == game.buttons.next,
				"%s: Tab focuses the first narrative action" % prefix)
			await key(KEY_ENTER)
			check(game.state.beat == 1, "%s: Enter advances the focused line" % prefix)
			if not small: text_audit("%s line 2" % prefix)
			for beat in range(Rules.ARRIVAL_BEATS - 1): await click("next")
			check(game.state.stage == "approach",
				"%s: the last line walks the player onto the dock" % prefix)
			await click("pause")
			var frozen: float = game.elapsed
			await create_timer(0.12).timeout
			check(game.elapsed == frozen, "%s: pause freezes the walk-in" % prefix)
			await shot(prefix, "02-walk-in", branch, small)
			await click("skip")
			check(game.state.stage == "ready", "%s: approach stops before player control" % prefix)
			await click("next")
			check(game.state.stage == "puzzle" and game.phase() == 1,
				"%s: the counter is handed to the player" % prefix)
			if not small:
				text_audit("%s phase 1" % prefix)
				check(spilled(game.ui) == 0,
					"%s: nothing spills out of its box on an empty counter" % prefix)
			check("键盘 1 2 3" in game.line() and "Q W E" in game.line(),
				"%s: 开台那一句把两颗键各自管什么都说出来" % prefix)
			check(game.buttons.pack_0_0.tooltip_text.count("\n") == 1
				and "键盘 1 加一包" in game.buttons.pack_0_0.tooltip_text,
				"%s: 每一行封包的说明里写着自己那两颗键" % prefix)
			await shot(prefix, "03-order", branch, small)
			if not small: await paper_audit(prefix)
			await click("pack_0_2")
			check(game.state.order == [3, 0, 0],
				"%s: one click dials three packs of a kind at once" % prefix)
			await click("deliver")
			check(game.state.stage == "puzzle" and "共同订单要 14 提油" in game.message,
				"%s: the refusal counts the jugs in the player's own units" % prefix)
			await shot(prefix, "04-refusal", branch, small)
			for tier in range(Rules.HINT_TIERS): await click("hint")
			check(game.state.hint == Rules.HINT_TIERS and "芯还差 4 束" in game.message
				and not "A×1" in game.message,
				"%s: the third reminder gives one step, never the whole order" % prefix)
			await click("pack_0_2")
			check(game.state.order == [2, 0, 0],
				"%s: clicking the front of the booked run dials one back" % prefix)
			await click("pack_0_1"); await click("pack_1_2"); await click("pack_2_3")
			check(game.state.order == SOLUTION,
				"%s: the whole order is dialled in three clicks" % prefix)
			await key(KEY_1)
			check(game.state.order[0] == 2, "%s: the number keys dial their own pack kind" % prefix)
			await key(KEY_Q)
			check(game.state.order == SOLUTION, "%s: the second row of keys hands a pack back" % prefix)
			check(game.world.sealed_count() == 0, "%s: no receipt exists before the delivery" % prefix)
			await shot(prefix, "05-solved-order", branch, small)
			await click("deliver")
			check(game.state.stage == "stocking" and game.state.bought == SOLUTION,
				"%s: one submit books the whole order" % prefix)
			await hold(1.3)
			check(game.world.progress > 0.4 and game.world.progress < 0.6,
				"%s: the goods are carried in one continuous motion" % prefix)
			await shot(prefix, "06-stocking", branch, small)
			await click("skip")
			check(game.state.stage == "clarify",
				"%s: the correction letter arrives after 桥头街 is served" % prefix)
			await click("next"); await click("next")
			check(game.state.beat == 2, "%s: the envelopes are read one beat at a time" % prefix)
			if not small: text_audit("%s letters" % prefix)
			check(Level.BRANCH_LINE[branch] == game.line(),
				"%s: the last letter names the reply in play" % prefix)
			await shot(prefix, "07-letters-stamped", branch, small)
			await click("next")
			check(game.state.stage == "puzzle" and game.phase() == 2, "%s: the second phase begins" % prefix)
			check(game.state.branch == branch,
				"%s: reading the letters never re-rolls the reply" % prefix)
			if not small: text_audit("%s phase 2" % prefix)
			await click("put_0_0"); await click("put_0_0"); await click("put_2_0")
			check(game.state.alloc == [[2, 0], [0, 0], [1, 0]], "%s: a tap lays exactly one unit" % prefix)
			await click("back_0_0")
			check(game.state.alloc[0] == [1, 0],
				"%s: the minus cell hands one jug back to the counter" % prefix)
			await shot(prefix, "08-alloc", branch, small)
			await click("deliver")
			check(game.state.preview == 0 and "中街" in game.message and "现在摆的是" in game.message,
				"%s: an incomplete split is refused as 中街's own promise" % prefix)
			for slot in range(Rules.SLOTS):
				for kind in range(2):
					var owe = Rules.slot_needs(branch)[slot][kind] - game.state.alloc[slot][kind]
					for _unit in range(owe): await click("put_%d_%d" % [slot, kind])
			check(game.state.alloc == Rules.slot_needs(branch),
				"%s: the whole split is laid out by clicking (%s)" % [prefix, Rules.branch_word(branch)])
			if not small: check(spilled(game.ui) == 0, "%s: the filled table adds no spilled text" % prefix)
			await shot(prefix, "09-alloc-full", branch, small)
			await click("deliver")
			check(game.state.preview == 1, "%s: the first submit shows the whole order" % prefix)
			check(game.buttons.has("revoke"),
				"%s: the preview can be revoked before the goods move" % prefix)
			await shot(prefix, "10-preview", branch, small)
			await click("revoke")
			check(game.state.preview == 0, "%s: revoking puts every good back on the counter" % prefix)
			await click("deliver")
			check(game.state.preview == 1, "%s: the preview can be raised again" % prefix)
			await click("deliver")
			check(game.state.stage == "delivering" and game.state.handed == Rules.slot_needs(branch),
				"%s: the previewed split is what actually moves" % prefix)
			await hold(1.4)
			await shot(prefix, "11-delivering", branch, small)
			await click("skip")
			check(game.state.stage == "puzzle" and game.phase() == 3, "%s: the third phase begins" % prefix)
			check(game.history.is_empty(), "%s: the undo stack starts over with each phase" % prefix)
			if not small: text_audit("%s phase 3" % prefix)
			check("键盘 L" in game.line() and "键盘 L" in game.buttons.lamp.tooltip_text,
				"%s: 领航灯的键位写在台面话里，也写在灯自己的牌上" % prefix)
			await key(KEY_L)
			check(game.state.lamp == 1, "%s: 按 L 真把预留的那份装进灯里" % prefix)
			await click("lamp")
			check(game.state.lamp == 0, "%s: 再点一下把油芯抽回货台，账一克不动" % prefix)
			for tier in range(3): await click("hint")
			check(game.state.hint == Rules.HINT_TIERS, "%s: the third reminder is the last one" % prefix)
			await click("deliver")
			check("领航灯还空着" in game.message and game.state.lamp == 0,
				"%s: a dark lantern is refused in the player's own terms" % prefix)
			await shot(prefix, "12-lamp-dark", branch, small)
			await click("lamp")
			check(game.state.lamp == 1, "%s: the reserved 2 油 1 芯 goes into the lantern by hand" % prefix)
			await click("deliver")
			check("空信槽" in game.message, "%s: an empty chest slot is its own reason" % prefix)
			await click("lamp")
			check(game.state.lamp == 0, "%s: the load can be taken back out again" % prefix)
			await click("lamp")
			await shot(prefix, "13-lit", branch, small)
			for street in range(3): await click("seal_%d" % street)
			check(game.state.sealed == [1, 1, 1] and game.world.sealed_count() == 3,
				"%s: three real receipts close the chest slot" % prefix)
			await shot(prefix, "14-sealed", branch, small)
			await click("deliver")
			check(game.state.stage == "lighting", "%s: all three facts release the finale" % prefix)
			await hold(1.2)
			await click("skip")
			check(game.state.stage == "voyage", "%s: the lantern rig unfolds into the ship" % prefix)
			await hold(1.7)
			var ship = game.world.ship_foot()
			check(ship.x > 560 and ship.y < 480, "%s: the ship is on the water, not on the dock" % prefix)
			await shot(prefix, "15-voyage", branch, small)
			await click("skip")
			check(game.state.stage == "complete" and Rules.validate(game.state),
				"%s: the ship sails out on a legal save" % prefix)
			if not small: check(spilled(game.ui) == 0, "%s: the ending panel holds its own paper" % prefix)
			var handed = Rules.needs(branch)[1]
			var receipt: Label = null
			for child in game.ui.get_children():
				if child is Label and "让每一盏灯都有回信" in child.text: receipt = child
			check(receipt != null and receipt.text.contains(Rules.goods(handed[Rules.OIL], handed[Rules.WICK])),
				"%s: the receipt quotes what 中街 actually got" % prefix)
			check(receipt != null and receipt.text.contains(Rules.branch_word(branch)),
				"%s: the receipt names the reply this night actually honoured" % prefix)
			check(receipt != null and fits(receipt.text, 18, receipt.size.x)
				and receipt.get_combined_minimum_size().y <= receipt.size.y,
				"%s: the receipt holds its own paper" % prefix)
			await shot(prefix, "16-ending", branch, small)
			var on_disk = game.state.duplicate(true)
			game.queue_free(); await process_frame
			game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
			check(game.state == on_disk, "%s: the finished night reloads exactly as booked" % prefix)
			check(game.state.branch == branch, "%s: a reload never changes the reply" % prefix)
			game.queue_free(); await process_frame
			Bridge.origin = "hub"
			game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
			check(game.origin == "hub" and Bridge.origin.is_empty(),
				"%s: the chart hand-off is consumed once" % prefix)
			check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
				"%s: a visit from the chart offers only the way back" % prefix)
			await shot(prefix, "17-chart-return", branch, small)
			await click("next"); await click("confirm")
			check(game.state.stage == "arrival" and game.state.bought == [0, 0, 0]
				and Rules.legal_branch(game.state.branch),
				"%s: replaying rewinds only this station and refixes one reply" % prefix)
			await click("next"); await click("next"); await click("next"); await click("next")
			check(game.state.stage == "approach", "%s: the same four lines carry the player back" % prefix)
			await click("skip"); await click("next")
			check(game.state.stage == "puzzle" and game.phase() == 1,
				"%s: the counter opens untouched again" % prefix)
			for kind in range(Rules.KINDS):
				for index in range(SOLUTION[kind]): await click("pack_%d_%d" % [kind, index])
			check(game.state.order == SOLUTION, "%s: the mouse path dials the same order" % prefix)
			await click("reset"); await click("confirm")
			check(game.state.order == [0, 0, 0],
				"%s: 清空订单 puts every pack back on the shelf" % prefix)
			await click("deliver")
			check("先把这一晚要买的整包选出来" in game.message,
				"%s: an untouched counter asks for the order instead of blaming a promise" % prefix)
			await key(KEY_Z)
			check(game.state.order == SOLUTION, "%s: one undo brings the whole order back" % prefix)
			await shot(prefix, "18-replay-table", branch, small)
			game.queue_free(); await process_frame
			DirAccess.remove_absolute(path)
	print("MARKET MK18 WINDOW ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

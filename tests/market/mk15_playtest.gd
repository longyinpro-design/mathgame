extends SceneTree
# MK15 实窗审计：真实窗口里走一遍「听三句 → 走到摊前 → 一组组换 → 提交被拒 → 绕成一圈 → 拆招牌 → 风铃与回执」，
# 在 1280×720 与 960×540 各拍一次，并检查摊板与柜面的文字有没有爬出自己的牌子。
const Scene = preload("res://game/market_mk15.tscn")
const Rules = preload("res://scripts/market/mk15_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const CAPTURE = "res://docs/playtest/market-mk15-copper-nut"
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
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
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
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame
func hold(seconds: float) -> void:
	game.paused = true; game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	game.world.queue_redraw() # explicit fixture pose while presentation is paused
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

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("MK15 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk15-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival" and "凭空多一颗" in game.line(),
			"opens on the fraudulent sign across the street, not on a puzzle")
		check(spilled(game.ui) == 0,"the opening dialogue stays inside its board")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		await click("next"); await click("next")
		check(game.state.stage == "approach","the third line walks the player to the copper-fruit stall")
		await capture(prefix+"02-walk-in")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		await click("skip")
		check(game.state.stage == "ready","approach stops before player control")
		await click("next")
		check(game.state.stage == "puzzle" and game.state.fruit == 12,"the counter is handed over with one batch of 12 fruits")
		var small_target = 0
		var framed = 0
		for id in game.buttons:
			var b: Control = game.buttons[id]
			if not id.begins_with("line_") and not id.begins_with("bulk_") and not id.begins_with("pile_") and id != "sign": continue
			if b.size.x < 48 or b.size.y < 48: small_target += 1
			var rect = b.get_global_rect()
			if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed += 1
		check(small_target == 0,"every contract board, bulk strip, pile and the sign is a 48 pixel target or bigger")
		check(framed == 0,"no counter hotspot leaves the 1280x720 frame or sits under the bottom bar")
		check(spilled(game.ui) == 0,"no counter text spills out of its box on the untouched table")
		await capture(prefix+"03-table")
		await click("line_0")
		check(game.state.used == [1,0,0] and game.state.fruit == 10 and game.state.thread == 3,
			"clicking contract one really moves two fruits onto the thread pile")
		await key(KEY_1)
		check(game.state.used == [2,0,0],"the number key books the second group, not a replay of the first")
		await click("bulk_0")
		check(game.state.used == [6,0,0] and game.state.thread == 18 and game.state.fruit == 0,
			"整批 clears the whole batch of fruits into 18 spools in one move")
		await capture(prefix+"04-all-thread")
		await click("deliver")
		check(game.state.stage == "puzzle" and "合同二" in game.message,
			"the stall answers only after 拆穿招牌, and names the contract that never ran")
		await capture(prefix+"05-refused-halfway")
		await key(KEY_Z)
		check(game.state.used == [2,0,0],"one undo lifts the whole batch of fruits back off the thread")
		await click("bulk_1")
		check(game.state.used == [2,3,0] and game.state.core == 3,"整批 on contract two makes 3 wick cores out of 6 spools")
		await click("sign")
		check("13" in game.message and game.state.fruit == 8 and game.state.used == [2,3,0],
			"asking the sign books nothing: the 13th fruit fits no contract")
		await capture(prefix+"06-sign-asked")
		for n in range(4): await click("hint")
		check(game.state.hint == 3 and "4 果 → 6 线 → 3 芯 → 4 果" in game.message,
			"the third hint gives the shortest ring and stops there")
		await click("bulk_2")
		check(Rules.solved(game.state) and game.state.fruit == 12 and game.state.thread == 0 and game.state.core == 0,
			"the ring closes only when the counter holds the same 12 fruits and nothing else")
		check("台面共 36 格" in Rules.total_caption(game.state),"the running total never moved off 36 units")
		await capture(prefix+"07-closed-ring")
		await click("sign")
		check("没有第 13 颗" in game.message,"the sign is named as a lie once the ring is closed")
		await click("deliver")
		check(game.state.stage == "ringing","the accepted ring starts the counter showing its own loop")
		await hold(1.4)
		check(game.world.progress > 0.4 and game.world.progress < 0.6,"the goods ride round fruit → thread → core → fruit in one motion")
		await capture(prefix+"08-ringing")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the ringing")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "delivery","the ring hands over to taking the sign down")
		await hold(1.2); await capture(prefix+"09-sign-falls")
		await click("skip")
		check(game.state.stage == "complete" and Rules.validate(game.state),"the sign comes down as the exchange chime")
		check(spilled(game.ui) == 0,"the receipt adds no spilled text")
		var paper: Label = null
		for child in game.ui.get_children():
			if child is Label and "回执 · 铜果摊绕圈" in child.text: paper = child
		check(paper != null and paper.text.contains("合同一 ×2：4 果 → 6 线"),
			"the receipt restates the groups the player actually booked, not a fuller loop")
		var receipt_width := 0.0
		for spoken in String(paper.text).split("\n"):
			receipt_width = maxf(receipt_width, UIStyle.face().get_string_size(spoken, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UIStyle.text_size(16)).x)
		check(receipt_width <= paper.size.x,"回执最宽一行 %d 排在 %d 宽的纸上" % [receipt_width, paper.size.x])
		await capture(prefix+"10-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"the closed ring reloads from disk exactly as booked")
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
		check(game.state.used == [2,3,1],"cancelling keeps the ring the player closed")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.used == [0,0,0],"replaying rewinds only this stall")
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","the same three lines carry the player back to the counter")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle","the walk-in still stops before player control")
		for step in range(18):
			await key(KEY_1)
			await key(KEY_2)
			await key(KEY_3)
		check(game.state.used == [6,9,3] and Rules.solved(game.state),
			"the slow mouse-free path books all 18 groups one at a time and lands on the same 12 fruits")
		await click("reset"); await click("confirm")
		check(game.state.used == [0,0,0] and game.state.fruit == 12,"重摆 puts every good of this batch back on the counter")
		await click("deliver")
		check(game.state.stage == "puzzle" and "绕一圈" in game.message,"an untouched counter names its own gap instead of solving it")
		check(not "4 果 → 6 线" in game.message,"the refusal never highlights the answer")
		await capture(prefix+"11-back-to-start")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK15 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

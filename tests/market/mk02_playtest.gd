extends SceneTree
const Scene = preload("res://game/market_mk02.tscn")
const Rules = preload("res://scripts/market/mk02_rules.gd")
const Sample = preload("res://scripts/market/mk02_scene.gd")
const World = preload("res://scripts/market/mk02_world.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const HarborSample = preload("res://scripts/market/mk01_scene.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
var game: Control
var checks = 0
var failures = 0
const CAPTURE = "res://docs/playtest/market-mk02-exchange"
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
	# Pause first so the frame boundary cannot add a variable delta to the pose under test.
	game.paused = true
	game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	await process_frame
# 抬头那两块板与回执板都由 UIStyle.text 画：Label 的框按板子内框写死，汉字又从不折行，
# 一句超长的话会直接爬出板子外面。这里按真实字号量每一句，超框就算缺陷。
func spilled_labels() -> int:
	var over = 0
	for child in game.ui.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = 0.0
		var widest = ""
		for line in child.text.split("\n"):
			var width = UIStyle.face().get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,
				-1,child.get_theme_font_size("font_size")).x
			if width > needed: needed = width; widest = line
		if needed > child.size.x+0.5:
			over += 1; print("LABEL ",widest," needs ",needed," in ",child.size.x)
	return over
# 回执板在 ui 层、四条木牌画在世界层：谁压住谁要看镜头此刻的换算，这里不重抄那条换算式。
func receipt_covers_planks() -> bool:
	var at: Transform2D = game.world.get_global_transform_with_canvas()
	return Sample.RECEIPT.end.y > (at * Vector2(330,World.PLAQUE_ROW_Y)).y
func pool_readout() -> String:
	var found = ""
	for child in game.ui.get_children():
		if child is Label and "可换" in child.text: found += child.text
	return found
func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK02 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk02-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival","opens on the nursery dialogue")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused narrative action")
		await click("next"); await click("next")
		check(game.state.stage == "approach","the third line walks the player to the counter")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"camera pause freezes the walk-in")
		await click("skip")
		check(game.state.stage == "ready","approach stops before player control")
		await click("next")
		check(game.state.stage == "puzzle" and game.world.parts.has("copper_fruit"),"kit-v1 parts are loaded with the table")
		check(game.buttons.rack_0.size.x >= 48 and game.buttons.hook_0.size.y >= 48,"drop targets keep the 48 pixel logical floor")
		check(game.world.scale.x > 1.09,"the camera is already at the counter when the player takes over")
		check("第1位" in game.buttons.rack_0.tooltip_text and "第6位" in game.buttons.hook_0.tooltip_text
			and "第7位" in game.buttons.hook_1.tooltip_text,
			"the seven drop targets are numbered by the very key that reaches them")
		check("铜果 8 颗" in pool_readout() and "线卷 0 卷" in pool_readout() and not " 个 " in pool_readout(),
			"both pools are counted with the measure word the rest of the chapter uses")
		check(spilled_labels() == 0,"nothing written on a board climbs out of it")
		await capture(prefix+"02-table")
		await key(KEY_Q)
		check(game.state.stage == "exchanging" and game.state.exchange == [0,1],"keyboard Q stages one fruit group")
		check(game.world.scale.x > 1.09,"the camera holds the counter through the exchange animation")
		await click("skip")
		check(game.state.a == 1 and game.world.shown_state().b == 0,"a single group books exactly once")
		await click("batch_0")
		check(game.state.exchange == [0,3],"the batch button spends the remaining fruit pairs")
		game.elapsed = 0.5; game.world.progress = 0.5 / game.duration(); await process_frame
		check(game.world.progress > 0.2 and game.world.progress < 0.5,"the batch animation holds a mid-flight frame")
		check(game.world.in_flight_homes().size() == Rules.GROUP * 3,"the batch carries every fruit of the group at once")
		var closest := 9999.0
		var probe := 0.02
		while probe <= 0.5:
			var carried = game.world.carry_plan(probe)
			for i in range(carried.size()):
				for j in range(i + 1, carried.size()):
					closest = minf(closest, carried[i]["at"].distance_to(carried[j]["at"]))
			probe += 0.02
		check(closest >= 20.0,"the six carried fruits stay a piece apart for the whole flight")
		await capture(prefix+"03-exchange-flight")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		paused_at = game.elapsed; await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at,"focus loss freezes the exchange mid-flight")
		await click("skip")
		check(game.state.a == 4 and Rules.spools_loose(game.state) == 12,"the basket is spent and twelve spools are on the table")
		await capture(prefix+"04-full-table")
		await click("batch_1"); await click("skip")
		check(game.state.b == 6 and Rules.wicks_loose(game.state) == 6,"the all-line plan makes six wicks")
		for slot in range(Rules.RACK_SLOTS): await click("rack_%d"%slot)
		check(game.state.rack.count(1) == 5,"five clicks fill the delivery rack")
		await click("hook_0")
		check(game.state.hook == [0,0],"nothing hangs when the line has all become wicks")
		await click("deliver")
		check(game.state.stage == "puzzle" and "捆货绳" in game.message,"the unmet promise is named before the hand-over")
		await capture(prefix+"05-all-line-trap")
		for n in range(6): await key(KEY_Z)
		check(game.state.a == 4 and game.state.b == 0 and game.state.rack.count(1) == 0,"six undos rewind the trap to twelve spools")
		await key(KEY_Z)
		check(game.state.a == 1,"one more undo hands a fruit batch back to the basket")
		await click("batch_0"); await click("skip")
		check(game.state.a == 4 and Rules.spools_loose(game.state) == 12,"re-exchanging restores the full table")
		for n in range(3): await click("hint")
		check(game.state.hint == 3 and "留 2 卷给扣扣" in game.message,"the third hint states the whole split")
		await click("deliver")
		check(game.state.stage == "puzzle" and "灯芯" in game.message,"an empty rack blocks the hand-over with its own reason")
		for n in range(5):
			await click("single_1"); await click("skip")
		for slot in range(Rules.RACK_SLOTS): await click("rack_%d"%slot)
		for slot in range(Rules.HOOK_SLOTS): await key(KEY_6+slot)
		check(game.state.hook == [1,1],"the two keys the tooltips number 第6/第7位 are the two that hang the spools")
		check(Rules.solved(game.state),"five wicks and two bench spools close both promises")
		await capture(prefix+"06-solved-table")
		await click("reset"); await click("cancel")
		check(game.state.rack.count(1) == 5,"cancelling the reset keeps every good in place")
		await click("deliver")
		check(game.state.stage == "delivery","the accepted order starts the hand-over")
		await hold(2.8)
		check(game.world.progress > 0.6 and game.world.progress < 0.8,"wicks are away while the kept line is still on its way")
		await capture(prefix+"07-delivery")
		await hold(game.duration())
		check(game.world.walk_off() == 1.0 and game.world.hand_off() == 1.0 and game.world.shipped() == 1.0,
			"the last delivery frame has already handed every good over")
		await click("skip")
		check(game.state.stage == "complete" and game.state.hook.count(1) == 2,"the delivery ends with 扣扣's two spools kept")
		check(game.world.walk_off() == 1.0 and game.world.hand_off() == 1.0 and game.world.shipped() == 1.0,
			"the finished counter is the pose the hand-over ended in, not a snap back")
		check(not game.buttons.has("back_camp"),"a standalone sample keeps its own exit")
		await capture(prefix+"08-receipt")
		var receipt = ""
		for child in game.ui.get_children():
			if child is Label and "回执 · 育苗铺" in child.text: receipt = child.text
		check(receipt.contains("约定一 ×4") and receipt.contains("交付架 5 根"),
			"the receipt restates the groups the player actually made")
		check(not receipt_covers_planks(),"the receipt stops above the two conventions nailed to the counter")
		check(spilled_labels() == 0,"no word on the finished counter climbs out of its board")
		await click("next"); await click("cancel")
		check(game.state.stage == "complete","leaving the restart dialog preserves the finished order")
		game.queue_free(); await process_frame
		# A station opened from the chart hands the player back to the chart.
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state.stage == "complete" and game.buttons.has("back_hub"),
			"the finished nursery, opened from the chart, offers the way back to it")
		check(not game.buttons.has("back_camp"),"the camp door waits for the harbour hand-off only")
		game.queue_free(); await process_frame
		Bridge.origin = "mk01"; HarborSample.entry = "camp"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "mk01" and Bridge.origin.is_empty() and HarborSample.entry == "camp","the harbour hand-off is consumed once")
		check(game.buttons.has("back_camp") and not game.buttons.back_camp.disabled,"the finished order offers the way back to camp")
		if not small: await capture("09-return-to-camp")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK02 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

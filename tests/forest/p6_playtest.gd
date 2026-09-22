extends SceneTree
const SCENE = preload("res://game/forest_release.tscn")
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Cargo = preload("res://scripts/mechanisms/cargo_rules.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var game: Control
var checks = 0
var failures = 0
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func click(point: Vector2) -> void:
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; root.push_input(event)
	await process_frame
func button(id: String) -> void:
	if not game.buttons.has(id): check(false,"missing "+id); return
	var b: Button = game.buttons[id]
	var parent = b.get_parent()
	if parent.get_parent() is ScrollContainer:
		parent.get_parent().ensure_control_visible(b); await process_frame
	await click(b.get_global_rect().get_center())
	while game.busy: await create_timer(0.005).timeout
func key(code: Key, unicode_value: int = 0) -> void:
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for pressed in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.unicode = unicode_value; event.pressed = pressed; root.push_input(event)
	await process_frame
func number(id: String, value: int) -> void:
	var line: LineEdit = game.ui.get_node(id)
	line.grab_focus(); await process_frame; line.select_all()
	for character in str(value): await key(KEY_0+int(character),character.unicode_at(0))
	await key(KEY_ENTER)
	await process_frame
func capture(name: String) -> void:
	await create_timer(0.1).timeout; RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://docs/playtest/forest-release/"+name+".png")
func enter(id: String, region: String) -> void:
	game.show_region(region); await process_frame; await button("object_"+id)
	# The runner restores the foreground on the first click, which cancels a walk by
	# design; a player would simply click the object again, so the test does too.
	if game.page == "region":
		if not game.session.feedback.contains("先停在这里"): push_error("expected visible walk-cancel feedback")
		await button("object_"+id)
		while game.busy: await create_timer(0.005).timeout
	check(game.page == "challenge" and game.session.profile.active_run.level_id == id,"actual entrance "+id)
func run() -> void:
	create_timer(80).timeout.connect(func(): push_error("P6 UI watchdog"); quit(1))
	game = SCENE.instantiate(); game.story_enabled = false; game.save_path = "/tmp/pixel-forest-p6-ui-"+str(Time.get_ticks_usec())+"/save.json"; game.time_scale = 0.02; root.add_child(game); await create_timer(0.25).timeout
	for i in range(1,13): check(Scenarios.play(game.session,"FL%02d"%i),"prior fixture FL%02d"%i)
	await enter("FL13","treetop")
	var count = 0
	while not game.session.profile.active_run.state.complete and count < 100:
		var action = Cargo.hint(game.session.catalog.levels.FL13.params,game.session.profile.active_run.state)
		if action.kind == "move": await key(KEY_1+action.item); await key([KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_UP][action.target])
		elif action.kind == "travel": await button("travel"); await create_timer(0.08).timeout
		else: check(false,"cargo has valid test route"); quit(1); return
		count += 1
	check(game.session.profile.active_run.outcome == "complete" and game.session.profile.active_run.state.trips == 2,"FL13 two trips settle via actual input")
	await capture("fl13-complete")
	if game.session.profile.active_run.outcome != "complete": quit(1); return
	await enter("FL14","post")
	for i in range(5): await button("parity_0_2")
	for value in [2,2,2,2,1]: await button("parity_1_"+str(value))
	# 上路之前要给 8/9/10 各判一个原因，再说清改一次向的代价（4）。
	for classify in ["classify_0_2","classify_1_1","classify_2_0"]: await button(classify)
	await number("flip_loss",4)
	await button("try"); check(game.session.profile.active_run.outcome == "complete","FL14 actual trajectories to 10 and 9")
	await capture("fl14-complete")
	if game.session.profile.active_run.outcome != "complete": quit(1); return
	await enter("FL15","mill")
	# 先说清至少要称几次（由 3^k 追上九颗推出），再摆方案。
	await number("min_weighings",2)
	for coin in range(6): await button("coin_"+str(coin)); await button("pan_"+("left" if coin < 3 else "right"))
	for i in range(3):
		var node: String = ["left","right","equal"][i]
		await button("coin_node_"+node)
		await button("coin_"+str(i*3)); await button("pan_left")
		await button("coin_"+str(i*3+1)); await button("pan_right")
	await button("try"); check(game.session.profile.active_run.outcome == "complete","FL15 actual two-weighing plan distinguishes nine crystals")
	await capture("fl15-complete")
	if game.session.profile.active_run.outcome != "complete": quit(1); return
	await enter("FL16","post")
	# 先押一注（最大 18 格）才允许调宽度，再扫完五种宽度、说清宽多的代价（2），最后围定 3×6。
	await number("area_guess",18)
	for step in range(4): await button("fence_w_more")
	await number("fence_loss",2)
	await button("fence_choose_2"); await button("try")
	check(game.session.profile.active_run.outcome == "complete","FL16 actual integer plans and maximum area")
	await capture("fl16-complete")
	game.queue_free(); await create_timer(0.25).timeout
	print("FOREST P6 UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

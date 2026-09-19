extends SceneTree
const SCENE = preload("res://game/forest_release.tscn")
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
	create_timer(65).timeout.connect(func(): push_error("P3 UI watchdog"); quit(1))
	game = SCENE.instantiate(); game.story_enabled = false; game.save_path = "/tmp/pixel-forest-p3-ui-"+str(Time.get_ticks_usec())+"/save.json"; game.time_scale = 0.02; root.add_child(game); await create_timer(0.25).timeout
	# Earlier slice is an explicitly command-driven fixture; new slice uses viewport input below.
	for id in ["FL01","FL02"]: check(Scenarios.play(game.session,id),"prior quest fixture "+id)
	await enter("FL03","village")
	for source in [1,1,2,2,2,2]: await button("pile_"+str(source)); await button("pile_0")
	await button("try")
	check(game.session.profile.active_run.outcome == "complete","FL03 actual transfers settle")
	await capture("fl03-complete")
	await enter("FL04","village")
	for pair in ["ab","bc","ac"]: await button("weigh_"+pair)
	for i in range(3): await number("weight_"+str(i),[12,17,18][i])
	await button("try")
	check(game.session.profile.active_run.outcome == "complete","FL04 actual weights settle")
	if game.session.profile.active_run.outcome != "complete": print(game.session.profile.active_run.state); quit(1); return
	await capture("fl04-complete")
	await button("camp"); await button("build_roof")
	check(game.modal,"construction asks concrete confirmation")
	await click(Vector2(772,435)); check("roof" in game.session.profile.inventory.buildings,"real construction spends wood once")
	await enter("FL05","mill")
	await button("module_triple"); await button("module_plus2")
	await button("try")
	check(game.session.profile.active_run.outcome == "complete","FL05 assembled machine settles")
	await capture("fl05-complete")
	await enter("FL06","mill")
	await button("probe_input_6")
	for id in ["A","B","C"]: await number("predict_"+id,{"A":16,"B":20,"C":18}[id])
	await button("probe")
	var output = game.session.profile.active_run.state.observation
	check(output.size() == 2,"FL06 real probe runs once after its written predictions")
	if output.size() != 2: quit(1); return
	await button("identify_"+{16:"A",20:"B",18:"C"}[int(output[1])])
	check(game.session.profile.active_run.outcome == "complete","FL06 visible observation identifies candidate")
	await capture("fl06-complete")
	await enter("FL07","mill")
	await button("number_card_3"); await button("number_card_1"); await button("operator_1")
	await button("number_card_1"); await button("number_card_2"); await button("operator_2")
	await button("number_card_1"); await button("number_card_0"); await button("operator_1")
	check(game.session.profile.active_run.outcome == "complete","FL07 real 24-point card arithmetic completes")
	await capture("fl07-complete")
	game.queue_free(); await create_timer(0.25).timeout
	print("FOREST P3 UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

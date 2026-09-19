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
func draw_path(path: String) -> void:
	for direction in path:
		var canvas = game.ui.get_node("route_canvas")
		var state: Dictionary = game.session.profile.active_run.state
		var x = state.draft.count("R")+(1 if direction == "R" else 0)
		var y = state.draft.count("U")+(1 if direction == "U" else 0)
		await click(canvas.global_position+canvas.point(x,y))
func run() -> void:
	create_timer(80).timeout.connect(func(): push_error("P4/P5 UI watchdog"); quit(1))
	game = SCENE.instantiate(); game.story_enabled = false; game.save_path = "/tmp/pixel-forest-p45-ui-"+str(Time.get_ticks_usec())+"/save.json"; game.time_scale = 0.02; root.add_child(game); await create_timer(0.25).timeout
	for i in range(1,8): check(Scenarios.play(game.session,"FL%02d"%i),"prior fixture FL%02d"%i)
	await enter("FL08","post")
	# Redesigned FL08: click the misfiled card’s 移正, draw the missing route, then
	# state the per-bag counts that prove nothing else is lost.
	var audit = preload("res://scripts/mechanisms/route_rules.gd")
	var params8: Dictionary = game.session.catalog.levels.FL08.params
	for index in game.session.profile.active_run.state.filing.size():
		var card: Dictionary = game.session.profile.active_run.state.filing[index]
		if card.group != card.path.find("R"): await button("audit_move_"+str(index))
	var listed: Array = []
	for card in game.session.profile.active_run.state.filing: listed.append(card.path)
	var missing_path = ""
	for candidate in audit.all_paths(params8):
		if candidate not in listed: missing_path = candidate
	for direction in missing_path: await button("route_right" if direction == "R" else "route_up")
	await button("audit_add")
	for height in range(3): await number("counts_"+str(height),[6,3,1][height])
	await button("try"); check(game.session.profile.active_run.outcome == "complete","FL08 real audit: misfiled card, missing route and bag counts")
	await capture("fl08-complete")
	if game.session.profile.active_run.outcome != "complete": quit(1); return
	await enter("FL10","post")
	# Redesigned FL10: choose a maximum simultaneous set, then the pigeonhole reason.
	await button("pick_RRRUU"); await button("pick_URRUR")
	await button("reason_0")
	await button("try"); check(game.session.profile.active_run.outcome == "complete","FL10 real simultaneous set plus stated ceiling")
	await capture("fl10-complete")
	if game.session.profile.active_run.outcome != "complete": quit(1); return
	await enter("FL09","post")
	await button("guess_1")
	for i in range(4): await number("block_predict_"+str(i),[8,11,11,8][i])
	for i in range(4): await button("block_tab_"+str(i))
	await button("block_tab_1"); await button("choose_block"); await button("try")
	check(game.session.profile.active_run.outcome == "complete","FL09 predictions, block preview and optimal choice")
	await capture("fl09-complete")
	if game.session.profile.active_run.outcome != "complete": quit(1); return
	await enter("FL11","heart")
	var count = 0
	while not game.session.profile.active_run.state.complete and count < 100:
		var action = Cargo.hint(game.session.catalog.levels.FL11.params,game.session.profile.active_run.state)
		if action.kind == "move":
			await key(KEY_1+action.item); await key([KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_UP][action.target])
		elif action.kind == "travel": await button("travel"); await create_timer(0.08).timeout
		else: check(false,"cargo has valid test route"); quit(1); return
		count += 1
	check(game.session.profile.active_run.outcome == "complete" and game.session.profile.active_run.state.trips == 3,"FL11 three-trip delivery settles")
	await capture("fl11-complete")
	if game.session.profile.active_run.outcome != "complete": quit(1); return
	await enter("FL12","heart")
	while game.session.profile.active_run.state.winner == "": await button("take_"+str(int(game.session.profile.active_run.state.remaining)%4))
	check(game.session.profile.active_run.outcome == "complete","FL12 winning duel settles")
	await capture("fl12-complete")
	await button("camp"); await button("grow"); check(game.session.profile.roster.grown,"actual camp growth")
	await capture("grown-camp")
	game.queue_free(); await create_timer(0.25).timeout
	print("FOREST P4/P5 UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

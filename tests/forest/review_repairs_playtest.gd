extends SceneTree
const SCENE = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Selector = preload("res://scripts/learning/challenge_selector.gd")
var game: Control
var checks = 0
var failures = 0
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	root.focus_exited.connect(func():
		if is_instance_valid(game): print("WINDOW_FOCUS_EXIT page=",game.page," selected=",game.selected," walking=",game.walking," at=",Time.get_ticks_msec()))
	root.focus_entered.connect(func(): print("WINDOW_FOCUS_ENTER at=",Time.get_ticks_msec()))
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
	if game.page == "visit": await button("practice")
	if game.page != "challenge": print("ENTRY_DIAGNOSTIC focus=",root.has_focus()," page=",game.page," feedback=",game.session.feedback)
	check(game.page == "challenge" and game.session.profile.active_run.level_id == id,"actual entrance "+id)
func labels_contain(value: String) -> bool:
	for parent in [game.ui,game.overlay]:
		for node in parent.find_children("*","Label",true,false):
			if value in node.text: return true
	return false
func load_game(path: String) -> void:
	game = SCENE.instantiate(); game.story_enabled = false; game.save_path = path; game.time_scale = 0.02; root.add_child(game); await create_timer(0.2).timeout
func run() -> void:
	create_timer(100).timeout.connect(func(): push_error("review repair UI watchdog"); quit(1))
	await load_game("/tmp/pixel-forest-repair-ui-"+str(Time.get_ticks_usec())+"/save.json")
	check(Scenarios.play(game.session,"FL01"),"first quest fixture")
	game.show_region("treetop"); await process_frame
	game.time_scale = 1.0
	var previous_run = game.session.profile.active_run.run_id
	await click(game.buttons.object_FL13.get_global_rect().get_center())
	check(game.walking and game.page == "region" and game.session.profile.active_run.run_id == previous_run,"R4 object click walks before opening challenge")
	while game.busy: await create_timer(0.01).timeout
	# The runner's foreground handshake can deliver a real focus loss mid-walk, which the
	# production rule cancels; the player would simply click again, so the test does too.
	if game.page == "region":
		check(game.session.feedback.contains("先停在这里"),"R4 focus loss stops the walk with visible feedback")
		await click(game.buttons.object_FL13.get_global_rect().get_center())
		while game.busy: await create_timer(0.01).timeout
	check(game.page == "challenge" and game.session.profile.active_run.level_id == "FL13","R4 proximity opens actual object challenge")
	var source: Array = game.session.profile.active_run.source_position
	check(game.Layout.foot(game.region,source[0]).distance_to(game.world.hero_position) < 1,"R4 entered source position persisted")
	game.time_scale = 0.02; await button("region_back")
	check(game.page == "region" and game.world.hero_position == game.Layout.foot(game.region,source[0]),"R4 exit returns to source position")
	var before = game.session.profile.duplicate(true); var clock_before = game.world.npc.clock
	await create_timer(0.7).timeout
	check(game.world.npc.visible and game.world.npc.clock > clock_before+0.5 and game.session.profile == before,"R4 NPC daily animation does not write game state")
	await button("npc"); check("treetop/FL01" in game.session.profile.world.region_dialogues,"R4 approach and talk records valid NPC story state")
	await capture("region-npc-treetop")
	await button("object_FL13")
	for i in range(3): await button("hint")
	var optional = game.session.profile.active_run.duplicate(true)
	await button("camp"); await button("region_heart"); await button("object_FL02")
	check(game.session.profile.active_run.level_id == "FL02" and game.session.profile.suspended_runs.FL13 == optional,"R1 real optional-to-main transition preserves board and help")
	for i in range(3): await button("hint")
	var first_hint = game.session.feedback
	await button("pile_1"); await button("pile_0"); await button("hint")
	check(game.session.feedback != first_hint,"R2 real repeated hint follows changed board")
	for i in range(2): await button("pile_2"); await button("pile_0")
	await button("hint"); var settled_hint: String = game.session.feedback
	check(settled_hint.contains("门环"),"R2 hint recognizes the board is ready to ring")
	await button("try")
	check(game.session.profile.active_run.outcome == "complete","R2 matching echo settles FL02")
	await button("journal"); check(labels_contain(settled_hint),"R2 journal shows actual current-state guidance"); await button("back")
	for i in range(3,7): check(Scenarios.play(game.session,"FL%02d"%i),"mill prerequisite fixture FL%02d"%i)
	await enter("FL07","mill")
	await button("number_card_3"); await button("number_card_1"); await button("operator_1")
	await button("number_card_1"); await button("number_card_2"); await button("operator_2")
	await button("number_card_1"); await button("number_card_0"); await button("operator_1")
	check(game.session.profile.active_run.outcome == "complete","FL07 real 24-point card arithmetic completes")
	check(Scenarios.play(game.session,"FL08"),"post recruitment fixture")
	Scenarios.send(game.session,{"kind":"party","members":["acheng","feather"]})
	await enter("FL08","post")
	# R5 still applies: the audit board keeps a route-drawing panel for the missing card,
	# and the 路签 tool tags the route currently drawn on it.
	var listed: Array = []
	for card in game.session.profile.active_run.state.filing: listed.append(card.path)
	var missing_path = ""
	for candidate in preload("res://scripts/mechanisms/route_rules.gd").all_paths(game.session.catalog.levels.FL08.params):
		if candidate not in listed: missing_path = candidate
	for direction in missing_path: await button("route_right" if direction == "R" else "route_up")
	await button("tools"); await button("route_tag_0"); check(game.buttons.route_tag_0.text.begins_with("✓"),"R5 tool shows current chosen tag")
	await button("back"); check(game.ui.get_node("route_canvas").tag == 0,"R5 chosen tag appears on drawn route")
	await button("audit_add"); check(labels_contain("补进"),"R5 supplying the missing route reports its bag")
	await capture("route-tag-record")
	var path = game.save_path; game.queue_free(); await create_timer(0.15).timeout; await load_game(path); await button("resume")
	check(game.session.profile.active_run.state.filing.size() == 10,"R5 restored filing keeps the supplied route")
	var frozen_party: Array = game.session.profile.active_run.party.duplicate()
	await button("camp"); await button("party"); await button("party_acheng"); await button("camp"); await button("resume")
	check(game.world.party == frozen_party and game.session.profile.roster.party == ["feather"],"R7 ordinary world uses frozen party after camp change")
	await button("journal"); check(labels_contain("我的路签"),"R5 restored tag can be reviewed in journal")
	game.queue_free(); await create_timer(0.15).timeout
	var session = preload("res://scripts/core/game_session.gd").new()
	path = "/tmp/pixel-forest-transfer-ui-"+str(Time.get_ticks_usec())+"/save.json"; session.open(path)
	for i in range(1,13): Scenarios.play(session,"FL%02d"%i)
	await load_game(path)
	check(not game.buttons.has("recommendations") and game.page == "camp","R6 camp no longer offers exercise recommendations")
	check(not Selector.support_for(game.session.profile,game.session.catalog.levels.FL13,game.session.catalog).show_scaffold,"R6 scaffold stays disabled for assisted history")
	game.queue_free(); await create_timer(0.2).timeout
	# R8: exploration entry by walking up and pressing E, plus the completion banner.
	path = "/tmp/pixel-forest-explore-ui-"+str(Time.get_ticks_usec())+"/save.json"
	var explorer = preload("res://scripts/core/game_session.gd").new(); explorer.open(path)
	Scenarios.play(explorer,"FL01")
	await load_game(path)
	check(not game.buttons.has("level_FL02"),"R8 region offers no list-style level sign")
	game.show_region("heart"); game.time_scale = 1.0; await process_frame
	check(game.buttons.has("object_FL02"),"R8 region object hotspot exists")
	game.world.hero_position = Vector2(300,520); game.world.destination = game.world.hero_position
	await process_frame
	await key(KEY_E)
	check(game.busy and game.walking,"R8 pressing E walks the hero to the nearby object")
	while game.busy: await create_timer(0.01).timeout
	check(game.page == "challenge" and game.session.profile.active_run.level_id == "FL02","R8 nearby object opens its challenge")
	check(game.buttons.has("leave") and game.buttons.leave.text.contains("离开"),"R8 challenge always shows a leave control")
	for source_index in [1,2,2]: await button("pile_"+str(source_index)); await button("pile_0")
	await button("try")
	check(game.session.profile.active_run.outcome == "complete" and game.overlay.get_child_count() > 0,"R8 completion banner overlays the restored mechanism")
	check(labels_contain("机关恢复了") and (game.buttons.has("to_next") or game.buttons.has("to_region_alt")),"R8 banner names the restored mechanism and offers where to go next")
	await capture("exploration-and-completion")
	game.queue_free(); await create_timer(0.2).timeout
	print("FOREST REVIEW REPAIRS UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

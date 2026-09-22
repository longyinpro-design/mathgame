extends SceneTree
const Forest = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Board = preload("res://scripts/ui/twenty_four_board.gd")
var game: Control
var checks = 0
var failures = 0
var redraws = 0

func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)

func clocks(node: Node, values: Dictionary = {}) -> Dictionary:
	for property in node.get_property_list():
		if property.name in ["time","clock","elapsed","remaining"]: values[str(node.get_path())+":"+property.name] = node.get(property.name)
	for child in node.get_children(): clocks(child,values)
	return values

func hold() -> void:
	await create_timer(0.12).timeout

func click(id: String) -> void:
	var control: Control = game.buttons[id]
	var point = control.get_global_rect().get_center()*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
	await process_frame

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("presentation watchdog"); quit(1))
	game = Forest.instantiate(); game.save_path = "/tmp/pixel-presentation-"+str(Time.get_ticks_usec())+".json"; root.add_child(game)
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	await hold()
	var hidden = clocks(game.battle_world); var console_clock: float = game.twenty_console.clock
	await hold()
	check(hidden == clocks(game.battle_world) and game.twenty_console.clock == console_clock,"hidden battle subtree and console freeze")
	game.story_stage.paused = true
	var frozen = clocks(game.story_stage); var stable = game.session.profile.duplicate(true)
	await hold()
	check(frozen == clocks(game.story_stage),"pause freezes every story clock including nested actors")
	game.story_stage.skip(); await process_frame
	check(game.story_stage.done and game.session.profile == stable,"skip while paused installs final pose without advancing story or rewards")
	game.story_stage.paused = false
	await hold()
	check(frozen != clocks(game.story_stage),"story resumes without rebuilding its actors")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	frozen = clocks(game)
	await hold()
	check(frozen == clocks(game),"focus loss freezes all forest presentation branches")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await hold()
	check(frozen != clocks(game),"native focus notification restores processing")
	game.story_enabled = false
	check(Scenarios.play(game.session,"FL01"),"prepare transfer prerequisite")
	check(Scenarios.send(game.session,{"kind":"start","level_id":"FL02"}),"start transfer")
	game.page = "challenge"; game.region = "heart"; game.refresh()
	await hold(); frozen = clocks(game.story_stage)
	game.transfer_stage.draw.connect(func(): redraws += 1)
	await hold(); RenderingServer.force_draw(false); redraws = 0
	await hold(); RenderingServer.force_draw(false)
	check(redraws == 0,"static transfer keeps cached draw commands")
	check(frozen == clocks(game.story_stage),"leaving story freezes the entire old branch")
	var pile: Button = game.buttons.pile_0; var stage: Node2D = game.transfer_stage
	var revision = game.session.profile.revision
	await click("pile_0")
	check(game.selected == 0 and stage.selected == 0 and game.buttons.pile_0 == pile,"real click selects in place")
	await click("pile_0")
	check(game.selected == -1 and stage.selected == -1 and game.buttons.pile_0 == pile,"real click deselects in place")
	check(game.session.profile.revision == revision,"selection does not save or change the puzzle")
	redraws = 0; stage.flight = 0.5; await hold(); RenderingServer.force_draw(false)
	check(redraws > 0,"flight setter invalidates drawing")
	redraws = 0; stage.flight = -1; await hold(); RenderingServer.force_draw(false)
	check(redraws > 0,"flight completion clears its last visible frame")
	var tween = game.create_tween(); tween.tween_property(stage,"flight",1.0,0.5)
	await hold(); game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var flight: float = stage.flight
	await hold(); check(stage.flight == flight,"focus loss freezes host-bound flight tween")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await tween.finished
	check(stage.flight == 1.0 and game.session.profile.revision == revision,"focus recovery completes tween without duplicating a command")
	stage.flight = -1
	for id in ["FL02","FL03","FL04","FL05","FL06"]: check(Scenarios.play(game.session,id),"prepare "+id)
	check(Scenarios.send(game.session,{"kind":"start","level_id":"FL07"}),"start 24-point board")
	game.region = "mill"; game.refresh(); await hold()
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = size; await process_frame
		var card: Button = game.buttons.number_card_0
		await click("number_card_0"); await click("number_card_1")
		check(game.twenty_selection == [0,1] and game.buttons.number_card_0 == card,"cards retain identity at "+str(size))
		check(not game.buttons.operator_1.disabled,"two selected cards enable operations")
		await click("swap_operands")
		check(game.twenty_selection == [1,0] and card.position == Vector2(733,408),"operand swap updates real positions")
		await click("number_card_0"); await click("number_card_1")
		check(game.twenty_selection.is_empty() and game.buttons.operator_1.disabled,"deselect restores slots and disables operation")
	game.twenty_console.draw.connect(func(): redraws += 1)
	await hold(); redraws = 0; await hold(); RenderingServer.force_draw(false)
	check(redraws == 0,"unchanged unfinished console does not rebuild drawing")
	for id in ["FL07","FL08","FL09"]: check(Scenarios.play(game.session,id),"prepare route "+id)
	check(Scenarios.send(game.session,{"kind":"start","level_id":"FL10"}),"start simultaneous routes")
	game.region = "post"; game.refresh()
	game.animate_walk_pair({"a":"RRRUU","b":"URRUR"})
	await hold()
	var route = game.ui.get_node("route_canvas")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var route_time: float = route.walk_t; revision = game.session.profile.revision
	await create_timer(1.3).timeout
	check(game.busy and route.walk_t == route_time,"two letters stay mid-route throughout focus loss")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	while game.busy: await process_frame
	check(game.session.profile.revision == revision,"two-letter resume finishes without another command")
	check(Scenarios.play(game.session,"FL10"),"unlock route shadow")
	check(Scenarios.send(game.session,{"kind":"party","members":["feather"]}),"choose shadow companion for next run")
	check(Scenarios.send(game.session,{"kind":"start","level_id":"FL08"}),"start shadow route")
	for direction in "RRRUU": check(Scenarios.rule(game.session,{"kind":"step","direction":direction}),"prepare shadow step")
	game.refresh(); game.play_route_shadow(); await hold()
	route = game.ui.get_node("route_canvas")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var shadow_path: String = route.path; revision = game.session.profile.revision
	await create_timer(1.3).timeout
	check(game.busy and route.path == shadow_path,"shadow path freezes beyond the full unfocused animation duration")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	while game.busy: await process_frame
	check(game.session.profile.revision == revision,"shadow resumes without repeating the tool command")
	# Use the actual seven-object FL11 manifest: the seventh observation tag must
	# follow both its basket and the unloading offset rather than disappearing.
	var cargo = preload("res://scripts/cargo/world.gd").new()
	cargo.state = preload("res://scripts/mechanisms/cargo_rules.gd").fresh(game.session.catalog.levels.FL11.params)
	cargo.state.places[6] = 1; root.add_child(cargo)
	var marks = preload("res://scripts/ui/cargo_annotations.gd").new(); marks.world = cargo; marks.marks = [6]; root.add_child(marks)
	await hold(); var old_positions = marks.positions.duplicate()
	check(old_positions.size() == 1,"seventh cargo item retains its observation tag")
	cargo.lift = 0.5; cargo.offsets[6] = Vector2(9,17); await hold()
	check(marks.positions != old_positions and marks.positions[0] == cargo.item_position(6)+Vector2(9,17)-Vector2(0,85),"tag follows lift and unloading offset")
	marks.marks.clear(); await hold(); check(marks.positions.is_empty(),"in-place mark removal clears drawing")
	marks.queue_free(); cargo.queue_free()
	for player in game.sound.get_children():
		if player is AudioStreamPlayer:
			for connection in player.finished.get_connections(): player.finished.disconnect(connection.callable)
			player.stop(); player.stream = null
	await create_timer(0.15).timeout
	game.queue_free(); await process_frame; await process_frame
	print("FOREST PRESENTATION ",checks-failures,"/",checks," PASS")
	quit(1 if failures else 0)

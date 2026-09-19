extends SceneTree
const SCENE = preload("res://game/forest_release.tscn")
var game: Control
var checks = 0
var failures = 0
var capture_dir = "res://docs/playtest/forest-release"
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	root.focus_exited.connect(func():
		if is_instance_valid(game): print("WINDOW_FOCUS_EXIT page=",game.page," selected=",game.selected," walking=",game.walking," at=",Time.get_ticks_msec()))
	root.focus_entered.connect(func(): print("WINDOW_FOCUS_ENTER at=",Time.get_ticks_msec()))
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS ",label)
	else: failures += 1; push_error(label)
func click(point: Vector2) -> void:
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; root.push_input(event)
	await process_frame
func button(id: String) -> void:
	check(game.buttons.has(id),"button exists "+id)
	if game.buttons.has(id): await click(game.buttons[id].get_global_rect().get_center())
	while game.busy: await create_timer(0.005).timeout
func key(code: Key) -> void:
	if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
	for pressed in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = pressed; root.push_input(event)
	await process_frame
func capture(name: String) -> void:
	await create_timer(0.1).timeout; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(capture_dir+"/"+name+".png")
func move_item(item: int, target: int) -> void:
	await click(game.cargo_world.item_position(item)-Vector2(0,23))
	if game.selected != item: print("PICK_DIAGNOSTIC focus=",root.has_focus()," selected=",game.selected," page=",game.page," busy=",game.busy)
	check(game.selected == item,"cargo actual selection "+str(item))
	await click(game.cargo_world.zone_rect(target).get_center()+Vector2(0,37))
	check(game.session.profile.active_run.state.places[item] == target,"cargo actual placement "+str(item))
func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("P2 UI watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	game = SCENE.instantiate(); game.story_enabled = false; game.save_path = "/tmp/pixel-forest-ui-"+str(Time.get_ticks_usec())+"/save.json"; game.time_scale = 0.05; root.add_child(game)
	await create_timer(0.25).timeout
	check(game.page == "camp" and not game.modal,"new official camp")
	await capture("camp")
	await button("region_treetop"); await button("object_FL01")
	check(game.page == "challenge","FL01 real entrance")
	await capture("fl01-start")
	await move_item(0,1); await move_item(1,1); await move_item(2,1)
	await move_item(3,2); await move_item(4,2); await move_item(5,2)
	await button("travel")
	await create_timer(0.12).timeout
	check(game.session.profile.active_run.outcome == "complete" and game.session.profile.progress.journey_exp == 20,"actual input FL01 settles once")
	await button("camp"); await button("region_heart"); await button("object_FL02")
	await capture("fl02-start")
	for source in [1,2,2]: await button("pile_"+str(source)); await button("pile_0")
	check(game.session.profile.active_run.outcome == "active" and game.session.profile.active_run.state.initial == [11,7,6],"FL02 board holds 11/7/6 before running")
	await button("try")
	check(game.session.profile.active_run.outcome == "complete" and "mossling" in game.session.profile.roster.owned and game.session.profile.active_run.state.trace == [[11,7,6],[4,14,6],[4,8,12],[8,8,8]],"matching echo settles FL02 and recruits mossling")
	await capture("fl02-trace")
	await capture("fl02-complete")
	await button("camp"); await button("party"); await capture("party")
	await key(KEY_ESCAPE)
	await button("journal"); await capture("journal")
	root.size = Vector2i(960,540); await create_timer(0.15).timeout; await capture("small-journal")
	await key(KEY_ESCAPE)
	root.size = Vector2i(1280,720); await create_timer(0.15).timeout
	await button("settings"); await capture("settings")
	var slider = game.ui.get_node("volume"); slider.grab_focus(); var old_volume = slider.value; await key(KEY_RIGHT)
	check(slider.value > old_volume and is_equal_approx(slider.value,game.session.profile.settings.volume),"settings keyboard volume persists")
	game.queue_free(); await create_timer(0.2).timeout
	print("FOREST P2 UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

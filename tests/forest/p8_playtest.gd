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
func overlay_click(id: String) -> void:
	if not game.overlay.has_node(id): check(false,"missing overlay control "+id); return
	var control = game.overlay.get_node(id)
	await click(control.get_global_rect().get_center())
func run() -> void:
	create_timer(80).timeout.connect(func(): push_error("P8 UI watchdog"); quit(1))
	game = SCENE.instantiate(); game.story_enabled = false; game.save_path = "/tmp/pixel-forest-p8-ui-"+str(Time.get_ticks_usec())+"/save.json"; game.time_scale = 0.02; root.add_child(game); await create_timer(0.25).timeout
	for id in ["FL01","FL02"]: check(Scenarios.play(game.session,id),"prior fixture "+id)
	await enter("FL13","treetop"); await button("tools")
	for item in [0,1,2]: await button("group_item_"+str(item))
	var before = game.session.profile.duplicate(true)
	await button("group_target_1"); check(game.session.profile == before,"real group tool rejects whole oversized group")
	await button("group_item_2"); await button("group_target_1")
	check(game.session.profile.active_run.state.places.slice(0,2) == [1,1],"real group tool moves two items")
	await button("mark_0"); await button("back"); check(game.page == "challenge","tool panel returns to challenge")
	await capture("cargo-with-mark")
	await button("undo"); check(game.session.profile.active_run.state.places.slice(0,2) == [0,0],"actual undo reverses one grouped move")
	await button("reset"); check(game.modal,"reset confirmation visible")
	game.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var locked = true
	for control in game.buttons.values(): locked = locked and control.disabled
	check(locked,"focus loss keeps background controls disabled")
	game.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await key(KEY_ESCAPE); check(not game.modal,"Escape cancels reset without a background action")
	game.session.repository.fail_at = "replace"
	await key(KEY_1); await key(KEY_LEFT)
	check(game.modal and not game.session.pending.is_empty() and game.session.profile.active_run.state.places[0] == 0,"failed actual move keeps old board behind save modal")
	game.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await click(Vector2(1027,49)); check(game.page == "challenge","save modal blocks background camp")
	game.session.repository.fail_at = ""; await overlay_click("retry")
	check(not game.modal and game.session.profile.active_run.state.places[0] == 1,"actual retry installs preserved candidate")
	root.size = Vector2i(960,540); await create_timer(0.15).timeout
	await click((game.cargo_world.item_position(1)-Vector2(0,23))*0.75)
	check(game.selected == 1,"native960x540 cargo pick uses correct coordinates")
	await key(KEY_ESCAPE); await capture("small-cargo")
	root.size = Vector2i(1280,720); await create_timer(0.15).timeout
	await button("camp"); await button("party"); await button("party_acheng")
	check(game.session.profile.roster.party == ["mossling"] and game.session.profile.active_run.party == ["acheng","mossling"],"real future-party change preserves active party")
	await button("journal"); await button("settings"); await key(KEY_ESCAPE)
	check(game.page == "journal","nested settings returns to journal")
	await key(KEY_ESCAPE); check(game.page == "party","nested journal returns to partner page")
	await button("camp"); await button("resume")
	check(game.page == "challenge" and game.region == "treetop","resume restores challenge source region")
	Scenarios.send(game.session,{"kind":"reset","confirmed":true})
	check(Scenarios.play(game.session,"FL13"),"complete side fixture before chapter tour")
	for i in range(3,19):
		if i == 13: continue
		check(Scenarios.play(game.session,"FL%02d"%i),"chapter fixture FL%02d"%i)
	for building in ["roof","workbench","garden"]: check(Scenarios.send(game.session,{"kind":"build","building":building}),"camp fixture "+building)
	Scenarios.send(game.session,{"kind":"camp"}); Scenarios.send(game.session,{"kind":"grow"})
	game.page = "camp"; game.refresh(); await capture("complete-camp")
	await click(Vector2(858,573)); var initial_position = game.world.hero_position; await create_timer(0.25).timeout
	check(game.world.hero_position.distance_to(initial_position) > 20,"real ground click moves explorer along walkway")
	await button("region_village"); await capture("village-restored")
	await button("object_FL04"); check(game.page == "visit","resolved quest opens world revisit before practice")
	await button("practice"); check(game.page == "challenge" and game.session.profile.active_run.level_id == "FL04","explicit practice creates separate run")
	await button("camp"); await button("region_mill"); await capture("mill-restored")
	await button("camp"); await button("party"); await capture("three-partners")
	var corrupted_path = game.save_path+".bad"; game.queue_free(); await create_timer(0.2).timeout
	var file = FileAccess.open(corrupted_path,FileAccess.WRITE); file.store_string("{damaged"); file.close()
	game = SCENE.instantiate(); game.story_enabled = false; game.save_path = corrupted_path; root.add_child(game); await create_timer(0.2).timeout
	check(game.modal and game.session.repository.protected,"damaged record shows protection UI")
	await overlay_click("new_profile"); await key(KEY_ESCAPE); check(game.modal and game.session.repository.protected and not game.confirmation_open and game.overlay.has_node("new_profile"),"Escape returns from new-game confirmation to protected screen")
	await overlay_click("new_profile"); await overlay_click("confirm")
	check(not game.modal and game.page == "camp" and game.session.profile.progress.completed_levels.is_empty(),"explicit new journey preserves bad source and starts fresh")
	await capture("new-after-protected")
	game.queue_free(); await create_timer(0.25).timeout
	print("FOREST P8 UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

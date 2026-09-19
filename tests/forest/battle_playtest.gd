extends SceneTree
const SCENE = preload("res://game/forest_release.tscn")
const SeededSession = preload("res://tests/forest/seeded_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
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
	while game.busy: await create_timer(0.005).timeout
	# The runner restores the foreground mid-walk, which cancels the walk by design;
	# a player would simply click the object again, so the test does too.
	if game.page == "region":
		if not game.session.feedback.contains("先停在这里"): push_error("expected visible walk-cancel feedback")
		await button("object_"+id)
		while game.busy: await create_timer(0.005).timeout
	if game.page != "challenge": print("ENTRY_DIAGNOSTIC focus=",root.has_focus()," page=",game.page," feedback=",game.session.feedback)
	check(game.page == "challenge" and game.session.profile.active_run.level_id == id,"actual entrance "+id)
func settle_animation() -> void:
	var deadline = Time.get_ticks_msec()+4000
	while game.busy and Time.get_ticks_msec() < deadline: await create_timer(0.005).timeout
	check(not game.busy,"battle presentation settles")
func transfer(card: int, source: int, target: int) -> void:
	await button("card_"+str(card)); await button("core_"+str(source)); await button("core_"+str(target)); await settle_animation()
func run() -> void:
	create_timer(65).timeout.connect(func(): push_error("battle sample watchdog"); quit(1))
	game = SCENE.instantiate(); game.story_enabled = false; game.session = SeededSession.new(); game.save_path = "/tmp/pixel-forest-boss-ui-"+str(Time.get_ticks_usec())+"/save.json"; game.time_scale = 0.4; root.add_child(game); await create_timer(0.25).timeout
	for i in range(1,13): check(Scenarios.play(game.session,"FL%02d"%i),"prior fixture FL%02d"%i)
	await enter("FL17","heart"); await capture("fl17-start")
	await button("card_1"); await button("core_2"); await button("core_1")
	check(game.busy and game.session.profile.active_run.state.energy == [2,10,9],"enemy swap committed before animation")
	var restored = SeededSession.new(); check(restored.open(game.save_path) and restored.profile == game.session.profile,"mid-animation restore keeps swapped stable turn")
	await settle_animation(); await capture("fl17-after-swap")
	await transfer(2,2,0); check(game.session.profile.active_run.state.energy == [4,10,7],"actual second card adapts to swapped response")
	await transfer(3,1,0); check(game.session.profile.active_run.state.battle_phase == "ready" and game.session.profile.active_run.outcome == "active","balanced cores await explicit counterattack")
	await button("finish"); await settle_animation(); check(game.session.profile.active_run.outcome == "complete","actual counterattack settles FL17")
	await capture("fl17-complete")
	await enter("FL18","heart"); await capture("fl18-start")
	await button("probe_6"); await settle_animation()
	check(game.session.profile.active_run.state.active_observations == [[6,16]] and game.session.profile.active_run.state.seed_balance == 9,"probe6 echo16 and paid budget")
	await capture("fl18-echo16")
	await button("probe_2"); await settle_animation()
	check(game.session.profile.active_run.state.seed_balance == 7 and game.buttons.finish_8.disabled,"unique A with insufficient finisher reserve")
	await button("undo"); await button("undo")
	var run: Dictionary = game.session.profile.active_run
	check(run.state.seed_balance == 15 and run.state.probe_count == 0 and run.state.active_observations.is_empty(),"undo returns budget and removes both effective observations")
	check(run.observation_history == [[6,16],[2,8]] and run.replanned_after_observation and run.highest_hint == 0 and run.state.secret_form_id == "A","history retained separately without changing secret or hint tier")
	await capture("fl18-replan")
	await button("probe_5"); await settle_animation(); await button("finish_8"); await settle_animation()
	check(game.session.profile.active_run.outcome == "complete" and game.session.profile.progress.journey_exp == 300,"new valid observation plus finisher completes main story")
	var last: Dictionary = game.session.profile.learning.observations.back()
	check(last.replanned_after_observation and last.effective_observations == [[5,14]] and last.observation_history.size() == 3,"learning distinguishes effective evidence and historical replanning")
	await capture("fl18-complete")
	await button("camp"); await capture("main-story-homecoming")
	game.queue_free(); await create_timer(0.25).timeout
	print("FOREST BATTLE SAMPLE ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

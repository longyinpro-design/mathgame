extends SceneTree
const Rules = preload("res://scripts/encounter/rules.gd")
const Store = preload("res://scripts/encounter/store.gd")
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, title: String) -> void:
	checks += 1
	if value: print("PASS ",title)
	else: failures += 1; push_error(title)
func mouse(point: Vector2, pressed: bool) -> void:
	var e = InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.position = point; e.pressed = pressed; root.push_input(e)
func click(point: Vector2) -> void:
	mouse(point,true); mouse(point,false)
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.12).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("/tmp/encounter-v3-"+name+".png")
func wait_ready(game: Node) -> void:
	for i in range(200):
		if game.phase == "ready" and not game.busy: return
		await create_timer(0.01).timeout
func run() -> void:
	var path = "/tmp/encounter-v3-test-%d.json" % OS.get_process_id()
	var game = load("res://game/encounter.tscn").instantiate(); game.store.path = path; game.time_scale = 0.025
	root.add_child(game); await process_frame
	check(game.phase == "approach","sample begins in a physical scene")
	await capture("approach")
	click(Vector2(312,488)); await wait_ready(game)
	check(game.phase == "ready" and game.state.introduced,"ground click approaches and awakens guardian")
	check(game.scene.guardian_awake == 1 and game.scene.shield_alpha == 1,"guardian and independent shields animate in")
	check(game.sound.played.has("awaken") and game.sound.played.has("fox"),"arrival audio cues fired")
	check(game.state.left == 7 and Rules.result(game.state.left).right == 7,"starts with conserved 14 crystals")
	await capture("ready")
	var origin = game.scene.crystal_position(0,0)
	mouse(origin,true); await process_frame
	check(game.dragging and game.scene.drag_ghost.visible,"mouse press picks up visible crystal")
	mouse(Vector2(1150,655),false); await process_frame
	check(not game.dragging and game.state.left == 7,"dropping on toolbar cancels without losing energy")
	mouse(origin,true); game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.dragging and game.state.left == 7,"focus loss cancels drag without mutation")
	mouse(origin,true); mouse(Vector2(1050,350),false); await wait_ready(game)
	check(game.state.left == 6,"actual drag transfers one crystal to opposite shield")
	game.undo(); check(game.state.left == 7,"undo restores distribution")
	game.cast_spell(); await create_timer(0.01).timeout
	game.reset_distribution(); game.transfer(0,1); game.hint()
	check(game.busy and game.state.left == 7 and game.state.hint == 0,"cast locks input and state changes")
	check(game.cast_button.disabled and game.cast_button.text == "正在施法…","busy action label matches the current animation")
	await wait_ready(game)
	check(not game.state.won and game.state.left == 7 and game.state.attempts == 1,"failed cast preserves editable distribution")
	check(game.scene.shield_tilt == 0 and game.scene.zoom == 1,"failure animation restores camera and shields")
	check(game.difference_label.text.contains("0"),"failure reports actual difference")
	check(game.sound.played.has("charge") and game.sound.played.has("cast") and game.sound.played.has("unbalanced"),"cast and failure audio cues fired")
	await capture("failure")
	click(origin); click(Vector2(1050,350)); await wait_ready(game)
	check(game.state.left == 6,"click-pick and click-shield alternative works")
	game.hint(); game.undo()
	check(game.state.left == 7 and game.state.hint == 1,"undo retains assistance record")
	await game.transfer(0,1); await game.transfer(0,1)
	check(Rules.result(game.state.left).success,"direct operations produce unique 5/9 solution")
	var store = Store.new(); store.path = path; var read = store.read_save()
	check(read.left == 5 and not read.won,"mid-encounter distribution persists")
	await game.cast_spell()
	check(game.phase == "reward" and game.state.won and not game.state.reward,"success exposes claimable reward")
	check(game.scene.portal == 1 and game.scene.shield_alpha == 0,"success changes environment and removes shields")
	await capture("reward")
	game.store.path = path+"/missing/file.json"
	await game.claim_reward(); game.claim_reward()
	check(game.phase == "done" and game.retry_save_button.visible,"final reward save failure exposes a usable retry control")
	game.store.path = path
	click(Vector2(1160,131)); await process_frame
	check(game.save_warning.text.is_empty() and store.read_save().reward,"UI retry persists final reward without replaying encounter")
	check(game.state.reward and game.demo_events.count("reward") == 1,"reward claim is idempotent")
	check(game.sound.played.has("unlock") and game.sound.played.has("reward"),"unlock and reward audio cues fired")
	await capture("done")
	var resumed = load("res://game/encounter.tscn").instantiate(); resumed.store.path = path; root.add_child(resumed)
	check(resumed.phase == "done" and resumed.state.reward,"fresh scene restores claimed reward without regrant")
	resumed.queue_free(); await process_frame
	game.sound.set_volume(0); check(game.sound.music.volume_db <= -79,"zero volume mutes music")
	game.sound.set_volume(0.7); game.toggle_audio(); check(game.sound.music.volume_db <= -79,"mute toggle silences ambient track")
	game.toggle_audio(); check(game.sound.music.volume_db > -79,"unmute restores configured level")
	var good = game.state.duplicate(true)
	game.store.path = path+"/missing/file.json"; game.save()
	check(not game.save_warning.text.is_empty(),"save failure immediately visible")
	game.store.path = path; game.save(); check(game.save_warning.text.is_empty(),"successful retry clears save warning")
	var bad = good.duplicate(); bad.left = 7
	check(not Rules.valid(bad),"impossible completed distribution rejected")
	bad = good.duplicate(); bad.left = 5.5
	check(not Rules.valid(bad),"fractional crystal count rejected")
	var f = FileAccess.open(path,FileAccess.WRITE); f.store_string("broken"); f.close(); store.read_save()
	check(store.protected and not store.write_save(good) and FileAccess.get_file_as_string(path) == "broken","corrupt save never overwritten")
	var solutions = []
	for n in range(15):
		if Rules.result(n).success: solutions.append(n)
	check(solutions == [5],"exhaustive 15-state oracle has exactly one solution")
	DirAccess.remove_absolute(path)
	game.queue_free(); await process_frame
	print("RESULT ",checks," checks; failures=",failures)
	quit(1 if failures else 0)

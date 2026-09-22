extends SceneTree
# Native, visible, non-focus-stealing rendering. Never opens a player profile.
const Forest = preload("res://game/forest_release.tscn")
const Market = preload("res://game/market_mk18.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var game: Control
var output = ""
var rows: Array = []
var draws: Dictionary = {}
var capture_draws = false
var save_root = "/tmp/pixel-performance-"+str(Time.get_ticks_usec())

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	Engine.max_fps = 60
	output = OS.get_environment("PIXEL_PERFORMANCE_OUTPUT")
	call_deferred("run")

func watch(node: Node) -> void:
	if node is CanvasItem:
		var key = str(node.get_path())
		node.draw.connect(func():
			if capture_draws: draws[key] = draws.get(key,0)+1)
	for child in node.get_children(): watch(child)

func percentile(values: Array, fraction: float) -> float:
	var ordered = values.duplicate(); ordered.sort()
	return ordered[mini(ordered.size()-1,int(ceil(ordered.size()*fraction))-1)]

func activity_clock(label: String) -> float:
	if label.begins_with("forest_story"): return game.story_stage.cargo.time if game.story_stage.cargo_scene else game.story_stage.backdrop.time
	if label.begins_with("forest_cargo"): return game.cargo_world.time
	if label.begins_with("forest_battle"): return game.battle_world.time
	if label.begins_with("forest_"): return game.world.time
	return game.world.clock

func sample(label: String, selection: bool = false, motion: String = "") -> void:
	# Model an active game without taking the real desktop focus.
	game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for i in range(120): await process_frame
	# Startup focus events can arrive during warm-up; bind the measured interval
	# to the requested active/paused state after those events have settled.
	game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var activity_before = activity_clock(label)
	draws = {}; watch(game); capture_draws = true
	var frames: Array = []; var process_ms: Array = []; var calls: Array = []; var selection_us: Array = []
	var started = Time.get_ticks_usec()
	for i in range(180):
		var before = Time.get_ticks_usec()
		if motion == "cargo": game.cargo_world.lift = (sin(i*TAU/180.0)+1)/2.0
		if motion == "transfer": game.transfer_stage.flight = (i%60)/60.0
		if selection:
			var select_start = Time.get_ticks_usec()
			game.select_pile(0)
			selection_us.append(Time.get_ticks_usec()-select_start)
		await process_frame
		frames.append((Time.get_ticks_usec()-before)/1000.0)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	capture_draws = false
	var row = {"case":label,"samples":frames.size(),"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,
		"frame_p50_ms":percentile(frames,0.5),"frame_p95_ms":percentile(frames,0.95),"frame_max_ms":frames.max(),
		"process_p50_ms":percentile(process_ms,0.5),"process_p95_ms":percentile(process_ms,0.95),
		"draw_calls_p50":percentile(calls,0.5),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"canvas_redraws":draws}
	if selection: row["selection_p50_us"] = percentile(selection_us,0.5); row["selection_p95_us"] = percentile(selection_us,0.95)
	row["activity_clock_before"] = activity_before
	row["activity_clock_after"] = activity_clock(label)
	if not label.ends_with("paused") and row.activity_clock_after <= activity_before:
		push_error("Active presentation did not advance during "+label); quit(1); return
	rows.append(row)
	print("BENCH ",label," frame p95=",row.frame_p95_ms," process p95=",row.process_p95_ms)
	# Disconnect only this fixture's callbacks; each case measures a fresh interval.
	unwatch(game)
	await capture(label)

func freeze(node: Node, saved: Array) -> void:
	saved.append([node,node.is_processing()]); node.set_process(false)
	for property in node.get_property_list():
		if property.name in ["time","clock"]: node.set(property.name,0.0)
	if node is CanvasItem: node.queue_redraw()
	for child in node.get_children(): freeze(child,saved)

func capture(label: String) -> void:
	var saved: Array = []; freeze(game,saved)
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.get_basename()+"-"+label+".png")
	for entry in saved: entry[0].set_process(entry[1])

func unwatch(node: Node) -> void:
	if node is CanvasItem:
		for connection in node.draw.get_connections():
			if connection.callable.get_object() == self: node.draw.disconnect(connection.callable)
	for child in node.get_children(): unwatch(child)

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("benchmark watchdog"); quit(1))
	if output.is_empty() or DisplayServer.get_name() == "headless": push_error("native benchmark requires output path"); quit(1); return
	DirAccess.make_dir_recursive_absolute(save_root)
	game = Forest.instantiate(); game.save_path = save_root+"/forest.json"; root.add_child(game)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	await process_frame
	game.story_stage.focused = true
	await sample("forest_story")
	game.story_stage.paused = true
	await sample("forest_story_paused")
	game.story_enabled = false
	if not Scenarios.send(game.session,{"kind":"start","level_id":"FL01"}): push_error("start FL01"); quit(1); return
	game.page = "challenge"; game.refresh()
	await sample("forest_cargo_idle")
	await sample("forest_cargo_moving",false,"cargo")
	if not Scenarios.play(game.session,"FL01"): push_error("complete FL01"); quit(1); return
	if not Scenarios.send(game.session,{"kind":"start","level_id":"FL02"}): push_error("start FL02"); quit(1); return
	game.region = "heart"; game.refresh()
	await sample("forest_transfer_idle")
	await sample("forest_transfer_selection",true)
	game.transfer_stage.from_index = 0; game.transfer_stage.to_index = 1
	await sample("forest_transfer_moving",false,"transfer")
	game.transfer_stage.flight = -1
	for id in ["FL02","FL03","FL04","FL05","FL06"]:
		if not Scenarios.play(game.session,id): push_error("fixture "+id); quit(1); return
	if not Scenarios.send(game.session,{"kind":"start","level_id":"FL07"}): push_error("start FL07"); quit(1); return
	game.region = "mill"; game.refresh()
	await sample("forest_console_idle")
	for id in ["FL07","FL08","FL09","FL10","FL11","FL12"]:
		if not Scenarios.play(game.session,id): push_error("fixture "+id); quit(1); return
	if not Scenarios.send(game.session,{"kind":"start","level_id":"FL17"}): push_error("start FL17"); quit(1); return
	game.region = "heart"; game.refresh()
	await sample("forest_battle_idle")
	for player in game.sound.get_children():
		if player is AudioStreamPlayer:
			for connection in player.finished.get_connections(): player.finished.disconnect(connection.callable)
			player.stop(); player.stream = null
	await create_timer(0.15).timeout
	game.queue_free(); await process_frame; await process_frame
	game = Market.instantiate(); game.save_path = save_root+"/market.json"; root.add_child(game)
	await sample("market_mk18_idle")
	game.paused = true
	await sample("market_mk18_paused")
	game.paused = false
	await sample("market_mk18_resumed")
	var report = {"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"window_mode":root.mode,
		"viewport":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"rows":rows,
		"limits":["Local visible native window; no cross-device performance claim.","180 samples per case after 120 warm-up frames at a 60 FPS cap; frame times include vsync/OS scheduling.","TIME_PROCESS is an engine interval monitor, not a per-frame CPU trace.","Draw signals count CanvasItem command rebuilds, not GPU draw calls.","Motion fixtures drive presentation only; functional transaction tests run separately."]}
	var file = FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ")); file.close()
	game.queue_free(); await process_frame; await process_frame
	print("BENCHMARK COMPLETE ",output)
	quit(0)

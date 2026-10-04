extends SceneTree
# Native imagegen integration screenshots, separate from all-level solver/UI suites.
var scene: Control
var errors: Array = []
func _initialize(): call_deferred("run")
func click(id: String):
	if not scene.buttons.has(id): errors.append("missing "+id); return
	var at: Vector2 = root.get_screen_transform()*scene.buttons[id].get_global_rect().get_center()
	var e = InputEventMouseButton.new(); e.position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=true
	Input.parse_input_event(e); await process_frame
	e=InputEventMouseButton.new(); e.position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=false
	Input.parse_input_event(e); await process_frame
func run():
	if DisplayServer.get_name() == "headless":
		push_error("This visual capture requires the native renderer."); quit(1); return
	DirAccess.make_dir_recursive_absolute("res://docs/playtest/late-islands-v1")
	var ids = ["GV01","GV05","GV17","FW01","FW18","SO01","SO17","SO18"]
	if "so17" in OS.get_cmdline_user_args(): ids = ["SO17"]
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size; root.content_scale_size=Vector2i(1280,720)
		for id in ids:
			var family="geometry" if id.begins_with("GV") else "fractions" if id.begins_with("FW") else "observatory"
			scene=load("res://game/%s_%s.tscn"%[family,id.to_lower()]).instantiate()
			scene.save_path="/tmp/imagegen-art-%s-%d-%d.json"%[id,size.x,Time.get_ticks_usec()]
			root.add_child(scene); await process_frame
			for beat in range(scene.definition.intro.size()): await click("next")
			if scene.stage != "puzzle": errors.append(id+" intro input")
			var before = scene.board.duplicate(true)
			await click("pause"); await click("pause")
			if scene.board != before: errors.append(id+" pause mutated board")
			await process_frame; await RenderingServer.frame_post_draw
			var result = root.get_texture().get_image().save_png("res://docs/playtest/late-islands-v1/%s-%d.png"%[id,size.x])
			if result != OK: errors.append(id+" screenshot failed")
			root.remove_child(scene); scene.queue_free(); await process_frame
	for error in errors: push_error(error)
	print("LATE ISLAND CAPTURE: %d native scenes, pause/resume, %d failures"%[ids.size()*2,errors.size()])
	quit(1 if not errors.is_empty() else 0)

extends SceneTree
var failures: Array=[]
var scene: Control
var witnesses: Dictionary
var index=0
var ids=preload("res://scripts/geometry/catalog.gd").ids()
func _initialize():
	witnesses=preload("res://scripts/content/content_catalog.gd").normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/geometry/witnesses.json")))
	call_deferred("run")
func check(ok: bool, text: String):
	if not ok:failures.append(text);push_error(text)
func click(id: String):
	check(scene.buttons.has(id),"missing "+id)
	if not scene.buttons.has(id):return
	var b=scene.buttons[id];var pos=b.get_global_rect().get_center()
	var event=InputEventMouseButton.new();event.position=pos;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	root.push_input(event,true);await process_frame
	event=InputEventMouseButton.new();event.position=pos;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false
	root.push_input(event,true);await process_frame
func capture(name: String):
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/playtest/geometry/"+name+".png")
func run():
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size
		for id in ids:
			var path="/tmp/geometry_ui_%s_%d.json"%[id,size.x]
			for suffix in ["",".bak",".tmp"]:
				if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
			scene=load("res://game/geometry_"+id.to_lower()+".tscn").instantiate();scene.save_path=path;root.add_child(scene)
			await process_frame
			await click("next");await click("next")
			check(scene.stage=="puzzle",id+" entered puzzle")
			if id in ["GV01","GV05","GV07","GV10","GV17","GV18"]:await capture(id+"_start_"+str(size.x))
			for a in witnesses[id]:
				match a.type:
					"cut","seal":
						await click(a.type)
						if a.type=="seal":await capture(id+"_seal_"+str(scene.board.proofs.size())+"_"+str(size.x))
					"toggle":await click("cell_%d_%d"%[a.x,a.y])
					"place":await click("piece_%d"%a.piece);await click("cell_%d_%d"%[a.x,a.y])
					"rotate","flip","lift":await click("piece_%d"%a.piece);await click(a.type)
			check(scene.rules.solved(scene.board),id+" UI solved at "+str(size))
			if id in ["GV01","GV05","GV07","GV10","GV17","GV18"]:await capture(id+"_solved_"+str(size.x))
			await click("submit");check(scene.stage=="outcome",id+" submitted")
			var reloaded=load("res://scripts/archipelago/session.gd").new();check(reloaded.open(path),id+" repository reopened");check(id in reloaded.profile.get("completed",[]),id+" reward saved")
			scene.queue_free();await process_frame
	print("Geometry UI: %d failures; 18 levels × 2 viewport sizes"%failures.size())
	quit(1 if failures.size() else 0)

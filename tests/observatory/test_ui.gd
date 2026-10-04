extends SceneTree
const Catalog=preload("res://scripts/observatory/catalog.gd")
const Session=preload("res://scripts/archipelago/session.gd")
var failures=0
var scene: Control
var screenshots="res://docs/playtest/observatory"
func check(ok: bool, message: String):
	if not ok: failures+=1; push_error(message)
func _initialize(): call_deferred("run")
func click(id: String):
	if not scene.buttons.has(id):check(false,"Missing actual UI control "+id);return
	var button:Button=scene.buttons[id]
	var at=button.get_global_rect().get_center()
	var down=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=at;down.global_position=at
	root.push_input(down,true)
	var up=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=at;up.global_position=at
	root.push_input(up,true)
	await process_frame
func capture(name: String):
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var img=root.get_texture().get_image()
	check(img.save_png(screenshots+"/"+name+".png")==OK,"Screenshot "+name)
func action(a: Dictionary):
	match a.type:
		"place":
			await click("star_%d" % a.piece);await click("grid_%d_%d" % [a.x,a.y])
		"toggle":await click("shutter_%d_%d" % [a.window,a.cell])
		"append":await click("node_%d" % a.node)
		"record":await click("record_route")
		"clear":await click("clear_route")
		"schedule":
			await click("job_%d" % a.job);await click("time_%d_%d" % [a.track,a.start])
		"cable":await click("cable_%d" % a.edge)
		"storm":await click("call_storm")
		"depart":
			await click("job_%d" % a.job);await click("depart_%d" % a.start)
func run():
	var fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/observatory/witnesses.json"))
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size
		for id in Catalog.ids():
			var session=Session.new();session.allow_locked=true
			var path="/tmp/observatory-ui-%s-%d-%d.json" % [id,size.x,Time.get_ticks_usec()]
			check(session.open(path),id+" isolated repository")
			scene=load(Catalog.definition(id).scene).instantiate();scene.session=session
			root.add_child(scene)
			await process_frame;await process_frame
			var guards=0
			while scene.stage=="intro" and guards<5:
				await click("next");guards+=1
			check(scene.stage=="puzzle",id+" intro to puzzle input")
			if id in ["SO01","SO05","SO08","SO11","SO17","SO18"]:await capture("%s-%d-start" % [id,size.x])
			for a in fixtures[id].actions:await action(a)
			check(scene.rules.solved(scene.board),id+" real UI witness completion at "+str(size))
			if id in ["SO01","SO05","SO08","SO11","SO17","SO18"]:await capture("%s-%d-solved" % [id,size.x])
			var reload=Session.new();reload.allow_locked=true
			check(reload.open(path),id+" repository reopen")
			check(reload.profile.runs[id].board==scene.board,id+" actual saved board matches UI")
			await click("submit")
			check(scene.stage=="outcome",id+" real submit reaches outcome")
			check(id in session.profile.completed,id+" actual reward commit")
			print("OBS UI ",id," ",size," verified")
			scene.queue_free();await process_frame
	print("OBSERVATORY UI: ",failures," failures")
	quit(1 if failures else 0)

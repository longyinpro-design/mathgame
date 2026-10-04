extends SceneTree
const Catalog=preload("res://scripts/fractions/catalog.gd")
const Campaign=preload("res://scripts/archipelago/session.gd")
var checks:=0
var scene: Control
func _init(): call_deferred("run")
func require(ok: bool, note: String):
	checks+=1
	if not ok: push_error(note); quit(1)
func click(id: String):
	require(scene.buttons.has(id),"missing button "+id)
	var button: Button=scene.buttons[id]
	var pos:Vector2=root.get_screen_transform() * button.get_global_rect().get_center()
	var event:=InputEventMouseButton.new(); event.position=pos; event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=InputEventMouseButton.new();event.position=pos;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false
	Input.parse_input_event(event)
	await process_frame
func run():
	var solutions:Dictionary=Catalog.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fractions/solutions.json")))
	var size:=1280
	for arg in OS.get_cmdline_user_args():
		if arg=="small":size=960
	root.size=Vector2i(size,size*720/1280)
	root.content_scale_size=Vector2i(1280,720)
	for id in Catalog.ids():
		scene=load(Catalog.definition(id).scene).instantiate()
		scene.save_path="/tmp/fractions-ui-%d-%s-%d/save.json"%[size,id,Time.get_ticks_usec()]
		root.add_child(scene)
		await process_frame
		for beat in range(scene.definition.intro.size()): await click("next")
		require(scene.stage=="puzzle",id+" puzzle")
		await click("hint")
		require(scene.hint_tier==1,id+" hint input")
		await capture(id,size,"start")
		for action in solutions[id]:
			match action.type:
				"split": await click("tile_%d"%action.tile);await click("split_%d"%action.parts)
				"place": await click("tile_%d"%action.tile);await click("bed_%d"%action.owner)
				"shift": await click("pool_%d"%action.source);await click("pool_%d"%action.target)
				"release": await click("release")
				"gate": await click("gate_%d"%action.edge)
				"pulse": await click("pulse")
				"checkpoint":
					await click("checkpoint")
					await capture(id,size,"phase%d"%scene.rules.projection(scene.board).stage)
		require(scene.rules.solved(scene.board),id+" solved with mouse events")
		await click("submit")
		require(scene.stage=="outcome",id+" outcome")
		await capture(id,size,"solved")
		var loaded=Campaign.new();loaded.allow_locked=true
		require(loaded.open(scene.save_path),id+" repository read")
		require(id in loaded.profile.completed,id+" persisted win")
		print(id," UI PASS ",size)
		root.remove_child(scene);scene.queue_free();await process_frame
	print("FRACTIONS UI PASS ",checks)
	quit()

func capture(id: String,size: int,tag: String):
	if DisplayServer.get_name()=="headless" or id not in ["FW01","FW05","FW07","FW13","FW14","FW16","FW17","FW18"]: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/playtest/fractions/%s-%d-%s.png"%[id,size,tag])

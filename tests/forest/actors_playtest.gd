extends SceneTree
const Actor = preload("res://scripts/ui/companion_actor.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
var actors = []
func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")
func run() -> void:
	var canvas = Control.new(); canvas.size = Vector2(1280,720); root.add_child(canvas)
	var actions = ["idle","walk","interact","skill","affected","success"]
	for column in range(6):
		var bg = ColorRect.new(); bg.position = Vector2(column*213,0); bg.size = Vector2(213,720); bg.color = Color("efe6cf") if column%2 == 0 else Color("233d35"); canvas.add_child(bg)
		UIStyle.text(canvas,["待机","移动","互动","能力","受影响","成功"][column],Rect2(column*213+54,17,162,38),20,UIStyle.DARK if column%2 == 0 else UIStyle.INK)
		for row in range(4):
			var id: String = ["hero","acheng","mossling","feather"][row]
			var actor = Actor.new(); actor.identity = id; actor.pixel_scale = 0.40; actor.position = Vector2(column*213+107,175+row*158); canvas.add_child(actor); actor.set_process(false); actor.action = actions[column]; actors.append(actor)
			UIStyle.text(canvas,{"hero":"小岚","acheng":"阿橙","mossling":"苔团","feather":"折羽"}[id],Rect2(column*213+77,185+row*158,128,29),18,UIStyle.DARK if column%2 == 0 else UIStyle.INK)
	for frame in range(3):
		for actor in actors:
			actor.clock = (frame+0.05)/(3.0 if actor.action == "idle" else 7.0); actor.queue_redraw()
		await create_timer(0.12).timeout; RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://docs/playtest/forest-release/actors-frame%d.png"%frame)
	canvas.queue_free(); await create_timer(0.15).timeout
	print("FOREST ACTORS UI 3/3 PASS"); quit()

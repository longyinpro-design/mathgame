extends SceneTree
# Asset assembly reference only: no game rules, state writes or rewards.
const Focus = preload("res://tests/forest/window_focus.gd")
var data: Dictionary
var stage: Node2D
var textures = {}
var entries = {}
var page = 0
var capture_mode = false
var time = 0.0
var beam: Sprite2D
var pans: Array = []
var weights: Array = []
var pivot = Vector2.ZERO
var font = preload("res://assets/fonts/NotoSansSC.ttf")
func _initialize() -> void:
	Focus.configure(root)
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func label_at(value: String, point: Vector2, size: Vector2 = Vector2(1100,36), font_size: int = 20) -> void:
	var label = Label.new(); label.text = value; label.position = point; label.size = size
	label.add_theme_font_override("font",font); label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_outline_color",Color.BLACK); label.add_theme_constant_override("outline_size",5)
	stage.add_child(label)
func sprite(id: String, anchor: Vector2, width: float = -1, factor: float = -1) -> Sprite2D:
	var item: Dictionary = entries[id]
	var node = Sprite2D.new(); node.texture = textures[id]; node.centered = false
	node.offset = -Vector2(item.anchor_px[0],item.anchor_px[1])
	node.position = anchor
	var ratio: float = factor if factor > 0 else (float(item.suggested_width) if width < 0 else width)/node.texture.get_width()
	node.scale = Vector2.ONE*ratio; node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.add_child(node); return node
func point_on(node: Sprite2D, id: String, attachment: String) -> Vector2:
	var item: Dictionary = entries[id]; var pt = item.attachments_px[attachment]
	return node.position+(Vector2(pt[0],pt[1])-Vector2(item.anchor_px[0],item.anchor_px[1])).rotated(node.rotation)*node.scale
func build() -> void:
	if is_instance_valid(stage): root.remove_child(stage); stage.queue_free()
	stage = Node2D.new(); root.add_child(stage); beam = null; pans = []; weights = []
	if page < 4:
		var scene: Dictionary = data.scenes[page]
		var bg = Sprite2D.new(); bg.texture = load("res://"+scene.background); bg.centered = false
		bg.scale = Vector2(1280.0/bg.texture.get_width(),720.0/bg.texture.get_height()); stage.add_child(bg)
		match page:
			0:
				for spec in [["copper_fruit",430,491],["rope_spool",620,491],["wick_bundle",800,491],["receipt_blank",202,418]]: sprite(spec[0],Vector2(spec[1],spec[2]))
			1:
				for spec in [["crate_red",456,532],["crate_blue",575,532],["cloth_bolt",698,532],["oil_bottle",803,532],["brass_bell",897,532]]: sprite(spec[0],Vector2(spec[1],spec[2]))
			2:
				for x in [348,607,859]:
					var cart = sprite("delivery_cart",Vector2(x,384))
					sprite("oil_jug_round",point_on(cart,"delivery_cart","cargo_left"),40)
					sprite("oil_jug_tall",point_on(cart,"delivery_cart","cargo_right"),27)
				var stand = sprite("scale_stand",Vector2(640,527),-1,0.42)
				pivot = point_on(stand,"scale_stand","pivot")
				beam = sprite("scale_beam",pivot,-1,0.42)
				for side in ["left_hook","right_hook"]:
					var pan = sprite("scale_pan",point_on(beam,"scale_beam",side),-1,0.42); pans.append(pan)
					weights.append(sprite("weight_small",point_on(pan,"scale_pan","cargo"),24))
			3:
				sprite("transport_boat_red",Vector2(460,227),90)
				sprite("transport_boat_blue",Vector2(650,240),90)
				sprite("navigation_lantern",Vector2(1198,464),100)
		label_at("资源组装检查 · "+scene.id+" · ←/→ 切换（不含关卡逻辑）",Vector2(24,16))
		if page == 2: label_at("秤梁摆动仅测试枢轴；左右盘保持水平，不表达称量结果",Vector2(24,675))
	else:
		var bg = ColorRect.new(); bg.color = Color("35414b") if page == 4 else Color("e2d8c2"); bg.size = Vector2(1280,720); stage.add_child(bg)
		label_at("独立透明资源 · "+("深底" if page == 4 else "浅底")+" · ←/→ 切换",Vector2(24,12))
		for i in range(data.sprites.size()):
			var item: Dictionary = data.sprites[i]; var x = 95+(i%7)*181; var y = 160+int(i/7)*160
			var node = sprite(item.id,Vector2(x,y),-1,1)
			var dims = node.texture.get_size(); var ratio = minf(136.0/dims.x,100.0/dims.y)
			node.offset = Vector2(-dims.x/2,-dims.y); node.scale = Vector2.ONE*ratio
			label_at(item.title,Vector2(x-80,y+7),Vector2(170,30))
			label_at(item.id,Vector2(x-80,y+34),Vector2(170,30),14)
func _process(delta: float) -> bool:
	time += delta
	if is_instance_valid(beam):
		beam.rotation = sin(time)*0.12
		for i in range(2):
			pans[i].position = point_on(beam,"scale_beam","left_hook" if i == 0 else "right_hook")
			weights[i].position = point_on(pans[i],"scale_pan","cargo")
	if Input.is_action_just_pressed("ui_right"): page = (page+1)%6; build()
	if Input.is_action_just_pressed("ui_left"): page = (page+5)%6; build()
	return false
func run() -> void:
	root.size = Vector2i(1280,720)
	data = JSON.parse_string(FileAccess.get_file_as_string("res://art/market-kit-v1/manifest.json"))
	for item in data.sprites:
		entries[item.id] = item
		textures[item.id] = load("res://"+item.atlas)
		if textures[item.id] == null: push_error("Missing atlas "+item.id); quit(1); return
	build()
	if not await Focus.ready(root): quit(1); return
	if capture_mode:
		for i in range(6):
			page = i; build(); await create_timer(0.2).timeout; await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://docs/playtest/market-kit-v1/preview-%d.png"%i)
		print("MARKET KIT PREVIEW 6/6 PASS"); quit()

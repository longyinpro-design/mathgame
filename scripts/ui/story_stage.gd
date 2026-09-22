extends "res://scripts/ui/presentation_layer.gd"
signal finished
const Actor = preload("res://scripts/ui/companion_actor.gd")
const NPC = preload("res://scripts/ui/npc_actor.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Forest = preload("res://scripts/ui/forest_world.gd")
const Transfer = preload("res://scripts/ui/transfer_stage.gd")
const Layout = preload("res://scripts/ui/scene_layout.gd")
const Story = preload("res://scripts/content/story_catalog.gd")
var node_id = ""
var presentation_key = ""
var scene: Dictionary = {}
var result: Dictionary = {}
var elapsed = 0.0
var duration = 3.0
var speed = 1.0
var paused = false:
	set(value):
		paused = value
		presentation_paused = paused or not focused
var focused = true:
	set(value):
		focused = value
		presentation_paused = paused or not focused
var done = false
var backdrop: Node2D
var cast: Dictionary = {}
var npc: Node2D
var gates: Node2D
var grown = false
var params: Dictionary = {}
var display_values: Array = []
var cargo: Node2D
var prop_layer: Node2D
var cargo_scene = false
var letter_owner = "bag"
var handoff = Vector2.ZERO
var initialized_pose = false
var mill: Node2D
var legacy_cargo_recap = false
var completed_levels: Array = []

func _ready() -> void:
	backdrop = Forest.new(); backdrop.page = "story"; backdrop.cinematic = true; backdrop.show_behind_parent = true; add_child(backdrop)
	cargo = preload("res://scripts/cargo/world.gd").new(); cargo.page = "camp"; cargo.render_people = false; cargo.render_background = false; add_child(cargo)
	for id in ["hero","acheng","mossling","feather"]:
		var actor = Actor.new(); actor.identity = id; actor.pixel_scale = 0.62; add_child(actor); cast[id] = actor
	npc = NPC.new(); npc.scale = Vector2(1.35,1.35); add_child(npc)
	gates = Transfer.new(); gates.scale = Vector2(0.64,0.64); gates.position = Vector2(280,95); add_child(gates); move_child(gates,2)
	prop_layer = Node2D.new(); add_child(prop_layer); prop_layer.draw.connect(_draw_hand_props)
	mill = preload("res://scripts/ui/twenty_four_console.gd").new(); mill.scale = Vector2.ONE*0.68; mill.position = Vector2(200,40); add_child(mill); move_child(mill,2)

func setup(id: String, profile: Dictionary, time_scale: float) -> void:
	var key = id+"|"+profile.story.excursion
	if profile.story.excursion != "" and profile.active_run != null: key += "|"+profile.active_run.run_id
	if presentation_key == key:
		grown = profile.roster.grown; _update_pose(); return
	presentation_key = key
	node_id = id; scene = Story.scene(id); result = profile.story.results.get(scene.level,{}).duplicate(true)
	if node_id == "joined": result = profile.story.results.get("FL02",{}).duplicate(true)
	completed_levels = profile.progress.completed_levels.duplicate()
	if profile.story.excursion != "" and profile.active_run != null and profile.active_run.level_id == scene.level and profile.active_run.outcome == "complete": result = profile.active_run.state.duplicate(true)
	initialized_pose = false
	elapsed = 0; done = false; paused = false; duration = 4.0 if scene.effect in ["delivery","letter","join","bridge","finale"] else 2.8
	if scene.effect == "finale": duration = 8.0
	if scene.level == "FL03" and scene.effect == "result": duration = 6.0
	speed = 1.0/maxf(0.02,time_scale*(0.3 if profile.settings.short_effects else 1.0))
	grown = profile.roster.grown
	params = {}
	if scene.level != "": params = preload("res://scripts/content/content_catalog.gd").new().definition(scene.level).params
	backdrop.region = "treetop" if scene.region == "camp" else scene.region
	backdrop.page = "camp" if scene.region == "camp" else "story"
	backdrop.completed = profile.progress.completed_levels; backdrop.buildings = profile.inventory.buildings
	backdrop.ground.region = "camp" if scene.region == "camp" else scene.region
	backdrop.original_village = scene.level == "FL03" or node_id == "village_arrive"
	backdrop.ground.visible = not backdrop.original_village
	backdrop.ground.story = true; backdrop.ground.completed = backdrop.completed
	backdrop.ground.bridge_gap = scene.effect == "bridge"
	backdrop.ravine_view = scene.effect == "bridge"
	backdrop.ground.queue_redraw()
	mill.visible = false # Full-scene story uses the painted mill, not the close-up console.
	mill.story_mode = scene.level == "FL07"
	mill.done = scene.level == "FL07" and not result.is_empty() and not result.has("final_order")
	mill.target_value = 24.0 if mill.done else 0.0
	mill.steps = result.get("steps",[]).size()
	# The stage owns its actors, separately from the frozen puzzle party.
	backdrop.owned = []; backdrop.party = []; backdrop.hero_position = Vector2(-200,560); backdrop.destination = backdrop.hero_position
	for id_actor in cast: cast[id_actor].visible = id_actor == "hero" or id_actor == "acheng" or id_actor in profile.roster.owned
	if node_id in ["pre_FL02","post_FL02","joined"]: cast.mossling.visible = true
	if scene.region == "post" or node_id == "pre_FL08": cast.feather.visible = true
	npc.visible = scene.region in ["treetop","village","mill"]; npc.region = scene.region
	gates.visible = scene.effect in ["gates","gates_lit","join"] or (scene.level == "FL03" and scene.effect == "result" and not result.is_empty())
	gates.warehouse = scene.level == "FL03"; gates.flight = -1
	gates.scale = Vector2.ONE if gates.warehouse else Vector2.ONE*0.64
	gates.position = Vector2.ZERO if gates.warehouse else Vector2(270,130)
	gates.values = result.get("trace",[]).back() if not result.get("trace",[]).is_empty() else [0,0,0]
	if scene.effect == "gates": gates.values = [0,0,0] # Ambient light introduces the doors; quantities appear only in the puzzle.
	cargo_scene = scene.level in ["FL01","FL11","FL13"] or node_id == "letter"
	legacy_cargo_recap = false
	cargo.visible = cargo_scene; backdrop.visible = not cargo_scene
	if cargo_scene:
		var saved: Dictionary = result
		if node_id == "letter": saved = profile.story.results.get("FL01",{})
		legacy_cargo_recap = not saved.has("places") and (node_id.begins_with("post_") or node_id == "letter")
		if legacy_cargo_recap:
			# Completion is known; the old route/load is not. Show a labelled static
			# recollection on the deck, never a fresh or invented winning cargo state.
			cargo_scene = false; cargo.visible = false; backdrop.visible = true
		else: cargo.state = saved.duplicate(true) if saved.has("places") else preload("res://scripts/mechanisms/cargo_rules.gd").fresh(params)
		cargo.lift = 0.0 if cargo.state.left_low else 1.0
		cargo.page = "camp"
		# A historical receipt is the scene authority, never a fabricated winning load.
		cargo.render_people = false
		npc.visible = scene.region == "treetop"
	_update_pose()

func skip() -> void:
	elapsed = duration; _update_pose(); queue_redraw()
	if not done: done = true; finished.emit()

func _process(delta: float) -> void:
	if not visible or scene.is_empty(): return
	if paused or not focused: return
	if not done:
		elapsed = minf(duration,elapsed+delta*speed)
		_update_pose()
		if elapsed >= duration: done = true; finished.emit()
	queue_redraw(); prop_layer.queue_redraw()

func _update_pose() -> void:
	var t = clampf(elapsed/duration,0,1)
	backdrop.ground.light_progress = t if scene.level == "FL04" and scene.effect == "result" else 1.0
	var travelling = scene.effect in ["travel","arrival","bridge"]
	var feet = Layout.party(scene.region)
	if backdrop.original_village: feet = Transfer.VILLAGE_FEET.duplicate()
	if scene.effect == "join": feet.mossling = Vector2(540,520)
	if legacy_cargo_recap: feet.hero = Vector2(800,592); feet.acheng = Vector2(700,592)
	if scene.effect == "finale":
		var regions = ["village","mill","post","camp"]
		var required = ["FL04","FL07","FL10","FL18"]
		var index = mini(3,int(t*4))
		var place: String = regions[index] if required[index] in completed_levels else "camp"
		backdrop.region = "treetop" if place == "camp" else place
		backdrop.page = "camp" if place == "camp" else "story"
		backdrop.ground.region = place; backdrop.ground.queue_redraw()
		feet = Layout.party(place)
	if cargo_scene:
		var zoom = smoothstep(0.05,0.7,t) if scene.effect == "delivery" else (1.0 if node_id == "letter" else 0.0)
		cargo.scale = Vector2.ONE*lerpf(0.74,1.50,zoom)
		cargo.position = Vector2(162,12).lerp(Vector2(-1040,-18),zoom)
		feet.hero = cargo.position+cargo.item_position(1)*cargo.scale
		feet.acheng = cargo.position+cargo.item_position(0)*cargo.scale
		npc.position = cargo.position+Vector2(1195,cargo.UPPER_Y)*cargo.scale
		npc.scale = Vector2.ONE*lerpf(0.78,1.20,zoom)
	else:
		npc.position = Layout.npc_foot(scene.region); npc.scale = Vector2.ONE*0.82
		if backdrop.original_village: npc.position = Vector2(1183,535); npc.scale = Vector2.ONE*0.75
		if legacy_cargo_recap: npc.position.x = 925
	for id in cast:
		var actor = cast[id]; actor.grown = grown; actor.reaching = false
		actor.pixel_scale = (0.34 if id == "hero" else 0.30)*cargo.scale.x if cargo_scene else 0.42
		var foot: Vector2 = feet[id]
		var walking = false
		if travelling and not cargo_scene:
			var start = 0.04+(["hero","acheng","mossling","feather"].find(id))*0.06
			var progress = smoothstep(start,0.82,t)
			if scene.effect == "bridge":
				progress = smoothstep(0.55,0.96,t)
				var order = ["hero","acheng","mossling","feather"].find(id)
				foot = Vector2(lerpf(658-order*57,1198-order*45,progress),358)
			else: foot.x -= (1.0-progress)*145
			walking = t > start and t < 0.82 and scene.effect != "bridge"
			if scene.effect == "bridge": walking = t > 0.55 and t < 0.96
		if scene.effect == "join" and id == "mossling":
			foot.x = lerpf(760,540,smoothstep(0.25,0.85,t)); walking = t > 0.25 and t < 0.85
		elif scene.effect == "join" and id in ["hero","acheng"]:
			foot.x += 170*smoothstep(0.3,0.85,t); walking = t > 0.3 and t < 0.85
		if not (scene.level == "FL03" and scene.effect == "result" and not result.is_empty() and id == "hero"):
			actor.place_at(foot,walking,not initialized_pose)
		actor.action = "walk" if walking else ("rest" if scene.effect == "rest" else "idle")
		if not walking: actor.facing_left = id == "feather"
		if not cargo_scene and scene.speaker.contains({"hero":"小岚","acheng":"阿橙","mossling":"苔团","feather":"折羽"}[id]) and not done:
			if not walking: actor.action = "talk"
		if cargo_scene and id in ["mossling","feather"]: actor.visible = false
	npc.talking = 0.5 if scene.speaker.contains("站长") or scene.speaker.contains("师傅") or scene.speaker.contains("林婆婆") else 0.0
	npc.facing_left = true
	letter_owner = "bag"
	if scene.effect in ["delivery","letter"]:
		cast.hero.facing_left = false
		var receive: Vector2 = cast.hero.hand_position()
		var give: Vector2 = npc.position+Vector2(-28,-60)*npc.scale.x
		var bag: Vector2 = npc.position+Vector2(-50,-30) if legacy_cargo_recap else cargo.position+(cargo.item_position(2)-Vector2(0,40))*cargo.scale
		handoff = bag.lerp(give,smoothstep(0.0,0.22,t)) if scene.effect == "delivery" and t < 0.25 else (give.lerp(receive,smoothstep(0.25,0.65,t)) if scene.effect == "delivery" else receive)
		letter_owner = "station" if t < 0.65 and scene.effect == "delivery" else "hero"
		cast.hero.reaching = true; cast.hero.prop_hand = receive.lerp(handoff,smoothstep(0.2,0.45,t))
		npc.reaching = letter_owner == "station"; npc.prop_hand = handoff
	else: npc.reaching = false
	initialized_pose = true
	prop_layer.queue_redraw()
	if scene.level == "FL03" and scene.effect == "result" and not result.is_empty():
		var trace: Array = result.trace
		var phase = clampf((t-0.16)/0.35,0.0,2.0)
		var step = mini(int(phase),2)
		gates.values = trace[step]; display_values = gates.values.duplicate()
		gates.flight = phase-step if step < 2 and t >= 0.16 else -1
		if step < 2:
			gates.from_index = int(params.moves[step][0]); gates.to_index = int(params.moves[step][1]); gates.quantity = int(params.moves[step][2])
		var foot: Vector2
		if t < 0.16: foot = Transfer.VILLAGE_FEET.hero.lerp(Vector2(Transfer.ROAD_X[0]-39,537),t/0.16)
		else: foot = Vector2(lerpf(Transfer.ROAD_X[mini(step,1)],Transfer.ROAD_X[mini(step+1,2)],phase-step if step < 2 else 1.0)-39,537)
		cast.hero.place_at(foot,t < 0.86,not initialized_pose)
		cast.hero.reaching = gates.flight >= 0
		cast.hero.prop_hand = foot+Vector2(2,-28)
		cast.hero.facing_left = t < 0.16
		for id in ["acheng","mossling","feather"]: cast[id].facing_left = cast[id].position.x > foot.x

	if done or t >= 1.0:
		for actor in cast.values(): actor.action = "idle"

	redraw_pose()

func _draw() -> void:
	if scene.is_empty(): return
	if cargo_scene: draw_texture_rect(Forest.BACKGROUND,Rect2(0,0,1280,720),false)
	if legacy_cargo_recap: _caption("送达已记在手记里 · 旧记录没有保留每一趟的装载细节")
	var t = clampf(elapsed/duration,0,1)
	# Props animate independently of the actors: unloading, handoff, unfolded letter,
	# light pulses and growing roots, with exact final frames when skipped.
	if scene.effect in ["gates_lit","gates"]:
		if scene.effect == "gates_lit":
			for mote in range(8):
				var q = Vector2(280+((mote*173)%720),150+fposmod(elapsed*26+mote*37,210))
				draw_texture_rect_region(Forest.SPARK,Rect2(q-Vector2(5,5),Vector2(10,10)),Rect2(0,0,Forest.SPARK.get_width(),Forest.SPARK.get_height()),Color(0.9,1,0.75,0.7))
		for i in range(3):
			var p = Vector2(270,130)+Transfer.CENTERS[i]*0.64
			var brightness = smoothstep(i*0.18,i*0.18+0.25,t) if scene.effect == "gates_lit" else 0.25+0.15*sin(elapsed*3+i)
			for ring in range(5): draw_circle(p-Vector2(0,18),42+ring*8,Color(0.8,0.94,0.53,brightness*0.075))
			if scene.effect == "gates_lit" and not result.is_empty(): draw_string(UIStyle.face(),p+Vector2(-19,-113),str(gates.values[i])+" 枚",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("f1e6b5"))
	elif scene.effect == "bridge":
		for i in range(4):
			var roots = PackedVector2Array()
			for j in range(30):
				var f = j/29.0*smoothstep(0,0.5,t)
				roots.append(Vector2(700+350*f,362+i*4+sin(f*PI*4+i)*2))
			if t > 0:
				draw_polyline(roots,Color("504b31"),10)
				draw_polyline(roots,Color("95855b") if i%2 else Color("77774b"),5)
	elif scene.effect == "travel":
		for i in range(14):
			var p = Vector2(fposmod(i*113-t*1550,1450)-85,160+i%5*43)
			draw_colored_polygon(PackedVector2Array([p,p+Vector2(50,-13),p+Vector2(91,2),p+Vector2(35,20)]),Color(0.11,0.25,0.16,0.65))
	elif scene.effect == "join" and t > 0.85:
		var burst = clampf((t-0.85)/0.15,0,1)
		var q = Vector2(630,420)
		draw_texture_rect_region(Forest.BURST_FX,Rect2(q-Vector2(60*burst,60*burst),Vector2(120*burst,120*burst)),Rect2(0,0,Forest.BURST_FX.get_width(),Forest.BURST_FX.get_height()),Color(1,1,1,0.9*burst))
	elif scene.effect == "result": _result(t)
	elif scene.effect == "finale":
		# Light catches existing foliage; no new row of plants crosses the path.
		var spots = {"village":[Vector2(44,496),Vector2(1240,500)],"mill":[Vector2(625,444),Vector2(678,446)],"post":[Vector2(78,312),Vector2(701,325)],"camp":[Vector2(42,480),Vector2(1228,536)]}
		for p in spots[backdrop.ground.region]:
			for ring in range(4): draw_circle(p,8+ring*9,Color(0.94,0.86,0.49,0.04*t))
	if scene.effect in ["arrival","travel","bridge"] and t < 0.2: draw_rect(Rect2(0,0,1280,500),Color(0.025,0.065,0.04,1-t*5))

func _letter(center: Vector2, opening: float) -> void:
	var size = Vector2(82+opening*290,48+opening*132)
	var rect = Rect2(center-size/2,size)
	draw_rect(rect,Color("e5d7ad"))
	draw_line(rect.position,center+Vector2(0,12-opening*70),Color("907e54"),3)
	draw_line(rect.position+Vector2(size.x,0),center+Vector2(0,12-opening*70),Color("907e54"),3)
	if opening > 0.6:
		for i in range(4): draw_line(center+Vector2(-130,-30+i*26),center+Vector2(90-i*15,-30+i*26),Color("b29d73"),3)

func _result(t: float) -> void:
	var id: String = scene.level
	if result.is_empty():
		draw_string(UIStyle.face(),Vector2(410,270),"手记中的旧事 · 当时的细节留在记忆里",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("f1deb0"))
		return
	if id == "FL03":
		pass # Warehouse counts are rendered at the original doors by the shared stage.
	elif id == "FL04":
		_caption("三架灯：%d / %d / %d" % result.weights)
	elif id in ["FL05","FL06","FL07"]:
		if id == "FL06":
			_caption("本次投入 %d → 收获 %d · 找到 %s 机" % [result.observation[0],result.observation[1],result.identified])
		elif id == "FL05": _caption("装回顺序："+_module_names(result.order))
		else:
			if not result.has("final_order"):
				var tokens = preload("res://scripts/mechanisms/twenty_four_rules.gd").replay(params,result)
				_caption(tokens[0].expression+" = 24 · 磨坊开工")
			else: _caption("旧版修复记录 · 原有完成进度保留")
	elif id == "FL08":
		# New receipts count the audited filing; legacy receipts counted the old classifications.
		var bag_counts = [0,0,0]
		if result.get("counts",[]).size() == 3:
			for i in range(3): bag_counts[i] = int(result.counts[i])
		elif result.has("filing"):
			var audit = preload("res://scripts/mechanisms/route_rules.gd")
			for card in result.filing: bag_counts[int(card.group)] += 1
		elif result.has("classifications"):
			for route in result.classifications: bag_counts[int(result.classifications[route])] += 1
		for i in range(3):
			var center = Vector2(516+i*75,342)
			draw_rect(Rect2(center-Vector2(27,29),Vector2(54,29)),Color("8e7852"))
			for j in range(bag_counts[i]):
				var fall = clampf(t*2-j*0.1,0,1)
				var point = center+Vector2((j%3-1)*12,-110+fall*(93-j/3*9))
				draw_rect(Rect2(point,Vector2(12,8)),Color("ead9aa"))
			draw_string(UIStyle.face(),center+Vector2(-22,23),str(bag_counts[i])+" 封",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("f1deb0"))
		_caption("每层 %d / %d / %d 条，一条不多一条不少；折羽收起路签，准备一起出发" % [bag_counts[0],bag_counts[1],bag_counts[2]])
	elif id == "FL09" and result.has("choice"):
		var routes = preload("res://scripts/mechanisms/route_rules.gd")
		var block: Array = params.candidate_blocks[int(result.choice)]
		for route in routes.all_paths(params):
			if block in routes.points(route): continue
			var points = PackedVector2Array()
			for point in routes.points(route): points.append(Vector2(465+point[0]*43,338-point[1]*30))
			draw_polyline(points,Color(0.77,0.87,0.60,0.7),3)
		var rock = Vector2(465+block[0]*43,338-block[1]*30)
		rock += Vector2(130*(1-t),-60*(1-t))
		draw_colored_polygon(PackedVector2Array([rock+Vector2(-18,10),rock+Vector2(-12,-12),rock+Vector2(10,-17),rock+Vector2(21,8)]),Color("c6b790"))
		_caption("落石位置 %d · 留下 %d 条路线" % [result.choice+1,routes.survivors(params,int(result.choice))])
	elif id == "FL10" and result.has("bound_set"):
		for index in result.bound_set.size():
			var progress = clampf(t*1.2-index*0.08,0,1)
			var point = Vector2(610,296).lerp(Vector2(1148,286),progress)-Vector2(0,sin(progress*PI)*(45+index*36))
			_letter(point,0)
		_caption("%d 封信沿选定邮路飞向崖边小屋" % result.bound_set.size())
	elif id == "FL10" and not result.get("pairs",[]).is_empty():
		# Legacy receipts keep their original two-letter walk.
		var pair: Dictionary = result.pairs.back()
		var index = 0
		for key in ["a","b"]:
			if not pair.has(key): continue
			var path: String = pair[key]; var points = [Vector2(470,365)]; var p: Vector2 = points[0]
			for step in path:
				p += Vector2(85,0) if step == "R" else Vector2(0,-65); points.append(p)
			draw_polyline(PackedVector2Array(points),Color("e7cf89") if index == 0 else Color("91cbbc"),3)
			var distance = minf(t*path.length(),path.length()-0.001); var segment = int(distance)
			_letter(points[segment].lerp(points[segment+1],distance-segment),0)
			index += 1

	elif id in ["FL11","FL13"]:
		_caption("%d 趟送达 · 站台上的人和货物与实际收据一致" % result.trips)

	elif id == "FL12":
		var remaining: int = result.start
		var count = mini(result.transcript.size(),int(ceil(t*result.transcript.size())))
		for i in range(count): remaining -= int(result.transcript[i][0])+int(result.transcript[i][1])
		for i in range(remaining): draw_circle(Vector2(430+i%10*36,265+i/10*37),12,Color("ddc484"))
		_caption("最后一枚已取走，守门人履约引路" if t == 1 else "棋盘上还剩 %d 枚" % remaining)
	elif id == "FL17":
		# Three carved rune slabs rise from the moss, numbers engraved by the engine.
		var stone = StyleBoxFlat.new(); stone.bg_color = Color("5a6a54"); stone.set_corner_radius_all(12)
		stone.border_width_left = 3; stone.border_width_right = 3; stone.border_width_top = 3; stone.border_width_bottom = 5
		stone.border_color = Color("3f5040")
		for i in range(3):
			var p = Vector2(570+i*190,448)
			var lift = sin(t*PI)*10
			var base = p+Vector2(0,-lift)
			draw_set_transform(p+Vector2(0,40),0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,38,Color(0,0,0,0.25)); draw_set_transform(Vector2.ZERO)
			draw_style_box(stone,Rect2(base-Vector2(34,38),Vector2(68,76)))
			for clump in [[-28,-34],[26,-32],[-24,30],[28,32]]:
				draw_circle(base+Vector2(clump[0],clump[1]),5+sin(t*PI+i)*1.5,Color("6f8a55"))
			draw_arc(base,25,0,TAU,40,Color("77876f"),2)
			draw_string(UIStyle.face(),base+Vector2(-13,10),str(result.energy[i]),HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color("f0ddb2"))
		if t >= 1.0:
			for mote in range(9):
				var a = mote*TAU/9+elapsed*0.7
				var q = Vector2(760,448)+Vector2(cos(a),sin(a))*65
				draw_texture_rect_region(Forest.SPARK,Rect2(q-Vector2(7,7),Vector2(14,14)),Rect2(0,0,Forest.SPARK.get_width(),Forest.SPARK.get_height()),Color(1,0.95,0.7,0.8))
		_caption("三枚符石各用一次，石灵收起试炼的封印")
	elif id == "FL18":
		var center = Vector2(680,525)
		for ring in range(5): draw_circle(center,30+ring*14*(0.4+t*0.8),Color(0.72,0.88,0.5,(1-t)*0.06))
		for i in range(int(result.finisher[0])):
			var a = i*TAU/maxi(1,int(result.finisher[0])); var radius = 155*(1-t)
			var q = center+Vector2(cos(a),sin(a))*radius
			draw_texture_rect_region(Forest.SPARK,Rect2(q-Vector2(6,6),Vector2(12,12)),Rect2(0,0,Forest.SPARK.get_width(),Forest.SPARK.get_height()),Color(1,0.93,0.7,0.9))
		# The sprout: a curved stem with two unfurling leaves and a golden bud.
		var height = 95*t
		if height > 1.0:
			var stem = PackedVector2Array()
			for step in range(9):
				var f = step/8.0
				stem.append(center+Vector2(sin(f*2.4)*7*f,-height*f))
			draw_polyline(stem,Color("6f9a55"),7)
			for side in [-1,1]:
				var leaf = center+Vector2(0,-height*0.45)
				var tip = leaf+Vector2(side*40*t,-26*t)
				var mid = tip+Vector2(-side*14,-16*t)
				var under = leaf+Vector2(side*6,4)
				# Two triangles: a four-point leaf quad self-intersects at large t
				# and trips polygon triangulation.
				draw_colored_polygon(PackedVector2Array([leaf,tip,mid]),Color("88b063"))
				draw_colored_polygon(PackedVector2Array([leaf,mid,under]),Color("88b063"))
		var bud = center+Vector2(sin(2.4)*7,-height)
		for ring in range(3): draw_circle(bud,6+ring*5+sin(elapsed*3)*2,Color(0.95,0.82,0.45,0.16))
		draw_circle(bud,8,Color("e9cf82"))
		_caption("合击 %d 颗 → 回响 %d · 余下 %d 颗种子" % [result.finisher[0],result.finisher[1],result.seed_balance])
	elif id == "FL14": _caption("石径留下了脚印，新的路带收进手记")
	elif id == "FL15": _caption("两次称量的每一种回响，都有了唯一去处")
	elif id == "FL16": _caption("花圃设计送回邻居家 · 营地花圃仍可自愿建设")

func _caption(value: String) -> void:
	draw_rect(Rect2(220,300 if scene.region in ["treetop","camp"] and not cargo_scene else 184,865,38),Color(0.04,0.08,0.05,0.78))
	draw_string(UIStyle.face(),Vector2(238,326 if scene.region in ["treetop","camp"] and not cargo_scene else 210),value,HORIZONTAL_ALIGNMENT_LEFT,830,18,Color("f1deb0"))

func _draw_hand_props() -> void:
	if scene.is_empty() or scene.effect not in ["delivery","letter"]: return
	var t = clampf(elapsed/duration,0,1)
	var opening = smoothstep(0.25,0.8,t) if scene.effect == "letter" else 0.0
	var size = Vector2(38+opening*42,27+opening*27)
	var center = handoff+Vector2(opening*28,5)
	var rect = Rect2(center-size/2,size)
	prop_layer.draw_rect(Rect2(rect.position+Vector2(2,3),rect.size),Color(0.08,0.08,0.04,0.3))
	var paper = UIStyle.PAPER_PANEL
	prop_layer.draw_texture_rect_region(paper,rect,Rect2(Vector2(paper.get_width(),paper.get_height())*0.35,Vector2(paper.get_width(),paper.get_height())*0.3))
	prop_layer.draw_rect(rect,Color("aa9163"),false,1.5)
	if opening < 0.5:
		prop_layer.draw_line(rect.position,center+Vector2(0,6),Color("9f8560"),1.5)
		prop_layer.draw_line(rect.position+Vector2(size.x,0),center+Vector2(0,6),Color("9f8560"),1.5)
		prop_layer.draw_circle(center+Vector2(0,7),4,Color("6d8652"))
	else:
		for i in range(3): prop_layer.draw_line(center+Vector2(-24,-12+i*11),center+Vector2(22-i*5,-12+i*11),Color("ad9871"),2)
		prop_layer.draw_circle(center+Vector2(23,18),5,Color("6d8652"))

func _module_names(order: Array) -> String:
	var names = []
	for module in order: names.append({"triple":"×3","plus2":"+2","minus1":"−1","plus3":"+3","double":"×2"}.get(module,module))
	return " → ".join(names)

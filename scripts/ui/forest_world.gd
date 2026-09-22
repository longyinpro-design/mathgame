extends "res://scripts/ui/presentation_layer.gd"
const UIStyle = preload("res://scripts/cargo/skin.gd")
const BACKGROUND = preload("res://assets/runtime/treetop-v5.png")
const RAVINE = preload("res://assets/runtime/forest-ravine-v2.png")
const FOX = preload("res://assets/runtime/fox-v2.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
const Actor = preload("res://scripts/ui/companion_actor.gd")
const VILLAGE = preload("res://assets/runtime/forest/village-v1.png")
var mill_texture: Texture2D
const GUARDIAN = preload("res://assets/runtime/v3/objects.png")
const CARGO_PROPS = preload("res://assets/runtime/cargo-props-v5.png")
const Catalog = preload("res://scripts/content/content_catalog.gd")
const Story = preload("res://scripts/content/story_catalog.gd")
const NPC = preload("res://scripts/ui/npc_actor.gd")
const Layout = preload("res://scripts/ui/scene_layout.gd")
const ARENA = preload("res://assets/runtime/v3/arena.png")
var ravine_view = false
var inspecting = false
var active_level = ""
const Ground = preload("res://scripts/ui/scene_ground.gd")
const Grain = preload("res://scripts/ui/transfer_stage.gd")
var original_village = false
var grain_hero = Grain.VILLAGE_FEET.hero
var grain_moving = false
var grain_pushing = false
var ground: Node2D
var cinematic = false
var page = "camp"
var region = "treetop"
var buildings: Array = []
var owned: Array = ["acheng"]
var grown = false
var completed: Array = []
var time = 0.0
var hero_position = Vector2(470,565)
var destination = Vector2(470,565)
var reaction = 0.0
var fountain = false
var actors: Dictionary = {}
var party: Array = ["acheng"]
var walk_speed = 190.0
var npc: Node2D
var post_npc: Node2D
var object_positions: Dictionary = {}
var available_ids: Array = []
var suspended_ids: Array = []
var near_glow = 0.0
var flavor_spots: Array = []
var poked = Vector2.ZERO
var poked_time = 0.0
const SPARK = preload("res://assets/runtime/forest/fx/spark.png")
const BURST_FX = preload("res://assets/runtime/forest/fx/burst.png")

func _ready() -> void:
	mill_texture = load("res://assets/runtime/forest/mill-v1.png")
	ground = Ground.new(); add_child(ground)
	for id in ["hero","acheng","mossling","feather"]:
		var node = Actor.new(); node.identity = id; add_child(node); actors[id] = node
	npc = NPC.new(); npc.position = Vector2(1186,562); add_child(npc)
	post_npc = Actor.new(); post_npc.identity = "feather"; post_npc.position = Vector2(1186,562); post_npc.action = "rest"; post_npc.facing_left = true; add_child(post_npc)

func _process(delta: float) -> void:
	ground.region = "camp" if page == "camp" else region; ground.story = cinematic or page == "story"
	ground.visible = page in ["camp","region","story","challenge"] and not original_village
	ground.challenge = page == "challenge"
	ground.completed = completed
	time += delta; reaction = maxf(0,reaction-delta)
	poked_time = maxf(0.0,poked_time-delta)
	near_glow = 0.5+0.5*sin(time*2.4)
	hero_position = hero_position.move_toward(destination,delta*walk_speed)
	npc.visible = page == "region" and region in ["treetop","village","mill"]
	npc.region = region; npc.story_stage = 0
	npc.position = Layout.npc_foot(region)
	post_npc.position = Layout.npc_foot(region)
	for id in Catalog.REGIONS[region]:
		if id in completed: npc.story_stage = mini(3,npc.story_stage+1)
	post_npc.visible = page == "region" and region == "post" and "feather" not in owned
	var walking = hero_position.distance_to(destination) > 1
	for id in actors:
		var node: Node2D = actors[id]
		node.visible = not cinematic and not inspecting and page in ["camp","region","challenge"] and (id == "hero" or (id in owned if page == "camp" else (id in party if page == "challenge" else (not party.is_empty() and id == party[0]))))
		var foot: Vector2 = hero_position+{"hero":Vector2.ZERO,"acheng":Vector2(-88,8),"mossling":Vector2(82,3),"feather":Vector2(153,0)}[id]
		# Keep actors on the painted terrain; close inspections hide the cast.
		node.pixel_scale = 0.42 if id == "hero" else 0.38
		node.z_index = 1 if page == "challenge" else 0
		if page == "challenge": foot = Layout.party(region,active_level)[id]
		else: foot = Layout.foot("camp" if page == "camp" else region,foot.x)
		if original_village:
			node.pixel_scale = 0.42 if id == "hero" else 0.38
			foot = grain_hero if id == "hero" else Grain.VILLAGE_FEET[id]
			node.facing_left = foot.x > grain_hero.x
		foot.x = clampf(foot.x,72,1205)
		var own_walking = (walking if id == "hero" else node.position.distance_to(foot) > 1.0) and page == "region"
		if own_walking and id != "hero": foot = node.position.move_toward(foot,delta*walk_speed*1.04)
		node.place_at(foot,(own_walking or (original_village and id == "hero" and grain_moving)) and node.position.distance_to(foot) > 0.1)
		node.reaching = original_village and id == "hero" and grain_pushing
		if node.reaching: node.prop_hand = grain_hero+Vector2(2,-28)
		node.grown = grown
		if walking and not original_village: node.facing_left = destination.x < hero_position.x
	queue_redraw()

func actor(texture: Texture2D, region_rect: Rect2, foot: Vector2, height: float) -> void:
	var width = region_rect.size.x/region_rect.size.y*height
	draw_set_transform(foot,0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,width*0.35,Color(0,0,0,0.28)); draw_set_transform(Vector2.ZERO)
	draw_texture_rect_region(texture,Rect2(foot-Vector2(width/2,height),Vector2(width,height)),region_rect)

func _draw() -> void:
	var backdrop = VILLAGE if region == "village" and page != "camp" else (RAVINE if region in ["heart","post"] and page != "camp" else BACKGROUND)
	if region == "heart" and page != "camp" and not ravine_view: backdrop = ARENA
	if region == "mill" and page != "camp" and mill_texture != null: backdrop = mill_texture
	draw_texture_rect(backdrop,Rect2(0,0,1280,720),false)
	if inspecting: draw_rect(Rect2(0,0,1280,720),Color(0.02,0.04,0.03,0.48))
	for y in range(0,180,4): draw_rect(Rect2(0,y,1280,4),Color(0.025,0.065,0.04,0.83*(1-y/180.0)))
	for y in range(555,720,4): draw_rect(Rect2(0,y,1280,4),Color(0.025,0.065,0.04,0.92*(y-555)/165.0))
	if page in ["camp","region"]:
		if page == "region":
			object_positions.clear()
			var ids: Array = Catalog.REGIONS[region]
			for i in ids.size():
				var point = Layout.point(region,i); object_positions[ids[i]] = point; draw_object(point,ids[i],i)
		if page == "region" and region == "heart": actor(GUARDIAN,Rect2(29,10,596,607),Layout.npc_foot(region),125)
		if page == "region" and region == "village" and "FL04" in completed:
			for point in [Vector2(332,303),Vector2(824,405),Vector2(1187,324)]:
				var pulse = 0.055+0.02*sin(time*2.1+point.x)
				for ring in range(5): draw_circle(point,12+ring*8,Color(0.98,0.8,0.38,pulse))
				# A pool of lamplight on the ground: the village stays lit once restored.
				draw_set_transform(Vector2(point.x,563),0,Vector2(1,0.24))
				for pool in range(3): draw_circle(Vector2.ZERO,26+pool*13,Color(0.98,0.82,0.42,0.05))
				draw_set_transform(Vector2.ZERO)
		if region == "mill" and "FL07" in completed and page == "region":
			# The mill keeps working after its puzzle: warm windows and machine light.
			for window in [Vector2(830,320),Vector2(930,320),Vector2(1030,320),Vector2(1245,235)]:
				for ring in range(4): draw_circle(window,10+ring*8,Color(0.99,0.77,0.36,0.05))
		if page == "camp":
			if "roof" in buildings:
				draw_texture_rect(UIStyle.plank(),Rect2(997,244,251,12),false)
				for x in [1023,1215]: draw_texture_rect(UIStyle.plank(),Rect2(x,255,9,37),false)
				for radius in range(12,45,5): draw_circle(Vector2(1080,270),radius,Color(0.96,0.78,0.40,0.055))
			if "workbench" in buildings:
				draw_set_transform(Vector2(0,34))
				draw_texture_rect(UIStyle.plank(),Rect2(160,474,190,24),false)
				for x in [179,318]: draw_rect(Rect2(x,498,12,60),Color("6e593d"))
				draw_texture_rect_region(CARGO_PROPS,Rect2(187,430,40,46),Rect2(625,538,328,410))
				draw_rect(Rect2(270,450,43,23),Color("e5d5b0")); draw_line(Vector2(270,450),Vector2(292,463),Color("9c8256"),2); draw_line(Vector2(313,450),Vector2(292,463),Color("9c8256"),2)
				draw_texture_rect(UIStyle.plank(),Rect2(237,449,8,28),false); draw_rect(Rect2(229,445,25,9),Color("a4a486"))
				draw_set_transform(Vector2.ZERO)
			if "garden" in buildings:
				draw_set_transform(Vector2(0,17))
				draw_texture_rect(UIStyle.plank(),Rect2(824,532,183,28),false)
				for x in [836,983]: draw_texture_rect(UIStyle.plank(),Rect2(x,558,8,17),false)
				for i in range(12): flower(Vector2(842+i%6*24,526+i/6*18),i)
				draw_texture_rect_region(GUARDIAN,Rect2(1022,509,20,32),Rect2(778,664,323,520))
				draw_set_transform(Vector2.ZERO)
	if "FL18" in completed and region == "mill" and page == "region":
		for i in range(5): flower(Vector2(642+i*12,442),i)
	if region == "treetop":
		# The station lantern breathes; camp and region share this lamp.
		var flicker = 0.055+0.028*sin(time*6.3)+0.012*sin(time*13.7)
		for ring in range(4): draw_circle(Vector2(88,462),10+ring*9,Color(0.99,0.82,0.42,flicker))
	for i in flavor_spots.size():
		var spot: Array = flavor_spots[i]
		var glint = 0.45+0.35*sin(time*2.4+i*1.9)
		var point = Vector2(spot[0],spot[1])+Vector2(0,18+sin(time*1.7+i)*3)
		draw_texture_rect_region(SPARK,Rect2(point-Vector2(9,9),Vector2(18,18)),Rect2(0,0,SPARK.get_width(),SPARK.get_height()),Color(1,0.95,0.75,glint))
	if poked_time > 0.0:
		var wave = 1.0-poked_time/0.9
		for ring in range(3): draw_arc(poked,10+wave*46+ring*9,0,TAU,40,Color(0.98,0.9,0.6,(1-wave)*0.5),2.5)
	for i in range(22):
		var point = Vector2(fposmod(i*127+time*(3+i%5),1280),180+fposmod(i*59+sin(time+i)*7,370))
		draw_circle(point,1.5,Color(1,0.9,0.64,0.25))

func flower(foot: Vector2, index: int) -> void:
	draw_line(foot,foot-Vector2(0,24),Color("87a661"),3)
	for i in range(5): draw_circle(foot-Vector2(0,26)+Vector2(cos(i*TAU/5),sin(i*TAU/5))*5,4,Color("e5ce86") if index%2 else Color("d9b99d"))

func draw_object(foot: Vector2, id: String, index: int) -> void:
	# The object is already painted into the scene. A small glint identifies the
	# interaction; captions appear only when the party is near that object.
	var near = absf(hero_position.x-foot.x) < 150
	if id not in completed and available_ids.has(id):
		draw_texture_rect_region(SPARK,Rect2(foot-Vector2(7,35),Vector2(14,14)),Rect2(0,0,SPARK.get_width(),SPARK.get_height()),Color(1,0.93,0.68,0.45+near_glow*0.3))
	if near:
		var caption: String = Story.OBJECT_NAMES[id]+(" · 回访" if id in completed else (" · 继续" if id in suspended_ids else ""))
		if available_ids.has(id):
			draw_string_outline(UIStyle.face(),foot+Vector2(-55,-49),caption+" [E]",HORIZONTAL_ALIGNMENT_LEFT,-1,18,3,Color("1c2c24"))
			draw_string(UIStyle.face(),foot+Vector2(-55,-49),caption+" [E]",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("f1dfad"))

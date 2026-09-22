extends "res://scripts/ui/presentation_layer.gd"
const UIStyle = preload("res://scripts/cargo/skin.gd")
const BACKGROUND = preload("res://assets/runtime/v3/arena.png")
const OBJECTS = preload("res://assets/runtime/v3/objects.png")
const FOX = preload("res://assets/runtime/fox-v2.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
const CRYSTAL = preload("res://assets/runtime/forest/fx/crystal-idle.png")
const CRYSTAL_LIT = preload("res://assets/runtime/forest/fx/crystal-lit.png")
const ProbeRules = preload("res://scripts/mechanisms/probe_battle_rules.gd")
const Actor = preload("res://scripts/ui/companion_actor.gd")
var family = "boss_seal_duel"
var params: Dictionary = {}
var state: Dictionary = {}
var time = 0.0
var flight = -1.0
var swap = -1.0
var burst = 0.0
var source = 0
var target = 1
var card = 1
var selected_card = -1
var selected_core = -1
var previous_candidates: Array = []
var disappearing = 0.0
var font: Font
var tree_texture: Texture2D
var actors: Dictionary = {}
var flight_layer: Node2D
const PARTY_FEET = {"hero":Vector2(126,455),"acheng":Vector2(201,486),"mossling":Vector2(175,526),"feather":Vector2(200,548)}
const CENTERS = [Vector2(378,409),Vector2(684,409),Vector2(990,409)]

func _ready() -> void:
	font = UIStyle.face()
	tree_texture = load("res://assets/runtime/forest/tree-forms-v1.png")
	for id in ["hero","acheng","mossling","feather"]:
		var node = Actor.new(); node.identity = id; node.position = PARTY_FEET[id]; node.pixel_scale = 0.42 if id == "hero" else 0.38; node.z_index = 1
		add_child(node); actors[id] = node
	flight_layer = Node2D.new(); flight_layer.z_index = 2; add_child(flight_layer)
	flight_layer.draw.connect(_draw_flight)


func _process(delta: float) -> void:
	time += delta; queue_redraw(); flight_layer.queue_redraw()

func actor(texture: Texture2D, rect: Rect2, foot: Vector2, height: float, tint: Color = Color.WHITE) -> void:
	var width = rect.size.x/rect.size.y*height
	draw_set_transform(foot,0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,width*0.34,Color(0,0,0,0.26)); draw_set_transform(Vector2.ZERO)
	draw_texture_rect_region(texture,Rect2(foot-Vector2(width/2,height),Vector2(width,height)),rect,tint)

func words(value: String, point: Vector2, size_px: int = 22, color: Color = UIStyle.INK) -> void:
	draw_string_outline(font,point,value,HORIZONTAL_ALIGNMENT_CENTER,-1,size_px,3,Color("273629"))
	draw_string(font,point,value,HORIZONTAL_ALIGNMENT_CENTER,-1,size_px,color)

func _draw() -> void:
	if state.is_empty() or font == null: return
	draw_texture_rect(BACKGROUND,Rect2(0,0,1280,720),false)
	for y in range(0,150,4): draw_rect(Rect2(0,y,1280,4),Color(0.02,0.055,0.05,0.85*(1-y/150.0)))
	for y in range(535,720,4): draw_rect(Rect2(0,y,1280,4),Color(0.02,0.055,0.045,0.92*(y-535)/185.0))
	if family == "boss_seal_duel": draw_seal()
	else: draw_probe()

func _draw_flight() -> void:
	if flight >= 0:
		var from = CENTERS[source] if family == "boss_seal_duel" else actors.hero.hand_position()
		var to = CENTERS[target] if family == "boss_seal_duel" else Vector2(686,265)
		var p = from.lerp(to,flight)-Vector2(0,sin(flight*PI)*123)
		for i in range(card):
			var offset = Vector2((i%4)*13,(i/4)*14)
			if family == "boss_seal_duel":
				flight_layer.draw_texture_rect_region(CRYSTAL_LIT,Rect2(p+offset-Vector2(9,11),Vector2(18,23)),Rect2(0,0,CRYSTAL_LIT.get_width(),CRYSTAL_LIT.get_height()))
			else:
				flight_layer.draw_circle(p+offset,7,Color("f1d980")); flight_layer.draw_circle(p+offset,3,Color("fff5c5"))
	if burst > 0:
		for i in range(45):
			var radius = 20+burst*260
			var p = Vector2(685,286)+Vector2(cos(i*TAU/45),sin(i*TAU/45))*radius
			flight_layer.draw_circle(p,3+burst*2,Color(0.91,0.83,0.54,1-burst*0.6))

func draw_seal() -> void:
	var guardian_foot = Vector2(688,340)
	if swap >= 0: guardian_foot.y -= sin(swap*PI)*15
	actor(OBJECTS,Rect2(29,10,596,607),guardian_foot,245,Color("d7e2b4") if state.won else Color.WHITE)
	var locked = int(params.locked_core_by_turn[mini(int(state.turn_index),2)])
	for i in range(3):
		var p: Vector2 = CENTERS[i]
		draw_circle(p,79,Color("3e5140")); draw_arc(p,77,0,TAU,64,Color("ae9e68"),7)
		var energy_position = p
		if swap >= 0 and i in [1,2]:
			energy_position = p.lerp(CENTERS[3-i],swap)+Vector2(0,(-1 if i == 1 else 1)*sin(swap*PI)*105)
		for crystal in int(state.energy[i]):
			var q = energy_position+Vector2((crystal%5-2)*20,(crystal/5)*20-30)
			draw_texture_rect_region(CRYSTAL,Rect2(q+Vector2(-9,-12),Vector2(18,24)),Rect2(0,0,CRYSTAL.get_width(),CRYSTAL.get_height()))
		words(str(state.energy[i]),energy_position+Vector2(-11,46),28)
		words(["甲","乙","丙"][i],p+Vector2(-8,-96),24)
		if i == locked and state.battle_phase == "turns":
			draw_arc(p,88,0,TAU,64,Color("d2ae77"),4)
			for dx in [-54,54]: draw_line(p+Vector2(dx,-64),p+Vector2(-dx,64),Color(0.74,0.62,0.41,0.65),8)
			words("封",p+Vector2(-12,113),22)
		elif selected_core == i: draw_arc(p,86,0,TAU,64,Color("f9e5a1"),4)
	if state.battle_phase == "victory":
		for i in range(15): draw_line(Vector2(275+i*58,539),Vector2(295+i*58,563),Color("91a968"),12)

func draw_probe() -> void:
	var candidates = ProbeRules.candidates(params,state)
	var revealed = candidates.size() == 1
	# The bud opens only from effective observations; the full spring crown is reserved for victory.
	if tree_texture != null: actor(tree_texture,Rect2(1017,470,516,540) if state.won else Rect2(515,457,495,552),Vector2(686,466),310)
	if revealed:
		for ring in range(5): draw_circle(Vector2(685,288),12+ring*5,Color(0.97,0.83,0.45,0.10))
	var index = 0
	for id in params.forms:
		var center = Vector2(326+index*232,338+sin(time*1.5+index)*8)
		var active = id in candidates
		var alpha = 0.88 if active else 0.14
		if not active and id in previous_candidates and disappearing > 0: alpha = lerpf(0.14,0.88,disappearing)
		var regions = [Rect2(46,22,437,470),Rect2(621,24,306,449),Rect2(1100,8,369,493),Rect2(38,512,450,462)]
		if tree_texture != null: actor(tree_texture,regions[index],center+Vector2(0,75),143,Color(1,1,1,alpha))
		words({"A":"甲","B":"乙","C":"丙","D":"丁"}.get(id,id),center+Vector2(-8,98),24,Color(0.99,0.92,0.73,alpha))
		index += 1
	for i in int(state.seed_balance):
		var p = Vector2(352+(i%8)*27,514+(i/8)*23)
		draw_circle(p,8,Color("c2a668")); draw_line(p+Vector2(-2,4),p+Vector2(3,-4),Color("eee0a0"),2)
	words("种子储备 %d"%state.seed_balance,Vector2(347,485),22)
	if not state.active_observations.is_empty():
		var last: Array = state.active_observations.back()
		words("回响 %d → %d"%last,Vector2(586,444),26)

extends Node2D
const ART = preload("res://assets/runtime/v3/objects.png")
const BACKGROUND = preload("res://assets/runtime/v3/arena.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
const FOX = preload("res://assets/runtime/fox-v2.png")
const CAST = preload("res://assets/runtime/v3/cast.png")
const WIN = preload("res://assets/runtime/v3/victory.png")
const FOX_CAST = preload("res://assets/runtime/v3/fox-cast.png")
const TEAL = Color("8ce8d4")
const GOLD = Color("f0d78b")
const SHIELDS = [Vector2(610,340),Vector2(1050,340)]
var time = 0.0
var hero_x = 155.0
var fox_x = 65.0
var hero_pose = "idle"
var fox_pose = "idle"
var hero_recoil = 0.0
var fox_hop = 0.0
var guardian_offset = Vector2.ZERO
var guardian_awake = 0.0
var guardian_warmth = 0.0
var shield_alpha = 0.0
var shield_charge = [0.0,0.0]
var shield_tilt = 0.0
var zoom = 1.0
var shake = 0.0
var charge = 0.0
var cutin = 0.0
var cutin_kind = "cast"
var portal = 0.0
var spell_progress = -1.0
var impact = 0.0
var impact_success = true
var medal_alpha = 0.0
var medal_scale = 1.0
var left = 7
var selected = -1
var hover_side = -1
var crystal_visibility = 0.0
var drag_ghost: Sprite2D
var hero: Sprite2D
var fox: Sprite2D
var guardian: Sprite2D
var shield_nodes: Array[Sprite2D] = []
var crystal_nodes: Array[Sprite2D] = []
var medal: Sprite2D
var cast_portrait: Sprite2D
var fox_portrait: Sprite2D
var frames: Dictionary = {}
var objects: Dictionary = {}
var camera: Node2D
var background_node: Node2D
var overlays: Node2D
var portal_node: Polygon2D

static func atlas(texture: Texture2D, rect: Rect2) -> AtlasTexture:
	var a = AtlasTexture.new(); a.atlas = texture; a.region = rect; return a
func sprite(texture: Texture2D, height: float, parent: Node) -> Sprite2D:
	var s = Sprite2D.new(); s.texture = texture; s.scale = Vector2.ONE*height/texture.get_height(); parent.add_child(s); return s
func _ready() -> void:
	objects = {
		"guardian":atlas(ART,Rect2(29,10,596,607)),
		"shield":atlas(ART,Rect2(764,29,354,577)),
		"crystal":atlas(ART,Rect2(177,659,289,538)),
		"medal":atlas(ART,Rect2(778,664,323,520))}
	frames = {"idle":atlas(HERO,Rect2(1200,10,235,334)),"walk1":atlas(HERO,Rect2(1200,350,235,312)),"walk2":atlas(HERO,Rect2(1200,675,235,328))}
	camera = Node2D.new(); add_child(camera)
	background_node = Node2D.new(); camera.add_child(background_node); background_node.draw.connect(draw_background)
	portal_node = Polygon2D.new()
	var arch = PackedVector2Array([Vector2(799,328),Vector2(799,181)])
	for i in range(25):
		var a = PI+PI*i/24.0
		arch.append(Vector2(872,181)+Vector2(cos(a)*73,sin(a)*85))
	arch.append(Vector2(945,328)); portal_node.polygon = arch
	var uvs = PackedVector2Array()
	for v in arch: uvs.append((v-Vector2(799,96))/Vector2(146,232))
	portal_node.uv = uvs
	var shader = Shader.new()
	shader.code = """shader_type canvas_item;
	uniform float reveal = 0.0;
	varying vec2 portal_uv;
	void vertex() { portal_uv = (VERTEX-vec2(799.0,96.0))/vec2(146.0,232.0); }
	void fragment() {
		float ribbon = 0.5 + 0.5*sin(portal_uv.x*23.0 + sin(portal_uv.y*9.0-TIME)*2.0-TIME*0.7);
		float heart = pow(max(0.0,1.0-abs(portal_uv.x-0.5)*2.0),1.7);
		vec3 shade = mix(vec3(0.035,0.20,0.24),vec3(0.48,0.87,0.72),heart);
		shade += vec3(0.27,0.19,0.04)*ribbon*heart;
		shade = mix(shade,vec3(0.89,0.92,0.66),smoothstep(0.55,1.15,portal_uv.y)*heart);
		COLOR = vec4(shade,reveal);
	}"""
	var material_value = ShaderMaterial.new(); material_value.shader = shader; portal_node.material = material_value; camera.add_child(portal_node)
	guardian = sprite(objects.guardian,278,camera)
	for point in SHIELDS:
		var s = sprite(objects.shield,208,camera); s.position = point; shield_nodes.append(s)
	hero = sprite(frames.idle,154,camera)
	fox = sprite(atlas(FOX,Rect2(200,190,920,880)),99,camera)
	for i in range(14): crystal_nodes.append(sprite(objects.crystal,45,camera))
	overlays = Node2D.new(); camera.add_child(overlays); overlays.draw.connect(draw_effects)
	cast_portrait = sprite(CAST,350,camera); cast_portrait.z_index = 20
	fox_portrait = sprite(FOX_CAST,110,camera); fox_portrait.z_index = 5
	medal = sprite(objects.medal,165,camera); medal.z_index = 25
	drag_ghost = sprite(objects.crystal,56,self); drag_ghost.visible = false; drag_ghost.z_index = 50

func _process(delta: float) -> void:
	time += delta
	camera.scale = Vector2.ONE*zoom
	camera.position = Vector2(640,350)*(1-zoom)+Vector2(sin(time*71),cos(time*53))*shake
	var key = "idle"
	if hero_pose == "walk": key = ["idle","walk1","idle","walk2"][int(time*7)%4]
	hero.texture = frames[key]; hero.scale = Vector2.ONE*154/hero.texture.get_height()
	var bob = -absf(sin(time*14))*3 if hero_pose == "walk" else sin(time*2.2)*1.1
	hero.position = Vector2(hero_x-hero_recoil,465-77+bob)
	hero.rotation = -0.12 if hero_pose == "guard" else (-0.05*charge)
	fox.position = Vector2(fox_x,478-49-fox_hop+sin(time*3)*1.5)
	fox.rotation = -0.10*charge if fox_pose == "charge" else 0
	fox.modulate.a = 0.3 if fox_pose == "cast" else 1
	fox_portrait.modulate.a = 1.0 if fox_pose == "cast" else 0.0
	fox_portrait.position = Vector2(fox_x+15,425-fox_hop)
	guardian.position = Vector2(840,455-139+sin(time*1.6)*2)+guardian_offset
	guardian.modulate = Color(0.50,0.63,0.65).lerp(Color.WHITE,guardian_awake).lerp(Color("ffe4ae"),guardian_warmth*0.35)
	guardian.scale = Vector2(1+sin(time*1.6)*0.006,1-sin(time*1.6)*0.005)*278/607.0
	for i in range(2):
		var s = shield_nodes[i]
		s.position = SHIELDS[i]+Vector2(0,sin(time*2+i*1.4)*4)
		s.modulate = Color.WHITE.lerp(Color("fff0ad"),float(shield_charge[i])*0.7); s.modulate.a = shield_alpha
		s.rotation = shield_tilt*(1 if i == 0 else -1)
		s.scale = Vector2.ONE*(208/577.0)*(1+float(shield_charge[i])*0.07)
	for i in range(14):
		var side = 0 if i < left else 1
		var index = i if side == 0 else i-left
		var s = crystal_nodes[i]; s.position = crystal_position(side,index)+Vector2(0,sin(time*2.5+i*0.7)*2)
		s.modulate.a = crystal_visibility
		s.scale = Vector2.ONE*(45/538.0)*(1.12 if selected == i else 1)
		s.rotation = sin(time*1.4+i)*0.04
	cast_portrait.texture = WIN if cutin_kind == "victory" else CAST
	cast_portrait.scale = Vector2.ONE*(370.0 if cutin_kind == "victory" else 345.0)/cast_portrait.texture.get_height()
	cast_portrait.position = Vector2(265-(1-cutin)*95,345)
	cast_portrait.modulate.a = minf(1.0,cutin*1.5)
	hero.visible = cutin < 0.25
	portal_node.visible = portal > 0
	portal_node.material.set_shader_parameter("reveal",portal)
	medal.position = Vector2(850,307+sin(time*2.1)*7)
	medal.modulate.a = medal_alpha; medal.scale = Vector2.ONE*(165/520.0)*medal_scale
	background_node.queue_redraw(); overlays.queue_redraw()

func crystal_position(side: int, index: int) -> Vector2:
	return Vector2((486 if side == 0 else 926)+(index%7)*36,535+(index/7)*49)
func hit_crystal(point: Vector2) -> int:
	for i in range(14):
		if point.distance_to(crystal_nodes[i].position) < 27: return i
	return -1
func target_side(point: Vector2) -> int:
	for i in range(2):
		if Rect2(SHIELDS[i]-Vector2(90,122),Vector2(180,244)).has_point(point): return i
		if Rect2(Vector2(455 if i == 0 else 895,503),Vector2(302,110)).has_point(point): return i
	return -1
func world_point(point: Vector2) -> Vector2:
	return camera.transform.affine_inverse()*point

func draw_background() -> void:
	background_node.draw_texture_rect(BACKGROUND,Rect2(0,0,1280,720),false)
	for i in range(24):
		var x = fposmod(i*127.7+time*(3+i%3),1280)
		var y = 180+fposmod(i*87.1+sin(time+i)*12,430)
		background_node.draw_circle(Vector2(x,y),1.5,Color(0.90,0.82,0.40,0.20+0.22*sin(time*1.4+i)))
	# Contact shadows place every actor on the same stone floor.
	for pair in [[Vector2(hero_x,468),36.0],[Vector2(fox_x,481),34.0],[Vector2(840,461)+guardian_offset,104.0]]:
		background_node.draw_set_transform(pair[0],0,Vector2(1,0.2))
		background_node.draw_circle(Vector2.ZERO,pair[1],Color(0.01,0.04,0.05,0.45))
	background_node.draw_set_transform(Vector2.ZERO)
	if portal > 0:
		for i in range(14):
			var x = 803+i*10
			background_node.draw_line(Vector2(x,175),Vector2(x+(i-7)*12,466),Color(0.8,0.93,0.62,portal*0.07),8)

func draw_effects() -> void:
	if cutin > 0:
		overlays.draw_colored_polygon(PackedVector2Array([Vector2(0,134),Vector2(475,134),Vector2(412,585),Vector2(0,585)]),Color(0.025,0.10,0.13,cutin*0.76))
		overlays.draw_line(Vector2(475,134),Vector2(412,585),Color(0.69,0.90,0.74,cutin*0.65),3)
	for side in range(2):
		if crystal_visibility > 0:
			var center = Vector2(610 if side == 0 else 1050,579)
			overlays.draw_set_transform(center,0,Vector2(1,0.22))
			overlays.draw_arc(Vector2.ZERO,141,0,TAU,80,Color(0.4,0.8,0.7,0.24*crystal_visibility),2,true)
			overlays.draw_set_transform(Vector2.ZERO)
		if hover_side == side:
			overlays.draw_arc(SHIELDS[side],122,0,TAU,90,Color(0.94,0.84,0.49,0.7),3,true)
	if charge > 0:
		for i in range(18):
			var a = time*4+i*TAU/18
			var radius = 70*(1-charge)+20
			var pos = Vector2(hero_x+40,373)+Vector2(cos(a)*radius,sin(a)*radius*0.55)
			overlays.draw_circle(pos,2+charge*2,Color(0.52,0.94,0.83,charge))
	if spell_progress >= 0 and spell_progress <= 1:
		for side in range(2):
			var start = Vector2(hero_x+54,368) if side == 0 else Vector2(fox_x+42,427)
			var finish = SHIELDS[side]
			for j in range(14):
				var u = clampf(spell_progress-j*0.012,0,1)
				var p = start.lerp(finish,u)+Vector2(0,-sin(u*PI)*100)
				overlays.draw_circle(p,9*(1-j/15.0),Color(0.44,0.94,0.83,(1-j/15.0)*0.8))
	if impact > 0:
		for side in range(2):
			var color = TEAL if impact_success else Color("f0a177")
			color.a = 1-impact
			overlays.draw_arc(SHIELDS[side],22+impact*135,0,TAU,80,color,4,true)
			for i in range(12):
				var a = i*TAU/12+side
				var p = SHIELDS[side]+Vector2(cos(a),sin(a))*(20+impact*105)
				overlays.draw_circle(p,3*(1-impact),color)
	if medal_alpha > 0:
		for i in range(16):
			var a = i*TAU/16+time*0.12
			var p = Vector2(850,307)+Vector2(cos(a),sin(a))*118
			overlays.draw_line(Vector2(850,307),p,Color(0.96,0.81,0.43,0.13*medal_alpha),5)

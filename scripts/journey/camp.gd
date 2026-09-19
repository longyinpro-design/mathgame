extends Node2D

const MAP = preload("res://assets/source/world-map-v1.png")
const FOX = preload("res://assets/runtime/fox-v2.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
const OBJECTS = preload("res://assets/runtime/v3/objects.png")
const TEAL = Color("8fd4b1")
const GOLD = Color("e7c887")
var time = 0.0
var progress = 0
var returned = false
var page = "camp"
var fox_hop = 0.0

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("d6d0b7"))
	draw_texture_rect(MAP,Rect2(180,-35,1100,733.333),false)
	# A quiet ink wash leaves the map intact and gives the UI readable space.
	for x in range(0,1280,8):
		var alpha = lerpf(0.97,0.04,smoothstep(290,780,x))
		draw_rect(Rect2(x,0,8,720),Color(0.045,0.10,0.11,alpha))
	for y in range(0,100,4):
		draw_rect(Rect2(0,y,1280,4),Color(0.035,0.08,0.09,0.40*(1-y/100.0)))
	for y in range(570,720,4):
		draw_rect(Rect2(0,y,1280,4),Color(0.035,0.08,0.09,0.88*(y-570)/150.0))
	if page == "camp":
		# This small route focuses the authored first journey within the larger map.
		var route = [Vector2(744,355),Vector2(633,431),Vector2(475,511)]
		for i in range(2):
			for j in range(12):
				var p = route[i].lerp(route[i+1],j/12.0)
				draw_circle(p,2.0,Color(0.91,0.78,0.49,0.64))
		for i in range(3):
			var p = route[i]
			draw_circle(p,11,Color("173c36"))
			draw_arc(p,11,0,TAU,32,GOLD,2,true)
			if i <= progress: draw_circle(p,5,TEAL)
		var marker = route[mini(progress+1,2)] if not returned else route[0]
		draw_arc(marker,17+sin(time*2)*2,0,TAU,40,Color(0.91,0.78,0.49,0.7),1,true)
		# The camp seedling visibly grows after each concrete story milestone.
		var seed = Vector2(804,399)
		draw_set_transform(seed,0,Vector2(1,0.25)); draw_circle(Vector2.ZERO,22,Color(0.10,0.15,0.08,0.5)); draw_set_transform(Vector2.ZERO)
		var height = 9+progress*12+(12 if returned else 0)
		draw_line(seed,seed-Vector2(0,height),Color("456c3d"),4)
		for i in range(progress+1):
			var p = seed-Vector2(0,10+i*12)
			draw_colored_polygon(PackedVector2Array([p,p+Vector2(-17,-11),p+Vector2(-9,-15),p+Vector2(1,-4)]),Color("85ac56"))
			draw_colored_polygon(PackedVector2Array([p-Vector2(0,5),p+Vector2(15,-16),p+Vector2(20,-9),p]),Color("b2c971"))
		if returned:
			for i in range(5):
				var p = seed-Vector2(0,height)+Vector2(cos(i*TAU/5),sin(i*TAU/5))*6
				draw_circle(p,5,Color("edd28b"))
		# Familiar companions anchor the UI in the same world as the playable scenes.
		draw_actor(HERO,Rect2(1200,10,235,334),Vector2(113,502),120)
		draw_actor(FOX,Rect2(200,190,920,880),Vector2(218,512-fox_hop),90)
		if progress > 1:
			draw_texture_rect_region(OBJECTS,Rect2(225,470-fox_hop,12,20),Rect2(778,664,323,520))
	else:
		draw_rect(Rect2(0,94,1280,568),Color(0.04,0.09,0.10,0.48))
	for i in range(16):
		var p = Vector2(470+fposmod(i*83+time*(2+i%3),785),154+fposmod(i*59+sin(time+i)*7,425))
		draw_circle(p,1.4,Color(0.97,0.84,0.50,0.20+0.14*sin(time*1.3+i)))

func draw_actor(texture: Texture2D, region: Rect2, foot: Vector2, height: float) -> void:
	var width = region.size.x/region.size.y*height
	draw_set_transform(foot,0,Vector2(1,0.20)); draw_circle(Vector2.ZERO,width*0.35,Color(0,0,0,0.28)); draw_set_transform(Vector2.ZERO)
	draw_texture_rect_region(texture,Rect2(foot-Vector2(width/2,height+sin(time*2)*1.2),Vector2(width,height)),region)

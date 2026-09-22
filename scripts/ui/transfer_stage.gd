extends "res://scripts/ui/presentation_layer.gd"
const UIStyle = preload("res://scripts/cargo/skin.gd")
const OBJECTS = preload("res://assets/runtime/v3/objects.png")
const CRYSTAL = preload("res://assets/runtime/forest/fx/crystal-idle.png")
const CRYSTAL_LIT = preload("res://assets/runtime/forest/fx/crystal-lit.png")
# Anchors in the original village painting, in the shared 1280 x 720 viewport.
const DOORS = [Rect2(73,343,103,104),Rect2(570,383,83,89),Rect2(1007,412,78,73)]
const LABELS = [Vector2(60,350),Vector2(550,390),Vector2(984,397)]
const ROAD_X = [126.0,612.0,1048.0]
const VILLAGE_FEET = {"hero":Vector2(365,537),"acheng":Vector2(438,539),"mossling":Vector2(812,537),"feather":Vector2(898,538)}
var values: Array = [8,8,8]:
	set(value):
		values = value
		queue_redraw()
var selected = -1:
	set(value):
		selected = value
		queue_redraw()
var warehouse = false:
	set(value):
		warehouse = value
		queue_redraw()
var flight = -1.0:
	set(value):
		flight = value
		queue_redraw()
var from_index = 0:
	set(value):
		from_index = value
		queue_redraw()
var to_index = 1:
	set(value):
		to_index = value
		queue_redraw()
var quantity = 1:
	set(value):
		quantity = value
		queue_redraw()
var band_size = 0:
	set(value):
		band_size = value
		queue_redraw()
var marks: Array = []:
	set(value):
		marks = value
		queue_redraw()
const CENTERS = [Vector2(266,408),Vector2(631,408),Vector2(996,408)]

func _draw() -> void:
	if warehouse:
		_draw_warehouses(); return
	for index in range(3):
		var center: Vector2 = CENTERS[index]
		draw_texture_rect_region(OBJECTS,Rect2(center-Vector2(142,204),Vector2(284,294)),Rect2(764,29,354,577),Color("b0c6a5"))
		draw_circle(center-Vector2(0,19),77,Color(0.10,0.25,0.23,0.87))
		var count = int(values[index])
		for item in range(count):
			var columns = 6
			var point = center+Vector2((item%columns-2.5)*22,(item/columns)*22-64)
			var lit = index == selected
			var texture = CRYSTAL_LIT if lit else CRYSTAL
			var sway = sin(item*1.7)*2
			draw_texture_rect_region(texture,Rect2(point+Vector2(-9,-13+sway),Vector2(19,25)),Rect2(0,0,texture.get_width(),texture.get_height()))
			if band_size > 0 and (item+1)%band_size == 0: draw_arc(point,11,PI*0.1,PI*1.8,16,Color("e3c36d"),1.5)
		if index == selected: draw_arc(center-Vector2(0,16),91,0,TAU,48,Color("e9d085"),3)
		if index in marks:
			var point = center+Vector2(112,-109)
			draw_colored_polygon(PackedVector2Array([point,point+Vector2(22,-7),point+Vector2(22,25),point+Vector2(11,16),point+Vector2(0,25)]),Color("e9ca7f"))
	if flight >= 0:
		var point: Vector2 = CENTERS[from_index].lerp(CENTERS[to_index],flight)-Vector2(0,90+sin(flight*PI)*74)
		for i in range(quantity):
			var offset = Vector2((i%5-2)*13,(i/5)*13)
			draw_texture_rect_region(CRYSTAL_LIT,Rect2(point+offset-Vector2(8,10),Vector2(17,22)),Rect2(0,0,CRYSTAL_LIT.get_width(),CRYSTAL_LIT.get_height()))

func road_point(progress: float) -> Vector2:
	return Vector2(lerpf(ROAD_X[from_index],ROAD_X[to_index],progress),532)

func visible_values() -> Array:
	var counts = values.duplicate()
	if warehouse and flight >= 0: counts[from_index] -= quantity
	return counts

func grain_bag(foot: Vector2) -> void:
	# Small pixel silhouettes use the sacks' warm highlights and shaded seams.
	var outline = PackedVector2Array([Vector2(-7,0),Vector2(-9,-3),Vector2(-8,-11),Vector2(-4,-19),Vector2(-5,-23),Vector2(4,-24),Vector2(3,-19),Vector2(8,-11),Vector2(9,-3),Vector2(6,0)])
	for i in outline.size(): outline[i] += foot
	draw_colored_polygon(outline,Color("aa8652"))
	draw_line(foot+Vector2(-6,-4),foot+Vector2(-5,-12),Color("d1b379"),3)
	draw_line(foot+Vector2(6,-4),foot+Vector2(4,-14),Color("735736"),2)
	draw_line(foot+Vector2(-4,-19),foot+Vector2(4,-19),Color("584730"),2)
	draw_line(foot+Vector2(-6,-2),foot+Vector2(6,-2),Color("775e3c"),2)

func _draw_warehouses() -> void:
	var counts = visible_values()
	for i in range(3):
		var rect: Rect2 = DOORS[i]
		if i == selected:
			draw_rect(rect.grow(3),Color("e5c477"),false,2)
			draw_line(rect.position+Vector2(-7,0),rect.position+Vector2(-7,rect.size.y),Color("e5c477"),2)
		var label = Rect2(LABELS[i],Vector2(128,28))
		draw_rect(label,Color(0.12,0.15,0.10,0.88))
		draw_string(UIStyle.face(),label.position+Vector2(8,21),["甲仓 · ","乙仓 · ","丙仓 · "][i]+str(counts[i])+"袋",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("f0dfb0"))
		if i in marks: draw_circle(label.position+Vector2(120,5),4,Color("e9ca7f"))
		# Grouping remains a view tool; it never changes or solves the grain count.
		if band_size > 0:
			draw_string(UIStyle.face(),label.position+Vector2(2,-7),"%d组 + %d袋" % [int(counts[i])/band_size,int(counts[i])%band_size],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f0dfb0"))
	if flight < 0: return
	var point = road_point(flight)
	draw_set_transform(point,0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,27,Color(0.05,0.08,0.04,0.32)); draw_set_transform(Vector2.ZERO)
	for x in [-15,15]:
		draw_circle(point+Vector2(x,-3),5,Color("403c2c"))
		draw_circle(point+Vector2(x,-3),2,Color("af9763"))
	for i in range(quantity): grain_bag(point+Vector2((i%4-1.5)*12,-10-(i/4)*13))
	draw_rect(Rect2(point+Vector2(-26,-11),Vector2(52,5)),Color("78613f"))
	draw_line(point+Vector2(-26,-10),point+Vector2(-37,-23),Color("a38a5b"),3)

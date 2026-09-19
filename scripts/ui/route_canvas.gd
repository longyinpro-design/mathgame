extends Control
signal step_requested(direction: String)
var columns = 3
var rows = 2
var path = ""
var other_path = ""
var stone = Vector2i(-1,-1)
var enabled = true
var small = false
var tag = -1
var walk_pair: Array = []
var walk_t = -1.0

func point(x: int, y: int) -> Vector2:
	var padding = 12.0 if small else 30.0
	return Vector2(padding+x*(size.x-2*padding)/columns,size.y-padding-y*(size.y-2*padding)/rows)

func _draw() -> void:
	if not small:
		preload("res://scripts/ui/scene_materials.gd").surface(self,Rect2(Vector2.ZERO,size),"earth",Color("d1d3a8"))
	for x in range(columns+1):
		for y in range(rows+1):
			var p = point(x,y)
			if x < columns: draw_line(p,point(x+1,y),Color("887452"),1.4 if small else 10)
			if y < rows: draw_line(p,point(x,y+1),Color("887452"),1.4 if small else 10)
			draw_circle(p,2 if small else 9,Color("675e42"))
			if not small: draw_circle(p,5,Color("c0bc8e"))
		if not small: draw_string(get_theme_default_font(),point(x,0)+Vector2(-5,23),str(x),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("574f37"))
	if not small:
		for y in range(1,rows+1): draw_string(get_theme_default_font(),point(0,y)+Vector2(-21,5),str(y),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("574f37"))
	if stone.x >= 0:
		var p = point(stone.x,stone.y)
		draw_colored_polygon(PackedVector2Array([p+Vector2(-17,12),p+Vector2(-22,-5),p+Vector2(-7,-21),p+Vector2(17,-14),p+Vector2(22,9)]),Color("777a69"))
	if other_path != "": _path(other_path,Color("b38b58"))
	_path(path,Color("487e72"))
	if walk_t >= 0.0 and walk_pair.size() == 2:
		for i in range(2):
			var route: String = walk_pair[i]
			var total = maxf(1.0,float(route.length()))
			var progress = clampf(walk_t*total-float(i)*0.35,0.0,float(route.length()))
			var steps = int(progress)
			var frac = progress-float(steps)
			var x = 0; var y = 0
			for s in range(mini(steps,route.length())):
				x += 1 if route[s] == "R" else 0; y += 1 if route[s] == "U" else 0
			var p0 = point(x,y)
			var p1 = p0
			if steps < route.length():
				var nx = x; var ny = y
				nx += 1 if route[steps] == "R" else 0; ny += 1 if route[steps] == "U" else 0
				p1 = point(nx,ny)
			var mark = p0.lerp(p1,frac)
			var color = Color("e9c05f") if i == 0 else Color("7fd0c0")
			draw_circle(mark,10,Color(color.r,color.g,color.b,0.35))
			draw_circle(mark,6,color)
	if not small:
		draw_circle(point(0,0),12,Color("c48f56")); draw_circle(point(columns,rows),12,Color("7d9862"))
		var end = Vector2i(path.count("R"),path.count("U")); var p = point(end.x,end.y)
		draw_circle(p,13,Color("e8c970")); draw_arc(p,18,0,TAU,24,Color("fff0c3"),2)
		for next in [end+Vector2i(1,0),end+Vector2i(0,1)]:
			if next.x <= columns and next.y <= rows: draw_arc(point(next.x,next.y),15,0,TAU,24,Color("557f63"),2)
		if tag >= 0:
			var flag = point(end.x,end.y)+Vector2(-25,-8)
			draw_line(flag,flag-Vector2(0,35),Color("745e3c"),3)
			draw_colored_polygon(PackedVector2Array([flag-Vector2(0,35),flag+Vector2(32,-30),flag+Vector2(0,-13)]),Color("d7ad55"))
			draw_string(get_theme_default_font(),flag+Vector2(6,-18),str(tag),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("453f29"))

func _path(value: String, color: Color) -> void:
	var x = 0; var y = 0
	for direction in value:
		var start = point(x,y); x += 1 if direction == "R" else 0; y += 1 if direction == "U" else 0
		draw_line(start,point(x,y),color,3 if small else 8,true)

func _gui_input(event: InputEvent) -> void:
	if not enabled or small: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var end = Vector2i(path.count("R"),path.count("U"))
		for direction in ["R","U"]:
			var next = end+(Vector2i(1,0) if direction == "R" else Vector2i(0,1))
			if next.x <= columns and next.y <= rows and event.position.distance_to(point(next.x,next.y)) < 28:
				step_requested.emit(direction); accept_event(); return

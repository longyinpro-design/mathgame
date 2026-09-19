extends Node2D
const Rules = preload("res://scripts/cargo/rules.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const FOX = preload("res://assets/runtime/fox-v2.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
var background: Texture2D
var props: Texture2D
const REGIONS = [Rect2(18,180,565,235),Rect2(681,184,275,238),Rect2(1136,74,310,382),Rect2(78,531,390,441),Rect2(625,538,328,410),Rect2(1147,619,305,307)]
var state = Rules.fresh()
var lift = 0.0
var time = 0.0
var selected = -1
var hovered = -1
var target = -1
var dragging = false
var pointer = Vector2.ZERO
var page = "camp"
var font: Font
var offsets: Dictionary = {}
var show_direction = false
var limits: Dictionary = {}
var moving = false
var timber: Texture2D
var render_people = true
var story_view = false
var render_background = true
const LOWER_Y = 592.0
const UPPER_Y = 263.0
func _ready() -> void:
	props = load("res://assets/runtime/cargo-props-v5.png")
	timber = UIStyle.plank()
	font = UIStyle.face()
	background = load("res://assets/runtime/treetop-v5.png")
func _process(delta: float) -> void:
	time += delta; queue_redraw()
func basket_position(side: int) -> Vector2:
	return Vector2(510,lerpf(LOWER_Y,UPPER_Y,lift)) if side == 1 else Vector2(805,lerpf(UPPER_Y,LOWER_Y,lift))
func zone_rect(location: int) -> Rect2:
	if location == 0: return Rect2(80,478,290,136)
	if location == 3: return Rect2(968,193,276,137)
	return Rect2(basket_position(location)-Vector2(112,99),Vector2(224,113))
func item_count() -> int:
	return state.get("weights",Rules.WEIGHTS).size()
func item_position(item: int) -> Vector2:
	var loc = int(state.places[item]); var items: Array[int] = []
	for i in item_count():
		if state.places[i] == loc: items.append(i)
	var index = items.find(item)
	var columns = 3
	var center = Vector2(224,LOWER_Y) if loc == 0 else Vector2(1100,UPPER_Y)
	if loc in [1,2]: center = basket_position(loc)-Vector2(0,4)
	var count = mini(columns,items.size())
	return center+Vector2((index%columns-(count-1)*0.5)*65,-floori(index/float(columns))*65)
func hit_item(p: Vector2) -> int:
	for i in range(item_count()-1,-1,-1):
		if Rect2(item_position(i)-Vector2(29,59),Vector2(58,66)).has_point(p): return i
	return -1
func hit_zone(p: Vector2) -> int:
	for loc in [1,2,0,3]:
		if zone_rect(loc).has_point(p): return loc
	return -1
func rounded(rect: Rect2, color: Color, radius: int = 12, border: Color = Color.TRANSPARENT) -> void:
	var s = StyleBoxFlat.new(); s.bg_color = color; s.set_corner_radius_all(radius)
	if border.a > 0: s.set_border_width_all(2); s.border_color = border
	draw_style_box(s,rect)
func words(value: String, p: Vector2, size_px: int = 18, color: Color = UIStyle.INK) -> void:
	draw_string(font,p,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)
func actor(tex: Texture2D, region: Rect2, foot: Vector2, height: float, alpha: float = 1) -> void:
	var width = region.size.x/region.size.y*height
	draw_texture_rect_region(tex,Rect2(foot-Vector2(width/2,height),Vector2(width,height)),region,Color(1,1,1,alpha))
func _draw() -> void:
	if background == null or font == null: return
	if render_background: draw_texture_rect(background,Rect2(0,0,1280,720),false)
	# Gentle edge shade supports text without enclosing the whole scene in panels.
	for y in range(0,156,4): draw_rect(Rect2(0,y,1280,4),Color(0.035,0.09,0.07,0.82*(1-y/156.0)))
	for y in range(610,720,4): draw_rect(Rect2(0,y,1280,4),Color(0.025,0.075,0.055,0.92*(y-610)/110.0))
	if page not in ["cargo","camp"]:
		draw_rect(Rect2(0,0,1280,720),Color(0.025,0.045,0.03,0.65))
	else:
		# Two docks, one continuous rope: the math is visible in the mechanism.
		# Both unloading areas use the original lower bridge and upper treehouse deck.
		# The pulley attaches to the existing branch rather than an unrelated flat bar.
		for x in [510,805]:
			for dx in [-5,0,5]: draw_line(Vector2(x+dx,118),Vector2(x+dx,151),Color("b9a578"),2)
		if page == "cargo":
			draw_texture_rect(timber,Rect2(1155,529,22,93),false)
			draw_texture_rect_region(props,Rect2(1137,540,60,60),REGIONS[5])
			draw_line(Vector2(1167,570),Vector2(1194,546 if moving else 585),Color("d0b17a"),7,true)
			draw_circle(Vector2(1194,546 if moving else 585),7,Color("6b5032"))
		draw_line(Vector2(510,169),Vector2(805,169),Color("d6b578"),4,true)
		for side in [1,2]:
			var x = basket_position(side).x
			draw_line(Vector2(x,170),basket_position(side)-Vector2(0,105),Color("403a25"),7,true)
			draw_line(Vector2(x-1,170),basket_position(side)-Vector2(1,105),Color("d9bc83"),3,true)
			draw_set_transform(Vector2(x,169),lift*4)
			draw_texture_rect_region(props,Rect2(-25,-25,50,50),REGIONS[5])
			draw_set_transform(Vector2.ZERO)
			basket(side)
		if page == "cargo" and selected >= 0:
			for loc in range(4):
				if Rules.can_move(state,selected,loc):
					var r = zone_rect(loc)
					rounded(r,Color(0.73,0.88,0.61,0.10 if target != loc else 0.24),15,Color("e6d39a") if target == loc else Color("8fba85"))
		for i in item_count():
			if not render_people and i < 2: continue
			if not (dragging and i == selected): item(i,item_position(i)+offsets.get(i,Vector2.ZERO),i == selected or i == hovered)
		if dragging and selected >= 0: item(selected,pointer+Vector2(0,22),true)
		if state.complete:
			for i in range(2): sprout(Vector2(1214+i*23,UPPER_Y-2),true)
		elif state.places[2] == 3: sprout(Vector2(1235,UPPER_Y-2),false)
	for i in range(20):
		var p = Vector2(fposmod(i*131+time*(5+i%4),1280),180+fposmod(i*47+sin(time+i)*10,400))
		draw_circle(p,1.5,Color(1,0.90,0.62,0.15+0.12*sin(time+i)))
func basket(side: int) -> void:
	var p = basket_position(side)
	for dx in [-99,99]:
		draw_line(p-Vector2(0,105),p+Vector2(dx,-9),Color("383c29"),6,true)
		draw_line(p-Vector2(0,105),p+Vector2(dx,-9),Color("c6ab76"),2,true)
	draw_texture_rect_region(props,Rect2(p-Vector2(117,23),Vector2(234,73)),REGIONS[0])
	if page != "cargo": return
	var w = Rules.weight(state,side)
	var count = state.places.count(side)
	draw_texture_rect(timber,Rect2(p+Vector2(-78,12),Vector2(156,27)),false)
	if limits.is_empty():
		words("载重 "+str(w),p+Vector2(-29,32),18)
	elif limits.has("max_weight"):
		words("载重 %d/%d · %d/%d件" % [w,int(limits.max_weight),count,int(limits.max_items)],p+Vector2(-75,32),17)
	else:
		words("已装 %d/%d 件 · 载重 %d" % [count,int(limits.max_items),w],p+Vector2(-72,32),17)
	var after = state
	if selected >= 0 and Rules.can_move(state,selected,target): after = Rules.moved(state,selected,target)
	var predicted = Rules.weight(after,side)
	if predicted != w:
		words(str(w)+" → "+str(predicted),p+Vector2(-28,68),18,UIStyle.GOLD)
	if show_direction and not state.complete:
		var difference = Rules.weight(after,1)-Rules.weight(after,2)
		if difference != 0:
			var down = (difference > 0) == (side == 1)
			var a = p+Vector2(-136 if side == 1 else 136,-50)
			var direction = 1 if down else -1
			draw_line(a-Vector2(0,19*direction),a+Vector2(0,11*direction),Color("f0dc9c"),3,true)
			draw_colored_polygon(PackedVector2Array([a+Vector2(-7,8*direction),a+Vector2(7,8*direction),a+Vector2(0,20*direction)]),Color("f0dc9c"))
func item(i: int, p: Vector2, active: bool) -> void:
	if active:
		draw_set_transform(p-Vector2(0,6),0,Vector2(1,0.25)); draw_circle(Vector2.ZERO,31,Color(0.95,0.85,0.54,0.6)); draw_set_transform(Vector2.ZERO)
	p.y -= 7 if active else 0
	var goal = Rules.goal_count(state)
	var weights: Array = Rules.item_weights(state)
	if i == 0: actor(FOX,Rect2(200,190,920,880),p,58)
	elif i == 1: actor(HERO,Rect2(1200,10,235,334),p,79)
	elif i == 2:
		draw_texture_rect_region(props,Rect2(p-Vector2(22,54),Vector2(44,55)),REGIONS[4])
	elif i == goal-1:
		# A further up-item (the mail parcel) rides without a sprite region.
		draw_rect(Rect2(p-Vector2(21,40),Vector2(42,40)),Color("a5834f"),true)
		draw_rect(Rect2(p-Vector2(21,40),Vector2(42,40)),Color("6a5334"),false,2.0)
		draw_line(p-Vector2(21,20),p+Vector2(21,0),Color("6a5334"),3)
		draw_line(p+Vector2(21,20),p-Vector2(21,0),Color("6a5334"),3)
	else:
		# Counterweights map size to their real heft: heaviest first.
		var sizes = {2:Vector2(50,44),3:Vector2(52,64),4:Vector2(59,67),5:Vector2(66,72)}
		var size_value: Vector2 = sizes.get(weights[i],Vector2(52,64))
		var region_index: int = clampi(weights[i]-1,1,3)
		draw_texture_rect_region(props,Rect2(p-Vector2(size_value.x/2,size_value.y),size_value),REGIONS[region_index])
	if page == "cargo" and i >= 2:
		var number = str(weights[i])
		draw_string_outline(font,p+Vector2(-6,-12),number,HORIZONTAL_ALIGNMENT_LEFT,-1,18,1,Color("313629"))
		words(number,p+Vector2(-6,-12),18,Color("f4e3b7"))
func sprout(p: Vector2, flower: bool) -> void:
	draw_line(p,p-Vector2(0,24),Color("72974e"),3,true)
	draw_colored_polygon(PackedVector2Array([p-Vector2(0,10),p-Vector2(15,23),p-Vector2(10,25),p-Vector2(0,17)]),Color("a7be61"))
	draw_colored_polygon(PackedVector2Array([p-Vector2(0,15),p+Vector2(12,-30),p+Vector2(18,-25),p-Vector2(0,8)]),Color("ced88b"))
	if flower:
		for j in range(5): draw_circle(p-Vector2(0,28)+Vector2(cos(j*TAU/5),sin(j*TAU/5))*5,4,Color("f0d697"))

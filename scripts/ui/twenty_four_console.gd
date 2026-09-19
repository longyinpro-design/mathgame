extends Node2D
# The mill's 24-point console: gears and an energy dial drawn as machine parts.
# Rotation and needle carry the arithmetic: one turn per combined pair, needle
# easing toward the current single-card value, 24 marked as the gold tooth.
const GOLD_PLATE = Color("c9ab63")
const BRASS = Color("93763d")
const FACE = Color("20301f")
const INK = Color("f1e5ca")
const GOLD = Color("e4cd80")
const BURST = preload("res://assets/runtime/forest/fx/burst.png")
const UIStyle = preload("res://scripts/cargo/skin.gd")
var story_mode = false
var steps = 0
var target_value = 0.0
var shown_value = 0.0
var done = false
var clock = 0.0
const DIAL = Vector2(1146,297)
const GEAR_A = Vector2(1143,410)
const GEAR_B = Vector2(1184,444)

func _process(delta: float) -> void:
	clock += delta
	shown_value = lerpf(shown_value,target_value,minf(1.0,delta*6.0))
	queue_redraw()

func _draw() -> void:
	# Close-up of the painted mill control, with no artificial support platform.
	draw_line(Vector2(1081,458),GEAR_A,BRASS,15)
	draw_line(GEAR_A,GEAR_B,Color("484938"),8)
	draw_line(Vector2(1090,291),DIAL,BRASS,12)
	var case_style = UIStyle.dark_style(); case_style.bg_color = Color("334438")
	draw_style_box(case_style,Rect2(314,208,780,345))
	preload("res://scripts/ui/scene_materials.gd").surface(self,Rect2(319,213,770,335),"metal",Color("697765"))
	draw_rect(Rect2(323,214,761,330),Color(0.12,0.19,0.15,0.62))
	for x in [326,1080]:
		for y in [220,540]: draw_circle(Vector2(x,y),4,BRASS)
	for i in range(4):
		var p = Vector2(335+i*184,255)
		draw_rect(Rect2(p,Vector2(160,61)),Color("1e2b24"))
		draw_line(p+Vector2(0,62),p+Vector2(160,62),BRASS,4)
		if story_mode:
			draw_style_box(UIStyle.sign_style(),Rect2(p+Vector2(12,5),Vector2(136,49)))
			draw_string(UIStyle.face(),p+Vector2(65,38),str([1,4,5,9][i]),HORIZONTAL_ALIGNMENT_LEFT,-1,31,UIStyle.INK)
	for x in [483,727]:
		draw_rect(Rect2(x,403,164,84),Color("182d24"))
		draw_rect(Rect2(x,403,164,84),BRASS,false,3)
	draw_line(Vector2(565,487),Vector2(565,511),BRASS,5)
	draw_line(Vector2(809,487),Vector2(809,511),BRASS,5)
	var creep = clock*0.55 if done else 0.0
	gear(GEAR_A,24,8,steps*0.62+creep)
	gear(GEAR_B,15,7,-steps*0.95-creep*1.6)
	dial()
	if done:
		for ring in range(4): draw_circle(DIAL,30+ring*10+sin(clock*3.0)*3,Color(0.9,0.78,0.42,0.05))
		draw_texture_rect_region(BURST,Rect2(DIAL-Vector2(34,34),Vector2(68,68)),Rect2(12,10,BURST.get_width()-24,BURST.get_height()-20),Color(1,1,1,0.85))

func gear(center: Vector2, radius: float, teeth: int, angle: float) -> void:
	for i in range(teeth):
		var a = angle+TAU*i/teeth
		var dir = Vector2(cos(a),sin(a))
		var side = dir.orthogonal()*radius*0.30
		var outer = center+dir*(radius+6)
		draw_colored_polygon(PackedVector2Array([center+dir*radius+side,center+dir*radius-side,outer-side,outer+side]),BRASS)
	draw_circle(center,radius,GOLD_PLATE)
	draw_circle(center,radius-4,FACE)
	draw_circle(center,5,BRASS)

func dial() -> void:
	draw_circle(DIAL,30,GOLD_PLATE)
	draw_circle(DIAL,26,FACE)
	for i in range(7):
		var a = PI*0.75+i*PI*1.5/6.0
		var tick = Vector2(cos(a),sin(a))
		var mark = GOLD if i == 4 else Color(0.62,0.6,0.45)
		var length_value = 8.0 if i != 4 else 10.0
		draw_line(DIAL+tick*14,DIAL+tick*(14+length_value),mark,3.0 if i != 4 else 4.0)
	var frac = clampf(shown_value/30.0,0.0,1.0)
	var needle = PI*0.75+frac*PI*1.5
	draw_line(DIAL-Vector2(cos(needle),sin(needle))*6,DIAL+Vector2(cos(needle),sin(needle))*20,GOLD,3)
	draw_circle(DIAL,4,GOLD_PLATE)
	draw_string(UIStyle.face(),DIAL+Vector2(-30,48),"24点",HORIZONTAL_ALIGNMENT_LEFT,-1,17,GOLD)

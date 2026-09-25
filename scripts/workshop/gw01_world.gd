extends Node2D
const Rules = preload("res://scripts/workshop/gw01_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/mistimed-dock-stage-v1.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
const FOX = preload("res://assets/runtime/fox-v2.png")
const TRAY = preload("res://assets/runtime/workshop/gw01/tray.tres")
const SPINDLE = preload("res://assets/runtime/workshop/gw01/spindle.tres")
const LIFT = preload("res://assets/runtime/workshop/gw01/lift.tres")
const CART = preload("res://assets/runtime/workshop/gw01/cart.tres")
const BELL = preload("res://assets/runtime/workshop/gw01/bell.tres")
const DADA = preload("res://assets/runtime/workshop/gw01/dada_idle.tres")
const Batch2 = preload("res://scripts/workshop/batch2.gd")
var scene_id = "dock"
var state = Rules.fresh()
var selected = -1
var progress = 0.0
var land_place = ""
var land_progress = 1.0
# 宿主契约：暂停/失焦时 level_host 会写这里。GW01 的动效全部由 scene 的 progress 驱动，
# 世界本身没有自走动画，所以目前只写不读；删掉它会让宿主的赋值报错。
var presentation_paused = false
var font: Font
var moving = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()

func tray_foot(i: int) -> Vector2:
	if i == 0 and state.stage in ["delivery","aftermath","complete"]:
		var p = progress if state.stage == "delivery" else 1.0
		return Vector2(360,448).lerp(lift_foot()-Vector2(0,25),smoothstep(0,0.45,p))
	return Vector2(360+i*240,448)

func lift_foot() -> Vector2:
	var rise = 0.0
	if state.stage == "approach": rise = sin(progress*PI)*80.0
	if state.stage == "delivery": rise = smoothstep(0.48,1,progress)*60.0
	if state.stage in ["aftermath","complete"]: rise = 60.0
	return Vector2(661,334-rise)

func cart_foot() -> Vector2:
	var x = 938.0
	if state.stage in ["approach","delivery"]: x -= sin(progress*PI)*370
	return Vector2(x,357)

func tray_rect(i: int) -> Rect2:
	return Rect2(Vector2(248+i*240,345),Vector2(224,141))
func source_foot(index: int) -> Vector2:
	return Vector2(50+(index%6)*20,373+floori(index/6.0)*22)
func target_foot(target: int, index: int) -> Vector2:
	if target == -1: return source_foot(index)
	return tray_foot(target)+Vector2(-74+(index%8)*21,-20-floori(index/8.0)*22)

func begin_land(previous: Dictionary) -> void:
	land_place = ""; moving = []
	if previous.stage not in ["puzzle","trial"] or state.stage not in ["puzzle","trial"]: return
	var before = Rules.displayed(previous); before.append(Rules.stock(previous))
	var after = Rules.displayed(state); after.append(Rules.stock(state))
	var origins = []; var destinations = []
	for slot in range(4):
		var target = -1 if slot == 3 else slot
		for index in range(after[slot],before[slot]): origins.append(target_foot(target,index))
		for index in range(before[slot],after[slot]): destinations.append({"target":target,"index":index})
	assert(origins.size() == destinations.size())
	for i in range(origins.size()):
		var dest = destinations[i]
		moving.append({"target":dest.target,"index":dest.index,"from":origins[i],"to":target_foot(dest.target,dest.index)})
	if not moving.is_empty(): land_place = "goods"

func hidden(target: int, index: int) -> bool:
	if land_progress >= 1: return false
	for item in moving:
		if item.target == target and item.index == index: return true
	return false

func prop(texture: Texture2D, foot: Vector2, width: float) -> void:
	var dims = Vector2(texture.get_width(),texture.get_height())*width/texture.get_width()
	draw_texture_rect(texture,Rect2(foot-Vector2(dims.x/2,dims.y),dims),false)
func spindle(foot: Vector2, width: float = 12) -> void: prop(SPINDLE,foot,width)
func contact(foot: Vector2, radius: float) -> void:
	draw_set_transform(foot,0,Vector2(1,0.18))
	draw_circle(Vector2.ZERO,radius,Color(0.08,0.1,0.12,0.3))
	draw_set_transform(Vector2.ZERO)
func words(value: String, at: Vector2, size_px: int = 20) -> void:
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,4,Color("21313c"))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,Color("fff0d1"))
func plaque(value: String, rect: Rect2, size_px: int = 19) -> void:
	draw_style_box(ArtStyle.sign_style(),rect)
	words(value,rect.position+Vector2(10,rect.size.y-10),size_px)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	prop(BELL,Vector2(969,221),33)
	var lift = lift_foot()
	draw_line(Vector2(617,83),lift+Vector2(-69,-20),Color("c49c5e"),3)
	draw_line(Vector2(705,83),lift+Vector2(69,-20),Color("c49c5e"),3)
	prop(LIFT,lift,172)
	# 蒸汽是这一关的题眼：升降台一动，平台顶上就冒一股。
	if lift.y < 334.0:
		Batch2.draw_centered(self,"steam",Vector2(lift.x,lift.y-86),134)
	contact(cart_foot(),72); prop(CART,cart_foot(),159)
	# The existing overhead winch carries the loading tray; the lift takes over at contact.
	if state.stage == "delivery" and progress < 0.45:
		var tray = tray_foot(0)
		var hook = tray-Vector2(0,76)
		draw_line(Vector2(661,83),hook,Color("bca375"),3)
		for dx in [-62,62]: draw_line(hook,tray+Vector2(dx,-15),Color("bca375"),3)
	# Counts and movements are derived from the saved initial manifest and verified round.
	for n in range(Rules.stock(state)):
		if not hidden(-1,n): spindle(source_foot(n))
	if state.stage not in ["arrival","approach"]: plaque("待摆 %d 根"%Rules.stock(state),Rect2(25,450,158,38))
	var counts = Rules.displayed(state)
	for i in range(3):
		var foot = tray_foot(i)
		contact(foot,96); prop(TRAY,foot,210)
		for slot in range(counts[i]):
			if not hidden(i,slot): spindle(target_foot(i,slot),9)
		if state.stage not in ["arrival","approach"] and not (i == 0 and state.stage == "delivery"):
			plaque("%s托 · %d 根"%[Rules.NAMES[i],counts[i]],Rect2(foot+Vector2(-100,5),Vector2(200,35)),20)
		if selected == i and state.stage == "puzzle": draw_rect(tray_rect(i),Color("ffe19c"),false,3)
	if state.stage not in ["arrival","approach"]:
		plaque("记录终点：各 8 根",Rect2(25,193,217,37),18)
		if state.stage == "trial":
			plaque("试运行 · 甲 / 乙 / 丙",Rect2(25,235,217,37),18)
			for r in range(state.round+1):
				var row = Rules.after_rounds(state.trays,r)
				plaque(("起始" if r == 0 else "%d轮后"%r)+"  %d / %d / %d"%row,Rect2(25,274+r*36,217,34),17)
	if land_progress < 1:
		for item in moving:
			var p: Vector2 = item.from.lerp(item.to,smoothstep(0,1,land_progress))
			spindle(p-Vector2(0,sin(land_progress*PI)*30))
	# Fixed feet on the same stone plane. Dada's anchor follows its body, not the tail's bounding box.
	var hero = Vector2(120,604); var fox = Vector2(207,612); var dada = Vector2(1170,626)
	contact(hero,24); draw_texture_rect_region(HERO,Rect2(hero-Vector2(36,105),Vector2(73,105)),Rect2(1200,10,235,334))
	contact(fox,29); draw_texture_rect_region(FOX,Rect2(fox-Vector2(37,70),Vector2(74,70)),Rect2(200,190,920,880))
	contact(dada,25); draw_texture_rect(DADA,Rect2(dada-Vector2(262,534)*0.22,Vector2(416,534)*0.22),false)
	words("小岚",hero+Vector2(-22,24),18); words("阿橙",fox+Vector2(-22,24),18); words("嗒嗒",dada+Vector2(-22,24),18)

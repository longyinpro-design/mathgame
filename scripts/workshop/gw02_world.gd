extends Node2D
# GW02 装配间现场：一行 8 片铜料、两台留样盒、一架护栏，压机按排产顺序逐片落下。
# 模具孔位、留样与安装数全部由引擎绘制；母版只提供铜板、压机、盒子与护栏的造型。
const Rules = preload("res://scripts/workshop/gw02_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/assembly-room-stage-v1.png")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const Batch2 = preload("res://scripts/workshop/batch2.gd")
const PLATE = preload("res://assets/runtime/workshop/kit-v1/plate.tres")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const BOX = preload("res://assets/runtime/workshop/kit-v1/box.tres")
const SPINDLE = preload("res://assets/runtime/workshop/kit-v1/spindle.tres")
const SHEET_STEP = 126
const SHEET_FOOT = 560.0
const RAIL_LEFT = 806.0
const RAIL_RIGHT = 1246.0
const RAIL_Y = 292.0
const PRESS_REST = Vector2(168, 470)
const BOX_LEFT = Vector2(884, 468)
const BOX_RIGHT = Vector2(1072, 468)
var scene_id = "assembly"
var state = Rules.fresh()
var selected = Rules.SMALL
var progress = 0.0
var presentation_paused = false
var land_progress = 1.0
var land_place = ""
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()

func begin_land(_previous: Dictionary) -> void:
	land_place = ""; land_progress = 1.0

func sheet_foot(i: int) -> Vector2:
	return Vector2(170.0+i*SHEET_STEP,SHEET_FOOT)
func sheet_rect(i: int) -> Rect2:
	return Rect2(sheet_foot(i)-Vector2(58,100),Vector2(116,120))
func box_foot(index: int) -> Vector2:
	return BOX_LEFT if index == 0 else BOX_RIGHT

# 试压演到第几片：progress 走满时等于 8，表示 8 片都过了一遍。
func processed() -> int:
	if state.stage != "pressing": return Rules.SHEETS
	return clampi(floori(progress*Rules.SHEETS),0,Rules.SHEETS)

# 留样与安装数只在试压之后才公开：摆放期间就把「能安装多少」挂在墙上，
# 等于替玩家做完了「把 11 枚补回来」这一步，那是本关唯一要自己想的事。
func revealed() -> int:
	if state.stage == "pressing": return processed()
	if state.stage in ["delivery","aftermath","complete"]: return Rules.SHEETS
	return 0

# 前 limit 片里，每种模第一次加工的那一片就是封存的那一片。
func sealed_upto(limit: int) -> Dictionary:
	var first = {}
	for i in range(limit):
		var mould = state.molds[i]
		if mould != 0 and not first.has(mould): first[mould] = i
	return first

func installed_upto(limit: int) -> int:
	var first = sealed_upto(limit); var count = 0
	for i in range(limit):
		if state.molds[i] != 0 and first.get(state.molds[i], -1) != i: count += 1
	return count

func press_foot() -> Vector2:
	if state.stage != "pressing": return PRESS_REST
	var index = clampi(floori(progress*Rules.SHEETS),0,Rules.SHEETS-1)
	var local = progress*Rules.SHEETS-index
	return Vector2(sheet_foot(index).x,sheet_foot(index).y-104+sin(local*PI)*42.0)

func prop(texture: Texture2D, foot: Vector2, width: float, tint: Color = Color.WHITE) -> void:
	var dims = Vector2(texture.get_width(),texture.get_height())*width/texture.get_width()
	draw_texture_rect(texture,Rect2(foot-Vector2(dims.x/2,dims.y),dims),false,tint)
func contact(foot: Vector2, radius: float) -> void:
	draw_set_transform(foot,0,Vector2(1,0.18))
	draw_circle(Vector2.ZERO,radius,Color(0.08,0.1,0.12,0.28))
	draw_set_transform(Vector2.ZERO)
func words(value: String, at: Vector2, size_px: int = 20) -> void:
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,4,Color("21313c"))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,Color("fff0d1"))
func plaque(value: String, rect: Rect2, size_px: int = 19) -> void:
	draw_style_box(ArtStyle.sign_style(),rect)
	words(value,rect.position+Vector2(10,rect.size.y-10),size_px)

# 四孔是两行两列；七孔是三行（3+2+2），两种模一眼能分辨。
func hole_offsets(count: int) -> Array:
	if count == Rules.SMALL:
		return [Vector2(-13,-9),Vector2(13,-9),Vector2(-13,9),Vector2(13,9)]
	return [Vector2(-22,-14),Vector2(0,-14),Vector2(22,-14),Vector2(-11,0),Vector2(11,0),Vector2(-11,14),Vector2(11,14)]

func draw_holes(center: Vector2, count: int) -> void:
	if count == 0:
		draw_circle(center,5,Color("6d5a44")); return
	for offset in hole_offsets(count):
		draw_circle(center+offset,6.5,Color("2b2419"))
		draw_circle(center+offset+Vector2(-1.5,-1.5),2.4,Color("6f5a3f"))

func draw_rail(limit: int) -> void:
	draw_rect(Rect2(RAIL_LEFT,RAIL_Y,RAIL_RIGHT-RAIL_LEFT,14),Color("8d6a3c"))
	draw_rect(Rect2(RAIL_LEFT,RAIL_Y,RAIL_RIGHT-RAIL_LEFT,4),Color("c9a566"))
	var filled = installed_upto(limit)
	for slot in range(Rules.SHEETS*4):
		var column = slot%14; var row = floori(slot/14.0)
		var at = Vector2(RAIL_LEFT+18+column*31,RAIL_Y-row*38)
		if slot < filled: prop(SPINDLE,at+Vector2(0,4),14)
		else: draw_circle(at-Vector2(0,12),5,Color(0.16,0.13,0.1,0.35))
	if limit == 0:
		plaque("护栏 · 待试压",Rect2(RAIL_LEFT-6,RAIL_Y+22,268,34),18)
	else:
		plaque("护栏 · 已安装 %d / %d 枚"%[filled,Rules.NEED],Rect2(RAIL_LEFT-6,RAIL_Y+22,268,34),18)

func draw_box(index: int, limit: int) -> void:
	var foot = box_foot(index)
	var mould = Rules.SMALL if index == 0 else Rules.LARGE
	prop(BOX,foot,150)
	if sealed_upto(limit).get(mould,-1) >= 0:
		words("封存 %d 枚"%mould,foot-Vector2(58,108),20)
		prop(SPINDLE,foot-Vector2(0,70),15)
	else:
		words("留样盒空着",foot-Vector2(62,108),19)
	plaque("%d 孔模"%mould,Rect2(foot-Vector2(66,26),Vector2(132,32)),19)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	var limit = revealed()
	var press = press_foot()
	contact(press,86); prop(PRESS,press,168)
	draw_rail(limit)
	for index in range(2): draw_box(index,limit)
	if state.stage not in ["arrival","approach"]:
		plaque("8 片铜料 · 每片一种模",Rect2(24,148,268,34),18)
		plaque("压机 · 逐片试压",Rect2(24,190,190,34),18)
		if state.stage in ["delivery","aftermath","complete"]:
			plaque("已安装 %d 枚 · 需要 %d 枚"%[Rules.installed(state),Rules.NEED],Rect2(24,232,300,34),18)
		for i in range(Rules.SHEETS):
			var foot = sheet_foot(i)
			var mould = state.molds[i]
			var done = i < limit
			var lit = 1.0 if (done or state.stage != "pressing") else 0.5
			contact(foot,62)
			prop(PLATE,foot-Vector2(52,44),104,Color(lit,lit,lit))
			draw_holes(foot-Vector2(0,22),mould if (state.stage != "pressing" or done) else 0)
			var tag = "未选" if mould == 0 else "%d 孔"%mould
			if done and mould != 0 and sealed_upto(limit).get(mould,-1) == i: tag += " · 留样"
			words("%d 号"%[i+1],foot+Vector2(-16,24),18)
			words(tag,foot-Vector2(46,62),17)
	var dada = Vector2(1190,630)
	contact(dada,26); prop(DADA,dada,96)
	words("嗒嗒",dada-Vector2(22,0),18)
	# 装配班长弥师傅站在工作台旁看这一批留样。
	var shifu = Vector2(430,634)
	contact(shifu,30); Batch2.draw_part(self,"mi_shifu",shifu,80)
	words("弥师傅",shifu-Vector2(34,0),18)

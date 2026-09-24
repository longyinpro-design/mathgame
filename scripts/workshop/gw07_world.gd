extends Node2D
# GW07 装配间现场：上排压制带、下排冷却带，四件货各占一格。
# 检修段固定画在冷却带上；两排之间那条细线是唯一的暂存位，重叠就说明顶住了。
# 每个时刻、每段占位都按当前排法现算，画面不另存一份会走样的表。
const Rules = preload("res://scripts/workshop/gw07_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/assembly-room-stage-v1.png")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const DIAL = preload("res://assets/runtime/workshop/kit-v1/dial.tres")
const RACK = preload("res://assets/runtime/workshop/kit-v1/rack.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_brace.tres")
const TICK_LEFT = 300.0
const TICK_W = 66.0
const HORIZON = 14
const PRESS_ROW_Y = 288.0
const COOL_ROW_Y = 372.0
const ROW_H = 68.0
const CELL_H = 48.0
const CELL_STEP = 5.0
const WAIT_Y = 362.0
const TINTS = [Color("c98a5b"),Color("7fa8c9"),Color("9ec98a"),Color("c9a0cf")]
const EDGES = [Color("6b4525"),Color("33536b"),Color("41602e"),Color("6a4a70")]
var scene_id = "assembly"
var state = Rules.fresh()
var focus_row = 0
var focus_item = 0
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

func tick_x(t: int) -> float:
	return TICK_LEFT+t*TICK_W
func row_y(row: int) -> float:
	return PRESS_ROW_Y if row == 0 else COOL_ROW_Y
# 同一排上的四件货各错开 5 像素，重叠时两块都还看得见。
func cell_rect(row: int, index: int) -> Rect2:
	var start = state.press[index] if row == 0 else state.cool[index]
	var span = Rules.PRESS_TIME if row == 0 else Rules.COOL_TIME
	return Rect2(tick_x(start)+2,row_y(row)+2+index*CELL_STEP,TICK_W*span-4,CELL_H)
# 试演进行到第几拍。
func playhead() -> int:
	if state.stage != "trial": return -1
	return clampi(floori(progress*(Rules.makespan(state)+1)),0,Rules.makespan(state))

func prop(texture: Texture2D, foot: Vector2, width: float, tint: Color = Color.WHITE) -> void:
	var dims = Vector2(texture.get_width(),texture.get_height())*width/texture.get_width()
	draw_texture_rect(texture,Rect2(foot-Vector2(dims.x/2,dims.y),dims),false,tint)
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

func draw_row(row: int) -> void:
	draw_rect(Rect2(TICK_LEFT-8,row_y(row),TICK_W*HORIZON+16,ROW_H),Color("2a3138"))
	for t in range(HORIZON+1):
		draw_line(Vector2(tick_x(t),row_y(row)),Vector2(tick_x(t),row_y(row)+ROW_H),Color(1,1,1,0.12),1)
	if row == 1:
		# 检修段：冷却机这一整段不能用，画成一条竖纹带。
		var left = tick_x(Rules.MAINT_START); var right = tick_x(Rules.MAINT_END)
		draw_rect(Rect2(left,row_y(row)-10,right-left,ROW_H+20),Color(0.62,0.22,0.18,0.42))
		draw_rect(Rect2(left,row_y(row)-10,right-left,ROW_H+20),Color("e2604f"),false,3)
		var stripe = left+4
		while stripe < right-2:
			draw_line(Vector2(stripe,row_y(row)-8),Vector2(stripe-14,row_y(row)+ROW_H+8),Color(1,0.86,0.78,0.28),2)
			stripe += 12

func draw_cells() -> void:
	var at_tick = playhead()
	for index in range(Rules.COUNT):
		for row in range(2):
			var cell = cell_rect(row,index)
			draw_rect(cell,TINTS[index])
			draw_rect(cell,EDGES[index],false,3)
			words(Rules.ITEMS[index],cell.position+Vector2(10,30),24)
			words("%d 拍"%[Rules.PRESS_TIME if row == 0 else Rules.COOL_TIME],cell.position+Vector2(40,28),15)
			var span_start = state.press[index] if row == 0 else state.cool[index]
			var span = Rules.PRESS_TIME if row == 0 else Rules.COOL_TIME
			if at_tick >= span_start and at_tick < span_start+span: draw_rect(cell,Color(1,0.95,0.75,0.6),false,5)
			if state.stage == "puzzle" and row == focus_row and index == focus_item:
				draw_rect(cell.grow(3),Color("f6e2a8"),false,3)

# 暂存位就是两排之间那条细线：等着的货在这里占一格，两件同时出现就是顶住了。
# 画在两排之后，重叠的那一段才不会被货块盖掉。
func draw_waiting() -> void:
	for index in range(Rules.COUNT):
		var row = Rules.plan(state)[index]
		if row.wait_end <= row.wait_start: continue
		var left = tick_x(row.wait_start); var right = tick_x(row.wait_end)
		draw_rect(Rect2(left,WAIT_Y,right-left,9),TINTS[index])
		draw_rect(Rect2(left,WAIT_Y,right-left,9),EDGES[index],false,2)

func draw_ruler() -> void:
	var top = PRESS_ROW_Y-10
	var bottom = COOL_ROW_Y+ROW_H+4
	for t in range(HORIZON+1):
		var x = tick_x(t)
		words(str(t),Vector2(x-6,bottom+20),17)
	var edge = tick_x(Rules.DEADLINE)
	draw_line(Vector2(edge,top),Vector2(edge,bottom),Color("e2604f"),3)
	plaque("第 %d 拍结束"%Rules.DEADLINE,Rect2(edge-176,240,176,32),17)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	contact(Vector2(60,PRESS_ROW_Y+ROW_H),30); prop(PRESS,Vector2(60,PRESS_ROW_Y+ROW_H),90)
	contact(Vector2(60,COOL_ROW_Y+ROW_H),30); prop(DIAL,Vector2(60,COOL_ROW_Y+ROW_H),90)
	plaque("压制带",Rect2(108,PRESS_ROW_Y+18,170,34),17)
	plaque("冷却带",Rect2(108,COOL_ROW_Y+18,170,34),17)
	if state.stage not in ["arrival","approach"]:
		plaque("A、B、C、D 依次经过压机与冷却机 · 压制 1 拍 · 冷却 2 拍",Rect2(20,200,660,34),17)
		plaque("中间只有一个暂存位，先来先冷却",Rect2(692,200,320,34),17)
		plaque("冷却机检修 %d～%d 拍"%[Rules.MAINT_START,Rules.MAINT_END],Rect2(454,240,260,32),16)
		draw_row(0)
		draw_row(1)
		draw_cells()
		draw_waiting()
		draw_ruler()
		var rows = Rules.plan(state)
		plaque("压制 %s"%starts_text(0),Rect2(24,486,300,34),16)
		plaque("冷却 %s"%starts_text(1),Rect2(336,486,300,34),16)
		plaque("总拍 %d / 上限 %d"%[Rules.makespan(state),Rules.DEADLINE],Rect2(648,486,240,34),17)
	if state.stage in ["delivery","aftermath","complete"]:
		contact(Vector2(900,660),40); prop(RACK,Vector2(900,660),110)
		words("晾晒线展开",Vector2(860,578),18)
	var dada = Vector2(1190,634)
	contact(dada,26); prop(DADA,dada,92)
	words("嗒嗒",dada-Vector2(22,0),18)

func starts_text(row: int) -> String:
	var parts = []
	var starts = state.press if row == 0 else state.cool
	for index in range(Rules.COUNT): parts.append("%s%d"%[Rules.ITEMS[index],starts[index]])
	return " ".join(parts)

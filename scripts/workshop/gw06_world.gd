extends Node2D
# GW06 装配间现场：一条炉次时刻表铺开，每一炉占一格，换模另占一格。
# 产量、加工拍、换模拍与总拍都按当前工单现算，画面不另存一份会走样的读数。
const Rules = preload("res://scripts/workshop/gw06_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/assembly-room-stage-v1.png")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const RACK = preload("res://assets/runtime/workshop/kit-v1/rack.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_idle.tres")
const TICK_LEFT = 250.0
const TICK_W = 76.0
const HORIZON = 12
const LANE_Y = 300.0
const LANE_H = 76.0
const TALLY_LEFT = 262.0
const TALLY_STEP = 28.0
const TALLY_Y = 503.0
const SMALL_TINT = Color("7fa8c9")
const LARGE_TINT = Color("c98a5b")
const CHANGE_TINT = Color("d9c47a")
var scene_id = "assembly"
var state = Rules.fresh()
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
# 试演进行到第几拍：走到 makespan 就算跑完。
func cursor() -> int:
	if state.stage != "trial": return -1
	var span = maxi(Rules.makespan(state),1)
	return clampi(floori(progress*(span+1)),0,span)
func cell_rect(start: int, end: int) -> Rect2:
	return Rect2(tick_x(start)+4,LANE_Y+10,tick_x(end)-tick_x(start)-8,LANE_H-20)
# 工单上第 index 炉的格子：玩家点它就是把这一炉从工单上撤下来。
func batch_rect(index: int) -> Rect2:
	var rows = Rules.schedule(state).batches
	if index < 0 or index >= rows.size(): return Rect2()
	return cell_rect(rows[index].start,rows[index].end)

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

func draw_lane() -> void:
	draw_rect(Rect2(TICK_LEFT-8,LANE_Y,TICK_W*HORIZON+16,LANE_H),Color("2a3138"))
	var rows = Rules.schedule(state)
	var at_tick = cursor()
	var span = lane_span()
	# 排得太长时，超出画面的那几拍裁掉，别让格子跑到窗口外面去。
	for change in rows.changes:
		var cell = clipped(cell_rect(change.start,change.end),span)
		if cell.size.x <= 8: continue
		draw_rect(cell,CHANGE_TINT)
		draw_rect(cell,Color("6d5a22"),false,3)
		words("换模",cell.position+Vector2(6,44),18)
		if at_tick >= change.start and at_tick < change.end: draw_rect(cell,Color(1,0.95,0.75,0.6),false,5)
	for index in range(rows.batches.size()):
		var row = rows.batches[index]
		var cell = clipped(cell_rect(row.start,row.end),span)
		if cell.size.x <= 8: continue
		draw_rect(cell,SMALL_TINT if row.mould == Rules.SMALL else LARGE_TINT)
		draw_rect(cell,Color("2f4a60") if row.mould == Rules.SMALL else Color("6b4525"),false,3)
		words("小" if row.mould == Rules.SMALL else "大",cell.position+Vector2(8,26),22)
		words("%d 枚"%row.mould,cell.position+Vector2(8,46),17)
		words("%d 号"%[index+1],cell.position+Vector2(8,64),15)
		if at_tick >= row.start and at_tick < row.end: draw_rect(cell,Color(1,0.95,0.75,0.6),false,5)

func lane_span() -> Vector2:
	return Vector2(TICK_LEFT-8,TICK_LEFT-8+TICK_W*HORIZON+16)
func clipped(cell: Rect2, span: Vector2) -> Rect2:
	var left = maxf(cell.position.x,span.x)
	return Rect2(left,cell.position.y,minf(cell.end.x,span.y)-left,cell.size.y)

func draw_ruler() -> void:
	var top = LANE_Y-30
	var bottom = LANE_Y+LANE_H+4
	for t in range(HORIZON+1):
		var x = tick_x(t)
		draw_line(Vector2(x,top),Vector2(x,bottom),Color(1,1,1,0.16),1)
		words(str(t),Vector2(x-6,bottom+20),17)
	plaque("时刻（拍）",Rect2(TICK_LEFT-8,234,150,32),17)
	var edge = tick_x(Rules.DEADLINE)
	draw_line(Vector2(edge,top),Vector2(edge,bottom),Color("e2604f"),3)

# 产量按枚画成一排环：空环是还没做出来的那一枚。
func draw_tally() -> void:
	var produced = Rules.output(state)
	for slot in range(Rules.NEED):
		var at = Vector2(TALLY_LEFT+slot*TALLY_STEP,TALLY_Y)
		if slot < produced:
			draw_circle(at,10,Color("e0b877"))
			draw_circle(at,4,Color("2a3138"))
		else:
			draw_circle(at,8,Color(0.16,0.13,0.1,0.32))

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	# 熔炉画在左侧，和炉次时刻表对齐；牌子写清两种模各出多少。
	contact(Vector2(128,LANE_Y+LANE_H),46)
	prop(PRESS,Vector2(128,LANE_Y+LANE_H),140)
	plaque("熔炉 · 一次一炉",Rect2(20,196,200,34),17)
	if state.stage not in ["arrival","approach"]:
		plaque("小模每炉 %d 枚 · 大模每炉 %d 枚"%[Rules.SMALL,Rules.LARGE],Rect2(236,196,326,34),17)
		plaque("每炉 1 拍 · 换模另用 1 拍 · 首次装模免费",Rect2(578,196,430,34),17)
		draw_ruler()
		draw_lane()
		var rows = Rules.schedule(state)
		plaque("加工拍 %d · 换模拍 %d · 总拍 %d"%[Rules.firing(state),rows.changes.size(),rows.makespan],
			Rect2(24,428,388,34),17)
		plaque("第 %d 拍结束"%Rules.DEADLINE,Rect2(tick_x(Rules.DEADLINE)-176,234,176,32),17)
		if rows.makespan > HORIZON:
			plaque("超出画面的拍数不画，总拍按左边的读数",Rect2(430,428,500,34),17)
		plaque("产量 %d / %d 枚"%[Rules.output(state),Rules.NEED],Rect2(24,486,222,34),17)
		draw_tally()
	if state.stage in ["delivery","aftermath","complete"]:
		contact(Vector2(1050,640),40)
		prop(RACK,Vector2(1050,640),120)
		words("灯架合拢",Vector2(976,606),18)
	var dada = Vector2(1190,634)
	contact(dada,26); prop(DADA,dada,92)
	words("嗒嗒",dada-Vector2(22,0),18)

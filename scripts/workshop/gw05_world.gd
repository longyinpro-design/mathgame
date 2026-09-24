extends Node2D
# GW05 装配间现场：两条工序带并排铺开，钻孔带从第 0 拍起贴紧排，
# 抛光带等前一件抛光完、且这一件钻完才接得上。每块的位置都按当前顺序现算，画面不另存时刻表。
const Rules = preload("res://scripts/workshop/gw05_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/assembly-room-stage-v1.png")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const DIAL = preload("res://assets/runtime/workshop/kit-v1/dial.tres")
const INGOT = preload("res://assets/runtime/workshop/kit-v1/ingot.tres")
const TRAY = preload("res://assets/runtime/workshop/kit-v1/tray.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_brace.tres")
const TICK_LEFT = 306.0
const TICK_W = 62.0
# 画到第 12 拍：最糟的排法（先做钻得最久的 A）正好第 12 拍完工，玩家看得到自己排到哪儿了。
const WINDOW = 12
const LANE_H = 72.0
const LANE_Y = [280.0,392.0]
const FILL = [Color("c98a5b"),Color("7fa8c9"),Color("9ec98a")]
const EDGE = [Color("6b4525"),Color("33536b"),Color("41602e")]
var scene_id = "assembly"
var state = Rules.fresh()
var track = 0
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
func lane_rect(index: int) -> Rect2:
	return Rect2(TICK_LEFT-8,LANE_Y[index],TICK_W*WINDOW+16,LANE_H)
# 超出画面的那几拍裁掉，别让货块跑到窗口外面去；读数牌照旧写出真实完工拍。
func lane_span() -> Vector2:
	var rect = lane_rect(0)
	return Vector2(rect.position.x,rect.end.x)
# 某一带上第 index 块工序的位置：直接问规则算出的时刻表，避免另存一份会走样的坐标。
func block_rect(index: int, at: int) -> Rect2:
	var rows = Rules.timeline(state).get("drill" if index == 0 else "polish",[])
	if at < 0 or at >= rows.size(): return Rect2()
	var row = rows[at]
	return Rect2(tick_x(row.start)+5,LANE_Y[index]+11,tick_x(row.end)-tick_x(row.start)-10,LANE_H-22)
func order_of(index: int) -> Array:
	return state.drill if index == 0 else state.polish
# 下一件会落在这一带的哪一拍：钻孔带按已排时长贴紧，抛光带接在最后一件之后。
func next_x(index: int) -> float:
	var rows = Rules.timeline(state).get("drill" if index == 0 else "polish",[])
	if rows.is_empty(): return tick_x(0)
	return tick_x(rows[-1].end)
# 试演进行到第几拍。
func cursor() -> int:
	if state.stage != "trial": return -1
	return clampi(floori(progress*(Rules.DEADLINE+1)),0,Rules.DEADLINE)

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

func draw_lane(index: int) -> void:
	var rect = lane_rect(index)
	draw_rect(rect.grow(4),Color(0.1,0.13,0.16,0.5))
	draw_rect(rect,Color("2a3138"))
	var rows = Rules.timeline(state).get("drill" if index == 0 else "polish",[])
	var at_tick = cursor()
	var span = lane_span()
	for row in rows:
		var block = Rect2(tick_x(row.start)+5,LANE_Y[index]+11,tick_x(row.end)-tick_x(row.start)-10,LANE_H-22)
		block = Rect2(maxf(block.position.x,span.x),block.position.y,
			minf(block.end.x,span.y)-maxf(block.position.x,span.x),block.size.y)
		if block.size.x <= 8: continue
		var tool = row.tool
		draw_rect(block,FILL[tool])
		draw_rect(block,EDGE[tool],false,3)
		var running = at_tick >= row.start and at_tick < row.end
		if running: draw_rect(block,Color(1,0.95,0.75,0.55),false,5)
		words(Rules.NAMES[tool],block.position+Vector2(14,44),30)
		words("%d 拍"%[row.end-row.start],block.position+Vector2(46,40),17)
	# 试演时把正在加工的那一件画在机器旁；摆放时只在选定带上标出「下一件放这里」。
	if at_tick >= 0:
		for row in rows:
			if at_tick >= row.start and at_tick < row.end:
				prop(INGOT,Vector2(tick_x(row.start)+26,LANE_Y[index]-6),64)
	if state.stage == "puzzle" and index == track:
		var x = next_x(index)
		draw_line(Vector2(x,LANE_Y[index]-6),Vector2(x,LANE_Y[index]+LANE_H+6),Color("f6e2a8"),3)
		words("下一件",Vector2(x-32,LANE_Y[index]-30),17)

func draw_ruler() -> void:
	var top = LANE_Y[0]-34
	var bottom = LANE_Y[1]+LANE_H+6
	for t in range(WINDOW+1):
		var x = tick_x(t)
		draw_line(Vector2(x,top),Vector2(x,bottom),Color(1,1,1,0.16),1)
		words(str(t),Vector2(x-6,bottom+20),18)
	plaque("时刻（拍）",Rect2(TICK_LEFT-8,top-38,150,32),17)
	var edge = tick_x(Rules.DEADLINE)
	draw_line(Vector2(edge,top),Vector2(edge,bottom),Color("e2604f"),3)
	plaque("第 %d 拍结束"%Rules.DEADLINE,Rect2(edge-176,bottom+42,176,32),17)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	# 两台机器画在左侧，和各自那条带对齐；牌子上写清这一带是哪台机。
	contact(Vector2(146,LANE_Y[0]+LANE_H),44)
	prop(PRESS,Vector2(146,LANE_Y[0]+LANE_H),124)
	plaque("钻孔带 · 钻机",Rect2(24,LANE_Y[0]-46,224,34),17)
	contact(Vector2(146,LANE_Y[1]+LANE_H),44)
	prop(DIAL,Vector2(146,LANE_Y[1]+LANE_H),140)
	plaque("抛光带 · 抛光机",Rect2(24,LANE_Y[1]-46,224,34),17)
	if state.stage not in ["arrival","approach"]:
		draw_ruler()
		draw_lane(0)
		draw_lane(1)
		var ready = Rules.ready(state)
		var finish = Rules.makespan(state) if ready else 0
		plaque("完工：%s"%("第 %d 拍"%finish if ready else "还没排满"),Rect2(24,LANE_Y[1]+LANE_H+42,224,34),17)
		# 每件工具的工时表始终挂在墙上：这是开局就该能查的题面，不是提示。
		plaque("工序工时",Rect2(1068,196,196,38),18)
		for tool in range(Rules.TOOLS):
			plaque("%s 钻%d 抛%d"%[Rules.NAMES[tool],Rules.DRILL[tool],Rules.POLISH[tool]],
				Rect2(1068,242+tool*44,196,38),17)
	if state.stage in ["delivery","aftermath","complete"]:
		prop(TRAY,Vector2(1078,LANE_Y[1]+LANE_H+60),170)
		words("三件已抛光",Vector2(1006,LANE_Y[1]+LANE_H+30),19)
		for tool in range(Rules.TOOLS):
			prop(INGOT,Vector2(1014+tool*44,LANE_Y[1]+LANE_H+40),52)
	var dada = Vector2(1190,634)
	contact(dada,26); prop(DADA,dada,92)
	words("嗒嗒",dada-Vector2(22,0),18)

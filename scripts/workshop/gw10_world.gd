extends Node2D
# GW10 装配间现场：一台维修台，时间尺上并排四张单的占台区间。
# 每单的到料闸（C 第 1 拍才送到）、各自的最晚完成线、开工拍与占台区间全部按当前排法现算；
# 撞台、未到料与逾期只标出玩家自己排出来的样子，判定仍由规则模块逐单给出。
# 演出时扫过一条验收线，四单按做完的先后依次盖上「已验收」。
const Rules = preload("res://scripts/workshop/gw10_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/rooftop-repair-street-stage-v1.png")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const LEVER = preload("res://assets/runtime/workshop/kit-v1/lever.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_brace.tres")
const TICK_LEFT = 176.0
const TICK_W = 78.0
const TICKS = 12
const ROW_TOP = 230.0
const ROW_H = 66.0
const ROW_GAP = 4.0
const BAR_TOP = 6.0
const BAR_H = 42.0
const TINTS = [Color("c98a5b"),Color("7fa8c9"),Color("9ec98a"),Color("c9a0cf")]
const EDGES = [Color("6b4525"),Color("33536b"),Color("41602e"),Color("6a4a70")]
const GREEN = Color("8fd694")
const RED = Color("e2604f")
const AMBER = Color("e8c06a")
var scene_id = "rooftop"
var state = Rules.fresh()
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
func row_y(index: int) -> float:
	return ROW_TOP+index*(ROW_H+ROW_GAP)
# 点这一块就选中那一单：和画面上的单牌同一处。
func row_rect(index: int) -> Rect2:
	return Rect2(20,row_y(index)+8,142,44)

func prop(texture: Texture2D, foot: Vector2, width: float, tint: Color = Color.WHITE) -> void:
	var dims = Vector2(texture.get_width(),texture.get_height())*width/texture.get_width()
	draw_texture_rect(texture,Rect2(foot-Vector2(dims.x/2,dims.y),dims),false,tint)
func contact(foot: Vector2, radius: float) -> void:
	draw_set_transform(foot,0,Vector2(1,0.18))
	draw_circle(Vector2.ZERO,radius,Color(0.08,0.1,0.12,0.3))
	draw_set_transform(Vector2.ZERO)
func words(value: String, at: Vector2, size_px: int = 20) -> void:
	words_tint(value,at,size_px,Color("fff0d1"))
func words_tint(value: String, at: Vector2, size_px: int, tint: Color) -> void:
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,4,Color("21313c"))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,tint)
func plaque(value: String, rect: Rect2, size_px: int = 19) -> void:
	draw_style_box(ArtStyle.sign_style(),rect)
	words(value,rect.position+Vector2(10,rect.size.y-10),size_px)

func sequence_text() -> String:
	return "→".join(state.order)

# 演出进行到第几拍：验收线从第 0 拍扫到第 8 拍。
func playhead() -> int:
	if state.stage != "delivery": return -1
	return clampi(floori(progress*(Rules.HORIZON+1)),0,Rules.HORIZON)

# 显示用的重叠检查：只看玩家自己排出来的两段区间有没有抢同一拍。
func overlaps(index: int) -> bool:
	var rows = Rules.plan(state)
	for other in range(Rules.COUNT):
		if other == index: continue
		if maxi(rows[index].start,rows[other].start) < mini(rows[index].end,rows[other].end): return true
	return false

func draw_slips() -> void:
	plaque("四张维修单",Rect2(430,236,420,40),20)
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		plaque("%s 单 · 用时 %d 拍 · 最晚第 %d 拍完成"%[id,Rules.DURATIONS[id],Rules.DEADLINES[id]],
			Rect2(430,286+index*62,420,50),19)

func draw_headers() -> void:
	plaque("一张维修台一次一单 · 开工后不能中断",Rect2(20,196,470,34),17)
	plaque("A/B/D 第 0 拍就绪 · C 第 1 拍送到",Rect2(502,196,470,34),17)
	plaque("验收顺序 %s"%sequence_text(),Rect2(984,196,272,34),17)

# 到料闸与最晚完成线：开局就画出来，玩家的排法只决定区间落在哪一段。
func draw_limits(index: int, id: String, top: float) -> void:
	var deadline_x = tick_x(Rules.DEADLINES[id])
	draw_rect(Rect2(deadline_x,top+2,tick_x(TICKS)-deadline_x,ROW_H-4),Color(0.62,0.22,0.18,0.18))
	draw_line(Vector2(deadline_x,top),Vector2(deadline_x,top+ROW_H),RED,2)
	words_tint("最晚 %d 拍"%Rules.DEADLINES[id],Vector2(deadline_x+8,top+20),15,RED)
	if Rules.RELEASES[id] > 0:
		var gate = tick_x(Rules.RELEASES[id])
		draw_rect(Rect2(tick_x(0),top+2,gate-tick_x(0),ROW_H-4),Color(0.72,0.52,0.18,0.22))
		draw_dashed_line(Vector2(gate,top+2),Vector2(gate,top+ROW_H-2),AMBER,2)
		# 开工拍压在到料之前时，这一段被占台区间盖住，标签让位给红色描边。
		if state.starts[index] >= Rules.RELEASES[id]:
			words_tint("未到料",Vector2(tick_x(0)+6,top+18),14,AMBER)

func draw_bar(index: int, id: String, top: float) -> void:
	var start = state.starts[index]
	var finish = start+Rules.DURATIONS[id]
	var bar = Rect2(tick_x(start)+3,top+BAR_TOP,TICK_W*Rules.DURATIONS[id]-6,BAR_H)
	var early = start < Rules.RELEASES[id]
	var late = finish > Rules.DEADLINES[id]
	var hit = overlaps(index)
	draw_rect(bar,TINTS[index])
	draw_rect(bar,EDGES[index],false,3)
	words("%s %d 拍"%[id,Rules.DURATIONS[id]],bar.position+Vector2(10,28),20)
	words_tint("第 %d 拍开工"%start,Vector2(bar.position.x+6,top+62),14,
		RED if early or late else Color("d8e2d2"))
	if early or late: draw_rect(bar.grow(3),RED,false,3)
	elif hit: draw_rect(bar.grow(3),Color("e8a04f"),false,3)
	if state.stage == "puzzle" and index == focus_item:
		draw_rect(bar.grow(5),Color("f6e2a8"),false,3)

func draw_rows() -> void:
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		var top = row_y(index)
		draw_rect(Rect2(TICK_LEFT-10,top,TICK_W*TICKS+20,ROW_H),Color("2a3138"))
		for t in range(TICKS+1):
			draw_line(Vector2(tick_x(t),top),Vector2(tick_x(t),top+ROW_H),Color(1,1,1,0.10),1)
		draw_limits(index,id,top)
		draw_bar(index,id,top)
		plaque("%s %d拍 最晚%d拍"%[id,Rules.DURATIONS[id],Rules.DEADLINES[id]],
			Rect2(20,top+8,142,44),16)

func draw_ruler() -> void:
	var bottom = row_y(Rules.COUNT-1)+ROW_H
	for t in range(TICKS+1):
		words(str(t),Vector2(tick_x(t)-6,bottom+22),16)

# 逐单验收：验收线扫到哪一拍，已经做完的单就盖上一枚「已验收」。
func draw_acceptance() -> void:
	var tick = playhead()
	if tick < 0: return
	draw_line(Vector2(tick_x(tick),row_y(0)-6),Vector2(tick_x(tick),row_y(Rules.COUNT-1)+ROW_H+6),
		Color("f6e2a8"),3)
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		if state.starts[index]+Rules.DURATIONS[id] > tick: continue
		var top = row_y(index)
		draw_rect(Rect2(TICK_LEFT-10,top,TICK_W*TICKS+20,ROW_H),GREEN,false,3)
		var center = Vector2(TICK_LEFT+TICK_W*TICKS+26,top+ROW_H/2-2)
		draw_arc(center,13,0,TAU,24,GREEN,2)
		draw_line(center+Vector2(-6,0),center+Vector2(-1,5),GREEN,3)
		draw_line(center+Vector2(-1,5),center+Vector2(7,-6),GREEN,3)
		words_tint("已验收",Vector2(center.x+20,top+ROW_H/2+6),17,GREEN)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	contact(Vector2(92,640),34); prop(PRESS,Vector2(92,640),120)
	contact(Vector2(1196,638),26); prop(DADA,Vector2(1196,638),92)
	plaque("维修台",Rect2(30,524,120,30),15)
	words("嗒嗒",Vector2(1160,638),18)
	if state.stage == "arrival":
		draw_slips()
	else:
		draw_headers()
		draw_rows()
		draw_ruler()
		if state.stage in ["delivery","aftermath","complete"]:
			draw_acceptance()
	if state.stage in ["ready","puzzle"]:
		contact(Vector2(1214,356),22); prop(LEVER,Vector2(1214,356),76)

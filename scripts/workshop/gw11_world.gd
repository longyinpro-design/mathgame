extends Node2D
# GW11 装卸码头现场：一张 0～15 拍的共用时刻表。
# 顶上挂三张船票（A 钉死第 12 拍，B 可选第 13 或 14 拍），中间是 A、B 两批各三段流程条，
# 下面三条带是两批共用的装配台、冷却架与吊机：谁在哪一拍占着哪条带，全按当前开工拍现算，
# 撞车的时刻当场标红。船票比对、首尾相接与共用带判定都由规则模块算，画面只负责摆出来。
const Rules = preload("res://scripts/workshop/gw11_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/mistimed-dock-stage-v1.png")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const RACK = preload("res://assets/runtime/workshop/kit-v1/rack.tres")
const LIFT = preload("res://assets/runtime/workshop/kit-v1/lift.tres")
const BOX = preload("res://assets/runtime/workshop/kit-v1/box.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_brace.tres")
const TICK_LEFT = 196.0
const TICK_W = 58.0
const TICKET_Y = 272.0
const TICKET_H = 46.0
const TICKET_W = 56.0
const ROW_Y = [320.0,372.0]
const BAR_H = 48.0
const LANE_Y = [428.0,468.0,508.0]
const LANE_H = 34.0
const VERDICT = Rect2(24,196,1232,44)
const LANE_NAMES = ["装配台","冷却架","吊机"]
const LANE_CAPS = ["一次一批","可放两批","一次一批"]
const TINTS = [Color("c98a5b"),Color("7fa8c9")]
const EDGES = [Color("6b4525"),Color("33536b")]
const CONFLICT = Color("e2604f")
const GREEN = Color("8fd694")
var scene_id = "dock"
var state = Rules.fresh()
var focus_batch = 0
var focus_row = 0
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
# 一批的一道工序条：按当前开工拍与时长现算，超出台面的部分裁到最后一拍。
func span_rect(batch: int, row: int) -> Rect2:
	var span = Rules.interval(state,batch,row)
	var left = tick_x(span[0])+2
	var right = minf(tick_x(span[1]),tick_x(Rules.HORIZON))-2
	return Rect2(left,ROW_Y[batch]+2,maxf(right-left,20.0),BAR_H-4)
# 三张船票：0 是 A 的第 12 拍票，1、2 是 B 的两张候选票。
func ticket_rect(index: int) -> Rect2:
	var tick = [Rules.A_LOAD,Rules.TICKETS[0],Rules.TICKETS[1]][index]
	return Rect2(tick_x(tick)-TICKET_W/2,TICKET_Y,TICKET_W,TICKET_H)
func lane_rect(row: int, tick: int) -> Rect2:
	return Rect2(tick_x(tick)+2,LANE_Y[row]+2,TICK_W-4,LANE_H-4)

# 试演跑到第几拍。
func playhead() -> int:
	if state.stage != "delivery": return -1
	return clampi(floori(progress*(Rules.HORIZON+1)),0,Rules.HORIZON)

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

func plan_text() -> String:
	var parts = []
	for batch in range(Rules.COUNT):
		var segs = []
		for row in range(3):
			var span = Rules.interval(state,batch,row)
			segs.append("%s %d–%d"%[Rules.STAGE_NAMES[row],span[0],span[1]])
		parts.append("%s 批 %s"%[Rules.BATCHES[batch],"、".join(segs)])
	return "；".join(parts)

func ticket_text() -> String:
	return "还没选（B 两张船票）" if not Rules.TICKETS.has(state.ticket) else "第 %d 拍（B）"%state.ticket

func draw_verdict() -> void:
	var text = ""
	var tint = Color("fff0d1")
	if Rules.solved(state):
		text = "两批都排好了：%s"%plan_text()
		tint = GREEN
	else:
		var gaps = Rules.shortfalls(state)
		if not gaps.is_empty(): text = "还差：%s"%gaps[0]
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(text,VERDICT.position+Vector2(10,VERDICT.size.y-12),17,tint)

# 刻度：0～16 每拍一条竖线，数字排在船票行上方。
func draw_ruler() -> void:
	for t in range(Rules.HORIZON+1):
		var x = tick_x(t)
		draw_line(Vector2(x,TICKET_Y-6),Vector2(x,LANE_Y[2]+LANE_H+4),Color(1,1,1,0.11),1)
		words(str(t),Vector2(x-9,TICKET_Y-10),16)
	var arrive = tick_x(Rules.ARRIVAL_BEAT)
	var y = TICKET_Y
	while y < LANE_Y[2]+LANE_H:
		draw_line(Vector2(arrive,y),Vector2(arrive,y+12),Color("f2cf7a"),3)
		y += 20

func draw_tickets() -> void:
	plaque("船票",Rect2(16,TICKET_Y,170,TICKET_H),17)
	for index in range(3):
		var rect = ticket_rect(index)
		var fixed = index == 0
		var tick = [Rules.A_LOAD,Rules.TICKETS[0],Rules.TICKETS[1]][index]
		var chosen = fixed or state.ticket == tick
		draw_rect(rect,Color(0.10,0.16,0.13,0.94) if chosen else Color(0.14,0.17,0.18,0.72))
		draw_rect(rect,Color("f2cf7a") if chosen else Color(1,1,1,0.18),false,3 if chosen else 2)
		words_tint("%d 拍"%tick,rect.position+Vector2(6,30),16,Color("fff0d1") if chosen else Color(0.70,0.72,0.68))
		# 票角上的小色块认领批次：橙是 A，蓝是 B。
		draw_rect(Rect2(rect.position+Vector2(rect.size.x-16,8),Vector2(9,9)),TINTS[0 if fixed else 1])
	if Rules.TICKETS.has(state.ticket):
		var mark = ticket_rect(1 if state.ticket == Rules.TICKETS[0] else 2)
		draw_rect(mark.grow(3),Color("f6e2a8"),false,2)

func draw_batch(batch: int) -> void:
	plaque("%s 批"%Rules.BATCHES[batch],Rect2(16,ROW_Y[batch],170,BAR_H),20)
	for row in range(3):
		var rect = span_rect(batch,row)
		var span = Rules.interval(state,batch,row)
		draw_rect(rect,TINTS[batch])
		draw_rect(rect,EDGES[batch],false,3)
		var label = Rules.STAGE_NAMES[row]
		if rect.size.x >= 80: label += " %d 拍"%Rules.duration(batch,row)
		words(label,rect.position+Vector2(7,20),15)
		words("%d–%d"%[span[0],span[1]],rect.position+Vector2(7,38),15)
		if state.stage == "puzzle" and batch == focus_batch and row == focus_row:
			draw_rect(rect.grow(3),Color("f6e2a8"),false,3)

# 三条共用带：哪一批在哪一拍占着哪条带；一次一批的带子上出现两批就是撞车。
func draw_lane(row: int) -> void:
	plaque(LANE_NAMES[row],Rect2(16,LANE_Y[row],170,LANE_H),18)
	words(LANE_CAPS[row],Vector2(1140,LANE_Y[row]+23),17)
	for tick in range(Rules.HORIZON):
		var rect = lane_rect(row,tick)
		var held = Rules.holders(state,row,tick)
		if held.is_empty():
			draw_rect(rect,Color(0.11,0.14,0.17,0.55))
			draw_rect(rect,Color(1,1,1,0.08),false,1)
			continue
		if held.size() == 1:
			draw_rect(rect,TINTS[held[0]])
			draw_rect(rect,EDGES[held[0]],false,2)
			words(Rules.BATCHES[held[0]],rect.position+Vector2(20,25),18)
			continue
		if row == 1:
			var half = rect.size.y/2
			draw_rect(Rect2(rect.position,Vector2(rect.size.x,half)),TINTS[held[0]])
			draw_rect(Rect2(rect.position+Vector2(0,half),Vector2(rect.size.x,half)),TINTS[held[1]])
			draw_rect(rect,EDGES[held[0]],false,2)
			words("%s+%s"%[Rules.BATCHES[held[0]],Rules.BATCHES[held[1]]],rect.position+Vector2(7,24),16)
		else:
			draw_rect(rect,CONFLICT)
			draw_rect(rect,Color("7a2f26"),false,2)
			words("冲突",rect.position+Vector2(8,24),16)

# 底栏上方的操作提示与三件共用设备的小像。
func draw_controls() -> void:
	plaque("←→ 换工序 · ↑↓ 换批 · Q/E 提前·推后 1 拍 · T 换船票 · Z 撤销 · X 重摆 · H 提示",Rect2(24,600,636,42),16)
	contact(Vector2(700,642),16); prop(PRESS,Vector2(700,642),44)
	contact(Vector2(802,642),16); prop(RACK,Vector2(802,642),62)
	contact(Vector2(912,642),16); prop(LIFT,Vector2(912,642),58)
	contact(Vector2(1050,642),18); prop(DADA,Vector2(1050,642),72)
	words("嗒嗒",Vector2(958,626),18)

func draw_arrival() -> void:
	contact(Vector2(400,642),30); prop(BOX,Vector2(400,642),120)
	contact(Vector2(600,642),30); prop(BOX,Vector2(600,642),120,Color("cfe0f2"))
	plaque("两批材料都第 %d 拍到"%Rules.ARRIVAL_BEAT,Rect2(760,596,300,44),18)
	contact(Vector2(1160,642),26); prop(DADA,Vector2(1160,642),92)
	words("嗒嗒",Vector2(1040,626),18)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	if state.stage in ["arrival","approach"]:
		draw_arrival()
		return
	draw_verdict()
	draw_ruler()
	draw_tickets()
	for batch in range(Rules.COUNT): draw_batch(batch)
	for row in range(3): draw_lane(row)
	var at = playhead()
	if at >= 0:
		draw_rect(Rect2(tick_x(at)+2,ROW_Y[0],TICK_W-4,LANE_Y[2]+LANE_H-ROW_Y[0]),Color(1,0.93,0.72,0.16),true)
		words("第 %d 拍"%at,Vector2(24,570),20)
		# 吊机就在底栏上方：货箱随进度从吊机上抬起，像真的被吊上船。
		contact(Vector2(912,642-46*progress),22)
		prop(BOX,Vector2(912,642-46*progress),56)
	elif state.stage in ["aftermath","complete"]:
		plaque("A 批第 %d 拍开船 · B 批第 %d 拍开船"%[Rules.A_LOAD,state.ticket],Rect2(24,566,470,44),18)
	draw_controls()

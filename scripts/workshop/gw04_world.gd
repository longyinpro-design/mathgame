extends Node2D
# GW04 码头现场：一条 0～16 拍的班次表，上排吊台、下排小车，两排都点得。
# 到达格按当前延后量现算：换一档，上排整条时刻表跟着挪，下排固定不动。
const Rules = preload("res://scripts/workshop/gw04_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/mistimed-dock-stage-v1.png")
const LIFT = preload("res://assets/runtime/workshop/kit-v1/lift.tres")
const CART = preload("res://assets/runtime/workshop/kit-v1/cart.tres")
const TRAY = preload("res://assets/runtime/workshop/kit-v1/tray.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const TICK_LEFT = 210.0
const TICK_W = 60.0
const BAR_H = 46.0
const TRACK_Y = [300.0,380.0]
var scene_id = "dock"
var state = Rules.fresh()
var cursor = 1
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
func track_rect(track: int) -> Rect2:
	return Rect2(TICK_LEFT-TICK_W/2,TRACK_Y[track],TICK_W*(Rules.HORIZON+1),BAR_H)
# 一次交接点横跨两排：点哪一排都是同一件事，格子也够大。
func pick_rect(t: int) -> Rect2:
	return Rect2(tick_x(t)-TICK_W/2,TRACK_Y[0],TICK_W,TRACK_Y[1]+BAR_H-TRACK_Y[0])
# 试演进行到第几拍。
func playhead() -> int:
	if state.stage != "trial": return -1
	return clampi(floori(progress*(Rules.HORIZON+1)),0,Rules.HORIZON)

func prop(texture: Texture2D, foot: Vector2, width: float) -> void:
	var dims = Vector2(texture.get_width(),texture.get_height())*width/texture.get_width()
	draw_texture_rect(texture,Rect2(foot-Vector2(dims.x/2,dims.y),dims),false)
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

func draw_track(track: int, arrivals: Array, at_tick: int) -> void:
	var y = TRACK_Y[track]
	draw_rect(Rect2(TICK_LEFT-TICK_W/2-4,y-2,TICK_W*(Rules.HORIZON+1)+8,BAR_H+4),Color(0.12,0.15,0.18,0.5))
	draw_rect(Rect2(TICK_LEFT-TICK_W/2,y,TICK_W*(Rules.HORIZON+1),BAR_H),Color("2a3138"))
	for t in range(Rules.HORIZON+1):
		var x = tick_x(t)
		draw_line(Vector2(x-TICK_W/2,y),Vector2(x-TICK_W/2,y+BAR_H),Color(1,1,1,0.14),1)
		words(str(t),Vector2(x-8,y+BAR_H+22),16)
		if arrivals.has(t):
			draw_circle(Vector2(x,y+BAR_H/2),11,Color("f2cf7a"))
			draw_circle(Vector2(x,y+BAR_H/2),4.5,Color("6a4b1d"))
		if t == at_tick:
			draw_rect(Rect2(x-TICK_W/2,y,TICK_W,BAR_H),Color(1,0.93,0.72,0.28),true)
	plaque(["吊台","小车"][track],Rect2(20,y,168,BAR_H),20)

func draw_picks() -> void:
	if state.stage == "puzzle":
		var x = tick_x(cursor)
		draw_rect(Rect2(x-TICK_W/2,TRACK_Y[0]-4,TICK_W,TRACK_Y[1]+BAR_H-TRACK_Y[0]+8),Color(1,0.93,0.72,0.16),true)
	for t in state.picks:
		var x = tick_x(t)
		draw_line(Vector2(x,TRACK_Y[0]-26),Vector2(x,TRACK_Y[1]+BAR_H+30),Color("f6e2a8"),3)
		draw_circle(Vector2(x,TRACK_Y[0]-40),13,Color("f2cf7a"))
		prop(TRAY,Vector2(x,TRACK_Y[1]+BAR_H+58),74)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	if state.stage not in ["arrival","approach"]:
		words("新班次：余下两托已在第 0 拍备好，第 16 拍结束前要交完",Vector2(24,244),19)
		var at = playhead()
		draw_track(0,Rules.lift_times(state.delay),at)
		draw_track(1,Rules.CARTS,at)
		draw_picks()
		var lifts = []
		for t in Rules.lift_times(state.delay): lifts.append(str(t))
		plaque("延后 %d 拍 · 吊台到 %s 拍"%[state.delay,"、".join(lifts)],Rect2(300,478,540,44),19)
	if state.stage == "trial":
		var t = maxi(playhead(),0)
		prop(LIFT,Vector2(tick_x(t),TRACK_Y[0]-34),132)
		prop(CART,Vector2(tick_x(t),TRACK_Y[1]+BAR_H+78),124)
		if state.picks.has(t) and Rules.meetings(state.delay).has(t):
			words("接走一托",Vector2(tick_x(t)-46,TRACK_Y[0]-96),19)
	if state.stage in ["delivery","aftermath","complete"]:
		for index in range(state.picks.size()):
			var t = state.picks[index]
			var settle = 1.0 if state.stage != "delivery" else smoothstep(float(index)*0.4,float(index)*0.4+0.5,progress)
			prop(LIFT,Vector2(tick_x(t),lerpf(TRACK_Y[0]-34,TRACK_Y[1]+BAR_H+30,1-settle)),132)
		prop(CART,Vector2(tick_x(Rules.HORIZON),TRACK_Y[1]+BAR_H+78),124)
	var dada = Vector2(1190,632)
	contact(dada,26); prop(DADA,dada,92)
	words("嗒嗒",dada-Vector2(22,0),18)

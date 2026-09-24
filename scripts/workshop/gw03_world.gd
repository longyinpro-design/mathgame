extends Node2D
# GW03 错拍码头现场：三条节拍带（吊台 / 小车 / 放行灯）横贯画面，第 0～40 拍逐格对齐。
# 到达格只有在玩家真的运行过那一拍之后才点亮，画面不预先摊开整张时刻表。
const Rules = preload("res://scripts/workshop/gw03_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/mistimed-dock-stage-v1.png")
const LIFT = preload("res://assets/runtime/workshop/kit-v1/lift.tres")
const CART = preload("res://assets/runtime/workshop/kit-v1/cart.tres")
const BELL = preload("res://assets/runtime/workshop/kit-v1/bell.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_brace.tres")
const TICK_LEFT = 156.0
const TICK_W = 26.0
const BAR_H = 44.0
const TRACK_Y = [296.0,356.0,416.0]
var scene_id = "dock"
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
	return TICK_LEFT+t*TICK_W+1.5
func track_rect(track: int) -> Rect2:
	return Rect2(TICK_LEFT-2,TRACK_Y[track],TICK_W*(Rules.HORIZON+1)+4,BAR_H)
# 热区左上角在 TICK_LEFT-2，所以控件内的横坐标要减掉那 2 像素再折算成拍号。
func tick_at(local_x: float) -> int:
	return clampi(floori((local_x-2.0)/TICK_W),0,Rules.HORIZON)

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

func draw_ruler() -> void:
	for t in range(Rules.HORIZON+1):
		if t%5 != 0: continue
		var x = tick_x(t)
		draw_line(Vector2(x,TRACK_Y[0]-20),Vector2(x,TRACK_Y[0]-4),Color(1,1,1,0.34),2)
		words(str(t),Vector2(x-8,TRACK_Y[0]-24),17)

func draw_track(track: int) -> void:
	var y = TRACK_Y[track]
	draw_rect(Rect2(TICK_LEFT-4,y-2,TICK_W*(Rules.HORIZON+1)+8,BAR_H+4),Color(0.12,0.15,0.18,0.5))
	draw_rect(Rect2(TICK_LEFT,y,TICK_W*(Rules.HORIZON+1),BAR_H),Color("2a3138"))
	var watched = state.watched
	for t in range(Rules.HORIZON+1):
		var x = TICK_LEFT+t*TICK_W
		if t%5 == 0: draw_line(Vector2(x,y),Vector2(x,y+BAR_H),Color(1,1,1,0.16),1)
		if watched.has(t) and Rules.arrives(track,t):
			draw_circle(Vector2(x+TICK_W/2,y+BAR_H/2),8,Color("f2cf7a"))
			draw_circle(Vector2(x+TICK_W/2,y+BAR_H/2),3.4,Color("6a4b1d"))
	plaque(Rules.TRACK_NAMES[track],Rect2(20,y,128,BAR_H),20)

func draw_probe() -> void:
	var x = tick_x(state.probe)
	draw_line(Vector2(x,TRACK_Y[0]-24),Vector2(x,TRACK_Y[2]+BAR_H+34),Color("f6e2a8"),3)
	var seen = state.watched.has(state.probe)
	var marks = []
	for track in range(3):
		var arrived = Rules.arrives(track,state.probe)
		marks.append("%s %s"%[Rules.TRACK_NAMES[track],"到" if arrived else "没到"])
	var label = "第 %d 拍 · %s"%[state.probe," · ".join(marks)]
	plaque(label,Rect2(300,470,540,44),20)
	if seen: plaque("这一拍运行过了",Rect2(856,470,200,44),19)
	else: plaque("还没运行这一拍",Rect2(856,470,200,44),19)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	if state.stage not in ["arrival","approach"]:
		words("节拍：吊台 2+3k · 小车 3+4k · 放行灯 3+5k（1～40 拍）",Vector2(24,236),19)
		draw_ruler()
		for track in range(3): draw_track(track)
		draw_probe()
	# 交付那一幕：吊台落到小车上方，正好停在真正同时的那一拍上。
	var handover = Vector2(tick_x(Rules.earliest()),TRACK_Y[1]-96)
	var settle = 1.0
	if state.stage == "delivery": settle = smoothstep(0,0.7,progress)
	if state.stage in ["aftermath","complete"]: settle = 0.0
	if state.stage in ["delivery","aftermath","complete"]:
		var at = Vector2(handover.x,lerpf(TRACK_Y[0]+BAR_H/2-70,handover.y,1-settle))
		prop(LIFT,at,150)
		prop(CART,Vector2(handover.x,TRACK_Y[1]+BAR_H/2+40),140)
		prop(BELL,Vector2(handover.x,TRACK_Y[2]+BAR_H/2),64)
	var dada = Vector2(1190,632)
	contact(dada,26); prop(DADA,dada,92)
	words("嗒嗒",dada-Vector2(22,0),18)

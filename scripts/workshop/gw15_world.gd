extends Node2D
# GW15 装配间现场：左边一台出料机，出料窗上方挂着观察读数；右边是第 1～12 拍的时间尺、
# 已锁过的时刻与三块周期牌。三份数量、开窗读数与判定都由规则模块算；
# 三周期对照表只在第 2 档主动提示之后才摊开，正常界面不自动填关键中间量。
# 出料窗只开一次：锁好时刻、开过窗之后时间尺就冻住，要换时刻只能重摆。
const Rules = preload("res://scripts/workshop/gw15_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/old-chime-corridor-stage-v1.png")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const TRAY = preload("res://assets/runtime/workshop/kit-v1/tray.tres")
const SPINDLE = preload("res://assets/runtime/workshop/kit-v1/spindle.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const WINDOW = Rect2(36,196,352,168)
const OPEN = Rect2(440,460,232,54)
const RULER_LEFT = 440.0
const RULER_Y = 224.0
const RULER_W = 62.0
const RULER_GAP = 4.0
const RULER_H = 50.0
const PANEL = Rect2(440,292,816,156)
const COL_W = 252.0
const COL_GAP = 16.0
const COL_Y = 344.0
const COL_H = 96.0
const PLAQUE_LEFT = 684.0
const PLAQUE_W = 180.0
const PLAQUE_GAP = 12.0
const PLAQUE_Y = 460.0
const PLAQUE_H = 54.0
const VERDICT = Rect2(440,526,816,62)
# 三周期对照表属于第 2 档主动提示：正常界面只留时间尺、已锁时刻与自己开过的那一次窗，
# 不自动把关键中间量填给玩家。hint 到 2 才摊开三列累计数与迷你出料条。
const COMPARE_HINT = 2
const GREEN = Color("8fd694")
const RED = Color("f08a7a")
const GOLD = Color("f2cf7a")
var scene_id = "corridor"
var state = Rules.fresh()
var progress = 0.0
var presentation_paused = false
var land_progress = 1.0
var land_place = ""
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()

# 刚落下的那一下闪一圈：新比较的时刻、开窗、挂上的周期牌各一次。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_progress = 1.0
	if previous.is_empty() or state.stage != "puzzle" or previous.stage != "puzzle": return
	if state.opened and not previous.opened: land_place = "window"
	elif state.assigned != previous.assigned and state.assigned != 0: land_place = "plaque_%d"%state.assigned
	elif state.observe != previous.observe and state.observe != 0: land_place = "time_%d"%state.observe

func time_rect(t: int) -> Rect2:
	return Rect2(RULER_LEFT+(t-Rules.TIME_MIN)*(RULER_W+RULER_GAP),RULER_Y,RULER_W,RULER_H)
func open_rect() -> Rect2: return OPEN
func column_rect(i: int) -> Rect2:
	return Rect2(PANEL.position.x+12+i*(COL_W+COL_GAP),COL_Y,COL_W,COL_H)
func plaque_rect(period: int) -> Rect2:
	return Rect2(PLAQUE_LEFT+(period-Rules.PERIOD_MIN)*(PLAQUE_W+PLAQUE_GAP),PLAQUE_Y,PLAQUE_W,PLAQUE_H)

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
func words_center(value: String, center: Vector2, size_px: int, tint: Color) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	words_tint(value,center+Vector2(-width/2,size_px*0.36),size_px,tint)
func plaque(value: String, rect: Rect2, size_px: int = 19) -> void:
	draw_style_box(ArtStyle.sign_style(),rect)
	words(value,rect.position+Vector2(10,rect.size.y-10),size_px)

func draw_machine() -> void:
	var settle = 1.0
	if state.stage == "approach": settle = smoothstep(0,1,progress)
	prop(PRESS,Vector2(200,640),280,Color(1,1,1,0.55+0.45*settle))
	words("出料机 · 每 3 / 4 / 5 拍出一件",Vector2(46,388),18)

func draw_window() -> void:
	draw_rect(WINDOW,Color(0.05,0.07,0.08,0.9))
	draw_rect(Rect2(WINDOW.position+Vector2(5,5),WINDOW.size-Vector2(10,10)),Color("1b272b"))
	draw_rect(WINDOW,Color(1,1,1,0.18),false,3)
	plaque("出料窗",Rect2(WINDOW.position+Vector2(10,8),Vector2(104,34)),19)
	var readout = "先锁一个观察时刻"
	var tint = Color("fff0d1")
	if state.observe >= Rules.TIME_MIN:
		readout = "第 %d 拍 · 还没开窗"%state.observe
		if state.opened:
			readout = "第 %d 拍 · 累计 %d 件"%[state.observe,Rules.observed(state)]
			tint = GOLD
	words_tint(readout,WINDOW.position+Vector2(20,66),22,tint)
	if not state.opened:
		words("开窗只有一次，看准了再开。",WINDOW.position+Vector2(20,96),18)
		return
	var count = Rules.observed(state)
	var pop = 1.0 if state.stage != "delivery" else smoothstep(0,0.8,progress)
	var tray = WINDOW.position+Vector2(WINDOW.size.x/2,WINDOW.size.y-6)
	prop(TRAY,tray,170)
	var start = tray.x-(count-1)*15
	for i in range(count):
		if i >= int(ceil(count*pop)): break
		prop(SPINDLE,Vector2(start+i*30,tray.y-20),26)
	if count == 0:
		words("到这一拍还没出过件。",WINDOW.position+Vector2(20,140),18)

func draw_ruler() -> void:
	words("观察时刻：第 1～12 拍里选一拍（←/→ 或 A/D）",Vector2(RULER_LEFT,212),19)
	for t in range(Rules.TIME_MIN,Rules.TIME_MAX+1):
		var rect = time_rect(t)
		if state.observe == t:
			draw_rect(Rect2(rect.position-Vector2(4,4),rect.size+Vector2(8,8)),GOLD,false,3)
		elif state.tried.has(t):
			draw_rect(Rect2(rect.position-Vector2(3,3),rect.size+Vector2(6,6)),Color(0.72,0.63,0.42,0.9),false,2)
		if state.tried.has(t) and state.observe != t:
			draw_circle(rect.position+Vector2(rect.size.x-7,7),3.5,GOLD)

# 对照表只在第 2 档主动提示之后摊开；draw_column 自己再守一道，画面不会绕过这个判据。
func comparison_open() -> bool:
	return state.hint >= COMPARE_HINT

func draw_column(i: int) -> void:
	if not comparison_open(): return
	var period = Rules.PERIODS[i]
	var rect = column_rect(i)
	draw_rect(rect,Color(0.06,0.08,0.09,0.55))
	draw_rect(rect,Color(1,1,1,0.10),false,2)
	words("%d 拍一台"%period,rect.position+Vector2(12,26),19)
	var count = Rules.counts(state.observe)[i]
	words_tint("%d 件"%count,rect.position+Vector2(12,66),30,GOLD)
	# 迷你出料条：第 t 拍出过件的格子点亮，已过去的拍才画满。
	var left = rect.position.x+118
	for t in range(Rules.TIME_MIN,Rules.TIME_MAX+1):
		var x = left+(t-1)*11
		var made = t % period == 0 and t <= state.observe
		draw_rect(Rect2(x,rect.position.y+30,8,26),GOLD if made else Color(1,1,1,0.12))
	draw_rect(Rect2(left,rect.position.y+60,132,2),Color(1,1,1,0.16))
	words("到第 %d 拍为止出过 %d 次"%[state.observe,count],rect.position+Vector2(12,88),17)

func draw_comparison() -> void:
	draw_rect(PANEL,Color(0.07,0.09,0.11,0.42))
	draw_rect(PANEL,Color(1,1,1,0.12),false,2)
	plaque("同一时刻的三种累计数",Rect2(PANEL.position+Vector2(12,10),Vector2(360,38)),19)
	if not comparison_open():
		if state.observe < Rules.TIME_MIN:
			words("先锁一个观察时刻，再自己算三种周期各会累计多少件。",PANEL.position+Vector2(22,102),20)
		else:
			words("第 %d 拍锁定了。先自己算：三种周期各会累计多少件？"%state.observe,PANEL.position+Vector2(22,102),20)
		words("要看对照，按 H 用主动提示（求助级别会记进档案）。",PANEL.position+Vector2(22,132),18)
		return
	if state.observe < Rules.TIME_MIN:
		words("先锁一个观察时刻，这里会摊开三种周期在这一拍各自累计多少件。",PANEL.position+Vector2(22,102),20)
		return
	words("第 %d 拍"%state.observe,PANEL.position+Vector2(PANEL.size.x-146,44),20)
	for i in range(Rules.PERIODS.size()): draw_column(i)

func draw_plaques() -> void:
	if state.assigned != 0:
		var rect = plaque_rect(state.assigned)
		draw_rect(Rect2(rect.position-Vector2(4,4),rect.size+Vector2(8,8)),GOLD,false,3)

func draw_verdict() -> void:
	var text = ""
	var tint = Color("fff0d1")
	if state.observe < Rules.TIME_MIN:
		text = "还没锁观察时刻：先在 1～12 拍里选一拍。"
	elif not state.opened:
		text = "第 %d 拍 · 还没开窗：开窗只有一次，看准再开。"%state.observe
	elif not Rules.distinguishing(state.observe):
		text = "第 %d 拍 · %s，分不清周期；换一个时刻。"%[state.observe,Rules.collision_note(state.observe)]
		tint = RED
	elif state.observe > Rules.earliest():
		text = "第 %d 拍能分清，可第 %d 拍更早也能分清。"%[state.observe,Rules.earliest()]
		tint = RED
	elif state.assigned == 0:
		text = "第 %d 拍累计 %d 件 · 还没挂周期牌。"%[state.observe,Rules.observed(state)]
	elif Rules.solved(state):
		text = "第 %d 拍累计 %d 件 · 周期牌 %d 拍：可以确认。"%[state.observe,Rules.observed(state),state.assigned]
		tint = GREEN
	else:
		text = "第 %d 拍累计 %d 件，对应的是 %d 拍；挂的是 %d 拍。"%[
			state.observe,Rules.observed(state),state.period,state.assigned]
		tint = RED
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(text,VERDICT.position+Vector2(12,VERDICT.size.y-12),20,tint)

func draw_land_pulse() -> void:
	if land_place.is_empty() or land_progress >= 1.0: return
	var tint = Color(GOLD,0.9*(1.0-land_progress))
	if land_place == "window":
		draw_rect(Rect2(WINDOW.position-Vector2(6,6),WINDOW.size+Vector2(12,12)),tint,false,5)
	elif land_place.begins_with("plaque_"):
		var rect = plaque_rect(int(land_place.substr(7)))
		draw_rect(Rect2(rect.position-Vector2(5,5),rect.size+Vector2(10,10)),tint,false,4)
	elif land_place.begins_with("time_"):
		var rect = time_rect(int(land_place.substr(5)))
		draw_rect(Rect2(rect.position-Vector2(5,5),rect.size+Vector2(10,10)),tint,false,4)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	draw_machine()
	draw_window()
	draw_ruler()
	draw_comparison()
	draw_plaques()
	draw_verdict()
	draw_land_pulse()
	words("←/→ 选时刻 · O 开窗 · 3/4/5 挂周期牌 · Space 确认",Vector2(440,614),18)
	var dada = Vector2(398,642)
	contact(dada,24); prop(DADA,dada,78)
	words("嗒嗒",dada-Vector2(30,0),18)

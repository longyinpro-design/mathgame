extends Node2D
# GW13 休息桌现场：0～24 的时间尺横贯画面，上面两条叫点带分别是甲（每 4 拍）与乙（每 6 拍）。
# 玩家圈出的重合画成金圈套住整列，两个数量用 0～12 的候选牌提交；
# 叫点、重合、独鸣与判定全部读规则模块现算的结果，画面不另存叫点表。
const Rules = preload("res://scripts/workshop/gw13_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/old-chime-corridor-stage-v1.png")
const TRAY = preload("res://assets/runtime/workshop/kit-v1/tray.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_invite.tres")
const HEADER = Rect2(140,196,1100,40)
const LANE_LEFT = 140.0
const LANE_Y = [266.0,314.0]
const LANE_H = 44.0
const TICK_W = 44.0
const MARKS = Rect2(140,366,700,40)
const CHIP_LEFT = 372.0
const CHIP_STEP = 45.0
const CHIP_W = 44.0
const COUNT_Y = [414.0,468.0]
const COUNT_LABEL_W = 300.0
const VERDICT = Rect2(140,540,1000,46)
const TABLE_FOOT = Vector2(1110,516)
const DADA_FOOT = Vector2(1230,644)
const RING_R = 30.0
const RING_SQUASH = 1.62
const RING_Y = (LANE_Y[0]+LANE_Y[1]+LANE_H)/2
const GREEN = Color("8fd694")
const RED = Color("f08a7a")
const GOLD = Color("f2cf7a")
const BIRD_TINTS = [Color("e8b45c"),Color("8fc7c0")]
var scene_id = "corridor"
var state = Rules.fresh()
# 时间尺上指着的拍：只影响下一次按键从哪一列起，不进存档。
var cursor = 0
var progress = 0.0
var presentation_paused = false
var land_progress = 1.0
var land_place = ""
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()

# 刚圈上的那一列闪一圈：别的提交不动 land_place。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_progress = 1.0
	if previous.is_empty() or state.stage != "puzzle" or previous.stage != "puzzle": return
	for tick in state.marks:
		if not previous.marks.has(tick): land_place = "tick_%d"%tick

func tick_rect(tick: int) -> Rect2:
	return Rect2(LANE_LEFT+tick*TICK_W,238.0,TICK_W,124.0)
func count_rect(row: int, value: int) -> Rect2:
	return Rect2(CHIP_LEFT+value*CHIP_STEP,COUNT_Y[row],CHIP_W,44)
func count_label_rect(row: int) -> Rect2:
	return Rect2(56,COUNT_Y[row],COUNT_LABEL_W,44)
func ring_at(tick: int, radius: float, tint: Color, width: float = 3.5) -> void:
	draw_set_transform(Vector2(LANE_LEFT+tick*TICK_W+TICK_W/2,RING_Y),0,Vector2(1,RING_SQUASH))
	draw_arc(Vector2.ZERO,radius,0,TAU,64,tint,width,true)
	draw_set_transform(Vector2.ZERO)

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

func draw_header() -> void:
	plaque("两只玩具鸟第 0 拍一起叫：甲每 %d 拍、乙每 %d 拍（观察 0～%d 拍，两端都算）"%[
		Rules.PERIODS[0],Rules.PERIODS[1],Rules.HORIZON],HEADER,19)

# 每一拍一列：拍号在列顶，两条叫点带里的圆点就是「实际声音」。
func draw_ruler() -> void:
	for tick in range(Rules.HORIZON+1):
		var center = LANE_LEFT+tick*TICK_W+TICK_W/2
		draw_line(Vector2(center,LANE_Y[0]-8),Vector2(center,LANE_Y[0]-2),Color(1,1,1,0.28),2)
		words_center(str(tick),Vector2(center,250),17,Color("fff0d1"))

func draw_lane(bird: int) -> void:
	var y = LANE_Y[bird]
	draw_rect(Rect2(LANE_LEFT-4,y-4,Rules.HORIZON*TICK_W+TICK_W+8,LANE_H+8),Color(0.12,0.15,0.18,0.5))
	draw_rect(Rect2(LANE_LEFT,y,Rules.HORIZON*TICK_W+TICK_W,LANE_H),Color("2a3138"))
	for tick in Rules.calls(bird):
		var center = Vector2(LANE_LEFT+tick*TICK_W+TICK_W/2,y+LANE_H/2)
		draw_circle(center,11,Color(0.05,0.06,0.07,0.6))
		draw_circle(center,9,BIRD_TINTS[bird])
		draw_arc(center,9,0,TAU,24,Color(0.10,0.12,0.14,0.9),2,true)
	plaque("%s 每 %d 拍"%[Rules.BIRD_NAMES[bird],Rules.PERIODS[bird]],Rect2(20,y,112,LANE_H),17)

# 玩家圈出的重合：金圈套住整列，两端的圆点都看得见。
func draw_marks() -> void:
	for tick in state.marks: ring_at(tick,RING_R,GOLD)

func draw_land_pulse() -> void:
	if land_place.is_empty() or land_progress >= 1.0 or not land_place.begins_with("tick_"): return
	var tick = int(land_place.substr(5))
	ring_at(tick,RING_R+26*land_progress,Color(GOLD,0.9*(1.0-land_progress)),4)

func draw_marks_panel() -> void:
	plaque(Rules.marks_text(state),MARKS,19)

func draw_count_rows() -> void:
	for row in range(2):
		var value = Rules.count_of(state,row)
		# 提交前是候选牌（按钮自己画），其余阶段只把当时的两个数量读出来。
		if state.stage != "puzzle" and value < 0: continue
		plaque("%s？"%Rules.count_name(row),count_label_rect(row),18)
		if state.stage != "puzzle":
			plaque(str(value),Rect2(CHIP_LEFT,COUNT_Y[row],120,44),20)

func verdict_text() -> Array:
	if state.marks.is_empty():
		return ["先在时间尺上圈出两只鸟同拍的时刻。",Color("fff0d1")]
	if state.heard < 0 or state.solo < 0:
		var row = 0 if state.heard < 0 else 1
		return ["圈了 %d 处重合；再填「%s」。"%[state.marks.size(),Rules.count_name(row)],Color("fff0d1")]
	if Rules.solved(state):
		return ["总时刻 %d · 独鸣 %d · 与逐拍叫点相符，可以提交。"%[state.heard,state.solo],GREEN]
	return ["总时刻 %s · 独鸣 %s · 再对照时间尺上的叫点数一遍。"%[
		Rules.value_text(state.heard),Rules.value_text(state.solo)],RED]

func draw_verdict() -> void:
	var verdict = verdict_text()
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(verdict[0],VERDICT.position+Vector2(12,VERDICT.size.y-12),19,verdict[1])

# 两只鸟蹲在休息桌上：光标指到的那一拍，正在叫的那只会张开嘴。
func draw_bird(foot: Vector2, bird: int) -> void:
	var tint: Color = BIRD_TINTS[bird]
	var calling = Rules.callers(cursor).has(bird) and state.stage not in ["arrival","approach"]
	var body = foot+Vector2(0,-24)
	draw_colored_polygon(PackedVector2Array([body+Vector2(-14,-4),body+Vector2(-32,-14),body+Vector2(-28,6)]),tint.darkened(0.35))
	draw_circle(body,20,tint)
	draw_arc(body,20,0,TAU,32,Color(0.10,0.12,0.14,0.85),2,true)
	draw_colored_polygon(PackedVector2Array([body+Vector2(-2,-8),body+Vector2(-20,2),body+Vector2(-2,10)]),tint.darkened(0.22))
	var head = body+Vector2(15,-16)
	draw_circle(head,12,tint)
	draw_arc(head,12,0,TAU,24,Color(0.10,0.12,0.14,0.85),2,true)
	if calling:
		draw_colored_polygon(PackedVector2Array([head+Vector2(8,-5),head+Vector2(25,-9),head+Vector2(9,0)]),GOLD)
		draw_colored_polygon(PackedVector2Array([head+Vector2(8,1),head+Vector2(24,6),head+Vector2(9,7)]),GOLD)
	else:
		draw_colored_polygon(PackedVector2Array([head+Vector2(8,-4),head+Vector2(24,1),head+Vector2(8,6)]),GOLD)
	draw_circle(head+Vector2(3,-4),2.6,Color("22282b"))
	words_center(Rules.BIRD_NAMES[bird],body+Vector2(0,2),17,Color("2b2a1d"))
	draw_line(body+Vector2(-6,17),foot+Vector2(-6,-2),Color(0.35,0.28,0.16,0.9),2)
	draw_line(body+Vector2(6,17),foot+Vector2(6,-2),Color(0.35,0.28,0.16,0.9),2)
	if calling: words_tint("♪",head+Vector2(10,-32),18,GOLD)

# 走位那一格：休息桌和两只鸟从左边推进来；其余阶段就摆在原地。
func draw_rest_table() -> void:
	if state.stage == "arrival": return
	var slide = Vector2(-420*(1-smoothstep(0,0.8,progress)),0) if state.stage == "approach" else Vector2.ZERO
	var foot = TABLE_FOOT+slide
	contact(foot+Vector2(0,-4),64)
	prop(TRAY,foot,220)
	draw_bird(foot+Vector2(-52,-72),0)
	draw_bird(foot+Vector2(52,-72),1)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	draw_header()
	draw_ruler()
	draw_lane(0)
	draw_lane(1)
	draw_marks()
	draw_marks_panel()
	draw_count_rows()
	draw_verdict()
	draw_land_pulse()
	draw_rest_table()
	words("←/→ 移拍 · M 圈重合 · ↑/↓ 换数量 · Q/E 改数量 · Z 撤销 · X 重摆 · H 提示 · Space 提交",
		Vector2(150,634),17)
	var dada = DADA_FOOT
	contact(dada,26); prop(DADA,dada,84)
	words("嗒嗒",dada-Vector2(54,0),18)

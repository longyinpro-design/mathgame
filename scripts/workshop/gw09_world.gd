extends Node2D
# GW09 旧报时廊现场：12 盏灯围成一圈，0 号在最上面，顺时针编号。
# 玩家设好步长与第 3 站预测后一格一格跳：轨迹、停站顺序与两条判定全部按状态现画；
# 覆盖率与第 3 站由规则模块算，回 0 的那一跳用红金两色分开，漏灯一眼看得出。
const Rules = preload("res://scripts/workshop/gw09_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/old-chime-corridor-stage-v1.png")
const BELL = preload("res://assets/runtime/workshop/kit-v1/bell.tres")
const DIAL = preload("res://assets/runtime/workshop/kit-v1/dial.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const PANEL = Rect2(620,196,636,448)
const CENTER = Vector2(330,404)
const RADIUS = 176.0
const LAMP_R = 30.0
const STEP_LEFT = 648.0
const STEP_Y = 292.0
const STEP_W = 76.0
const STEP_GAP = 8.0
const PRED_LEFT = 634.0
const PRED_Y = 376.0
const PRED_W = 47.0
const PRED_GAP = 4.0
const JUMP = Rect2(632,570,612,52)
const VERDICT = Rect2(632,494,612,66)
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

# 刚落下的那一盏（或回 0 的那一跳）闪一圈：别的提交不动 land_place。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_progress = 1.0
	if previous.is_empty() or state.stage != "puzzle" or previous.stage != "puzzle": return
	if state.visited.size() > previous.visited.size():
		land_place = "lamp_%d"%state.visited[-1]
	elif Rules.returned(state) and not Rules.returned(previous):
		land_place = "return"

func step_rect(step: int) -> Rect2:
	return Rect2(STEP_LEFT+(step-Rules.STEP_MIN)*(STEP_W+STEP_GAP),STEP_Y,STEP_W,50)
func predict_rect(lamp: int) -> Rect2:
	return Rect2(PRED_LEFT+lamp*(PRED_W+PRED_GAP),PRED_Y,PRED_W,46)
func jump_rect() -> Rect2: return JUMP
func jump_half_rect() -> Rect2:
	return Rect2(JUMP.position,Vector2((JUMP.size.x-12)/2,JUMP.size.y))
func rerun_half_rect() -> Rect2:
	return Rect2(JUMP.position+Vector2((JUMP.size.x+12)/2,0),Vector2((JUMP.size.x-12)/2,JUMP.size.y))
func lamp_position(lamp: int) -> Vector2:
	var angle = -PI/2 + TAU*lamp/Rules.LAMPS
	return CENTER + Vector2(cos(angle),sin(angle))*RADIUS

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

func dashed_line(from: Vector2, to: Vector2, tint: Color, width: float = 3.0, dash: float = 11.0, gap: float = 8.0) -> void:
	var span = from.distance_to(to)
	if span <= 0.0: return
	var dir = (to-from)/span
	var at = 0.0
	while at < span:
		var end = minf(span,at+dash)
		draw_line(from+dir*at,from+dir*end,tint,width)
		at = end+gap
func dashed_ring(center: Vector2, radius: float, tint: Color) -> void:
	for i in range(18):
		if i%2 == 0: draw_arc(center,radius,i*TAU/18,(i+1)*TAU/18,6,tint,3,true)

func draw_track() -> void:
	draw_arc(CENTER,RADIUS,0,TAU,120,Color(0.07,0.09,0.10,0.62),18,true)
	draw_arc(CENTER,RADIUS,0,TAU,120,Color(0.62,0.55,0.36,0.55),2,true)
	for lamp in range(Rules.LAMPS):
		var p = lamp_position(lamp)
		var inward = (CENTER-p).normalized()
		draw_line(p+inward*(LAMP_R+7),p+inward*(LAMP_R+17),Color(0.62,0.55,0.36,0.45),2)

func draw_run_path() -> void:
	if state.step < Rules.STEP_MIN: return
	var points = [lamp_position(0)]
	for lamp in state.visited: points.append(lamp_position(lamp))
	var back = Rules.returned(state)
	if back: points.append(lamp_position(0))
	for i in range(points.size()-1):
		var a = points[i]; var b = points[i+1]
		var last = back and i == points.size()-2
		var tint = GOLD
		if last: tint = GREEN if Rules.covered(state) else RED
		draw_line(a,b,Color(0.05,0.06,0.07,0.75),9)
		draw_line(a,b,tint,5)
		var dir = (b-a).normalized()
		var side = Vector2(-dir.y,dir.x)
		draw_colored_polygon(PackedVector2Array([b-dir*18+side*7,b-dir*18-side*7,b-dir*2]),tint)
	# 下一跳预览：只画下一格，第 3 站还得自己数。
	if not back:
		var from = lamp_position(Rules.cursor(state))
		var to = lamp_position((Rules.cursor(state)+state.step) % Rules.LAMPS)
		dashed_line(from,to,Color(0.62,0.94,0.83,0.75),3)

func draw_claim() -> void:
	if state.step < Rules.STEP_MIN or state.third < 0: return
	var claimed = lamp_position(state.third)
	if state.jumps < Rules.RECORD_JUMP:
		dashed_ring(claimed,LAMP_R+11,Color(0.62,0.94,0.83,0.8))
		return
	var actual = Rules.third_stop(state.step)
	var tint = GREEN if actual == state.third else RED
	draw_arc(lamp_position(actual),LAMP_R+8,0,TAU,48,tint,4,true)
	if actual != state.third: dashed_ring(claimed,LAMP_R+11,Color(0.94,0.54,0.48,0.8))

func draw_lamp(lamp: int) -> void:
	var p = lamp_position(lamp)
	var visited = state.visited.has(lamp)
	var is_cursor = state.step >= Rules.STEP_MIN and not Rules.returned(state) and Rules.cursor(state) == lamp
	draw_circle(p,LAMP_R+3,Color(0.04,0.05,0.06,0.8))
	draw_circle(p,LAMP_R,GOLD if visited else Color(0.10,0.13,0.14,0.92))
	draw_arc(p,LAMP_R,0,TAU,48,GOLD if visited else Color(0.55,0.50,0.36,0.9),3,true)
	if lamp == 0: draw_arc(p,LAMP_R+7,0,TAU,48,Color(0.62,0.94,0.83,0.75),2,true)
	words_center(str(lamp),p,24,Color("2b2a1d") if visited else Color("fff0d1"))
	var order = state.visited.find(lamp)+1
	if order > 0:
		var badge = p+(CENTER-p).normalized()*(RADIUS-LAMP_R-19)
		draw_circle(badge,13,Color(0.08,0.10,0.11,0.95))
		draw_arc(badge,13,0,TAU,24,GOLD,2,true)
		words_center(str(order),badge,15,GOLD)
	if is_cursor: draw_arc(p,LAMP_R+5,0,TAU,48,Color("f5dc91"),4,true)

func draw_land_pulse() -> void:
	if land_place.is_empty() or land_progress >= 1.0: return
	var lamp = -1
	if land_place == "return": lamp = 0
	elif land_place.begins_with("lamp_"): lamp = int(land_place.substr(5))
	if lamp < 0: return
	var tint = RED if land_place == "return" else GOLD
	draw_arc(lamp_position(lamp),LAMP_R+6+26*land_progress,0,TAU,48,Color(tint,0.9*(1.0-land_progress)),5,true)

func third_text() -> String:
	if state.step < Rules.STEP_MIN or state.third < 0: return "第 3 站：还没写预测。"
	if state.jumps < Rules.RECORD_JUMP: return "第 3 站：预测 %d 号灯，还没跳到。"%state.third
	return "第 3 站：预测 %d · 实际 %d。"%[state.third,Rules.third_stop(state.step)]

func verdict_text() -> Array:
	if state.step < Rules.STEP_MIN:
		return ["还没设步长：先点一个 2～8 的步长。",Color("fff0d1")]
	if state.jumps == 0:
		return ["步长 %d · 还没起跑：按「跳一格」开始。"%state.step,Color("fff0d1")]
	if not Rules.returned(state):
		return ["步长 %d · 跳了 %d 次，现在停在 %d 号灯。"%[state.step,state.jumps,Rules.cursor(state)],Color("fff0d1")]
	if state.jumps < Rules.LAMPS:
		return ["步长 %d · 第 %d 跳就回到 0，只停过 %d 盏。"%[state.step,state.jumps,state.visited.size()],RED]
	if state.third < 0:
		return ["步长 %d · 跑完一圈停遍 11 盏；还没写预测。"%state.step,Color("fff0d1")]
	if Rules.solved(state):
		return ["步长 %d · 全覆盖 · 第 3 站 9 号灯：可以报时校准。"%state.step,GREEN]
	return ["步长 %d · 跑完一圈，第 3 站 %d 号灯；旧记录要 9。"%[state.step,Rules.third_stop(state.step)],RED]

func draw_panel() -> void:
	draw_rect(PANEL,Color(0.07,0.09,0.11,0.42))
	draw_rect(PANEL,Color(1,1,1,0.12),false,2)
	plaque("旧报时记录：第 3 次跳动后停在 9 号灯",Rect2(632,206,612,44),19)
	words("① 设步长：每次固定走 2～8 格，途中不改。",Vector2(636,284),18)
	words("② 预测第 3 次跳动停在哪一盏。",Vector2(636,368),18)
	var readout = "还没起跑：按「跳一格」开始这一圈。"
	if state.step < Rules.STEP_MIN: readout = "还没设步长。"
	elif state.jumps > 0:
		readout = "跳了 %d 次 · 停过 %d / 11 盏 · 现在停在 %d 号灯。"%[state.jumps,state.visited.size(),Rules.cursor(state)]
	words(readout,Vector2(636,450),18)
	words(third_text(),Vector2(636,474),18)
	var verdict = verdict_text()
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(verdict[0],VERDICT.position+Vector2(12,VERDICT.size.y-12),19,verdict[1])
	words("J 跳一格 · R 重跑 · ←/→ 换步长 · Q/E 换预测",Vector2(636,638),17)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	draw_track()
	draw_run_path()
	draw_claim()
	for lamp in range(Rules.LAMPS): draw_lamp(lamp)
	draw_land_pulse()
	draw_panel()
	var bell = Vector2(108,642)
	contact(bell,20); prop(BELL,bell,68)
	var dial = Vector2(100,286)
	contact(dial,16); prop(DIAL,dial,88)
	var dada = Vector2(560,644)
	contact(dada,24); prop(DADA,dada,88)
	words("嗒嗒",dada-Vector2(30,0),18)

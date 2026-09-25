extends Node2D
# GW16 屋顶修理街现场：左边一排四格午休铃架，右边一块收集板。
# 段长、合计拍数、循环首尾关系与已收集清单全部由引擎绘制；合法与否由规则模块现算，画面不另存判定。
# 收下新的一首时，收集板上那一枚从上方落下；交货时铃架按当前一段一段亮起来。
const Rules = preload("res://scripts/workshop/gw16_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/rooftop-repair-street-stage-v1.png")
const BELL = preload("res://assets/runtime/workshop/kit-v1/bell.tres")
const PLATE = preload("res://assets/runtime/workshop/kit-v1/plate.tres")
const LEVER = preload("res://assets/runtime/workshop/kit-v1/lever.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const RACK = Rect2(24,196,760,330)
const BOARD = Rect2(800,196,456,330)
const VERDICT = Rect2(24,536,1232,40)
const SLOT_LEFT = 44.0
const SLOT_Y = 244.0
const SLOT_W = 168.0
const SLOT_H = 216.0
const SLOT_STEP = 180.0
const LENGTH_Y = 584.0
const LENGTH_W = 72.0
const LENGTH_STEP = 76.0
const LISTEN = Rect2(270,584,140,44)
const SAVE = Rect2(422,584,150,44)
const BOARD_ROW_Y = 254.0
const BOARD_ROW_STEP = 58.0
const BOARD_CHIP = Vector2(150,44)
const BOARD_CHIP_X = 918.0
const BOARD_CHIP_STEP = 158.0
const GREEN = Color("8fd694")
const RED = Color("f08a7a")
const GOLD = Color("f2cf7a")
var scene_id = "rooftop"
var state = Rules.fresh()
var progress = 0.0
var presentation_paused = false
var land_progress = 1.0
var land_place = ""
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()

# 收下一首新曲子时让它在收集板上落位；取段、试听与换曲都不演出。
func begin_land(previous: Dictionary) -> void:
	land_place = ""
	if previous.saved.size() < state.saved.size(): land_place = "save"
	land_progress = 1.0

func slot_rect(index: int) -> Rect2:
	return Rect2(SLOT_LEFT+index*SLOT_STEP,SLOT_Y,SLOT_W,SLOT_H)
func length_rect(length: int) -> Rect2:
	return Rect2(24+(length-Rules.LENGTH_MIN)*LENGTH_STEP,LENGTH_Y,LENGTH_W,44)
func listen_rect() -> Rect2: return LISTEN
func save_rect() -> Rect2: return SAVE
func group_row(first: int) -> int:
	return first-Rules.LENGTH_MIN
# 收集板按首段分类：同一首段的一行，行内按收下的先后排。
func tune_rect(index: int) -> Rect2:
	var order: Array = state.saved[index]
	var column = 0
	for other in range(index):
		if state.saved[other][0] == order[0]: column += 1
	return Rect2(BOARD_CHIP_X+column*BOARD_CHIP_STEP,BOARD_ROW_Y+group_row(order[0])*BOARD_ROW_STEP,
		BOARD_CHIP.x,BOARD_CHIP.y)

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
func words_center(value: String, center_x: float, y: float, size_px: int, tint: Color) -> void:
	draw_string_outline(font,Vector2(center_x-400,y),value,HORIZONTAL_ALIGNMENT_CENTER,800,size_px,4,Color("21313c"))
	draw_string(font,Vector2(center_x-400,y),value,HORIZONTAL_ALIGNMENT_CENTER,800,size_px,tint)
func plaque(value: String, rect: Rect2, size_px: int = 19) -> void:
	draw_style_box(ArtStyle.sign_style(),rect)
	words(value,rect.position+Vector2(10,rect.size.y-10),size_px)

# 走位时整座铃架从下往上推入；交货时铃架留在原地，由高亮一段一段地唱。
func flow_offset() -> Vector2:
	if state.stage == "approach": return Vector2(0,150*(1-smoothstep(0,1,progress)))
	return Vector2.ZERO

# 留了午休曲之后，铃架上显示的就是那首；否则显示玩家正在排的草稿。
func shown_segments() -> Array:
	if state.chosen >= 0 and state.chosen < state.saved.size(): return state.saved[state.chosen]
	return state.segments

func draw_slot(index: int, off: Vector2, shown: Array) -> void:
	var rect = Rect2(slot_rect(index).position+off,slot_rect(index).size)
	var playing = state.stage == "delivery" and index == mini(Rules.SEGMENTS-1,int(progress*Rules.SEGMENTS))
	draw_rect(rect,Color(0.07,0.09,0.11,0.42))
	draw_rect(rect,Color(1,1,1,0.14),false,2)
	if playing: draw_rect(rect.grow(3),GOLD,false,3)
	words("第 %d 段"%[index+1],rect.position+Vector2(10,26),18)
	if index >= shown.size():
		words_center("空",rect.position.x+rect.size.x/2,rect.position.y+130,22,Color(1,1,1,0.32))
		return
	var length: int = shown[index]
	var bar = Rect2(rect.position+Vector2(14,52),Vector2(rect.size.x-28,10))
	draw_rect(bar,Color("6b4a33"))
	draw_rect(bar,Color(0,0,0,0.25),false,2)
	prop(PLATE,Vector2(rect.position.x+rect.size.x/2,rect.position.y+196),140)
	var step = (rect.size.x-36)/float(length)
	for beat in range(length):
		var x = rect.position.x+18+step*(beat+0.5)
		draw_line(Vector2(x,rect.position.y+62),Vector2(x,rect.position.y+112),Color("d8c9a6"),1.0)
		prop(BELL,Vector2(x,rect.position.y+156),minf(34,step-4))
	words_tint("%d 拍"%length,rect.position+Vector2(16,192),19,GREEN if length == 3 else Color("fff0d1"))

# 循环首尾关系：铃架下方一条回环箭头，把末段接回首段；相同就当场标红。
func draw_loop(off: Vector2, shown: Array) -> void:
	var left = SLOT_LEFT+SLOT_W/2+off.x
	var right = SLOT_LEFT+(Rules.SEGMENTS-1)*SLOT_STEP+SLOT_W/2+off.x
	var top = SLOT_Y+SLOT_H+off.y
	var y = top+26
	var color = Color(1,1,1,0.35)
	var text = "循环播放：末段接回首段"
	if shown.size() == Rules.SEGMENTS:
		if shown[0] == shown[Rules.SEGMENTS-1]:
			color = RED; text = "末段与首段都是 %d 拍：接不上"%shown[0]
		else:
			color = GREEN; text = "末段 %d 与首段 %d 不同，循环接得上"%[shown[Rules.SEGMENTS-1],shown[0]]
	draw_polyline(PackedVector2Array([Vector2(right,top),Vector2(right,y),Vector2(left,y),Vector2(left,top)]),color,2.0,true)
	draw_colored_polygon(PackedVector2Array([Vector2(left,top),Vector2(left-7,top+16),Vector2(left+7,top+16)]),color)
	words_center(text,(left+right)/2,y+22,19,color)

func draw_tune_chip(index: int, at: Vector2) -> void:
	var rect = Rect2(at,BOARD_CHIP)
	var picked = index == state.chosen
	var landing = land_place == "save" and index == state.saved.size()-1 and land_progress < 1
	if landing: rect.position += Vector2(0,-60*(1-smoothstep(0,1,land_progress)))
	draw_rect(rect,GOLD if picked else Color(0.12,0.2,0.17,0.9))
	draw_rect(rect,GOLD if picked else Color(1,1,1,0.25),false,2 if picked else 1)
	var text = Rules.order_text(state.saved[index])
	if picked: text = "★ " + text
	words_tint(text,rect.position+Vector2(12,rect.size.y-12),19,Color("26372b") if picked else Color("fff0d1"))

# 收集板按首段分类：首段 2、3、4 各一行，重存同一首不会多出一枚。
func draw_board() -> void:
	draw_rect(BOARD,Color(0.07,0.09,0.11,0.34))
	draw_rect(BOARD,Color(1,1,1,0.12),false,2)
	plaque("收集板 · 已收 %d / %d 首"%[state.saved.size(),Rules.TUNES],
		Rect2(BOARD.position+Vector2(12,10),Vector2(432,36)))
	for first in range(Rules.LENGTH_MIN,Rules.LENGTH_MAX+1):
		var y = BOARD_ROW_Y+group_row(first)*BOARD_ROW_STEP
		words("首段 %d 拍"%first,Vector2(BOARD.position.x+12,y+28),19)
		var column = 0
		for index in range(state.saved.size()):
			if state.saved[index][0] != first: continue
			draw_tune_chip(index,Vector2(BOARD_CHIP_X+column*BOARD_CHIP_STEP,y))
			column += 1
	words_tint("重存同一首不算新的：按首段分类，不重不漏。",BOARD.position+Vector2(12,286),18,Color("fff0d1"))

func draw_verdict() -> void:
	var text = ""
	var tint = Color("fff0d1")
	if state.stage in ["arrival","approach","ready"]:
		text = "每首 4 段 · 合计 12 拍 · 恰好两段 3 拍 · 相邻与首尾都不能相同"
	elif state.stage == "puzzle":
		if state.segments.size() < Rules.SEGMENTS:
			text = "铃架还差 %d 段：每段从 2、3、4 拍里选。"%(Rules.SEGMENTS-state.segments.size())
		else:
			var problems = Rules.phrase_problems(state.segments)
			if problems.is_empty():
				text = "%s · 接得上，可以保存。"%Rules.order_text(state.segments)
				if state.saved.has(state.segments): text += "（这首已经收下）"
				tint = GREEN
			else:
				text = "%s · %s"%[Rules.order_text(state.segments),"；".join(problems.slice(0,2))]
				if problems.size() > 2: text += "（还有 %d 处）"%(problems.size()-2)
				tint = RED
	elif state.chosen >= 0 and state.chosen < state.saved.size():
		var order = state.saved[state.chosen]
		if state.stage == "delivery":
			text = "午休曲 %s · 循环到第 %d / %d 拍"%[Rules.order_text(order),
				clampi(int(progress*Rules.TOTAL_BEATS)+1,1,Rules.TOTAL_BEATS),Rules.TOTAL_BEATS]
		else:
			text = "午休曲 %s · 四首收齐，不重不漏。"%Rules.order_text(order)
		tint = GREEN
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(text,VERDICT.position+Vector2(12,VERDICT.size.y-11),19,tint)

func draw_controls() -> void:
	if state.stage != "puzzle": return
	words("排满四段 → 试听 T → 保存 S",Vector2(600,614),18)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	var off = flow_offset()
	var shown = shown_segments()
	draw_rack_panel(off,shown)
	draw_board()
	draw_verdict()
	draw_controls()
	var dada = Vector2(1205,622)
	contact(dada,24); prop(DADA,dada,84)
	words("嗒嗒",dada-Vector2(20,0),18)

func draw_rack_panel(off: Vector2, shown: Array) -> void:
	var panel = Rect2(RACK.position+off,RACK.size)
	draw_rect(panel,Color(0.07,0.09,0.11,0.34))
	draw_rect(panel,Color(1,1,1,0.12),false,2)
	plaque("午休铃架 · 四段",Rect2(panel.position+Vector2(12,10),Vector2(200,36)))
	var total = Rules.beats(shown)
	draw_style_box(ArtStyle.sign_style(),Rect2(panel.position+Vector2(452,10),Vector2(296,36)))
	words_tint("合计 %d / %d 拍"%[total,Rules.TOTAL_BEATS],panel.position+Vector2(464,36),19,
		GREEN if total == Rules.TOTAL_BEATS else Color("fff0d1"))
	for index in range(Rules.SEGMENTS): draw_slot(index,off,shown)
	draw_loop(off,shown)
	prop(LEVER,Vector2(740,522)+off,52)

extends Node2D
# GW14 装配间现场：维修盒推上台面，三张复测记录并排挂开，每张记录挂着「列候选」与「复演」。
# 候选枚数、三种托的复演（满托排开、零散留在旁边）与下面的排除表都由规则模块现算；
# 画面只负责摆出来，换候选不会留下旧判定。
const Rules = preload("res://scripts/workshop/gw14_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/rooftop-repair-street-stage-v1.png")
const TRAY = preload("res://assets/runtime/workshop/kit-v1/tray.tres")
const SPINDLE = preload("res://assets/runtime/workshop/kit-v1/spindle.tres")
const BOX = preload("res://assets/runtime/workshop/kit-v1/box.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const Batch2 = preload("res://scripts/workshop/batch2.gd")
const PANEL_TOP = 190.0
const PANEL_W = 400.0
const PANEL_H = 330.0
const PANEL_STEP = 416.0
const CHIP_LEFT = 8.0
const CHIP_TOP = 292.0
const CHIP_W = 44.0
const CHIP_H = 44.0
const CHIP_COLS = 8
const CHIP_STEP = 48.0
const CHIP_ROW = 46.0
const TABLE = Rect2(24,528,980,112)
const GREEN = Color("8fd694")
const RED = Color("f08a7a")
const DIM = Color("c9c2ad")
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

# 复演一张记录的那一下：这一张的满托从空台面上一个个排出来。
func begin_land(previous: Dictionary) -> void:
	land_place = ""
	for record in range(3):
		if not Rules.tested(previous,record).has(state.count) and Rules.tested(state,record).has(state.count):
			land_place = "record_%d"%record
	land_progress = 1.0

func panel_rect(record: int) -> Rect2:
	return Rect2(24+record*PANEL_STEP,PANEL_TOP,PANEL_W,PANEL_H)
func list_rect(record: int) -> Rect2:
	return Rect2(panel_rect(record).position+Vector2(10,50),Vector2(148,44))
func replay_rect(record: int) -> Rect2:
	return Rect2(panel_rect(record).position+Vector2(166,50),Vector2(224,44))
func chip_rect(record: int, index: int) -> Rect2:
	var col = index % CHIP_COLS
	var row = floori(index/float(CHIP_COLS))
	return Rect2(panel_rect(record).position+Vector2(CHIP_LEFT+col*CHIP_STEP,CHIP_TOP-PANEL_TOP+row*CHIP_ROW),Vector2(CHIP_W,CHIP_H))

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

# 走位时三张记录从下往上推入；交货时整排往右送出去。
func flow_offset() -> Vector2:
	if state.stage == "approach": return Vector2(0,170*(1-smoothstep(0,1,progress)))
	if state.stage == "delivery": return Vector2(430*smoothstep(0.1,0.75,progress),0)
	return Vector2.ZERO

# 一张记录的复演：满托按行排开、零散留在下面，等式与判定都由规则模块现算。
func draw_replay(record: int, rect: Rect2) -> void:
	if state.count < Rules.BOX_MIN:
		words_tint("提出候选后，这里按 %d 一托复演。"%Rules.TRAYS[record],rect.position+Vector2(20,216),18,DIM)
		return
	if not Rules.tested(state,record).has(state.count):
		words_tint("%d 枚还没按 %d 一托复演过。"%[state.count,Rules.TRAYS[record]],rect.position+Vector2(20,216),18,DIM)
		return
	var parts = Rules.division(state.count,Rules.TRAYS[record])
	words("%d = %d × %d + 剩 %d"%[state.count,parts[0],Rules.TRAYS[record],parts[1]],
		rect.position+Vector2(20,216),19)
	var ok = parts[1] == Rules.REMAINDERS[record]
	words_tint("与%s相符。"%Rules.RECORD_NAMES[record] if ok else "记录写的是剩 %d 枚，对不上。"%Rules.REMAINDERS[record],
		rect.position+Vector2(20,240),19,GREEN if ok else RED)
	var shown = parts[0]
	if land_place == "record_%d"%record: shown = clampi(ceili(land_progress*parts[0]),0,parts[0])
	var per_row = 10
	for i in range(shown):
		var row = floori(i/float(per_row)); var col = i%per_row
		prop(TRAY,rect.position+Vector2(20+col*36+17,262+row*16),34)
	var left = rect.position.x+20
	for i in range(parts[1]):
		prop(SPINDLE,Vector2(left+6,rect.position.y+310),11)
		left += 14
	if parts[1] == 0:
		words_tint("零散 0 枚",Vector2(left,rect.position.y+306),17,DIM)

func draw_panel(record: int, off: Vector2) -> void:
	var rect = Rect2(panel_rect(record).position+off,panel_rect(record).size)
	draw_rect(rect,Color(0.07,0.09,0.11,0.42))
	draw_rect(rect,Color(1,1,1,0.12),false,2)
	plaque("%s · 按 %d 一托，剩 %d 枚"%[Rules.RECORD_NAMES[record],Rules.TRAYS[record],Rules.REMAINDERS[record]],
		Rect2(rect.position+Vector2(10,8),Vector2(380,36)),19)
	if state.listed.has(record):
		words_tint("%d 个候选"%Rules.candidates(record).size(),rect.position+Vector2(300,34),17,DIM)
	else:
		words_tint("先「列候选」，看看哪些枚数说得通。",rect.position+Vector2(20,150),18,DIM)
	draw_replay(record,rect)

# 排除表：列是试过的候选，行是三张记录与结论。✓ 用汉字写出，不靠符号字体。
func draw_table(off: Vector2) -> void:
	var rect = Rect2(TABLE.position+off,TABLE.size)
	draw_rect(rect,Color(0.07,0.09,0.11,0.46))
	draw_rect(rect,Color(1,1,1,0.12),false,2)
	var tried = Rules.tried_counts(state)
	var title = "排除表 · 试过的候选"
	if tried.size() > 6: title += "（只列前 6 个，共 %d 个）"%tried.size()
	words(title,rect.position+Vector2(10,20),17)
	if tried.is_empty():
		words_tint("还没有复演过任何候选：先列候选，再挑一个枚数复演。",rect.position+Vector2(10,52),17,DIM)
		return
	var shown = tried.slice(0,6)
	for i in range(shown.size()):
		words("%d 枚"%shown[i],rect.position+Vector2(190+i*138,20),17)
	var labels = ["记录一 · 4 一托","记录二 · 6 一托","记录三 · 5 一托"]
	for row in range(3):
		words(labels[row],rect.position+Vector2(10,42+row*20),16)
		for i in range(shown.size()):
			var mark = Rules.verdict(state,row,shown[i])
			var tint = GREEN if mark == "相符" else (RED if mark == "不符" else DIM)
			words_tint(mark,rect.position+Vector2(190+i*138,42+row*20),16,tint)
	words("结论",rect.position+Vector2(10,102),16)
	for i in range(shown.size()):
		var st = Rules.chip_state(state,shown[i])
		var text = "全相符" if st == "定下" else ("排除" if st == "排除" else "还差复演")
		var tint = GREEN if st == "定下" else (RED if st == "排除" else DIM)
		words_tint(text,rect.position+Vector2(190+i*138,102),16,tint)

# 当前候选的金框：画在候选牌外面，和按钮的底不打架。候选牌只在解题这一幕存在。
func draw_marks(off: Vector2) -> void:
	if state.stage != "puzzle": return
	for record in range(3):
		if not state.listed.has(record): continue
		var index = Rules.candidates(record).find(state.count)
		if index < 0: continue
		var chip = Rect2(chip_rect(record,index).position+off,Vector2(CHIP_W,CHIP_H))
		draw_rect(Rect2(chip.position-Vector2(3,3),chip.size+Vector2(6,6)),Color("f2cf7a"),false,3)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	var off = flow_offset()
	for record in range(3): draw_panel(record,off)
	draw_table(off)
	draw_marks(off)
	# 三张记录台下的维修页架，翻页用的那件。
	Batch2.draw_part(self,"page_rack",Vector2(700,640),90)
	contact(Vector2(1085,638),26)
	prop(BOX,Vector2(1085,638),112)
	contact(Vector2(1215,640),24)
	prop(DADA,Vector2(1215,640),80)
	words("嗒嗒",Vector2(1197,640),18)

extends Node2D
# GW12 装配间现场：左右两块台面分别是第一班与第二班，右上角挂着交接册。
# 槽盘、满托、余料盒与两班合计全部由引擎绘制；道具只提供托盘、灯轴、维修盒与嗒嗒的造型。
# 满托数、余料与合计一律由规则模块现算，画面不另存除法结果，换槽数不会留下旧判定。
const Rules = preload("res://scripts/workshop/gw12_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/rooftop-repair-street-stage-v1.png")
const TRAY = preload("res://assets/runtime/workshop/kit-v1/tray.tres")
const SPINDLE = preload("res://assets/runtime/workshop/kit-v1/spindle.tres")
const BOX = preload("res://assets/runtime/workshop/kit-v1/box.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const Batch2 = preload("res://scripts/workshop/batch2.gd")
const PANEL = [Rect2(24,248,608,326),Rect2(648,248,608,326)]
const BOOK = Rect2(830,196,426,44)
const TALLY = Rect2(24,584,900,44)
const CAP_LEFT = 140.0
const CAP_Y = 196.0
const CAP_W = 62.0
const CAP_STEP = 66.0
const KEEP_LEFT = 176.0
const KEEP_Y = 584.0
const KEEP_W = 58.0
const KEEP_STEP = 62.0
const GREEN = Color("8fd694")
const RED = Color("f08a7a")
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

# 余料落盒的那一下：第一次交班、最后收工各演一次，盒子里的灯轴一枚枚落进去。
func begin_land(previous: Dictionary) -> void:
	land_place = ""
	if previous.first_keep < 0 and state.first_keep >= 0: land_place = "first"
	elif previous.second_keep < 0 and state.second_keep >= 0: land_place = "second"
	land_progress = 1.0

func capacity_rect(capacity: int) -> Rect2:
	return Rect2(CAP_LEFT+(capacity-Rules.CAP_MIN)*CAP_STEP,CAP_Y,CAP_W,44)
func keep_rect(keep: int) -> Rect2:
	return Rect2(KEEP_LEFT+keep*KEEP_STEP,KEEP_Y,KEEP_W,44)

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

# 走位时两块台面从下往上推入；交货时满托整排往右送出去。
func flow_offset() -> Vector2:
	if state.stage == "approach": return Vector2(0,150*(1-smoothstep(0,1,progress)))
	if state.stage == "delivery": return Vector2(340*smoothstep(0.1,0.75,progress),0)
	return Vector2.ZERO

# 满托：一只槽盘壳，里面按槽数点出孔位；槽数一眼可数，不必先做除法。
func draw_tray_chip(at: Vector2, capacity: int) -> void:
	prop(TRAY,at,84)
	var rows = 1 if capacity <= 6 else 2
	var per = int(ceil(capacity/float(rows)))
	for i in range(capacity):
		var row = i/per; var col = i%per
		var span = 62.0
		var x = at.x-span/2+(col+0.5)*span/per
		var y = at.y-24+(row+0.5)*13
		draw_circle(Vector2(x,y),2.8,Color("4a3a28"))

# 还没分托的散件：一堆灯轴，只表现「有这么多」，除法留给玩家自己做。
func draw_pile(foot: Vector2, count: int, tint: Color = Color.WHITE) -> void:
	for i in range(count):
		var row = i/8; var col = i%8
		prop(SPINDLE,foot+Vector2(col*26+(12 if row%2 else 0),-row*30),18,tint)

# 余料盒里按行码灯轴：容量 11 的盒子装得下所有 3～12 槽的合法余料。
func draw_box(rect: Rect2, kept: int, landing: bool) -> void:
	var foot = rect.position+Vector2(rect.size.x-110,rect.size.y)
	var shown = kept
	if landing: shown = clampi(ceili(land_progress*kept),0,kept)
	prop(BOX,foot,150)
	for i in range(shown):
		var row = i/5; var col = i%5
		prop(SPINDLE,foot-Vector2(38-col*19,58+row*20),14)

func draw_panel(index: int, off: Vector2) -> void:
	var rect = Rect2(PANEL[index].position+off,PANEL[index].size)
	var first = index == 0
	var kept = state.first_keep if first else state.second_keep
	var total = Rules.FIRST if first else Rules.second_total(state)
	draw_rect(rect,Color(0.07,0.09,0.11,0.42))
	draw_rect(rect,Color(1,1,1,0.12),false,2)
	plaque("%s · %d 枚"%["第一班" if first else "第二班",total],
		Rect2(rect.position+Vector2(12,10),Vector2(300,36)))
	if state.capacity >= Rules.CAP_MIN:
		plaque("每托 %d 枚"%state.capacity,Rect2(rect.position+Vector2(460,10),Vector2(136,36)),19)
	else:
		plaque("槽数未定",Rect2(rect.position+Vector2(460,10),Vector2(136,36)),19)
	# 台面：还没执行就摆散件，执行过就摆满托。
	if kept < 0 or state.capacity < Rules.CAP_MIN:
		draw_pile(rect.position+Vector2(40,236),total)
		var idle = "%d 枚标准件"%total
		if state.stage not in ["arrival","approach","ready"]:
			idle = "%d 枚散件 · 还没交班"%total if first else "%d 枚散件 · 还没收工"%total
		words(idle,rect.position+Vector2(20,276),19)
	else:
		var trays = Rules.first_trays(state) if first else Rules.second_trays(state)
		for i in range(trays):
			draw_tray_chip(rect.position+Vector2(60+(i%4)*92,100+floori(i/4.0)*54),state.capacity)
		if trays == 0:
			words("没有满托可交",rect.position+Vector2(20,150),19)
		words("%d 枚 = %d 个满托 × %d 枚 + 留 %d 枚"%[total,trays,state.capacity,kept],
			rect.position+Vector2(20,276),19)
	# 余料盒
	plaque("余料盒",Rect2(rect.position+Vector2(400,56),Vector2(196,34)),18)
	draw_box(Rect2(rect.position+Vector2(400,56),Vector2(196,232)),maxi(kept,0),
		(land_place == "first" and first) or (land_place == "second" and not first))
	var kept_text = "留 %d 枚"%kept if kept >= 0 else "空着"
	plaque(kept_text,Rect2(rect.position+Vector2(400,292),Vector2(196,30)),18)

func draw_book() -> void:
	# 交接册：两班一共交 9 个满托、最后还剩 2 枚，是开局就确定的凭据。
	draw_style_box(ArtStyle.sign_style(),BOOK)
	var cover = Rect2(BOOK.position+Vector2(12,6),Vector2(34,32))
	draw_rect(cover,Color("7a4a35"))
	draw_rect(Rect2(cover.position+Vector2(6,4),Vector2(26,24)),Color("efe0c2"))
	for line in range(3):
		draw_rect(Rect2(cover.position+Vector2(9,9+line*7),Vector2(20,2)),Color("9c8b6d"))
	words("交接册 · 两班共交 9 个满托 · 最后剩 2 枚",BOOK.position+Vector2(56,33),18)

func draw_labels() -> void:
	if state.stage != "puzzle": return
	words("每托槽数 →",Vector2(24,224),20)
	if state.capacity < Rules.CAP_MIN: return
	if state.first_keep < 0: words("第一班留几枚 →",Vector2(24,612),19)
	elif state.second_keep < 0: words("最后留几枚 →",Vector2(24,612),19)

func draw_tally() -> void:
	if state.stage != "puzzle": return
	if state.capacity < Rules.CAP_MIN:
		plaque("先从 3～12 里提出一个槽数，再分两班执行。",TALLY,19)
		return
	if state.first_keep < 0 or state.second_keep < 0: return
	var ok = Rules.solved(state)
	var text = "第一班 %d 托 ＋ 第二班 %d 托 ＝ %d 托 · 最后剩 %d 枚"%[
		Rules.first_trays(state),Rules.second_trays(state),Rules.total_trays(state),state.second_keep]
	if not ok: text += "（交接册：9 托、剩 2 枚）"
	draw_style_box(ArtStyle.sign_style(),TALLY)
	words_tint(text,TALLY.position+Vector2(12,TALLY.size.y-11),19,GREEN if ok else RED)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	var off = flow_offset()
	draw_book()
	for index in range(2): draw_panel(index,off)
	draw_labels()
	draw_tally()
	var dada = Vector2(1205,622)
	contact(dada,24); prop(DADA,dada,84)
	words("嗒嗒",dada-Vector2(20,0),18)
	# 装配班长弥师傅站在两张台面中间，两班的交接都经他的手。
	var shifu = Vector2(620,636)
	contact(shifu,30); Batch2.draw_part(self,"mi_shifu",shifu,80)
	words("弥师傅",shifu-Vector2(34,0),18)

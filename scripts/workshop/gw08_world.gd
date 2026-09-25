extends Node2D
# GW08 旧报时廊现场：两张维修记录并排，左边一块还没配容量牌的旧槽板。
# 重演一张记录时，按当前候选槽数真的分一遍：满托排开、零散数单独留在旁边；
# 余数与记录不符就当场标红。除法、候选与排除表都由规则模块算，画面只负责摆出来。
const Rules = preload("res://scripts/workshop/gw08_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/assembly-room-stage-v1.png")
const TRAY = preload("res://assets/runtime/workshop/kit-v1/tray.tres")
const SPINDLE = preload("res://assets/runtime/workshop/kit-v1/spindle.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_hold.tres")
const PANEL = [Rect2(24,196,608,330),Rect2(648,196,608,330)]
const VERDICT = Rect2(24,536,900,40)
const CAP_LEFT = 186.0
const CAP_Y = 584.0
const CAP_W = 72.0
const CAP_STEP = 76.0
const GREEN = Color("8fd694")
const RED = Color("f08a7a")
var scene_id = "assembly"
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

func capacity_rect(capacity: int) -> Rect2:
	return Rect2(CAP_LEFT+(capacity-Rules.CAP_MIN)*CAP_STEP,CAP_Y,CAP_W,44)
func replay_rect(record: int) -> Rect2:
	var rect: Rect2 = PANEL[record]
	return Rect2(rect.position.x+rect.size.x-158,rect.position.y+10,146,44)

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

func mark(record: int) -> String:
	return Rules.mark(state,record)

func draw_tray_chip(at: Vector2, capacity: int) -> void:
	prop(TRAY,at+Vector2(32,32),66)
	words(str(capacity),at+Vector2(22,26),18)

func draw_record(record: int) -> void:
	var rect: Rect2 = PANEL[record]
	draw_rect(rect,Color(0.07,0.09,0.11,0.42))
	draw_rect(rect,Color(1,1,1,0.12),false,2)
	plaque("记录%s：%d 根 · 满托后剩 %d 根"%[["一","二"][record],Rules.RECORDS[record],Rules.REMAINDERS[record]],
		Rect2(rect.position+Vector2(12,10),Vector2(400,38)),19)
	if state.capacity < Rules.CAP_MIN:
		words("先提出槽数，再重演这张记录。",rect.position+Vector2(22,92),19)
		return
	if not Rules.tested(state,record).has(state.capacity):
		words("这张记录还没重演过。",rect.position+Vector2(22,92),19)
		return
	var parts = Rules.division(Rules.RECORDS[record],state.capacity)
	var left = rect.position.x+22
	var y = rect.position.y+70
	for i in range(parts[0]):
		draw_tray_chip(Vector2(left,y),state.capacity)
		left += 70
		if (i+1)%5 == 0: left = rect.position.x+22; y += 42
	if parts[0]%5 != 0: left = rect.position.x+22; y += 42
	for i in range(parts[1]):
		prop(SPINDLE,Vector2(left+9,y+30),14)
		left += 18
	if parts[1] == 0:
		words("零散 0 根",Vector2(rect.position.x+22,y+26),18)
	var ok = parts[1] == Rules.REMAINDERS[record]
	words("%d 根 = %d 个满托 × %d 槽 + %d 根"%[Rules.RECORDS[record],parts[0],state.capacity,parts[1]],
		rect.position+Vector2(22,rect.size.y-62),19)
	var tail = "相符" if ok else "写的 %d 根对不上"%Rules.REMAINDERS[record]
	words_tint("余 %d 根，与记录%s"%[parts[1],tail],
		rect.position+Vector2(22,rect.size.y-28),20,GREEN if ok else RED)

func draw_verdict() -> void:
	var text = ""
	var tint = Color("fff0d1")
	if state.capacity < Rules.CAP_MIN:
		text = "先提出一个槽数，再分别重演两张记录。"
	elif Rules.solved(state):
		text = "%d 槽 · 两张记录都吻合，可以定为正式槽数。"%state.capacity
		tint = GREEN
	else:
		text = "%d 槽 · 记录一 %s · 记录二 %s"%[state.capacity,mark(0),mark(1)]
		if mark(0) == "不符" or mark(1) == "不符":
			text += " · 还有记录对不上。"
			tint = RED
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(text,VERDICT.position+Vector2(10,VERDICT.size.y-10),20,tint)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	for record in range(2): draw_record(record)
	draw_verdict()
	words("提出槽数 →",Vector2(30,612),20)
	var selected = state.capacity >= Rules.CAP_MIN and state.capacity <= Rules.CAP_MAX
	if selected:
		var chip = capacity_rect(state.capacity)
		draw_rect(Rect2(chip.position-Vector2(4,4),chip.size+Vector2(8,8)),Color("f2cf7a"),false,3)
	var dada = Vector2(1205,622)
	contact(dada,24); prop(DADA,dada,84)
	words("嗒嗒",dada-Vector2(20,0),18)

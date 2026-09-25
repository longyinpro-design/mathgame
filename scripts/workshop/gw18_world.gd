extends Node2D
# GW18 百臂总机现场：一张 0～10 拍的共用时刻表，两条流水线夹着两级单格暂存架。
# 上排是压机（一次一批）、下排是冷却间（每批 2 拍、按出压机的顺序），中间两条窄带
# 分别是「压机→冷却间」和「冷却→吊机间」的 1 批暂存位；最下面是吊机与第 10 拍开船。
# 早班、晚班两页推演共用同一份草稿：V 的吊运点只差第 6 与第 8 拍，逐拍占位与冲突全部
# 由规则模块现算，画面不另存会走样的表。正式运行、第 3 拍通知与交接杆都跟着真实轨迹走。
const Rules = preload("res://scripts/workshop/gw18_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/mistimed-dock-stage-v1.png")
const PRESS = preload("res://assets/runtime/workshop/kit-v1/press.tres")
const RACK = preload("res://assets/runtime/workshop/kit-v1/rack.tres")
const LIFT = preload("res://assets/runtime/workshop/kit-v1/lift.tres")
const BOX = preload("res://assets/runtime/workshop/kit-v1/box.tres")
const INGOT = preload("res://assets/runtime/workshop/kit-v1/ingot.tres")
const BELL = preload("res://assets/runtime/workshop/kit-v1/bell.tres")
const LEVER = preload("res://assets/runtime/workshop/kit-v1/lever.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_brace.tres")
const DADA_REST = preload("res://assets/runtime/workshop/kit-v1/dada_invite.tres")
const TICK_LEFT = 196.0
const TICK_W = 96.0
const TICKS = 11
const PRESS_Y = 296.0
const RACK1_Y = 346.0
const COOL_Y = 382.0
const RACK2_Y = 432.0
const LOAD_Y = 468.0
const ROW_H = 44.0
const RACK_H = 30.0
const SHIP_Y = 514.0
const SHIP_H = 38.0
const VERDICT = Rect2(24,240,1232,30)
const TRIAL_STEP = 0.34
const TINTS = [Color("9ec98a"),Color("7fa8c9"),Color("e0a35c")]
const EDGES = [Color("41602e"),Color("33536b"),Color("7a5220")]
const GREEN = Color("8fd694")
const RED = Color("e2604f")
const AMBER = Color("e8c06a")
const DIM = Color(0.72,0.72,0.66,0.55)
var scene_id = "dock"
var state = Rules.fresh()
# 焦点与推演页只属于工作台：不进存档，撤销与重摆都不动它。
var focus_slot = 0
var page = 6
var progress = 0.0
var presentation_paused = false
var land_progress = 1.0
var land_place = ""
var trial_page = 6
var trial_tick = 0
var trial_clock = 0.0
var trial_active = false
var trial_conflict: Dictionary = {}
var page_hit: Dictionary = {}
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()

# 上台面的那一下：通知板落下、船离港，都借用宿主这段 0.28 秒的落位窗口。
func begin_land(previous: Dictionary) -> void:
	land_place = ""
	if previous.stage == state.stage: return
	if state.stage == "trial": start_trial(page)
	elif state.stage == "notice": land_place = "notice"
	elif state.stage == "aftermath" and previous.stage == "handover": land_place = "sail"

# 试演本页：从第 0 拍跑到第一处说不通的地方，走得通就跑到第 10 拍。
func start_trial(slot: int) -> void:
	trial_page = slot
	trial_conflict = Rules.run_conflict(state,slot)
	trial_tick = 0
	trial_clock = 0.0
	trial_active = true
	queue_redraw()

func trial_limit() -> int:
	if trial_conflict.is_empty(): return Rules.HORIZON
	return clampi(trial_conflict.tick,0,Rules.HORIZON)

func _process(delta: float) -> void:
	if presentation_paused or not trial_active: return
	if state.stage != "trial":
		trial_active = false
		return
	trial_clock += delta
	while trial_clock >= TRIAL_STEP and trial_active:
		trial_clock -= TRIAL_STEP
		trial_tick += 1
		if trial_tick >= trial_limit(): trial_active = false
	queue_redraw()

func tick_x(t: int) -> float:
	return TICK_LEFT+t*TICK_W
func cell_rect(row: float, tick: int, height: float = ROW_H) -> Rect2:
	return Rect2(tick_x(tick)+3,row+3,TICK_W-6,height-6)
func bar_rect(row: float, start: int, length: int, height: float = ROW_H) -> Rect2:
	var left = tick_x(start)+3
	var right = minf(tick_x(start+length),tick_x(TICKS))-3
	return Rect2(left,row+3,maxf(right-left,24.0),height-6)
func page_rect(index: int) -> Rect2:
	return Rect2(24+index*628,194,604,46)
# 条子画的是行内实高，可点区域就是整行：触控目标不缩水。
func press_rect(index: int) -> Rect2:
	var span = Rules.press_span(state,index)
	var bar = bar_rect(PRESS_Y,span[0],span[1]-span[0])
	return Rect2(bar.position.x,PRESS_Y,bar.size.x,ROW_H)
func cool_rect(index: int) -> Rect2:
	var span = Rules.cool_span(state,index)
	var bar = bar_rect(COOL_Y,span[0],span[1]-span[0])
	return Rect2(bar.position.x,COOL_Y,bar.size.x,ROW_H)
func lever_rect() -> Rect2:
	return Rect2(1116,404,132,104)

# 正式运行跑到第几拍：只认存档里的实际班次。
func playhead() -> int:
	match state.stage:
		"delivery": return clampi(floori(progress*4.0),0,3)
		"notice": return 3
		"launch": return clampi(3+floori(progress*7.0),3,Rules.HORIZON)
		"handover": return Rules.HORIZON
	return -1

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
	words(value,rect.position+Vector2(10,rect.size.y-9),size_px)

# 逐拍扫描暂存链：produced 拍下线、consumed 拍被取走；这一拍上谁占着位子。
func holders(produced: Array, consumed: Array, tick: int) -> Array:
	var out: Array = []
	for index in range(Rules.COUNT):
		if produced[index] <= tick and tick < consumed[index]: out.append(index)
	return out
func press_ends() -> Array:
	var out: Array = []
	for index in range(Rules.COUNT): out.append(state.press[index]+Rules.PRESS_TIME[index])
	return out
func cool_ends() -> Array:
	var out: Array = []
	for index in range(Rules.COUNT): out.append(state.cool[index]+Rules.COOL_TIME)
	return out
func load_starts(slot: int) -> Array:
	var out: Array = []
	for index in range(Rules.COUNT): out.append(Rules.load_start(slot,index))
	return out

func draw_ruler() -> void:
	for t in range(TICKS+1):
		draw_line(Vector2(tick_x(t),PRESS_Y-10),Vector2(tick_x(t),LOAD_Y+ROW_H+4),Color(1,1,1,0.11),1)
	for t in range(TICKS):
		words(str(t),Vector2(tick_x(t)+TICK_W/2-9,PRESS_Y-6),17)
	var ship = tick_x(Rules.HORIZON)
	draw_dashed_line(Vector2(ship,PRESS_Y-10),Vector2(ship,SHIP_Y+SHIP_H),Color("f2cf7a"),2)

# 两页推演：同一份草稿、只差 V 的吊运点；每页当场给出走得通／说不通。
func draw_page_tabs() -> void:
	for index in range(2):
		var slot = Rules.BRANCHES[index]
		var rect = page_rect(index)
		var chosen = page == slot
		draw_rect(rect,Color(0.10,0.16,0.13,0.94) if chosen else Color(0.13,0.15,0.16,0.82))
		draw_rect(rect,Color("f2cf7a") if chosen else Color(1,1,1,0.16),false,3 if chosen else 2)
		words_tint("%s推演 · V 第 %d 拍吊运"%[Rules.page_name(slot),slot],
			rect.position+Vector2(14,29),19,Color("fff0d1") if chosen else DIM)
		var ok = Rules.page_ok(state,slot)
		words_tint("走得通" if ok else "说不通",rect.position+Vector2(rect.size.x-104,29),19,
			GREEN if ok else RED)

# 压机、冷却两条流水线：开工拍就是条子左端，占几拍由批次决定。
func draw_press_row() -> void:
	plaque("压机 一次一批",Rect2(16,PRESS_Y,164,ROW_H),17)
	draw_rect(Rect2(tick_x(0),PRESS_Y,tick_x(TICKS)-tick_x(0),ROW_H),Color("2a3138"))
	for index in range(Rules.COUNT):
		var span = Rules.press_span(state,index)
		var rect = bar_rect(PRESS_Y,span[0],span[1]-span[0])
		draw_rect(rect,TINTS[index]); draw_rect(rect,EDGES[index],false,3)
		words("%s %d件"%[Rules.BATCHES[index],Rules.ITEM_COUNT[index]],rect.position+Vector2(8,21),17)
		words_tint("压制 %d拍 · 第%d拍"%[Rules.PRESS_TIME[index],span[0]],rect.position+Vector2(8,36),13,
			Color("d8e2d2"))
		if state.stage == "puzzle" and focus_slot == index:
			draw_rect(rect.grow(3),Color("f6e2a8"),false,3)
		if page_hit.get("row",-1) == 0 and (page_hit.get("first",-1) == index or page_hit.get("second",-1) == index):
			draw_rect(rect.grow(4),RED,false,3)

func draw_cool_row() -> void:
	plaque("冷却间 每批2拍",Rect2(16,COOL_Y,164,ROW_H),16)
	draw_rect(Rect2(tick_x(0),COOL_Y,tick_x(TICKS)-tick_x(0),ROW_H),Color("2a3138"))
	for index in range(Rules.COUNT):
		var span = Rules.cool_span(state,index)
		var rect = bar_rect(COOL_Y,span[0],span[1]-span[0])
		draw_rect(rect,TINTS[index]); draw_rect(rect,EDGES[index],false,3)
		words("%s 冷却"%Rules.BATCHES[index],rect.position+Vector2(8,21),17)
		words_tint("第%d拍入位 · 第%d拍好"%[span[0],span[1]],rect.position+Vector2(8,36),13,Color("d8e2d2"))
		if state.stage == "puzzle" and focus_slot == Rules.COUNT+index:
			draw_rect(rect.grow(3),Color("f6e2a8"),false,3)
		if page_hit.get("row",-1) == 2 and (page_hit.get("first",-1) == index or page_hit.get("second",-1) == index):
			draw_rect(rect.grow(4),RED,false,3)

# 一条暂存链：每一拍画一格，格子里就是这一拍占着位子的那一批；两批同格当场标红。
func draw_rack_row(row: float, name: String, produced: Array, consumed: Array) -> void:
	plaque(name,Rect2(16,row,164,RACK_H),15)
	draw_rect(Rect2(tick_x(0),row,tick_x(TICKS)-tick_x(0),RACK_H),Color("232a30"))
	for tick in range(TICKS):
		var rect = cell_rect(row,tick,RACK_H)
		var held = holders(produced,consumed,tick)
		if held.is_empty():
			draw_rect(rect,Color(0.11,0.14,0.17,0.55))
			draw_rect(rect,Color(1,1,1,0.08),false,1)
			continue
		if held.size() == 1:
			draw_rect(rect,TINTS[held[0]])
			draw_rect(rect,EDGES[held[0]],false,2)
			words(Rules.BATCHES[held[0]],rect.position+Vector2(rect.size.x/2-7,21),17)
			continue
		draw_rect(rect,RED)
		draw_rect(rect,Color("7a2f26"),false,2)
		words("挤住",rect.position+Vector2(6,21),15)
	if page_hit.get("row",-1) == (1 if row == RACK1_Y else 3):
		draw_rect(cell_rect(row,clampi(page_hit.tick,0,TICKS-1),RACK_H).grow(3),Color("f6e2a8"),false,3)

# 吊机：F 第 3 拍、M 第 9 拍钉死，V 按这一页取第 6 或第 8 拍；另一页的 V 位画虚框。
func draw_load_row(slot: int) -> void:
	plaque("吊机 一次一批",Rect2(16,LOAD_Y,164,ROW_H),17)
	draw_rect(Rect2(tick_x(0),LOAD_Y,tick_x(TICKS)-tick_x(0),ROW_H),Color("2a3138"))
	var other = Rules.BRANCHES[1] if slot == Rules.BRANCHES[0] else Rules.BRANCHES[0]
	for index in range(Rules.COUNT):
		var at = Rules.load_start(slot,index)
		var rect = bar_rect(LOAD_Y,at,Rules.LOAD_TIME)
		if index == 1:
			var ghost = bar_rect(LOAD_Y,Rules.load_start(other,index),Rules.LOAD_TIME)
			draw_rect(ghost,Color(1,1,1,0.06))
			draw_dashed_line(ghost.position+Vector2(0,1),ghost.position+Vector2(ghost.size.x,1),DIM,1)
			draw_dashed_line(ghost.position+Vector2(0,ghost.size.y-1),
				ghost.position+Vector2(ghost.size.x,ghost.size.y-1),DIM,1)
			words_tint("%s班"%Rules.page_name(other),ghost.position+Vector2(10,36),12,DIM)
		draw_rect(rect,TINTS[index]); draw_rect(rect,EDGES[index],false,3)
		words("%s 吊"%Rules.BATCHES[index],rect.position+Vector2(8,21),17)
		words_tint("第%d拍"%at,rect.position+Vector2(8,36),13,Color("d8e2d2"))
		if index == 1:
			draw_rect(rect.grow(3),Color("f2cf7a"),false,2)
		if page_hit.get("row",-1) == 4 and index == 1:
			draw_rect(rect.grow(5),RED,false,3)

# 船期带：第 10 拍开船；正式运行里三批的接收记录按实际吊运依次登记。
func draw_ship_row(slot: int, receipts: bool) -> void:
	plaque("总机船 第%d拍开船"%Rules.HORIZON,Rect2(16,SHIP_Y,164,SHIP_H),15)
	draw_rect(Rect2(tick_x(0),SHIP_Y,tick_x(TICKS)-tick_x(0),SHIP_H),Color(0.09,0.13,0.16,0.72))
	for index in range(Rules.COUNT):
		var at = Rules.load_start(slot,index)
		var rect = bar_rect(SHIP_Y,at,Rules.LOAD_TIME,SHIP_H)
		draw_rect(rect,TINTS[index]); draw_rect(rect,EDGES[index],false,3)
		if receipts:
			words("%s 第%d拍收"%[Rules.BATCHES[index],at+Rules.LOAD_TIME],rect.position+Vector2(6,25),15)
	contact(Vector2(1240,SHIP_Y+SHIP_H-2),30); prop(LIFT,Vector2(1240,SHIP_Y+SHIP_H-2),124)

func draw_verdict() -> void:
	var text = ""
	var tint = Color("fff0d1")
	if state.stage == "trial":
		if trial_tick < trial_limit():
			text = "%s：试演到第 %d 拍……"%[Rules.page_name(trial_page),trial_tick]
		elif trial_conflict.is_empty():
			text = "%s：第 0～%d 拍都走得通，没有挤位。"%[Rules.page_name(trial_page),Rules.HORIZON]
			tint = GREEN
		else:
			text = "第 %d 拍：%s"%[trial_limit(),trial_conflict.text]
			tint = RED
	elif page_hit.is_empty():
		text = "%s：两批机器不撞、暂存不挤，第 %d 拍开船。"%[Rules.page_name(page),Rules.HORIZON]
		tint = GREEN
	else:
		text = "%s：%s"%[Rules.page_name(page),page_hit.text]
		tint = RED
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(text,VERDICT.position+Vector2(10,23),17,tint)

# 规划台面：两页推演、两条流水线、两级暂存架与吊机，全部按当前草稿现算。
func draw_board() -> void:
	page_hit = Rules.run_conflict(state,page)
	draw_page_tabs()
	draw_ruler()
	draw_press_row()
	draw_rack_row(RACK1_Y,"暂存 压机→冷却",press_ends(),state.cool)
	draw_cool_row()
	draw_rack_row(RACK2_Y,"暂存 冷却→吊机",cool_ends(),load_starts(page))
	draw_load_row(page)
	draw_ship_row(page,false)
	if state.stage == "trial":
		var tick = clampi(trial_tick,0,Rules.HORIZON)
		draw_line(Vector2(tick_x(tick),PRESS_Y-10),Vector2(tick_x(tick),SHIP_Y+SHIP_H),Color("f6e2a8"),3)
		words_tint("试演 第 %d 拍"%tick,Vector2(24,PRESS_Y-6),19,Color("f6e2a8"))
	draw_verdict()

# 正式运行：逐拍照真实轨迹走，压机、冷却、两级暂存与吊机都停在这一拍的样子上。
func draw_run() -> void:
	var tick = playhead()
	page_hit = {}
	draw_ruler()
	draw_press_row()
	var produced = press_ends()
	var finished = cool_ends()
	var loads = load_starts(state.branch)
	draw_rack_row(RACK1_Y,"暂存 压机→冷却",produced,state.cool)
	draw_cool_row()
	draw_rack_row(RACK2_Y,"暂存 冷却→吊机",finished,loads)
	draw_load_row(state.branch)
	draw_ship_row(state.branch,tick >= Rules.HORIZON)
	draw_line(Vector2(tick_x(tick),PRESS_Y-10),Vector2(tick_x(tick),SHIP_Y+SHIP_H),Color("f6e2a8"),3)
	words_tint("第 %d 拍"%tick,Vector2(24,PRESS_Y-6),19,Color("f6e2a8"))
	for index in range(Rules.COUNT):
		var span = Rules.press_span(state,index)
		var press_bar = bar_rect(PRESS_Y,span[0],span[1]-span[0])
		if span[1] <= tick: draw_rect(press_bar.grow(2),GREEN,false,2)
		elif span[0] <= tick: draw_rect(press_bar.grow(2),AMBER,false,2)
		var cool = Rules.cool_span(state,index)
		var cool_bar = bar_rect(COOL_Y,cool[0],cool[1]-cool[0])
		if cool[1] <= tick: draw_rect(cool_bar.grow(2),GREEN,false,2)
		elif cool[0] <= tick: draw_rect(cool_bar.grow(2),AMBER,false,2)
		if loads[index] <= tick and tick < loads[index]+Rules.LOAD_TIME:
			draw_rect(bar_rect(LOAD_Y,loads[index],Rules.LOAD_TIME).grow(2),AMBER,false,2)
	# 第 3 拍的通知板：读的是实际班次，计划本身不动。
	var text = ""
	var tint = Color("fff0d1")
	if state.stage == "delivery":
		text = "正式运行：先跑到第 3 拍，等总机确认 V 的班次。"
	elif state.stage == "notice" or (state.stage == "launch" and tick <= 4):
		text = "第 3 拍收到确认：V 走%s班，实际吊运点第 %d 拍。"%[Rules.page_name(state.branch),state.branch]
		tint = Color("f6e2a8")
	else:
		text = "正式运行：V 走%s班，第 %d 拍吊运，第 %d 拍开船。"%[
			Rules.page_name(state.branch),state.branch,Rules.HORIZON]
		tint = GREEN
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint(text,VERDICT.position+Vector2(10,23),17,tint)

# 交接：三处接收记录齐全，拉下确认交接杆，总机船才出海。
func draw_handover() -> void:
	draw_run()
	draw_style_box(ArtStyle.sign_style(),VERDICT)
	words_tint("三处接收记录齐全：F 第 4 拍、V 第 %d 拍、M 第 10 拍——拉下右边的确认交接杆。"%(
		state.branch+Rules.LOAD_TIME),VERDICT.position+Vector2(10,23),17,GREEN)
	contact(Vector2(1180,502),26); prop(LEVER,Vector2(1180,502),100)
	plaque("确认交接杆",Rect2(1108,404,144,30),15)

# 出海：船离开总机船坞，接收记录留档，嗒嗒挂上休息牌。
func draw_departed() -> void:
	var sail = 0.0
	if land_place == "sail": sail = land_progress
	var ship_x = 1220+sail*120
	contact(Vector2(ship_x,SHIP_Y+SHIP_H-2),30)
	prop(LIFT,Vector2(ship_x,SHIP_Y+SHIP_H-2),124)
	plaque("总机船已出海",Rect2(1030,296,226,38),18)
	plaque("接收记录：F 第 4 拍 · V 第 %d 拍 · M 第 10 拍"%(state.branch+Rules.LOAD_TIME),
		Rect2(24,300,620,38),18)
	plaque("库存 7 件全部交清 · 第 %d 拍开船"%Rules.HORIZON,Rect2(24,346,620,38),18)
	plaque("发现卡：把不同情况都想一遍",Rect2(24,392,620,38),18)
	contact(Vector2(900,642),26); prop(DADA_REST,Vector2(900,642),96)
	plaque("嗒嗒挂上休息牌",Rect2(760,556,220,34),16)
	contact(Vector2(680,642),24); prop(BELL,Vector2(680,642),72)
	plaque("开船铃",Rect2(600,556,120,34),16)

func draw_arrival() -> void:
	plaque("库存 7 件 · 不拆批",Rect2(24,296,300,44),19)
	plaque("F 森林 2 件 · 压制 1 拍",Rect2(24,352,300,42),18)
	plaque("V 山谷 3 件 · 压制 2 拍",Rect2(24,404,300,42),18)
	plaque("M 集市 2 件 · 压制 1 拍",Rect2(24,456,300,42),18)
	plaque("冷却每批 2 拍 · 暂存位各 1 批",Rect2(24,508,300,42),18)
	contact(Vector2(420,642),34); prop(BOX,Vector2(420,642),120)
	contact(Vector2(560,642),30); prop(INGOT,Vector2(560,642),96,Color("cfe0f2"))
	contact(Vector2(700,642),30); prop(RACK,Vector2(700,642),116)
	contact(Vector2(860,642),30); prop(PRESS,Vector2(860,642),120)
	contact(Vector2(1000,642),28); prop(DADA,Vector2(1000,642),96)
	words("嗒嗒",Vector2(920,624),18)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	match state.stage:
		"arrival","approach": draw_arrival()
		"delivery","notice","launch": draw_run()
		"handover": draw_handover()
		"aftermath","complete": draw_departed()
		_: draw_board()

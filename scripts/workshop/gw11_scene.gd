extends "res://scripts/workshop/workshop_host.gd"
# GW11 装卸码头「两张船票，倒排到同一张台」：A、B 两批材料都在第 6 拍到，
# 每批三段工序首尾相接；A 的船票钉死第 12 拍，B 的船票先在第 13、14 拍里选定一班。
# 玩家排的是六个开工拍；三条共用带由规则模块现算，撞车当场标红，提交也过不去。
const Rules = preload("res://scripts/workshop/gw11_rules.gd")
const World = preload("res://scripts/workshop/gw11_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["小岚：两批材料都在第 %d 拍送到。A 批的船票钉死在第 %d 拍开船；B 批有两张票，第 13 拍和第 14 拍，得先定一张。"%[Rules.ARRIVAL_BEAT,Rules.A_LOAD],
	"嗒嗒：A 批装配 %d 拍、冷却 %d 拍、装船 %d 拍；B 批装配 %d 拍、冷却 %d 拍、装船 %d 拍。三段都得首尾相接，中间不能等。"%[Rules.ASSEMBLY_TIME[0],Rules.COOL_TIME[0],Rules.LOAD_TIME,Rules.ASSEMBLY_TIME[1],Rules.COOL_TIME[1],Rules.LOAD_TIME],
	"小岚：装配台只有一张，一次一批；冷却架能放两批；吊机一次吊一批。先选票，再从船票往回倒着排。"]
const AFTER = ["小岚：从各自的船票往回倒：A 冷却 9–12、装配 7–9；B 走第 14 拍，冷却 12–14、装配 9–12。",
	"嗒嗒：B 要是选第 13 拍，装配就得排 8–11，正好压在 A 的 7–9 上——单批都没错，合起来才撞车。",
	"小岚：弥师傅说，这次等待是有依据的：材料第 %d 拍到，两批却都从第 7 拍以后才动手。"%Rules.ARRIVAL_BEAT]
var gw_pending_feedback = ""
var focus_batch = 0
var focus_row = 0

func configure() -> void:
	scene_id = "dock"; level_id = "GW11"; title = "两张船票，倒排到同一张台"
	if save_path.is_empty(): save_path = Catalog.save_path("GW11")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []
	focus_batch = 0; focus_row = 0

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

# 本关标题 12 个字：22 号在 410 宽的板子上会折成两行、第二行压过板底。
# 只把标题这一块降到 19 号；板子位置、字号下限与其它板子都不动。
func sign_text(text: String, rect: Rect2, size_px: int = 20) -> void:
	if size_px > 19 and text.begins_with(chapter_label()):
		UIStyle.sign(ui,rect)
		UIStyle.text(ui,text,Rect2(rect.position+Vector2(14,8),rect.size-Vector2(28,12)),19)
		return
	super.sign_text(text,rect,size_px)

func goal_line() -> String: return "两批第 %d 拍到 · A 装船 %d · B 票 13/14 · 共用一张装配台"%[Rules.ARRIVAL_BEAT,Rules.A_LOAD]
func status_line() -> String:
	var ticket = "未选" if not Rules.TICKETS.has(state.ticket) else str(state.ticket)
	return "选中 %s 批 %s 第 %d 拍 · 票 %s"%[Rules.BATCHES[focus_batch],Rules.STAGE_NAMES[focus_row],
		Rules.start_of(state,focus_batch,focus_row),ticket]
func submit_label() -> String: return "排好提交 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "看看装卸台","approach":"铺开时刻表",
		"ready":"开始排拍子","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装卸台","重新体验"]
func reset_prompt() -> Array: return ["把船票和六个开工拍全部退回开局草稿？\n求助级别仍保留。","继续排拍子","退回草稿"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "共用时刻表铺开了：两批材料第 %d 拍到，船票挂在第 %d、13、14 拍上。"%[Rules.ARRIVAL_BEAT,Rules.A_LOAD]
		"ready": return "先点一张 B 的船票定下来，再点一格工序，用「提前／推后 1 拍」把它挪到合适的拍子上。"
		"puzzle": return "三段首尾相接、中间不能等；装配台和吊机一次只过一批，冷却架能放两批。"
		"delivery": return "按排好的拍子跑一遍：材料到场、装配、冷却，再各自上船……"
		"aftermath": return AFTER[state.beat]
		"complete": return "倒排之后，还要把两批合到同一张台上检查。"
	return ""

func build() -> void:
	for index in range(2):
		var ticket = Rules.TICKETS[index]
		add_button("ticket_%d"%ticket,"选 %d 拍票"%ticket,Rect2(24+index*158,548,150,46),
			choose_ticket.bind(ticket),state.ticket == ticket)
	add_button("earlier","提前 1 拍",Rect2(360,548,170,46),earlier)
	add_button("later","推后 1 拍",Rect2(538,548,170,46),later)
	for batch in range(Rules.COUNT):
		for row in range(3):
			var span = Rules.interval(state,batch,row)
			add_hotspot("cell_%d_%d"%[batch,row],world.span_rect(batch,row),select_cell.bind(batch,row),
				"%s 批 %s · 第 %d–%d 拍 · 点一下选中"%[Rules.BATCHES[batch],Rules.STAGE_NAMES[row],span[0],span[1]])

func extra() -> void:
	world.focus_batch = focus_batch; world.focus_row = focus_row
	add_button("journal","回看与发现",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary:
	return {"ticket":v.ticket,"assembly":v.assembly.duplicate(),"cool":v.cool.duplicate(),"load":v.load.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true)
	n.ticket = 0
	n.assembly = Rules.DEFAULT_ASSEMBLY.duplicate()
	n.cool = Rules.DEFAULT_COOL.duplicate()
	n.load = Rules.DEFAULT_LOAD.duplicate()
	return n

func select_cell(batch: int, row: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	focus_batch = clampi(batch,0,Rules.COUNT-1); focus_row = clampi(row,0,2)
	message = ""; refresh()

func step_stage(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	focus_row = clampi(focus_row+delta,0,2); message = ""; refresh()

# 选 B 的船票：和底栏那两块按钮走的是同一条合法性判据。
func choose_ticket(ticket: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if not Rules.TICKETS.has(ticket): return
	if state.ticket == ticket:
		message = "B 已经定了第 %d 拍的票；要换就点另一张。"%ticket; refresh(); return
	var next = Rules.choose_ticket(state,ticket)
	if next.is_empty(): return
	gw_pending_feedback = "B 的船票定了：第 %d 拍开船，装船那一格也要排到第 %d 拍。"%[ticket,ticket]
	place(next)

func cycle_ticket() -> void:
	choose_ticket(Rules.TICKETS[1] if state.ticket == Rules.TICKETS[0] else Rules.TICKETS[0])

func adjust(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.step_start(state,focus_batch,focus_row,delta)
	if next.is_empty():
		message = "%s 批的%s已经到边上了：开工拍只能排在第 0 到第 %d 拍之间。"%[
			Rules.BATCHES[focus_batch],Rules.STAGE_NAMES[focus_row],Rules.RANGE_MAX]
		refresh(); return
	message = ""
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func earlier() -> void: adjust(-1)
func later() -> void: adjust(1)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["从各自的船票往回排：装船那一格先对准船票，A 是第 %d 拍。"%Rules.A_LOAD,
		"再还原两种船票的冷却：A 冷却 %d 拍排 9～12；B 冷却 %d 拍，13 拍票是 11～13、14 拍票是 12～14。"%[Rules.COOL_TIME[0],Rules.COOL_TIME[1]],
		"最后比装配：A 装配 7～9；B 走 13 拍票要排 8～11，与 A 的 7～9 在装配台上重叠；走 14 拍票是 9～12。",
		"选第 14 拍的票：A 装配 7–9、冷却 9–12、装船 12–13；B 装配 9–12、冷却 12–14、装船 14–15。两批在第 9 拍交接装配台。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: step_stage(-1)
	elif key == KEY_RIGHT or key == KEY_D: step_stage(1)
	elif key == KEY_UP or key == KEY_W: select_cell(0,focus_row)
	elif key == KEY_DOWN or key == KEY_S: select_cell(1,focus_row)
	elif key == KEY_Q: earlier()
	elif key == KEY_E: later()
	elif key == KEY_T: cycle_ticket()
	else: return false
	return true

func plan_line(batch: int) -> String:
	var segs = []
	for row in range(3):
		var span = Rules.interval(state,batch,row)
		segs.append("%s %d–%d"%[Rules.STAGE_NAMES[row],span[0],span[1]])
	return "%s 批：%s"%[Rules.BATCHES[batch],"、".join(segs)]

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "工序与共用资源\n"
	text += "两批材料都在第 %d 拍到。三段工序必须首尾相接，中间不能等待。\n"%Rules.ARRIVAL_BEAT
	text += "A 批：装配 %d 拍、冷却 %d 拍、装船 %d 拍；船票钉死在第 %d 拍开船。\n"%[Rules.ASSEMBLY_TIME[0],Rules.COOL_TIME[0],Rules.LOAD_TIME,Rules.A_LOAD]
	text += "B 批：装配 %d 拍、冷却 %d 拍、装船 %d 拍；船票可选第 13 或第 14 拍，先选定一班。\n"%[Rules.ASSEMBLY_TIME[1],Rules.COOL_TIME[1],Rules.LOAD_TIME]
	text += "装配台一次一批；冷却架可容两批；吊机一次一批。\n\n当前排法\n"
	for batch in range(Rules.COUNT): text += plan_line(batch) + "\n"
	text += "船票：%s\n"%world.ticket_text()
	var table = Rules.clash(state,0)
	var crane = Rules.clash(state,2)
	if table.is_empty() and crane.is_empty():
		text += "共用装配台与吊机：现在没有两批抢同一拍。\n"
	else:
		if not table.is_empty():
			text += "共用装配台：第 %d～%d 拍 %s、%s 两批重叠。\n"%[table.from,table.to,Rules.BATCHES[table.first],Rules.BATCHES[table.second]]
		if not crane.is_empty():
			text += "吊机：第 %d～%d 拍 %s、%s 两批重叠。\n"%[crane.from,crane.to,Rules.BATCHES[crane.first],Rules.BATCHES[crane.second]]
	if Rules.solved(state): text += "\n两批都排好了，可以提交。\n"
	UIStyle.text(overlay,text,Rect2(250,121,780,440),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：排好拍子后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

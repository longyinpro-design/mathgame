extends "res://scripts/workshop/workshop_host.gd"
# GW17 总机船坞「巡轨兽 · 空出第一拍」：四辆工具车共用一段承重轨道，一次一辆、开工后不能中断。
# 第 0 拍开始规划，全部最晚第 9 拍驶离，各有独立期限；玩家给每辆车排开工拍。
# 提交就是让巡轨兽逐段放行：上轨许可、轨道占用、最晚驶离按放行顺序逐辆检查，
# 第一次说不通就念出真实原因（还没到点／轨上压着／驶离太晚），不替玩家填中间量。
const Rules = preload("res://scripts/workshop/gw17_rules.gd")
const World = preload("res://scripts/workshop/gw17_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["小岚：总机船坞的轨口只有一段承重轨道，四辆工具车都要从这儿过，一次一辆，开出去就不能停。",
	"嗒嗒：第 0 拍开始规划，四辆车最晚第 9 拍全部驶离；每辆还有自己的上轨许可和最晚驶离。",
	"小岚：B 最急——第 1 拍可发、最晚第 4 拍驶离；A 最晚第 7 拍，C 最晚第 5 拍，D 第 6 拍才准上轨。"]
const AFTER = ["嗒嗒：巡轨兽逐段放行：第 0 拍空着等，B 1–3、C 3–4、A 4–7、D 7–9，四辆都赶上自己的期限。",
	"小岚：A 先走会把 B 卡到第 5 拍；B 之后先接 A，C 就赶不上；为等 D 把 A 挪后也不行——只有这一张时刻表。",
	"嗒嗒：空出的第一拍不是口令，是期限逼出来的。巡轨兽折下路障，工具开进总机船坞。发现卡：有依据地留空。"]
# 左下角是放行牌、右下角是「回看与发现」；小岚缩小站在共用轨道的下沿、嗒嗒的左边。
func companion_foot() -> Vector2: return Vector2(760,620)
func companion_scale() -> float: return 0.8
var gw_pending_feedback = ""
var focus_item = 0

func configure() -> void:
	scene_id = "engine"; level_id = "GW17"; title = "巡轨兽 · 空出第一拍"
	if save_path.is_empty(): save_path = Catalog.save_path("GW17")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":4.2}
	zoom_stages = []
	focus_item = 0

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "四辆车最晚第 9 拍全部驶离 · 期限 A≤7 B≤4 C≤5 D≤9"
func status_line() -> String: return "选中 %s 车 · 第 %d 拍发车"%[Rules.ITEMS[focus_item],state.starts[focus_item]]
func submit_label() -> String: return "逐段放行 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向轨口","approach":"铺开轨道时刻表",
		"ready":"开始排发车拍","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在轨口","重新体验"]
func reset_prompt() -> Array: return ["把四辆车的发车拍退回开局草稿？\n求助级别仍保留。","继续排","退回草稿"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "轨道时刻表从第 0 拍铺到第 %d 拍：四辆车各有一段占轨区间。"%Rules.HORIZON
		"ready": return "先点一辆车，再用「提前／推后」把它排到合适的发车拍；放行顺序会跟着发车拍走。"
		"puzzle": return "巡轨兽一次只放一辆过轨：先看上轨许可，再看轨道空不空，最后看最晚驶离。"
		"delivery": return "逐段放行：巡轨兽扫到哪一拍，就报出这一拍轨上的车；空着的拍写明空着等。"
		"aftermath": return AFTER[state.beat]
		"complete": return "空出的第一拍不是口令，是期限逼出来的。"
	return ""

func build() -> void:
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		add_hotspot("row_%d"%index,world.row_rect(index),select_car.bind(index),
			"%s 车 · 最早第 %d 拍 · 占轨 %d 拍 · 最晚第 %d 拍驶离 · 点一下选中它"%[
				id,Rules.RELEASES[id],Rules.DURATIONS[id],Rules.DEADLINES[id]])
	add_button("earlier","提前 1 拍",Rect2(24,548,170,46),earlier)
	buttons["earlier"].tooltip_text = "把选中的那辆车往前挪 1 拍 · 键盘 Q"
	add_button("later","推后 1 拍",Rect2(202,548,170,46),later)
	buttons["later"].tooltip_text = "把选中的那辆车往后挪 1 拍 · 键盘 W"

func extra() -> void:
	world.focus_item = focus_item
	add_button("journal","回看与发现",Rect2(1092,548,164,46),journal).disabled = transient > 0
	if state.stage != "puzzle": return
	sign_text("← → / ↑ ↓ 选车 · Q 提前 1 拍 · W 推后 1 拍",Rect2(24,600,560,42),18)

func snapshot(v: Dictionary) -> Dictionary:
	return {"starts":v.starts.duplicate(),"order":v.order.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.starts = Rules.DEFAULT_STARTS.duplicate(); n.order = Rules.sequence(n.starts); return n

func select_car(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	focus_item = clampi(index,0,Rules.COUNT-1); message = ""; refresh()

func move_selection(delta: int) -> void:
	focus_item = clampi(focus_item+delta,0,Rules.COUNT-1); message = ""; refresh()

func adjust(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var value = state.starts[focus_item]+delta
	if value < 0 or value > Rules.START_MAX:
		message = "已经到头了：发车拍只能排在第 0 到第 %d 拍之间。"%Rules.START_MAX
		refresh(); return
	message = ""
	var next = Rules.nudge(state,focus_item,delta)
	if next.is_empty(): return
	commit_plan(next)

func earlier() -> void: adjust(-1)
func later() -> void: adjust(1)

# 宿主同名的 place() 走的是另一套语义，这里另起一个名字提交排好的四辆车。
func commit_plan(next: Dictionary) -> void:
	if state.stage != "puzzle" or modal or transient > 0 or next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

# 提交就是逐段放行：第一次说不通的原因由规则模块给出，多处时只说还有几处。
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle":
		var missing = Rules.shortfalls(state)
		if not missing.is_empty():
			message = missing[0] + ("（还有 %d 处说不通）"%(missing.size()-1) if missing.size() > 1 else "")
			refresh(); return
		commit(Rules.advance(state),history)
		return
	super.advance()

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["先比每辆车的放行窗口：B 最早第 1 拍、最晚第 4 拍驶离，占轨 2 拍，只有第 1、2 拍两个发车点。",
		"第 0 拍就发 A：A 占 0–3，B 只能第 3 拍上轨、第 5 拍才驶离，超过最晚 4 拍。",
		"B 1–3 之后先接 A 的话，A 到第 6 拍才走完，C 只能第 6 拍发、第 7 拍驶离，超过最晚 5 拍。",
		"完整时刻表：第 0 拍空着等，B 1–3、C 3–4、A 4–7、D 7–9；空出的第一拍是期限逼出来的。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_UP: move_selection(-1)
	elif key == KEY_RIGHT or key == KEY_DOWN: move_selection(1)
	elif key == KEY_Q: adjust(-1)
	elif key == KEY_W: adjust(1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "巡轨兽的放行记录\n\n"
	text += "四辆工具车共用一段承重轨道，一次一辆，开工后不能中断。\n"
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		text += "%s 车 · 最早第 %d 拍 · 占轨 %d 拍 · 最晚第 %d 拍驶离\n"%[
			id,Rules.RELEASES[id],Rules.DURATIONS[id],Rules.DEADLINES[id]]
	text += "\n当前排法（放行顺序 %s）\n"%["→".join(state.order)]
	var starts = []
	for index in range(Rules.COUNT):
		starts.append("%s 第 %d 拍"%[Rules.ITEMS[index],state.starts[index]])
	text += "发车：%s\n"%[" · ".join(starts)]
	if Rules.solved(state):
		text += "\n四辆都赶上期限：可以让巡轨兽逐段放行。"
	else:
		var gaps = Rules.shortfalls(state)
		if not gaps.is_empty(): text += "\n还没排好：%s"%gaps[0]
	UIStyle.text(overlay,text,Rect2(250,121,780,440),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：排好四辆车后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

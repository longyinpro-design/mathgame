extends "res://scripts/workshop/workshop_host.gd"
# GW10 装配间「最急的那单，为什么不能先开」：一张维修台一次一单，开工后不能中断。
# A、B、D 第 0 拍就绪，C 第 1 拍才送到；四单各有最晚完成。玩家把每单排到某一拍开工，
# 验收顺序跟着开工拍走；提交时逐单验收，第一次说不通就念出真实原因（等料／撞台／逾期）。
const Rules = preload("res://scripts/workshop/gw10_rules.gd")
const World = preload("res://scripts/workshop/gw10_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["小岚：四张单都等着上维修台，一次只做一单，开了不能停。山谷的实物先收着，忙完一起看。",
	"嗒嗒：A、B、D 第 0 拍就在手边，C 要第 1 拍才送来；四单最晚第 8 拍都得做完。",
	"小岚：每单还有自己的期限——A 最晚 5 拍、B 最晚 8 拍、C 最晚 3 拍、D 最晚 6 拍，用时也各不相同。"]
const AFTER = ["嗒嗒：A 0–2、C 2–3、D 3–5、B 5–8，四单都不逾期，台子一刻没空。",
	"小岚：D 先上、再接 C、A，最后 B，也一样成立。C 第 1 拍才到，所以第一件只能在 A 和 D 里挑。",
	"嗒嗒：总工作量正好 8 拍，空一拍就赶不上。发现卡：紧急程度和到达时间要一起看。码头还有两批货等着排。"]
# 右下角是「回看与发现」；小岚站到它左边、嗒嗒的左侧。
func companion_foot() -> Vector2: return Vector2(1000,620)
var gw_pending_feedback = ""
var focus_item = 0

func configure() -> void:
	scene_id = "rooftop"; level_id = "GW10"; title = "最急的那单，不能先开"
	if save_path.is_empty(): save_path = Catalog.save_path("GW10")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []
	focus_item = 0

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "四单最晚第 8 拍完成 · 期限 A≤5 B≤8 C≤3 D≤6"
func status_line() -> String: return "顺序 %s · 选中 %s"%["→".join(state.order),Rules.ITEMS[focus_item]]
func submit_label() -> String: return "逐单验收 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向维修台","approach":"铺开四张单",
		"ready":"开始排开工拍","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在维修台","重新体验"]
func reset_prompt() -> Array: return ["把四张单退回开局那张草稿？\n求助级别仍保留。","继续排","退回草稿"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "四张单并排铺开，维修台的时间尺从第 0 拍排到第 %d 拍。"%Rules.HORIZON
		"ready": return "先点一张单，再用「提前／推后」把它排到合适的开工拍；验收顺序会跟着开工拍走。"
		"puzzle": return "台子一次只做一单、开工不能停；C 第 1 拍才送到，四单还各有最晚完成。"
		"delivery": return "逐单验收：先看到料，再看台子空不空，最后看最晚期限。"
		"aftermath": return AFTER[state.beat]
		"complete": return "最急的单也得等到料；紧急程度和到达时间要一起看。"
	return ""

func build() -> void:
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		add_hotspot("row_%d"%index,world.row_rect(index),select_order.bind(index),
			"%s 单 · 用时 %d 拍 · 最晚第 %d 拍 · 点一下选中它"%[id,Rules.DURATIONS[id],Rules.DEADLINES[id]])
	add_button("earlier","提前 1 拍",Rect2(24,548,170,46),earlier)
	buttons["earlier"].tooltip_text = "把选中的那一单往前挪 1 拍 · 键盘 Q"
	add_button("later","推后 1 拍",Rect2(202,548,170,46),later)
	buttons["later"].tooltip_text = "把选中的那一单往后挪 1 拍 · 键盘 W"

func extra() -> void:
	world.focus_item = focus_item
	add_button("journal","回看与发现",Rect2(1092,548,164,46),journal).disabled = transient > 0
	if state.stage != "puzzle": return
	sign_text("← → 选单 · Q 提前 1 拍 · W 推后 1 拍",Rect2(24,600,560,42),18)

func snapshot(v: Dictionary) -> Dictionary:
	return {"starts":v.starts.duplicate(),"order":v.order.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.starts = Rules.DEFAULT_STARTS.duplicate(); n.order = Rules.sequence(n.starts); return n

func select_order(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	focus_item = clampi(index,0,Rules.COUNT-1); message = ""; refresh()

func move_selection(delta: int) -> void:
	focus_item = clampi(focus_item+delta,0,Rules.COUNT-1); message = ""; refresh()

func adjust(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var value = state.starts[focus_item]+delta
	if value < 0 or value > Rules.START_MAX:
		message = "已经到头了：开工拍只能排在第 0 到第 %d 拍之间。"%Rules.START_MAX
		refresh(); return
	message = ""
	var next = Rules.nudge(state,focus_item,delta)
	if next.is_empty(): return
	commit_plan(next)

func earlier() -> void: adjust(-1)
func later() -> void: adjust(1)

# 宿主同名的 place() 走的是另一套语义，这里另起一个名字提交排好的四张单。
func commit_plan(next: Dictionary) -> void:
	if state.stage != "puzzle" or modal or transient > 0 or next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

# 提交就是逐单验收：第一次说不通的原因由规则模块给出，多处时只说还有几处。
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
	return ["先把四单的用时加起来：A 2 拍、B 3 拍、C 1 拍、D 2 拍，一共要忙几拍？",
		"C 第 1 拍才送到。要是先等它，第 0 拍台上就空着；四单一共正好 8 拍，空一拍就赶不上第 8 拍。",
		"第一件从 A、D 里挑一件 2 拍的：它做到第 2 拍，C 正好送到，接上只占 1 拍，台子一刻不空。",
		"两种完整计划：A 0–2、C 2–3、D 3–5、B 5–8；或 D 0–2、C 2–3、A 3–5、B 5–8。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT: move_selection(-1)
	elif key == KEY_RIGHT: move_selection(1)
	elif key == KEY_Q: adjust(-1)
	elif key == KEY_W: adjust(1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(230,113,820,522),true)
	var text = "最急的那单，为什么不能先开\n\n"
	text += "维修台一次一单，开工后不能中断。\n"
	text += "A、B、D 第 0 拍就绪，C 第 1 拍才送到。\n"
	text += "用时：A 2 拍、B 3 拍、C 1 拍、D 2 拍。\n"
	text += "期限：A 最晚 5 拍、B 最晚 8 拍、C 最晚 3 拍、D 最晚 6 拍。\n\n"
	text += "当前排法（验收顺序 %s）\n"%["→".join(state.order)]
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		text += "%s 第 %d 拍开工，第 %d 拍做完（最晚 %d 拍）\n"%[
			id,state.starts[index],state.starts[index]+Rules.DURATIONS[id],Rules.DEADLINES[id]]
	if Rules.solved(state):
		text += "\n四单不撞台也不逾期：到料、台子、期限都过得了。"
	UIStyle.text(overlay,text,Rect2(270,141,740,404),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,569,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：排好四张单后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

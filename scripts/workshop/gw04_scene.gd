extends "res://scripts/workshop/workshop_host.gd"
const Rules = preload("res://scripts/workshop/gw04_rules.gd")
const World = preload("res://scripts/workshop/gw04_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：第一托交出去了。余下两托要赶下一班船，新班次从第 0 拍重新计时。",
	"小岚：小车第 4、8、12、16 拍到，每次接走一托；这条轨是直通的，没有放行灯。",
	"嗒嗒：吊台本来第 2、8、14 拍到，周期 6 拍。开工前我可以把整条时刻表一起往后挪，最多挪 2 拍。"]
const AFTER = ["嗒嗒：延后 2 拍，吊台改成 4、10、16 拍，正好在小车到的 4 拍和 16 拍接上两次。",
	"小岚：不延后只在 8 拍碰上一次；延后 1 拍一次也碰不上——起点不同，整张表都不一样。",
	"嗒嗒：两托都上船了，这一趟是我按住启动杆的。留出来的空拍，也许不都该填满。"]
var gw_pending_feedback = ""
var cursor = 1
const DELAY_KEYS = [KEY_1,KEY_2,KEY_3]

func configure() -> void:
	scene_id = "dock"; level_id = "GW04"; title = "两班船，都要赶上"
	if save_path.is_empty(): save_path = Catalog.save_path("GW04")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"trial":3.6,"delivery":3.4}
	zoom_stages = []
	cursor = 1

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "第 16 拍前送完两托 · 开工前可整体延后 0/1/2 拍"
func status_line() -> String: return "延后 %d 拍 · 已选 %d 次交接" % [state.delay,state.picks.size()]
func submit_label() -> String: return "试运行 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "看看班次表","ready":"开始排班",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在码头","重新体验"]
func reset_prompt() -> Array: return ["把延后量和两次交接全部清掉？\n本次试运行与求助次数仍保留。","继续排班","全部清掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "新班次的时刻表铺在码头上，从第 0 拍排到第 16 拍。"
		"ready": return "先挑一档延后量，再点出两次交接；吊台和小车得真的碰上。"
		"puzzle": return "吊台只碰得上小车的那几拍才接得走货。两次都要在第 16 拍前。"
		"trial": return "按这一档延后量跑一遍：吊台逐拍到，小车按点来接……"
		"delivery": return "两托货挂上小车，赶在开船前送出去了。"
		"aftermath": return AFTER[state.beat]
		"complete": return "起点挪一挪，整张时刻表都会跟着变。"
	return ""

func build() -> void:
	for delay in Rules.DELAYS:
		var id = "delay_%d"%delay
		add_button(id,"延后 %d 拍"%delay,delay_rect(delay),set_delay.bind(delay))
		buttons[id].tooltip_text = "开工前把吊台整条时刻表往后挪 %d 拍 · 键盘 %d"%[delay,delay+1]
		UIStyle.style_button(buttons[id],delay == state.delay)
	for tick in range(1,Rules.HORIZON+1):
		add_hotspot("pick_%d"%tick,world.pick_rect(tick),toggle_pick.bind(tick),
			"第 %d 拍 · 点一下设为交接，再点一下取消"%tick)

func delay_rect(delay: int) -> Rect2:
	return Rect2(20+delay*152,210,140,46)

func extra() -> void:
	add_button("journal","回看与发现",Rect2(786,654,124,46),journal).disabled = transient > 0
	if state.stage != "puzzle": return
	world.cursor = cursor
	sign_text("光标：第 %d 拍 · 回车键 R 设为交接"%cursor,Rect2(486,596,348,44),19)

func snapshot(v: Dictionary) -> Dictionary:
	return {"delay":v.delay,"picks":v.picks.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.delay = 0; n.picks = []; return n

func set_delay(delay: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.set_delay(state,delay)
	if next.is_empty(): message = "已经就是延后 %d 拍。"%delay; refresh(); return
	message = ""; place(next)

func toggle_pick(tick: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.toggle_pick(state,tick)
	if next.is_empty():
		message = "两次交接已经选满了：先点掉一次，再选新的。"; refresh(); return
	message = ""; place(next)

func step_cursor(delta: int) -> void:
	cursor = clampi(cursor+delta,1,Rules.HORIZON)
	message = ""; refresh()

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	var previous_stage = state.stage
	super.apply_committed(candidate,next_history)
	if previous_stage == "trial" and candidate.stage == "puzzle":
		message = Rules.shortfalls(candidate)[0]; refresh()
	elif not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

# 选满两次才允许试运行：没选够时先说清缺几次，不进演出。
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle" and state.picks.size() != 2:
		var n = state.duplicate(true); n.attempts = mini(1000000,n.attempts+1)
		gw_pending_feedback = Rules.shortfalls(state)[0]
		commit(n,history); return
	commit(Rules.advance(state),history)

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["吊台每 6 拍到一次，小车每 4 拍到一次。整条吊台时刻表能一起往后挪 0、1 或 2 拍。",
		"把三档都排一遍：不延后吊台到 2、8、14 拍，延后 1 拍到 3、9、15 拍，延后 2 拍到 4、10、16 拍。",
		"小车固定在 4、8、12、16 拍。不延后只在小车第 8 拍碰上一次，凑不满两托。",
		"延后 2 拍：吊台的 4 拍碰上小车第 4 拍、16 拍碰上小车第 16 拍。两次交接就是 4 和 16。"]

func handle_key(key: int) -> bool:
	var slot = DELAY_KEYS.find(key)
	if slot >= 0: set_delay(slot)
	elif key == KEY_LEFT or key == KEY_A: step_cursor(-1)
	elif key == KEY_RIGHT or key == KEY_D: step_cursor(1)
	elif key == KEY_R: toggle_pick(cursor)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,133,780,502),true)
	var text = "班次规则\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	text += "\n\n小车：第 4、8、12、16 拍到，每次接走一托。"
	text += "\n吊台：第 2 拍第一次到，以后每 6 拍一次；开工前可以整条往后挪 0、1 或 2 拍。"
	text += "\n只有吊台和小车同一拍到，才接得走一托。余下两托都要在第 16 拍结束前交完。"
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n\n延后 2 拍：吊台到 4、10、16 拍，\n正好在小车第 4 拍和第 16 拍各接走一托。"
	UIStyle.text(overlay,text,Rect2(290,161,700,389),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,569,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：选好两次交接后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

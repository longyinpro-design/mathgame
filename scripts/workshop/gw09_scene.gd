extends "res://scripts/workshop/workshop_host.gd"
# GW09 旧报时廊「既不漏灯，也不错站」：12 盏灯编号 0～11，从 0 出发固定走 2～8 格，
# 第一次回到 0 前要停遍 1～11，旧记录还要求第 3 站是 9 号灯；两条同时成立才算过。
# 逐跳运行、停站记录与判定都由规则模块算；按钮与键盘共用同一套动作函数。
const Rules = preload("res://scripts/workshop/gw09_rules.gd")
const World = preload("res://scripts/workshop/gw09_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：旧报时廊的 12 盏灯都排在这一圈上，0 号在最上面，顺着圈编号。",
	"小岚：报时的走法固定：从 0 出发，每次走 2～8 格，一圈里不能改；停下才算访问，跨过去不算。",
	"嗒嗒：旧记录写着「第 3 次跳动后停在 9 号灯」。第一次回到 0 之前，要停遍 1～11 每一盏，还不许错站。"]
const AFTER = ["小岚：步长 7：0→7→2→9→4→11→6→1→8→3→10→5→0，12 跳回到 0，一盏都没漏。",
	"嗒嗒：步长 5 也能停遍每一盏，可它第 3 站是 3 号灯；步长 3 第 3 站正好是 9，但第 4 跳就回到 0 了。",
	"小岚：不漏灯和不错站要同时成立，两个条件一起筛，才只剩 7 格。报时信号齐了，屋顶的工单也到了。"]
# 左下角是报时铃的实物；小岚站到右下角、嗒嗒的左边。
func companion_foot() -> Vector2: return Vector2(1100,620)
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "corridor"; level_id = "GW09"; title = "既不漏灯，也不错站"
	if save_path.is_empty(): save_path = Catalog.save_path("GW09")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "从 0 出发 · 固定 2～8 格 · 回 0 前停遍 1～11 · 第 3 站 9"
func status_line() -> String:
	if state.step == 0: return "步长 未设"
	if state.jumps == 0: return "步长 %d · 未起跑"%state.step
	return "步长 %d · 停过 %d / 11 盏"%[state.step,state.visited.size()]
func submit_label() -> String: return "报时校准 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向旧灯环","approach":"铺开灯环",
		"ready":"开始设步长","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在旧报时廊","重新体验"]
func reset_prompt() -> Array: return ["把步长、预测和这一圈停站记录全部抹掉，从头查起？\n求助级别仍保留。","继续查看","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "12 盏灯绕着圈排开，0 号在最上面；旧记录压在一旁。"
		"ready": return "先设步长，再预测第 3 次跳动停在哪一盏，然后一格一格跳。"
		"puzzle": return "从 0 出发，每次固定走 2～8 格；回 0 前停遍 1～11，第 3 站还要是 9。"
		"delivery": return "步长 7：0、7、2、9、4、11、6、1、8、3、10、5，第 12 跳回到 0……"
		"aftermath": return AFTER[state.beat]
		"complete": return "局部对还不够，整圈都要对得上。"
	return ""

func build() -> void:
	for step in range(Rules.STEP_MIN,Rules.STEP_MAX+1):
		add_button("step_%d"%step,str(step),world.step_rect(step),
			choose_step.bind(step),step == state.step)
	for lamp in range(Rules.LAMPS):
		add_button("predict_%d"%lamp,str(lamp),world.predict_rect(lamp),
			predict_lamp.bind(lamp),lamp == state.third)
	if state.jumps == 0:
		add_button("jump","跳一格 J",world.jump_rect(),jump_once,true)
	else:
		add_button("jump","跳一格 J",world.jump_half_rect(),jump_once,true).disabled = Rules.returned(state)
		add_button("rerun","重跑这一圈 R",world.rerun_half_rect(),rerun_circle)

func extra() -> void:
	add_button("journal","回看记录",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary:
	return {"step":v.step,"third":v.third,"jumps":v.jumps,"visited":v.visited.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.step = 0; n.third = -1; n.jumps = 0; n.visited = []; return n

# 设步长：换一个步长会清空这一圈，原来的第 3 站预测也不再作数。
func choose_step(step: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	message = ""; place(Rules.choose_step(state,step))

func step_by(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	place(Rules.move_step(state,delta))

# 预测只能写在第 3 次跳动落地之前；跑过第 3 站之后要重跑才能改口。
# 按钮与键盘都先过这一条判据，再交给规则模块。
func prediction_blocked() -> bool:
	if state.step == 0:
		message = "先设一个步长，再预测第 3 站。"; refresh(); return true
	if state.jumps >= Rules.RECORD_JUMP:
		message = "第 3 站已经跳过了：要改预测，先按 R 重跑这一圈。"; refresh(); return true
	return false

func predict_lamp(lamp: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if prediction_blocked(): return
	var next = Rules.predict(state,lamp)
	if next.is_empty(): return
	message = ""; place(next)

func predict_by(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if prediction_blocked(): return
	place(Rules.move_predict(state,delta))

func jump_once() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.step == 0:
		message = "先设一个步长：每次固定走 2～8 格。"; refresh(); return
	if Rules.returned(state):
		message = "这一圈已经跑完了：点「重跑这一圈」或换一个步长。"; refresh(); return
	message = ""; place(Rules.jump(state))

# 重跑：停站清空，步长与预测都留着；跑过第 3 站之后想改预测就走这里。
func rerun_circle() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.step == 0:
		message = "先设一个步长，再跑这一圈。"; refresh(); return
	if state.jumps == 0:
		message = "这一圈还没起跑。"; refresh(); return
	message = ""; place(Rules.choose_step(state,state.step))

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
	return ["先看 3 格：0、3、6、9，第 3 站正好是 9 号灯——可它第 4 跳就回到 0，漏掉了 8 盏。",
		"把 2～8 每个步长都跑一圈，看哪几个回 0 前能停遍 1～11：只有 5 格和 7 格不会漏灯。",
		"两个不漏灯的候选里，5 格第 3 站是 3 号灯，7 格第 3 站才是 9 号灯。再核对旧记录。",
		"完整示范：步长 7，0→7→2→9→4→11→6→1→8→3→10→5→0；第 3 站 9 号灯，12 跳回到 0。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: step_by(-1)
	elif key == KEY_RIGHT or key == KEY_D: step_by(1)
	elif key == KEY_J: jump_once()
	elif key == KEY_R: rerun_circle()
	elif key == KEY_Q: predict_by(-1)
	elif key == KEY_E: predict_by(1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "旧报时记录\n环上 12 盏灯编号 0～11，从 0 出发，每次固定走 2～8 格。\n顺时针，途中不改步长；停下才算访问，跨过不算。\n第一次回到 0 之前要停遍 1～11 每一盏。\n旧记录：第 3 次跳动后停在 9 号灯。\n\n这一圈\n"
	if state.step == 0:
		text += "还没设步长。\n"
	else:
		text += "步长 %d，跳了 %d 次"%[state.step,state.jumps]
		if state.visited.is_empty(): text += "，还没停过灯。\n"
		else:
			var stops = []
			for lamp in state.visited: stops.append(str(lamp))
			text += "，停站 %s。\n"%("→".join(stops))
		if Rules.returned(state):
			if Rules.covered(state): text += "第 %d 跳回到 0 号灯，回 0 前停遍 11 盏。\n"%state.jumps
			else: text += "第 %d 跳就回到 0 号灯，只停过 %d 盏。\n"%[state.jumps,state.visited.size()]
		else:
			text += "现在停在 %d 号灯，这一圈还没跑完。\n"%Rules.cursor(state)
		if state.third < 0: text += "第 3 站预测：还没写。\n"
		elif state.jumps < Rules.RECORD_JUMP: text += "第 3 站预测：%d 号灯。\n"%state.third
		else: text += "第 3 站：预测 %d 号灯，实际 %d 号灯。\n"%[state.third,Rules.third_stop(state.step)]
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n发现卡\n步长 7：0→7→2→9→4→11→6→1→8→3→10→5→0，全覆盖且第 3 站 9 号灯。\n步长 5 也全覆盖，但第 3 站是 3；步长 3 第 3 站是 9，却第 4 跳就回到 0。\n"
	UIStyle.text(overlay,text,Rect2(250,121,780,440),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：设好步长与预测后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

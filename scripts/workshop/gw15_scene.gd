extends "res://scripts/workshop/workshop_host.gd"
# GW15 装配间「最早的一次观察」：机器周期可能是 3、4、5 拍之一，身份开局固定、重试不重抽；
# 出料窗只能开一次，要在第 1～12 拍里选最早能分清三种机器的时刻，再挂对周期牌。
# 时刻、开窗与周期牌都走规则模块；按钮与键盘共用同一套动作函数与合法性判据。
const Rules = preload("res://scripts/workshop/gw15_rules.gd")
const World = preload("res://scripts/workshop/gw15_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：它每 3、4 或 5 拍出一件，开局 0 件，第一件要等第一个周期结束。",
	"小岚：身份开局就定死了，只知道是 3、4、5 拍里的一个；出料窗只开一次。",
	"嗒嗒：锁一个时刻开窗，看那一拍累计多少件，再挂周期牌；要选最早能分清的。"]
const AFTER = ["嗒嗒：第 9 拍，3 拍机器是 3 件、4 拍是 2 件、5 拍是 1 件，三份全不一样。",
	"小岚：1～8 拍每次都至少两份相同；第 12 拍也能分，但不是最早。",
	"嗒嗒：挂上 4 拍的牌子，这台机器的周期就定下来了；观察记录也留进档案。"]
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "assembly"; level_id = "GW15"; title = "最早的一次观察"
	if save_path.is_empty(): save_path = Catalog.save_path("GW15")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "周期 3/4/5 拍之一 · 出料窗只开一次 · 选最早能分清三种机器的时刻"
func status_line() -> String:
	if state.stage != "puzzle": return ""
	if state.observe < Rules.TIME_MIN: return "观察时刻 未锁定"
	if not state.opened: return "第 %d 拍 · 未开窗"%state.observe
	if state.assigned == 0: return "第 %d 拍 · 累计 %d 件 · 未挂牌"%[state.observe,Rules.observed(state)]
	return "第 %d 拍 · 累计 %d 件 · %d 拍牌"%[state.observe,Rules.observed(state),state.assigned]
func submit_label() -> String:
	if state.observe < Rules.TIME_MIN: return "先锁时刻 Space"
	if not state.opened: return "先开窗 Space"
	if state.assigned == 0: return "先挂周期牌 Space"
	return "确认周期 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向出料机","ready":"开始观察",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装配间","重新体验"]
func reset_prompt() -> Array: return ["把这一次锁定的时刻、开窗结果与周期牌全部抹掉？\n比较过的时刻也会清空，求助级别仍保留。","继续观察","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "出料机推上台面，时间尺与三块周期牌摊在一旁。"
		"ready": return "先锁一个观察时刻；开窗前先想：这一拍三种周期各累计多少件？"
		"puzzle":
			if state.observe < Rules.TIME_MIN:
				return "第 1～12 拍选一个观察时刻：出料窗只开一次，先想清楚。"
			if not state.opened:
				return "第 %d 拍锁定了。开窗前先想：三种机器这一拍各累计多少件？"%state.observe
			if state.assigned == 0:
				return "第 %d 拍开窗看到累计 %d 件。挂上对应的周期牌。"%[state.observe,Rules.observed(state)]
			return "第 %d 拍累计 %d 件 · 周期牌 %d 拍。确认就提交。"%[state.observe,Rules.observed(state),state.assigned]
		"delivery": return "按第 9 拍重演：3 拍机器 3 件、4 拍机器 2 件、5 拍机器 1 件……"
		"aftermath": return AFTER[state.beat]
		"complete": return "先选能分清的观察，再挂对周期牌。"
	return ""

func build() -> void:
	for t in range(Rules.TIME_MIN,Rules.TIME_MAX+1):
		add_button("time_%d"%t,str(t),world.time_rect(t),select_time.bind(t),
			t == state.observe).disabled = state.opened
	add_button("open","开窗 O（只有一次）",world.open_rect(),open_window).disabled = state.observe < Rules.TIME_MIN or state.opened
	for period in Rules.PERIODS:
		add_button("period_%d"%period,"周期牌 %d 拍"%period,world.plaque_rect(period),
			hang.bind(period),period == state.assigned).disabled = not state.opened

func extra() -> void:
	add_button("journal","观察记录",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary:
	return {"observe":v.observe,"opened":v.opened,"assigned":v.assigned,"tried":v.tried.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.observe = 0; n.opened = false; n.assigned = 0; n.tried = []; return n

# 锁一个观察时刻：开过窗之后时刻冻住，要换只能重摆。
func select_time(t: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.opened:
		message = "观察时刻已经开过窗了：要换时刻，先按 X 重新安排。"; refresh(); return
	message = ""; place(Rules.select_time(state,t))

func step_time(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.opened:
		message = "观察时刻已经开过窗了：要换时刻，先按 X 重新安排。"; refresh(); return
	place(Rules.move_time(state,delta))

# 开窗：这一下就是玩家花掉的那一次观察，先念出实际累计数。
func open_window() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.observe < Rules.TIME_MIN:
		message = "先锁一个观察时刻：第 1～12 拍里选一拍。"; refresh(); return
	if state.opened:
		message = "出料窗只能打开一次：要重新观察，先按 X 重新安排。"; refresh(); return
	var next = Rules.open_window(state)
	if next.is_empty(): return
	gw_pending_feedback = "出料窗打开：第 %d 拍累计 %d 件。"%[next.observe,Rules.observed(next)]
	place(next)

func hang(period: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if not state.opened:
		message = "先开窗看一眼实际累计数，再挂周期牌。"; refresh(); return
	message = ""; place(Rules.hang(state,period))

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
	return ["观察前就要考虑三种可能：3 拍、4 拍、5 拍在同一拍各会累计多少件。",
		"比较同一时刻的三份累计数：三份都不一样，才能凭这一次观察分清是哪台机器。",
		"第 8 拍是 2、2、1：3 拍和 4 拍都是 2 件，还分不清；再往后找三份都不同的时刻。",
		"第 9 拍是 3、2、1，三份全不同；1～8 拍每次都至少两份相同。第 9 拍就是最早的。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: step_time(-1)
	elif key == KEY_RIGHT or key == KEY_D: step_time(1)
	elif key == KEY_O: open_window()
	elif key == KEY_3: hang(3)
	elif key == KEY_4: hang(4)
	elif key == KEY_5: hang(5)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "出料观察记录\n机器周期可能是 3、4、5 拍之一；开局 0 件，第一件在第一个周期结束时出现。\n出料窗只能打开一次，要选最早能分清三种机器的观察时刻；周期牌也要和实际一致。\n\n比较过的时刻\n"
	if state.tried.is_empty(): text += "还没锁过任何时刻。\n"
	for t in state.tried.slice(0,6):
		# 对照数属于第 2 档主动提示：没到那一步，记录里只留玩家自己锁过的时刻。
		if world.comparison_open(): text += "第 %d 拍：%s\n"%[t,Rules.count_text(t)]
		else: text += "第 %d 拍\n"%t
	if state.tried.size() > 6: text += "…还有 %d 个时刻没列出来。\n"%(state.tried.size()-6)
	if not state.tried.is_empty() and not world.comparison_open():
		text += "（第 2 档主动提示后，这里会附上每一拍的三份累计数。）\n"
	if state.opened:
		text += "\n本次观察：第 %d 拍 · 累计 %d 件。"%[state.observe,Rules.observed(state)]
		if state.assigned != 0: text += " 周期牌：%d 拍。"%state.assigned
		text += "\n"
	else:
		text += "\n本次还没开窗。\n"
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n发现卡\n第 9 拍是 3、2、1，三份全不同；1～8 拍每次都至少两份相同。\n第 12 拍也能分，但不是最早；第 10 拍是 3、2、2，晚一点不一定更有用。"
	UIStyle.text(overlay,text,Rect2(250,121,780,500),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：锁好时刻、开过窗、挂好牌之后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

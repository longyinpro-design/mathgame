extends "res://scripts/workshop/workshop_host.gd"
const Rules = preload("res://scripts/workshop/gw01_rules.gd")
const World = preload("res://scripts/workshop/gw01_world.gd")
const ARRIVAL = ["阿橙：搬运记录被蒸汽打湿了，只剩最后一行：甲、乙、丙各 8 根。",
	"嗒嗒：我先用甲托给另外两托补到两倍，再轮到乙托，最后轮到丙托。",
	"小岚：共 24 根，一根没丢。找回三托最初各有多少，才能修好这张货单。"]
const AFTER = ["嗒嗒：三轮后果然各 8 根！起始货单找回来了。",
	"阿橙：等等……托盘还在上面，小车却已经走过去了。",
	"小岚：数量的来龙去脉清楚了。下一步，再查升降台和小车的时间。"]
var selected = -1
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "dock"; level_id = "GW01"; title = "被蒸汽抹去的货单"
	if save_path.is_empty(): save_path = "user://profiles/workshop-gw01-3/save-v1.json"
	rules = Rules; world_script = World
	durations = {"approach":2.4,"delivery":4.0}
	zoom_stages = []

# 工坊镜头固定：宿主 _process 每帧都会调用这里，覆写后整幕保持 1:1、不平移。
func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func snapshot(v: Dictionary) -> Dictionary: return {"trays":v.trays.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.trays = [0,0,0]; return n
func reset_prompt() -> Array: return ["把三托全部取回，重新推想起始数量？\n本次求助与试运行次数仍保留。","继续推想","全部取回"]
func restart_prompt() -> Array: return ["重新体验这张被打湿的货单？","留在码头","重新体验"]
func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "空车又过去了。先找回货单，弄清这一批灯轴是怎样分配的。"
		"ready": return "每轮由一托出货，让另外两托各变成原来的两倍。顺序：甲 → 乙 → 丙。"
		"puzzle": return "还原起始数量。每轮用接收托当时的数量计算；第三轮结束，三托各 8 根。"
		"trial":
			if state.round == 3: return "三轮已走完。对照记录：三托是否各有 8 根？"
			return "第 %d 轮将由%s托出货：给另外两托各补一份，让它们的数量翻倍。"%[state.round+1,Rules.NAMES[state.round]]
		"delivery": return "三轮验证成功，货单恢复。升降台试着把第一托抬起来……"
		"aftermath": return AFTER[state.beat]
		"complete": return "从结果倒着想，找回了起点。货还在码头，接着要查交接的时间。"
	return ""

func target_name() -> String: return Rules.NAMES[selected]+"托"
func target_count() -> int: return state.trays[selected]

func refresh() -> void:
	if not is_instance_valid(world): return
	world.state = state; world.selected = selected; world.presentation_paused = modal or paused or not focused
	world.queue_redraw()
	clear_children(ui)
	for child in world.get_children(): world.remove_child(child); child.queue_free()
	buttons = {}
	sign_text(chapter_label() + " · " + title,Rect2(24,18,480,52),24)
	if state.stage not in ["arrival","approach"]: sign_text("24 根 · 甲→乙→丙 · 最后各 8 根",Rect2(640,18,616,52),22)
	sign_text(message if not message.is_empty() else line(),Rect2(250,92,880,88),20)
	if state.stage == "puzzle":
		for i in range(3):
			var b = add_button("target_%d"%i,"",world.tray_rect(i),select_target.bind(i))
			UIStyle.hotspot(b,Rules.NAMES[i]+"托 · 键盘 %d"%(i+1))
			b.focus_mode = Control.FOCUS_ALL; b.disabled = transient > 0
		if selected >= 0:
			sign_text("起始："+target_name(),Rect2(260,520,180,48),20)
			add_button("one","放 1 根 A",Rect2(452,520,142,48),move_goods.bind(1)).disabled = not can_move(1)
			add_button("batch","放 5 根 B",Rect2(606,520,142,48),move_goods.bind(5)).disabled = not can_move(5)
			add_button("take","取 1 根 D",Rect2(760,520,142,48),move_goods.bind(-1)).disabled = not can_move(-1)
			add_button("empty","取空此托 C",Rect2(914,520,165,48),empty_tray).disabled = target_count() == 0 or transient > 0
		else: sign_text("点选甲、乙、丙托，摆出你推想的起始数量",Rect2(280,520,800,48),20)
		add_button("undo","撤销 Z",Rect2(24,650,130,50),undo).disabled = history.is_empty() or transient > 0
		add_button("reset","重摆 X",Rect2(166,650,130,50),confirm_reset).disabled = transient > 0
		add_button("hint","请嗒嗒提醒 H",Rect2(309,650,190,50),hint).disabled = transient > 0
		add_button("deliver","试运行 Space",Rect2(1010,650,246,50),advance,true).disabled = transient > 0
	elif state.stage == "trial":
		add_button("back_plan","返回起始摆法",Rect2(748,650,224,50),back_to_plan).disabled = transient > 0
		add_button("trial_next","核对记录 Space" if state.round == 3 else "执行第 %d 轮 Space"%(state.round+1),Rect2(990,650,266,50),advance,true).disabled = transient > 0
		sign_text("逐轮观察；可随时返回起始摆法修改",Rect2(290,525,680,48),20)
	elif state.stage in Rules.ANIMATIONS:
		add_button("pause","继续动画" if paused else "暂停动画",Rect2(882,650,150,50),toggle_pause)
		add_button("skip","跳过动画",Rect2(1046,650,210,50),skip_animation)
	else:
		var caption = {"arrival":"继续听他们说" if state.beat < 2 else "看看码头怎么走",
			"ready":"还原起始货单","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现",
			"complete":"重新体验这一关"}
		if caption.has(state.stage): add_button("next",caption[state.stage],Rect2(966,650,290,50),confirm_restart if state.stage == "complete" else advance,true)
	add_button("journal","回看与发现",Rect2(520,650,168,50),journal).disabled = transient > 0
	if state.stage == "complete":
		sign_text("倒着想：接收时变两倍，还原时就取一半。",Rect2(276,535,754,54),20)
	if modal:
		for b in buttons.values(): b.disabled = true

func select_target(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	selected = index; message = ""; refresh()
	buttons["target_%d"%index].grab_focus()
func can_move(amount: int) -> bool:
	return selected >= 0 and transient <= 0 and not Rules.move(state,selected,amount).is_empty()
func move_goods(amount: int) -> void:
	if modal or transient > 0 or selected < 0 or state.stage != "puzzle": return
	# 键盘 A/B/C/D 不受按钮禁用态约束：与按钮同一条 can_move 判据，不合法就安静地什么都不做。
	if not can_move(amount): return
	place(Rules.move(state,selected,amount))
func empty_tray() -> void:
	if selected >= 0 and state.stage == "puzzle" and target_count() > 0: move_goods(-target_count())
func back_to_plan() -> void:
	if modal or transient > 0: return
	commit(Rules.back_to_plan(state),history)
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle" and Rules.stock(state) != 0:
		var n = state.duplicate(true); n.attempts = mini(1000000,n.attempts+1)
		gw_pending_feedback = Rules.shortfalls(state)[0]
		commit(n,history); return
	var n = Rules.advance(state)
	if state.stage == "trial" and not n.is_empty() and n.stage == "puzzle":
		gw_pending_feedback = Rules.shortfalls(state)[0]
	commit(n,history)
# Feedback is installed with the candidate, including retry_save's shared apply path.
func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["起点不知道，终点却很清楚。可以从最后一轮发生的事往回想。",
		"最后是丙托出货。甲、乙收到后变成 8 根，那么收到以前各有几根？",
		"撤回最后一轮：甲、乙各退回 4 根给丙，得到 4、4、16。接下来该撤回谁的那一轮？",
		"示范倒推：8、8、8 → 4、4、16 → 2、14、8 → 13、7、4。再按甲、乙、丙正向验证。"]
func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_3: select_target(key-KEY_1)
	elif key == KEY_A: move_goods(1)
	elif key == KEY_B: move_goods(5)
	elif key == KEY_C: empty_tray()
	elif key == KEY_D: move_goods(-1)
	else: return false
	return true
func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,153,780,462),true)
	var text = "货单规则\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	if state.stage == "complete": text += "\n\n倒着想，顺着验\n8、8、8 ← 4、4、16 ← 2、14、8 ← 13、7、4。\n原来甲 13 根、乙 7 根、丙 4 根。每次接收变两倍，倒推取一半。"
	UIStyle.text(overlay,text,Rect2(290,181,700,349),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,549,225,48),close_modal,true,overlay).grab_focus()

# Space is the advertised inspection shortcut even immediately after choosing a target.
# Enter retains normal focused-button activation for Tab navigation.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") in ["puzzle","trial"] and not modal:
		advance(); get_viewport().set_input_as_handled()

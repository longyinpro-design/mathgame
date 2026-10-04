extends Control
const Archipelago = preload("res://scripts/archipelago/bridge.gd")
const Rules = preload("res://scripts/market/mk01_rules.gd")
const World = preload("res://scripts/market/mk01_world.gd")
const Repository = preload("res://scripts/persistence/save_repository.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const DURATIONS = {"approach":1.6,"measuring":4.5,"delivery":5.0}
const FOREST_SCENE = "res://game/forest_release.tscn"
const NURSERY_SCENE = "res://game/market_mk02.tscn"
const ISLAND_SCENE = "res://game/market_island.tscn"
const LINES = ["码头工：容量牌被雨冲掉了，这批杯子可不能凭外形猜。","陶姨：蓝杯和白杯各能装二到八小杯，同一种杯装得一样多。","小岚：先测两种混合装法，看看换一只杯会改变多少。"]
var save_path = "user://profiles/market-mk01-2/save-v2.json"
# Set by the forest release hub before switching in: "camp" = arrived from the camp,
# and this sample writes "return" back on the way out so the forest opens at the camp.
static var entry = ""
var from_camp = false
var from_hub = false
var repository = Repository.new()
var state = Rules.fresh()
var pending: Dictionary = {}
var pending_history: Array = []
var history: Array = []
var world: Node2D
var ui: Control
var overlay: Control
var buttons: Dictionary = {}
var selected = -1
var elapsed = 0.0
var time_scale = 1.0
var paused = false:
	set(value):
		paused = value
		sync_presentation()
var message = ""
var modal = false:
	set(value):
		modal = value
		sync_presentation()
var transient = 0.0
var focused = true:
	set(value):
		focused = value
		sync_presentation()
var window_theme: Theme

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	from_camp = entry == "camp"; entry = ""
	from_hub = Bridge.origin == "hub"
	if from_hub: Bridge.origin = ""
	save_path = Archipelago.legacy_path("MK01",save_path)
	repository.path = save_path
	var read = repository.read_profile(Rules.validate)
	if read.status == "loaded": state = read.profile
	world = World.new(); add_child(world)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	get_window().title = "千灯集市 · MK01 接货台样板"
	# 与 level_host 同一条：tooltip 的主题只继承到 Window，MK01 不走宿主基类，所以这里各设一次。
	window_theme = get_window().theme
	get_window().theme = UIStyle.tooltip_theme()
	refresh()
	if read.status == "protected": show_protected()
	Archipelago.attach_legacy(self,"market")

func _exit_tree() -> void:
	if is_instance_valid(get_window()): get_window().theme = window_theme

func sync_presentation() -> void:
	if is_instance_valid(world): world.presentation_paused = modal or paused or not focused

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: focused = true
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(world) and state.stage in Rules.ANIMATIONS:
		paused = true
		if buttons.has("pause"): buttons.pause.text = "继续动画"

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_visible_in_tree(): return
	if modal or paused or not focused: return
	if transient > 0:
		transient = maxf(0,transient-delta/maxf(0.01,time_scale))
		world.move_progress = 1-transient/0.3
		if transient == 0: refresh()
	if state.stage in Rules.ANIMATIONS:
		elapsed += delta/maxf(0.01,time_scale)
		world.progress = minf(1,elapsed/DURATIONS[state.stage])
		if world.progress >= 1: commit(Rules.advance(state),history)
	update_camera()
	world.queue_redraw()

func update_camera() -> void:
	var amount = 0.0 if state.stage in ["arrival","complete"] else 1.0
	if state.stage == "approach": amount = smoothstep(0,1,world.progress)
	if state.stage == "delivery": amount = 1-smoothstep(0,0.45,world.progress)
	world.scale = Vector2.ONE*lerpf(1,1.16,amount)
	# 贴脸那一段整张台面往下让 26 像素：吊车的滑轮画在世界 (313,96)，按旧的 -66 换算到屏幕只剩 y 45，
	# 正好藏进「千灯集市」那块抬头板底下，绳子看着就像拴在标题牌上。让到 -40 之后滑轮落在 71.4，
	# 抬头板底是 68；台面最下沿那块小杯容量签（世界 515）换算到 557，离底栏按钮的 646 还留着 89 像素。
	world.position = Vector2(-111,-40)*amount

func commit(candidate: Dictionary, next_history: Array = []) -> bool:
	if candidate.is_empty() or modal: return false
	if not repository.write_profile(candidate,Rules.validate):
		pending = candidate.duplicate(true); pending_history = next_history.duplicate(true)
		show_save_error(); return false
	apply_committed(candidate,next_history)
	return true

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	var previous = state
	state = candidate.duplicate(true); history = next_history.duplicate(true)
	if previous.stage != state.stage:
		elapsed = 0; world.progress = 0; paused = false; selected = -1
	# 与宿主同一条：每落一步先把上一句说过的话收掉。留在屏上就会出现
	# 「交货需要恰好三只满杯」还挂在一盘已经摆好三只杯的托盘旁边。
	message = ""
	if previous.slots != state.slots and state.stage == "puzzle":
		for id in range(8):
			if previous.slots.find(id) != state.slots.find(id):
				world.state = previous; world.move_from = world.cup_foot(id)
				world.state = state; world.move_to = world.cup_foot(id)
				world.move_id = id; transient = 0.3; world.move_progress = 0; break
	selected = -1
	refresh()

func retry_save() -> void:
	if pending.is_empty(): return
	if not repository.write_profile(pending,Rules.validate): show_save_error(); return
	var candidate = pending; var next_history = pending_history
	pending = {}; pending_history = []; close_modal(); apply_committed(candidate,next_history)

func clear_children(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func add_button(id: String, text: String, rect: Rect2, callback: Callable, primary: bool = false, parent: Node = null) -> Button:
	var button = UIStyle.button(ui if parent == null else parent,text,rect,callback,primary)
	button.name = id; buttons[id] = button
	return button

func sign_text(text: String, rect: Rect2, size_px: int = 20) -> void:
	UIStyle.sign(ui,rect)
	UIStyle.text(ui,text,Rect2(rect.position+Vector2(14,8),rect.size-Vector2(28,12)),size_px)

func refresh() -> void:
	sync_presentation()
	world.queue_redraw()
	clear_children(ui)
	for child in world.get_children(): world.remove_child(child); child.queue_free()
	buttons = {}; world.state = state; world.selected = selected
	update_camera()
	sign_text("千灯集市 · 找回杯子的刻度",Rect2(24,20,394,48),22)
	if state.stage not in ["arrival","complete","delivery"]:
		# 三幕三种目标：还没核对时说的是复核规矩，推容量那一幕要说的是这一步真正要做的事，
		# 已经把签挂回去之后才轮到那张交货单。
		var goal = "交货：恰好 3 只满杯 · 合计 11 小杯"
		if not state.calibrated:
			if state.stage == "deduction": goal = "比较左边两张整盘回执：把蓝杯、白杯各装几小杯填进容量签"
			else: goal = "先复核：每盘 3 只 · 蓝白都要有 · 只读整盘"
		sign_text(goal,Rect2(442,20,790,48),22)
	var line = ""
	match state.stage:
		"arrival": line = LINES[state.beat]
		"approach": line = "两家的杯子放在同一张接货台上，测量回执就挂在旁边。"
		"ready": line = "每盘放三只满杯，蓝白都要有。蓝白各为 2—8 小杯；小杯留作交货。"
		"puzzle":
			line = "容量已经核对。现在接新订单：三只满杯装好十一小杯。" if state.calibrated else "先选一种蓝白混合装法。总量揭晓后，再换一只杯比较。"
		"measuring": line = "按你摆好的杯子倒入量槽……" if state.calibrated else "挡板合上，只在三杯混合完后读总量，不能逐杯偷看。"
		"result":
			if not state.calibrated:
				line = "整盘是 %d 小杯，回执已挂好。%s"%[Rules.volume(state.slots),"换一种蓝白组合，比较差别。" if not Rules.knowledge_ready(state) else "比较两张回执，给蓝杯、白杯挂回容量签。"]
			elif Rules.delivered(state): line = "陶姨：三只满杯，正好十一小杯！这次两家都能核对清楚。"
			else: line = "这次是 %d 只杯、%d 小杯的量；需要 3 只满杯、11 小杯。"%[Rules.count(state.slots),Rules.volume(state.slots)]
		"deduction": line = "看左边两张回执，蓝杯换成白杯后总量怎样变？请自己填写容量签。"
		"delivery": line = "码头工：刻度找回来了，订单也对了。起吊——把种子送上岸！"
		"complete": line = "扣扣：两张回执一起看，才找回了每只杯的刻度。种子可以交给陶姨啦！"
	if not message.is_empty(): line = message
	sign_text(line,Rect2(338,98,826,86),20)
	if state.stage in Rules.ANIMATIONS:
		add_button("pause","继续动画" if paused else "暂停动画",Rect2(922,654,140,46),toggle_pause)
		add_button("skip","跳过当前动画",Rect2(1080,654,176,46),skip_animation)
	elif state.stage == "puzzle":
		for id in range(8):
			if id in state.slots: continue
			var b = add_button("cup_%d"%id,"",world.cup_rect(id),select_cup.bind(id),false,world)
			UIStyle.hotspot(b,world.cup_description(id))
			# Cups and tray positions are reached with 1-8 and Q/W/E; the scene draws its own
			# highlight, so the button must not stamp a framed box over the artwork.
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = modal or transient > 0
		for slot in range(3):
			var seated = state.slots[slot]
			var note = "空着，先点一只杯子，再点这里放下"
			if seated >= 0: note = "放着%s，点一下取回"%["蓝杯","白杯","小杯"][world.cup_kind(seated)]
			var b = add_button("slot_%d"%slot,"",world.slot_rect(slot),choose_slot.bind(slot),false,world)
			UIStyle.hotspot(b,"托盘 %s 位 · %s"%[World.SLOT_KEYS[slot],note])
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = modal or transient > 0
		add_button("undo","撤销 Z",Rect2(24,654,124,46),undo).disabled = history.is_empty() or transient > 0
		add_button("reset","重摆 X",Rect2(162,654,110,46),confirm_reset).disabled = transient > 0
		add_button("hint","请扣扣提醒",Rect2(286,654,162,46),hint).disabled = transient > 0
		add_button("measure","验收交货" if state.calibrated else "测这一盘总量",Rect2(1020,646,235,54),advance,true).disabled = transient > 0
		var instruction = "已放 %d / 3 只 · %s"%[Rules.count(state.slots),"提交后验量" if state.calibrated else "已留 %d 份回执"%state.observations.size()]
		if selected >= 0: instruction = "已选%s · 点一个托盘位"%["蓝杯","白杯","小杯"][world.cup_kind(selected)]
		UIStyle.text(ui,instruction,Rect2(475,656,510,42),20)
	elif state.stage == "deduction":
		for kind in range(2):
			var x = 24+kind*344
			var value: int = state.guesses[kind]
			sign_text("%s签：%s 小杯"%["蓝杯" if kind == 0 else "白杯","？" if value == 0 else str(value)],Rect2(x+54,647,222,48),20)
			add_button("guess_down_%d"%kind,"−",Rect2(x,647,48,48),adjust_guess.bind(kind,-1))
			add_button("guess_up_%d"%kind,"+",Rect2(x+280,647,48,48),adjust_guess.bind(kind,1))
		add_button("hint","请扣扣提醒",Rect2(730,647,180,48),hint)
		add_button("confirm_capacity","挂回容量签",Rect2(1020,646,235,54),confirm_capacity,true)
	else:
		var result_action = "把种子吊上岸" if Rules.delivered(state) else "回到托盘调整"
		if not state.calibrated: result_action = "给杯子挂容量签" if Rules.knowledge_ready(state) else "换一只杯再测"
		var labels = {"arrival":"继续听他们说" if state.beat < 2 else "靠近接货台","ready":"开始复核","result":result_action,"complete":"再体验一次"}
		if labels.has(state.stage): add_button("next",labels[state.stage],Rect2(982,646,274,54),confirm_restart if state.stage == "complete" else advance,true)
		if state.stage == "complete" and from_camp: add_button("back_forest","交完货 · 回营地",Rect2(700,646,270,54),go_forest)
		if state.stage == "complete": add_button("next_sample","去育苗铺 · 留下一段线",Rect2(414,646,272,54),go_nursery)
		if state.stage == "complete" and from_hub: add_button("back_hub","返回千灯航图",Rect2(132,646,270,54),go_hub)
		# 营地进来的旅客也要能直接上航图，否则后面十七站在游戏里没有路可达（重玩时本关已经停在 complete，不该再走一遍育苗铺）。
		if state.stage == "complete" and from_camp: add_button("open_hub","去千灯航图",Rect2(132,646,270,54),go_hub)
		if state.stage == "result" and state.calibrated and not Rules.delivered(state): add_button("undo_result","撤销上一次摆杯",Rect2(24,654,225,46),undo_from_result).disabled = history.is_empty()
	if modal:
		for b in buttons.values(): b.disabled = true

func select_cup(id: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	selected = -1 if selected == id else id
	message = ""; refresh()

func choose_slot(slot: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.place(state,selected,slot) if selected >= 0 else Rules.remove(state,slot)
	if next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(state.slots.duplicate())
	commit(next,next_history)

func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle":
		var error = Rules.measurement_error(state)
		if not error.is_empty(): message = error; refresh(); return
	commit(Rules.advance(state),history)

func toggle_pause() -> void:
	if modal: return
	paused = not paused
	refresh()

func skip_animation() -> void:
	if modal or state.stage not in Rules.ANIMATIONS: return
	commit(Rules.advance(state),history)

func undo() -> void:
	if modal or transient > 0 or state.stage != "puzzle" or history.is_empty(): return
	var next_history = history.duplicate(true)
	var next = state.duplicate(true); next.slots = next_history.pop_back()
	commit(next,next_history)

func undo_from_result() -> void:
	if modal or history.is_empty() or state.stage != "result" or not state.calibrated or Rules.delivered(state): return
	var next_history = history.duplicate(true)
	var next = state.duplicate(true); next.stage = "puzzle"; next.slots = next_history.pop_back()
	commit(next,next_history)

func adjust_guess(kind: int, delta: int) -> void:
	if modal: return
	var value: int = state.guesses[kind]
	value = 2 if value == 0 else clampi(value+delta,2,8)
	if commit(Rules.set_guess(state,kind,value),history):
		buttons["guess_%s_%d"%["up" if delta > 0 else "down",kind]].grab_focus()

func confirm_capacity() -> void:
	if modal or state.stage != "deduction": return
	var next = Rules.confirm_capacity(state)
	if next.is_empty():
		message = "这两张容量签不能同时解释两份回执。保留你的标记，再核对一下。"
		refresh(); return
	commit(next)

func hint() -> void:
	if modal or state.stage not in ["puzzle","deduction"]: return
	var next = state.duplicate(true); next.hint = mini(3,next.hint+1)
	if commit(next,history):
		var hints = ["试着让两盘只相差一只杯，比较它们的总量。","把两盘中相同的杯子先放到一边，看看剩下哪种杯在互换。","蓝换成白以后少了多少？把这个差代回其中一盘，再找单杯容量。"]
		if state.calibrated: hints = ["现在用已确认的容量，思考怎样在三个位子里装十一小杯。","先看两只较大杯能组成多少，再想剩下的一个位子。","可以先放一只蓝杯，剩下两个位子还需要五小杯。"]
		message = hints[next.hint-1]; refresh()

func show_modal(text: String) -> void:
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.color = Color(0.035,0.05,0.055,0.8); shade.size = Vector2(1280,720); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(322,225,636,264))
	UIStyle.text(overlay,text,Rect2(360,257,560,126),22)

func close_modal() -> void:
	modal = false; clear_children(overlay); refresh()

func show_save_error() -> void:
	show_modal(repository.error+"\n现场仍是上次成功保存的状态。")
	add_button("retry","重试保存",Rect2(660,410,226,50),retry_save,true,overlay).grab_focus()

func show_protected() -> void:
	show_modal("样板记录无法读取，原文件已保留。\n可关闭窗口保留现场，或保留旧文件后重新开始。")
	add_button("protect_confirm","保留原档并重新开始",Rect2(504,410,382,50),recover_protected,true,overlay).grab_focus()

func recover_protected() -> void:
	if repository.preserve_protected_file().is_empty(): show_protected(); return
	close_modal(); commit(Rules.fresh())

func confirm_reset() -> void:
	if modal or transient > 0: return
	show_modal("把托盘上的杯子全部放回货架？\n你仍留在接货台，不重播开场。")
	add_button("cancel","继续摆杯",Rect2(390,410,206,50),close_modal,false,overlay)
	add_button("confirm","放回货架",Rect2(666,410,220,50),reset_cups,true,overlay).grab_focus()

func reset_cups() -> void:
	close_modal(); var next = state.duplicate(true); next.slots = [-1,-1,-1]
	commit(next)

func confirm_restart() -> void:
	if modal: return
	show_modal("重新体验码头这一幕？\n只重置本样板，不改变森林岛进度。")
	add_button("cancel","留在码头",Rect2(390,410,206,50),close_modal,false,overlay)
	add_button("confirm","重新体验",Rect2(666,410,220,50),restart,true,overlay).grab_focus()

func restart() -> void:
	close_modal(); commit(Rules.fresh())

func go_forest() -> void:
	if modal or transient > 0: return
	entry = "return"
	get_tree().change_scene_to_file(FOREST_SCENE)

func go_nursery() -> void:
	if modal or transient > 0: return
	Bridge.origin = "mk01"
	get_tree().change_scene_to_file(NURSERY_SCENE)

func go_hub() -> void:
	if modal or transient > 0: return
	get_tree().change_scene_to_file(ISLAND_SCENE)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or modal: return
	if event.keycode == KEY_ESCAPE:
		selected = -1
		if state.stage in Rules.ANIMATIONS: toggle_pause()
		else: refresh()
	elif state.stage == "puzzle" and transient <= 0:
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			var id = event.keycode-KEY_1
			if id not in state.slots: select_cup(id)
		elif event.keycode in [KEY_Q,KEY_W,KEY_E]: choose_slot([KEY_Q,KEY_W,KEY_E].find(event.keycode))
		elif event.keycode == KEY_Z: undo()
		elif event.keycode == KEY_X: confirm_reset()
		elif event.keycode == KEY_H: hint()
		elif event.keycode == KEY_SPACE: advance()
	get_viewport().set_input_as_handled()

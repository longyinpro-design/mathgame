extends Control
const Rules = preload("res://scripts/market/mk02_rules.gd")
const World = preload("res://scripts/market/mk02_world.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const HarborSample = preload("res://scripts/market/mk01_scene.gd")
const Repository = preload("res://scripts/persistence/save_repository.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const DURATIONS = {"approach":1.6,"delivery":4.2}
const LAND_TIME = 0.28
const FOREST_SCENE = "res://game/forest_release.tscn"
const LINES = ["扣扣：种子先寄存到育苗铺……这次的回礼，我可以少拿一点。","小岚：别急着让步。台面上有 8 颗铜果，门口挂着两条公开的约定。","陶姨：2 颗铜果换 3 卷线，2 卷线换 1 根灯芯，只能整组换。码头要 5 根灯芯，扣扣的捆货绳还差 2 卷线。"]
var save_path = "user://profiles/market-mk02-1/save-v1.json"
# Set by MK01 before switching in: "mk01" = arrived from the harbour, and this sample
# hands the camp return back through MK01's own forest handshake.
var from_harbour = false
var repository = Repository.new()
var state = Rules.fresh()
var pending: Dictionary = {}
var pending_history: Array = []
var history: Array = []
var world: Node2D
var ui: Control
var overlay: Control
var buttons: Dictionary = {}
var elapsed = 0.0
var time_scale = 1.0
var paused = false
var message = ""
var modal = false
var transient = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	from_harbour = Bridge.origin == "mk01"; Bridge.origin = ""
	repository.path = save_path
	var read = repository.read_profile(Rules.validate)
	if read.status == "loaded": state = read.profile
	world = World.new(); add_child(world)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	get_window().title = "千灯集市 · MK02 育苗铺回礼样板"
	refresh()
	if read.status == "protected": show_protected()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(world) and state.stage in Rules.ANIMATIONS:
		paused = true
		if buttons.has("pause"): buttons.pause.text = "继续动画"

func _process(delta: float) -> void:
	if not is_instance_valid(world): return
	if not modal and not paused:
		if transient > 0:
			transient = maxf(0,transient-delta/maxf(0.01,time_scale))
			world.land_progress = 1-transient/LAND_TIME
			if transient == 0: refresh()
		if state.stage in Rules.ANIMATIONS:
			elapsed += delta/maxf(0.01,time_scale)
			world.progress = minf(1,elapsed/duration())
			if world.progress >= 1: commit(Rules.advance(state),history)
	update_camera()
	world.queue_redraw()

# A batched exchange plays longer, but never faster per group than a single one.
func duration() -> float:
	if state.stage == "exchanging": return 0.8 + 0.22 * (state.exchange[1] if state.exchange.size() == 2 else 1)
	return DURATIONS[state.stage]

func update_camera() -> void:
	var amount = 0.0 if state.stage in ["arrival","complete"] else 1.0
	if state.stage == "approach": amount = smoothstep(0,1,world.progress)
	if state.stage == "delivery": amount = 1-smoothstep(0.5,1,world.progress)
	world.scale = Vector2.ONE*lerpf(1,1.10,amount)
	world.position = Vector2(-64,-43)*amount

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
		elapsed = 0; world.progress = 0; paused = false; message = ""
	world.begin_land(previous)
	if world.land_place != "": world.land_progress = 0; transient = LAND_TIME
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

func snapshot(value: Dictionary) -> Dictionary:
	return {"a": value.a, "b": value.b, "rack": value.rack.duplicate(), "hook": value.hook.duplicate()}

func refresh() -> void:
	clear_children(ui)
	for child in world.get_children(): world.remove_child(child); child.queue_free()
	buttons = {}; world.state = state
	update_camera()
	sign_text("千灯集市  /  育苗铺的回礼",Rect2(24,20,394,48),24)
	if state.stage not in ["arrival","complete","delivery"]:
		sign_text("回礼：码头 5 根灯芯 · 扣扣留下 2 卷线 · 铜果要用完",Rect2(442,20,790,48),22)
	var line = ""
	match state.stage:
		"arrival": line = LINES[state.beat]
		"approach": line = "两条约定就钉在柜面上，扣扣把货物一件件搬过来。"
		"ready": line = "只能整组兑换：一次 2 颗铜果，或者一次 2 卷线。"
		"puzzle": line = "换出来的货先堆在台面：灯芯上交付架，给扣扣的线挂上修补台。"
		"exchanging": line = "扣扣抱着货物一件件搬……这一组已经算进去了。"
		"delivery": line = "码头工：5 根灯芯到位！扣扣：这两卷线……真的是留给我的？"
		"complete": line = "小岚：说好的回礼，一卷都不能少。育苗铺的第一封回信寄出去了。"
	if not message.is_empty(): line = message
	sign_text(line,Rect2(338,98,826,68),20)
	if state.stage in Rules.ANIMATIONS:
		add_button("pause","继续动画" if paused else "暂停动画",Rect2(922,654,140,46),toggle_pause)
		add_button("skip","跳过当前动画",Rect2(1080,654,176,46),skip_animation)
	elif state.stage == "puzzle":
		for slot in range(Rules.RACK_SLOTS):
			var rack_button = add_button("rack_%d"%slot,"",world.rack_rect(slot),choose_rack.bind(slot),false,world)
			UIStyle.hotspot(rack_button,"码头交付架第%d位：%s"%[slot+1,"空着，点一下放灯芯" if state.rack[slot] == 0 else "点一下放回台面"])
			rack_button.focus_mode = Control.FOCUS_NONE
			rack_button.disabled = modal or transient > 0
		for slot in range(Rules.HOOK_SLOTS):
			var hook_button = add_button("hook_%d"%slot,"",world.hook_rect(slot),choose_hook.bind(slot),false,world)
			UIStyle.hotspot(hook_button,"修补台挂钩%d：%s"%[slot+1,"空着，点一下挂线卷" if state.hook[slot] == 0 else "点一下放回台面"])
			hook_button.focus_mode = Control.FOCUS_NONE
			hook_button.disabled = modal or transient > 0
		for rule in range(2):
			var times = Rules.affordable(state,rule)
			var x = 352 + rule * 242
			var single = add_button("single_%d"%rule,"换 1 组",Rect2(x,560,100,44),do_exchange.bind(rule,1))
			single.disabled = times < 1 or transient > 0
			var batch = add_button("batch_%d"%rule,"全换完",Rect2(x+106,560,92,44),do_exchange.bind(rule,times))
			batch.disabled = times < 1 or transient > 0
			batch.tooltip_text = "一次换满 %d 组，随后一次性演出"%times
			var pool = Rules.fruits_left(state) if rule == 0 else Rules.spools_loose(state)
			UIStyle.text(ui,"%s %d 个 · 可换 %d 组"%["铜果" if rule == 0 else "线卷",pool,times],Rect2(x,608,198,32),16)
		add_button("undo","撤销 Z",Rect2(24,654,124,46),undo).disabled = history.is_empty() or transient > 0
		add_button("reset","重摆",Rect2(162,654,110,46),confirm_reset).disabled = transient > 0
		add_button("hint","请扣扣提醒",Rect2(286,654,168,46),hint).disabled = transient > 0
		add_button("deliver","验货交货",Rect2(1020,646,235,54),advance,true).disabled = transient > 0
		UIStyle.text(ui,"台面：%d 卷线 · %d 根灯芯"%[Rules.spools_loose(state),Rules.wicks_loose(state)],Rect2(470,656,300,42),20)
	else:
		if state.stage == "complete":
			# The receipt restates the exchange the player actually performed.
			UIStyle.panel(ui,Rect2(196,368,412,152))
			UIStyle.text(ui,"回执 · 育苗铺 → 码头\n约定一 ×%d：%d 颗铜果换成 %d 卷线\n约定二 ×%d：%d 卷线换成 %d 根灯芯\n交付架 %d 根 · 修补台 %d 卷 · 台面已空"%[
				state.a,Rules.GROUP*state.a,Rules.SPOOL_PER_GROUP*state.a,state.b,Rules.GROUP*state.b,Rules.WICK_PER_GROUP*state.b,
				state.rack.count(1),state.hook.count(1)],Rect2(212,380,382,132),18)
		var labels = {"arrival":"继续听他们说" if state.beat < 2 else "靠近育苗铺","ready":"开始兑换","complete":"重新体验"}
		if labels.has(state.stage): add_button("next",labels[state.stage],Rect2(982,646,274,54),confirm_restart if state.stage == "complete" else advance,true)
		if state.stage == "complete" and from_harbour: add_button("back_camp","办完回礼 · 回营地",Rect2(690,646,280,54),go_camp)
	if modal:
		for b in buttons.values(): b.disabled = true

func choose_rack(slot: int) -> void:
	place(Rules.put_rack(state,slot) if state.rack[slot] == 0 else Rules.take_rack(state,slot))

func choose_hook(slot: int) -> void:
	place(Rules.put_hook(state,slot) if state.hook[slot] == 0 else Rules.take_hook(state,slot))

func place(next: Dictionary) -> void:
	if state.stage != "puzzle" or modal or transient > 0 or next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func do_exchange(rule: int, times: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.exchange(state,rule,times)
	if next.is_empty():
		var pool = Rules.fruits_left(state) if rule == 0 else Rules.spools_loose(state)
		message = "凑不成整组：%s 只剩 %d 个，%d 个才能换下一样。"%["铜果" if rule == 0 else "线卷",pool,Rules.GROUP]
		refresh(); return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle":
		var missing = Rules.shortfalls(state)
		if not missing.is_empty():
			message = missing[0] + ("（还有 %d 处没有归位）"%(missing.size()-1) if missing.size() > 1 else "")
			refresh(); return
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
	var next = Rules.restore(state,next_history.pop_back())
	if next.is_empty(): return
	commit(next,next_history)

func hint() -> void:
	if modal or state.stage != "puzzle": return
	var next = state.duplicate(true); next.hint = mini(3,next.hint+1)
	if commit(next,history):
		var groups = Rules.group_limit(0)
		var spools = Rules.SPOOL_PER_GROUP * groups
		var hints = ["只能整组换：%d 颗铜果 → %d 卷线，%d 卷线 → %d 根灯芯；同一组不能拆开用。"%[Rules.GROUP,Rules.SPOOL_PER_GROUP,Rules.GROUP,Rules.WICK_PER_GROUP],
			"%d 颗铜果正好换满 %d 组，得到 %d 卷线——铜果要全用完，线卷才只在两个去处之间分。"%[Rules.FRUITS,groups,spools],
			"%d 卷线里留 %d 卷给扣扣，另外 %d 卷换 %d 组，正好是码头要的 %d 根灯芯。"%[spools,Rules.SPOOL_ORDER,spools-Rules.SPOOL_ORDER,Rules.WICK_ORDER,Rules.WICK_ORDER]]
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
	show_modal("把交付架和修补台上的货全部放回台面？\n已经换好的组不会退回，你仍留在育苗铺。")
	add_button("cancel","继续摆放",Rect2(390,410,206,50),close_modal,false,overlay)
	add_button("confirm","全部放回台面",Rect2(666,410,220,50),reset_goods,true,overlay).grab_focus()

func reset_goods() -> void:
	close_modal()
	var next = state.duplicate(true); next.rack = Rules.rack_empty(); next.hook = Rules.hook_empty()
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func confirm_restart() -> void:
	if modal: return
	show_modal("重新体验育苗铺这一幕？\n只重置本样板，不改变森林岛进度。")
	add_button("cancel","留在育苗铺",Rect2(390,410,206,50),close_modal,false,overlay)
	add_button("confirm","重新体验",Rect2(666,410,220,50),restart,true,overlay).grab_focus()

func restart() -> void:
	close_modal(); commit(Rules.fresh())

func go_camp() -> void:
	if modal or transient > 0: return
	HarborSample.entry = "return"
	get_tree().change_scene_to_file(FOREST_SCENE)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or modal: return
	if event.keycode == KEY_ESCAPE:
		if state.stage in Rules.ANIMATIONS: toggle_pause()
		else: refresh()
	elif state.stage == "puzzle" and transient <= 0:
		var key = event.keycode
		if key >= KEY_1 and key <= KEY_5: choose_rack(key-KEY_1)
		elif key == KEY_6 or key == KEY_7: choose_hook(key-KEY_6)
		elif key == KEY_Q: do_exchange(0,1)
		elif key == KEY_A: do_exchange(0,Rules.affordable(state,0))
		elif key == KEY_W: do_exchange(1,1)
		elif key == KEY_S: do_exchange(1,Rules.affordable(state,1))
		elif key == KEY_Z: undo()
		elif key == KEY_H: hint()
		elif key == KEY_SPACE: advance()
	get_viewport().set_input_as_handled()

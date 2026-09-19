extends Control
# 集市关卡的统一宿主：存档事务、撤销、三级提示、暂停/跳过/失焦、模态与镜头只实现一次。
# 关卡子类在 configure() 里注入 rules/world_script 并实现 line()/build() 等钩子。
# 规则模块必须提供：fresh() validate() advance() restore() ANIMATIONS；
# shortfalls() 与玩家动作函数按关卡需要出现。
# configure() 只能给 save_path 一类字段填默认值：实窗测试会在加入场景树前先写入自己的
# /tmp 路径，子类若无条件覆盖就会读写玩家真实存档。
const Repository = preload("res://scripts/persistence/save_repository.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const FOREST_SCENE = "res://game/forest_release.tscn"
const LAND_TIME = 0.28
var rules: Script
var world_script: Script
var scene_id := ""
var level_id := ""
var title := ""
var save_path := ""
var durations := {}
var zoom_stages := ["puzzle"]
var repository = Repository.new()
var state: Dictionary = {}
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
var origin = ""

func _ready() -> void:
	configure()
	state = rules.fresh()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	repository.path = save_path
	var read = repository.read_profile(rules.validate)
	if read.status == "loaded": state = read.profile
	world = world_script.new(); world.scene_id = scene_id; add_child(world)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	get_window().title = "千灯集市 · " + title
	refresh()
	if read.status == "protected": show_protected()

# ---- overridable hooks ----
func configure() -> void: pass
func line() -> String: return ""
func goal_line() -> String: return ""
func status_line() -> String: return ""
func submit_label() -> String: return "提交"
func build() -> void: pass
func extra() -> void: pass
func exit_buttons() -> void: pass
func snapshot(_value: Dictionary) -> Dictionary: return {}
func cleared_state() -> Dictionary: return {}
func hint_texts() -> Array: return []
func handle_key(_key: int) -> bool: return false
func stage_labels() -> Dictionary: return {}
func reset_prompt() -> Array: return ["把摆好的货全部放回台面？", "继续摆放", "全部放回台面"]
func restart_prompt() -> Array: return ["重新体验这一幕？", "留在现场", "重新体验"]

func duration() -> float:
	return durations[state.stage] if durations.has(state.stage) else 1.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(world) and state.stage in rules.ANIMATIONS:
		paused = true
		if buttons.has("pause"): buttons.pause.text = "继续动画"

func _process(delta: float) -> void:
	if not is_instance_valid(world): return
	if not modal and not paused:
		if transient > 0:
			transient = maxf(0,transient-delta/maxf(0.01,time_scale))
			world.land_progress = 1-transient/LAND_TIME
			if transient == 0: refresh()
		if state.stage in rules.ANIMATIONS:
			elapsed += delta/maxf(0.01,time_scale)
			world.progress = minf(1,elapsed/duration())
			if world.progress >= 1: commit(rules.advance(state),history)
	update_camera()
	world.queue_redraw()

# Walk-in zooms the counter, the hand-out pulls back to the whole street.
func update_camera() -> void:
	var amount = 1.0 if state.stage in zoom_stages else 0.0
	if state.stage == "approach": amount = smoothstep(0,1,world.progress)
	if state.stage == "delivery": amount = 1-smoothstep(0.5,1,world.progress)
	world.scale = Vector2.ONE*lerpf(1,1.10,amount)
	world.position = Vector2(-64,-43)*amount

# ---- save transaction ----
func commit(candidate: Dictionary, next_history: Array = []) -> bool:
	if candidate.is_empty() or modal: return false
	if not repository.write_profile(candidate,rules.validate):
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
	if not repository.write_profile(pending,rules.validate): show_save_error(); return
	var candidate = pending; var next_history = pending_history
	pending = {}; pending_history = []; close_modal(); apply_committed(candidate,next_history)

# ---- shared controls ----
func clear_children(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func add_button(id: String, text: String, rect: Rect2, callback: Callable, primary: bool = false, parent: Node = null) -> Button:
	var button = UIStyle.button(ui if parent == null else parent,text,rect,callback,primary)
	button.name = id; buttons[id] = button
	return button

func add_hotspot(id: String, rect: Rect2, callback: Callable, label: String) -> Button:
	var button = add_button(id,"",rect,callback,false,world)
	UIStyle.hotspot(button,label)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = modal or transient > 0
	return button

func sign_text(text: String, rect: Rect2, size_px: int = 20) -> void:
	UIStyle.sign(ui,rect)
	UIStyle.text(ui,text,Rect2(rect.position+Vector2(14,8),rect.size-Vector2(28,12)),size_px)

func refresh() -> void:
	clear_children(ui)
	for child in world.get_children(): world.remove_child(child); child.queue_free()
	buttons = {}; world.state = state
	update_camera()
	sign_text("千灯集市  /  "+title,Rect2(24,20,394,48),24)
	var goal = goal_line()
	if not goal.is_empty() and state.stage not in ["arrival","complete","delivery"]:
		sign_text(goal,Rect2(442,20,790,48),22)
	var spoken = line()
	if not message.is_empty(): spoken = message
	sign_text(spoken,Rect2(338,98,826,68),20)
	if state.stage in rules.ANIMATIONS:
		add_button("pause","继续动画" if paused else "暂停动画",Rect2(922,654,140,46),toggle_pause)
		add_button("skip","跳过当前动画",Rect2(1080,654,176,46),skip_animation)
	elif state.stage == "puzzle":
		build()
		add_button("undo","撤销 Z",Rect2(24,654,124,46),undo).disabled = history.is_empty() or transient > 0
		add_button("reset","重摆",Rect2(162,654,110,46),confirm_reset).disabled = transient > 0
		add_button("hint","请扣扣提醒",Rect2(286,654,168,46),hint).disabled = transient > 0
		add_button("deliver",submit_label(),Rect2(1020,646,235,54),advance,true).disabled = transient > 0
		var status = status_line()
		if not status.is_empty(): UIStyle.text(ui,status,Rect2(470,656,300,42),20)
	else:
		var labels = stage_labels()
		if labels.has(state.stage):
			add_button("next",labels[state.stage],Rect2(982,646,274,54),confirm_restart if state.stage == "complete" else advance,true)
		if state.stage == "complete": exit_buttons()
	if modal:
		for b in buttons.values(): b.disabled = true

# ---- shared actions ----
func place(next: Dictionary) -> void:
	if state.stage != "puzzle" or modal or transient > 0 or next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func advance() -> void:
	if modal or transient > 0 or state.stage in rules.ANIMATIONS: return
	if state.stage == "puzzle" and rules.has_method("shortfalls"):
		var missing = rules.shortfalls(state)
		if not missing.is_empty():
			message = missing[0] + ("（还有 %d 处没有归位）"%(missing.size()-1) if missing.size() > 1 else "")
			refresh(); return
	commit(rules.advance(state),history)

func toggle_pause() -> void:
	if modal: return
	paused = not paused
	refresh()

func skip_animation() -> void:
	if modal or state.stage not in rules.ANIMATIONS: return
	commit(rules.advance(state),history)

func undo() -> void:
	if modal or transient > 0 or state.stage != "puzzle" or history.is_empty(): return
	var next_history = history.duplicate(true)
	var next = rules.restore(state,next_history.pop_back())
	if next.is_empty(): return
	commit(next,next_history)

func hint() -> void:
	if modal or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var next = state.duplicate(true); next.hint = mini(texts.size(),next.hint+1)
	if commit(next,history):
		message = texts[next.hint-1]; refresh()

func reset_layout() -> void:
	var next = cleared_state()
	if next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func confirm_reset() -> void:
	if modal or transient > 0: return
	var prompt = reset_prompt()
	show_modal(prompt[0])
	add_button("cancel",prompt[1],Rect2(390,410,206,50),close_modal,false,overlay)
	add_button("confirm",prompt[2],Rect2(666,410,220,50),do_reset,true,overlay).grab_focus()

func do_reset() -> void:
	close_modal(); reset_layout()

func confirm_restart() -> void:
	if modal: return
	var prompt = restart_prompt()
	show_modal(prompt[0] + "\n只重置本关，不改变其他关卡与森林岛进度。")
	add_button("cancel",prompt[1],Rect2(390,410,206,50),close_modal,false,overlay)
	add_button("confirm",prompt[2],Rect2(666,410,220,50),restart,true,overlay).grab_focus()

func restart() -> void:
	close_modal(); commit(rules.fresh())

func go_forest() -> void:
	get_tree().change_scene_to_file(FOREST_SCENE)

# ---- modals ----
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
	show_modal("关卡记录无法读取，原文件已保留。\n可关闭窗口保留现场，或保留旧文件后重新开始。")
	add_button("protect_confirm","保留原档并重新开始",Rect2(504,410,382,50),recover_protected,true,overlay).grab_focus()

func recover_protected() -> void:
	if repository.preserve_protected_file().is_empty(): show_protected(); return
	close_modal(); commit(rules.fresh())

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or modal: return
	if event.keycode == KEY_ESCAPE:
		if state.stage in rules.ANIMATIONS: toggle_pause()
		else: refresh()
	elif state.stage == "puzzle" and transient <= 0:
		var key = event.keycode
		if key == KEY_Z: undo()
		elif key == KEY_H: hint()
		elif key == KEY_SPACE: advance()
		else: handle_key(key)
	get_viewport().set_input_as_handled()

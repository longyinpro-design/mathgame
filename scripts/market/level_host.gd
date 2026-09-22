extends Control
# 集市关卡的统一宿主：存档事务、撤销、三级提示、暂停/跳过/失焦、模态与镜头只实现一次。
# 关卡子类在 configure() 里注入 rules/world_script 并实现 line()/build() 等钩子。
# 规则模块必须提供：fresh() validate() advance() restore() ANIMATIONS；
# shortfalls() 与玩家动作函数按关卡需要出现。
# configure() 只能给 save_path 一类字段填默认值：实窗测试会在加入场景树前先写入自己的
# /tmp 路径，子类若无条件覆盖就会读写玩家真实存档。
const Repository = preload("res://scripts/persistence/save_repository.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const FOREST_SCENE = "res://game/forest_release.tscn"
const ISLAND_SCENE = "res://game/market_island.tscn"
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
var origin = ""
var focused = true:
	set(value):
		focused = value
		sync_presentation()
var window_theme: Theme

func _ready() -> void:
	# 进来时是谁送的：hub = 千灯航图，mk01 = 码头，空 = 直接启动本关。读一次即清空。
	origin = Bridge.origin; Bridge.origin = ""
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
	# 热点是隐形按钮，它的中文说明只靠 tooltip。tooltip 的 Label 挂在 viewport 自己的画布上，
	# 主题继承只到 Window 这一级——挂在宿主 Control 上传不到它，于是全章唯一不用关卡字体的
	# 文字就是它（默认细灰字、压在石板上）。这里换成木纹牌主题，并在离场时还原，不漏给森林岛。
	window_theme = get_window().theme
	get_window().theme = UIStyle.tooltip_theme()
	refresh()
	if read.status == "protected": show_protected()

func _exit_tree() -> void:
	if is_instance_valid(get_window()): get_window().theme = window_theme

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

func sync_presentation() -> void:
	if is_instance_valid(world): world.presentation_paused = modal or paused or not focused

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: focused = true
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(world) and state.stage in rules.ANIMATIONS:
		paused = true
		if buttons.has("pause"): buttons.pause.text = "继续动画"

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_visible_in_tree(): return
	if modal or paused or not focused: return
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
	# 走位收尾已经把镜头推到 1.10，紧接的那一格（ready）说的是「先点什么、再点什么」，
	# 画面必须还贴着同一张台面。各关写 zoom_stages 时很容易只写 puzzle，于是 ready 先弹回
	# 1.0、点「开始」再弹回 1.10，两下硬跳（MK09／MK12 实窗量到的）。
	if state.stage == "ready" and "puzzle" in zoom_stages: amount = 1.0
	if state.stage == "approach": amount = smoothstep(0,1,world.progress)
	# 交货这一幕要演的是整条街：原先留到后半程才拉回，前半程一直贴着柜台，
	# 挂在庭院上方的灯串、驶出的车队正好被台词板切掉顶边（MK12 点灯那一幕实窗拍到的）。
	# 改成开场就往外收，四成五的时长内回到整院，之后全程保持。
	if state.stage == "delivery": amount = 1-smoothstep(0,0.45,world.progress)
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
		elapsed = 0; world.progress = 0; paused = false
	# 上一次按下的那句话只描述当时的现场：换货、撤销、重摆都会把状态改掉，
	# 留着它就会把「这一行本来就空着」这类旧话挂在已经改过的板子上。
	# hint() 在 commit 成功之后才写下新一句，所以不受这里影响。
	message = ""
	# begin_land compares the goods already on the table with the ones that just arrived,
	# so the world must be handed the committed state before it is asked who landed.
	world.state = state
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
	# 鼠标点过的按钮会把焦点留在自己身上，而 Godot 的 Button 用 ui_accept 响应 Space/Enter：
	# 玩家点过「扣扣提醒」或「撤销」之后再按 Space，等来的是那两块按钮被按第二次，而不是本关的提交。
	# 只在鼠标按下时把焦点放回窗口，Tab/Enter 的键盘走位照旧。
	button.gui_input.connect(_drop_focus_on_click)
	return button

func _drop_focus_on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked = get_viewport().gui_get_hovered_control()
		if clicked is Button: clicked.release_focus()

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
	sync_presentation()
	world.queue_redraw()
	clear_children(ui)
	for child in world.get_children(): world.remove_child(child); child.queue_free()
	buttons = {}; world.state = state
	update_camera()
	# 关卡名最长 9 个汉字：24 号被 skin 抬到 28 号，394 宽只剩 366 内框，
	# 「千灯集市 / 四张被雨打湿的货签」量到 372 就会折成第二行压过板底。410 留到 382。
	sign_text("千灯集市  /  "+title,Rect2(24,20,410,48),24)
	var goal = goal_line()
	if not goal.is_empty() and state.stage not in ["arrival","complete","delivery"]:
		sign_text(goal,Rect2(442,20,790,48),22)
	var spoken = line()
	if not message.is_empty(): spoken = message
	# 台词条内可以有一处显式换行：UIStyle 把 20 号抬到 22 号，两行 CJK 要 61px，
	# 板子内框只给 56px 时第二行会压过下边框。位置不能动（mk12 的审计按 (338,98) 认这块板）。
	sign_text(spoken,Rect2(338,98,826,86),20)
	if state.stage in rules.ANIMATIONS:
		add_button("pause","继续动画" if paused else "暂停动画",Rect2(922,654,140,46),toggle_pause)
		add_button("skip","跳过当前动画",Rect2(1080,654,176,46),skip_animation)
		# 演出那几格底栏原本是空的：好几关都写了「已落定 3 / 五件」这一类读数，
		# 宿主不在这里画，玩家就看不见一批货正在落下（MK02／MK09 都写了、都没显示）。
		var moving = status_line()
		if not moving.is_empty(): UIStyle.text(ui,moving,Rect2(470,656,300,42),20)
	elif state.stage == "puzzle":
		build()
		add_button("undo","撤销 Z",Rect2(24,654,124,46),undo).disabled = history.is_empty() or transient > 0
		add_button("reset","重摆 X",Rect2(162,654,110,46),confirm_reset).disabled = transient > 0
		add_button("hint","请扣扣提醒",Rect2(286,654,168,46),hint).disabled = transient > 0
		add_button("deliver",submit_label(),Rect2(1020,646,235,54),advance,true).disabled = transient > 0
		var status = status_line()
		if not status.is_empty(): UIStyle.text(ui,status,Rect2(470,656,300,42),20)
		# 摆放中途也能回航图：每一步都已经落盘，离开不会丢现场。
		if origin == "hub": add_button("leave_hub","千灯航图",Rect2(786,654,124,46),go_hub)
	else:
		var labels = stage_labels()
		if labels.has(state.stage):
			add_button("next",labels[state.stage],Rect2(982,646,274,54),confirm_restart if state.stage == "complete" else advance,true)
		if state.stage == "complete":
			exit_buttons()
			# 从航图进来的关卡，办完事就把玩家送回航图，灯火由枢纽读档补记。
			if origin == "hub": add_button("back_hub","返回千灯航图",Rect2(690,646,280,54),go_hub)
	# 关卡自己的回执、单据与阶段说明画在最后，才能压在按钮之上。
	extra()
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

func go_hub() -> void:
	get_tree().change_scene_to_file(ISLAND_SCENE)

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
	elif transient <= 0:
		var key = event.keycode
		if state.stage == "puzzle":
			if key == KEY_Z: undo()
			elif key == KEY_H: hint()
			# 重摆留给 X：R 已经被六关自己拿去当收货位快捷键（MK09 的丁摊就是 R），
			# 而这一枚按钮在底栏上写着「重摆 X」，玩家看得见就能按得到。
			elif key == KEY_X: confirm_reset()
			elif key == KEY_SPACE: advance()
			else: handle_key(key)
		elif key == KEY_SPACE and buttons.has("next"):
			# 开场那几句、走位、以及「开始装车」那一格原本只有鼠标能走：只用键盘的玩家
			# 会被钉在台词板前面。空格在这里按的就是 next 那一个动作；提交仍然只在 puzzle 里
			# 由空格触发，而那一格有 shortfalls 兜底，按错了只会念出还差哪一处。
			buttons["next"].pressed.emit()
	get_viewport().set_input_as_handled()

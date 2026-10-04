extends Control
# Shared input/presentation adapter. The session alone owns persistence and rewards.
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Campaign = preload("res://scripts/archipelago/session.gd")
const Journey = preload("res://scripts/archipelago/bridge.gd")
const Islands = preload("res://scripts/archipelago/catalog.gd")
@export var level_id = ""
var definition: Dictionary = {}
var rules: RefCounted
var world_script: Script
var world: Node2D
var ui: Control
var overlay: Control
var buttons: Dictionary = {}
var board: Dictionary = {}
var stage = "intro"
var hint_tier = 0
var history: Array = []
var modal = false
var paused = false
var focused = true
var navigating = false
var message = ""
var session: RefCounted
var save_path = ""
var beat = 0
var rendered_revision = -1
var render_epoch = 0
var annotation_mode = false
var annotation_layer: Node2D
var confirmation: Callable
var window_theme: Theme

func configure() -> void: pass
func build_board() -> void: pass
func sync_world() -> void: pass
func handle_key(_key: int) -> bool: return false

func _ready() -> void:
	configure()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = world_script.new(); world.definition = definition; world.state = rules.fresh(); add_child(world)
	annotation_layer = preload("res://scripts/archipelago/annotations.gd").new(); add_child(annotation_layer)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	window_theme = get_window().theme; get_window().theme = UIStyle.tooltip_theme()
	get_window().title = Islands.NAMES.get(definition.get("island",""),"数字群岛")+" · "+definition.get("title",level_id)
	if session == null:
		if not save_path.is_empty():
			session = Campaign.new(); session.allow_locked = true; session.open(save_path)
		else: session = Journey.ensure_session()
	if session.profile.is_empty(): show_protected(); return
	if not session.pending.is_empty(): show_save_error(); return
	if session.profile.active != level_id or not session.profile.runs.has(level_id):
		if not session.start(level_id):
			if not session.pending.is_empty(): show_save_error()
			else: show_modal(session.feedback); modal_button("back_locked","返回群岛航图",go_hub)
			return
	refresh()

func _exit_tree() -> void:
	if is_instance_valid(get_window()): get_window().theme = window_theme

func current() -> Dictionary: return session.profile.runs.get(level_id,{}) if session != null else {}
func blocked() -> bool: return modal or paused or navigating or session == null or not session.pending.is_empty()

func refresh() -> void:
	if not is_instance_valid(ui): return
	render_epoch += 1
	var record = current()
	rendered_revision = session.profile.get("revision",-1) if session != null else -1
	if not record.is_empty():
		board = record.board.duplicate(true); stage = record.stage; beat = record.beat; hint_tier = record.highest_hint
		history = session.history.get(level_id,[])
	elif board.is_empty(): board = rules.fresh()
	for child in ui.get_children(): ui.remove_child(child); child.queue_free()
	buttons = {}
	world.definition = definition; world.state = board
	world.presentation_paused = modal or paused or not focused
	sync_world(); world.queue_redraw()
	UIStyle.sign(ui,Rect2(24,18,1232,60))
	draw_label("%s · %s"%[level_id,definition.get("title","")],Rect2(42,25,820,46),26)
	draw_label("%s · 提示 %d/4"%[Islands.NAMES.get(definition.get("island",""),""),hint_tier],Rect2(930,29,308,36),19)
	UIStyle.sign(ui,Rect2(24,90,1232,106))
	var text = definition.get("instructions","")
	if stage == "intro": text = definition.intro[mini(beat,definition.intro.size()-1)] + "\n" + definition.goal
	elif stage == "outcome": text = definition.outro[mini(beat,definition.outro.size()-1)]
	elif stage == "complete": text = "这一处已经恢复。可以继续故事，也能回看或重新体验；首次奖励不会重复领取。"
	draw_label(text,Rect2(44,100,1192,82),21)
	if stage == "puzzle" and not paused: build_board()
	if not message.is_empty():
		UIStyle.sign(ui,Rect2(24,608,1232,36)); draw_label(message,Rect2(38,611,1204,29),17)
	add_button("back_hub","返回航图",Rect2(24,652,144,48),go_hub)
	add_button("pause","继续" if paused else "暂停",Rect2(598,652,108,48),toggle_pause)
	if stage == "puzzle":
		add_button("undo","撤销 Z",Rect2(180,652,112,48),undo).disabled = history.is_empty()
		add_button("reset","重摆 X",Rect2(304,652,112,48),confirm_reset)
		add_button("hint","伙伴提示 H",Rect2(428,652,158,48),request_hint)
		add_button("marks","收起观察签" if annotation_mode else "观察签",Rect2(720,652,168,48),toggle_annotations)
		add_button("submit","验收机关 Space",Rect2(1008,650,248,52),submit,true).disabled = paused
	elif stage == "complete":
		add_button("replay","重新体验",Rect2(724,652,208,48),confirm_restart)
		add_button("next","继续故事",Rect2(948,650,308,52),next_story,true)
	else:
		add_button("next","开始动手" if stage == "intro" and beat == definition.intro.size()-1 else "继续听他们说",Rect2(948,650,308,52),advance,true)
	if modal or navigating:
		for button in buttons.values(): button.disabled = true

func wrapped(value: String, width: float, size_px: int) -> String:
	var lines: Array = []
	for paragraph in value.split("\n"):
		var line = ""
		for character in paragraph:
			if not line.is_empty() and UIStyle.face().get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x > width:
				if character in "，。！？；：、）】》」』,.;:!?":
					line += character; continue
				lines.append(line); line = ""
			line += character
		lines.append(line)
	return "\n".join(lines)

func draw_label(value: String, rect: Rect2, size_px: int = 20) -> Label:
	var fitted = wrapped(value,rect.size.x,size_px)
	while size_px > 18 and fitted.split("\n").size()*UIStyle.face().get_height(size_px) > rect.size.y:
		size_px -= 1; fitted = wrapped(value,rect.size.x,size_px)
	var label = UIStyle.text(ui,fitted,rect,size_px)
	label.add_theme_font_size_override("font_size",size_px)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size = rect.size
	return label

func add_button(id: String, text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var epoch = render_epoch
	var guarded = func():
		if epoch == render_epoch and not modal and not navigating: callback.call()
	var button = UIStyle.button(ui,text,rect,guarded,primary)
	button.name = id; buttons[id] = button
	button.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: button.release_focus())
	return button

func add_hotspot(id: String, rect: Rect2, callback: Callable, tooltip: String) -> Button:
	var button = add_button(id,"",rect,callback)
	UIStyle.hotspot(button,tooltip); button.focus_mode = Control.FOCUS_ALL
	return button

func apply_result(saved: bool) -> void:
	message = session.feedback
	if not saved and not session.pending.is_empty(): show_save_error(); return
	refresh()

func act(action: Dictionary) -> void:
	if blocked() or stage != "puzzle": return
	apply_result(session.command({"kind":"board","action":action},rendered_revision))
func submit() -> void:
	if blocked() or stage != "puzzle": return
	apply_result(session.command({"kind":"submit"},rendered_revision))
func undo() -> void:
	if blocked(): return
	apply_result(session.command({"kind":"undo"},rendered_revision))
func request_hint() -> void:
	if blocked(): return
	apply_result(session.command({"kind":"hint"},rendered_revision))
func advance() -> void:
	if blocked(): return
	apply_result(session.command({"kind":"advance"},rendered_revision))

func toggle_pause() -> void:
	if modal: return
	paused = not paused; refresh()
func confirm_reset() -> void:
	if blocked(): return
	confirmation = func(): apply_result(session.reset_board())
	show_confirmation("重新摆放本关机关？求助记录与尝试次数仍保留。")
func confirm_restart() -> void:
	if blocked(): return
	confirmation = func(): apply_result(session.restart())
	show_confirmation("重新体验这一关？已获得的完成记录和首次奖励仍保留。")

func show_confirmation(text: String) -> void:
	show_modal(text)
	modal_button("cancel","留在现场",close_modal,Rect2(375,425,230,50))
	modal_button("confirm","确认",func(): var action = confirmation; close_modal(); action.call(),Rect2(675,425,230,50))

func clear_overlay() -> void:
	for child in overlay.get_children(): overlay.remove_child(child); child.queue_free()
func show_modal(text: String) -> void:
	modal = true; refresh(); clear_overlay()
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.03,0.04,0.06,0.85); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(280,205,720,300))
	var label = UIStyle.text(overlay,text,Rect2(320,240,640,150),22)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
func modal_button(id: String, text: String, callback: Callable, rect: Rect2 = Rect2(675,425,230,50)) -> Button:
	var epoch = render_epoch
	var guarded = func():
		if epoch == render_epoch and modal: callback.call()
	var button = UIStyle.button(overlay,text,rect,guarded,true); button.name = id; buttons[id] = button; button.grab_focus(); return button
func close_modal() -> void:
	modal = false; clear_overlay(); refresh()
func show_save_error() -> void:
	show_modal(session.feedback+"\n上一次成功保存的状态仍保留；请重试同一个操作。")
	modal_button("retry","重试保存",retry_save)
func retry_save() -> void:
	if session.retry(): message = session.feedback; close_modal()
	else: show_save_error()
func show_protected() -> void:
	show_modal("群岛记录无法读取，原文件已保留。可以关闭游戏保留现场，或保留旧文件后另开旅程。")
	modal_button("protect_confirm","保留旧档另开旅程",recover_protected,Rect2(565,425,360,50))
func recover_protected() -> void:
	if session.repository.preserve_protected_file().is_empty(): show_protected(); return
	session.profile = Campaign.fresh()
	if not session.commit(session.profile): show_save_error(); return
	if session.start(level_id): close_modal()
	else: show_modal("新旅程已保存，请从森林开始。" ); modal_button("back_new","群岛航图",go_hub)

func go_hub() -> void:
	if session == null or not session.pending.is_empty() or navigating: return
	Journey.session = session
	navigating = true
	if not Journey.hub(get_tree(),definition.get("island","")):
		navigating = false; message = session.feedback; refresh()

func next_story() -> void:
	if blocked(): return
	Journey.session = session
	var next = session.story_next()
	if next.is_empty(): go_hub(); return
	navigating = true
	if not Journey.launch(get_tree(),next): navigating = false; message = session.feedback; refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: focused = false; paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: focused = true
	if buttons.has("pause") and is_instance_valid(buttons.pause): buttons.pause.text = "继续" if paused else "暂停"
	if is_instance_valid(world): world.presentation_paused = paused or modal or not focused

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or modal: return
	var key = event.keycode
	if key == KEY_ESCAPE: toggle_pause()
	elif not paused:
		if key == KEY_Z: undo()
		elif key == KEY_H: request_hint()
		elif key == KEY_X: confirm_reset()
		elif key == KEY_SPACE:
			if stage == "puzzle": submit()
			elif stage in ["intro","outcome"]: advance()
		else:
			if not handle_key(key): return
	else: return
	get_viewport().set_input_as_handled()


func toggle_annotations() -> void:
	if blocked(): return
	if not annotation_mode and not session.record_support(): show_save_error(); return
	annotation_mode = not annotation_mode
	if not annotation_mode: annotation_layer.points=[];annotation_layer.queue_redraw()
	message = "点击现场放观察签；只做自己的标记，不会替你判答案。再点「收起观察签」退出。" if annotation_mode else ""
	refresh()

func _input(event: InputEvent) -> void:
	if not annotation_mode or blocked() or stage != "puzzle": return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at: Vector2 = make_input_local(event).position
		if Rect2(40,210,1200,390).has_point(at):
			if annotation_layer.points.size() < 24: annotation_layer.points.append(at)
			annotation_layer.queue_redraw();get_viewport().set_input_as_handled()

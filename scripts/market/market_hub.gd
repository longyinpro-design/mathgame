extends Control
# 千灯集市航图：18 张关卡卡片、逐关点亮的灯火，以及进入关卡的唯一入口。
# 这里只写章节进度；每一关的现场状态仍由各自的存档负责。
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Progress = preload("res://scripts/market/chapter_progress.gd")
const World = preload("res://scripts/market/hub_world.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const HarborSample = preload("res://scripts/market/mk01_scene.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const FOREST_SCENE = "res://game/forest_release.tscn"
const COLUMNS = 6

var save_note = ""
var progress = Progress.new()
var world: Node2D
var ui: Control
var overlay: Control
var buttons: Dictionary = {}
var modal = false:
	set(value):
		modal = value
		sync_presentation()
var focused = true:
	set(value):
		focused = value
		sync_presentation()
var window_theme: Theme

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_note = progress.load_record()
	progress.settle()
	world = World.new(); add_child(world)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	get_window().title = "千灯集市 · 航图与灯火"
	# 十八张卡片的完整目标只写在 tooltip 里，而 tooltip 的主题继承到 Window 为止：
	# 与 level_host 同一条修法，离场还原，不漏给森林岛。
	window_theme = get_window().theme
	get_window().theme = UIStyle.tooltip_theme()
	refresh()
	if save_note == "protected": show_protected()

func _exit_tree() -> void:
	if is_instance_valid(get_window()): get_window().theme = window_theme

func sync_presentation() -> void:
	if is_instance_valid(world): world.presentation_paused = modal or not focused

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: focused = true

# The next lamp breathes, so the world layer redraws every frame instead of on commit.
func _process(_delta: float) -> void:
	if is_instance_valid(world) and not modal and focused and is_visible_in_tree(): world.queue_redraw()

func next_id() -> String:
	var pending = Catalog.main_pending(progress.completed())
	return pending[0] if not pending.is_empty() else ""

func summary() -> String:
	var done = progress.completed()
	var next = next_id()
	if next.is_empty(): return "灯火 %d / 18 · 主线 14 / 14 全部点亮，夜市已经恢复" % done.size()
	return "灯火 %d / 18 · 主线 %d / 14 · 下一站 %s" % [done.size(), Catalog.MAIN.size() - pending_size(), next]

func pending_size() -> int: return Catalog.main_pending(progress.completed()).size()

# 卡片只说三件事：这是第几幕、叫什么、现在能不能进去。目标全文放在提示与下一站栏。
func card_status(id: String) -> String:
	if progress.is_done(id): return "已点亮 · 可重玩"
	if not progress.is_open(id): return "需先完成 " + Catalog.opens_after(id)
	if not Catalog.built(id): return "尚未制作"
	return "待出发"

# 点亮的关卡永远进得去：哪怕它的前置被清空，玩家也已经办完了那一幕。
func enterable(id: String) -> bool:
	return Catalog.built(id) and (progress.is_open(id) or progress.is_done(id))

func card_tone(id: String) -> String:
	if not enterable(id): return "locked"
	return "done" if progress.is_done(id) else "open"

func station_head(id: String) -> String:
	return "%s · %s" % [id, "支线" if Catalog.is_side(id) else "第%s幕" % ["零","一","二","三","四","五","六"][Catalog.act(id)]]

func refresh() -> void:
	sync_presentation()
	world.queue_redraw()
	for child in ui.get_children(): ui.remove_child(child); child.queue_free()
	buttons = {}
	var ids = Catalog.order()
	world.completed = progress.completed()
	world.next_id = next_id()
	sign_text("千灯集市  /  千灯航图", Rect2(24,20,394,48), 24)
	sign_text(summary(), Rect2(442,20,790,48), 22)
	for index in range(ids.size()):
		var id = ids[index]
		var rect = World.card_rect(index)
		var panel = UIStyle.sign(ui, rect)
		panel.add_theme_stylebox_override("panel", card_style(id))
		# Labels centre their block vertically by default, so a two-line title would
		# spill over the act line above and the status line below.
		# 卡片文字都落在 18px 下限上：三行同字号，层级靠颜色分，标题才站得住一行。
		card_text(station_head(id), Rect2(rect.position + Vector2(12, 8), Vector2(rect.size.x - 20, 24)), 16,
			UIStyle.GOLD if card_tone(id) != "locked" else Color("8d8577"))
		card_text(wrap_title(Catalog.card_title(id)), Rect2(rect.position + Vector2(12, 34), Vector2(rect.size.x - 20, 46)), 16)
		card_text(card_status(id), Rect2(rect.position + Vector2(12, rect.size.y - 32), Vector2(rect.size.x - 20, 26)),
			16, Color("ffe297") if progress.is_done(id) else Color("c9bda3"))
		var button = UIStyle.button(ui, "", rect, choose.bind(id))
		UIStyle.hotspot(button, card_hint(id))
		button.name = "card_" + id
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = modal or card_tone(id) == "locked"
		buttons["card_" + id] = button
	var next = next_id()
	if not next.is_empty():
		# The board behind the line keeps the goal readable over the street banner.
		UIStyle.sign(ui, Rect2(228,648,776,50))
		UIStyle.text(ui, "%s：%s" % [station_head(next), Catalog.goal(next)], Rect2(244,656,744,34), 16)
	add_button("camp","回森林营地",Rect2(24,646,190,54),go_camp)
	if not next.is_empty():
		add_button("next_station","下一站 · "+next,Rect2(1020,646,235,54),enter_next,true)
	if modal:
		for b in buttons.values(): b.disabled = true

func card_hint(id: String) -> String:
	return "%s %s（%s）\n%s\n%s"%[id, Catalog.title(id), Catalog.act_name(id), Catalog.goal(id), card_status(id)]

func card_text(value: String, rect: Rect2, size_px: int, color: Color = UIStyle.INK) -> void:
	var label = UIStyle.text(ui, value, rect, size_px, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

# 汉字之间没有空格，自动换行会把整句当成一个词横着画出去，所以卡片标题自己断行。
const CARD_TITLE_CHARS = 9
static func wrap_title(value: String) -> String:
	var total = value.length()
	if total <= CARD_TITLE_CHARS: return value
	var lines = ceili(total / float(CARD_TITLE_CHARS))
	var width = ceili(total / float(lines))
	var result = ""
	for line in range(lines):
		if line > 0: result += "\n"
		result += value.substr(line * width, width)
	return result

func card_style(id: String) -> StyleBoxFlat:
	var style = UIStyle.sign_style()
	match card_tone(id):
		"done":
			style.bg_color = Color(0.20,0.15,0.06,0.95); style.border_color = Color("d7bd83")
		"open":
			style.bg_color = Color(0.16,0.13,0.09,0.95)
		_:
			style.bg_color = Color(0.09,0.10,0.11,0.93); style.border_color = Color(0.40,0.36,0.30,0.9)
	return style

func sign_text(text: String, rect: Rect2, size_px: int = 20) -> void:
	UIStyle.sign(ui, rect)
	UIStyle.text(ui, text, Rect2(rect.position + Vector2(14,8), rect.size - Vector2(28,12)), size_px)

func add_button(id: String, text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var button = UIStyle.button(ui, text, rect, callback, primary)
	button.name = id; buttons[id] = button
	return button

func enter_next() -> void:
	var next = next_id()
	if enterable(next): launch(next)

func choose(id: String) -> void:
	if modal or not enterable(id): return
	launch(id)

# 进入关卡时留下出处，关卡办完事才知道该把玩家送回航图还是送回码头。
func launch(id: String) -> void:
	Bridge.origin = "hub"
	get_tree().change_scene_to_file(Catalog.scene(id))

func go_camp() -> void:
	if modal: return
	HarborSample.entry = "return"
	get_tree().change_scene_to_file(FOREST_SCENE)

func show_modal(text: String) -> void:
	modal = true; refresh(); clear_overlay()
	var shade = ColorRect.new(); shade.color = Color(0.035,0.05,0.055,0.8); shade.size = Vector2(1280,720); overlay.add_child(shade)
	UIStyle.panel(overlay, Rect2(322,225,636,264))
	UIStyle.text(overlay, text, Rect2(360,257,560,126), 22)

func clear_overlay() -> void:
	for child in overlay.get_children(): overlay.remove_child(child); child.queue_free()

func close_modal() -> void:
	modal = false; clear_overlay(); refresh()

func show_protected() -> void:
	show_modal("集市进度记录无法读取，原文件已保留。\n关卡现场不受影响，可先关闭窗口查看旧记录。")
	add_button("protect_confirm","保留原档并另存新进度",Rect2(504,410,382,50),recover_protected,true).grab_focus()

func recover_protected() -> void:
	if progress.repository.preserve_protected_file().is_empty(): show_protected(); return
	close_modal(); progress.settle()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or modal: return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER: enter_next()
	get_viewport().set_input_as_handled()

extends Control
const Rules = preload("res://scripts/cargo/rules.gd")
const Store = preload("res://scripts/cargo/store.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const World = preload("res://scripts/cargo/world.gd")
const Audio = preload("res://scripts/encounter/audio.gd")
const ENCOUNTER = preload("res://game/encounter.tscn")
var store = Store.new()
var world: Node2D
var sound: Node
var ui: Control
var overlay: Control
var page = "camp"
var previous_page = "camp"
var busy = false
var active: Control
var time_scale = 1.0
var selected = -1
var down_item = -1
var down_position = Vector2.ZERO
var history: Array[Dictionary] = []
var bubble: Panel
var message: Label
var preview: Label
var action_button: Button
var undo_button: Button
var reset_button: Button
var hint_button: Button
var error_label: Label
var retry_button: Button
var controls: Array[Button] = []
var modal = false
var hover_item = -1
var tooltip: Label
var target_buttons: Array[Button] = []
var camp_start: Button
var journal_button: Button
var settings_button: Button
var home_button: Button
var dialogue_left = 0.0
var dialogue_tail: Polygon2D
var goal_label: Label
func _ready() -> void:
	get_window().title = "数字群岛 · 森林手记 v0.5.2"
	mouse_filter = Control.MOUSE_FILTER_IGNORE; theme = UIStyle.make()
	store.read_save()
	world = World.new(); add_child(world); world.state = store.state.cargo
	sound = Audio.new(); add_child(sound)
	ui = Control.new(); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; overlay.z_index = 100; add_child(overlay)
	apply_audio(); show_camp()
func clear_ui() -> void:
	cancel_pickup(); controls.clear(); target_buttons.clear()
	for c in ui.get_children(): ui.remove_child(c); c.queue_free()
	bubble = null; message = null; preview = null; action_button = null; undo_button = null; tooltip = null
	error_label = null; retry_button = null
func b(value: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var button = UIStyle.button(ui,value,rect,action,primary); controls.append(button); return button
func text(value: String, rect: Rect2, size_px: int = 19, color: Color = UIStyle.INK) -> Label:
	return UIStyle.text(ui,value,rect,size_px,color)
func errors() -> void:
	error_label = text("",Rect2(36,607,888,33),17,Color("ffe0ac"))
	retry_button = b("重试保存",Rect2(1044,597,194,40),save)
	refresh_error()
func refresh_error() -> void:
	if is_instance_valid(error_label): error_label.text = store.error
	if is_instance_valid(retry_button): retry_button.visible = not store.error.is_empty(); retry_button.disabled = store.protected or busy or modal
func save() -> bool:
	if is_instance_valid(active): active.save()
	else: store.save()
	refresh_error(); return store.error.is_empty()
func navigation() -> void:
	journal_button = b("手记",Rect2(1092,30,68,35),show_journal)
	settings_button = b("设置",Rect2(1173,30,68,35),show_settings)
func make_dialogue() -> void:
	bubble = UIStyle.panel(ui,Rect2(204,385,310,100),true)
	message = UIStyle.text(bubble,"",Rect2(16,12,278,176),18,UIStyle.DARK)
	dialogue_tail = Polygon2D.new(); dialogue_tail.color = Color("e9ddba"); bubble.add_child(dialogue_tail)
func show_camp() -> void:
	if busy or modal: return
	clear_ui(); page = "camp"; world.page = page; world.visible = true; world.state = store.state.cargo
	world.lift = 0.0 if world.state.left_low else 1.0
	text("森林营地",Rect2(39,31,440,43),27)
	text("林间来信 · 第一章",Rect2(41,78,430,29),16,UIStyle.MINT)
	navigation()
	var station = b("树梢货运站 · 进入",Rect2(989,341,250,41),show_cargo)
	station.disabled = store.protected
	var house = b("",Rect2(976,176,265,155),show_cargo)
	UIStyle.hotspot(house,"进入树梢货运站"); house.disabled = store.protected
	camp_start = station
	if store.state.cargo.complete:
		camp_start = b("古林小径  →",Rect2(61,423,207,43),open_encounter)
		camp_start.disabled = store.protected
		station.text = "树梢货运站 · 回访"
	var fox = b("",Rect2(world.item_position(0)-Vector2(36,78),Vector2(72,82)),camp_chat)
	UIStyle.hotspot(fox,"和阿橙聊聊")
	text("点木牌出发，或和阿橙聊聊。",Rect2(42,661,670,31),16,UIStyle.MINT)
	make_dialogue(); camp_chat(); errors()
func camp_chat() -> void:
	sound.play_cue("fox")
	if store.state.encounter.reward: say("阿橙：种子、新朋友，还有一起想到的办法。我们都带回来啦。")
	elif store.state.cargo.complete: say("阿橙：种子已经送到树屋。沿着古林小径，去找那位新朋友吧。")
	else: say("阿橙：树屋在等我们的种子。去木牌那里，看看这座货运站吧。")
func show_cargo() -> void:
	if busy or store.protected: return
	clear_ui(); page = "cargo"; world.page = page; world.state = store.state.cargo; world.lift = 0.0 if world.state.left_low else 1.0
	text("树梢货运站",Rect2(38,29,510,42),27)
	goal_label = text("把阿橙、种子和小岚送到树梢",Rect2(40,78,790,29),17,UIStyle.MINT)
	home_button = b("营地",Rect2(1010,30,68,35),leave_cargo); navigation()
	make_dialogue()
	preview = text("",Rect2(982,473,268,72),17,UIStyle.INK)
	preview.add_theme_constant_override("outline_size",0)
	preview.add_theme_color_override("font_outline_color",Color("262e20"))
	preview.visible = false
	tooltip = text("",Rect2(80,469,290,50),16,UIStyle.INK)
	tooltip.add_theme_constant_override("outline_size",0)
	tooltip.add_theme_color_override("font_outline_color",Color("262e20"))
	hint_button = b("问阿橙",Rect2(40,656,87,37),hint)
	undo_button = b("撤销",Rect2(139,656,70,37),undo)
	reset_button = b("重摆",Rect2(221,656,70,37),confirm_reset)
	reset_button.tooltip_text = "重新摆放"
	action_button = b("松闸 · 空格",Rect2(1090,612,154,40),release)
	for entry in [["林下站",0],["左篮",1],["右篮",2],["树梢站",3]]:
		var loc = int(entry[1]); var btn = b("",world.zone_rect(loc),place.bind(loc))
		UIStyle.hotspot(btn,"放到"+entry[0]); target_buttons.append(btn)
	errors(); error_label.position = Vector2(39,128); error_label.size = Vector2(600,60); retry_button.position = Vector2(663,126)
	refresh_cargo()
	if not store.state.cargo.complete: say("阿橙：我和种子先上去，你能把我们送到树屋吗？")
	else: say("阿橙：树屋的花开了！配重留下来，村民也能继续运货。")
func leave_cargo() -> void:
	if busy or modal or not save(): return
	show_camp()
func say(value: String) -> void:
	if is_instance_valid(message):
		message.text = value
		bubble.size.y = clampf(message.get_line_count()*message.get_line_height()+28,84,230)
		message.size.y = bubble.size.y-24
		dialogue_left = maxf(8.0,value.length()*0.16)
func refresh_cargo() -> void:
	world.state = store.state.cargo
	if page != "cargo": return
	var s = store.state.cargo
	goal_label.text = "种子已送达 · 沿古林小径继续旅程" if s.complete else "把阿橙、种子和小岚送到树梢"
	var locked = busy or modal or store.protected
	for c in controls: c.disabled = locked
	undo_button.disabled = locked or history.is_empty() or s.complete
	reset_button.disabled = locked or s.complete
	hint_button.disabled = locked or s.complete
	action_button.text = "古林小径 →" if s.complete else "升降中" if busy else "松闸 · 空格"
	world.moving = busy
	for i in range(target_buttons.size()):
		target_buttons[i].visible = selected >= 0 and Rules.can_move(s,selected,i)
		target_buttons[i].disabled = locked or selected < 0 or not Rules.can_move(s,selected,i)
	if not busy:
		var left = Rules.weight(s,1); var right = Rules.weight(s,2)
		preview.text = "大家都到了。新的路，就从这里开始。" if s.complete else "一样重，吊篮会停在原处。" if left == right else "左篮 ↓   右篮 ↑" if left > right else "左篮 ↑   右篮 ↓"
		if not s.complete and Rules.direction(s) == 0 and left != right: preview.text += "  ·  已靠站"
	refresh_error()
func select_item(i: int) -> void:
	if page != "cargo" or busy or modal or store.state.cargo.complete: return
	selected = i; world.selected = i; sound.play_cue("pickup")
	tooltip.text = Rules.NAMES[i]+" · 重 "+str(Rules.WEIGHTS[i])+" · 选择发光落点"
	refresh_cargo()
func cancel_pickup() -> void:
	selected = -1; down_item = -1
	if is_instance_valid(world): world.selected = -1; world.dragging = false; world.target = -1
	if is_instance_valid(tooltip): tooltip.text = ""
func place(loc: int) -> void:
	if busy or modal or selected < 0: return
	if not Rules.can_move(store.state.cargo,selected,loc):
		say("这里还没靠站。先放下手里的东西，想想怎样让吊篮过来。")
		cancel_pickup(); refresh_cargo(); return
	history.append(store.state.cargo.duplicate(true))
	if history.size() > 100: history.pop_front()
	var item = selected
	var origin = world.pointer+Vector2(0,22) if world.dragging else world.item_position(item)
	store.state.cargo = Rules.moved(store.state.cargo,item,loc)
	world.state = store.state.cargo
	var offset = origin-world.item_position(item)
	cancel_pickup(); busy = true; refresh_cargo()
	var t = create_tween()
	t.tween_method(func(progress: float): world.offsets[item] = offset*(1-progress)-Vector2(0,sin(progress*PI)*18),0.0,1.0,maxf(0.02,0.22*time_scale)).set_trans(Tween.TRANS_SINE)
	await t.finished
	world.offsets.clear(); busy = false
	sound.play_cue("place"); save(); refresh_cargo()
	say("阿橙：松开绳闸前，看看两只篮子谁更重。")
func release() -> void:
	if busy or modal: return
	if store.state.cargo.complete: open_encounter(); return
	cancel_pickup()
	var s = store.state.cargo
	if Rules.direction(s) == 0:
		say("阿橙：一样重，谁也拉不动谁。试着搬一块配重。" if Rules.weight(s,1) == Rules.weight(s,2) else "阿橙：重的一边已经在下面了。换换配重，让另一边更重试试。")
		sound.play_cue("unbalanced"); refresh_cargo(); return
	history.append(s.duplicate(true)); busy = true; refresh_cargo()
	var next = Rules.travel(s)
	preview.text = "绳索绷紧了……重的一边正在下降"
	sound.play_cue("charge")
	var t = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(world,"lift",0.0 if next.left_low else 1.0,maxf(0.02,1.65*time_scale))
	await t.finished
	# Commit a stable arrival only; leaving and editing were locked for the journey.
	var arrivals = {}
	for i in range(3):
		if next.places[i] != s.places[i]: arrivals[i] = world.item_position(i)
	world.state = next
	for i in arrivals: arrivals[i] -= world.item_position(i)
	if not arrivals.is_empty():
		var step = create_tween()
		step.tween_method(func(progress: float):
			for i in arrivals: world.offsets[i] = arrivals[i]*(1-progress)-Vector2(0,sin(progress*PI)*24),0.0,1.0,maxf(0.02,0.65*time_scale))
		await step.finished
	world.offsets.clear(); store.state.cargo = next; busy = false
	sound.play_cue("place"); save(); refresh_cargo()
	if next.complete:
		sound.play_cue("reward"); say("阿橙：我们都到啦！留下的配重，还能帮村民把果子运下来。")
	elif next.places[0] == 3 and s.places[0] != 3:
		sound.play_cue("fox"); say("阿橙：我下篮啦！咦，篮子轻了……现在怎么接你上来？")
	else: say("阿橙：配重会跟着篮子走。让它留在合适的一边，下次还用得上。")
func undo() -> void:
	if busy or modal or history.is_empty() or store.state.cargo.complete: return
	var hints = store.state.cargo.hints
	store.state.cargo = history.pop_back(); store.state.cargo.hints = hints
	cancel_pickup(); world.lift = 0.0 if store.state.cargo.left_low else 1.0
	sound.play_cue("place"); save(); refresh_cargo(); say("回到上一步了。再试一个想法吧。")
func hint() -> void:
	if busy or modal or store.state.cargo.complete: return
	var index = mini(store.state.cargo.hints,2)
	var idea = "篮子连着同一条绳。右边比左边重时，左边就会上升。"
	if index == 1: idea = "乘客到站会下篮，配重会留下。要想想下一趟谁来拉动谁。"
	if index == 2:
		var step = Rules.next_step(store.state.cargo)
		if step.kind == "recover": idea = "现在的配重没法把大家送上去了。试试撤销；也能用「重新摆放」回到出发时。"
		elif step.kind == "travel": idea = "这次装载可以了。松开绳闸，看看谁会上升。"
		elif step.kind == "move": idea = "试着把%s放到%s，再看两边重量的变化。" % [Rules.NAMES[step.item],["林下站","左篮","右篮","树梢站"][step.target]]
	store.state.cargo.hints = mini(3,index+1); save(); say("阿橙："+idea); sound.play_cue("fox")
func confirm_reset() -> void:
	if busy or modal or store.state.cargo.complete: return
	modal = true; cancel_pickup()
	for c in controls: c.disabled = true
	var shade = ColorRect.new(); shade.color = Color(0.02,0.06,0.04,0.70); shade.size = Vector2(1280,720); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(395,249,490,216))
	UIStyle.text(overlay,"把货物放回出发时的位置？",Rect2(429,276,440,42),25)
	UIStyle.text(overlay,"提示记录会保留。也可以撤销回到刚才。",Rect2(429,328,420,47),18,UIStyle.MINT)
	UIStyle.button(overlay,"继续想想",Rect2(429,396,187,43),close_modal).grab_focus()
	UIStyle.button(overlay,"重新摆放",Rect2(638,396,210,43),func():
		history.append(store.state.cargo.duplicate(true)); var hints = store.state.cargo.hints
		store.state.cargo = Rules.fresh(); store.state.cargo.hints = hints
		close_modal(); save(); show_cargo(),true)
func close_modal() -> void:
	for c in overlay.get_children(): overlay.remove_child(c); c.queue_free()
	modal = false
	refresh_cargo()
func show_journal() -> void:
	if busy or modal: return
	previous_page = page if page in ["camp","cargo"] else previous_page
	clear_ui(); page = "journal"; world.page = page
	var paper = UIStyle.panel(ui,Rect2(235,141,810,469),true)
	UIStyle.text(paper,"伙伴手记",Rect2(31,23,740,46),29,UIStyle.DARK)
	UIStyle.text(paper,"阿橙",Rect2(42,91,165,38),24,UIStyle.DARK)
	var portrait = TextureRect.new(); var atlas = AtlasTexture.new(); atlas.atlas = World.FOX; atlas.region = Rect2(200,190,920,880)
	portrait.texture = atlas; portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.position = Vector2(38,141); portrait.size = Vector2(168,158); portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; paper.add_child(portrait)
	UIStyle.text(paper,"共鸣伙伴" if store.state.encounter.reward else "渐渐默契" if store.state.cargo.complete else "初次同行",Rect2(47,322,168,32),18,UIStyle.DARK)
	var learned = "两只篮子，一条绳索。\n我们正在寻找把种子送到树梢的办法。"
	if store.state.cargo.complete: learned = "重的一边下降，把另一边拉上去。\n阿橙下篮后，重量也跟着变了。\n为下一趟留好配重，才能把大家送到。"
	UIStyle.text(paper,"一 · 树梢货运站",Rect2(253,92,518,38),24,UIStyle.DARK)
	UIStyle.text(paper,learned,Rect2(253,147,518,120),19,UIStyle.DARK)
	UIStyle.text(paper,"二 · 石灵之约",Rect2(253,284,518,38),24,UIStyle.DARK)
	UIStyle.text(paper,"把一枚晶体从左搬到右，两边的差会改变两枚。" if store.state.encounter.reward else "送达种子后，去古林里认识一位新朋友。",Rect2(253,337,515,67),19,UIStyle.DARK)
	UIStyle.text(paper,"升降 %d 趟 · 提示 %d 层" % [store.state.cargo.trips,store.state.cargo.hints],Rect2(34,420,594,30),16,UIStyle.DARK)
	b("收起手记",Rect2(882,634,161,40),resume_page); errors()
func show_settings() -> void:
	if busy or modal: return
	previous_page = page if page in ["camp","cargo"] else previous_page
	clear_ui(); page = "settings"; world.page = page
	UIStyle.panel(ui,Rect2(286,151,709,453),true)
	text("旅途设置",Rect2(324,178,610,50),29,UIStyle.DARK)
	b("声音已关闭" if store.state.muted else "声音已开启",Rect2(749,264,205,40),func():
		store.state.muted = not store.state.muted; save(); apply_audio(); show_settings())
	text("环境与动作声音",Rect2(326,271,365,34),19,UIStyle.DARK)
	var slider = HSlider.new(); slider.position = Vector2(329,338); slider.size = Vector2(620,28); slider.min_value = 0; slider.max_value = 1; slider.step = 0.05; slider.value = store.state.volume
	slider.modulate = Color("b49b6e")
	slider.value_changed.connect(func(value: float): store.state.volume = value; save(); apply_audio()); ui.add_child(slider)
	text("拖动货物到发光位置，或先点物件，再点位置。\n1—6 选物件；← → 选吊篮，↓ ↑ 选站台。\n空格松闸，Z 撤销，H 问阿橙。\nEsc 放回手里物件，或返回上一页。",Rect2(327,403,635,139),18,UIStyle.DARK)
	b("返回旅程",Rect2(825,631,170,40),resume_page); errors()
func resume_page() -> void:
	if previous_page == "cargo": show_cargo()
	else: show_camp()
func apply_audio() -> void:
	sound.enabled = not store.state.muted
	sound.set_volume(0.0 if is_instance_valid(active) else store.state.volume)
func open_encounter() -> void:
	if busy or not store.state.cargo.complete or store.protected or not save(): return
	clear_ui(); page = "encounter"; world.visible = false
	active = ENCOUNTER.instantiate(); active.store = store.encounter_store(); active.journey_mode = true; active.time_scale = time_scale
	active.journey_requested.connect(return_encounter); add_child(active); move_child(ui,get_child_count()-1)
	active.theme = UIStyle.make()
	for c in active.hud.get_children():
		if c is Button: UIStyle.style_button(c,c == active.cast_button)
		if c is Label: c.add_theme_constant_override("outline_size",0)
	active.sound.enabled = not store.state.muted; active.sound_slider.value = store.state.volume; active.sound.set_volume(store.state.volume)
	active.mute_button.text = "声音 关" if store.state.muted else "声音 开"
	active.audio_settings_changed.connect(func(volume: float, enabled: bool): store.state.volume = volume; store.state.muted = not enabled; store.save())
	b("回营地",Rect2(489,27,104,44),return_encounter)
	apply_audio(); errors(); error_label.position = Vector2(40,592)
	get_window().title = "数字群岛 · 石灵之约"
func return_encounter() -> void:
	if not is_instance_valid(active) or active.busy or not save(): return
	if store.state.encounter.reward:
		store.state.returned = true
		if not store.save(): refresh_error(); return
	remove_child(active); active.queue_free(); active = null
	apply_audio(); show_camp(); get_window().title = "数字群岛 · 森林手记 v0.5.2"
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(world):
		cancel_pickup()
		if page == "cargo": refresh_cargo()
func _process(delta: float) -> void:
	if page in ["camp","cargo"] and is_instance_valid(bubble):
		dialogue_left = maxf(0,dialogue_left-delta)
		bubble.visible = dialogue_left > 0 and selected < 0 and not busy and not modal
		var foot = world.item_position(0)
		bubble.position = Vector2(clampf(foot.x-112,32,938),foot.y-bubble.size.y-95) if foot.y > 400 else Vector2(clampf(foot.x-140,32,938),foot.y+68)
		var tail_x = clampf(foot.x-bubble.position.x,18,292)
		var edge = bubble.size.y if foot.y > 400 else 0.0
		var tip = 12 if foot.y > 400 else -12
		dialogue_tail.polygon = PackedVector2Array([Vector2(tail_x-9,edge),Vector2(tail_x+9,edge),Vector2(tail_x,edge+tip)])
	if page != "cargo" or busy or modal: return
	world.show_direction = selected >= 0 or action_button.is_hovered() or action_button.has_focus()
	preview.visible = selected < 0 and (action_button.is_hovered() or action_button.has_focus())
	for i in range(target_buttons.size()):
		target_buttons[i].position = world.zone_rect(i).position
		target_buttons[i].size = world.zone_rect(i).size
	world.target = world.hit_zone(world.pointer) if selected >= 0 else -1
	world.hovered = world.hit_item(world.pointer)
	if selected >= 0 and Rules.can_move(store.state.cargo,selected,world.target):
		var after = Rules.moved(store.state.cargo,selected,world.target)
		var left = Rules.weight(after,1); var right = Rules.weight(after,2)
		preview.text = "放下后：左 %d  ·  右 %d\n" % [left,right]+("一样重，停在原处" if left == right else "左篮 ↓   右篮 ↑" if left > right else "左篮 ↑   右篮 ↓")
	elif selected >= 0: preview.text = "选择发光的落点；Esc 可放回"

	var shown_item = selected if selected >= 0 else world.hovered
	if shown_item >= 0 and is_instance_valid(tooltip):
		var point = world.item_position(shown_item)
		tooltip.position = Vector2(clampf(point.x-85,35,964),maxf(111,point.y-120))
	if selected < 0 and is_instance_valid(tooltip):
		var i = world.hovered
		tooltip.text = Rules.NAMES[i]+" · 重 "+str(Rules.WEIGHTS[i])+" · 拿起" if i >= 0 and not store.state.cargo.complete else ""
func _unhandled_input(event: InputEvent) -> void:
	if busy or modal or store.protected: return
	if page != "cargo" or store.state.cargo.complete: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos = event.position
		if event.pressed:
			var i = world.hit_item(pos)
			if selected >= 0 and world.hit_zone(pos) >= 0 and Rules.can_move(store.state.cargo,selected,world.hit_zone(pos)):
				place(world.hit_zone(pos)); return
			if i >= 0: select_item(i); down_item = i; down_position = pos
			elif selected >= 0: cancel_pickup(); refresh_cargo()
		else:
			if world.dragging:
				var loc = world.hit_zone(pos)
				if loc >= 0: place(loc)
				else: cancel_pickup(); refresh_cargo()
			down_item = -1; world.dragging = false

func _input(event: InputEvent) -> void:
	if not is_instance_valid(world): return
	if event is InputEventMouse:
		world.pointer = event.position
	if modal and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_modal(); get_viewport().set_input_as_handled(); return
	if busy or modal or store.protected: return
	if event is InputEventKey and event.pressed and not event.echo:
		if page == "cargo":
			if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_SPACE,KEY_Z,KEY_H,KEY_ESCAPE]:
				get_viewport().set_input_as_handled()
			if event.keycode >= KEY_1 and event.keycode <= KEY_6: select_item(event.keycode-KEY_1)
			elif event.keycode == KEY_LEFT: place(1)
			elif event.keycode == KEY_RIGHT: place(2)
			elif event.keycode == KEY_DOWN: place(0)
			elif event.keycode == KEY_UP: place(3)
			elif event.keycode == KEY_SPACE: release()
			elif event.keycode == KEY_Z: undo()
			elif event.keycode == KEY_H: hint()
			elif event.keycode == KEY_ESCAPE:
				if selected >= 0: cancel_pickup(); refresh_cargo()
				else: leave_cargo()
		elif event.keycode == KEY_ESCAPE and page in ["journal","settings"]:
			resume_page(); get_viewport().set_input_as_handled()
	if busy or modal or page != "cargo": return
	if event is InputEventMouseMotion and down_item >= 0 and selected >= 0:
		if event.position.distance_to(down_position) > 7: world.dragging = true

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and down_item >= 0:
		if world.dragging:
			var loc = world.hit_zone(event.position)
			if loc >= 0: place(loc)
			else: cancel_pickup(); refresh_cargo()
			get_viewport().set_input_as_handled()
		down_item = -1; world.dragging = false

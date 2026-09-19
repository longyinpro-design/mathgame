extends Control
signal journey_requested
signal audio_settings_changed(volume: float, enabled: bool)
var journey_mode = false
const Rules = preload("res://scripts/encounter/rules.gd")
const Store = preload("res://scripts/encounter/store.gd")
const Visuals = preload("res://scripts/encounter/visuals.gd")
const Audio = preload("res://scripts/encounter/audio.gd")
const INK = Color("f4ead1")
const GOLD = Color("eace83")
const TEAL = Color("89d9c6")
var store = Store.new()
var state: Dictionary
var scene: Node2D
var sound: Node
var hud: Control
var controls: Array[Button] = []
var phase = "approach"
var busy = false
var time_scale = 1.0
var selected = -1
var drag_side = -1
var drag_start = Vector2.ZERO
var dragging = false
var pointer_position = Vector2.ZERO
var history: Array[int] = []
var walk_target = 155.0
var foot_timer = 0.0
var status: Label
var save_warning: Label
var left_label: Label
var right_label: Label
var difference_label: Label
var ribbon: Label
var cast_button: Button
var undo_button: Button
var reset_button: Button
var hint_button: Button
var mute_button: Button
var sound_slider: HSlider
var retry_save_button: Button
var caption = ""
var demo_events: Array[String] = []

func _ready() -> void:
	get_window().title = "数字群岛 · 石灵双护盾 v0.3"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font = SystemFont.new(); font.font_names = PackedStringArray(["Heiti SC","Noto Sans CJK SC","Microsoft YaHei","PingFang SC"])
	var theme_value = Theme.new(); theme_value.default_font = font; theme_value.default_font_size = 20; theme = theme_value
	scene = Visuals.new(); add_child(scene)
	sound = Audio.new(); add_child(sound)
	state = store.read_save(); scene.left = state.left
	hud = Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(hud)
	make_hud()
	if state.won:
		phase = "done" if state.reward else "reward"; scene.hero_x = 300; scene.fox_x = 407
		scene.portal = 1; scene.guardian_awake = 1; scene.guardian_warmth = 1; scene.guardian_offset = Vector2(220,0)
		scene.medal_alpha = 1; show_reward()
	elif state.introduced:
		phase = "ready"; scene.hero_x = 300; scene.fox_x = 407; scene.guardian_awake = 1; scene.shield_alpha = 1; scene.crystal_visibility = 1
		caption = "拖动一枚晶体到另一面护盾；也可以点晶体，再点护盾。"
	refresh()

func seconds(value: float) -> float: return maxf(0.002,value*time_scale)
func wait_for(value: float) -> void: await get_tree().create_timer(seconds(value)).timeout
func record(event: String) -> void:
	demo_events.append(event)
	if demo_events.size() > 100: demo_events.pop_front()
func save() -> void:
	store.write_save(state)
	if is_instance_valid(save_warning): save_warning.text = store.error
	if is_instance_valid(retry_save_button):
		retry_save_button.visible = not store.error.is_empty()
		retry_save_button.disabled = busy or store.protected
func label(text: String, rect: Rect2, size_px: int = 20, color: Color = INK) -> Label:
	var l = Label.new(); l.clip_text = true; l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.add_theme_font_size_override("font_size",size_px); l.add_theme_color_override("font_color",color)
	l.add_theme_color_override("font_outline_color",Color("0b1d20")); l.add_theme_constant_override("outline_size",4)
	l.text = text; l.position = rect.position; l.size = rect.size; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l); return l
func panel(rect: Rect2, color: Color, border: bool = false) -> Panel:
	var p = Panel.new(); p.position = rect.position; p.size = rect.size; p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new(); style.bg_color = color; style.set_corner_radius_all(10)
	if border: style.border_color = Color("a89866"); style.set_border_width_all(1)
	p.add_theme_stylebox_override("panel",style); hud.add_child(p); return p
func button(text: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var b = Button.new(); b.text = text; b.position = rect.position; b.size = rect.size
	for key in ["normal","hover","pressed","focus","disabled"]:
		var style = StyleBoxFlat.new(); style.set_corner_radius_all(9); style.set_border_width_all(1)
		style.bg_color = Color("d6ba74") if primary else Color("182c30")
		style.border_color = GOLD if key == "focus" else Color("7e8f78")
		if key == "hover": style.bg_color = Color("edd293") if primary else Color("31504b")
		if key == "pressed": style.bg_color = Color("b99d58") if primary else Color("426b60")
		if key == "disabled": style.bg_color = Color("283a3a")
		b.add_theme_stylebox_override(key,style)
	b.add_theme_color_override("font_color",Color("172d30") if primary else INK)
	b.add_theme_color_override("font_hover_color",Color("172d30") if primary else INK)
	b.add_theme_color_override("font_pressed_color",Color("172d30") if primary else INK)
	b.add_theme_color_override("font_disabled_color",Color("879890"))
	b.pressed.connect(action); hud.add_child(b); controls.append(b); return b

func make_hud() -> void:
	panel(Rect2(24,20,453,92),Color(0.025,0.085,0.11,0.86))
	label("古林遗迹",Rect2(44,29,405,34),21,TEAL)
	label("石灵的双重封印",Rect2(44,65,405,41),28,GOLD)
	panel(Rect2(605,25,450,70),Color(0.025,0.085,0.11,0.82))
	label("14 枚晶体  ·  右侧要比左侧多 4 枚",Rect2(623,45,418,40),22)
	mute_button = button("声音 开",Rect2(1092,24,160,38),toggle_audio)
	sound_slider = HSlider.new(); sound_slider.min_value = 0; sound_slider.max_value = 1; sound_slider.step = 0.05; sound_slider.value = 0.7
	sound_slider.position = Vector2(1097,76); sound_slider.size = Vector2(147,18); sound_slider.value_changed.connect(set_audio_volume); hud.add_child(sound_slider)
	panel(Rect2(24,638,1232,63),Color(0.025,0.085,0.11,0.92),true)
	status = label("点击地面走近石灵  ·  A / D 移动",Rect2(43,652,654,42),20)
	undo_button = button("撤销",Rect2(700,648,85,44),undo)
	reset_button = button("重置",Rect2(795,648,85,44),reset_distribution)
	hint_button = button("阿橙",Rect2(890,648,85,44),hint)
	cast_button = button("走近石灵",Rect2(990,648,246,44),primary_action,true)
	left_label = label("",Rect2(519,468,180,48),27,TEAL); left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_label = label("",Rect2(959,468,180,48),27,GOLD); right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difference_label = label("",Rect2(713,546,197,61),21); difference_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ribbon = label("",Rect2(106,155,400,109),24,GOLD)
	save_warning = label(store.error,Rect2(26,117,1030,34),18,Color("ffc795"))
	retry_save_button = button("重试保存",Rect2(1092,116,160,36),retry_save)
	retry_save_button.visible = not store.error.is_empty()

func refresh() -> void:
	var ready = phase == "ready" and not busy
	undo_button.disabled = not ready or history.is_empty(); reset_button.disabled = not ready; hint_button.disabled = not ready or state.hint >= 2
	cast_button.disabled = busy
	var action_labels = {"approach":"走近石灵","intro":"封印苏醒中…","ready":"晶体归位中…" if busy else "合力施法","casting":"正在施法…","reward":"收下信物","done":"再次体验","confirm":"再次体验"}
	cast_button.text = action_labels[phase]
	if journey_mode and phase == "done": cast_button.text = "带信物返回营地"
	var counts_visible = phase in ["ready","casting"]
	left_label.visible = counts_visible; right_label.visible = counts_visible; difference_label.visible = counts_visible
	left_label.text = "左  %d" % state.left; right_label.text = "右  %d" % (14-state.left)
	if state.attempts == 0: difference_label.text = "总数始终为 14"
	status.text = caption if not caption.is_empty() else "点击地面走近石灵  ·  A / D 移动"
	scene.left = state.left; scene.selected = selected
	save_warning.text = store.error
	retry_save_button.visible = not store.error.is_empty()
	retry_save_button.disabled = busy or store.protected

func retry_save() -> void:
	if busy or store.protected: return
	save(); refresh()

func _process(delta: float) -> void:
	if scene == null: return
	if phase == "approach" and not busy:
		var direction = 0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction += 1
		if direction != 0: walk_target = clampf(scene.hero_x+direction*80,100,310)
		if absf(scene.hero_x-walk_target) > 2:
			scene.hero_pose = "walk"; scene.hero_x = move_toward(scene.hero_x,walk_target,165*delta/maxf(time_scale,0.05))
			scene.fox_x = move_toward(scene.fox_x,scene.hero_x-80,160*delta/maxf(time_scale,0.05))
			foot_timer -= delta
			if foot_timer <= 0: sound.play_cue("footstep"); foot_timer = 0.32
		else: scene.hero_pose = "idle"
		if scene.hero_x >= 307: awaken()
	if dragging:
		var p = pointer_position; scene.drag_ghost.position = p
		scene.hover_side = scene.target_side(scene.world_point(p))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(scene): cancel_drag()
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M: toggle_audio()
		elif event.keycode == KEY_ESCAPE: cancel_drag()
		elif event.keycode in [KEY_SPACE,KEY_ENTER] and not busy: primary_action()
		elif event.keycode == KEY_Z: undo()
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if busy: return
	var p = scene.world_point(event.position)
	if phase == "approach" and event.pressed and p.y > 170 and p.y < 610:
		walk_target = clampf(p.x,100,310); return
	if phase != "ready": return
	if event.pressed:
		var side = scene.target_side(p)
		if selected >= 0:
			var from = 0 if selected < state.left else 1
			if side >= 0 and side != from:
				transfer(from,side); return
		var index = scene.hit_crystal(p)
		if index < 0: cancel_drag(); return
		selected = index; drag_side = 0 if index < state.left else 1; dragging = true; drag_start = event.position; pointer_position = event.position
		scene.drag_ghost.position = event.position; scene.drag_ghost.visible = true; scene.selected = selected; sound.play_cue("pickup")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_position = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		dragging = false; scene.drag_ghost.visible = false; scene.hover_side = -1
		if event.position.distance_to(drag_start) > 12:
			var side = scene.target_side(scene.world_point(event.position))
			if side >= 0 and side != drag_side: transfer(drag_side,side)
			else: cancel_drag()
		get_viewport().set_input_as_handled()

func cancel_drag() -> void:
	dragging = false; selected = -1; drag_side = -1
	scene.drag_ghost.visible = false; scene.hover_side = -1; scene.selected = -1
func toggle_audio() -> void:
	sound.toggle(); mute_button.text = "声音 开" if sound.enabled else "声音 关"
	audio_settings_changed.emit(sound.volume,sound.enabled)
func set_audio_volume(value: float) -> void:
	sound.set_volume(value)
	audio_settings_changed.emit(sound.volume,sound.enabled)
func primary_action() -> void:
	if busy: return
	match phase:
		"approach": walk_target = 310
		"ready": cast_spell()
		"reward": claim_reward()
		"done":
			if journey_mode: journey_requested.emit()
			else: confirm_replay()

func awaken() -> void:
	if busy or phase != "approach": return
	busy = true; phase = "intro"; scene.hero_pose = "idle"; caption = "阿橙：等等……它醒了！"; refresh(); record("awaken")
	sound.play_cue("fox"); ribbon.text = "阿橙：\n“它的护盾里，藏着一道封印。”"
	var t = create_tween().set_parallel(true)
	t.tween_property(scene,"fox_x",398.0,seconds(0.65)); t.tween_property(scene,"fox_hop",20.0,seconds(0.3))
	await t.finished
	sound.play_cue("awaken"); scene.shake = 2.2
	t = create_tween().set_parallel(true)
	t.tween_property(scene,"guardian_awake",1.0,seconds(1.0)); t.tween_property(scene,"zoom",1.045,seconds(1.2))
	t.tween_property(scene,"fox_hop",0.0,seconds(0.4))
	await t.finished; scene.shake = 0
	t = create_tween().set_parallel(true)
	t.tween_property(scene,"shield_alpha",1.0,seconds(0.8)); t.tween_property(scene,"crystal_visibility",1.0,seconds(1.2))
	await t.finished
	ribbon.text = "“14 枚晶体……\n让右侧比左侧多 4 枚。”"
	await wait_for(1.6)
	t = create_tween(); t.tween_property(scene,"zoom",1.0,seconds(0.5)); await t.finished
	state.introduced = true; save(); ribbon.text = ""; phase = "ready"; busy = false
	caption = "拖动晶体到另一面护盾；也可点晶体，再点护盾。"; refresh()

func transfer(from: int, to: int) -> void:
	if busy or phase != "ready" or from not in [0,1] or to != 1-from: return
	var source_count = state.left if from == 0 else 14-state.left
	if source_count <= 0: return
	var source_index = selected if selected >= 0 else (state.left-1 if from == 0 else 13)
	var start = scene.crystal_nodes[source_index].position
	var finish = scene.crystal_position(to,state.left if to == 0 else 14-state.left)
	history.append(state.left)
	if history.size() > 60: history.pop_front()
	var previous_left = state.left
	state.left += 1 if to == 0 else -1
	cancel_drag(); busy = true; save(); refresh(); scene.left = previous_left; record("transfer")
	scene.crystal_nodes[source_index].visible = false
	scene.drag_ghost.visible = true; scene.drag_ghost.position = start
	var t = create_tween(); t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(scene.drag_ghost,"position",(start+finish)/2-Vector2(0,60),seconds(0.18))
	t.tween_property(scene.drag_ghost,"position",finish,seconds(0.18))
	await t.finished
	scene.crystal_nodes[source_index].visible = true; scene.drag_ghost.visible = false
	sound.play_cue("place"); busy = false; difference_label.text = "总数始终为 14"; refresh()

func undo() -> void:
	if busy or phase != "ready" or history.is_empty(): return
	cancel_drag(); state.left = history.pop_back(); save(); caption = "已撤销这次移动。"; sound.play_cue("place"); difference_label.text = "总数始终为 14"; refresh()
func reset_distribution() -> void:
	if busy or phase != "ready": return
	cancel_drag(); history.append(state.left); state.left = 7; save(); caption = "回到两侧各 7 枚，可以重新分配。"; difference_label.text = "总数始终为 14"; refresh()
func hint() -> void:
	if busy or phase != "ready" or state.hint >= 2: return
	state.hint += 1; save(); sound.play_cue("fox")
	caption = "阿橙：从左移 1 枚到右边，左少 1、右多 1，差会增加多少？" if state.hint == 1 else "阿橙：两边原本一样多。每移 1 枚，差增加 2；想要差 4 呢？"
	refresh()

func cast_spell() -> void:
	if busy or phase != "ready": return
	cancel_drag(); busy = true; phase = "casting"; state.attempts += 1; save(); caption = "小岚与阿橙正在合力施法……"; refresh(); record("charge")
	var outcome = Rules.result(state.left)
	scene.hero_pose = "charge"; scene.fox_pose = "charge"; scene.cutin_kind = "cast"
	sound.play_cue("charge")
	var t = create_tween().set_parallel(true)
	t.tween_property(scene,"charge",1.0,seconds(0.95)); t.tween_property(scene,"zoom",1.04,seconds(0.7)); t.tween_property(scene,"cutin",0.90,seconds(0.4))
	await t.finished
	await wait_for(0.2)
	t = create_tween(); t.tween_property(scene,"cutin",0.0,seconds(0.24)); await t.finished
	scene.hero_pose = "cast"; scene.fox_pose = "cast"; scene.fox_hop = 13; scene.spell_progress = 0
	sound.play_cue("cast"); record("release")
	t = create_tween().set_parallel(true)
	t.tween_property(scene,"spell_progress",1.0,seconds(0.62)); t.tween_property(scene,"charge",0.0,seconds(0.4))
	await t.finished
	scene.spell_progress = -1; scene.impact = 0.01; scene.impact_success = outcome.success; scene.shake = 2.6 if outcome.success else 4.1
	scene.shield_charge = [state.left/14.0,(14-state.left)/14.0]
	sound.play_cue("impact"); record("impact")
	t = create_tween().set_parallel(true)
	t.tween_property(scene,"impact",1.0,seconds(0.65)); t.tween_property(scene,"fox_hop",0.0,seconds(0.4)); t.tween_property(scene,"shake",0.0,seconds(0.45))
	await t.finished; scene.impact = 0; scene.fox_pose = "idle"
	if not outcome.success:
		sound.play_cue("unbalanced"); scene.hero_pose = "guard"; scene.guardian_offset = Vector2(-8,0)
		difference_label.text = "右 − 左 = %d\n还未达到 4" % outcome.difference
		caption = "护盾失衡了！布局保留，调整后再试。"; status.text = caption; record("failure")
		t = create_tween().set_parallel(true)
		t.tween_property(scene,"shield_tilt",0.16,seconds(0.15)); t.tween_property(scene,"hero_recoil",14.0,seconds(0.16))
		await t.finished; await wait_for(0.25)
		t = create_tween().set_parallel(true)
		t.tween_property(scene,"shield_tilt",0.0,seconds(0.45)); t.tween_property(scene,"hero_recoil",0.0,seconds(0.45)); t.tween_property(scene,"guardian_offset",Vector2.ZERO,seconds(0.45)); t.tween_property(scene,"zoom",1.0,seconds(0.5))
		await t.finished; scene.hero_pose = "idle"; phase = "ready"; busy = false; refresh(); return
	state.won = true; save(); record("success")
	difference_label.text = "9 − 5 = 4\n封印稳定"; caption = "两面护盾产生了共鸣……"; status.text = caption
	sound.play_cue("unlock")
	t = create_tween().set_parallel(true)
	t.tween_property(scene,"shield_alpha",0.0,seconds(1.25)); t.tween_property(scene,"crystal_visibility",0.0,seconds(1.1)); t.tween_property(scene,"guardian_warmth",1.0,seconds(1.6))
	t.tween_property(scene,"portal",1.0,seconds(1.7)); t.tween_property(scene,"guardian_offset",Vector2(218,0),seconds(1.7)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	scene.hero_pose = "idle"; scene.cutin_kind = "victory"
	t = create_tween().set_parallel(true)
	t.tween_property(scene,"zoom",1.0,seconds(0.8)); t.tween_property(scene,"medal_alpha",1.0,seconds(0.9)); t.tween_property(scene,"fox_hop",24.0,seconds(0.3))
	await t.finished
	t = create_tween(); t.tween_property(scene,"fox_hop",0.0,seconds(0.3)); await t.finished
	phase = "reward"; busy = false; show_reward(); refresh()

func show_reward() -> void:
	ribbon.position = Vector2(478,176); ribbon.size = Vector2(330,116)
	ribbon.text = "封印解除\n石灵认可了你们的合作。"
	caption = "石灵留下了一枚信物。点击「收下信物」。" if not state.reward else "已获得「石灵之约」· 这段旅程已记录。"
	scene.medal_alpha = 1; scene.cutin_kind = "victory"
	if state.reward: scene.cutin = 0.55

func claim_reward() -> void:
	if busy or phase != "reward" or not state.won or state.reward: return
	state.reward = true; save(); busy = true; sound.play_cue("reward"); record("reward")
	ribbon.position = Vector2(478,176); ribbon.text = "石灵之约\n获得信物 × 1"
	var t = create_tween().set_parallel(true)
	t.tween_property(scene,"medal_scale",1.3,seconds(0.35)); t.tween_property(scene,"cutin",0.72,seconds(0.45))
	await t.finished
	t = create_tween(); t.tween_property(scene,"medal_scale",1.0,seconds(0.35)); await t.finished
	phase = "done"; busy = false
	caption = "石灵之约已收下。带着阿橙和这份发现，一起回营地吧。" if journey_mode else "石灵之约已收下。感谢体验这段伙伴协作。"
	refresh()

func confirm_replay() -> void:
	if journey_mode: return
	if busy or phase != "done": return
	phase = "confirm"; cast_button.disabled = true
	var overlay = PanelContainer.new(); overlay.name = "ReplayConfirmation"; overlay.position = Vector2(355,248); overlay.size = Vector2(570,200)
	var box = StyleBoxFlat.new(); box.bg_color = Color("112c30"); box.border_color = GOLD; box.set_border_width_all(2); box.set_corner_radius_all(14)
	overlay.add_theme_stylebox_override("panel",box); hud.add_child(overlay)
	var body = VBoxContainer.new(); body.add_theme_constant_override("separation",18); overlay.add_child(body)
	var l = Label.new(); l.text = "重新开始这次遭遇？\n本样板的分配和信物记录将重新开始。"; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; body.add_child(l)
	var row = HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation",26); body.add_child(row)
	for choice in ["留在这里","重新体验"]:
		var b = Button.new(); b.text = choice; b.custom_minimum_size = Vector2(210,48); row.add_child(b)
		b.pressed.connect(func():
			overlay.queue_free()
			if choice == "重新体验": restart()
			else: phase = "done"; refresh())

func restart() -> void:
	if journey_mode: return
	if phase != "confirm" or busy: return
	state = Rules.fresh(); history.clear(); cancel_drag(); save()
	phase = "approach"; scene.hero_x = 155; scene.fox_x = 65; walk_target = 155
	scene.guardian_offset = Vector2.ZERO; scene.guardian_awake = 0; scene.guardian_warmth = 0; scene.shield_alpha = 0; scene.portal = 0; scene.cutin = 0; scene.medal_alpha = 0; scene.crystal_visibility = 0; scene.shield_charge = [0.0,0.0]
	caption = ""; ribbon.text = ""; ribbon.position = Vector2(106,155); difference_label.text = ""; refresh()

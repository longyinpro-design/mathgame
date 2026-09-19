extends Control

const Store = preload("res://scripts/journey/store.gd")
const Camp = preload("res://scripts/journey/camp.gd")
const Audio = preload("res://scripts/encounter/audio.gd")
const CHAPTER = preload("res://game/chapter.tscn")
const ENCOUNTER = preload("res://game/encounter.tscn")
const INK = Color("f3e8cd")
const GOLD = Color("e7c887")
const TEAL = Color("a6d5bd")
const MUTED = Color("a9b7ab")
var store = Store.new()
var active: Control
var active_kind = ""
var page = "camp"
var scenery: Node2D
var sound: Node
var ui: Control
var chrome: Control
var home_button: Button
var error_panel: Panel
var error_label: Label
var retry_button: Button
var notice: Label
var transition = false
var animation_scale = 1.0

func _ready() -> void:
	get_window().title = "数字群岛 · 森林来信"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Heiti SC","Noto Sans CJK SC","Microsoft YaHei","PingFang SC"])
	var skin = Theme.new(); skin.default_font = font; skin.default_font_size = 21; theme = skin
	store.read_save()
	scenery = Camp.new(); add_child(scenery)
	sound = Audio.new(); add_child(sound)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(ui)
	chrome = Control.new(); chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE; chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); chrome.z_index = 100; add_child(chrome)
	home_button = button("回营地",Rect2(726,26,150,44),return_to_camp,false,chrome)
	home_button.visible = false
	error_panel = panel(Rect2(230,558,820,67),chrome)
	error_panel.z_index = 110
	error_label = label("",Rect2(16,12,622,48),18,GOLD,error_panel)
	retry_button = button("重试保存",Rect2(650,12,154,43),retry_save,false,error_panel)
	show_camp()

func _process(_delta: float) -> void:
	refresh_chrome()

func refresh_chrome() -> void:
	home_button.visible = is_instance_valid(active)
	home_button.disabled = transition or (is_instance_valid(active) and active.busy)
	error_panel.visible = not store.error.is_empty()
	error_label.text = store.error
	retry_button.disabled = store.protected or transition or (is_instance_valid(active) and active.busy)

func clear_ui() -> void:
	for child in ui.get_children():
		ui.remove_child(child); child.queue_free()
	notice = null

func panel(rect: Rect2, parent: Node = null, parchment: bool = false) -> Panel:
	var p = Panel.new(); p.position = rect.position; p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color("ede2c5") if parchment else Color(0.055,0.13,0.135,0.97)
	style.border_color = Color("b59a66") if parchment else Color("5e7464")
	style.set_border_width_all(1); style.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel",style)
	(parent if parent != null else ui).add_child(p); return p

func label(value: String, rect: Rect2, size_px: int = 21, color: Color = INK, parent: Node = null) -> Label:
	var l = Label.new(); l.text = value; l.position = rect.position; l.size = rect.size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size",size_px); l.add_theme_color_override("font_color",color)
	(parent if parent != null else ui).add_child(l); return l

func button(value: String, rect: Rect2, action: Callable, primary: bool = false, parent: Node = null) -> Button:
	var b = Button.new(); b.text = value; b.position = rect.position; b.size = rect.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for key in ["normal","hover","pressed","focus","disabled"]:
		var style = StyleBoxFlat.new(); style.set_corner_radius_all(6); style.set_border_width_all(1)
		style.bg_color = Color("e1c386") if primary else Color("183531")
		style.border_color = Color("ccb67e") if primary else Color("75866b")
		if key == "hover": style.bg_color = Color("f1d69c") if primary else Color("315449")
		if key == "pressed": style.bg_color = Color("bca06a") if primary else Color("3c6756")
		if key == "focus": style.set_border_width_all(3); style.border_color = Color("fff0b6")
		if key == "disabled": style.bg_color = Color("293c37"); style.border_color = Color("44574b")
		b.add_theme_stylebox_override(key,style)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		b.add_theme_color_override(key,Color("24372c") if primary else INK)
	b.add_theme_color_override("font_disabled_color",MUTED)
	b.pressed.connect(action)
	(parent if parent != null else ui).add_child(b); return b

func picture(texture: Texture2D, region: Rect2, rect: Rect2, parent: Node = null) -> TextureRect:
	var atlas = AtlasTexture.new(); atlas.atlas = texture; atlas.region = region
	var p = TextureRect.new(); p.texture = atlas; p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; p.position = rect.position; p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else ui).add_child(p); return p

func heading() -> void:
	label("像素数学   /   数字群岛",Rect2(42,26,450,36),22,GOLD)
	button("旅程",Rect2(766,22,100,44),show_camp)
	button("伙伴手记",Rect2(877,22,151,44),show_journal)
	button("声音与操作",Rect2(1039,22,199,44),show_settings)

func show_camp() -> void:
	if is_instance_valid(active) or transition: return
	page = "camp"; scenery.page = page; scenery.visible = true
	scenery.progress = store.milestone(); scenery.returned = store.state.returned
	apply_audio(); clear_ui(); heading()
	var progress = store.milestone()
	label("第一章    森林来信",Rect2(44,113,384,38),20,TEAL)
	label("把新发现，\n带回营地。" if progress == 2 else "带上阿橙，\n去发现吧。",Rect2(40,160,394,132),48)
	var story = "种子在阿橙的挎包里。\n去断桥，找一条通往对岸的路。"
	if progress == 1: story = "种子送到了，林间的路再次相连。\n古林深处，石灵正在等你们。"
	elif progress == 2: story = "修好一座桥，带回一枚信物。\n你们的发现，让营地长出了新芽。"
	label(story,Rect2(44,308,356,96),21,INK)
	label(["阿橙   ·   初次同行","阿橙   ·   渐渐默契","阿橙   ·   共鸣伙伴"][progress],Rect2(44,538,354,34),20,TEAL)
	var action = "开始旅程  →"
	if store.state.chapter.intro: action = "继续修桥之旅  →"
	if progress == 1: action = "前往古林遗迹  →"
	if progress == 2: action = "翻开伙伴手记  →" if store.state.returned else "点亮营地  →"
	var primary = button(action,Rect2(42,593,336,58),camp_primary,true)
	primary.disabled = store.protected
	label("随时回营地休息，操作进度会留下。",Rect2(44,665,560,30),17,MUTED)
	panel(Rect2(925,96,310,158))
	label(["守桥人的来信","来自古林的回声","给下一次远行的信"][progress],Rect2(948,117,268,32),22,GOLD)
	label(["“村里的苗圃在等种子。\n带上阿橙，我们在桥边见。”", "“林间有一位沉睡的石灵，\n它的护盾，需要你们的合作。”", "“桥通了，种子也发芽了。\n谢谢你们带回森林的生机。”"][progress],Rect2(948,162,266,75),19,INK)
	button("探险营地",Rect2(781,329,172,44),camp_story)
	var forest = button("森林断桥"+ ("  ✓" if progress > 0 else ""),Rect2(632,455,181,44),open_stage.bind("chapter"))
	forest.disabled = store.protected
	var gate = button("古林遗迹"+ ("  ✓" if progress > 1 else ""),Rect2(425,551,184,44),open_stage.bind("encounter"))
	gate.disabled = progress < 1 or store.protected
	if progress == 0: label("送达种子后开启",Rect2(433,601,210,28),17,INK)
	if progress > 0:
		panel(Rect2(898,601,337,37))
		label("营地的新芽  ·  "+("已经开花" if store.state.returned else "正在生长"),Rect2(912,609,314,27),17,TEAL)
	panel(Rect2(414,647,833,51))
	notice = label("",Rect2(424,656,812,40),19,INK)
	notice.text = "从营地出发，沿着标记去往森林。" if progress == 0 else "可以回访走过的地方，也可以翻开手记，看看共同的发现。"
	refresh_chrome()

func camp_primary() -> void:
	if store.state.encounter.reward:
		if not store.state.returned:
			store.state.returned = true
			if not store.save(): return
		show_journal()
	else: open_stage(store.next_stop())

func camp_story() -> void:
	if not is_instance_valid(notice): return
	notice.text = ["阿橙：种子在包里，地图也带上了。我们去看看那座断桥吧！", "阿橙：村里的种子发芽了。接下来，去听听石灵的故事。", "阿橙：我们把发现带回来了。下次远行，也要一起！"][store.milestone()]
	sound.play_cue("fox")
	var tween = create_tween(); tween.tween_property(scenery,"fox_hop",16.0,0.2); tween.tween_property(scenery,"fox_hop",0.0,0.24)

func show_journal() -> void:
	if is_instance_valid(active) or transition: return
	page = "journal"; scenery.page = page; clear_ui(); heading()
	label("伙伴手记",Rect2(48,105,620,68),42)
	label("一起走过的路，会变成彼此的故事。",Rect2(49,175,825,36),21,TEAL)
	panel(Rect2(46,239,355,392))
	picture(Camp.FOX,Rect2(200,190,920,880),Rect2(117,263,205,179))
	var progress = store.milestone()
	label("阿橙",Rect2(76,455,290,40),32,GOLD)
	if progress > 1: picture(Camp.OBJECTS,Rect2(778,664,323,520),Rect2(292,452,35,49))
	label(["初次同行","渐渐默契","共鸣伙伴"][progress]+"  ·  默契 %d / 2" % progress,Rect2(76,506,290,36),22,TEAL)
	for i in range(2):
		var bar = ColorRect.new(); bar.position = Vector2(78+i*141,556); bar.size = Vector2(126,7)
		bar.color = GOLD if i < progress else Color("40594b"); bar.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.add_child(bar)
	label("送种与合力施法，让默契成长。",Rect2(76,588,294,31),16,MUTED)
	var paper = panel(Rect2(426,239,807,392),null,true)
	var ink = Color("354337")
	label("这一次，我们发现了什么",Rect2(27,23,745,47),28,ink,paper)
	var bridge = "还未写下。去森林里寻找三条线索。"
	if progress > 0: bridge = "顶点上的一块石头，会同时影响两条光路。\n我们计划好两次交换，让整座桥亮了起来。"
	label("01  森林的另一边"+ ("  ·  种子已送达" if progress > 0 else ""),Rect2(27,88,741,35),22,ink,paper)
	label(bridge,Rect2(27,131,738,63),20,ink,paper)
	var guardian = "林间还有一道封印，等我们一起去认识。"
	if progress > 1: guardian = "从左边搬一枚到右边，差就增加两枚。\n5 与 9 的能量产生共鸣，石灵把信物交给了我们。"
	label("02  石灵之约"+ ("  ·  信物 × 1" if progress > 1 else ""),Rect2(27,217,741,34),22,ink,paper)
	label(guardian,Rect2(27,262,660,65),20,ink,paper)
	if progress > 1: picture(Camp.OBJECTS,Rect2(778,664,323,520),Rect2(1131,505,66,91))
	var hints = store.state.chapter.hints[0]+store.state.chapter.hints[1]+store.state.encounter.hint
	label("旅途中：供能 %d 次  /  施法 %d 次  /  提示 %d 层" % [store.state.chapter.attempts[0]+store.state.chapter.attempts[1],store.state.encounter.attempts,hints],Rect2(49,661,989,30),18,MUTED)
	button("回到营地",Rect2(1041,651,192,46),show_camp,true)

func show_settings() -> void:
	if is_instance_valid(active) or transition: return
	page = "settings"; scenery.page = page; clear_ui(); heading()
	panel(Rect2(245,131,790,499))
	label("舒服地开始旅程",Rect2(286,164,698,63),36,GOLD)
	label("声音",Rect2(287,246,116,40),25)
	var mute = button("已静音" if store.state.muted else "声音开启",Rect2(799,244,188,44),func():
		store.state.muted = not store.state.muted; store.save(); apply_audio(); show_settings())
	mute.name = "Mute"
	var slider = HSlider.new(); slider.name = "Volume"; slider.min_value = 0; slider.max_value = 1; slider.step = 0.05
	slider.value = store.state.volume; slider.position = Vector2(409,255); slider.size = Vector2(357,34)
	slider.value_changed.connect(func(value: float): store.state.volume = value; apply_audio(); store.save())
	ui.add_child(slider)
	label("探索",Rect2(287,330,104,35),22,TEAL)
	label("点击地面，或用 A / D、左右方向键移动。\n点击场景标记走近查看；空格推进对话。",Rect2(408,329,576,73),21)
	label("机关",Rect2(287,420,104,35),22,TEAL)
	label("数字石：先点石头，再点位置。晶体可拖动，\n也可先点晶体，再点另一面护盾。",Rect2(408,419,576,74),21)
	label("慢慢想，没有倒计时。随时使用撤销或伙伴提示。",Rect2(287,516,697,37),20,INK)
	button("回到营地",Rect2(760,566,226,45),show_camp,true)

func apply_audio() -> void:
	sound.enabled = not store.state.muted
	sound.set_volume(0.0 if active_kind == "encounter" else store.state.volume)

func open_stage(kind: String) -> void:
	if transition or is_instance_valid(active) or store.protected: return
	if kind not in ["chapter","encounter"]: return
	if kind == "encounter" and store.state.chapter.stage < 3: return
	if not store.save(): return
	await mount_stage(kind)

func mount_stage(kind: String) -> void:
	# Callers have already saved the departure; no fallible write after detaching it.
	transition = true; clear_ui(); scenery.visible = false
	active_kind = kind
	active = (CHAPTER if kind == "chapter" else ENCOUNTER).instantiate()
	active.store = store.section_store(kind); active.journey_mode = true
	if kind == "chapter": active.animation_seconds = 0.7*animation_scale
	else: active.time_scale = animation_scale
	active.journey_requested.connect(advance)
	add_child(active); move_child(chrome,get_child_count()-1)
	home_button.position = Vector2(726,26) if kind == "chapter" else Vector2(489,27)
	home_button.size = Vector2(150,44) if kind == "chapter" else Vector2(104,44)
	if kind == "encounter":
		active.sound.enabled = not store.state.muted
		active.sound_slider.value = store.state.volume
		active.sound.set_volume(store.state.volume)
		active.mute_button.text = "声音 关" if store.state.muted else "声音 开"
		active.audio_settings_changed.connect(sync_encounter_audio)
	apply_audio(); get_window().title = "数字群岛 · 森林来信"
	active.modulate.a = 0
	var tween = create_tween(); tween.tween_property(active,"modulate:a",1.0,maxf(0.01,0.32*animation_scale))
	await tween.finished
	transition = false
	refresh_chrome()

func sync_encounter_audio(volume: float, enabled: bool) -> void:
	store.state.volume = volume; store.state.muted = not enabled
	store.save()
	refresh_chrome()

func persist_active() -> bool:
	if is_instance_valid(active): active.save()
	else: store.save()
	refresh_chrome()
	return store.error.is_empty()

func detach_active() -> void:
	remove_child(active); active.queue_free(); active = null; active_kind = ""
	home_button.visible = false; apply_audio()

func return_to_camp() -> void:
	if transition or not is_instance_valid(active) or active.busy: return
	if not persist_active(): return
	var homecoming = store.state.encounter.reward and not store.state.returned
	if homecoming:
		store.state.returned = true
		if not store.save(): store.state.returned = false; return
	detach_active(); show_camp()
	if homecoming:
		notice.text = "营地的新芽开花了。阿橙与你成为「共鸣伙伴」，石灵之约已记入手记。"
		sound.play_cue("reward")

func advance() -> void:
	if transition or not is_instance_valid(active) or active.busy: return
	if active_kind == "chapter":
		if active.state.stage != 3 or not persist_active(): return
		detach_active(); mount_stage("encounter")
	else:
		if active.state.reward: return_to_camp()

func retry_save() -> void:
	if transition or store.protected or (is_instance_valid(active) and active.busy): return
	if is_instance_valid(active):
		persist_active()
	else: store.save()
	if is_instance_valid(active) and active_kind == "encounter": active.refresh()
	refresh_chrome()

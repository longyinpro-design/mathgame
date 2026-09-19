extends Control
signal journey_requested
var journey_mode = false
const Rules = preload("res://scripts/chapter_rules.gd")
const Store = preload("res://scripts/chapter_store.gd")
const World = preload("res://scripts/forest_world.gd")
const INK = Color("f3e4c0")
const GOLD = Color("e5c679")
const TEAL = Color("6bc4b2")
const POINTS = [Vector2(354,230),Vector2(267,357),Vector2(180,484),Vector2(354,484),Vector2(528,484),Vector2(441,357)]
var store = Store.new()
var state: Dictionary
var world: Node2D
var ui: Control
var modal: Control
var mode: String = "world"
var busy: bool = false
var selected: int = -1
var history: Array = []
var target_x: float = 170
var pending: String = ""
var dialogue: Array = []
var dialogue_done: Callable
var dialogue_index: int = 0
var message: String = ""
var checked: bool = false
var light: Line2D
var slots_ui: Array = []
var status_label: Label
var save_warning: Label
var energy_labels: Array = []
var animation_seconds: float = 0.7

func _ready() -> void:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Heiti SC","Noto Sans CJK SC","Microsoft YaHei","PingFang SC"])
	var skin = Theme.new(); skin.default_font = font; skin.default_font_size = 21; theme = skin
	world = World.new(); add_child(world)
	save_warning = Label.new()
	save_warning.position = Vector2(32,585); save_warning.size = Vector2(1216,40)
	save_warning.z_index = 100; save_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_warning.add_theme_font_size_override("font_size",19)
	save_warning.add_theme_color_override("font_color",GOLD)
	save_warning.add_theme_color_override("font_outline_color",Color("071618"))
	save_warning.add_theme_constant_override("outline_size",8)
	add_child(save_warning)
	state = store.read_save()
	save_warning.text = store.error
	world.hero_x = state.x; target_x = state.x; world.fox_x = state.x-66
	world.bridge = 0 if state.stage == 0 else (0.5 if state.stage == 1 else 1)
	world.glow = 1 if state.stage > 0 else 0
	world.bloom = 1 if state.stage == 3 else 0
	show_world()
	if not state.intro:
		talk([
			["小岚 · 探险者","地图上的晨种村就在对岸。我们得把这袋种子送到村里。"],
			["阿橙 · 狐狸伙伴","桥怎么不见了？那边有人在挥手！先看看断桥，再问问他。"],
			["探索开始","点击地面行走，也可用 A / D 或左右方向键。点击发光标记，会走近查看。"]],finish_intro)

func finish_intro() -> void:
	state.intro = true
	save()

func save() -> void:
	state.x = clampi(roundi(world.hero_x),90,1150 if state.stage >= 2 else 700)
	store.write_save(state)
	save_warning.text = store.error

func _process(delta: float) -> void:
	if world == null: return
	if mode != "world" or busy:
		world.walking = false
		return
	var axis = 0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): axis -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): axis += 1
	if axis != 0:
		pending = ""
		target_x = clampf(world.hero_x+axis*100,90,1150 if state.stage >= 2 else 700)
	var distance = target_x-world.hero_x
	world.walking = absf(distance) > 2
	if world.walking:
		world.facing = 1 if distance > 0 else -1
		world.hero_x = move_toward(world.hero_x,target_x,210*delta)
		world.fox_x = move_toward(world.fox_x,world.hero_x-60*world.facing,185*delta)
	else:
		if int(state.x) != roundi(world.hero_x): save()
		if not pending.is_empty():
			var action = pending; pending = ""; interact(action)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE,KEY_ENTER] and mode == "dialogue": next_dialogue(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and not busy:
			if mode in ["puzzle","journal"]: show_world()
		elif event.keycode == KEY_E and mode == "world" and not busy:
			var closest = "stele" if world.hero_x < 440 else ("core" if world.hero_x < 640 else "bridge")
			if world.hero_x > 990 and state.stage >= 2: closest = "gate"
			go_to(closest)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and mode == "world" and not busy:
		if event.position.y > 160 and event.position.y < 540:
			pending = ""; target_x = clampf(event.position.x,90,1150 if state.stage >= 2 else 700)

func clear_ui() -> void:
	if is_instance_valid(ui): remove_child(ui); ui.queue_free()
	ui = Control.new(); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)

func panel(rect: Rect2, color: Color = Color("152e30"), parent: Control = null) -> Panel:
	var p = Panel.new(); p.position = rect.position; p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box = StyleBoxFlat.new(); box.bg_color = color; box.border_color = Color("6f805a"); box.set_border_width_all(2); box.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel",box); (parent if parent != null else ui).add_child(p); return p

func text_at(text: String, rect: Rect2, size_px: int = 21, color: Color = INK) -> Label:
	var l = Label.new(); l.clip_text = true; l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.add_theme_color_override("font_color",color); l.add_theme_font_size_override("font_size",size_px)
	l.text = text; l.position = rect.position; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(l); l.size = Vector2(rect.size.x,maxf(rect.size.y,size_px*1.6)); return l

func button(text: String, rect: Rect2, action: Callable, disabled: bool = false, active: bool = false) -> Button:
	var b = Button.new(); b.text = text; b.position = rect.position; b.size = rect.size; b.disabled = disabled
	for key in ["normal","hover","pressed","focus","disabled"]:
		var box = StyleBoxFlat.new(); box.bg_color = Color("234641") if not active else Color("457763")
		if key == "hover": box.bg_color = Color("3c6657")
		if key == "disabled": box.bg_color = Color("243332")
		box.border_color = GOLD if key == "focus" or active else Color("738261"); box.set_border_width_all(2); box.set_corner_radius_all(6)
		b.add_theme_stylebox_override(key,box)
	b.add_theme_color_override("font_color",INK); b.add_theme_color_override("font_disabled_color",Color("96a59a"))
	b.pressed.connect(action); ui.add_child(b); return b

func show_world() -> void:
	mode = "world"; selected = -1; clear_ui()
	panel(Rect2(24,22,650,88),Color(0.04,0.12,0.13,0.88))
	text_at("第一章   /   森林的另一边",Rect2(44,33,590,30),23,GOLD)
	var goal = "查看断桥、石碑与守桥人的线索  ·  %d / 3" % state.clues.size()
	if Rules.unlocked(state): goal = "修复供能台，让三条线路同时亮起"
	if state.stage == 1: goal = "远端接通了！回到供能台，用两次交换调整线路"
	if state.stage == 2: goal = "桥已修复 · 带阿橙走过桥，把种子送到村口"
	if state.stage == 3: goal = "种子已送达 · 森林重新苏醒"
	text_at(goal,Rect2(44,70,606,30),19)
	button("线索笔记  %d/3" % state.clues.size(),Rect2(1000,24,254,52),show_journal)
	if state.stage < 2:
		hotspot("stele","旧石碑",Vector2(326,234),state.clues.has("stele"))
		hotspot("core","供能台",Vector2(605,232),state.stage > 0)
		hotspot("bridge","断桥",Vector2(703,408),state.clues.has("bridge"))
		hotspot("keeper","呼喊守桥人",Vector2(1060,272),state.clues.has("keeper"))
	else:
		hotspot("gate","送达种子" if state.stage == 2 else "晨种村",Vector2(1150,234),state.stage == 3)
		hotspot("core","回望遗迹",Vector2(605,232),true)
	panel(Rect2(24,626,1232,70),Color(0.04,0.12,0.13,0.88))
	text_at(message if not message.is_empty() else "点击地面行走  ·  A / D 或 ← / → 移动  ·  点击标记查看  ·  E 与附近物件互动",Rect2(44,642,1190,43),20)
	if state.stage == 3: button("章节回忆",Rect2(1000,90,254,48),ending)

func hotspot(id: String, title: String, pos: Vector2, found: bool) -> void:
	button(("◇ " if not found else "✓ ")+title,Rect2(pos-Vector2(74,22),Vector2(148,44)),go_to.bind(id))

func go_to(id: String) -> void:
	if busy or mode != "world": return
	pending = id
	target_x = {"stele":330,"core":600,"bridge":698,"keeper":690,"gate":1130}[id]

func interact(id: String) -> void:
	if busy: return
	if id == "core":
		if state.stage >= 2: talk([["小岚","三条光路稳定地亮着。该把种子送到村里了。"]]); return
		if not Rules.unlocked(state): talk([["阿橙","先别乱动。看看断桥和石碑，再问问守桥人：我们得知道机关在给什么供能。"]]); return
		open_puzzle(); return
	if id == "gate":
		if state.stage == 2: finish_chapter()
		elif state.stage == 3: ending()
		return
	if not state.clues.has(id): state.clues.append(id); save()
	match id:
		"stele": talk([["旧石碑 · 线索已记入笔记","六块数字石各用一次。起桥时，每条边要有 10 格能量。顶点同时连接两条光路。"],["小岚","三个边合起来会数到 30，但六块石头合起来只有 21。多出的能量，是哪些石头贡献的？"]])
		"bridge": talk([["阿橙","十二节桥板都收进了岩壁。近岸和远岸各需要一半能量。"],["桥边铭牌 · 线索已记入笔记","先唤醒近岸，再接通远岸。远端接通后，三条线路的需求会改变；剩余能量只够交换两次石头。"]])
		"keeper": talk([["守桥人 · 从对岸传来的声音","你们带来种子了！村里的苗圃正等着呢。供能台上的六块石头还在，先让三条线路同时亮起！"],["守桥人 · 线索已记入笔记","每次摆好后拉下供能杆，观察光停在哪里。失败不会毁掉石头，别急着乱换，先想好每条边。"]])

func talk(lines: Array, done: Callable = Callable()) -> void:
	mode = "dialogue"; pending = ""; dialogue = lines; dialogue_index = 0; dialogue_done = done; target_x = world.hero_x
	draw_dialogue()

func draw_dialogue() -> void:
	clear_ui()
	panel(Rect2(56,470,1168,214),Color(0.04,0.12,0.13,0.97))
	text_at(dialogue[dialogue_index][0],Rect2(88,490,1040,38),24,GOLD)
	var body = text_at(dialogue[dialogue_index][1],Rect2(88,539,1090,94),24)
	body.visible_ratio = 0
	create_tween().tween_property(body,"visible_ratio",1.0,0.5)
	button("继续  →" if dialogue_index < dialogue.size()-1 else "出发  →",Rect2(1000,631,190,42),next_dialogue)
	text_at("%d / %d  ·  空格继续" % [dialogue_index+1,dialogue.size()],Rect2(88,640,700,28),17)

func next_dialogue() -> void:
	if mode != "dialogue": return
	dialogue_index += 1
	if dialogue_index < dialogue.size(): draw_dialogue(); return
	var done = dialogue_done; dialogue_done = Callable()
	show_world()
	if done.is_valid(): done.call()

func show_journal() -> void:
	if busy: return
	mode = "journal"; target_x = world.hero_x; pending = ""; clear_ui()
	panel(Rect2(120,105,1040,520),Color("182f30"))
	text_at("旅途笔记",Rect2(160,135,900,54),36,GOLD)
	var notes = {"stele":"石碑：三边总计 30，六石总计 21。顶点被光路照到两次。顶点合计应该是多少？","bridge":"桥边：近岸唤醒后，远岸的三条需求会变化。届时最多交换两次；先计划，再搬石。","keeper":"守桥人：数字石每个只用一次。拉下供能杆才开始；观察每条线路，失败后可以撤销或重新规划。"}
	var y = 212
	for key in ["stele","bridge","keeper"]:
		text_at(notes[key] if state.clues.has(key) else "◇ 尚未找到这条线索，回到遗迹继续观察。",Rect2(160,y,940,82),23,INK if state.clues.has(key) else Color("92a49b"))
		y += 104
	button("合上笔记",Rect2(902,553,214,48),show_world)

func open_puzzle() -> void:
	if busy or state.stage >= 2 or not Rules.unlocked(state): return
	mode = "puzzle"; target_x = world.hero_x; selected = -1; message = ""; checked = false; history.clear(); draw_puzzle()

func draw_puzzle() -> void:
	clear_ui(); slots_ui.clear(); energy_labels.clear()
	var shade = ColorRect.new(); shade.color = Color(0.02,0.07,0.08,0.82); shade.size = Vector2(1280,720); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.add_child(shade)
	panel(Rect2(28,24,750,670),Color("172e2c")); panel(Rect2(796,24,456,670),Color("14292a"))
	text_at("供 能 石 阵",Rect2(58,43,540,49),32,GOLD)
	text_at("Ⅰ  唤醒近岸" if state.stage == 0 else "Ⅱ  接通远岸 · 最多交换两次",Rect2(58,94,680,38),23)
	button("离开机关",Rect2(1081,43,145,44),leave_puzzle)
	var room = TextureRect.new(); var atlas = AtlasTexture.new(); atlas.atlas = preload("res://assets/source/chapter-rooms-v1.png"); atlas.region = Rect2(16,26,485,470)
	room.texture = atlas; room.position = Vector2(77,158); room.size = Vector2(556,420); room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; room.modulate = Color(0.7,0.78,0.66,0.28); room.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.add_child(room)
	var track = Line2D.new(); track.points = PackedVector2Array([POINTS[0],POINTS[2],POINTS[4],POINTS[0]]); track.width = 14; track.default_color = Color("273d36"); ui.add_child(track)
	var inner = Line2D.new(); inner.points = track.points; inner.width = 3; inner.default_color = Color("8d8856"); ui.add_child(inner)
	light = Line2D.new(); light.width = 6; light.default_color = TEAL; ui.add_child(light)
	var targets = Rules.targets(state)
	var positions = [Vector2(67,337),Vector2(274,531),Vector2(538,337)]
	for i in range(3):
		var title = ["左路","底路","右路"][i]
		energy_labels.append(text_at("%s\n需求 %d" % [title,targets[i]],Rect2(positions[i],Vector2(154,90)),22,GOLD))
	for i in range(6):
		var value = state.slots[i]
		var active = selected == (value if state.stage == 0 else i)
		var b = button(str(value) if value else "◇",Rect2(POINTS[i]-Vector2(34,32),Vector2(68,64)),select_slot.bind(i),false,active)
		b.add_theme_font_size_override("font_size",30); slots_ui.append(b)
	if state.stage == 0:
		text_at("石袋",Rect2(55,613,58,38),19)
		for n in range(1,7): button(str(n),Rect2(122+(n-1)*98,606,75,57),select_stone.bind(n),state.slots.has(n),selected == n)
	else:
		text_at("剩余交换  %d / 2" % (2-state.swaps.size()),Rect2(69,615,620,44),25,GOLD)
	text_at("先观察，再供能",Rect2(823,112,396,42),28,GOLD)
	var task = "六石各用一次，让三边同时达到需求。\n摆好再供能，观察每条光路。" if state.stage == 0 else "远端负载改变了。保留当前六石，用最多两次交换满足三条新需求。\n点两块石头进行一次交换。"
	text_at(task,Rect2(823,165,397,122),23)
	button("撤销",Rect2(823,302,118,49),undo,history.is_empty())
	button("重新规划",Rect2(951,302,145,49),reset_board)
	button("提示",Rect2(1106,302,118,49),give_hint,state.hints[state.stage] >= 3)
	var hints = hint_lines()
	var h = state.hints[state.stage]
	text_at("阿橙的观察  %d / 3" % h,Rect2(823,374,393,32),19,TEAL)
	text_at(hints[h-1] if h > 0 else "“石碑和桥边的铭牌都记在笔记里了。别急着拉杆，先想想这次移动会影响哪两条边。”",Rect2(823,416,396,105),22)
	status_label = text_at(message,Rect2(823,527,396,89),20,GOLD)
	button("拉下供能杆  →",Rect2(823,624,400,48),run_power,state.slots.has(0))

func leave_puzzle() -> void:
	if busy: return
	message = "进度已留在机关上，随时可以回来。"; save(); show_world()

func hint_lines() -> Array:
	if state.stage == 0:
		return ["把三条边的需求相加：30。六石合计21。哪三个位置被算了两次？","30－21＝9，所以三个顶点合计9。先安排顶点，再补每条边的中间。","可以让1、3、5占据顶点。每条边还缺多少？用剩下的2、4、6补齐。"]
	return ["先比较三条新需求。交换一块顶点石时，会同时影响两条光路。","可以先在纸上圈出两对要交换的石头，再检查最终三条边。撤销和重新规划不会消耗额外机会。","一个可行方向：将顶点A与左边中点交换，再将底边中点与右边中点交换。槽位A在最上方。"]

func give_hint() -> void:
	if busy or state.stage >= 2: return
	state.hints[state.stage] = mini(3,state.hints[state.stage]+1); save(); draw_puzzle()

func select_stone(n: int) -> void:
	if busy or mode != "puzzle" or state.stage != 0 or state.slots.has(n): return
	selected = n; draw_puzzle()

func remember() -> void:
	history.append({"slots":state.slots.duplicate(),"swaps":state.swaps.duplicate(true)})
	if history.size() > 60: history.pop_front()

func select_slot(index: int) -> void:
	if busy or mode != "puzzle": return
	if selected == -1:
		if state.slots[index] == 0: return
		selected = state.slots[index] if state.stage == 0 else index; draw_puzzle(); return
	if state.stage == 0:
		var from = state.slots.find(selected)
		if from == index: selected = -1; draw_puzzle(); return
		remember()
		if from >= 0: state.slots[from] = state.slots[index]
		state.slots[index] = selected
		var start = POINTS[from] if from >= 0 else Vector2(160+(selected-1)*98,632)
		var value = selected; selected = -1; checked = false; message = ""; save()
		await animate_stone(value,start,POINTS[index])
	else:
		if selected == index: selected = -1; draw_puzzle(); return
		if state.swaps.size() >= 2:
			message = "这轮已交换两次。可以启动、撤销，或重新规划。"; selected = -1; draw_puzzle(); return
		remember()
		var from = selected; var n = state.slots[from]; state.slots[from] = state.slots[index]; state.slots[index] = n
		state.swaps.append([from,index]); selected = -1; checked = false; message = ""; save()
		await animate_stone(n,POINTS[from],POINTS[index])
	draw_puzzle()

func animate_stone(n: int, start: Vector2, finish: Vector2) -> void:
	busy = true
	var token = text_at(str(n),Rect2(start-Vector2(20,25),Vector2(50,55)),35,GOLD)
	var tween = create_tween(); tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(token,"position",(start+finish)/2-Vector2(20,62),animation_seconds*0.25)
	tween.tween_property(token,"position",finish-Vector2(20,25),animation_seconds*0.25)
	await tween.finished
	busy = false

func undo() -> void:
	if busy or history.is_empty(): return
	var prior = history.pop_back(); state.slots = prior.slots; state.swaps = prior.swaps
	selected = -1; checked = false; message = "已撤销，可以换一种计划。"; save(); draw_puzzle()

func reset_board() -> void:
	if busy: return
	remember(); state.slots = [0,0,0,0,0,0] if state.stage == 0 else state.origin.duplicate(); state.swaps = []
	selected = -1; checked = false; message = "已回到这一段的起点，线索和提示记录保留。"; save(); draw_puzzle()

func run_power() -> void:
	if busy or mode != "puzzle" or state.slots.has(0): return
	busy = true; selected = -1; state.attempts[state.stage] += 1; save()
	status_label.text = "能量正在沿三条光路传递……"
	var sums = Rules.edge_sums(state.slots); var targets = Rules.targets(state)
	var edges = [[0,1,2],[2,3,4],[4,5,0]]
	for i in range(3):
		var points = edges[i]
		light.clear_points(); light.add_point(POINTS[points[0]]); light.add_point(POINTS[points[0]])
		light.default_color = TEAL if sums[i] == targets[i] else Color("df9470")
		var tween = create_tween()
		tween.tween_method(func(t: float): light.set_point_position(1,POINTS[points[0]].lerp(POINTS[points[2]],t)),0.0,1.0,animation_seconds)
		await tween.finished
		energy_labels[i].text = "%s  %d / %d\n%s" % [["左路","底路","右路"][i],sums[i],targets[i],"稳定" if sums[i] == targets[i] else ("能量不足" if sums[i] < targets[i] else "能量过载")]
	checked = true
	if not Rules.powered(state):
		message = "光路停下了。观察不足或过载的边，想好再换石。"; status_label.text = message; busy = false; return
	status_label.text = "三条光路同时亮起！桥梁正在回应……"
	if state.stage == 0:
		state.origin = state.slots.duplicate(); state.stage = 1; state.swaps = []
	else: state.stage = 2
	save()
	show_world(); busy = true
	var t = create_tween(); t.set_parallel(true)
	t.tween_property(world,"bridge",0.5 if state.stage == 1 else 1.0,animation_seconds*3)
	t.tween_property(world,"glow",1.0,animation_seconds*2)
	await t.finished; busy = false
	if state.stage == 1:
		var targets2 = Rules.targets(state)
		talk([["阿橙","桥伸出来了！可是……只到一半。远端的三个指示灯亮起来了！"],["守桥人","现在左路需要%d，底路需要%d，右路需要%d。石头不必取下，剩余能量只够交换两次。先想好两对石头！" % targets2]],Callable())
	else:
		talk([["阿橙","桥接上了！这一次，每条光路都刚刚好。带我和种子一起去村口吧！"]])

func finish_chapter() -> void:
	if busy or state.stage != 2: return
	busy = true; world.walking = true
	var t = create_tween(); t.set_parallel(true)
	t.tween_property(world,"fox_x",1100.0,animation_seconds*2)
	t.tween_property(world,"bloom",1.0,animation_seconds*3)
	await t.finished
	state.stage = 3; save(); busy = false
	var next_line = "守桥人说古林里还有一位石灵。带上刚才的发现，我们去认识它吧。" if journey_mode else "下一站是晨种村！不过今天，我们可以先在这里歇一会儿。"
	talk([["守桥人","种子到了！看，第一株小芽已经探出头了。谢谢你们把森林两边重新连在一起。"],["小岚","我发现了：同一块石头放在顶点，会同时改变两条路。先想清楚关系，再动手，真的不一样。"],["阿橙",next_line]],ending)

func ending() -> void:
	mode = "ending"; clear_ui()
	panel(Rect2(288,125,704,470),Color(0.04,0.12,0.13,0.96))
	text_at("森林的另一边",Rect2(338,166,610,70),43,GOLD)
	text_at("种子已送达 · 晨种村的路重新打开",Rect2(338,247,610,55),25)
	text_at("你让六块数字石为不同的线路供能，\n也让一座沉睡的桥重新连接了伙伴。",Rect2(338,315,610,83),24)
	text_at("尝试 %d 次  ·  使用提示 %d 层" % [state.attempts[0]+state.attempts[1],state.hints[0]+state.hints[1]],Rect2(338,422,610,68),19,TEAL)
	button("留在森林",Rect2(338,523,260,48),show_world)
	if journey_mode:
		button("前往古林遗迹  →",Rect2(623,523,316,48),func(): journey_requested.emit())
	else: button("重新开启这段旅程",Rect2(623,523,316,48),confirm_restart)

func confirm_restart() -> void:
	if journey_mode: return
	mode = "confirm"; clear_ui(); panel(Rect2(300,230,680,245))
	text_at("重新探索会替换本章节的进度。\n旧版两关试玩的记录会保留。",Rect2(336,265,605,96),25)
	button("返回",Rect2(336,389,240,52),ending)
	button("确认重新探索",Rect2(600,389,340,52),restart)

func restart() -> void:
	if journey_mode: return
	state = Rules.fresh(); world.hero_x = 170; world.fox_x = 104; target_x = 170; world.bridge = 0; world.bloom = 0; world.glow = 0
	message = ""; pending = ""; history.clear(); save(); show_world()
	talk([["小岚","我们带着种子再次抵达森林遗迹。先去看看断桥吧。"]],finish_intro)

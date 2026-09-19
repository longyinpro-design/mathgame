extends Control
const Rules = preload("res://scripts/puzzle.gd")
const Store = preload("res://scripts/save_store.gd")
const INK = Color("f3e4c0")
const GOLD = Color("d7ad55")
const TEAL = Color("438c91")
var store = Store.new()
var levels: Dictionary = {}
var definitions: Dictionary = {}
var state: Dictionary = {}
var history: Array = []
var selected: int = 0
var message: String = ""
var screen: Control
var board_points = [Vector2(380,220),Vector2(290,350),Vector2(200,480),Vector2(380,480),Vector2(560,480),Vector2(470,350)]

func _ready() -> void:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei"])
	var skin = Theme.new()
	skin.default_font = font
	skin.default_font_size = 22
	theme = skin
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://docs/首章关卡-v1.json"))
	for entry in data.levels:
		if entry.id in ["F12","F07"]: definitions[entry.id] = entry
	levels = store.read_save()
	show_map()

func panel(rect: Rect2, color: Color) -> void:
	var p = Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("789c59")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	p.add_theme_stylebox_override("panel", style)
	screen.add_child(p)

func label_at(text: String, rect: Rect2, font_size: int = 22, color: Color = INK) -> Label:
	var l = Label.new()
	l.clip_text = true
	l.text = text
	l.position = rect.position
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size = rect.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(l)
	return l

func button(text: String, rect: Rect2, action: Callable, disabled: bool = false, active: bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.disabled = disabled
	for mode in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("263f42") if not active else TEAL
		if mode == "hover": style.bg_color = Color("42605a")
		if mode == "pressed": style.bg_color = TEAL
		if mode == "disabled": style.bg_color = Color("273032")
		style.border_color = GOLD if mode == "focus" or active else Color("789c59")
		style.set_border_width_all(3 if mode == "focus" else 2)
		style.set_corner_radius_all(8)
		b.add_theme_stylebox_override(mode, style)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_disabled_color", Color("a7b7ae"))
	b.pressed.connect(action)
	screen.add_child(b)
	return b

func base() -> void:
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var bg = TextureRect.new()
	bg.texture = preload("res://assets/source/world-map-v1.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	var shade = ColorRect.new()
	shade.color = Color(0.04,0.10,0.12,0.70)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)

func show_map() -> void:
	state = {}
	base()
	label_at("数 字 群 岛", Rect2(80,65,900,70), 52, GOLD)
	label_at("森林遗迹  /  两关探索试玩", Rect2(84,145,800,45), 25)
	label_at("修复沉睡的机关，点亮通往下一座岛的路。", Rect2(84,207,1000,45))
	var ids = ["F12","F07"]
	for i in range(2):
		var id: String = ids[i]
		var x = 84 + i*566
		panel(Rect2(x,295,530,255), Color("172f32"))
		label_at("0%d  /  %s" % [i+1,definitions[id].title], Rect2(x+26,316,480,50), 30, GOLD)
		var status = "尚未探索"
		if levels.has(id): status = "已点亮 · " + ("借助提示" if levels[id].hint > 0 else "独立完成") if Rules.solved(levels[id]) else "探索中 · 可继续"
		label_at(status,Rect2(x+26,377,470,40))
		button("进入遗迹  →", Rect2(x+26,454,478,64), enter.bind(id))
	label_at("点击数字石，再点击槽位；也可以用 Tab 与空格操作。进度自动保存。", Rect2(84,595,1130,45), 20)
	if not store.error.is_empty(): label_at(store.error,Rect2(84,644,1130,45),20,GOLD)

func enter(id: String) -> void:
	state = levels.get(id, Rules.fresh(id)).duplicate(true)
	history.clear()
	selected = 0
	message = ""
	render()

func remember() -> void:
	history.append(state.duplicate(true))
	if history.size() > 100: history.pop_front()

func save() -> void:
	levels[state.id] = state.duplicate(true)
	store.write_save(levels)

func change_slot(index: int) -> void:
	if Rules.solved(state): return
	remember()
	if selected == 0:
		selected = int(state.slots[index])
		state.slots[index] = 0
	else:
		var previous = state.slots.find(selected)
		if previous >= 0: state.slots[previous] = state.slots[index]
		state.slots[index] = selected
		selected = 0
	message = ""
	save()
	render()

func choose(n: int) -> void:
	selected = n
	render()

func undo() -> void:
	if history.is_empty(): return
	var hints = state.hint
	state = history.pop_back()
	state.hint = maxi(int(hints),int(state.hint))
	selected = 0
	message = "已撤销上一步。"
	save()
	render()

func reset_level() -> void:
	remember()
	var hints = state.hint
	state = Rules.fresh(state.id)
	state.hint = hints
	selected = 0
	message = "机关已复位。"
	save()
	render()

func hint() -> void:
	if Rules.solved(state): return
	state.hint = mini(3,int(state.hint)+1)
	save()
	render()

func adjust(amount: int) -> void:
	remember()
	state.input = clampi(int(state.input)+amount,0,20)
	state.ran = false
	message = ""
	save()
	render()

func reverse_step(key: String) -> void:
	var expected = ["add4","div2","sub5"]
	if key != expected[state.reverse.size()]:
		message = "先撤销最靠近输出端的操作，再向左还原。"
		render()
		return
	remember()
	state.reverse.append(key)
	message = "还原了一步！观察上方的数值变化。"
	save()
	render()

func run_machine() -> void:
	remember()
	state.ran = true
	message = "输出为 %d，目标为 18；调整输入后再试试。" % Rules.forward(int(state.input))[3]
	if state.input == 6 and state.reverse.size() < 3: message = "输出正确！再完成逆序还原，说明输入是怎样得到的。"
	save()
	render()

func render() -> void:
	base()
	button("← 群岛",Rect2(34,25,150,54),show_map)
	label_at(definitions[state.id].title,Rect2(220,26,760,54),34,GOLD)
	label_at("森林遗迹 / " + state.id,Rect2(980,30,265,45),20)
	panel(Rect2(34,100,735,580),Color("142d30"))
	panel(Rect2(789,100,457,580),Color("203837"))
	label_at("修复目标",Rect2(815,120,400,35),24,GOLD)
	label_at(definitions[state.id].brief,Rect2(815,165,400,100),23)
	if state.id == "F12": triangle()
	else: machine()
	button("撤销",Rect2(815,293,122,54),undo,history.is_empty())
	button("重置",Rect2(950,293,122,54),reset_level)
	button("提示 %d/3" % int(state.hint),Rect2(1085,293,134,54),hint,state.hint >= 3 or Rules.solved(state))
	var hint_text = "观察机关，先试着操作。\n需要帮助时，点开一层提示。"
	if state.hint > 0:
		hint_text = ""
		for i in range(int(state.hint)): hint_text += "%d. %s\n" % [i+1,definitions[state.id].hints[i]]
	label_at(hint_text,Rect2(815,367,404,170),21)
	if Rules.solved(state):
		label_at("机关已点亮！",Rect2(815,530,404,44),30,GOLD)
		label_at("借助提示完成" if state.hint > 0 else "本次独立完成",Rect2(815,576,404,30),20)
		button("前往倒流机器 →" if state.id == "F12" else "回到群岛 · 查看成果",Rect2(815,617,404,48),enter.bind("F07") if state.id == "F12" else show_map)
	else:
		label_at(message,Rect2(815,540,404,80),20,GOLD)
	if not store.error.is_empty(): label_at(store.error,Rect2(40,681,1190,35),18,GOLD)

func triangle() -> void:
	label_at("让每条光路的三个数字之和都为 10",Rect2(64,119,680,44),24)
	var line = Line2D.new()
	line.points = PackedVector2Array([board_points[0],board_points[2],board_points[4],board_points[0]])
	line.width = 7
	line.default_color = GOLD if Rules.solved(state) else TEAL
	screen.add_child(line)
	for i in range(6):
		var n = int(state.slots[i])
		button(str(n) if n else "·",Rect2(board_points[i]-Vector2(34,30),Vector2(68,60)),change_slot.bind(i),Rules.solved(state),n == selected and n != 0)
	var totals = Rules.sums(state.slots)
	label_at("左边 %d / 10" % totals[0],Rect2(65,320,155,40),21,GOLD)
	label_at("右边 %d / 10" % totals[2],Rect2(584,320,175,40),21,GOLD)
	label_at("底边 %d / 10" % totals[1],Rect2(300,524,240,40),21,GOLD)
	for n in range(1,7):
		button(str(n),Rect2(104+(n-1)*96,591,76,58),choose.bind(n),Rules.solved(state),selected == n)
	label_at("先选数字再点槽位；点已填槽位可取回，换位时自动交换。",Rect2(62,165,680,36),18)

func machine() -> void:
	label_at("① 从输出端倒着还原",Rect2(64,121,660,44),25,GOLD)
	var trail = "18"
	var values = [22,11,6]
	var names = ["＋4","÷2","－5"]
	for i in range(state.reverse.size()): trail += "  →  %s  →  %d" % [names[i],values[i]]
	label_at(trail,Rect2(65,180,675,80),25)
	var keys = ["sub5","add4","div2"]
	var labels = ["减去 5","加回 4","平分成 2 份"]
	for i in range(3): button(labels[i],Rect2(65+i*226,272,210,58),reverse_step.bind(keys[i]),state.reverse.has(keys[i]) or Rules.solved(state))
	label_at("② 放入输入，看看每一步的结果",Rect2(64,360,675,45),25,GOLD)
	button("－",Rect2(65,424,68,60),adjust.bind(-1),state.input <= 0 or Rules.solved(state))
	label_at(str(int(state.input)),Rect2(161,424,80,60),35)
	button("＋",Rect2(260,424,68,60),adjust.bind(1),state.input >= 20 or Rules.solved(state))
	button("启动机器 →",Rect2(378,424,352,60),run_machine,Rules.solved(state))
	label_at("输入范围 0～20  /  加 5 → 翻倍 → 减 4",Rect2(65,502,665,38),21)
	if state.ran:
		var v = Rules.forward(int(state.input))
		label_at("%d  →  %d  →  %d  →  %d" % v,Rect2(65,562,665,65),34,GOLD)
	else: label_at("启动后，这里会显示每一步的结果。",Rect2(65,568,665,65),21)

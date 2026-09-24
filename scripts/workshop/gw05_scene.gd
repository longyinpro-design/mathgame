extends "res://scripts/market/level_host.gd"
# GW05 装配间「七拍能做完吗」：三件工具各先钻孔再抛光，一台钻机一台抛光机。
# 玩家排的是两条工序带上的先后顺序；完成时刻由顺序现算，画面不替玩家记时刻。
const Rules = preload("res://scripts/workshop/gw05_rules.gd")
const World = preload("res://scripts/workshop/gw05_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：三件工具都在第 0 拍就绪，每一件都得先钻孔、再抛光。",
	"小岚：一台钻机、一台抛光机，每台一次只做一件，中途不能换手，也不能停下来等。",
	"嗒嗒：机间暂存放得下，随便堆。可第 7 拍一过就要全部交出去——做得到吗？"]
const AFTER = ["小岚：抛光机一共要忙 1+3+2=6 拍，最早也要等第一件钻完才能开工，所以第 7 拍本来就是下限。",
	"嗒嗒：先钻 C 只花 1 拍，正好让抛光机从第 1 拍就有活干；要是先做钻得最久的 A，抛光机只能干等着。",
	"小岚：想让抛光机一刻不停，钻孔带就得按抛光带需要的顺序喂料。"]
const TRACK_NAMES = ["钻孔带","抛光带"]
const TRACK_KEYS = [KEY_1,KEY_2]
const TOOL_KEYS = [KEY_Q,KEY_W,KEY_E]
var gw_pending_feedback = ""
var track = 0

func configure() -> void:
	scene_id = "assembly"; level_id = "GW05"; title = "七拍能做完吗"
	if save_path.is_empty(): save_path = Catalog.save_path("GW05")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"trial":3.8,"delivery":3.2}
	zoom_stages = []
	track = 0

func _ready() -> void:
	super._ready()
	get_window().title = "齿轮工坊 · GW05 七拍能做完吗"

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func chapter_label() -> String: return "齿轮工坊"

func goal_line() -> String: return "三件都先钻后抛 · 第 %d 拍结束前做完"%Rules.DEADLINE
func status_line() -> String:
	# 底栏这一格只有 300 像素宽：完工拍数写在现场的牌子上，这里只说两条带排了几件。
	return "钻孔带 %d/3 · 抛光带 %d/3"%[state.drill.size(),state.polish.size()]
func submit_label() -> String: return "试运行 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "看看工序带","approach":"铺开两条工序带",
		"ready":"开始排工序","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装配间","重新体验"]
func reset_prompt() -> Array: return ["把两条工序带全部清空？\n本次试运行与求助次数仍保留。","继续排工序","全部清空"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "两条工序带铺开了：钻孔带和抛光带各从第 0 拍排到第 %d 拍。"%Rules.DEADLINE
		"ready": return "先把三件工具在钻孔带上排一遍顺序，再排抛光带上的顺序。"
		"puzzle": return "同一台机上的工序不能重叠，抛光也不能早于这一件钻完。"
		"trial": return "按这个顺序跑一遍：钻机一件接一件，抛光机等着接得上……"
		"delivery": return "三件工具都在第 %d 拍前抛光完，正好卡着下限交出去。"%Rules.DEADLINE
		"aftermath": return AFTER[state.beat]
		"complete": return "先算清下限，再让每台机都别空等。"
	return ""

func build() -> void:
	for index in range(2):
		var id = "track_%d"%index
		add_button(id,TRACK_NAMES[index],track_rect(index),select_track.bind(index))
		buttons[id].tooltip_text = "把下一件排到%s · 键盘 %d"%[TRACK_NAMES[index],index+1]
		UIStyle.style_button(buttons[id],index == track)
	for tool in range(Rules.TOOLS):
		var id = "tool_%d"%tool
		add_button(id,"%s · 钻%d 抛%d"%[Rules.NAMES[tool],Rules.DRILL[tool],Rules.POLISH[tool]],
			tool_rect(tool),put_tool.bind(tool))
		buttons[id].tooltip_text = "把 %s 排到%s末尾 · 键盘 %s"%[Rules.NAMES[tool],TRACK_NAMES[track],
			["Q","W","E"][tool]]
	for index in range(state.drill.size()):
		var tool = state.drill[index]
		add_hotspot("drill_%d"%index,world.block_rect(0,index),take_back.bind(0,tool),
			"钻孔带第 %d 件 %s · 点一下取下来重排"%[index+1,Rules.NAMES[tool]])
	for index in range(state.polish.size()):
		var tool = state.polish[index]
		add_hotspot("polish_%d"%index,world.block_rect(1,index),take_back.bind(1,tool),
			"抛光带第 %d 件 %s · 点一下取下来重排"%[index+1,Rules.NAMES[tool]])

func track_rect(index: int) -> Rect2:
	return Rect2(24+index*156,548,146,46)
func tool_rect(tool: int) -> Rect2:
	return Rect2(360+tool*186,548,176,46)

func extra() -> void:
	world.track = track
	add_button("journal","回看与发现",Rect2(1092,548,164,46),journal).disabled = transient > 0
	if state.stage != "puzzle": return
	sign_text("当前带：%s · 1/2 换带 · Q/W/E 放件 · R 取下最后一件"%TRACK_NAMES[track],Rect2(24,596,560,46),18)

func snapshot(v: Dictionary) -> Dictionary:
	return {"drill":v.drill.duplicate(),"polish":v.polish.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.drill = []; n.polish = []; return n

func select_track(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	track = index; message = ""; refresh()

# 把一件工具排到当前选定的工序带末尾。
func put_tool(tool: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.place_tool(state,track,tool)
	if next.is_empty():
		message = "%s 已经排在%s上了：点带上的那块就能取下来重排。"%[Rules.NAMES[tool],TRACK_NAMES[track]]
		refresh(); return
	message = ""; commit_plan(next)

func take_back(index: int, tool: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.remove_tool(state,index,tool)
	if next.is_empty(): message = "这一件已经不在带上了。"; refresh(); return
	message = ""; commit_plan(next)

func drop_last() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var order = state.drill if track == 0 else state.polish
	if order.is_empty(): message = "%s上还没有排任何一件。"%TRACK_NAMES[track]; refresh(); return
	take_back(track,order[-1])

# 宿主同名的 place() 走的是另一套语义，这里另起一个名字提交排好的两条带。
func commit_plan(next: Dictionary) -> void:
	if state.stage != "puzzle" or modal or transient > 0 or next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	var previous_stage = state.stage
	super.apply_committed(candidate,next_history)
	if previous_stage == "trial" and candidate.stage == "puzzle":
		message = Rules.shortfalls(candidate)[0]; refresh()
	elif not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

# 两条带都排满才允许试运行：没排满时先说清缺几件，不进演出。
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle" and not Rules.ready(state):
		var n = state.duplicate(true); n.attempts = mini(1000000,n.attempts+1)
		gw_pending_feedback = Rules.shortfalls(state)[0]
		commit(n,history); return
	commit(Rules.advance(state),history)

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["钻机一共要忙 3+2+1=6 拍，抛光机一共要忙 1+3+2=6 拍；两条带都从第 0 拍起贴紧排。",
		"抛光最早也要等第一件钻完才能开工：钻孔最短的只有 C，1 拍就下钻机。",
		"抛光从第 1 拍开始，6 拍要一路不停排到第 7 拍；C 抛完正好第 3 拍，接着得挑一件第 3 拍前钻完的。",
		"完整示范：钻孔带 C 0–1、B 1–3、A 3–6；抛光带 C 1–3、B 3–6、A 6–7，正好第 7 拍完工。"]

func handle_key(key: int) -> bool:
	var slot = TRACK_KEYS.find(key)
	if slot >= 0: select_track(slot)
	elif key == KEY_R: drop_last()
	else:
		var tool = TOOL_KEYS.find(key)
		if tool < 0: return false
		put_tool(tool)
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,133,780,502),true)
	var text = "工序规则\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	text += "\n\n工时：A 钻3抛1；B 钻2抛3；C 钻1抛2。"
	text += "\n一台钻机、一台抛光机，一次一件，不能中断。"
	text += "\n三件第 0 拍就绪，都先钻孔再抛光。"
	text += "\n同一台机上的工序不能重叠，抛光不能早于钻完。"
	text += "\n两条带从第 0 拍起贴紧排，顺序决定开工拍。"
	text += "\n第 %d 拍结束前全部抛光完才算通过。"%Rules.DEADLINE
	if Rules.solved(state):
		text += "\n\n这一套：钻 %s，抛 %s，第 %d 拍完工。"%[order_text(state.drill),order_text(state.polish),Rules.makespan(state)]
	UIStyle.text(overlay,text,Rect2(290,161,700,389),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,569,225,48),close_modal,true,overlay).grab_focus()

func order_text(order: Array) -> String:
	var names = []
	for tool in order: names.append(Rules.NAMES[tool])
	return "、".join(names) if not names.is_empty() else "（空）"

# 空格是招牌动作：排满两条带后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

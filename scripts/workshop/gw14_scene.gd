extends "res://scripts/workshop/workshop_host.gd"
# GW14 装配间「第三张记录才有用」：维修盒里 20～80 枚标准件，三张复测记录都来自同一盒：
# 4 一托剩 3、6 一托剩 5、5 一托剩 2。前两张只留下五个共同候选，第三张才排除到 47。
# 列候选、复演与提交都先过规则模块的判据；按钮与键盘走同一套动作函数。
const Rules = preload("res://scripts/workshop/gw14_rules.gd")
const World = preload("res://scripts/workshop/gw14_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：维修盒里装着 20～80 枚标准件，盒盖上的三张记录是同一次复测。",
	"小岚：记录一：按 4 一托，满托之外还剩 3 枚。记录二：按 6 一托，还剩 5 枚。记录三：按 5 一托，还剩 2 枚。",
	"嗒嗒：三张都是同一盒、不取走物件。把盒里的枚数找出来，数量牌才写得准。"]
const AFTER = ["嗒嗒：47 枚！按 4 一托 11 个满托剩 3，按 6 一托 7 个满托剩 5，按 5 一托 9 个满托剩 2。",
	"小岚：只看前两张，23、35、47、59、71 都说得通；第三张一上来就把另外四个排除了。",
	"嗒嗒：数量牌挂好了。三张记录都留着——换盒复测时还要照着对。"]
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "rooftop"; level_id = "GW14"; title = "第三张记录才有用"
	if save_path.is_empty(): save_path = Catalog.save_path("GW14")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "20～80 枚 · 4 剩 3、6 剩 5、5 剩 2 · 找出同一盒枚数"
func status_line() -> String:
	if state.count < Rules.BOX_MIN: return "候选 未提出"
	var done = 0
	for record in range(3):
		if Rules.tested(state,record).has(state.count): done += 1
	return "候选 %d 枚 · 已复演 %d / 3 张"%[state.count,done]
func submit_label() -> String:
	if state.count < Rules.BOX_MIN: return "先提出候选 Space"
	return "核对三张记录 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向维修盒","ready":"开始列候选",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装配间","重新体验"]
func reset_prompt() -> Array: return ["把候选、三张复演记录和已列出的候选全部抹掉，从头查起？\n求助级别仍保留。","继续查看","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "维修盒推上台面，三张复测记录并排挂开。"
		"ready": return "先列候选，再看三种托的复演；三张记录都对得上才算数。"
		"puzzle":
			if state.count < Rules.BOX_MIN: return "盒里有 20～80 枚。先列候选，再挑一个枚数，用 4、6、5 三种托分别复演。"
			return "候选 %d 枚：三张记录都要复演过、都对得上，才能定下数量牌。"%state.count
		"delivery": return "按 47 枚复演：4 一托 11 个满托剩 3，6 一托 7 个满托剩 5，5 一托 9 个满托剩 2……"
		"aftermath": return AFTER[state.beat]
		"complete": return "只满足两条还不够：第三张记录才把候选定下来。"
	return ""

func build() -> void:
	for record in range(3):
		var listed = state.listed.has(record)
		add_button("list_%d"%record,"候选已列" if listed else "列候选",
			world.list_rect(record),list_candidates.bind(record)).disabled = listed or transient > 0
		add_button("replay_%d"%record,"复演 · %d 一托"%Rules.TRAYS[record],
			world.replay_rect(record),replay_record.bind(record)).disabled = state.count < Rules.BOX_MIN or transient > 0
		if not listed: continue
		var list = Rules.candidates(record)
		for index in range(list.size()):
			var count = list[index]
			var button = add_button("cand_%d_%d"%[record,count],str(count),
				world.chip_rect(record,index),select_count.bind(count),count == state.count)
			# 试过的候选牌按结论着色：任一记录不符就是被排除，三条都相符就是定下。
			if count != state.count: button.modulate = chip_tint(count)

func extra() -> void:
	add_button("journal","记录与排除",Rect2(786,654,124,46),journal).disabled = transient > 0

func chip_tint(count: int) -> Color:
	match Rules.chip_state(state,count):
		"排除": return Color("f0a598")
		"定下": return Color("a8e6ae")
	return Color.WHITE

func snapshot(v: Dictionary) -> Dictionary:
	return {"count":v.count,"listed":v.listed.duplicate(),"tested_first":v.tested_first.duplicate(),
		"tested_second":v.tested_second.duplicate(),"tested_third":v.tested_third.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true)
	n.count = 0; n.listed = []; n.tested_first = []; n.tested_second = []; n.tested_third = []
	return n

# 列候选：把一张记录在 20～80 里说得通的枚数摆上台面，并报一次清单。
func list_candidates(record: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.listed.has(record):
		message = "%s的候选已经列出来了。"%Rules.RECORD_NAMES[record]; refresh(); return
	var next = Rules.list(state,record)
	if next.is_empty(): return
	gw_pending_feedback = "%s的候选：%s。"%[Rules.RECORD_NAMES[record],candidate_brief(record)]
	place(next)

# 候选清单只报一次：太长就截到 8 个，剩下的用数量带过。
func candidate_brief(record: int) -> String:
	var list = Rules.candidates(record)
	var parts = []
	for count in list.slice(0,8): parts.append(str(count))
	var text = "、".join(parts)
	if list.size() > 8: text += "、…（共 %d 个）"%list.size()
	return text

func select_count(count: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	message = ""; place(Rules.select(state,count))

func step_count(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	place(Rules.move_count(state,delta))

# 复演一张记录：把当前候选记进这张记录的重演表，并当场说清余数对不对得上。
func replay_record(record: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.count < Rules.BOX_MIN:
		message = "先提出一个候选枚数，再复演记录。"; refresh(); return
	var next = Rules.replay(state,record)
	if next.is_empty(): return
	var parts = Rules.division(state.count,Rules.TRAYS[record])
	if parts[1] == Rules.REMAINDERS[record]:
		gw_pending_feedback = "%s复演：%d 枚按 %d 一托，装 %d 个满托、剩 %d 枚，与记录相符。"%[
			Rules.RECORD_NAMES[record],state.count,Rules.TRAYS[record],parts[0],parts[1]]
	else:
		gw_pending_feedback = "%s复演：%d 枚按 %d 一托，装 %d 个满托、剩 %d 枚；记录写的是剩 %d 枚，对不上。"%[
			Rules.RECORD_NAMES[record],state.count,Rules.TRAYS[record],parts[0],parts[1],Rules.REMAINDERS[record]]
	place(next)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["前两条都差一枚成整托：按 4 一托剩 3，按 6 一托剩 5，都是再补 1 枚就凑满整托。",
		"把前两条合起来：枚数加 1 要同时被 4 和 6 整除，也就是 12 的倍数；20～80 里只有 23、35、47、59、71。",
		"第三张一上来就能排除：这五个候选按 5 一托，23 剩 3、35 剩 0、59 剩 4、71 剩 1，只有 47 剩 2。",
		"47 枚：47 = 11×4 + 3 = 7×6 + 5 = 9×5 + 2。三张记录都吻合，才能写数量牌。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: step_count(-1)
	elif key == KEY_RIGHT or key == KEY_D: step_count(1)
	elif key == KEY_R: replay_record(0)
	elif key == KEY_T: replay_record(1)
	elif key == KEY_Y: replay_record(2)
	elif key == KEY_1: list_candidates(0)
	elif key == KEY_2: list_candidates(1)
	elif key == KEY_3: list_candidates(2)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "维修盒复测记录（盒中 20～80 枚）\n"
	text += "记录一：按 4 一托，满托之外还剩 3 枚。\n"
	text += "记录二：按 6 一托，满托之外还剩 5 枚。\n"
	text += "记录三：按 5 一托，满托之外还剩 2 枚。\n"
	text += "三张都是同一盒、不取走物件的复测；余数必须比每托枚数小。\n"
	text += "已列出的候选\n"
	if state.listed.is_empty(): text += "还没列过候选。\n"
	for record in state.listed:
		text += "%s：%s\n"%[Rules.RECORD_NAMES[record],candidate_brief(record)]
	text += "试过的候选\n"
	var tried = Rules.tried_counts(state)
	if tried.is_empty(): text += "还没复演过任何候选。\n"
	for count in tried.slice(0,3):
		var marks = []
		for record in range(3):
			marks.append("%s %s"%[Rules.RECORD_NAMES[record],Rules.verdict(state,record,count)])
		text += "%d 枚：%s\n"%[count," · ".join(marks)]
	if tried.size() > 3: text += "…还有 %d 个候选试过。\n"%(tried.size()-3)
	if state.stage in ["delivery","aftermath","complete"]:
		text += "47 = 11×4 + 3 = 7×6 + 5 = 9×5 + 2"
	UIStyle.text(overlay,text,Rect2(250,113,780,468),18,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,601,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：提出候选后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

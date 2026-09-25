extends "res://scripts/workshop/workshop_host.gd"
const Rules = preload("res://scripts/workshop/gw13_rules.gd")
const World = preload("res://scripts/workshop/gw13_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["小岚：休息桌上那两只旧玩具鸟，第 0 拍一起叫了一声。",
	"嗒嗒：甲每 4 拍叫一次、乙每 6 拍叫一次，都从第 0 拍算起；观察 0 到 24 拍，两端都算。",
	"小岚：同一拍两只一起叫，只算一个「听到叫声的时刻」。要数的是：总共几个时刻听到叫声，其中几个只有一只鸟叫。"]
const AFTER = ["嗒嗒：甲叫 7 次、乙叫 5 次；0、12、24 三拍两只一起叫，只能算一个时刻。",
	"小岚：所以听到叫声的时刻一共 9 个；其中只有一只鸟叫的有 6 个：4、6、8、16、18、20。",
	"嗒嗒：把重合的部分分清，同一拍就不会数两遍。小鸟留在休息桌，午休曲那边还等着排。"]
# 左下角是整行操作提示；小岚站在提示行上方、休息桌的左边。
func companion_foot() -> Vector2: return Vector2(990,620)
var gw_pending_feedback = ""
# 时间尺上指着的拍与正在改的数量行：只影响下一次按键，不进存档。
var cursor = 0
var count_row = 0

func configure() -> void:
	scene_id = "corridor"; level_id = "GW13"; title = "两只鸟，到底叫了几次"
	if save_path.is_empty(): save_path = Catalog.save_path("GW13")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []
	cursor = 0; count_row = 0

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "0～24 拍 · 同一拍只算一次 · 数总时刻与独鸣"
func status_line() -> String:
	if state.stage != "puzzle": return ""
	if state.heard < 0 or state.solo < 0: return "圈 %d 处 · 数量未填完"%state.marks.size()
	return "圈 %d · 总时刻 %d · 独鸣 %d"%[state.marks.size(),state.heard,state.solo]
func submit_label() -> String:
	if state.marks.is_empty(): return "先圈重合 Space"
	if state.heard < 0: return "先填总时刻 Space"
	if state.solo < 0: return "先填独鸣 Space"
	return "提交两个数量 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向休息桌","ready":"开始数叫声",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在休息桌","重新体验"]
func reset_prompt() -> Array: return ["把圈过的重合和两个数量全部抹掉，从头数起？\n求助级别仍保留。","继续数","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "两只旧玩具鸟被请到休息桌上，叫点和时间尺一起摆开。"
		"ready": return "先在时间尺上圈出两只鸟同拍的时刻，再提交两个数量。"
		"puzzle":
			if state.marks.is_empty(): return "0～24 拍都算。先在时间尺上圈出两只鸟同拍的时刻。"
			if state.heard < 0: return "重合圈好了：再填「总共几个时刻听到叫声」。"
			if state.solo < 0: return "再填「其中几个只有一只鸟叫」。"
			return "圈了 %d 处重合 · 总时刻 %s · 独鸣 %s，可以提交。"%[
				state.marks.size(),Rules.value_text(state.heard),Rules.value_text(state.solo)]
		"delivery": return "逐拍对照：甲 0、4、8、12、16、20、24；乙 0、6、12、18、24……"
		"aftermath": return AFTER[state.beat]
		"complete": return "同一拍只算一个时刻；重合要从两只鸟的次数里都扣掉。"
	return ""

func build() -> void:
	for tick in range(Rules.HORIZON+1):
		add_hotspot("tick_%d"%tick,world.tick_rect(tick),toggle_mark.bind(tick),
			"第 %d 拍：圈出 / 取消重合标记"%tick)
	for value in range(Rules.COUNT_MAX+1):
		add_button("heard_%d"%value,str(value),world.count_rect(0,value),
			set_count.bind(0,value),value == state.heard)
		add_button("solo_%d"%value,str(value),world.count_rect(1,value),
			set_count.bind(1,value),value == state.solo)

func extra() -> void:
	add_button("journal","叫点记录",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary:
	return {"marks":v.marks.duplicate(),"heard":v.heard,"solo":v.solo}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.marks = []; n.heard = -1; n.solo = -1; return n

func toggle_mark(tick: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	cursor = tick
	message = ""
	place(Rules.mark(state,tick))

func set_count(row: int, value: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	count_row = row
	message = ""
	place(Rules.set_count(state,row,value))

func step_count(row: int, delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	count_row = row
	place(Rules.step_count(state,row,delta))

func move_cursor(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	cursor = clampi(cursor+delta,0,Rules.HORIZON)
	refresh()

func switch_row(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	count_row = clampi(count_row+delta,0,1)
	refresh()

func hint_texts() -> Array:
	return ["两只鸟第 0 拍一起叫。同一拍不管几只鸟叫，都只算一个「听到叫声的时刻」。",
		"先在时间尺上把两只鸟同拍的时刻圈出来，再数总共几个时刻。",
		"总时刻 = 甲叫的时刻与乙叫的时刻合起来去重；独鸣 = 总时刻里减去重合的那些。",
		"总共 9 个时刻：0、4、6、8、12、16、18、20、24；其中独鸣 6 个：4、6、8、16、18、20。"]

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

# 提示那句话要等保存成功才说：中途失败重试后，话还是同一句。
func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: move_cursor(-1)
	elif key == KEY_RIGHT or key == KEY_D: move_cursor(1)
	elif key == KEY_M: toggle_mark(cursor)
	elif key == KEY_UP or key == KEY_W: switch_row(-1)
	elif key == KEY_DOWN or key == KEY_S: switch_row(1)
	elif key == KEY_Q: step_count(count_row,-1)
	elif key == KEY_E: step_count(count_row,1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "叫点记录\n两只旧玩具鸟第 0 拍一起叫：甲每 4 拍叫一次、乙每 6 拍叫一次。\n观察 0～24 拍，两端都算；同一拍两只一起叫，只算一个「听到叫声的时刻」。\n\n你圈的重合\n"
	if state.marks.is_empty(): text += "还没圈任何一拍。\n"
	else: text += "%s，共 %d 处。\n"%[Rules.tick_list(state.marks),state.marks.size()]
	text += "\n两个数量\n总共几个时刻听到叫声：%s\n其中几个只有一只鸟叫：%s\n"%[
		Rules.value_text(state.heard),Rules.value_text(state.solo)]
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n甲叫 7 次：0、4、8、12、16、20、24；乙叫 5 次：0、6、12、18、24。\n0、12、24 三拍两只一起叫：不同时刻 9 个，独鸣 6 个。\n重复的部分要分清，小鸟留在休息桌。"
	UIStyle.text(overlay,text,Rect2(250,121,780,440),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 光标也要跟着刷新传给画面，金圈才画在正确的列上。
func refresh() -> void:
	super()
	if is_instance_valid(world): world.cursor = cursor

# 空格是招牌动作：圈好重合、填好数量后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

extends "res://scripts/workshop/workshop_host.gd"
# GW07 装配间「检修前，先留好位置」：四件货各要压制 1 拍、冷却 2 拍，冷却机第 4～5 拍检修。
# 玩家改的是两条带上每一件的开工拍；中间只有一个暂存位，压机不能当仓库。
# 试演跑到第一处说不通的地方就停，并说清是哪件货、哪一拍。
const Rules = preload("res://scripts/workshop/gw07_rules.gd")
const World = preload("res://scripts/workshop/gw07_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ROW_NAMES = ["压制带","冷却带"]
const ARRIVAL = ["小岚：A、B、C、D 依次过压机和冷却机。压制各 1 拍，冷却各 2 拍。",
	"嗒嗒：冷却机第 %d～%d 拍要检修，那一段不能用；冷却也不能停下来等，一进机就得连着做满 %d 拍。"%[Rules.MAINT_START,Rules.MAINT_END,Rules.COOL_TIME],
	"小岚：两机之间只有一个暂存位，先来的先冷却——压机可不能当仓库。第 %d 拍前要全部做完。"%Rules.DEADLINE]
const AFTER = ["小岚：A 冷却 1–3 是检修前唯一塞得下的完整 2 拍；B 只能等到第 5 拍才进冷却机。",
	"嗒嗒：B 在暂存位上一等就是三拍，后面两件就得跟着往后压，不然位置不够。",
	"小岚：冷却 5–7、7–9、9–11 一路排满，第 %d 拍正好是下限。"%Rules.DEADLINE]
var gw_pending_feedback = ""
var focus_row = 0
var focus_item = 0

func configure() -> void:
	scene_id = "assembly"; level_id = "GW07"; title = "检修前，先留好位置"
	if save_path.is_empty(): save_path = Catalog.save_path("GW07")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"trial":3.6,"delivery":3.2}
	zoom_stages = []
	focus_row = 0; focus_item = 0

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "四件都先压后冷 · 冷却避开第 %d～%d 拍检修 · 第 %d 拍前做完"%[Rules.MAINT_START,Rules.MAINT_END,Rules.DEADLINE]
func status_line() -> String:
	return "选中：%s %s（第 %d 拍）"%[ROW_NAMES[focus_row],Rules.ITEMS[focus_item],
		state.press[focus_item] if focus_row == 0 else state.cool[focus_item]]
func submit_label() -> String: return "试运行 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "看看两条带","approach":"铺开两条带",
		"ready":"开始排开工拍","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装配间","重新体验"]
func reset_prompt() -> Array: return ["把两条带退回开局那张顺排草稿？\n本次试运行与求助次数仍保留。","继续改排法","退回草稿"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "两条带铺开了：上排压制、下排冷却，从第 0 拍排到第 %d 拍。"%Rules.DEADLINE
		"ready": return "先点一格选中它，再用「提前／推后」把它挪到合适的拍子上。"
		"puzzle": return "冷却机一次一件、每件连做 2 拍；两排之间只有一个暂存位。"
		"trial": return "按这套排法跑一遍：压制、进暂存位、冷却……"
		"delivery": return "四件都在第 %d 拍前冷却完，晾晒线展开。"%Rules.DEADLINE
		"aftermath": return AFTER[state.beat]
		"complete": return "停机那一段不能用，就得在它前后留好位置。"
	return ""

func build() -> void:
	for row in range(2):
		var id = "row_%d"%row
		add_button(id,ROW_NAMES[row],Rect2(24+row*158,548,150,46),select_row.bind(row))
		buttons[id].tooltip_text = "选中%s上的货 · 键盘 %s"%[ROW_NAMES[row],"↑" if row == 0 else "↓"]
		UIStyle.style_button(buttons[id],row == focus_row)
	add_button("back","提前 1 拍",Rect2(360,548,170,46),earlier)
	buttons["back"].tooltip_text = "把选中的那一格往前挪 1 拍 · 键盘 Q"
	add_button("forward","推后 1 拍",Rect2(538,548,170,46),later)
	buttons["forward"].tooltip_text = "把选中的那一格往后挪 1 拍 · 键盘 W"
	for row in range(2):
		for index in range(Rules.COUNT):
			add_hotspot("%s_%d"%["press" if row == 0 else "cool",index],world.cell_rect(row,index),
				select_cell.bind(row,index),
				"%s %s · 第 %d 拍 · 点一下选中它"%[ROW_NAMES[row],Rules.ITEMS[index],
					state.press[index] if row == 0 else state.cool[index]])

func extra() -> void:
	world.focus_row = focus_row; world.focus_item = focus_item
	add_button("journal","回看与发现",Rect2(1092,548,164,46),journal).disabled = transient > 0
	if state.stage != "puzzle": return
	sign_text("左右换货 · 上下换带 · Q 提前 1 拍 · W 推后 1 拍",Rect2(24,596,560,46),18)

func snapshot(v: Dictionary) -> Dictionary:
	return {"press":v.press.duplicate(),"cool":v.cool.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.press = Rules.DEFAULT_PRESS.duplicate(); n.cool = Rules.DEFAULT_COOL.duplicate(); return n

func select_row(row: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	focus_row = clampi(row,0,1); message = ""; refresh()

func select_cell(row: int, index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	focus_row = clampi(row,0,1); focus_item = clampi(index,0,Rules.COUNT-1); message = ""; refresh()

func move_item(delta: int) -> void:
	focus_item = clampi(focus_item+delta,0,Rules.COUNT-1); message = ""; refresh()

func adjust(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var starts = state.press if focus_row == 0 else state.cool
	var next = Rules.set_start(state,focus_row,focus_item,starts[focus_item]+delta)
	if next.is_empty():
		message = "已经到头了：开工拍只能排在第 0 到第 %d 拍之间。"%Rules.RANGE_MAX
		refresh(); return
	message = ""; commit_plan(next)

func earlier() -> void: adjust(-1)
func later() -> void: adjust(1)

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

# 试运行会跑到第一处说不通的地方才停，所以任何排法都进得了演出。
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	commit(Rules.advance(state),history)

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["先看冷却机哪一段不能用，再看四件冷却各要 2 拍。",
		"检修前只剩第 1～3 拍这一段完整的 2 拍，最多塞得下一件；A 冷却 1–3 之后，B 最早也只能第 5 拍进冷却机。",
		"倒着看：D 冷却 9–11、C 7–9、B 5–7。B 要到第 5 拍才进机，可它要是早早压完占着暂存位，后面两件就没位置了。",
		"示例：压制 0–1、1–2、4–5、6–7；冷却 1–3、5–7、7–9、9–11。冷却整段避开检修、暂存位一次只停一件、第 %d 拍前做完，都算过。"%Rules.DEADLINE]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT: move_item(-1)
	elif key == KEY_RIGHT: move_item(1)
	elif key == KEY_UP: select_row(0)
	elif key == KEY_DOWN: select_row(1)
	elif key == KEY_Q: adjust(-1)
	elif key == KEY_W: adjust(1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,133,780,502),true)
	var text = "工序规则\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	text += "\n\n压制各 1 拍、冷却各 2 拍，两机一次各一件。"
	text += "\n冷却机第 %d～%d 拍检修，冷却工序不能压在这段上。"%[Rules.MAINT_START,Rules.MAINT_END]
	text += "\n冷却不能中途暂停，一进机就得连着做满 %d 拍。"%Rules.COOL_TIME
	text += "\n中间只有一个暂存位，先来先冷却，压机不能当仓库。"
	text += "\n第 %d 拍结束前四件都要冷却完才算通过。"%Rules.DEADLINE
	if Rules.solved(state):
		text += "\n\n这一套：压制 %s；冷却 %s，第 %d 拍完工。"%[starts_text(0),starts_text(1),Rules.makespan(state)]
	UIStyle.text(overlay,text,Rect2(290,161,700,389),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,569,225,48),close_modal,true,overlay).grab_focus()

func starts_text(row: int) -> String:
	var parts = []
	var starts = state.press if row == 0 else state.cool
	for index in range(Rules.COUNT): parts.append("%s%d"%[Rules.ITEMS[index],starts[index]])
	return " ".join(parts)

# 空格是招牌动作：排好两条带后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

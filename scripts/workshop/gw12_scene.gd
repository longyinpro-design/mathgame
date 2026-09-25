extends "res://scripts/workshop/workshop_host.gd"
const Rules = preload("res://scripts/workshop/gw12_rules.gd")
const World = preload("res://scripts/workshop/gw12_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：第一班 23 枚标准件，第二班还有 24 枚，用的是同一种托。",
	"小岚：托盘容量牌丢了，只记得每托装 3～12 枚整数。每班结束只交走所有满托，余料留到下一班。",
	"嗒嗒：交接册上写得明白：两班一共交 9 个满托，最后还剩 2 枚。把槽数找出来，两班才好分开记。"]
const AFTER = ["嗒嗒：两班合起来 47 枚，扣掉最后剩的 2 枚，9 个满托一共装了 45 枚——每托 5 枚。",
	"小岚：第一班 23 枚按 5 枚一托，交 4 托留 3；第二班接入 3 枚共 27 枚，交 5 托、最后留 2 枚。",
	"嗒嗒：最后剩的 2 枚是第二班收工留下的，不是第一班的余料。写进交接册，安心吃饭；总机船坞还等着开工。"]
var gw_pending_feedback = ""
# ←/→ 走余料时的落点：只影响下一次按键从哪一枚开始数，不进存档。
var keep_pick = 0

func configure() -> void:
	scene_id = "rooftop"; level_id = "GW12"; title = "两班合并，槽数才找得到"
	if save_path.is_empty(): save_path = Catalog.save_path("GW12")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []
	keep_pick = 0

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "两班同一种托 · 共交 9 个满托、最后剩 2 枚 · 找出每托几枚"
func status_line() -> String:
	if state.stage != "puzzle": return ""
	if state.capacity < Rules.CAP_MIN: return "槽数 未提出"
	if state.first_keep < 0: return "槽数 %d · 一班未交班"%state.capacity
	if state.second_keep < 0: return "槽数 %d · 一班交 %d 托"%[state.capacity,Rules.first_trays(state)]
	return "共交 %d / 9 托 · 最后 %d 枚"%[Rules.total_trays(state),state.second_keep]
func submit_label() -> String:
	if state.capacity < Rules.CAP_MIN: return "先提出槽数 Space"
	if state.first_keep < 0: return "先定一班余料 Space"
	if state.second_keep < 0: return "先定最后余料 Space"
	return "核对交接册 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向台面","ready":"开始分托",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装配间","重新体验"]
func reset_prompt() -> Array: return ["把槽数和两班执行全部抹掉，从头查起？\n求助级别仍保留。","继续分托","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "两班的料车推上台面：第一班 23 枚，第二班 24 枚。"
		"ready": return "先提出一个槽数，再实际执行两班：第一班留几枚、第二班接入后最后留几枚。"
		"puzzle":
			if state.capacity < Rules.CAP_MIN: return "每托 3～12 枚整数。先提出槽数，再分两班执行。"
			if state.first_keep < 0: return "第一班 23 枚按 %d 枚一托：交走几托、留几枚？"%state.capacity
			if state.second_keep < 0: return "第二班接入 %d 枚，共 %d 枚：交走几托、最后留几枚？"%[state.first_keep,Rules.second_total(state)]
			return "两班一共交 %d 个满托、最后剩 %d 枚；对照交接册的 9 托与 2 枚。"%[Rules.total_trays(state),state.second_keep]
		"delivery": return "按 5 枚一托重演两班：第一班 4 托留 3，第二班 5 托留 2，共 9 托……"
		"aftermath": return AFTER[state.beat]
		"complete": return "先看两班总账，再还原每一班。"
	return ""

func build() -> void:
	for capacity in range(Rules.CAP_MIN,Rules.CAP_MAX+1):
		add_button("cap_%d"%capacity,str(capacity),world.capacity_rect(capacity),
			select_capacity.bind(capacity),capacity == state.capacity)
	if state.capacity < Rules.CAP_MIN: return
	# 当前这一步的余料：每个候选都能点，装不成整托的当场念出真实原因。
	if state.first_keep < 0:
		for keep in range(0,Rules.BOX+1):
			add_button("keep1_%d"%keep,str(keep),world.keep_rect(keep),choose_first.bind(keep))
	elif state.second_keep < 0:
		for keep in range(0,Rules.BOX+1):
			add_button("keep2_%d"%keep,str(keep),world.keep_rect(keep),choose_second.bind(keep))

func extra() -> void:
	add_button("journal","交接册",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary:
	return {"capacity":v.capacity,"first_keep":v.first_keep,"second_keep":v.second_keep,"tried":v.tried.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true)
	n.capacity = 0; n.first_keep = -1; n.second_keep = -1; n.tried = []
	return n

func select_capacity(capacity: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	message = ""; place(Rules.select(state,capacity))

func step_capacity(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	place(Rules.move_capacity(state,delta))

# 第一班交班：留下的余料要正好让 23 枚交成整托。按下这一下就是玩家确认的切班。
func choose_first(keep: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle" or state.first_keep >= 0: return
	keep_pick = keep
	if state.capacity < Rules.CAP_MIN:
		message = "先提出槽数，再定第一班留几枚。"; refresh(); return
	var next = Rules.set_first_keep(state,keep)
	if next.is_empty():
		message = Rules.keep_reason(Rules.FIRST,state.capacity,keep); refresh(); return
	gw_pending_feedback = "第一班交班：23 枚按 %d 枚一托，交走 %d 个满托，留 %d 枚给第二班。"%[
		state.capacity,(Rules.FIRST-keep)/state.capacity,keep]
	place(next)

# 第二班收工：接入第一班余料后，最后留下的也要让交走的是整托。
func choose_second(keep: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle" or state.first_keep < 0 or state.second_keep >= 0: return
	keep_pick = keep
	var next = Rules.set_second_keep(state,keep)
	if next.is_empty():
		message = Rules.keep_reason(state.first_keep+Rules.SECOND,state.capacity,keep); refresh(); return
	var total = Rules.second_total(state)
	var tail = "与交接册相符。" if Rules.solved(next) else "交接册写的是 9 个满托、最后剩 2 枚。"
	gw_pending_feedback = "第二班收工：接入 %d 枚后共 %d 枚，按 %d 枚一托，交走 %d 个满托，最后留 %d 枚——两班共交 %d 个满托，%s"%[
		state.first_keep,total,state.capacity,(total-keep)/state.capacity,keep,Rules.total_trays(next),tail]
	place(next)

# ←/→ 先管当前这一步：还没提槽数就换槽数，提了就调当前余料；↑/↓ 始终换槽数。
func step(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.capacity < Rules.CAP_MIN: step_capacity(delta); return
	if state.first_keep < 0: step_first(delta); return
	if state.second_keep < 0: step_second(delta); return
	step_capacity(delta)

func step_first(delta: int) -> void:
	keep_pick = clampi(keep_pick+delta,0,Rules.BOX)
	choose_first(keep_pick)

func step_second(delta: int) -> void:
	keep_pick = clampi(keep_pick+delta,0,Rules.BOX)
	choose_second(keep_pick)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	var previous = state
	super.apply_committed(candidate,next_history)
	# 换槽数或推进到下一步时，余料落点从 0 重新数起，不沿用上一步的读数。
	if candidate.capacity != previous.capacity or candidate.first_keep != previous.first_keep \
		or candidate.second_keep != previous.second_keep: keep_pick = 0
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
	return ["两班其实是同一批活：第一班 23 枚、第二班 24 枚，一共 47 枚。先把两班合并看。",
		"最后剩下的 2 枚不在 9 个满托里：9 个满托一共装了 47−2=45 枚。",
		"45 枚装 9 个满托，每托就是 45÷9=5 枚。容量定下来，再把两班分开各还原一次。",
		"每托 5 枚：第一班 23=4×5+3，交 4 托留 3；第二班 3+24=27=5×5+2，交 5 托留 2，共 9 托。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: step(-1)
	elif key == KEY_RIGHT or key == KEY_D: step(1)
	elif key == KEY_UP or key == KEY_W: step_capacity(1)
	elif key == KEY_DOWN or key == KEY_S: step_capacity(-1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "交接册\n第一班 23 枚、第二班 24 枚同型标准件，两班用同一种托。\n托盘容量牌丢了，只记得每托 3～12 枚整数。\n每班结束只交走所有满托，余料完整留到下一班；余料盒装得下所有合法余料。\n交接册写着：两班一共交 9 个满托，最后还剩 2 枚。\n\n试过的槽数\n"
	if state.tried.is_empty(): text += "还没执行完任何一个槽数。\n"
	for capacity in state.tried.slice(0,5):
		var parts = Rules.plan(capacity)
		text += "%d 槽：第一班 %d 托留 %d，第二班 %d 托留 %d，共 %d 托。\n"%[capacity,parts[0],parts[1],parts[2],parts[3],parts[0]+parts[2]]
	if state.tried.size() > 5: text += "…还有 %d 个槽数没列出来。\n"%(state.tried.size()-5)
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n两班合并：23+24=47 枚；最后剩的 2 枚不在 9 个满托里。\n9 个满托装了 47−2=45 枚，45÷9=5。\n第一班 23=4×5+3，第二班 3+24=27=5×5+2。"
	UIStyle.text(overlay,text,Rect2(250,121,780,440),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：定完余料不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

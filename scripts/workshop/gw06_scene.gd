extends "res://scripts/workshop/workshop_host.gd"
# GW06 装配间「产量一样，工时不同」：凑出 31 枚扣环，还要在第 8 拍结束前做完。
# 玩家排的是一张炉次工单；产量与拍数都由工单现算，画面不替玩家记数。
const Rules = preload("res://scripts/workshop/gw06_rules.gd")
const World = preload("res://scripts/workshop/gw06_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["小岚：要正好 %d 枚扣环。小模每炉出 %d 枚，大模每炉出 %d 枚，都得整炉加工，不能丢。"%[Rules.NEED,Rules.SMALL,Rules.LARGE],
	"嗒嗒：每开一炉占 1 拍；要是下一炉要换模，还得另花 1 拍——头一炉装模不用花。",
	"小岚：第 %d 拍一过就得交货。开几炉、怎么排，都归你定。"%Rules.DEADLINE]
const AFTER = ["小岚：凑 %d 枚只有两种组合——小 7 炉大 2 炉，或者小 2 炉大 5 炉。"%Rules.NEED,
	"嗒嗒：9 炉那一种，光加工就要 9 拍，还没算换模，早就超过 %d 拍了。"%Rules.DEADLINE,
	"小岚：7 炉加工 7 拍，只剩 1 拍，只够换一次模——同类的炉次得排在一起。冷却机还得检修，先留位置。"]
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "assembly"; level_id = "GW06"; title = "产量一样，工时不同"
	if save_path.is_empty(): save_path = Catalog.save_path("GW06")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"trial":3.8,"delivery":3.2}
	zoom_stages = []

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "正好 %d 枚扣环 · 第 %d 拍结束前做完"%[Rules.NEED,Rules.DEADLINE]
func status_line() -> String:
	var rows = Rules.schedule(state)
	return "工单 %d 炉 · 产量 %d 枚 · 总拍 %d"%[Rules.firing(state),Rules.output(state),rows.makespan]
func submit_label() -> String: return "试运行 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "看看炉次表","approach":"铺开炉次表",
		"ready":"开始排工单","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装配间","重新体验"]
func reset_prompt() -> Array: return ["把整张炉次工单清空？\n本次试运行与求助次数仍保留。","继续排工单","全部清空"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "炉次表铺开了：从第 0 拍排到第 %d 拍，每格一拍。"%Rules.DEADLINE
		"ready": return "先想好开几炉、各用什么模，再一炉一炉排上去。"
		"puzzle": return "同一炉只出一种模；相邻两炉换模要另占一拍，同类排在一起才省。"
		"trial": return "按这张工单跑一遍：装模、开炉、换模、再开炉……"
		"delivery": return "正好 %d 枚扣环，第 %d 拍前交了货，灯架合拢。"%[Rules.NEED,Rules.DEADLINE]
		"aftermath": return AFTER[state.beat]
		"complete": return "把额外花的拍数算进去，才挑得对方案。"
	return ""

func build() -> void:
	add_button("small","小模 · 每炉 %d 枚"%Rules.SMALL,Rect2(24,548,196,46),add_small)
	buttons["small"].tooltip_text = "在工单末尾加一炉小模 · 出 %d 枚 · 键盘 Q"%Rules.SMALL
	add_button("large","大模 · 每炉 %d 枚"%Rules.LARGE,Rect2(232,548,196,46),add_large)
	buttons["large"].tooltip_text = "在工单末尾加一炉大模 · 出 %d 枚 · 键盘 W"%Rules.LARGE
	for index in range(state.order.size()):
		var mould = state.order[index]
		add_hotspot("batch_%d"%index,world.batch_rect(index),take_back.bind(index),
			"第 %d 炉 · %s · 出 %d 枚 · 点一下撤下来"%[index+1,"小模" if mould == Rules.SMALL else "大模",mould])

func extra() -> void:
	add_button("journal","回看与发现",Rect2(1092,548,164,46),journal).disabled = transient > 0
	if state.stage != "puzzle": return
	sign_text("Q 加小模 · W 加大模 · R 撤最后一炉 · Z 撤销",Rect2(24,596,520,46),18)

func snapshot(v: Dictionary) -> Dictionary:
	return {"order":v.order.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.order = []; return n

func add_mould(mould: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.place(state,mould)
	if next.is_empty():
		message = "工单最多排 %d 炉：先撤掉一炉再加。"%Rules.MAX_BATCHES
		refresh(); return
	message = ""; commit_order(next)

func add_small() -> void: add_mould(Rules.SMALL)
func add_large() -> void: add_mould(Rules.LARGE)

func take_back(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.remove_at(state,index)
	if next.is_empty(): message = "这一炉已经不在工单上了。"; refresh(); return
	message = ""; commit_order(next)

func drop_last() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.order.is_empty(): message = "工单上还没有炉次。"; refresh(); return
	take_back(state.order.size()-1)

# 宿主同名的 place() 走的是另一套语义，这里另起一个名字提交排好的工单。
func commit_order(next: Dictionary) -> void:
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

# 工单空着不能试运行：先说清缺什么，不进演出。
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
	return ["先列产量组合：3 枚一炉和 5 枚一炉各开几炉，加起来才正好 %d 枚？"%Rules.NEED,
		"只有小 7 炉大 2 炉（共 9 炉）和小 2 炉大 5 炉（共 7 炉）两种凑得出 %d 枚。"%Rules.NEED,
		"9 炉那一种，光加工就要 9 拍，还没算换模，已经超过 %d 拍；只剩 7 炉那一种。"%Rules.DEADLINE,
		"7 炉加工 7 拍，还剩 1 拍，只够换一次模：同类的炉次必须排在一起，所以是小小大大大大大，或者大大大大大小小。"]

func handle_key(key: int) -> bool:
	if key == KEY_Q: add_small()
	elif key == KEY_W: add_large()
	elif key == KEY_R: drop_last()
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,133,780,502),true)
	var text = "炉次规则\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	text += "\n\n小模每炉 %d 枚，大模每炉 %d 枚，整炉加工、不丢弃。"%[Rules.SMALL,Rules.LARGE]
	text += "\n每开一炉占 1 拍；相邻两炉要换模时，另花 1 拍。"
	text += "\n首次装模免费，所以头一炉不占换模拍。"
	text += "\n同一拍不能既换模又开炉，工单最多 %d 炉。"%Rules.MAX_BATCHES
	text += "\n第 %d 拍结束前做够 %d 枚才算通过。"%[Rules.DEADLINE,Rules.NEED]
	if Rules.solved(state):
		text += "\n\n这一套：%s，加工 %d 拍、换模 %d 拍，第 %d 拍完工。"%[order_text(state.order),
			Rules.firing(state),Rules.schedule(state).changes.size(),Rules.makespan(state)]
	UIStyle.text(overlay,text,Rect2(290,161,700,389),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,569,225,48),close_modal,true,overlay).grab_focus()

func order_text(order: Array) -> String:
	var names = []
	for mould in order: names.append("小" if mould == Rules.SMALL else "大")
	return "".join(names) if not names.is_empty() else "（空）"

# 空格是招牌动作：排好工单后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

extends "res://scripts/workshop/workshop_host.gd"
# GW18 百臂总机「两种船期，一套准备」：全岛终局关。
# 库存 7 件分三批（F 2 件、V 3 件、M 2 件），压机、冷却各一次一批，两级暂存各 1 批。
# 玩家排的是三个压制开工拍与三个冷却开工拍；工作台有「早班推演」「晚班推演」两页，
# 共用同一份草稿：V 的吊运点早班第 6 拍、晚班第 8 拍，两页都走得通才收。
# 正式运行到第 3 拍停下读通知，玩家确认后按同一份计划继续；失败回规划，不消耗库存。
const Rules = preload("res://scripts/workshop/gw18_rules.gd")
const World = preload("res://scripts/workshop/gw18_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["小岚：总机船第 10 拍就要开。库存 7 件分三批：森林 F 2 件、山谷 V 3 件、集市 M 2 件，不拆批、不超量。",
	"嗒嗒：压机一次一批，2 件批次 1 拍、3 件批次 2 拍；冷却每批 2 拍，按出压机的顺序来，两级暂存架各只放得下 1 批。",
	"小岚：吊机 F 固定第 3 拍、M 固定第 9 拍；V 走早班还是晚班，第 3 拍才收到确认——先做一套两班都能用的计划。"]
const AFTER = ["嗒嗒：F 压制 0–1、冷却 1–3；V 压制 1–3、冷却 3–5；M 压制 3–4、冷却 6–8。",
	"小岚：早班 V 第 6 拍吊运、晚班第 8 拍；M 的冷却放在 6–8，晚班第 7 拍暂存架上就不会两批挤在一起。",
	"嗒嗒：三处接收记录齐全，第 10 拍出海；总机留了一只臂给休息牌，阿舷递来山谷的退件包。发现卡：把不同情况都想一遍。"]
var gw_pending_feedback = ""
var focus_slot = 0
var page = 6

func configure() -> void:
	scene_id = "engine"; level_id = "GW18"; title = "百臂总机 · 一套准备"
	if save_path.is_empty(): save_path = Catalog.save_path("GW18")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":1.6,"launch":2.8}
	zoom_stages = []
	focus_slot = 0; page = Rules.BRANCHES[0]

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "库存 7 件 · 不拆批 · F2/V3/M2 · 第 10 拍开船"
func status_line() -> String:
	if state.stage == "trial": return "%s页试演 · 第 %d 拍"%[Rules.page_name(page),world.trial_tick]
	if state.stage not in ["ready","puzzle"]: return ""
	var row = "压制" if focus_slot < Rules.COUNT else "冷却"
	var index = focus_slot%Rules.COUNT
	var at = state.press[index] if focus_slot < Rules.COUNT else state.cool[index]
	return "%s %s 第%d拍 · %s页"%[Rules.BATCHES[index],row,at,Rules.page_name(page)]
func submit_label() -> String: return "两页都过才收 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向总机船坞","approach":"铺开两班时刻表",
		"ready":"开始排工序","trial":"返回规划","notice":"确认通知，继续执行","handover":"拉下确认交接杆",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在总机船坞","重新体验"]
func reset_prompt() -> Array: return ["把六个开工拍退回开局草稿？\n求助级别仍保留。","继续排工序","退回草稿"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "两班共用一张时刻表：早班 V 第 6 拍吊运、晚班第 8 拍，其余工序一模一样。"
		"ready": return "先点一格工序，再用「提前／推后 1 拍」挪到合适的开工拍；两页推演共用这份草稿。"
		"puzzle": return "压机、冷却各一次一批，两级暂存各 1 批；第 3 拍才确认 V 的班次，两页都得走得通。"
		"trial": return "试演这一页：看暂存架在哪一拍挤住，或者一路走到第 10 拍开船。"
		"delivery": return "正式运行：先跑到第 3 拍，停下读总机确认。"
		"notice": return "第 3 拍确认：V 走晚班，实际吊运点第 8 拍。已兼顾两班的计划不必改动。"
		"launch": return "按确认的班次继续跑：冷却、吊运，第 10 拍开船。"
		"handover": return "三处接收记录齐全，拉下确认交接杆，总机船才出海。"
		"aftermath": return AFTER[state.beat]
		"complete": return "一套准备，两种船期都走得通。发现卡：把不同情况都想一遍。"
	return ""

func build() -> void:
	for index in range(Rules.COUNT):
		add_hotspot("press_%d"%index,world.press_rect(index),select_slot.bind(index),
			"%s 批压制 · %d 件 · %d 拍 · 点一下选中"%[Rules.BATCHES[index],Rules.ITEM_COUNT[index],Rules.PRESS_TIME[index]])
		add_hotspot("cool_%d"%index,world.cool_rect(index),select_slot.bind(Rules.COUNT+index),
			"%s 批冷却 · 每批 2 拍 · 点一下选中"%Rules.BATCHES[index])
	for index in range(2):
		var slot = Rules.BRANCHES[index]
		add_hotspot("page_%d"%index,world.page_rect(index),pick_page.bind(slot),
			"%s推演 · V 第 %d 拍吊运 · 点一下切到这一页"%[Rules.page_name(slot),slot])

func extra() -> void:
	world.focus_slot = focus_slot
	world.page = page
	if state.stage in ["ready","puzzle","trial"]:
		add_button("earlier","提前 1 拍 Q",Rect2(24,556,150,46),earlier).disabled = transient > 0
		add_button("later","推后 1 拍 E",Rect2(182,556,150,46),later).disabled = transient > 0
		add_button("page_early","早班推演 1",Rect2(340,556,150,46),pick_page.bind(Rules.BRANCHES[0])).disabled = transient > 0
		add_button("page_late","晚班推演 2",Rect2(498,556,150,46),pick_page.bind(Rules.BRANCHES[1])).disabled = transient > 0
		if state.stage == "trial":
			add_button("trial_again","再演一遍 R",Rect2(656,556,150,46),retry_trial).disabled = transient > 0
		else:
			add_button("trial","试演本页 R",Rect2(656,556,150,46),start_trial).disabled = transient > 0
		sign_text("←→ 换批次 · ↑↓ 换压机/冷却 · Q/E 挪 1 拍 · 1/2 换推演页 · R 试演 · Z 撤销 · X 重摆 · H 提示",
			Rect2(24,608,1232,38),15)
	add_button("journal","回看与发现",Rect2(1092,556,164,46),journal).disabled = transient > 0
	if state.stage == "handover":
		add_hotspot("lever",world.lever_rect(),advance,"确认交接杆 · 拉下就开船 · 键盘 Space")

func snapshot(v: Dictionary) -> Dictionary:
	return {"press":v.press.duplicate(),"cool":v.cool.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true)
	n.press = Rules.DEFAULT_PRESS.duplicate(); n.cool = Rules.DEFAULT_COOL.duplicate()
	return n

func select_slot(slot: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	focus_slot = clampi(slot,0,Rules.COUNT*2-1); message = ""; refresh()

func move_batch(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var base = 0 if focus_slot < Rules.COUNT else Rules.COUNT
	focus_slot = base+(focus_slot-base+delta+Rules.COUNT)%Rules.COUNT
	message = ""; refresh()

func move_machine(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var row = 0 if focus_slot < Rules.COUNT else 1
	var next = clampi(row+delta,0,1)
	focus_slot = next*Rules.COUNT+focus_slot%Rules.COUNT
	message = ""; refresh()

func adjust(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var index = focus_slot%Rules.COUNT
	var current = state.press[index] if focus_slot < Rules.COUNT else state.cool[index]
	var value = current+delta
	if value < 0 or value > Rules.START_MAX:
		message = "已经到头了：开工拍只能排在第 0 到第 %d 拍之间。"%Rules.START_MAX
		refresh(); return
	message = ""
	var next = Rules.nudge_press(state,index,delta) if focus_slot < Rules.COUNT else Rules.nudge_cool(state,index,delta)
	if next.is_empty(): return
	commit_plan(next)

func earlier() -> void: adjust(-1)
func later() -> void: adjust(1)

func pick_page(slot: int) -> void:
	if modal or transient > 0 or state.stage not in ["ready","puzzle","trial"]: return
	if page == slot: return
	page = slot
	if state.stage == "trial": world.start_trial(page)
	message = ""; refresh()

func start_trial() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.begin_trial(state)
	if next.is_empty(): return
	message = ""; commit(next,history)

func retry_trial() -> void:
	if modal or transient > 0 or state.stage != "trial": return
	world.start_trial(page); message = ""; refresh()

func trial_key() -> void:
	if state.stage == "puzzle": start_trial()
	elif state.stage == "trial": retry_trial()

# 宿主同名的 place() 走的是另一套语义，这里另起一个名字提交排好的六个开工拍。
func commit_plan(next: Dictionary) -> void:
	if state.stage != "puzzle" or modal or transient > 0 or next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

# 提交就是两页推演逐页验收：第一次说不通的原因由规则模块给出，两页都说不过就只念第一处。
# 通知那一格不摆姿态：玩家读完就按，正好落在落位动画里也照样放行。
func advance() -> void:
	if modal or state.stage in Rules.ANIMATIONS: return
	if state.stage == "notice":
		commit(Rules.advance(state),history)
		return
	if transient > 0: return
	if state.stage == "puzzle":
		var missing = Rules.shortfalls(state)
		if not missing.is_empty():
			message = missing[0] + ("（还有 %d 处说不通）"%(missing.size()-1) if missing.size() > 1 else "")
			refresh(); return
		commit(Rules.advance(state),history)
		return
	super.advance()

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["一张方案要经历两种情况：早班 V 第 6 拍吊运、晚班 V 第 8 拍吊运。先用两页推演各跑一遍。",
		"早班通过不代表晚班通过：V 晚一班，冷却到吊机间的暂存位就要多占两拍。",
		"检查第 7 拍以后：M 的冷却若第 7 拍就完，晚班第 7 拍 V 还在暂存架上等吊机，两批就挤在同一个位子上。",
		"兼顾两班的示范：压制 F 0–1、V 1–3、M 3–4；冷却 F 1–3、V 3–5、M 6–8；吊运 F 第 3 拍、M 第 9 拍，V 按第 6 或第 8 拍。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT: move_batch(-1)
	elif key == KEY_RIGHT: move_batch(1)
	elif key == KEY_UP: move_machine(-1)
	elif key == KEY_DOWN: move_machine(1)
	elif key == KEY_Q: adjust(-1)
	elif key == KEY_E: adjust(1)
	elif key == KEY_1: pick_page(Rules.BRANCHES[0])
	elif key == KEY_2: pick_page(Rules.BRANCHES[1])
	elif key == KEY_R: trial_key()
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(200,90,880,566),true)
	var text = "百臂总机：两种船期，一套准备\n\n"
	text += "库存 7 件：F 森林 2 件（压制 1 拍）、V 山谷 3 件（压制 2 拍）、M 集市 2 件（压制 1 拍）。\n"
	text += "压机一次一批、不能中断；冷却每批 2 拍，按出压机的顺序；两级暂存架各 1 批。\n"
	text += "吊机 F 第 3 拍、M 第 9 拍；V 早班第 6 拍、晚班第 8 拍，第 3 拍收到确认。第 10 拍开船。\n\n"
	text += "当前草稿\n"
	for index in range(Rules.COUNT):
		text += "%s 压制第 %d 拍、冷却第 %d 拍；"%[Rules.BATCHES[index],state.press[index],state.cool[index]]
	text += "\n\n"
	for slot in Rules.BRANCHES:
		var hit = Rules.run_conflict(state,slot)
		if hit.is_empty():
			text += "%s推演：走得通。\n"%Rules.page_name(slot)
		else:
			text += "%s推演：说不通——%s\n"%[Rules.page_name(slot),hit.text]
	if Rules.solved(state):
		text += "\n两页都走得通：这份计划在两种船期下都能交货。"
	UIStyle.text(overlay,text,Rect2(240,116,800,470),19,UIStyle.DARK)
	add_button("close_journal","回到工作台",Rect2(741,572,225,48),close_modal,true,overlay).grab_focus()

# 空格与翻页键是招牌动作：排工序时不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or modal or transient > 0: return
	if event.keycode == KEY_SPACE and state.get("stage") == "puzzle":
		advance(); get_viewport().set_input_as_handled(); return
	if state.get("stage") in ["ready","puzzle","trial"]:
		if event.keycode == KEY_1: pick_page(Rules.BRANCHES[0])
		elif event.keycode == KEY_2: pick_page(Rules.BRANCHES[1])
		elif event.keycode == KEY_R: trial_key()
		else: return
		get_viewport().set_input_as_handled()

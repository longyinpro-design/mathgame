extends "res://scripts/workshop/workshop_host.gd"
const Rules = preload("res://scripts/workshop/gw16_rules.gd")
const World = preload("res://scripts/workshop/gw16_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：午休铃要换一首新曲。老工匠留话说：每首恰好 4 段，每段长 2、3 或 4 拍。",
	"小岚：整首正好 12 拍，其中恰好两段是 3 拍；曲子循环播放，相邻两段不能一样长，末段和首段也相邻。",
	"嗒嗒：工匠说这样的曲子一共有 4 首。排一段试听一段，把 4 首都收进收集板，午休就有曲子了。"]
const AFTER = ["嗒嗒：四首都收齐了！两个 3 隔开，首段 2 的一首、首段 4 的一首、首段 3 的两首。",
	"小岚：要是把末段和首段当成不相邻，2/3/4/2 这样的也会被算进来，就会多算。",
	"嗒嗒：同一首重存一遍不算新的一首。留 %s 作章末午休曲，分类着找才不重也不漏。"]
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "assembly"; level_id = "GW16"; title = "找全四种午休曲"
	if save_path.is_empty(): save_path = Catalog.save_path("GW16")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "四段 12 拍 · 恰好两段 3 拍 · 首尾也不相同 · 收齐 4 首"
func status_line() -> String:
	if state.stage != "puzzle": return ""
	if Rules.solved(state): return "已收 4 / 4 · 午休曲已定"
	return "已收 %d / 4 首"%state.saved.size()
func submit_label() -> String:
	if state.saved.size() < Rules.TUNES: return "还差 %d 首 Space"%(Rules.TUNES-state.saved.size())
	if state.chosen < 0: return "点一首留曲 Space"
	return "定为午休曲 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向铃架",
		"ready":"开始排铃",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在屋顶修理街","重新体验"]
func reset_prompt() -> Array: return ["把铃架上的四段全部取下，从头排起？\n收集板与求助级别仍保留。","继续排铃","全部取下"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "午休铃架推上台面：四格空位，等着排一段循环的曲子。"
		"ready": return "先排四段，每段 2、3 或 4 拍；排好试听，接得上再保存。"
		"puzzle":
			if state.segments.size() < Rules.SEGMENTS:
				return "铃架还差 %d 段：每段从 2、3、4 拍里选。"%(Rules.SEGMENTS-state.segments.size())
			var problems = Rules.phrase_problems(state.segments)
			if not problems.is_empty(): return "这段循环接不上：%s"%problems[0]
			if not state.heard: return "排好了：先按「试听」听一遍这段循环。"
			if state.saved.has(state.segments): return "这首已经收下了：改几段，再排一首新的。"
			return "这段循环接得上，可以保存。"
		"delivery": return "午休铃响起来：%s 一段接一段，正好 12 拍……"%Rules.order_text(state.saved[state.chosen])
		"aftermath":
			if state.beat == 2 and state.chosen >= 0:
				return AFTER[2]%Rules.order_text(state.saved[state.chosen])
			return AFTER[state.beat]
		"complete": return "分类才能不重不漏。"
	return ""

func build() -> void:
	for length in range(Rules.LENGTH_MIN,Rules.LENGTH_MAX+1):
		add_button("seg_%d"%length,"%d 拍"%length,world.length_rect(length),put_segment.bind(length))
	add_button("listen","试听 T",world.listen_rect(),listen_tune)
	add_button("save","保存这首 S",world.save_rect(),save_tune)
	for index in range(state.segments.size()):
		add_hotspot("slot_%d"%index,world.slot_rect(index),take_segment.bind(index),
			"第 %d 段 %d 拍 · 点一下取下来重排"%[index+1,state.segments[index]])
	if Rules.collected(state):
		for index in range(state.saved.size()):
			add_hotspot("pick_%d"%index,world.tune_rect(index),pick_tune.bind(index),
				"把 %s 留作午休曲 · 点一下选它"%Rules.order_text(state.saved[index]))

func extra() -> void:
	add_button("journal","铃谱与发现",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary:
	return {"segments":v.segments.duplicate(),"heard":v.heard,"saved":v.saved.duplicate(true),"chosen":v.chosen}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.segments = []; n.heard = false; return n

func put_segment(length: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.put(state,length)
	if next.is_empty():
		message = "铃架已经排满 4 段：点一段取下来重排，或者直接试听。"; refresh(); return
	gw_pending_feedback = "第 %d 段定为 %d 拍：铃架合计 %d / %d 拍。"%[
		next.segments.size(),length,Rules.beats(next.segments),Rules.TOTAL_BEATS]
	place(next)

func take_segment(slot: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.take(state,slot)
	if next.is_empty(): return
	gw_pending_feedback = "取下第 %d 段，重新排。"%(slot+1)
	place(next)

func take_last() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.segments.is_empty():
		message = "铃架上还没有段可以取。"; refresh(); return
	take_segment(state.segments.size()-1)

# 试听：完整放一遍循环。不合法就当场说清是总拍数、3 的段数还是首尾相邻对不上。
func listen_tune() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.segments.size() != Rules.SEGMENTS:
		message = "铃架还差 %d 段才能试听：每首正好 4 段。"%(Rules.SEGMENTS-state.segments.size())
		refresh(); return
	var next = Rules.listen(state)
	if next.is_empty(): return
	gw_pending_feedback = audition_text(state.segments)
	if next == state:
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh(); return
	place(next)

func audition_text(order: Array) -> String:
	var problems = Rules.phrase_problems(order)
	if problems.is_empty():
		return "试听 %s：相邻两段都不同，末段 %d 与首段 %d 也接得上；合计 %d 拍、两个 3 拍。可以保存。"%[
			Rules.order_text(order),order[Rules.SEGMENTS-1],order[0],Rules.beats(order)]
	return "试听 %s：%s"%[Rules.order_text(order),problems[0]]

func save_tune() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.save_tune(state)
	if next.is_empty():
		message = Rules.save_reason(state); refresh(); return
	gw_pending_feedback = "收下这首 %s：收集板已有 %d / 4 首。"%[Rules.order_text(state.segments),next.saved.size()]
	place(next)

func pick_tune(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.choose(state,index)
	if next.is_empty():
		message = "四首收齐后才能挑一首留作午休曲。"; refresh(); return
	gw_pending_feedback = "把 %s 留作章末午休曲。"%Rules.order_text(state.saved[index])
	if next == state:
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh(); return
	place(next)

func cycle_chosen(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.cycle_chosen(state,delta)
	if next.is_empty(): return
	gw_pending_feedback = "午休曲换成 %s。"%Rules.order_text(next.saved[next.chosen])
	place(next)

func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

# 提交只在四首收齐、留好一首后通过；没到时把真实缺的条件一次说清。
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle":
		var missing = Rules.shortfalls(state)
		if not missing.is_empty():
			message = "；".join(missing); refresh(); return
	commit(Rules.advance(state),history)

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["两个 3 一共占 6 拍：12−6=6，另外两段合起来 6 拍，只能是 2 和 4。",
		"两个 3 不能相邻，末段和首段也算相邻：它们只能隔开，一个占第 1、3 段，一个占第 2、4 段。",
		"按首段分类记：首段 2 的一类、首段 4 的一类、首段 3 的两类——三类正好 4 首。",
		"四种完整段序：2/3/4/3、3/2/3/4、3/4/3/2、4/3/2/3。"]

func handle_key(key: int) -> bool:
	if key == KEY_2 or key == KEY_KP_2: put_segment(2)
	elif key == KEY_3 or key == KEY_KP_3: put_segment(3)
	elif key == KEY_4 or key == KEY_KP_4: put_segment(4)
	elif key == KEY_T: listen_tune()
	elif key == KEY_S: save_tune()
	elif key == KEY_R or key == KEY_BACKSPACE: take_last()
	elif key == KEY_C or key == KEY_RIGHT: cycle_chosen(1)
	elif key == KEY_LEFT: cycle_chosen(-1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "午休铃规则\n每首曲子恰好 4 段，每段长 2、3 或 4 拍。\n整首正好 12 拍，其中恰好两段是 3 拍。\n曲子循环播放：相邻两段长度不能相同，末段与首段也相邻。\n固定起拍点；旋转后的段序只要不同，就算另一首。\n\n收集板\n"
	if state.saved.is_empty(): text += "还没有保存任何一首。\n"
	for index in range(state.saved.size()):
		var mark = "（已留作午休曲）" if index == state.chosen else ""
		text += "%d. %s %s\n"%[index+1,Rules.order_text(state.saved[index]),mark]
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n四种段序：2/3/4/3、3/2/3/4、3/4/3/2、4/3/2/3。\n两个 3 隔开，另外两段就是 2 和 4；按首段分类才不重不漏。"
	UIStyle.text(overlay,text,Rect2(250,121,780,460),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：收齐后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

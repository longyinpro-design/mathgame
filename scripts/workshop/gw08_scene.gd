extends "res://scripts/workshop/workshop_host.gd"
const Rules = preload("res://scripts/workshop/gw08_rules.gd")
const World = preload("res://scripts/workshop/gw08_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：旧槽板换过一批，容量牌掉了，维修单上只剩两张用过的记录。",
	"小岚：记录一：35 根灯轴装完满托，还剩 3 根。记录二：47 根装完满托，还剩 7 根。",
	"嗒嗒：每托装 5～16 根整数，余数一定比每托容量小。把槽数找出来，新托盘才好配牌。"]
const AFTER = ["嗒嗒：8 槽！35 根装 4 个满托剩 3，47 根装 5 个满托剩 7，两张都吻合。",
	"小岚：只看记录一，8 和 16 都说得通；只看记录二，8 和 10 都说得通。合起来才只剩 8。",
	"嗒嗒：容量牌补上了。旧报时廊的灯还等着换，那边少一盏都报不准点。"]
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "assembly"; level_id = "GW08"; title = "两张旧单，锁定一块槽板"
	if save_path.is_empty(): save_path = Catalog.save_path("GW08")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "每托 5～16 根 · 35 剩 3、47 剩 7 · 找出同一槽数"
func status_line() -> String:
	if state.capacity < Rules.CAP_MIN: return "候选 未提出"
	var done = 0
	for record in range(2):
		if Rules.tested(state,record).has(state.capacity): done += 1
	return "候选 %d 槽 · 已重演 %d / 2 张"%[state.capacity,done]
func submit_label() -> String: return "定为槽数 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向旧槽板","ready":"开始提槽数",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在旧报时廊","重新体验"]
func reset_prompt() -> Array: return ["把试过的槽数和重演记录全部抹掉，从头查起？\n求助级别仍保留。","继续查看","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "两张维修记录并排压上台面，旧槽板等着配容量牌。"
		"ready": return "先提出一个槽数，再分别重演两张记录；两张都吻合才算数。"
		"puzzle": return "每托装 5～16 根整数。找出让两张记录都成立的槽数。"
		"delivery": return "按 8 槽重演：35 根装 4 个满托剩 3，47 根装 5 个满托剩 7……"
		"aftermath": return AFTER[state.beat]
		"complete": return "一条线索不够，就把两条合起来看。"
	return ""

func build() -> void:
	for capacity in range(Rules.CAP_MIN,Rules.CAP_MAX+1):
		add_button("cap_%d"%capacity,str(capacity),world.capacity_rect(capacity),
			select_capacity.bind(capacity),capacity == state.capacity)
	for record in range(2):
		add_button("replay_%d"%record,"重演记录%s"%["一","二"][record],world.replay_rect(record),
			replay_record.bind(record)).disabled = state.capacity < Rules.CAP_MIN

func extra() -> void:
	add_button("journal","记录与排除",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary:
	return {"capacity":v.capacity,"tested_first":v.tested_first.duplicate(),"tested_second":v.tested_second.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.capacity = 0; n.tested_first = []; n.tested_second = []; return n

func select_capacity(capacity: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	message = ""; place(Rules.select(state,capacity))

func step_capacity(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	place(Rules.move_capacity(state,delta))

# 重演一张记录：把当前槽数记进这张记录的重演表，并当场说清余数对不对得上。
func replay_record(record: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	if state.capacity < Rules.CAP_MIN:
		message = "先提出一个槽数，再重演记录。"; refresh(); return
	var next = Rules.replay(state,record)
	if next.is_empty(): return
	var parts = Rules.division(Rules.RECORDS[record],state.capacity)
	var name = Rules.RECORD_NAMES[record]
	if parts[1] == Rules.REMAINDERS[record]:
		gw_pending_feedback = "%s重演：%d 根按 %d 一托，装 %d 个满托、剩 %d 根，与记录相符。"%[name,Rules.RECORDS[record],state.capacity,parts[0],parts[1]]
	else:
		gw_pending_feedback = "%s重演：%d 根按 %d 一托，装 %d 个满托、剩 %d 根；记录写的是剩 %d 根，对不上。"%[name,Rules.RECORDS[record],state.capacity,parts[0],parts[1],Rules.REMAINDERS[record]]
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
	return ["先去掉零散数：两张记录剩下的 3 根和 7 根不在满托里。",
		"两张满托总数分别是 32 根和 40 根；槽数要能同时整分这两个数。",
		"第一张的候选是 8、16；第二张的候选是 8、10。两边都试过就能看出谁同时成立。",
		"只有 8 同时出现在两份候选里：32 是 4 个 8，40 是 5 个 8；35 剩 3、47 剩 7。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: step_capacity(-1)
	elif key == KEY_RIGHT or key == KEY_D: step_capacity(1)
	elif key == KEY_R: replay_record(0)
	elif key == KEY_T: replay_record(1)
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(210,93,860,582),true)
	var text = "维修记录\n记录一：35 根装完满托，还剩 3 根。\n记录二：47 根装完满托，还剩 7 根。\n每托装 5～16 根整数，余数一定比每托容量小。\n\n已试过的槽数\n"
	var tried = []
	for capacity in range(Rules.CAP_MIN,Rules.CAP_MAX+1):
		if Rules.tested(state,0).has(capacity) or Rules.tested(state,1).has(capacity): tried.append(capacity)
	if tried.is_empty(): text += "还没试过任何槽数。\n"
	for capacity in tried.slice(0,7):
		var marks = []
		for record in range(2):
			var mark = "—"
			if Rules.tested(state,record).has(capacity): mark = "相符" if Rules.matches(record,capacity) else "不符"
			marks.append("记录%s %s"%[["一","二"][record],mark])
		text += "%d 槽：%s\n"%[capacity," · ".join(marks)]
	if tried.size() > 7: text += "…还有 %d 个槽数没列出来。\n"%(tried.size()-7)
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n两张都认的只有 8 槽：32=4×8、40=5×8，35 剩 3、47 剩 7。"
	UIStyle.text(overlay,text,Rect2(250,121,780,440),19,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(741,589,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：提出槽数后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

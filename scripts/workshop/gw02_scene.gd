extends "res://scripts/workshop/workshop_host.gd"
const Rules = preload("res://scripts/workshop/gw02_rules.gd")
const World = preload("res://scripts/workshop/gw02_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：护栏缺 27 枚可安装的卡销，架上的 8 片铜料正好都要用掉。",
	"嗒嗒：每片配四孔模或七孔模，一次出 4 枚或 7 枚。两种模这一批都要开。",
	"小岚：慢着——每种模第一次加工的那一整批要先封存检测，不算安装。"]
const AFTER = ["嗒嗒：四孔 6 片、七孔 2 片，一共 38 枚；两盒留样封存 11 枚，护栏正好装上 27 枚。",
	"嗒嗒：以前我只记「做出来多少」，忘了「能拿去装的有多少」。",
	"小岚：先把拿走的补回来，再数能装的数量。走，去看升降台和小车的时间。"]
var selected = Rules.SMALL
var gw_pending_feedback = ""
# Q/W/E/R/T/Y/U/I 在 Godot 里不是连续键码（KEY_E=69 反而小于 KEY_I=73），
# 只能查表，不能写成区间。
const SHEET_KEYS = [KEY_Q,KEY_W,KEY_E,KEY_R,KEY_T,KEY_Y,KEY_U,KEY_I]

func configure() -> void:
	scene_id = "assembly"; level_id = "GW02"; title = "留样之后，还缺多少"
	if save_path.is_empty(): save_path = Catalog.save_path("GW02")
	rules = Rules; world_script = World
	durations = {"approach":2.4,"pressing":4.4,"delivery":3.4}
	zoom_stages = []
	selected = Rules.SMALL

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func goal_line() -> String: return "护栏需要 27 枚 · 8 片铜料全用 · 两种模都要开"
func status_line() -> String: return "已选 %d / %d 片" % [Rules.assigned(state),Rules.SHEETS]
func submit_label() -> String: return "试压 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走进装配间","ready":"开始选模具",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在装配间","重新体验"]
func reset_prompt() -> Array: return ["把 8 片铜料的模具全部抹掉？\n本次试压与求助次数仍保留。","继续选模","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "8 片铜料排在工作台上，压机停在旁边。"
		"ready": return "先挑一种模，再逐片盖上去。四孔出 4 枚，七孔出 7 枚。"
		"puzzle": return "8 片都要选模，两种模都要用；试压时会看到哪两批被封存。"
		"pressing": return "压机按排产顺序逐片落下，每种模的第一批送进留样盒……"
		"delivery": return "护栏上的卡销一枚枚装上去，数目对上了。"
		"aftermath": return AFTER[state.beat]
		"complete": return "先把拿走的补回来，再数能安装的数量。"
	return ""

func build() -> void:
	# 两枚模具按钮要看得见字：hotspot() 会把文字收进 tooltip，这里只挂提示、保留按钮外观。
	for mould in Rules.MOULDS:
		var id = "mould_%d"%mould
		add_button(id,"四孔模 4" if mould == Rules.SMALL else "七孔模 7",mould_rect(mould),select_mould.bind(mould))
		buttons[id].tooltip_text = "选中后逐片盖章 · 键盘 %d"%(1 if mould == Rules.SMALL else 2)
		UIStyle.style_button(buttons[id],mould == selected)
	for i in range(Rules.SHEETS):
		add_hotspot("sheet_%d"%i,world.sheet_rect(i),stamp_sheet.bind(i),
			"第 %d 片 · 盖上%s（键盘 %s）"%[i+1,"四孔模" if selected == Rules.SMALL else "七孔模","QWERTYUI"[i]])

func mould_rect(mould: int) -> Rect2:
	return Rect2(20,204,148,46) if mould == Rules.SMALL else Rect2(176,204,148,46)

func extra() -> void:
	# 基类宿主只排底栏那几枚按钮，回看面板得各关自己挂；extra() 在每一格都会跑到。
	add_button("journal","回看与发现",Rect2(786,654,124,46),journal).disabled = transient > 0
	if state.stage != "puzzle": return
	sign_text("当前模具：%s"%("四孔模（4 枚）" if selected == Rules.SMALL else "七孔模（7 枚）"),Rect2(486,596,348,44),19)

func snapshot(v: Dictionary) -> Dictionary: return {"molds":v.molds.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.molds = Rules.empty(); return n

func select_mould(mould: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	selected = mould; message = ""; refresh()
	buttons["mould_%d"%mould].grab_focus()

func stamp_sheet(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.set_mould(state,index,selected)
	if next.is_empty(): message = "这一片盖不上模。"; refresh(); return
	place(next)

# 试压失败时，理由要跟着候选一起落盘：动画结束那一格也走 apply_committed。
func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	var previous_stage = state.stage
	super.apply_committed(candidate,next_history)
	if previous_stage == "pressing" and candidate.stage == "puzzle":
		message = Rules.shortfalls(candidate)[0]; refresh()
	elif not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

# 8 片选满就允许试压：错答案也看得到这一台出了什么，宿主只拦「还没选满」。
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle" and not Rules.ready_to_press(state):
		var n = state.duplicate(true); n.attempts = mini(1000000,n.attempts+1)
		gw_pending_feedback = Rules.shortfalls(state)[0]
		commit(n,history); return
	commit(Rules.advance(state),history)

# 提示文字要跟着候选一起落盘：写盘失败时，重试走的是 apply_committed 这条共用路径，
# 直接写 message 会在重试成功后被清掉（基类 apply_committed 先把 message 置空）。
func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	if texts.is_empty(): return
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	return ["封存的那两批不算安装，可它们确实是这 8 片做出来的：留样也是产量。",
		"两种模各封存一整批：一盒 4 枚、一盒 7 枚，共 11 枚要先补回来。8 片一共要出 27+11=38 枚。",
		"如果 8 片全用四孔模，只有 32 枚，比 38 枚少 6 枚。",
		"每把一片换成七孔模就多 3 枚：6÷3=2，所以七孔 2 片、四孔 6 片。哪两片用七孔模都合法。"]

func handle_key(key: int) -> bool:
	if key == KEY_1: select_mould(Rules.SMALL)
	elif key == KEY_2: select_mould(Rules.LARGE)
	else:
		var index = SHEET_KEYS.find(key)
		if index < 0: return false
		stamp_sheet(index)
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,133,780,502),true)
	var text = "装配间规则\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	text += "\n\n四孔模一次出 4 枚，七孔模一次出 7 枚。8 片全部使用，两种模都要开。"
	text += "\n每种模第一次加工的那一整批要封存检测，不装到护栏上。"
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n\n先补回留样：\n8 片共出 %d 枚，封存 4+7=11 枚，能安装 %d 枚。\n七孔 2 片、四孔 6 片。" % [Rules.produced(state),Rules.installed(state)]
	UIStyle.text(overlay,text,Rect2(290,161,700,389),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,569,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：选好一片后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/workshop/gw03_rules.gd")
const World = preload("res://scripts/workshop/gw03_world.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const ARRIVAL = ["嗒嗒：余下三托要接着交出去，可吊台和小车总是错开。",
	"小岚：吊台第 2 拍第一次到，往后每 3 拍一次；小车第 3 拍第一次到，往后每 4 拍一次。",
	"嗒嗒：码头的放行灯第 3 拍第一次亮，往后每 5 拍亮一次，只亮那一拍。三个都碰上才接得上货。"]
const AFTER = ["嗒嗒：第 23 拍！吊台到了、小车到了，灯也正好亮着。",
	"小岚：11 拍上两机确实碰头，可灯没亮——条件要一起成立才算数。",
	"嗒嗒：第一托交出去了。剩下两托要赶下一班船，那边从第 0 拍重新计时。"]
var gw_pending_feedback = ""
# 三条节拍带各挂一个整条热区，点哪一格由横坐标算出来：41 个 26 像素的小格子当按钮太小了。
func configure() -> void:
	scene_id = "dock"; level_id = "GW03"; title = "相遇了，还不能交接"
	if save_path.is_empty(): save_path = Catalog.save_path("GW03")
	rules = Rules; world_script = World
	durations = {"approach":2.2,"delivery":3.6}
	zoom_stages = []

func _ready() -> void:
	super._ready()
	get_window().title = "齿轮工坊 · GW03 相遇了，还不能交接"

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func chapter_label() -> String: return "齿轮工坊"

func goal_line() -> String: return "1～40 拍 · 三者同一拍才接得上货"
func status_line() -> String: return "第 %d 拍 · 已运行 %d 拍" % [state.probe,state.watched.size()]
func submit_label() -> String: return "定为交接点 Space"

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "走向节拍表","ready":"开始逐拍查看",
		"aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验这一幕？","留在码头","重新体验"]
func reset_prompt() -> Array: return ["把看过的拍号全部抹掉，从头查起？\n求助级别仍保留。","继续查看","全部抹掉"]

func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "三条节拍带铺在码头上，从第 0 拍排到第 40 拍。"
		"ready": return "点节拍带上的任意一格就是运行那一拍；左右键逐拍回看。"
		"puzzle": return "找到 1～40 拍里第一次三者同时，把拍号定为交接点。"
		"delivery": return "吊台落下来，货挂上小车，放行灯正好亮着……"
		"aftermath": return AFTER[state.beat]
		"complete": return "条件要一起成立，才算真的遇上了。"
	return ""

func build() -> void:
	for track in range(3):
		var id = "track_%d"%track
		add_hotspot(id,world.track_rect(track),noop,"点这一格运行那一拍 · %s带"%Rules.TRACK_NAMES[track])
		buttons[id].gui_input.connect(track_clicked.bind(track))
	add_button("prev","上一拍 ←",Rect2(486,596,120,44),step_probe.bind(-1)).disabled = state.probe <= 0
	add_button("next_tick","下一拍 →",Rect2(618,596,120,44),step_probe.bind(1)).disabled = state.probe >= Rules.HORIZON
	add_button("watch","运行此拍 R",Rect2(750,596,150,44),watch_probe)

func extra() -> void:
	add_button("journal","回看与发现",Rect2(786,654,124,46),journal).disabled = transient > 0

func snapshot(v: Dictionary) -> Dictionary: return {"probe":v.probe,"watched":v.watched.duplicate()}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.probe = 0; n.watched = []; return n

func noop() -> void: pass

func track_clicked(event: InputEvent, _track: int) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	watch_tick(world.tick_at(event.position.x))

func watch_tick(tick: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var next = Rules.watch(state,tick)
	if next.is_empty(): return
	message = ""; place(next)

func step_probe(delta: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	place(Rules.move_probe(state,delta))

func watch_probe() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	watch_tick(state.probe)

# 提交失败的说明由基类 advance() 从 shortfalls() 取；这里只在提示落盘失败时补一句。
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
	return ["两条机轨先各列一遍：吊台 2、5、8…，小车 3、7、11…，它们同时出现在哪几拍？",
		"两机同时的拍是 11、23、35。放行灯只在 3、8、13、18、23…亮，而且只亮那一拍。",
		"11 拍上灯没有亮：两条规则成立，不等于三条一起成立。",
		"第 23 拍：吊台到、小车到、放行灯也亮着。这就是 1～40 拍里第一次合法交接。"]

func handle_key(key: int) -> bool:
	if key == KEY_LEFT or key == KEY_A: step_probe(-1)
	elif key == KEY_RIGHT or key == KEY_D: step_probe(1)
	elif key == KEY_R: watch_probe()
	else: return false
	return true

func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,133,780,502),true)
	var text = "节拍表规则\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	text += "\n\n吊台：第 2 拍第一次到，以后每 3 拍一次。"
	text += "\n小车：第 3 拍第一次到，以后每 4 拍一次。"
	text += "\n放行灯：第 3 拍第一次亮，以后每 5 拍亮一次；只亮那一拍。"
	text += "\n\n只有三者同一拍成立，才能交接。第 0 拍不算到达。"
	if state.stage in ["delivery","aftermath","complete"]:
		text += "\n\n第 23 拍：吊台到、小车到、灯亮。\n两机相遇的 11、35 拍都不满足全部三个条件。"
	UIStyle.text(overlay,text,Rect2(290,161,700,389),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,569,225,48),close_modal,true,overlay).grab_focus()

# 空格是招牌动作：选好拍号后不必先把焦点挪到底栏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

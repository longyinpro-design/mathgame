extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/workshop/gw01_rules.gd")
const World = preload("res://scripts/workshop/gw01_world.gd")
const ARRIVAL = ["阿橙：灯轴明明做好了，小车怎么又空着回来了？",
	"嗒嗒：这里有 23 根。本班收 5 个满托，每托 4 根。多的也挤上车？",
	"小岚：先装好整托。装不满的留下维修，别让它们没了去处。"]
const AFTER = ["嗒嗒：五个满托都准备好了！维修盒里的三根，也不会丢掉。",
	"阿橙：等等……托盘还在上面，小车却已经走过去了。",
	"小岚：数量整理好了。下一步，得看看升降台和小车什么时候到。"]
var selected = -1
var gw_focused = true
var gw_pending_feedback = ""

func configure() -> void:
	scene_id = "dock"; level_id = "GW01"; title = "装不满的最后一托"
	if save_path.is_empty(): save_path = "user://profiles/workshop-gw01-1/save-v1.json"
	rules = Rules; world_script = World
	durations = {"approach":2.4,"delivery":4.0}
	zoom_stages = []

func _ready() -> void:
	super._ready()
	get_window().title = "齿轮工坊 · GW01 装不满的最后一托"

func update_camera() -> void:
	world.scale = Vector2.ONE; world.position = Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		gw_focused = false
		if is_instance_valid(world) and state.stage in Rules.ANIMATIONS: paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: gw_focused = true
	else: return
	if is_instance_valid(world):
		world.presentation_paused = modal or paused or not gw_focused
	if buttons.has("pause"): buttons.pause.text = "继续动画" if paused else "暂停动画"

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_visible_in_tree() or modal or paused or not gw_focused: return
	var changed = false
	if transient > 0:
		changed = true
		transient = maxf(0,transient-delta/maxf(0.01,time_scale))
		world.land_progress = 1-transient/LAND_TIME
		if transient == 0: refresh()
	if state.stage in Rules.ANIMATIONS:
		changed = true
		elapsed += delta/maxf(0.01,time_scale)
		world.progress = minf(1,elapsed/duration())
		if world.progress >= 1: commit(Rules.advance(state),history)
	if changed: world.queue_redraw()

func snapshot(v: Dictionary) -> Dictionary: return {"trays":v.trays.duplicate(),"box":v.box}
func cleared_state() -> Dictionary:
	var n = state.duplicate(true); n.trays = [0,0,0,0,0]; n.box = 0; return n
func reset_prompt() -> Array: return ["把五托和维修盒里的灯轴全部放回原处？\n本次求助与验收记录仍保留。","继续整理","全部放回"]
func restart_prompt() -> Array: return ["重新体验这批灯轴的整理？","留在码头","重新体验"]
func line() -> String:
	match state.stage:
		"arrival": return ARRIVAL[state.beat]
		"approach": return "先看一遍：升降台上去的时候，小车从下面经过了。"
		"ready": return "看看这批灯轴：五个托盘、每托四槽；维修盒留给装不成整托的。"
		"puzzle": return "先点一托或维修盒，再放入或取回。整理好了，请嗒嗒验收。"
		"delivery": return "满托已备好，维修用的灯轴留在盒里。升降台试着把第一托抬起来……"
		"aftermath": return AFTER[state.beat]
		"complete": return "这一批整理好了。货还在码头，接下来要让升降台和小车赶上彼此。"
	return ""

func target_name() -> String: return "维修盒" if selected == 5 else "第 %d 托"%(selected+1)
func target_count() -> int: return state.box if selected == 5 else state.trays[selected]
func batch_size() -> int: return Rules.stock(state) if selected == 5 else 4-target_count()

func refresh() -> void:
	if not is_instance_valid(world): return
	world.state = state; world.selected = selected; world.presentation_paused = modal or paused or not gw_focused
	world.queue_redraw()
	clear_children(ui)
	for child in world.get_children(): world.remove_child(child); child.queue_free()
	buttons = {}
	sign_text("齿轮工坊 · 装不满的最后一托",Rect2(24,18,480,52),24)
	sign_text("本班订单：5 个满托，每托 4 根",Rect2(640,18,616,52),22)
	sign_text(message if not message.is_empty() else line(),Rect2(250,92,880,88),20)
	if state.stage == "puzzle":
		for i in range(6):
			var rect = world.box_rect() if i == 5 else world.tray_rect(i)
			var b = add_button("target_%d"%i,"",rect,select_target.bind(i))
			UIStyle.hotspot(b,("维修盒" if i == 5 else "第 %d 托"%(i+1))+" · 键盘 %d"%(i+1))
			b.focus_mode = Control.FOCUS_ALL
			b.disabled = transient > 0
		if selected >= 0:
			sign_text("已选："+target_name(),Rect2(279,514,235,46),20)
			add_button("one","放 1 根 A",Rect2(530,514,160,48),move_goods.bind(1)).disabled = not can_move(1)
			var n = batch_size()
			var batch_label = "放余下 %d 根"%n if selected == 5 else "补满此托 B"
			add_button("batch",batch_label,Rect2(705,514,160,48),batch).disabled = n < 1 or not can_move(n)
			add_button("take","取回 1 根 D",Rect2(880,514,175,48),move_goods.bind(-1)).disabled = not can_move(-1)
		else: sign_text("点选托盘 1—5 或维修盒 6",Rect2(326,517,590,44),20)
		add_button("undo","撤销 Z",Rect2(24,650,130,50),undo).disabled = history.is_empty() or transient > 0
		add_button("reset","重摆 X",Rect2(166,650,130,50),confirm_reset).disabled = transient > 0
		add_button("hint","请嗒嗒提醒 H",Rect2(309,650,190,50),hint).disabled = transient > 0
		add_button("deliver","验收整托 Space",Rect2(1010,650,246,50),advance,true).disabled = transient > 0
	elif state.stage in Rules.ANIMATIONS:
		add_button("pause","继续动画" if paused else "暂停动画",Rect2(882,650,150,50),toggle_pause)
		add_button("skip","跳过动画",Rect2(1046,650,210,50),skip_animation)
	else:
		var caption = {"arrival":"继续听他们说" if state.beat < 2 else "看看码头怎么走",
			"ready":"看看这批灯轴","aftermath":"继续听他们说" if state.beat < 2 else "记住这次发现",
			"complete":"重新体验这一关"}
		if caption.has(state.stage): add_button("next",caption[state.stage],Rect2(966,650,290,50),confirm_restart if state.stage == "complete" else advance,true)
	add_button("journal","回看与发现",Rect2(520,650,168,50),journal).disabled = transient > 0
	if state.stage == "complete":
		sign_text("留住剩下的：一托装不满的先留住，下次还能用。",Rect2(276,535,754,54),20)
	if modal:
		for b in buttons.values(): b.disabled = true

func select_target(index: int) -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	selected = index; message = ""; refresh()
	buttons["target_%d"%index].grab_focus()
func can_move(amount: int) -> bool:
	return selected >= 0 and transient <= 0 and not Rules.move(state,selected,amount).is_empty()
func move_goods(amount: int) -> void:
	if modal or transient > 0 or selected < 0 or state.stage != "puzzle": return
	var n = Rules.move(state,selected,amount)
	if n.is_empty(): message = "这一托放不下，或原处没有足够灯轴。取回后可以重新摆。"; refresh(); return
	place(n)
func batch() -> void:
	if selected >= 0 and state.stage == "puzzle": move_goods(batch_size())
func advance() -> void:
	if modal or transient > 0 or state.stage in Rules.ANIMATIONS: return
	if state.stage == "puzzle" and not Rules.solved(state):
		var n = state.duplicate(true); n.attempts = mini(1000000,n.attempts+1)
		gw_pending_feedback = Rules.shortfalls(state)[0]
		commit(n,history)
		return
	commit(Rules.advance(state),history)
# Feedback is installed with the candidate, including retry_save's shared apply path.
func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	super.apply_committed(candidate,next_history)
	if not gw_pending_feedback.is_empty():
		message = gw_pending_feedback; gw_pending_feedback = ""; refresh()

func hint() -> void:
	if modal or transient > 0 or state.stage != "puzzle": return
	var texts = hint_texts()
	var n = state.duplicate(true); n.hint = mini(texts.size(),n.hint+1)
	gw_pending_feedback = texts[n.hint-1]
	commit(n,history)

func hint_texts() -> Array:
	var next = ""
	for i in range(5):
		if state.trays[i] < 4:
			next = "选第 %d 托，点「补满此托」。"%(i+1); break
	if state.trays == [4,4,4,4,4]: next = "五托已满。把剩下的灯轴放进维修盒。"
	elif state.box > 3: next = "维修盒先取回几根，让五个托盘都有机会装满。"
	return ["先看本班收几托、每托几个槽，余下的灯轴也要有去处。",
		"可以先装一个满托，再看原处还剩多少。不必逐根点。",
		"五托每托四根，共要二十根；和原有的二十三根比一比。",
		"示范下一步："+next]
func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_6: select_target(key-KEY_1)
	elif key == KEY_A: move_goods(1)
	elif key == KEY_B: batch()
	elif key == KEY_D: move_goods(-1)
	else: return false
	return true
func journal() -> void:
	if modal or transient > 0: return
	modal = true; refresh(); clear_children(overlay)
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.07,0.82); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(250,153,780,462),true)
	var text = "码头手记\n" + "\n".join(ARRIVAL.slice(0,state.beat+1) if state.stage == "arrival" else ARRIVAL)
	if state.stage == "complete": text += "\n\n留住剩下的\n23 根 = 5 托 × 4 根 + 维修盒 3 根。\n只是整理好，货还没有交到小车。"
	UIStyle.text(overlay,text,Rect2(290,181,700,349),20,UIStyle.DARK)
	add_button("close_journal","回到现场",Rect2(761,549,225,48),close_modal,true,overlay).grab_focus()

# Space is the advertised inspection shortcut even immediately after choosing a target.
# Enter retains normal focused-button activation for Tab navigation.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and state.get("stage") == "puzzle" and not modal:
		advance(); get_viewport().set_input_as_handled()

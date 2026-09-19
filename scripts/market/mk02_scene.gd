extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk02_rules.gd")
const World = preload("res://scripts/market/mk02_world.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const HarborSample = preload("res://scripts/market/mk01_scene.gd")
const LINES = ["扣扣：种子先寄存到育苗铺……这次的回礼，我可以少拿一点。","小岚：别急着让步。台面上有 8 颗铜果，门口挂着两条公开的约定。","陶姨：2 颗铜果换 3 卷线，2 卷线换 1 根灯芯，只能整组换。码头要 5 根灯芯，扣扣的捆货绳还差 2 卷线。"]

func configure() -> void:
	scene_id = "nursery"; level_id = "MK02"; title = "育苗铺的回礼"
	# A playtest injects its own /tmp path before the scene is added, so defaults never win.
	if save_path.is_empty(): save_path = "user://profiles/market-mk02-1/save-v1.json"
	durations = {"approach":1.6,"delivery":4.2}
	rules = Rules; world_script = World
	origin = Bridge.origin; Bridge.origin = ""

# A batched exchange plays longer, but never faster per group than a single one.
func duration() -> float:
	if state.stage == "exchanging": return 0.8 + 0.22 * (state.exchange[1] if state.exchange.size() == 2 else 1)
	return durations[state.stage]

func goal_line() -> String: return "回礼：码头 5 根灯芯 · 扣扣留下 2 卷线 · 铜果要用完"
func status_line() -> String: return "台面：%d 卷线 · %d 根灯芯"%[Rules.spools_loose(state),Rules.wicks_loose(state)]
func submit_label() -> String: return "验货交货"
func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < 2 else "靠近育苗铺","ready":"开始兑换","complete":"重新体验"}
func restart_prompt() -> Array: return ["重新体验育苗铺这一幕？","留在育苗铺","重新体验"]
func reset_prompt() -> Array:
	return ["把交付架和修补台上的货全部放回台面？\n已经换好的组不会退回，你仍留在育苗铺。","继续摆放","全部放回台面"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "两条约定就钉在柜面上，扣扣把货物一件件搬过来。"
		"ready": return "只能整组兑换：一次 2 颗铜果，或者一次 2 卷线。"
		"puzzle": return "换出来的货先堆在台面：灯芯上交付架，给扣扣的线挂上修补台。"
		"exchanging": return "扣扣抱着货物一件件搬……这一组已经算进去了。"
		"delivery": return "码头工：5 根灯芯到位！扣扣：这两卷线……真的是留给我的？"
		"complete": return "小岚：说好的回礼，一卷都不能少。育苗铺的第一封回信寄出去了。"
	return ""

func build() -> void:
	for slot in range(Rules.RACK_SLOTS):
		add_hotspot("rack_%d"%slot,world.rack_rect(slot),choose_rack.bind(slot),
			"码头交付架第%d位：%s"%[slot+1,"空着，点一下放灯芯" if state.rack[slot] == 0 else "点一下放回台面"])
	for slot in range(Rules.HOOK_SLOTS):
		add_hotspot("hook_%d"%slot,world.hook_rect(slot),choose_hook.bind(slot),
			"修补台挂钩%d：%s"%[slot+1,"空着，点一下挂线卷" if state.hook[slot] == 0 else "点一下放回台面"])
	for rule in range(2):
		var times = Rules.affordable(state,rule)
		var x = 352 + rule * 242
		var single = add_button("single_%d"%rule,"换 1 组",Rect2(x,560,100,44),do_exchange.bind(rule,1))
		single.disabled = times < 1 or transient > 0
		var batch = add_button("batch_%d"%rule,"全换完",Rect2(x+106,560,92,44),do_exchange.bind(rule,times))
		batch.disabled = times < 1 or transient > 0
		batch.tooltip_text = "一次换满 %d 组，随后一次性演出"%times
		var pool = Rules.fruits_left(state) if rule == 0 else Rules.spools_loose(state)
		UIStyle.text(ui,"%s %d 个 · 可换 %d 组"%["铜果" if rule == 0 else "线卷",pool,times],Rect2(x,608,198,32),16)

func extra() -> void:
	if state.stage != "complete": return
	# The receipt restates the exchange the player actually performed.
	UIStyle.panel(ui,Rect2(196,368,412,152))
	UIStyle.text(ui,"回执 · 育苗铺 → 码头\n约定一 ×%d：%d 颗铜果换成 %d 卷线\n约定二 ×%d：%d 卷线换成 %d 根灯芯\n交付架 %d 根 · 修补台 %d 卷 · 台面已空"%[
		state.a,Rules.GROUP*state.a,Rules.SPOOL_PER_GROUP*state.a,state.b,Rules.GROUP*state.b,Rules.WICK_PER_GROUP*state.b,
		state.rack.count(1),state.hook.count(1)],Rect2(212,380,382,132),18)

func exit_buttons() -> void:
	if origin == "mk01": add_button("back_camp","办完回礼 · 回营地",Rect2(690,646,280,54),go_camp)

func snapshot(value: Dictionary) -> Dictionary:
	return {"a": value.a, "b": value.b, "rack": value.rack.duplicate(), "hook": value.hook.duplicate()}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true); next.rack = Rules.rack_empty(); next.hook = Rules.hook_empty()
	return next

func hint_texts() -> Array:
	var groups = Rules.group_limit(0)
	var spools = Rules.SPOOL_PER_GROUP * groups
	return ["只能整组换：%d 颗铜果 → %d 卷线，%d 卷线 → %d 根灯芯；同一组不能拆开用。"%[Rules.GROUP,Rules.SPOOL_PER_GROUP,Rules.GROUP,Rules.WICK_PER_GROUP],
		"%d 颗铜果正好换满 %d 组，得到 %d 卷线——铜果要全用完，线卷才只在两个去处之间分。"%[Rules.FRUITS,groups,spools],
		"%d 卷线里留 %d 卷给扣扣，另外 %d 卷换 %d 组，正好是码头要的 %d 根灯芯。"%[spools,Rules.SPOOL_ORDER,spools-Rules.SPOOL_ORDER,Rules.WICK_ORDER,Rules.WICK_ORDER]]

func choose_rack(slot: int) -> void:
	place(Rules.put_rack(state,slot) if state.rack[slot] == 0 else Rules.take_rack(state,slot))

func choose_hook(slot: int) -> void:
	place(Rules.put_hook(state,slot) if state.hook[slot] == 0 else Rules.take_hook(state,slot))

func do_exchange(rule: int, times: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.exchange(state,rule,times)
	if next.is_empty():
		var pool = Rules.fruits_left(state) if rule == 0 else Rules.spools_loose(state)
		message = "凑不成整组：%s 只剩 %d 个，%d 个才能换下一样。"%["铜果" if rule == 0 else "线卷",pool,Rules.GROUP]
		refresh(); return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next,next_history)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_5: choose_rack(key-KEY_1)
	elif key == KEY_6 or key == KEY_7: choose_hook(key-KEY_6)
	elif key == KEY_Q: do_exchange(0,1)
	elif key == KEY_A: do_exchange(0,Rules.affordable(state,0))
	elif key == KEY_W: do_exchange(1,1)
	elif key == KEY_S: do_exchange(1,Rules.affordable(state,1))
	else: return false
	return true

func go_camp() -> void:
	if modal or transient > 0: return
	HarborSample.entry = "return"
	get_tree().change_scene_to_file(FOREST_SCENE)

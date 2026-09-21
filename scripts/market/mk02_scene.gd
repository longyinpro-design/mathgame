extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk02_rules.gd")
const World = preload("res://scripts/market/mk02_world.gd")
const HarborSample = preload("res://scripts/market/mk01_scene.gd")
const LINES = ["扣扣：种子先寄存到育苗铺……这次的回礼，我可以少拿一点。","小岚：别急着让步。台面上有 8 颗铜果，门口挂着两条公开的约定。","陶姨：2 颗铜果换 3 卷线，2 卷线换 1 根灯芯，只能整组换。码头要 5 根灯芯，扣扣的捆货绳还差 2 卷线。"]
# 回执板与它内框的字：写成常量是给实窗检查用的，它要拿这块板的下沿去比柜面那一排木牌。
const RECEIPT = Rect2(196,344,412,152)
const RECEIPT_TEXT = Rect2(212,356,382,132)

func configure() -> void:
	scene_id = "nursery"; level_id = "MK02"; title = "育苗铺的回礼"
	# A playtest injects its own /tmp path before the scene is added, so defaults never win.
	if save_path.is_empty(): save_path = "user://profiles/market-mk02-1/save-v1.json"
	durations = {"approach":1.6,"delivery":4.2}
	# 换货那一格必须还贴着同一张台面：只写 puzzle 的话，每按一次「换 1 组」镜头先从 1.10
	# 弹回 1.00 演完再弹回去，一组货搬完画面硬跳两下（本章另外六关的交换幕都在这一列里）。
	zoom_stages = ["puzzle","exchanging"]
	rules = Rules; world_script = World

# A batched exchange plays longer, but never faster per group than a single one.
func duration() -> float:
	if state.stage == "exchanging": return 0.8 + 0.22 * (state.exchange[1] if state.exchange.size() == 2 else 1)
	return durations[state.stage]

func goal_line() -> String:
	return "回礼：码头 %d 根灯芯 · 扣扣留下 %d 卷线 · 铜果要用完"%[Rules.WICK_ORDER,Rules.SPOOL_ORDER]
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
		"puzzle": return "线退不回来了：交付架只放得下 %d 根灯芯，回本关开头重摆。"%Rules.RACK_SLOTS \
			if Rules.stranded(state) else "换出来的货先堆在台面：灯芯上交付架，给扣扣的线挂上修补台。"
		"exchanging": return "扣扣抱着货物一件件搬……这一组已经算进去了。"
		"delivery": return "码头工：5 根灯芯到位！扣扣：这两卷线……真的是留给我的？"
		"complete": return "小岚：说好的回礼，一卷都不能少。育苗铺的第一封回信寄出去了。"
	return ""

func build() -> void:
	# 七处落点共用一套 1—7 编号：牌上写的第几位，就是键盘上按的那个数。
	# 原先挂钩叫「挂钩1／挂钩2」，可按的却是 6 和 7——照着 tooltip 去按 1，动的是交付架。
	for slot in range(Rules.RACK_SLOTS):
		add_hotspot("rack_%d"%slot,world.rack_rect(slot),choose_rack.bind(slot),
			"码头交付架第%d位：%s"%[slot+1,"空着，点一下放灯芯" if state.rack[slot] == 0 else "点一下放回台面"])
	for slot in range(Rules.HOOK_SLOTS):
		add_hotspot("hook_%d"%slot,world.hook_rect(slot),choose_hook.bind(slot),
			"扣扣的修补台第%d位：%s"%[Rules.RACK_SLOTS+slot+1,
				"空着，点一下挂线卷" if state.hook[slot] == 0 else "点一下放回台面"])
	for rule in range(2):
		var times = Rules.affordable(state,rule)
		var x = 352 + rule * 242
		var single = add_button("single_%d"%rule,"换 1 组",Rect2(x,560,100,44),do_exchange.bind(rule,1))
		single.disabled = times < 1 or transient > 0
		var batch = add_button("batch_%d"%rule,"全换完",Rect2(x+106,560,92,44),do_exchange.bind(rule,times))
		batch.disabled = times < 1 or transient > 0
		# 「一次性演出」是说给做动画的人听的，不是说给小孩听的。
		batch.tooltip_text = "一次换满 %d 组，扣扣一趟全搬过去"%times
		var pool = Rules.fruits_left(state) if rule == 0 else Rules.spools_loose(state)
		# 量词跟着货走：本章通篇是 8 颗铜果、2 卷线，这里不能改口叫「个」。
		UIStyle.text(ui,"%s %d %s · 可换 %d 组"%["铜果" if rule == 0 else "线卷",pool,
			"颗" if rule == 0 else "卷",times],Rect2(x,608,198,32),16)
	# 走死了才多出来的这一枚：不代解、不高亮，只把还回得去的那扇门摆出来（铜鹭巡守同款）。
	if Rules.stranded(state):
		var escape = add_button("plan","回本关开头",Rect2(1020,586,235,48),confirm_restart)
		escape.tooltip_text = "换出去的线退不回铜果，灯芯也退不回线卷：从这一幕的开头重新兑换，不动其他关卡与森林岛进度"
		escape.disabled = transient > 0

func extra() -> void:
	if state.stage != "complete": return
	# The receipt restates the exchange the player actually performed.
	# 这块板原先下沿在 520，正好把柜面上那两条公开约定各切掉一截（牌子顶边在世界 514，
	# complete 这一格镜头是 1.0 倍，两者就是同一套坐标）；抬 24 像素让板底停在 496。
	UIStyle.panel(ui,RECEIPT)
	UIStyle.text(ui,"回执 · 育苗铺 → 码头\n约定一 ×%d：%d 颗铜果换成 %d 卷线\n约定二 ×%d：%d 卷线换成 %d 根灯芯\n交付架 %d 根 · 修补台 %d 卷 · 台面已空"%[
		state.a,Rules.GROUP*state.a,Rules.SPOOL_PER_GROUP*state.a,state.b,Rules.GROUP*state.b,Rules.WICK_PER_GROUP*state.b,
		state.rack.count(1),state.hook.count(1)],RECEIPT_TEXT,18)

func exit_buttons() -> void:
	if origin == "mk01": add_button("back_camp","办完回礼 · 回营地",Rect2(690,646,280,54),go_camp)
	# 营地的旅客经 MK01 → MK02 走进岛里，这一张是航图的第一道门：不给他这条，
	# 后面十六站在游戏里就没有路可以到达（从航图进来的场合由宿主给「返回千灯航图」）。
	if origin != "hub": add_button("open_hub","去千灯航图",Rect2(390,646,280,54),go_hub)

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
		message = "凑不成整组：%s 只剩 %d %s，%d %s才能换下一样。"%["铜果" if rule == 0 else "线卷",pool,
			"颗" if rule == 0 else "卷",Rules.GROUP,"颗" if rule == 0 else "卷"]
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

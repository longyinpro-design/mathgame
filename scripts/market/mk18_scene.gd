extends "res://scripts/market/level_host.gd"
# MK18 万签守约兽「让每一盏灯都有回信」：全章的联合履约，三阶段共用一台机关。
# 宿主只在 stage == "puzzle" 时交给 build() 摆热点，所以三个阶段留在同一幕里，
# 由规则层从账（bought / handed）推出当前阶段；玩家永远没有第二个「阶段」可改。
# 第一阶段在采购台上按包种一次选数量、一次提交整单；第二阶段在三处托盘与领航灯之间拆开分配，
# 不再购买，整单预览在实际交货前可以撤回；第三阶段亲手装灯、把三张真实回执投进万签胸前的空信槽。
const Rules = preload("res://scripts/market/mk18_rules.gd")
const World = preload("res://scripts/market/mk18_world.gd")
const KIND_KEYS = [KEY_1, KEY_2, KEY_3]
const LINES = [
	"小岚：三条街今晚一起报数——桥头 3/1、中街 4/2、西坡 5/3。\n万签背着灯架站在码头尽头，一次也没敢抬脚。",
	"万签：我身上挂的全是旧货签，每张都写着「已收」。\n可是没有一盏灯回过信……我不知道哪一张才算数。",
	"扣扣：今晚一起点灯。领航灯还要另留 2 提油 1 束芯，\n那一份也得算进同一张订单里。",
	"小岚：那就当场把单位说定：1 提油、1 束芯。总计 14 提油 7 束芯，\n没有隐藏收费——先写一张共同订单。",
]
const CLARIFY_LINES = [
	"信使：中街与西坡的回信都在这儿，两种安排各自带着自己的印记。",
	"信使：这一局要兑现哪一张，读信之前就已经定在纸上了。\n把两封信翻来覆去地读，也不会换成另一张。",
]
const BRANCH_LINE = [
	"小岚：甲印有效——中街 4 提油 2 束芯、西坡 5 提油 3 束芯，维持原安排。",
	"小岚：乙印有效——中街改成 5 提油 1 束芯、西坡 4 提油 4 束芯，总需求没变。",
]

func configure() -> void:
	scene_id = "dock"; level_id = "MK18"; title = "万签守约兽"
	# 试玩与实窗检查会在加入场景树前写入自己的 /tmp 路径，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk18-1/save-v1.json"
	durations = {"approach": 1.8, "stocking": 2.6, "delivering": 2.8, "lighting": 2.4, "voyage": 3.4}
	zoom_stages = ["puzzle"]
	rules = Rules; world_script = World

# ---- 三阶段共用的读数 ----
func phase() -> int: return Rules.phase_of(state)

func goal_line() -> String:
	match phase():
		1: return "共同订单：14 提油 7 束芯 · 预算 29 票"
		2: return "按本局印记摆货：不再购买，领航灯留 2/1"
		3: return "点亮领航灯，再投进三张真实回执"
	return ""

func status_line() -> String:
	match phase():
		1: return Rules.order_caption(state.order)
		2:
			var left = Rules.alloc_left(state.alloc)
			if state.preview == 1: return "整单预览已摆给三街 · 还没交货"
			return "货台还剩 %s" % Rules.goods(left[Rules.OIL], left[Rules.WICK])
		3:
			var sealed := 0
			for one in state.sealed: sealed += one
			return "领航灯 %s · 回执 %d/3" % ["已点亮" if state.lamp == 1 else "还空着", sealed]
	return ""

func submit_label() -> String:
	match phase():
		2: return "确认按这一单交货" if state.preview == 1 else "摆好了，交整单预览"
		3: return "送灯出海"
	return "提交共同订单"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.ARRIVAL_BEATS - 1 else "走上码头",
		"ready": "开始办这一晚的订单",
		"clarify": "再读一封信" if state.beat < Rules.CLARIFY_BEATS - 1 else "按这一张摆货",
		"complete": "再守一次约"}

func restart_prompt() -> Array:
	return ["重新体验这一幕？\n两种回信会重新轮流固定，本关其他记录不变。", "留在现场", "重新体验"]

func reset_prompt() -> Array:
	match phase():
		2: return ["把三处摆好的货全部放回货台？\n买回来的整包不会退，领航灯那一份也回到台上。", "继续摆放", "全部放回货台"]
		3: return ["把领航灯里的油芯抽出、三张回执取回？\n三街已经交出去的货不会退回来。", "继续点灯", "抽出并取回"]
	return ["把采购台上的订单全部清空？\n还没提交，一票也没花。", "继续挑包", "清空订单"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "万签把灯架从背上卸下来，总货栈的采购台在码头尽头摊开。"
		"ready": return "先把这一晚要买的整包选出来：按包种一次选数量，一次提交。"
		"puzzle": return puzzle_line()
		"stocking": return "货搬到桥头街，托盘落回台面……更正信就是这时候送到的。"
		"clarify": return CLARIFY_LINES[state.beat] if state.beat < 2 else BRANCH_LINE[state.branch]
		"delivering": return "中街、西坡按这一单交货，领航灯那一份留在货台上不动。"
		"lighting": return "万签胸前的空信槽收到三张真实回执，咔哒一声合拢了。"
		"voyage": return "灯架展开成一艘明亮的灯船，往海面上走。"
		"complete": return "扣扣：每一盏灯都有回信了。\n小岚：这一次没有人被落下——回去把航图点亮吧。"
	return ""

func puzzle_line() -> String:
	match phase():
		1: return "采购台只卖三种封装：A 3油+1芯 5票、B 1油+2芯 4票、C 2油 3票。\n预算 29 票，库存 A4 B4 C5，必须恰好凑成 14 提油 7 束芯。"
		2: return "桥头街已经交完，中街与西坡的最终安排现在才公开。\n封装可以拆开分配，但不再购买；摆齐了先交整单预览。"
		3: return "三街都齐了。亲手把预留的 2 提油 1 束芯装进领航灯，\n再把三条街的回执一张张投进万签胸前的空信槽。"
	return ""

# ---- 热点：三阶段各摆自己那一套，每一处都有中文说明 ----
func build() -> void:
	match phase():
		2: build_allocating()
		3: build_lighting()
		_: build_purchasing()

func build_purchasing() -> void:
	for kind in range(Rules.KINDS):
		for index in range(Rules.STOCK[kind]):
			var booked = index < state.order[kind]
			var tip = "%s 种第 %d 包 · %s · 库存 %d 包：" % [Rules.PACK_NAMES[kind], index + 1,
				Rules.pack_caption(kind), Rules.STOCK[kind]]
			tip += "已订着，点一下退到 %d 包" % index if booked else "点一下订到 %d 包" % (index + 1)
			add_hotspot("pack_%d_%d" % [kind, index], world.pack_rect(kind, index),
				choose_pack.bind(kind, index), tip)

func slot_foot(slot: int) -> Vector2:
	return world.lamp_cells_foot() if slot == Rules.SLOTS - 1 else world.board_foot(slot + 1)

func unit_word(kind: int) -> String: return "1 提灯油" if kind == Rules.OIL else "1 束灯芯"

func build_allocating() -> void:
	for slot in range(Rules.SLOTS):
		var foot = slot_foot(slot)
		var name = Rules.LINES[slot + 1]
		for kind in range(2):
			add_hotspot("put_%d_%d" % [slot, kind], world.put_rect(foot, kind),
				do_put.bind(slot, kind), "给%s摆 %s（整单预览会先撤回）" % [name, unit_word(kind)])
			add_hotspot("back_%d_%d" % [slot, kind], world.back_rect(foot, kind),
				do_back.bind(slot, kind), "从%s取回 %s，放回货台" % [name, unit_word(kind)])
	if state.preview == 1:
		add_hotspot("revoke", world.pool_rect(), do_revoke, "撤回这份整单预览，回到摆放")

func build_lighting() -> void:
	add_hotspot("lamp", world.lamp_rect(), do_lamp,
		"把预留的 %s 装进领航灯" % Rules.goods(Rules.RESERVED[Rules.OIL], Rules.RESERVED[Rules.WICK])
			if state.lamp == 0 else "把领航灯里的油芯先抽回货台")
	for slot in range(3):
		add_hotspot("seal_%d" % slot, world.seal_rect(slot), do_seal.bind(slot),
			"%s已经交齐：把这张真实回执投进万签胸前的空信槽" % Rules.LINES[slot]
				if state.sealed[slot] == 0 else "把%s的回执从信槽里取回" % Rules.LINES[slot])

func extra() -> void:
	if state.stage != "complete": return
	# 结局面板只复述玩家本局真正做过的事：买了哪一单、按哪一封回信各街拿到多少。
	var body = "回执 · 让每一盏灯都有回信\n本局兑现：%s\n" % Rules.branch_word(state.branch)
	for row in Rules.delivery_lines(state): body += row + "\n"
	body += "采购：%s · 共 %d 票" % [Rules.purchase_line(state.bought), Rules.cost_of(state.bought)]
	# 七行 × 18 号（汉字行高 27）要 189 高，盒子给到 226；宽 588 让最长一行也不用折行。
	UIStyle.panel(ui, Rect2(96, 300, 620, 250))
	UIStyle.text(ui, body, Rect2(112, 312, 588, 226), 18)

func exit_buttons() -> void:
	# 从航图进来的场合由宿主给出「返回集市航图」；单独启动本关时也要有一条回去的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"phase": Rules.phase_of(value), "order": value.order.duplicate(true),
		"alloc": value.alloc.duplicate(true), "preview": value.preview,
		"lamp": value.lamp, "sealed": value.sealed.duplicate(true)}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	match phase():
		2: next.alloc = Rules.empty_alloc(); next.preview = 0
		3: next.lamp = 0; next.sealed = Rules.empty_sealed()
		_: next.order = Rules.empty_order()
	return next

# 每一阶段都有自己三级提示：提醒关系 → 收窄关键选择 → 给出具体下一步。
func hint_texts() -> Array:
	match phase():
		2: return ["更正信只改中街与西坡的最终安排：桥头那一份已经交出去了，\n买回来的整包可以拆开分配，但这一阶段不再购买。",
			"先看带印记的那张回执要多少，再数货台上还剩多少：\n领航灯那一份是从剩下的货里留出来的，不是货栈另给的。",
			"按本局印记摆：%s。\n摆齐了三处就交整单预览。" % branch_hint()]
		3: return ["三街都拿到正确数量，才轮到领航灯。\n现在万签胸前的空信槽还张着。",
			"先点领航灯，把预留的 %s 亲手装进去；\n再点三条街托盘上的回执，一张张投进信槽。" % Rules.goods(
				Rules.RESERVED[Rules.OIL], Rules.RESERVED[Rules.WICK]),
			"点亮领航灯，然后依次点桥头、中街、西坡托盘上的回执，\n三张都进了信槽，灯架就展开成灯船。"]
	return ["共同订单要 14 提油 7 束芯，票只有 29 票：\n三种封装的含量与价钱都写在采购台左边。",
		"C 只有油、没有芯：7 束芯只能靠 A 和 B 出。\n先想清楚几包 A、几包 B 凑得出 7 束芯，再拿 C 补油。",
		purchase_step()]

# 第三级提示只给「眼前这一步」：按玩家自己那张订单还差多少说一句，永不打印整解。
func purchase_step() -> String:
	var oil = Rules.oil_of(state.order)
	var wick = Rules.wick_of(state.order)
	if Rules.purchase_ok(state.order):
		return "整单正好 %s、%d 票：按「提交共同订单」一次付清。\n不用一包一包再点八次。" % [
			Rules.goods(oil, wick), Rules.cost_of(state.order)]
	if wick < Rules.TOTAL_WICK:
		return "芯还差 %d 束：一包 B 出 2 束芯。\n把一包 C 换成 B，芯多 2 束、油少 1 提。" % (Rules.TOTAL_WICK - wick)
	if wick > Rules.TOTAL_WICK:
		return "芯多了 %d 束：一包 B 换成一包 C，芯少 2 束、油多 1 提。" % (wick - Rules.TOTAL_WICK)
	if oil < Rules.TOTAL_OIL:
		return "油还差 %d 提：一包 C 出 2 提油、3 票，先加一包 C。" % (Rules.TOTAL_OIL - oil)
	return "油多了 %d 提：减一包 C，或者把一包 C 换成 A。" % (oil - Rules.TOTAL_OIL)

func branch_hint() -> String:
	var rows = Rules.slot_needs(state.branch)
	return "%s %s、%s %s、%s %s" % [Rules.LINES[1], Rules.goods(rows[0][Rules.OIL], rows[0][Rules.WICK]),
		Rules.LINES[2], Rules.goods(rows[1][Rules.OIL], rows[1][Rules.WICK]),
		Rules.LINES[3], Rules.goods(rows[2][Rules.OIL], rows[2][Rules.WICK])]

# ---- 玩家动作 ----
func choose_pack(kind: int, index: int) -> void:
	# 点到第几包就订到第几包；再点已经订着的最前面那一包就退一格。
	place(Rules.set_count(state, kind, index if index < state.order[kind] else index + 1))

func do_put(slot: int, kind: int) -> void: place(Rules.put(state, slot, kind))
func do_back(slot: int, kind: int) -> void: place(Rules.take_back(state, slot, kind))
func do_revoke() -> void: place(Rules.cancel_preview(state))
func do_lamp() -> void: place(Rules.unload_lamp(state) if state.lamp == 1 else Rules.load_lamp(state))
func do_seal(street: int) -> void:
	place(Rules.unseal_receipt(state, street) if state.sealed[street] == 1 else Rules.seal_receipt(state, street))

# 跨阶段推进就把撤销栈清空：上一阶段的摆法不该被撤销回眼前这一阶段。
# 走 apply_committed 而不是 advance()，动画自己走完（或跳过）时同样成立。
func apply_committed(candidate: Dictionary, next_history: Array) -> void:
	if Rules.phase_of(candidate) != Rules.phase_of(state): next_history = []
	super(candidate, next_history)

func handle_key(key: int) -> bool:
	if phase() == 1:
		var kind = KIND_KEYS.find(key)
		if kind >= 0:
			choose_pack(kind, state.order[kind]); return true
		var back = [KEY_Q, KEY_W, KEY_E].find(key)
		if back >= 0:
			choose_pack(back, state.order[back] - 1); return true
	elif phase() == 3 and key == KEY_L:
		do_lamp(); return true
	return false

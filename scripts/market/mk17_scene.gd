extends "res://scripts/market/level_host.gd"
# MK17 铜鹭巡守 · 三次验货：千灯集市第一场首领。
# 铜鹭不质疑玩家聪明与否，它查这一晚的约定能不能在三个码头真的办成：
# 台上六只大包共 18 单位，重新封装只有三次机会，三站各自要 5 / 7 / 6 单位、最多 2 / 4 / 3 包。
# 玩家自己决定怎么封、把哪几包放上验货托盘、按「提交这一站验收」，缺哪条承诺就在提交后按玩家
# 自己的说法讲给他听；二站的旗在关卡创建时已经固定，第一站交完才翻面，重读存档也不会换旗。
const Rules = preload("res://scripts/market/mk17_rules.gd")
const World = preload("res://scripts/market/mk17_world.gd")
const LINES = [
	"小岚：铜鹭来了。它不查你聪明不聪明，\n它查这一晚的约定能不能在三个码头真的办成。",
	"扣扣：六只大包都在台上，一共十八单位。\n重新封装只有三次机会，拆错一次就少一次，它不会白退给你。",
	"铜鹭：三张货单都钉在栏上，现在就能看。\n我按旗收货：旗A 全收，旗B 不接大包。哪一面旗，第一站交完才翻。",
]

func configure() -> void:
	# 抬头木牌内框只有 382：全名「铜鹭巡守 · 三次验货」量到 386，最后一个「货」会被折到板外。
	# 用航图卡上同一个短名，「三次验货」这件事由目标板「18 单位 · 3 次封装」说。
	scene_id = "dock"; level_id = "MK17"; title = "铜鹭巡守"
	# 试玩与实窗检查会在加入场景树前写入自己的 /tmp 路径，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk17-1/save-v1.json"
	durations = {"approach": 1.9, "flag": 2.6, "lift": 2.6, "carrying": 3.2, "delivery": 4.4}
	# 摆货与两次交接都贴着台面看，展翼成搬运台之后镜头退回整个码头（宿主的 delivery 分支负责）。
	zoom_stages = ["puzzle", "flag", "lift"]
	rules = Rules; world_script = World

func goal_line() -> String:
	return "三站各按单位与包数验收：18 单位 · 3 次封装"

func flag_word() -> String:
	return "旗未翻" if state.shown == 0 else Rules.FLAG_SHORT[state.flag]

func status_line() -> String: return "封装余 %d · %s" % [state.chances, flag_word()]

func submit_label() -> String: return "提交这一站验收"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < 2 else "请铜鹭入港",
		"ready": "开始验货", "complete": "再巡一次"}

func restart_prompt() -> Array:
	return ["回到关前重新规划？\n三站的货、三次机会都回到开局，旗也重新掷一面。", "留在码头", "回到关前规划"]
func reset_prompt() -> Array:
	return ["把托盘上的货放回台面？\n已经用掉的封装机会不会退回来。", "继续摆放", "货放回台面"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "铜鹭踏着栈桥走过来，检查旗还收在翼下。"
		# 简报把两条路都说全：鼠标点牌，键盘上 1—4 走封装、Q W E 上货、R 请回最后一包、F 看旗。
		"ready": return "铜鹭：先决定怎么封，再决定交哪几包，货单随时能看。\n点牌或按键都行：1—4 重封，Q W E 上货，R 放回，F 看旗。"
		"puzzle": return puzzle_line()
		"flag": return "铜鹭翻出本局固定的那面验货旗。"
		"lift": return "二站的货吊上蓝船。已交出去的货不回收。"
		"carrying": return "铜鹭收起检查旗，展开双翼，把自己变成搬运台。"
		"delivery": return "码头一盏一盏亮起来：船跟着交出去的货轻轻起伏。"
		"complete": return "铜鹭：三站都按你们自己写的约定办成了。\n今晚的灯船，就载着这批货出海。"
	return ""

func puzzle_line() -> String:
	match state.station:
		1: return "一站要 5 单位、最多 2 包，台上全是 3 单位的大包。\n点封装牌重封一次，再把货放上托盘。"
		2: return "旗已经翻过来了：%s（%s）。\n二站要 7 单位、最多 4 包。" % [Rules.FLAG_SHORT[state.flag], Rules.FLAG_RULE[state.flag]]
		3: return "三站要 6 单位、最多 3 包，固定不接大包。\n剩下的货和封装机会都得留到这里。"
	return ""

# ---- 热点：四条封装走法、三行封包、托盘上的每一包、三张货单与检查旗 ----
func build() -> void:
	for index in range(Rules.OPS.size()):
		add_hotspot("op_%d" % index, world.bench_rect(index), do_op.bind(index), op_tip(index))
	for kind in range(Rules.KINDS):
		add_hotspot("take_%d" % kind, world.stock_row_rect(kind), do_take.bind(kind), take_tip(kind))
	var kinds = Rules.tray_kinds(state)
	for slot in range(kinds.size()):
		add_hotspot("tray_%d" % slot, world.tray_rect(slot), do_unload.bind(slot), unload_tip(slot, kinds[slot]))
	for index in range(Rules.KINDS):
		add_hotspot("berth_%d" % index, world.berth_rect(index), read_berth.bind(index), berth_tip(index))
	add_hotspot("flag", world.flag_rect(), look_flag, flag_tip())

func op_tip(index: int) -> String:
	var op: Dictionary = Rules.OPS[index]
	return "重新封装「%s」· 花 1 次机会，剩 %d 次 · 键盘 %d\n%s" % [op.name, state.chances, index + 1,
		"这一步现在走得通，点一下就走" if Rules.can_apply(state, index) else "现在走不通：点了只会告诉你为什么"]

func take_tip(kind: int) -> String:
	return "把 1 个%s（%d 单位）放上验货托盘 · 台上还有 %d 个 · 键盘 %s\n托盘上的货还没离手，点它可以放回" % [
		Rules.PACK_NAMES[kind], Rules.UNITS[kind], state.stock[kind], ["Q", "W", "E"][kind]]

# 键盘上只有 R 这一颗，管的是最后放上托盘的那一包：其余格子按它不放回东西，就不写这句话。
func unload_tip(slot: int, kind: int) -> String:
	return "把这一包%s放回台面 · 交货之前随时可以反悔%s" % [Rules.PACK_NAMES[kind],
		" · 键盘 R" if slot == Rules.packs_of(state.tray) - 1 else ""]

func berth_tip(index: int) -> String:
	return "看 %s 的货单：%s" % [Rules.STATION_NAMES[index], Rules.rule_caption(state, index)]

func flag_tip() -> String:
	if state.shown == 1:
		return "本局固定的是 %s（%s）· 重新读档也不会换旗 · 键盘 F" % [
			Rules.FLAG_SHORT[state.flag], Rules.FLAG_RULE[state.flag]]
	return "旗还没翻：第一站交完才翻面\n两种可能开局就写在牌上，没人替你猜 · 键盘 F"

# ---- 回执：只复述玩家真正交出去的包与真正翻出来的那面旗 ----
func receipt_lines() -> Array:
	var lines = ["铜鹭验货回执 · 三站全部办成"]
	for index in range(Rules.KINDS):
		lines.append(Rules.delivery_caption(state, index))
	lines.append("验货旗：%s · %s" % [Rules.FLAG_SHORT[state.flag], Rules.FLAG_RULE[state.flag]])
	lines.append("重新封装用去 %d 次 · 余 %d 次" % [Rules.CHANCES - state.chances, state.chances])
	lines.append("台上余货 %d 单位 · 一单位都不剩" % Rules.held_units(state))
	return lines

# 回执钉在左下方：上沿 196 躲开口条（338,98,826,86 的底板画到 184），
# 右沿 388 躲开一站的栈位牌（世界 404..516，complete 这一幕不缩放）。
func receipt_rect() -> Rect2: return Rect2(36, 196, 352, 244)
func receipt_text_rect() -> Rect2:
	var board = receipt_rect()
	return Rect2(board.position + Vector2(16, 12), board.size - Vector2(30, 20))

func extra() -> void:
	if state.stage == "puzzle":
		tune_undo()
		# 撤销整站交货：货和幕一起退回，绝不只把封装机会退回来却留着变出的货。
		# 托盘上还摆着货时牌子照旧挂着，点下去只会如实说「先把它放回台面」——两批货不能叠在一起退。
		if Rules.has_previous_delivery(state):
			add_button("rewind", "退回上一站的货", Rect2(1020, 586, 235, 48), do_undeliver)
		# 走死了也如实说：只在真的办不成时给一条回关前的路，不高亮、不代解。
		if Rules.dead_end(state):
			add_button("plan", "回到关前规划", Rect2(1020, 532, 235, 48), confirm_restart)
	if state.stage == "complete":
		UIStyle.panel(ui, receipt_rect())
		UIStyle.text(ui, "\n".join(receipt_lines()), receipt_text_rect(), 17)

# 撤销只退本站的摆法：上一站的货已经不在本站的账里，按钮就不该亮着骗人点。
func tune_undo() -> void:
	if not buttons.has("undo"): return
	var restorable = not history.is_empty() and Rules.can_restore(state, history.back())
	buttons.undo.disabled = not restorable or transient > 0
	if restorable:
		buttons.undo.tooltip_text = "退回本站上一步摆法（已经花掉的封装机会跟着货一起退）"
		return
	# 这句只指真摆在桌上的牌子：一站、二站没有「退回上一站的货」，没走死时也没有「回到关前规划」，
	# 照着不存在的牌子去摸，玩家只会更确信是自己算错了。
	var exits: Array = []
	if Rules.has_previous_delivery(state): exits.append("退回上一站的货")
	if Rules.dead_end(state): exits.append("回到关前规划")
	buttons.undo.tooltip_text = "本站还没有摆过货：上一站的货不回收" + \
		("，要重来请用「" + "」或「".join(exits) + "」" if not exits.is_empty() else "，先把货摆上托盘")

func exit_buttons() -> void:
	# 从航图进来的场合由宿主给出「返回千灯航图」；单独启动本关时也要有一条回去的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"station": value.station, "stock": value.stock.duplicate(true), "tray": value.tray.duplicate(true),
		"chances": value.chances, "delivered": value.delivered.duplicate(true)}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	next.stock = Rules.sum_packs(state.stock, state.tray)
	next.tray = Rules.empty_packs()
	return next

func hint_texts() -> Array:
	return ["封装只有两条规则：1大 ↔ 1中+1小、2大 ↔ 3中。\n每走一次就少一次机会，反着走同一条也要再花一次。",
		"一站要 5 单位又只收 2 包：手里全是 3 单位的大包，\n只有 3+2 这一种摆法——所以第一次机会非动不可。",
		"先把 1 大 拆成 1 中 1 小，交「1大+1中」给一站。\n剩下 4 大 1 小要养住 7 单位与 6 单位两站：旗B 就得先并 2 大换 3 中。"]

func do_op(index: int) -> void:
	var next = Rules.apply_op(state, index)
	if next.is_empty():
		message = Rules.refusal(state, index); refresh(); return
	place(next)

func do_take(kind: int) -> void:
	var next = Rules.load_pack(state, kind)
	if next.is_empty():
		message = Rules.load_refusal(state, kind); refresh(); return
	place(next)

func do_unload(slot: int) -> void:
	var next = Rules.unload_slot(state, slot)
	if next.is_empty():
		message = "那一格本来就是空的。"; refresh(); return
	place(next)

func read_berth(index: int) -> void:
	message = "%s · %s\n%s" % [Rules.STATION_NAMES[index], Rules.STATION_PLACES[index], Rules.rule_caption(state, index)]
	refresh()

func look_flag() -> void:
	message = flag_tip(); refresh()

func do_undeliver() -> void:
	var next = Rules.undeliver(state)
	if next.is_empty():
		message = Rules.undeliver_refusal(state); refresh(); return
	place(next)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_1 + Rules.OPS.size() - 1: do_op(key - KEY_1)
	elif key == KEY_Q: do_take(Rules.LARGE)
	elif key == KEY_W: do_take(Rules.MEDIUM)
	elif key == KEY_E: do_take(Rules.SMALL)
	elif key == KEY_R: do_unload(Rules.packs_of(state.tray) - 1)
	elif key == KEY_F: look_flag()
	else: return false
	return true

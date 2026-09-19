extends "res://scripts/market/level_host.gd"
# MK15 灯芯街铜果摊「不会越换越多的铜果」（可选支线，MK09 之后开门）。
# 摊板上贴着本摊自己的三条合同，柜面上是 12 颗铜果这一批货：点摊板真的换一组货、点「整批」把这一条能换的全换完，
# 换出去的货一件件看得见、也能一步步退回去。台面重新摆回 12 颗果、线与芯都空了，才按「拆穿招牌」。
# 缺哪一条承诺只在提交之后按玩家自己数出来的货讲给他听；招牌那句「绕一圈凭空多一颗」由规则层点名拒收。
const Rules = preload("res://scripts/market/mk15_rules.gd")
const World = preload("res://scripts/market/mk15_world.gd")
const LINE_KEYS = [KEY_1, KEY_2, KEY_3]
const LINE_LETTERS = ["1", "2", "3"]
const BULK_KEYS = [KEY_Q, KEY_W, KEY_E]
const BULK_LETTERS = ["Q", "W", "E"]
const LINES = [
	"衡伯：街尾贴了张招揽牌，写「绕一圈，凭空多一颗」。\n我这铜果摊开了三十年，从没越换越多过。",
	"扣扣：12 颗果换出去，绕一圈回来变 13 颗？那多出来的一颗是谁的？",
	"小岚：把这三条合同真的换一遍就知道了。\n台面上剩什么，比牌上写什么算数。",
]

func configure() -> void:
	scene_id = "street"; level_id = "MK15"; title = "不会越换越多的铜果"
	# 试玩与实窗检查会在加入场景树前先写入自己的 /tmp 路径，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk15-1/save-v1.json"
	durations = {"approach": 1.6, "ringing": 2.8, "delivery": 4.0}
	zoom_stages = ["puzzle", "ringing"]
	rules = Rules; world_script = World

func goal_line() -> String:
	return "照本摊三条合同绕一圈：台面重新只剩 12 颗果"

func status_line() -> String:
	# 这块板子只有 300×42：状态压成一行，汉字不靠自动折行。
	return "果 %d · 线 %d · 芯 %d · %d 格" % [state.fruit, state.thread, state.core,
		Rules.value_of(Rules.stock(state))]

func submit_label() -> String: return "拆穿招牌"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "走到铜果摊前",
		"ready": "开始换这一批货", "complete": "再绕一次"}

func restart_prompt() -> Array: return ["重新体验铜果摊这一幕？", "留在摊前", "重新体验"]
func reset_prompt() -> Array:
	return ["把这一批 12 颗果全部放回台面？\n台账一起清零，本摊不再记住这一趟。", "继续换", "全部放回台面"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "柜面上摊着这一批 12 颗铜果，三条合同贴在身后三块摊板上。"
		"ready": return "衡伯：照我这三条换，一次一组，看得见、也退得回。"
		"puzzle": return "点摊板换一组，点摊板下的「整批」把这一条能换的全换完；\n换出去的货一件件都在台面上，绕回 12 颗果再拆招牌。"
		"ringing": return "衡伯：一条一条数回去——果 → 线 → 芯 → 果。"
		"delivery": return "扣扣：真的是 12 颗！那张牌上写的是 13 颗。"
		"complete": return "小岚：牌拆了，换成一串会绕圈的交换风铃。\n这三条兑换只在这一摊算数，别拿去别的街说。"
	return ""

func build() -> void:
	for line in range(Rules.KINDS):
		var spec: Array = Rules.LINES[line]
		var room: int = Rules.affordable(state, line)
		var note = "还能换 %d 组" % room if room > 0 else "台面上的%s凑不成 %d %s 一组，这一条现在换不动" % [
			Rules.NAMES[spec[0]], spec[1], Rules.MEASURE[spec[0]]]
		add_hotspot("line_%d" % line, world.board_rect(line), do_trade.bind(line, 1),
			"%s：点一下换一组（%s）[%s]" % [Rules.line_caption(line), note, LINE_LETTERS[line]])
		add_hotspot("bulk_%d" % line, world.bulk_target(line), do_bulk.bind(line),
			"合同%s摊板下的整批：把这一条能换的 %d 组一次换完 [%s]" % [
				Rules.ORDINAL[line], room, BULK_LETTERS[line]])
	for kind in range(Rules.KINDS):
		add_hotspot("pile_%d" % kind, world.pile_rect(kind), count_pile.bind(kind),
			"数一遍台面上的%s：%d %s" % [Rules.NAMES[kind], Rules.pile(state, kind), Rules.MEASURE[kind]])
	add_hotspot("sign", world.sign_target(), read_sign,
		"招揽牌「%s」：点一下问本摊兑不兑得出来 [S]" % Rules.sign_caption())

func extra() -> void:
	if state.stage != "complete": return
	# 回执只复述台账上真发生过的那几组兑换，一个数都不替玩家补。
	var rect = world.receipt_rect()
	UIStyle.panel(ui, rect)
	UIStyle.text(ui, Rules.receipt(state), Rect2(rect.position + Vector2(18, 12), rect.size - Vector2(36, 24)), 16)

func exit_buttons() -> void:
	# 从航图进来的场合由宿主给出「返回集市航图」；单独启动本关时也要有一条回去的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"used": value.used.duplicate(true), "fruit": value.fruit,
		"thread": value.thread, "core": value.core}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	next.used = [0, 0, 0]; next.fruit = Rules.STOCK; next.thread = 0; next.core = 0
	return next

func hint_texts() -> Array:
	# 对白板的内框是 798×56：每档最多两行，折行点写在文案里而不是交给自动折行。
	return ["三条合同是接得上的：果换线、线换芯、芯再换回果。\n先照合同一把果换出去，再看台面上多出什么、少了什么。",
		"本摊的尺：果 3 格、线 2 格、芯 4 格。\n2 果 = 6 格 = 3 线，2 线 = 4 格 = 1 芯，3 芯 = 12 格 = 4 果——绕一圈格数不变。",
		"要让线、芯都清零，果得整批走完这一圈：4 果 → 6 线 → 3 芯 → 4 果。\n台面上重新摆满 12 颗果、线与芯都空了，再按「拆穿招牌」。"]

# ---- 玩家动作 ----
func do_trade(line: int, times: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.trade(state, line, times)
	if next.is_empty():
		message = trade_reason(line, times); refresh(); return
	place(next)

func do_bulk(line: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var room = Rules.affordable(state, line)
	if room < 1:
		message = trade_reason(line, 1); refresh(); return
	do_trade(line, room)

# 换不动的时候说清是哪一堆货不够：本摊一次只记这一批 12 颗果。
func trade_reason(line: int, times: int) -> String:
	var spec: Array = Rules.LINES[line]
	if Rules.LINE_CAP[line] - state.used[line] <= 0:
		return "这一批 12 颗果已经全部走过合同%s一次：本摊一次只记这一批货。\n想再演一遍，先按「重摆」把货放回台面。" % Rules.ORDINAL[line]
	if Rules.pile(state, spec[0]) < spec[1] * times:
		return "%s只剩 %d %s：合同%s要 %d %s一组，凑不成整组换不了。" % [
			Rules.NAMES[spec[0]], Rules.pile(state, spec[0]), Rules.MEASURE[spec[0]],
			Rules.ORDINAL[line], spec[1], Rules.MEASURE[spec[0]]]
	return "台面上的货不够再走 %d 组合同%s。" % [times, Rules.ORDINAL[line]]

func count_pile(kind: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	message = "数一遍：果 %d 颗、线 %d 卷、芯 %d 根，按本摊的尺合起来 %d 格。" % [
		state.fruit, state.thread, state.core, Rules.value_of(Rules.stock(state))]
	refresh()

func read_sign() -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	# 招牌要本摊按 13 颗结账：先让规则层试一次入账。台账只认那三条合同，
	# 这一笔记不进去（payout 返回空），玩家听到的就是点名拒绝的那句话。
	var claimed = Rules.payout(state, Rules.SIGN_CLAIM)
	if not claimed.is_empty():
		place(claimed); return
	if Rules.closed(state):
		message = "台面已经绕回 12 颗果，没有第 13 颗。\n按「拆穿招牌」把那张牌换下来。"
	else:
		message = Rules.refusal(Rules.SIGN_CLAIM)
	refresh()

func handle_key(key: int) -> bool:
	if LINE_KEYS.find(key) >= 0: do_trade(LINE_KEYS.find(key), 1)
	elif BULK_KEYS.find(key) >= 0: do_bulk(BULK_KEYS.find(key))
	elif key == KEY_S: read_sign()
	else: return false
	return true

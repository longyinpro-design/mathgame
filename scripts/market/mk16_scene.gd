extends "res://scripts/market/level_host.gd"
# MK16 大码头「给森林寄回一份礼物」：可选支线，第五幕之后开。
# 玩家从货架上把纪念物一样样放上打包台（重量实时报数），凑够三样再点红船寄出去；
# 缺哪条承诺只在按下「封箱上红船」之后按玩家自己的说法讲给他听。
# 选中的那一样会系在包裹外面跟着船走，森林的回信也照它来写——但主线奖励一分不变。
const Rules = preload("res://scripts/market/mk16_rules.gd")
const World = preload("res://scripts/market/mk16_world.gd")
const SHELF_KEYS = [KEY_1, KEY_2, KEY_3, KEY_4]
const LINES = [
	"扣扣：当初森林把种子寄来，我们连一份回礼都没凑齐。\n衡伯说红船明早开，还能赶在灯会前到。",
	"小岚：回礼挑三样，红船只在 7 斤以内接单。\n绿叶章和信纸非带不可——前者是森林的东西，后者用来写回信。",
	"折羽：杯和铃都想带，可两样一起就超重了。\n挑一样吧：森林收到什么，就会照什么回信。",
]
const RECEIPT_TITLE = "回执 · 给森林寄回的礼物"

func configure() -> void:
	scene_id = "dock"; level_id = "MK16"; title = "给森林寄回一份礼物"
	# 试玩与实窗检查会在加入场景树前写入自己的 /tmp 路径，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk16-1/save-v1.json"
	durations = {"approach": 1.6, "loading": 3.0, "delivery": 4.4}
	zoom_stages = ["puzzle", "loading"]
	rules = Rules; world_script = World

func goal_line() -> String:
	return "恰好 3 种不同纪念物 · 总重不超过 7 斤 · 必带绿叶章和信纸"

func status_line() -> String:
	return "已选 %d/%d · 共 %d 斤" % [state.table.size(), Rules.PICKS, Rules.total(state.table)]

func submit_label() -> String: return "封箱上红船"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "走向打包台",
		"ready": "开始打包", "complete": "再寄一份"}

func restart_prompt() -> Array: return ["重新寄一份礼物？", "留在码头", "重新寄一份"]
func reset_prompt() -> Array:
	return ["把选中的那一样放回货架？\n必带的绿叶章和信纸留在台面上。", "继续摆放", "那一样放回货架"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "红船泊在旧码头，打包台还空着一整面。"
		"ready": return "扣扣把四样纪念物摆上货板：绿叶章、信纸、杯、铃。"
		"puzzle": return "点货板上的纪念物放上打包台，凑够三样再点红船寄出去；\n台面上的重量实时报数，超过 7 斤船老大不接。"
		"loading": return "扣扣把三样纪念物裹进包裹，把选中的那一样系在最外面……"
		"delivery": return Rules.sail_line(state.gift)
		"complete": return "小岚：礼物已经上路，回执留在灯会这头。\n灯会该备的货一样不少，这份礼物不占主线。"
	return ""

func build() -> void:
	for id in Rules.KINDS:
		var held = Rules.on_table(state, id)
		var slot = Rules.slot_of(state, id)
		var rect = world.table_rect(slot) if held else world.shelf_rect(id)
		var where = "在打包台上，点一下放回货板" if held else "在货板上，点一下放上打包台"
		add_hotspot(("slot_%d" % slot) if held else ("shelf_%d" % id), rect, move_good.bind(id),
			"%s %d 斤 · %s" % [Rules.name_of(id), Rules.weight_of(id), where])
	add_hotspot("boat", world.boat_rect(), advance,
		"红船 · 7 斤以内接单：把包好的三样寄回森林")

func extra() -> void:
	if state.stage != "complete": return
	# 回执只复述玩家真正寄出去的那三样，以及森林会怎么回；主线奖励那一句两条分支完全相同。
	UIStyle.panel(ui, Rect2(660, 176, 470, 190))
	UIStyle.text(ui, receipt_text(), Rect2(676, 188, 442, 166), 15)

func receipt_text() -> String:
	var reply = Rules.reply_lines(state.gift)
	return "\n".join([RECEIPT_TITLE, Rules.gift_line(state.gift),
		"恰好 3 样 · 上限 %d 斤 · 已封箱上红船" % Rules.LIMIT,
		Rules.REPLY_LEAD + reply[0], reply[1], Rules.REWARD])

func exit_buttons() -> void:
	# 从航图进来的场合由宿主给出「返回集市航图」；单独启动本关时也要有一条回去的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"table": value.table.duplicate(true)}

func cleared_state() -> Dictionary:
	# 重摆只收回玩家那一点偏好：必带的两样留在台面上，已经想清楚的推理不被没收。
	var kept: Array = []
	for id in state.table:
		if Rules.MANDATORY.has(id): kept.append(id)
	if kept == state.table: return {}
	var next = state.duplicate(true)
	next.table = kept
	return next

func hint_texts() -> Array:
	return ["绿叶章代表森林，信纸用来写回信：这两样非带不可。\n货板上的重量都写在牌子上：2、1、4、3 斤。",
		"必带的两样已经 3 斤，上限 7 斤：第三样最多再挑 4 斤。\n杯 4 斤刚好装满，铃 3 斤也带得动。",
		"杯和铃都想带？两样一起就是 10 斤，红船不接。\n2+1+4=7 与 2+1+3=6 都过得了秤，两条都能寄出去。"]

func move_good(id: int) -> void:
	var next = Rules.toggle(state, id)
	if not next.is_empty():
		place(next)
		return
	var reason = Rules.refusal(state, id)
	message = reason if not reason.is_empty() else "现在不是摆货的时候。"
	refresh()

func handle_key(key: int) -> bool:
	var index = SHELF_KEYS.find(key)
	if index < 0: return false
	move_good(index)
	return true

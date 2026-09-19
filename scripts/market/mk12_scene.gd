extends "res://scripts/market/level_host.gd"

# MK12 千灯集市「不一样多，也都够用」：装车草稿与交接记录在 mk12_rules.gd，
# 庭院与三辆车在 mk12_world.gd；这里只做台词、热点、联合回执与键盘操作。
# 台词按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
const Rules = preload("res://scripts/market/mk12_rules.gd")
const World = preload("res://scripts/market/mk12_world.gd")
const LINES = [
	"扣扣：三处的需求单都收齐了。\n桥头要 4 单位、中街要 5 单位、西坡要 6 单位灯油。",
	"衡伯：封油不能拆。柜上只有三壶 2 单位的、三壶 3 单位的，一共六壶。",
	"衡伯：每一处最多接两壶，六壶都要交出去，还要每处不多不少刚刚接满。",
	"扣扣：不一样的数，也能都够用。\n你先分，我们不替你算。",
]
var picked := -1

func configure() -> void:
	scene_id = "oil"; level_id = "MK12"; title = "不一样多，也都够用"
	# 实窗检查会在加入场景树前写入自己的 /tmp 落点，默认值永远不覆盖它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk12-1/save-v1.json"
	durations = {"approach": 1.6, "handing": 2.6, "delivery": 3.4}
	rules = Rules; world_script = World
	# 装车时贴近台面与三辆车；车离场与点灯都退回整个庭院。
	zoom_stages = ["puzzle"]

func goal_line() -> String: return "三处已确认要 4、5、6 单位 · 六壶一壶不剩 · 每处最多两壶"
func submit_label() -> String: return "三处一起交货"
func status_line() -> String:
	return "车上 %d/%d 壶 · 台面 %d 壶" % [Rules.assigned(state.plan), Rules.JUGS,
		Rules.stock_of(state.plan).size()]

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "走向分油庭院",
		"ready": "开始装车", "complete": "重新体验"}

func restart_prompt() -> Array:
	return ["重新体验分油这一幕？\n只重置本关，不改其他关卡。", "留在庭院", "重新体验"]
func reset_prompt() -> Array:
	return ["把三辆车上的封油全部放回台面？\n壶没拆过，也一壶没交出去。", "继续装车", "全部放回台面"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "三辆车停在庭院里，车帮上钉着各自确认过的需求单。"
		"ready": return "先点台面上的一壶封油，再点接它的那辆车；再点车上的壶就放回台面。"
		"puzzle": return "每处最多两壶，六壶全交完，还要每一处刚好按自己的单子接满。"
		"handing": return "三辆车各自载着两壶封油驶向街口。壶没有拆开——路上也不用拆。"
		"delivery": return "桥头、中街、西坡各自把油接进自己的灯具，一处的灯先亮起来。"
		"complete": return "三家把需求单压在同一块板上：「这回，我们一起签。」\n衡伯打开了总货栈，三处的灯一起亮着。"
	return ""

func build() -> void:
	world.picked = picked
	for jug in range(Rules.JUGS):
		if Rules.place_of(state.plan, jug) >= 0: continue
		add_hotspot("stock_%d" % jug, world.stock_rect(jug), choose_jug.bind(jug),
			"%d 单位封油（第 %d 壶）· 键盘 %d：%s" % [Rules.JUG_UNITS[jug], jug + 1, jug + 1,
				"已拿起，点一处车交给它" if picked == jug else "点一下拿起来，再点一次放下"])
	for place in range(Rules.PLACES.size()):
		var row: Array = state.plan[place]
		add_hotspot("cart_%d" % place, world.cart_rect(place), choose_place.bind(place),
			"%s · 需求单 %d 单位 · 键盘 %s：%s" % [Rules.PLACES[place], Rules.NEEDS[place],
				["Q", "W", "E"][place],
				"车上两壶已经放满，先点车上的壶放回台面" if row.size() >= Rules.MAX_PER_PLACE
				else ("把 %d 单位这一壶装上" % Rules.JUG_UNITS[picked]) if picked >= 0 else "先点一壶封油"])
		for slot in range(row.size()):
			add_hotspot("slot_%d_%d" % [place, slot], world.slot_rect(place, slot),
				do_unload.bind(place, slot),
				"%s车上的 %d 单位封油：点一下放回台面，一壶都还没交出去" %
					[Rules.PLACES[place], Rules.JUG_UNITS[row[slot]]])

# 联合回执只复述真正交出去的那一单：哪一壶上了哪辆车、各是多少单位，都从 handed 读回。
# 汉字不换行，所以每一行都写短到 18 号字能塞进回执栏的宽度。
func receipt_lines() -> Array:
	var lines = ["三家联合回执 · 灯会分油"]
	for place in range(Rules.PLACES.size()):
		var row: Array = state.handed[place]
		var marks := []
		for jug in row: marks.append("%d" % Rules.JUG_UNITS[jug])
		lines.append("%s %s=%d · 单子要 %d" % [Rules.PLACES[place], "+".join(marks),
			Rules.units_of(row), Rules.NEEDS[place]])
	lines.append("台面剩 %d 壶 · 封油没拆过" % Rules.stock_of(state.handed).size())
	lines.append("六壶共 %d 单位" % Rules.jug_total())
	lines.append("三处共要 %d 单位" % Rules.need_total())
	lines.append("不一样多，也都够用")
	lines.append("三家一起签 · 衡伯开总货栈")
	return lines

func extra() -> void:
	if state.stage != "complete": return
	# 回执栏贴着西坡车的右手边：不压灯串、不压需求单、也不压宿主底部的按钮。
	UIStyle.panel(ui, Rect2(976, 170, 284, 300))
	UIStyle.text(ui, "\n".join(receipt_lines()), Rect2(992, 184, 254, 272), 16)

func exit_buttons() -> void:
	# 从航图进来时宿主已经挂好返回按钮；单独启动本关时补一个同样的出口。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"plan": value.plan.duplicate(true), "handed": value.handed.duplicate(true)}

func cleared_state() -> Dictionary:
	picked = -1
	var next = state.duplicate(true)
	next.plan = Rules.empty_plan()
	return next

func hint_texts() -> Array:
	return ["封油不能拆，每处最多接两壶：一处能接到的只有 2+2、2+3 或 3+3，\n也就是 4、5 或 6 单位——三处要的正好是这三个数。",
		"先看最紧的两张单子：要 4 单位的那处，两壶只能都是 2 单位；\n要 6 单位的那处，两壶只能都是 3 单位。",
		"示范一步：先给要 4 单位的桥头装上两壶 2 单位的圆壶，桥头就满了；\n剩下的壶怎么分，还是你自己排。"]

func choose_jug(jug: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if jug < 0 or jug >= Rules.JUGS: return
	var holder := Rules.place_of(state.plan, jug)
	if holder >= 0:
		# 车上的壶：点一下就放回台面，草稿的其他部分不动，台面由规则重新数出来。
		picked = -1
		place(Rules.unload(state, holder, Rules.slot_of(state.plan, jug)))
		return
	picked = -1 if picked == jug else jug
	refresh()

func choose_place(place_index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if place_index < 0 or place_index >= Rules.PLACES.size(): return
	if picked < 0:
		message = "先在台面上点一壶封油，再点这一处的车。"
		refresh(); return
	var next = Rules.load(state, picked, place_index)
	if next.is_empty():
		message = "%s那辆车最多接两壶：先点车上的壶放回台面，再装新的。" % Rules.PLACES[place_index]
		refresh(); return
	picked = -1
	place(next)

func do_unload(place_index: int, slot: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	picked = -1
	var next = Rules.unload(state, place_index, slot)
	if next.is_empty():
		message = "那一壶已经回到台面上了。"
		refresh(); return
	place(next)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_6: choose_jug(key - KEY_1)
	elif key == KEY_Q: choose_place(0)
	elif key == KEY_W: choose_place(1)
	elif key == KEY_E: choose_place(2)
	else: return false
	return true

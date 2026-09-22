extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk10_rules.gd")
const World = preload("res://scripts/market/mk10_world.gd")
# 台词按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
# 白板内框 798×56（20 号请求实际按 22 号画），每句最多两行。
const LINES = [
	"折羽：两张订单还在等回信——一张要运 3 箱，一张要运 6 箱。",
	"折羽：回信没说中是哪一张，两个可能现在就摆上预测板。",
	"扣扣：这次筹票上限 10 张，两条船的收费都公开贴在船底。",
]
const CLARIFY = [
	"折羽：工坊那几单一直没回信……不是货没送到，是回信没送到。",
	"折羽：单号我已经订正过。无论最后回哪封信，这一单都得先送出去。",
	"扣扣：查询信我折进回执里，让这条船顺路捎去齿轮工坊。",
]
const PICK_NOTE = "现在写的是「运 %d 箱」那一格：点一边的票额签。"
const CHANGE_NOTE = "换成了%s：两格的票额得照这条约定重算。"
# 键盘：1/2 选订单格，QWERTY 六张票额签，A/S 选船——Z 撤销、H 提醒、空格交单由宿主负责。
const CELL_KEYS = [KEY_1, KEY_2]
const TILE_KEYS = [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y]
const BOAT_KEYS = [KEY_A, KEY_S]

func configure() -> void:
	scene_id = "dock"; level_id = "MK10"; title = "无论回哪封信"
	# 试玩会在入树前写入自己的 /tmp 落点，默认值永远不覆盖它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk10-1/save-v1.json"
	durations = {"approach": 1.6, "confirming": 2.4, "delivery": 4.2}
	# 摆票与结票贴近预测板；delivery 前半程仍跟着船，后半程由宿主拉回整个大码头。
	zoom_stages = ["puzzle", "confirming", "clarify"]
	rules = Rules; world_script = World

func goal_line() -> String: return "两张订单或运 3 箱／6 箱：选一条两种都盖得住的船"
func submit_label() -> String: return "按这条约定交单"

# 这块板子只有 300×42：状态压成一行，两个可能的票额现算，不另存计数。
func status_line() -> String:
	if state.boat < 0: return "未选约定 · 上限 %d 票" % Rules.BUDGET
	var values = Rules.fares(state.boat)
	return "%s %d/%d 票 · 限 %d" % [Rules.BOAT_NAMES[state.boat], values[0], values[1], Rules.BUDGET]

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.ARRIVAL_BEATS - 1 else "到预测板前看看",
		"ready": "开始摆票额",
		"clarify": "继续听他们说" if state.beat < Rules.CLARIFY_BEATS - 1 else "看这一单的回执",
		"complete": "重新体验"}

func restart_prompt() -> Array: return ["重新体验大码头这一幕？", "留在码头", "重新体验"]
func reset_prompt() -> Array:
	return ["把两格票额擦回空白、约定也退回未选？\n本局是哪一张订单不会变。", "继续摆票", "全部擦回空白"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "两张订单并排钉上预测板，红船与蓝船就泊在近岸。"
		"ready": return "两条约定都公开：%s%s，%s%s。" % [Rules.BOAT_NAMES[0], Rules.tariff_text(0),
			Rules.BOAT_NAMES[1], Rules.tariff_text(1)]
		"puzzle": return "点一条船选定约定，再照它的收费把 3 箱与 6 箱两种可能都写在纸上。"
		"confirming": return "回信到了：本局确认要运 %d 箱。票按选定的约定一次性结清……" % state.branch
		"clarify": return CLARIFY[state.beat]
		"delivery": return "%s载着这一单离岸，回执里另夹了一封带订正单号的查询信……" % Rules.BOAT_NAMES[state.boat]
		"complete": return "小岚：无论最后回哪封信，这一单都付得起。\n齿轮工坊那边，欠着的几封回信也该有人去问了。"
	return ""

func build() -> void:
	for boat in range(Rules.BOATS):
		var values = Rules.fares(boat)
		add_hotspot("boat_%d" % boat, world.boat_rect(boat), do_choose.bind(boat),
			"%s约定：%s · 3 箱 %d 票／6 箱 %d 票%s" % [Rules.BOAT_NAMES[boat], Rules.tariff_text(boat),
				values[0], values[1], "（已选，再点一次退回未选）" if state.boat == boat
					else "（键盘 %s）" % OS.get_keycode_string(BOAT_KEYS[boat])])
	for slot in range(Rules.SLOTS):
		add_hotspot("case_%d" % slot, world.cell_rect(slot), do_pick.bind(slot),
			"点这一格表示要在这里写票额：或运 %d 箱 · 键盘 %d" % [Rules.CASES[slot], slot + 1])
	for index in range(Rules.TILES):
		add_hotspot("tile_%d" % index, world.tile_rect(index), do_mark.bind(Rules.TILE_VALUES[index]),
			"把「%s」写进现在选中的那一格 · 键盘 %s" % [Rules.slip_text(Rules.TILE_VALUES[index]),
				OS.get_keycode_string(TILE_KEYS[index])])

# 回执逐行写在这里，交给无头检查量宽度：Label 不会在汉字中间断行，超框就会画到面板外。
func receipt_lines() -> Array:
	var values = Rules.fares(state.boat)
	var lines = ["大码头 · 无论回哪封信"]
	for slot in range(Rules.SLOTS):
		lines.append("%s 或运 %d 箱：%s %d 票" % [World.ORDER_TAGS[slot], Rules.CASES[slot],
			Rules.BOAT_NAMES[state.boat], values[slot]])
	lines.append("上限 %d 票 · 两种都没顶穿" % Rules.BUDGET)
	lines.append("本局运 %d 箱 · 付讫 %d 票 · 余 %d 张" % [state.branch, state.paid, Rules.BUDGET - state.paid])
	lines.append("另带一封查询信去齿轮工坊")
	return lines

# 面板摆在左侧海面上：既压不住两张订单格，也不压右下角的出口按钮。
# 宽 306 是被宿主那块对白板（Rect2(338,98,826,86)，两行 22 号汉字之后加高到 86）钉死的：
# 320 宽的纸脚会爬到对白板左下角 22×8 的一块上，压掉那块木头的下边框。
# 左边取 24，与顶上的标题板对齐，纸边到板边还留 8 像素。
func receipt_rect() -> Rect2: return Rect2(24, 176, 306, 194)
func receipt_text_rect() -> Rect2:
	var board = receipt_rect()
	return Rect2(board.position + Vector2(12, 12), board.size - Vector2(24, 26))

func extra() -> void:
	if state.stage != "complete": return
	# 回执复述的是「两种可能各自要多少票」与本局真正付掉的那个数：都由规则现算。
	UIStyle.panel(ui, receipt_rect())
	var paper = UIStyle.text(ui, "\n".join(receipt_lines()), receipt_text_rect(), 16)
	# 18 号汉字的行高 27 像素、主题默认行距再加 5：六行就得收紧行距才出不了纸面。
	paper.add_theme_constant_override("line_spacing", 0)

func exit_buttons() -> void:
	# 从航图进来时宿主已经放了返回键；单独启动这一幕也要有一条回航图的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"written": value.written.duplicate(), "boat": value.boat, "paid": value.paid}

func cleared_state() -> Dictionary:
	# 重摆只退纸面：本局是哪一张订单留在状态里，绝不在这里重抽。
	var next = state.duplicate(true)
	next.written = Rules.empty_written(); next.boat = -1; next.paid = 0
	return next

func hint_texts() -> Array:
	# 对白板的内框是 798×56：每档最多两行，折行点写在文案里而不是交给自动折行。
	return ["两张订单都可能成真：3 箱与 6 箱的票额都要写在板上。\n一条约定要能用，两种可能都不能顶穿 %d 票上限。" % Rules.BUDGET,
		"红船每箱 2 票；蓝船先付 4 票开船、再每箱 1 票。\n箱数翻倍时看谁涨得快：红船 3 箱到 6 箱多出 6 票。",
		"照蓝船算：3 箱是 4 加 3 等于 7 票，6 箱是 4 加 6 等于 10 票。\n红船运 6 箱要 12 票，先顶穿上限——这一条怎么都交不出去。"]

func do_choose(boat: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.choose_boat(state, boat)
	if next.is_empty():
		message = "两条约定都公开贴在船底：先点一条船，再照它算票额。"
		refresh(); return
	var rewrite = next.boat >= 0 and next.written != Rules.empty_written() and not Rules.written_matches(next)
	place(next)
	if rewrite and state.boat == boat:
		message = CHANGE_NOTE % Rules.BOAT_NAMES[boat]; refresh()

func do_pick(slot: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if slot < 0 or slot >= Rules.SLOTS: return
	world.picked = slot
	message = PICK_NOTE % Rules.CASES[slot]; refresh()

func do_mark(value: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.mark_case(state, world.picked, value)
	if next.is_empty():
		message = "「运 %d 箱」那一格已经写着 %s 了。" % [Rules.CASES[world.picked], Rules.slip_text(value)]
		refresh(); return
	place(next)

func handle_key(key: int) -> bool:
	if key in CELL_KEYS: do_pick(CELL_KEYS.find(key))
	elif key in TILE_KEYS: do_mark(Rules.TILE_VALUES[TILE_KEYS.find(key)])
	elif key in BOAT_KEYS: do_choose(BOAT_KEYS.find(key))
	else: return false
	return true

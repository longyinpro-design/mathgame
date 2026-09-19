extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk08_rules.gd")
const World = preload("res://scripts/market/mk08_world.gd")
# 台词按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
const LINES = [
	"衡伯：出库板上写着 16 瓶，\n码头回话说只收到 13 瓶。",
	"衡伯：板上是红 6、蓝 4、红 6。\n三张原单都在架子上，我一张一张也对不平。",
	"扣扣：多出来的三瓶、差出来的三瓶，\n会不会是同一只手写重了，又写漏了一张？",
	"小岚：这块板只许钉三行：先对上单位，再对上单号。\n总数我们不动，动的是那三条记录。",
]
const ROW_KEYS = ["Q", "W", "E"]			# 撤下第 1/2/3 行
const UNIT_KEYS = ["A", "S", "D"]			# 换算第 1/2/3 行

func configure() -> void:
	scene_id = "street"; level_id = "MK08"; title = "多出来的三瓶油"
	# 试玩会在入树前写入自己的 /tmp 落点，默认值永远不覆盖它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk08-1/save-v1.json"
	durations = {"approach": 1.6, "filing": 2.8, "delivery": 3.8}
	# 走到柜台、钉单与归档都贴近汇总板；点收盖讫那一段拉回整条街（宿主的 delivery 分支负责）。
	zoom_stages = ["ready", "puzzle", "filing"]
	rules = Rules; world_script = World

func goal_line() -> String: return "汇总板按瓶记：三张原单各记一次，合计对上码头实收的 13 瓶"
func status_line() -> String: return "板上 %d 瓶 · 码头实收 %d 瓶" % [
	Rules.total_of(state.lines), Rules.RECEIVED]
func submit_label() -> String: return "重新归档这块板"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "走到柜台前",
		"ready": "开始归档", "complete": "重新体验"}

func restart_prompt() -> Array:
	return ["重新体验老货栈这一幕？\n只重置本关，不改其他关卡。", "留在柜台", "重新体验"]
func reset_prompt() -> Array:
	return ["把板上的三行全部撤下？\n架上的原单一张都不会少。", "继续归档", "全部撤下"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "扣扣把三张原单摊在账架上，那块汇总板还压在柜台上没揭。"
		"ready": return "衡伯：板上的行随你重钉，架上的原单一张都不能改。"
		"puzzle": return "点架子上的原单，抄件就钉进第一个空行；撤下、拨数、换算都能点。\n对不上的地方，提交时一行一条讲给你听。"
		"filing": return "三行一起归档：撤下的抄件落进纸篓，补回的单号落回板上……"
		"delivery": return "码头的点收数一行一行盖讫。13 瓶对上，两头的争执就消了。"
		"complete": return "扣扣：多出来的三瓶和缺的三瓶，原是同一只手的错。\n这块板原先写着 16 瓶，如今三行都对上了。"
	return ""

func build() -> void:
	for order in range(Rules.ORDERS):
		add_hotspot("pin_%d" % order, world.ticket_rect(order), do_pin.bind(order),
			"把%s的抄件钉进空行 · %s · 键盘 %d" % [Rules.NAMES[order], Rules.note(order), order + 1])
	for row in range(Rules.LINES):
		add_hotspot("chip_%d" % row, world.chip_rect(row), do_unpin.bind(row),
			"撤下第 %d 行的抄件 · 板上的账跟着少一行 · 键盘 %s" % [row + 1, ROW_KEYS[row]])
		add_hotspot("less_%d" % row, world.less_rect(row), do_bump.bind(row, -1),
			"第 %d 行少记一件 · 最少 1 件" % (row + 1))
		add_hotspot("more_%d" % row, world.more_rect(row), do_bump.bind(row, 1),
			"第 %d 行多记一件 · 最多 %d 件" % [row + 1, Rules.MAX_COUNT])
		add_hotspot("unit_%d" % row, world.unit_rect(row), do_convert.bind(row),
			"第 %d 行换算箱与瓶 · 每箱 %d 瓶 · 键盘 %s" % [row + 1, Rules.PER_BOX, UNIT_KEYS[row]])

# 回执逐行写在这里，交给无头检查量宽度：Label 不会在汉字中间断行，超框就会画到面板外。
func receipt_lines() -> Array:
	var lines = ["老货栈 · 归档回执"]
	for order in range(Rules.ORDERS):
		var packed: String = "%d 箱" % Rules.BOXES[order] if Rules.BOXES[order] > 0 \
			else "%d 散瓶" % Rules.LOOSE[order]
		lines.append("%s %s = %d 瓶" % [Rules.NAMES[order], packed, Rules.bottles_of(order)])
	lines.append("合计 %d 瓶 · 码头实收 %d 瓶" % [Rules.total_of(state.filed), Rules.RECEIVED])
	lines.append("撤下重复抄件 %d 张" % Rules.copies_out(state).size())
	lines.append("补回漏掉的单号 %d 个" % Rules.copies_in(state).size())
	return lines

# 摆在街角左侧的空档：右让开三张原单，下让开柜台上盖了讫的板。
func receipt_rect() -> Rect2: return Rect2(24, 76, 312, 238)
func receipt_text_rect() -> Rect2:
	var board = receipt_rect()
	return Rect2(board.position + Vector2(16, 12), board.size - Vector2(30, 20))

func extra() -> void:
	if state.stage != "complete": return
	# 回执只复述 filed：板上此刻是什么，归档就是什么，画面不另存一份账。
	UIStyle.panel(ui, receipt_rect())
	UIStyle.text(ui, "\n".join(receipt_lines()), receipt_text_rect(), 16)

func exit_buttons() -> void:
	# 从航图进来时宿主已经给出「返回集市航图」；直接启动本关样板时留一条回航图的路。
	if origin != "hub":
		add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"lines": value.lines.duplicate(true), "filed": value.filed.duplicate(true)}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	next.lines = Rules.empty_lines()
	return next

func hint_texts() -> Array:
	return ["架上的原单各写着 2 箱、4 散瓶、1 箱，每箱 3 瓶；\n这块板是按瓶记的，箱没换算成瓶就对不上。",
		"合计 16 瓶只说明板上一共记了 16 瓶，说不清是谁被记了两回。\n三行里有一张单的抄件钉了两次，也有一张单一次都没上板。",
		"拿第 3 行做个样子：点「换算」，6 瓶就写成 2 箱；\n再点一次，2 箱又回到 6 瓶——换的是写法，不是数目。"]

func do_pin(order: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.pin(state, order)
	if next.is_empty():
		if not Rules.rows_of(state.lines, order).is_empty():
			message = "%s已经钉在板上了：同一张原单只记一次。" % Rules.NAMES[order]
		else:
			message = "板上三行都钉满了：先撤下一行，再钉新的单。"
		refresh(); return
	place(next)

func do_unpin(row: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.unpin(state, row)
	if next.is_empty():
		message = "第 %d 行本来就空着，没什么可撤的。" % (row + 1)
		refresh(); return
	place(next)

func do_bump(row: int, step: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.bump(state, row, step)
	if next.is_empty():
		if state.lines[row][0] < 0: message = "第 %d 行还空着：先从架上钉一张单下来。" % (row + 1)
		elif step > 0: message = "板上每行最多画 %d 件：这一行已经到头了。" % Rules.MAX_COUNT
		else: message = "至少留 1 件：整行不要就按「撤下」。"
		refresh(); return
	place(next)

func do_convert(row: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.convert(state, row)
	if next.is_empty():
		var line: Array = state.lines[row] if row >= 0 and row < Rules.LINES else [-1, 0, Rules.UNIT_BOTTLE]
		if line[0] < 0: message = "第 %d 行还空着：空行没有单位可换。" % (row + 1)
		elif line[2] == Rules.UNIT_BOX:
			message = "%d 箱换算成瓶要画 %d 件：板上每行最多画 %d 件。" % [
				line[1], line[1] * Rules.PER_BOX, Rules.MAX_COUNT]
		else:
			message = "%d 瓶装不满整箱：这一行只能按瓶记。" % line[1]
		refresh(); return
	place(next)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_1 + Rules.ORDERS - 1: do_pin(key - KEY_1)
	elif key == KEY_Q: do_unpin(0)
	elif key == KEY_W: do_unpin(1)
	elif key == KEY_E: do_unpin(2)
	elif key == KEY_A: do_convert(0)
	elif key == KEY_S: do_convert(1)
	elif key == KEY_D: do_convert(2)
	else: return false
	return true

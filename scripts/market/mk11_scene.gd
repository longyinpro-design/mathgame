extends "res://scripts/market/level_host.gd"
# MK11 千灯集市「砝码也能站在货物旁」：老货栈的铜秤立在分油庭院正中，秤杆锁着制动。
# 陶姨要分装恰好 7 单位灯油，衡伯只借出 1、3、9 三枚砝码，每枚最多上一次秤；
# 两边盘面都能站砝码，灯油只进指定的货盘，空接油罐的皮重已经归零。
# 玩家自己摆砝码、自己一格一格接油，按「抬起这杆秤」之后才看到秤如实沉向哪一头；
# 摆法不清空、不扣分，提示只多说话，奖励一律不变。
# 台词按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
const Rules = preload("res://scripts/market/mk11_rules.gd")
const World = preload("res://scripts/market/mk11_world.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const RETURN_KEYS = [KEY_Q, KEY_W, KEY_E]
const LINES = [
	"陶姨：灯会要的是恰好 7 单位灯油，我的罐子没有刻度。\n货栈只肯借三枚砝码，一、三、九，每枚只能用一次。",
	"扣扣：砝码摆在对面那盘不就行了，\n哪头沉哪头轻，谁看不出来？",
	"衡伯：这杆秤两边都能站砝码，空罐的皮重我已经归零。\n油只能进左边那只货盘。摆法我不给，秤也不提前说话。",
]

func configure() -> void:
	scene_id = "oil"; level_id = "MK11"; title = Catalog.title("MK11")
	# 试玩与实窗检查会在加入场景树前写入自己的 /tmp 落点，默认值永远不覆盖它。
	if save_path.is_empty(): save_path = Catalog.save_path("MK11")
	durations = {"approach": 1.6, "weighing": 2.4, "delivery": 3.6}
	# 走到秤前与抬秤那一段贴近铜秤，交付封坛的那一段再拉回整座庭院（宿主的 delivery 分支负责）。
	zoom_stages = ["puzzle", "weighing"]
	rules = Rules; world_script = World

func goal_line() -> String:
	return "陶姨要恰好 7 单位灯油 · 1 / 3 / 9 各一次 · 两边都能站"

# 提交之前只报玩家自己做过的事：接了几格、几枚上秤、抬过几次。
# 两盘各压多少、哪头沉一律不写在这里——那要等秤抬起来才作数。
func status_line() -> String:
	return "接油 %d · 上秤 %d 枚 · 抬 %d 次" % [state.oil, Rules.weights_on_scale(state), state.weighs]

func submit_label() -> String: return "抬起这杆秤"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "走向铜秤",
		"ready": "开始分油", "result": "回到秤前再摆", "complete": "重新体验"}

func restart_prompt() -> Array: return ["重新体验分油这一秤？", "留在秤前", "重新体验"]
func reset_prompt() -> Array:
	return ["三枚砝码全部放回台面、罐里的油倒回油壶？\n已经抬过的次数留着，秤仍然锁着。", "继续摆放", "全部放回台面"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "铜秤的制动销还插着，三枚砝码摆在左手的接货台上。"
		"ready": return "衡伯只借出一、三、九这三枚：每枚最多上一次秤，两边盘面都能站。"
		"puzzle": return "点一枚砝码，它就往前走一格：台面 → 对面那盘 → 货盘。\n油壶接一格，提斗或罐口倒回一格；秤要提交之后才抬。"
		"weighing": return "扣扣替大家扶稳秤盘……秤杆往哪头沉，这会儿才看得出来。"
		"result": return Rules.result_line(state)
		"delivery": return "陶姨把接好的油封进坛子，搬到台面边上等衡伯画押。"
		"complete": return "衡伯：同一份 7 单位的约定，砝码站在货物这头也兑得了。\n下一处的油，就照这个法子分。"
	return ""

# 每一格都永远点得动：砝码站在哪儿，那一格就是「挪一挪」；
# 空着的那一格写着它的名字，点一下就是把它直接请过来。
func build() -> void:
	add_hotspot("valve", world.valve_rect(), do_draw,
		"拧一格油进货盘里的接油罐（一格 1 单位）· 键盘 A")
	add_hotspot("ladle", world.ladle_rect(), do_pour_back,
		"用提斗把罐里的油舀回油壶一格 · 键盘 S")
	add_hotspot("pot", world.pot_rect(), do_pour_back,
		"接油罐里现在 %d 单位：点罐口也能倒回一格" % state.oil)
	for index in range(Rules.COUNT):
		var standing: int = Rules.side_of(state, index)
		var weight_label = Rules.weight_name(index)
		if standing == Rules.OFF:
			add_hotspot("bench_%d" % index, world.bench_rect(index), do_cycle.bind(index),
				"%s 还在台面：点一下请它上秤，先站到对面那盘（再点一次才是货盘）· 键盘 %d" % [weight_label, index + 1])
		else:
			# 键盘上把这一枚请回台面是 Q/W/E，跟点这一下是同一件事，就一并写出来。
			add_hotspot("bench_%d" % index, world.bench_rect(index), do_return.bind(index),
				"%s 正站在%s：点一下放回台面 · 键盘 %s" % [weight_label, Rules.pan_name(standing), ["Q", "W", "E"][index]])
		for side in [Rules.GOODS, Rules.FAR]:
			if standing == side:
				var onward = Rules.pan_name(Rules.NEXT[side])
				add_hotspot("pan_%d_%d" % [side, index], world.pan_rect(side, index), do_cycle.bind(index),
					"%s 正站在%s：再点一次挪去%s · 键盘 %d" % [weight_label, Rules.pan_name(side), onward, index + 1])
			else:
				# 这半句不写「键盘 %d」：数字键走的是 cycle 那一格一格的路，
				# 砝码还搁在台面上时按 2 只会先把它请到对面那盘，不会请到这一格。
				add_hotspot("pan_%d_%d" % [side, index], world.pan_rect(side, index), do_place.bind(index, side),
					"这一格是留给%s的：点一下把它请上%s" % [weight_label, Rules.pan_name(side)])

# 抬秤之后的回执：只复述玩家真正摆出来的那两盘，不另立第二套说法。
func receipt_lines() -> Array:
	var lines = ["衡伯的验看单 · 老货栈铜秤", "约定：恰好 %d 单位灯油" % Rules.PROMISE]
	for side in [Rules.GOODS, Rules.FAR]:
		lines.append("%s：%s = %d 单位" % ["货盘" if side == Rules.GOODS else "对面",
			" + ".join(Rules.terms(state, side)), Rules.pan_total(state, side)])
	lines.append("砝码站在货物这头，约也兑了")
	lines.append("这一坛抬过 %d 次秤" % state.weighs)
	return lines

# 验看单摊在右下角：左边那格原本压在第三辆油车上（那辆车画到 x 945、y 286.7…384.5，
# 这块板是不透明底、又画在最后一层，收尾画面正好把车尾切掉一块），上边那格又盖住了
# 台词板 184 那条下沿。挪到 950/200 起：离车尾 5 像素、离台词板的投影 9 像素，右沿仍停在 1256。
func receipt_rect() -> Rect2: return Rect2(950, 200, 306, 232)
func receipt_text_rect() -> Rect2:
	var board = receipt_rect()
	return Rect2(board.position + Vector2(16, 12), board.size - Vector2(30, 20))

func extra() -> void:
	if state.stage != "complete": return
	UIStyle.panel(ui, receipt_rect())
	var paper = UIStyle.text(ui, "\n".join(receipt_lines()), receipt_text_rect(), 16)
	# 18 号汉字的默认行距是 5 像素，六行就会把末行推出纸面：行距是主题常量，只能覆盖。
	paper.add_theme_constant_override("line_spacing", 0)

func exit_buttons() -> void:
	# 从航图进来时宿主已经给出「返回千灯航图」；直接启动本关样板时留一条回航图的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"goods": value.goods.duplicate(), "far": value.far.duplicate(), "oil": value.oil}

func cleared_state() -> Dictionary: return Rules.cleared(state)

# 三级提示：提醒关系 → 缩小关键选择 → 示范一个步骤。提示只多说话，奖励一分不扣。
func hint_texts() -> Array:
	return ["陶姨要的是恰好 7 单位，不是至少 7 单位。\n三枚砝码各只有一枚：1、3、9，谁也不能用两遍。",
		"先只把砝码全站到对面那盘：那盘能凑出的数是 1、3、4、9、10、12、13。\n7 不在里面——对面这一头再怎么加，也接不出 7 单位的约定。",
		"把 9 单独留在对面，让 3 站到灯油这一头：对面 9，货盘 7 + 3。\n再把 1 补到对面，两头都是 10，秤就平了。"]

func do_cycle(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.cycle(state, index)
	if next.is_empty():
		message = "这一枚现在挪不动：先把它放回台面，再决定它站哪一头。"
		refresh(); return
	place(next)

func do_place(index: int, side: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.place(state, index, side)
	if next.is_empty():
		message = "%s 已经站在%s了。" % [Rules.weight_name(index), Rules.pan_name(side)]
		refresh(); return
	place(next)

func do_return(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.return_weight(state, index)
	if next.is_empty():
		message = "%s 本来就还在台面上。" % Rules.weight_name(index)
		refresh(); return
	place(next)

func do_draw() -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.draw_oil(state)
	if next.is_empty():
		message = "接油罐最多接满 %d 单位：三枚砝码全压上秤也就这些，再多这杆秤就兑不了了。" % Rules.OIL_MAX
		refresh(); return
	place(next)

func do_pour_back() -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.pour_back(state)
	if next.is_empty():
		message = "接油罐已经空了：先点油壶接一格。"
		refresh(); return
	place(next)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_1 + Rules.COUNT - 1: do_cycle(key - KEY_1)
	elif RETURN_KEYS.find(key) >= 0: do_return(RETURN_KEYS.find(key))
	elif key == KEY_A: do_draw()
	elif key == KEY_S: do_pour_back()
	else: return false
	return true

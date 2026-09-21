extends "res://scripts/market/level_host.gd"
# MK14 千灯集市「三枚砝码的小摊」（可选支线，MK11 之后开放）：
# 老货栈把摊子上唯一的三枚砝码 1、3、9 借给油庭院的小摊，两盘都能站，每枚最多上一次秤。
# 街上停着三单真货——桥头灯行 4 单位、中街油铺 7 单位、河下米行 13 单位，谁先上秤由玩家点车挑。
# 这一关的新规矩只有一条：头一单的摆法随便摆，往后每一单只能从上一单记进账里的那一式挪一枚砝码，
# 第二枚一碰就被当场拦下。三进制砝码让 1 至 13 每一单都只有一种摆法配得平，于是 4→13→7 与 7→13→4
# 是走得完的两条顺序；13 必须走在中间，从它开局最多只交得出两单——那正是本关要玩家自己算到的事。
# 台词与提示按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
const Rules = preload("res://scripts/market/mk14_rules.gd")
const World = preload("res://scripts/market/mk14_world.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
# 1 / 2 / 3 挪砝码，Q / W / E 把手里那枚放回架上；A / S / D 挑街上那三辆车；
# 提交与撤销由宿主的空格、Z 负责。
const RETURN_KEYS = [KEY_Q, KEY_W, KEY_E]
const CHOOSE_KEYS = [KEY_A, KEY_S, KEY_D]
# 热点文字与台词里写出来的键名：与上面两组键码同一顺序，画面不另立一套说法。
const RETURN_LABELS = ["Q", "W", "E"]
const CHOOSE_LABELS = ["A", "S", "D"]
const LINES = [
	"衡伯：摊子上就这三枚砝码，一、三、九，\n街上三辆车各压着一单货，一单也不添新的砝码。",
	"扣扣：砝码站在对面那盘不就行了，\n哪头沉哪头轻，谁看不出来？",
	"小岚：货压在左边这只货盘上，砝码两边都能站，一枚最多上一次秤。\n摆法我们不给你，秤也不提前说话——抬起来才知道。哪一单先上秤，你点车挑。",
]

func configure() -> void:
	scene_id = "oil"; level_id = "MK14"; title = Catalog.title("MK14")
	# 试玩与实窗检查会在加入场景树前先写入自己的 /tmp 落点，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = Catalog.save_path("MK14")
	durations = {"approach": 1.8, "weighing": 2.4, "delivery": 3.8}
	# 走到秤前、摆放与抬秤那几幕贴近铜秤；交付那一幕由宿主负责拉回整座庭院。
	zoom_stages = ["puzzle", "weighing", "result"]
	rules = Rules; world_script = World

func goal_line() -> String:
	return "点车接单 · 每一单只从上一式挪一枚 · 抬秤验平"

# 提交之前只报玩家自己做过的事：交了几单、这一单手里挪了几枚。
# 两盘各压多少、哪头沉一律不写在这里——那要等秤抬起来才作数。
func status_line() -> String:
	var step := "还没接单" if state.order < 0 else "这一单挪了 %d 枚" % Rules.moved_count(state)
	return "已交 %d 单 · %s" % [Rules.delivered(state), step]

func submit_label() -> String: return "抬秤验收"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "走到摊前",
		"ready": "开始挑单", "result": "回到秤前再摆", "complete": "再配一次"}

func restart_prompt() -> Array: return ["重新体验挑单配秤这一幕？", "留在小摊", "重新体验"]

# 重摆是把整条链重排：已经签了收的那几单也一起退回街上，只留下抬过几次秤这个事实。
# 这话必须说在按钮前面——链子是一环扣一环的，留下任何一环都算不上「重摆」。
func reset_prompt() -> Array:
	var gone := "这一单还没交出去"
	if Rules.delivered(state) > 0: gone = "已经交出去的 %d 单也会退回街上，重新排过" % Rules.delivered(state)
	return ["三枚砝码放回架上、三单货退回各自的车？\n%s，秤仍然锁着。" % gone, "继续摆放", "全部退回重排"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "铜秤的制动还插着，三枚砝码都在左手边的架上；街上三辆车各压着一单货。"
		"ready": return "点街上那三辆车挑一单，货就搬上货盘；头一单的摆法随便摆。\n点砝码挪一格（架上 → 对面那盘 → 货盘），摆好抬秤。"
		"puzzle": return puzzle_line()
		"weighing": return "扣扣扶稳秤盘，衡伯拔出制动销……哪头沉，这会儿才看得出来。"
		"result": return Rules.result_line(state)
		"delivery": return Rules.delivery_line(state)
		"complete": return "小岚：三单都是这三枚砝码配的平，一枚也没有再添。\n衡伯：难的不是哪一式配得平，是哪一单能走在中间。"
	return ""

# 柜面那一幕的说法：规矩 + 挑单之后还能说什么。「走死了」这件事不藏，说清楚就指出退路。
func puzzle_line() -> String:
	if Rules.stuck(state): return Rules.stuck_line(state)
	if state.order < 0:
		return "点街上那三辆车挑一单：A、S、D，或者点一下车顶板。\n接了单才轮到砝码——这一单只能从上一单那一式挪一枚。"
	if state.served.is_empty():
		return "头一单随便摆：点砝码挪一格，摆好按「抬秤验收」。\n秤抬起来之前不预告平不平。"
	return "上一单记下的那一式钉在秤座上方：这一单只许从它挪一枚砝码，第二枚一碰就被拦下。"

# 三辆车是这一关的入口：点一下就把那一单的货搬上货盘。砝码架与两只盘照旧。
func build() -> void:
	for index in range(Rules.COUNT):
		add_hotspot("rack_%d" % index, world.rack_rect(index), do_cycle.bind(index), rack_tip(index))
	for side in [Rules.GOODS, Rules.FAR]:
		add_hotspot("pan_%d" % side, world.pan_rect(side), read_pan.bind(side), pan_hint(side))
	for index in range(Rules.CARTS.size()):
		add_hotspot("cart_%d" % index, world.cart_rect(index), do_choose.bind(index), cart_hint(index))

# 架上一格的说法：只说这一枚现在在哪儿、点一下会去哪儿，不说该去哪儿。
func rack_tip(index: int) -> String:
	var label := Rules.weight_name(index)
	var standing: int = Rules.side_of(state, index)
	var onward: int = Rules.next_side(state, index)
	var key := str(index + 1)
	var text := "%s 还在架上：点一下请它上秤，先站到对面那盘，再点一次才到货盘 · 键盘 %s" % [label, key] \
		if standing == Rules.OFF else \
		"%s 正站在%s：点一下挪去%s · 键盘 %s，或按 %s 让它直接回架" % [
			label, Rules.pan_name(standing), Rules.pan_name(onward), key, RETURN_LABELS[index]]
	# 只许挪一枚：能动几枚是账上的事实，说在热点文字里，玩家不必点了才知道。
	if not Rules.baseline(state).is_empty() and not Rules.can_touch(state, index):
		text += "\n这一枚已经挪过了，这一单只许挪一枚。"
	return text

func pan_hint(side: int) -> String:
	var items: Array = Rules.side_terms(state.goods, state.far, Rules.cargo_units(state), side)
	var text := "%s上站着：%s。" % [Rules.pan_name(side), "、".join(items)]
	if side == Rules.FAR: text += "这一盘不装货，只站砝码。"
	return text + "要挪砝码就点架上那一格；两盘平不平，抬了秤才知道。"

# 车上的说法：这一单写着几单位、在不在自己那辆车里、还要不要动得着。
func cart_hint(index: int) -> String:
	var key: String = CHOOSE_LABELS[index]
	if Rules.is_served(state, index):
		return "%s：这一单早就配平交出去了，货在自己车上 · 键盘 %s" % [Rules.order_tag(index), key]
	if state.order == index:
		return "%s：这一单已经接了，%d 单位的货正压在货盘上 · 键盘 %s" % [
			Rules.order_tag(index), Rules.ORDERS[index], key]
	return "%s · %d 单位：点一下接这一单，货从车上搬上货盘 · 键盘 %s" % [
		Rules.order_tag(index), Rules.ORDERS[index], key]

# 回执只复述账上真有的那几式：起手一式、每一步挪了哪一枚，最后一行是这三单之间的数学事实。
# 左上角这一张的边界三头都要算过：右边躲开口述板（338 起，位置由宿主定，动不得），
# 上边躲开关卡名牌（画到 68），下边躲开左侧那辆车（车顶画到 267）。
# 六行 16 号字、行距压到 0 才是 126 像素，150 的内框刚好装下——实窗审计量出来的。
func receipt_rect() -> Rect2: return Rect2(24, 76, 306, 182)
func receipt_text_rect() -> Rect2:
	var panel = receipt_rect()
	return Rect2(panel.position + Vector2(16, 12), panel.size - Vector2(30, 20))

func receipt_lines() -> Array:
	var lines := ["回执 · 一单只挪一枚"]
	lines.append_array(Rules.migration_parts(state))
	lines.append(Rules.distant_line())
	# 这一行是三枚砝码的数学事实：1 至 13 每一单都只有一种摆法配得平，回执上说的是真话。
	if Rules.spans_all(): lines.append("1 至 13 每单只一解")
	return lines

func extra() -> void:
	if state.stage != "complete": return
	UIStyle.panel(ui, receipt_rect())
	var paper = UIStyle.text(ui, "\n".join(receipt_lines()), receipt_text_rect(), 16)
	# 18 号字的默认行距是 5 像素，六行就会把末行推出纸面：行距是主题常量，只能覆盖。
	paper.add_theme_constant_override("line_spacing", 0)

func exit_buttons() -> void:
	# 从航图进来的场合由宿主给出「返回千灯航图」；单独启动本关时也要有一条回去的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"goods": value.goods.duplicate(), "far": value.far.duplicate(), "order": value.order}

func cleared_state() -> Dictionary: return Rules.cleared(state)

# 三级提示：提醒关系 → 缩小关键选择 → 示范一个步骤。提示只多说话，奖励一分不扣。
# 第三级把「谁走中间」这一步示范出来：这一句复述的是数学事实（每单只一解，见 spans_all 检查），
# 不是作者另写的一份答案；接哪一单、挪哪一枚仍然要玩家自己动手。
func hint_texts() -> Array:
	var units: int = Rules.ORDERS[state.order] if state.order >= 0 else 13
	var whose := "13 单位那一单" if state.order < 0 else "%s 那一单" % Rules.order_tag(state.order)
	return ["往后每一单只能从上一单记下的那一式挪一枚砝码，第二枚一碰就被拦下。\n货压在货盘上，砝码两边都能站，一枚不能用两遍。",
		"三单的摆法各只有一种，所以「挪几枚」是定死的：有两单看着最近，反而要动两枚。\n谁走在中间，才让前后两单都只挪一枚。",
		"%s 的摆法只有一种：%s。\n三单里 13 单位那一单必须走在中间：走得完的顺序只有 4→13→7 与 7→13→4。" % [
			whose, Rules.arrangement_caption(units)]]

func do_cycle(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.cycle(state, index)
	if next.is_empty():
		var refused := Rules.touch_refusal(state, index)
		if not refused.is_empty():
			message = refused
			refresh(); return
		message = "这一枚现在挪不动：要么它已经站在你要去的那一盘，要么秤还没走到跟前。"
		refresh(); return
	place(next)

func do_return(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.return_weight(state, index)
	if next.is_empty():
		var refused := Rules.touch_refusal(state, index)
		if not refused.is_empty():
			message = refused
			refresh(); return
		message = "%s 本来就还在架上。" % Rules.weight_name(index)
		refresh(); return
	place(next)

# 挑单就是把那一单的货搬上货盘：数字是货单上写好的，玩家不填、也不改。
# 货盘上同一时刻只压着一单——交出去的那一单跟着自己的车走了，才轮到下一单。
func do_choose(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if Rules.is_served(state, index):
		message = "这一单早就配平交出去了：货回到自己那辆车上，等的是另外两单。"
		refresh(); return
	if state.order == index:
		message = cart_hint(index)
		refresh(); return
	var next = Rules.choose(state, index)
	if next.is_empty(): return
	message = ""
	place(next)

# 盘面那一格只念不动：把玩家自己摆出来的东西照念一遍，不替他改。
func read_pan(side: int) -> void:
	if modal or transient > 0 or state.stage in rules.ANIMATIONS: return
	message = pan_hint(side); refresh()

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_1 + Rules.COUNT - 1: do_cycle(key - KEY_1)
	elif RETURN_KEYS.find(key) >= 0: do_return(RETURN_KEYS.find(key))
	elif CHOOSE_KEYS.find(key) >= 0: do_choose(CHOOSE_KEYS.find(key))
	else: return false
	return true

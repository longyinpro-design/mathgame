extends "res://scripts/market/level_host.gd"
# MK14 千灯集市「三枚砝码的小摊」（可选支线，MK11 之后开放）：
# 老货栈把摊子上唯一的三枚砝码 1、3、9 借给油庭院的小摊，两盘都能站，每枚最多上一次秤；
# 街上接连送来两单真货——桥头灯行 5 单位、中街油铺 8 单位，货压在指定的货盘上。
# 玩家只挪砝码，不解锁新砝码：5+3+1=9、8+1=9。 reward 那一拍是「迁移」：
# 上一单交完，下一单的货被推上同一具秤，三枚砝码留在原地，挪一挪就又兑了一单。
# 台词与提示按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
const Rules = preload("res://scripts/market/mk14_rules.gd")
const World = preload("res://scripts/market/mk14_world.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
# 1 / 2 / 3 挪砝码，Q / W / E 把手里那枚放回架上；提交与撤销由宿主的空格、Z 负责。
const RETURN_KEYS = [KEY_Q, KEY_W, KEY_E]
const LINES = [
	"衡伯：摊子上就这三枚砝码，一、三、九，\n两单新到的货都得凭它们配平，一枚也不添。",
	"扣扣：砝码站在对面那盘不就行了，\n哪头沉哪头轻，谁看不出来？",
	"小岚：货压在左边这只货盘上，砝码两边都能站，一枚最多上一次秤。\n摆法我们不给你，秤也不提前说话——抬起来才知道。",
]

func configure() -> void:
	scene_id = "oil"; level_id = "MK14"; title = Catalog.title("MK14")
	# 试玩与实窗检查会在加入场景树前先写入自己的 /tmp 落点，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = Catalog.save_path("MK14")
	durations = {"approach": 1.8, "weighing": 2.4, "delivery": 3.8}
	# 走到秤前与抬秤那两幕贴近铜秤；交付那一幕由宿主负责拉回整座庭院。
	zoom_stages = ["puzzle", "weighing", "result"]
	rules = Rules; world_script = World

func goal_line() -> String:
	return "两盘一样重这一单才走 · 1/3/9 各一枚 · 两盘都能站"

# 提交之前只报玩家自己做过的事：几枚上秤、抬过几次。
# 两盘各压多少、哪头沉一律不写在这里——那要等秤抬起来才作数。
func status_line() -> String:
	return "上秤 %d 枚 · 抬 %d 次" % [Rules.weights_on_scale(state), state.weighs]

func submit_label() -> String: return "抬秤验收"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "走到摊前",
		"ready": "开始配秤", "result": "回到秤前再摆", "complete": "再配一次"}

func restart_prompt() -> Array: return ["重新体验配秤这一幕？", "留在小摊", "重新体验"]
# 第二句只说此刻真在账上的事：第一单还没交出去时，「已经配平交出去的那一单」还不存在。
func reset_prompt() -> Array:
	var kept := "已经配平交出去的那一单不会重来" if state.delivered > 0 else "这一单还没交出去"
	return ["三枚砝码全部放回架上？\n%s，秤仍然锁着。" % kept, "继续摆放", "砝码放回架上"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "铜秤的制动还插着，三枚砝码都在左手的架上。"
		# 简报把两条操作都说全：鼠标一格一格挪，键盘上想省事就直接把手里那枚放回架上。
		"ready": return "货压在货盘上，砝码两边都能站，一枚最多上一次秤。\n点一下挪一格；按 Q、W、E 让手里那枚直接回架。"
		"puzzle": return "点一下架上的砝码，它就挪一个地方：架上 → 对面那盘 → 货盘。\n摆好就按「抬秤验收」，秤抬起来之前不预告平不平。"
		"weighing": return "扣扣扶稳秤盘，衡伯拔出制动销……哪头沉，这会儿才看得出来。"
		"result": return Rules.result_line(state)
		"delivery": return delivery_line()
		"complete": return complete_line()
	return ""

# 交付那一幕说的是眼前这一次：还有下一单就说货又被推上秤，最后一单就说三枚没添。
func delivery_line() -> String:
	var head := "衡伯画押：%s 的 %d 单位当场配平。" % [Rules.order_name(state.order), Rules.ORDERS[state.order]]
	if state.order + 1 < Rules.ORDERS.size():
		return head + "\n下一单的货紧跟着推上同一具秤，砝码一枚也没换。"
	return head + "\n两单都是这三枚砝码配的平，一枚也没有再添。"

func complete_line() -> String:
	return "小岚：两单的摆法都记在那具小铜秤上了。\n衡伯：同一组砝码挪个位置就又兑了一单。"

# 三格砝码架永远点得动：站在哪儿，那一格就是「挪一挪」或「放回架上」。
# 两只盘与三辆车也点得，但只把玩家自己摆出来的东西念给他听，不改现场。
func build() -> void:
	for index in range(Rules.COUNT):
		add_hotspot("rack_%d" % index, world.rack_rect(index), do_cycle.bind(index), rack_tip(index))
	for side in [Rules.GOODS, Rules.FAR]:
		add_hotspot("pan_%d" % side, world.pan_rect(side), read_pan.bind(side), pan_hint(side))
	for index in range(Rules.CARTS.size()):
		add_hotspot("cart_%d" % index, world.cart_rect(index), read_order.bind(index), cart_hint(index))

# 架上一格的说法：只说这一枚现在在哪儿、点一下会去哪儿，不说该去哪儿。
func rack_tip(index: int) -> String:
	var label := Rules.weight_name(index)
	var standing: int = Rules.side_of(state, index)
	if standing == Rules.OFF:
		return "%s 还在架上：点一下请它上秤，先站到对面那盘，再点一次才到货盘 · 键盘 %d" % [label, index + 1]
	return "%s 正站在%s：点一下挪去%s · 键盘 %d" % [label, Rules.pan_name(standing),
		Rules.pan_name(Rules.NEXT[standing]), index + 1]

func pan_hint(side: int) -> String:
	var items: Array = Rules.side_terms(state.goods, state.far, Rules.cargo_units(state), side)
	var text := "%s上站着：%s。" % [Rules.pan_name(side), "、".join(items)]
	if side == Rules.FAR: text += "这一盘不装货，只站砝码。"
	return text + "要挪砝码就点架上那一格；两盘平不平，抬了秤才知道。"

func cart_hint(index: int) -> String:
	if index >= Rules.ORDERS.size():
		return "交货车：已经签了收的 %d 单都停在这儿。" % state.delivered
	return "%s：%s。点一下让扣扣把这单再念一遍。" % [Rules.ORDER_TAGS[index], Rules.order_caption(index)]

# 回执只复述账上真有两笔：谁留在原地、谁挪了地方，最后一行是这一组砝码的数学事实。
# 左上角这一张的边界三头都要算过：右边躲开口述板（338 起，位置由宿主定，动不得），
# 上边躲开关卡名牌（画到 68），下边躲开左侧那辆接货车（车顶画到 267）。
# 六行 18 号字要 162 像素高，168 的板留下 20 的上下内边距只够五行——实窗审计量出来的。
func receipt_rect() -> Rect2: return Rect2(24, 76, 306, 182)
func receipt_text_rect() -> Rect2:
	var panel = receipt_rect()
	return Rect2(panel.position + Vector2(16, 12), panel.size - Vector2(30, 20))

func receipt_lines() -> Array:
	var lines := ["回执 · 砝码一枚没添"]
	lines.append_array(Rules.migration_parts(state))
	# 这一行是本章最长的一句汉字：342 像素比 276 的内框还宽，Godot 把汉字当一个不断词，
	# 整句会画到口述板上去，所以按「一行只在一处换行」的写法自己拆开。
	if Rules.spans_all(): lines.append("同一组 1、3、9\n1 至 13 每单只一解")
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
	return {"goods": value.goods.duplicate(), "far": value.far.duplicate()}

func cleared_state() -> Dictionary: return Rules.cleared(state)

# 三级提示：提醒关系 → 缩小关键选择 → 示范一个步骤。提示只多说话，奖励一分不扣。
func hint_texts() -> Array:
	var units: int = Rules.ORDERS[clampi(int(state.get("order", 0)), 0, Rules.ORDERS.size() - 1)]
	return ["两盘一样重，这一单才走得掉。\n货压在货盘上，砝码两边都能站，一枚不能用两遍。",
		"先只把砝码全站到对面那盘：凑得出 %s。\n里面没有 %d——总得有一枚站到货物这头来。" % [
			"、".join(number_words(Rules.one_pan_sums())), units],
		"这一单的摆法只有一种：%s。\n点一下架上的砝码，让它一站一站挪过去。" % Rules.arrangement_caption(units)]

func number_words(values: Array) -> Array:
	var out := []
	for value in values: out.append(str(value))
	return out

func do_cycle(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.cycle(state, index)
	if next.is_empty():
		message = "这一枚现在挪不动：秤还没走到跟前，或它已经站在你要去的那一盘。"
		refresh(); return
	place(next)

func do_return(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.return_weight(state, index)
	if next.is_empty():
		message = "%s 本来就还在架上。" % Rules.weight_name(index)
		refresh(); return
	place(next)

# 盘面与车上那两格只念不动：把玩家自己摆出来的东西照念一遍，不替他改。
func read_pan(side: int) -> void:
	if modal or transient > 0 or state.stage in rules.ANIMATIONS: return
	message = pan_hint(side); refresh()

func read_order(index: int) -> void:
	if modal or transient > 0 or state.stage in rules.ANIMATIONS: return
	if index >= Rules.ORDERS.size():
		message = "交货车上停着已经签收的 %d 单。" % state.delivered
	else:
		message = "扣扣把这单念了一遍：%s。\n货压在货盘上，砝码还是这三枚。" % Rules.order_caption(index)
	refresh()

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_1 + Rules.COUNT - 1: do_cycle(key - KEY_1)
	elif RETURN_KEYS.find(key) >= 0: do_return(RETURN_KEYS.find(key))
	else: return false
	return true

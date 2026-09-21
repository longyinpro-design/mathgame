extends "res://scripts/market/level_host.gd"
# MK03 育苗铺「封箱里的重量」：柜面上摊着两份公开称量，秤被制动锁着。
# 玩家先把记录二叠到记录一上消去相同的一组，再为红、蓝箱各挑一枚重签挂上，最后按「挂签复秤」，
# 缺哪条承诺只在提交之后按玩家自己的说法讲给他听；复秤通过才翻出那次的原单。
const Rules = preload("res://scripts/market/mk03_rules.gd")
const World = preload("res://scripts/market/mk03_world.gd")
const BLUE_KEYS = [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U]
const LINES = [
	"衡伯：那两单货，一单 14 斤、一单 13 斤，\n封箱交来却没人称过。扣扣，你说箱里没少东西？",
	"扣扣：箱子是封着的，我不敢拆。\n两次交货的重量签都在路上掉了……",
	"小岚：不用拆。柜面上贴着两次公开称量，同类封箱一样重。\n给红箱、蓝箱各挂一枚重签，再复一次秤，原单就找得出来。",
]

func configure() -> void:
	scene_id = "nursery"; level_id = "MK03"; title = "封箱里的重量"
	# 试玩与实窗检查会在加入场景树前写入自己的 /tmp 路径，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk03-1/save-v1.json"
	durations = {"approach": 1.6, "reweigh": 2.6, "delivery": 4.2}
	zoom_stages = ["puzzle", "reweigh"]
	rules = Rules; world_script = World

func goal_line() -> String:
	return "两条公开称量都要成立：%s · %s" % [Rules.equation(0), Rules.equation(1)]

func status_line() -> String:
	return "红 %s · 蓝 %s · %s" % [tag_word(state.red), tag_word(state.blue), "已叠" if Rules.folded(state) else "未叠"]

func tag_word(tag: int) -> String: return "未挂" if tag == 0 else str(tag)

func submit_label() -> String: return "挂签复秤"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < 2 else "靠近育苗铺",
		"ready": "开始查货", "complete": "再查一次"}

func restart_prompt() -> Array: return ["重新体验查货这一幕？", "留在育苗铺", "重新体验"]
func reset_prompt() -> Array:
	return ["把两枚重签放回签架？\n已经叠好的记录会保持叠好，秤仍然锁着。", "继续摆放", "重签放回签架"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "柜面上摊着两次公开称量，货栈的铜秤锁着制动。"
		"ready": return "封箱不能拆：先叠合两份记录，再给红、蓝箱挂重签。"
		"puzzle": return "点记录二把它叠到记录一上，消去相同的一组；\n再从两排重签里各挑一枚挂上，秤不会提前告诉你对没对。"
		"reweigh": return "衡伯松开制动销……两条记录依次上秤。"
		"delivery": return "衡伯：两次合重都对上了！扣扣，把那次的原单翻出来。"
		"complete": return "小岚：箱子没拆，重量签回来了，原单也就找到了。"
	return ""

func build() -> void:
	# 热点要压在 tooltip 说的那张纸上：没叠的时候能点的是右边那张记录二，
	# 叠好之后能点的是合起来的那一摞。原先两处正好写反，玩家点记录二没有反应，
	# 点叠好的那一摞也没反应，倒是把右侧空台上那张「差量签」点了就分开。
	var folding = not Rules.folded(state)
	add_hotspot("fold", world.card_rect(1) if folding else world.stack_rect(), do_fold,
		"把记录二叠到记录一上，消去相同的 1 红 1 蓝" if folding else "把两份记录分开，重新摆回台面")
	for kind in range(2):
		var label = Rules.kind_name(kind)
		var tag: int = Rules.hung(state, kind)
		var hook = ("挂着 %d 号重签，点一下取回签架" % tag) if tag > 0 else "还空着，点下面签架挑一枚"
		add_hotspot("crate_%d" % kind, world.crate_rect(kind), take_tag.bind(kind),
			"%s的钩子：%s" % [label, hook])
		for value in range(Rules.TAG_MIN, Rules.TAG_MAX + 1):
			var slot = "已经挂着，点一下取回" if tag == value else "点一下挂上"
			add_hotspot("tag_%d_%d" % [kind, value], world.tag_rect(kind, value), choose_tag.bind(kind, value),
				"%s挂 %d 号重签：%s" % [label, value, slot])

func extra() -> void:
	if state.stage != "complete": return
	# 回执只复述玩家真正做过的事：他挂的两枚重签、消去的那一组，以及两条公开记录各自合出多少
	# （能翻出原单，说明这两条都被他的挂法兑现了，所以直接引用柜面上那两行原话）。
	UIStyle.panel(ui, Rect2(116, 352, 432, 172))
	UIStyle.text(ui, "回执 · 育苗铺封箱重签\n红箱挂 %d 号 · 蓝箱挂 %d 号\n叠合两份记录，消去 1 红 1 蓝：红比蓝重 %d 斤\n复秤：%s · %s" % [
		state.red, state.blue, Rules.DIFFERENCE, Rules.equation(0), Rules.equation(1)],
		Rect2(132, 364, 404, 152), 18)

func exit_buttons() -> void:
	# 从航图进来的场合由宿主给出「返回千灯航图」；单独启动本关时也要有一条回去的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"stacked": value.stacked, "red": value.red, "blue": value.blue}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true); next.red = 0; next.blue = 0
	return next

func hint_texts() -> Array:
	return ["同类封箱一样重，箱子不能拆开称。\n两份记录里都出现 1 红 1 蓝，那一部分叠起来就抵消了。",
		"记录一 14 斤、记录二 13 斤：叠合消去 1 红 1 蓝之后，\n只剩 1 红 比 1 蓝 重 1 斤。",
		"把记录一看成 1 红 +（1 红 1 蓝）：红箱比蓝箱重 1，\n14 斤就是 3 个蓝箱加 1 斤——蓝 4、红 5，两个钩子各挂一枚。"]

func do_fold() -> void:
	place(Rules.unfold(state) if Rules.folded(state) else Rules.fold(state))

func choose_tag(kind: int, tag: int) -> void:
	# 同一枚重签再点一次就是取回：签架上不会有第二枚挂到同一个钩子上。
	place(Rules.unhang(state, kind) if Rules.hung(state, kind) == tag else Rules.hang(state, kind, tag))

func take_tag(kind: int) -> void:
	place(Rules.unhang(state, kind))

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_1 + Rules.TAG_MAX - 1: choose_tag(Rules.RED, key - KEY_1 + Rules.TAG_MIN)
	elif BLUE_KEYS.find(key) >= 0: choose_tag(Rules.BLUE, BLUE_KEYS.find(key) + Rules.TAG_MIN)
	elif key == KEY_A: do_fold()
	else: return false
	return true

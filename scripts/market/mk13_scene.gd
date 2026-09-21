extends "res://scripts/market/level_host.gd"
# MK13 扣扣的旧围巾（可选支线，MK04 之后开门）：柜面上摊着两包 5 段与三包 3 段补边布，
# 柜头立着一把 11 格的对折样边尺——第 6 格正中压着折线。玩家把整包拿起来按拿的先后摊到尺上，
# 再按「交给扣扣补边」。交的条件有两条：11 格摊满，且对折过来两头一段对一段。
# 只看段数，摊满 11 格有三条走法（5+3+3、3+5+3、3+3+5），对折这一条把前两种和最后一种都挡在门外：
# 5 段那一包必须压在折线上，两边各余 3 格。差几段、齐不齐都不写在底栏里，尺面自己数得出来。
# 补好的边先出现在扣扣的围巾上，接着是她学徒第一次送货的那一小段故事；
# 要不要把补好的边戴在外面，是玩家自愿的选择，只写进本关自己的存档。
# 台词与提示按行写死：一长串汉字在 Godot 里是一个不可断的词，会自动画到框外。
const Rules = preload("res://scripts/market/mk13_rules.gd")
const World = preload("res://scripts/market/mk13_world.gd")
const PACKAGE_KEYS = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
# 回执纸放在柜台左边：不压住扣扣脖子上补好的那条边，也不盖掉柜面上的货与货签。
const RECEIPT = Rect2(96, 232, 432, 180)
const RECEIPT_TEXT = Rect2(112, 244, 404, 160)
const LINES = [
	"扣扣：我这条围巾的边磨开了，一段一段数下来，正好缺 11 段补边布。\n育苗铺只按整包卖：一包 3 段，或者一包 5 段。",
	"扣扣：补这条边得把围巾对折着来，缝完两头要一样长。\n折过来哪一段对不上哪一段，戴出去一边长一边短，比现在还难看。",
	"小岚：包不能剪开，也不退半包。柜头这把样边尺有 11 格，折线正压在第 6 格上。\n把包摊上去，两头一段对一段地照齐了，扣扣才肯收钱。",
]
const STORY = [
	"扣扣：这条围巾是我当学徒第一次送货那天，师父用剩下的布头给我围上的。\n那天我拉一车铃铛去东堤，怕出错，一路都在数轮子响了几声。",
	"扣扣：送到以后我才知道，回执上的数目和我数的一样。师父让我自己把围巾洗了。\n边就是那次洗开的。他说：边开了别剪，剪了就短一截，补上去就好。",
	"扣扣：这是我第一次自己攒钱补它。\n……补好的边，你要我戴出来吗？你说戴，我就戴。",
]

func configure() -> void:
	scene_id = "nursery"; level_id = "MK13"; title = "扣扣的旧围巾"
	# 试玩与实窗检查会在加入场景树前写入自己的 /tmp 路径，默认值永远不能盖过它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk13-1/save-v1.json"
	durations = {"approach": 1.6, "delivery": 4.2}
	zoom_stages = ["puzzle"]
	rules = Rules; world_script = World

func goal_line() -> String:
	# 故事与交货之后不再挂目标：那一段是回报，不是题目。
	if state.get("stage", "") in ["story"]: return ""
	return "整包摊满 11 格 · 对折过来两头要一段对一段"

# 底栏只报尺面上数得出的事：摊了几包、几段。差几段、齐不齐都不写在这里——
# 尺上的格子本来就从 1 编到 11，折线就压在第 6 格上，那是玩家自己眼睛该做的两次比对。
func status_line() -> String:
	return "%d 包 · %d 段摊在尺上" % [Rules.carried(state), Rules.total(state)]

func submit_label() -> String: return "交给扣扣补边"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听她说" if state.beat < 2 else "走到育苗铺柜前",
		"ready": "开始挑包",
		"story": "再听一句" if state.beat < 2 else "看看补好的围巾",
		"complete": "再补一次"}

func restart_prompt() -> Array: return ["重新体验补围巾这一幕？", "留在育苗铺", "重新体验"]
func reset_prompt() -> Array:
	return ["把摊在样边尺上的包全部退回柜面？\n段数与折线都会跟着退回去，钱一文没花。", "继续挑包", "全部退回柜面"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "柜头立着育苗铺的样边尺：11 格，一格一段补边布，折线压在第 6 格上。"
		"ready": return "整包拿起来摊到尺上，对折照得齐了再交给扣扣去缝。"
		"puzzle": return "点柜面上的整包，它就摊到样边尺的空格里；再点那一截就退回柜面。\n包不能剪开，摊不下的那一包拿不起来。"
		"delivery": return "扣扣把量好的补边布一针一针缝上围巾的边……"
		"story": return STORY[state.beat]
		"complete": return "小岚：摊得满，折得齐。这条边往后就是你的了。"
	return ""

func build() -> void:
	for id in range(Rules.packages()):
		var segs: int = Rules.segs(id)
		var held = Rules.in_hand(state, id)
		var tip = "这包 %d 段已经摊在样边尺上：点一下退回柜面" % segs if held else \
			"整包 %d 段，不能剪开：尺上还剩 %d 格，摊得下就点一下拿起来" % [segs, Rules.free_slots(state)]
		add_hotspot("stock_%d" % id, world.stock_rect(id), toggle_package.bind(id), tip)
	for slot in range(Rules.carried(state)):
		var pid: int = Rules.run_package(state, slot)
		var from = Rules.run_start(state, slot) + 1
		var tip = "第 %d~%d 格是这包 %d 段摊开的：点一下整包退回柜面" % [from, from + Rules.run_segs(state, slot) - 1, Rules.segs(pid)]
		add_hotspot("run_%d" % slot, world.run_rect(state, slot), toggle_package.bind(pid), tip)

func extra() -> void:
	if state.stage not in ["story", "complete"]: return
	add_button("wear", "换回原来的样子" if Rules.wearing(state) else "换上补好的围巾",
		Rect2(380, 646, 290, 54), toggle_wear)
	if state.stage != "complete": return
	# 回执只复述玩家真正拿过的那几包，以及柜上因此少了什么。
	UIStyle.panel(ui, RECEIPT)
	UIStyle.text(ui, receipt_text(), RECEIPT_TEXT, 18)

func receipt_text() -> String:
	return "回执 · 育苗铺补边布\n拿的包：%s = %d 段\n对折过来：两头一段挨着一段，正好齐\n柜上还剩：%s" % [
		Rules.packages_line(state), Rules.total(state), Rules.left_line(state)]

func exit_buttons() -> void:
	# 从航图进来的场合由宿主给出「返回千灯航图」；单独启动本关时也要有一条回去的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"hand": value.hand.duplicate(true), "worn": value.worn}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true); next.hand = []
	return next

# 三级提示：提醒对折这件事 → 缩小「哪一包压折线」这个关键选择 → 示范一步。
# 提示只多说话，奖励一分不扣；最短的那一级不替玩家点包。
func hint_texts() -> Array:
	return ["围巾是对折着补的：从第 6 格折过去，两头要一段对一段。\n包只有 3 段和 5 段两种，不能剪开，摊满 11 格为止。",
		"压着折线的那一包若是 3 段，两头各余 4 格：4 段摊不成整包。\n是 5 段就各余 3 格，正好一边一包 3 段。",
		"先点一包 3 段摊到最左边，再点一包 5 段：它正好跨过折线。\n最后再点一包 3 段，落在最右边那三格上。"]

# 柜面上的包一换，上一句按旧拿法说的话当场就不成立了：撤销与「重摆」也走这里，
# 先收回那句话，再让样边尺自己报新数——玩家看到的永远是自己此刻手上的段数。
func commit(candidate: Dictionary, next_history: Array = []) -> bool:
	if state.stage == "puzzle" and candidate.has("hand") and candidate.hand != state.hand: message = ""
	return super.commit(candidate, next_history)

func toggle_package(id: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if Rules.in_hand(state, id):
		var back = Rules.give_back(state, id)
		if back.is_empty(): return
		var said = Rules.returned_line(back, id)
		place(back)
		# 只有真的退回柜面了才说这一句：存盘失败时保留模态里的原话。
		if state.hand == back.hand: message = said; refresh()
		return
	var next = Rules.take(state, id)
	if next.is_empty():
		message = Rules.refusal(state, id)
		refresh()
		return
	message = ""
	place(next)

func toggle_wear() -> void:
	if modal or transient > 0: return
	var next = Rules.tuck(state) if Rules.wearing(state) else Rules.wear(state)
	if next.is_empty(): return
	var said = Rules.wear_line(next)
	commit(next)
	if state.worn == next.worn: message = said; refresh()

func handle_key(key: int) -> bool:
	var at = PACKAGE_KEYS.find(key)
	if at < 0 or at >= Rules.packages(): return false
	toggle_package(at)
	return true

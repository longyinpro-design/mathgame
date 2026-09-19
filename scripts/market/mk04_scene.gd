extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk04_rules.gd")
const World = preload("res://scripts/market/mk04_world.gd")
# 开场三句、澄清四句逐句由玩家推进；第三张单的拒绝理由常显在这一份文案里。
const LINES = [
	"衡伯：这批货的收据对不上，铃少了一只。扣扣，你数过没有？",
	"扣扣：我是照着第三张换的……要不要我再赔一点？",
	"小岚：先别赔。三条单子并排放好，用真货物换一遍再说。"]
const CLARIFY = [
	"正确的货物摆在原单下，扣扣把自己抄的那张货签翻了过来。",
	"扣扣：这个三，是我写的。可我没有藏起来那只铃。",
	"衡伯：是两回事。我把它们当成了一回事。",
	"扣扣：那……下一次，能不能和我一起看一遍？"]
# 对白板的内框只有 798×56：一行 22 像素的字刚好，两行就会从板子下沿爬出去。理由压成一句。
const REFUSAL = "第三张是抄来的，柜面上没人认这一条：按它换会凭空多出铃，还能反复刷货。"
const RULE_NOTES = ["原约一：两家各留一张原章，1 卷布换 2 瓶油。",
	"原约二：两家各留一张原章，3 瓶油换 1 只铜铃。"]

func configure() -> void:
	scene_id = "nursery"; level_id = "MK04"; title = "对不上的收据"
	# 实窗测试会在加入场景树前写入自己的 /tmp 路径，默认值永远不能盖掉它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk04-1/save-v1.json"
	durations = {"approach": 1.6, "exchanging": 0.8, "correcting": 1.2, "delivery": 4.6}
	rules = Rules; world_script = World
	zoom_stages = ["puzzle", "exchanging", "correcting"]

# 一批换得越多演得越久，但每组不会比单独换更快；改签是一次书写，不是一批搬运。
func duration() -> float:
	if state.stage == "exchanging": return 0.8 + 0.24 * (state.exchange[1] if state.exchange.size() == 2 else 1)
	if state.stage == "correcting": return 1.2
	return durations[state.stage]

func goal_line() -> String: return "实换 3 卷布：布 → 油 → 铃，再给第三张改签"
func submit_label() -> String: return "核对收据"

func status_line() -> String:
	# 这块板子只有 300×42：状态压成一行，中文不靠自动折行。
	var claim = "待核对" if state.correction == 0 else "订正 %d" % state.correction
	return "布 %d · 油 %d · 铃 %d · %s" % [Rules.cloth_left(state), Rules.oil_loose(state),
		Rules.bells_loose(state), claim]

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.ARRIVAL_BEATS - 1 else "到柜面前看看",
		"ready": "开始实换",
		"clarify": "继续听他们说" if state.beat < Rules.CLARIFY_BEATS - 1 else "看这次的回执",
		"complete": "重新体验"}

func restart_prompt() -> Array: return ["重新体验收据这一幕？", "留在柜面", "重新体验"]
func reset_prompt() -> Array:
	return ["把换出去的货全部退回原处？\n第三张也回到扣扣抄来的那个数。", "继续核对", "全部退回原处"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "两张原约并排钉上柜面，扣扣把 3 卷布搬到左边。"
		"ready": return "只有两边都盖了章的约定能执行：1 卷布换 2 瓶油，3 瓶油换 1 只铜铃。"
		"puzzle": return "把 3 卷布沿两条原约换到底，再和第三张对照，给它改签。"
		"exchanging": return "扣扣一件件搬货……这一组是按原约换的，已经记上了。"
		"correcting": return "扣扣把数字写回第三张：写几只，得看你刚换出来的铃。"
		"delivery": return "衡伯：铃是两只，收据写的却是三只……我把两回事当成了一回事。"
		"clarify": return CLARIFY[state.beat]
		"complete": return "小岚：数字不对只说明收据不一致，抄错不等于偷货。"
	return ""

func build() -> void:
	for rule in range(Rules.RULE_COUNT):
		var times = Rules.affordable(state, rule)
		var x = 330 + rule * 470
		var single = add_button("single_%d" % rule, "换 1 组", Rect2(x, 560, 100, 44), do_exchange.bind(rule, 1))
		single.disabled = times < 1 or transient > 0
		var batch = add_button("batch_%d" % rule, "全换完", Rect2(x + 106, 560, 92, 44), do_exchange.bind(rule, times))
		batch.disabled = times < 1 or transient > 0
		batch.tooltip_text = "一次换满 %d 组，随后一次性演出" % times
		var pool = Rules.cloth_left(state) if rule == 0 else Rules.oil_loose(state)
		UIStyle.text(ui, "%s %d %s · 可换 %d 组" % ["布" if rule == 0 else "油", pool, "卷" if rule == 0 else "瓶", times],
			Rect2(x, 608, 240, 32), 16)
	# 三张单都要点得动：两张原约念出条款，第三张念出「为什么现在不能按它换」。
	for index in range(2):
		add_hotspot("card_%d" % index, world.card_rect(index), read_rule.bind(index),
			"原约%s：双方都留有原章，可以执行" % ["一", "二"][index])
	add_hotspot("card_third", world.card_rect(2), try_third, "第三张：扣扣的转抄件，点它按这一条换一次")
	add_button("third_try", "按第三张换", Rect2(52, 596, 140, 44), try_third)
	for index in range(Rules.CANDIDATES.size()):
		var value: int = Rules.CANDIDATES[index]
		add_hotspot("cand_%d" % index, world.cand_rect(index), choose_candidate.bind(index),
			"改签候选：%d 卷布换 %d 只铜铃%s" % [Rules.CLOTH, value, "（当前已选）" if state.correction == value else ""])

func extra() -> void:
	if state.stage != "complete": return
	# 回执按玩家真的做过的那一遍复述：两条原约各几组、换出多少，以及第三张最后写成几。
	# 这块纸只占柜面左下：三张单、扣扣、两只铃与右半的台面牌都要留在眼睛看得见地方。
	UIStyle.panel(ui, Rect2(24, 412, 486, 232))
	UIStyle.text(ui, "回执 · 育苗铺 第 4 单\n原约一 ×%d：%d 卷布 → %d 瓶油\n原约二 ×%d：%d 瓶油 → %d 只铜铃\n第三张改签：%d 卷布换 %d 只铜铃\n收据不一致：两条原约实换证明\n抄错不是偷货：原单 2、转抄 3" % [
		state.a, Rules.CLOTH, Rules.OIL_PER_CLOTH * state.a, state.b, Rules.OIL_PER_BELL * state.b,
		Rules.bells_loose(state), Rules.CLOTH, state.correction], Rect2(40, 424, 456, 208), 18)

func exit_buttons() -> void:
	# 从航图进来时宿主已经放了返回键；单独启动这一幕也要有一条回航图的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"a": value.a, "b": value.b, "correction": value.correction}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	next.a = 0; next.b = 0; next.correction = 0; next.proposed = 0; next.exchange = []
	return next

func hint_texts() -> Array:
	# 对白板的内框是 798×56：每档只放得下一行 22 像素的字，所以每档各留一个重点。
	return ["能执行的只有盖了章的两张原约：1 卷布换 2 瓶油，3 瓶油换 1 只铜铃。",
		"把 %d 卷布全按原约一换完是 %d 瓶油；再看 %d 瓶油能分几组，每组 %d 瓶。" % [
			Rules.CLOTH, Rules.OIL, Rules.OIL, Rules.OIL_PER_BELL],
		"%d 卷布 → %d 瓶油 → %d 只铃；要 %d 只铃得 %s 卷布，柜面上换不出来。" % [
			Rules.CLOTH, Rules.OIL, Rules.CORRECT_BELLS, Rules.WRITTEN_BELLS, "4.5"]]

func read_rule(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	message = RULE_NOTES[index]; refresh()

func try_third() -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	message = REFUSAL; refresh()

func do_exchange(rule: int, times: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.exchange(state, rule, times)
	if next.is_empty():
		if rule == 0: message = "柜面上的布已经全部换过了，剩下的铃只能由油换出来。"
		else: message = "台面上只剩 %d 瓶油，凑不成 %d 瓶一组：这一组换不出来。" % [Rules.oil_loose(state), Rules.OIL_PER_BELL]
		refresh(); return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next, next_history)

func choose_candidate(index: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if index < 0 or index >= Rules.CANDIDATES.size(): return
	var value: int = Rules.CANDIDATES[index]
	if state.a != Rules.CLOTH:
		message = "先按两条原约把 %d 卷布换完，再决定第三张写几只。" % Rules.CLOTH
		refresh(); return
	if state.correction == value:
		place(Rules.clear_correction(state)); return
	var next = Rules.propose(state, value)
	if next.is_empty(): return
	var next_history = history.duplicate(true); next_history.append(snapshot(state))
	commit(next, next_history)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_3: choose_candidate(key - KEY_1)
	elif key == KEY_Q: do_exchange(0, 1)
	elif key == KEY_A: do_exchange(0, Rules.affordable(state, 0))
	elif key == KEY_W: do_exchange(1, 1)
	elif key == KEY_S: do_exchange(1, Rules.affordable(state, 1))
	elif key == KEY_T: try_third()
	else: return false
	return true

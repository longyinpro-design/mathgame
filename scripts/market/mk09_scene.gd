extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk09_rules.gd")
const World = preload("res://scripts/market/mk09_world.gd")
const KEYS = ["Q", "W", "E", "R", "T"]
# 台词按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
const LINES = [
	"扣扣：五家的货都摆在门口了，\n可谁都不肯先把自己手上那件交出去。",
	"老规矩是以物易物，两个人当面换。\n小岚：那要是五摊一起换，还得两两凑成一对吗？",
	"扣扣：我把五摊第一次当众叫到同一条街上。\n需求都写在自家门面上——你们牵线，一次换完。",
]

func configure() -> void:
	scene_id = "street"; level_id = "MK09"; title = "不必两个人就换成"
	# 试玩会在入树前写入自己的 /tmp 落点，默认值永远不覆盖它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk09-1/save-v1.json"
	durations = {"approach": 1.7, "exchanging": 3.2, "delivery": 3.4}
	# 牵线与整批换货两段都贴近五摊，只有交货与点灯拉回整条街。
	zoom_stages = ["puzzle", "exchanging"]
	rules = Rules; world_script = World

func goal_line() -> String: return "牵起交换线，让五摊一次换完且各自满意"

func status_line() -> String:
	match state.stage:
		"puzzle":
			return "线 %d / 五 · 满意 %d / 五" % [Rules.drawn(state.lines), Rules.satisfied(state.lines).size()]
		"exchanging":
			return "已落定 %d / 五件" % world.in_flight(world.carry_plan(world.progress))["landed"].size()
		"delivery": return "满意 %d / 五摊" % Rules.satisfied(state.booked).size()
		"complete": return "三摊一圈 + 两摊对换"
	# 叫齐五摊之前没有「进度」可报：宿主也只在牵线阶段才画这一行。
	return ""

func submit_label() -> String: return "一次交上这条线"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < Rules.BEATS - 1 else "当众叫齐五摊",
		"ready": "开始牵线", "complete": "重新体验"}

func restart_prompt() -> Array:
	return ["重新体验五摊换货这一幕？", "留在街上", "重新体验"]
func reset_prompt() -> Array:
	return ["把街上的线全部拉回？\n一件货都还没挪动。", "继续牵线", "全部拉回"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "五摊各自挂着自己那件货，门前摆好一只收货盘。\n扣扣把需求挨家念了一遍。"
		"ready": return "小岚：货不能凭空多出来，也不能有一件留在原地。\n线从「谁的货」牵到「给谁」，一次牵完再交上去。"
		"puzzle": return "点一摊挂着的货，再点另一摊门前的收货盘，就牵好一条线。\n点有线的收货盘把那条线拉回；五件货各走一次，再一次交上。"
		"exchanging": return "扣扣照着你们牵的线一次挪货……\n每一件货都沿着自己的那条线走。"
		"delivery": return "五摊各自点头：拿到的是自己肯收的那一件。\n街上第一段灯串跟着亮起来。"
		"complete": return "小岚：不用两两凑对，也不用五摊挤成一个大环。\n三摊转一圈、两摊对换一次，整条街就换完了。"
	return ""

func build() -> void:
	for giver in range(Rules.COUNT):
		var note = "点一下拿起 %s 摊要出的 %s，再点收货摊" % [Rules.ACTORS[giver], Rules.GOODS[giver]]
		if state.hand == giver: note = "已经拿在手里，再点一次放手"
		elif state.lines.has(giver): note = "已许给 %s 摊：再牵一条就是同时许两家，提交时会说清" % Rules.ACTORS[state.lines.find(giver)]
		add_hotspot("good_%d" % giver, world.good_rect(giver), choose_good.bind(giver),
			"%s 摊的 %s（键盘 %d）：%s" % [Rules.ACTORS[giver], Rules.GOODS_FULL[giver], giver + 1, note])
	for receiver in range(Rules.COUNT):
		var held = state.lines[receiver]
		var kept = "空着：手里拿着货点一下就牵上 [%s]" % KEYS[receiver]
		if held >= 0: kept = "接的是 %s 摊的 %s：点一下把线拉回 [%s]" % [Rules.ACTORS[held], Rules.GOODS[held], KEYS[receiver]]
		add_hotspot("tray_%d" % receiver, world.tray_rect(receiver), choose_tray.bind(receiver),
			"%s 摊的收货盘（%s）：%s" % [Rules.ACTORS[receiver], Rules.accepts_text(receiver), kept])

# 回执逐行写在这里，交给无头检查量宽度：Label 不会在汉字中间断行，超框就会画到面板外。
# 一行一件货：从出货的那一摊念到收货的那一摊，读的全是玩家自己入账的那批线。
# 面板贴在街面左下角，上沿让到甲摊收货盘之下：只压住甲摊门口那两块木牌（内容回执自己已经复述过），
# 五摊门前的收货盘、货样与檐口的第一段灯串都留在面板之外。
func receipt_lines() -> Array:
	var lines = ["%d 件货各走一次 · %d 摊点头" % [Rules.COUNT - Rules.unmoved(state.booked).size(),
		Rules.satisfied(state.booked).size()]]
	for giver in range(Rules.COUNT):
		var receiver: int = state.booked.find(giver)
		lines.append("%s摊的%s → %s摊：%s" % [Rules.ACTORS[giver], Rules.GOODS[giver],
			Rules.ACTORS[receiver], Rules.accepts_text(receiver)])
	lines.append("合起来：%s" % Rules.shape(state.booked))
	return lines

func receipt_rect() -> Rect2: return Rect2(24, 436, 350, 222)
func receipt_text_rect() -> Rect2:
	var board = receipt_rect()
	return Rect2(board.position + Vector2(16, 12), board.size - Vector2(32, 24))

func extra() -> void:
	if state.stage != "complete": return
	# 回执按玩家真正入账的那批线复述一遍：谁把哪件货牵给了谁，全部读回 booked。
	# 行距在这里钉死为 0，八行的高度才能被无头检查按字体度量精确复算。
	UIStyle.panel(ui, receipt_rect())
	var paper = UIStyle.text(ui, "\n".join(receipt_lines()), receipt_text_rect(), 16)
	paper.add_theme_constant_override("line_spacing", 0)

func exit_buttons() -> void:
	# 从航图进来时宿主已经给出「返回集市航图」；直接启动本关样板时留一条回航图的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"lines": value.lines.duplicate(true), "hand": value.hand}

func cleared_state() -> Dictionary:
	# 重摆只清线：入账记录本来就在提交之后才出现，这里不存在需要退回的货权。
	return Rules.clear_street(state)

func hint_texts() -> Array:
	return ["五摊手上的货：甲布、乙油、丙纸、丁铃、戊绳。\n门面上写着各自肯收哪一件，一件货只能有一个新主人。",
		"戊只认铃，铃在丁手里；丁要的是绳，绳在戊手里——\n这两摊自己对上就够了，不必把五摊接成一个大环。",
		"试一条：把甲摊挂的布牵到丙摊的收货盘上——\n丙的纸正好去乙摊，乙的油回甲摊，这三摊就转成了一圈。"]

func choose_good(giver: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.pick(state, giver)
	if next.is_empty():
		message = "这一摊的货现在拿不起来。"
		refresh(); return
	# 拿起与放手只是手感，不占撤销步数：撤销一次只退回上一条牵好的线。
	commit(next, history)

func choose_tray(receiver: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.connect_line(state, receiver) if Rules.holding(state) else Rules.cut_line(state, receiver)
	if next.is_empty():
		message = "手里还没有货：先点一摊挂着的那件，再点收货盘。" if not Rules.holding(state) else "这条线拉不动。"
		refresh(); return
	place(next)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_5: choose_good(key - KEY_1)
	elif key == KEY_Q: choose_tray(0)
	elif key == KEY_W: choose_tray(1)
	elif key == KEY_E: choose_tray(2)
	elif key == KEY_R: choose_tray(3)
	elif key == KEY_T: choose_tray(4)
	else: return false
	return true

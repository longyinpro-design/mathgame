extends "res://scripts/market/level_host.gd"

# MK07 千灯集市「先别把东西平均分」：分配方案与试交回执由 mk07_rules.gd 记账，
# 画面在 mk07_world.gd；这里只做台词、热点、回执单与键盘操作。
const Rules = preload("res://scripts/market/mk07_rules.gd")
const World = preload("res://scripts/market/mk07_world.gd")
const MOSS = "苔团：都分到一件，还得是用得上的那一件。"
const LINES = [
	"扣扣：这批援助一共四件——绳、钉、布、铃，各一件。\n街上四位居民都还缺一样东西。",
	"帆匠：绳和布我都用得上。修桥人：绳、钉我也都行。",
	"乐手：我只有铃能用。医护：我只有布能用。",
	"扣扣：排好了就整批交一次。试交不扣货，方案留在街上，随时能改。",
]
var picked := -1

func configure() -> void:
	scene_id = "street"; level_id = "MK07"; title = "先别把东西平均分"
	# 实窗检查会在加入场景树前写入自己的 /tmp 路径，默认值只能填空。
	if save_path.is_empty(): save_path = "user://profiles/market-mk07-1/save-v1.json"
	durations = {"approach":1.6,"handover":3.2,"delivery":4.0}
	rules = Rules; world_script = World
	# 走近柜台才开始分配；整批交货仍留在柜台镜头内，交付才拉回整条街。
	zoom_stages = ["ready","puzzle","handover"]

func goal_line() -> String: return "把绳、钉、布、铃各分一件，让四位居民都拿到用得上的那一件"
func submit_label() -> String: return "整批试交"
func status_line() -> String:
	return "已分 %d/4 · 台面 %d 件"%[Rules.assigned(state),Rules.free_goods(state).size()]

func stage_labels() -> Dictionary:
	return {"arrival":"继续听他们说" if state.beat < Rules.BEATS - 1 else "走上前去",
		"ready":"开始分配","complete":"重新体验"}

func restart_prompt() -> Array: return ["重新体验这一幕？","留在街上","重新体验"]
func reset_prompt() -> Array:
	return ["把四位居民预定的货全部收回柜台？\n已经试交过的回执仍留在街上。","继续摆放","全部收回柜台"]

# 上一次试交没交齐、方案又还没改动时，台词位就是诚实的回执：说清缺谁、缺哪一件。
func has_report() -> bool:
	if state.stage != "puzzle" or state.failed.is_empty(): return false
	return state.failed[state.failed.size() - 1] == state.plan

func report_line() -> String:
	var lines = Rules.trial_report(state.plan)
	if lines.is_empty(): return MOSS
	var tail = "" if lines.size() < 2 else "（还有 %d 家）"%(lines.size() - 1)
	return MOSS + "\n" + lines[0] + tail

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "四位居民各守一个摊位，能用什么已经写在牌子上。"
		"ready": return "先点柜台上的一件货，再点一位居民；点已分出去的货就收回柜台。"
		"puzzle": return report_line() if has_report() else "四件货都在柜台上：照每家能用的排，排满四户再整批试交。"
		"handover": return "扣扣抱着四件货挨家递过去……"
		"delivery": return "帆匠接住绳，修桥人接住钉，乐手摇响铃，医护把布抱进怀里。"
		"complete": return "这一场的四件货，每家都拿到了一件用得上。下一场怎么分，还得再对着账看。"
	return ""

func build() -> void:
	world.picked = picked
	for good in range(Rules.COUNT):
		var holder := Rules.holder_of(state.plan, good)
		var tip = "%s：%s"%[Rules.GOODS[good],"已分给"+Rules.PERSONS[holder]+"，点一下收回柜台"
			if holder >= 0 else "点一下拿起来"]
		add_hotspot("good_%d"%good, world.good_rect(good), choose_good.bind(good), tip)
	for person in range(Rules.COUNT):
		var good: int = state.plan[person]
		var tip = "%s（%s）：%s"%[Rules.PERSONS[person], Rules.usable_text(person),
			"点一下收回柜台" if good >= 0 else ("点一下交给"+Rules.GOODS[picked] if picked >= 0 else "先点一件货")]
		add_hotspot("person_%d"%person, world.person_rect(person), choose_person.bind(person), tip)
	UIStyle.text(ui,"1-4 拿货 · Q W E R 交给对应居民 · Space 试交",Rect2(24,606,470,32),16)

# 完成后的分配单只复述玩家真正做过的事：四件各归一家，以及第一次试交落在哪。
# 纸面右缘停在 360：柜台最左那件货的木牌从 372 起，单据不能压住它说的那四件货。
func extra() -> void:
	if state.stage != "complete": return
	UIStyle.panel(ui,Rect2(24,446,336,212))
	var text = "分配单 · 千灯集市\n"
	for person in range(Rules.COUNT):
		text += "%s ← %s（%s）\n"%[Rules.PERSONS[person],Rules.GOODS[state.plan[person]],Rules.usable_text(person)]
	if state.failed.is_empty():
		text += "第一次试交就齐了。"
	else:
		var first: Array = state.failed[0]
		var entry: Array = Rules.unmet_of(first)[0]
		var holder := Rules.holder_of(first, entry[1])
		text += "第一次试交：%s给了%s\n"%[Rules.GOODS[entry[1]],Rules.PERSONS[holder]]
		text += "%s那时还没有能用的%s"%[Rules.PERSONS[entry[0]],Rules.GOODS[entry[1]]]
	# 抬头一行、四户各一行、首次试交两行：18 号汉字带上主题行距 5 是每行 30 像素，
	# 七行 210 会把末行推出纸面、压在街面的彩旗上。行距是 Label 的主题常量，
	# 只能 add_theme_constant_override 压回 0（与 MK06 的回执同法）：压完每行 27、七行 189。
	# 字号停在屋里的下限 18，纸面按 12 + 189 + 11 留边。
	var paper = UIStyle.text(ui,text,Rect2(40,458,304,189),16)
	paper.add_theme_constant_override("line_spacing",0)

func exit_buttons() -> void:
	# 从航图进来时宿主已经挂好返回按钮；单独启动本关时补一个同样的出口。
	if origin != "hub": add_button("open_hub","回千灯航图",Rect2(690,646,280,54),go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"plan": value.plan.duplicate(true)}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	next.plan = Rules.empty_plan()
	return next

func hint_texts() -> Array:
	return ["四位居民各要一件：乐手只能用铃，医护只能用布；帆匠和修桥人还能用别的。",
		"先把不可替代的两样定下来：铃给乐手、布给医护，剩下绳和钉才有得排。",
		"布已经归医护，帆匠用得上的就只剩绳；绳给帆匠，钉就给修桥人。"]

func choose_good(good: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if good < 0 or good >= Rules.COUNT: return
	var holder := Rules.holder_of(state.plan, good)
	if holder >= 0:
		# 已经预定出去的货：点一下就收回柜台，方案的其他部分不动。
		picked = -1
		place(Rules.take_back(state,holder))
		return
	picked = -1 if picked == good else good
	refresh()

func choose_person(person: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	if person < 0 or person >= Rules.COUNT: return
	if picked < 0:
		if state.plan[person] >= 0:
			place(Rules.take_back(state,person))
		else:
			message = "先在柜台上点一件货，再点这位居民。"
			refresh()
		return
	var next = Rules.give(state,person,picked)
	if next.is_empty():
		var holder := Rules.holder_of(state.plan,picked)
		message = "%s已经预定给%s了：先点它把它收回柜台。"%[Rules.GOODS[picked],Rules.PERSONS[holder]]
		refresh()
		return
	picked = -1
	place(next)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_4: choose_good(key - KEY_1)
	elif key == KEY_Q: choose_person(0)
	elif key == KEY_W: choose_person(1)
	elif key == KEY_E: choose_person(2)
	elif key == KEY_R: choose_person(3)
	else: return false
	return true

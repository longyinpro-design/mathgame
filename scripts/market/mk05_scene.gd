extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk05_rules.gd")
const World = preload("res://scripts/market/mk05_world.gd")
const LINES = [
	"扣扣：四只箱子都在，布、油、铃、纸还看得出，去处却被雨糊成了一片。",
	"小岚：别开箱，也别猜。四家的订单还钉在板上，只剩三句话读得清。",
	"扣扣：一张货签只对应一家……我念，你按？",
]
const KEYS = ["Q", "W", "E", "R"]

func configure() -> void:
	scene_id = "street"; level_id = "MK05"; title = "四张货签"
	# 试玩会在加入场景树之前先写入自己的 /tmp 路径，默认值永远让给它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk05-1/save-v1.json"
	durations = {"approach": 1.5, "delivery": 3.6}
	rules = Rules; world_script = World

func goal_line() -> String: return "四个去处各收一箱：照订单板上留下的三句话配对"
func status_line() -> String:
	return "板上 %d/4 · 手里：%s" % [Rules.placed_count(state),
		"空" if state.hand < 0 else Rules.GOODS_FULL[state.hand]]
func submit_label() -> String: return "验货交货"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < 2 else "走进灯芯街",
		"ready": "开始配对货签", "complete": "重新体验"}

func reset_prompt() -> Array:
	return ["把四张货签全部取回柜台？\n已经按好的格子会一起空出来。", "继续摆放", "全部取回"]
func restart_prompt() -> Array:
	return ["重新体验灯芯街这一幕？", "留在街上", "重新体验"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "雨停了。四张货签摊在柜台上，四家铺子各自还钉着一张订单。"
		"ready": return "小岚：先按读得清的那两句，剩下的两家自己就分出来了。"
		"puzzle": return "点货签拿在手里，再点一家铺子的订单按下；点已按好的格子取回。"
		"delivery": return "扣扣：箱子跟着货签走，一家一家送过去。"
		"complete": return "小岚：面包铺那一张也定了。灯串的订单，明天直接去领。"
	return ""

func build() -> void:
	for good in range(Rules.GOODS.size()):
		var worn = Rules.at(state, good)
		var note = "拿在手里，再点一家铺子按下；点自己也放回柜台"
		if state.hand != good:
			note = "点一下拿起来 [%d]" % (good + 1)
			if worn >= 0: note = "已按在%s，点那一格取回" % Rules.PLACE_CN[worn]
		var spot = add_hotspot("good_%d" % good, world.label_rect(good), choose_good.bind(good),
			"货签 · %s：%s" % [Rules.GOODS_FULL[good], note])
		spot.disabled = spot.disabled or worn >= 0
	for place in range(Rules.PLACES.size()):
		var held = state.assign[place]
		var kept = "空着，按上手里那张 [%s]" % KEYS[place]
		if held >= 0: kept = "%s · 点一下取回 [%s]" % [Rules.GOODS_FULL[held], KEYS[place]]
		add_hotspot("place_%d" % place, world.card_rect(place), choose_place.bind(place),
			"%s的订单：%s" % [Rules.PLACE_CN[place], kept])

# 完成后的回执按玩家实际按下的格子复述四对配对，并把面包铺那张交给下一关。
func extra() -> void:
	if state.stage != "complete": return
	var pairs = []
	for place in range(Rules.PLACES.size()):
		pairs.append("%s 收 %s" % [Rules.PLACE_CN[place], Rules.GOODS_FULL[state.assign[place]]])
	# 羊皮纸四边有 30~36 像素宽的装饰框：字要落在框内的净空里，最后一行才不压在框边上。
	# 五行 22 像素的字（一行 33、行距 5）要 173 像素，净空给到 182；纸面仍摊在空柜台上，不碰任何一张订单。
	UIStyle.panel(ui, Rect2(376, 388, 548, 244), true)
	UIStyle.text(ui, "验货回执 · 灯芯街\n" + pairs[0] + " · " + pairs[1] + "\n" + pairs[2] + " · " + pairs[3] +
		"\n一家一箱：四张货签都点对了。\n面包铺那张订单已确认，十根灯芯明天去领。",
		Rect2(412, 418, 476, 182), 18)

func exit_buttons() -> void:
	# 从航图进来的由宿主送回航图；直接启动或上一关递条子进来的，办完货签也给一条回航图的路。
	if origin != "hub": add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"assign": value.assign.duplicate(true), "hand": value.hand}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	next.assign = Rules.empty_assign(); next.hand = -1
	return next

func hint_texts() -> Array:
	# 台词牌的内框只有 74 像素高：22 像素的字两行 69 像素是上限，三行就掉出牌外。
	# 提示要一眼读完，所以每一档都写成一行。
	return ["一家只收一箱，一张货签只按一处：四张都要按满。",
		"布去育苗铺、纸去邮亭还读得清，先按这两张。",
		"面包铺留下的是「不收 铜铃」：铃去桥头，油去面包铺。"]

func choose_good(good: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.pick(state, good)
	if next.is_empty():
		var worn = Rules.at(state, good)
		message = "这一张现在取不到。"
		if worn >= 0: message = "这张已经按在%s：点那一格取回。" % Rules.PLACE_CN[worn]
		refresh(); return
	# 玩家一动手，上一句拒绝的话就该收回：不然板子摆对了，台词牌还写着「还有 4 家没按货签」。
	message = ""
	# 拿起与放回只是手感，不占撤销步数：撤销一次就退回上一次按下的格子。
	commit(next, history)

func choose_place(place: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.drop(state, place) if Rules.holding(state) else Rules.take(state, place)
	if next.is_empty():
		message = "手里还没有货签：先点柜台上的那一张。"
		refresh(); return
	message = ""
	place(next)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_4: choose_good(key - KEY_1)
	elif key == KEY_Q: choose_place(0)
	elif key == KEY_W: choose_place(1)
	elif key == KEY_E: choose_place(2)
	elif key == KEY_R: choose_place(3)
	else: return false
	return true

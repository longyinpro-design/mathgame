extends "res://scripts/market/level_host.gd"
const Rules = preload("res://scripts/market/mk06_rules.gd")
const World = preload("res://scripts/market/mk06_world.gd")
# 台词按行写死：一长串汉字会被 Godot 当成一个不可断的词画到框外，所以这里手动换行。
const LINES = [
	"小岚：雨里那四张货签对上了。\n面包铺收的那箱油已经送到，它的订单还留在柜上。",
	"面包铺伙计：灯会分给我们这一街十盏灯，\n灯芯要恰好 10 根，这次能用的筹票只有 19 张。",
	"面包铺伙计：三种封装都在摊上，包不拆卖、不退差价。\n你先凑单，我们不替你算。",
]

func configure() -> void:
	scene_id = "street"; level_id = "MK06"; title = "十根灯芯怎么凑"
	# 试玩会在入树前写入自己的 /tmp 落点，默认值永远不覆盖它。
	if save_path.is_empty(): save_path = "user://profiles/market-mk06-1/save-v1.json"
	durations = {"approach": 1.6, "purchasing": 2.8, "delivery": 3.6}
	# 走到摊前与购买时贴近柜台，挂灯的那一段再拉回整条街（宿主的 delivery 分支负责）。
	zoom_stages = ["puzzle", "purchasing"]
	rules = Rules; world_script = World

func goal_line() -> String: return "面包铺订单：恰好 10 根 · 手里只有 19 张筹票"
func status_line() -> String: return "订单 %d 根 · %d / %d 票" % [
	Rules.sticks_of(state.order), Rules.tickets_of(state.order), Rules.BUDGET]
func submit_label() -> String: return "一次付清这一单"

func stage_labels() -> Dictionary:
	return {"arrival": "继续听他们说" if state.beat < 2 else "走向灯芯摊", "ready": "开始配单", "complete": "重新体验"}

func restart_prompt() -> Array: return ["重新体验灯芯摊这一幕？", "留在灯芯摊", "重新体验"]
func reset_prompt() -> Array: return ["把订单上的整包放回摊位？\n筹票还在你手里。", "继续配单", "全部放回摊位"]

func line() -> String:
	match state.stage:
		"arrival": return LINES[state.beat]
		"approach": return "灯芯摊的三种封装摆在柜上，筹票匣压在你手边。"
		"ready": return "只能整包拿：4 根 7 票、3 根 6 票、单根 3 票。"
		"puzzle": return "点摊位拿一包上订单，点订单上的包放回摊位。凑够 10 根再一次付清。"
		"purchasing": return "伙计把整包灯芯抱向面包铺……这一单已经算进去了。"
		"delivery": return "面包铺把第一段灯串挂上檐口。灯一盏一盏亮起来。"
		"complete": return "小岚：这一街的灯芯凑齐了。\n等别的街也愿意一起备货，夜市就能重新开起来。"
	return ""

func build() -> void:
	for kind in range(Rules.KINDS):
		add_hotspot("take_%d" % kind, world.stall_rect(kind), do_take.bind(kind),
			"拿一整包 %d 根（%d 票）· 键盘 %d" % [Rules.STICKS[kind], Rules.PRICES[kind], kind + 1])
		for slot in range(state.order[kind]):
			add_hotspot("row_%d_%d" % [kind, slot], world.order_rect(kind, slot), do_return.bind(kind, slot),
				"放回第 %d 包 %d 根（%d 票）· 键盘 %s · 订单还没付款" % [slot + 1, Rules.STICKS[kind],
					Rules.PRICES[kind], "QWE"[kind]])

# 回执逐行写在这里，交给无头检查量宽度：Label 不会在汉字中间断行，超框就会画到面板外。
func receipt_lines() -> Array:
	var lines = ["面包铺 · 灯芯订单已付清"]
	for kind in range(Rules.KINDS):
		lines.append("%d 根一包 ×%d → %d 根 · %d 票" % [Rules.STICKS[kind], state.bought[kind],
			Rules.STICKS[kind] * state.bought[kind], Rules.PRICES[kind] * state.bought[kind]])
	lines.append("合计 %d 根 · 用去 %d 票" % [Rules.sticks_of(state.bought), Rules.tickets_of(state.bought)])
	lines.append("手里筹票 %d 张" % (Rules.BUDGET - Rules.tickets_of(state.bought)))
	# 末行原先还有一句「第一段暖灯已经挂上檐口」：檐口那块木牌与亮起来的五盏灯已经说了这件事，
	# 回执留 6 行才装得进这块收进 200 高的面板（18 号汉字行高 30，7 行正好顶到旧下沿）。
	return lines

# 面板收进 200 高：`complete` 一幕镜头已经拉回 1:1，旧的下沿 606 与街面「合计」木牌的上沿 606 齐平，
# 两块板看起来像同一块。上沿 396 不动（三摊的摊板底边在 387），只把下沿让到 596 留出一条缝。
func receipt_rect() -> Rect2: return Rect2(486, 396, 300, 200)
func receipt_text_rect() -> Rect2:
	var board = receipt_rect()
	return Rect2(board.position + Vector2(16,12), board.size - Vector2(30,20))

func extra() -> void:
	if state.stage != "complete": return
	# 回执按玩家真正买下的包复述一遍：包数、根数、票数都从 bought 读回。
	UIStyle.panel(ui, receipt_rect())
	var paper = UIStyle.text(ui, "\n".join(receipt_lines()), receipt_text_rect(), 16)
	# 18 号汉字的默认行距是 30 像素，七行就会把末行推出纸面、压到「合计」摊板上。
	# 行距是 Label 的主题常量，不是属性：只有 add_theme_constant_override 才压得住。
	paper.add_theme_constant_override("line_spacing", 0)

func exit_buttons() -> void:
	# 从航图进来时宿主已经给出「返回千灯航图」；直接启动本关样板时留一条回航图的路。
	if origin == "hub": return
	add_button("open_hub", "回千灯航图", Rect2(690, 646, 280, 54), go_hub)

func snapshot(value: Dictionary) -> Dictionary:
	return {"order": value.order.duplicate(), "bought": value.bought.duplicate()}

func cleared_state() -> Dictionary:
	var next = state.duplicate(true)
	next.order = Rules.empty_order()
	return next

func hint_texts() -> Array:
	return ["三种封装的价钱写在摊板上：4 根一包 7 票、3 根一包 6 票、单根 3 票。\n包不拆卖也不退差价，只能整包买。",
		"先只列「恰好 10 根」的整包摆法：4 根一包最多拿 2 包，\n剩下的根数只能由 3 根一包和单根补齐。",
		"两包 4 根再补两包单根正好 10 根，却要 20 票：\n单根那摊每根合 3 票最贵。局部便宜不等于整单可行，看的是包怎么配。"]

func do_take(kind: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.take_package(state, kind)
	if next.is_empty():
		message = "订单板上每类最多摆 %d 包：先放回一包，再拿新的。" % Rules.MAX_PER_KIND
		refresh(); return
	place(next)

func do_return(kind: int, slot: int) -> void:
	if state.stage != "puzzle" or modal or transient > 0: return
	var next = Rules.return_package(state, kind, slot)
	if next.is_empty():
		message = "那一包已经放回摊位了。"
		refresh(); return
	place(next)

func do_return_last(kind: int) -> void:
	if state.stage != "puzzle": return
	# 键盘上这一类本来就空着：按下 Q/W/E 不该听到「那一包已经放回摊位了」这种话。
	if state.order[kind] == 0:
		message = "%d 根那一类还没有包在订单上。" % Rules.STICKS[kind]
		refresh(); return
	do_return(kind, state.order[kind] - 1)

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_3: do_take(key - KEY_1)
	elif key == KEY_Q: do_return_last(0)
	elif key == KEY_W: do_return_last(1)
	elif key == KEY_E: do_return_last(2)
	else: return false
	return true

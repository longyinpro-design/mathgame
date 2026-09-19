extends "res://scripts/market/kit_world.gd"
# MK06 灯芯摊：三种整包摆在街面三座摊位的柜面上，订单板与筹票匣摆在前景柜台。
# 底景、封包、灯芯束、灯串、回执纸全部取自 kit-v1 拆件包；根数、票数与站位由引擎绘制，
# 坐标只来自 manifest 的 street 场景（counter / stall_left / stall_midleft / stall_middle /
# stall_midright / stall_right），不在关卡里另立第二套摊位位置。
const Rules = preload("res://scripts/market/mk06_rules.gd")
const BACKDROP = preload("res://assets/source/market/lantern-street-stage-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 三种封装分别落在 manifest `street` 的三座摊位站位上；面包铺在 stall_left，摊主的票匣在 stall_right。
const STALLS = ["stall_midleft", "stall_middle", "stall_midright"]
# [封包拆件, 封包显示宽, 灯芯束显示宽, 灯芯束抬高]
const STALL_ART = [["parcel_large", 78.0, 46.0, 44.0], ["parcel_medium", 68.0, 40.0, 28.0], ["", 0.0, 34.0, 0.0]]
const ROW_ART = [["parcel_large", 54.0, 30.0, 30.0], ["parcel_medium", 48.0, 26.0, 20.0], ["", 0.0, 26.0, 0.0]]
# 灯串拆件上五盏灯的玻璃中心（裁剪图像素），按 manifest 的 attachment 公式换算到世界坐标。
const LANTERN_GLASS = [Vector2(47, 124), Vector2(136, 163), Vector2(225, 173), Vector2(316, 163), Vector2(402, 125)]
const STRING_WIDTH = 240.0
const TICKET_WIDTH = 24.0
const PAID_SLIP_WIDTH = 92.0
const ROW_PITCH = 50.0
const ROW_FROM = 516.0
# 底景只有一条木板台面：从 counter 站位上方 83 像素到下方 14 像素（458..555）。
# 三行订单与筹票匣都必须落在这条带子里，再往下就是柜台的暗色台裙，货会看起来从桌上掉出去。
const BOARD_BACK = 458.0
const BOARD_FRONT = 555.0
const ROW_DEPTH = 49.0

var _tickets: Array = []

func ready_level() -> void:
	scene_id = "street"
	backdrop = BACKDROP

# 只有刚拿上订单板的那一包需要落下动画；放回是退回摊位，不留下落点。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	if not previous.has("order") or not state.has("order"): return
	for kind in range(Rules.KINDS):
		if state.order[kind] > previous.order[kind]:
			land_place = "row"; land_slot = kind * 100 + state.order[kind] - 1

# ---- geometry: everything hangs off the manifest stations ----
func stall_foot(kind: int) -> Vector2: return station(STALLS[kind]) + Vector2(0, 6)
func stall_rect(kind: int) -> Rect2: return target(stall_foot(kind) - Vector2(0, 26), 96, 72)
func order_foot(kind: int, slot: int) -> Vector2:
	return Vector2(ROW_FROM + slot * ROW_PITCH, BOARD_FRONT - 1.0 - float(Rules.KINDS - 1 - kind) * ROW_DEPTH)
func order_rect(kind: int, slot: int) -> Rect2: return target(order_foot(kind, slot) - Vector2(0, 6), 48, 42)
func label_rect(kind: int) -> Rect2: return Rect2(288, order_foot(kind, 0).y - 22, 190, 26)
func bakery_foot(index: int) -> Vector2: return station("stall_left") + Vector2(-56 + index * 56, 2)
func string_foot() -> Vector2: return station("stall_left") + Vector2(0, -104)
func paid_foot() -> Vector2: return station("stall_right") + Vector2(0, -22)
func counter_at(dx: float, dy: float) -> Vector2: return station("counter") + Vector2(dx, dy)
# 付清的那张单据摊在摊主的柜台上，正好在收讫那一叠的下面：票匣的位置留给票，不压任何摊板。
func paid_slip_foot() -> Vector2: return counter_at(425, 44)

func ticket_spots() -> Array:
	# 19 张票排成 3 行（7+7+5），24 宽的票实际高 32 像素，所以行距压在票高之内，
	# 整匣才摊得进那条木板台面（456..553），最后一排的纸边不会翻到柜台暗色的台裙上。
	if _tickets.is_empty(): _tickets = grid(counter_at(188, 11), Vector2(27, -32), 7, Rules.BUDGET)
	return _tickets

func ticket_spot(index: int) -> Vector2: return ticket_spots()[index]

# manifest 的 attachment 公式：世界落点 = 脚点 + (附件像素 - anchor_px) × scale，缩放只乘一次。
func kit_point(id: String, foot: Vector2, width: float, px: Vector2) -> Vector2:
	var item: Dictionary = parts[id]
	return foot + (px - Vector2(item.anchor_px[0], item.anchor_px[1])) * (width / atlases[id].get_width())

# ---- derived reading of the order sheet ----
# 交付过半：整批货已经离架，订单板上不再画这些包（它们此刻正落在面包铺的柜面上）。
func shown_order() -> Array:
	if state.stage == "purchasing" and progress < 0.5: return state.order
	if state.stage in ["purchasing", "delivery", "complete"]: return Rules.empty_order()
	return state.order

func tickets_left() -> int:
	match state.stage:
		"purchasing": return Rules.BUDGET - ticket_plan(progress).size()
		"delivery", "complete": return 0
	return Rules.BUDGET

func paid_tickets() -> int:
	return Rules.tickets_of(state.bought) if state.stage in ["purchasing", "delivery", "complete"] else 0

# 一次购买的全部灯芯包：整批离开订单板，落向面包铺的柜面。
func carry_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "purchasing" or not state.has("order"): return plan
	var phase = clampf(p / 0.5, 0, 1)
	var index = 0
	for kind in range(Rules.KINDS):
		for slot in range(state.order[kind]):
			var home = order_foot(kind, slot)
			plan.append({"kind": kind, "home": home, "at": home.lerp(bakery_foot(index), phase)
				- Vector2(0, sin(phase * PI) * 46.0), "phase": phase})
			index += 1
	return plan

# 付出去的筹票：货落地后整批飞向摊主的票匣，最后一段淡出，表示已经收讫。
func ticket_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "purchasing" or not state.has("order"): return plan
	var phase = clampf((p - 0.5) / 0.5, 0, 1)
	if phase <= 0.0: return plan
	var spots = ticket_spots()
	for step in range(int(ceil(Rules.tickets_of(state.order) * phase))):
		var home: Vector2 = spots[Rules.BUDGET - 1 - step]
		var to = paid_foot() + Vector2(-14 + (step % 5) * 7, -4 * (step % 4))
		plan.append({"home": home, "at": home.lerp(to, phase), "phase": phase})
	return plan

# ---- drawing ----
# 每种封装 = 一只封包 + 一束灯芯；散装只画灯芯。根数与票数永远写在摊板上，画面不靠猜。
func pack(foot: Vector2, kind: int, art: Array, alpha: float = 1.0) -> void:
	var spec: Array = art[kind]
	if spec[0] != "":
		kit("wick_bundle", foot - Vector2(0, spec[3]), spec[2], alpha)
		kit(spec[0], foot, spec[1], alpha)
	else:
		kit("wick_bundle", foot, spec[2], alpha)

func pack_width(kind: int, art: Array) -> float:
	var spec: Array = art[kind]
	return spec[1] if spec[0] != "" else spec[2]

func draw_stalls() -> void:
	for kind in range(Rules.KINDS):
		var foot = stall_foot(kind)
		contact(foot, pack_width(kind, STALL_ART) * 0.52, 0.24)
		pack(foot, kind, STALL_ART)
		# 摊位可拿：只点亮「这里摆着一整包」，不判断这一单是否付得起。
		if state.stage == "puzzle": socket(foot - Vector2(0, 10), Vector2(34, 13), 0.28 + 0.20 * pulse())

func draw_board(hidden: Array) -> void:
	var rows = shown_order()
	for kind in range(Rules.KINDS):
		for slot in range(rows[kind]):
			var foot = order_foot(kind, slot)
			if foot in hidden: continue
			var drop = landing("row", kind * 100 + slot)
			contact(foot, pack_width(kind, ROW_ART) * 0.52, 0.24 * (1.0 - drop))
			pack(foot - Vector2(0, 40 * drop), kind, ROW_ART, 1.0 - drop * 0.7)
		# 下一个空位闪一下：这是落点提示，不是对错判断，所以贴着货的落脚点亮。
		if state.stage == "puzzle" and rows[kind] < Rules.MAX_PER_KIND:
			socket(order_foot(kind, rows[kind]) - Vector2(0, 3), Vector2(22, 9), 0.32 + 0.26 * pulse())

func draw_tickets() -> void:
	var spots = ticket_spots()
	for index in range(tickets_left()):
		kit("receipt_blank", spots[index], TICKET_WIDTH)
	if state.stage in ["delivery", "complete"]:
		# 摊主收讫的那一叠：张数由玩家实际买下的包算出，不是写死的。
		var pile = paid_foot()
		for step in range(4):
			kit("receipt_blank", pile + Vector2(-10 + step * 7, -3 * step), 30, 0.9)

func draw_bakery() -> void:
	var foot = string_foot()
	match state.stage:
		"delivery":
			var rise = smoothstep(0.0, 0.45, progress)
			var hung = foot + Vector2(0, (1.0 - rise) * 46)
			kit("lantern_string", hung, STRING_WIDTH, 0.35 + 0.65 * rise)
			light_string(hung, smoothstep(0.4, 1.0, progress))
		"complete":
			kit("lantern_string", foot, STRING_WIDTH)
			light_string(foot, 1.0)
	if state.stage in ["delivery", "complete"]:
		var index = 0
		for kind in range(Rules.KINDS):
			for slot in range(state.bought[kind]):
				var at = bakery_foot(index)
				contact(at, pack_width(kind, ROW_ART) * 0.52, 0.24)
				pack(at, kind, ROW_ART)
				index += 1

# 暖灯：灯罩玻璃的位置由拆件自己的 anchor 换算，光晕是引擎另画的一层。
func light_string(foot: Vector2, strength: float) -> void:
	if strength <= 0.0: return
	for index in range(LANTERN_GLASS.size()):
		var one = clampf(strength * LANTERN_GLASS.size() - index * 0.7, 0, 1)
		if one <= 0.0: continue
		var at = kit_point("lantern_string", foot, STRING_WIDTH, LANTERN_GLASS[index])
		var beat = 0.86 + 0.14 * sin(clock * 3.2 + index * 1.7)
		draw_circle(at, 21.0 * one * beat, Color(1.0, 0.72, 0.30, 0.20 * one))
		draw_circle(at, 11.0 * one, Color(1.0, 0.80, 0.38, 0.52 * one))
		draw_circle(at, 5.5 * one, Color(1.0, 0.95, 0.78, 0.9 * one))
	draw_set_transform(station("stall_left") + Vector2(0, 62), 0, Vector2(1, 0.22))
	draw_circle(Vector2.ZERO, 132, Color(1.0, 0.66, 0.28, 0.10 * strength))
	draw_set_transform(Vector2.ZERO)

func draw_flight(carried: Array, tickets: Array) -> void:
	for entry in carried: pack(entry["at"], entry["kind"], ROW_ART)
	for entry in tickets:
		kit("receipt_blank", entry["at"], TICKET_WIDTH, 1.0 - clampf((entry["phase"] - 0.75) / 0.25, 0, 1))

func draw_figure() -> void:
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.5)
	# street 场景没有人物站位，扣扣落在前景柜台的右端（由 counter 站位推出，不另立坐标）。
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, counter_at(550, 58), 0.5)

# 摊板与订单牌集中在这里列出，画之前先被无头检查逐条量过宽度：
# 汉字在 Godot 里是一个不断词，plaque 又不会换行，超框就会画到牌子外面。
func signs() -> Array:
	var boards = []
	for kind in range(Rules.KINDS):
		var at = station(STALLS[kind])
		boards.append({"text": "%d 根 · %d 票" % [Rules.STICKS[kind], Rules.PRICES[kind]],
			"rect": Rect2(at.x - 75, at.y + 16, 150, 26)})
	if state.stage == "arrival": return boards
	# 两块抬头牌压在摊板与第一行订单牌之间：摊板底 387，第一行订单牌顶 434。
	boards.append({"text": "面包铺订单 · 10 根", "rect": Rect2(288, 396, 190, 28)})
	for kind in range(Rules.KINDS):
		boards.append({"text": "%d 根一包 ×%d" % [Rules.STICKS[kind], state.order[kind]], "rect": label_rect(kind)})
	boards.append({"text": "合计 %d 根 · %d 票" % [Rules.sticks_of(state.order), Rules.tickets_of(state.order)],
		"rect": Rect2(516, 606, 214, 28)})
	boards.append({"text": "包不拆卖 · 不退差价", "rect": Rect2(742, 606, 200, 28)})
	boards.append({"text": "筹票匣 · 剩 %d 张" % tickets_left(), "rect": Rect2(800, 396, 190, 28)})
	boards.append({"text": "面包铺 · 灯会第一段灯串", "rect": Rect2(104, 306, 244, 28)})
	if state.stage in ["delivery", "complete"]:
		boards.append({"text": "摊主收讫 %d 票" % paid_tickets(), "rect": Rect2(977, 340, 176, 26)})
	return boards

func draw_signs() -> void:
	for board in signs():
		plaque(board["text"], board["rect"])

func draw_level() -> void:
	if not state.has("order"): return
	var carried = carry_plan(progress)
	# 整批货离架的前半程，订单板上原来的位置由基类一并遮住，不会留下重影。
	var hidden = hide_while_moving(carried)
	draw_bakery()
	draw_stalls()
	draw_board(hidden)
	draw_tickets()
	draw_figure()
	draw_flight(carried, ticket_plan(progress))
	draw_signs()
	# 付清的单据压在柜面上，作为这一单已经发生的实物凭据。
	if state.stage == "complete": kit("receipt_blank", paid_slip_foot(), PAID_SLIP_WIDTH)

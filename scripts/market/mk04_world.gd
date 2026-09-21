extends "res://scripts/market/kit_world.gd"
# MK04 育苗铺柜面：两张盖了双方原章的约定钉在柜台上方，扣扣的转抄件单独摆在最左的核对板上。
# 底景、三种货物与回执全部来自 kit-v1 拆件包；章印、数量与约定文字由引擎绘制。
const Rules = preload("res://scripts/market/mk04_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/nursery-exchange-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const TRAY_WIDTH = 174.0
const CARD_WIDTH = 120.0
const CAND_WIDTH = 58.0
# 纸顶与纸高（空白回执 237×316、anchor 118.5/308）由 kit_world 的 PAPER_TOP/PAPER_TALL 统一给出。
const GOODS = {"cloth": ["cloth_bolt", 64], "oil": ["oil_bottle", 38], "bell": ["brass_bell", 42]}
const SEAL_RED = Color("b8412c")
const SEAL_BLUE = Color("2f6f86")

func ready_level() -> void:
	scene_id = "nursery"; backdrop = BACKDROP

# ---- 站位：三处柜台与扣扣全部读 manifest，其余按脚点偏移，托盘不压住单纸下沿 ----
func row(centre: Vector2, count: int, step: float) -> Array:
	var spots: Array = []
	for index in range(count):
		spots.append(centre + Vector2((index - (count - 1) / 2.0) * step, 6))
	return spots

func cloth_spots() -> Array: return row(station("counter_left"), Rules.CLOTH, 70.0)
func oil_spots() -> Array: return row(station("counter_middle"), Rules.OIL, 42.0)
func bell_spots() -> Array: return row(station("counter_right"), Rules.BELL_GROUPS, 46.0)

# 0 = 原约一（左柜台上方），1 = 原约二（右柜台上方），2 = 扣扣的转抄件（最左核对板）。
func card_foot(index: int) -> Vector2:
	match index:
		0: return station("counter_left") + Vector2(0, -103)
		1: return station("counter_right") + Vector2(0, -103)
		_: return station("counter_left") + Vector2(-255, -103)

# 三张候选签各 58 宽、纸高 77.3：间距必须比纸还高一点，选中那圈金框才不会被下一张切掉。
func cand_foot(index: int) -> Vector2:
	return station("counter_right") + Vector2(158, -199 + index * 84)

# 热点就是纸面本身：target() 给的是正方框，120 见方够不到 160 高的纸，
# 纸的上沿有 36 像素（候选签是 27 像素）点不着，玩家照着纸尖去点就落空。
func card_rect(index: int) -> Rect2: return paper_rect(card_foot(index), CARD_WIDTH)
func cand_rect(index: int) -> Rect2: return paper_rect(cand_foot(index), CAND_WIDTH)

# 只有刚落地的那一件需要弹跳：油是这一批换出来的，铃同理。退回的货不弹。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if state.stage != "puzzle": return
	if state.b > previous.b: land_place = "bell"; land_slot = Rules.bells_loose(state) - 1
	elif state.a > previous.a: land_place = "oil"; land_slot = Rules.oil_loose(state) - 1

# 演出过半才把结果画进台面与单子上，和 advance() 的入账时机严格对齐。
func shown_state() -> Dictionary:
	var shown = state.duplicate(true)
	if state.stage == "exchanging" and progress >= 0.5:
		if state.exchange[0] == 0: shown.a += state.exchange[1]
		else: shown.b += Rules.BELLS_PER_GROUP * state.exchange[1]
		shown.exchange = []
	if state.stage == "correcting" and progress >= 0.5:
		shown.correction = state.proposed
		shown.proposed = 0
	return shown

func goods_layout(placed: Dictionary) -> Dictionary:
	# 每件货物只有一个归属：柜面布堆、台面油瓶、右柜铜铃。
	var cloth = []
	for index in range(Rules.cloth_left(placed)): cloth.append(cloth_spots()[index])
	var oil = []
	for index in range(Rules.oil_loose(placed)): oil.append(oil_spots()[index])
	var bell = []
	for index in range(Rules.bells_loose(placed)): bell.append(bell_spots()[index])
	return {"cloth": cloth, "oil": oil, "bell": bell}

# 整批一起搬：被抬走的每一件脚点只在这里算一次，原位同时隐藏以免重影。
func carry_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage == "correcting":
		# 改签演出的是「候选数字」飞到第三张单子上，不是货物。
		# 三张候选签高低不同：先把它抬到柜面上方的同一高度再横过去，
		# 贴着台面走的话，最低那一张会从扣扣脸上抹过去。
		var home = cand_foot(Rules.CANDIDATES.find(state.proposed))
		var phase = clampf(p / 0.5, 0, 1)
		var at = home.lerp(card_foot(2) + Vector2(0, -30), phase)
		# 拱顶只能抬到 286：台词条那块板钉在屏上 98..184，这张 58 宽的纸有 75 高，
		# 再往上拱，纸的上半截就钻进板子后面，看着像数字被台词吃掉了半截。
		at.y = lerpf(at.y, 286.0, sin(phase * PI))
		plan.append({"what": "claim", "home": home, "at": at, "phase": phase})
		return plan
	if state.stage != "exchanging": return plan
	var rule: int = state.exchange[0]
	var spots = cloth_spots() if rule == 0 else oil_spots()
	var pool = Rules.cloth_left(state) if rule == 0 else Rules.oil_loose(state)
	var size = 1 if rule == 0 else Rules.OIL_PER_BELL
	var count: int = size * state.exchange[1]
	var homes: Array = []
	var centre := Vector2.ZERO
	for step in range(count):
		homes.append(spots[pool - 1 - step])
		centre += homes[step]
	centre /= count
	# 货物落到扣扣爪前、中间那只托盘的口上：脚点低于头顶，整段航迹都不会盖住他的脸。
	var hands = station("resident") + Vector2(-14, 20)
	var phase = clampf(p / 0.5, 0, 1)
	var lift = sin(phase * PI) * 34
	for step in range(count):
		# 整批作为一个整体离开原堆、飞向扣扣爪边，途中收紧到五分之四，
		# 共用同一个相位，玩家数过的间距就不会变成另一堆。
		var at: Vector2 = centre.lerp(hands, phase) + (homes[step] - centre) * lerpf(1.0, 0.8, phase) - Vector2(0, lift)
		plan.append({"what": "cloth" if rule == 0 else "oil", "home": homes[step], "at": at, "phase": phase})
	return plan

func draw_level() -> void:
	var placed = shown_state()
	var layout = goods_layout(placed)
	var carried = carry_plan(progress)
	var hidden = hide_while_moving(carried)
	draw_cards(placed)
	draw_candidates(placed, hidden)
	# 扣扣站在育苗铺的 resident 站位上，验收之后把铃送去衡伯那一侧。
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	var feet = station("resident")
	if state.stage == "delivery": feet += Vector2(lerpf(0, 96, smoothstep(0.4, 1, progress)), 0)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, feet, 0.5)
	for name in ["counter_left", "counter_middle", "counter_right"]: kit("receiving_tray", station(name), TRAY_WIDTH)
	draw_goods("cloth", cloth_spots(), layout.cloth, hidden)
	draw_goods("oil", oil_spots(), layout.oil, hidden)
	draw_bells(layout.bell, hidden)
	draw_carried(carried)
	draw_signs(placed)
	# 衡伯把那枚空货签递过来：新的约定可以当众重写。
	if (state.stage == "delivery" and progress > 0.72) or state.stage == "complete":
		var rise = 1.0 if state.stage == "complete" else smoothstep(0.72, 0.92, progress)
		kit("receipt_blank", Vector2(1146, 470 + 26 * (1 - rise)), 58, rise)

func draw_goods(kind: String, list: Array, spots: Array, hidden: Array) -> void:
	for foot in spots:
		if foot in hidden: continue
		var drop = landing(kind, list.find(foot))
		contact(foot, GOODS[kind][1] * 0.42, 0.26 * (1.0 - drop))
		kit(GOODS[kind][0], foot - Vector2(0, 34 * drop), GOODS[kind][1], 1.0 - drop * 0.7)

func draw_bells(spots: Array, hidden: Array) -> void:
	var list = bell_spots()
	for foot in spots:
		if foot in hidden: continue
		var drop = landing("bell", list.find(foot))
		var give = smoothstep(0.35, 0.92, progress) if state.stage == "delivery" else 0.0
		var at: Vector2 = foot.lerp(foot + Vector2(330, -34), give)
		contact(at, GOODS["bell"][1] * 0.42, 0.26 * (1.0 - drop) * (1.0 - give))
		kit("brass_bell", at - Vector2(0, 34 * drop), GOODS["bell"][1], (1.0 - drop * 0.7) * (1.0 - give * 0.85))

func draw_carried(carried: Array) -> void:
	for entry in carried:
		var fade = 1.0 - clampf((entry["phase"] - 0.7) / 0.3, 0, 1)
		if entry["what"] == "claim":
			var value: int = Rules.CANDIDATES[Rules.CANDIDATES.find(state.proposed)]
			kit("receipt_blank", entry["at"], CAND_WIDTH, fade)
			words("%d 只" % value, entry["at"] + Vector2(-16, -18), 13, INK_GOLD)
			continue
		var kind: Array = GOODS[entry["what"]]
		kit(kind[0], entry["at"], kind[1], fade)

# ---- 三张单：两张原约各盖两枚方章（双方都留原章），第三张只有扣扣自己的一枚圆章 ----
func draw_cards(placed: Dictionary) -> void:
	draw_card(card_foot(0), ["原约一", "1 卷布", "换 2 瓶油"], 2)
	draw_card(card_foot(1), ["原约二", "3 瓶油", "换 1 只铜铃"], 2)
	draw_card(card_foot(2), ["转抄件", "3 卷布", "换 %d 只铜铃" % Rules.bell_claim(placed)], 1)

func draw_card(foot: Vector2, lines: Array, marks: int) -> void:
	kit("receipt_blank", foot, CARD_WIDTH)
	var top = foot.y - CARD_WIDTH * PAPER_TOP
	var left = foot.x - CARD_WIDTH / 2.0
	words(lines[0], Vector2(left + 10, top + 24), 15, INK_GOLD)
	for index in range(1, lines.size()):
		words(lines[index], Vector2(left + 10, top + 52 + (index - 1) * 22), 15)
	var sealed = marks == 2
	words("双方有章" if sealed else "扣扣抄的", Vector2(left + 10, top + 100), 12,
		Color("ffe297") if sealed else Color("9fd6e0"))
	var base = Vector2(foot.x - 26, foot.y - 26)
	for mark in range(marks):
		stamp(base + Vector2(mark * 34, 0), SEAL_RED if sealed else SEAL_BLUE, not sealed)
	if sealed:
		draw_rect(Rect2(Vector2(left - 3, top - 3), Vector2(CARD_WIDTH + 6, CARD_WIDTH * PAPER_TALL + 6)), Color("ffe297", 0.75), false, 3.0)

func stamp(centre: Vector2, color: Color, round: bool) -> void:
	if round:
		draw_circle(centre, 10, Color(color, 0.9))
		draw_circle(centre, 4.5, Color(0.95, 0.92, 0.8, 0.95))
		return
	draw_rect(Rect2(centre - Vector2(10, 10), Vector2(20, 20)), Color(color, 0.9))
	draw_rect(Rect2(centre - Vector2(4.5, 4.5), Vector2(9, 9)), Color(0.95, 0.92, 0.8, 0.95))

# ---- 改签候选：3 卷布到底换几只铃，玩家从这三张里挑一张 ----
func draw_candidates(placed: Dictionary, hidden: Array) -> void:
	var open = placed.a == Rules.CLOTH
	var beat = pulse()
	for index in range(Rules.CANDIDATES.size()):
		var foot = cand_foot(index)
		if foot in hidden: continue
		var value: int = Rules.CANDIDATES[index]
		var chosen = placed.correction == value
		kit("receipt_blank", foot, CAND_WIDTH, 0.6 if not open else 1.0)
		var top = foot.y - CAND_WIDTH * PAPER_TOP
		# 11 号字压在牌夹那一横黄铜上，缩到 960×540 就成了一片糊色；让到夹子下沿、加到 13 号。
		words("3 卷布", Vector2(foot.x - 22, top + 28), 13, Color("c9bda3"))
		words("%d" % value, Vector2(foot.x - 12, foot.y - 26), 22, INK_GOLD if chosen else INK_LIGHT)
		words("只铃", Vector2(foot.x + 7, foot.y - 26), 12)
		if state.stage != "puzzle": continue
		if chosen:
			draw_rect(Rect2(foot + Vector2(-CAND_WIDTH / 2.0 - 3, -CAND_WIDTH * PAPER_TALL - 3),
				Vector2(CAND_WIDTH + 6, CAND_WIDTH * PAPER_TALL + 6)), Color("ffe297", 0.85), false, 3.0)
		elif open:
			socket(foot - Vector2(0, 26), Vector2(26, 12), 0.35 + 0.3 * beat)

func draw_signs(placed: Dictionary) -> void:
	for plate in sign_plates(placed):
		plaque(plate["text"], plate["rect"], plate["px"], plate["color"])

# 台面牌的矩形集中在这里：播放测试才能量「回执压住了哪块牌」，而不是靠肉眼翻截图。
func sign_plates(placed: Dictionary) -> Array:
	var plates: Array = [{"text": "原约二 · 3 油 → 1 铃", "rect": Rect2(756, 514, 250, 28), "px": 16, "color": INK_LIGHT}]
	if state.stage != "complete":
		# 回执逐行复述这两条原约，结账时再并排在柜面上只会被回执压住。
		plates.append({"text": "原约一 · 1 布 → 2 油", "rect": Rect2(300, 514, 250, 28), "px": 16, "color": INK_LIGHT})
		plates.append({"text": "扣扣的转抄件 · 待核对" if placed.correction == 0
			else "扣扣的转抄件 · 已订正 %d 只" % placed.correction,
			"rect": Rect2(66, 514, 236, 28), "px": 16, "color": INK_LIGHT})
	plates.append({"text": "实换 %d 只 · 单上 %d 只" % [Rules.bells_loose(placed), Rules.bell_claim(placed)],
		"rect": Rect2(516, 514, 232, 28), "px": 16,
		"color": INK_GOLD if Rules.bells_loose(placed) == Rules.bell_claim(placed) else INK_LIGHT})
	# 「改签 · 3 卷布换几只铃」这块牌原先钉在柜面上方 y 192：那是台词条那块板（屏上 98..184）
	# 的下沿，牌的上半截永远被吃掉。往哪儿挪都躲不开——候选签的纸尖就在它下面 6 像素，
	# 底下那一排四块牌也已经排满。这句话本来就有三处说：目标行、候选签的悬停说明、
	# 还有「实换几只 · 单上几只」那块对照牌，删掉不丢信息。
	if state.stage == "complete":
		plates.append({"text": "空货签 · 当众重写", "rect": Rect2(1024, 514, 200, 28), "px": 16, "color": INK_LIGHT})
	return plates

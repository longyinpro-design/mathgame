extends "res://scripts/market/kit_world.gd"
# MK05 灯芯街：四张货签摊在柜台上，四家铺子各自钉着一张被雨打湿的订单。
# 底景、四家铺子的站位与柜台全部引用 manifest 的 scenes[street].stations；
# 雨痕、糊开的墨迹与订单文字由引擎画在纸面与木牌上，不使用烘焙文本。
const Rules = preload("res://scripts/market/mk05_rules.gd")
const BACKDROP = preload("res://assets/source/market/lantern-street-stage-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 四个去处按街上从左到右排，与 Rules.PLACES 同序；stall_middle 留给订单板的牌头。
const STALLS = ["stall_left", "stall_midleft", "stall_midright", "stall_right"]
const TAG_WIDTH = 76.0
const CARD_WIDTH = 84.0
const PIN_WIDTH = 58.0
# 签面与订单上的货物显示宽度按各自纸面的高度配平，不越过纸边。
const GOOD_ON_TAG = [50.0, 36.0, 38.0, 46.0]
const GOOD_ON_CARD = [38.0, 28.0, 30.0, 34.0]
const TAG_LIFT = 50.0
const CARD_LIFT = 60.0
# 一家晚起步 0.12、各自抬得不一样高：四只箱子在街上排成一串，而不是叠成一团。
const START_GAP = 0.12
const WALK_TIME = 0.62
const LIFT = 26.0

func ready_level() -> void:
	scene_id = "street"; backdrop = BACKDROP

# 一处只落一张新签：只有刚按上的那一张需要落纸的弹跳。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	for place in range(Rules.PLACES.size()):
		if previous.assign[place] != state.assign[place] and state.assign[place] >= 0:
			land_place = "card"; land_slot = place

func counter() -> Vector2: return station("counter")
func stall(place: int) -> Vector2: return station(STALLS[place])

# 残句牌与店名牌的牌子位置：试玩按同样的矩形检查它们有没有被台词牌与按钮排压住。
# 中间两家（育苗铺、桥头）的订单钉得最高：残句牌原来钉在纸面上方 14 像素处，
# 镜头拉近之后上缘会被共用台词牌（下缘落在 184）切掉一截。往下让 14 像素，
# 牌子改成钉在纸面上缘，既离开台词牌，也像直接钉在订单上的样子。
func kept_rect(place: int) -> Rect2: return Rect2(stall(place).x - 64, stall(place).y - 132, 128, 28)
func name_rect(place: int) -> Rect2: return Rect2(stall(place).x - 90, stall(place).y + 8, 180, 28)

# 摊在柜台上的四张货签：脚点落在桌面，左右各留一指宽的空隙。
func label_spots() -> Array:
	return grid(counter() + Vector2(-144, 6), Vector2(96, 0), 4, 4)

func label_rect(good: int) -> Rect2: return target(label_spots()[good], 76, 84)
func card_rect(place: int) -> Rect2: return target(stall(place), 88, 96)

# 交货演出：四只箱子按去处依次离开柜台，一路抬到各自家门口。
# 每件货物有自己的起步时刻与抬升高度，到家的先后就是玩家按签的左右顺序。
func carry_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "delivery": return plan
	for place in range(Rules.PLACES.size()):
		var good: int = state.assign[place]
		if good < 0: continue
		var phase = clampf((p - START_GAP * place) / WALK_TIME, 0.0, 1.0)
		if phase <= 0.0: continue
		var home: Vector2 = label_spots()[good]
		var dest: Vector2 = stall(place) - Vector2(0, CARD_LIFT)
		var at: Vector2 = home.lerp(dest, smoothstep(0.0, 1.0, phase))
		plan.append({"good": good, "place": place, "home": home, "dest": dest,
			"at": at - Vector2(0, sin(phase * PI) * (LIFT + 6.0 * place)), "phase": phase})
	return plan

# 一件货在演出里有三段：还摊在柜台上、在路上、已经收进订单。
# 起飞之前不许画到订单上，落地之后不再画在柜台上，免得同一只箱子在街上出现两次。
# waiting = 这一家的箱子还没到货（到货的就从表里划掉），still = 这一只箱子还在柜台上等。
func in_flight(plan: Array) -> Dictionary:
	var flying = {}
	var waiting = {}
	var still = {}
	if state.stage == "delivery":
		for place in range(Rules.PLACES.size()): waiting[place] = true
		for entry in plan:
			if entry["phase"] >= 1.0: waiting.erase(entry["place"])
			else: flying[entry["good"]] = true
		for good in range(Rules.GOODS.size()):
			var worn = Rules.at(state, good)
			if worn >= 0 and waiting.has(worn) and not flying.has(good): still[good] = true
	return {"flying": flying, "waiting": waiting, "still": still}

func draw_rain() -> void:
	var amount = 0.0
	if state.stage == "arrival": amount = 1.0
	elif state.stage == "approach": amount = 1.0 - smoothstep(0.3, 1.0, progress)
	if amount <= 0.0: return
	for drop in range(46):
		var x = fmod(drop * 137.0 + clock * 26.0, 1340.0) - 30.0
		var y = fmod(drop * 271.0 + clock * 330.0, 830.0) - 60.0
		draw_line(Vector2(x, y), Vector2(x + 5.0, y + 22.0), Color(0.78, 0.86, 0.96, 0.3 * amount), 2)

# 被雨冲开的墨迹：纸面还在，字糊成一片，只有钉在木牌上的那半句读得清。
func draw_wash(foot: Vector2, half: float, rows: Array) -> void:
	for index in range(rows.size()):
		var lift: float = rows[index]
		var width = half * (0.82 if index % 2 == 0 else 0.6)
		var y = foot.y - lift
		draw_rect(Rect2(foot.x - width, y - 3.5, width * 2.0, 7.0), Color(0.24, 0.2, 0.16, 0.34))
		draw_line(Vector2(foot.x - width - 6.0, y + 4.0), Vector2(foot.x + width - 2.0, y + 6.0),
			Color(0.72, 0.82, 0.92, 0.26), 2)

func draw_tag(good: int, spot: Vector2, held: bool) -> void:
	var foot = spot + Vector2(0, -22.0 if held else 0.0)
	contact(spot, 24, 0.1 if held else 0.2)
	# 麻绳把签子挂在木夹上，拿起来的时候绳子跟着抬。
	draw_line(foot + Vector2(0, -96), foot + Vector2(6, -116), Color("8f6420", 0.85), 2)
	kit("receipt_blank", foot, TAG_WIDTH, 1.0 if held else 0.92)
	draw_wash(foot, 34.0, [42.0, 32.0])
	kit(Rules.KIT_GOODS[good], foot - Vector2(0, TAG_LIFT), GOOD_ON_TAG[good])
	words(Rules.GOODS_FULL[good], foot + Vector2(-16, -12), 16, INK_GOLD if held else INK_LIGHT)
	if held: socket(foot - Vector2(0, TAG_LIFT), Vector2(34, 32), 0.5 + 0.4 * pulse())

func draw_order(place: int, foot: Vector2, good: int, waiting: bool) -> void:
	contact(foot, 30, 0.22)
	kit("receipt_blank", foot, CARD_WIDTH, 0.9)
	draw_wash(foot, 38.0, [100.0, 20.0, 10.0])
	plaque(Rules.KEPT[place], kept_rect(place))
	# 货签一按上就钉在订单上，箱子却还在街上走：没到货的这一家只写店名。
	if good >= 0: kit("receipt_blank", foot - Vector2(0, 30), PIN_WIDTH, 0.98)
	if good < 0 or waiting:
		plaque(Rules.PLACE_CN[place], name_rect(place))
		# 空着的格子只在手里有签时闪，免得满街都是提示。
		if good < 0 and state.stage == "puzzle" and Rules.holding(state):
			socket(foot - Vector2(0, CARD_LIFT), Vector2(30, 28), 0.4 + 0.3 * pulse())
		return
	var rise = landing("card", place)
	kit(Rules.KIT_GOODS[good], foot - Vector2(0, CARD_LIFT + 30.0 * rise), GOOD_ON_CARD[good], 1.0 - rise * 0.7)
	plaque("%s · 收 %s" % [Rules.PLACE_CN[place], Rules.GOODS_FULL[good]], name_rect(place), 16, INK_GOLD)

func draw_level() -> void:
	var spots = label_spots()
	var carried = carry_plan(progress)
	var moved = in_flight(carried)
	# 扣扣站在柜台左手边念签，四张货签摊在桌面上。
	var feet = counter() + Vector2(-330, 44)
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.8)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, feet, 0.5)
	draw_rain()
	for place in range(Rules.PLACES.size()):
		draw_order(place, stall(place), state.assign[place], moved["waiting"].has(place))
	var middle = station("stall_middle")
	plaque("订单板 · 三句留下的话", Rect2(middle.x - 90, middle.y - 45, 180, 28))
	if state.stage == "delivery":
		# 货签都按上订单板了，柜台上只剩还没起飞的箱子。
		for good in range(Rules.GOODS.size()):
			if not moved["still"].has(good): continue
			contact(spots[good], 24, 0.2)
			kit(Rules.KIT_GOODS[good], spots[good], GOOD_ON_TAG[good])
	elif state.stage != "complete":
		plaque("柜台 · 四张货签", Rect2(counter().x - 90, counter().y + 12, 180, 28))
		for good in range(Rules.GOODS.size()):
			if state.assign.has(good): continue
			draw_tag(good, spots[good], state.hand == good)
	for entry in carried:
		if entry["phase"] < 1.0: kit(Rules.KIT_GOODS[entry["good"]], entry["at"], GOOD_ON_TAG[entry["good"]])

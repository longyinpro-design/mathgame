extends "res://scripts/market/kit_world.gd"
# MK02 育苗铺交换台：底景与货物全部来自 kit-v1 拆件包，数量与约定由引擎绘制。
const Rules = preload("res://scripts/market/mk02_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/nursery-exchange-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const TRAY_WIDTH = 174.0
const GOODS = {"fruit": ["copper_fruit", 34], "spool": ["rope_spool", 38], "wick": ["wick_bundle", 34]}
static var FRUIT_SPOTS := grid(Vector2(371, 492), Vector2(36, -34), 4, 8)
static var TABLE_SPOTS := grid(Vector2(591, 488), Vector2(36, -28), 4, 12)
const RACK_SPOTS = [Vector2(830, 496), Vector2(878, 496), Vector2(926, 496), Vector2(854, 444), Vector2(902, 444)]
const BENCH = [Vector2(1096, 492), Vector2(1160, 492)]
# 柜面前沿那一排木牌共用的底线：回执板压在 ui 层，谁盖住谁要看镜头，两边都从这一个数出发。
const PLAQUE_ROW_Y = 514.0

func ready_level() -> void:
	scene_id = "nursery"; backdrop = BACKDROP

# A good only changes hands one at a time, so the newest arrival is the single place
# that needs the drop-in animation. Taking it back simply returns it to the shared stack.
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	for slot in range(Rules.RACK_SLOTS):
		if previous.rack[slot] != state.rack[slot] and state.rack[slot] == 1: land_place = "rack"; land_slot = slot
	for slot in range(Rules.HOOK_SLOTS):
		if previous.hook[slot] != state.hook[slot] and state.hook[slot] == 1: land_place = "hook"; land_slot = slot

func rack_rect(slot: int) -> Rect2: return target(RACK_SPOTS[slot], 52, 46)
func hook_rect(slot: int) -> Rect2: return target(BENCH[slot], 52, 48)

# The pending exchange lands at the half-way mark, so the flying goods and the
# counts on the plaques always describe the same moment.
func shown_state() -> Dictionary:
	var shown = state.duplicate(true)
	if state.stage == "exchanging" and progress >= 0.5:
		if state.exchange[0] == 0: shown.a += state.exchange[1]
		else: shown.b += state.exchange[1]
		shown.exchange = []
	return shown

func goods_layout(placed: Dictionary) -> Dictionary:
	# Every good has exactly one owner: basket, table, rack or bench.
	var spools = Rules.spools_loose(placed)
	var wicks = Rules.wicks_loose(placed)
	var fruits = []
	for index in range(Rules.fruits_left(placed)): fruits.append(FRUIT_SPOTS[index])
	var table = []
	for index in range(spools): table.append([TABLE_SPOTS[index], "spool"])
	for index in range(wicks): table.append([TABLE_SPOTS[spools + index], "wick"])
	var rack = []
	for slot in range(Rules.RACK_SLOTS):
		if placed.rack[slot] == 1: rack.append([RACK_SPOTS[slot], slot])
	var hook = []
	for slot in range(Rules.HOOK_SLOTS):
		if placed.hook[slot] == 1: hook.append([BENCH[slot], slot])
	return {"fruit": fruits, "table": table, "rack": rack, "hook": hook}

func carry_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "exchanging": return plan
	var rule: int = state.exchange[0]
	var spots = FRUIT_SPOTS if rule == 0 else TABLE_SPOTS
	var pool = Rules.fruits_left(state) if rule == 0 else Rules.spools_loose(state)
	var count: int = Rules.GROUP * state.exchange[1]
	var homes: Array = []
	var centre := Vector2.ZERO
	for step in range(count):
		homes.append(spots[pool - 1 - step])
		centre += homes[step]
	centre /= count
	var hands = station("resident") + Vector2(0, -40)
	var phase = clampf(p / 0.5, 0, 1)
	var lift = sin(phase * PI) * 34
	for step in range(count):
		# The group travels as one cluster that tightens a fifth on the way. Sharing the phase
		# keeps the spacing the player counted in the stack, so six pieces stay six sprites.
		var at: Vector2 = centre.lerp(hands, phase) + (homes[step] - centre) * lerpf(1.0, 0.8, phase) - Vector2(0, lift)
		plan.append({"what": "fruit" if rule == 0 else "spool", "home": homes[step], "at": at, "phase": phase})
	return plan

# The group being carried starts on top of its own stack, so those foot positions
# are read straight from the plan and reused to hide them.
func in_flight_homes() -> Array:
	var homes: Array = []
	for entry in carry_plan(progress): homes.append(entry["home"])
	return homes

# 交货那一段的三条量出曲线：扣扣抱着线卷走到台前（walk）、线卷离钩落到她爪边（hand_off）、
# 灯芯离架被码头接走（shipped）。complete 一律取 1.0：动画最后一帧已经把货交出去了，
# 下一帧不该整批摆回原处——原先正是这样，五捆灯芯凭空回到刚清空的托盘，两卷线也回了挂钩。
func walk_off() -> float:
	return smoothstep(0.45, 1, progress) if state.stage == "delivery" else (1.0 if state.stage == "complete" else 0.0)

func hand_off() -> float:
	return smoothstep(0.5, 0.95, progress) if state.stage == "delivery" else (1.0 if state.stage == "complete" else 0.0)

func shipped() -> float:
	return smoothstep(0.05, 0.55, progress) if state.stage == "delivery" else (1.0 if state.stage == "complete" else 0.0)

func draw_level() -> void:
	# 扣扣 stands at the nursery's resident station; goods in front of it belong to the table.
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	var feet = station("resident") + Vector2(lerpf(0, 34, walk_off()), 0)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, feet, 0.5)
	var placed = shown_state()
	var layout = goods_layout(placed)
	var carried = carry_plan(progress)
	var hidden = hide_while_moving(carried)
	for name in ["counter_left","counter_middle","counter_right"]: kit("receiving_tray", station(name), TRAY_WIDTH)
	for foot in layout.fruit:
		if foot in hidden: continue
		contact(foot, GOODS["fruit"][1] * 0.42, 0.2)
		kit("copper_fruit", foot, GOODS["fruit"][1])
	# Empty drop targets pulse only while there is something that may go there.
	var beat = pulse()
	if state.stage == "puzzle":
		if Rules.wicks_loose(state) > 0:
			for slot in range(Rules.RACK_SLOTS):
				if state.rack[slot] == 0: socket(RACK_SPOTS[slot] - Vector2(0, 14), Vector2(24, 10), 0.4 + 0.3 * beat)
		if Rules.spools_loose(state) > 0:
			for slot in range(Rules.HOOK_SLOTS):
				if state.hook[slot] == 0: socket(BENCH[slot] - Vector2(0, 12), Vector2(24, 10), 0.4 + 0.3 * beat)
	for entry in layout.hook:
		var rise = landing("hook", entry[1])
		# 扣扣's two spools leave the bench only once the order is being handed over.
		var give = hand_off()
		var hook_foot: Vector2 = entry[0].lerp(feet + Vector2(-48 + entry[1] * 52, -8), give)
		contact(hook_foot, GOODS["spool"][1] * 0.42, 0.26 * (1.0 - rise) * (1.0 - give))
		kit("rope_spool", hook_foot - Vector2(0, 38 * rise), GOODS["spool"][1], 1.0 - rise * 0.75)
	for entry in layout.rack:
		var foot: Vector2 = entry[0]
		var drop = landing("rack", entry[1])
		var drift = shipped()
		contact(foot, GOODS["wick"][1] * 0.42, 0.26 * (1.0 - drift) * (1.0 - drop))
		kit("wick_bundle", foot + Vector2(drift * 300, -drift * drift * 120 - 38 * drop), GOODS["wick"][1],
			(1.0 - drift) * (1.0 - drop * 0.75))
	for entry in layout.table:
		var foot: Vector2 = entry[0]
		if foot in hidden: continue
		var kind: Array = GOODS[entry[1]]
		var drop = 0.0
		if state.stage == "exchanging" and progress >= 0.5: drop = -46.0 * (1.0 - smoothstep(0.5, 0.85, progress))
		contact(foot, kind[1] * 0.42)
		kit(kind[0], foot, kind[1], 1.0, drop)
	# The exchange itself: the consumed group walks from its home stack to 扣扣's paws.
	if state.stage == "exchanging":
		for entry in carried:
			var kind: Array = GOODS[entry["what"]]
			kit(kind[0], entry["at"], kind[1], 1.0 - clampf((entry["phase"] - 0.7) / 0.3, 0, 1))
	draw_signs(placed)
	# The completed order is read back from the goods themselves; the wording lives on the paper.
	if state.stage == "complete": kit("receipt_blank", Vector2(150, 496), 84)

func draw_signs(placed: Dictionary) -> void:
	plaque("约定一 · 2 铜果 → 3 线卷", Rect2(330, PLAQUE_ROW_Y, 192, 28))
	plaque("约定二 · 2 线卷 → 1 灯芯", Rect2(550, PLAQUE_ROW_Y, 192, 28))
	plaque("码头交付架 · %d / %d 根灯芯" % [placed.rack.count(1), Rules.WICK_ORDER], Rect2(776, PLAQUE_ROW_Y, 206, 28),
		16, INK_GOLD if placed.rack.count(1) == Rules.WICK_ORDER else INK_LIGHT)
	plaque("扣扣的修补台 · %d / %d 卷线" % [placed.hook.count(1), Rules.SPOOL_ORDER], Rect2(1004, PLAQUE_ROW_Y, 206, 28),
		16, INK_GOLD if placed.hook.count(1) == Rules.SPOOL_ORDER else INK_LIGHT)

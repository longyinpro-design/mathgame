extends "res://scripts/market/kit_world.gd"
# MK17 铜鹭巡守 · 三次验货：大码头的首领舞台。
# 底景、封包、托盘、纸卷、灯与船全部取自 kit-v1 拆件包；站位只读 manifest 的 dock 场景
# （packing = 封装台、boss_foot = 铜鹭脚点、boat_red/boat_blue = 两条运输船、lantern = 领航灯）。
# 三个栈位由两条船自身的间距等距外推（船距即栈距），关卡里不再另立第二套摊位坐标。
# 铜鹭三态：patrol（巡守）→ flag（举检查旗与托盘）→ platform（展翼成搬运台），全部是 feet-anchored 原图。
# 布局只有一个原点：封装台整列挂在 packing 上，托盘与检查旗挂在 boss_foot 上，
# 缩放镜头（puzzle/flag/lift）下 screen = world*1.1-(64,43)，下面每个可点框都按这条换算留在画面内。
const Rules = preload("res://scripts/market/mk17_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/grand-dock-clean-v1.png")
const HERON_PATROL = preload("res://assets/runtime/market/characters/heron-v1/brass-heron-patrol.png")
const HERON_FLAG = preload("res://assets/runtime/market/characters/heron-v1/brass-heron-flag.png")
const HERON_PLATFORM = preload("res://assets/runtime/market/characters/heron-v1/brass-heron-platform.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const INK_WARN = Color("ffbe9e")
const INK_DIM = Color("9c8f78")
const INK_FLAG_A = Color("9fe3c6")
const INK_FLAG_B = Color("ffb46a")
const PACK_ART = ["parcel_large", "parcel_medium", "parcel_small"]
const BOAT_ART = ["transport_boat_red", "transport_boat_blue"]
const BOAT_STATIONS = ["boat_red", "boat_blue"]
const BOAT_WIDTH = 90.0
const LANTERN_WIDTH = 100.0
const CARD_WIDTH = 112.0
const HERON_SCALE = 0.62
const KOUKOU_SCALE = 0.42
# ---- 封装台：整列原点 = manifest 的 packing 脚点 + BENCH_SHIFT ----
# 台头木牌 → 三次机会纸卷 → 四条走法 → 三行封包，自上而下排成一列，全部落在画面左栏。
const BENCH_SHIFT = Vector2(-136, -281)
const BENCH_WIDTH = 248.0
const BENCH_PITCH = 52.0
const BENCH_HEIGHT = 48.0
const HEADER_LIFT = 78.0
const CHIP_SHIFT = Vector2(130, -8)
const CHIP_STEP = 36.0
const CHIP_WIDTH = 34.0
const STOCK_TOP = 208.0
const STOCK_PITCH = 54.0
const STOCK_HEIGHT = 52.0
const STOCK_LIFT = 46.0
const STOCK_FIRST = 12.0
const STOCK_STEP = 24.0
const PACK_WIDTH = [26.0, 24.0, 22.0]
# 收货处与搬运台货床上的包按原尺寸摆，只有封台上的样本缩小一档。
const BERTH_PACK_WIDTH = [30.0, 28.0, 24.0]
# ---- 验货托盘：原点 = boss_foot + TRAY_SHIFT，两行三列最多摆 6 包 ----
const TRAY_SHIFT = Vector2(-320, -83)
const TRAY_WIDTH = 262.0
const TRAY_FIRST = Vector2(-58, -68)
const TRAY_PITCH = Vector2(58, 56)
const TRAY_COLUMNS = 3
const TRAY_PACK_WIDTH = [40.0, 36.0, 32.0]
const TRAY_TARGET = 52.0
const TRAY_LIFT = 30.0
const TRAY_PLAQUE = Vector2(-112, 10)
const TRAY_PLAQUE_SIZE = Vector2(224, 26)
# ---- 检查旗：旗杆脚点 = boss_foot + FLAG_SHIFT，站在第三根栈位牌右边一格 ----
const FLAG_SHIFT = Vector2(160, -166)
const FLAG_POLE = 157.0
const FLAG_WIDTH = 104.0
const FLAG_PLAQUE = Vector2(8, 10)
const FLAG_PLAQUE_WIDTH = 210.0
# ---- 栈位：船距即栈距，脚点往下 BERTH_DROP 就是收货的木台 ----
const BERTH_DROP = 124.0
const BERTH_PACK_SHIFT = Vector2(-45, 16)
const BERTH_PACK_STEP = Vector2(30, 24)
# 三站的货落在搬运台左翼的货床上：脚点相对 boss_foot，逐格沿甲板前沿那条透视线下沉，
# 一眼看得出是铜鹭驮走的。画在铜鹭之后（draw_bed），否则整片羽翅会把这三包压得一颗不见。
const BED_FIRST = Vector2(-147, -113)
const BED_STEP = Vector2(40, 6)
const DROP_LIFT = 30.0
# 交货演出：货从托盘飞到栈位牌前，0.14 起步、0.62 落位。
const FLY_START = 0.14
const FLY_TRAVEL = 0.48

func ready_level() -> void:
	scene_id = "dock"; backdrop = BACKDROP

# 刚放上托盘的那一包才需要落下动画：宿主已先把提交后的状态交给世界，这里才比得出差在哪。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if state.stage != "puzzle" or previous.stage != "puzzle": return
	if not previous.has("tray") or not state.has("tray"): return
	for kind in range(Rules.KINDS):
		if state.tray[kind] == previous.tray[kind]: continue
		if state.tray[kind] > previous.tray[kind]:
			land_place = "tray"; land_slot = first_tray_slot(kind) + state.tray[kind] - 1
		else:
			land_place = "stock"; land_slot = kind
		return

func first_tray_slot(kind: int) -> int:
	var order = Rules.tray_kinds(state)
	return maxi(0, order.find(kind))

# ---- 站位：全部由 manifest 推出来 ----
func table_foot() -> Vector2: return station("packing")
func boss_foot() -> Vector2: return station("boss_foot")
func heron_foot() -> Vector2: return boss_foot()

# 三个栈位 = 两条船的等距外推：船距就是栈距，第三处正落在码头第三根木桩上。
func berth_step() -> Vector2: return station(BOAT_STATIONS[1]) - station(BOAT_STATIONS[0])
func berth_foot(index: int) -> Vector2:
	return station(BOAT_STATIONS[0]) + berth_step() * index + Vector2(0, BERTH_DROP)
func berth_rect(index: int) -> Rect2:
	return Rect2(berth_foot(index) + Vector2(-CARD_WIDTH / 2.0, -CARD_WIDTH * 1.31),
		Vector2(CARD_WIDTH, CARD_WIDTH * 1.31))

func bench_origin() -> Vector2: return table_foot() + BENCH_SHIFT
func header_rect() -> Rect2:
	return Rect2(bench_origin() + Vector2(0, -HEADER_LIFT), Vector2(BENCH_WIDTH, 26))
func chip_foot(index: int) -> Vector2:
	return bench_origin() + CHIP_SHIFT + Vector2(CHIP_STEP * index, 0)
func bench_rect(index: int) -> Rect2:
	return Rect2(bench_origin() + Vector2(0, BENCH_PITCH * index), Vector2(BENCH_WIDTH, BENCH_HEIGHT))
func stock_row_rect(kind: int) -> Rect2:
	return Rect2(bench_origin() + Vector2(0, STOCK_TOP + STOCK_PITCH * kind), Vector2(BENCH_WIDTH, STOCK_HEIGHT))
func stock_foot(kind: int, slot: int) -> Vector2:
	return stock_row_rect(kind).position + Vector2(STOCK_FIRST + STOCK_STEP * slot, STOCK_LIFT)

func tray_foot() -> Vector2: return boss_foot() + TRAY_SHIFT
func tray_slot_origin() -> Vector2: return tray_foot() + TRAY_FIRST
func tray_spot(slot: int) -> Vector2:
	return tray_slot_origin() + Vector2(TRAY_PITCH.x * (slot % TRAY_COLUMNS), TRAY_PITCH.y * int(slot / TRAY_COLUMNS))
func tray_rect(slot: int) -> Rect2: return target(tray_spot(slot), TRAY_TARGET, TRAY_LIFT)
func tray_plaque_rect() -> Rect2: return Rect2(tray_foot() + TRAY_PLAQUE, TRAY_PLAQUE_SIZE)

func flag_foot() -> Vector2: return boss_foot() + FLAG_SHIFT
func flag_rect() -> Rect2:
	return Rect2(flag_foot() + Vector2(-28, -160), Vector2(152, 168))
func flag_plaque_rect() -> Rect2:
	return Rect2(flag_foot() + FLAG_PLAQUE, Vector2(FLAG_PLAQUE_WIDTH, 26))

# ---- 状态读取 ----
func active_station() -> int: return state.station - 1
func bench_visible() -> bool: return state.stage in ["ready", "puzzle", "flag", "lift"]
func flying() -> bool: return state.stage in ["flag", "lift", "carrying"]
func heron_pose() -> int:
	if state.stage in ["carrying", "delivery", "complete"]: return 2
	if state.shown == 1 or state.stage in ["flag", "lift"]: return 1
	return 0

# ---- 飞行演出：刚交出去的那一站，货从托盘飞到栈位牌（三站飞到搬运台的货床） ----
func fly_plan(p: float) -> Array:
	var plan: Array = []
	var index = active_station() - 1
	if index < 0 or index >= Rules.KINDS: return plan
	var row: Array = state.delivered[index]
	var spots = grid(tray_spot(0), TRAY_PITCH, TRAY_COLUMNS, Rules.packs_of(row))
	var slot = 0
	for kind in range(Rules.KINDS):
		for step in range(row[kind]):
			var home: Vector2 = spots[slot]
			var glide = smoothstep(0, 1, clampf((p - FLY_START) / FLY_TRAVEL, 0, 1))
			plan.append({"kind": kind, "at": home.lerp(pack_home(index, slot), glide) - Vector2(0, sin(glide * PI) * 40),
				"phase": glide, "slot": slot})
			slot += 1
	return plan

# 已收下的那一包平时钉在哪里：一、二站在栈位牌前，三站在铜鹭左翼的货床上。
func pack_home(index: int, slot: int) -> Vector2:
	if index == Rules.KINDS - 1:
		return boss_foot() + BED_FIRST + BED_STEP * slot
	return berth_foot(index) + BERTH_PACK_SHIFT + Vector2(BERTH_PACK_STEP.x * (slot % 4), BERTH_PACK_STEP.y * int(slot / 4))

# ---- 绘制 ----
func draw_level() -> void:
	draw_harbour()
	draw_berths()
	if bench_visible(): draw_bench()
	draw_heron()
	draw_bed()
	draw_flag()
	if bench_visible(): draw_tray()
	if state.stage in ["delivery", "complete"]: draw_lamplight()

func draw_harbour() -> void:
	for index in range(2):
		var bob = sin(clock * 1.7 + index * 1.9) * 4.0 if state.stage in ["delivery", "complete"] else 0.0
		kit(BOAT_ART[index], station(BOAT_STATIONS[index]) + Vector2(0, bob), BOAT_WIDTH)
	kit("navigation_lantern", station("lantern"), LANTERN_WIDTH)
	if state.stage in ["arrival", "approach"]:
		figure(KOUKOU_TIE, table_foot() + Vector2(150, 40), KOUKOU_SCALE)
	elif state.stage in ["ready", "complete"]:
		figure(KOUKOU_WAVE if state.stage == "complete" else KOUKOU_TIE, boss_foot() + Vector2(250, 30), KOUKOU_SCALE)

func draw_berths() -> void:
	for index in range(Rules.KINDS):
		var foot = berth_foot(index)
		var current = index == active_station() and state.stage not in ["arrival", "complete"]
		kit("receipt_blank", foot, CARD_WIDTH, 1.0 if current or state.stage == "complete" else 0.84)
		words("%s·%s" % [Rules.STATION_NAMES[index], Rules.STATION_PLACES[index]], foot + Vector2(-52, -134), 11,
			INK_GOLD if current else INK_LIGHT)
		words("要 %d 单位" % Rules.DEMAND[index], foot + Vector2(-52, -112), 15, INK_GOLD)
		words("最多 %d 包" % Rules.MAX_PACKS[index], foot + Vector2(-52, -92), 13)
		var lines = berth_rule_lines(index)
		for line in range(lines.size()):
			words(lines[line], foot + Vector2(-52, -72 + 18 * line), 12, berth_rule_color(index))
		if current and state.stage == "puzzle":
			socket(foot + Vector2(0, -24), Vector2(46, 15), 0.22 + 0.16 * pulse(3.2))
		draw_delivered(index)

# 货单上写死的约定：二站没翻旗之前把两种可能一并写出来，不藏。
func berth_rule_lines(index: int) -> Array:
	if index == 2: return ["固定不接大包"]
	if index == 1:
		if state.shown == 1: return ["%s %s" % [Rules.FLAG_SHORT[state.flag], Rules.FLAG_RULE[state.flag]]]
		return ["没翻旗之前：", "A 全收 · B 拒大包"]
	return ["大小包都收"]

func berth_rule_color(index: int) -> Color:
	if index == 1 and state.shown == 1: return INK_FLAG_A if state.flag == Rules.FLAG_A else INK_FLAG_B
	if index == 2: return INK_WARN
	return INK_LIGHT

# 已交出去的货钉在收货处：一单位都不回收，画面上也一直看得见。
# 三站那一行不在这里画——它的落点在铜鹭身上，得等羽翅画完才压得住（draw_bed）。
func draw_delivered(index: int) -> void:
	if index == Rules.KINDS - 1: return
	draw_packs(index)

# 三站的货床：整片展翼是同一张原图，先画的包会被后画的翅膀盖得一颗不见，所以这一格排在铜鹭之后。
func draw_bed() -> void:
	draw_packs(Rules.KINDS - 1)

func draw_packs(index: int) -> void:
	var row: Array = state.delivered[index]
	if Rules.packs_of(row) == 0: return
	if flying() and index == active_station() - 1:
		for entry in fly_plan(progress):
			contact(entry["at"], 12, 0.16)
			kit(PACK_ART[entry["kind"]], entry["at"], BERTH_PACK_WIDTH[entry["kind"]], 0.55 + 0.45 * entry["phase"])
		return
	var slot = 0
	for kind in range(Rules.KINDS):
		for step in range(row[kind]):
			var at = pack_home(index, slot)
			contact(at, 12, 0.2)
			kit(PACK_ART[kind], at, BERTH_PACK_WIDTH[kind])
			slot += 1

# 封装台：四条走法 + 三次机会 + 三行封包。牌上的字只复述规则，不判分、也不指出该怎么走。
func draw_bench() -> void:
	plaque("重新封装 · 剩 %d 次" % state.chances, header_rect(), 15,
		INK_WARN if state.chances == 0 else INK_GOLD)
	for index in range(Rules.CHANCES):
		var spent = index >= state.chances
		kit("paper_roll", chip_foot(index), CHIP_WIDTH, 0.24 if spent else 1.0)
	for index in range(Rules.OPS.size()):
		var rect = bench_rect(index)
		var ready = Rules.can_apply(state, index) if state.stage == "puzzle" else false
		plaque(Rules.OPS[index].name, rect, 15, INK_LIGHT if ready else INK_DIM)
		if ready: socket(rect.position + rect.size / 2.0, Vector2(rect.size.x / 2.0, 24), 0.09 + 0.09 * pulse(3.6))
	for kind in range(Rules.KINDS):
		var row = stock_row_rect(kind)
		var held = state.stock[kind]
		words("%s = %d 单位" % [Rules.PACK_NAMES[kind], Rules.UNITS[kind]], row.position + Vector2(2, 12), 12,
			INK_GOLD if held > 0 else INK_DIM)
		for slot in range(maxi(held, 1)):
			var at = stock_foot(kind, slot)
			var lift = landing("stock", kind) if slot == held - 1 else 0.0
			if held == 0:
				kit(PACK_ART[kind], at, PACK_WIDTH[kind], 0.14)
				continue
			contact(at, PACK_WIDTH[kind] * 0.4, 0.2)
			kit(PACK_ART[kind], at - Vector2(0, DROP_LIFT * lift), PACK_WIDTH[kind], 0.4 + 0.6 * (1.0 - lift))

func draw_tray() -> void:
	var foot = tray_foot()
	kit("receiving_tray", foot, TRAY_WIDTH)
	var kinds = Rules.tray_kinds(state)
	for slot in range(maxi(kinds.size(), 1)):
		var at = tray_spot(slot)
		if slot >= kinds.size():
			kit(PACK_ART[Rules.LARGE], at, 30.0, 0.12)
			continue
		var kind: int = kinds[slot]
		var lift = landing("tray", slot)
		contact(at, 15, 0.2)
		kit(PACK_ART[kind], at - Vector2(0, DROP_LIFT * lift), TRAY_PACK_WIDTH[kind], 0.35 + 0.65 * (1.0 - lift))
	plaque("验货托盘 · %d 单位 / %d 包" % [Rules.units_of(state.tray), Rules.packs_of(state.tray)],
		tray_plaque_rect(), 15, INK_GOLD)

# 铜鹭：巡守 → 举旗 → 展翼成搬运台。approach 从海侧走进来，carrying 里双翼摊开。
func draw_heron() -> void:
	var foot = heron_foot()
	if state.stage == "approach": foot += Vector2(lerpf(360, 0, smoothstep(0, 1, progress)), 0)
	var pose = heron_pose()
	if state.stage == "carrying":
		var spread = smoothstep(0, 1, progress)
		figure(HERON_FLAG, foot, HERON_SCALE * (1.0 - 0.22 * spread), 1.0 - spread)
		figure(HERON_PLATFORM, foot, HERON_SCALE * (0.66 + 0.34 * spread), spread)
		return
	var texture = [HERON_PATROL, HERON_FLAG, HERON_PLATFORM][pose]
	var sway = 0.0 if pose == 2 else sin(clock * 1.4) * 2.0
	figure(texture, foot + Vector2(0, sway), HERON_SCALE)

# 检查旗：翻面之前只有背面与两种可能；flag 那一幕里绕旗杆转过来。
func draw_flag() -> void:
	if state.stage == "arrival": return
	var foot = flag_foot()
	var flip = 1.0
	var face = state.shown == 1
	if state.stage == "flag":
		flip = cos(PI * clampf(progress, 0, 1))
		face = progress > 0.5
	var width = FLAG_WIDTH * maxf(0.06, absf(flip))
	draw_line(foot, foot + Vector2(0, -FLAG_POLE), Color("6d4a25"), 6.0)
	draw_set_transform(foot + Vector2(0, -FLAG_POLE + 6), 0, Vector2(1.0, 1.0))
	var points = PackedVector2Array([Vector2(0, 0), Vector2(width, 12), Vector2(width, 62), Vector2(0, 74)])
	draw_colored_polygon(points, Color("2c4a44") if face else Color("4a3a28"))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color("d8b46a"), 3.0)
	draw_string_outline(font, Vector2(width / 2.0 - 12, 48), "A/B" if not face else Rules.FLAG_SHORT[state.flag][1],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 4, Color("382515"))
	draw_string(font, Vector2(width / 2.0 - 12, 48), "A/B" if not face else Rules.FLAG_SHORT[state.flag][1],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK_FLAG_A if state.flag == Rules.FLAG_A and face else INK_LIGHT)
	draw_set_transform(Vector2.ZERO)
	kit("brass_bell", foot + Vector2(0, -FLAG_POLE), 22.0)
	if not face:
		plaque("旗未翻：A 全收 · B 拒大包", flag_plaque_rect(), 13)
	else:
		plaque("%s · %s" % [Rules.FLAG_SHORT[state.flag], Rules.FLAG_RULE[state.flag]], flag_plaque_rect(), 13,
			INK_FLAG_A if state.flag == Rules.FLAG_A else INK_FLAG_B)

# 三站办完，码头按玩家真正交出去的货亮起来：船随货起伏，灯串逐盏点亮。
func draw_lamplight() -> void:
	var lit = 3 if state.stage == "complete" else int(ceil(3 * clampf(progress, 0, 1)))
	for index in range(lit):
		kit("lantern_string", berth_foot(index) + Vector2(0, -215), 96.0, 0.9)
		socket(pack_home(index, 0) + Vector2(18, -10), Vector2(58, 20), 0.26 + 0.16 * pulse(2.4 + index))
	draw_circle(station("lantern") + Vector2(0, -58), 34 + 6 * pulse(2.0), Color(1.0, 0.86, 0.5, 0.14 + 0.1 * pulse(2.0)))

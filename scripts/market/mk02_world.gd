extends Node2D
# MK02 育苗铺交换台：底景与货物全部来自 kit-v1 拆件包，数量与约定由引擎绘制。
const Rules = preload("res://scripts/market/mk02_rules.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const MANIFEST_PATH = "res://art/market-kit-v1/manifest.json"
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/nursery-exchange-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const TRAY_WIDTH = 174.0
const RESIDENT = Vector2(659, 424)
const BENCH = [Vector2(1096, 492), Vector2(1160, 492)]
const FRUIT_SPOTS = [Vector2(371, 492), Vector2(407, 492), Vector2(443, 492), Vector2(479, 492),
	Vector2(371, 458), Vector2(407, 458), Vector2(443, 458), Vector2(479, 458)]
const TABLE_SPOTS = [Vector2(591, 488), Vector2(627, 488), Vector2(663, 488), Vector2(699, 488),
	Vector2(591, 460), Vector2(627, 460), Vector2(663, 460), Vector2(699, 460),
	Vector2(591, 432), Vector2(627, 432), Vector2(663, 432), Vector2(699, 432)]
const RACK_SPOTS = [Vector2(830, 496), Vector2(878, 496), Vector2(926, 496), Vector2(854, 444), Vector2(902, 444)]
const GOODS = {"fruit": ["copper_fruit", 34], "spool": ["rope_spool", 38], "wick": ["wick_bundle", 34]}
var state = Rules.fresh()
var progress = 0.0
var clock = 0.0
var land_place = ""
var land_slot = -1
var land_progress = 1.0
var parts: Dictionary = {}
var atlases: Dictionary = {}
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = UIStyle.face()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	for item in parsed.sprites:
		parts[item.id] = item
		atlases[item.id] = load("res://" + item.atlas)

func _process(delta: float) -> void:
	clock += delta

# The pending exchange lands at the half-way mark, so the flying goods and the
# counts on the plaques always describe the same moment.
func shown_state() -> Dictionary:
	var shown = state.duplicate(true)
	if state.stage == "exchanging" and progress >= 0.5:
		if state.exchange[0] == 0: shown.a += state.exchange[1]
		else: shown.b += state.exchange[1]
		shown.exchange = []
	return shown

# A good only changes hands one at a time, so the newest arrival is the single place
# that needs the drop-in animation. Taking it back simply returns it to the shared stack.
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	for slot in range(Rules.RACK_SLOTS):
		if previous.rack[slot] != state.rack[slot] and state.rack[slot] == 1: land_place = "rack"; land_slot = slot
	for slot in range(Rules.HOOK_SLOTS):
		if previous.hook[slot] != state.hook[slot] and state.hook[slot] == 1: land_place = "hook"; land_slot = slot

func landing(place: String, slot: int) -> float:
	return 1.0 - land_progress if land_place == place and land_slot == slot else 0.0

# Drop targets are logical squares around the good's foot, never the raw alpha bounds.
func rack_rect(slot: int) -> Rect2:
	return Rect2(RACK_SPOTS[slot] + Vector2(-26, -46), Vector2(52, 52))

func hook_rect(slot: int) -> Rect2:
	return Rect2(BENCH[slot] + Vector2(-26, -48), Vector2(52, 52))

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

func kit(id: String, foot: Vector2, width: float, alpha: float = 1.0, drop: float = 0.0) -> void:
	var texture: Texture2D = atlases[id]
	var item: Dictionary = parts[id]
	var scale = width / texture.get_width()
	var dims = Vector2(texture.get_width(), texture.get_height()) * scale
	var origin = foot + Vector2(0, drop) - Vector2(item.anchor_px[0], item.anchor_px[1]) * scale
	draw_texture_rect(texture, Rect2(origin, dims), false, Color(1, 1, 1, alpha))

func contact(foot: Vector2, radius: float, alpha: float = 0.26) -> void:
	draw_set_transform(foot + Vector2(0, 2), 0, Vector2(1, 0.26))
	draw_circle(Vector2.ZERO, radius, Color(0.1, 0.06, 0.03, alpha))
	draw_set_transform(Vector2.ZERO)

func words(text: String, at: Vector2, size_px: int = 17, color: Color = Color("fff0d1")) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 3, Color("382515"))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func plaque(text: String, rect: Rect2, size_px: int = 16, color: Color = Color("fff0d1")) -> void:
	var style = UIStyle.sign_style(); style.shadow_size = 0; style.bg_color.a = 1.0
	draw_style_box(style, rect)
	words(text, rect.position + Vector2(10, rect.size.y - 9), size_px, color)

func socket(centre: Vector2, radii: Vector2, strength: float) -> void:
	var pts = PackedVector2Array()
	for i in range(25):
		var angle = TAU * i / 24.0
		pts.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	pts.append(pts[0])
	draw_colored_polygon(pts, Color(1.0, 0.87, 0.58, 0.28 * strength))
	draw_polyline(pts, Color("8f6420", 0.9 * strength), 4, true)
	draw_polyline(pts, Color("ffe297", 1.0 * strength), 2, true)

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
	var hands = RESIDENT + Vector2(0, -40)
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

func _draw() -> void:
	if font == null or parts.is_empty(): return
	draw_texture_rect(BACKDROP, Rect2(0, 0, 1280, 720), false)
	# 扣扣 stands at the nursery's resident station; goods in front of it belong to the table.
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	var pose = KOUKOU_WAVE if happy else KOUKOU_TIE
	var feet = RESIDENT
	var pose_size = Vector2(pose.get_width(), pose.get_height()) * 0.5
	if state.stage == "delivery": feet += Vector2(lerpf(0, 34, smoothstep(0.45, 1, progress)), 0)
	contact(feet, 34, 0.2)
	draw_texture_rect(pose, Rect2(feet - Vector2(pose_size.x / 2, pose_size.y), pose_size), false)
	var placed = shown_state()
	var layout = goods_layout(placed)
	var carried = carry_plan(progress)
	var flying: Array = []
	for entry in carried: flying.append(entry["home"])
	var hidden = flying if (state.stage == "exchanging" and progress < 0.5) else []
	for foot in [Vector2(425, 499), Vector2(645, 499), Vector2(877, 499)]: kit("receiving_tray", foot, TRAY_WIDTH)
	for foot in layout.fruit:
		if foot in hidden: continue
		contact(foot, GOODS["fruit"][1] * 0.42, 0.2)
		kit("copper_fruit", foot, GOODS["fruit"][1])
	# Empty drop targets pulse only while there is something that may go there.
	var beat = 0.5 + 0.5 * sin(clock * 4.6)
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
		var give = smoothstep(0.5, 0.95, progress) if state.stage == "delivery" else 0.0
		var hook_foot: Vector2 = entry[0].lerp(feet + Vector2(-48 + entry[1] * 52, -8), give)
		contact(hook_foot, GOODS["spool"][1] * 0.42, 0.26 * (1.0 - rise) * (1.0 - give))
		kit("rope_spool", hook_foot - Vector2(0, 38 * rise), GOODS["spool"][1], (1.0 - rise * 0.75) * (1.0 - give * 0.6))
	for entry in layout.rack:
		var foot: Vector2 = entry[0]
		var drop = landing("rack", entry[1])
		var drift = 0.0
		if state.stage == "delivery": drift = smoothstep(0.05, 0.55, progress)
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
	plaque("约定一 · 2 铜果 → 3 线卷", Rect2(330, 514, 192, 28))
	plaque("约定二 · 2 线卷 → 1 灯芯", Rect2(550, 514, 192, 28))
	plaque("码头交付架 · %d / %d 根灯芯" % [placed.rack.count(1), Rules.WICK_ORDER], Rect2(776, 514, 206, 28),
		16, Color("ffe297") if placed.rack.count(1) == Rules.WICK_ORDER else Color("fff0d1"))
	plaque("扣扣的修补台 · %d / %d 卷线" % [placed.hook.count(1), Rules.SPOOL_ORDER], Rect2(1004, 514, 206, 28),
		16, Color("ffe297") if placed.hook.count(1) == Rules.SPOOL_ORDER else Color("fff0d1"))

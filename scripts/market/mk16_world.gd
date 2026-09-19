extends "res://scripts/market/kit_world.gd"
# MK16 大码头「给森林寄回一份礼物」：打包台（packing）摊着三格台面，四样纪念物摆在右边的货板上，
# 红船（boat_red）泊在旧码头接单，领航灯（lantern）照着港口的出口，扣扣（boss_foot 右侧）守着秤。
# 底景、船、纸卷、铜铃、封包、回执纸与灯壳全部取自 art/market-kit-v1 的 dock 场景；
# 落点一律读 manifest 的 station，格位由 grid() 算，关卡里不另立第二套摊位坐标。
# 白杯取自 MK01 读的那张机制图源表（同一只量过水的杯子），是引用现成图块、不是新裁美术。
const Rules = preload("res://scripts/market/mk16_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/grand-dock-clean-v1.png")
const PROPS = preload("res://assets/source/market/mechanisms-source-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const CUP_REGION = Rect2(376, 176, 249, 179)
const ITEM_WIDTH = [56.0, 62.0, 58.0, 50.0]
const ITEM_HEIGHT = [56.0, 50.0, 42.0, 63.0]
const SLOT_STEP = 74.0
const SHELF_STEP = 88.0
const SHELF_FROM = Vector2(-330, -43)
const KEEPER_FROM = Vector2(120, 0)
const PARCEL_WIDTH = 78.0
const BOAT_WIDTH = 175.0
const BLUE_BOAT_WIDTH = 148.0
const LANTERN_WIDTH = 84.0
const LETTER_WIDTH = 124.0
const PLACE_TIME = 0.34
const WRAP_AT = 0.4
const CARRY_END = 0.9
const SAIL_SHIFT = Vector2(70, -26)
const SAIL_FAR = 0.4
const SAIL_ALPHA = 0.62
const REPLY_AT = 0.45
var _slots: Array = []
var _shelf: Array = []
var landed: Array = [-100.0, -100.0, -100.0, -100.0]
var lifted: Array = [-100.0, -100.0, -100.0, -100.0]
var held_seen: Array = [0, 0, 0, 0]

func ready_level() -> void:
	scene_id = "dock"
	backdrop = BACKDROP

# ---- 落点：全部由 manifest 的三个 station 推出来 ----
func table_slots() -> Array:
	if _slots.is_empty():
		_slots = grid(station("packing") - Vector2(SLOT_STEP, 0), Vector2(SLOT_STEP, 0),
			Rules.PICKS, Rules.PICKS)
	return _slots

func table_foot(index: int) -> Vector2: return table_slots()[index]
func table_rect(index: int) -> Rect2: return target(table_foot(index), 70.0, 58.0)
# 包裹在画面上的位置（含镜头与窗口缩放）：离岸一幕的审计就圈这一块看两条分支差在哪。
func charm_box() -> Rect2:
	var canvas = get_global_transform_with_canvas()
	var scale = canvas.get_scale().x
	return Rect2(canvas * parcel_foot() - Vector2(46, 84) * scale, Vector2(92, 100) * scale)

func shelf_slots() -> Array:
	if _shelf.is_empty():
		_shelf = grid(station("boss_foot") + SHELF_FROM, Vector2(SHELF_STEP, 0), 4, 4)
	return _shelf

func shelf_foot(id: int) -> Vector2: return shelf_slots()[id]
func shelf_rect(id: int) -> Rect2: return target(shelf_foot(id), 68.0, 54.0)

func keeper_foot() -> Vector2: return station("boss_foot") + KEEPER_FROM
func boat_foot() -> Vector2: return station("boat_red")
func boat_rect() -> Rect2: return target(boat_foot() + Vector2(0, 46), 132.0, 86.0)
func lantern_foot() -> Vector2: return station("lantern")
func sail_point() -> Vector2: return boat_foot().lerp(station("boat_blue"), 0.5) + SAIL_SHIFT

# ---- 派生读数：画面不另存任何计数 ----
func held_ids() -> Array:
	return state.gift if state.stage in Rules.PACKED else state.table

func carried(id: int) -> bool: return held_ids().has(id)

func table_weight() -> int: return Rules.total(state.table)

# 台面上那杆秤只念玩家自己摆下的数字：文字与牌子共用这一个入口，审计也读它。
func table_plaque() -> String:
	return "打包台 · %s = %d 斤 / 上限 %d 斤" % [Rules.sum_text(state.table), table_weight(), Rules.LIMIT]

# 台面与货架上的货都只有一件：拿起就空，放下才出现，读起来才是真的在搬东西。
func track_changes() -> void:
	for id in Rules.KINDS:
		var held = 1 if carried(id) else 0
		if held_seen[id] == held: continue
		if held == 1: landed[id] = clock
		else: lifted[id] = clock
		held_seen[id] = held

func placed_progress(id: int) -> float:
	return clampf((clock - landed[id]) / PLACE_TIME, 0.0, 1.0)

func lifted_progress(id: int) -> float:
	return clampf((clock - lifted[id]) / PLACE_TIME, 0.0, 1.0)

# 放上台面那一程：从货架抬起来，画一道短弧落到格位上。
func table_item_foot(id: int, index: int) -> Vector2:
	var t = placed_progress(id)
	var from = shelf_foot(id) - Vector2(0, 26)
	return from.lerp(table_foot(index), t) - Vector2(0, sin(t * PI) * 34)

# ---- 红船与包裹：船带着真正装好的那一件离开 ----
func sailing() -> bool: return state.stage in ["delivery", "complete"]

func sail_amount() -> float:
	if state.stage == "complete": return 1.0
	return smoothstep(0.4, 1.0, progress) if state.stage == "delivery" else 0.0

func boat_now() -> Vector2: return boat_foot().lerp(sail_point(), sail_amount())

func boat_width() -> float: return BOAT_WIDTH * lerpf(1.0, SAIL_FAR, sail_amount())

func boat_scale() -> float: return boat_width() / BOAT_WIDTH

func boat_alpha() -> float: return lerpf(1.0, SAIL_ALPHA, sail_amount())

func deck_foot() -> Vector2: return boat_now() + Vector2(-6 * boat_scale(), -54 * boat_scale())

func wrap_phase() -> float: return clampf(progress / WRAP_AT, 0.0, 1.0)

func carry_phase() -> float:
	return clampf((progress - WRAP_AT) / (CARRY_END - WRAP_AT), 0.0, 1.0)

func parcel_seat(id: int) -> Vector2:
	return table_foot(1) + Vector2((id - 1.5) * 20.0, -10.0)

func parcel_foot() -> Vector2:
	match state.stage:
		"loading":
			var from = table_foot(1) + Vector2(0, 6)
			return from.lerp(deck_foot(), carry_phase()) - Vector2(0, sin(carry_phase() * PI) * 30)
		"delivery", "complete":
			return deck_foot()
	return Vector2.ZERO

func parcel_width() -> float:
	return PARCEL_WIDTH * (boat_scale() if sailing() else 1.0)

func parcel_alpha() -> float:
	if state.stage == "loading": return clampf((wrap_phase() - 0.5) / 0.5, 0.0, 1.0)
	return boat_alpha() if sailing() else 0.0

func charm_id() -> int: return Rules.chosen(state.gift)

func show_letter() -> bool:
	if state.stage == "complete": return true
	return state.stage == "delivery" and progress >= REPLY_AT

# ---- 图块：四样纪念物共用一个入口 ----
func souvenir(id: int, foot: Vector2, alpha: float = 1.0, scale: float = 1.0) -> void:
	if not Rules.known(id) or alpha <= 0: return
	var width = ITEM_WIDTH[id] * scale
	if id == Rules.PAPER: kit("paper_roll", foot, width, alpha)
	elif id == Rules.BELL: kit("brass_bell", foot, width, alpha)
	elif id == Rules.CUP: draw_cup(foot, width, alpha)
	else: draw_leaf(foot, width, alpha)

func draw_cup(foot: Vector2, width: float, alpha: float) -> void:
	var height = width * CUP_REGION.size.y / CUP_REGION.size.x
	draw_texture_rect_region(PROPS, Rect2(foot.x - width / 2.0, foot.y - height, width, height),
		CUP_REGION, Color(1, 1, 1, alpha))

# 绿叶章：铜环里一枚两叶芽——森林那枚印记的老造型，全部由引擎画，不裁新图。
func draw_leaf(foot: Vector2, width: float, alpha: float) -> void:
	var centre = foot - Vector2(0, width / 2.0)
	var ring = width / 2.0
	draw_circle(centre, ring, Color("8a5a1c", alpha))
	draw_circle(centre, ring - 3.0, Color("e3bd63", alpha))
	draw_circle(centre, ring - 6.5, Color("f7edcd", alpha))
	var stem = Color("3f7a34", alpha)
	draw_line(centre + Vector2(0, ring * 0.52), centre + Vector2(0, -ring * 0.18), stem, 2.4)
	leaf_shape(centre + Vector2(-ring * 0.24, -ring * 0.2), ring * 0.84, -2.25, Color("4f9a45", alpha))
	leaf_shape(centre + Vector2(ring * 0.24, -ring * 0.26), ring * 0.9, -0.92, Color("68b855", alpha))

func leaf_shape(at: Vector2, length: float, angle: float, color: Color) -> void:
	var pts = PackedVector2Array()
	var steps = 7
	# 两条边要同向绕一圈才是一片叶子：第二条边倒着走，否则多边形会自交成蝴蝶结。
	for flip in [false, true]:
		var order = range(steps + 1) if not flip else range(steps, -1, -1)
		for step in order:
			var t = float(step) / steps
			var wide = sin(t * PI) * length * 0.26 * (-1.0 if flip else 1.0)
			pts.append(at + Vector2(length * (t - 0.5), wide).rotated(angle))
	draw_colored_polygon(pts, color)
	var edge = pts.duplicate(); edge.append(pts[0])
	draw_polyline(edge, Color(0.16, 0.32, 0.13, color.a), 1.0, true)
	draw_line(at + Vector2(-length * 0.4, 0).rotated(angle), at + Vector2(length * 0.4, 0).rotated(angle),
		Color(0.16, 0.32, 0.13, color.a), 1.0)

# ---- 绘制 ----
func draw_level() -> void:
	track_changes()
	draw_lantern()
	draw_boats()
	draw_shelf()
	draw_table()
	draw_parcel()
	draw_letter()
	draw_keeper()

func draw_lantern() -> void:
	var foot = lantern_foot()
	kit("navigation_lantern", foot, LANTERN_WIDTH)
	var item: Dictionary = parts["navigation_lantern"]
	var glass = Vector2(item.attachments_px.light_center[0], item.attachments_px.light_center[1])
	var centre = foot + (glass - Vector2(item.anchor_px[0], item.anchor_px[1])) * (LANTERN_WIDTH / float(atlases["navigation_lantern"].get_width()))
	socket(centre, Vector2(26, 26), 0.22 + 0.16 * pulse())

func draw_boats() -> void:
	var blue = station("boat_blue")
	contact(blue + Vector2(0, 4), BLUE_BOAT_WIDTH * 0.3, 0.14)
	kit("transport_boat_blue", blue, BLUE_BOAT_WIDTH, 0.8)
	var foot = boat_now()
	var width = boat_width()
	var alpha = boat_alpha()
	contact(foot + Vector2(0, 4), width * 0.32, 0.16 * alpha)
	kit("transport_boat_red", foot, width, alpha)
	if state.stage == "puzzle":
		socket(foot + Vector2(0, -10), Vector2(width * 0.26, 12), 0.26 + 0.2 * pulse())

func draw_shelf() -> void:
	if state.stage in ["arrival", "approach"]: return
	plaque("码头纪念物 · 每样只有一件", Rect2(shelf_foot(0).x - 20, shelf_foot(0).y - 96, 268, 26), 14)
	for id in Rules.KINDS:
		var foot = shelf_foot(id)
		var gone = carried(id)
		var alpha = 0.0 if gone else lifted_progress(id)
		if gone:
			socket(foot - Vector2(0, 12), Vector2(26, 9), 0.16 + 0.1 * pulse())
		else:
			contact(foot, ITEM_WIDTH[id] * 0.42, 0.22 * alpha)
			souvenir(id, foot, alpha)
		plaque("%s %d" % [Rules.name_of(id), Rules.weight_of(id)],
			Rect2(foot.x - 42, foot.y + 10, 84, 22), 13, INK_GOLD if not gone else INK_LIGHT)

func draw_table() -> void:
	if state.stage in ["arrival", "approach"]:
		plaque("打包台 · 还没摆货", Rect2(table_foot(1).x - 96, table_foot(1).y - 108, 192, 26), 14)
		return
	if state.stage == "puzzle":
		for index in range(Rules.PICKS):
			var foot = table_foot(index)
			var id = state.table[index] if index < state.table.size() else -1
			if id < 0:
				socket(foot - Vector2(0, 14), Vector2(30, 11), 0.2 + 0.16 * pulse())
				continue
			var at = table_item_foot(id, index)
			contact(foot, ITEM_WIDTH[id] * 0.44, 0.24)
			souvenir(id, at, 1.0)
		plaque(table_plaque(), Rect2(table_foot(1).x - 212, table_foot(1).y - 112, 424, 28), 15)
	if state.stage == "ready":
		for index in range(Rules.PICKS):
			socket(table_foot(index) - Vector2(0, 14), Vector2(30, 11), 0.2 + 0.16 * pulse())

func draw_parcel() -> void:
	if state.stage == "loading":
		for index in range(state.gift.size()):
			var id: int = state.gift[index]
			var t = wrap_phase()
			var at = table_foot(index).lerp(parcel_seat(id), t) - Vector2(0, sin(t * PI) * 26)
			souvenir(id, at, 1.0 - t, 0.9)
	if parcel_alpha() <= 0: return
	var foot = parcel_foot()
	var width = parcel_width()
	var height = width * 218.0 / 328.0
	contact(foot, width * 0.4, 0.2 * parcel_alpha())
	kit("parcel_medium", foot, width, parcel_alpha())
	var charm = charm_id()
	if charm < 0: return
	# 系在最外面的那一件就是玩家的偏好：包裹在码头上、在船上、在回执里都带着它。
	var top = foot - Vector2(0, height - 6)
	draw_line(top + Vector2(-14, 6), top + Vector2(14, 2), Color("8a5a1c", parcel_alpha()), 2.0)
	souvenir(charm, top + Vector2(16, 4), parcel_alpha(), 0.74 * (width / PARCEL_WIDTH))

func draw_letter() -> void:
	if not show_letter() or state.stage not in Rules.PACKED: return
	var foot = station("packing")
	kit("receipt_blank", foot, LETTER_WIDTH)
	words("包裹收讫", foot + Vector2(-40, -132), 15, INK_GOLD)
	words("三样 · %d 斤" % Rules.total(state.gift), foot + Vector2(-46, -108), 13)
	words("上限 %d 斤" % Rules.LIMIT, foot + Vector2(-46, -88), 13)
	words("吊牌 · %s" % Rules.present_name(state.gift), foot + Vector2(-46, -64), 13, INK_GOLD)
	words("红船 · 已离岸", foot + Vector2(-46, -42), 13)

func draw_keeper() -> void:
	if state.stage in ["arrival", "approach"]: return
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress >= REPLY_AT)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, keeper_foot(), 0.5)

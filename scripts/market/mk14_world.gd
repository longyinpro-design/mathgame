extends "res://scripts/market/kit_world.gd"
# MK14 三枚砝码的小摊：油庭院前景那具货栈铜秤、架上的三枚砝码、接连送来的两单真货。
# 底景、铜秤三构件、砝码、油纸封包、接货车、接货托盘与回执全部来自 kit-v1 拆件包；
# 坐标只来自 manifest `oil` 场景（scale_foot / cart_left / cart_middle / cart_right）与
# delivery_cart 自己的 cargo_left / cargo_right 挂点，砝码排与盘内站位都由 grid() 算出来，
# 关卡里不另立第二套站位、也不手写任何 manifest 已经给出的挂点关系。
# 秤在摆放过程中始终锁着（braked），读数只在提交之后的抬秤里出现；判分只在规则层，
# 画面只复述玩家自己摆出来的那一式，永远不预告它平不平。
const Rules = preload("res://scripts/market/mk14_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/oil-courtyard-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 三件秤构件共用一个组装系数，挂点链才接得上：stand.pivot → beam.pivot、
# beam.left_hook/right_hook → pan.suspension（正好是 scale_pan 自己的 anchor_px）、
# pan.cargo 才是盘底放货的那一点。manifest 的 suggested_width 是拆件包的紧凑示尺寸
# （94/224 ≈ 180/431 ≈ 100/239 ≈ 0.42），在 1280×720 的庭院里立起来只有 90 像素高；
# 第五幕 MK11 把同一具秤立成 0.85，本关借的就是那一具，所以沿用同一个系数。
const SCALE_FACTOR = 0.85
const SCALE_PARTS = ["scale_stand", "scale_beam", "scale_pan"]
# 一盘最多要站下「一单货 + 三枚砝码」四件东西：四个盘内站位按 50 像素排开（±75），
# 最外侧那件的外缘必须落在 239×0.85 = 203 像素宽的盘沿（±101.6）之内，
# 所以货与砝码的宽度都被这条盘沿算死，不由作者凭手感写。
const WEIGHT_WIDTHS = [40.0, 46.0, 40.0]
const PARCEL_WIDTHS = [46.0, 52.0]
const PAN_PITCH = 50.0
const PAN_LIFT = 6.0
# 砝码架摆在铜秤左手边的地上：三格 56 像素一排，全部落在 receiving_tray 的 174 宽之内。
const RACK_OFFSET = Vector2(-330, 40)
const RACK_PITCH = 56.0
const RACK_LIFT = 4.0
const SLOT_SIZE = 52.0
const SLOT_LIFT = 44.0
const PAN_SIZE = 96.0
const PAN_TOP = 60.0
const CART_SIZE = 120.0
const CART_LIFT = 130.0
# 货与砝码站同一条横排；飞行途中加一点抛物线。
const CARRY_ARC = 46.0
# 秤杆静止时最多沉到多少弧度：只决定演出的幅度，从不参与判分。
const MAX_ANGLE = 0.14
const DROP_TIME = 0.24
const DROP_LIFT = 18.0
# 迷你铜秤纪念物：同一套构件、同一个挂点链，只整体再缩 0.42；它立在右下角的空地上，
# 三块牌子压在它头顶，离右边那辆车与按钮排都留出距离。
const SOUVENIR_SCALE = 0.42
const SOUVENIR_FOOT = Vector2(470, 63)
const SOUVENIR_BASE = Vector2(0, -30)
const SOUVENIR_PLANK = 240.0
const KEEPER = Vector2(-540, 33)
# 盘内横排里「这一单的货」占的那一格用这个哨兵表示，砝码一律用 0..2 的下标。
const PARCEL_SLOT = -1
var drop_seen := [0, 0, 0]
var drop_at := [-100.0, -100.0, -100.0]

func ready_level() -> void:
	scene_id = "oil"; backdrop = BACKDROP

# ---- manifest 换算：尺寸与挂点都从清单里读，缩放只乘一次 ----
func suggested(id: String) -> float: return float(parts[id].suggested_width)

func atlas_w(id: String) -> float: return float(atlases[id].get_width())

func atlas_h(id: String) -> float: return float(atlases[id].get_height())

# 铜秤三构件共用的组装系数：座、梁、盘都用它，挂点链才不会各算一套。
func unit_scale() -> float: return SCALE_FACTOR

func part_width(id: String, factor: float = -1.0) -> float:
	return atlas_w(id) * (unit_scale() if factor < 0.0 else factor)

func kit_height(id: String, width: float) -> float:
	return width * atlas_h(id) / atlas_w(id)

# 世界落点 = 脚点 + (附件像素 − anchor_px) × scale。
func attach(id: String, name: String, foot: Vector2, factor: float) -> Vector2:
	var item: Dictionary = parts[id]
	var point: Array = item.attachments_px[name]
	return foot + Vector2(point[0] - item.anchor_px[0], point[1] - item.anchor_px[1]) * factor

# ---- 落点：一律由 station() 与 grid() 推出来 ----
func scale_foot() -> Vector2: return station("scale_foot")

func cart_station(index: int) -> Vector2:
	return station(Rules.CARTS[clampi(index, 0, Rules.CARTS.size() - 1)])

func bed_px() -> Array:
	var table: Dictionary = parts["delivery_cart"]["attachments_px"]
	var out := []
	for key in ["cargo_left", "cargo_right"]:
		var point: Array = table[key]
		out.append(Vector2(point[0], point[1]))
	return out

func cart_scale() -> float: return suggested("delivery_cart") / atlas_w("delivery_cart")

# 车斗里的两个放货位：跟着 delivery_cart 自己的挂点走，不另立坐标。
func cart_bed(cart_index: int, slot: int) -> Vector2:
	var item: Dictionary = parts["delivery_cart"]
	var point: Vector2 = bed_px()[clampi(slot, 0, 1)]
	return cart_station(cart_index) + (point - Vector2(item.anchor_px[0], item.anchor_px[1])) * cart_scale()

func rack_foot() -> Vector2: return scale_foot() + RACK_OFFSET

func rack_spots() -> Array:
	return grid(rack_foot() + Vector2(-RACK_PITCH, -RACK_LIFT), Vector2(RACK_PITCH, 0),
		Rules.COUNT, Rules.COUNT)

func rack_spot(index: int) -> Vector2: return rack_spots()[index]

# ---- 铜秤：梁绕 pivot 转，盘只跟着梁端平移、自身保持水平 ----
func hook_of(side: int) -> int: return 0 if side == Rules.GOODS else 1

func pivot_at(foot: Vector2, factor: float) -> Vector2:
	return attach("scale_stand", "pivot", foot, factor)

func hook_at(foot: Vector2, factor: float, side: int, angle: float) -> Vector2:
	var item: Dictionary = parts["scale_beam"]
	var point: Array = item.attachments_px["left_hook" if hook_of(side) == 0 else "right_hook"]
	var local = Vector2(point[0] - item.anchor_px[0], point[1] - item.anchor_px[1]) * factor
	return pivot_at(foot, factor) + local.rotated(angle)

func cargo_at(foot: Vector2, factor: float, side: int, angle: float = 0.0) -> Vector2:
	return attach("scale_pan", "cargo", hook_at(foot, factor, side, angle), factor)

func beam_pivot() -> Vector2: return pivot_at(scale_foot(), unit_scale())

func beam_hook(side: int, angle: float) -> Vector2:
	return hook_at(scale_foot(), unit_scale(), side, angle)

# 命中区用静止位置（梁锁着），画面用当前倾角，两者永远不各算一套。
func pan_cargo(side: int) -> Vector2: return cargo_at(scale_foot(), unit_scale(), side, 0.0)

func live_cargo(side: int) -> Vector2: return cargo_at(scale_foot(), unit_scale(), side, beam_angle())

# 盘里这一横排站着什么：货盘的头一格永远是这一单的货，其后按 9、3、1 从大到小排砝码，
# 读起来就是柜面上那一式从左到右的顺序。
func pan_items(side: int) -> Array:
	var list := []
	if side == Rules.GOODS and Rules.cargo_on_pan(state): list.append(PARCEL_SLOT)
	for weight in Rules.on_list_state(state, side): list.append(weight)
	return list

func pan_row(side: int, foot: Vector2 = Vector2.INF) -> Array:
	var items := pan_items(side)
	if items.is_empty(): return []
	var base: Vector2 = (live_cargo(side) if foot == Vector2.INF else foot) + Vector2(0, PAN_LIFT)
	return grid(base + Vector2(-PAN_PITCH * (items.size() - 1) / 2.0, 0), Vector2(PAN_PITCH, 0),
		items.size(), items.size())

func item_foot(side: int, item: int) -> Vector2:
	var items := pan_items(side)
	var slot: int = items.find(item)
	if slot < 0: return rack_spot(item) if item >= 0 else pan_cargo(side)
	return pan_row(side)[slot]

func weight_foot(index: int) -> Vector2:
	var side: int = Rules.side_of(state, index)
	return rack_spot(index) if side == Rules.OFF else item_foot(side, index)

# 排在货盘头一格的封包：它跟着横排走，砝码才不会被画到货里。
# 这一条只按「货盘上有几枚砝码」算，与在哪一幕无关，飞行途中与落到盘里是同一个落点。
func parcel_on_pan(_index: int) -> Vector2:
	var count: int = Rules.pan_count(state, Rules.GOODS) + 1
	return live_cargo(Rules.GOODS) + Vector2(-PAN_PITCH * (count - 1) / 2.0, PAN_LIFT)

func weight_width(index: int) -> float:
	return WEIGHT_WIDTHS[clampi(index, 0, Rules.COUNT - 1)]

func weight_height(index: int) -> float:
	return kit_height(Rules.WEIGHT_KITS[index], weight_width(index))

func parcel_width(index: int) -> float:
	return PARCEL_WIDTHS[clampi(index, 0, Rules.ORDERS.size() - 1)]

# ---- 两单货的位置：车上等着、盘上压着、交完回到交货车 ----
func parcel_foot(index: int) -> Vector2:
	if index < 0 or index >= Rules.ORDERS.size(): return scale_foot()
	if index < state.order: return cart_bed(2, index)
	if index > state.order: return cart_bed(index, 0)
	match state.stage:
		"arrival":
			return cart_bed(index, 0)
		"approach":
			return carry(cart_bed(index, 0), parcel_on_pan(index), smoothstep(0.2, 1.0, progress))
		"delivery":
			return carry(parcel_on_pan(index), cart_bed(2, index), smoothstep(0.15, 0.9, progress))
		"complete":
			return cart_bed(2, index)
	return parcel_on_pan(index)

# 交付那一幕里，下一单的货同时被推上秤：迁移就这么演出来。
func next_parcel_foot() -> Vector2:
	var index: int = state.order + 1
	if index >= Rules.ORDERS.size(): return Vector2.INF
	return carry(cart_bed(index, 0), parcel_on_pan(index), smoothstep(0.4, 1.0, progress))

func carry(from: Vector2, to: Vector2, amount: float) -> Vector2:
	return from.lerp(to, amount) + Vector2(0, -CARRY_ARC * sin(amount * PI))

# ---- 命中区：全部 KitWorld.target()，最小 52 逻辑像素 ----
func rack_rect(index: int) -> Rect2: return target(rack_spot(index), SLOT_SIZE, SLOT_LIFT)

func pan_rect(side: int) -> Rect2: return target(pan_cargo(side), PAN_SIZE, PAN_TOP)

func cart_rect(index: int) -> Rect2: return target(cart_station(index), CART_SIZE, CART_LIFT)

func keeper_foot() -> Vector2: return scale_foot() + KEEPER

func souvenir_foot() -> Vector2: return scale_foot() + SOUVENIR_FOOT

# ---- 制动与倾斜：只有抬秤与结果牌那两幕梁才会摆 ----
func braked() -> bool: return state.stage not in ["weighing", "result"]

func beam_angle() -> float:
	if not state.has("goods"): return 0.0
	if state.stage == "result": return MAX_ANGLE * Rules.tilt(state)
	if state.stage != "weighing": return 0.0
	if Rules.balanced(state): return MAX_ANGLE * 0.55 * sin(progress * PI * 2.4) * (1.0 - progress)
	return MAX_ANGLE * Rules.tilt(state) * smoothstep(0.1, 0.72, progress)

# 砝码挪盘的那一下用世界自己的时钟下落，不占用宿主的落地锁。
func track_changes() -> void:
	for index in range(Rules.COUNT):
		var side: int = Rules.side_of(state, index)
		if drop_seen[index] != side:
			drop_at[index] = clock; drop_seen[index] = side

func drop(index: int) -> float:
	return clampf((clock - drop_at[index]) / DROP_TIME, 0.0, 1.0)

# ---- 绘制 ----
func draw_level() -> void:
	if not state.has("goods"): return
	track_changes()
	draw_carts()
	draw_scale()
	draw_parcels()
	for side in [Rules.GOODS, Rules.FAR]:
		draw_pan(side)
	draw_rack()
	if state.stage == "complete": draw_souvenir()
	draw_figure()
	draw_text()

func draw_carts() -> void:
	for index in range(Rules.CARTS.size()):
		contact(cart_station(index) + Vector2(0, -6), 84, 0.18)
		kit("delivery_cart", cart_station(index), suggested("delivery_cart"))

func draw_parcels() -> void:
	for index in range(Rules.ORDERS.size()):
		if state.stage == "delivery" and index == state.order + 1: continue
		draw_parcel(index, parcel_foot(index))
	if state.stage == "delivery":
		var coming := next_parcel_foot()
		if coming != Vector2.INF: draw_parcel(state.order + 1, coming)

func draw_parcel(index: int, foot: Vector2) -> void:
	var width := parcel_width(index)
	contact(foot, width * 0.44, 0.2)
	kit(Rules.ORDER_KITS[index], foot, width)
	words("%d" % Rules.ORDERS[index], foot + Vector2(-4, -width * 0.3), 15, INK_GOLD)

# 座、梁、两只空盘：真秤与纪念物共用这一段。
func draw_scale_frame(foot: Vector2, factor: float, angle: float) -> void:
	kit("scale_stand", foot, atlas_w("scale_stand") * factor)
	var beam: Dictionary = parts["scale_beam"]
	draw_set_transform(pivot_at(foot, factor), angle, Vector2.ONE)
	draw_texture_rect(atlases["scale_beam"], Rect2(-Vector2(beam.anchor_px[0], beam.anchor_px[1]) * factor,
		Vector2(atlas_w("scale_beam") * factor, atlas_h("scale_beam") * factor)), false)
	draw_set_transform(Vector2.ZERO)
	for side in [Rules.GOODS, Rules.FAR]:
		kit("scale_pan", hook_at(foot, factor, side, angle), atlas_w("scale_pan") * factor)

func draw_scale() -> void:
	draw_scale_frame(scale_foot(), unit_scale(), beam_angle())

func draw_pan(side: int) -> void:
	var items := pan_items(side)
	var row := pan_row(side)
	for slot in range(items.size()):
		# 货盘头一格是这一单的货，由 draw_parcels 统一画；这里只画站在盘里的砝码。
		if items[slot] == PARCEL_SLOT: continue
		draw_weight(items[slot], row[slot])

func draw_rack() -> void:
	kit("receiving_tray", rack_foot(), suggested("receiving_tray"))
	for index in range(Rules.COUNT):
		if Rules.side_of(state, index) != Rules.OFF:
			# 架上空出来的那一格：只标「这一枚在秤上」，不指出该站哪一边。
			var spot := rack_spot(index)
			socket(spot - Vector2(0, 16), Vector2(22, 9), 0.2 + 0.14 * pulse())
			words(str(Rules.WEIGHTS[index]), spot + Vector2(-5, -20), 15, Color("c2a26c"))
			continue
		draw_weight(index, rack_spot(index))

func draw_weight(index: int, foot: Vector2) -> void:
	var amount := drop(index)
	var at := foot + Vector2(0, -DROP_LIFT * (1.0 - amount))
	var alpha := 0.45 + 0.55 * amount
	contact(foot, weight_width(index) * 0.48, 0.18 * alpha)
	kit(Rules.WEIGHT_KITS[index], at, weight_width(index), alpha)
	words(str(Rules.WEIGHTS[index]), at + Vector2(-5, -weight_height(index) - 6), 15, INK_GOLD)

# 迷你铜秤纪念物：同一套构件、同一个挂点公式，只是整体再缩 SOUVENIR_SCALE；
# 它上头重演的是玩家真正记进账里的那一式，不是作者写死的答案。
# 纪念物只重演最后一单真正记下的那一式：货与砝码同一条横排，与真秤的排法同一个算法。
func souvenir_pitch() -> float:
	return part_width("scale_pan", unit_scale() * SOUVENIR_SCALE) * 0.24

func souvenir_row(side: int) -> Array:
	var items: Array = souvenir_items(side)
	var factor: float = unit_scale() * SOUVENIR_SCALE
	var base: Vector2 = souvenir_foot() + SOUVENIR_BASE
	return grid(cargo_at(base, factor, side, 0.0) + Vector2(-souvenir_pitch() * (items.size() - 1) / 2.0, 0),
		Vector2(souvenir_pitch(), 0), items.size(), items.size())

func draw_souvenir() -> void:
	var foot: Vector2 = souvenir_foot()
	kit("receiving_tray", foot, suggested("receiving_tray"))
	var base: Vector2 = foot + SOUVENIR_BASE
	draw_scale_frame(base, unit_scale() * SOUVENIR_SCALE, 0.0)
	for side in [Rules.GOODS, Rules.FAR]:
		var items: Array = souvenir_items(side)
		var row: Array = souvenir_row(side)
		for slot in range(items.size()):
			if items[slot] == PARCEL_SLOT:
				kit(Rules.ORDER_KITS[Rules.ORDERS.size() - 1], row[slot],
					parcel_width(Rules.ORDERS.size() - 1) * SOUVENIR_SCALE)
			else:
				kit(Rules.WEIGHT_KITS[items[slot]], row[slot], weight_width(items[slot]) * SOUVENIR_SCALE)

func souvenir_items(side: int) -> Array:
	var last: int = Rules.ORDERS.size() - 1
	var list := []
	if side == Rules.GOODS: list.append(PARCEL_SLOT)
	for weight in Rules.on_list(state.built_goods[last], state.built_far[last], side): list.append(weight)
	return list

# 扣扣站在铜秤左手边的空地上：oil 场景没有人物站位，坐标由秤脚推出，不另立锚点。
func draw_figure() -> void:
	var happy: bool = state.stage == "complete" or (state.stage == "delivery" and progress > 0.5)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, keeper_foot(), 0.5)

# ---- 柜面文字：画之前先被无头检查逐条量过宽度 ----
# 汉字在 Godot 里是一个不断词，plaque 与 words 都不换行，超框就会画到旁边的货上。
# 板的落点都躲开实物：车顶板只在车斗上方的空带里，盘名贴着盘底，读数板压在秤座下方。
func sign_board(text: String, at: Vector2, wide: float, size_px: int, plaque_board: bool) -> Dictionary:
	return {"text": text, "rect": Rect2(at.x - wide / 2.0, at.y, wide, 26), "size": size_px,
		"board": plaque_board}

func signs() -> Array:
	var boards := []
	if not state.has("delivered"): return boards
	for index in range(Rules.CARTS.size()):
		if state.stage == "complete": break
		var at := cart_station(index)
		boards.append(sign_board(cart_caption(index), Vector2(at.x, at.y - 176), 248.0, 14, true))
	if state.stage in ["arrival", "approach"]: return boards
	for side in [Rules.GOODS, Rules.FAR]:
		var dish := pan_cargo(side)
		boards.append(sign_board(pan_label(side), Vector2(dish.x, dish.y + 26), 96.0, 14, false))
	if state.stage == "puzzle":
		boards.append(sign_board(Rules.equation(state), Vector2(690, 592), 340.0, 15, true))
		boards.append(sign_board("三枚砝码 · 点一下挪地方", Vector2(310, 600), 248.0, 15, true))
	if state.stage == "weighing":
		boards.append(sign_board("制动已松 · 秤杆抬起来", Vector2(670, 596), 260.0, 15, true))
	if state.stage == "result":
		boards.append(sign_board("两盘差 %d 单位 · 这一单还不能走" % absi(Rules.difference(state)),
			Vector2(690, 596), 340.0, 15, true))
	if state.stage == "delivery":
		boards.append(sign_board("%s 签了收 · 砝码一枚没换" % Rules.order_name(state.order),
			Vector2(690, 596), 320.0, 15, true))
	if state.stage == "complete":
		var foot: Vector2 = souvenir_foot()
		boards.append(sign_board("迷你铜秤 · 两单的摆法", Vector2(foot.x, foot.y - 250), SOUVENIR_PLANK, 14, true))
		for index in range(Rules.ORDERS.size()):
			boards.append(sign_board(Rules.built_equation(state, index),
				Vector2(foot.x, foot.y - 220 + index * 30), SOUVENIR_PLANK, 13, true))
	return boards

# 车顶板上只写「哪一单、几单位、现在在哪」：完整说法留在热点文字与回执里。
func cart_caption(index: int) -> String:
	if index >= Rules.ORDERS.size(): return "交货车 · 已交 %d 单" % state.delivered
	var text := "%s · %d 单位" % [Rules.ORDER_NAMES[index], Rules.ORDERS[index]]
	if index < state.order: return text + " · 已交货"
	# 车顶板说的是「这一单的货此刻站在哪儿」：cargo_on_pan() 问的是整具秤，
	# 拿它来写后面那一辆车，就会对还压在车上的货说「已经上秤了」。
	if index == state.order and Rules.cargo_on_pan(state): return text + " · 上秤了"
	return text + " · 在车上"

func pan_label(side: int) -> String:
	return "货盘" if side == Rules.GOODS else "对面那盘"

func mark(text: String, rect: Rect2, size_px: int) -> void:
	var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	words(text, rect.position + Vector2((rect.size.x - wide) / 2.0, rect.size.y - 6), size_px)

func draw_text() -> void:
	if font == null: return
	for board in signs():
		if board["board"]: plaque(board["text"], board["rect"], board["size"])
		else: mark(board["text"], board["rect"], board["size"])

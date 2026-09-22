extends "res://scripts/market/kit_world.gd"
# MK18 万签守约兽的总货栈：码头、领航灯、三处街口接货板与采购台，全部取 kit-v1 拆件包与 dock 站位。
# 三阶段共用同一张台面：第一阶段在采购台上按包种一次选数量，第二阶段在三处街口摆货并留领航灯，
# 第三阶段把预留的货装进领航灯、把三张真实回执投进万签胸前的空信槽。
# 首领三态与灯船是已切好的源图脚点裁片，一律用 figure() 按脚点落位；柜台、船位与脚点都读 manifest。
# 布局只有一个原点组：packing（采购台）、boss_foot（万签）、lantern（领航灯）、两条船。
# 镜头在 puzzle 下放大 1.10 并偏移 (-64,-43)，下面每个可点框都按这条换算留在画面内。
const Rules = preload("res://scripts/market/mk18_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/grand-dock-clean-v1.png")
const WANQIAN_TAGS = preload("res://assets/runtime/market/characters/wanqian-v1/wanqian-tags.png")
const WANQIAN_LANTERNS = preload("res://assets/runtime/market/characters/wanqian-v1/wanqian-lanterns.png")
const LANTERN_SHIP = preload("res://assets/runtime/market/characters/wanqian-v1/lantern-ship.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const INK_WARN = Color("ffbe9e")
const INK_SEAL = Color("b8402f")
const PAPER = Color("fdf3d8")
const BOSS_SCALE = 0.52
const SHIP_SCALE = 0.62
const KOUKOU_SCALE = 0.5
const PACK_WIDTH = 54.0
const PACK_PITCH = 58.0
const PACK_FIRST = 16.0
const PACK_ROW_PITCH = 70.0
const PACK_ROW_LIFT = 70.0
const BOARDS = 3
const BOARD_PITCH = 165.0
const BOARD_FIRST = 4.0
# 接货板抬到 32：两行加减格（foot+76 起）在 1.10 镜头下正好停在底栏之上。
const BOARD_LIFT = 32.0
const TRAY_WIDTH = 150.0
const POOL_WIDTH = 130.0
const CELL = 58.0
const CELL_GAP = 8.0
const CHIP_OIL = 20.0
const CHIP_WICK = 20.0
const PAPER_WIDTH = 96.0
const PLAQUE_WIDTH = 152.0
const CAPTION_WIDTH = 140.0
# 三种封装各自的造型：A 大封包、B 中封包、C 只有油的圆封油壶——包种与含量在画面上是一回事。
const PACK_SPRITES = ["parcel_large", "parcel_medium", "oil_jug_round"]
# 散货：油用圆封油壶、芯用灯芯束，与 MK11/MK12 那两关的油芯是同一份钱货。
const UNIT_SPRITES = ["oil_jug_round", "wick_bundle"]

func ready_level() -> void:
	scene_id = "dock"; backdrop = BACKDROP

# ---- 落点：码头站位一律读 manifest 的 dock stations，其余坐标都由它们算出来 ----
func boss_foot() -> Vector2: return station("boss_foot")

func counter_foot() -> Vector2: return station("packing")

func lamp_foot() -> Vector2: return station("lantern") + Vector2(-46, 0)

func pool_foot() -> Vector2: return counter_foot() + Vector2(34, -179)

func crew_foot() -> Vector2: return boss_foot() + Vector2(218, 12)

# 万签从码头左端走上前来：arrival 站在原位左边，approach 一幕沿甲板走到 boss_foot。
func boss_anchor() -> Vector2:
	if state.stage == "arrival": return boss_foot() + Vector2(-260, 0)
	if state.stage == "approach": return (boss_foot() + Vector2(-260, 0)).lerp(boss_foot(), progress)
	return boss_foot()

# 三处街口接货板：桥头（更正信之前就已交完，只摆回执）、中街、西坡。
func board_foot(slot: int) -> Vector2:
	return counter_foot() + Vector2(BOARD_FIRST + slot * BOARD_PITCH, -BOARD_LIFT)

# 第一阶段：三种封装各占一行，行首对齐采购台，行内按库存铺包。
func pack_foot(kind: int, index: int) -> Vector2:
	return counter_foot() + Vector2(PACK_FIRST + index * PACK_PITCH,
		-PACK_ROW_LIFT + kind * PACK_ROW_PITCH)

func pack_caption_rect(kind: int) -> Rect2:
	return Rect2(counter_foot() + Vector2(-154, -96 + kind * PACK_ROW_PITCH), Vector2(CAPTION_WIDTH, 26))

func draft_rect() -> Rect2:
	return Rect2(counter_foot() + Vector2(-154, -160), Vector2(300, 26))

# 信件板：共同订单挂在左侧牌柱，两种安排与各自印记挂在万签右上方，开局就摆在那儿。
func order_foot() -> Vector2: return boss_foot() + Vector2(-467, -273)

func letter_foot(index: int) -> Vector2: return boss_foot() + Vector2(33 + index * 140.0, -273)

# ---- 热点矩形：接货 / 退回 / 交回执，全部 ≥48 逻辑像素 ----
func pack_rect(kind: int, index: int) -> Rect2:
	return target(pack_foot(kind, index), CELL, 29.0)

# 一格接货板配四个格子：油加、油减、芯加、芯减，纵向两行摆在托盘下面。
func put_rect(foot: Vector2, kind: int) -> Rect2:
	return Rect2(foot + Vector2(-CELL - CELL_GAP / 2.0 if kind == Rules.OIL else CELL_GAP / 2.0,
		CELL_GAP + 2.0), Vector2(CELL, CELL))

func back_rect(foot: Vector2, kind: int) -> Rect2:
	return Rect2(foot + Vector2(-CELL - CELL_GAP / 2.0 if kind == Rules.OIL else CELL_GAP / 2.0,
		CELL_GAP + 2.0 + CELL + CELL_GAP), Vector2(CELL, CELL))

# 第三阶段：托盘上的回执纸就是投递点。
func seal_rect(slot: int) -> Rect2:
	return Rect2(board_foot(slot) + Vector2(-62, CELL_GAP - 6.0), Vector2(124, 60))

func lamp_rect() -> Rect2: return target(lamp_foot() + Vector2(0, -58), 116.0, 128.0)

func lamp_cells_foot() -> Vector2: return lamp_foot() + Vector2(0, 10)

# 整单预览还没交货时可以撤回：撤回点落在货台上，与「还剩多少」是同一处。
func pool_rect() -> Rect2: return target(pool_foot(), 116.0, 100.0)

func chest_rect() -> Rect2: return Rect2(boss_anchor() + Vector2(-52, -126), Vector2(104, 52))

# ---- 阶段读数 ----
func phase() -> int: return Rules.phase_of(state)

func handed_out() -> bool: return state.handed != Rules.empty_alloc()

func boss_pose() -> Texture2D: return WANQIAN_TAGS if phase() == 1 else WANQIAN_LANTERNS

func lamp_lit() -> bool: return state.lamp == 1 or state.stage in ["lighting", "voyage", "complete"]

func sealed_count() -> int:
	if state.stage in ["lighting", "voyage", "complete"]: return 3
	if state.stage == "puzzle" and phase() == 3:
		var count := 0
		for one in state.sealed: count += one
		return count
	return 0

# 接货板此刻该摆的是哪一份：交出去的按 handed 复述，正在摆的按 alloc，桥头永远是自己那份。
func board_row(slot: int) -> Array:
	if slot == Rules.FIRST_STREET: return Rules.NEEDS_A[Rules.FIRST_STREET]
	var index = slot - 1
	if handed_out() or state.stage in ["delivering", "lighting", "voyage", "complete"]:
		return state.handed[index]
	if state.stage == "puzzle" and phase() == 2: return state.alloc[index]
	return [0, 0]

func lamp_row() -> Array:
	if state.lamp == 1 or state.stage in ["lighting", "voyage", "complete"]: return Rules.RESERVED
	if state.stage == "puzzle" and phase() == 2: return state.alloc[Rules.SLOTS - 1]
	if state.stage == "puzzle" and phase() == 3: return Rules.RESERVED
	return [0, 0]

# 灯船从万签背上的灯架展开：lighting 原地亮起，voyage 才滑到海面上。
func ship_foot() -> Vector2:
	var from = boss_foot() + Vector2(-10, -30)
	var to = station("boat_blue") + Vector2(-40, 40)
	if state.stage == "lighting": return from
	if state.stage == "voyage": return from.lerp(to, smoothstep(0.0, 1.0, progress))
	return to

func ship_alpha() -> float:
	if state.stage == "lighting": return clampf(progress * 1.6, 0.0, 1.0)
	if state.stage in ["voyage", "complete"]: return 1.0
	return 0.0

func boss_alpha() -> float:
	if state.stage == "lighting": return 1.0 - clampf((progress - 0.45) / 0.55, 0.0, 1.0)
	if state.stage == "voyage": return 0.0
	return 1.0

# ---- 绘制 ----
func draw_level() -> void:
	draw_harbour()
	draw_letters()
	draw_boss()
	draw_lamp()
	if state.stage in ["puzzle", "stocking", "clarify", "delivering"]:
		if state.stage == "puzzle" and phase() == 1: draw_counter()
		if phase() >= 2: draw_streets()
		if state.stage == "puzzle" and phase() == 2: draw_pool()
	draw_crew()
	draw_voyage()
	draw_captions()

func draw_harbour() -> void:
	# 两条运输船按 manifest 的船位落回码头；灯船启航那一幕它们退成背景。
	var dim = 0.55 if state.stage in ["voyage", "complete"] else 0.9
	kit("transport_boat_red", station("boat_red"), 150.0, dim)
	kit("transport_boat_blue", station("boat_blue"), 150.0, dim)

func draw_boss() -> void:
	var alpha = boss_alpha()
	if alpha > 0.0: figure(boss_pose(), boss_anchor(), BOSS_SCALE, alpha)
	if state.stage not in ["arrival", "approach"]:
		words("万签", boss_anchor() + Vector2(-24, -208), 16, INK_GOLD)
	draw_chest()

# 胸前一直转动的空信槽：收到几张真实回执就贴几张纸，三张齐了才合拢。
func draw_chest() -> void:
	if state.stage in ["arrival", "approach", "ready"]: return
	var slot = chest_rect()
	var count = sealed_count()
	for index in range(count):
		var at = slot.position + Vector2(3 + index * 34.0, 4.0)
		draw_rect(Rect2(at, Vector2(32, 44)), PAPER, true)
		draw_rect(Rect2(at, Vector2(32, 44)), Color("8f6420"), false, 2.0)
		words(Rules.LINES[index].substr(0, 2), at + Vector2(4, 38), 13, Color("8f3f2a"))
	if count < 3:
		var open = Rect2(slot.position + Vector2(3 + count * 34.0, 4.0), Vector2(32.0 + (2 - count) * 34.0, 44))
		draw_rect(open, Color(0.14, 0.09, 0.05, 0.62), true)
		words("空信槽 %d/3" % count, slot.position + Vector2(2, 72), 14)

func draw_lamp() -> void:
	var foot = lamp_foot()
	kit("navigation_lantern", foot, 112.0)
	if lamp_lit():
		socket(foot + Vector2(0, -76), Vector2(48, 42), 0.5 + 0.35 * pulse())
	if state.stage == "puzzle" and phase() == 2:
		draw_units(lamp_row(), foot + Vector2(6, -16), 1.0)
		for kind in range(2):
			cell(put_rect(lamp_cells_foot(), kind), kind, "+")
			cell(back_rect(lamp_cells_foot(), kind), kind, "-")
		plaque("领航灯 %d/%d·留 %d/%d" % [lamp_row()[Rules.OIL], lamp_row()[Rules.WICK],
			Rules.RESERVED[Rules.OIL], Rules.RESERVED[Rules.WICK]],
			Rect2(foot + Vector2(-140, -206), Vector2(180, 26)), 14,
			INK_GOLD if lamp_row() == Rules.RESERVED else INK_WARN)
	if state.stage == "puzzle" and phase() == 3 and state.lamp == 0:
		draw_units(Rules.RESERVED, foot + Vector2(6, -16), 0.95)

# 采购买回来的整包在第二阶段摊在货台上：允许拆开分配，但不再购买。
func draw_counter() -> void:
	for kind in range(Rules.KINDS):
		for index in range(Rules.STOCK[kind]):
			var foot = pack_foot(kind, index)
			var taken = index < state.order[kind]
			contact(foot, PACK_WIDTH * 0.42, 0.16 if taken else 0.07)
			kit(PACK_SPRITES[kind], foot, PACK_WIDTH, 1.0 if taken else 0.4)
			words(str(index + 1), foot + Vector2(-5, -PACK_WIDTH - 2), 12,
				INK_GOLD if taken else INK_LIGHT)
		plaque(Rules.pack_caption(kind), pack_caption_rect(kind), 14,
			INK_GOLD if state.order[kind] > 0 else INK_LIGHT)
	plaque(Rules.order_caption(state.order), draft_rect(), 15,
		INK_GOLD if Rules.purchase_ok(state.order) else INK_LIGHT)

# 三处街口：托盘上摆着玩家真正放过去的货，牌子上写当前数量与该街的需要。
func draw_streets() -> void:
	for slot in range(BOARDS):
		var foot = board_foot(slot)
		kit("receiving_tray", foot, TRAY_WIDTH)
		var row = board_row(slot)
		var need = Rules.needs(state.branch)[slot]
		draw_units(row, foot + Vector2(0, -26), 1.0)
		plaque("%s %d/%d·需 %d/%d" % [Rules.LINES[slot], row[Rules.OIL], row[Rules.WICK],
			need[Rules.OIL], need[Rules.WICK]],
			Rect2(foot + Vector2(-PLAQUE_WIDTH / 2.0, -120), Vector2(PLAQUE_WIDTH, 26)), 14,
			INK_GOLD if row == need else INK_WARN)
		if state.stage == "puzzle" and phase() == 2 and slot > Rules.FIRST_STREET:
			for kind in range(2):
				cell(put_rect(foot, kind), kind, "+")
				cell(back_rect(foot, kind), kind, "-")
		if phase() >= 3 or state.stage in ["delivering", "lighting", "voyage", "complete"]:
			draw_seal_paper(foot, slot)

# 货台上还剩多少：由 alloc 现算，画面上永远不会凭空多出一提油。
func draw_pool() -> void:
	var left = Rules.alloc_left(state.alloc)
	var foot = pool_foot()
	kit("receiving_tray", foot, POOL_WIDTH)
	draw_units(left, foot + Vector2(0, -24), 1.0)
	if state.preview == 1:
		draw_rect(Rect2(foot + Vector2(-24, -60), Vector2(48, 34)), PAPER, true)
		words("预览", foot + Vector2(-19, -36), 14, Color("8f3f2a"))
		plaque("整单预览中 · 点货台撤回", Rect2(foot + Vector2(-96, -146), Vector2(202, 26)), 14, INK_GOLD)
	else:
		plaque("货台还剩 %d/%d" % [left[Rules.OIL], left[Rules.WICK]],
			Rect2(foot + Vector2(-78, -116), Vector2(166, 26)), 14,
			INK_GOLD if left == [0, 0] else INK_LIGHT)

func draw_units(row: Array, foot: Vector2, alpha: float) -> void:
	var oil = grid(foot + Vector2(-48, 0), Vector2(15.0, -14.0), 4, row[Rules.OIL])
	for at in oil: kit(UNIT_SPRITES[Rules.OIL], at, CHIP_OIL, alpha)
	var wick = grid(foot + Vector2(18, 0), Vector2(17.0, -14.0), 3, row[Rules.WICK])
	for at in wick: kit(UNIT_SPRITES[Rules.WICK], at, CHIP_WICK, alpha)

func cell(rect: Rect2, kind: int, mark: String) -> void:
	var style = UIStyle.sign_style(); style.shadow_size = 0
	draw_style_box(style, rect)
	kit(UNIT_SPRITES[kind], rect.position + Vector2(rect.size.x * 0.36, rect.size.y - 10.0), 26.0, 0.95)
	words(mark, rect.position + Vector2(rect.size.x - 20, rect.size.y - 13), 22,
		INK_GOLD if mark == "+" else INK_WARN)

# 扣扣在码头边照着货单动手：第一阶段封箱、后两阶段搬货，请它提醒时才腾出一只手挥。
func draw_crew() -> void:
	if state.stage in ["voyage", "complete"]: return
	var happy = state.stage == "puzzle" and state.hint > 0
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, crew_foot(), KOUKOU_SCALE, 0.98)

func draw_seal_paper(foot: Vector2, slot: int) -> void:
	var paper = Rect2(foot + Vector2(-20, CELL_GAP - 2.0), Vector2(40, 46))
	draw_rect(paper, PAPER, true)
	draw_rect(paper, Color("8f6420"), false, 2.0)
	words("回执", paper.position + Vector2(7, 22), 12, Color("8f3f2a"))
	var sealed = slot
	if state.stage == "puzzle" and phase() == 3: sealed = state.sealed[slot]
	else: sealed = 1
	if sealed == 1:
		draw_circle(paper.position + Vector2(30, 34), 9, INK_SEAL)

# 信件板：共同订单（第一阶段）与两种安排（读信之后），印记只盖在实际那一张上。
func draw_letters() -> void:
	if state.stage in ["arrival", "approach", "ready", "stocking"] or (state.stage == "puzzle" and phase() == 1):
		draw_paper(order_foot(), "共同订单", order_lines(), false)
	if state.stage in ["clarify", "delivering", "lighting", "voyage", "complete"] \
		or (state.stage == "puzzle" and phase() >= 2):
		draw_paper(letter_foot(0), "安排甲 · 维持", branch_lines(0), stamped_in(0))
		draw_paper(letter_foot(1), "安排乙 · 更正", branch_lines(1), stamped_in(1))

# 读信那一幕才逐张落印；之后两张都摊着，只有本局那一张带着印记。
func stamped_in(branch: int) -> bool:
	if state.stage == "clarify": return state.beat > branch
	return true

func order_lines() -> Array:
	var lines = []
	for slot in range(4): lines.append(Rules.line_caption(Rules.NEEDS_A, slot))
	return lines

func branch_lines(branch: int) -> Array:
	var lines = []
	for slot in range(4): lines.append(Rules.line_caption(Rules.needs(branch), slot))
	return lines

func draw_paper(foot: Vector2, title: String, lines: Array, stamped: bool) -> void:
	kit("receipt_blank", foot, PAPER_WIDTH)
	var top = foot + Vector2(-PAPER_WIDTH / 2.0 + 9, -PAPER_WIDTH * 1.33 + 26)
	words(title, top, 13, INK_GOLD)
	for index in range(lines.size()):
		paper_words(str(lines[index]), top + Vector2(0, 19.0 * (index + 1)), 12)
	if stamped: stamp(foot)

# 信纸右下角那颗封蜡是原图里烤死的，第四行「领航灯 2/1」的尾巴正好压在它身上。
# 世界层的字一律是浅字加深描边，落在蓝蜡上就糊成一片；纸上反过来描——浅纸色光晕托着深墨字，
# 落在米色纸上看不见，压在蜡上就把字托出来。
func paper_words(text: String, at: Vector2, size_px: int) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, PAPER)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color("40291a"))

func stamp(foot: Vector2) -> void:
	var at = foot + Vector2(24, -26)
	draw_circle(at, 14, Color("b8402f", 0.92))
	words("本局", at + Vector2(-13, 5), 12, Color("fff0d1"))

# 第三阶段与结局：三张回执、亮起的领航灯与展开的灯船。
func draw_voyage() -> void:
	var alpha = ship_alpha()
	if alpha > 0.0: figure(LANTERN_SHIP, ship_foot(), SHIP_SCALE, alpha)
	if state.stage == "voyage" and progress > 0.45:
		socket(ship_foot() + Vector2(0, -96), Vector2(160, 62), 0.3 * (progress - 0.45) / 0.55)

func draw_captions() -> void:
	match state.stage:
		"stocking":
			plaque("桥头街先交货……更正信这时才送到", Rect2(392, 300, 300, 28), 15, INK_GOLD)
		"clarify":
			plaque("两封回信都在，印记只盖在实际那一张上", Rect2(372, 300, 340, 28), 15, INK_GOLD)
		"delivering":
			plaque("中街、西坡按这一单交货，领航灯留着不动", Rect2(362, 300, 350, 28), 15, INK_GOLD)
		"lighting":
			plaque("空信槽合拢，灯架亮起来", Rect2(402, 258, 280, 28), 15, INK_GOLD)
		"voyage":
			plaque("灯船展开：每一盏灯都有回信了", Rect2(392, 258, 300, 28), 15, INK_GOLD)
		"puzzle":
			if phase() == 3:
				plaque("先装领航灯，再把三张回执投进万签胸前", Rect2(342, 258, 350, 28), 15, INK_GOLD)
			elif phase() == 2:
				plaque("拆开分配：不再购买，领航灯那份留着", Rect2(342, 258, 350, 28), 15, INK_LIGHT)
			else:
				plaque("按包种一次选数量，整单一次提交", Rect2(342, 258, 300, 28), 15, INK_LIGHT)

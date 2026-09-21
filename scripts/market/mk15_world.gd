extends "res://scripts/market/kit_world.gd"
# MK15 铜果摊的街面：三块摊板上各贴一条本摊合同，前景柜台上摆着 12 颗铜果这一批货，
# 右侧摊口挂着那张「绕一圈，凭空多一颗」的招揽牌——绕成闭环之后它被拆下来，换成一串会绕圈的交换风铃。
# 底景、六个站位、铜果/绳盘/灯芯/铜铃拆件全部来自 art/market-kit-v1/manifest.json：
# 落点一律由 station() 加固定偏移推出，本文件不另立第二套摊位坐标。
# 兑换率与判断全在 Rules 里；这里只画玩家真的换过的那几堆货，画面上不出现「该点哪一块」的记号。
const Rules = preload("res://scripts/market/mk15_rules.gd")
const BACKDROP = preload("res://assets/source/market/lantern-street-stage-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 三条合同从左到右贴在街面三座摊位上；counter 摆这一批货，stall_right 挂招牌与风铃。
const STALLS = ["stall_midleft", "stall_middle", "stall_midright"]
const GOOD_WIDTH = [26.0, 30.0, 28.0]
const SAMPLE_WIDTH = [34.0, 40.0, 36.0]
# 三条合同的命中区上下错开：摊板（样品+合同牌）在上，「整批」牌压在柜台边缘之上，
# 台面三堆货的点击区再从整批牌下面起头，任何两块热点都不互相盖住。
const BOARD_TARGET = 112.0
const BOARD_LIFT = 60.0
const NAME_PLAQUE = 96.0
const RATE_PLAQUE = 110.0
const BULK_TARGET = 76.0
const BULK_DROP = 78.0
const BULK_FOOT = 116.0
const PILE_TARGET = [120.0, 130.0, 96.0]
const PILE_LIFT = [82.0, 86.0, 86.0]
const PILE_LABEL = 130.0
const FALL_TIME = 0.34
const HOP_LIFT = 44.0
const CHIME_RADIUS = 52.0
const RING_STEPS = 24
const SIGN_SIZE = Vector2(234, 34)
const SIGN_DROP = 150.0
# 柜面下方那一排短牌的落点：y 596 已经在柜台台裙之外，不会再压到台面上的货。
# 左边留出 300 宽的缺口给扣扣站脚，四块牌依次往右排，最右一块落在 1206（放大 1.10 倍后 1262）。
const ROW_Y = 596
const ROWS = [300, 546, 792, 992]
const ROW_W = [236, 236, 190, 214]

var _piles: Array = []
var seen_stock := [-1, -1, -1]
var seen_used := [-1, -1, -1]
var hops: Array = []

func ready_level() -> void:
	scene_id = "street"; backdrop = BACKDROP

# ---- 落点：全部由 manifest 的 street 站位推出 ----
func stall_foot(line: int) -> Vector2: return station(STALLS[line]) + Vector2(0, 6)
func board_foot(line: int) -> Vector2: return station(STALLS[line]) + Vector2(0, -14)
func board_rect(line: int) -> Rect2: return target(board_foot(line), BOARD_TARGET, BOARD_LIFT)
func name_rect(line: int) -> Rect2:
	var at = station(STALLS[line])
	return Rect2(at.x - NAME_PLAQUE / 2.0, at.y - 70, NAME_PLAQUE, 26)
func rate_rect(line: int) -> Rect2:
	var at = station(STALLS[line])
	return Rect2(at.x - RATE_PLAQUE / 2.0, at.y + 8, RATE_PLAQUE, 28)
func bulk_rect(line: int) -> Rect2:
	var at = station(STALLS[line])
	return Rect2(at.x - BULK_TARGET / 2.0, at.y + BULK_DROP, BULK_TARGET, 24)
func bulk_target(line: int) -> Rect2:
	return target(Vector2(station(STALLS[line]).x, station(STALLS[line]).y + BULK_FOOT),
		BULK_TARGET, BULK_TARGET)
func counter_at(dx: float, dy: float) -> Vector2: return station("counter") + Vector2(dx, dy)
# 扣扣站在柜台的左角上：她的立绘在 0.5 倍下有 164 逻辑像素宽，
# 再往右半步就会被下面那一排短牌压住身子，所以退到 x 210，让牌从 x 300 起头。
func koukou_foot() -> Vector2: return counter_at(-430, 62)
func sign_rect() -> Rect2:
	return Rect2(station("stall_right") + Vector2(-SIGN_SIZE.x / 2.0, -96), SIGN_SIZE)
func sign_target() -> Rect2:
	# 热点跟着牌沿走：`target()` 只给正方框，120 见方比 234 宽的牌左右各短 57 像素，
	# 玩家照着牌的两头点下去什么也不会发生（提示也不弹）。高度按 48 的下限抬到 52。
	var rect = sign_rect()
	return Rect2(rect.position.x, rect.position.y - 8, rect.size.x, 52.0)
func chime_foot() -> Vector2: return station("stall_right") + Vector2(0, -132)
# 拆穿之后那句真话挂在谎话原来那块牌上：同一位置、同一尺寸，玩家不必在两处之间找对应。
# 旧落点 (955,300,220,30) 正压在风铃那一圈里——环脚在 stall_right 上方 132（y 303），
# 环半径 52、纵向压扁 0.42（y 281..325），铃在 y 319，三件货的脚点低到 y 337。
func honest_rect() -> Rect2: return sign_rect()
func chime_rect() -> Rect2: return Rect2(940, 452, 250, 28)
# 回执贴在左边空出来的街面上：不与白板（338 起）、三条合同牌（411 起）与底部短牌（596 起）重叠。
func receipt_rect() -> Rect2: return Rect2(24, 196, 360, 232)

# 这一批货的三堆排布是算术，不是手抄坐标：12 果 6×2、18 线 6×3、9 芯 3×3。
func pile_spots(kind: int) -> Array:
	if _piles.is_empty():
		var counter = station("counter")
		_piles = [grid(counter + Vector2(-250, 8), Vector2(32, -30), 6, Rules.MAX_PILE[Rules.FRUIT]),
			grid(counter + Vector2(-60, 8), Vector2(32, -28), 6, Rules.MAX_PILE[Rules.THREAD]),
			grid(counter + Vector2(215, 8), Vector2(30, -28), 3, Rules.MAX_PILE[Rules.CORE])]
	return _piles[kind]

func pile_foot(kind: int, slot: int) -> Vector2: return pile_spots(kind)[slot]
func pile_bottom(kind: int) -> float: return pile_spots(kind)[0].y
func pile_mid(kind: int) -> float:
	var spots = pile_spots(kind)
	return (spots[0].x + spots[spots.size() - 1].x) / 2.0
func pile_rect(kind: int) -> Rect2:
	return target(Vector2(pile_mid(kind), pile_bottom(kind)), PILE_TARGET[kind], PILE_LIFT[kind])
func pile_label(kind: int) -> Rect2:
	return Rect2(pile_mid(kind) - PILE_LABEL / 2.0, pile_bottom(kind) + 14, PILE_LABEL, 26)

# ---- 兑换演出：新上台的那几件货从贴着合同的摊板上桌；撤销与重摆只是退回，不演第二遍 ----
func track_changes() -> void:
	var items = Rules.stock(state)
	if seen_stock[0] < 0:
		seen_stock = items; seen_used = state.used.duplicate(true); return
	var source := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var arrived := [false, false, false]
	for line in range(Rules.KINDS):
		if state.used[line] > seen_used[line]:
			var spec: Array = Rules.LINES[line]
			arrived[spec[2]] = true
			source[spec[2]] = board_foot(line)
	for kind in range(Rules.KINDS):
		if items[kind] > seen_stock[kind]:
			for slot in range(seen_stock[kind], items[kind]):
				hops.append({"kind": kind, "slot": slot, "at": clock,
					"from": source[kind] if arrived[kind] else pile_foot(kind, slot) - Vector2(0, 52)})
	seen_stock = items; seen_used = state.used.duplicate(true)

func prune_hops() -> void:
	var kept: Array = []
	for hop in hops:
		if (clock - hop["at"]) / FALL_TIME < 1.0: kept.append(hop)
	hops = kept

func hop_at(kind: int, slot: int) -> Dictionary:
	for hop in hops:
		if hop["kind"] == kind and hop["slot"] == slot: return hop
	return {}

# ---- 环：柜面 → 合同一 → 合同二 → 合同三 → 回到柜面 ----
func ring_nodes() -> Array:
	return [counter_at(0, -52), board_foot(0), board_foot(1), board_foot(2)]

func ring_point(index: float) -> Vector2:
	var nodes = ring_nodes()
	var step := int(index * nodes.size()) % nodes.size()
	return nodes[step].lerp(nodes[(step + 1) % nodes.size()], fmod(index * nodes.size(), 1.0))

# ---- 绘制 ----
func draw_level() -> void:
	if not state.has("used"): return
	track_changes(); prune_hops()
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, koukou_foot(), 0.5)
	draw_boards()
	draw_piles()
	draw_ring()
	draw_right_stall()
	draw_signs()

# 摊板上左边是这一条要付出的货、右边是换回来的货，中间一支箭：样品摆在这里，不判断该点哪一块。
func draw_boards() -> void:
	for line in range(Rules.KINDS):
		var spec: Array = Rules.LINES[line]
		var at = stall_foot(line)
		draw_sample(at + Vector2(-46, -4), spec[0], spec[1])
		draw_sample(at + Vector2(46, -10), spec[2], spec[3])
		draw_arrow(at + Vector2(-16, -26), at + Vector2(20, -26))
		if state.stage == "puzzle" and Rules.affordable(state, line) > 0:
			socket(at + Vector2(0, -22), Vector2(52, 14), 0.22 + 0.14 * pulse())

func draw_sample(foot: Vector2, kind: int, count: int) -> void:
	for step in range(count):
		var at = foot + Vector2((step - float(count - 1) / 2.0) * 26.0, 0)
		contact(at, GOOD_WIDTH[kind] * 0.44, 0.22)
		kit(Rules.KIT_GOODS[kind], at, GOOD_WIDTH[kind])

func draw_arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, Color("ffe297", 0.75), 3.0)
	draw_line(to, to + Vector2(-9, -6), Color("ffe297", 0.75), 3.0)
	draw_line(to, to + Vector2(-9, 6), Color("ffe297", 0.75), 3.0)

# 台面上的三堆货就是玩家换出来的那一批：颗数、卷数、根数都数得出来，多不出第 13 颗。
func draw_piles() -> void:
	var items = Rules.stock(state)
	for kind in range(Rules.KINDS):
		for slot in range(items[kind]):
			var land = pile_foot(kind, slot)
			var foot = land
			var alpha := 1.0
			var hop = hop_at(kind, slot)
			if not hop.is_empty():
				var t = clampf((clock - hop["at"]) / FALL_TIME, 0.0, 1.0)
				foot = hop["from"].lerp(land, t) - Vector2(0, sin(t * PI) * HOP_LIFT)
				alpha = 0.55 + 0.45 * t
			contact(land, GOOD_WIDTH[kind] * 0.44, 0.22 * alpha)
			kit(Rules.KIT_GOODS[kind], foot, GOOD_WIDTH[kind], alpha)

# 绕圈演出：四条边依次亮起来，一件货沿着玩家自己走过的那条环跑一圈，最后落回柜面那堆果。
func draw_ring() -> void:
	if state.stage != "ringing": return
	var nodes = ring_nodes()
	draw_polyline(nodes + [nodes[0]], Color("8f6420", 0.45), 5.0, true)
	var head = clampf(progress, 0.0, 0.999)
	var span = 1.0 / nodes.size()
	for step in range(nodes.size()):
		var from: Vector2 = nodes[step]
		var part = clampf((head - step * span) / span, 0.0, 1.0)
		if part > 0.0:
			draw_line(from, from.lerp(nodes[(step + 1) % nodes.size()], part), Color("ffe297", 0.9), 4.0)
	var at = ring_point(head)
	var riding := Rules.FRUIT if head < 0.25 else (Rules.THREAD if head < 0.5 else (Rules.CORE if head < 0.75 else Rules.FRUIT))
	kit(Rules.KIT_GOODS[riding], at + Vector2(0, -18 * sin(head * PI * 4.0)), SAMPLE_WIDTH[riding], 0.95)
	socket(at, Vector2(26, 12), 0.5 + 0.4 * pulse(6.0))

# 右侧摊口：牌在的时候是那句谎，绕成闭环之后它落下去，换成会绕圈的交换风铃。
func draw_right_stall() -> void:
	var foot = station("stall_right")
	draw_line(foot + Vector2(0, -150), foot + Vector2(0, -86), Color("8f6420"), 4.0)
	match state.stage:
		"delivery":
			var drop = smoothstep(0.0, 0.4, progress) * SIGN_DROP
			if drop < SIGN_DROP:
				plaque(Rules.sign_caption(), Rect2(sign_rect().position + Vector2(0, drop), SIGN_SIZE), 17,
					Color(1.0, 0.84, 0.63, 1.0 - drop / SIGN_DROP))
			if progress > 0.35: hang_chime(smoothstep(0.35, 0.75, progress))
		"complete":
			hang_chime(1.0)
		_:
			plaque(Rules.sign_caption(), sign_rect(), 17, Color("ffd7a1"))

func hang_chime(strength: float) -> void:
	var at = chime_foot()
	var spin = clock * 0.8
	var pts := PackedVector2Array()
	for step in range(RING_STEPS + 1):
		var angle = spin + TAU * step / RING_STEPS
		pts.append(at + Vector2(cos(angle) * CHIME_RADIUS, sin(angle) * CHIME_RADIUS * 0.42))
	draw_polyline(pts, Color("8f6420", 0.9 * strength), 4.0, true)
	draw_polyline(pts, Color("ffe297", 0.55 * strength), 2.0, true)
	kit("brass_bell", at + Vector2(0, 16), 34.0, strength)
	for kind in range(Rules.KINDS):
		var angle = spin + TAU * kind / Rules.KINDS
		var foot = at + Vector2(cos(angle) * CHIME_RADIUS, sin(angle) * CHIME_RADIUS * 0.42)
		kit(Rules.KIT_GOODS[kind], foot + Vector2(0, 12), GOOD_WIDTH[kind] * 0.8, strength)

# 摊板与柜面文字集中在这里，先被无头检查逐条量过宽度：
# 汉字在 Godot 里是一个不断词，plaque 又不会换行，超框就会画到旁边的货上。
func signs() -> Array:
	var boards = []
	if state.stage != "arrival":
		for line in range(Rules.KINDS):
			boards.append({"text": Rules.name_caption(line), "rect": name_rect(line), "size": 16})
			boards.append({"text": Rules.rate_caption(line), "rect": rate_rect(line), "size": 17})
			if state.stage == "puzzle":
				boards.append({"text": Rules.bulk_caption(state, line), "rect": bulk_rect(line), "size": 15})
	boards.append({"text": Rules.ruler_caption(), "rect": Rect2(ROWS[0], ROW_Y, ROW_W[0], 26), "size": 15})
	boards.append({"text": Rules.total_caption(state), "rect": Rect2(ROWS[1], ROW_Y, ROW_W[1], 26), "size": 15})
	boards.append({"text": Rules.ring_caption(state), "rect": Rect2(ROWS[2], ROW_Y, ROW_W[2], 26), "size": 15})
	boards.append({"text": Rules.local_caption(), "rect": Rect2(ROWS[3], ROW_Y, ROW_W[3], 26), "size": 15})
	for kind in range(Rules.KINDS):
		boards.append({"text": Rules.pile_caption(kind, Rules.pile(state, kind)),
			"rect": pile_label(kind), "size": 15})
	if state.stage == "complete":
		boards.append({"text": Rules.honest_caption(), "rect": honest_rect(), "size": 17})
		boards.append({"text": Rules.chime_caption(), "rect": chime_rect(), "size": 15})
	return boards

func draw_signs() -> void:
	for board in signs():
		plaque(board["text"], board["rect"], board["size"])

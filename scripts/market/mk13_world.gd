extends "res://scripts/market/kit_world.gd"
# MK13 育苗铺的补边布柜面：左柜两包 5 段、中柜三包 3 段，柜头立着一把 11 格的样边尺。
# 货是实物库存：拿起来就离开柜面（柜上只留一个淡影），摊到样边尺上按段数一格一格压过去；
# 退回柜面则反过来。围巾始终在扣扣脖子上，补好的边只在交货之后一段一段出现在她的围巾下沿。
# 柜面不判分：样边尺只如实数段数，够不够要到「交给扣扣补边」之后才知道。
const Rules = preload("res://scripts/market/mk13_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/nursery-exchange-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const FIGURE_SCALE = 0.8
const FIVE_PITCH = 84.0
const THREE_PITCH = 62.0
const BOLT_WIDTH = {5: 80.0, 3: 58.0}
const BOLT_RATIO = 280.0 / 383.0
const SLOT_PITCH = 26.0
const SLOT_WIDTH = 22.0
const SLOT_HEIGHT = 22.0
const SLOT_DROP = 12.0
const BOARD_SIDE = 152.0
const BOARD_TOP = 74.0
const RUN_LIFT = 46.0
const RUN_HEIGHT = 52.0
const GHOST_ALPHA = 0.15
const MOVE_TIME = 0.3
# 两种整包各认一种补边布颜色：围巾上的边能一段一段对回玩家真正拿的那几包。
const PATCH = {5: Color("c9662f"), 3: Color("d9a13c")}
# 围巾下沿在两张角色原图里的位置（源图像素、脚点锚定），用来把边画在真正的边上。
const SCARF_HEM = {"tie": Rect2(150, 163, 86, 13), "waving": Rect2(138, 159, 96, 13)}
var seen_flag = [0, 0, 0, 0, 0]
var seen_at = [-100.0, -100.0, -100.0, -100.0, -100.0]

func ready_level() -> void:
	scene_id = "nursery"; backdrop = BACKDROP

# ---- 落点：柜台一律读 nursery 的 station，格距是算术，不写死坐标 ----
func shelf_foot(id: int) -> Vector2:
	if id < 2: return station("counter_left") + Vector2((id * 2 - 1) * FIVE_PITCH / 2.0, 0)
	return station("counter_middle") + Vector2((id - 3) * THREE_PITCH, 0)

func stock_rect(id: int) -> Rect2:
	var size = 78.0 if Rules.segs(id) == Rules.FIVE else 58.0
	return target(shelf_foot(id), size, size * 0.8)

func board_centre() -> Vector2: return station("counter_right") + Vector2(18, 0)

# 尺框单独成一个矩形：审计据此检查它没有压住扣扣的围巾，也不越出画面。
func board_frame() -> Rect2:
	return Rect2(board_centre() + Vector2(-BOARD_SIDE, -BOARD_TOP), Vector2(BOARD_SIDE * 2, BOARD_TOP + 6))

func slot_foot(index: int) -> Vector2:
	return board_centre() + Vector2((index - (Rules.NEED - 1) / 2.0) * SLOT_PITCH, -SLOT_DROP)

func cell_rect(index: int) -> Rect2:
	var at = slot_foot(index)
	return Rect2(at - Vector2(SLOT_WIDTH / 2.0, SLOT_HEIGHT), Vector2(SLOT_WIDTH, SLOT_HEIGHT))

# 一截摊开的补边布：宽按段数算出来，高始终留够 48 逻辑像素。
func run_rect(state: Dictionary, slot: int) -> Rect2:
	var first = slot_foot(Rules.run_start(state, slot))
	var last = slot_foot(Rules.run_start(state, slot) + Rules.run_segs(state, slot) - 1)
	return Rect2(first.x - SLOT_WIDTH / 2.0 - 2, first.y - RUN_LIFT, last.x - first.x + SLOT_WIDTH + 4, RUN_HEIGHT)

func scarf_hem(texture: Texture2D) -> Rect2:
	var box: Rect2 = SCARF_HEM["tie"] if texture == KOUKOU_TIE else SCARF_HEM["waving"]
	var foot = station("resident")
	var top_left = foot + Vector2(box.position.x - texture.get_width() / 2.0, box.position.y - texture.get_height()) * FIGURE_SCALE
	return Rect2(top_left, box.size * FIGURE_SCALE)

# ---- 换手计时：本关不占用宿主的落地锁，用世界自己的时钟 ----
func track_changes() -> void:
	for id in range(Rules.packages()):
		var flag = 1 if Rules.in_hand(state, id) else 0
		if seen_flag[id] != flag:
			seen_at[id] = clock; seen_flag[id] = flag

func slide(id: int) -> float:
	return clampf((clock - seen_at[id]) / MOVE_TIME, 0.0, 1.0)

# 缝到围巾上的段数：交货演出里随 progress 一段一段长出来。
func sewn() -> int:
	if state.stage == "delivery": return mini(Rules.NEED, int(progress * float(Rules.NEED + 1)))
	if state.stage in ["story", "complete"]: return Rules.NEED
	return 0

# 还压在样边尺上的段数：缝走一格，尺上就空一格。
func laid() -> int:
	if state.stage in ["story", "complete"]: return 0
	return maxi(0, Rules.total(state) - sewn())

# 样边尺/围巾上第 index 段来自哪一包：按拿起来的先后排，两处共用同一个排法。
func cell_owner(index: int) -> int:
	var at := 0
	for slot in range(state.hand.size()):
		var count: int = Rules.run_segs(state, slot)
		if index < at + count: return Rules.run_package(state, slot)
		at += count
	return -1

# ---- 绘制 ----
func draw_level() -> void:
	track_changes()
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.62)
	var texture = KOUKOU_WAVE if happy else KOUKOU_TIE
	figure(texture, station("resident"), FIGURE_SCALE)
	draw_scarf(texture)
	if state.stage != "arrival": draw_board()
	draw_stock()
	draw_signs()

func draw_scarf(texture: Texture2D) -> void:
	var hem = scarf_hem(texture)
	var pitch = hem.size.x / float(Rules.NEED)
	var patch = hem.size.y - 5.0
	var done = sewn()
	if done < Rules.NEED:
		# 磨开的边：围巾下沿挂着几根松掉的纬线，缺几段就露几格暗口
		for step in range(Rules.NEED - done):
			var gap = hem.position + Vector2(pitch * (step + done), patch)
			draw_rect(Rect2(gap, Vector2(maxf(1.0, pitch - 1.0), 5)), Color(0.11, 0.08, 0.06, 0.6))
		for step in range(4):
			var at = hem.position + Vector2(pitch * (1.5 + step * 2.6), hem.size.y)
			draw_line(at, at + Vector2(1, 4 + (step % 3)), Color("e6d9b6", 0.8), 1.0)
	for index in range(done):
		var owner = cell_owner(index)
		if owner < 0: continue
		var colour: Color = PATCH[Rules.segs(owner)]
		var at = hem.position + Vector2(pitch * index, patch)
		draw_rect(Rect2(at, Vector2(maxf(1.0, pitch - 1.0), 5)), colour)
		draw_rect(Rect2(at, Vector2(maxf(1.0, pitch - 1.0), 5)), colour.lightened(0.4), false, 1.0)
	if done == Rules.NEED and state.worn == 1:
		socket(hem.position + Vector2(hem.size.x / 2.0, 3), Vector2(34, 13), 0.26 + 0.18 * pulse())

func draw_board() -> void:
	var frame = board_frame()
	draw_rect(frame, Color(0.23, 0.15, 0.09, 0.96))
	draw_rect(frame.grow(-7), Color(0.33, 0.23, 0.13, 0.96))
	draw_rect(frame, Color(0.56, 0.42, 0.24), false, 3.0)
	for index in range(Rules.NEED):
		var rect = cell_rect(index)
		var owner = cell_owner(index) if index < laid() else -1
		if owner >= 0:
			var colour: Color = PATCH[Rules.segs(owner)]
			var tint = colour if slide(owner) > 0.99 else colour.lerp(Color(0.19, 0.13, 0.08), 1.0 - slide(owner))
			draw_rect(rect.grow(-1.0), tint)
			draw_rect(rect.grow(-1.0), colour.lightened(0.34), false, 1.0)
			draw_line(rect.position + Vector2(2, rect.size.y - 3), rect.position + Vector2(rect.size.x - 2, 3),
				Color("fff0d1", 0.45), 1.0)
		else:
			draw_rect(rect, Color(0.08, 0.06, 0.05, 0.88))
			draw_rect(rect, Color(0.44, 0.33, 0.20, 0.9), false, 1.0)
			words(str(index + 1), rect.position + Vector2(5, 5), 10, Color("9c8461"))
	for slot in range(state.hand.size()):
		if Rules.run_start(state, slot) >= laid(): continue
		var count: int = Rules.run_segs(state, slot)
		var mid = slot_foot(Rules.run_start(state, slot) + int(count / 2.0))
		words("%d 段" % count, mid + Vector2(-14, -34), 14, PATCH[count])

func draw_stock() -> void:
	for id in range(Rules.packages()):
		var width: float = BOLT_WIDTH[Rules.segs(id)]
		var held = Rules.in_hand(state, id)
		var foot = shelf_foot(id)
		var alpha = lerpf(1.0, GHOST_ALPHA, slide(id)) if held else lerpf(GHOST_ALPHA, 1.0, slide(id))
		if not held: contact(foot, width * 0.40, 0.22)
		kit("cloth_bolt", foot, width, alpha)
		words("%d 段" % Rules.segs(id), foot + Vector2(-13, -width * BOLT_RATIO - 8), 14,
			INK_GOLD if not held else Color("8f7a5a"))
	if state.stage == "puzzle" and state.hand.is_empty():
		var beat = pulse()
		for id in range(Rules.packages()):
			socket(shelf_foot(id) + Vector2(0, -20), Vector2(40, 11), 0.2 + 0.16 * beat)

func draw_signs() -> void:
	plaque(Rules.shelf_caption(state, Rules.FIVE), shelf_plaque(Rules.FIVE), 15)
	plaque(Rules.shelf_caption(state, Rules.THREE), shelf_plaque(Rules.THREE), 15)
	if state.stage == "puzzle":
		plaque(Rules.gauge_caption(state), board_plaque(), 15, INK_GOLD if Rules.total(state) > 0 else INK_LIGHT)
		plaque("整包不能剪开 · 一次最多 3 包", rule_plaque(), 14)
	if state.stage == "delivery":
		plaque("扣扣在缝边 · 已缝 %d 段" % sewn(), board_plaque(), 15, INK_GOLD)
	if state.stage in ["story", "complete"]:
		plaque("围巾的边 · %d 段全缝上了" % Rules.NEED, board_plaque(), 15, INK_GOLD)
		plaque("补好的边 · %s" % ("戴在外面" if state.worn == 1 else "藏在领子里"), look_plaque(), 14,
			INK_GOLD if state.worn == 1 else INK_LIGHT)

func shelf_plaque(size: int) -> Rect2:
	return Rect2(296, 502, 226, 26) if size == Rules.FIVE else Rect2(534, 502, 214, 26)

func board_plaque() -> Rect2: return Rect2(756, 508, 286, 26)

# 柜规牌与外观牌各占一条：审计据此量字数，也据此确认它们没有叠在一起。
func rule_plaque() -> Rect2: return Rect2(534, 532, 214, 24)
func look_plaque() -> Rect2: return Rect2(756, 538, 214, 24)

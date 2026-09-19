extends "res://scripts/market/kit_world.gd"
# MK03 育苗铺查货台：一具货栈铜秤、两份可叠合的称量记录、两排封箱重签，全部来自 kit-v1 拆件包。
# 秤在挂签过程中始终锁着（制动），读数只在提交后的复秤里出现；柜面文字全部由 Rules 统一给出，
# 因此画面无论玩家挂到哪一枚，公开记录的说法都不会变——判分只发生在「挂签复秤」之后。
const Rules = preload("res://scripts/market/mk03_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/nursery-exchange-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 三件秤构件共用同一个缩放系数（manifest 的组装约定），不各自套 suggested_width 后强行对接。
const SCALE_FACTOR = 0.36
const CARD_WIDTH = 100.0
const CRATE_WIDTH = 26.0
const WEIGHT_WIDTH = 30.0
const TAG_SLOT = 52.0
const TAG_PITCH = 56.0
const TAG_ROW_LIFT = 93.0
const FALL_TIME = 0.28
const FOLD_TIME = 0.34
# 每类封箱认得的重签造型固定：红箱用阶梯砝码、蓝箱用六角砝码，挂上后与签架上的是同一枚。
const TAG_SPRITE = ["weight_stepped", "weight_hex"]
# 记录纸内部按纸底脚点相对排布：纸宽 100 时三只封箱正好排满一行，蓝蜡封在右下不被压住。
const CARD_LABEL_Y = -124.0
const CARD_CRATE_Y = -52.0
const CARD_TOTAL_Y = -34.0
var tag_seen = [-1, -1]
var tag_at = [-100.0, -100.0]
var fold_seen = -1
var fold_at = -100.0

func ready_level() -> void:
	scene_id = "nursery"; backdrop = BACKDROP

# ---- 落点：柜台位置一律读 nursery 的 station，manifest 仍是唯一坐标来源 ----
func record_foot(index: int) -> Vector2:
	return station("counter_left") if index == 0 else station("counter_right")

func scale_foot() -> Vector2: return station("counter_middle")

func tag_foot(kind: int, tag: int) -> Vector2:
	var middle := (Rules.TAG_MIN + Rules.TAG_MAX) / 2.0
	return record_foot(kind) + Vector2((tag - middle) * TAG_PITCH, TAG_ROW_LIFT)

func tag_rect(kind: int, tag: int) -> Rect2:
	return target(tag_foot(kind, tag), TAG_SLOT, TAG_SLOT / 2.0)

func card_rect(index: int) -> Rect2:
	return target(record_foot(index), 124.0, 150.0)

# 叠好之后两张纸一起成为热点：再点一下就分开重摆。
func stack_rect() -> Rect2:
	return target(record_foot(0) + Vector2(8, -26), 150.0, 176.0)

func crate_rect(kind: int) -> Rect2:
	return target(pan_cargo(kind) + Vector2(0, -12), 62.0, 50.0)

# ---- 铜秤组装：梁绕 pivot 旋转，盘只跟着梁端平移、自身保持水平 ----
func part_width(id: String, factor: float) -> float:
	return float(atlases[id].get_width()) * factor

func attach(id: String, name: String, foot: Vector2, factor: float) -> Vector2:
	var item: Dictionary = parts[id]
	var point: Array = item.attachments_px[name]
	return foot + Vector2(point[0] - item.anchor_px[0], point[1] - item.anchor_px[1]) * factor

func beam_pivot(factor: float) -> Vector2:
	return attach("scale_stand", "pivot", scale_foot(), factor)

func beam_hook(pivot: Vector2, side: int, factor: float, angle: float) -> Vector2:
	var item: Dictionary = parts["scale_beam"]
	var point: Array = item.attachments_px["left_hook" if side == 0 else "right_hook"]
	var local = Vector2(point[0] - item.anchor_px[0], point[1] - item.anchor_px[1]) * factor
	return pivot + local.rotated(angle)

func pan_cargo(side: int) -> Vector2:
	var hook = beam_hook(beam_pivot(SCALE_FACTOR), side, SCALE_FACTOR, 0.0)
	return attach("scale_pan", "cargo", hook, SCALE_FACTOR)

# 只有复秤那一刻梁才会摆：先向砝码一侧偏，再阻尼回到水平。
func braked() -> bool: return state.stage != "reweigh"

func beam_angle() -> float:
	if braked(): return 0.0
	var phase = fmod(progress * 2.0, 1.0)
	return 0.13 * cos(phase * PI * 2.5) * (1.0 - phase)

# ---- 下落与叠合动画 ----
# 宿主的 land_place 在 begin_land 里看不到刚提交的状态（那时 world.state 仍是上一份），
# 所以本关的下落改用世界自己的时钟计时，不去占用宿主的落地锁。
func track_changes() -> void:
	for kind in range(2):
		var value: int = Rules.hung(state, kind)
		if tag_seen[kind] != value: tag_at[kind] = clock; tag_seen[kind] = value
	if fold_seen != state.stacked: fold_at = clock; fold_seen = state.stacked

func rise(kind: int) -> float:
	return clampf(1.0 - (clock - tag_at[kind]) / FALL_TIME, 0.0, 1.0)

func fold_progress() -> float:
	return clampf((clock - fold_at) / FOLD_TIME, 0.0, 1.0)

func fold_foot() -> Vector2:
	var from = record_foot(1)
	var to = record_foot(0) + Vector2(16, -54)
	return from.lerp(to, fold_progress()) if Rules.folded(state) else to.lerp(from, fold_progress())

# ---- 绘制 ----
func draw_level() -> void:
	track_changes()
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, station("resident"), 0.5)
	# 查完货就把签架与记录纸收进回执：结幕只剩秤、两只样本箱与找到的原单。
	if state.stage not in ["arrival", "approach", "complete"]:
		draw_records()
		if state.stage == "puzzle": draw_racks()
	draw_scale()
	draw_signs()

func draw_records() -> void:
	draw_card(0, record_foot(0))
	draw_card(1, fold_foot())
	if Rules.folded(state): draw_difference(record_foot(1))

func card_group(index: int) -> Array:
	var record: Array = Rules.RECORDS[index]
	var group = []
	for step in range(record[0]): group.append(Rules.RED)
	for step in range(record[1]): group.append(Rules.BLUE)
	return group

# 消去的是两份记录里都出现的那一组：各取前 CANCELLED 只，剩下的那一只才是差量。
func cancelled_slots(index: int) -> Array:
	var group = card_group(index)
	var struck = []
	var taken = [0, 0]
	for step in range(group.size()):
		var kind: int = group[step]
		if taken[kind] < Rules.CANCELLED[kind]:
			struck.append(step); taken[kind] += 1
	return struck

func draw_card(index: int, foot: Vector2) -> void:
	kit("receipt_blank", foot, CARD_WIDTH)
	words("记录" + ("一" if index == 0 else "二"), foot + Vector2(-40, CARD_LABEL_Y), 16)
	var group = card_group(index)
	var pitch = CRATE_WIDTH + 2.0
	var first = foot + Vector2(-pitch * (group.size() - 1) / 2.0, CARD_CRATE_Y)
	var struck = cancelled_slots(index) if Rules.folded(state) else []
	for step in range(group.size()):
		var at = first + Vector2(pitch * step, 0)
		var dimmed = step in struck
		if dimmed: draw_line(at + Vector2(-15, -13), at + Vector2(15, -1), Color("b8402f", 0.9), 3.0)
		contact(at, CRATE_WIDTH * 0.42, 0.1 if dimmed else 0.24)
		kit("crate_red" if group[step] == Rules.RED else "crate_blue", at, CRATE_WIDTH, 0.32 if dimmed else 1.0)
	words("%d 斤" % Rules.published(index), foot + Vector2(-40, CARD_TOTAL_Y), 15, INK_GOLD)

# 叠合后差量卡出现在空出来的右侧台面上：只剩 1 红 与 1 蓝 的差。
func draw_difference(foot: Vector2) -> void:
	kit("receipt_blank", foot, CARD_WIDTH)
	words("差量签", foot + Vector2(-40, CARD_LABEL_Y), 16, INK_GOLD)
	words(Rules.cancelled_caption(), foot + Vector2(-40, CARD_LABEL_Y + 22), 13)
	var left = foot + Vector2(-22, CARD_CRATE_Y)
	contact(left, CRATE_WIDTH * 0.42, 0.24); kit("crate_red", left, CRATE_WIDTH)
	var right = foot + Vector2(22, CARD_CRATE_Y - 6)
	contact(right, CRATE_WIDTH * 0.42, 0.24); kit("crate_blue", right, CRATE_WIDTH)
	words("差 %d 斤" % Rules.DIFFERENCE, foot + Vector2(-40, CARD_TOTAL_Y), 15, INK_GOLD)

func draw_racks() -> void:
	var beat = pulse()
	for kind in range(2):
		for tag in range(Rules.TAG_MIN, Rules.TAG_MAX + 1):
			var foot = tag_foot(kind, tag) + Vector2(0, 18)
			var used = Rules.hung(state, kind) == tag
			contact(foot, 17, 0.14)
			kit(TAG_SPRITE[kind], foot, WEIGHT_WIDTH - 4.0, 0.68 if used else 1.0)
			words(str(tag), foot + Vector2(-5, -32), 16, INK_GOLD if used else INK_LIGHT)
		if Rules.hung(state, kind) == 0:
			socket(record_foot(kind) + Vector2(0, TAG_ROW_LIFT - 32), Vector2(152, 13), 0.3 + 0.22 * beat)

# 左盘：复秤时装这一条记录的封箱组，平时是待挂签的样本箱；右盘：与记录同重的砝码。
func draw_scale() -> void:
	var factor = SCALE_FACTOR
	var angle = beam_angle()
	var pivot = beam_pivot(factor)
	kit("scale_stand", scale_foot(), part_width("scale_stand", factor))
	var texture: Texture2D = atlases["scale_beam"]
	var item: Dictionary = parts["scale_beam"]
	var dims = Vector2(texture.get_width(), texture.get_height()) * factor
	draw_set_transform(pivot, angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-Vector2(item.anchor_px[0], item.anchor_px[1]) * factor, dims), false)
	draw_set_transform(Vector2.ZERO)
	for side in range(2):
		var hook = beam_hook(pivot, side, factor, angle)
		kit("scale_pan", hook, part_width("scale_pan", factor))
		draw_pan(side, attach("scale_pan", "cargo", hook, factor))
	if braked():
		for kind in range(2): draw_hung_tag(kind)

func draw_pan(side: int, cargo: Vector2) -> void:
	if state.stage != "reweigh":
		var foot = cargo + Vector2(0, -8)
		contact(foot, CRATE_WIDTH * 0.42, 0.24)
		kit("crate_red" if side == Rules.RED else "crate_blue", foot, CRATE_WIDTH)
		return
	var index := 0 if progress < 0.5 else 1
	var record: Array = Rules.RECORDS[index]
	if side == 0:
		var group = card_group(index)
		var pitch = CRATE_WIDTH + 2.0
		var first = cargo + Vector2(-pitch * (group.size() - 1) / 2.0, -6)
		for step in range(group.size()):
			var at = first + Vector2(pitch * step, 0)
			contact(at, CRATE_WIDTH * 0.42, 0.24)
			kit("crate_red" if group[step] == Rules.RED else "crate_blue", at, CRATE_WIDTH)
			words(str(Rules.hung(state, group[step])), at + Vector2(-4, -CRATE_WIDTH - 14), 14, INK_GOLD)
	else:
		kit("weight_hex", cargo + Vector2(0, -4), WEIGHT_WIDTH)
		kit("weight_stepped", cargo + Vector2(-24, -6), WEIGHT_WIDTH - 8.0)
		kit("weight_small", cargo + Vector2(24, -6), WEIGHT_WIDTH - 12.0)
		words("%d 斤" % record[2], cargo + Vector2(-14, -48), 14, INK_GOLD)

# 挂好的重签吊在样本箱上方：新挂的那一枚从签架升上来，只用世界时钟计时。
func draw_hung_tag(kind: int) -> void:
	var foot = pan_cargo(kind) + Vector2(0, -CRATE_WIDTH - 28.0)
	var tag: int = Rules.hung(state, kind)
	var at = foot + Vector2(0, 30.0 * rise(kind))
	plaque("空钩" if tag == 0 else "%d 号" % tag, Rect2(at + Vector2(-26, -22), Vector2(52, 24)), 15,
		INK_GOLD if tag > 0 else INK_LIGHT)
	if tag > 0: kit(TAG_SPRITE[kind], at + Vector2(0, 20), WEIGHT_WIDTH - 6.0, 0.94)

func draw_signs() -> void:
	if state.stage in ["arrival", "approach"]: return
	plaque(Rules.record_caption(0), Rect2(286, 506, 244, 28), 16)
	plaque(Rules.difference_caption() if Rules.folded(state) else Rules.record_caption(1),
		Rect2(742, 506, 244, 28), 16, INK_GOLD if Rules.folded(state) else INK_LIGHT)
	if state.stage == "puzzle":
		plaque("红箱重签 · 点一枚挂上", Rect2(257, 540, 220, 24), 15)
		plaque("蓝箱重签 · 点一枚挂上", Rect2(709, 540, 220, 24), 15)
		plaque("已制动 · 提交后才复秤", Rect2(538, 506, 190, 28), 15)
	if state.stage == "reweigh":
		var index := 0 if progress < 0.5 else 1
		plaque("复秤 %d 斤 = 记录 %d 斤" % [Rules.reading(state, index), Rules.published(index)],
			Rect2(538, 506, 196, 28), 14, INK_GOLD)
	if state.stage == "delivery" and progress > 0.35:
		# 原单从柜台下翻出来：重量签回来了，那批货的单号也就对上了。
		# 纸必须落在台面上（counter 的脚点），挂在 resident 之内的空中读起来像一张没贴住的标签。
		var foot = station("counter_right") + Vector2(150, 0)
		kit("receipt_blank", foot, 100)
		words("原单", foot + Vector2(-42, -96), 15, INK_GOLD)
		words("2红+1蓝 14 斤", foot + Vector2(-42, -76), 12)
		words("1红+2蓝 13 斤", foot + Vector2(-42, -58), 12)
		words("红 %d · 蓝 %d" % [state.red, state.blue], foot + Vector2(-42, -40), 12)

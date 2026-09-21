extends "res://scripts/market/kit_world.gd"
# MK11 分油庭院：老货栈的铜秤立在正中，左边那盘是接灯油的货盘、右边那盘是对面，
# 三枚砝码先站在台面（地上那块接货盘）上，油壶与提斗在陶姨的左边那辆车上。
# 底景、铜秤三构件、三种砝码、油壶油瓶、接货盘、送货车全部来自 kit-v1 拆件包；
# 盘面合计、倾斜与读数一律由 mk11_rules.gd 现算，这里一克都不自己攒、也一克都不另存。
# 坐标只来自 manifest `oil` 场景的站位（cart_left / cart_middle / cart_right / scale_foot）
# 与拆件自己的挂点，关卡里不再另立第二套庭院位置。
const Rules = preload("res://scripts/market/mk11_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/oil-courtyard-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 铜秤是本关的主角，三构件共用同一个缩放系数（manifest 的铜秤组装约定），
# 不各自套 suggested_width 后强行对接。
const SCALE_FACTOR = 0.85
# 秤杆静止时最多沉到多少弧度：只决定演出幅度，判分永远在 Rules 里。
const MAX_ANGLE = 0.2
# 三枚砝码的造型按轻重分配：1 用扁圆码、3 用六角码、9 用最高那只阶梯码。
const WEIGHT_SPRITES = ["weight_small", "weight_hex", "weight_stepped"]
const WEIGHT_WIDTHS = [40.0, 46.0, 40.0]
# 每盘三个砝码位相对挂盘 cargo 点的横向偏移（键取 Rules.GOODS / Rules.FAR）：
# 货盘最左边那一格留给接油罐，对面那盘没有罐、三格居中。
const SLOT_DX = {Rules.GOODS: [-25.0, 25.0, 75.0], Rules.FAR: [-50.0, 0.0, 50.0]}
const POT_DX = -75.0
const SLOT_SLOT = 48.0
const PAN_LIFT = 6.0
const BENCH_DX = [-56.0, 0.0, 56.0]
const BENCH_WIDTH = 200.0
const CART_WIDTHS = [200.0, 132.0, 172.0]

func ready_level() -> void:
	scene_id = "oil"
	backdrop = BACKDROP

# ---- 落点：一切从 station 与拆件挂点推出来 ----
func scale_foot() -> Vector2: return station("scale_foot")
func cart_station(index: int) -> String: return ["cart_left", "cart_middle", "cart_right"][index]
func cart_foot(index: int) -> Vector2: return station(cart_station(index))
func cart_width(index: int) -> float: return CART_WIDTHS[index]
func cart_factor(index: int) -> float: return cart_width(index) / float(atlases["delivery_cart"].get_width())
func cart_cargo(cart: int, name: String) -> Vector2:
	return attach("delivery_cart", name, cart_foot(cart), cart_factor(cart))

# manifest 的 attachment 公式：世界位置 = 脚点 + (挂点像素 − anchor_px) × 缩放，缩放只乘一次。
func part_width(id: String, factor: float) -> float: return float(atlases[id].get_width()) * factor

func attach(id: String, name: String, foot: Vector2, factor: float) -> Vector2:
	var item: Dictionary = parts[id]
	var point: Array = item.attachments_px[name]
	return foot + Vector2(point[0] - item.anchor_px[0], point[1] - item.anchor_px[1]) * factor

func beam_pivot(factor: float) -> Vector2:
	return attach("scale_stand", "pivot", scale_foot(), factor)

func beam_hook(pivot: Vector2, side: int, factor: float, angle: float) -> Vector2:
	var item: Dictionary = parts["scale_beam"]
	var point: Array = item.attachments_px["left_hook" if side == Rules.GOODS else "right_hook"]
	var local = Vector2(point[0] - item.anchor_px[0], point[1] - item.anchor_px[1]) * factor
	return pivot + local.rotated(angle)

# 盘只跟着梁端平移，自身永远保持水平（manifest 的铜秤组装约定）。
func pan_hook(side: int, angle: float = 0.0) -> Vector2:
	return beam_hook(beam_pivot(SCALE_FACTOR), side, SCALE_FACTOR, angle)

func pan_cargo(side: int, angle: float = 0.0) -> Vector2:
	return attach("scale_pan", "cargo", pan_hook(side, angle), SCALE_FACTOR)

# ---- 可点的东西：台面三格、每盘三格、油壶与提斗、盘上的接油罐 ----
func bench_tray() -> Vector2: return scale_foot() + Vector2(-340, 33)
func bench_foot(index: int) -> Vector2: return scale_foot() + Vector2(-340 + BENCH_DX[index], 25)
func bench_rect(index: int) -> Rect2: return target(bench_foot(index), 52, 28)
func pan_slot(side: int, index: int) -> Vector2:
	return pan_cargo(side) + Vector2(SLOT_DX[side][index], -PAN_LIFT)
func pan_rect(side: int, index: int) -> Rect2: return target(pan_slot(side, index), SLOT_SLOT, 26)
func pot_foot() -> Vector2: return pan_cargo(Rules.GOODS) + Vector2(POT_DX, -PAN_LIFT)
func pot_rect() -> Rect2: return target(pot_foot(), SLOT_SLOT, 26)
func valve_rect() -> Rect2: return target(cart_cargo(0, "cargo_left") - Vector2(0, 4), 56, 30)
func ladle_rect() -> Rect2: return target(cart_cargo(0, "cargo_right") - Vector2(0, 4), 56, 30)
func koukou_foot() -> Vector2: return scale_foot() + Vector2(420, 73)

# 全部命中区：无头检查逐条量大小、是否越出 1280×720、以及两两不相撞。
func targets() -> Array:
	var rects = [valve_rect(), ladle_rect(), pot_rect()]
	for index in range(Rules.COUNT):
		rects.append(bench_rect(index))
		for side in [Rules.GOODS, Rules.FAR]: rects.append(pan_rect(side, index))
	return rects

# ---- 落下：只说「谁刚刚落到哪儿」，0.28 秒的落地锁由宿主跑 ----
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if state.stage != "puzzle" or String(previous.get("stage", "")) != "puzzle": return
	if not previous.has("goods") or not state.has("goods"): return
	for index in range(Rules.COUNT):
		var onward: int = Rules.side_of(state, index)
		if onward == Rules.OFF or onward == Rules.side_of(previous, index): continue
		land_place = "pan"; land_slot = onward * 10 + index
	if state.has("oil") and previous.has("oil") and state.oil > previous.oil:
		land_place = "pot"; land_slot = 0

# ---- 秤的阅读：画面只转述 Rules 的算式 ----
# 提交之前秤始终锁着；抬秤那一段先如实沉到该沉的一侧，再带一点阻尼回到静止位置。
func braked() -> bool: return state.stage not in ["weighing", "result", "delivery", "complete"]

func beam_angle() -> float:
	var settled = MAX_ANGLE * Rules.tilt(state)
	if state.stage == "weighing":
		var phase = clampf(progress, 0.0, 1.0)
		var ease = 1.0 - (1.0 - phase) * (1.0 - phase)
		var wobble = 0.32 * sin(phase * PI * 3.0) * (1.0 - phase)
		return settled * (ease + wobble)
	return 0.0 if braked() else settled

# 交付过半：罐里的油已经倒进陶姨的封坛，盘上不再留这一份油（坛子改画在庭院边上）。
# 只有这一处跟着动画走：牌面与两盘读数仍然念玩家提交的那一份约定（见 boards()/notes()），
# 秤杆也照那一份保持水平——演出的一分半里不能出现「砝码 3 = 砝码 1 + 砝码 9」这种话。
func shown_oil() -> int:
	if state.stage == "delivery" and progress >= 0.5: return 0
	return state.oil

func oil_height(oil: int) -> float: return 5.0 + oil * 1.9
# 交付落点：铜秤右边那块台面，陶姨的封坛放在那儿等衡伯来验。
func shelf_foot() -> Vector2: return scale_foot() + Vector2(260, 33)

func delivery_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "delivery" or not state.has("oil"): return plan
	var phase = clampf(p / 0.55, 0.0, 1.0)
	if phase <= 0.0: return plan
	var from = pot_foot() - Vector2(0, 14.0)
	var to = shelf_foot() - Vector2(0, 12.0)
	plan.append({"at": from.lerp(to, phase) - Vector2(0, sin(phase * PI) * 44.0), "phase": phase})
	return plan

# ---- 绘制 ----
func draw_level() -> void:
	if not state.has("oil"): return
	draw_carts()
	draw_bench()
	draw_scale()
	draw_koukou()
	draw_flight(delivery_plan(progress))
	draw_boards()

func draw_carts() -> void:
	# 三辆车是三个实例，各拉各的货：左边陶姨的油车、中间待送走的空车、右边老货栈的存货。
	kit("delivery_cart", cart_foot(1), cart_width(1), 0.94)
	kit("delivery_cart", cart_foot(2), cart_width(2))
	kit("delivery_cart", cart_foot(0), cart_width(0))
	kit("oil_jug_tall", cart_cargo(0, "cargo_left"), 44.0)
	kit("oil_bottle", cart_cargo(0, "cargo_right"), 34.0)
	kit("oil_jug_round", cart_cargo(2, "cargo_left"), 44.0, 0.96)
	kit("oil_bottle", cart_cargo(2, "cargo_right") - Vector2(0, 2), 30.0, 0.96)
	if state.stage in ["delivery", "complete"]:
		var sealed = state.stage == "delivery"
		contact(shelf_foot(), 26.0, 0.2)
		kit("receiving_tray", shelf_foot() + Vector2(0, 6), 120.0, 0.96)
		kit("oil_jug_round", shelf_foot() - Vector2(0, 12), 46.0, 0.5 if sealed else 1.0)
		if state.stage == "complete":
			kit("oil_bottle", shelf_foot() + Vector2(40, -8), 30.0)
			kit("receipt_blank", shelf_foot() + Vector2(40, -2), 52.0)

func draw_bench() -> void:
	kit("receiving_tray", bench_tray(), BENCH_WIDTH, 0.98)
	for index in range(Rules.COUNT):
		if Rules.side_of(state, index) != Rules.OFF: continue
		var foot = bench_foot(index)
		contact(foot, WEIGHT_WIDTHS[index] * 0.52, 0.24)
		kit(WEIGHT_SPRITES[index], foot, WEIGHT_WIDTHS[index])
		words(str(Rules.WEIGHTS[index]), foot + Vector2(-5, -WEIGHT_WIDTHS[index] * 1.5), 15, INK_GOLD)
	# 还没上秤的砝码这里亮一下：只说「这里能拿」，不判断拿了对不对。
	if state.stage == "puzzle":
		for index in range(Rules.COUNT):
			if Rules.side_of(state, index) == Rules.OFF:
				socket(bench_foot(index) - Vector2(0, 18), Vector2(24, 10), 0.26 + 0.2 * pulse())

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
	for side in [Rules.GOODS, Rules.FAR]:
		var hook = pan_hook(side, angle)
		kit("scale_pan", hook, part_width("scale_pan", factor))
		draw_pan(side, attach("scale_pan", "cargo", hook, factor))

func draw_pan(side: int, cargo: Vector2) -> void:
	if side == Rules.GOODS: draw_pot(cargo)
	for index in range(Rules.COUNT):
		if not Rules.on_pan(state, side, index): continue
		var foot = cargo + Vector2(SLOT_DX[side][index], -PAN_LIFT)
		var drop = landing("pan", side * 10 + index)
		var at = foot + Vector2(0, 34.0 * drop)
		contact(foot, WEIGHT_WIDTHS[index] * 0.5, 0.24 * (1.0 - drop))
		kit(WEIGHT_SPRITES[index], at, WEIGHT_WIDTHS[index], 1.0 - drop * 0.6)
		words(str(Rules.WEIGHTS[index]), at + Vector2(-5, -WEIGHT_WIDTHS[index] * 1.5), 15, INK_GOLD)

# 接油罐：皮重已经归零，罐口的油面随接进来的单位数长高。
func draw_pot(cargo: Vector2) -> void:
	var foot = cargo + Vector2(POT_DX, -PAN_LIFT)
	var drop = landing("pot", 0)
	var oil: int = shown_oil()
	var lift = oil_height(oil) * (1.0 - drop)
	contact(foot, 21.0, 0.22)
	kit("oil_jug_round", foot, 44.0, 0.98)
	if oil > 0:
		var mouth = foot - Vector2(0, 32.0)
		draw_set_transform(mouth, 0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 13.0, Color("b8721a"))
		draw_circle(Vector2(0, -lift * 0.16), 10.0, Color("ffd27a", 0.72))
		draw_set_transform(Vector2.ZERO)
		words("%d"%oil, foot + Vector2(-5, -58.0), 16, INK_GOLD)
	if state.stage == "puzzle" and oil == 0:
		socket(foot - Vector2(0, 24), Vector2(21, 10), 0.24 + 0.2 * pulse())

func draw_koukou() -> void:
	# oil 场景没有人物站位：扣扣由 scale_foot 推出来，站在对面那盘旁边替大家扶稳秤盘。
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, koukou_foot(), 0.5)

func draw_flight(plan: Array) -> void:
	for entry in plan:
		kit("oil_jug_round", entry["at"], 44.0, 1.0 - clampf((float(entry["phase"]) - 0.8) / 0.2, 0.0, 1.0) * 0.5)

# 牌面（有底的牌子）集中在 boards()、说明与读数集中在 notes()，
# 画之前先被无头检查逐条量过宽度：汉字在 Godot 里是一个不断词，plaque 与 words 都不会换行，
# 超框就会画到牌子外面。
func boards() -> Array:
	var boards = [
		# 这块牌子原来在 y 250、宽 196，横穿 44 宽的高油壶（壶身画到 313.7），
		# 木牌是不透明底、又排在最后画，正好把壶拦腰切成两截。挪到壶底下面 4 像素、
		# 只留车名这么宽（右沿 330）：秤杆摆到最满那一格，货盘连盘上数字扫到的是 x 374 起，
		# 两块各说各的，谁也压不到谁。「一格 1 单位」本来就写在油阀的悬停句里，不必挤在这块牌上。
		{"text": "陶姨的油车", "rect": Rect2(238, 318, 92, 26), "px": 15},
		{"text": "衡伯借出的三枚砝码 · 每枚最多一次", "rect": Rect2(150, 584, 300, 26), "px": 15},
	]
	if state.stage in ["arrival", "approach"]: return boards
	boards.append({"text": Rules.equation(state), "rect": Rect2(470, 584, 330, 28), "px": 15})
	return boards

# 没有底板的描边短词：盘名与锁秤说明。width 一格是可用宽度，无头检查按它量字。
func notes() -> Array:
	var revealed = not braked()
	var goods = "货盘 · 油压在这头" if not revealed else "货盘 %d 单位"%Rules.pan_total(state, Rules.GOODS)
	var far = "对面那盘 · 只站砝码" if not revealed else "对面 %d 单位"%Rules.pan_total(state, Rules.FAR)
	var notes = [
		{"text": goods, "at": Vector2(404, 514), "px": 14, "width": 140.0},
		{"text": far, "at": Vector2(740, 514), "px": 14, "width": 156.0},
	]
	if state.stage == "puzzle":
		var lock = "秤已锁 · 提交之后才抬秤" if state.weighs == 0 else "秤又锁上了 · 再提一次看看"
		# y 从 216 抬到 232：puzzle 把整座庭院按 1.10 抬起来（宿主的镜头），216 那行的字面顶边
		# 换算到屏幕是 180.6，会被 y 98..184 的台词板切掉一小截；232 留 8 像素余量，仍在秤杆上方。
		notes.append({"text": lock, "at": Vector2(500, 232), "px": 15, "width": 264.0})
	if state.stage in ["delivery", "complete"]:
		notes.append({"text": "扣扣替大家扶稳秤盘", "at": koukou_foot() - Vector2(60, 138), "px": 14, "width": 190.0})
	return notes

func draw_boards() -> void:
	for note in notes():
		words(note["text"], note["at"], int(note["px"]))
	for board in boards():
		plaque(board["text"], board["rect"], int(board["px"]))

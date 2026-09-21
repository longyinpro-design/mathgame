extends "res://scripts/market/kit_world.gd"
# MK12 分油庭院：三处街口的接货车就是三个收货位，每一辆车前面摆着各自的已确认需求单；
# 六壶封油摆在前景的接货台面上，壶没拆开过，也不需要拆开。
# 底景、封油壶、接货车、灯串与回执全部来自 kit-v1 拆件包；坐标只来自 manifest `oil` 场景
# （cart_left / cart_middle / cart_right / scale_foot）与 delivery_cart 自己的
# cargo_left / cargo_right 挂点，壶排由 grid() 算出来，关卡里不另立第二套站位或壶排。
const Rules = preload("res://scripts/market/mk12_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/oil-courtyard-clean-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 三处街口的需求单按桥头 → 中街 → 西坡排在 manifest 的三辆车站位上，不按多少重排。
const CARTS = ["cart_left", "cart_middle", "cart_right"]
const CARGO_KEYS = ["cargo_left", "cargo_right"]
const CART_WIDTH = 206.0
const TRAY_WIDTH = 150.0
const STRING_WIDTH = 150.0
const STOCK_PITCH = 62.0
const SHEET_WIDTH = 44.0
# 离场只是整辆车平移（manifest 明确允许单件车整体平移），不是车轮或车辕动画。
const ROLL = [Vector2(-84, 4), Vector2(0, 24), Vector2(84, 4)]
# 灯串拆件上五盏灯的玻璃中心（裁剪图像素），按 manifest 的 attachment 公式换算到世界坐标。
const LANTERN_GLASS = [Vector2(47, 124), Vector2(136, 163), Vector2(225, 173), Vector2(316, 163), Vector2(402, 125)]

var picked := -1
var _cargo: Array = []
var _stock: Array = []
var _trays: Array = []

func ready_level() -> void:
	scene_id = "oil"
	backdrop = BACKDROP

# 只有刚装上车的这一壶需要落下动画；放回是回到台面，不留下落点。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	if not previous.has("plan") or not state.has("plan"): return
	for place in range(Rules.PLACES.size()):
		for jug in state.plan[place]:
			if not previous.plan[place].has(jug):
				land_place = "jug"; land_slot = jug

# ---- geometry: everything hangs off the manifest stations ----
# manifest 的 attachment 公式：世界落点 = 脚点 + (附件像素 − anchor_px) × scale，缩放只乘一次。
func kit_point(id: String, foot: Vector2, width: float, px: Vector2) -> Vector2:
	var item: Dictionary = parts[id]
	return foot + (px - Vector2(item.anchor_px[0], item.anchor_px[1])) * (width / atlases[id].get_width())

func cargo_px() -> Array:
	if _cargo.is_empty():
		var table: Dictionary = parts["delivery_cart"]["attachments_px"]
		for key in CARGO_KEYS:
			var point: Array = table[key]
			_cargo.append(Vector2(point[0], point[1]))
	return _cargo

func cart_station(place: int) -> Vector2: return station(CARTS[place])

# 交货演出里车会整体平移，车上的壶跟着车走，所以落点永远从当前的车脚算。
# 只在 handing 一幕里加这个偏移，换到 delivery 的那一帧三辆车会整排弹回庭院原位（实窗拍到的跳），
# 所以点灯那一段用一条从 1 回到 0 的曲线把它们接回来：车驶向街口、在镜头拉远的路上回到庭院，
# 收尾那一格车、车帮上的收讫纸与联合回执栏才都待在审计量过的位置上（西坡车一旦停在街口，
# 它的车斗与车帮算式就会整块滑到回执栏底下）。
func cart_foot(place: int) -> Vector2:
	var at: Vector2 = cart_station(place)
	if state.stage == "handing": return at + ROLL[place] * smoothstep(0.0, 0.85, progress)
	if state.stage == "delivery": return at + ROLL[place] * (1.0 - smoothstep(0.0, 0.6, progress))
	return at

func slot_foot(place: int, slot: int) -> Vector2:
	return kit_point("delivery_cart", cart_foot(place), CART_WIDTH, cargo_px()[slot]) + Vector2(0, 2)

func stock_spots() -> Array:
	if _stock.is_empty():
		var from: Vector2 = station("scale_foot") + Vector2(-float(Rules.JUGS - 1) * STOCK_PITCH / 2.0, 60)
		_stock = grid(from, Vector2(STOCK_PITCH, 0), Rules.JUGS, Rules.JUGS)
	return _stock

func tray_spots() -> Array:
	if _trays.is_empty():
		_trays = grid(station("scale_foot") + Vector2(-150.0, 64), Vector2(TRAY_WIDTH, 0), 3, 3)
	return _trays

func stock_spot(jug: int) -> Vector2: return stock_spots()[jug]

# 台面上的一壶：命中方框盖住画出来的壶身，不越到车上。
func stock_rect(jug: int) -> Rect2: return target(stock_spot(jug), 56, 52)
# 车上一壶的单位读数就写在壶脚下：审计与画面共用这一个方框，改一处不会漏改另一处。
func jug_mark_rect(place: int, slot: int) -> Rect2:
	var at = slot_foot(place, slot)
	return Rect2(at.x - 30, at.y + 28, 60, 18)
# 一整辆车的接货框：贴着车斗与车身，落在壶的命中框下面，两者不抢。
func cart_rect(place: int) -> Rect2: return target(cart_station(place), 150, 64)
func slot_rect(place: int, slot: int) -> Rect2:
	return target(kit_point("delivery_cart", cart_station(place), CART_WIDTH, cargo_px()[slot]) - Vector2(0, 6), 52, 52)
func string_foot(place: int) -> Vector2: return cart_foot(place) + Vector2(0, -128)
func sheet_foot(place: int) -> Vector2: return cart_foot(place) + Vector2(74, 46)
# oil 场景没有人物站位，扣扣站在接货台面的左手边（由 scale_foot 推出，不另立坐标）。
func keeper_foot() -> Vector2: return station("scale_foot") + Vector2(-268, 96)

func jug_width(jug: int, on_cart: bool) -> float:
	var base: float = 50.0 if Rules.JUG_UNITS[jug] == 2 else 38.0
	return base * (0.86 if on_cart else 1.0)

# ---- derived reading of the loading draft ----
# 车上的合计永远由 plan 现算：画面自己不留任何一份计数。
# 离场与交货那两幕把算式写在车帮上——这一关的收尾就是「不一样多，也都够用」这笔账，
# 而回执那张纸只有 44 像素宽，塞不下 18 号字，算式只能读在车斗下方这一行。
func cart_mark(place: int) -> String:
	var row: Array = state.plan[place]
	var marks := []
	for jug in row: marks.append("%d" % Rules.JUG_UNITS[jug])
	var sum = "+".join(marks)
	match state.stage:
		"handing": return "抱着 %s=%d 单位上路" % [sum, Rules.units_of(row)]
		"delivery", "complete": return "%s=%d · 正好够用" % [sum, Rules.units_of(row)]
	return "车上 %d 单位" % Rules.units_of(row) if not row.is_empty() else "车上还空着"

# 封油壶不拆封：三辆车各自载着自己的两壶离开，接油的是这一处的灯具。
func light_string(foot: Vector2, strength: float) -> void:
	if strength <= 0.0: return
	for index in range(LANTERN_GLASS.size()):
		var one = clampf(strength * LANTERN_GLASS.size() - index * 0.7, 0, 1)
		if one <= 0.0: continue
		var at = kit_point("lantern_string", foot, STRING_WIDTH, LANTERN_GLASS[index])
		var beat = 0.86 + 0.14 * sin(clock * 3.2 + index * 1.7)
		draw_circle(at, 21.0 * one * beat, Color(1.0, 0.72, 0.30, 0.20 * one))
		draw_circle(at, 11.0 * one, Color(1.0, 0.80, 0.38, 0.52 * one))
		draw_circle(at, 5.5 * one, Color(1.0, 0.95, 0.78, 0.9 * one))

# ---- drawing ----
func draw_strings() -> void:
	for place in range(Rules.PLACES.size()):
		var foot = string_foot(place)
		match state.stage:
			"delivery":
				# 车离场那一幕灯串已经满透明度挂着了：这里再乘一个 0.45 起步的系数，
				# 换幕那一帧绳子会突然暗掉一半，而真正亮起来的应该是灯芯的光晕。
				kit("lantern_string", foot, STRING_WIDTH)
				light_string(foot, smoothstep(0.3 + 0.2 * place, 1.0, progress))
			"complete":
				kit("lantern_string", foot, STRING_WIDTH)
				light_string(foot, 1.0)
			_:
				kit("lantern_string", foot, STRING_WIDTH)
		if state.stage in ["delivery", "complete"]:
			# 三家把确认过的需求单一起递回来：车帮上这一纸是这一处收讫的凭证。
			# 纸面只有 44 像素宽，装不下任何 18 号字，所以算式读在车斗下方那一行，不写在纸上。
			kit("receipt_blank", sheet_foot(place), SHEET_WIDTH)

func draw_carts() -> void:
	var beat = 0.6 + 0.4 * pulse()
	for place in range(Rules.PLACES.size()):
		var foot = cart_foot(place)
		contact(foot + Vector2(0, -4), 88, 0.2)
		kit("delivery_cart", foot, CART_WIDTH)
		var row: Array = state.plan[place]
		for slot in range(row.size()):
			var jug: int = row[slot]
			var at = slot_foot(place, slot)
			var drop = landing("jug", jug)
			contact(at, jug_width(jug, true) * 0.5, 0.2 * (1.0 - drop))
			kit(Rules.JUG_KITS[jug], at - Vector2(0, 38 * drop), jug_width(jug, true), 1.0 - drop * 0.7)
			# 壶一上车不改名字：台面上写着几单位，车上就写着几单位。装车这一段玩家要对着
			# 壶身想「这两壶合不够那张单子」，读数不能一下车就消失。
			# 交货之后由车帮那一行算式接手，壶身不再叠字。
			if state.stage in ["ready", "puzzle", "handing"]:
				mark("%d 单位" % Rules.JUG_UNITS[jug], jug_mark_rect(place, slot), 16)
		# 空车位各标一个「这里还能放一壶」：两壶的上限画在车上，不用玩家去数台词。
		# 手里拿着壶时这一圈要亮起来——不然「哪辆车还接得下」只能靠记忆。
		if state.stage == "puzzle":
			for slot in range(row.size(), Rules.MAX_PER_PLACE):
				socket(slot_foot(place, slot) - Vector2(0, 12), Vector2(26, 11),
					(0.62 if picked >= 0 else 0.26) * beat)
		if state.stage == "delivery" and progress > 0.2 + 0.2 * place:
			socket(foot - Vector2(0, 96), Vector2(40, 16), 0.5 + 0.5 * pulse())

func draw_stock() -> void:
	for spot in tray_spots(): kit("receiving_tray", spot, TRAY_WIDTH)
	var idle: Array = Rules.stock_of(state.plan)
	for jug in idle:
		var at = stock_spot(jug)
		# 只有摆在装车这一步才会被拿起来；重新体验之后画面里没有「还捏在手里」的壶。
		var lift := 16.0 if picked == jug and state.stage == "puzzle" else 0.0
		contact(at, jug_width(jug, false) * 0.52, 0.22)
		kit(Rules.JUG_KITS[jug], at - Vector2(0, lift), jug_width(jug, false))
		# 封好的壶身上写着这一壶是几单位：数量写在实物上，不靠玩家记台词。
		mark("%d 单位" % Rules.JUG_UNITS[jug], Rect2(at.x - 30, at.y + 28, 60, 18), 16)
		if state.stage == "puzzle":
			socket(at - Vector2(0, lift + 12), Vector2(26, 11), (0.72 if picked == jug else 0.2) * (0.6 + 0.4 * pulse()))

func draw_figure() -> void:
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.5)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, keeper_foot(), 0.5)

# ---- text boards：画之前先被无头检查逐条量过宽度 ----
# 汉字在 Godot 里是一个不断词，plaque 与 words 都不换行，超框就会画到板子外面。
func signs() -> Array:
	var boards = []
	for place in range(Rules.PLACES.size()):
		var at: Vector2 = cart_station(place)
		# 车帮那一行算式说的是「这一辆车正带着什么」，所以它跟着车脚走；需求单是钉在庭院里
		# 的那张纸，车驶向街口时它留在原位。
		var cart: Vector2 = cart_foot(place)
		# 需求单宽 230 而不是 240：西坡那张的右端要留在联合回执栏（x=984，投影再往里 7）的左手边，
		# 收尾一摊纸就把「西坡 · 需求单 6 单位」的木边啃掉一角（审计量出来的 3 像素）。
		boards.append({"text": "%s · 需求单 %d 单位" % [Rules.PLACES[place], Rules.NEEDS[place]],
			"rect": Rect2(at.x - 115, at.y + 92, 230, 28), "plaque": true, "size": 16})
		boards.append({"text": cart_mark(place), "rect": Rect2(cart.x - 100, cart.y - 26, 200, 20),
			"plaque": false, "size": 16})
	if state.stage == "arrival": return boards
	# 装车那一格镜头把庭院抬到 1.10 并左移 64：屏幕横坐标 = 世界 × 1.1 − 64，
	# 所以侧板的世界边界必须留在 58.2 与 1221.8 之间，否则首字会被窗框切掉、
	# 右边那块也会从右沿外溢出去（实窗审计拍到的真缺陷）。
	# 「每处最多两壶」这块侧板已经删掉：它原先就画在扣扣的左臂与封包上（世界 x 290.2 起，
	# 板子右端到 328），而同一句话在抬头目标板上一直挂着，宿主那块板不会被人物挡住。
	boards.append({"text": "货栈封油 · 六壶都不能拆", "rect": Rect2(512, 440, 256, 26), "plaque": true, "size": 16})
	boards.append({"text": "封油共 %d 单位 · 三处共要 %d 单位" % [Rules.jug_total(), Rules.need_total()],
		"rect": Rect2(900, 596, 314, 28), "plaque": true, "size": 16})
	return boards

func mark(text: String, rect: Rect2, size_px: int) -> void:
	var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	words(text, rect.position + Vector2((rect.size.x - wide) / 2.0, rect.size.y - 4), size_px)

func draw_text() -> void:
	for board in signs():
		if board["plaque"]: plaque(board["text"], board["rect"], board["size"])
		else: mark(board["text"], board["rect"], board["size"])

func draw_level() -> void:
	if not state.has("plan"): return
	draw_strings()
	draw_carts()
	draw_stock()
	draw_figure()
	draw_text()

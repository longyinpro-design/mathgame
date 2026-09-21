extends "res://scripts/market/kit_world.gd"

# MK08 老货栈门前：账架上钉着三张原单，柜台上压着那块把红单抄了两回的汇总板。
# 底景、整箱、散瓶、包裹、回执纸与收货台全部来自 kit-v1 拆件包；单号颜色、瓶数与单位牌由引擎画，
# 坐标只来自 manifest 的 street 场景（counter / stall_left / stall_midleft / stall_middle /
# stall_midright / stall_right），货样一律用 grid()/row_of() 按件数排开，不在关卡里另立第二套站位。
# 板上每行的合计、点收的瓶数全部向规则层要（Rules.total_of / dock_count），画面自己不存计数。
const Rules = preload("res://scripts/market/mk08_rules.gd")
const BACKDROP = preload("res://assets/source/market/lantern-street-stage-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const INK_SEAL = Color("8fdca0")
const INK_DIM = Color("b6a98d")
# 三张原单按街上从左到右钉在账架上，顺序与 Rules.NAMES 同序。
const RACK_STALLS = ["stall_left", "stall_midleft", "stall_midright"]
const ROW_PITCH = 58.0
const COL_PITCH = 92.0
const GOODS_EDGE = 50.0				# 第一件货的左沿离本行第 4 列槽位中心：「换算」牌只占中心右 42，留 8 像素不压牌
const BOX_MINI = 20.0				# 汇总板上的整箱显示宽：只表示「这一行记了几件」
const BOTTLE_MINI = 14.0
const RACK_BOX = 46.0
const RACK_BOTTLE = 24.0
const DOCK_BOX = 30.0
const DOCK_BOTTLE = 20.0
const PAPER_WIDTH = 120.0
const TICKET_PAPER = 62.0
const TRAY_WIDTH = 174.0
const BASKET_WIDTH = 116.0
const STAMP_STEP = 0.24				# 交付演出：一行一行盖讫，托盘上的点收数跟着走
var _dock: Array = []				# 收货台上的货样位置，按单号分组算一次就复用

func ready_level() -> void:
	scene_id = "street"; backdrop = BACKDROP

# 只有刚钉上板的那一行需要落纸动画：撤行与换算都不是新到的货。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	if not previous.has("lines") or not state.has("lines"): return
	for row in range(Rules.LINES):
		if state.lines[row][0] >= 0 and previous.lines[row][0] < 0:
			land_place = "line"; land_slot = row

# ---- 站位与热点：全部从 manifest 的站位推出来 ----
func counter() -> Vector2: return station("counter")
func board_origin() -> Vector2: return counter() + Vector2(-330, -120)
func row_foot(row: int) -> Vector2: return board_origin() + Vector2(0, ROW_PITCH * row)
func slot_foot(row: int, col: int) -> Vector2: return row_foot(row) + Vector2(COL_PITCH * col, 0)
func chip_rect(row: int) -> Rect2: return target(slot_foot(row, 0), 56, 40)
func less_rect(row: int) -> Rect2: return target(slot_foot(row, 1), 52, 38)
func more_rect(row: int) -> Rect2: return target(slot_foot(row, 3), 52, 38)
func unit_rect(row: int) -> Rect2: return target(slot_foot(row, 4), 56, 40)
func rack_foot(order: int) -> Vector2: return station(RACK_STALLS[order]) + Vector2(0, 6)
func ticket_rect(order: int) -> Rect2: return target(rack_foot(order), 96, 76)
func dock_foot() -> Vector2: return station("stall_right") + Vector2(0, 10)
func basket_foot() -> Vector2: return station("stall_right") + Vector2(-6, 130)
# 扣扣站在汇总板左边。原先停在柜台左 560：0.5 倍身位有 163 宽，左沿落在世界 −1.75，
# puzzle/filing 那一档 1.10 倍镜头再把她往屏幕外推 64——半个身子被窗框切掉。
func koukou_foot() -> Vector2: return counter() + Vector2(-490, 56)

# 一排货样：以 center 为中线按件数等距排开，位置由基类的 grid() 算出，不手写坐标列表。
func row_of(part: String, center: Vector2, count: int, width: float) -> Array:
	if count <= 0: return []
	return grid(center - Vector2((width + 6.0) * (count - 1) / 2.0, 0), Vector2(width + 6.0, 0), count, count)

# 账架上某张原单的实物：整箱用该单的代表箱，散瓶用油瓶；两拨货各按自己的件数排开。
func rack_goods(order: int) -> Array:
	var items: Array = []
	var loose_span: float = (RACK_BOTTLE + 6.0) * Rules.LOOSE[order]
	var box_span: float = (RACK_BOX + 6.0) * Rules.BOXES[order]
	var foot = rack_foot(order)
	if Rules.BOXES[order] > 0:
		var box_centre = foot + Vector2(loose_span / 2.0 - box_span / 2.0 + (RACK_BOX + 6.0) / 2.0, 0)
		for spot in row_of(Rules.KIT_BOX[order], box_centre, Rules.BOXES[order], RACK_BOX):
			items.append({"kit": Rules.KIT_BOX[order], "at": spot, "w": RACK_BOX})
	if Rules.LOOSE[order] > 0:
		var bottle_centre = foot - Vector2(box_span / 2.0 - loose_span / 2.0 + (RACK_BOTTLE + 6.0) / 2.0, 0)
		for spot in row_of("oil_bottle", bottle_centre, Rules.LOOSE[order], RACK_BOTTLE):
			items.append({"kit": "oil_bottle", "at": spot, "w": RACK_BOTTLE})
	return items

# 汇总板某一行的实物：按这一行此刻记的单位画——箱就画箱、瓶就画瓶，不做任何对错判断。
func line_goods(row: int, rows: Array) -> Array:
	var items: Array = []
	var line: Array = rows[row]
	if line[0] < 0: return items
	var boxed: bool = line[2] == Rules.UNIT_BOX
	var part: String = Rules.KIT_BOX[line[0]] if boxed else "oil_bottle"
	var width: float = BOX_MINI if boxed else BOTTLE_MINI
	# 货样左对齐、件数多了往右长：原先按中线排，6 瓶那一行的头两件正好落进「换算」牌底下
	# （木牌最后画、是实心的），玩家数出来 4 件、计数牌却写着 6 件——这一关要数的就是货。
	var pitch: float = width + 6.0
	var from = slot_foot(row, 4) + Vector2(GOODS_EDGE + width / 2.0 + pitch * (line[1] - 1) / 2.0, 2)
	for spot in row_of(part, from, line[1], width):
		items.append({"kit": part, "at": spot, "w": width})
	return items

# 收货台上的实物就是三张原单的那批货：先整箱、后散瓶，两排摆开，与板上的行无关。
func dock_goods() -> Array:
	if not _dock.is_empty(): return _dock
	for order in range(Rules.ORDERS):
		var boxes = row_of(Rules.KIT_BOX[order], dock_foot() + Vector2(-36.0, -46.0), Rules.BOXES[order], DOCK_BOX)
		for spot in boxes: _dock.append({"kit": Rules.KIT_BOX[order], "at": spot, "w": DOCK_BOX, "order": order})
		var loose = row_of("oil_bottle", dock_foot() + Vector2(18.0, 0.0), Rules.LOOSE[order], DOCK_BOTTLE)
		for spot in loose: _dock.append({"kit": "oil_bottle", "at": spot, "w": DOCK_BOTTLE, "order": order})
	return _dock

# ---- 派生读数 ----
func board() -> Array:
	return state.lines if state.get("lines") is Array else Rules.empty_lines()

# 归档演出：改过的那一行同时飞走旧抄件、飞回新抄件，两程都在前半段落地。
func filing_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "filing" or not state.has("filed"): return plan
	var phase = clampf(p / 0.5, 0, 1)
	# 落定之后（后半程整段都夹在 1.0）就不必再报「还在飞」：`draw_board()` 会为了空中那张
	# 抄件把整行让出来，货样也跟着一起消失——归档动画有一半时长板上是缺货的。
	if phase <= 0.0 or phase >= 1.0: return plan
	for row in Rules.changed_rows(state):
		var home: Vector2 = row_foot(row)
		var glide = smoothstep(0, 1, phase)
		plan.append({"mode": "out", "order": Rules.START[row][0], "row": row, "home": home, "phase": phase,
			"at": home.lerp(basket_foot() - Vector2(0, 26), glide) - Vector2(0, sin(phase * PI) * 30.0)})
		plan.append({"mode": "in", "order": state.filed[row][0], "row": row, "home": home, "phase": phase,
			"at": rack_foot(state.filed[row][0]).lerp(home, glide) - Vector2(0, sin(phase * PI) * 44.0)})
	return plan

# 这一行的新抄件还在空中：等它落到行位再画板上的常驻件。
func copying_in(row: int, plan: Array) -> bool:
	for entry in plan:
		if entry["mode"] == "in" and entry["row"] == row: return true
	return false

# 交付演出：一行一行盖讫；托盘上点收的瓶数由已盖的那几行现算。
func stamped(p: float) -> Array:
	var done: Array = []
	if state.stage == "complete":
		for row in range(Rules.LINES): done.append(row)
		return done
	if state.stage != "delivery" or not state.has("filed"): return done
	for row in range(Rules.LINES):
		if p >= STAMP_STEP * row + 0.12: done.append(row)
	return done

func dock_count() -> int:
	match state.stage:
		"delivery":
			var total = 0
			for row in stamped(progress): total += Rules.bottles_of(state.filed[row][0])
			return total
		"complete": return Rules.total_of(state.filed)
	return Rules.RECEIVED

# 一张抄件：纸 + 该单的代表货样 + 单号色块。
func draw_copy(order: int, at: Vector2, alpha: float, rise: float = 0.0) -> void:
	var foot = at - Vector2(0, 34 * rise)
	contact(foot + Vector2(0, 34 * rise), 24, 0.2 * (1.0 - rise))
	kit("receipt_blank", foot, PAPER_WIDTH, alpha)
	var boxed: bool = Rules.BOXES[order] > 0
	kit(Rules.KIT_BOX[order] if boxed else "oil_bottle", foot - Vector2(0, 20),
		(BOX_MINI + 4.0) if boxed else (BOTTLE_MINI + 3.0), alpha)
	draw_rect(Rect2(foot.x - 50, foot.y - 44, 12, 12), Color(Rules.TAG_INK[order], alpha))

func stamp(foot: Vector2) -> void:
	draw_circle(foot + Vector2(92, -14), 15, Color(0.24, 0.52, 0.3, 0.9))
	words("讫", foot + Vector2(84, -8), 16, INK_SEAL)

# ---- 画 ----
func draw_rack() -> void:
	var rows = board()
	var open_row: bool = state.stage == "puzzle" and not Rules.free_rows(rows).is_empty()
	for order in range(Rules.ORDERS):
		var foot = rack_foot(order)
		contact(foot, RACK_BOX * 0.6, 0.22)
		kit("receipt_blank", foot - Vector2(0, 4), TICKET_PAPER, 0.96)
		for item in rack_goods(order): kit(item["kit"], item["at"], item["w"])
		if state.stage != "puzzle": continue
		# 已经上过板的单号只标「板上有了」，不判对错；空位才亮落点。
		if Rules.rows_of(rows, order).is_empty():
			socket(foot - Vector2(0, 12), Vector2(38, 15), 0.3 + 0.24 * pulse())
		else: words("已上板", foot + Vector2(-21, 26), 14, INK_DIM)

func draw_board() -> void:
	var rows = board()
	var plan = filing_plan(progress)
	# 正在飞的那张抄件离开板面，基类一并遮住原位，避免出现「板上还有一份 + 空中又一份」。
	var hidden = hide_while_moving(plan)
	for row in range(Rules.LINES):
		var foot = row_foot(row)
		var line: Array = rows[row]
		draw_rect(Rect2(foot.x - 40, foot.y - 34, 730, 48), Color(0.1, 0.07, 0.04, 0.34))
		if line[0] < 0:
			if state.stage == "puzzle": socket(foot - Vector2(0, 10), Vector2(26, 11), 0.3 + 0.24 * pulse())
			continue
		if copying_in(row, plan) or foot in hidden: continue
		var rise = landing("line", row)
		# 抄件本身一直在板上：归档之后它就是要交给码头的那一份，落纸动画只给刚钉上来的行。
		draw_copy(line[0], foot, 1.0 - rise * 0.7, rise)
		for item in line_goods(row, rows):
			if rise > 0.0: kit(item["kit"], item["at"] - Vector2(0, 30 * rise), item["w"], 1.0 - rise * 0.7)
			else: kit(item["kit"], item["at"], item["w"])
		if row in stamped(progress): stamp(foot)
	for entry in plan:
		var alpha: float = 1.0 - clampf((entry["phase"] - 0.75) / 0.25, 0, 1) if entry["mode"] == "out" else 0.96
		draw_copy(entry["order"], entry["at"], alpha)

func draw_dock() -> void:
	var lit: Array = []
	if state.stage != "puzzle" and state.has("filed"):
		for row in stamped(progress): lit.append(state.filed[row][0])
	kit("receiving_tray", dock_foot(), TRAY_WIDTH, 0.98)
	contact(dock_foot(), TRAY_WIDTH * 0.42, 0.2)
	for item in dock_goods():
		var alpha: float = 0.9 if state.stage == "puzzle" else 1.0
		if state.stage == "delivery" and not lit.is_empty() and not lit.has(item["order"]): alpha = 0.45
		elif state.stage == "filing": alpha = 0.75
		kit(item["kit"], item["at"], item["w"], alpha)
	kit("receiving_tray", basket_foot(), BASKET_WIDTH, 0.9)

func draw_figure() -> void:
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, koukou_foot(), 0.5)

# 所有木牌集中列在这里，画之前先被无头检查逐条量过宽度：
# 汉字在 Godot 里是一个不断词，plaque 又不会换行，超框就会画到牌子外面。
func signs() -> Array:
	var boards: Array = []
	var rows = board()
	var middle = station("stall_middle")
	# 街景在 puzzle/filing/delivery 前半程被抬到 1.10：木牌一旦高过 y=214，放大后就会钻进口述板底下。
	boards.append({"text": "老货栈 · 原单三张 · 每箱 3 瓶", "rect": Rect2(middle.x - 150, middle.y - 129, 300, 30)})
	for order in range(Rules.ORDERS):
		# 归档回执会把这三张单子原样复述一遍，收单时就让位给面板。
		if state.stage == "complete": break
		var foot = rack_foot(order)
		boards.append({"text": "%s · %s" % [Rules.NAMES[order], Rules.note(order)],
			"rect": Rect2(foot.x - 110, foot.y - 100, 220, 28)})
	if state.stage == "arrival": return boards
	# 交付那一段是「一行一行盖讫」的进行读数：只写「点收 10 瓶」像是在说码头只到了 10 瓶，
	# 托盘上明明摆着 13 瓶。这一段报的是进度（已盖 / 实收），其余时候报码头实收的总数。
	var dock_board: String = "码头 · 点收 %d 瓶" % dock_count()
	if state.stage == "delivery":
		dock_board = "码头 · 点收中 %d/%d 瓶" % [dock_count(), Rules.RECEIVED]
	boards.append({"text": dock_board,
		"rect": Rect2(dock_foot().x - 120, dock_foot().y - 148, 240, 28)})
	boards.append({"text": "撤下的抄件", "rect": Rect2(basket_foot().x - 70, basket_foot().y - 96, 140, 26)})
	var legend = row_foot(Rules.LINES - 1).y + 24
	boards.append({"text": "本板按瓶记", "rect": Rect2(board_origin().x - 32, legend, 130, 28)})
	boards.append({"text": "单号顺序 红 蓝 绿", "rect": Rect2(board_origin().x + 110, legend, 210, 28)})
	for row in range(Rules.LINES):
		var foot = row_foot(row)
		var line: Array = rows[row]
		if line[0] < 0:
			if state.stage == "puzzle":
				boards.append({"text": "空行", "rect": Rect2(foot.x - 42, foot.y - 30, 84, 26)})
			continue
		boards.append({"text": Rules.NAMES[line[0]], "rect": Rect2(slot_foot(row, 0).x - 42, foot.y - 30, 84, 26)})
		# 撤下/拨数/换算这三块控制牌只在摆放阶段出现：归档之后板面冻结，
		# 留着它们既像还能点，又正好盖住这一行的「讫」——码头盖讫是这一关的收尾画面。
		if state.stage == "puzzle":
			boards.append({"text": "-", "rect": Rect2(slot_foot(row, 1).x - 20, foot.y - 28, 40, 26)})
			boards.append({"text": "+", "rect": Rect2(slot_foot(row, 3).x - 20, foot.y - 28, 40, 26)})
			boards.append({"text": "换算", "rect": Rect2(slot_foot(row, 4).x - 42, foot.y - 30, 84, 26)})
		boards.append({"text": "%d %s" % [line[1], Rules.UNIT_CN[line[2]]],
			"rect": Rect2(slot_foot(row, 2).x - 42, foot.y - 30, 84, 26)})
	return boards

func draw_signs() -> void:
	for ticket in signs():
		plaque(ticket["text"], ticket["rect"])

func draw_level() -> void:
	if not state.has("lines"): return
	draw_rack()
	draw_board()
	draw_dock()
	draw_figure()
	draw_signs()

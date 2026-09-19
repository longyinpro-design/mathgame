extends RefCounted

# MK08 千灯集市「多出来的三瓶油」：出库与实收差 3 瓶，毛病不在总数，在那张被记了两次、又被漏掉的单。
# 账架上三张原单是事实：红单 2 箱、蓝单 4 散瓶、绿单 1 箱，每箱 3 瓶，合计 13 瓶，码头也正是收到 13 瓶；
# 汇总板上却贴着红 6、蓝 4、红 6——红单的抄件钉了两回、绿单一次都没上板，合计就成了 16 瓶。
# `lines` 只是玩家此刻钉在板上的三行，一张纸都还没归档；`filed` 只在提交通过
# 「三个单号各一次 + 单位统一到瓶 + 每行数量等于原单」之后一次性记下整块板，之后的演出全从 `filed` 读回。
# 合计永远在这里现算（total_of），画面与按钮都不存瓶数，所以撤下一行不会留下幻影瓶数。
# 只把某个数量拨到让合计凑满 13 不算完成：重复的那一行与漏掉的单号会被逐条点名到第几行。
# 规则层是纯函数：不 preload 场景、不碰 Node、不用随机，同一个输入永远得到同一个输出。
const LINES = 3					# 汇总板固定三行
const ORDERS = 3					# 账架上的三张原单
const NAMES = ["红单","蓝单","绿单"]
const TAGS = ["红","蓝","绿"]
const TAG_INK = [Color("e0795f"), Color("6fb6dd"), Color("7fd08c")]	# 单号颜色由引擎画，不靠拆件
const KIT_BOX = ["crate_red","crate_red","parcel_medium"]				# 各单的整箱货样（绿单没有绿箱，用素包裹）
const BOXES = [2,0,1]				# 每张原单里有几只整箱
const LOOSE = [0,4,0]				# 每张原单里的散瓶数
const PER_BOX = 3				# 每箱 3 瓶
const UNIT_BOX = 0
const UNIT_BOTTLE = 1
const UNIT_CN = ["箱","瓶"]
const MAX_COUNT = 8				# 数量牌最多拨到 8（板上画得下的最多件数）
const COPIES = 2				# 同一张原单在抽屉里最多两份抄件——红单那份就是被抄了两回
const RECEIVED = 13				# 码头点收实数
const BOOKED = 16				# 衡伯那块板原先合计出来的瓶数
const BEATS = 4				# 开场四句
const HINTS = 3				# 三级主动提示：提醒关系 → 缩小关键选择 → 示范一个步骤
# 有毛病的板：红单的抄件钉了两回，绿单一次都没上，合计 16 瓶。
const START = [[0,6,1],[1,4,1],[0,6,1]]
# 唯一正解：三个单号各记一次、统一到瓶、每行数量等于原单，合计 13 瓶。
const SOLUTION = [[0,6,1],[1,4,1],[2,3,1]]
const STAGES = ["arrival","approach","ready","puzzle","filing","delivery","complete"]
const ANIMATIONS = ["approach","filing","delivery"]

static func empty_lines() -> Array:
	var board: Array = []
	for _row in range(LINES): board.append([-1,0,UNIT_BOTTLE])
	return board

static func start_lines() -> Array: return START.duplicate(true)

static func fresh() -> Dictionary:
	return {"sample":"market-mk08-1","stage":"arrival","beat":0,"hint":0,
		"lines":start_lines(),"filed":empty_lines()}

# ---- 计数：全部由板面现算，任何一处都不另存总数 ----
static func bottles_of(order: int) -> int:
	return BOXES[order] * PER_BOX + LOOSE[order]

static func note(order: int) -> String:
	if BOXES[order] > 0: return "%d 箱 × 每箱 %d 瓶" % [BOXES[order], PER_BOX]
	return "%d 散瓶" % LOOSE[order]

# 一行写着多少瓶：空行永远算 0，所以撤下的那行不会留在合计里。
static func row_bottles(line: Array) -> int:
	if line[0] < 0: return 0
	return line[1] * (PER_BOX if line[2] == UNIT_BOX else 1)

static func total_of(board: Array) -> int:
	var total = 0
	for line in board: total += row_bottles(line)
	return total

static func rows_of(board: Array, order: int) -> Array:
	var rows: Array = []
	for row in range(board.size()):
		if board[row][0] == order: rows.append(row)
	return rows

static func free_rows(board: Array) -> Array:
	var rows: Array = []
	for row in range(board.size()):
		if board[row][0] < 0: rows.append(row)
	return rows

# 同一张单第二次上板起，后面这些都是重复抄件。
static func duplicate_rows(board: Array) -> Array:
	var rows: Array = []
	for order in range(ORDERS):
		var held: Array = rows_of(board, order)
		for index in range(1, held.size()): rows.append(held[index])
	rows.sort()
	return rows

static func missing_orders(board: Array) -> Array:
	var gone: Array = []
	for order in range(ORDERS):
		if rows_of(board, order).is_empty(): gone.append(order)
	return gone

# 归档之后相对衡伯原来那块板改了什么：撤下的抄件、补回的漏单、以及哪几行动过。
static func changed_rows(state: Dictionary) -> Array:
	var rows: Array = []
	for row in range(LINES):
		if state.filed[row][0] != START[row][0]: rows.append(row)
	return rows

static func copies_out(state: Dictionary) -> Array:
	return copies_delta(START, state.filed)

static func copies_in(state: Dictionary) -> Array:
	return copies_delta(state.filed, START)

static func copies_delta(from: Array, to: Array) -> Array:
	var moved: Array = []
	for order in range(ORDERS):
		var gone: int = rows_of(from, order).size() - rows_of(to, order).size()
		for _step in range(gone): moved.append(order)
	return moved

# ---- 玩家动作：钉单、撤行、拨数量、换算单位 ----
static func at_board(state: Dictionary) -> bool: return state.stage == "puzzle"

static func can_pin(state: Dictionary, order: int) -> bool:
	return at_board(state) and order >= 0 and order < ORDERS \
		and rows_of(state.lines, order).is_empty() and not free_rows(state.lines).is_empty()

# 钉上来的抄件照原单自己的写法记：红单写 2 箱、蓝单写 4 瓶、绿单写 1 箱，还没对齐单位。
static func pin(state: Dictionary, order: int) -> Dictionary:
	if not can_pin(state, order): return {}
	var next = state.duplicate(true)
	var row: int = free_rows(state.lines)[0]
	next.lines[row] = [order, BOXES[order] if BOXES[order] > 0 else LOOSE[order],
		UNIT_BOX if BOXES[order] > 0 else UNIT_BOTTLE]
	return next if validate(next) else {}

static func can_unpin(state: Dictionary, row: int) -> bool:
	return at_board(state) and row >= 0 and row < LINES and state.lines[row][0] >= 0

static func unpin(state: Dictionary, row: int) -> Dictionary:
	if not can_unpin(state, row): return {}
	var next = state.duplicate(true)
	next.lines[row] = [-1,0,UNIT_BOTTLE]
	return next if validate(next) else {}

static func can_bump(state: Dictionary, row: int, step: int) -> bool:
	if not at_board(state) or row < 0 or row >= LINES or step not in [-1,1]: return false
	if state.lines[row][0] < 0: return false
	var value: int = state.lines[row][1] + step
	return value >= 1 and value <= MAX_COUNT

# 拨数量：这一行的瓶数跟着变，合计由 total_of 现算，不做任何剪枝。
static func bump(state: Dictionary, row: int, step: int) -> Dictionary:
	if not can_bump(state, row, step): return {}
	var next = state.duplicate(true)
	next.lines[row][1] += step
	return next if validate(next) else {}

static func can_convert(state: Dictionary, row: int) -> bool:
	if not at_board(state) or row < 0 or row >= LINES: return false
	if state.lines[row][0] < 0: return false
	var line: Array = state.lines[row]
	if line[2] == UNIT_BOX: return line[1] * PER_BOX <= MAX_COUNT
	return line[1] % PER_BOX == 0 and int(line[1] / float(PER_BOX)) >= 1

# 换算：箱与瓶说的是同一批货，数字要跟着单位走。装不满整箱的散瓶只能按瓶记。
static func convert(state: Dictionary, row: int) -> Dictionary:
	if not can_convert(state, row): return {}
	var next = state.duplicate(true)
	var line: Array = next.lines[row]
	if line[2] == UNIT_BOX: next.lines[row] = [line[0], line[1] * PER_BOX, UNIT_BOTTLE]
	else: next.lines[row] = [line[0], int(line[1] / float(PER_BOX)), UNIT_BOX]
	return next if validate(next) else {}

# ---- 提交闸口：一行一条真实货，单位统一到瓶，数量等于原单 ----
static func shortfalls(state: Dictionary) -> Array:
	var missing: Array = []
	var board: Array = state.lines
	for row in range(LINES):
		if board[row][0] < 0: missing.append("汇总板第 %d 行还空着：三张原单各钉一行。" % [row + 1])
	for row in duplicate_rows(board):
		missing.append("第 %d 行的%s是重复抄件：同一张原单只记一次。" % [row + 1, NAMES[board[row][0]]])
	for order in missing_orders(board):
		missing.append("%s一次都没上板：漏掉的单号就是下一次争执的开头。" % NAMES[order])
	# 三个单号都齐了才轮到排法：这块板按红、蓝、绿记，下一个人才能一眼对上。
	if missing.is_empty():
		for row in range(LINES):
			if board[row][0] != row:
				missing.append("第 %d 行钉的是%s：汇总板按红、蓝、绿的单号顺序记。" % [row + 1, NAMES[board[row][0]]])
				break
	for row in range(LINES):
		var line: Array = board[row]
		if line[0] < 0: continue
		if line[2] == UNIT_BOX:
			missing.append("第 %d 行记的是 %d 箱：箱不是瓶，先换算成瓶再记。" % [row + 1, line[1]])
		elif line[1] != bottles_of(line[0]):
			missing.append("第 %d 行写着 %d 瓶，%s实际是 %d 瓶（%s）。" % [
				row + 1, line[1], NAMES[line[0]], bottles_of(line[0]), note(line[0])])
	return missing

static func solved(state: Dictionary) -> bool:
	return shortfalls(state).is_empty()

static func advance(state: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match state.stage:
		"arrival":
			if state.beat < BEATS - 1: next.beat += 1
			else:
				next.stage = "approach"; next.beat = 0
		"approach": next.stage = "ready"
		"ready": next.stage = "puzzle"
		"puzzle":
			if not solved(state): return {}
			# 一次归档：整块板同时生效，之后所有演出都从 filed 读回。
			next.filed = state.lines.duplicate(true)
			next.stage = "filing"
		"filing": next.stage = "delivery"
		"delivery": next.stage = "complete"
		_: return {}
	return next

static func restore(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if state.stage != "puzzle": return {}
	if not snapshot.has("lines") or not snapshot.has("filed"): return {}
	if not legal_board(snapshot["lines"]) or not legal_board(snapshot["filed"]): return {}
	var next = state.duplicate(true)
	next.lines = (snapshot["lines"] as Array).duplicate(true)
	next.filed = (snapshot["filed"] as Array).duplicate(true)
	return next if validate(next) else {}

# 一块合法的板：三行、每行 [单号, 数量, 单位]，撤下的行不留数量，一张单最多两份抄件。
static func legal_board(value: Variant) -> bool:
	if not value is Array or value.size() != LINES: return false
	var board: Array = value
	for line in board:
		if not line is Array or line.size() != 3: return false
		var order: Variant = line[0]
		var count: Variant = line[1]
		var unit: Variant = line[2]
		if not order is int or not count is int or not unit is int: return false
		if order < -1 or order >= ORDERS: return false
		if unit != UNIT_BOX and unit != UNIT_BOTTLE: return false
		if order < 0:
			if count != 0: return false
			continue
		if count < 1 or count > MAX_COUNT: return false
		if rows_of(board, order).size() > COPIES: return false
	return true

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("sample") != "market-mk08-1" or value.get("stage") not in STAGES: return false
	if not value.get("beat") is int or value.beat < 0 or value.beat > BEATS - 1: return false
	if value.stage != "arrival" and value.beat != 0: return false
	if not value.get("hint") is int or value.hint < 0 or value.hint > HINTS: return false
	if not legal_board(value.get("lines")) or not legal_board(value.get("filed")): return false
	match value.stage:
		"arrival","approach","ready":
			# 还没人动过这块板：行是衡伯贴的原样，正式记录一页都没有。
			if value.lines != start_lines() or value.filed != empty_lines(): return false
		"puzzle":
			# 摆放阶段一张纸都还没归档：不存在「先记档再改单」。
			if value.filed != empty_lines(): return false
		"filing","delivery","complete":
			# 声称已经归档：正式记录必须就是板上这一份，而且这一份当时确实修好了。
			if value.filed != value.lines or not solved(value): return false
		_: return false
	return true

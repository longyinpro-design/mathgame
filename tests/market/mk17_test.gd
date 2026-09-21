extends SceneTree
# MK17 铜鹭巡守 · 三次验货：无头规则、存档与真实场景检查。
# 运行：godot --headless --path . --script tests/market/mk17_test.gd
# 检查只读 Rules/Scene/Catalog 的公开说法，另附一份手工拼现场的 pose()，
# 这样「旗固定」「机会不退」「已交不回收」这三条都能在无头里被真的按一遍。
const Rules = preload("res://scripts/market/mk17_rules.gd")
const World = preload("res://scripts/market/mk17_world.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Scene = preload("res://game/market_mk17.tscn")
const SAVE_DEFAULT = "user://profiles/market-mk17-1/save-v1.json"
const L = Rules.LARGE
const M = Rules.MEDIUM
const S = Rules.SMALL
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk17-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 手工拼一份现场；非 arrival 幕必须已经听完三句台词，和 advance 的走位一致。
func pose(stage: String, flag: int, station: int, stock: Array, tray: Array,
		delivered: Array, chances: int) -> Dictionary:
	var value = Rules.fresh()
	value.stage = stage; value.flag = flag; value.station = station
	value.stock = stock.duplicate(true); value.tray = tray.duplicate(true)
	value.delivered = delivered.duplicate(true); value.chances = chances
	value.shown = int(station >= 2)
	if stage != "arrival": value.beat = 2
	return value

# 每一幕的一份真实现场：既用来驱动绘制，也用来当校验的正例。
func stage_pose(stage: String) -> Dictionary:
	match stage:
		"arrival", "approach", "ready":
			return pose(stage, Rules.FLAG_A, 1, Rules.START_STOCK.duplicate(), Rules.empty_packs(),
				Rules.empty_deliveries(), 3)
		"puzzle":
			return pose(stage, Rules.FLAG_A, 1, [4, 0, 1], [1, 1, 0], Rules.empty_deliveries(), 2)
		"flag":
			return pose(stage, Rules.FLAG_A, 2, [4, 0, 1], Rules.empty_packs(), [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 2)
		"lift":
			return pose(stage, Rules.FLAG_A, 3, [2, 0, 0], Rules.empty_packs(), [[1, 1, 0], [2, 0, 1], [0, 0, 0]], 2)
	# 三站办完：货全交出去了，台上与托盘都空着，机会还剩 1 次
	return pose(stage, Rules.FLAG_A, 4, Rules.empty_packs(), Rules.empty_packs(),
		[[1, 1, 0], [2, 0, 1], [0, 3, 0]], 1)

func with_tray(row: Array, stock: Array, chances: int, station: int = 1,
		flag: int = Rules.FLAG_A, delivered: Array = []) -> Dictionary:
	return pose("puzzle", flag, station, stock, row,
		Rules.empty_deliveries() if delivered.is_empty() else delivered, chances)

func opened(flag: int) -> Dictionary:
	return pose("puzzle", flag, 1, Rules.START_STOCK.duplicate(), Rules.empty_packs(),
		Rules.empty_deliveries(), Rules.CHANCES)

# 「· 键盘 X」这半句是热点对自己说的话：按那个键要做出跟点这下一模一样的动作才算数，
# 否则玩家照着提示按键，等来的却是另一件事。逐条按键与点击各演一遍，比状态。
func advertised_audit(game: Node, ids: Array) -> Array:
	var keys := {"1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
		"Q": KEY_Q, "W": KEY_W, "E": KEY_E, "R": KEY_R, "F": KEY_F}
	var told = 0
	var lied = 0
	for id in ids:
		if not game.buttons.has(id): continue
		var before = game.state.duplicate(true)
		var book = game.history.duplicate(true)
		ready_input(game)
		var tip: String = game.buttons[id].tooltip_text
		var at = tip.find("键盘 ")
		if at < 0: continue
		told += 1
		# 「· 键盘 X」可能写在说明的第一行中间，取到行尾就得停，不能把下一句一起当键名。
		var key: int = keys.get(tip.substr(at + 3).split("\n")[0].strip_edges(), -1)
		if key == -1:
			lied += 1; print("牌上写着认不出的键：", id, " 「", tip, "」")
			continue
		for conn in game.buttons[id].get_signal_connection_list("pressed"):
			conn["callable"].call()
		ready_input(game)
		var by_click = game.state.duplicate(true)
		game.apply_committed(before, book); ready_input(game)
		game.handle_key(key)
		ready_input(game)
		var by_key = game.state.duplicate(true)
		game.apply_committed(before, book); ready_input(game)
		if by_click != by_key:
			lied += 1
			print("键与点不是一回事 ", id, " 「", tip, "」 点了 ", by_click, " 按了 ", by_key)
	return [told, lied]

# 口条的内框只有 798 宽（Rect2(338,98,826,86) 去掉 14/28 边距），汉字不会自己断行。
func line_fits(value: String, width: float) -> bool:
	var widest = 0.0
	for line in value.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UIStyle.text_size(20)).x)
	return widest <= width

# 只把动画一幕一幕推过去，不依赖计时器：等价于玩家按「跳过当前动画」。
func settle(state: Dictionary) -> Dictionary:
	if state.is_empty(): return state
	for step in range(8):
		if state.stage not in Rules.ANIMATIONS: break
		state = Rules.advance(state)
	return state

func take(state: Dictionary, kind: int) -> Dictionary:
	if state.is_empty(): return state
	return Rules.load_pack(state, kind)

func send(state: Dictionary) -> Dictionary:
	if state.is_empty(): return state
	return settle(Rules.advance(state))

func loads(state: Dictionary, row: Array) -> Dictionary:
	for kind in range(Rules.KINDS):
		for step in range(row[kind]): state = take(state, kind)
	return state

func named(missing: Array, ordinal: String) -> bool:
	for line in missing:
		if ordinal in line: return true
	return false

# 实窗里的落地锁与动画计时在无头里会挡住下一步：按一下就当作已经松开。
func ready_input(game) -> void:
	game.paused = true; game.transient = 0.0; game.world.land_progress = 1.0; game.refresh()

func skip(game) -> void:
	for step in range(8):
		ready_input(game)
		if game.state.stage not in Rules.ANIMATIONS: break
		game.skip_animation()

# 热点几何：登记了吗、够不够 48、缩放镜头下还在不在画面里、有没有中文说明。
func frame_report(game, ids: Array) -> Array:
	var present = true
	var sized = true
	var framed = true
	var tips = true
	for id in ids:
		if not game.buttons.has(id): present = false; continue
		var button: Button = game.buttons[id]
		if button.size.x < 48 or button.size.y < 48: sized = false
		var rect = button.get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
		if button.tooltip_text.is_empty(): tips = false
	return [present, sized, framed, tips]

# 撤销之后除了摆法，别的东西一律不动。
func untouched(value: Dictionary) -> bool:
	if value.is_empty(): return false
	return value.stage == "puzzle" and value.station == 1 and value.flag == Rules.FLAG_A \
		and value.delivered == Rules.empty_deliveries()

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("MK17 rule watchdog"); quit(1))
	# ---- 开局与常量：契约里的数字先钉住 ----
	var start = Rules.fresh()
	check(Rules.validate(start), "fresh model valid")
	check(start.sample == "market-mk17-1", "fresh carries the mk17 sample id")
	check(start.stage == "arrival" and start.beat == 0 and start.hint == 0, "fresh opens on the three dialogue beats")
	check(start.stock == [6, 0, 0] and start.tray == [0, 0, 0] and start.chances == 3, "six 大包 and three repack chances on the dock")
	check(start.station == 1 and start.shown == 0, "the flag stays folded until the first station is served")
	check(start.flag in [Rules.FLAG_A, Rules.FLAG_B], "fresh rolls one of the two shipped flags")
	check(Rules.UNITS == [3, 2, 1] and Rules.TOTAL_UNITS == 18, "大包=3、中包=2、小包=1，共 18 单位")
	check(Rules.DEMAND == [5, 7, 6] and Rules.MAX_PACKS == [2, 4, 3], "三站要 5/7/6 单位、最多 2/4/3 包")
	check(Rules.DEMAND[0] + Rules.DEMAND[1] + Rules.DEMAND[2] == Rules.TOTAL_UNITS, "三站需求之和正好等于全部 18 单位")
	check(Rules.OPS.size() == 4 and Rules.CHANCES == 3, "两条规则的四端、三次机会")
	check(Rules.MAX_TRAY == 6, "托盘最多摆 6 包")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "flag", "lift", "carrying", "delivery", "complete"],
		"stage list is the dialogue, three stations and the two hand-offs")
	check(Rules.ANIMATIONS == ["approach", "flag", "lift", "carrying", "delivery"], "only the five transitions animate")
	for stage in Rules.STAGES: check(Rules.validate(stage_pose(stage)), "%s 那一幕的现场本身合法" % stage)
	# 站与旗的约定：三站固定不接大包，二站看那面开局就定下的旗
	var board = opened(Rules.FLAG_B)
	check(not Rules.accepts_large(board, 2) and not Rules.accepts_large(board, 1), "旗B：二站与三站都不接大包，翻旗之前也已成立")
	var board_a = opened(Rules.FLAG_A)
	check(Rules.accepts_large(board_a, 1) and not Rules.accepts_large(board_a, 2), "旗A：二站全收，三站仍不接大包")
	check(Rules.accepts_large(board_a, 0), "一站大小包都收")
	# 一站 5 单位 / 最多 2 包：全部摆法里只有 1大+1中 这一种
	var first_ways = []
	for a in range(7):
		for b in range(10):
			for c in range(4):
				if Rules.rule_met(board_a, 0, [a, b, c]): first_ways.append([a, b, c])
	check(first_ways == [[1, 1, 0]], "一站只有「1大+1中」这一种摆法，所以第一次机会非动不可")
	# ---- 参考应对一：旗A 用 2 次机会 ----
	var a_run = Rules.apply_op(opened(Rules.FLAG_A), 0)
	check(not a_run.is_empty() and a_run.chances == 2 and a_run.stock == [5, 1, 1], "1大 → 1中+1小 真的走通，并只花掉 1 次机会")
	a_run = send(loads(a_run, [1, 1, 0]))
	check(a_run.stage == "puzzle" and a_run.station == 2 and a_run.shown == 1, "一站交完，旗翻面，二站开始")
	check(a_run.delivered[0] == [1, 1, 0] and a_run.stock == [4, 0, 1], "一站收下的那两包钉在栈位上，不再回到台面")
	a_run = send(loads(a_run, [2, 0, 1]))
	check(a_run.station == 3 and a_run.chances == 2, "旗A：二站交 2大+1小，机会还剩 2 次")
	a_run = send(loads(Rules.apply_op(a_run, 2), [0, 3, 0]))
	check(a_run.stage == "complete" and a_run.chances == 1, "旗A 参考应对共用 2 次机会")
	check(a_run.delivered == [[1, 1, 0], [2, 0, 1], [0, 3, 0]], "旗A：三站各收到 1大1中 / 2大1小 / 3中")
	check(Rules.held_units(a_run) == 0 and Rules.validate(a_run), "旗A 收完一单位不剩，存档仍然合法")
	# ---- 参考应对二：旗B 用满 3 次机会 ----
	var b_run = send(loads(Rules.apply_op(opened(Rules.FLAG_B), 0), [1, 1, 0]))
	b_run = send(loads(Rules.apply_op(b_run, 2), [0, 3, 1]))
	check(b_run.station == 3 and b_run.chances == 1, "旗B：二站交 3中+1小，只剩 1 次机会")
	b_run = send(loads(Rules.apply_op(b_run, 2), [0, 3, 0]))
	check(b_run.stage == "complete" and b_run.chances == 0, "旗B 参考应对用满 3 次机会")
	check(b_run.delivered == [[1, 1, 0], [0, 3, 1], [0, 3, 0]], "旗B：三站各收到 1大1中 / 3中1小 / 3中")
	check(Rules.held_units(b_run) == 0 and Rules.validate(b_run), "旗B 收完一单位不剩，存档仍然合法")
	# 两面旗都得真的掷得出来，重读不换
	seed(11)
	var rolled = Rules.fresh().flag
	seed(11)
	check(rolled == Rules.fresh().flag, "同一颗种子重掷两次得到同一面旗")
	var seen = {}
	for probe_seed in range(12):
		seed(probe_seed)
		seen[Rules.fresh().flag] = true
	check(seen.has(Rules.FLAG_A) and seen.has(Rules.FLAG_B), "两面旗都会出现，检查两边都有解")
	# ---- 机会的账：绝不存在「退机会又留货」 ----
	check(Rules.apply_op(a_run, 1).is_empty(), "办完三站之后没有机会也没有货可以再走")
	check(Rules.apply_op(opened(Rules.FLAG_A), 1).is_empty(), "台上没有中包与小包时，「中包+小包 → 大包」走不通")
	var there = Rules.apply_op(Rules.apply_op(opened(Rules.FLAG_A), 0), 1)
	check(there.chances == 1 and there.stock == [6, 0, 0], "反着走同一条规则要再花 1 次机会，机会不会随货退回")
	check(Rules.units_of(there.stock) == 18 and Rules.packs_of(there.stock) == 6, "来回一次只退回包数，单位一克没多")
	var broke = pose("puzzle", Rules.FLAG_A, 1, [6, 0, 0], Rules.empty_packs(), Rules.empty_deliveries(), 0)
	check(Rules.apply_op(broke, 0).is_empty() and "机会" in Rules.refusal(broke, 0), "机会用完就走不了下一步，拒绝里说清是机会")
	check("回到关前规划" in Rules.refusal(broke, 0), "机会用尽的拒绝给出回关前规划这条路")
	check(Rules.apply_op(opened(Rules.FLAG_A), 4).is_empty(), "第 5 条走法不存在，点了什么也不改")
	check(not Rules.refusal(opened(Rules.FLAG_A), 9).is_empty(), "越界的走法也有话说")
	var ops_ok = true
	for index in range(Rules.OPS.size()):
		var probe = pose("puzzle", Rules.FLAG_A, 2, [2, 3, 1], Rules.empty_packs(),
			[[1, 1, 0], [0, 0, 0], [0, 0, 0]], 1)
		var moved = Rules.apply_op(probe, index)
		if moved.is_empty(): ops_ok = false; continue
		if moved.chances != probe.chances - 1: ops_ok = false
		if Rules.units_of(moved.stock) != Rules.units_of(probe.stock): ops_ok = false
		if absi(Rules.packs_of(moved.stock) - Rules.packs_of(probe.stock)) != 1: ops_ok = false
	check(ops_ok, "四条走法每条恰好花 1 次机会、单位不变、包数只动 1")
	# ---- 装托盘 / 放回：还没离手，随时反悔 ----
	var tray = take(opened(Rules.FLAG_A), L)
	check(tray.stock == [5, 0, 0] and tray.tray == [1, 0, 0], "把大包放上验货托盘：台面上少一只，托盘上多一只")
	check(Rules.units_of(tray.stock) + Rules.units_of(tray.tray) == 18, "上托盘不产生也不消灭任何单位")
	tray = take(Rules.apply_op(tray, 0), M)
	check(tray.tray == [1, 1, 0], "封装出来的那只中包也能放上托盘")
	check(Rules.unload_slot(tray, 0).tray == [0, 1, 0], "点托盘上的第一包把它放回台面")
	check(Rules.unload_slot(tray, 5).is_empty(), "空着的那一格没有货可退")
	check(Rules.unload_slot(tray, -1).is_empty(), "负号槽位是伪造，不是空位")
	var full = with_tray([3, 2, 1], [0, 2, 0], 1)
	check(Rules.packs_of(full.tray) == Rules.MAX_TRAY and Rules.validate(full), "托盘摆满 6 包的现场合法")
	check(Rules.load_pack(full, L).is_empty() and "6 包" in Rules.load_refusal(full, L), "托盘摆满 6 包就装不下了，说法里给出上限")
	check(Rules.load_pack(opened(Rules.FLAG_A), M).is_empty() and "中包" in Rules.load_refusal(opened(Rules.FLAG_A), M),
		"台上没有中包时不凭空拿：先封装变出来")
	check(Rules.load_pack(stage_pose("flag"), L).is_empty(), "翻旗那一幕不在码头上，摆不了货")
	# ---- 提交验收：缺哪条承诺就点名哪条 ----
	var near = pose("puzzle", Rules.FLAG_A, 1, [4, 1, 0], [1, 0, 1], Rules.empty_deliveries(), 2)
	var missing = Rules.shortfalls(near)
	check(missing.size() == 1 and "4 单位" in missing[0] and "差 1" in missing[0], "3+1 只有 4 单位：只说单位差多少")
	check("最多" not in missing[0], "单位不对时不顺手编一条包数的错")
	near = with_tray([0, 2, 1], [4, 0, 1], 1)
	missing = Rules.shortfalls(near)
	check(missing.size() == 1 and "最多只收 2 包" in missing[0], "6 单位摆 3 包：只说包数超了")
	check("单位" not in missing[0], "包数超了而单位正好，就不提单位")
	near = pose("puzzle", Rules.FLAG_B, 2, [2, 3, 1], [2, 0, 1], [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 1)
	missing = Rules.shortfalls(near)
	check(missing.size() == 1 and "旗B" in missing[0] and "不接大包" in missing[0], "旗B 的二站只按旗拒绝，不编别的错")
	near = pose("puzzle", Rules.FLAG_A, 3, [2, 0, 0], [2, 0, 0], [[1, 1, 0], [0, 3, 1], [0, 0, 0]], 0)
	missing = Rules.shortfalls(near)
	check(missing.size() == 1 and "三站固定不接大包" in missing[0], "三站固定不接大包，与旗无关")
	var empty_tray = Rules.shortfalls(opened(Rules.FLAG_A))
	check(empty_tray.size() == 1 and named(empty_tray, "一站") and "托盘上还什么都没放" in empty_tray[0],
		"空托盘也按当前这一站说话")
	check(Rules.solved(with_tray([1, 1, 0], [4, 0, 1], 2)), "1大+1中 满足一站")
	check(not Rules.solved(with_tray([0, 2, 1], [4, 0, 1], 1)), "2中+1小 单位对但包数超")
	check(not Rules.solved(with_tray([1, 0, 2], [4, 0, 1], 1)), "1大2小 单位对但包数超")
	var big_two = with_tray([2, 0, 1], [0, 3, 0], 1, 2, Rules.FLAG_B, [[1, 1, 0], [0, 0, 0], [0, 0, 0]])
	var big_two_a = with_tray([2, 0, 1], [0, 3, 0], 1, 2, Rules.FLAG_A, [[1, 1, 0], [0, 0, 0], [0, 0, 0]])
	check(not Rules.solved(big_two) and Rules.solved(big_two_a), "同一摆法：旗B 不收，旗A 收下")
	check(Rules.advance(opened(Rules.FLAG_A)).is_empty(), "没满足约定就不能推进：advance 不替玩家判通过")
	# ---- 走死了如实说：浪费一次机会会把旗B 走死 ----
	var stuck = Rules.apply_op(opened(Rules.FLAG_B), 0)
	stuck = send(loads(stuck, [1, 1, 0]))
	stuck = Rules.apply_op(stuck, 0)
	stuck = Rules.apply_op(stuck, 2)
	stuck = send(loads(stuck, [0, 3, 1]))
	check(stuck.stage == "puzzle" and stuck.station == 3 and stuck.chances == 0 and stuck.stock == [1, 1, 1],
		"旗B 里多拆一次：三站只剩 1大1中1小、0 次机会")
	check(Rules.dead_end(stuck) and not Rules.can_serve(stuck), "这一步之后三站办不成，dead_end 认出来")
	check(Rules.dead_end(loads(stuck, [1, 1, 1])), "把货摆上托盘也还是办不成：不给假希望")
	var stuck_said = Rules.shortfalls(loads(stuck, [1, 1, 1]))
	check(named(stuck_said, "三站") and "大包" in stuck_said[0], "拒绝里点名失败的那一站与那条约定")
	var alive = pose("puzzle", Rules.FLAG_B, 3, [2, 0, 0], Rules.empty_packs(), [[1, 1, 0], [0, 3, 1], [0, 0, 0]], 1)
	check(not Rules.dead_end(alive) and Rules.can_serve(alive), "同样到三站、还剩 1 次机会就不是死局")
	check(not Rules.dead_end(loads(Rules.apply_op(opened(Rules.FLAG_A), 0), [1, 1, 0])), "开局摆好一站不是死局")
	# 只看脚前这一站的判法会在这里给出假活路：二站照样交得出去，交完才发现三站再凑不齐。
	var doomed = pose("puzzle", Rules.FLAG_B, 2, [3, 1, 2], Rules.empty_packs(), [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 1)
	check(Rules.can_serve(doomed) and not Rules.can_finish(doomed), "旗B 二站剩一次机会：二站交得出去，三站就没货了")
	check(Rules.dead_end(doomed), "把剩下的站一起往前推，这一格当场就认死")
	var wasted = Rules.apply_op(Rules.apply_op(Rules.apply_op(opened(Rules.FLAG_A), 0), 0), 0)
	check(wasted.stock == [3, 3, 3] and wasted.chances == 0 and wasted.station == 1, "一站里把三次机会全花在同一个方向")
	check(Rules.can_serve(wasted) and not Rules.can_finish(wasted), "一站交得出去、三站却办不成：本站的活路不算活路")
	check(Rules.dead_end(wasted), "死局在摆上托盘之前就认出来，不用走到下一站")
	check(Rules.can_finish(opened(Rules.FLAG_A)) and Rules.can_finish(opened(Rules.FLAG_B)),
		"两面旗开局都还有路：死局是走出来的，不是发牌发出来的")
	check(not Rules.dead_end(stage_pose("lift")), "不在码头上那一格，dead_end 不开口")
	# ---- 撤销整站交货：货和幕一起回来，不发明货物 ----
	var rewind = Rules.undeliver(stuck)
	check(not rewind.is_empty() and rewind.station == 2 and rewind.tray == [0, 3, 1], "退回上一站：那四包回到托盘")
	check(Rules.units_of(rewind.stock) + Rules.units_of(rewind.tray) + Rules.delivered_units(rewind) == 18,
		"退回整站之后 18 单位一克不少")
	check(rewind.chances == stuck.chances, "退回交货绝不补一次封装机会")
	check(Rules.validate(rewind) and Rules.undeliver(rewind).is_empty(), "退回之后账还是合法的，也退不出第三站")
	check(not Rules.can_undeliver(loads(Rules.apply_op(opened(Rules.FLAG_A), 0), [1, 1, 0])), "一站还没交，没有上一站可退")
	var first = send(loads(Rules.apply_op(opened(Rules.FLAG_A), 0), [1, 1, 0]))
	check(not Rules.can_undeliver(first) and "一站的货已经" in Rules.undeliver_refusal(first),
		"一站交完就退不回来，说法指向「回到关前规划」")
	check(Rules.undeliver(first).is_empty(), "退不回来的那一站真的什么都没退")
	# 托盘上还摆着货的时候退整站：两批货会叠在一起，退回时必有一批凭空蒸发，所以直接不让你退。
	var stacked = loads(stuck, [1, 1, 1])
	check(Rules.has_previous_delivery(stacked) and not Rules.can_undeliver(stacked),
		"上一站的货在，可托盘上也摆着货：整站退不了")
	check("放回台面" in Rules.undeliver_refusal(stacked) and "3 包" in Rules.undeliver_refusal(stacked),
		"退不了的那句说清了先腾出托盘，还报出真正摆着的包数")
	check(Rules.undeliver(stacked).is_empty()
		and Rules.units_of(stacked.stock) + Rules.units_of(stacked.tray) + Rules.delivered_units(stacked) == 18,
		"退不了的时候一单位也不动：没有一批货会凭空蒸发")
	check(not Rules.has_previous_delivery(first) and not Rules.can_undeliver(first), "二站还没有上一站可退")
	# ---- 幕的推进 ----
	var walk = Rules.advance(Rules.advance(Rules.fresh()))
	check(walk.beat == 2 and walk.stage == "arrival", "三句台词按拍子走完")
	check(Rules.advance(walk).stage == "approach", "台词说完，铜鹭踏着栈桥进来")
	check(Rules.advance(Rules.advance(walk)).stage == "ready", "入幕后先把三张货单钉在栏上")
	var ready = Rules.advance(Rules.advance(walk))
	check(Rules.advance(ready).stage == "puzzle" and Rules.advance(ready).stock == Rules.START_STOCK,
		"开始验货不碰任何货")
	check(Rules.advance(ready).chances == 3, "开始验货也不动机会")
	check(Rules.advance(stage_pose("complete")).is_empty(), "complete 没有下一幕可编")
	check(Rules.advance(pose("elsewhere", Rules.FLAG_A, 1, Rules.START_STOCK.duplicate(), Rules.empty_packs(),
		Rules.empty_deliveries(), 3)).is_empty(), "不认识的幕不推进")
	check(Rules.advance(stage_pose("flag")).stage == "puzzle", "翻旗之后回到码头摆二站的货")
	check(Rules.advance(stage_pose("lift")).stage == "puzzle", "二站吊上蓝船之后回到码头摆三站")
	check(Rules.advance(stage_pose("carrying")).stage == "delivery", "三站办完，铜鹭展翼把自己变成搬运台")
	check(Rules.advance(stage_pose("delivery")).stage == "complete", "灯火亮起，这一幕收在回执上")
	# ---- 撤销快照：只退本站的摆法 ----
	var mid = loads(Rules.apply_op(opened(Rules.FLAG_A), 0), [1, 1, 0])
	var snap = {"station": 1, "stock": [4, 1, 1], "tray": [1, 0, 0], "chances": 2, "delivered": Rules.empty_deliveries()}
	var undone = Rules.restore(mid, snap)
	check(not undone.is_empty() and undone.stock == [4, 1, 1] and undone.tray == [1, 0, 0] and undone.chances == 2,
		"撤销把上一步的摆法一起退回去")
	check(untouched(undone), "撤销只改摆法：幕、旗、站都不动")
	check(Rules.restore(mid, {"station": 2, "stock": [4, 1, 1], "tray": [1, 0, 0], "chances": 2,
		"delivered": Rules.empty_deliveries()}).is_empty(), "上一站的快照不属于本站，撤销拒绝")
	check(Rules.restore(mid, {"stock": [4, 1, 1], "tray": [1, 0, 0], "chances": 2}).is_empty(), "缺 station 的快照是伪造")
	check(Rules.restore(mid, {"station": 1, "stock": mid.stock, "tray": mid.tray, "chances": 3,
		"delivered": Rules.empty_deliveries()}).is_empty(), "机会退回来、货却留着：这种撤销不存在")
	var flat = Rules.restore(mid, {"station": 1, "stock": [6, 0, 0], "tray": [0, 0, 0], "chances": 3,
		"delivered": Rules.empty_deliveries()})
	check(not flat.is_empty() and flat.stock == Rules.START_STOCK and flat.chances == 3,
		"连封装那一步一起退：货与机会同时回来，账才平")
	check(Rules.restore(stage_pose("flag"), snap).is_empty(), "翻旗那一幕不在码头上，撤销不生效")
	# ---- 存档 schema：伪造与损坏 ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record " + str(bad))
	var forged = opened(Rules.FLAG_A)
	forged.sample = "market-mk16-1"
	check(not Rules.validate(forged), "别的关卡的存档不认")
	for field in [["stage", "checking"], ["hint", 4], ["hint", -1], ["flag", 0], ["flag", 3], ["flag", "A"],
			["shown", 2], ["station", 0], ["station", 5], ["chances", 4], ["chances", -1], ["beat", 3]]:
		forged = opened(Rules.FLAG_A)
		forged[field[0]] = field[1]
		check(not Rules.validate(forged), "坏字段 %s=%s 被拒" % [field[0], str(field[1])])
	for missing_field in ["stock", "tray", "delivered", "chances", "flag", "shown", "station", "beat", "hint"]:
		forged = opened(Rules.FLAG_A)
		forged.erase(missing_field)
		check(not Rules.validate(forged), "缺 %s 的存档是损坏不是默认值" % missing_field)
	var packs = [
		[[7, 0, 0], "七只大包：三次机会变不出来"],
		[[6, 0, 4], "四只小包：拆不出第四只"],
		[[6, 10, 0], "十只中包：超出包数上限"],
		[[6, 0, -1], "负数包"],
		[[6, 0, 1.5], "半只包"],
		[[6], "包数数组短了一截"],
	]
	for row in packs:
		forged = pose("puzzle", Rules.FLAG_A, 1, row[0], Rules.empty_packs(), Rules.empty_deliveries(), 3)
		check(not Rules.validate(forged), row[1])
	forged = pose("puzzle", Rules.FLAG_A, 1, [0, 3, 0], [1, 3, 3], Rules.empty_deliveries(), 1)
	check(Rules.packs_of(forged.tray) == Rules.MAX_TRAY + 1 and Rules.units_of(forged.stock) + Rules.units_of(forged.tray) == 18
		and not Rules.validate(forged),
		"托盘摆到第 7 包：单位一克不多，可柜面上没有那个位置，也不认")
	forged = pose("puzzle", Rules.FLAG_A, 2, [4, 0, 0], Rules.empty_packs(), [[2, 0, 0], [0, 0, 0], [0, 0, 0]], 3)
	check(not Rules.validate(forged), "一站交 2 大包是 6 单位，不是 5")
	forged = pose("puzzle", Rules.FLAG_A, 1, [6, 0, 0], Rules.empty_packs(), [[0, 0, 0], [0, 3, 1], [0, 0, 0]], 3)
	check(not Rules.validate(forged), "二站收过而一站没收：站序不能跳")
	forged = pose("puzzle", Rules.FLAG_B, 3, [0, 3, 0], Rules.empty_packs(), [[1, 1, 0], [2, 0, 1], [0, 0, 0]], 1)
	check(not Rules.validate(forged), "旗B 的二站收过大包：这一条约定不许改写")
	forged = pose("puzzle", Rules.FLAG_A, 4, Rules.empty_packs(), Rules.empty_packs(), [[1, 1, 0], [2, 0, 1], [2, 0, 0]], 2)
	check(not Rules.validate(forged), "三站收过 2 大包：固定不接大包写进校验")
	forged = pose("puzzle", Rules.FLAG_A, 2, [3, 0, 0], Rules.empty_packs(), [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 2)
	check(not Rules.validate(forged), "少了一只大包：18 单位不能凭空蒸发")
	forged = pose("puzzle", Rules.FLAG_A, 2, [4, 1, 1], Rules.empty_packs(), [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 2)
	check(not Rules.validate(forged), "多出一中一小：账对不上就是伪造")
	forged = pose("puzzle", Rules.FLAG_A, 1, [5, 1, 1], Rules.empty_packs(), Rules.empty_deliveries(), 3)
	check(not Rules.validate(forged), "走过一步封装却不扣机会")
	forged = pose("puzzle", Rules.FLAG_A, 1, [3, 3, 3], Rules.empty_packs(), Rules.empty_deliveries(), 1)
	check(not Rules.validate(forged), "包数比机会允许的更多：凭空造货")
	forged = pose("flag", Rules.FLAG_A, 1, [4, 0, 1], Rules.empty_packs(), [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 2)
	check(not Rules.validate(forged), "翻旗那一幕必须已经在二站")
	forged = pose("flag", Rules.FLAG_A, 2, [4, 0, 0], [0, 0, 1], [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 2)
	check(not Rules.validate(forged), "翻旗的时候托盘该空着：货已经交出去了")
	forged = pose("complete", Rules.FLAG_A, 4, [0, 3, 0], Rules.empty_packs(), [[1, 1, 0], [2, 0, 1], [0, 3, 0]], 1)
	check(not Rules.validate(forged), "办完三站还留着货：18 单位的账立刻对不上")
	forged = opened(Rules.FLAG_A); forged.beat = 1
	check(not Rules.validate(forged), "台词没走完就写成后面的幕")
	forged = pose("puzzle", Rules.FLAG_A, 2, [4, 0, 1], Rules.empty_packs(), [[1, 1, 0], [0, 0, 0], [0, 0, 0]], 2)
	forged.shown = 0
	check(not Rules.validate(forged), "二站还没翻旗：旗与站序必须一起说真话")
	forged = opened(Rules.FLAG_A); forged.shown = 1
	check(not Rules.validate(forged), "一站还没交就翻旗：不认")
	forged = pose("ready", Rules.FLAG_B, 1, Rules.START_STOCK.duplicate(), Rules.empty_packs(), Rules.empty_deliveries(), 3)
	check(Rules.validate(forged), "关前规划的那一幕合法")
	forged.stock = [5, 1, 1]
	check(not Rules.validate(forged), "开始验货之前不该已经封过包")
	forged = pose("puzzle", Rules.FLAG_A, 1, [5, 1, 1], Rules.empty_packs(), Rules.empty_deliveries(), 2)
	forged.chances = 2.0
	check(not Rules.validate(forged) and Rules.validate(Content.normalize_numbers(forged)),
		"chances 写成浮点：归一化之后仍是合法存档")
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(a_run)))
	check(round_trip == a_run and Rules.validate(round_trip), "办完的三站经历一次 JSON 往返仍是同一份账")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh())))), "开局存档能过 JSON 往返")
	# ---- 货单文字：开局就能读，不替玩家判分 ----
	var sheet_a = Rules.rule_caption(opened(Rules.FLAG_A), 1)
	var sheet_b = Rules.rule_caption(opened(Rules.FLAG_B), 1)
	check(sheet_a == sheet_b and "旗A" in sheet_a and "旗B" in sheet_a, "没翻旗之前二站把两种可能一并写出来")
	check("5" in Rules.rule_caption(opened(Rules.FLAG_A), 0) and "2" in Rules.rule_caption(opened(Rules.FLAG_A), 0),
		"一站的货单写着单位与包数两条")
	check("不接大包" in Rules.rule_caption(opened(Rules.FLAG_A), 2), "三站的货单从一开始就写死不收大包")
	check("大小包都收" in Rules.rule_caption(a_run, 1), "旗A 翻出来之后二站按那面旗说")
	check("不接大包" in Rules.rule_caption(b_run, 1), "旗B 翻出来之后二站也按那面旗说")
	check(Rules.delivery_caption(a_run, 1) == "二站 2大包 1小包 = 7 单位 · 3 包", "回执按玩家真正交出去的包复述")
	check(Rules.delivery_caption(stuck, 1) == "二站 3中包 1小包 = 7 单位 · 4 包", "旗B 的回执复述另一条路")
	# ---- 提示与文案（离树探针，用完即释） ----
	var probe_scene = Scene.instantiate(); probe_scene.configure()
	check(probe_scene.save_path == SAVE_DEFAULT, "本关默认写 market-mk17-1 存档")
	probe_scene.free()
	probe_scene = Scene.instantiate(); probe_scene.save_path = path; probe_scene.configure()
	check(probe_scene.save_path == path, "configure 不覆盖测试注入的存档路径")
	check(probe_scene.scene_id == "dock" and probe_scene.level_id == "MK17", "本关认得自己的 kit 场景与编号")
	check(probe_scene.title == Catalog.card_title("MK17"), "招牌与航图卡同一个短名")
	# 抬头木牌内框只有 382，全名「铜鹭巡守 · 三次验货」量到 386 会把「货」折到板外。
	var header_w = UIStyle.face().get_string_size("千灯集市  /  "+probe_scene.title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(24)).x
	check(header_w <= 382.0, "抬头「千灯集市 / %s」量到 %.0f，装得下那块木牌" % [probe_scene.title, header_w])
	check(probe_scene.rules == Rules and probe_scene.world_script != null, "宿主接上了 mk17 的规则与世界层")
	for stage in Rules.ANIMATIONS: check(probe_scene.durations.has(stage), "动画 %s 有明确时长" % stage)
	check(probe_scene.zoom_stages.has("puzzle") and probe_scene.zoom_stages.has("flag"), "摆货与翻旗都贴着台面看")
	check(probe_scene.hint_texts().size() == Rules.HINTS, "三级提示，没有更多")
	for spoken in probe_scene.hint_texts():
		check(not spoken.is_empty() and spoken.count("\n") <= 1, "提示 %s 不超过两行" % spoken.left(4))
	probe_scene.state = opened(Rules.FLAG_A)
	check("\n" not in probe_scene.goal_line() and "\n" not in probe_scene.status_line(), "目标与状态各占一行")
	check("封装余 3" in probe_scene.status_line() and "旗未翻" in probe_scene.status_line(), "状态栏说清余下几次、旗还没翻")
	probe_scene.state = stuck
	check("封装余 0" in probe_scene.status_line() and "旗B" in probe_scene.status_line(), "状态栏跟着真实的旗与机会走")
	for beat in range(3):
		var opening = Rules.fresh(); opening.beat = beat
		probe_scene.state = opening
		var text = probe_scene.line()
		check(not text.is_empty() and text.count("\n") <= 1, "开场第 %d 句不超过两行" % (beat + 1))
	check("旗A" in probe_scene.line() and "旗B" in probe_scene.line(), "开场就把两面旗的可能都讲给玩家")
	for stage in Rules.STAGES:
		probe_scene.state = stage_pose(stage)
		check(not probe_scene.line().is_empty(), "幕 %s 总有一句可说" % stage)
		check(probe_scene.line().count("\n") <= 1, "幕 %s 的台词不超过两行" % stage)
	for station in range(1, 4):
		probe_scene.state = stage_pose("puzzle"); probe_scene.state.station = station
		if station == 2: probe_scene.state.shown = 1; probe_scene.state.delivered = [[1, 1, 0], [0, 0, 0], [0, 0, 0]]
		if station == 3:
			probe_scene.state.delivered = [[1, 1, 0], [2, 0, 1], [0, 0, 0]]; probe_scene.state.shown = 1
			probe_scene.state.stock = [2, 0, 0]
		check("站" in probe_scene.puzzle_line(), "%d 站的台上话点得出是哪一站" % station)
	probe_scene.state = stage_pose("lift")
	for tip in [probe_scene.op_tip(0), probe_scene.take_tip(L), probe_scene.unload_tip(0, M),
			probe_scene.berth_tip(1), probe_scene.flag_tip()]:
		check(not tip.is_empty() and tip.count("\n") <= 1, "热点说明 %s 不超过两行" % tip.left(6))
	check("花 1 次机会" in probe_scene.op_tip(0), "封装牌上先写清这一步要花一次机会")
	check("重新读档也不会换旗" in probe_scene.flag_tip(), "翻出来的旗上写明重读不换")
	probe_scene.state = stage_pose("ready")
	check("两种可能" in probe_scene.flag_tip(), "没翻旗之前热点上也写着两种可能")
	check(probe_scene.restart_prompt().size() == 3 and probe_scene.reset_prompt().size() == 3, "两条回退都先问一句")
	check("已经用掉的封装机会不会退回来" in probe_scene.reset_prompt()[0], "重摆的确认里说清机会不退")
	probe_scene.state = a_run
	check(probe_scene.receipt_lines().size() == 7, "回执七行：标题、三站、旗、机会、余货")
	probe_scene.free()
	# ---- 真实场景：站位、拆件、按钮 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); ready_input(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "真场景开局站在台词前")
	check(not game.buttons.has("deliver"), "还没到码头，提交按钮不亮")
	check(game.world.scene_id == "dock" and game.world.stations.has("packing"), "舞台读的是 manifest 的 dock 站位")
	for anchor in ["packing", "boss_foot", "boat_red", "boat_blue", "lantern"]:
		check(game.world.stations.has(anchor), "dock 场景里有 %s 这个站位" % anchor)
	var parts = []
	parts.append_array(game.world.PACK_ART); parts.append_array(game.world.BOAT_ART)
	parts.append_array(["paper_roll", "receiving_tray", "receipt_blank", "brass_bell", "lantern_string", "navigation_lantern"])
	for part in parts: check(game.world.has_part(part), "拆件包里有 %s" % part)
	# 三个栈位由两条船等距外推，不另立第二套坐标
	var step = game.world.berth_step()
	check(step == game.world.station("boat_blue") - game.world.station("boat_red"), "栈距就是船距")
	check(game.world.berth_foot(1) - game.world.berth_foot(0) == step, "栈位一个等距排在另一个右边")
	check(game.world.berth_rect(0).size.x >= 48 and game.world.berth_rect(0).size.y >= 48, "栈位牌的命中区够大")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); ready_input(game); await process_frame
	game.commit(stuck); ready_input(game)
	check(game.state.stage == "puzzle" and game.state.station == 3 and game.history.is_empty(), "读档直接回到三站的码头")
	var hotspots = ["flag", "take_0", "take_1", "take_2", "op_0", "op_1", "op_2", "op_3", "berth_0", "berth_1", "berth_2"]
	var report = frame_report(game, hotspots)
	check(report[0], "码头上的 %d 类热点全部登记" % hotspots.size())
	check(report[1], "每个热点至少 48×48 逻辑像素")
	check(report[2], "缩放镜头下每个热点都还在画面里，也不压住底栏")
	check(report[3], "每个热点都有中文说明")
	check(game.buttons.has("plan"), "走死了就给出「回到关前规划」")
	check(game.buttons.has("rewind"), "三站的码头上能「退回上一站的货」")
	check(not game.buttons.plan.text.is_empty() and not game.buttons.rewind.text.is_empty(), "两条出路都写着中文")
	check(game.buttons.has("deliver") and not game.buttons.deliver.disabled, "提交按钮在码头上亮着")
	check(game.buttons.undo.disabled and "上一站的货不回收" in game.buttons.undo.tooltip_text,
		"没有本站摆法时撤销不亮，说明里指清退的是哪一段")
	check(game.buttons.has("reset") and game.buttons.has("hint"), "码头给得出「重摆」与「请扣扣提醒」")
	# 一站上那两块牌子都还没画出来：撤销的说明不能指向玩家摸不到的地方。
	game.apply_committed(opened(Rules.FLAG_A), []); ready_input(game)
	check(not game.buttons.has("plan") and not game.buttons.has("rewind"), "一站既没有退整站、也还没走死")
	check("退回上一站的货" not in game.buttons.undo.tooltip_text and "回到关前规划" not in game.buttons.undo.tooltip_text,
		"没有那两块牌子时，撤销只说「先把货摆上托盘」")
	# ---- 键盘层：牌上写的那颗键，按下去必须和点这一下做出同一个动作 ----
	var told = 0
	var mistaken = 0
	# 四种现场：托盘空着、只一包、最后一包不是选中的那种、摆满六包。
	for layout in [[[0, 0, 0], [6, 0, 0], 3], [[1, 0, 0], [5, 0, 0], 3],
			[[1, 1, 0], [4, 0, 1], 2], [[3, 2, 1], [1, 0, 1], 1]]:
		var arranged = with_tray(layout[0], layout[1], layout[2])
		if not Rules.validate(arranged):
			check(false, "键盘审计的现场本身不合法：%s" % layout)
			continue
		game.apply_committed(arranged, []); ready_input(game)
		var ids = hotspots.duplicate(true)
		for slot in range(Rules.packs_of(layout[0])): ids.append("tray_%d" % slot)
		var verdict = advertised_audit(game, ids)
		told += int(verdict[0]); mistaken += int(verdict[1])
	check(mistaken == 0 and told == 35,
		"牌上写出的快捷键，按下去就是点它那一下（%d 处写着，%d 处说错）" % [told, mistaken])
	# ---- 口条只有两行的位置：每一幕的台词都得在自己的板子里说完 ----
	var too_wide = 0
	var longest = ""
	for stage in Rules.STAGES:
		for beat in range(3 if stage == "arrival" else 1):
			var look = stage_pose(stage)
			if stage == "arrival": look.beat = beat
			if not Rules.validate(look): continue
			game.apply_committed(look, []); ready_input(game)
			var spoken = game.line()
			if not line_fits(spoken, 798.0): too_wide += 1; longest = spoken
	check(too_wide == 0, "九幕台词与开场三句都出不了口条（挤不下的：「%s」）" % longest)
	# ---- 三站的货床：三包落在展翼的实心甲板上，一格压不上一格，也不出画面 ----
	game.apply_committed(stage_pose("carrying"), []); ready_input(game)
	var atlas: Texture2D = game.world.atlases["parcel_medium"]
	var pinned: Array = game.world.parts["parcel_medium"].anchor_px
	var anchor := Vector2(pinned[0], pinned[1])
	var bed_scale: float = World.BERTH_PACK_WIDTH[M] / atlas.get_width()
	var dims := Vector2(atlas.get_width(), atlas.get_height()) * bed_scale
	var plate: Texture2D = World.HERON_PLATFORM
	var plate_dims := Vector2(plate.get_width(), plate.get_height()) * World.HERON_SCALE
	var plate_rect := Rect2(game.world.boss_foot() - Vector2(plate_dims.x / 2, plate_dims.y), plate_dims)
	var bed: Array = []
	var doubled = 0
	var off_deck = 0
	for slot in range(Rules.MAX_PACKS[2]):
		var rect := Rect2(game.world.pack_home(2, slot) - anchor * bed_scale, dims)
		for other: Rect2 in bed:
			if rect.intersects(other): doubled += 1
		if not plate_rect.encloses(rect): off_deck += 1
		bed.append(rect)
	check(doubled == 0, "货床上的三包各占一格，后一包不会压住前一包")
	check(off_deck == 0, "货床整排都还在搬运台的甲板里，没有一包飘在台外")
	# 包的正中心落在搬运台原图的实心木色上：这一格若画在铜鹭之前，玩家一颗也看不见。
	var plate_image: Image = plate.get_image()
	var on_plate = 0
	for rect: Rect2 in bed:
		var at: Vector2 = rect.position + rect.size / 2.0
		var pixel := Vector2i(int((at.x + 0.5 - plate_rect.position.x) / World.HERON_SCALE),
			int((at.y + 0.5 - plate_rect.position.y) / World.HERON_SCALE))
		if plate_image.get_pixelv(pixel).a > 0.99: on_plate += 1
	check(on_plate == bed.size(), "三包的中心都压在展翼的实心甲板上（画在铜鹭之后才看得见）")
	game.apply_committed(stuck, []); ready_input(game)
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	for stage in Rules.STAGES:
		for look in [stage_pose(stage), stage_pose(stage).duplicate(true)]:
			if stage == "complete": look.flag = Rules.FLAG_B
			if not Rules.validate(look): continue
			game.apply_committed(look, [])
			for at in [0.0, 0.5, 1.0]:
				ready_input(game); game.world.progress = at; await process_frame
	check(is_instance_valid(game.world) and not game.modal, "每一幕都重画一遍，绘制代码没有崩")
	# ---- 摆满 6 包时托盘热点仍然在画面里、也还够大 ----
	var crowded = with_tray([3, 2, 1], [0, 2, 0], 1)
	game.apply_committed(crowded, []); ready_input(game)
	var tray_ids = []
	for slot in range(Rules.MAX_TRAY): tray_ids.append("tray_%d" % slot)
	report = frame_report(game, tray_ids)
	check(report[0] and report[1] and report[2] and report[3], "摆满 6 包：每一包都能点、都在画面里")
	# ---- 在真场景里把旗A 的参考应对走一遍 ----
	var opened_a = Rules.fresh(); opened_a.flag = Rules.FLAG_A
	game.apply_committed(opened_a, []); ready_input(game)
	check(game.state.flag == Rules.FLAG_A and game.state.shown == 0, "这一遍走的是旗A 那条支路，旗照旧没翻")
	skip(game)
	while game.state.stage != "puzzle":
		ready_input(game)
		if game.state.stage in Rules.ANIMATIONS: game.skip_animation()
		else: game.advance()
	check(game.state.stage == "puzzle" and game.state.station == 1, "台词与入幕之后站到一站前")
	ready_input(game); game.do_op(0)
	check(game.state.chances == 2 and game.history.size() == 1, "点封装牌：机会真的少一次")
	ready_input(game); game.do_take(L); ready_input(game); game.do_take(M)
	check(game.state.tray == [1, 1, 0] and game.state.stock == [4, 0, 1], "两包放上托盘，台面同步少两只")
	report = frame_report(game, ["tray_0", "tray_1"])
	check(report[0] and report[1] and report[2], "托盘上的两包各占一格，也都在画面里")
	ready_input(game)
	check(not game.buttons.undo.disabled, "摆过一步之后撤销亮了")
	ready_input(game); game.undo()
	check(game.state.tray == [1, 0, 0] and game.state.stock == [4, 1, 1], "撤销只退一步摆法")
	ready_input(game); game.undo()
	check(game.state.tray == [0, 0, 0] and game.state.chances == 2, "再退一步：货回到台面，机会仍是已用一次")
	ready_input(game); game.undo()
	check(game.state.stock == Rules.START_STOCK and game.state.chances == 3 and game.history.is_empty(),
		"退到底：封装那一步也回来了")
	ready_input(game); game.do_op(0); ready_input(game); game.do_take(L); ready_input(game); game.do_take(M)
	ready_input(game); game.advance()
	check(game.state.stage == "flag" and game.state.shown == 1, "一站交完，铜鹭翻旗")
	skip(game)
	check(game.state.station == 2 and game.state.stage == "puzzle", "翻旗之后回到码头摆二站")
	check(not game.buttons.has("rewind"), "二站的码头上还没有可退的上一站")
	ready_input(game); game.do_take(L); ready_input(game); game.do_take(L)
	ready_input(game); game.advance()
	check(game.state.stage == "puzzle" and "二站" in game.message and "7 单位" in game.message,
		"只交 2 大包会被点名：二站要 7 单位")
	check("一站" not in game.message, "拒绝里不怪已经办成的那一站")
	ready_input(game); game.do_take(S)
	ready_input(game); game.advance(); skip(game)
	check(game.state.station == 3 and game.state.stage == "puzzle", "旗A 的二站收下 2大+1小")
	ready_input(game); game.do_op(2)
	ready_input(game); game.do_take(M); ready_input(game); game.do_take(M); ready_input(game); game.do_take(M)
	ready_input(game); game.advance()
	check(game.state.stage == "carrying", "三站收下 3 中包，铜鹭展翼")
	skip(game)
	check(game.state.stage == "complete" and Rules.validate(game.state), "旗A 一路走到回执，存档合法")
	check(game.state.chances == 1 and game.state.delivered == [[1, 1, 0], [2, 0, 1], [0, 3, 0]],
		"回执上记着玩家自己走出来的那三站")
	check(game.buttons.has("next") and game.buttons.next.text == "再巡一次", "最后一块牌子邀请再巡一次")
	check(game.buttons.has("open_hub"), "单独启动本关也有一条回航图的路")
	var receipt = ""
	for child in game.ui.get_children():
		if child is Label and "回执" in child.text: receipt = child.text
	check("一站 1大包 1中包 = 5 单位" in receipt, "回执复述一站真实收到的包")
	check("旗A" in receipt and "重新封装用去 2 次" in receipt, "回执复述真正翻出来的旗与真正用掉的机会")
	# ---- 存档事务：失败不脏写、重试一次成 ----
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; ready_input(game); game.restart()
	check(game.modal and game.state.stage == "complete" and FileAccess.get_file_as_bytes(path) == bytes,
		"保存失败时现场保持原样，只弹重试")
	game.repository.fail_at = ""; game.retry_save()
	check(not game.modal and game.state.stage == "arrival", "重试之后这一次改写成功")
	game.repository.fail_at = "open"; ready_input(game); game.advance()
	check(game.modal and game.state.stage == "arrival", "读不到写不进时也不会推进")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.beat == 1 and not game.modal, "台词照样能重试保存")
	# ---- 旗不会被重读换掉 ----
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); ready_input(game); await process_frame
	var rolled_flag = game.state.flag
	check(rolled_flag in [Rules.FLAG_A, Rules.FLAG_B], "写进存档的旗是一面真旗")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); ready_input(game); await process_frame
	check(game.state.flag == rolled_flag, "重读之后还是那一面旗")
	game.queue_free(); await process_frame
	var writer = FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(pose("puzzle", Rules.FLAG_B, 3, [2, 0, 0], Rules.empty_packs(),
		[[1, 1, 0], [0, 3, 1], [0, 0, 0]], 1))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); ready_input(game); await process_frame
	check(game.state.stage == "puzzle" and game.state.station == 3 and game.state.flag == Rules.FLAG_B,
		"读到没办完的三站就站在三站前，旗照旧")
	check(not game.buttons.has("open_hub") and not game.buttons.has("back_hub"), "还在摆货的时候不塞出口按钮")
	check(Rules.validate(game.state), "续上的这一站仍是合法存档")
	ready_input(game); game.do_undeliver()
	check(game.state.station == 2 and game.state.tray == [0, 3, 1] and game.state.chances == 1,
		"实窗里点「退回上一站的货」：那四包回到托盘")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(stage_pose("complete"))); writer.close()
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "航图的来路只被消费一次")
	check(game.buttons.has("back_hub"), "从航图进来就给一条回去的路")
	check(not game.buttons.has("open_hub"), "两条出口不同时出现")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin != "hub" and game.buttons.has("open_hub"), "直接启动也回得去千灯航图")
	game.queue_free(); await process_frame
	var broken = FileAccess.open(path, FileAccess.WRITE); broken.store_string("{broken"); broken.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"损坏的存档被保留下来，不会被覆盖")
	game.queue_free(); await process_frame
	# ---- 目录一致性 ----
	check(Catalog.scene("MK17") == "res://game/market_mk17.tscn", "目录指向真正做出来的场景")
	check(Catalog.save_path("MK17") == SAVE_DEFAULT, "目录里的存档路径就是本关写的这一份")
	check(Catalog.LEVELS["MK17"].kit == "dock", "本关留在大码头的 kit 场景上")
	check(Catalog.opens_after("MK17") == "MK12" and Catalog.act("MK17") == 6, "MK17 是第六幕的第一场首领")
	check(ResourceLoader.exists(Catalog.scene("MK17")), "航图现在能点亮 MK17，不再写「尚未制作」")
	check(Catalog.built("MK17") and Catalog.available("MK17", ["MK12"]), "MK12 之后 MK17 可进")
	check(not Catalog.is_side("MK17"), "首领一在主线里，不是支线")
	DirAccess.remove_absolute(path)
	print("MARKET MK17 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

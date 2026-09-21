extends SceneTree
# MK12「不一样多，也都够用」的无头检查：只驱动状态机、热点与真实存档，不开窗口。
# 除了逐条 transition，它把全部 3^6 种「每一壶交给哪一处」的摆法数一遍：
# 解集恰好是设计的那九种，「三处都给 5 单位」那一族 36 种必须被拒，并点名是哪张需求单没被满足。
# 测试只往 /tmp 写自己的落点，绝不往 user:// 下写。
const Rules = preload("res://scripts/market/mk12_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Scene = preload("res://game/market_mk12.tscn")
const World = preload("res://scripts/market/mk12_world.gd")

var checks = 0
var failures = 0
var path = "/tmp/pixel-mk12-rules-" + str(Time.get_ticks_usec()) + ".json"
var face: Font

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)
	return ok

# ---- 小工具 --------------------------------------------------------------
func rows_of(count: int) -> Array:
	var rows: Array = []
	for _place in range(count): rows.append([])
	return rows

# 把 [[壶号...]×3] 写成一份状态；只有过了提交闸口才由 handed 记账。
func build(rows: Array, stage: String = "puzzle") -> Dictionary:
	var state = Rules.fresh()
	state.stage = stage
	if stage != "arrival": state.beat = Rules.BEATS - 1
	for place in range(Rules.PLACES.size()):
		for jug in rows[place]: state.plan[place].append(jug)
		state.plan[place].sort()
	if stage in ["handing", "delivery", "complete"]: state.handed = state.plan.duplicate(true)
	return state

func solution_rows() -> Array: return [[0, 1], [2, 3], [4, 5]]
func fives_rows() -> Array: return [[0, 3], [1, 4], [2, 5]]
func plan_text(plan: Array) -> String: return JSON.stringify(plan)

func units_in(row: Array) -> Array:
	var marks: Array = []
	for jug in row: marks.append(Rules.JUG_UNITS[jug])
	marks.sort()
	return marks

# 汉字按整宽、拉丁字母按六成宽估算；再用真实字体量一遍：Godot 不会在汉字串中间断行。
func units(text: String, size_px: int) -> float:
	var wide = 0.0
	for index in range(text.length()):
		wide += size_px if text.unicode_at(index) >= 0x2000 else size_px * 0.6
	return wide

func fits(text: String, size_px: int, box: float) -> bool:
	var ok = true
	for line in text.split("\n"):
		if units(line, size_px) > box: ok = false
	return ok

func real_fits(text: String, size_px: int, box: float) -> bool:
	if face == null: face = UIStyle.face()
	var ok = true
	for line in text.split("\n"):
		if face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > box: ok = false
	return ok

# 落下动画只影响手感：清掉锁定再重画，热点的可用状态才与实窗一致。
func settle(game: Node) -> void:
	game.transient = 0.0
	game.refresh()

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK12 rule watchdog"); quit(1))
	# ---- 1. 开局现场与 schema ----
	check(Rules.fresh() == {"sample": "market-mk12-1", "stage": "arrival", "beat": 0, "hint": 0,
		"plan": [[], [], []], "handed": [[], [], []]}, "fresh state carries exactly the six frozen fields")
	check(Rules.JUG_UNITS == [2, 2, 2, 3, 3, 3] and Rules.NEEDS == [4, 5, 6], "六壶三单的量与剧情一致")
	check(Rules.jug_total() == 15 and Rules.need_total() == 15, "六壶总量恰好等于三处需要之和")
	check(Rules.PLACES == ["桥头", "中街", "西坡"] and Rules.MAX_PER_PLACE == 2, "三处街口与每处两壶的上限")
	check(Rules.stock_of(Rules.empty_plan()) == [0, 1, 2, 3, 4, 5] and Rules.assigned(Rules.empty_plan()) == 0,
		"开局六壶都在台面")
	check(Rules.units_of([0, 3]) == 5 and Rules.totals(solution_rows()) == Rules.NEEDS, "车上单位由规则现算")
	check(Rules.place_of(solution_rows(), 3) == 1 and Rules.slot_of(solution_rows(), 3) == 1 and
			Rules.slot_of(solution_rows(), 2) == 0 and Rules.place_of(solution_rows(), 9) == -1,
			"每一壶知道自己在哪辆车的第几格")
	check(Rules.stock_units(Rules.empty_plan()) == 15 and Rules.stock_units(solution_rows()) == 0,
		"台面上还剩多少单位也只数实物")
	var schema_ok := true
	for candidate in [[[], [], []], solution_rows(), fives_rows(), [[0], [1], [2]], [[], [], [5]]]:
		if not Rules.legal_plan(candidate): schema_ok = false
	for broken in [[[], [], [], []], [[], []], [[0, 1, 2], [], []], [[0], [0], []], [[6], [], []],
		[[-1], [], []], [[1.5], [], []], [["0"], [], []], [[0, 1], [2, 3], [4, 4]], [], "plan", null]:
		if Rules.legal_plan(broken): schema_ok = false
	check(schema_ok, "处数不对、一处三壶、同一壶上两辆车、越界、非整数都不算合法草稿")
	check(Rules.validate(Rules.fresh()) and Rules.validate(build(solution_rows())) and
			Rules.validate(build(solution_rows(), "handing")) and Rules.validate(build(solution_rows(), "complete")),
		"合法状态通过校验")
	check(not Rules.validate(build(fives_rows(), "handing")) and not Rules.validate(build(fives_rows(), "complete"))
			and not Rules.validate(build(solution_rows(), "ready")),
		"没分完的记录、装车之前的记录都不算合法状态")

	# ---- 2. 全枚举：解集恰好九种，陷阱恰好三十六种 ----
	var total_rows = 0
	var over_capacity = 0
	var solutions: Array = []
	var all_fives: Array = []
	var misplaced: Array = []
	for code in range(int(pow(3, Rules.JUGS))):
		var rest = code
		var rows = rows_of(Rules.PLACES.size())
		for jug in range(Rules.JUGS):
			rows[rest % Rules.PLACES.size()].append(jug)
			rest = int(rest / float(Rules.PLACES.size()))
		total_rows += 1
		var draft = build(rows)
		if not Rules.legal_plan(draft.plan): over_capacity += 1; continue
		var totals = Rules.totals(draft.plan)
		if totals == Rules.NEEDS: solutions.append(rows)
		elif totals == [5, 5, 5]: all_fives.append(rows)
		else: misplaced.append(rows)
	check(total_rows == 729 and over_capacity == 639 and
			solutions.size() + all_fives.size() + misplaced.size() == 90,
		"3^6 全枚举：639 种塞不进每处两壶，剩下 90 种摆得下（实得 %d/%d）" % [total_rows, over_capacity])
	check(solutions.size() == 9, "满足三张需求单的摆法恰好九种（实得 %d）" % solutions.size())
	check(solutions.has(solution_rows()), "设计里的那一份摆法确实在解集中")
	var shape_ok := true
	for rows in solutions:
		if units_in(rows[0]) != [2, 2] or units_in(rows[1]) != [2, 3] or units_in(rows[2]) != [3, 3]: shape_ok = false
	check(shape_ok, "九种解都是 2+2→4、2+3→5、3+3→6，只是彼此不同的壶换了位置")
	check(all_fives.size() == 36 and misplaced.size() == 45,
		"三处都给 5 的摆法三十六种，其余四十五种（实得 %d/%d）" % [all_fives.size(), misplaced.size()])
	var trap_named = 0
	for rows in all_fives:
		var missing = Rules.plan_shortfalls(build(rows).plan)
		var spoken = " ".join(missing)
		if missing.size() == 2 and "桥头" in spoken and "西坡" in spoken and "中街" not in spoken and \
				"多了 1" in spoken and "还差 1" in spoken: trap_named += 1
	check(trap_named == all_fives.size(), "三十六种「都给 5」全被拒，理由点名桥头多接与西坡少接（%d/%d）" %
		[trap_named, all_fives.size()])
	var two_wrong = 0
	var three_wrong = 0
	var honest = 0
	for rows in misplaced:
		var totals = Rules.totals(build(rows).plan)
		var counted = totals.duplicate(true); counted.sort()
		var missing = Rules.plan_shortfalls(build(rows).plan)
		if counted != [4, 5, 6]: honest += 1
		if missing.size() == 2: two_wrong += 1
		elif missing.size() == 3: three_wrong += 1
	check(honest == 0 and two_wrong == 27 and three_wrong == 18,
		"三个数都对却发错街口的情形全部拒收，缺口只点名接错的那几处（2 处 %d、3 处 %d）" % [two_wrong, three_wrong])

	# 只用玩家能做的动作走一遍：可达的完成态与解集一样多，全程不留幻影壶。
	var seen := {}
	var queue: Array = [Rules.empty_plan()]
	var reachable_solved = 0
	var phantom = 0
	while not queue.is_empty():
		var plan: Array = queue.pop_front()
		var key = plan_text(plan)
		if seen.has(key): continue
		seen[key] = true
		var draft = build(plan)
		if Rules.stock_of(plan).size() + Rules.assigned(plan) != Rules.JUGS: phantom += 1
		if Rules.totals(plan) == Rules.NEEDS: reachable_solved += 1
		for jug in Rules.stock_of(plan):
			for place in range(Rules.PLACES.size()):
				var moved = Rules.load(draft, jug, place)
				if not moved.is_empty(): queue.append(moved.plan)
	check(reachable_solved == 9 and phantom == 0, "只用装/卸两个动作就能走到全部九解（可达态 %d，幻影 %d）" %
		[seen.size(), phantom])
	check(seen.has(plan_text(solution_rows())) and seen.has(plan_text(fives_rows())),
		"唯一解与「都给 5」都摆得出来，拒绝只发生在提交闸口")
	var rotated = 0
	for rows in solutions:
		if Rules.totals(build([rows[2], rows[0], rows[1]]).plan) != Rules.NEEDS: rotated += 1
	check(rotated == solutions.size(), "把任何一解整体挪一个街口就变成发错单子的摆法")

	# ---- 3. 阶段机：每一次 advance 的去向，含被拒的那些 ----
	var spoken_steps = 0
	var walking = Rules.fresh()
	while walking.stage == "arrival":
		check(walking.beat < Rules.BEATS, "开场只播四句，当前第 %d 句" % (walking.beat + 1))
		walking = Rules.advance(walking)
		spoken_steps += 1
	check(spoken_steps == Rules.BEATS and walking.stage == "approach" and walking.beat == Rules.BEATS - 1,
		"四句之后走向庭院")
	check(Rules.advance(walking).stage == "ready", "走到庭院前停下来等确认")
	check(Rules.advance(Rules.advance(walking)).stage == "puzzle", "确认后才开始装车")
	check(Rules.advance(build(rows_of(3))).is_empty(), "台面还有剩就不允许交货")
	check(Rules.advance(build([[0, 1], [2, 3], []])).is_empty(), "西坡没接满就不允许交货")
	check(Rules.advance(build(fives_rows())).is_empty(), "三处都给 5 不允许交货")
	var booked = Rules.advance(build(solution_rows()))
	check(booked.stage == "handing" and booked.handed == booked.plan and booked.plan == solution_rows() and
			Rules.validate(booked), "一次提交就记账：handed 与 plan 同一份")
	check(Rules.advance(booked).stage == "delivery" and Rules.advance(Rules.advance(booked)).stage == "complete",
		"交货 → 点灯 → 收尾")
	check(Rules.advance(Rules.advance(Rules.advance(booked))).is_empty(), "收尾之后没有下一阶段")
	check(Rules.restore(booked, {"plan": Rules.empty_plan(), "handed": Rules.empty_plan()}).is_empty(),
		"交出去之后撤销不再改写草稿")
	var stuck = 0
	for stage in Rules.STAGES:
		if stage in Rules.ANIMATIONS: continue
		if Rules.advance(build(solution_rows(), stage)).is_empty(): stuck += 1
	check(stuck == 1, "只有 complete 停住，其余阶段都有去处（停住的 %d 个）" % stuck)
	var fake_stage = build(solution_rows()); fake_stage.stage = "pouring"
	check(Rules.advance(fake_stage).is_empty() and not Rules.validate(fake_stage), "没有拆封倒油这一步")

	# ---- 4. 装/卸：草稿是唯一事实，放回不留计数 ----
	var puzzle_state = Rules.fresh()
	while puzzle_state.stage != "puzzle": puzzle_state = Rules.advance(puzzle_state)
	check(puzzle_state.stage == "puzzle" and Rules.validate(puzzle_state), "advance 一路走到装车")
	var refusal = 0
	for jug in [-1, 0, 3, 6, 99, 1000]:
		for place in [-1, 0, 2, 3, 9]:
			if jug >= 0 and jug < Rules.JUGS and place >= 0 and place < Rules.PLACES.size(): continue
			if Rules.can_load(puzzle_state, jug, place) or not Rules.load(puzzle_state, jug, place).is_empty():
				refusal += 1
			if Rules.can_unload(puzzle_state, jug, place): refusal += 1
	check(refusal == 0, "越界壶号与越界街口一律拒收（漏网 %d 个）" % refusal)
	var ready_state = build(rows_of(3), "ready")
	check(not Rules.can_load(ready_state, 0, 0) and Rules.load(ready_state, 0, 0).is_empty() and
			Rules.unload(ready_state, 0, 0).is_empty(), "装车之前动不了草稿")
	var one = Rules.load(puzzle_state, 0, 0)
	check(not one.is_empty() and Rules.place_of(one.plan, 0) == 0 and Rules.slot_of(one.plan, 0) == 0 and
			Rules.stock_of(one.plan) == [1, 2, 3, 4, 5], "装一壶：台面少一壶，车上多一壶")
	check(Rules.load(one, 0, 1).is_empty(), "同一壶不能上两辆车")
	var two = Rules.load(one, 1, 0)
	check(not two.is_empty() and Rules.totals(two.plan) == [4, 0, 0] and Rules.room(two.plan, 0) == 0 and
			two.plan[0] == [0, 1], "桥头接满两壶 2 单位")
	check(Rules.load(two, 2, 0).is_empty() and Rules.can_unload(two, 0, 1) and not Rules.can_unload(two, 0, 2),
		"一处的车最多两壶，第三个位置没有壶可卸")
	var back = Rules.unload(two, 0, 1)
	check(not back.is_empty() and back.plan == [[0], [], []] and Rules.stock_of(back.plan) == [1, 2, 3, 4, 5] and
			Rules.assigned(back.plan) == 1 and Rules.totals(back.plan) == [2, 0, 0],
		"点回车上的壶就回台面：没有幻影壶，也不需要归还")
	var empty_board = build(rows_of(3))
	check(Rules.unload(empty_board, 0, 0).is_empty() and Rules.unload(empty_board, 5, 9).is_empty(),
		"空车没有可卸的壶，也没有越界的车")
	check(Rules.room(empty_board.plan, 0) == Rules.MAX_PER_PLACE and Rules.room(two.plan, 0) == 0 and
			Rules.room(two.plan, 9) == 0, "空位也只由草稿算出来")
	var order_check = Rules.load(Rules.load(empty_board, 1, 2), 0, 2)
	check(order_check.plan[2] == [0, 1] and Rules.stock_of(order_check.plan) == [2, 3, 4, 5],
		"先拿哪壶都不影响草稿，台面与车上永远互补")

	# ---- 5. 撤销与跨阶段恢复 ----
	var empty_snapshot = {"plan": Rules.empty_plan(), "handed": Rules.empty_plan()}
	var loaded_pair = Rules.load(Rules.load(empty_board, 4, 1), 1, 2)
	var restored = Rules.restore(loaded_pair, empty_snapshot)
	check(restored.stage == "puzzle" and restored.plan == Rules.empty_plan(), "撤销回空车")
	check(Rules.restore(restored, empty_snapshot) == restored, "撤销到空状态仍然合法")
	var cross = 0
	for stage in Rules.STAGES:
		if stage == "puzzle": continue
		if not Rules.restore(build(solution_rows(), stage), empty_snapshot).is_empty(): cross += 1
	check(cross == 0, "交货之后撤销不再改写草稿（漏网 %d 个阶段）" % cross)
	var round_trip = 0
	var draft = empty_board
	for step in range(Rules.JUGS):
		var prior = draft.plan.duplicate(true)
		var moved = Rules.load(draft, step, int(step / 2.0))
		if moved.is_empty(): continue
		var undone = Rules.restore(moved, {"plan": prior, "handed": Rules.empty_plan()})
		if not undone.is_empty() and undone.plan == prior: round_trip += 1
		draft = moved
	check(round_trip == Rules.JUGS and draft.plan == solution_rows(),
		"每一装一撤都能精确回到原来的草稿（%d/%d）" % [round_trip, Rules.JUGS])
	check(Rules.restore(empty_board, {"plan": [[0, 1], [2, 3], [4]]}).is_empty() and
			Rules.restore(empty_board, {"plan": [[0, 1], [2, 3], [4, 4]]}).is_empty() and
			Rules.restore(empty_board, {"plan": [[0, 1], [2, 3], [4, 6]]}).is_empty() and
			Rules.restore(empty_board, {"plan": Rules.empty_plan()}).is_empty() and
			Rules.restore(empty_board, {"handed": Rules.empty_plan()}).is_empty(),
		"撤销快照里缺 handed、越界或重复的草稿都不能被写回现场")

	# ---- 6. 缺口：只数实物，不说答案，也不带责备 ----
	var empty_missing = Rules.shortfalls(puzzle_state)
	check(empty_missing.size() == 4 and Rules.solved(build(solution_rows())), "空车时四处缺口，九种解都没有缺口")
	check(empty_missing[0] == "货栈台面上还剩 6 壶封油：六壶都要交出去，一壶不剩。", "第一句先把「一壶不剩」说清")
	var partial_missing = Rules.plan_shortfalls(build([[0, 1], [2, 3], []]).plan)
	check(partial_missing.size() == 2 and "还剩 2 壶" in partial_missing[0] and "西坡" in partial_missing[1] and
			"还差 6 单位" in partial_missing[1], "缺口说清是哪一处差多少，不点破该装哪几壶")
	var one_wrong = Rules.plan_shortfalls(build([[0, 1], [2, 3], [4]]).plan)
	check(one_wrong.size() == 2 and "西坡" in " ".join(one_wrong) and "桥头" not in " ".join(one_wrong) and
			"中街" not in " ".join(one_wrong), "只有接错的那一处会被点名，接满的两处不陪着挨说")
	var sheet_order = Rules.plan_shortfalls(build([[0, 1], [4, 5], [2, 3]]).plan)
	check(sheet_order.size() == 2 and sheet_order[0].begins_with(Rules.PLACES[1]) and
			sheet_order[1].begins_with(Rules.PLACES[2]), "缺口按桥头、中街、西坡的需求单顺序说，不按多少重排")
	var tone_ok := true
	var blame = ["罚", "错了", "不行", "笨", "失败", "不够格"]
	for rows in [solution_rows(), fives_rows(), [[0, 1], [2, 3], []], [[0, 1], [2, 3], [4]]]:
		for line in Rules.plan_shortfalls(build(rows).plan):
			for word in blame:
				if word in line: tone_ok = false
	check(tone_ok, "缺口只报数与差额，没有一句责备：少接不是罚，多接也不算赚")
	var less_words = Rules.plan_shortfalls(build([[0, 1], [2], [3, 4]]).plan)
	check("还差 3 单位" in " ".join(less_words) and "不够" not in " ".join(less_words),
		"中街少接只说还差多少：" + " ".join(less_words))

	# ---- 7. 坏档批量拒绝 ----
	var fresh_state = Rules.fresh()
	var solved_state = build(solution_rows(), "complete")
	var corrupt: Array = []
	corrupt.append([{}, "空档"])
	for key in ["sample", "stage", "beat", "hint", "plan", "handed"]:
		var cut = fresh_state.duplicate(true); cut.erase(key)
		corrupt.append([cut, "缺少 " + key])
	var added = fresh_state.duplicate(true); added.stars = 3
	corrupt.append([added, "多存了一个本关没有的奖励字段"])
	for value in [null, "", "mk12", "market-mk12-2", "market-mk12-1 ", 12]:
		var forged = fresh_state.duplicate(true); forged.sample = value
		corrupt.append([forged, "sample 被改成 " + str(value)])
	for value in [null, "", "Puzzle", "puzzling", "done", "complete ", 6, true]:
		var forged = fresh_state.duplicate(true); forged.stage = value
		corrupt.append([forged, "stage 被改成 " + str(value)])
	for value in [null, -1, Rules.BEATS, 99, 1.0, "1", true]:
		var forged = fresh_state.duplicate(true); forged.beat = value
		corrupt.append([forged, "beat 被改成 " + str(value)])
	for value in [null, -1, Rules.HINT_TIERS + 1, 99, 1.5, "2", true]:
		var forged = fresh_state.duplicate(true); forged.hint = value
		corrupt.append([forged, "hint 被改成 " + str(value)])
	for value in [null, [], [[], []], [[], [], [], []], "plan", [[0], [1], [2]], [[0, 1, 2], [], []],
		[[0], [0], []], [[6], [], []], [[-1], [], []], [[1.5], [], []], [["0"], [], []], [[0, 1], [2, 3], [4, 4]]]:
		var forged = solved_state.duplicate(true); forged.plan = value
		corrupt.append([forged, "plan 被改成 " + JSON.stringify(value)])
	for value in [null, [], [[], []], "handed", [[0], [0], []], [[0, 3], [1, 4], [2, 5]], [[0, 1], [2, 3], [4]]]:
		var forged = solved_state.duplicate(true); forged.handed = value
		corrupt.append([forged, "complete 的 handed 被改成 " + JSON.stringify(value)])
	corrupt.append([build(solution_rows(), "ready"), "ready 时草稿必须还是空的"])
	corrupt.append([build([[0], [], []], "arrival"), "开场时不该已经装好壶"])
	corrupt.append([build(solution_rows(), "approach"), "走向庭院的路上不能带着草稿"])
	var early_hint = build(rows_of(3), "approach"); early_hint.hint = 1
	corrupt.append([early_hint, "还没装车不许记提示"])
	var beat_slip = build(solution_rows()); beat_slip.beat = 0
	corrupt.append([beat_slip, "摆放中途的 beat 不能退回开场"])
	var puzzle_handed = build(solution_rows()); puzzle_handed.handed = solution_rows()
	corrupt.append([puzzle_handed, "摆放中途不存「已经交出去」的记录"])
	var handing_split = build(solution_rows(), "handing"); handing_split.plan = Rules.empty_plan()
	corrupt.append([handing_split, "handing 的草稿必须与交出去的一致"])
	corrupt.append([build(fives_rows(), "delivery"), "delivery 不能记着没分完的一单"])
	corrupt.append([build([[0, 1], [2, 3], [4]], "complete"), "complete 还留着一壶在台面上"])
	corrupt.append([build([[0, 1], [2, 3], [4]], "handing"), "handing 也不能先交出去再少一壶"])
	var forged_hint = build(solution_rows(), "complete"); forged_hint.hint = Rules.HINT_TIERS + 4
	corrupt.append([forged_hint, "收尾档也不能伪造提示数"])
	var rejected = 0
	for record in corrupt:
		if not Rules.validate(record[0]): rejected += 1
		else: print("  漏网存档：", record[1])
	check(rejected == corrupt.size(), "坏档全部被拒（%d/%d）" % [rejected, corrupt.size()])
	check(Rules.validate(solved_state) and Rules.validate(build(solution_rows(), "puzzle")) and
			Rules.validate(build([[0], [], []], "puzzle")), "合法的好档仍然通过（对照组）")
	var capped = build(solution_rows()); capped.hint = Rules.HINT_TIERS
	check(Rules.validate(capped), "第三档提示仍在界内")

	# ---- 8. 章节目录与本关身份 ----
	var entry = Catalog.LEVELS["MK12"]
	check(entry.title == "不一样多，也都够用" and entry.act == 5 and Catalog.act_name("MK12") == "公平不只是一样多",
		"MK12 收在第五幕「公平不只是一样多」")
	check(entry.kit == "oil" and entry.scene == "res://game/market_mk12.tscn", "MK12 用 oil 底景与自己的场景文件")
	check(entry.save == "user://profiles/market-mk12-1/save-v1.json" and Catalog.save_path("MK12") == entry.save,
		"目录里的落点就是本关的落点")
	check(entry.after == "MK11" and Catalog.opens_after("MK12") == "MK11", "MK12 接在 MK11 之后")
	check(Catalog.MAIN[Catalog.MAIN.find("MK12") + 1] == "MK17", "第五幕收口之后才进首领")
	check(entry.goal == "按三处各自的需要分封油，一壶不剩" and Catalog.goal("MK12") == entry.goal, "一句话目标对上")
	check(not Catalog.is_side("MK12") and Catalog.exists("MK12"), "MK12 是主线关")
	check(ResourceLoader.exists(entry.scene) and Catalog.built("MK12"), "场景文件存在，航图才会点亮这盏灯")
	var host = Scene.instantiate(); host.configure()
	# 没有进场景树就没有 _ready，子类读 state 的钩子得先有一份开局状态可看。
	host.state = Rules.fresh()
	check(host.save_path == Catalog.save_path("MK12"), "configure 只在落点为空时填目录里的默认值")
	check(host.scene_id == "oil" and host.level_id == "MK12" and host.title == entry.title, "场景声明了自己的身份")
	check(host.rules == Rules and host.world_script == World, "宿主接到 MK12 的规则与世界")
	check(host.durations.has("handing") and host.durations.has("delivery"), "两段演出都有时长")
	check(host.zoom_stages == ["ready", "puzzle", "handing"],
		"装车、那句操作说明与三辆车一起离场都贴着庭院，点灯才退回全景：" +
		"漏掉 ready 会让镜头先弹回 1.0 再弹回 1.10，漏掉 handing 则在交接那两帧连着跳三次")
	check(Rules.BEATS == host.LINES.size() and host.submit_label() == "三处一起交货", "开场四句，提交是一次性交货")
	check(not host.cleared_state().is_empty() and not host.reset_prompt().is_empty() and
			not host.restart_prompt().is_empty(), "重摆与重新体验的文案齐全")
	var keys_ok := true
	for key in [KEY_1, KEY_6, KEY_Q, KEY_W, KEY_E]:
		if not host.handle_key(key): keys_ok = false
	if host.handle_key(KEY_TAB): keys_ok = false
	check(keys_ok, "键盘 1..6 拿壶、Q/W/E 选街口，其他键不吞")
	check(fits(host.goal_line(), 22, 762.0) and real_fits(host.goal_line(), 22, 762.0), "目标板一句话装得下")
	var labels = host.stage_labels()
	for stage in labels:
		if not real_fits(labels[stage], 24, 246.0): keys_ok = false
	check(keys_ok and labels.has("arrival") and labels.has("complete"), "阶段按钮的字数得进按钮")
	host.free()

	# ---- 9. 真实场景：从点击到落盘 ----
	var game = Scene.instantiate()
	game.save_path = path
	root.add_child(game)
	await process_frame
	check(game.save_path == path, "测试注入的 /tmp 落点没有被 configure 覆盖")
	check(not FileAccess.file_exists(path), "开局一句话都没说时不写盘，等第一次改动再落第一档")
	check(game.state == Rules.fresh(), "新档从开场四句开始")
	check(game.buttons.has("next") and game.buttons["next"].text == "继续听他们说", "第一句只请他们继续说")
	check(not game.buttons.has("deliver") and not game.buttons.has("stock_0"), "开场没有提交按钮，也没有货物热点")
	check(fits(game.line(), 20, 798.0) and real_fits(game.line(), 20, 798.0), "开场台词一行装得下")
	for index in range(Rules.BEATS - 1):
		game.advance(); settle(game)
		check(game.state.stage == "arrival" and game.state.beat == index + 1, "第 %d 句落盘" % (index + 2))
		check(game.line() == game.LINES[index + 1] and real_fits(game.line(), 20, 798.0),
			"第 %d 句台词对上" % (index + 2))
	check(game.repository.read_profile(Rules.validate).status == "loaded", "说完一句就写出第一份合法记录")
	game.advance(); settle(game)
	check(game.state.stage == "approach" and game.buttons.has("skip"), "最后一句的按钮把人带到庭院前")
	game.skip_animation(); settle(game)
	check(game.state.stage == "ready" and game.buttons.next.text == "开始装车", "到庭院前停一下等确认")
	game.advance(); settle(game)
	check(game.state.stage == "puzzle", "确认后才开始装车")
	check(game.buttons.has("deliver") and game.buttons.deliver.text == "三处一起交货", "提交按钮写着这是一单三处")
	check(game.buttons.undo.disabled, "第一步之前撤销是空的")
	check(game.status_line() == "三车已装 0/6 壶 · 台面 6 壶" and real_fits(game.status_line(), 20, 300.0),
		"计数只数实物：" + game.status_line())
	# 计数只在装车与离场两幕说话：approach 还没进庭院、delivery 已经在点灯，
	# 那时候再报「三车已装几壶」就是把一张已经交出去的草稿挂在车帮的算式板旁边。
	var draft_stage: String = game.state.stage
	var guard_ok := true
	for stage in ["arrival", "approach", "ready", "delivery", "complete"]:
		game.state.stage = stage
		if not game.status_line().is_empty(): guard_ok = false
	game.state.stage = draft_stage
	check(guard_ok, "其余五幕底栏留白，不挂过期的草稿计数")
	var rects: Array = []
	for jug in range(Rules.JUGS): rects.append(game.world.stock_rect(jug))
	for place in range(Rules.PLACES.size()):
		rects.append(game.world.cart_rect(place))
		for slot in range(Rules.MAX_PER_PLACE): rects.append(game.world.slot_rect(place, slot))
	var small = 0
	var outside = 0
	var overlap = 0
	for rect in rects:
		if rect.size.x < 48 or rect.size.y < 48: small += 1
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 720: outside += 1
	for first in range(rects.size()):
		for second in range(first + 1, rects.size()):
			if rects[first].intersects(rects[second]): overlap += 1
	check(small == 0, "台面、车与车格的目标都不小于 48 像素")
	check(outside == 0, "所有目标都留在 1280x720 画内")
	check(overlap == 0, "六壶、三处接货框与车上的两格互不抢同一格点击")
	check(rects.size() == Rules.JUGS + Rules.PLACES.size() * (1 + Rules.MAX_PER_PLACE), "目标数量刚好")
	var targets = 0
	for id in game.buttons:
		if str(id).begins_with("stock_") or str(id).begins_with("cart_") or str(id).begins_with("slot_"): targets += 1
	check(targets == Rules.JUGS + Rules.PLACES.size(), "开局只有六壶与三辆车是目标，没有空扫的格子")
	var labelled = 0
	for id in ["stock_0", "stock_3", "cart_0", "cart_2"]:
		if str(game.buttons[id].tooltip_text).length() > 8: labelled += 1
	check(labelled == 4, "壶写着单位数、车写着需求单，都带键盘提示")
	game.buttons.stock_0.pressed.emit(); settle(game)
	check(game.picked == 0 and game.world.picked == 0 and game.state.plan == Rules.empty_plan(),
		"拿起一壶只是选择，不写存档")
	game.buttons.cart_0.pressed.emit(); settle(game)
	check(game.state.plan == [[0], [], []] and game.history.size() == 1 and game.picked == -1,
		"点一处车就装上这一壶，手里不剩")
	check(game.world.land_place == "jug" and game.world.land_slot == 0, "落下的只有刚上车的那一壶")
	check(game.buttons.has("slot_0_0") and not game.buttons.has("slot_0_1"), "车上的壶成为第二个目标")
	check(game.handle_key(KEY_3) and game.picked == 2, "键盘 3 拿起第二壶 2 单位")
	game.handle_key(KEY_W); settle(game)
	check(game.state.plan == [[0], [2], []], "键盘 W 交给中街")
	game.message = ""; game.choose_place(1); settle(game)
	check("先在台面上点一壶封油" in game.message, "没拿壶就点车：只提醒，不动草稿")
	game.choose_jug(1); settle(game); game.choose_place(0); settle(game)
	check(game.state.plan == [[0, 1], [2], []], "桥头接满")
	game.choose_jug(3); settle(game); game.choose_place(0); settle(game)
	check("最多接两壶" in game.message and game.state.plan == [[0, 1], [2], []] and game.picked == 3 and
			Rules.stock_of(game.state.plan) == [3, 4, 5], "满车的第三壶被拒，壶还留在玩家手里")
	game.choose_place(2); settle(game)
	check(game.state.plan == [[0, 1], [2], [3]], "换个有空位的地方继续装")
	game.choose_jug(4); settle(game); game.choose_place(2); settle(game)
	check(game.state.plan == [[0, 1], [2], [3, 4]] and game.status_line() == "三车已装 5/6 壶 · 台面 1 壶",
		"西坡接满两壶 3 单位，计数跟着走：" + game.status_line() + " " + str(game.state.plan))
	game.message = ""; game.advance(); settle(game)
	check(game.state.stage == "puzzle" and game.state.handed == Rules.empty_plan() and "还剩 1 壶" in game.message,
		"缺一壶不交货，第一句先说台面还剩几壶：" + game.message)
	game.buttons.slot_1_0.pressed.emit(); settle(game)
	check(game.state.plan == [[0, 1], [], [3, 4]] and Rules.stock_of(game.state.plan) == [2, 5],
		"点回车上的那一壶就回台面")
	game.choose_jug(2); settle(game); game.choose_place(1); settle(game)
	game.do_reset(); settle(game)
	check(game.state.plan == Rules.empty_plan() and game.state.stage == "puzzle" and
			Rules.stock_of(game.state.plan) == [0, 1, 2, 3, 4, 5] and game.picked == -1,
		"重摆清空草稿与手里的壶，实物一壶不多一壶不少")
	var load_steps = [[0, 0], [1, 0], [2, 1], [3, 1], [4, 2], [5, 2]]
	for step in load_steps:
		game.choose_jug(step[0]); settle(game)
		game.choose_place(step[1]); settle(game)
	check(game.state.plan == solution_rows() and Rules.assigned(game.state.plan) == Rules.JUGS and
			Rules.totals(game.state.plan) == Rules.NEEDS, "六步装完：一壶不剩，三处各自接满")
	check(game.status_line() == "三车已装 6/6 壶 · 台面 0 壶", "装完后计数说台面 0 壶")
	var history_size = game.history.size()
	game.undo(); settle(game); game.undo(); settle(game)
	check(game.state.plan == [[0, 1], [2, 3], []] and game.history.size() == history_size - 2,
		"撤销逐壶回退，不越到动画里")
	game.choose_jug(4); settle(game); game.choose_place(2); settle(game)
	game.choose_jug(5); settle(game); game.choose_place(2); settle(game)
	check(game.state.plan == solution_rows(), "重新装回去还是那份草稿")
	for _tier in range(Rules.HINT_TIERS + 2):
		game.hint(); settle(game)
	check(game.state.hint == Rules.HINT_TIERS, "提示最多三档且不会替玩家装车：" + str(game.state.hint))
	var tiers = game.hint_texts()
	var named = 0
	for index in range(tiers.size()):
		check(real_fits(tiers[index], 20, 798.0), "第 %d 档提示一屏装得下" % (index + 1))
		check(tiers[index].split("\n").size() <= 2, "第 %d 档提示不超过两行" % (index + 1))
		for place_name in Rules.PLACES:
			if place_name in str(tiers[index]): named += 1
	check(tiers.size() == Rules.HINT_TIERS and named == 1,
		"三级提示只说关系与一步示范，不报整单名单（点名 %d 处）" % named)
	check("2+2" in str(tiers[0]) and "示范一步" in str(tiers[2]), "第一档提醒关系，第三档示范一步")
	var hinted = build(solution_rows()); hinted.hint = Rules.HINT_TIERS
	var hinted_booking = Rules.advance(hinted)
	check(hinted_booking.handed == solution_rows() and hinted_booking.stage == "handing",
		"看过提示也照样按同一单交货，奖励不打折")
	check(game.state.plan == solution_rows(), "三档提示都没有替玩家挪过壶")

	# ---- 10. 陷阱摆法：交得出去，但违背确认过的需要 ----
	game.do_reset(); settle(game)
	for step in [[0, 0], [3, 0], [1, 1], [4, 1], [2, 2], [5, 2]]:
		game.choose_jug(step[0]); settle(game)
		game.choose_place(step[1]); settle(game)
	check(game.state.plan == fives_rows() and Rules.stock_of(game.state.plan).is_empty() and
			Rules.totals(game.state.plan) == [5, 5, 5], "三处各 5 单位：六壶确实全部交出去了")
	game.message = ""; game.advance(); settle(game)
	check(game.state.stage == "puzzle" and "桥头" in game.message and "多了 1 单位" in game.message and
			"还有 1 处" in game.message, "「都给 5」被拒，理由是需求单没被满足：" + game.message)
	check("中街" not in game.message, "刚好接到 5 单位的中街不被牵连：" + game.message)
	check(game.snapshot(game.state).handed == Rules.empty_plan() and game.state.handed == Rules.empty_plan(),
		"被拒的摆法一壶都没交出去，草稿原样留着")
	game.do_reset(); settle(game)
	for step in load_steps:
		game.choose_jug(step[0]); settle(game)
		game.choose_place(step[1]); settle(game)
	check(game.state.plan == solution_rows(), "重摆后装回按着单子的那一份")

	# ---- 11. 一次性交货：写盘失败不记账，重试才推进 ----
	var saved_state = game.state.duplicate(true)
	var before_bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "flush"
	game.advance()
	# 弹窗按钮是 show_save_error 直接挂到覆盖层上的：一刷新就从 buttons 里掉了，
	# 所以这一条必须在任何重画之前看。
	check(game.state == saved_state and game.modal and game.buttons.has("retry") and
			not game.pending.is_empty() and game.pending.stage == "handing",
		"写盘失败时现场不变，失败的提交只留在待处理区")
	check(FileAccess.get_file_as_bytes(path) == before_bytes, "失败的那次没有写坏存档")
	settle(game)
	game.repository.fail_at = ""
	game.retry_save(); settle(game)
	check(game.state.stage == "handing" and not game.modal and game.pending.is_empty() and
			game.world.state.stage == "handing", "重试成功后才推进，世界读的是同一份状态")
	# 读盘走宿主自己的仓库：它会把 JSON 还原成整数，比较结果才与关卡里的一致。
	var on_disk = game.repository.read_profile(Rules.validate)
	check(on_disk.status == "loaded" and on_disk.profile.stage == "handing" and
			on_disk.profile.handed == solution_rows() and on_disk.profile.plan == solution_rows(),
		"交出去那一刻才落盘，handed 与 plan 同一份")
	check(game.buttons.has("skip") and game.buttons.has("pause"), "离场动画可以先停住")
	game._process(0.5)
	check(game.world.progress > 0.0 and game.world.progress < 1.0 and game.state.stage == "handing",
		"动画按自己的节奏走")
	var rolled = game.world.cart_foot(2) - game.world.cart_station(2)
	var rolled_left = game.world.cart_foot(0) - game.world.cart_station(0)
	check(rolled.x > 0.0 and rolled_left.x < 0.0, "三辆车各自载着两壶驶向街口，壶没有拆开")
	check(game.world.slot_foot(0, 0) != game.world.stock_spot(0), "车上的壶跟着车走，不落回台面")
	game.toggle_pause()
	var frozen = game.world.progress
	var frozen_stage = game.state.stage
	for _frame in range(120): game._process(1.0)
	check(game.paused and game.world.progress == frozen and game.state.stage == frozen_stage,
		"暂停后动画不推进、也不改草稿")
	game.toggle_pause()
	game.skip_animation(); settle(game)
	check(game.state.stage == "delivery" and game.state.handed == solution_rows(), "跳过演出仍按同一单点灯")
	game._process(2.0)
	check(game.world.progress > 0.5, "三处的灯按桥头、中街、西坡依次亮起来")
	game.skip_animation(); settle(game)
	check(game.state.stage == "complete" and game.state.plan == game.state.handed and
			game.state.handed == solution_rows(), "三家都接完才收尾")
	check(game.buttons.next.text == "重新体验" and game.buttons.has("open_hub") and
			game.buttons.open_hub.text == "回千灯航图", "收尾同时给回航图与重新体验")
	check(Rect2(Vector2(690, 646), Vector2(280, 54)) == game.buttons.open_hub.get_global_rect(), "出口按约定位置")
	check(game.snapshot(game.state).handed == solution_rows() and game.snapshot(game.state).plan == solution_rows(),
		"快照读回交出去的那一单")
	var kept_clear = game.cleared_state()
	check(kept_clear.plan == Rules.empty_plan() and kept_clear.handed == solution_rows(),
		"重新体验清空装车草稿，但不抹掉已经交出去的那一单")
	game.picked = 2
	game.cleared_state()
	check(game.picked == -1, "重新体验也放下手里的壶")
	var receipt = game.receipt_lines()
	check(receipt.size() == 9 and "一起签" in " ".join(receipt), "收尾回执写着三家一起签")
	var receipt_ok := true
	for line in receipt:
		if not real_fits(line, UIStyle.text_size(16), 254.0): receipt_ok = false
	check(receipt_ok, "回执九行都贴得进面板")
	check("2+2=4" in receipt[1] and "2+3=5" in receipt[2] and "3+3=6" in receipt[3], "回执复述玩家实际交的壶")
	check("台面剩 0 壶" in receipt[4] and "封油没拆过" in receipt[4], "回执说明六壶都交了、一壶没拆")
	var painted = false
	for node in game.get_children():
		for child in node.get_children():
			if child is Label and child.text == "\n".join(receipt): painted = true
	check(painted, "回执真的贴在收尾画面上")
	var boards = game.world.signs()
	var spill = 0
	for board in boards:
		var room = board.rect.size.x - 20.0 if board.plaque else board.rect.size.x - 8.0
		if not real_fits(board.text, board.size, room): spill += 1
	check(spill == 0 and boards.size() >= 6, "庭院里 %d 块牌子都装得下自己的字" % boards.size())

	# ---- 12. 每个阶段都重画一遍，画完还在画框里 ----
	# 换幕不跳：handing 最后一帧的车脚必须就是 delivery 第一帧的车脚，点灯过半时车回到庭院原位，
	# 收尾那一格的车、车帮算式与联合回执栏才还按审计量过的坐标各占各处。
	game.state = build(solution_rows(), "handing"); game.world.state = game.state
	game.world.progress = 1.0
	var rolled_out: Vector2 = game.world.cart_foot(2) - game.world.cart_station(2)
	game.state = build(solution_rows(), "delivery"); game.world.state = game.state
	game.world.progress = 0.0
	var rolled_back: Vector2 = game.world.cart_foot(2) - game.world.cart_station(2)
	game.world.progress = 0.6
	check(rolled_out.distance_to(rolled_back) < 0.01 and
			game.world.cart_foot(2) == game.world.cart_station(2) and rolled_out.x > 20.0,
		"三辆车驶向街口再回到庭院是一来一回：换幕那一帧没有整排弹回去的跳变")
	var repaints = 0
	var offscreen = 0
	var lines_ok := true
	for stage in Rules.STAGES:
		var wanted = Rules.fresh() if stage == "arrival" else build(solution_rows(), stage)
		for frame in [0.0, 0.5, 1.0]:
			game.state = wanted.duplicate(true)
			game.history = []
			game.transient = 0.0
			game.refresh()
			game.world.state = game.state
			game.world.progress = frame
			game.world.queue_redraw()
			game.world.notification(CanvasItem.NOTIFICATION_DRAW)
			for child in game.world.get_children():
				if child is Control and (child.position.x < -10 or child.position.y < -10): offscreen += 1
			if not real_fits(game.line(), 20, 798.0): lines_ok = false
			if not fits(game.status_line(), 20, 300.0): lines_ok = false
			repaints += 1
	check(repaints == Rules.STAGES.size() * 3, "%d 个阶段状态各画过三帧" % Rules.STAGES.size())
	check(offscreen == 0, "任何阶段的物件都留在画内")
	check(lines_ok, "每句台词、目标与计数都装得下自己的板")
	game.state = Rules.fresh(); game.transient = 0.0; game.refresh()
	var arrival_boards = 0
	var arrival_targets = 0
	for child in game.ui.get_children():
		if child is Panel and child.position == Vector2(442, 20): arrival_boards += 1
	for child in game.world.get_children():
		if child is Button: arrival_targets += 1
	check(arrival_boards == 0 and arrival_targets == 0, "开场不收货物：既没有目标板也没有货物热点")
	settle(game)

	# ---- 13. 读回真实磁盘、动画中断、航图返回与坏档保护 ----
	var again = Scene.instantiate(); again.save_path = path
	root.remove_child(game)
	root.add_child(again)
	await process_frame
	check(again.state.stage == "complete" and again.state.handed == solution_rows() and again.history.is_empty(),
		"重进本关直接回到收尾，且没有撤销栈")
	check(again.repository.read_profile(Rules.validate).status == "loaded", "落盘记录可以重新读取")
	again.commit(build(solution_rows(), "delivery")); settle(again)
	root.remove_child(again)
	var mid_probe = Scene.instantiate(); mid_probe.save_path = path
	root.add_child(mid_probe)
	await process_frame
	check(mid_probe.state.stage == "delivery" and mid_probe.state.handed == solution_rows() and
			mid_probe.buttons.has("skip"), "动画未完成时退出，再回来仍能看到当前一单")
	# 航图进来的那一趟要看收尾，先把这一单演完再离场。
	mid_probe.commit(build(solution_rows(), "complete"))
	root.remove_child(mid_probe)
	Bridge.origin = "hub"
	var routed = Scene.instantiate(); routed.save_path = path
	root.add_child(routed)
	await process_frame
	check(routed.origin == "hub" and Bridge.origin == "", "读取一次发送方即清空")
	check(routed.state.stage == "complete" and routed.buttons.has("back_hub") and
			not routed.buttons.has("open_hub"), "从航图进来时收尾只有一个返回航图")
	root.remove_child(routed)
	var broken_file = FileAccess.open(path, FileAccess.WRITE)
	broken_file.store_string("{not json}"); broken_file.close()
	var broken = Scene.instantiate(); broken.save_path = path
	root.add_child(broken)
	await process_frame
	check(broken.modal and broken.repository.protected and FileAccess.get_file_as_string(path) == "{not json}" and
			broken.state == Rules.fresh(), "坏 JSON 被原样保留，本关仍可安全重开")
	broken.buttons.protect_confirm.pressed.emit(); settle(broken)
	var kept_dir = DirAccess.open("/tmp")
	var backups = 0
	for file_name in kept_dir.get_files():
		if file_name.begins_with(path.get_file() + ".protected-"): backups += 1
	check(backups == 1 and broken.repository.read_profile(Rules.validate).status == "loaded" and
			not broken.repository.protected, "确认之后才归档损坏记录并重新开局")
	for file_name in kept_dir.get_files():
		if file_name.begins_with(path.get_file() + ".protected-"): kept_dir.remove(file_name)
	var fault_state = broken.state.duplicate(true)
	broken.repository.fail_at = "open"
	broken.advance()
	check(broken.state == fault_state and broken.modal and broken.buttons.has("retry"), "写入故障不推进阶段")
	settle(broken)
	broken.repository.fail_at = ""
	broken.retry_save(); settle(broken)
	check(broken.state.beat == 1 and not broken.modal, "重试成功后接着说下一句")
	root.remove_child(broken)
	for stale in [game, again, mid_probe, routed, broken]:
		if is_instance_valid(stale): stale.free()
	var janitor = DirAccess.open("/tmp")
	for file_name in janitor.get_files():
		if file_name.begins_with(path.get_file()): janitor.remove(file_name)
	check(not FileAccess.file_exists(path), "测试只留下 /tmp 里自己的临时档，且已清干净")

	print("MARKET MK12 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

extends SceneTree
# 无头规则检查：MK11「砝码也能站在货物旁」。不开窗口、不碰 user://，
# 所有写档都落在 /tmp 的一次性路径上；实窗审计由集成者另跑 window_focus。
# 这一关的命门是「秤只在提交之后说话」，所以除了状态机，还要穷举 27 种摆法，
# 确认 7 单位那一份解唯一、而且必须有一枚砝码站到灯油这一头来。
const Rules = preload("res://scripts/market/mk11_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Scene = preload("res://game/market_mk11.tscn")
# 唯一的解：货盘 灯油7 + 砝码3 = 对面 砝码9 + 砝码1 = 10。
const GOOD = [0, 1, 0]
const FAR = [1, 0, 1]
const EMPTY_PAN = [0, 0, 0]
var checks = 0
var failures = 0
var face: FontFile
var path = "/tmp/pixel-mk11-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 一份可存档的现场：抬过秤的每一幕都必须真的抬过秤，交付与完成只认那份解。
func pose(goods: Array, far: Array, oil: int, stage: String = "puzzle", weighs: int = 0) -> Dictionary:
	var state = Rules.fresh()
	state.stage = stage
	state.goods = goods.duplicate(true)
	state.far = far.duplicate(true)
	state.oil = oil
	if stage != "arrival": state.beat = Rules.BEATS - 1
	if stage in ["weighing", "result", "delivery", "complete"]: weighs = maxi(1, weighs)
	state.weighs = weighs
	return state

# 每一幕都取一份合法现场：开场三幕不许碰货，交付与完成只认那份解。
func legal_look(stage: String) -> Dictionary:
	if stage in ["arrival", "approach", "ready"]: return pose(EMPTY_PAN, EMPTY_PAN, 0, stage, 0)
	if stage == "puzzle" or stage == "result": return pose(EMPTY_PAN, [1, 1, 1], 7, stage, 1)
	if stage == "weighing": return pose(EMPTY_PAN, [0, 0, 1], 3, stage, 1)
	return pose(GOOD, FAR, 7, stage, 2)

func width(text: String, size_px: int) -> float:
	if face == null: face = UIStyle.face()
	return face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

# 汉字在 Godot 里是一个不断词：Label 不会在串中间换行，超框就是画到框外。
# Label 的字号会被 UIStyle.text_size 抬到 18/22/28，量之前先按同一条规则取整。
func fits(text: String, requested: int, box: float) -> bool:
	var size_px = UIStyle.text_size(requested)
	var ok = true
	for line in text.split("\n"):
		if width(line, size_px) > box: ok = false
	return ok

func rows(text: String) -> int: return text.split("\n").size()

# 世界层的木牌走 draw_string，字号原样生效，不做 18/22/28 的抬升。
func carves(text: String, size_px: int, box: float) -> bool:
	return width(text, size_px) <= box

# 落下动画只影响手感：清掉 it 再重画，热点的可用状态才与实窗一致。
func settle(game: Node) -> void:
	game.transient = 0.0
	game.refresh()

# 「· 键盘 X」这半句是热点对自己说的话：按那个键要做出跟点这下一模一样的动作才算数，
# 否则玩家照着提示按键，等来的却是把砝码请到另一头。逐条按键与点击各演一遍，比状态。
func advertised_audit(game: Node, ids: Array) -> Array:
	var advertised = {"1": KEY_1, "2": KEY_2, "3": KEY_3, "Q": KEY_Q, "W": KEY_W, "E": KEY_E,
		"A": KEY_A, "S": KEY_S}
	var named = 0
	var lied = 0
	for id in ids:
		var before = game.state.duplicate(true); var book = game.history.duplicate(true)
		settle(game)
		var tip: String = game.buttons[id].tooltip_text
		var at = tip.find("键盘 ")
		if at < 0: continue
		named += 1
		var key = advertised.get(tip.substr(at + 3).strip_edges(), -1)
		if key == -1:
			lied += 1; print("UNKNOWN key advertised by ", id, ": ", tip)
		else:
			for conn in game.buttons[id].get_signal_connection_list("pressed"):
				conn["callable"].call()
			var by_click = game.state.duplicate(true)
			game.apply_committed(before, book); settle(game)
			game.handle_key(int(key))
			var by_key = game.state.duplicate(true)
			game.apply_committed(before, book); settle(game)
			if by_click != by_key:
				lied += 1
				print("KEY MISMATCH ", id, " tip 「", tip, "」 click ", by_click, " key ", by_key)
	return [named, lied]

# 三枚砝码、每枚三个去处：27 种摆法，全部由规则层的记法生成。
func placements() -> Array:
	var all: Array = []
	for first in Rules.SIDES:
		for second in Rules.SIDES:
			for third in Rules.SIDES:
				var goods = Rules.empty_pan(); var far = Rules.empty_pan()
				var picks = [first, second, third]
				for index in range(Rules.COUNT):
					if picks[index] == Rules.GOODS: goods[index] = 1
					elif picks[index] == Rules.FAR: far[index] = 1
				all.append([goods, far])
	return all

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("MK11 rule watchdog"); quit(1))
	# ---- 1. 开局现场与字段 ----
	check(Rules.validate(Rules.fresh()), "fresh model validates")
	check(Rules.fresh().sample == "market-mk11-1", "fresh carries the mk11 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens on 陶姨's first line")
	check(Rules.fresh().goods == EMPTY_PAN and Rules.fresh().far == EMPTY_PAN, "all three weights start on the bench")
	check(Rules.fresh().oil == 0 and Rules.fresh().weighs == 0, "the pot is empty and the beam has never been lifted")
	check(Rules.fresh().hint == 0, "hints start unused")
	check(Rules.fresh().keys().size() == 8, "the profile carries exactly the eight frozen fields")
	check(Rules.WEIGHTS == [1, 3, 9] and Rules.COUNT == 3, "the loaned weights are 1, 3 and 9")
	check(Rules.PROMISE == 7 and Rules.OIL_MAX == 13, "the promise is exactly 7 units, the pot caps at the whole loan")
	check(Rules.OFF == 0 and Rules.GOODS == 1 and Rules.FAR == 2, "a weight has three homes and two pans")
	check(Rules.NEXT == [Rules.FAR, Rules.OFF, Rules.GOODS], "one click steps 台面 → 对面那盘 → 货盘 → 台面")
	check(Rules.STAGES == ["arrival","approach","ready","puzzle","weighing","result","delivery","complete"],
		"the stage list is the frozen eight")
	check(Rules.ANIMATIONS == ["approach","weighing","delivery"], "only the walk-in, the lift and the carry animate")
	# ---- 2. 穷举 27 种摆法：三进制砝码与 -13..13 一一对应 ----
	var seen := {}
	var mismatch := 0
	for pick in placements():
		var sum = Rules.signed_sum(pick[0], pick[1])
		if seen.has(sum): mismatch += 1
		seen[sum] = true
		var state = pose(pick[0], pick[1], 0)
		if not Rules.validate(state): mismatch += 1
		if Rules.difference(state) != sum: mismatch += 1
	check(mismatch == 0 and seen.size() == 27, "27 placements give 27 different signed sums")
	var gaps := {}
	for value in range(-13, 14): gaps[value] = 0
	for pick in placements(): gaps[Rules.signed_sum(pick[0], pick[1])] += 1
	var bijection = true
	for value in range(-13, 14):
		if gaps[value] != 1: bijection = false
	check(bijection, "every integer from -13 to 13 is hit by exactly one placement")
	var unique = true
	for amount in range(0, 14):
		var hits := []
		for pick in placements():
			# 称得出来 = 那一摆法恰好把秤压平：油 amount 与两盘砝码一起平衡。
			if Rules.balanced(pose(pick[0], pick[1], amount)): hits.append(pick)
		if hits.size() != 1: unique = false
	check(unique, "every amount 0..13 is weighable in exactly one way")
	var seven := []
	for pick in placements():
		if Rules.solved(pose(pick[0], pick[1], Rules.PROMISE)): seven.append(pick)
	check(seven.size() == 1, "the 7-unit promise has one solution, not a family of them")
	check(seven[0][0] == GOOD and seven[0][1] == FAR, "that solution is 油+3 对 9+1")
	check(Rules.pan_total(pose(GOOD, FAR, 7), Rules.GOODS) == 10 and Rules.pan_total(pose(GOOD, FAR, 7), Rules.FAR) == 10,
		"both pans really press 10 units in the solution")
	check(Rules.equation(pose(GOOD, FAR, 7)) == "灯油 7 + 砝码 3 = 砝码 1 + 砝码 9", "the equation reads the way it is taught")
	var naive_pans := []
	var naive_amounts := []
	for pick in placements():
		if pick[0] != EMPTY_PAN: continue
		naive_pans.append(pick[1])
		for amount in range(0, 14):
			if Rules.balanced(pose(pick[0], pick[1], amount)) and not naive_amounts.has(amount): naive_amounts.append(amount)
	check(naive_pans.size() == 8, "keeping every weight off the goods pan leaves eight arrangements")
	naive_amounts.sort()
	check(naive_amounts == [0, 1, 3, 4, 9, 10, 12, 13], "the far-pan-only trick can only weigh those amounts")
	check(not naive_amounts.has(7), "7 units is unreachable while all weights stand opposite")
	var needs_goods := 0
	for pick in placements():
		if Rules.solved(pose(pick[0], pick[1], 7)) and Rules.pan_count(pose(pick[0], pick[1], 7), Rules.GOODS) == 0:
			needs_goods += 1
	check(needs_goods == 0, "the only 7-unit solution puts a weight beside the oil")
	check(Rules.balanced(pose(EMPTY_PAN, [1, 1, 1], 13)) and not Rules.solved(pose(EMPTY_PAN, [1, 1, 1], 7)),
		"all three opposite weigh 13, not 7")
	check(Rules.difference(pose(EMPTY_PAN, [1, 1, 1], 7)) == 6, "the naive guess is off by six units, honestly")
	check(Rules.tilt(pose(EMPTY_PAN, [1, 1, 1], 7)) == 1.0, "a six-unit gap bottoms the beam out at full tilt")
	check(Rules.tilt(pose(GOOD, FAR, 7)) == 0.0 and Rules.balanced(pose(GOOD, FAR, 7)), "the solution reads level")
	check(absf(Rules.tilt(pose(GOOD, FAR, 8)) + 1.0 / 3.0) < 0.0001, "one unit over the promise tips the goods pan")
	check(Rules.heavier(pose(GOOD, FAR, 8)) == Rules.GOODS and Rules.heavier(pose(GOOD, FAR, 6)) == Rules.FAR,
		"over- and under-filling sink opposite pans")
	check(Rules.heavier(pose(GOOD, FAR, 7)) == Rules.OFF and Rules.heavier_word(pose(GOOD, FAR, 7)) == "两边",
		"a level beam has no heavier side")
	check(Rules.terms(pose(EMPTY_PAN, EMPTY_PAN, 0), Rules.GOODS) == ["空盘"], "an empty pan still has a name")
	# ---- 3. 阶段机 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.stage == "arrival" and arriving.beat == 1, "the first line asks for the next one")
	arriving = Rules.advance(arriving)
	check(arriving.beat == 2 and Rules.advance(arriving).stage == "approach", "the third line walks up to the scale")
	var walked = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(walked.stage == "puzzle" and walked.oil == 0 and walked.goods == EMPTY_PAN, "the walk-in never touches the goods")
	check(not (walked.stage in Rules.ANIMATIONS), "puzzle is not an animation stage")
	var single = true
	for stage in Rules.STAGES:
		# 结果牌是唯一不往前落的幕：读完判词就把摆法原样交回台面，另有一行专门验它。
		if stage in ["arrival", "complete", "result"]: continue
		var look = pose(GOOD, FAR, 7, stage, 2) if stage == "delivery" else pose(EMPTY_PAN, [0, 0, 1], 3, stage, 1)
		var moved = Rules.advance(look)
		if moved.is_empty(): single = false; continue
		if moved.stage != Rules.STAGES[Rules.STAGES.find(stage) + 1]: single = false
	check(single, "every stage but the verdict board advances exactly one step")
	check(Rules.advance(pose(EMPTY_PAN, EMPTY_PAN, 0)).is_empty(), "an untouched bench cannot lift the beam")
	check(Rules.advance(pose(GOOD, FAR, 0)).is_empty(), "weights alone are not yet an oil order")
	check(Rules.advance(pose(EMPTY_PAN, EMPTY_PAN, 7)).is_empty(), "oil alone never lifts the beam")
	var lifted = Rules.advance(pose(EMPTY_PAN, [0, 0, 1], 7))
	check(lifted.stage == "weighing" and lifted.weighs == 1, "submit lifts the beam and counts the weigh")
	check(lifted.oil == 7 and lifted.far == [0, 0, 1], "the lift changes nothing on the pans")
	check(Rules.advance(lifted).stage == "result", "an unsolved lift lands on the result board")
	check(Rules.advance(Rules.advance(lifted)).stage == "puzzle", "the result board hands the arrangement back")
	check(Rules.advance(pose(GOOD, FAR, 7)).weighs == 1, "the winning submit is also just one weigh")
	check(Rules.advance(Rules.advance(pose(GOOD, FAR, 7))).stage == "delivery", "a kept promise goes straight to the carry")
	check(Rules.advance(Rules.advance(Rules.advance(pose(GOOD, FAR, 7)))).stage == "complete", "the sealed jar closes the scene")
	check(Rules.advance(pose(GOOD, FAR, 7, "complete", 2)).is_empty(), "complete has no next stage")
	check(Rules.advance(pose(EMPTY_PAN, [0, 0, 1], 3, "result", 1)).stage == "puzzle", "the result board never repeats itself")
	check(Rules.advance(pose(EMPTY_PAN, [0, 0, 1], 3, "result", 1)).oil == 3, "reading the verdict costs no oil")
	check(Rules.advance(pose(EMPTY_PAN, [1, 1, 1], 7, "puzzle", 4)).weighs == 5, "a second try counts as its own weigh")
	# ---- 4. 摆法可逆：拿起来又放回，绝不留幻影砝码 ----
	var board = pose(EMPTY_PAN, EMPTY_PAN, 0)
	check(Rules.place(Rules.fresh(), 0, Rules.FAR).is_empty(), "no weight moves before the table opens")
	check(Rules.cycle(Rules.fresh(), 0).is_empty(), "the keyboard is idle during the lines")
	check(Rules.draw_oil(Rules.fresh()).is_empty() and Rules.pour_back(Rules.fresh()).is_empty(),
		"the oil tap is shut during the lines")
	check(Rules.place(board, -1, Rules.FAR).is_empty() and Rules.place(board, Rules.COUNT, Rules.FAR).is_empty(),
		"unknown weights are refused")
	check(Rules.place(board, 0, Rules.OFF).is_empty() and Rules.place(board, 0, 7).is_empty(),
		"the bench is not a pan")
	var first = Rules.place(board, 0, Rules.FAR)
	check(first.far == [1, 0, 0] and first.goods == EMPTY_PAN, "one weight steps onto the far pan")
	check(board.far == EMPTY_PAN, "the previous state is left untouched")
	check(Rules.place(first, 0, Rules.FAR).is_empty(), "a weight already standing there is not placed twice")
	var moved_over = Rules.place(first, 0, Rules.GOODS)
	check(moved_over.goods == [1, 0, 0] and moved_over.far == EMPTY_PAN, "calling it to the goods pan clears the far pan")
	check(Rules.validate(moved_over), "the moved state is a legal save")
	var back_home = Rules.return_weight(moved_over, 0)
	check(back_home.goods == EMPTY_PAN and back_home.far == EMPTY_PAN, "putting it back clears both pans at once")
	check(not Rules.can_return(back_home, 0), "an empty bench slot has nothing to take back")
	check(Rules.return_weight(back_home, 0).is_empty(), "a second take-back is refused, not a negative count")
	var cycled = board
	var trail := []
	for step in range(4):
		cycled = Rules.cycle(cycled, 1)
		if cycled.is_empty(): break
		trail.append([cycled.goods[1], cycled.far[1]])
	check(trail == [[0,1],[1,0],[0,0],[0,1]], "one weight cycles 台面 → 对面那盘 → 货盘 → 台面")
	check(Rules.cycle(board, 0).far == [1, 0, 0], "the first click is the naive one: onto the far pan")
	check(Rules.side_of(pose(GOOD, FAR, 7), 0) == Rules.FAR and Rules.side_of(pose(GOOD, FAR, 7), 1) == Rules.GOODS,
		"the side reader agrees with the two arrays")
	check(Rules.side_of(pose(EMPTY_PAN, [1, 0, 0], 1), 1) == Rules.OFF and Rules.side_of(pose(EMPTY_PAN, [1, 0, 0], 1), 2) == Rules.OFF,
		"a weight neither pan took still reads as the bench")
	check(Rules.pan_count(pose(GOOD, FAR, 7), Rules.GOODS) == 1 and Rules.pan_count(pose(GOOD, FAR, 7), Rules.FAR) == 2,
		"one weight here, two there")
	check(Rules.weights_on_scale(pose(GOOD, FAR, 7)) == 3, "all three loans are on the scale")
	check(Rules.weight_total(pose(GOOD, FAR, 7), Rules.FAR) == 10 and Rules.weight_total(pose(GOOD, FAR, 7), Rules.GOODS) == 3,
		"the goods pan's own weight excludes the oil")
	check(Rules.pan_total(pose(GOOD, FAR, 7), Rules.GOODS) == 10, "the goods pan presses oil plus weight")
	var phantom = 0
	for pick in placements():
		var walk = pose(EMPTY_PAN, EMPTY_PAN, 0)
		for index in range(Rules.COUNT):
			if pick[0][index] == 1: walk = Rules.place(walk, index, Rules.GOODS)
			elif pick[1][index] == 1: walk = Rules.place(walk, index, Rules.FAR)
		if walk.is_empty() or walk.goods != pick[0] or walk.far != pick[1]: phantom += 1
		var wiped = walk
		for index in range(Rules.COUNT):
			if Rules.can_return(wiped, index): wiped = Rules.return_weight(wiped, index)
		if wiped.is_empty() or wiped.goods != EMPTY_PAN or wiped.far != EMPTY_PAN: phantom += 1
	check(phantom == 0, "all 27 placements are reachable and every one wipes clean")
	var filled = board
	for step in range(Rules.OIL_MAX + 3):
		if Rules.can_draw(filled): filled = Rules.draw_oil(filled)
	check(filled.oil == Rules.OIL_MAX, "the tap stops at thirteen units")
	check(Rules.draw_oil(filled).is_empty(), "a fourteenth unit is refused outright")
	var drained = filled
	for step in range(Rules.OIL_MAX + 2):
		if Rules.can_pour_back(drained): drained = Rules.pour_back(drained)
	check(drained.oil == 0 and Rules.pour_back(drained).is_empty(), "pouring back empties the pot and then refuses")
	check(Rules.validate(drained), "the pot round trip leaves a legal save")
	# ---- 5. 提交闸口只管动手，不管数学 ----
	check(Rules.shortfalls(pose(EMPTY_PAN, EMPTY_PAN, 0)) == [
		"接油罐还空着：先拧开油壶，一格一格往货盘里接。",
		"三枚砝码都还在台面上：至少请一枚上秤，空秤称不出任何约定。"],
		"an untouched bench names both undone duties")
	check(Rules.shortfalls(pose(EMPTY_PAN, EMPTY_PAN, 7)).size() == 1, "oil alone leaves one duty open")
	check("砝码" in Rules.shortfalls(pose(EMPTY_PAN, EMPTY_PAN, 7))[0], "the remaining duty is the weights")
	check(Rules.shortfalls(pose(GOOD, FAR, 0)).size() == 1, "weights alone leave the oil duty")
	check(Rules.shortfalls(pose(EMPTY_PAN, [1, 1, 1], 7)).is_empty(), "the naive guess passes the gate and gets weighed")
	check(Rules.shortfalls(pose(GOOD, FAR, 7)).is_empty() and Rules.ready_to_weigh(pose(GOOD, FAR, 7)),
		"the solution is always allowed up")
	var gate := {}
	for pick in placements():
		for amount in range(0, 14):
			var state = pose(pick[0], pick[1], amount)
			var blocked = not Rules.shortfalls(state).is_empty()
			if blocked != (amount == 0 or Rules.weights_on_scale(state) == 0): gate[str(pick) + str(amount)] = true
	check(gate.is_empty(), "the gate blocks nothing but an empty pot or an untouched bench")
	var leaks = 0
	for pick in placements():
		for amount in range(0, 14):
			for word in ["差", "多", "沉", "不平", "答案", "7 单位"]:
				if word in " ".join(Rules.shortfalls(pose(pick[0], pick[1], amount))): leaks += 1
	check(leaks == 0, "the submit gate never speaks the balance out loud")
	check(not Rules.solved(pose(EMPTY_PAN, [1, 1, 1], 7)) and Rules.ready_to_weigh(pose(EMPTY_PAN, [1, 1, 1], 7)),
		"the near miss is reachable and only the beam can reject it")
	# ---- 6. 抬秤之后的如实回话：点名那一盘 ----
	# 平秤却接错数：1 + 8 = 9 与 3 + 6 = 9 都是平的，只有约定被打破，秤杆不该背锅。
	var over = pose([1, 0, 0], [0, 0, 1], 8)
	check(Rules.balanced(over) and not Rules.promise_kept(over), "a level beam can still break the promise")
	check(Rules.result_lines(over).size() == 1, "one unit over breaks only the promise")
	check("多了 1 单位" in Rules.result_lines(over)[0], "the overshoot is named in units")
	check("沉" not in Rules.result_line(over), "a level beam is never blamed")
	var under = pose([0, 1, 0], [0, 0, 1], 6)
	check(Rules.balanced(under) and Rules.result_lines(under).size() == 1
		and "还差 1 单位" in Rules.result_lines(under)[0], "a unit short is named as a debt, not a failure")
	var naive_read = Rules.result_lines(pose(EMPTY_PAN, [1, 1, 1], 7))
	check(naive_read.size() == 1 and "对面那盘沉下去了" in naive_read[0], "the naive guess is reported as the far pan sinking")
	check("货盘 7 单位" in naive_read[0] and "对面 13 单位" in naive_read[0], "both pan totals are read back")
	var heavy_goods = Rules.result_lines(pose(EMPTY_PAN, [0, 0, 1], 10))
	check("货盘这一头沉下去了" in heavy_goods[0], "overfilling past the far pan sinks the goods pan")
	var both_wrong = Rules.result_lines(pose(GOOD, FAR, 8))
	check(both_wrong.size() == 2 and "货盘这一头沉下去了" in both_wrong[0] and "多了 1 单位" in both_wrong[1],
		"an unbalanced beam and a broken promise are two separate sentences")
	check(Rules.result_lines(pose(GOOD, FAR, 7)).is_empty(), "the solution needs no verdict")
	check("沉下去了" in Rules.beam_line(pose(GOOD, FAR, 8)), "the beam line always names the sinking pan")
	check(Rules.promise_kept(pose(GOOD, FAR, 7)) and not Rules.promise_kept(pose(GOOD, FAR, 6)),
		"the promise reader only accepts exactly seven")
	check(Rules.heavier_word(pose(EMPTY_PAN, [1, 1, 1], 7)) == "对面那盘", "the far pan keeps its own name")
	check(Rules.pan_name(Rules.GOODS) == "货盘" and Rules.pan_name(Rules.FAR) == "对面那盘" and Rules.pan_name(Rules.OFF) == "台面",
		"three homes, three names")
	# ---- 7. 撤销与快照 ----
	var snap = {"goods": GOOD.duplicate(true), "far": FAR.duplicate(true), "oil": 7}
	var half_set = pose(EMPTY_PAN, [1, 0, 0], 3)
	var half_snap = {"goods": EMPTY_PAN.duplicate(true), "far": [1, 0, 0], "oil": 3}
	check(Rules.restore(Rules.place(half_set, 1, Rules.FAR), half_snap).far == [1, 0, 0], "undo rewinds a weight called onto a pan")
	check(Rules.restore(Rules.place(half_set, 0, Rules.GOODS), half_snap).far == [1, 0, 0],
		"undo rewinds a weight moved across the beam")
	check(Rules.restore(Rules.return_weight(pose(GOOD, FAR, 7), 1), snap).goods == GOOD, "undo rewinds a taken-back weight")
	check(Rules.restore(Rules.draw_oil(pose(GOOD, FAR, 7)), snap).oil == 7, "undo rewinds a drawn unit")
	check(Rules.restore(Rules.pour_back(pose(GOOD, FAR, 7)), snap).oil == 7, "undo rewinds a poured-back unit")
	var every = 0
	for pick in placements():
		var prior = pose(pick[0], pick[1], 5)
		for index in range(Rules.COUNT):
			for target in [Rules.GOODS, Rules.FAR]:
				var after = Rules.place(prior, index, target)
				if after.is_empty(): continue
				if Rules.restore(after, {"goods": prior.goods, "far": prior.far, "oil": prior.oil}) != prior: every += 1
			var lifted_off = Rules.return_weight(prior, index)
			if not lifted_off.is_empty():
				if Rules.restore(lifted_off, {"goods": prior.goods, "far": prior.far, "oil": prior.oil}) != prior: every += 1
	check(every == 0, "every move in reach round-trips through the undo snapshot")
	var weigher = pose(GOOD, FAR, 7, "puzzle", 3)
	check(Rules.restore(Rules.draw_oil(weigher), snap).weighs == 3, "undo cannot erase a weigh that already happened")
	check(Rules.restore(pose(GOOD, FAR, 7, "arrival"), snap).is_empty(), "undo only works at the scale")
	check(Rules.restore(pose(GOOD, FAR, 7, "weighing", 1), snap).is_empty(), "undo cannot reopen a lifted beam")
	check(Rules.restore(pose(GOOD, FAR, 7, "complete", 1), snap).is_empty(), "undo cannot un-deliver a sealed jar")
	check(Rules.restore(pose(GOOD, FAR, 7), {"goods": GOOD, "far": FAR}).is_empty(), "a snapshot without the oil is refused")
	check(Rules.restore(pose(GOOD, FAR, 7), {"goods": GOOD, "oil": 7}).is_empty(), "a snapshot without both pans is refused")
	check(Rules.restore(pose(GOOD, FAR, 7), {"goods": [1, 0, 0], "far": [1, 0, 0], "oil": 7}).is_empty(),
		"undo refuses a placement that double-books a weight")
	check(Rules.restore(pose(GOOD, FAR, 7), {"goods": GOOD, "far": FAR, "oil": 14}).is_empty(), "undo refuses an overfull pot")
	check(Rules.restore(pose(GOOD, FAR, 7), {"goods": GOOD, "far": FAR, "oil": 7.0}).is_empty(),
		"a float oil count is not a snapshot")
	check(Rules.cleared(pose(GOOD, FAR, 7, "puzzle", 2)) == pose(EMPTY_PAN, EMPTY_PAN, 0, "puzzle", 2),
		"重摆 wipes the pans and keeps the weigh count")
	check(Rules.validate(Rules.cleared(pose(GOOD, FAR, 7, "puzzle", 2))), "the wiped table is a legal save")
	# ---- 8. 存档 schema：坏档一律拒收 ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record " + str(bad))
	var piece = pose(GOOD, FAR, 7, "puzzle", 1)
	piece.sample = "market-mk03-1"
	check(not Rules.validate(piece), "a foreign sample is rejected")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.stage = "weigh"
	check(not Rules.validate(piece), "an unknown stage is rejected")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.erase("stage")
	check(not Rules.validate(piece), "a record without a stage is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.beat = 3
	check(not Rules.validate(piece), "arrival beats are bounded")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.beat = -1
	check(not Rules.validate(piece), "beats cannot go negative")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.beat = "2"
	check(not Rules.validate(piece), "a string beat is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.beat = 1
	check(not Rules.validate(piece), "a later stage cannot keep a half-finished intro")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.hint = Rules.HINT_TIERS + 1
	check(not Rules.validate(piece), "hint level is capped")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.hint = -1
	check(not Rules.validate(piece), "hints cannot go negative")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.hint = 1.0
	check(not Rules.validate(piece), "a float hint count is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.goods = [1, 1, 1, 1]
	check(not Rules.validate(piece), "a goods pan longer than the loan is rejected")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.far = [1, 0]
	check(not Rules.validate(piece), "a short far pan is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.goods = [0, 2, 0]
	check(not Rules.validate(piece), "a pan flag outside 0/1 is rejected")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.goods = [-1, 0, 0]
	check(not Rules.validate(piece), "negative pan flags are rejected")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.goods = [0, 1.0, 0]
	check(not Rules.validate(piece), "a fractional weight is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.far = ["1", 0, 1]
	check(not Rules.validate(piece), "a string flag is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.goods = 5
	check(not Rules.validate(piece), "a pan is an array, not a number")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.far = null
	check(not Rules.validate(piece), "a null pan is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.erase("goods")
	check(not Rules.validate(piece), "a missing field is corruption, not a default")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.oil = Rules.OIL_MAX + 1
	check(not Rules.validate(piece), "the pot cannot hold fourteen units")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.oil = -1
	check(not Rules.validate(piece), "the pot cannot hold minus one")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.oil = 6.5
	check(not Rules.validate(piece), "half a unit is not a click of the tap")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.oil = "7"
	check(not Rules.validate(piece), "a string oil count is corruption")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.erase("oil")
	check(not Rules.validate(piece), "a record without the pot is corruption")
	piece = pose(GOOD, [1, 0, 1], 7, "puzzle", 1); piece.goods = [1, 1, 0]
	check(not Rules.validate(piece), "one weight standing on both pans at once is rejected")
	piece = pose([1, 1, 1], [1, 1, 1], 7, "puzzle", 1)
	check(not Rules.validate(piece), "a save that used every weight twice is rejected")
	piece = pose(EMPTY_PAN, EMPTY_PAN, 0, "puzzle", -1)
	check(not Rules.validate(piece), "the weigh count cannot go negative")
	piece = pose(EMPTY_PAN, EMPTY_PAN, 0, "puzzle", 1); piece.weighs = 1.5
	check(not Rules.validate(piece), "a fractional weigh count is corruption")
	piece = pose(EMPTY_PAN, EMPTY_PAN, 0, "puzzle", 1); piece.weighs = "2"
	check(not Rules.validate(piece), "a string weigh count is corruption")
	piece = pose(GOOD, FAR, 7, "arrival")
	check(not Rules.validate(piece), "the walk-in cannot carry an arrangement")
	piece = pose(EMPTY_PAN, [1, 0, 0], 4, "approach")
	check(not Rules.validate(piece), "nobody has reached the scale yet")
	piece = pose(EMPTY_PAN, EMPTY_PAN, 3, "ready")
	check(not Rules.validate(piece), "the tap cannot run before the table opens")
	check(Rules.validate(pose(EMPTY_PAN, [0, 0, 1], 7, "puzzle", 0)),
		"the very first arrangement at the table is a legal save with zero lifts")
	piece = pose(GOOD, FAR, 7, "weighing", 1); piece.weighs = 0
	check(not Rules.validate(piece), "the lift stage must have lifted")
	piece = pose(GOOD, FAR, 7, "result", 1)
	check(not Rules.validate(piece), "a solved arrangement cannot still hold a verdict board up")
	piece = pose(EMPTY_PAN, [1, 1, 1], 7, "delivery", 1)
	check(not Rules.validate(piece), "an unbalanced pan cannot seal a jar")
	piece = pose(GOOD, FAR, 6, "complete", 1)
	check(not Rules.validate(piece), "a complete with six units is a forged promise")
	piece = pose(GOOD, FAR, 7, "complete", 1); piece.far = [1, 0, 0]
	check(not Rules.validate(piece), "a complete with an unbalanced beam is rejected")
	piece = pose(GOOD, FAR, 7, "puzzle", 1); piece.erase("far")
	check(not Rules.validate(piece), "one pan array is not enough to describe the scale")
	check(Rules.validate(pose(GOOD, FAR, 7)), "the solution at the table is a legal save")
	check(Rules.validate(pose(EMPTY_PAN, [1, 1, 1], 7, "puzzle", 3)), "a failed guess kept on the table is a legal save")
	check(Rules.validate(pose(EMPTY_PAN, [0, 0, 1], 3, "weighing", 1)), "the lift is a legal save")
	check(Rules.validate(pose(GOOD, FAR, 7, "delivery", 2)), "the carry is a legal save")
	check(Rules.validate(pose(GOOD, FAR, 7, "complete", 2)), "the cleared scene is a legal save")
	var capped = pose(EMPTY_PAN, EMPTY_PAN, Rules.OIL_MAX, "puzzle", 5); capped.hint = Rules.HINT_TIERS
	check(Rules.validate(capped), "a fully hinted, fully filled pot is inside the bounds")
	# ---- 9. 章节目录与本关身份 ----
	var entry = Catalog.LEVELS["MK11"]
	check(entry.title == "砝码也能站在货物旁", "the catalog title is the level title")
	check(entry.scene == "res://game/market_mk11.tscn", "the catalog points at the shipped scene path")
	check(ResourceLoader.exists(entry.scene) and Catalog.built("MK11"), "the scene file exists so the chart lights up")
	check(entry.save == "user://profiles/market-mk11-1/save-v1.json", "the catalog save path is the mk11 profile")
	check(entry.kit == "oil" and entry.act == 5 and entry.after == "MK10", "act 5, oil kit, opens after MK10")
	check(entry.goal == "用 1、3、9 三枚砝码称出恰好 7 单位灯油", "the chart card states the promise in units")
	check(Catalog.ACTS[entry.act] == "公平不只是一样多", "the level belongs to the fairness act")
	check(Catalog.save_path("MK11") == entry.save and Catalog.title("MK11") == entry.title, "the catalog accessors agree")
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == Catalog.save_path("MK11"), "configure only fills the catalog save path as a default")
	check(probe.scene_id == "oil" and probe.level_id == "MK11", "the scene declares its own identity")
	check(probe.title == entry.title, "the window title comes from the catalog")
	check(probe.rules == Rules and probe.world_script.resource_path.ends_with("mk11_world.gd"), "the host is wired to mk11")
	check(probe.durations.has("weighing") and probe.durations.has("delivery"), "the host owns the stage durations")
	check(probe.zoom_stages.has("puzzle") and not probe.zoom_stages.has("result"), "only the table and the lift lean in")
	probe.free()
	# ---- 10. 真实场景：热点、按钮、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.save_path == path, "an injected test path survives configure")
	check(game.state.stage == "arrival" and game.repository.path == path, "a new profile opens on 陶姨's first line")
	check(game.buttons.has("next") and game.buttons["next"].text == "继续听他们说", "the first beat only asks to keep listening")
	var beats_ok = true
	for beat in range(Rules.BEATS):
		var speaker = pose(EMPTY_PAN, EMPTY_PAN, 0, "arrival", 0); speaker.beat = beat
		game.apply_committed(speaker, [])
		if not fits(game.line(), 20, 798.0) or rows(game.line()) > 2: beats_ok = false
	check(beats_ok, "all three arrival lines fit the spoken board in two lines")
	check(fits(game.goal_line(), 22, 762.0), "the goal board fits one line")
	game.apply_committed(pose(EMPTY_PAN, EMPTY_PAN, 0, "arrival", 0), [])
	game.advance(); game.advance(); game.advance()
	check(game.state.stage == "approach", "the third line starts the walk-in")
	game.skip_animation(); settle(game)
	check(game.state.stage == "ready" and game.buttons.has("next"), "ready offers the way to the scale")
	check(game.buttons["next"].text == "开始分油", "the ready button names the oil")
	game.advance(); settle(game)
	check(game.state.stage == "puzzle", "the table opens")
	check(game.buttons.has("deliver") and game.buttons["deliver"].text == "抬起这杆秤", "submit lifts the beam, it does not grade it")
	check(game.buttons.has("undo") and game.buttons["undo"].disabled, "undo is idle before the first move")
	check(game.buttons.has("reset") and game.buttons.has("hint"), "the table offers 重摆 and 请扣扣提醒")
	var ids = ["valve", "ladle", "pot", "bench_0", "bench_1", "bench_2",
		"pan_1_0", "pan_2_0", "pan_1_1", "pan_2_1", "pan_1_2", "pan_2_2"]
	var absent = 0
	for id in ids:
		if not game.buttons.has(id): absent += 1
	check(absent == 0 and game.buttons.size() == ids.size() + 4, "all twelve scale hotspots are registered")
	check(game.world.targets().size() == 12, "the world exposes exactly those twelve hit targets")
	var small = 0
	var outside = 0
	var overlap = 0
	var rects = game.world.targets()
	for rect in rects:
		if rect.size.x < 48 or rect.size.y < 48: small += 1
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 720: outside += 1
	for a in range(rects.size()):
		for b in range(a + 1, rects.size()):
			if rects[a].intersects(rects[b]): overlap += 1
	check(small == 0, "every scale target is at least 48x48 logical pixels")
	check(outside == 0, "every scale target stays inside the 1280x720 frame")
	check(overlap == 0, "no two scale targets overlap, so every one is clickable")
	var drifted = 0
	for id in ids:
		var rect: Rect2 = game.buttons[id].get_global_rect()
		if rect.size.x < 48 or rect.size.y < 48: drifted += 1
		if rect.position.x < 0 or rect.position.y < 166 or rect.end.x > 1280 or rect.end.y > 646: drifted += 1
	check(drifted == 0, "the zoomed hotspots stay tappable and clear of the boards and the button row")
	# 三种台面各量一遍：空着的格、站着砝码的格、要挪去另一头的格，提示话术都不一样。
	var told = 0
	var mistaken = 0
	for layout in [[EMPTY_PAN, EMPTY_PAN], [[1, 0, 0], EMPTY_PAN], [EMPTY_PAN, [0, 1, 0]]]:
		game.apply_committed(pose(layout[0], layout[1], 0, "puzzle", 0), [])
		settle(game)
		var verdict = advertised_audit(game, ids)
		told += int(verdict[0]); mistaken += int(verdict[1])
	check(mistaken == 0 and told >= 12, "every shortcut a hotspot advertises is the one it really answers to")
	game.apply_committed(pose(EMPTY_PAN, EMPTY_PAN, 0, "puzzle", 0), []); settle(game)
	game.do_place(0, Rules.FAR); settle(game)
	check(game.state.far == [1, 0, 0] and not game.buttons["undo"].disabled, "a weight called onto the far pan is saved")
	check(game.world.land_place == "pan" and game.world.land_slot == 20, "the landing knows which weight just dropped")
	game.do_cycle(0); settle(game)
	check(game.state.goods == [1, 0, 0] and game.state.far == EMPTY_PAN, "the second click moves it beside the oil")
	game.do_cycle(0); settle(game)
	check(game.state.goods == EMPTY_PAN, "the third click puts it back on the bench")
	game.do_place(0, Rules.GOODS); settle(game)
	check(game.state.goods == [1, 0, 0], "an empty slot can call a weight straight onto the goods pan")
	game.do_return(0); settle(game)
	check(game.state.goods == EMPTY_PAN and game.state.far == EMPTY_PAN, "putting it back leaves no phantom weight")
	game.do_draw(); settle(game); game.do_draw(); settle(game)
	check(game.state.oil == 2 and game.status_line() == "接油 2 · 上秤 0 枚 · 抬 0 次", "the status only reports what the player did")
	game.do_pour_back(); settle(game)
	check(game.state.oil == 1, "the ladle takes one unit back")
	game.undo(); settle(game)
	check(game.state.oil == 2, "undo rewinds through the host")
	var rewound = 0
	while not game.history.is_empty() and rewound < 12:
		game.undo(); settle(game); rewound += 1
	check(game.state.oil == 0 and game.history.is_empty() and game.state.goods == EMPTY_PAN,
		"the rewind consumes every recorded step and leaves nothing behind")
	game.do_place(1, Rules.GOODS); settle(game)
	game.do_place(1, Rules.FAR); settle(game)
	check(game.state.goods == EMPTY_PAN and game.state.far == [0, 1, 0], "moving a weight across clears the old pan")
	game.do_reset()
	check(game.state.goods == EMPTY_PAN and game.state.far == EMPTY_PAN and game.state.oil == 0,
		"重摆 clears the pans and the pot without leaving the scale")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "open"; game.do_place(2, Rules.FAR)
	check(game.modal and game.state.far == EMPTY_PAN and FileAccess.get_file_as_bytes(path) == bytes,
		"a failed placement save keeps the last written arrangement")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(not game.modal and game.state.far == [0, 0, 1], "retry republishes the same placement")
	game.do_reset(); settle(game)
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and "接油罐还空着" in game.message, "submit refuses an empty pot")
	game.do_draw(); settle(game)
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and "三枚砝码都还在台面上" in game.message, "submit refuses an untouched bench")
	game.do_place(0, Rules.FAR); settle(game)
	game.do_place(1, Rules.FAR); settle(game)
	game.do_place(2, Rules.FAR); settle(game)
	for step in range(6): game.do_draw(); settle(game)
	check(game.state.oil == 7 and game.state.far == [1, 1, 1], "seven clicks and all three weights opposite")
	game.advance()
	check(game.state.stage == "weighing" and game.state.weighs == 1, "the naive arrangement is allowed up")
	game.skip_animation(); settle(game)
	check(game.state.stage == "result", "the beam answers with an honest tilt")
	check("对面那盘沉下去了" in game.line() and "还差" not in game.line(), "the verdict names the sinking pan only")
	game.advance(); settle(game)
	check(game.state.stage == "puzzle" and game.state.oil == 7 and game.state.far == [1, 1, 1],
		"reading the verdict keeps the arrangement intact")
	game.do_place(1, Rules.GOODS); settle(game)
	check(Rules.solved(game.state), "the 3 steps beside the oil and the 9 stays opposite")
	game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINT_TIERS and "把 9 单独留在对面" in game.message, "the third hint walks one step")
	game.hint()
	check(game.state.hint == Rules.HINT_TIERS and Rules.validate(game.state), "hints stop at the shipped tier count")
	check(game.hint_texts().size() == Rules.HINT_TIERS, "the hint bound matches the shipped hint count")
	var hinted = game.state.duplicate(true)
	game.advance()
	check(game.state.stage == "weighing", "three hints never block the win")
	game.skip_animation(); settle(game)
	check(game.state.stage == "delivery", "a hinted solution carries the same jar")
	game.skip_animation(); settle(game)
	check(game.state.stage == "complete" and game.state.hint == hinted.hint, "the carry closes the scene")
	var on_disk = game.state.duplicate(true)
	check(game.buttons["next"].text == "重新体验" and game.buttons.has("open_hub"), "a standalone sample keeps its own exit")
	check(game.buttons["open_hub"].position == Vector2(690, 646) and game.buttons["open_hub"].size == Vector2(280, 54),
		"the exit button sits on the shared row")
	var boards = game.world.boards()
	var spill = 0
	for plaque in boards:
		if not carves(plaque["text"], int(plaque["px"]), plaque["rect"].size.x - 16): spill += 1
	check(spill == 0 and boards.size() == 3, "all three scale boards hold their own text")
	var carved = 0
	var overflow = 0
	for stage in Rules.STAGES:
		game.apply_committed(legal_look(stage), [])
		for note in game.world.notes():
			carved += 1
			if not carves(note["text"], int(note["px"]), float(note["width"])): overflow += 1
	check(overflow == 0 and carved >= 18, "every outlined readout in the world fits its own budget")
	var widest = 0.0
	for pick in placements():
		for amount in range(0, 14):
			widest = maxf(widest, width(Rules.equation(pose(pick[0], pick[1], amount)), 15))
	check(widest <= 314.0, "the longest arrangement still fits the equation board")
	game.apply_committed(pose(GOOD, FAR, 7, "complete", 2), [])
	# 预算跟着纸面走：挪动验看单的宽度时不必再回来改一个写死的数。
	var sheet = game.receipt_text_rect().size.x
	var receipt = 0
	for line in game.receipt_lines():
		if not fits(line, 16, sheet): receipt += 1
	check(receipt == 0 and game.receipt_lines().size() == 6,
		"the 衡伯 slip fits its panel and restates both pans")
	# 纵向同理：六行的总高（extra() 把行距覆盖成 0，就只剩字形高）不许越过纸面下沿。
	check(game.receipt_lines().size() * face.get_height(UIStyle.text_size(16))
		<= game.receipt_text_rect().size.y, "all six lines of the slip stay on the paper")
	check("灯油 7 + 砝码 3 = 10 单位" in game.receipt_lines()[2], "the slip reads the goods pan the way it was pressed")
	check("砝码 1 + 砝码 9 = 10 单位" in game.receipt_lines()[3], "the slip reads the far pan the way it was pressed")
	var lines_ok = true
	for stage in Rules.STAGES:
		game.apply_committed(legal_look(stage), [])
		if not fits(game.line(), 20, 798.0) or rows(game.line()) > 2: lines_ok = false
		if not fits(game.goal_line(), 22, 762.0): lines_ok = false
		if not fits(game.status_line(), 20, 300.0): lines_ok = false
	for hint in game.hint_texts():
		if not fits(hint, 20, 798.0) or rows(hint) > 2: lines_ok = false
	check(lines_ok, "every spoken, goal, status and hint line fits its board without auto-wrapping")
	var verdict_ok = true
	for pick in placements():
		for amount in range(1, 14):
			var looked = pose(pick[0], pick[1], amount, "result", 1)
			if Rules.solved(looked): continue
			if not fits(Rules.result_line(looked), 20, 798.0) or rows(Rules.result_line(looked)) > 2: verdict_ok = false
	check(verdict_ok, "every honest verdict fits the spoken board in two lines")
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	# 无头模式没有渲染器，draw 信号不会发；直接给 NOTIFICATION_DRAW 才是真的走一遍 _draw。
	var drawn = 0
	for stage in Rules.STAGES:
		var looks = [legal_look(stage)]
		if stage == "puzzle":
			looks.append(pose(GOOD, FAR, 7, stage, 2))
			looks.append(pose([1, 0, 1], [0, 1, 0], 13, stage, 1))
		if stage == "weighing": looks.append(pose(GOOD, FAR, 8, stage, 2))
		if stage == "result": looks.append(pose(GOOD, FAR, 6, stage, 2))
		for look in looks:
			check(Rules.validate(look), "the repaint walk carries a legal save at " + stage)
			game.apply_committed(look, [])
			for at in [0.0, 0.5, 1.0]:
				game.paused = true; game.world.progress = at
				game.world.queue_redraw()
				game.world.notification(CanvasItem.NOTIFICATION_DRAW)
				drawn += 1
	check(is_instance_valid(game.world) and not game.modal, "every stage repaints without breaking the scale")
	check(drawn == 36, "秤的每一份现场都真的重画过 %d 帧" % drawn)
	game.paused = false
	game.apply_committed(pose(GOOD, FAR, 7, "puzzle", 2), [])
	check(game.world.braked() and game.world.beam_angle() == 0.0, "the beam is braked again while the table is open")
	game.apply_committed(pose(GOOD, FAR, 7, "weighing", 3), [])
	game.world.progress = 1.0
	check(game.world.beam_angle() == 0.0, "a level beam never tips, even mid-animation")
	game.apply_committed(pose(EMPTY_PAN, [1, 1, 1], 7, "weighing", 3), [])
	check(game.world.beam_angle() > 0.0, "the naive arrangement tips the far side down")
	game.apply_committed(pose(GOOD, FAR, 8, "weighing", 3), [])
	check(game.world.beam_angle() < 0.0, "overfilling tips the goods side down")
	game.apply_committed(pose(GOOD, FAR, 7, "result", 3), [])
	var booked = game.world.boards()[2]["text"]
	game.apply_committed(pose(GOOD, FAR, 7, "delivery", 3), [])
	game.world.progress = 0.9
	check(game.world.shown_oil() == 0 and game.world.delivery_plan(0.9).size() == 1,
		"the jar leaves the pan and flies to the shelf")
	# 收走盘上那一格油只是演出：木牌说的还得是玩家抬过秤的那份摆法，
	# 读数不能在半路改成「灯油 0」，两头也不许跟着抹平成 0 单位。
	check(game.world.boards()[2]["text"] == booked and "灯油 7" in booked,
		"the equation board keeps naming the 7 units that were weighed while the jar flies")
	var readouts = ""
	for note in game.world.notes(): readouts += note["text"] + "|"
	check("货盘 10 单位" in readouts and "对面 10 单位" in readouts,
		"both pan readouts still press 10 units after the oil is poured into the jar")
	game.apply_committed(pose(GOOD, FAR, 7, "puzzle", 3), [])
	check(game.world.delivery_plan(0.5).is_empty(), "nothing flies while the table is open")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state == on_disk and game.state.stage == "complete" and game.state.oil == 7 and game.state.hint == 3,
		"the sealed jar reloads from disk exactly as delivered")
	check(game.snapshot(on_disk) == {"goods": GOOD, "far": FAR, "oil": 7}, "the undo snapshot reads the pans back")
	var wiped_table = game.cleared_state()
	check(wiped_table.goods == EMPTY_PAN and wiped_table.far == EMPTY_PAN and wiped_table.oil == 0
		and wiped_table.weighs == on_disk.weighs and wiped_table.stage == "complete", "重摆 keeps a cleared scene's weigh count")
	Bridge.origin = "hub"
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"), "finishing from the chart returns to the chart")
	game.apply_committed(Rules.fresh(), [])
	game.advance(); game.advance(); game.advance(); game.skip_animation(); game.advance(); settle(game)
	game.do_draw(); settle(game); game.do_place(1, Rules.GOODS); settle(game)
	check(game.state.stage == "puzzle" and game.buttons.has("leave_hub"), "the table keeps its own way back to the chart")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK11 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

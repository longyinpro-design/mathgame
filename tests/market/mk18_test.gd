extends SceneTree
# MK18 万签守约兽「让每一盏灯都有回信」：无头规则、存档与真实场景检查。
# 运行：godot --headless --path . --script tests/market/mk18_test.gd
# 检查覆盖：三阶段的全部动作与推进、库存内 150 种摆法的唯一解与近 miss、两种回信各自的分配、
# 撤销快照在每个阶段边界往返、被篡改的存档、真实码头的热点几何与逐幕重画。
const Rules = preload("res://scripts/market/mk18_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Scene = preload("res://game/market_mk18.tscn")
const SAVE_DEFAULT = "user://profiles/market-mk18-1/save-v1.json"
# 候选整单：A1 · B3 · C4 = 14 提油 7 束芯 = 29 票。
const SOLUTION = [1, 3, 4]
const EXACT_OIL = [3, 2, 1]      # 恰好差 1 提油，芯一分不差
const SHORT_WICK = [2, 2, 3]     # 恰好差 1 束芯
const OVER_WICK = [4, 2, 0]      # 多出 1 束芯
const OVER_PAID = [4, 4, 5]      # 把库存全买光：超票也超货
const SWAPPED = [[5, 3], [4, 2], [2, 1]]  # 总数对、两街对调（分支甲）
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk18-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

func named(missing: Array, word: String) -> bool:
	for line in missing:
		if word in line: return true
	return false

func lines_of(missing: Array) -> String:
	return " / ".join(missing)

# 说明是不是中文：逐码点找 CJK 基本区，不接受只有数字与符号的空壳。
func chinese(text: String) -> bool:
	if text.is_empty(): return false
	for index in range(text.length()):
		var code = text.unicode_at(index)
		if code >= 0x4e00 and code <= 0x9fff: return true
	return false

# 台词板内框 798 宽、22 号字：汉字不会自动折行，越框就是画到旁边的货上。
func fits(text: String, size_px: int, width: float) -> bool:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UIStyle.text_size(size_px)).x)
	return widest <= width

# ---- 现场拼装：所有非法状态都从合法开局改一处，避免把检查写成第二套规则 ----
func at_stage(stage: String, branch: int = 0, beat: int = 0) -> Dictionary:
	var value = Rules.fresh(branch)
	value.stage = stage; value.beat = beat
	return value

func drafting(order: Array, branch: int = 0) -> Dictionary:
	var value = at_stage("puzzle", branch)
	value.order = order.duplicate(true)
	return value

func purchased(branch: int = 0) -> Dictionary:
	var value = at_stage("puzzle", branch)
	value.order = SOLUTION.duplicate(true); value.bought = SOLUTION.duplicate(true)
	return value

func placing(alloc: Array, preview: int, branch: int = 0) -> Dictionary:
	var value = purchased(branch)
	value.alloc = alloc.duplicate(true); value.preview = preview
	return value

func delivered(lamp: int, sealed: Array, branch: int = 0) -> Dictionary:
	var value = purchased(branch)
	value.alloc = Rules.slot_needs(branch); value.handed = Rules.slot_needs(branch)
	value.preview = 1; value.lamp = lamp; value.sealed = sealed.duplicate(true)
	return value

# 演出幕与结局幕的合法现场：账上必须已经走到那一格。
func cut(stage: String, branch: int = 0, beat: int = 0) -> Dictionary:
	var value = at_stage(stage, branch, beat)
	if stage in ["stocking", "clarify"]:
		value.order = SOLUTION.duplicate(true); value.bought = SOLUTION.duplicate(true)
	if stage == "delivering":
		value.order = SOLUTION.duplicate(true); value.bought = SOLUTION.duplicate(true)
		value.alloc = Rules.slot_needs(branch); value.handed = Rules.slot_needs(branch)
		value.preview = 1
	if stage in ["lighting", "voyage", "complete"]:
		value = delivered(1, [1, 1, 1], branch); value.stage = stage
	return value

func walk_in() -> Dictionary:
	var value = Rules.fresh(0)
	for _step in range(Rules.ARRIVAL_BEATS + 2): value = Rules.advance(value)
	return value

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK18 rule watchdog"); quit(1))
	# ---- 开局：常量、派生读数与「同一晚的账」不变 ----
	check(Rules.validate(Rules.fresh(0)), "fresh model valid")
	check(Rules.fresh(0).sample == "market-mk18-1", "fresh carries the mk18 sample id")
	check(Rules.fresh(0).stage == "arrival" and Rules.fresh(0).beat == 0, "fresh opens at the harbour mouth")
	check(Rules.fresh(0).hint == 0, "fresh opens without a used hint")
	check(Rules.fresh(0).order == [0, 0, 0] and Rules.fresh(0).bought == [0, 0, 0], "fresh order and booking are both empty")
	check(Rules.fresh(0).alloc == Rules.empty_alloc() and Rules.fresh(0).handed == Rules.empty_alloc(), "fresh table has nothing allocated")
	check(Rules.fresh(0).preview == 0 and Rules.fresh(0).lamp == 0 and Rules.fresh(0).sealed == [0, 0, 0], "no preview, no light, no receipt before the walk-in")
	check(Rules.NEEDS_A == [[3, 1], [4, 2], [5, 3], [2, 1]], "branch A keeps 3/1 · 4/2 · 5/3 and the lamp's 2/1")
	check(Rules.NEEDS_B == [[3, 1], [5, 1], [4, 4], [2, 1]], "branch B changes the last two streets to 5/1 · 4/4")
	check(Rules.PACKS == [[3, 1], [1, 2], [2, 0]] and Rules.PRICES == [5, 4, 3], "packs are A 3油1芯/5票, B 1油2芯/4票, C 2油/3票")
	check(Rules.STOCK == [4, 4, 5] and Rules.BUDGET == 29, "stock is A4 B4 C5 with a 29-ticket budget")
	check(Rules.TOTAL_OIL == 14 and Rules.TOTAL_WICK == 7 and Rules.RESERVED == [2, 1], "the shared order is 14 oil, 7 wick, 2/1 reserved for the lamp")
	check(Rules.total_of(0) == [14, 7] and Rules.total_of(1) == [14, 7], "both replies add up to the same grand total")
	check(Rules.pool() == [11, 6], "after the first street is handed there are 11 oil and 6 wick left to move")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "stocking", "clarify",
		"delivering", "lighting", "voyage", "complete"], "the stage list walks the three phases in order")
	check(Rules.ANIMATIONS == ["approach", "stocking", "delivering", "lighting", "voyage"], "only the five transitions animate")
	check(not Rules.ANIMATIONS.has("clarify"), "reading the letters is a stop, not an animation")
	check(Rules.phase_of(Rules.fresh(0)) == 1 and Rules.phase_of(purchased(0)) == 2, "the phase is read off the ledger, not stored")
	check(Rules.phase_of(delivered(0, [0, 0, 0], 0)) == 3, "the third phase opens once the goods are handed")
	var rolled = Rules.fresh()
	check(Rules.validate(rolled) and rolled.branch in [0, 1],
		"the host's no-arg fresh always fixes one of the two replies")
	check(Rules.fresh().branch != rolled.branch, "two new plays alternate between the two replies")
	# ---- 第一阶段：150 种摆法里只有一个解 ----
	var rows = Rules.enumerate()
	check(rows.size() == 150, "all A0..4 x B0..4 x C0..5 rows are enumerated")
	var exact = Rules.exact_rows()
	check(exact.size() == 1, "exactly one purchase satisfies the shared order inside the budget")
	check(exact.size() == 1 and exact[0].order == SOLUTION, "the unique solution is A1 · B3 · C4")
	check(exact.size() == 1 and exact[0].cost == 29, "that unique order spends exactly the 29 tickets")
	var goods_winners = 0
	var budget_only_breaks = 0
	var mismatches = 0
	for row in rows:
		if row.oil == Rules.TOTAL_OIL and row.wick == Rules.TOTAL_WICK:
			goods_winners += 1
			if row.order != SOLUTION: mismatches += 1
		if row.cost > Rules.BUDGET and row.oil == Rules.TOTAL_OIL and row.wick == Rules.TOTAL_WICK:
			budget_only_breaks += 1
		var probe = drafting(row.order)
		var missing = Rules.purchase_shortfalls(row.order)
		if row.order == SOLUTION:
			if not missing.is_empty() or not Rules.solved(probe): mismatches += 1
		elif missing.is_empty() or Rules.solved(probe): mismatches += 1
	check(mismatches == 0, "every enumerated row agrees with the submit gate")
	check(goods_winners == 1, "no second row reaches 14 oil and 7 wick at all, budget or not")
	check(budget_only_breaks == 0, "an order can never break only the budget: the goods decide the price")
	check(Rules.cost_of(SOLUTION) == 29 and Rules.oil_of(SOLUTION) == 14 and Rules.wick_of(SOLUTION) == 7, "A1 B3 C4 reads back 29 票 · 14 油 · 7 芯")
	check(Rules.shortfalls(drafting(EXACT_OIL)) == ["共同订单要 14 提油，订单上是 13 提，还差 1 提。"],
		"one jug short is named as one jug, in the player's own units")
	check(Rules.shortfalls(drafting(SHORT_WICK)) == ["共同订单要 7 束芯，订单上是 6 束，还差 1 束。"],
		"one bundle of wick short is named on its own")
	check(Rules.shortfalls(drafting(OVER_WICK)) == ["共同订单要 7 束芯，订单上是 8 束，多了 1 束。"],
		"too much wick is refused as surplus, not as a shortage")
	var paid = Rules.purchase_shortfalls(OVER_PAID)
	check(named(paid, "票") and named(paid, "提油"), "buying the whole shelf is told both the goods and the over-spend")
	check(named(paid, "超了 %d 票" % (Rules.cost_of(OVER_PAID) - Rules.BUDGET)), "the over-spend is stated as an exact number of tickets")
	check(Rules.purchase_shortfalls([0, 0, 0]) == ["采购台上三种封装都还在：先把这一晚要买的整包选出来。"],
		"an untouched counter asks for the order instead of blaming a promise")
	check(Rules.oil_of(OVER_PAID) == 26 and Rules.wick_of(OVER_PAID) == 12, "the whole shelf is 26 油 12 芯, far from the order")
	# ---- 第一阶段动作：一次选数量，不是八次点击购物 ----
	var table = drafting([0, 0, 0])
	var one_a = Rules.set_count(table, 0, 1)
	check(one_a.order == [1, 0, 0] and table.order == [0, 0, 0], "dialling pack A to 1 is a real action on the counter")
	check(Rules.set_count(one_a, 0, 1).is_empty(), "the same quantity cannot be booked twice")
	check(Rules.set_count(one_a, 0, 0).order == [0, 0, 0], "dialling back to zero puts the pack on the shelf")
	check(Rules.set_count(one_a, 0, 5).is_empty(), "five pack A is beyond the four in stock")
	check(Rules.set_count(one_a, 2, 6).is_empty(), "six pack C is beyond the five in stock")
	check(Rules.set_count(one_a, 0, -2).is_empty() and Rules.set_count(one_a, 7, 1).is_empty(),
		"negative counts and unknown pack kinds are refused")
	check(Rules.set_count(at_stage("arrival"), 0, 1).is_empty(), "nothing can be ordered before the player walks in")
	check(Rules.set_count(cut("stocking"), 0, 1).is_empty(), "the counter is closed while the goods are carried")
	check(Rules.set_count(purchased(0), 0, 2).is_empty(), "the second phase never buys another pack")
	check(Rules.set_count(delivered(0, [0, 0, 0], 0), 0, 2).is_empty(), "the third phase never buys another pack")
	check(Rules.advance(drafting(EXACT_OIL)).is_empty(), "a near-miss order cannot be submitted")
	var booked = Rules.advance(drafting(SOLUTION))
	check(booked.stage == "stocking" and booked.bought == SOLUTION, "submitting the whole order books it in one move")
	check(booked.order == SOLUTION, "the order sheet stays visible after booking")
	check(Rules.advance(booked).stage == "clarify", "the first street is handed over before the correction letter")
	# ---- 第二阶段：拆开分配，但不再购买 ----
	var desk = purchased(0)
	check(Rules.shortfalls(desk).size() == 3, "an untouched second phase still owes three places")
	var put_oil = Rules.put(desk, 0, Rules.OIL)
	check(put_oil.alloc[0] == [1, 0] and desk.alloc[0] == [0, 0], "one jug of oil goes onto 中街's tray")
	check(Rules.alloc_left(put_oil.alloc) == [10, 6], "the counter reads back one jug fewer")
	check(Rules.take_back(put_oil, 0, Rules.OIL).alloc == Rules.empty_alloc(), "the same jug can be taken back")
	check(Rules.take_back(desk, 0, Rules.OIL).is_empty(), "an empty tray cannot give anything back")
	check(Rules.put(at_stage("puzzle"), 0, Rules.OIL).is_empty(), "nothing can be allocated before the goods are bought")
	check(Rules.put(cut("clarify"), 0, Rules.OIL).is_empty(), "the allocation waits until the letter is read")
	check(Rules.put(delivered(0, [0, 0, 0], 0), 0, Rules.OIL).is_empty(), "the third phase no longer moves goods")
	check(Rules.put(desk, 9, Rules.OIL).is_empty() and Rules.put(desk, -1, Rules.OIL).is_empty(),
		"unknown allocation places are refused")
	check(Rules.put(desk, 0, 5).is_empty(), "only oil and wick are goods")
	# 无凭空多出的货：货台上的 11 油 6 芯摆完就一格也加不上去
	var filled = desk
	for _jug in range(Rules.pool()[Rules.OIL]): filled = Rules.put(filled, 0, Rules.OIL)
	for _bundle in range(Rules.pool()[Rules.WICK]): filled = Rules.put(filled, 1, Rules.WICK)
	check(Rules.alloc_left(filled.alloc) == [0, 0], "the whole counter can be laid out")
	check(Rules.put(filled, 0, Rules.OIL).is_empty() and Rules.put(filled, 1, Rules.WICK).is_empty(),
		"no free oil or wick: an empty counter refuses another unit")
	check(named(Rules.shortfalls(placing([[12, 3], [0, 0], [0, 0]], 0, 0)), "不是货栈给的"),
		"an invented jug is named as not coming from the warehouse")
	# 分支甲：维持原安排
	var solved_a = placing(Rules.slot_needs(0), 0, 0)
	check(Rules.solved(solved_a), "branch A's 4/2 · 5/3 · 2/1 split is accepted")
	check(named(Rules.shortfalls(placing(SWAPPED, 0, 0)), "总数") or Rules.shortfalls(placing(SWAPPED, 0, 0)).size() == 2,
		"swapping the two streets is refused even though the grand total matches")
	check(not Rules.solved(placing(SWAPPED, 0, 0)), "a matching grand total alone is not a delivery")
	# 分支乙：更正安排，旧的逐街分装不能沿用
	var solved_b = placing(Rules.slot_needs(1), 0, 1)
	check(Rules.solved(solved_b), "branch B's 5/1 · 4/4 · 2/1 split is accepted")
	check(not Rules.solved(placing(Rules.slot_needs(0), 0, 1)), "the old per-street split does not survive the correction letter")
	var wrong_b = Rules.shortfalls(placing(Rules.slot_needs(0), 0, 1))
	check(named(wrong_b, "更正回执"), "branch B names the corrected receipt when it refuses the old plan")
	check(not named(Rules.shortfalls(placing(Rules.slot_needs(1), 0, 0)), "更正回执"),
		"branch A is told with the original receipt instead")
	check(named(Rules.shortfalls(placing([[4, 2], [5, 3], [2, 0]], 0, 0)), "领航灯"),
		"a wick missing from the lamp's reservation is named as the lamp's own promise")
	# 整单预览：交货前可以撤回
	var previewed = Rules.make_preview(solved_a)
	check(previewed.preview == 1, "the whole order can be laid out for the three streets to see")
	check(Rules.make_preview(placing(SWAPPED, 0, 0)).is_empty(), "a wrong split never reaches the preview")
	check(Rules.cancel_preview(previewed).preview == 0, "the preview can be revoked before the goods move")
	check(Rules.take_back(previewed, 0, Rules.OIL).preview == 0, "taking a jug back revokes the preview it described")
	var moved = Rules.put(Rules.take_back(previewed, 0, Rules.OIL), 0, Rules.OIL)
	check(moved.preview == 0 and moved.alloc == Rules.slot_needs(0),
		"a jug put back does not resurrect the preview it left behind")
	check(Rules.cancel_preview(solved_a).is_empty(), "there is nothing to revoke before a preview exists")
	check(Rules.advance(desk).is_empty(), "an empty second phase cannot be delivered")
	var to_delivery = Rules.advance(previewed)
	check(to_delivery.stage == "delivering" and to_delivery.handed == Rules.slot_needs(0),
		"the previewed split is what actually gets handed over")
	check(Rules.advance(solved_a).stage == "puzzle" and Rules.advance(solved_a).preview == 1,
		"the first submit only raises the preview")
	# ---- 第三阶段：亲手装灯、投回执，三件缺一不可 ----
	var final = delivered(0, [0, 0, 0], 0)
	check(Rules.win_parts(final).bought and Rules.win_parts(final).streets, "the first two facts already hold before the lamp")
	check(not Rules.win_parts(final).lamp and not Rules.win_ok(final), "an unlit lantern is not a victory")
	var lit = Rules.load_lamp(final)
	check(lit.lamp == 1 and final.lamp == 0, "the reserved 2 油 1 芯 goes into the lantern by hand")
	check(Rules.load_lamp(lit).is_empty(), "the lantern cannot be filled twice")
	check(Rules.unload_lamp(lit).lamp == 0, "the load can be taken back out of the lamp")
	check(Rules.load_lamp(purchased(0)).is_empty(), "nothing can be loaded before the streets are served")
	check(Rules.load_lamp(cut("delivering")).is_empty(), "the lamp stays shut while the goods are still moving")
	var sealed_one = Rules.seal_receipt(lit, 0)
	check(sealed_one.sealed == [1, 0, 0], "桥头街's real receipt closes the empty slot on 万签's chest")
	check(Rules.seal_receipt(sealed_one, 0).is_empty(), "a sealed street cannot be sealed again")
	check(Rules.unseal_receipt(sealed_one, 0).sealed == [0, 0, 0], "the receipt can be taken back out of the slot")
	check(Rules.seal_receipt(sealed_one, 3).is_empty(), "there is no fourth street to seal")
	var half = Rules.seal_receipt(Rules.seal_receipt(lit, 0), 1)
	check(not Rules.win_ok(half) and Rules.shortfalls(half).size() == 1, "two receipts in the slot still leaves the promise open")
	check(named(Rules.shortfalls(half), "西坡街"), "the refusal names which street's receipt is missing")
	var won = Rules.seal_receipt(Rules.seal_receipt(Rules.seal_receipt(lit, 0), 1), 2)
	check(Rules.win_ok(won), "all three facts together are what wins the night")
	check(Rules.advance(won).stage == "lighting", "the closed slot lets the lantern rig unfold")
	var lit_only = delivered(1, [0, 0, 0], 0)
	check(not Rules.win_ok(lit_only) and Rules.shortfalls(lit_only).size() == 3, "a lit lantern with no receipts is not enough")
	check(not Rules.win_parts({"sample": "market-mk18-1", "stage": "puzzle", "beat": 0, "hint": 0,
		"branch": 0, "order": SOLUTION.duplicate(true), "bought": SOLUTION.duplicate(true),
		"alloc": Rules.empty_alloc(), "handed": Rules.empty_alloc(), "preview": 0, "lamp": 1,
		"sealed": [1, 1, 1]}).streets, "three sealed streets without the delivery is not enough")
	# ---- 每一幕的推进都走一遍（两种回信各走一次） ----
	for branch in range(2):
		var walk = Rules.fresh(branch)
		check(walk.branch == branch, "an explicit branch is fixed at creation for reply %d" % branch)
		for _beat in range(Rules.ARRIVAL_BEATS - 1): walk = Rules.advance(walk)
		check(walk.stage == "arrival" and walk.beat == Rules.ARRIVAL_BEATS - 1, "the opening dialogue runs out at branch %d" % branch)
		walk = Rules.advance(walk)
		check(walk.stage == "approach" and Rules.advance(walk).stage == "ready", "the walk-in leads to the ready beat at branch %d" % branch)
		walk = Rules.advance(Rules.advance(walk))
		check(walk.stage == "puzzle" and walk.order == [0, 0, 0], "the counter opens untouched at branch %d" % branch)
		for kind in range(Rules.KINDS): walk = Rules.set_count(walk, kind, SOLUTION[kind])
		walk = Rules.advance(walk)
		check(walk.stage == "stocking" and walk.bought == SOLUTION, "the booked order carries to the first street at branch %d" % branch)
		walk = Rules.advance(walk)
		check(walk.stage == "clarify", "the correction letter arrives only after 桥头街 is served (branch %d)" % branch)
		for _beat in range(Rules.CLARIFY_BEATS - 1): walk = Rules.advance(walk)
		check(walk.stage == "clarify" and walk.beat == Rules.CLARIFY_BEATS - 1, "the letters are read one beat at a time (branch %d)" % branch)
		walk = Rules.advance(walk)
		check(walk.stage == "puzzle" and Rules.phase_of(walk) == 2, "the second phase begins after the letter (branch %d)" % branch)
		check(walk.branch == branch, "reading the letters never re-rolls the branch (branch %d)" % branch)
		for row in range(Rules.SLOTS):
			for kind in range(2):
				var want = Rules.slot_needs(branch)[row][kind]
				for _unit in range(want): walk = Rules.put(walk, row, kind)
		check(walk.alloc == Rules.slot_needs(branch), "the whole split can be laid out unit by unit (branch %d)" % branch)
		walk = Rules.advance(walk)
		check(walk.preview == 1 and walk.stage == "puzzle", "the submit first shows the whole order (branch %d)" % branch)
		walk = Rules.advance(walk)
		check(walk.stage == "delivering" and walk.handed == Rules.slot_needs(branch), "the previewed goods are what move (branch %d)" % branch)
		walk = Rules.advance(walk)
		check(walk.stage == "puzzle" and Rules.phase_of(walk) == 3, "the third phase begins after the delivery (branch %d)" % branch)
		check(walk.hint == 0, "each phase starts with its own three hints (branch %d)" % branch)
		walk = Rules.load_lamp(walk)
		for street in range(3): walk = Rules.seal_receipt(walk, street)
		check(Rules.advance(walk).stage == "lighting", "the lantern rig unfolds at branch %d" % branch)
		check(Rules.advance(cut("lighting", branch)).stage == "voyage", "the rig becomes a ship at branch %d" % branch)
		check(Rules.advance(cut("voyage", branch)).stage == "complete", "the ship sails out at branch %d" % branch)
		check(Rules.advance(cut("complete", branch)).is_empty(), "complete invents no next stage at branch %d" % branch)
		check(Rules.validate(cut("complete", branch)), "both replies end on a legal save (branch %d)" % branch)
	check(Rules.advance(at_stage("elsewhere")).is_empty(), "an unknown stage advances nowhere")
	# ---- 撤销快照：每个阶段边界都能原样回来 ----
	var snap_a = {"phase": 1, "order": [0, 0, 0], "alloc": Rules.empty_alloc(), "preview": 0,
		"lamp": 0, "sealed": [0, 0, 0]}
	check(Rules.restore(drafting(SOLUTION), snap_a).order == [0, 0, 0], "undo clears the draft order")
	check(Rules.restore(previewed, {"phase": 2, "order": SOLUTION.duplicate(true),
		"alloc": Rules.slot_needs(0), "preview": 0, "lamp": 0, "sealed": [0, 0, 0]}).preview == 0,
		"undo drops the whole-order preview")
	check(Rules.restore(placing(SWAPPED, 0, 0), {"phase": 2, "order": SOLUTION.duplicate(true),
		"alloc": Rules.slot_needs(0), "preview": 0, "lamp": 0, "sealed": [0, 0, 0]}).alloc == Rules.slot_needs(0),
		"undo puts the jugs back where they were")
	check(Rules.restore(won, {"phase": 3, "order": SOLUTION.duplicate(true),
		"alloc": Rules.slot_needs(0), "preview": 1, "lamp": 0, "sealed": [1, 1, 0]}).lamp == 0,
		"undo takes the oil back out of the lantern")
	check(Rules.restore(won, {"phase": 3, "order": SOLUTION.duplicate(true),
		"alloc": Rules.slot_needs(0), "preview": 1, "lamp": 1, "sealed": [0, 0, 0]}).sealed == [0, 0, 0],
		"undo lifts the receipts out of the chest slot")
	check(Rules.restore(won, snap_a).is_empty(), "a snapshot from another phase is refused")
	check(Rules.restore(previewed, {"phase": 2, "order": [0, 0, 0], "alloc": Rules.empty_alloc(),
		"preview": 0, "lamp": 0, "sealed": [0, 0, 0]}).is_empty(), "undo cannot rewrite what was already bought")
	check(Rules.restore(previewed, {"phase": 2, "order": SOLUTION.duplicate(true),
		"alloc": Rules.empty_alloc(), "preview": 0, "lamp": 0, "sealed": [0, 0, 0], "branch": 1}).is_empty(),
		"a snapshot carrying a branch is corruption, not an undo")
	check(Rules.restore(previewed, {"phase": 2, "order": SOLUTION.duplicate(true),
		"alloc": Rules.empty_alloc(), "preview": 0, "lamp": 0}).is_empty(), "a snapshot missing a field is refused")
	check(Rules.restore(previewed, {"phase": 2, "order": SOLUTION.duplicate(true),
		"alloc": [[9, 5], [4, 4], [2, 1]], "preview": 0, "lamp": 0, "sealed": [0, 0, 0]}).is_empty(),
		"undo refuses an allocation bigger than the goods")
	check(Rules.restore(cut("stocking"), snap_a).is_empty(), "undo only works at the counter")
	# ---- 被篡改的存档：一条也不能过 ----
	var forged: Dictionary
	for bad in [null, {}, [], "x", 5.0, [0, 0], Rules.fresh(0).duplicate(true).keys()]:
		check(not Rules.validate(bad), "reject record " + str(bad))
	forged = Rules.fresh(0); forged.sample = "market-mk17-1"
	check(not Rules.validate(forged), "another level's save is rejected")
	forged = Rules.fresh(0); forged.stage = "shopping"
	check(not Rules.validate(forged), "unknown stage rejected")
	forged = Rules.fresh(0); forged.beat = 9
	check(not Rules.validate(forged), "a dialogue beat past the shipped lines is corruption")
	forged = purchased(0); forged.beat = 1
	check(not Rules.validate(forged), "the counter cannot claim an unfinished line")
	forged = cut("clarify", 0, 1); forged.beat = 3
	check(not Rules.validate(forged), "the letters cannot be read a fourth time")
	forged = Rules.fresh(0); forged.hint = 4
	check(not Rules.validate(forged), "hint level is capped by the shipped hints")
	forged = Rules.fresh(0); forged.hint = -1
	check(not Rules.validate(forged), "a negative hint count is corruption")
	forged = Rules.fresh(0); forged.branch = 2
	check(not Rules.validate(forged), "there is no third reply to a letter")
	forged = Rules.fresh(0); forged.branch = -1
	check(not Rules.validate(forged), "an unfixed branch is not a save")
	forged = Rules.fresh(0); forged.branch = "0"
	check(not Rules.validate(forged), "a written branch is not a fixed branch")
	forged = Rules.fresh(0); forged.order = [5, 0, 0]
	check(not Rules.validate(forged), "five pack A is beyond the shelf")
	forged = Rules.fresh(0); forged.order = [1, 1.5, 1]
	check(not Rules.validate(forged), "a fractional pack is rejected")
	forged = Rules.fresh(0); forged.order = [1, 1]
	check(not Rules.validate(forged), "an order sheet with two kinds is corruption")
	forged = Rules.fresh(0); forged.order = ["1", 0, 0]
	check(not Rules.validate(forged), "a written count is not an ordered count")
	forged = purchased(0); forged.bought = [2, 2, 2]
	check(not Rules.validate(forged), "the second phase cannot claim a purchase that never worked")
	forged = placing(Rules.slot_needs(0), 0, 0); forged.bought = [0, 0, 0]
	check(not Rules.validate(forged), "goods cannot be laid out while nothing was bought")
	forged = purchased(0); forged.order = [2, 2, 2]
	check(not Rules.validate(forged), "the order sheet cannot drift from what was booked")
	forged = purchased(0); forged.alloc = [[9, 5], [4, 4], [2, 1]]
	check(not Rules.validate(forged), "an allocation bigger than the bought goods is rejected")
	forged = purchased(0); forged.alloc = [[11, 6], [0, 0], [0, 1]]
	check(not Rules.validate(forged), "a single wick above the counter is still invented goods")
	forged = purchased(0); forged.alloc = [[-1, 0], [0, 0], [0, 0]]
	check(not Rules.validate(forged), "negative goods are corruption")
	forged = purchased(0); forged.alloc = [[0, 0], [0, 0]]
	check(not Rules.validate(forged), "the lamp's share cannot be erased from the table")
	forged = purchased(0); forged.lamp = 1
	check(not Rules.validate(forged), "the lantern cannot be lit before the streets are served")
	forged = purchased(0); forged.sealed = [1, 1, 1]
	check(not Rules.validate(forged), "receipts cannot be sealed before the delivery")
	forged = purchased(0); forged.preview = 1
	check(not Rules.validate(forged), "a preview of an empty table is corruption")
	forged = placing(SWAPPED, 1, 0)
	check(not Rules.validate(forged), "a preview must describe a split that actually works")
	forged = delivered(0, [0, 0, 0], 0); forged.branch = 1
	check(not Rules.validate(forged), "the branch cannot be flipped under a delivered order")
	forged = cut("delivering", 1); forged.handed = Rules.slot_needs(0)
	check(not Rules.validate(forged), "a delivery of the other reply's split is rejected")
	forged = cut("delivering", 0); forged.handed = [[4, 2], [5, 3], [3, 1]]
	check(not Rules.validate(forged), "the lamp's reserved 2/1 cannot be quietly enlarged")
	forged = cut("delivering", 0); forged.preview = 0
	check(not Rules.validate(forged), "goods moved without a previewed order is corruption")
	forged = cut("complete", 0); forged.lamp = 0
	check(not Rules.validate(forged), "the ending cannot be reached with a dark lantern")
	forged = cut("complete", 0); forged.sealed = [1, 1, 0]
	check(not Rules.validate(forged), "the ending cannot be reached with an open chest slot")
	forged = cut("lighting", 0); forged.bought = [2, 2, 2]
	check(not Rules.validate(forged), "the finale cannot hide a purchase that never worked")
	forged = delivered(1, [1, 1, 1], 0); forged.erase("sealed")
	check(not Rules.validate(forged), "a missing field is corruption, not a default")
	forged = delivered(1, [1, 1, 1], 0); forged.erase("branch")
	check(not Rules.validate(forged), "a save without the fixed reply is rejected")
	forged = delivered(1, [1, 1, 1], 0); forged.lamp = 2
	check(not Rules.validate(forged), "the lantern is either lit or it is not")
	forged = delivered(1, [1, 1, 1], 0); forged.sealed = [1, 1, 2]
	check(not Rules.validate(forged), "a receipt cannot be half-sealed")
	check(Rules.validate(walk_in()), "the walk-in ends on a legal counter")
	check(Rules.validate(purchased(1)), "both replies open the second phase legally")
	check(Rules.validate(delivered(1, [1, 1, 1], 1)), "branch B's own finale reloads")
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(cut("complete", 1))))
	check(round_trip == cut("complete", 1) and Rules.validate(round_trip), "the finished record survives a JSON round trip")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh(0))))),
		"the opening record survives a JSON round trip")
	var half_done = placing(Rules.slot_needs(1), 1, 1)
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(half_done)))),
		"a half-finished second phase survives a JSON round trip")
	# ---- 台面文字：只复述玩家做过的事，不替玩家算账 ----
	var captions = {}
	for row in rows:
		captions[Rules.order_caption(row.order)] = true
		var probe = drafting(row.order)
		if row.order != SOLUTION and Rules.total_caption() in Rules.order_caption(row.order): mismatches += 1
	check(mismatches == 0, "no draft order ever prints the target totals as its own")
	check(captions.size() == rows.size() or captions.size() > 100, "the order sheet reads differently for different orders")
	check(Rules.order_caption(SOLUTION) == "订单 14 提油 7 束芯 · 29 票", "the winning order reads back exactly what it is")
	check(Rules.pack_caption(2) == "C · 2油+0芯 · 3票", "pack C says plainly that it carries no wick")
	check(Rules.total_caption() == "合计 14 提油 7 束芯 · 没有隐藏收费", "the shared order publishes the total and the no-fee promise")
	check(Rules.need_caption(1, 2) == "西坡街 4油4芯", "the corrected sheet is quoted street by street")
	check(Rules.line_caption(Rules.NEEDS_B, 1) == "中街 5/1", "both replies are readable from the letter board")
	check(not Rules.delivery_lines(cut("complete", 0))[2].contains("更正回执"), "branch A's receipt is restated as the original")
	check("更正回执" in Rules.delivery_lines(cut("complete", 1))[2], "branch B's receipt is restated as the correction")
	check(Rules.delivery_lines(cut("complete", 1))[1] == "中街 5 提油 1 束芯 · 按更正回执交货",
		"the ending caption quotes what the player actually handed to 中街")
	check(Rules.delivery_lines(delivered(0, [0, 0, 0], 0))[3].contains("还空着"), "an unlit lantern is admitted in the record")
	check(Rules.purchase_line(SOLUTION) == "A×1 · B×3 · C×4", "the booked purchase is restated pack by pack")
	check(Rules.branch_word(1) == "乙印 · 更正安排", "each reply carries its own confirmation seal")
	# ---- 场景与文案（离树探针，用完即释） ----
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == SAVE_DEFAULT, "the level defaults to the market-mk18-1 profile")
	check(Catalog.save_path("MK18") == probe.save_path, "the catalogue points at the same profile")
	probe.free()
	probe = Scene.instantiate(); probe.save_path = path; probe.configure()
	check(probe.save_path == path, "configure never overwrites an injected test path")
	check(probe.scene_id == "dock" and probe.level_id == "MK18", "the level declares its kit scene and id")
	check(Catalog.title("MK18").begins_with(probe.title), "the sign carries the catalogue's level name")
	check(("千灯集市  /  " + probe.title).length() <= 20, "the sign title stays inside the board")
	check(probe.rules == Rules and probe.world_script != null, "the host is wired to the mk18 rules and world")
	for stage in Rules.ANIMATIONS: check(probe.durations.has(stage), "the %s animation has its own duration" % stage)
	check(probe.zoom_stages == ["puzzle"], "only the counter pulls the camera in")
	for branch in range(2):
		for stage in Rules.STAGES:
			if stage == "puzzle": probe.state = purchased(branch)
			elif stage in ["arrival", "approach", "ready"]: probe.state = at_stage(stage, branch)
			else: probe.state = cut(stage, branch)
			var spoken = probe.line()
			check(not spoken.is_empty() and spoken.count("\n") <= 1, "stage %s branch %d speaks in two lines at most" % [probe.state.stage, branch])
			check(fits(spoken, 20, 798.0), "stage %s branch %d stays inside the dialogue board" % [probe.state.stage, branch])
	probe.state = at_stage("arrival", 0)
	for beat in range(Rules.ARRIVAL_BEATS):
		probe.state.beat = beat
		check(probe.line().count("\n") <= 1, "opening line %d stays inside the two-line board" % (beat + 1))
	probe.state = cut("clarify", 1, 2)
	check("5 提油 1 束芯" in probe.line(), "the letter beat reads out the branch that was fixed")
	for branch in range(2):
		probe.state = purchased(branch)
		check("\n" not in probe.goal_line() and "\n" not in probe.status_line(), "phase 2 readouts fit one line (branch %d)" % branch)
		check(fits(probe.goal_line(), 22, 762.0), "phase 2's goal fits the goal board (branch %d)" % branch)
		check(fits(probe.status_line(), 20, 300.0), "phase 2's readout fits the counter board (branch %d)" % branch)
		check("还剩" in probe.status_line(), "the counter shows what is still on the table")
		probe.state = placing(Rules.slot_needs(branch), 1, branch)
		check("预览" in probe.status_line() and "确认" in probe.submit_label(), "a live preview asks for confirmation, not another submit")
		probe.state = drafting(SOLUTION)
		check("29" in probe.status_line(), "the draft order's price is always on the board")
		check(fits(probe.goal_line(), 22, 762.0) and fits(probe.status_line(), 20, 300.0),
			"phase 1's two readouts hold their own boards")
		probe.state = delivered(0, [0, 0, 0], branch)
		check("领航灯" in probe.goal_line() and probe.submit_label() == "送灯出海", "phase 3 hands the lantern over")
		check(fits(probe.goal_line(), 22, 762.0) and fits(probe.status_line(), 20, 300.0),
			"phase 3's two readouts hold their own boards")
		for tier in range(3):
			probe.state.hint = tier
			var texts = probe.hint_texts()
			check(texts.size() == Rules.HINT_TIERS, "three hints ship for branch %d and no more" % branch)
			for spoken in texts:
				check(not spoken.is_empty() and spoken.count("\n") <= 1,
					"hint %s stays inside two lines" % spoken.left(4))
				# 汉字不会自动折行：台词板内框只有 798 宽，超出去就画到旁边的货上。
				check(fits(spoken, 20, 798.0), "hint %s holds the dialogue board" % spoken.left(4))
		# 另两个阶段的提示各自也有三级：同一套板子，一样不能越框。
		for other in [drafting(SOLUTION), purchased(branch)]:
			probe.state = other
			for spoken in probe.hint_texts():
				check(fits(spoken, 20, 798.0), "phase %d hint %s holds the dialogue board" % [
					Rules.phase_of(other), spoken.left(4)])
		probe.state = delivered(0, [0, 0, 0], branch)
	probe.state = drafting([0, 0, 0])
	check(probe.submit_label() == "提交共同订单", "the first phase submits one whole order")
	for order in [[0, 0, 0], [3, 2, 1], [4, 2, 0], [1, 3, 4]]:
		probe.state = drafting(order)
		var tiers = probe.hint_texts()
		check(tiers.size() == Rules.HINT_TIERS, "the counter ships three hints for every draft")
		var last = tiers[2]
		check(not last.is_empty() and last.count("\n") <= 1, "the concrete hint stays inside the sign board")
		check(not ("1 包" in last and "3 包" in last and "4 包" in last),
			"the third hint names the next step, never the whole order")
	for stage in Rules.STAGES:
		probe.state = cut(stage, 0)
		check(not probe.line().contains("A1") and not probe.line().contains("点成 3 包"),
			"the scene never hands out the purchase answer at %s" % stage)
	for stage in ["arrival", "ready", "clarify", "complete"]:
		probe.state = at_stage(stage, 0, 0)
		check(probe.stage_labels().has(stage), "stage %s names its own next step" % stage)
	probe.state = cut("clarify", 0, 1)
	check("再读" in probe.stage_labels()["clarify"], "the letter board offers the next envelope")
	probe.free()
	# ---- 真实场景：热点、命中区、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "a fresh scene opens on the dialogue")
	check(not game.buttons.has("deliver"), "the submit button waits for the counter")
	check(game.world.scene_id == "dock" and game.world.stations.has("boss_foot"), "the dock is drawn from the manifest stations")
	for beat in range(Rules.ARRIVAL_BEATS): game.advance()
	check(game.state.stage == "approach", "the four opening lines walk the player onto the dock")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the walk-in can be paused or skipped")
	game.skip_animation(); game.advance()
	check(game.state.stage == "puzzle" and game.phase() == 1, "the counter opens after the walk-in")
	var expected = []
	for kind in range(Rules.KINDS):
		for index in range(Rules.STOCK[kind]): expected.append("pack_%d_%d" % [kind, index])
	audit_hotspots(game, expected, "phase 1")
	game.choose_pack(0, 2)
	check(game.state.order == [3, 0, 0], "clicking the third pack of a kind books three at once, not one")
	game.choose_pack(0, 2)
	check(game.state.order == [2, 0, 0], "clicking the front of the booked run dials one pack back")
	game.choose_pack(0, 2)
	check(game.state.order == [3, 0, 0], "the same slot books it again: the counter is a dial, not eight clicks")
	game.advance()
	check(game.state.stage == "puzzle" and game.state.bought == [0, 0, 0], "a wrong order is refused before anything is spent")
	check("共同订单要 14 提油" in game.message, "the refusal names the shared order in the player's own units")
	game.choose_pack(0, 1)
	check(game.state.order == [1, 0, 0], "dialling one kind down is a single move")
	game.choose_pack(1, 2); game.choose_pack(2, 3)
	check(game.state.order == SOLUTION, "three clicks on the shelf dial the whole order in")
	game.choose_pack(2, 4)
	check(game.state.order[2] == 5, "the last pack in stock can still be booked")
	game.choose_pack(2, 4)
	check(game.state.order == SOLUTION, "dialling back from the top of the stock lands on the order that fits")
	game.advance()
	check(game.state.stage == "stocking" and game.state.bought == SOLUTION, "the whole order is booked in one submit")
	check(game.history.is_empty(), "crossing into the next phase starts a fresh undo stack")
	game.skip_animation()
	check(game.state.stage == "clarify", "the correction letter arrives after the first street")
	for beat in range(Rules.CLARIFY_BEATS - 1): game.advance()
	game.advance()
	check(game.state.stage == "puzzle" and game.phase() == 2, "the second phase begins once the letter is read")
	var alloc_ids = []
	for slot in range(Rules.SLOTS):
		for kind in range(2):
			alloc_ids.append("put_%d_%d" % [slot, kind]); alloc_ids.append("back_%d_%d" % [slot, kind])
	audit_hotspots(game, alloc_ids, "phase 2")
	game.do_put(0, Rules.OIL)
	check(game.state.alloc[0] == [1, 0] and game.history.size() == 1, "a jug laid on a tray is saved and recorded")
	game.undo()
	check(game.state.alloc[0] == [0, 0], "undo takes the jug back to the counter")
	for slot in range(Rules.SLOTS):
		for kind in range(2):
			for _unit in range(Rules.slot_needs(0)[slot][kind]): game.do_put(slot, kind)
	check(game.state.alloc == Rules.slot_needs(0), "the whole split can be laid out by clicking")
	game.do_put(0, Rules.OIL)
	check(game.state.alloc[0] == Rules.slot_needs(0)[0], "the counter cannot give a nineteenth unit")
	game.advance()
	check(game.state.preview == 1, "the first submit lays the whole order out for the streets")
	audit_hotspots(game, alloc_ids + ["revoke"], "phase 2 preview")
	game.do_revoke()
	check(game.state.preview == 0, "the preview is revoked before any goods move")
	game.advance()
	game.advance()
	check(game.state.stage == "delivering" and game.state.handed == Rules.slot_needs(0), "the previewed split is what gets handed over")
	game.skip_animation()
	check(game.state.stage == "puzzle" and game.phase() == 3, "the third phase begins after the delivery")
	audit_hotspots(game, ["lamp", "seal_0", "seal_1", "seal_2"], "phase 3")
	game.do_lamp()
	check(game.state.lamp == 1, "the reserved goods go into the lantern by hand")
	game.advance()
	check(game.state.stage == "puzzle" and "空信槽" in game.message, "an empty chest slot blocks the finale")
	for street in range(3): game.do_seal(street)
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == 3 and "灯船" in game.message, "the third hint gives the whole next step and stops there")
	game.advance()
	check(game.state.stage == "lighting", "all three facts together release the finale")
	game.skip_animation(); game.skip_animation()
	check(game.state.stage == "complete" and Rules.validate(game.state), "the ship sails out on a legal save")
	check(game.buttons.has("open_hub"), "a standalone sample still finds a way back to the chart")
	check(game.ui.get_child_count() > 2, "the ending panel is drawn from the player's own record")
	var receipt = ""
	for child in game.ui.get_children():
		if child is Label: receipt += child.text
	check("中街 4 提油 2 束芯" in receipt and "甲印" in receipt, "the ending panel quotes the actual branch and amounts")
	game.paused = true; game.queue_free(); await process_frame
	# ---- 读档：分支永远沿用存档里的那一个 ----
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "complete" and game.state.branch == 0, "the finished scene reloads with its own reply")
	game.queue_free(); await process_frame
	var mid = placing(Rules.slot_needs(1), 0, 1)
	var writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(mid)); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.branch == 1 and game.state.alloc == Rules.slot_needs(1), "an unfinished correction resumes as it was")
	var first_branch = game.state.branch
	game.advance()
	check(game.state.branch == first_branch and game.state.preview == 1, "submitting the preview never re-rolls the reply")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.branch == first_branch and game.state.preview == 1, "re-reading the save keeps the same reply")
	check(Rules.validate(game.state), "the resumed stage is still a legal save")
	game.queue_free(); await process_frame
	# ---- 存档事务：失败不动现场 ----
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(purchased(0))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.alloc == Rules.empty_alloc(), "the counter resumes untouched")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.do_put(0, Rules.OIL)
	check(game.modal and game.state.alloc[0] == [0, 0] and FileAccess.get_file_as_bytes(path) == bytes,
		"a failed allocation save keeps the counter as it was")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.alloc[0] == [1, 0] and not game.modal, "retry publishes the allocation as one move")
	for slot in range(Rules.SLOTS):
		for kind in range(2):
			var owe = Rules.slot_needs(0)[slot][kind] - game.state.alloc[slot][kind]
			for _unit in range(owe): game.do_put(slot, kind)
	check(game.state.alloc == Rules.slot_needs(0), "the rest of the split lands by clicking too")
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle", "a failed preview save cannot raise the preview")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.preview == 1, "retry raises the preview")
	game.confirm_reset()
	check(game.modal, "重摆 asks before putting the whole table back")
	game.close_modal(); game.hint()
	check(game.state.hint == 1 and not game.modal, "a cancelled 重摆 leaves the allocation and costs nothing")
	game.confirm_reset(); game.do_reset()
	check(game.state.alloc == Rules.empty_alloc() and game.state.preview == 0, "重摆 puts every good back on the counter")
	game.queue_free(); await process_frame
	# ---- 坏档保护 ----
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	game.queue_free(); await process_frame
	# ---- 目录一致性 ----
	check(Catalog.scene("MK18") == "res://game/market_mk18.tscn", "the catalogue points at the shipped scene")
	check(ResourceLoader.exists(Catalog.scene("MK18")), "the chart can now light mk18 instead of 尚未制作")
	check(Catalog.LEVELS["MK18"].kit == "dock", "mk18 stays on the grand dock kit scene")
	check(Catalog.opens_after("MK18") == "MK17" and Catalog.act("MK18") == 6, "mk18 is the chapter's last stand")
	check(Catalog.built("MK18") and Catalog.available("MK18", ["MK17"]), "mk18 opens once mk17 is lit")
	DirAccess.remove_absolute(path)
	print("MARKET MK18 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

# 热点必须全部登记、至少 48 逻辑像素、留在画面内并带着中文说明。
func audit_hotspots(game: Node, ids: Array, label: String) -> bool:
	var present = true
	var sized = true
	var framed = true
	var told = true
	for id in ids:
		if not game.buttons.has(id): present = false; continue
		var button: Button = game.buttons[id]
		if button.size.x < 48 or button.size.y < 48: sized = false
		var rect = button.get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
		if not chinese(button.tooltip_text) or button.tooltip_text.length() < 8: told = false
	check(present, "all %d %s hotspots are registered" % [ids.size(), label])
	check(sized, "every %s hotspot is at least 48 logical pixels wide and tall" % label)
	check(framed, "every %s hotspot stays inside the frame and clear of the bottom bar" % label)
	check(told, "every %s hotspot explains itself in Chinese" % label)
	return present

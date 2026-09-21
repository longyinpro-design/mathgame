extends SceneTree
# MK14 三枚砝码的小摊：无头规则、存档与真实场景检查。
# 运行：godot --headless --path . --script tests/market/mk14_test.gd
const Rules = preload("res://scripts/market/mk14_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk14.tscn")
# 只在检查里对照第五幕那具铜秤的组装约定：本关运行时不依赖 MK11 的任何文件。
const MK11World = preload("res://scripts/market/mk11_world.gd")
const SAVE_DEFAULT = "user://profiles/market-mk14-1/save-v1.json"
# 两单的参考摆法（下标 0/1/2 对应 1/3/9 三枚砝码）：
# 5 = 货 + 3 + 1 对 9；8 = 货 + 1 对 9。同一具秤、同样三枚，只挪不换。
const FIVE_GOODS = [1, 1, 0]
const FIVE_FAR = [0, 0, 1]
const EIGHT_GOODS = [1, 0, 0]
const EIGHT_FAR = [0, 0, 1]
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk14-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 手工拼一份现场：非 arrival 幕必须已经听完三句台词，与 advance 的走位一致。
# "complete" 一栏永远是那两笔记完账的真摆法，因为完成态的定义就是「两单都记下了」。
func pose(goods: Array, far: Array, stage: String = "puzzle", order: int = 0) -> Dictionary:
	var value = Rules.fresh()
	value.stage = stage; value.beat = 2
	value.goods = goods.duplicate(); value.far = far.duplicate()
	value.order = order; value.delivered = order
	if stage not in ["arrival", "approach", "ready"]: value.weighs = 1
	if order > 0:
		value.built_goods[0] = FIVE_GOODS.duplicate(); value.built_far[0] = FIVE_FAR.duplicate()
	if stage == "complete":
		value.built_goods[0] = FIVE_GOODS.duplicate(); value.built_far[0] = FIVE_FAR.duplicate()
		value.built_goods[1] = EIGHT_GOODS.duplicate(); value.built_far[1] = EIGHT_FAR.duplicate()
		value.order = 1; value.delivered = 2
		value.goods = EIGHT_GOODS.duplicate(); value.far = EIGHT_FAR.duplicate()
	return value

func named(lines: Array, word: String) -> bool:
	for line in lines:
		if word in line: return true
	return false

func settle(game: Node) -> void:
	game.transient = 0.0
	game.refresh()

# 「· 键盘 X」这半句是热点对自己说的话：按那个键要做出跟点这下一模一样的动作才算数，
# 否则玩家照着提示按键，等来的却是把砝码请到另一头。逐条按键与点击各演一遍，比状态。
func advertised_audit(game: Node, ids: Array) -> Array:
	var advertised = {"1": KEY_1, "2": KEY_2, "3": KEY_3}
	var told = 0
	var lied = 0
	for id in ids:
		var before = game.state.duplicate(true); var book = game.history.duplicate(true)
		settle(game)
		var tip: String = game.buttons[id].tooltip_text
		var at = tip.find("键盘 ")
		if at < 0: continue
		told += 1
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
	return [told, lied]

# 用真动作把现场摆成指定那一式：摆不出来就说明这一步玩家根本点不到。
func walk_to(goods: Array, far: Array) -> Dictionary:
	var value = pose(Rules.empty_pan(), Rules.empty_pan())
	for index in range(Rules.COUNT):
		var side: int = Rules.OFF
		if goods[index] == 1: side = Rules.GOODS
		elif far[index] == 1: side = Rules.FAR
		if side == Rules.OFF: continue
		value = Rules.place_weight(value, index, side)
	return value

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("MK14 rule watchdog"); quit(1))
	# ---- 开局：状态是常量，不是巧合 ----
	check(Rules.validate(Rules.fresh()), "fresh model valid")
	check(Rules.fresh().sample == "market-mk14-1", "fresh carries the mk14 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens at the street mouth")
	check(Rules.fresh().order == 0 and Rules.fresh().delivered == 0, "fresh opens before the first order")
	check(Rules.fresh().goods == [0, 0, 0] and Rules.fresh().far == [0, 0, 0], "fresh leaves all three weights on the rack")
	check(Rules.fresh().built_goods == [[0, 0, 0], [0, 0, 0]], "fresh books no arrangement yet")
	check(Rules.fresh().weighs == 0 and Rules.fresh().hint == 0, "fresh has lifted no beam and used no hint")
	check(Rules.WEIGHTS == [1, 3, 9] and Rules.WEIGHT_TOTAL == 13, "the rack lends 1, 3 and 9 only")
	check(Rules.ORDERS == [5, 8], "the two new orders are 5 then 8 units")
	check(Rules.COUNT == 3 and Rules.WEIGHT_KITS.size() == 3, "three physical weights, three kit parts, no fourth")
	check(Rules.CARTS == ["cart_left", "cart_middle", "cart_right"], "the two orders and the hand-off use the kit's three carts")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "weighing", "result", "delivery", "complete"],
		"stage list matches the shipped beats")
	check(Rules.ANIMATIONS == ["approach", "weighing", "delivery"], "only the three transitions animate")
	# ---- 数学：同一组砝码配平两单，且每一单只有一解 ----
	check(Rules.balances(FIVE_GOODS, FIVE_FAR, 5), "5 + 3 + 1 = 9 balances the first order")
	check(Rules.balances(EIGHT_GOODS, EIGHT_FAR, 8), "8 + 1 = 9 balances the second order")
	check(Rules.arrangements_for(5).size() == 1 and Rules.arrangements_for(8).size() == 1,
		"each order has exactly one arrangement with these three weights")
	check(Rules.arrangements_for(5)[0].goods == FIVE_GOODS and Rules.arrangements_for(8)[0].goods == EIGHT_GOODS,
		"the shipped reference arrangements are the unique ones")
	check(Rules.placements().size() == 27 and Rules.span_units() == range(1, 14),
		"27 placements span 1..13 with one arrangement each")
	check(Rules.spans_all(), "1..13 are all solvable, so the receipt line about it is the truth")
	var one_pan := Rules.one_pan_sums()
	check(one_pan == [0, 1, 3, 4, 9, 10, 12, 13], "one-pan readings only reach the subset sums of 1/3/9")
	check(not one_pan.has(5) and not one_pan.has(8), "neither order can be made by piling weights on one pan")
	check(Rules.arrangement_caption(5) == "货 5 + 砝码 3 + 砝码 1 = 砝码 9", "the third hint reads its wording out of the math")
	check("配不出来" in Rules.arrangement_caption(14), "an amount these weights cannot make says so")
	# ---- 真动作：一枚砝码在三个去处之间走 ----
	var empty := pose(Rules.empty_pan(), Rules.empty_pan())
	check(Rules.side_of(empty, 0) == Rules.OFF, "a fresh weight stands on the rack")
	var to_far := Rules.place_weight(empty, 1, Rules.FAR)
	check(Rules.side_of(to_far, 1) == Rules.FAR and to_far.goods[1] == 0, "a weight can be asked onto the far pan")
	var to_goods := Rules.place_weight(to_far, 1, Rules.GOODS)
	check(Rules.side_of(to_goods, 1) == Rules.GOODS and to_goods.far[1] == 0,
		"the same weight crosses the beam instead of being duplicated")
	check(Rules.place_weight(to_goods, 1, Rules.GOODS).is_empty(), "a weight already on that pan is not booked twice")
	check(Rules.return_weight(to_goods, 1).goods[1] == 0, "a weight goes back to the rack")
	check(Rules.return_weight(Rules.return_weight(to_goods, 1), 1).is_empty(), "an empty rack slot gives nothing back")
	check(Rules.cycle(empty, 0).far[0] == 1, "the first click lends the weight to the far pan")
	check(Rules.side_of(Rules.cycle(Rules.cycle(empty, 0), 0), 0) == Rules.GOODS, "the second click brings it to the goods pan")
	check(Rules.side_of(Rules.cycle(Rules.cycle(Rules.cycle(empty, 0), 0), 0), 0) == Rules.OFF, "the third click puts it back on the rack")
	check(Rules.cycle(empty, 3).is_empty() and Rules.cycle(empty, -1).is_empty(), "a fourth weight does not exist to be moved")
	check(Rules.place_weight(empty, 0, Rules.OFF).is_empty(), "the rack is not a pan to place a weight on")
	check(Rules.place_weight(empty, 0, 7).is_empty(), "a pan that is not there refuses the weight")
	check(Rules.place_weight(pose(Rules.empty_pan(), Rules.empty_pan(), "arrival"), 0, Rules.FAR).is_empty(),
		"nothing can be placed before the player walks in")
	check(Rules.place_weight(pose(Rules.empty_pan(), Rules.empty_pan(), "ready"), 0, Rules.FAR).is_empty(),
		"the rack stays shut until the table opens")
	check(Rules.place_weight(pose(FIVE_GOODS, FIVE_FAR, "weighing"), 0, Rules.GOODS).is_empty(),
		"no weight moves while the beam is lifted")
	check(Rules.place_weight(pose(FIVE_GOODS, FIVE_FAR, "complete"), 0, Rules.GOODS).is_empty(),
		"the stall is closed once both orders are booked")
	check(walk_to(FIVE_GOODS, FIVE_FAR).goods == FIVE_GOODS, "the reference arrangement is reachable by clicking")
	check(walk_to(EIGHT_GOODS, EIGHT_FAR).far == EIGHT_FAR, "the second reference arrangement is reachable too")
	check(Rules.next_side(empty, 0) == Rules.FAR and Rules.next_side(to_far, 1) == Rules.GOODS,
		"the tooltip knows where each weight goes next")
	# ---- 提交闸口与如实回话 ----
	check(Rules.shortfalls(empty).size() == 1 and "架上" in Rules.shortfalls(empty)[0],
		"an all-on-rack submit is refused and names what is still missing")
	check(Rules.ready_to_weigh(pose([0, 0, 0], [0, 0, 1])) and not Rules.ready_to_weigh(empty),
		"the gate only asks for a first weight, never for correctness")
	var naive := pose(Rules.empty_pan(), [1, 1, 0])
	check(Rules.difference(naive) == -1, "the naive one-pan 5 leaves the goods pan heavier by one")
	check(not Rules.solved(naive), "the naive one-pan 5 is not solved")
	check(Rules.result_lines(naive).size() == 2, "the refusal says which pan sank and which promise is unmet")
	check(Rules.heavier_word(naive) == "货盘这一头", "the beam names the goods pan as the heavy side")
	check("5 单位" in Rules.promise_line(naive) and "差 1 单位" in Rules.promise_line(naive),
		"the refusal quotes the 5-unit promise and the one-unit gap the player made")
	check(Rules.result_lines(pose(FIVE_GOODS, FIVE_FAR)).is_empty(), "a balanced order is given no refusal at all")
	check(Rules.solved(pose(FIVE_GOODS, FIVE_FAR)) and Rules.solved(pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1)),
		"both orders read as solved with the same three weights")
	check(Rules.tilt(pose([1, 1, 1], Rules.empty_pan())) == -1.0, "an over-loaded goods pan bottoms the beam out")
	# ---- 幕的推进：两单连着走 ----
	var arriving := Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "the first line hands over to the second")
	arriving = Rules.advance(Rules.advance(arriving))
	check(arriving.beat == 2 and arriving.stage == "approach", "the third line walks the player to the stall")
	check(Rules.advance(arriving).stage == "ready", "the walk-in ends at the counter")
	var opened := Rules.advance(Rules.advance(arriving))
	check(opened.stage == "puzzle" and opened.goods == [0, 0, 0], "the walk-in never touches the weights")
	check(Rules.advance(opened).is_empty(), "an untouched rack cannot lift the beam")
	var first := pose(FIVE_GOODS, FIVE_FAR)
	check(Rules.advance(first).stage == "weighing" and Rules.advance(first).weighs == 2, "lifting the beam counts the weigh")
	check(Rules.advance(Rules.advance(first)).stage == "delivery", "a balanced first order goes straight to the hand-off")
	var off_level := pose([1, 0, 0], Rules.empty_pan())
	check(Rules.advance(Rules.advance(off_level)).stage == "result", "an unbalanced lift shows the result board")
	check(Rules.advance(Rules.advance(Rules.advance(off_level))).stage == "puzzle",
		"the result board hands the same arrangement back, nothing is deducted")
	var handed := Rules.advance(Rules.advance(Rules.advance(first)))
	check(handed.stage == "puzzle" and handed.order == 1 and handed.delivered == 1,
		"the first hand-off books order one and calls order two")
	check(handed.goods == FIVE_GOODS and handed.far == FIVE_FAR,
		"the second order starts with the first order's weights still in place")
	check(handed.built_goods[0] == FIVE_GOODS and handed.built_far[0] == FIVE_FAR,
		"the booked record is the arrangement actually built")
	check(Rules.advance(pose([1, 1, 0], [0, 0, 1], "delivery", 1)).is_empty(),
		"the second order cannot be handed over while its pans disagree")
	check(Rules.advance(pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1)).stage == "weighing",
		"order two may be weighed once order one is booked")
	var done := Rules.advance(Rules.advance(Rules.advance(pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1))))
	check(done.stage == "complete" and done.delivered == 2, "the second hand-off closes the stall")
	check(Rules.advance(done).is_empty(), "complete invents no next stage")
	check(Rules.advance(pose(FIVE_GOODS, FIVE_FAR, "nowhere")).is_empty(), "an unknown stage advances nowhere")
	# ---- 撤销、重摆与快照 ----
	var moved := Rules.return_weight(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1), 1)
	check(moved.goods[1] == 0, "the transfer step itself is one real move")
	check(Rules.restore(moved, {"goods": FIVE_GOODS.duplicate(), "far": FIVE_FAR.duplicate()}).goods == FIVE_GOODS,
		"undo puts the weight back where the previous order left it")
	check(Rules.restore(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1), {"goods": [1, 1, 0], "far": [1, 0, 0]}).is_empty(),
		"undo refuses a snapshot that uses one weight twice")
	check(Rules.restore(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1), {"goods": [1, 1, 0]}).is_empty(),
		"a snapshot missing a pan is refused")
	check(Rules.restore(pose(FIVE_GOODS, FIVE_FAR, "weighing", 1),
		{"goods": FIVE_GOODS.duplicate(), "far": FIVE_FAR.duplicate()}).is_empty(),
		"undo cannot reach into a lifted beam")
	var rewound := Rules.restore(pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1),
		{"goods": FIVE_GOODS.duplicate(), "far": FIVE_FAR.duplicate()})
	check(rewound.order == 1 and rewound.delivered == 1 and rewound.weighs == 1,
		"undo rewinds the arrangement only, never the booked order")
	var cleared := Rules.cleared(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1))
	check(cleared.goods == [0, 0, 0] and cleared.far == [0, 0, 0], "重摆 puts all three weights back on the rack")
	check(cleared.delivered == 1 and cleared.order == 1, "重摆 keeps the order that has already been handed over")
	check(Rules.cleared(pose(FIVE_GOODS, FIVE_FAR, "weighing", 1)).is_empty(), "重摆 is not offered while the beam is lifted")
	# ---- 存档 schema：残缺、伪造与非法现场 ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record " + str(bad))
	var forged := pose(FIVE_GOODS, FIVE_FAR); forged.sample = "market-mk11-1"
	check(not Rules.validate(forged), "another level's save is rejected")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.stage = "measuring"
	check(not Rules.validate(forged), "unknown stage rejected")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.beat = 1
	check(not Rules.validate(forged), "a stage past the walk-in cannot claim an unfinished dialogue")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.hint = 4
	check(not Rules.validate(forged), "hint level is capped by the shipped hints")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.hint = -1
	check(not Rules.validate(forged), "a negative hint count is corruption")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.weighs = -2
	check(not Rules.validate(forged), "a beam cannot have been lifted minus twice")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.weighs = 1.5
	check(not Rules.validate(forged), "a fractional weigh count is rejected")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.goods = [1, 1, 0, 0]
	check(not Rules.validate(forged), "a fourth weight on the pan is rejected")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.goods = [1, 2, 0]
	check(not Rules.validate(forged), "a weight cannot be counted twice on one pan")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.far = [1, 0, 1]
	check(not Rules.validate(forged), "the same weight standing on both pans at once is rejected")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.far = [0, 0, 0.5]
	check(not Rules.validate(forged), "a halved weight is corruption")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.goods = "110"
	check(not Rules.validate(forged), "a written pan is not a read pan")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.order = 5
	check(not Rules.validate(forged), "an order id that was never sent is rejected")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.delivered = 2
	check(not Rules.validate(forged), "nothing may be booked as delivered before it is handed over")
	forged = pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1); forged.delivered = 0
	check(not Rules.validate(forged), "order two cannot be worked while order one is still owed")
	forged = pose(FIVE_GOODS, FIVE_FAR, "complete"); forged.built_goods[0] = EIGHT_GOODS.duplicate()
	check(not Rules.validate(forged), "a booked record that never balanced its own order is rejected")
	forged = pose(FIVE_GOODS, FIVE_FAR, "complete"); forged.built_far[1] = [0, 0, 0]
	check(not Rules.validate(forged), "an empty booked record cannot have delivered eight units")
	forged = pose(FIVE_GOODS, FIVE_FAR, "complete"); forged.goods = FIVE_GOODS.duplicate()
	check(not Rules.validate(forged), "the closed stall must show the arrangement it actually booked")
	forged = pose(FIVE_GOODS, FIVE_FAR, "result")
	check(not Rules.validate(forged), "a result board cannot stand on a level beam")
	forged = pose([1, 0, 0], Rules.empty_pan(), "delivery")
	check(not Rules.validate(forged), "a delivery whose pans never agreed is corruption")
	forged = pose(FIVE_GOODS, FIVE_FAR, "weighing"); forged.weighs = 0
	check(not Rules.validate(forged), "the beam cannot be mid-lift with no weigh recorded")
	forged = Rules.fresh(); forged.goods = [0, 0, 1]
	check(not Rules.validate(forged), "nothing is on the scale before the player reaches it")
	forged = pose(FIVE_GOODS, FIVE_FAR, "ready")
	check(not Rules.validate(forged), "the rack cannot be emptied before the table opens")
	forged = pose(FIVE_GOODS, FIVE_FAR); forged.erase("far")
	check(not Rules.validate(forged), "a missing field is corruption, not a default")
	check(Rules.validate(pose(FIVE_GOODS, FIVE_FAR)) and Rules.validate(pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1)),
		"both reference arrangements reload as legal saves")
	check(Rules.validate(pose(FIVE_GOODS, FIVE_FAR, "complete")), "the two booked orders reload at the last stage")
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(pose(FIVE_GOODS, FIVE_FAR, "complete"))))
	check(round_trip == pose(FIVE_GOODS, FIVE_FAR, "complete") and Rules.validate(round_trip),
		"the nested booked records survive a JSON round trip")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh())))),
		"the opening record survives a JSON round trip")
	# ---- 画面只复述，不预告 ----
	check(Rules.equation(pose(FIVE_GOODS, FIVE_FAR)) == "货 5 + 砝码 3 + 砝码 1 = 砝码 9",
		"the live board reads the player's own arrangement")
	check(Rules.equation(empty) == "货 5 = 空盘", "an untouched rack reads as the goods against an empty far pan")
	check(not "平" in Rules.equation(pose(FIVE_GOODS, FIVE_FAR)) and not "差" in Rules.equation(empty),
		"the reading board never judges")
	check(Rules.pan_caption(pose(FIVE_GOODS, FIVE_FAR), Rules.FAR) == "对面那盘：砝码 9 = 9 单位",
		"a pan caption totals what stands on it")
	check(Rules.order_caption(1) == "订单二 · 8 单位 · 中街油铺", "the order slip is published verbatim")
	check(Rules.order_units(9) == 0 and Rules.order_name(9) == "订单", "an order that was never sent reads as nothing")
	check(Rules.built_equation(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1), 0) == "货 5 + 砝码 3 + 砝码 1 = 砝码 9",
		"the booked first order still reads its own equation")
	check(Rules.built_equation(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1), 7) == "", "a booked record for a phantom order is blank")
	check(Rules.migration_parts(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1)) == [],
		"no migration is claimed before both orders are booked")
	var parts := Rules.migration_parts(pose(FIVE_GOODS, FIVE_FAR, "complete"))
	check(parts == ["1 留在货盘", "3 从货盘挪到砝码架", "9 留在对面那盘"],
		"the migration line is read out of the two booked records")
	check("挪到" in Rules.migration_caption(pose(FIVE_GOODS, FIVE_FAR, "complete")), "the transfer is what gets named")
	# ---- 文案与柜面（离树探针，用完即释） ----
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == SAVE_DEFAULT, "the level defaults to the catalogue's market-mk14-1 profile")
	probe.free()
	probe = Scene.instantiate(); probe.save_path = path; probe.configure()
	check(probe.save_path == path, "configure never overwrites an injected test path")
	check(probe.scene_id == "oil" and probe.level_id == "MK14", "the level declares its kit scene and id")
	check(probe.title == Catalog.title("MK14"), "the sign title matches the chapter catalogue")
	check(probe.rules == Rules and probe.world_script != null, "the host is wired to the mk14 rules and world")
	check(probe.durations.has("weighing") and probe.zoom_stages.has("puzzle"), "the lift keeps the camera at the scale")
	probe.state = pose(FIVE_GOODS, FIVE_FAR)
	var hints: Array = probe.hint_texts()
	check(hints.size() == Rules.HINT_TIERS, "three hints ship and no more")
	for spoken in hints:
		check(not spoken.is_empty() and spoken.count("\n") == 1, "hint %s stays on the two-line board" % spoken.left(4))
	check("货 5 + 砝码 3" in hints[2], "the third hint demonstrates the arrangement the math allows")
	probe.state = pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1)
	check("货 8" in probe.hint_texts()[2], "the third hint follows the order actually on the scale")
	check("\n" not in probe.goal_line() and "\n" not in probe.status_line(), "the standing boards stay single lines")
	probe.state = pose(Rules.empty_pan(), Rules.empty_pan())
	check("上秤 0 枚" in probe.status_line(), "the status counts only what the player lifted")
	probe.state = pose(FIVE_GOODS, FIVE_FAR)
	check("上秤 3 枚" in probe.status_line(), "the status follows the weights on the scale")
	for beat in range(Rules.BEATS):
		var opening := Rules.fresh(); opening.beat = beat
		probe.state = opening
		var spoken: String = probe.line()
		check(not spoken.is_empty() and spoken.count("\n") <= 1, "arrival line %d stays inside the two-line board" % (beat + 1))
	for stage in Rules.STAGES:
		if stage == "arrival": probe.state = Rules.fresh()
		elif stage == "result": probe.state = pose([1, 0, 0], Rules.empty_pan())
		else: probe.state = pose(FIVE_GOODS, FIVE_FAR, stage)
		var told: String = probe.line()
		check(not told.is_empty() and told.count("\n") <= 1, "stage %s speaks in at most two lines" % stage)
	for order in range(Rules.ORDERS.size()):
		probe.state = pose(FIVE_GOODS if order == 0 else EIGHT_GOODS, FIVE_FAR, "delivery", order)
		check("砝码" in probe.delivery_line(), "the hand-off of order %d names what did not change" % (order + 1))
	for stage in ["arrival", "ready", "result", "complete"]:
		probe.state = Rules.fresh() if stage == "arrival" else pose(FIVE_GOODS, FIVE_FAR, stage)
		check(not probe.stage_labels().has(stage) or not probe.stage_labels()[stage].is_empty(),
			"stage %s names its own next step" % stage)
	# 热点文字：只复述现场，永不判对错；每一枚、每一盘、每一辆车都有中文说明。
	probe.state = pose(FIVE_GOODS, FIVE_FAR)
	for index in range(Rules.COUNT):
		var tip: String = probe.rack_tip(index)
		check(Rules.weight_name(index) in tip and "点一下" in tip, "rack slot %d names its weight and its next step" % index)
		check(not "沉" in tip and not "差" in tip, "rack slot %d gives no reading of the beam" % index)
	for side in [Rules.GOODS, Rules.FAR]:
		var read: String = probe.pan_hint(side)
		check(Rules.pan_name(side) in read and "抬了秤才知道" in read, "the pan tooltip describes, then defers the verdict")
		check(not "沉" in read and not "差" in read, "the pan tooltip never pre-announces which side sank")
	for index in range(Rules.CARTS.size()):
		var slip: String = probe.cart_hint(index)
		check(not slip.is_empty() and ("单位" in slip or "交货车" in slip), "cart %d tells its own story" % index)
	probe.state = pose(Rules.empty_pan(), Rules.empty_pan())
	check("货 5" in probe.pan_hint(Rules.GOODS), "the goods pan tooltip counts the real parcel on it")
	check("空盘" in probe.pan_hint(Rules.FAR), "an empty far pan is read as empty, not as zero")
	probe.free()
	# ---- 真实场景：开局、命中区、按钮 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "a fresh scene opens on the dialogue")
	check(not game.buttons.has("deliver"), "the lift button waits for the stall")
	check(game.world.scene_id == "oil" and game.world.stations.has("scale_foot"),
		"the scale is drawn from the oil courtyard stations")
	check(game.world.has_part("scale_stand") and game.world.has_part("weight_hex"),
		"the kit manifest lends the scale parts and the three weights")
	var stand: float = float(game.world.parts["scale_stand"].suggested_width) / game.world.atlas_w("scale_stand")
	var beam: float = float(game.world.parts["scale_beam"].suggested_width) / game.world.atlas_w("scale_beam")
	var pan: float = float(game.world.parts["scale_pan"].suggested_width) / game.world.atlas_w("scale_pan")
	check(maxf(absf(stand - beam), absf(stand - pan)) < 0.0025,
		"the manifest's own assembly note agrees on one factor for the three scale parts")
	check(absf(game.world.unit_scale() - MK11World.SCALE_FACTOR) < 0.0001,
		"the borrowed scale stands at the same assembly factor as the fifth-act scale")
	var chain: Dictionary = game.world.parts["scale_pan"]
	check(chain.anchor_px == chain.attachments_px.suspension,
		"the pan hangs by its own anchor, so the drawn pan can never slip off the beam hook")
	var pivot: Vector2 = game.world.beam_pivot()
	var foot: Vector2 = game.world.scale_foot()
	check(absf(pivot.x - foot.x) < 2.0 and pivot.y < foot.y,
		"the beam pivots on the stand's own spine, above its foot")
	var chain_closed := true
	var arms := []
	for side in [Rules.GOODS, Rules.FAR]:
		var hook: Vector2 = game.world.beam_hook(side, 0.0)
		var dish: Vector2 = game.world.pan_cargo(side)
		arms.append(absf(hook.x - pivot.x))
		if absf(hook.y - pivot.y) > 0.01 or dish.y <= hook.y: chain_closed = false
	check(chain_closed, "both hooks ride level with the pivot and both dishes hang below their hook")
	check(absf(arms[0] - arms[1]) < 3.0 and arms[0] > 120.0,
		"the two pans hang from arms of the same length, well clear of the pillar")
	check(Rules.WEIGHT_KITS == MK11World.WEIGHT_SPRITES and game.world.WEIGHT_WIDTHS == MK11World.WEIGHT_WIDTHS,
		"the 1, 3 and 9 are the same three props at the same size as in the fifth act")
	var rects: Array = []
	for index in range(Rules.COUNT): rects.append(game.world.rack_rect(index))
	for side in [Rules.GOODS, Rules.FAR]: rects.append(game.world.pan_rect(side))
	for index in range(Rules.CARTS.size()): rects.append(game.world.cart_rect(index))
	var sized := true
	var framed := true
	for rect in rects:
		if rect.size.x < 48 or rect.size.y < 48: sized = false
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 720: framed = false
	var clean := true
	for first_index in range(rects.size()):
		for second in range(first_index + 1, rects.size()):
			if rects[first_index].intersects(rects[second]): clean = false
	check(sized, "every hotspot is at least 48 logical pixels wide and tall")
	check(framed, "every hotspot stays inside the 1280x720 frame")
	check(clean, "no two hotspots fight over the same pixel")
	var tray_half: float = game.world.suggested("receiving_tray") / 2.0
	var on_tray := true
	for index in range(Rules.COUNT):
		var slot: Rect2 = game.world.rack_rect(index)
		if slot.position.x < game.world.rack_foot().x - tray_half or slot.end.x > game.world.rack_foot().x + tray_half:
			on_tray = false
	check(on_tray, "all three rack hit boxes sit on the receiving tray that holds the weights")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	game.commit(pose(Rules.empty_pan(), Rules.empty_pan()))
	check(game.state.stage == "puzzle" and game.history.is_empty(), "a saved stall opens without history")
	var hotspots := []
	for index in range(Rules.COUNT): hotspots.append("rack_%d" % index)
	for side in [Rules.GOODS, Rules.FAR]: hotspots.append("pan_%d" % side)
	for index in range(Rules.CARTS.size()): hotspots.append("cart_%d" % index)
	var present := true
	var labelled := true
	for id in hotspots:
		if not game.buttons.has(id): present = false; continue
		if game.buttons[id].tooltip_text.is_empty(): labelled = false
	check(present, "all 8 stall hotspots are registered")
	check(labelled, "every hotspot carries a Chinese tooltip")
	check(game.buttons.has("deliver") and not game.buttons.deliver.disabled, "the lift button is live on an untouched rack")
	check(game.buttons.has("undo") and game.buttons.undo.disabled, "nothing to undo on a fresh rack")
	check(game.buttons.has("reset") and game.buttons.has("hint"), "the stall offers 重摆 and 请扣扣提醒")
	# 架上的三种现场各量一遍：这格空着、这枚站在对面那盘、这枚站在货盘，提示话术都不一样。
	var told = 0
	var mistaken = 0
	for layout in [[Rules.empty_pan(), Rules.empty_pan()],
			[Rules.empty_pan(), [1, 0, 0]], [[1, 0, 0], Rules.empty_pan()]]:
		game.apply_committed(pose(layout[0], layout[1]), [])
		settle(game)
		var verdict = advertised_audit(game, hotspots)
		told += int(verdict[0]); mistaken += int(verdict[1])
	check(mistaken == 0 and told == Rules.COUNT * 3,
		"砝码热点写出的快捷键，按下去就是点它那一下（%d 枚，%d 处说错）" % [told, mistaken])
	game.apply_committed(pose(Rules.empty_pan(), Rules.empty_pan()), []); settle(game)
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	var looks := []
	for stage in Rules.STAGES:
		looks.append(pose(Rules.empty_pan(), Rules.empty_pan(), stage))
		looks.append(pose(FIVE_GOODS, FIVE_FAR, stage))
	looks.append(pose([1, 1, 1], Rules.empty_pan(), "puzzle"))
	looks.append(pose(Rules.empty_pan(), [1, 1, 1], "puzzle"))
	looks.append(pose(FIVE_GOODS, FIVE_FAR, "puzzle", 1))
	looks.append(pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1))
	looks.append(pose([0, 1, 0], [1, 0, 1], "puzzle", 1))
	for look in looks:
		if not Rules.validate(look): continue
		game.apply_committed(look, [])
		for at in [0.0, 0.5, 1.0]:
			game.paused = true; game.world.progress = at; await process_frame
	check(is_instance_valid(game.world) and not game.modal, "every stage repaints without breaking the scale")
	game.paused = false
	# ---- 文字与画面共用同一套算术：盘子装得下，字也出不了板 ----
	var font: Font = game.world.font
	var overflow := 0
	var offenders := ""
	var offscreen := 0
	for look in looks:
		if not Rules.validate(look): continue
		game.apply_committed(look, [])
		await process_frame
		for plank in game.world.signs():
			var wide: float = font.get_string_size(plank["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, plank["size"]).x
			if wide > plank["rect"].size.x - 20:
				overflow += 1; offenders = plank["text"]
			var rect: Rect2 = plank["rect"]
			if rect.position.x < 0 or rect.end.x > 1280 or rect.end.y > 720: offscreen += 1
	check(overflow == 0, "no board ever overflows its plank (%s)" % offenders)
	check(offscreen == 0, "no board leaves the 1280x720 frame")
	game.apply_committed(pose(FIVE_GOODS, FIVE_FAR), [])
	var row: Array = game.world.pan_row(Rules.GOODS)
	check(row.size() == Rules.pan_count(game.state, Rules.GOODS) + 1,
		"the goods pan seats the parcel and every weight on one row")
	check(game.world.pan_items(Rules.FAR) == Rules.on_list_state(game.state, Rules.FAR),
		"the far pan's row is exactly the weights standing on it")
	check(absf(row[0].x - game.world.parcel_on_pan(0).x) < 0.01, "the parcel stands in the row's first slot")
	game.apply_committed(pose([1, 1, 1], Rules.empty_pan()), [])
	var dish: Vector2 = game.world.pan_cargo(Rules.GOODS)
	var scale_half: float = game.world.part_width("scale_pan", game.world.unit_scale()) / 2.0
	var full: Array = game.world.pan_row(Rules.GOODS)
	var items: Array = game.world.pan_items(Rules.GOODS)
	var left: float = dish.x
	var right: float = dish.x
	for slot in range(items.size()):
		var half: float = game.world.parcel_width(0) / 2.0 if items[slot] == game.world.PARCEL_SLOT \
			else game.world.weight_width(items[slot]) / 2.0
		left = minf(left, full[slot].x - half); right = maxf(right, full[slot].x + half)
	check(left >= dish.x - scale_half and right <= dish.x + scale_half,
		"a fully loaded goods pan still fits inside the drawn dish")
	# ---- 纪念物那一横排也得装在自己的小盘里，摊子上的每一样东西都还在画面内 ----
	game.apply_committed(pose(EIGHT_GOODS, EIGHT_FAR, "complete"), [])
	var mini_half: float = game.world.part_width("scale_pan",
		game.world.unit_scale() * game.world.SOUVENIR_SCALE) / 2.0
	var seated := true
	for side in [Rules.GOODS, Rules.FAR]:
		var centre: Vector2 = game.world.cargo_at(game.world.souvenir_foot() + game.world.SOUVENIR_BASE,
			game.world.unit_scale() * game.world.SOUVENIR_SCALE, side, 0.0)
		var mini_items: Array = game.world.souvenir_items(side)
		var mini_row: Array = game.world.souvenir_row(side)
		for slot in range(mini_items.size()):
			var mini_w: float = game.world.parcel_width(1) * game.world.SOUVENIR_SCALE \
				if mini_items[slot] == game.world.PARCEL_SLOT \
				else game.world.weight_width(mini_items[slot]) * game.world.SOUVENIR_SCALE
			if mini_row[slot].x - mini_w / 2.0 < centre.x - mini_half: seated = false
			if mini_row[slot].x + mini_w / 2.0 > centre.x + mini_half: seated = false
	check(seated, "the miniature pans seat the booked arrangement the same way the real ones do")
	var placed := true
	for spot in [game.world.scale_foot(), game.world.rack_foot(), game.world.souvenir_foot(),
			game.world.keeper_foot()]:
		var point: Vector2 = spot
		if point.x < 40 or point.y < 40 or point.x > 1240 or point.y > 700: placed = false
	check(placed, "the scale, the rack, the souvenir and the keeper all stand inside the courtyard")
	# ---- 贴脸镜头下的扣扣：不能被窗框切掉，也不能踩上摊子上的货 ----
	# 镜头是宿主每帧算出来的派生值，这里先叫它按新那一幕换算一次，再读它自己写回的 scale。
	game.apply_committed(pose(FIVE_GOODS, FIVE_FAR, "puzzle"), [])
	game.update_camera()
	var leaned: Vector2 = game.world.position
	var close_up: float = game.world.scale.x
	check(absf(close_up - 1.10) < 0.002 and leaned.distance_to(Vector2(-64, -43)) < 0.002,
		"配秤这一幕镜头真的贴到铜秤跟前")
	var keeper: Rect2 = game.world.keeper_rect()
	check(keeper.position.x * close_up + leaned.x >= 0.0
		and keeper.end.x * close_up + leaned.x <= 1280.0
		and keeper.position.y * close_up + leaned.y >= 0.0,
		"扣扣在贴脸镜头下整只都还在画面里，左边那半个圆码没被窗框切掉")
	# 谁盖住谁与镜头无关：她在世界坐标里挨着砝码架，就量这一格。
	var clear := true
	var crowded := ""
	for index in range(Rules.COUNT):
		var seat: float = game.world.rack_spot(index).x - game.world.weight_width(index) / 2.0
		if game.world.keeper_rect().end.x > seat:
			clear = false; crowded = "第 %d 格砝码在 %.1f，她画到 %.1f" % [index + 1, seat, keeper.end.x]
	check(clear, "扣扣没有压到架上那三枚砝码（%s）" % crowded)
	# ---- 车顶板上那句「在哪儿」与货真正站的那一格是同一件事 ----
	# 交付那一幕两单同时在场：本单从秤盘飞回交货车、下一单从车上推上秤。
	# 牌子只跟着 parcel_leg 的落点走，才不会对着已经落定的货说反话。
	var pitches := {0: [FIVE_GOODS, FIVE_FAR], 1: [EIGHT_GOODS, EIGHT_FAR]}
	var mismatch := 0
	var seen := 0
	var wrong := ""
	for look in [["arrival", 0], ["approach", 0], ["puzzle", 0], ["delivery", 0],
			["approach", 1], ["puzzle", 1], ["delivery", 1], ["complete", 1]]:
		for step in range(9):
			var stage: String = look[0]
			var order: int = int(look[1])
			var pitch: Array = pitches[order] if stage not in ["arrival", "approach"] \
				else [Rules.empty_pan(), Rules.empty_pan()]
			var scene = pose(pitch[0], pitch[1], stage, order)
			if not Rules.validate(scene): continue
			game.apply_committed(scene, [])
			game.world.progress = step / 8.0
			seen += 1
			for index in range(Rules.ORDERS.size()):
				var spot: int = game.world.parcel_spot(index)
				var want := " · 在车上"
				if spot == game.world.SPOT_PAN: want = " · 上秤了"
				elif spot == game.world.SPOT_DONE: want = " · 已交货"
				var plank: String = game.world.cart_caption(index)
				if not plank.ends_with(want):
					mismatch += 1
					wrong = "%s %d 成 · %s 写着「%s」，货却算 %d" % [stage, int(step * 100 / 8), plank, want, spot]
	check(mismatch == 0 and seen == 63,
		"每一块车顶板说的都是那单货此刻真站的地方（%d 个现场，%s）" % [seen, wrong])
	# 交付那一幕的头一格里，两单货正同时被搬：一块说「已交货」的时机与一块说「上秤了」的时机
	# 都得落在飞行过半之后，且两单各自的说法互不串台。
	game.apply_committed(pose(FIVE_GOODS, FIVE_FAR, "delivery", 0), [])
	game.world.progress = 1.0
	check(game.world.parcel_spot(0) == game.world.SPOT_DONE
		and game.world.parcel_spot(1) == game.world.SPOT_PAN
		and game.world.cart_caption(0).ends_with("已交货")
		and game.world.cart_caption(1).ends_with("上秤了"),
		"交付收势时本单已停进交货车、下一单已经站上秤盘，两块牌各说各的")
	# ---- 重摆那一句只说此刻真在账上的事 ----
	game.apply_committed(pose(Rules.empty_pan(), Rules.empty_pan(), "puzzle", 0), [])
	check(game.reset_prompt()[0].contains("这一单还没交出去")
		and not game.reset_prompt()[0].contains("不会重来"),
		"第一单还没交出去时，重摆不承诺「已经交出去的那一单」")
	game.apply_committed(pose(EIGHT_GOODS, EIGHT_FAR, "puzzle", 1), [])
	check(game.reset_prompt()[0].contains("已经配平交出去的那一单不会重来"),
		"第二单在秤前时，重摆说清前一单不退回来")
	# ---- 实际操作：摆 → 抬 → 交 → 挪 → 再抬 → 再交 ----
	game.apply_committed(pose(Rules.empty_pan(), Rules.empty_pan()), [])
	game.do_cycle(0); game.do_cycle(0)
	check(game.state.goods[0] == 1 and game.history.size() == 2, "two clicks seat the 1-unit weight on the goods pan")
	game.read_pan(Rules.FAR)
	check("对面那盘" in game.message and game.state.far == [0, 0, 0], "reading an empty pan changes nothing")
	game.read_order(0)
	check("桥头灯行" in game.message, "the order slip can be read out again")
	game.advance()
	check(game.state.stage == "weighing" and game.buttons.has("skip"), "the beam lifts with pause and skip available")
	check(not game.buttons.has("rack_0"), "the rack stays shut while the beam is lifted")
	game.skip_animation()
	check(game.state.stage == "result" and "货盘这一头" in game.line(), "six against nothing sinks the goods pan and says so")
	game.advance()
	check(game.state.stage == "puzzle" and game.state.goods[0] == 1, "the result board hands the same arrangement back")
	for step in range(8):
		if game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR: break
		var want := -1
		for index in range(Rules.COUNT):
			var seat: int = Rules.GOODS
			if FIVE_FAR[index] == 1: seat = Rules.FAR
			elif FIVE_GOODS[index] != 1: seat = Rules.OFF
			if Rules.side_of(game.state, index) != seat: want = index; break
		if want < 0: break
		game.do_cycle(want)
	check(game.state.goods == FIVE_GOODS and game.state.far == FIVE_FAR, "the player can reach the reference arrangement by clicking")
	game.advance(); game.skip_animation()
	check(game.state.stage == "delivery", "the balanced first order is handed over")
	game.skip_animation()
	check(game.state.order == 1 and game.state.delivered == 1 and game.state.goods == FIVE_GOODS,
		"the second order arrives on the same scale with the weights where they were left")
	check(game.state.built_goods[0] == FIVE_GOODS, "the first arrangement is booked as it was actually built")
	for index in range(Rules.COUNT):
		var seat: int = Rules.GOODS
		if EIGHT_FAR[index] == 1: seat = Rules.FAR
		elif EIGHT_GOODS[index] != 1: seat = Rules.OFF
		var guard := 0
		while Rules.side_of(game.state, index) != seat and guard < 4:
			guard += 1; game.do_cycle(index)
	check(game.state.goods == EIGHT_GOODS and game.state.far == EIGHT_FAR,
		"one weight stepping off the pan settles the second order")
	game.advance(); game.skip_animation()
	check(game.state.stage == "delivery" and game.state.order == 1, "the second order is handed over too")
	game.skip_animation()
	check(game.state.stage == "complete" and game.state.delivered == 2 and Rules.validate(game.state),
		"the stall closes with both orders in the book")
	check(game.buttons.has("back_hub") or game.buttons.has("open_hub"), "the finished stall offers a way back to the chart")
	var receipt := ""
	for child in game.ui.get_children():
		if child is Label: receipt += child.text
	check("3 从货盘挪到砝码架" in receipt, "the receipt repeats the transfer that really happened")
	check("1 至 13" in receipt, "the receipt notes what this set of weights can span")
	check(game.world.souvenir_items(Rules.GOODS).size() == Rules.pan_count(game.state, Rules.GOODS) + 1,
		"the souvenir re-plays the booked arrangement, not an authored one")
	# ---- 存档事务：坏一次就不许留下半个现场 ----
	game.apply_committed(pose(Rules.empty_pan(), Rules.empty_pan()), [])
	game.do_cycle(2)
	var bytes := FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.do_cycle(1)
	check(game.modal and game.state.far == [0, 0, 1] and FileAccess.get_file_as_bytes(path) == bytes,
		"a failed save keeps the rack exactly as it was")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.far == [0, 1, 1] and not game.modal, "retry publishes the move as one step")
	game.undo()
	check(game.state.far == [0, 0, 1], "undo rewinds the retried move")
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == 3, "hints stop at the third tier")
	check("货 5 + 砝码 3" in game.message, "the third hint reads the first order's only arrangement")
	var kept: Dictionary = game.state.duplicate(true)
	game.reset_layout()
	check(game.state.goods == [0, 0, 0] and game.state.hint == kept.hint, "重摆 clears the pans and keeps the hints used")
	game.repository.fail_at = "open"; game.advance()
	check(not game.modal and game.state.stage == "puzzle", "an empty rack refuses the lift before anything is written")
	game.repository.fail_at = ""; game.do_cycle(1)
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle", "a failed lift save cannot start the animation")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "weighing", "retry lifts the beam at the arrangement actually saved")
	game.queue_free(); await process_frame
	# ---- 重进现场：读档读回的是玩家真正摆过的那一式 ----
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "weighing" or game.state.stage == "puzzle", "the reopened stall resumes where the player left it")
	check(Rules.validate(game.state), "the resumed stage is still a legal save")
	game.queue_free(); await process_frame
	var mid := pose(FIVE_GOODS, FIVE_FAR, "weighing", 1)
	var writer := FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(mid)); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.order == 1 and game.world.state.order == 1, "a saved second order reloads onto the same scale")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the resumed lift can be paused or skipped again")
	check(not game.buttons.has("open_hub"), "a running lift keeps the way out for later")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(pose(FIVE_GOODS, FIVE_FAR, "complete"))); writer.close()
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("back_hub"), "arriving from the chart offers the way back")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin != "hub" and game.buttons.has("open_hub"), "a standalone sample still finds a way back to the chart")
	check(game.buttons.open_hub.text == "回千灯航图", "the exit contract copies mk03's button verbatim")
	game.queue_free(); await process_frame
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	# ---- 目录一致性 ----
	check(Catalog.scene("MK14") == "res://game/market_mk14.tscn", "the catalogue points at the shipped scene")
	check(Catalog.save_path("MK14") == SAVE_DEFAULT, "the catalogue save path is the one this level writes")
	check(Catalog.LEVELS["MK14"].kit == "oil", "the catalogue keeps mk14 on the oil kit scene")
	check(Catalog.opens_after("MK14") == "MK11" and Catalog.is_side("MK14"), "mk14 is the side stall that opens after MK11")
	check(Catalog.act("MK14") == 5, "the side stall belongs to the fifth act")
	check("5" in Catalog.goal("MK14") and "8" in Catalog.goal("MK14"), "the catalogue goal names the same two orders")
	check(ResourceLoader.exists(Catalog.scene("MK14")) and Catalog.built("MK14"), "the chart can now light MK14")
	check(Catalog.available("MK14", ["MK11"]) and not Catalog.available("MK14", ["MK10"]),
		"MK14 opens for a player who finished MK11 only")
	DirAccess.remove_absolute(path)
	print("MARKET MK14 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

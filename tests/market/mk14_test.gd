extends SceneTree
# MK14 三枚砝码的小摊 v2：无头规则、存档与真实场景检查。
# 运行：godot --headless --path . --script tests/market/mk14_test.gd
# 本关的新规矩只有一条：头一单的摆法随便摆，往后每一单只能从上一单记进账里的那一式挪一枚砝码。
# 所以检查的重心不在「这一式配不配得平」，而在「哪一单能走在中间」：
# 三单接成链一共 6 条顺序，走得完的只有 4→13→7 与 7→13→4；其余四条分别死在交完第一单或第二单之后。
const Rules = preload("res://scripts/market/mk14_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk14.tscn")
const Level = preload("res://scripts/market/mk14_scene.gd")
const World = preload("res://scripts/market/mk14_world.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const SAVE_DEFAULT = "user://profiles/market-mk14-1/save-v1.json"
# 订单下标：0=4 单位、1=7 单位、2=13 单位。三进制让每一单都只有一种摆法。
const FOUR = 0
const SEVEN = 1
const THIRTEEN = 2
const WIN_A = [FOUR, THIRTEEN, SEVEN]
const WIN_B = [SEVEN, THIRTEEN, FOUR]
const DEAD_A = [THIRTEEN, FOUR]
const DEAD_B = [THIRTEEN, SEVEN]
const HALF_A = [FOUR, SEVEN]
const HALF_B = [SEVEN, FOUR]
const BEAT_DONE = 2
# 抬秤之后没配平的那一式：对面只有 9，货盘压着 4 单位的货与 1、3——两盘差 2 单位。
const OFF_BALANCE = {"goods": [1, 1, 0], "far": [0, 0, 1]}
const DEAD_LINE = "三单里只剩 7 单位那一单，可从 4 单位记下的摆法起，两枚砝码都得动。\n" \
	+ "要接着走下去，就按「重摆」把三枚放回架上，从头挑一单。"
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk14-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 独立算一遍「两单的摆法之间挪了几枚」：不复用 Rules.moved_indices，免得把同一份代码验两遍。
func moved_apart(units_from: int, units_to: int) -> int:
	var from := {}
	var to := {}
	for spot in Rules.placements():
		if Rules.balances(spot.goods, spot.far, units_from): from = spot
		if Rules.balances(spot.goods, spot.far, units_to): to = spot
	var hit := 0
	for index in range(Rules.COUNT):
		if from.goods[index] != to.goods[index] or from.far[index] != to.far[index]: hit += 1
	return hit

func arrangement(units: int) -> Dictionary:
	var found: Array = Rules.arrangements_for(units)
	return found[0] if found.size() == 1 else {}

# 手工拼一份现场：账上的每一式都由那一单唯一的摆法算出来，非 arrival 幕一律算走完三句台词。
func pose(stage: String, sequence: Array = [], order: int = Rules.NONE, goods: Array = [],
		far: Array = [], weighs: int = 0, hint: int = 0, beat: int = BEAT_DONE) -> Dictionary:
	var value = Rules.fresh()
	value.stage = stage; value.beat = beat; value.hint = hint; value.weighs = weighs
	value.order = order
	value.goods = Rules.empty_pan() if goods.is_empty() else goods.duplicate(true)
	value.far = Rules.empty_pan() if far.is_empty() else far.duplicate(true)
	value.served = sequence.duplicate(true)
	var built_goods = Rules.empty_records()
	var built_far = Rules.empty_records()
	for index in sequence:
		var spot = arrangement(Rules.ORDERS[index])
		built_goods[index] = spot.goods.duplicate(true)
		built_far[index] = spot.far.duplicate(true)
	value.built_goods = built_goods; value.built_far = built_far
	return value

func pan_of(sequence: Array, step: int) -> Array:
	var spot = arrangement(Rules.ORDERS[sequence[step]])
	return [spot.goods, spot.far]

var typeface: FontFile
func width_of(text: String, size_px: int) -> float:
	if typeface == null: typeface = UIStyle.face()
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, typeface.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(size_px)).x)
	return widest

# 台词板内框 798、20 号字：一长串汉字在 Godot 里是一个不断词，多一个字就整句画到板外。
func fits_board(text: String) -> bool: return width_of(text, 20) <= 798.0
# 回执纸内框 276、16 号字，同一道理。
func fits_paper(text: String) -> bool: return width_of(text, 16) <= 276.0

func perm(list: Array) -> Array:
	if list.size() <= 1: return [list.duplicate(true)]
	var out := []
	for at in range(list.size()):
		var rest: Array = list.duplicate(true)
		var head: int = rest.pop_at(at)
		for tail in perm(rest):
			var line: Array = tail.duplicate(true)
			line.push_front(head)
			out.append(line)
	return out

func write_save(value: Dictionary) -> void:
	var writer = FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(value))
	writer.close()

func reopen(paused: bool = true) -> Variant:
	var game = Scene.instantiate(); game.save_path = path; game.paused = paused
	root.add_child(game)
	return game

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK14 rule watchdog"); quit(1))
	# ---- 开局存档与公开常量 ----
	check(Rules.validate(Rules.fresh()), "fresh model valid")
	check(Rules.fresh().sample == "market-mk14-1", "fresh carries the mk14 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens on the three of them talking, not on a scale")
	check(Rules.fresh().order == Rules.NONE, "fresh has taken no order: all three carts are still in the street")
	check(Rules.fresh().served.is_empty(), "fresh has booked nothing: the chain starts with the player's first pick")
	check(Rules.fresh().goods == Rules.empty_pan() and Rules.fresh().far == Rules.empty_pan(), "all three weights start on the rack")
	check(Rules.fresh().weighs == 0 and Rules.fresh().hint == 0, "fresh opens without a lifted beam or a used hint")
	check(Rules.WEIGHTS == [1, 3, 9] and Rules.COUNT == 3, "the stall lends exactly the ternary set 1、3、9")
	check(Rules.ORDERS == [4, 7, 13], "the street brings 4、7、13 单位, and 13 is the one that must sit in the middle")
	check(Rules.ORDER_TAGS == ["桥头灯行", "中街油铺", "河下米行"], "each order carries its own buyer")
	check(Rules.CARTS.size() == Rules.ORDERS.size(), "one cart per order — the manifest's three anchors are exactly enough")
	check(Rules.ORDER_KITS == ["parcel_small", "parcel_medium", "parcel_large"], "the parcels grow with the units they hold")
	check(Rules.WEIGHT_KITS == ["weight_small", "weight_hex", "weight_stepped"], "the three weights keep MK11's shapes")
	check(Rules.NEXT == [Rules.FAR, Rules.OFF, Rules.GOODS], "one click steps 架上 → 对面那盘 → 货盘 → 架上")
	check(Rules.BEATS == 3 and Rules.HINT_TIERS == 3 and Rules.FULL_TILT == 3, "three lines, three hints, three units to sink the beam")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "weighing", "result", "delivery", "complete"],
		"stage list is the walk-in, the carts, the scale, the beam and the receipt")
	check(Rules.ANIMATIONS == ["approach", "weighing", "delivery"], "only the walk-in, the lift and the hand-over animate")
	# ---- 数学：每一单只有一解，两单之间挪几枚是定死的事实 ----
	check(Rules.spans_all(), "1 至 13 每一单都只有一种摆法配得平，而且各只一种")
	for units in Rules.ORDERS:
		check(Rules.arrangements_for(units).size() == 1, "%d 单位 has exactly one arrangement" % units)
	check(Rules.moved_indices(4, 13) == [2], "4 → 13 moves only the 9, off the rack")
	check(Rules.moved_indices(13, 7) == [1], "13 → 7 moves only the 3, across the beam")
	check(Rules.moved_indices(7, 13) == [1], "and back it is the same single weight")
	check(Rules.moved_indices(13, 4) == [2], "13 → 4 is one weight too")
	check(Rules.moved_indices(4, 7) == [1, 2], "4 → 7 would move two — this level's trap")
	check(Rules.moved_indices(7, 4) == [1, 2], "and 7 → 4 the same two")
	var disagree := 0
	for a in Rules.ORDERS:
		for b in Rules.ORDERS:
			if a == b: continue
			if moved_apart(a, b) != Rules.moved_indices(a, b).size(): disagree += 1
	check(disagree == 0, "moved_indices agrees with an independent scan over all 27 placements")
	check(Rules.one_move(4, 13) and Rules.one_move(13, 4) and Rules.one_move(13, 7) and Rules.one_move(7, 13),
		"13 is one weight away from both of the other two")
	check(not Rules.one_move(4, 7) and not Rules.one_move(7, 4), "the two nearest-looking orders are the farthest apart by weights")
	check(Rules.distant_pair() == [4, 7, 2], "the receipt names the 4-vs-7 pair and the two weights it costs")
	check(Rules.distant_line() == "4与7差3单位，需动两枚砝码", "and states it as arithmetic, not as a hint")
	# ---- 六条顺序：走得完的只有两条 ----
	var finished := []
	var broken := []
	for order in perm([FOUR, SEVEN, THIRTEEN]):
		var got = Rules.serve_orders(order)
		if not got.is_empty() and got.stage == "complete": finished.append(order)
		else: broken.append(order)
	check(finished.size() == 2, "exactly 2 of the 6 orders the player could pick run all the way through")
	check(finished == [WIN_A, WIN_B], "and they are 4→13→7 and 7→13→4: 13 has to be the middle order")
	check(broken.size() == 4, "the other four break the one-weight chain")
	# 从 13 开局的两条：前两单都兑得出去，死的是第三单——所以拿不到 complete，而不是走不动。
	for seq in [DEAD_A, DEAD_B]:
		var stalled = Rules.serve_orders(seq)
		check(not stalled.is_empty() and stalled.served == seq and stalled.stage != "complete",
			"%s gets two orders out and dies on the third" % str(seq))
		check(Rules.stuck(stalled), "and the stall is reported as stuck, not as an unsolved puzzle")
	# 4 与 7 互为前后单：第二单当场就写不进账，压根到不了抬秤那一步。
	for seq in [HALF_A, HALF_B]:
		check(Rules.serve_orders(seq).is_empty(), "%s is refused at the second pick: two weights is not one move" % str(seq))
	check(not Rules.serve_orders([THIRTEEN, FOUR]).is_empty() and not Rules.serve_orders([THIRTEEN, SEVEN]).is_empty(),
		"starting from 13 still gets two orders out — it only dies on the third")
	check(not Rules.serve_orders([FOUR, THIRTEEN]).is_empty() and not Rules.serve_orders([SEVEN, THIRTEEN]).is_empty(),
		"the two winning chains both survive their first two steps")
	check(Rules.serve_orders([]) == pose_open(), "an empty sequence is just the open counter")
	# ---- 记账与迁移：回执上那几行全部来自真账 ----
	var book = Rules.serve_orders(WIN_A)
	check(book.served == WIN_A and Rules.delivered(book) == 3, "the ledger keeps the order the player actually served")
	check(Rules.migration_parts(book) == ["起手 4 单位：对面 3、1 · 架上 9",
		"4 → 13：只挪 9（架上→对面）", "13 → 7：只挪 3（对面→货盘）"],
		"the migration restates each step as the weight the player moved, and where it went")
	var other = Rules.serve_orders(WIN_B)
	check(Rules.migration_parts(other)[0] == "起手 7 单位：对面 9、1 · 货盘 3", "the other chain starts from 7's own arrangement")
	check(Rules.migration_parts(other)[1] == "7 → 13：只挪 3（货盘→对面）", "and moves the 3 back across the beam")
	check(Rules.migration_parts(pose("puzzle")) == [], "nothing has been booked yet, so there is nothing to restate")
	var crowded := 0
	for sequence in [WIN_A, WIN_B]:
		for line in Rules.migration_parts(Rules.serve_orders(sequence)):
			if not fits_paper(line): crowded += 1
	check(crowded == 0, "every migration line fits the receipt paper")
	check(fits_paper(Rules.distant_line()) and fits_paper("1 至 13 每单只一解"), "the two closing lines fit the paper too")
	# ---- 挑单：三辆车都是入口 ----
	var open_counter = pose("puzzle")
	check(Rules.can_choose(open_counter, FOUR) and Rules.can_choose(open_counter, THIRTEEN),
		"the open counter lets any of the three carts be picked")
	var took = Rules.choose(open_counter, THIRTEEN)
	check(not took.is_empty() and took.order == THIRTEEN and open_counter.order == Rules.NONE,
		"picking a cart is a real move: 13 单位的货被搬上货盘")
	check(Rules.cargo_units(took) == 13 and Rules.cargo_on_pan(took), "the picked order's units are the ones压在盘上")
	check(Rules.choose(open_counter, FOUR) != open_counter, "choosing is not a no-op")
	check(Rules.choose(open_counter, 3).is_empty() and Rules.choose(open_counter, -1).is_empty(),
		"a cart that is not in the street cannot be picked")
	check(Rules.choose(pose("arrival"), FOUR).is_empty() and Rules.choose(pose("ready"), FOUR).is_empty(),
		"nothing can be picked before the player reaches the stall")
	check(Rules.choose(pose("weighing", [], FOUR, arrangement(4).goods, arrangement(4).far, 1), SEVEN).is_empty(),
		"the beam cannot be lifted over a second order")
	check(Rules.choose(book, FOUR).is_empty(), "the stall is closed once the receipt is out")
	var one_booked = pose("puzzle", [FOUR], Rules.NONE, arrangement(4).goods, arrangement(4).far, 1)
	check(Rules.choose(one_booked, FOUR).is_empty(), "an order already handed over is not on the street any more")
	check(not Rules.choose(one_booked, SEVEN).is_empty() and not Rules.choose(one_booked, THIRTEEN).is_empty(),
		"the other two carts are still there to pick")
	check(Rules.choose(one_booked, FOUR).is_empty() and not Rules.is_served(pose("puzzle"), FOUR),
		"the ledger decides which cart is empty, not the picture")
	check(Rules.is_served(one_booked, FOUR) and Rules.remaining(one_booked) == [SEVEN, THIRTEEN],
		"what is left in the street is read off the ledger")
	check(Rules.remaining_units(one_booked) == [7, 13], "and stated in units")
	# ---- 只许挪一枚：本关的规矩本身 ----
	var picked = Rules.choose(open_counter, FOUR)
	var first_lift = Rules.place_weight(picked, 2, Rules.FAR)
	check(not first_lift.is_empty() and Rules.moved_count(first_lift) == 0,
		"the first order has no baseline yet: everything is free to move")
	check(Rules.baseline(open_counter).is_empty() and Rules.baseline_caption(open_counter).is_empty(),
		"and with no booked arrangement the plaque above the beam has nothing to state")
	var booked_pans = pose("puzzle", [FOUR], Rules.NONE, arrangement(4).goods, arrangement(4).far, 1)
	check(Rules.moved_count(booked_pans) == 0 and Rules.can_touch(booked_pans, 0),
		"right after a hand-over the pans hold the booked arrangement and every weight is free")
	check(Rules.baseline_caption(booked_pans) == "4 单位的摆法：对面 3、1 · 架上 9",
		"the plaque states the booked arrangement in the weights, not as an answer")
	var second = Rules.choose(booked_pans, THIRTEEN)
	var nudged = Rules.place_weight(second, 2, Rules.FAR)
	check(not nudged.is_empty() and Rules.moved_count(nudged) == 1, "one weight off the rack is a legal second order")
	check(Rules.touch_refusal(nudged, 1) == "9 单位那一枚已经挪过了：一单只许挪一枚，先把它挪回原处。",
		"reaching for a second weight is refused by naming the one already moved, in this level's own words")
	check(Rules.touch_refusal(nudged, 2).is_empty(), "the weight already moved is never refused")
	check(not Rules.can_touch(nudged, 0) and not Rules.can_touch(nudged, 1), "the two untouched weights are locked out")
	check(Rules.can_touch(nudged, 2), "and the one already moved stays movable — putting it back is not a second move")
	check(Rules.place_weight(nudged, 1, Rules.GOODS).is_empty(), "the 3 cannot join the scale while the 9 is the moved one")
	check(Rules.return_weight(nudged, 2).far == [1, 1, 0], "taking that one weight back leaves 4's arrangement intact")
	var reopened = Rules.return_weight(nudged, 2)
	check(not reopened.is_empty() and Rules.moved_count(reopened) == 0, "one step back reopens the choice")
	check(not Rules.place_weight(reopened, 1, Rules.GOODS).is_empty(),
		"putting that one weight back reopens the choice: any of the three may go up again")
	check(Rules.cycle(second, 2) == nudged, "one click on the rack steps the chosen weight onto the far pan")
	var stepped = Rules.cycle(nudged, 2)
	check(stepped.goods[2] == 1 and stepped.far[2] == 0, "the next click steps it across to the goods pan")
	check(Rules.cycle(stepped, 2).goods[2] == 0, "and the third puts it back on the rack")
	var forced = Rules.arrange(second, arrangement(13).goods, arrangement(13).far)
	check(not forced.is_empty() and Rules.moved_count(forced) == 1, "13 is reachable from 4: one weight, the 9")
	check(Rules.arrange(second, arrangement(7).goods, arrangement(7).far).is_empty(),
		"7 is not: two weights away, so the helper is gated by the same validate")
	check(not Rules.within_one_move(pose("puzzle", [FOUR], Rules.NONE, arrangement(7).goods,
		arrangement(7).far, 1)), "and the two-weight layout is reported as outside one move")
	# ---- 死局：说清楚，并指出退路 ----
	var dead = pose("puzzle", DEAD_A, Rules.NONE, arrangement(4).goods, arrangement(4).far, 2)
	check(Rules.stuck(dead), "13 then 4 leaves 7 two weights away — the chain is dead")
	check(Rules.stuck_line(dead) == DEAD_LINE, "the dead end names the surviving order, the baseline and the way out")
	check(Rules.stuck_line(pose("puzzle", DEAD_B, Rules.NONE, arrangement(7).goods, arrangement(7).far, 2))
		.contains("只剩 4 单位那一单"), "and it names the other dead end's surviving order")
	check(not Rules.stuck(one_booked) and not Rules.stuck(open_counter), "the open counter and a fresh ledger are never 走死")
	check(not Rules.stuck(book), "a finished ledger has nothing left to reach")
	check(Rules.reachable_units(one_booked) == [13], "what is reachable is computed from the ledger")
	check(Rules.reachable_units(pose("puzzle", [FOUR, THIRTEEN], Rules.NONE, arrangement(13).goods,
		arrangement(13).far, 2)) == [7], "and narrows to the last order")
	check(Rules.reachable_units(open_counter) == [4, 7, 13], "before the first hand-over every order is fair game")
	check(fits_board(Rules.stuck_line(dead).split("\n")[0]) and fits_board(Rules.stuck_line(dead).split("\n")[1]),
		"both lines of the dead end fit the dialogue board")
	# ---- 幕的推进 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "the first line hands over to the second")
	arriving = Rules.advance(Rules.advance(arriving))
	check(arriving.beat == BEAT_DONE and arriving.stage == "approach", "the third line walks the player to the stall")
	check(Rules.advance(arriving).stage == "ready", "approach stops before player control")
	var opened = Rules.advance(Rules.advance(arriving))
	check(opened.stage == "puzzle" and opened.order == Rules.NONE and opened.goods == Rules.empty_pan(),
		"the walk-in never touches the goods")
	check(opened == open_counter, "and lands on the same open counter the rules describe")
	var nothing = Rules.advance(open_counter)
	check(nothing.is_empty(), "an empty pan with no order on it cannot be lifted")
	var reasons = Rules.shortfalls(open_counter)
	check(reasons.size() == 2, "no order picked and no weight up: two plain facts, no verdict")
	check(reasons[0] == "街上三辆车还没有一辆被你点中：先挑一单，衡伯才把货搬上货盘。",
		"the missing order is stated as the shop's own reason")
	check(reasons[1] == "三枚砝码都还在架上：先请一枚上秤，空盘配不出这一单的货。",
		"the empty pans are the second reason")
	check(Rules.shortfalls(picked).size() == 1, "a picked order with nothing on the pans is one reason short")
	check(Rules.shortfalls(Rules.arrange(pose("puzzle", [], FOUR), arrangement(4).goods, arrangement(4).far)).is_empty(),
		"once a weight stands on a pan the beam is free to lift — the rules never pre-judge the maths")
	var lift = Rules.advance(Rules.arrange(pose("puzzle", [], FOUR), arrangement(4).goods, arrangement(4).far))
	check(lift.stage == "weighing" and lift.weighs == 1, "lifting the beam costs one weigh and keeps the arrangement")
	var unbalanced = Rules.advance(Rules.arrange(pose("puzzle", [], FOUR), OFF_BALANCE.goods, OFF_BALANCE.far))
	check(Rules.advance(unbalanced).stage == "result", "an unbalanced beam comes back as a result, not a scolding")
	check(Rules.result_lines(unbalanced).size() == 2 and "沉下去了" in Rules.result_line(unbalanced)
		and "还压" in Rules.result_line(unbalanced), "the result states which side sank and what still sits on it")
	check(not "错了" in Rules.result_line(unbalanced) and not "笨" in Rules.result_line(unbalanced),
		"and it never grades the player")
	check(fits_board(Rules.result_line(unbalanced).split("\n")[0]), "the result's first line fits the board")
	var balanced = Rules.arrange(pose("puzzle", [], FOUR), arrangement(4).goods, arrangement(4).far)
	var handed = Rules.advance(Rules.advance(balanced))
	check(handed.stage == "delivery" and Rules.balanced(handed), "a level beam hands the order over")
	check(Rules.delivery_line(handed) == "衡伯画押：桥头灯行的 4 单位当场配平。\n还有 2 单在街上，下一单只许挪一枚砝码。",
		"the first hand-over counts what is still in the street, not what has already been booked")
	var after = Rules.advance(handed)
	check(after.stage == "puzzle" and after.order == Rules.NONE and after.served == [FOUR],
		"the booked order goes back to its cart and the pans stay where the player left them")
	check(after.goods == arrangement(4).goods and after.far == arrangement(4).far,
		"so the next order really does start from the arrangement just booked")
	var penultimate = Rules.advance(Rules.advance(Rules.arrange(
		pose("puzzle", [FOUR], THIRTEEN), arrangement(13).goods, arrangement(13).far)))
	check(penultimate.stage == "delivery" and "还有 1 单在街上" in Rules.delivery_line(penultimate),
		"the penultimate hand-over says the last one is still in the street")
	var last = Rules.advance(Rules.advance(Rules.arrange(
		pose("puzzle", [FOUR, THIRTEEN], SEVEN), arrangement(7).goods, arrangement(7).far)))
	check(last.stage == "delivery" and "三单都兑完了" in Rules.delivery_line(last),
		"the closing hand-over says the three weights were never added to")
	check(Rules.advance(last).stage == "complete", "the third hand-over closes the ledger")
	check(Rules.advance(book).is_empty(), "complete has no next stage to invent")
	check(Rules.advance(pose("elsewhere")).is_empty(), "an unknown stage advances nowhere")
	check(Rules.advance({"stage": "puzzle"}).is_empty() and Rules.advance({}).is_empty(),
		"a record without its beats is never advanced")
	# ---- 重摆与撤销：链子是一环扣一环的 ----
	var mid = pose("puzzle", [FOUR, THIRTEEN], Rules.NONE, arrangement(13).goods, arrangement(13).far, 2)
	var wiped = Rules.cleared(mid)
	check(not wiped.is_empty() and wiped.served.is_empty() and wiped.order == Rules.NONE,
		"重摆 rewinds the whole chain: a partial chain is not a redo")
	check(wiped.goods == Rules.empty_pan() and wiped.far == Rules.empty_pan(), "all three weights go back to the rack")
	check(wiped.built_goods == Rules.empty_records() and wiped.built_far == Rules.empty_records(), "the ledger is blank again")
	check(wiped.weighs == mid.weighs, "how many times the beam was lifted is a fact about the street, kept")
	check(Rules.cleared(pose("arrival")).is_empty() and Rules.cleared(pose("delivery", [], FOUR,
		arrangement(4).goods, arrangement(4).far, 1)).is_empty(), "重摆 only belongs to the counter")
	var host = Level.new()
	var snap: Dictionary = host.snapshot(mid)
	check(snap.order == Rules.NONE and snap.goods == arrangement(13).goods, "the undo snapshot carries the pans and which order is on them")
	check(Rules.restore(mid, snap).served == mid.served, "undo cannot un-book an order: the ledger is not in the snapshot")
	var carrying = pose("puzzle", [FOUR], THIRTEEN, arrangement(13).goods, arrangement(13).far, 2)
	var rewind = Rules.restore(carrying, {"goods": arrangement(4).goods, "far": arrangement(4).far, "order": Rules.NONE})
	check(not rewind.is_empty() and rewind.order == Rules.NONE, "undo can put a picked order back on its cart")
	check(Rules.restore(carrying, {"goods": arrangement(4).goods, "far": arrangement(4).far}).is_empty(),
		"a snapshot that forgets which order was on is refused")
	check(Rules.restore(carrying, {"goods": arrangement(4).goods, "far": arrangement(4).far, "order": FOUR}).is_empty(),
		"a snapshot cannot re-book an order that has already been handed over")
	check(Rules.restore(carrying, {"goods": [1, 0, 0], "far": [1, 0, 0], "order": Rules.NONE}).is_empty(),
		"a snapshot standing one weight on both pans at once is refused")
	check(Rules.restore(carrying, {"goods": arrangement(7).goods, "far": arrangement(7).far, "order": Rules.NONE}).is_empty(),
		"a snapshot two weights away from the booked arrangement is refused")
	check(Rules.restore(carrying, {"goods": arrangement(13).goods, "far": arrangement(13).far, "order": "2"}).is_empty(),
		"a snapshot written with a cart number as text is refused")
	check(Rules.restore(pose("arrival"), snap).is_empty() and Rules.restore(pose("weighing", [], FOUR,
		arrangement(4).goods, arrangement(4).far, 1), snap).is_empty(), "undo only works at the counter")
	# 离树探针用完就放掉：漏掉一个 Control，整关审计会在退出时报「resources still in use」。
	host.free()
	# ---- 说法：盘、式、货单 ----
	check(Rules.order_caption(SEVEN) == "订单二 · 7 单位 · 中街油铺",
		"the order sheet is public: units and buyer, nothing about how to weigh it")
	check(Rules.equation_of(arrangement(4).goods, arrangement(4).far, 4) == "货 4 = 砝码 3 + 砝码 1",
		"the equation reads the pans, cargo side against the far side")
	check(Rules.pan_caption(balanced, Rules.FAR) == "对面那盘：砝码 3 + 砝码 1 = 4 单位", "the pan caption counts what stands on it")
	check(Rules.arrangement_caption(7) == "货 7 + 砝码 3 = 砝码 9 + 砝码 1",
		"the third hint restates the maths, not an author's answer")
	check(Rules.one_pan_sums() == [0, 1, 3, 4, 9, 10, 12, 13], "one-pan sums of 1、3、9 — and 7 is not among them")
	check(Rules.cart_caption(one_booked, FOUR) == "桥头灯行 4 单位 · 已交货", "the cart plaque knows an emptied cart")
	check(Rules.cart_caption(carrying, THIRTEEN) == "河下米行 13 单位 · 上秤了", "and the one whose parcel is on the beam")
	check(Rules.cart_caption(open_counter, SEVEN) == "中街油铺 7 单位 · 在车上", "and the two still waiting in the street")
	# ---- 存档 schema ----
	for bad in [null, {}, [], "x", 5.0, [0, 0], true, 3]:
		check(not Rules.validate(bad), "reject record " + str(bad))
	var forged = pose("complete", WIN_A, Rules.NONE, arrangement(7).goods, arrangement(7).far, 3)
	var intact = forged.duplicate(true)
	forged.sample = "market-mk03-1"
	check(not Rules.validate(forged), "another level's save is rejected")
	forged = intact.duplicate(true); forged.stage = "elsewhere"
	check(not Rules.validate(forged), "an unknown stage is rejected")
	forged = intact.duplicate(true); forged.beat = 3
	check(not Rules.validate(forged), "a fourth opening line is not in the shipped script")
	forged = pose("puzzle", [], FOUR, arrangement(4).goods, arrangement(4).far, 0, 0, 0)
	check(not Rules.validate(forged), "the counter cannot open before the lines are finished")
	forged = intact.duplicate(true); forged.erase("served")
	check(not Rules.validate(forged), "a missing ledger is corruption, not an empty street")
	forged = intact.duplicate(true); forged.served = [FOUR, FOUR, SEVEN]
	check(not Rules.validate(forged), "the same order cannot be handed over twice")
	forged = intact.duplicate(true); forged.served = [FOUR, SEVEN, THIRTEEN, FOUR]
	check(not Rules.validate(forged), "a ledger longer than the street's three orders is rejected")
	forged = intact.duplicate(true); forged.served = [FOUR, SEVEN, 3]
	check(not Rules.validate(forged), "an order number above the three in the street is rejected")
	forged = intact.duplicate(true); forged.served = [FOUR, 2.0, SEVEN]
	check(not Rules.validate(forged) and Rules.validate(Content.normalize_numbers(forged)),
		"a whole number stored as a float is normalized back")
	forged = intact.duplicate(true); forged.order = SEVEN
	check(not Rules.validate(forged), "an order cannot be both picked and booked")
	forged = intact.duplicate(true); forged.order = 9
	check(not Rules.validate(forged), "a cart that is not in the street cannot be the current order")
	forged = intact.duplicate(true); forged.goods = [1, 0, 0]; forged.far = [1, 0, 0]
	check(not Rules.validate(forged), "one weight standing on both pans at once is using it twice")
	forged = intact.duplicate(true); forged.goods = [0.0, 1.0, 0.0]; forged.far = [1.0, 0.0, 1.0]
	check(not Rules.validate(forged) and Rules.validate(Content.normalize_numbers(forged)), "floats in a pan normalize back")
	forged = intact.duplicate(true); forged.goods = [0, 0]
	check(not Rules.validate(forged), "a pan with two slots is not a three-weight pan")
	forged = intact.duplicate(true); forged.goods = [2, 0, 0]
	check(not Rules.validate(forged), "a pan slot holding two of one weight is corruption")
	forged = intact.duplicate(true); forged.built_goods[SEVEN] = Rules.empty_pan()
	check(not Rules.validate(forged), "a booked order whose ledger was wiped is corruption")
	forged = intact.duplicate(true); forged.built_far[FOUR] = [1, 0, 1]
	check(not Rules.validate(forged), "a booked arrangement that does not balance its own order is corruption")
	forged = intact.duplicate(true); forged.built_goods[SEVEN] = arrangement(4).goods; forged.built_far[SEVEN] = arrangement(4).far
	check(not Rules.validate(forged), "a receipt that booked 4 单位 twice is rejected")
	check(not Rules.validate(pose("puzzle", [FOUR, SEVEN], Rules.NONE, arrangement(7).goods, arrangement(7).far, 2)),
		"4 then 7 cannot be written down at all: two weights is not one move")
	forged = intact.duplicate(true); forged.goods = arrangement(4).goods; forged.far = arrangement(4).far
	check(not Rules.validate(forged), "the finished receipt cannot sit on a stale arrangement")
	forged = pose("puzzle", [FOUR], Rules.NONE, arrangement(7).goods, arrangement(7).far, 1)
	check(not Rules.validate(forged), "the pans may sit at most one weight away from the booked arrangement")
	forged = intact.duplicate(true); forged.weighs = -1
	check(not Rules.validate(forged), "a negative weigh count is corruption")
	forged = intact.duplicate(true); forged.hint = 4
	check(not Rules.validate(forged), "hint level is capped by the shipped hints")
	forged = intact.duplicate(true); forged.hint = -1
	check(not Rules.validate(forged), "a negative hint count is corruption")
	forged = pose("weighing", [FOUR], Rules.NONE, arrangement(4).goods, arrangement(4).far, 1)
	check(not Rules.validate(forged), "the beam cannot be lifted over an empty order")
	forged = pose("delivery", [], FOUR, Rules.empty_pan(), Rules.empty_pan(), 1)
	check(not Rules.validate(forged), "a delivery of an unbalanced scale is corruption")
	forged = pose("result", [], FOUR, arrangement(4).goods, arrangement(4).far, 1)
	check(not Rules.validate(forged), "the result board cannot stand while the beam is actually level")
	forged = pose("complete", [FOUR, SEVEN, THIRTEEN], Rules.NONE, arrangement(7).goods, arrangement(7).far, 3)
	check(not Rules.validate(forged), "a ledger whose middle link is two weights away never becomes a receipt")
	check(Rules.validate(intact), "the shipped chain reloads at the receipt")
	check(Rules.validate(open_counter) and Rules.validate(carrying), "an unfinished counter is still a legal save")
	check(Rules.validate(pose("puzzle", [FOUR], SEVEN, arrangement(4).goods, arrangement(4).far, 1)),
		"picking the next order over the booked pans is a legal save")
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(intact)))
	check(round_trip == intact and Rules.validate(round_trip), "the finished ledger survives a JSON round trip")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh())))),
		"the opening record survives a JSON round trip")
	# ---- 台词、提示与回执（离树探针） ----
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == SAVE_DEFAULT, "the level defaults to the market-mk14-1 profile")
	check(probe.scene_id == "oil" and probe.level_id == "MK14", "the level declares its kit scene and id")
	check(probe.title == Catalog.title("MK14"), "the sign title matches the chapter catalogue")
	check(probe.rules == Rules and probe.world_script == World, "the host is wired to the mk14 rules and world")
	check(probe.durations.has("delivery") and probe.zoom_stages == ["puzzle", "weighing", "result"],
		"the beam lifts close and the hand-over pulls back to the courtyard")
	# 提示要说「你手里这一单」，所以离树探针也得先有一份现场：状态由宿主在 _ready 里装好。
	probe.state = Rules.fresh()
	check(probe.hint_texts().size() == Rules.HINT_TIERS, "three hints ship and no more")
	check(probe.submit_label() == "抬秤验收", "the submit button lifts the beam")
	check(probe.snapshot(Rules.fresh()) == {"goods": [0, 0, 0], "far": [0, 0, 0], "order": Rules.NONE},
		"the snapshot helper ships the three fields undo needs")
	probe.state = pose("puzzle")
	check(probe.cleared_state() == Rules.cleared(probe.state), "重摆 defers to the rules")
	probe.free()
	probe = Scene.instantiate(); probe.save_path = path; probe.configure()
	check(probe.save_path == path, "configure never overwrites an injected test path")
	probe.state = open_counter
	check("\n" not in probe.goal_line() and "\n" not in probe.status_line(), "the goal and status lines hold one unbroken line")
	check("挪一枚" in probe.goal_line() and "点车" in probe.goal_line(),
		"the goal states the ask and this level's one new rule")
	check(width_of(probe.goal_line(), 22) <= 790.0, "the goal line fits the sign it is drawn on")
	check("已交 0 单" in probe.status_line() and "还没接单" in probe.status_line(),
		"the status line reads the ledger and the current pick, nothing the beam has not already shown")
	probe.state = pose("puzzle", [FOUR], THIRTEEN, arrangement(4).goods, arrangement(4).far, 1)
	check("这一单挪了 0 枚" in probe.status_line() and "已交 1 单" in probe.status_line(),
		"and it counts the weights the player has moved in this order")
	for spoken in Level.LINES:
		check(fits_board(spoken), "an opening line fits the board: " + spoken.left(8))
	var spoken_stages := {}
	for stage in Rules.STAGES:
		var shaped = open_counter if stage == "puzzle" else book
		if stage in ["weighing", "result", "delivery"]: shaped = pose("puzzle", [FOUR], FOUR, arrangement(4).goods, arrangement(4).far, 1)
		if stage == "result": shaped = pose("result", [], FOUR, OFF_BALANCE.goods, OFF_BALANCE.far, 1)
		if stage == "weighing": shaped = pose("weighing", [], FOUR, arrangement(4).goods, arrangement(4).far, 1)
		if stage == "delivery": shaped = pose("delivery", [], FOUR, arrangement(4).goods, arrangement(4).far, 1)
		if stage == "approach": shaped = pose("approach")
		if stage == "ready": shaped = pose("ready")
		shaped = shaped.duplicate(true); shaped.stage = stage
		probe.state = shaped
		var said: String = probe.line()
		check(not said.is_empty() and fits_board(said.split("\n")[0]), "%s speaks in lines the board can hold" % stage)
		spoken_stages[stage] = said
	check("制动还插着" in spoken_stages["approach"], "the walk-in says the beam is still locked")
	check("点街上那三辆车" in spoken_stages["ready"], "the briefing sends the player to the carts")
	# 死局那句话不在循环里：柜面那一幕的说法完全取决于账上还剩什么，得单独摆一份走死的现场。
	probe.state = walked_dead()
	check("重摆" in probe.line() and "只剩 7 单位" in probe.line(),
		"a dead chain is spoken on the counter itself, and points at the way out")
	for tier in probe.hint_texts():
		check(not tier.is_empty() and tier.count("\n") <= 1, "hint %s stays inside the sign board" % tier.left(4))
		check(fits_board(tier.split("\n")[0]), "and a hint line fits the board: " + tier.left(6))
		for word in ["错了", "笨", "不行", "重新听"]: check(not word in tier, "no hint grades the player")
	check("挪一枚" in probe.hint_texts()[0], "the first tier states the rule the level is built on")
	check("中间" in probe.hint_texts()[2], "the third tier demonstrates one step, in the maths' own words")
	check("→" in probe.hint_texts()[2] and probe.hint_texts()[2].count("→") >= 2,
		"and it shows the whole winning order, which is what the level cannot say without doing the player's work")
	# 接了单的那一支：第三级提示说的是玩家手里这一单，不是作者另挑的一单。
	probe.state = pose("puzzle", [FOUR], SEVEN, arrangement(4).goods, arrangement(4).far, 1)
	for tier in probe.hint_texts():
		check(fits_board(tier.split("\n")[0]), "an order in hand keeps the hint inside the board: " + tier.left(6))
	check("中街油铺" in probe.hint_texts()[2], "and its third tier names that order's own arrangement")
	probe.state = book
	var paper: Array = probe.receipt_lines()
	check(paper.size() == 6, "the receipt ships six lines: title, three steps, the pair, the maths")
	for line in paper: check(fits_paper(line), "receipt line fits its paper: " + line.left(8))
	check(paper[1] == "起手 4 单位：对面 3、1 · 架上 9", "and the receipt opens on the order the player actually picked first")
	check(probe.receipt_rect().end.x < 338 and probe.receipt_rect().position.y > 68
		and probe.receipt_rect().end.y < 267, "the receipt panel keeps clear of the board, the sign and the cart")
	probe.state = pose("puzzle", [FOUR], THIRTEEN, arrangement(4).goods, arrangement(4).far, 1)
	check("退回街上" in probe.reset_prompt()[0], "the redo warning says the booked order goes back to the street too")
	probe.state = open_counter
	check("还没交出去" in probe.reset_prompt()[0], "an un-booked counter is warned with its own words")
	check("留在小摊" in probe.restart_prompt()[1], "replaying the scene can be declined")
	probe.free()
	# ---- 真实场景：按钮、命中区、每一幕重画 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "a fresh scene opens on the dialogue")
	check(not game.buttons.has("deliver"), "the beam button waits for the stall")
	check(game.world.scene_id == "oil" and game.world.stations.has("scale_foot"), "the stall is drawn from the oil stations")
	check(game.world.cart_station(FOUR) == game.world.station("cart_left")
		and game.world.cart_station(SEVEN) == game.world.station("cart_middle")
		and game.world.cart_station(THIRTEEN) == game.world.station("cart_right"),
		"each order stands on the cart the manifest names")
	for at in range(Rules.BEATS): game.advance()
	check(game.state.stage == "approach", "the three lines walk the player to the stall")
	game.skip_animation()
	check(game.state.stage == "ready", "approach stops before player control")
	game.advance()
	check(game.state.stage == "puzzle", "the stall is handed to the player")
	var small_target := 0
	var labelled := 0
	var targets := 0
	for id in game.buttons:
		if not id.begins_with("rack_") and not id.begins_with("cart_") and not id.begins_with("pan_"): continue
		targets += 1
		var b: Control = game.buttons[id]
		if b.size.x < 48 or b.size.y < 48: small_target += 1
		if b.tooltip_text.is_empty(): labelled += 1
	check(targets == Rules.COUNT + Rules.CARTS.size() + 2, "three weights, two pans and three carts are all clickable")
	check(small_target == 0, "every one of them is a 48 pixel target or bigger")
	check(labelled == 0, "and every one carries its own tooltip")
	var framed := true
	for id in game.buttons:
		if not id.begins_with("rack_") and not id.begins_with("cart_"): continue
		var rect: Rect2 = game.buttons[id].get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
	check(framed, "every weight and cart target stays inside the frame and clear of the button bar")
	check(game.buttons.cart_0.tooltip_text.contains("4 单位") and game.buttons.cart_2.tooltip_text.contains("13 单位"),
		"the cart tooltips state the units written on the order sheet")
	check(game.buttons.cart_0.tooltip_text.contains("键盘 A"), "and name the key that picks that cart")
	check(game.buttons.rack_2.tooltip_text.contains("9 单位") and game.buttons.rack_2.tooltip_text.contains("对面那盘"),
		"the rack tooltip names the weight and where one click takes it")
	check(game.buttons.deliver.disabled == false, "the submit button is live at the counter")
	check(game.buttons.undo.disabled, "nothing to undo on an untouched stall")
	# ---- 挑单：接单、再点同一辆车、货上盘 ----
	game.do_choose(THIRTEEN)
	check(game.state.order == THIRTEEN and game.message.is_empty(), "picking a cart lifts 13 单位的货 onto the pan")
	check(game.world.parcel_spot(THIRTEEN) == game.world.SPOT_CART, "the parcel starts its hop from its own cart")
	check(game.world.parcel_spot(FOUR) == game.world.SPOT_CART, "the two carts left in the street still say 在车上")
	game.world.clock = game.world.pick_at + World.PICK_TIME
	check(game.world.parcel_spot(THIRTEEN) == game.world.SPOT_PAN,
		"once the hop is over the plaque reads the same leg the picture drew")
	game.do_choose(THIRTEEN)
	check(game.state.order == THIRTEEN and "已经接了" in game.message, "clicking the same cart again says where that order stands")
	game.do_choose(SEVEN)
	check(game.state.order == SEVEN, "before anything is booked the player may still change their mind")
	game.do_choose(THIRTEEN)
	check(game.state.order == THIRTEEN and not game.modal, "and change it back")
	# 13 那一式：三枚各点一下，全站到对面那盘。
	game.do_cycle(0); game.do_cycle(1); game.do_cycle(2)
	check(game.state.far == [1, 1, 1] and game.state.goods == [0, 0, 0], "9、3、1 all step onto the far pan")
	game.advance()
	check(game.state.stage == "weighing", "the beam lifts on the player's own arrangement")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the lift animates with pause and skip")
	check(not game.buttons.has("rack_0"), "the stall's hotspots are gone while the beam is moving")
	game.skip_animation()
	check(game.state.stage == "delivery", "a level beam hands the order straight over")
	game.skip_animation()
	check(game.state.stage == "puzzle" and game.state.served == [THIRTEEN], "the booked order returns to the stall")
	check(game.state.order == Rules.NONE, "with no order on the pans the next pick is the player's again")
	check(game.world.parcel_spot(THIRTEEN) == game.world.SPOT_DONE, "the handed-over parcel is back on its own cart")
	# ---- 第二单：只许挪一枚，第二枚当场被拦 ----
	game.do_choose(SEVEN)
	game.do_cycle(1)
	check(game.state.goods == [0, 1, 0] and Rules.moved_count(game.state) == 1, "the 3 steps across the beam")
	game.do_cycle(0)
	check(game.state.far == [1, 0, 1] and "已经挪过了" in game.message, "reaching for the 1 is refused by name")
	check("一单只许挪一枚" in game.message, "and the refusal states the rule it hit")
	game.message = ""
	game.do_return(0)
	check(game.state.goods == [0, 1, 0] and game.state.far == [1, 0, 1], "the untouched 1 cannot be dropped back either")
	game.do_cycle(2)
	check(game.state.far == [1, 0, 1] and "3 单位那一枚已经挪过了" in game.message,
		"nor the 9, while the 3 is the one this order already spent")
	game.undo()
	check(game.state.goods == [0, 0, 0] and game.message.is_empty(), "undo takes the 3 back onto the far pan and withdraws that sentence")
	check(not game.buttons.rack_0.tooltip_text.contains("已经挪过了"), "a fresh baseline locks nothing out")
	game.do_cycle(1)
	check(Rules.moved_count(game.state) == 1, "and the 3 can be moved again")
	game.do_choose(SEVEN)
	check(game.state.order == SEVEN, "re-picking the order on the pan changes nothing but the message")
	# ---- 交完第二单，走进死局：说法与退路都在柜面上 ----
	game.advance(); game.skip_animation(); game.skip_animation()
	check(game.state.served == [THIRTEEN, SEVEN], "7 单位那一单也记进账里")
	check(game.state.goods == arrangement(7).goods and game.state.far == arrangement(7).far,
		"the pans keep 7's booked arrangement for the last order to move from")
	check(Rules.stuck(game.state), "and the last order is two weights away: the chain is dead")
	check("重摆" in game.line() and "只剩 4 单位" in game.line(), "the counter says it plainly and points at 重摆")
	check(game.buttons.has("deliver") and not game.buttons.deliver.disabled, "the beam can still be lifted — it just will not balance")
	game.advance()
	check(game.state.stage == "puzzle" and not game.message.is_empty(), "an empty ledger cannot be handed over, so the reason shows")
	# 提示只是扣扣多说话：三级问完，现场一枚砝码也没动，奖励一分不扣。
	var asked = game.state.duplicate(true)
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINT_TIERS, "the hint counter stops at the shipped tiers")
	check("中间" in game.message and "4→13→7" in game.message, "the last tier names the order that has to sit in the middle")
	check(game.state.goods == asked.goods and game.state.far == asked.far, "asking never touches the pans")
	game.message = ""
	game.do_reset()
	check(game.state.served.is_empty() and game.state.goods == Rules.empty_pan(), "重摆 blanks the whole chain in the scene")
	check(game.message.is_empty() and game.line() != DEAD_LINE, "and the dead end's sentence is withdrawn with the layout")
	# ---- 走完一条真链：全程键盘，再看回执 ----
	game.handle_key(KEY_A)
	check(game.state.order == FOUR, "A picks the first cart")
	game.handle_key(KEY_1); game.handle_key(KEY_2)
	check(game.state.far == [1, 1, 0], "1 and 2 step the 1、3 onto the far pan")
	game.handle_key(KEY_3)
	check(game.state.far == [1, 1, 1], "3 would put the 9 up too — 4 单位 does not need it")
	game.handle_key(KEY_W)
	check(game.state.far == [1, 0, 1] and game.state.goods == [0, 0, 0],
		"W is really wired: it drops the 3 straight back on the rack")
	game.handle_key(KEY_2)
	check(game.state.far == [1, 1, 1], "and one more press of 2 steps it back onto the pan")
	game.handle_key(KEY_E)
	check(game.state.far == [1, 1, 0], "E puts the 9 straight back on the rack")
	game.advance()
	check(game.state.stage == "weighing", "the submit button lifts the beam")
	game.skip_animation(); game.skip_animation()
	check(game.state.served == [FOUR], "the first step of the winning chain is booked")
	game.handle_key(KEY_D)
	check(game.state.order == THIRTEEN, "D picks 13, the order that has to sit in the middle")
	game.handle_key(KEY_3)
	check(game.state.far == [1, 1, 1] and Rules.moved_count(game.state) == 1, "one weight, the 9, and the pans read 13")
	game.advance(); game.skip_animation(); game.skip_animation()
	game.handle_key(KEY_S)
	check(game.state.order == SEVEN and game.state.served == [FOUR, THIRTEEN], "then 中街油铺 for the last order")
	game.handle_key(KEY_2)
	check(game.state.goods == [0, 1, 0] and game.state.far == [1, 0, 1],
		"one click carries the 3 across the beam — 7 is one weight from 13")
	check(Rules.moved_count(game.state) == 1 and Rules.balanced(game.state),
		"and that single weight is all this order asks for")
	game.advance(); game.skip_animation(); game.skip_animation()
	check(game.state.stage == "complete" and Rules.validate(game.state), "the third hand-over closes the ledger")
	check(game.state.served == WIN_A, "and the chain the receipt reports is the one the player walked")
	var paper_label: Label = null
	for child in game.ui.get_children():
		if child is Label and "回执 · 一单只挪一枚" in child.text: paper_label = child
	check(paper_label != null, "the receipt is drawn on the panel")
	check(paper_label != null and paper_label.text.contains("起手 4 单位"), "it restates the order the player actually picked first")
	check(paper_label != null and paper_label.text.contains("4与7差3单位"), "and closes on the maths it was built to teach")
	check(paper_label != null and width_of(paper_label.text, 16) <= 276.0, "the receipt holds its own paper")
	# 纸面量的是真高度：主题把 16 号字落到 18 像素，六行压不压得下只有排版器说了算。
	var stacked := 0.0
	if paper_label != null:
		for row in range(paper_label.get_line_count()): stacked += paper_label.get_line_height(row)
	check(paper_label != null and paper_label.get_line_count() == game.receipt_lines().size()
		and paper_label.position.y + stacked <= game.receipt_rect().end.y,
		"every receipt line is written on the paper, none hangs off its bottom edge")
	check(game.buttons.has("next") and game.buttons.next.text == "再配一次", "the receipt offers to redo the errand")
	var boards: Array = game.world.signs()
	var apart := true
	for a in range(boards.size()):
		for b in range(a + 1, boards.size()):
			if boards[a]["rect"].intersects(boards[b]["rect"]): apart = false
	check(apart, "no two stall plaques are printed on top of each other")
	var overflow := 0
	for board in boards:
		if width_of(board["text"], board["size"]) > board["rect"].size.x - 20.0: overflow += 1
	check(overflow == 0, "every plaque holds its own words inside its board")
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	for stage in Rules.STAGES:
		var looks := [book, mid]
		if stage in ["weighing", "result", "delivery"]:
			looks.append(pose("puzzle", [], FOUR, arrangement(4).goods, arrangement(4).far, 1))
			looks.append(pose("result", [], FOUR, OFF_BALANCE.goods, OFF_BALANCE.far, 1))
		if stage == "puzzle": looks.append(dead)
		for look in looks:
			var shaped = look.duplicate(true)
			shaped.stage = stage
			if stage in ["weighing", "result", "delivery"] and shaped.order < 0: shaped.order = FOUR
			if stage in ["delivery"] and not Rules.balanced(shaped):
				shaped.goods = arrangement(4).goods; shaped.far = arrangement(4).far
			if stage in ["arrival", "approach", "ready"]:
				shaped.order = Rules.NONE; shaped.served = []; shaped.weighs = 0
				shaped.goods = Rules.empty_pan(); shaped.far = Rules.empty_pan()
				shaped.built_goods = Rules.empty_records(); shaped.built_far = Rules.empty_records()
			if stage == "complete": shaped = book.duplicate(true)
			if not Rules.validate(shaped): continue
			game.apply_committed(shaped, [])
			for at in [0.0, 0.5, 1.0]:
				game.paused = true; game.world.progress = at; await process_frame
	check(is_instance_valid(game.world) and not game.modal, "every stage repaints without breaking the stall")
	game.paused = false
	# ---- 存档事务：现场写盘、失败保护、从档里接着走 ----
	# 宿主的规矩是「写不进去就当没发生过」：状态、画面与磁盘三份必须一起停在上一次成功的那一步。
	game.apply_committed(mid, [])
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.do_reset()
	check(game.modal and game.state.served == [FOUR, THIRTEEN] and FileAccess.get_file_as_bytes(path) == bytes,
		"a redo whose save fails never reaches the table, and the old file keeps every byte")
	game.repository.fail_at = ""; game.retry_save()
	check(not game.modal and game.state.served.is_empty(), "retry publishes the redo as one move")
	game.repository.fail_at = "open"; game.do_choose(THIRTEEN)
	check(game.modal and game.state.order == Rules.NONE, "a pick that cannot be saved never reaches the pans")
	game.repository.fail_at = ""; game.retry_save()
	check(not game.modal and game.state.order == THIRTEEN, "retry publishes the pick as one move")
	game.queue_free(); await process_frame
	game = reopen(); await process_frame
	check(game.state.served.is_empty() and game.state.order == THIRTEEN, "the reload resumes the pick the disk agreed to")
	check(game.world.pick_seen == THIRTEEN, "the world notices the resumed pick instead of treating it as untouched")
	game.world.clock = game.world.pick_at + World.PICK_TIME
	check(game.world.parcel_spot(THIRTEEN) == game.world.SPOT_PAN,
		"and that parcel is standing on the pan once its own hop is over")
	game.queue_free(); await process_frame
	write_save(pose("puzzle", [FOUR, SEVEN], Rules.NONE, arrangement(7).goods, arrangement(7).far, 2))
	game = reopen(); await process_frame
	check(game.modal and game.repository.protected and game.state.stage == "arrival",
		"a two-weight ledger is protected and the stall reopens clean")
	game.queue_free(); await process_frame
	write_save(pose("puzzle", [], FOUR, arrangement(4).goods, arrangement(4).far, 0))
	game = reopen(); await process_frame
	check(Rules.validate(game.state) and game.state.order == FOUR and not game.modal,
		"an unfinished pick resumes where it stopped")
	check(game.buttons.has("deliver"), "the lifted-never button is back for the player's own hand")
	game.queue_free(); await process_frame
	write_save(pose("weighing", [], FOUR, arrangement(4).goods, arrangement(4).far, 1))
	game = reopen(); await process_frame
	check(game.state.stage == "weighing" and game.buttons.has("skip"), "a beam caught mid-lift resumes its animation")
	game.queue_free(); await process_frame
	write_save(pose("delivery", [FOUR], THIRTEEN, arrangement(13).goods, arrangement(13).far, 2))
	game = reopen(); await process_frame
	check(game.state.stage == "delivery" and game.world.parcel_spot(THIRTEEN) == game.world.SPOT_PAN,
		"a resumed hand-over starts with the parcel still on the pan")
	game.world.progress = 1.0
	check(game.world.parcel_spot(THIRTEEN) == game.world.SPOT_DONE,
		"and the same leg carries it back to its own cart as the animation closes")
	# 交付木牌要分清头一单和后面的单子：第一式是从架上一枚一枚摆起来的，
	# 把它写成「只挪了一枚」就是替玩家记下一件没发生过的事。
	var plates := {"first": "", "later": ""}
	for served_before in [[], [FOUR]]:
		game.apply_committed(pose("delivery", served_before, THIRTEEN,
			arrangement(13).goods, arrangement(13).far, 1 + served_before.size()), [])
		for board in game.world.signs():
			if "签了收" in board["text"]:
				if served_before.is_empty(): plates.first = board["text"]
				else: plates.later = board["text"]
	check(plates.first == "订单三 签了收 · 这一式从架上摆起",
		"the first hand-over says the arrangement was built off the rack")
	check(plates.later == "订单三 签了收 · 只挪了一枚砝码",
		"only a hand-over that really moved one weight may say so")
	game.queue_free(); await process_frame
	write_save({"stage": "complete", "sample": "market-mk13-1"})
	game = reopen(); await process_frame
	check(game.modal and game.repository.protected, "another level's receipt is rejected, not adopted")
	game.recover_protected()
	check(not game.modal and game.state.stage == "arrival", "keeping the old file and starting over is the only way through")
	game.queue_free(); await process_frame
	write_save(pose("puzzle"))
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("leave_hub") and not game.buttons.has("open_hub"),
		"a stall entered from the chart keeps one way back, mid-placement included")
	game.queue_free(); await process_frame
	write_save(book)
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "complete" and game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
		"a standalone launch of a finished stall still finds its way back to the chart")
	check(game.buttons.has("next") and game.buttons.next.text == "再配一次", "the receipt offers to redo the errand")
	var door: Button = game.buttons.open_hub
	check(door.position == Vector2(690, 646) and door.size == Vector2(280, 54), "the way out keeps the chapter's own rect")
	game.confirm_restart()
	check(game.modal and game.state.stage == "complete", "replaying the stall asks first")
	game.close_modal()
	check(game.state.served == WIN_A and Rules.validate(game.state), "cancelling keeps the ledger the player built")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK14 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

func pose_open() -> Dictionary: return pose("puzzle")
func walked_dead() -> Dictionary: return pose("puzzle", DEAD_A, Rules.NONE, arrangement(4).goods, arrangement(4).far, 2)

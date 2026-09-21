extends SceneTree
# MK13 扣扣的旧围巾：无头规则、存档与真实场景检查。
# 本关的两条验收条件是「摊满 11 格」与「对折过来两头一段对一段」，检查按这两条分别穷举：
# 只看段数有 36 条拿法能摊满 11 格，加上对折只剩 12 条，而 12 条读出来的段数序列都是 3、5、3。
# 运行：godot --headless --path . --script tests/market/mk13_test.gd
const Rules = preload("res://scripts/market/mk13_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk13.tscn")
const Level = preload("res://scripts/market/mk13_scene.gd")
const World = preload("res://scripts/market/mk13_world.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const SAVE_DEFAULT = "user://profiles/market-mk13-1/save-v1.json"
# 5 段那两包是 0、1 号，3 段那三包是 2、3、4 号。解是 3 + 5 + 3：5 段那一包压住第 6 格的折线。
const WIN = [2, 0, 3]
# 旧版的解搬到对折尺上就是本关的陷阱：段数正好 11，折过来两头对不上。
const FLIPPED = [0, 2, 3]
const SHIFTED = [2, 3, 0]
# 扣扣最先看中的那两包 5 段：10 段，尺上只剩 1 格。
const TENS = [0, 1]
const NINES = [2, 3, 4]
# 13 段在 11 格的尺面上没有那一摊：拿起来那一步就被挡回去，压根到不了柜台的验收。
const OVERFLOW = [0, 1, 2]
# 柜面那一幕的说法：重摆之后必须原样回到这一句，上一句提示不能继续挂着。
const PUZZLE_LINE = "点柜面上的整包，它就摊到样边尺的空格里；再点那一截就退回柜面。\n包不能剪开，摊不下的那一包拿不起来。"
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk13-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 手工拼一份现场：非 arrival/story 幕必须已经听完三句台词，和 advance 的走位一致。
func pose(hand: Array, stage: String = "puzzle", worn: int = 0, beat: int = -1) -> Dictionary:
	var value = Rules.fresh()
	value.stage = stage; value.hand = hand.duplicate(true); value.worn = worn
	if beat >= 0: value.beat = beat
	elif stage == "arrival": value.beat = 0
	else: value.beat = 2
	return value

# 把一种包型组合摊成所有可能的拿法（同一类型内部哪一包无所谓，只要它换得开）。
func orderings(hand: Array) -> Array:
	if hand.size() <= 1: return [hand]
	var out := []
	for at in range(hand.size()):
		var rest = hand.slice(0, at) + hand.slice(at + 1)
		for tail in orderings(rest): out.append([hand[at]] + tail)
	return out

# 拒收的话要说得完：台词板内框 798、20 号字，汉字串中间不会自动折行，
# 改一次措辞就可能悄悄多出一个字把它撑到板子外面，这里逐条量一遍。
var typeface: FontFile
func fits_board(text: String) -> bool:
	if typeface == null: typeface = UIStyle.face()
	if "\n" in text: return false
	return typeface.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(20)).x <= 798.0

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("MK13 rule watchdog"); quit(1))
	# ---- 开局存档与公开常量 ----
	check(Rules.validate(Rules.fresh()), "fresh model valid")
	check(Rules.fresh().sample == "market-mk13-1", "fresh carries the mk13 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens on 扣扣 talking, not on a puzzle")
	check(Rules.fresh().hand.is_empty(), "fresh hand is empty: every package is still on the counter")
	check(Rules.fresh().worn == 0, "the mended look is off until the player asks for it")
	check(Rules.fresh().hint == 0, "fresh opens without a used hint")
	check(Rules.NEED == 11 and Rules.CREASE == 6, "the gauge has 11 cells and the fold sits on cell 6")
	check(Rules.SEGS == [5, 5, 3, 3, 3], "the counter stocks two 5-段 and three 3-段 packages, nothing else")
	check(Rules.packages() == 5 and Rules.shelf_total(Rules.FIVE) == 2 and Rules.shelf_total(Rules.THREE) == 3, "the visible stock limit is five packages in two sizes")
	check(Rules.segs(0) == 5 and Rules.segs(2) == 3 and Rules.segs(5) == 0, "package sizes read off the counter, unknown ids give nothing")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "delivery", "story", "complete"], "stage list is the walk-in, the counter, the mend and her story")
	check(Rules.ANIMATIONS == ["approach", "delivery"], "only the walk-in and the sewing are animations")
	# ---- 尺面容量：11 格就是上限，段数永远不会摊过头 ----
	check(Rules.free_slots(pose([])) == 11 and Rules.free_slots(pose(TENS)) == 1, "the ruler counts the cells still empty")
	check(not Rules.fits(pose(TENS), 2) and not Rules.fits(pose(TENS), 0), "1 格空位摊不进任何一包，不管它是 3 段还是 5 段")
	check(Rules.fits(pose([2, 3]), 0) and not Rules.fits(pose([0, 2]), 1),
		"6 段摊着时 5 段那一包正好补满，而 8 段摊着时只剩 3 格、5 段的包塞不进去")
	check(Rules.smallest_left(pose(TENS)) == 3 and Rules.smallest_left(pose(NINES)) == 5, "the smallest package still on the shelf is read off the shelf")
	check(Rules.on_shelf(pose(WIN)) == [1, 4], "the two packages left on the counter are the second 5-段 one and the last 3-段 one")
	# ---- 对折：逐格照一遍，中间那一格自己对自己 ----
	check(Rules.cells(pose(WIN)) == [3, 3, 3, 5, 5, 5, 5, 5, 3, 3, 3], "3+5+3 covers the 11 cells in the order it was carried")
	check(Rules.cells(pose([])) == [], "an empty gauge has no cells to fold")
	check(Rules.folds_even(pose(WIN)) and Rules.mismatch_pair(pose(WIN)) == [], "3+5+3 folds even and has nothing left to point at")
	check(not Rules.folds_even(pose(FLIPPED)) and Rules.mismatch_pair(pose(FLIPPED)) == [1, 11], "5+3+3 fails the fold at cells 1 and 11")
	check(not Rules.folds_even(pose(SHIFTED)) and Rules.mismatch_pair(pose(SHIFTED)) == [1, 11], "3+3+5 fails it at the very same pair")
	check(Rules.folds_even(pose([2])) and Rules.folds_even(pose([2, 3])), "a run that is short enough always folds even — the 11 cells are what makes it a task")
	# ---- 数学：摊满 11 格有 18 条拿法，对折只剩 6 条，读出来都是 3、5、3 ----
	var full: Array = []
	var folded: Array = []
	var patterns := {}
	var mismatches = 0
	var scolding = 0
	var crowded = 0
	for mask in range(1 << Rules.packages()):
		var hand = []
		for id in range(Rules.packages()):
			if mask & (1 << id): hand.append(id)
		for order in orderings(hand):
			var probe = pose(order)
			if not Rules.validate(probe): continue
			var missing = Rules.shortfalls(probe)
			if Rules.total(probe) == Rules.NEED:
				full.append(order)
				if Rules.folds_even(probe):
					folded.append(order); patterns[str(Rules.cells(probe))] = true
				if Rules.solved(probe) != missing.is_empty(): mismatches += 1
			else:
				if Rules.solved(probe) or missing.is_empty(): mismatches += 1
				# 拒绝必须用玩家自己摊的段数说话，并且不出现评价。
				for id in order:
					if not str(Rules.segs(id)) in missing[0]: mismatches += 1
				for word in ["错", "笨", "不行", "重新听"]:
					if word in missing[0]: scolding += 1
				for sentence in missing:
					if not fits_board(sentence): crowded += 1
	check(full.size() == 36, "36 ways of carrying whole packages lay out exactly 11 cells")
	check(folded.size() == 12, "only 12 of them fold even — which pack of a size is free, the pattern is not")
	check(patterns.size() == 1 and patterns.has("[3, 3, 3, 5, 5, 5, 5, 5, 3, 3, 3]"), "every accepted layout reads 3、5、3 from either end")
	check(mismatches == 0, "every legal layout agrees with the fold and the 11 cells the scarf asks for")
	check(scolding == 0, "no refusal ever judges the player")
	check(crowded == 0, "every refusal is one line that the dialogue board can hold whole")
	# 摊过头的那一摊在 11 格的尺面上根本不存在：段数只会不够，不会多。
	check(not Rules.validate(pose(OVERFLOW)) and Rules.total(pose(OVERFLOW)) == 13, "13 段 on an 11-cell gauge is not a legal counter")
	var jammed := 0
	for mask in range(1 << Rules.packages()):
		var hand = []
		for id in range(Rules.packages()):
			if mask & (1 << id): hand.append(id)
		if Rules.total(pose(hand)) > Rules.NEED: jammed += 1
	check(jammed > 0, "the subsets that would overshoot the gauge do exist as sets — the ruler is what refuses them")
	# ---- 招牌近 miss：每一条都按玩家自己摊的格子点名 ----
	check(Rules.shortfalls(pose(TENS)) == ["两包 5 段已经 10 段，尺上只剩 1 格：柜上没有 1 段的整包。"],
		"the two 5-段 packages are refused with the contract's own words")
	check("9 段" in Rules.shortfalls(pose(NINES))[0] and "还差 2 段" in Rules.shortfalls(pose(NINES))[0],
		"three 3-段 packages are named as 9 段, two short")
	check("摊不进" in Rules.shortfalls(pose(NINES))[0], "the 9-段 refusal says the last package cannot be squeezed in")
	check(Rules.shortfalls(pose([])).size() == 1 and "尺上还空着" in Rules.shortfalls(pose([]))[0], "an empty gauge is its own reason")
	check(Rules.shortfalls(pose(FLIPPED)).size() == 1 and "两头不齐" in Rules.shortfalls(pose(FLIPPED))[0],
		"11 段 that will not fold is refused for the fold, not for the count")
	check("第 1 格是 5 段包，第 11 格是 3 段包" in Rules.shortfalls(pose(FLIPPED))[0],
		"the fold refusal names the two cells that miss each other")
	check("第 1 格是 3 段包，第 11 格是 5 段包" in Rules.shortfalls(pose(SHIFTED))[0],
		"and it names them the other way round when the layout is mirrored")
	check(Rules.shortfalls(pose(WIN)).is_empty() and Rules.solved(pose(WIN)), "3+5+3 is accepted")
	check(not Rules.solved(pose(FLIPPED)), "the old answer is not a solution any more")
	check(Rules.shortfalls(pose([2, 3])).size() == 1 and "6 段" in Rules.shortfalls(pose([2, 3]))[0],
		"two small packages are counted in the player's own numbers")
	check(Rules.shortfalls(pose([0]))[0] == "一包 5 段，还差 6 段：对折要两头齐，先想好哪一包压住折痕。",
		"a lone package is named once, and the fold is what it points at")
	check(Rules.shortfalls(pose([2]))[0] == "一包 3 段，还差 8 段：对折要两头齐，先想好哪一包压住折痕。",
		"the 3-段 package alone keeps the same shape of sentence")
	# 负数只在「摊过头」那一摊上出现，而 11 格的尺面根本不允许摊过头：take 拒收、validate 判腐。
	check(fits_board(Rules.shortfalls(pose(FLIPPED))[0]) and fits_board(Rules.shortfalls(pose(NINES))[0])
		and fits_board(Rules.shortfalls(pose(TENS))[0]),
		"the fold, the jam and the tightest 10-段 near miss each hold one line the board can carry")
	# ---- 拿包 / 退包 / 摊不下 ----
	var empty = pose([])
	var first = Rules.take(empty, 0)
	check(first.hand == [0] and empty.hand.is_empty(), "taking a package is a real move on the counter")
	check(Rules.take(first, 0).is_empty(), "the same package cannot be taken twice")
	check(Rules.take(pose(TENS), 2).is_empty(), "a package that would overshoot the gauge is never laid")
	check("摊不进去" in Rules.refusal(pose(TENS), 2), "the overflow is refused out loud, in the shop's own words")
	check(not Rules.refusal(pose(WIN), 2).is_empty(), "a package already on the gauge still gets an answer when clicked twice")
	check("退回柜面" in Rules.refusal(pose([0, 2]), 0), "pointing at a package already on the gauge says where to click instead")
	check(Rules.refusal(pose([2]), 1) == "", "a package that fits is never refused")
	check(fits_board(Rules.refusal(pose(TENS), 2)) and fits_board(Rules.refusal(pose([0, 2]), 0))
		and fits_board(Rules.returned_line(pose([0, 2]), 0)),
		"the two refusals and the take-back are each one line the board can hold")
	check(Rules.take(empty, 5).is_empty() and Rules.take(empty, -2).is_empty(), "packages that are not on the counter cannot be taken")
	check(Rules.take(pose([], "arrival"), 0).is_empty(), "nothing can be carried before the player walks in")
	check(Rules.take(pose(WIN, "complete"), 4).is_empty(), "the counter is closed once the receipt is out")
	var back = Rules.give_back(pose(WIN), 2)
	check(back.hand == [0, 3] and Rules.total(back) == 8, "one package goes back to the shelf and the gauge drops to 8 段")
	check("8 段" in Rules.returned_line(back, 2) and "还差 3 格" in Rules.returned_line(back, 2),
		"the take-back is narrated in the cells the player still has")
	check(Rules.give_back(pose(WIN), 4).is_empty(), "a package still on the shelf cannot be given back")
	check(Rules.give_back(pose([], "delivery"), 0).is_empty(), "the sewing is not a shopping trip")
	# ---- 柜面是实物库存：拿走就少一格 ----
	var held = pose(WIN)
	check(Rules.shelf_count(held, Rules.FIVE) == 1 and Rules.shelf_count(held, Rules.THREE) == 1, "the shelf visibly loses the packages the player carried off")
	check(Rules.shelf_caption(held, Rules.FIVE) == "5 段整包 · 柜上还有 1 包", "the stock limit is published on the counter")
	check(Rules.shelf_caption(pose([]), Rules.THREE) == "3 段整包 · 柜上还有 3 包", "untouched stock reads three packages")
	check(Rules.left_line(held) == "5 段 1 包 · 3 段 1 包", "the receipt states what is left on the counter")
	check(Rules.packages_line(held) == "3 段 + 5 段 + 3 段", "the packages are restated in the order they were carried")
	check(Rules.packages_line(pose([])) == "还没拿包", "an empty hand is stated as empty")
	check(Rules.gauge_caption(pose([0, 2])) == "样边尺 · 11 格 · 已摊 8 段", "the gauge counts what is laid on it, nothing else")
	check(not "齐" in Rules.gauge_caption(pose(FLIPPED)), "the gauge tag never announces whether the two ends match")
	check(Rules.run_start(held, 2) == 8 and Rules.run_segs(held, 2) == 3 and Rules.run_package(held, 2) == 3, "the third package covers gauge cells 9 to 11")
	check(Rules.run_start(held, 0) == 0 and Rules.run_segs(held, 9) == 0 and Rules.run_package(held, 9) == -1, "a run outside the hand owns no cells")
	check(Rules.run_start(held, 1) == 3, "the 5-段 package starts right where the first 3-段 run ends")
	# ---- 幕的推进 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "the first line hands over to the second")
	arriving = Rules.advance(arriving); arriving = Rules.advance(arriving)
	check(arriving.beat == 2 and arriving.stage == "approach", "the third line walks the player to the counter")
	check(Rules.advance(arriving).stage == "ready" and Rules.advance(Rules.advance(arriving)).stage == "puzzle", "approach then ready then the counter")
	var opened = Rules.advance(Rules.advance(arriving))
	check(opened.hand.is_empty(), "the walk-in never touches the goods")
	check(Rules.advance(opened).is_empty(), "an empty counter cannot be handed over")
	check(Rules.advance(pose(TENS)).is_empty(), "the two 5-段 packages are not accepted, however tempting")
	check(Rules.advance(pose(NINES)).is_empty(), "9 段 stays at the counter")
	check(Rules.advance(pose(FLIPPED)).is_empty() and Rules.advance(pose(SHIFTED)).is_empty(),
		"a full 11 cells that will not fold still stays at the counter")
	var mending = Rules.advance(held)
	check(mending.stage == "delivery" and Rules.validate(mending), "11 cells folded even release the sewing")
	var story = Rules.advance(mending)
	check(story.stage == "story" and story.beat == 0, "the sewing hands over to her own story, from its first line")
	check(Rules.advance(story).beat == 1 and Rules.advance(Rules.advance(story)).beat == 2, "the story is told line by line")
	check(Rules.advance(Rules.advance(Rules.advance(story))).stage == "complete", "the last line ends the scene")
	check(Rules.advance(pose(WIN, "complete")).is_empty(), "complete has no next stage to invent")
	check(Rules.advance(pose(WIN, "elsewhere")).is_empty(), "an unknown stage advances nowhere")
	check(Rules.advance({"stage": "puzzle"}).is_empty() and Rules.advance({}).is_empty(), "a record without its beats is never advanced")
	# ---- 撤销快照 ----
	check(Rules.restore(Rules.take(pose([0, 2]), 3), {"hand": [0, 2], "worn": 0}).hand == [0, 2], "undo puts the last package back on the shelf")
	check(Rules.restore(Rules.give_back(held, 2), {"hand": WIN, "worn": 0}).hand == WIN, "undo re-takes a package that was given back")
	check(Rules.restore(pose([], "arrival"), {"hand": WIN, "worn": 0}).is_empty(), "undo only works at the counter")
	check(Rules.restore(pose([], "delivery"), {"hand": WIN, "worn": 0}).is_empty(), "undo cannot reach into the sewing")
	check(Rules.restore(held, {"hand": [0, 2]}).is_empty(), "a snapshot missing the worn flag is refused")
	check(Rules.restore(held, {"hand": [0, 2, 2], "worn": 0}).is_empty(), "a snapshot carrying one package twice is refused")
	check(Rules.restore(held, {"hand": [0, 1, 2], "worn": 0}).is_empty(), "a snapshot of 13 段 is refused: the gauge has 11 cells")
	check(Rules.restore(held, {"hand": [0, 2, 9], "worn": 0}).is_empty(), "a snapshot pointing at a package the shop never had is refused")
	check(Rules.restore(held, {"hand": [0.0, 2, 3], "worn": 0}).is_empty(), "a snapshot storing a package number as a float is normalized back")
	check(Rules.restore(held, {"hand": WIN, "worn": 1}).is_empty(), "undo cannot put the mended look on at the counter")
	var kept = Rules.restore(held, {"hand": [0], "worn": 0})
	check(kept.stage == "puzzle" and kept.hint == 0 and kept.sample == "market-mk13-1", "undo only rewinds the counter, never the scene")
	# ---- 自愿换上：只写本关自己的存档 ----
	var worn_story = Rules.wear(pose(WIN, "story"))
	check(not worn_story.is_empty() and worn_story.worn == 1, "the mended edge can be worn from the story onward")
	check(Rules.wear(worn_story).is_empty(), "wearing it twice invents nothing")
	check(Rules.tuck(worn_story).worn == 0, "and it can be tucked away again, still mended")
	check(Rules.wear(pose(WIN)).is_empty(), "the counter does not offer the look yet")
	check(Rules.wear(pose(WIN, "delivery")).is_empty(), "the sewing does not offer the look either")
	check(Rules.wear_line(worn_story) != Rules.wear_line(Rules.tuck(worn_story)), "both choices answer in their own words")
	check("对折" in Rules.wear_line(worn_story), "what she says about it is the fold, not a reward")
	check(not "森林" in Rules.wear_line(worn_story), "the reward stays inside this station")
	# ---- 存档 schema ----
	for bad in [null, {}, [], "x", 5.0, [0, 0], true, 3]: check(not Rules.validate(bad), "reject record " + str(bad))
	var forged = pose(WIN); forged.sample = "market-mk03-1"
	check(not Rules.validate(forged), "another level's save is rejected")
	forged = pose(WIN); forged.stage = "sewing"
	check(not Rules.validate(forged), "unknown stage rejected")
	forged = pose(WIN); forged.beat = 3
	check(not Rules.validate(forged), "a fourth opening line is not in the shipped script")
	forged = pose(WIN, "puzzle", 0, 1)
	check(not Rules.validate(forged), "the counter cannot open before the lines are finished")
	forged = pose(WIN, "complete", 0, 1)
	check(not Rules.validate(forged), "the receipt cannot claim a story left half-told")
	forged = pose(WIN, "story", 0, 3)
	check(not Rules.validate(forged), "the story has as many beats as it ships and no more")
	forged = pose(WIN); forged.hint = 4
	check(not Rules.validate(forged), "hint level is capped by the shipped hints")
	forged = pose(WIN); forged.hint = -1
	check(not Rules.validate(forged), "a negative hint count is corruption")
	forged = pose(WIN); forged.hand = OVERFLOW
	check(not Rules.validate(forged), "13 段 laid on an 11-cell gauge is corruption, not a longer ruler")
	forged = pose(WIN); forged.hand = [0, 2, 5]
	check(not Rules.validate(forged), "a package number above the counter's stock is rejected")
	forged = pose(WIN); forged.hand = [0, 2, -1]
	check(not Rules.validate(forged), "a negative package number is rejected")
	forged = pose(WIN); forged.hand = [0, 2, 2]
	check(not Rules.validate(forged), "the same package cannot be carried twice")
	forged = pose(WIN); forged.hand = "203"
	check(not Rules.validate(forged), "a written-down hand is not a carried hand")
	forged = pose(WIN); forged.hand = [0, 2, 3, 1, 4]
	check(not Rules.validate(forged), "a hand the gauge cannot hold is rejected")
	forged = pose(WIN); forged.erase("hand")
	check(not Rules.validate(forged), "a missing field is corruption, not an empty hand")
	forged = pose(WIN); forged.worn = 2
	check(not Rules.validate(forged), "the mended look is a choice, not a counter")
	forged = pose(WIN); forged.worn = -1
	check(not Rules.validate(forged), "a negative appearance flag is corruption")
	forged = pose(WIN); forged.worn = "1"
	check(not Rules.validate(forged), "a written flag is not a worn flag")
	forged = pose([0], "arrival")
	check(not Rules.validate(forged), "nothing can be carried before the player reaches the counter")
	forged = pose([0], "ready")
	check(not Rules.validate(forged), "the goods stay on the counter until the table is handed over")
	forged = pose(WIN, "puzzle", 1)
	check(not Rules.validate(forged), "the mended edge cannot be worn before it is sewn")
	forged = pose(WIN, "delivery", 1)
	check(not Rules.validate(forged), "the sewing cannot be wearing it either")
	forged = pose(TENS, "delivery")
	check(not Rules.validate(forged), "a sewing of 10 段 is rejected")
	forged = pose(FLIPPED, "delivery")
	check(not Rules.validate(forged), "11 cells that miss the fold cannot be a finished sewing")
	forged = pose(FLIPPED, "complete")
	check(not Rules.validate(forged), "nor a finished receipt")
	forged = pose(NINES, "story")
	check(not Rules.validate(forged), "her story cannot be told off an unfinished edge")
	forged = pose([], "complete")
	check(not Rules.validate(forged), "a receipt with nothing bought is rejected")
	check(Rules.validate(pose(WIN, "complete")), "the shipped solution reloads at the last stage")
	check(Rules.validate(pose([], "puzzle")) and Rules.validate(pose(TENS, "puzzle")), "an unfinished counter is still a legal save")
	check(Rules.validate(pose(WIN, "story", 1, 1)), "the look can be chosen part-way through her story")
	check(Rules.validate(pose(WIN, "delivery", 0, 2)), "the sewing is a legal save with the look still off")
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(pose(WIN, "complete", 1))))
	check(round_trip == pose(WIN, "complete", 1) and Rules.validate(round_trip), "the worn receipt survives a JSON round trip")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh())))), "the opening record survives a JSON round trip")
	# ---- 台词与提示（离树探针，用完即释） ----
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == SAVE_DEFAULT, "the level defaults to the market-mk13-1 profile")
	probe.free()
	probe = Scene.instantiate(); probe.save_path = path; probe.configure()
	check(probe.save_path == path, "configure never overwrites an injected test path")
	check(probe.scene_id == "nursery" and probe.level_id == "MK13", "the level declares its kit scene and id")
	check(probe.title == Catalog.title("MK13"), "the sign title matches the chapter catalogue")
	check(probe.rules == Rules and probe.world_script != null, "the host is wired to the mk13 rules and world")
	check(probe.durations.has("delivery") and probe.zoom_stages == ["puzzle"], "the sewing plays wide and the counter keeps its zoom")
	check(probe.hint_texts().size() == Rules.HINTS, "three hints ship and no more")
	for spoken in probe.hint_texts():
		check(not spoken.is_empty() and spoken.count("\n") <= 1, "hint %s stays inside the sign board" % spoken.left(4))
		for line in spoken.split("\n"): check(fits_board(line), "hint line %s is one line the board holds" % line.left(4))
	check("对折" in probe.hint_texts()[0] and "折线" in probe.hint_texts()[1], "the hints go from the fold, to which pack straddles it")
	check("点一包" in probe.hint_texts()[2], "the last hint demonstrates one step instead of writing an equation")
	check("\n" not in probe.goal_line(), "the goal line fits one unbroken line")
	check("11 格" in probe.goal_line() and "对折" in probe.goal_line(), "the goal states both asks: fill the 11 cells, fold even")
	check(Rules.HINTS == probe.hint_texts().size(), "no hint tier ships without a line")
	probe.state = pose([])
	check("\n" not in probe.status_line() and "0 段摊在尺上" in probe.status_line(), "the status line counts only what the gauge can count")
	probe.state = pose(TENS)
	check("10 段" in probe.status_line() and "还差" not in probe.status_line() and "齐" not in probe.status_line(),
		"the bottom bar never does the subtraction or the folding for the player")
	probe.state = pose(WIN)
	check("11 段" in probe.status_line(), "the status follows the laid segments")
	probe.state = pose(FLIPPED)
	check("11 段" in probe.status_line() and "不齐" not in probe.status_line(),
		"a full gauge that misses the fold reads the same until it is handed over")
	for beat in range(3):
		probe.state = pose([], "arrival", 0, beat)
		var text = probe.line()
		check(not text.is_empty() and text.count("\n") <= 1, "arrival line %d stays inside the two-line board" % (beat + 1))
		for line in text.split("\n"): check(fits_board(line), "arrival line %d fits the board" % (beat + 1))
	check("对折" in Level.LINES[1], "the fold is on the table before the player reaches the counter")
	check("第 6 格" in Level.LINES[2], "the second speaker pins the crease to a numbered cell")
	for beat in range(3):
		probe.state = pose(WIN, "story", 0, beat)
		var told = probe.line()
		check(not told.is_empty() and told.count("\n") <= 1, "story beat %d stays inside the two-line board" % (beat + 1))
		for word in ["明白了吗", "一定要", "记住"]:
			check(not word in told, "story beat %d never turns into a lesson" % (beat + 1))
	probe.state = pose(WIN, "story", 0, 0)
	check("第一次送货" in probe.line(), "the reward is her own first delivery, told by her")
	for stage in Rules.STAGES:
		probe.state = pose(WIN, stage) if stage != "arrival" else pose([], "arrival")
		check(not probe.line().is_empty(), "stage %s always has a spoken line" % stage)
	probe.state = pose(WIN, "story", 0, 0)
	check(probe.goal_line().is_empty(), "her own story is not captioned as a task")
	for stage in ["arrival", "ready", "story", "complete"]:
		probe.state = pose(WIN, stage) if stage != "arrival" else pose([], "arrival")
		check(not probe.stage_labels().has(stage) or not probe.stage_labels()[stage].is_empty(), "stage %s names its own next step" % stage)
	check(probe.reset_prompt().size() == 3 and probe.reset_prompt()[0].count("\n") <= 1, "重摆 asks once, in two lines at most")
	check(probe.restart_prompt().size() == 3, "replaying the scene asks before touching anything")
	probe.free()
	# ---- 真实场景：按钮、命中区、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "a fresh scene opens on the dialogue")
	check(game.buttons.has("next") and not game.buttons.has("deliver"), "the hand-over button waits for the counter")
	check(game.world.scene_id == "nursery" and game.world.stations.has("counter_left"), "the counter is drawn from the nursery stations")
	check(game.world.board_centre() == game.world.station("counter_right") + Vector2(18, 0), "the gauge stands on the counter the manifest names")
	check(game.world.crease_x() == game.world.slot_foot(Rules.CREASE - 1).x, "the crease the world draws is the cell the rules name")
	var gauge = game.world.board_frame()
	var hem: Rect2 = game.world.scarf_hem(World.KOUKOU_TIE)
	check(not gauge.intersects(hem) and gauge.position.y > 184 and gauge.end.x < 1281 and gauge.end.y < 646,
		"the gauge clears her scarf, the dialogue board and the button bar")
	var tags = [game.world.shelf_plaque(Rules.FIVE), game.world.shelf_plaque(Rules.THREE), game.world.board_plaque(),
		game.world.rule_plaque(), game.world.look_plaque()]
	var apart = true
	for a in range(tags.size()):
		for b in range(a + 1, tags.size()):
			if tags[a].intersects(tags[b]): apart = false
	check(apart, "no two counter tags are printed on top of each other")
	var rule: Rect2 = game.world.rule_plaque()
	check(rule.end.x < game.world.board_plaque().position.x and rule.size.x >= 248,
		"the longer shop-rule tag has room and still keeps clear of the gauge tag")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	game.commit(pose([], "puzzle"))
	check(game.state.stage == "puzzle" and game.history.is_empty(), "a saved counter opens without history")
	var shelf = []
	for id in range(Rules.packages()): shelf.append("stock_%d" % id)
	var present = true
	var sized = true
	var framed = true
	for id in shelf:
		if not game.buttons.has(id): present = false; continue
		var button: Button = game.buttons[id]
		if button.size.x < 48 or button.size.y < 48: sized = false
		var rect = button.get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
	check(present, "all five packages on the counter are clickable")
	check(sized, "every package target is at least 48 logical pixels wide and tall")
	check(framed, "every package target stays inside the frame and clear of the bottom bar")
	check(game.buttons.has("deliver") and not game.buttons.deliver.disabled, "the hand-over button is live on an untouched counter")
	check(game.buttons.has("undo") and game.buttons.undo.disabled, "nothing to undo on a fresh counter")
	check(game.buttons.has("reset") and game.buttons.has("hint"), "the counter offers 重摆 and 请扣扣提醒")
	check(game.buttons.stock_0.tooltip_text.contains("5 段") and game.buttons.stock_2.tooltip_text.contains("3 段"), "the tooltips tell which size each package is")
	check(game.buttons.stock_2.tooltip_text.contains("还剩 11 格"), "the tooltip states how much of the gauge is still empty")
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	for stage in Rules.STAGES:
		var looks = [pose([], stage) if stage != "story" else pose(WIN, stage)]
		if stage == "puzzle":
			looks.append(pose(TENS, stage)); looks.append(pose(WIN, stage)); looks.append(pose(FLIPPED, stage))
		if stage in ["delivery", "story", "complete"]: looks.append(pose(WIN, stage, 1))
		for look in looks:
			game.apply_committed(look, [])
			for at in [0.0, 0.5, 1.0]:
				game.paused = true; game.world.progress = at; await process_frame
	check(is_instance_valid(game.world) and not game.modal, "every stage repaints without breaking the counter")
	game.paused = false
	# ---- 键盘走到解：3 段、5 段、3 段 ----
	game.apply_committed(pose([], "puzzle"), [])
	game.toggle_package(2)
	check(game.state.hand == [2] and game.history.size() == 1, "the first 3-段 package is laid at the left end")
	game.toggle_package(0)
	check(game.state.hand == [2, 0] and Rules.total(game.state) == 8, "the 5-段 package straddles the crease")
	check(Rules.run_start(game.state, 1) == 3 and Rules.run_segs(game.state, 1) == 5,
		"the 5-段 run starts on cell 4 and so covers the fold cell itself")
	game.toggle_package(3)
	check(game.state.hand == WIN and Rules.solved(game.state), "the second 3-段 package closes the right end")
	check(Rules.cells(game.state).size() == Rules.NEED, "the accepted layout fills every one of the 11 cells")
	# ---- 旧答案就是本关的陷阱：段数正好，对折照不上 ----
	game.do_reset()
	game.toggle_package(0); game.toggle_package(2); game.toggle_package(3)
	check(game.state.hand == FLIPPED and Rules.total(game.state) == Rules.NEED,
		"carrying the 5-段 pack first still lays out 11 cells")
	game.advance()
	check(game.state.stage == "puzzle" and "两头不齐" in game.message,
		"the old answer is refused for the fold, not for the count")
	check(game.message.contains("第 1 格是 5 段包"), "and it names the pair of cells that miss each other")
	game.undo()
	check(game.state.hand == [0, 2] and game.message.is_empty(),
		"undo takes the last package back and withdraws that sentence")
	# ---- 摊不下：两包 5 段之后柜上没有装得进的包 ----
	game.do_reset()
	game.toggle_package(0); game.toggle_package(1)
	check(Rules.total(game.state) == 10 and game.state.hand == TENS, "the tempting pair fills 10 of the 11 cells")
	game.toggle_package(2)
	check(game.state.hand == TENS and "摊不进去" in game.message, "a 3-段 package has nowhere to go on the last cell")
	game.advance()
	check(game.state.stage == "puzzle" and game.message == "两包 5 段已经 10 段，尺上只剩 1 格：柜上没有 1 段的整包。",
		"the two 5-段 packages are refused in the scene, in the contract's words")
	game.undo()
	check(game.state.hand == [0] and game.message.is_empty(), "undo takes the second 5-段 package back")
	# ---- 三包 3 段：9 段，剩下的空位装不下任何整包 ----
	game.do_reset()
	game.toggle_package(2); game.toggle_package(3); game.toggle_package(4)
	check(game.state.hand == NINES and Rules.total(game.state) == 9, "three 3-段 packages are 9 cells")
	game.advance()
	check(game.state.stage == "puzzle" and "摊不进这 2 格空位" in game.message, "9 段 names the two free cells it cannot fill")
	# ---- 三级提示：只提点，不代劳，也不判分 ----
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == 3 and "折线" in game.message, "the third hint points at the crease and stops there")
	check("点一包" in game.message and "5 + 3 + 3" not in game.message,
		"no hint hands over an equation the gauge was built to avoid")
	for word in ["重做", "错了", "笨"]: check(not word in game.message, "the third hint never grades the player")
	game.do_reset()
	check(game.state.hand.is_empty() and game.state.hint == 3, "重摆 puts every package back and keeps the hints the player already asked for")
	check(game.message.is_empty() and game.line() == PUZZLE_LINE,
		"重摆 withdraws the hint line the old layout was answering")
	# ---- 交货、故事、回执与存档事务 ----
	game.toggle_package(2); game.toggle_package(0); game.toggle_package(3)
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.toggle_package(4)
	check(not game.modal and game.state.hand == WIN and FileAccess.get_file_as_bytes(path) == bytes,
		"a package that would overshoot the gauge never reaches the disk")
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle", "a failed hand-over save cannot start the sewing")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "delivery" and not game.modal, "retry publishes the hand-over as one move")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the sewing animates with pause and skip")
	check(not game.buttons.has("stock_0"), "the counter hotspots are gone during the sewing")
	game.skip_animation()
	check(game.state.stage == "story" and game.state.beat == 0, "the sewing hands over to her own story")
	check(game.world.sewn() == Rules.NEED, "the whole edge is on her scarf by the time she talks")
	check(game.world.laid() == 0, "the gauge is empty again once the cloth is on her scarf")
	check(game.buttons.has("wear") and game.buttons.wear.text == "换上补好的围巾", "the mended look is offered, not applied")
	game.toggle_wear()
	check(game.state.worn == 1 and game.modal == false, "wearing it is one saved choice")
	game.advance()
	check(game.state.beat == 1, "the story keeps its own beats")
	game.advance(); game.advance()
	check(game.state.stage == "complete" and Rules.validate(game.state), "the last line ends on the receipt")
	check(game.buttons.has("next") and game.buttons.next.text == "再补一次", "the last board offers to redo the errand")
	check(game.buttons.has("wear") and game.buttons.wear.text == "换回原来的样子", "the offer stays reversible at the receipt")
	check(game.ui.get_child_count() > 2, "the receipt panel is drawn at the end")
	var paper: Label = null
	for child in game.ui.get_children():
		if child is Label and "回执 · 育苗铺补边布" in child.text: paper = child
	check(paper != null and paper.text.contains("拿的包：3 段 + 5 段 + 3 段 = 11 段"),
		"the receipt restates the packages the player actually carried, in the order they were laid")
	check(paper != null and paper.text.contains("对折过来"), "the receipt states the fold it checked")
	check(paper != null and paper.text.contains("柜上还剩：5 段 1 包 · 3 段 1 包"), "the receipt states what the counter lost")
	var on_disk = game.state.duplicate(true)
	game.paused = true; game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "complete" and game.state.hand == WIN and game.state.worn == 1,
		"the finished errand reloads with the player's own packages and the look he chose")
	check(game.state == on_disk, "the reload is byte-for-byte the booked state")
	game.toggle_wear()
	check(game.state.worn == 0, "the look can be tucked away again after a reload")
	game.toggle_wear()
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.worn == 1 and game.state.stage == "complete", "the voluntary appearance flag persists across reload")
	game.queue_free(); await process_frame
	var mid = pose(WIN, "delivery")
	var writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(mid)); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "delivery" and not game.modal, "an unfinished sewing resumes instead of vanishing")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the resumed sewing can be paused or skipped again")
	check(Rules.validate(game.state), "the resumed stage is still a legal save")
	check(not game.buttons.has("open_hub") and not game.buttons.has("back_hub"), "a running sewing keeps the way out for later")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose(WIN, "story", 0, 1))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "story" and game.state.beat == 1, "her story resumes on the line the player stopped at")
	check(game.buttons.has("next") and game.buttons.next.text == "再听一句", "the half-told story offers to go on")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose(TENS, "complete"))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.modal and game.repository.protected and game.state.stage == "arrival",
		"a receipt written without 11 段 is protected and the scene reopens clean")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose(FLIPPED, "complete"))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.modal and game.repository.protected, "a receipt of 11 cells that miss the fold is read as corruption")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose(WIN, "puzzle", 1))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.repository.protected, "a counter wearing the mended edge is read as corruption")
	game.recover_protected()
	check(not game.modal and game.state.stage == "arrival", "keeping the old file and starting over is the only way through")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose(OVERFLOW, "puzzle"))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.repository.protected, "13 段 written onto an 11-cell gauge is corruption, not a wider ruler")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string("{broken"); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken", "a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose(WIN, "complete", 1))); writer.close()
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"), "arriving from the chart offers only the way back")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin != "hub" and game.buttons.has("open_hub"), "a standalone sample still finds a way back to the chart")
	var door: Button = game.buttons.open_hub
	check(door.position == Vector2(690, 646) and door.size == Vector2(280, 54), "the way out keeps the chapter's own rect")
	check(game.buttons.has("next") and game.buttons.next.text == "再补一次", "the receipt still offers to redo the errand")
	game.confirm_restart()
	check(game.modal and game.state.stage == "complete", "replaying the scene asks first")
	game.close_modal()
	check(game.state.hand == WIN and game.state.worn == 1, "cancelling keeps the scarf the player mended")
	game.queue_free(); await process_frame
	# ---- 目录一致性：支线不挡主线 ----
	check(Catalog.scene("MK13") == "res://game/market_mk13.tscn", "the catalogue points at the shipped scene")
	check(Catalog.save_path("MK13") == SAVE_DEFAULT, "the catalogue save path is the one this level writes")
	check(Catalog.LEVELS["MK13"].kit == "nursery", "the catalogue keeps mk13 on the nursery kit scene")
	check(Catalog.opens_after("MK13") == "MK04", "the errand opens after 扣扣 is cleared")
	check(Catalog.is_side("MK13") and Catalog.SIDE.has("MK13") and not Catalog.MAIN.has("MK13"), "mk13 is a side quest and never gates the main line")
	check(Catalog.act("MK13") == 2 and Catalog.act_name("MK13") == "扣扣没有偷东西", "mk13 belongs to the second act's aftermath")
	check(Catalog.goal("MK13") == "整包摊满对折样边尺的 11 格，且对折两头齐", "the catalogue goal states both asks of the redesign")
	check(ResourceLoader.exists(Catalog.scene("MK13")), "the chart can now light mk13 instead of 尚未制作")
	check(Catalog.built("MK13") and Catalog.available("MK13", ["MK04"]), "mk13 opens once mk04 is lit")
	check(not Catalog.available("MK13", []), "mk13 stays closed before mk04")
	check(Catalog.next_main(["MK01", "MK02", "MK03", "MK04"]) == "MK05", "the main line asks for mk05 after mk04")
	check(Catalog.next_main(["MK01", "MK02", "MK03", "MK04", "MK13"]) == "MK05",
		"clearing the side quest never changes what the main line asks for")
	DirAccess.remove_absolute(path)
	print("MARKET MK13 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

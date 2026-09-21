extends SceneTree
# 无头规则检查：MK08「多出来的三瓶油」。不开窗口、不碰 user://，
# 所有写档都落在 /tmp 的一次性路径上；实窗审计由集成者另跑 window_focus。
const Rules = preload("res://scripts/market/mk08_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Scene = preload("res://game/market_mk08.tscn")
const KOUKOU = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const START = [[0, 6, 1], [1, 4, 1], [0, 6, 1]]
# 只把总数拨成 13：重复的红单还在板上，漏掉的绿单还是没上来。
const TRAP = [[0, 6, 1], [1, 4, 1], [0, 3, 1]]
const SOLVED = [[0, 6, 1], [1, 4, 1], [2, 3, 1]]
var checks = 0
var failures = 0
var face: FontFile
var path = "/tmp/pixel-mk08-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 一份可存档的现场：filing 之后板面与归档记录必须一致，由这里守住这个不变式。
func build(lines: Array, stage: String = "puzzle") -> Dictionary:
	var state = Rules.fresh()
	state.stage = stage
	state.lines = lines.duplicate(true)
	state.filed = lines.duplicate(true) if stage in ["filing", "delivery", "complete"] else Rules.empty_lines()
	return state

# 一行能有的写法：撤下（空行），或某张单的抄件按 1..8 件、按箱或按瓶记。
func row_options() -> Array:
	var options: Array = [[-1, 0, Rules.UNIT_BOTTLE]]
	for order in range(Rules.ORDERS):
		for count in range(1, Rules.MAX_COUNT + 1):
			for unit in [Rules.UNIT_BOX, Rules.UNIT_BOTTLE]:
				options.append([order, count, unit])
	return options

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

# 世界层的木牌走 draw_string，字号原样生效，不做 18/22/28 的抬升。
func carves(text: String, size_px: int, box: float) -> bool:
	return width(text, size_px) <= box

# 一件货画出来占多大，只由 manifest 的裁剪尺寸与 anchor_px 决定：这里照 kit() 的算法独立量一遍，
# 不去取绘制层算好的矩形——不然排版错在哪里，量出来的框就跟着错在哪里。
func sprite_box(node: Node, part: String, foot: Vector2, drawn: float) -> Rect2:
	var texture: Texture2D = node.atlases[part]
	var scale: float = drawn / texture.get_width()
	var anchor = node.parts[part]["anchor_px"]
	return Rect2(foot - Vector2(anchor[0], anchor[1]) * scale,
		Vector2(texture.get_width(), texture.get_height()) * scale)

func block_height(text: String, requested: int) -> float:
	var size_px = UIStyle.text_size(requested)
	var rows = text.split("\n").size()
	return rows * face.get_height(size_px) + (rows - 1) * 5

func settle(game: Node) -> void:
	game.transient = 0.0
	game.refresh()

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK08 rule watchdog"); quit(1))
	# ---- 1. 开局现场与字段 ----
	check(Rules.validate(Rules.fresh()), "fresh model validates")
	check(Rules.fresh().sample == "market-mk08-1", "fresh carries the mk08 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens on the arrival beats")
	check(Rules.fresh().lines == START, "the board arrives already wrong: 红6、蓝4、红6")
	check(Rules.fresh().filed == Rules.empty_lines(), "nothing is filed before the submit passes")
	check(Rules.fresh().hint == 0, "hints start unused")
	check(Rules.fresh().keys().size() == 6, "the profile carries exactly the six frozen fields")
	check(Rules.NAMES == ["红单", "蓝单", "绿单"] and Rules.BOXES == [2, 0, 1] and Rules.LOOSE == [0, 4, 0],
		"the three real tickets are 红单 2 箱、蓝单 4 散瓶、绿单 1 箱")
	check(Rules.PER_BOX == 3 and Rules.BOOKED == 16 and Rules.RECEIVED == 13,
		"每箱 3 瓶：板上 16 瓶对上码头实收 13 瓶")
	check([Rules.bottles_of(0), Rules.bottles_of(1), Rules.bottles_of(2)] == [6, 4, 3],
		"the tickets hold 6, 4 and 3 bottles")
	check(Rules.bottles_of(0) + Rules.bottles_of(1) + Rules.bottles_of(2) == Rules.RECEIVED,
		"the three real tickets are exactly what the dock received")
	check(Rules.total_of(START) == Rules.BOOKED and Rules.total_of(SOLVED) == Rules.RECEIVED,
		"totals are computed from the board, never stored")
	check(Rules.note(0) == "2 箱 × 每箱 3 瓶" and Rules.note(1) == "4 散瓶" and Rules.note(2) == "1 箱 × 每箱 3 瓶",
		"each ticket is described in its own notation")
	# ---- 2. 穷举：整块板只有一种摆法算对上账 ----
	var options = row_options()
	var probe_state = Rules.fresh()
	probe_state.stage = "puzzle"
	var legal = 0
	var hits: Array = []
	var thirteen = 0
	var thirteen_wrong = 0
	var disagreements = 0
	for a in options:
		for b in options:
			for c in options:
				var sheet = [a, b, c]
				if not Rules.legal_board(sheet): continue
				legal += 1
				probe_state.lines = sheet
				if Rules.total_of(sheet) == Rules.RECEIVED:
					thirteen += 1
					if not Rules.solved(probe_state): thirteen_wrong += 1
				if Rules.solved(probe_state) != (sheet == Rules.SOLUTION): disagreements += 1
				if Rules.solved(probe_state): hits.append(sheet)
	check(disagreements == 0, "solved agrees with the hand-derived account on all "+str(legal)+" boards")
	check(legal > 100000, "the enumeration covers the whole reachable board space")
	check(hits == [Rules.SOLUTION], "exactly one board arrangement passes: 红6、蓝4、绿3 全按瓶记")
	check(thirteen > 10 and thirteen_wrong == thirteen - 1,
		"every other 13-bottle arrangement still fails: 凑总数修不好这本账")
	# ---- 3. 阶段机 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "the arrival lines play in order")
	for step in range(Rules.BEATS - 2): arriving = Rules.advance(arriving)
	check(arriving.beat == Rules.BEATS - 1 and Rules.advance(arriving).stage == "approach",
		"the last line walks 扣扣 up to the counter")
	var walked = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(walked.stage == "puzzle" and walked.lines == START and walked.filed == Rules.empty_lines(),
		"approach and ready never touch the board")
	check(walked.beat == 0, "the beat counter is home again outside the arrival")
	check(not (walked.stage in Rules.ANIMATIONS), "puzzle is not an animation stage")
	var single = true
	for stage in Rules.STAGES:
		if stage in ["arrival", "complete"]: continue
		var moved = Rules.advance(build(SOLVED, stage))
		if moved.is_empty(): single = false; continue
		if moved.stage != Rules.STAGES[Rules.STAGES.find(stage) + 1]: single = false
	check(single, "advance only ever moves one stage forward")
	check(Rules.advance(build(START)).is_empty(), "the untouched board cannot be filed")
	check(Rules.advance(build([[0, 6, 1], [1, 4, 1], [-1, 0, 1]])).is_empty(), "an empty row blocks the filing")
	check(Rules.advance(build([[0, 6, 1], [1, 4, 1], [2, 1, 0]])).is_empty(), "a row still written in boxes blocks it")
	check(Rules.advance(build(TRAP)).is_empty(), "the total-corrected trap cannot be filed")
	var filed = Rules.advance(build(SOLVED))
	check(filed.stage == "filing" and filed.filed == SOLVED and filed.lines == SOLVED,
		"submit files the whole board in one go")
	check(Rules.advance(filed).stage == "delivery" and Rules.advance(filed).filed == SOLVED,
		"the hand-over does not re-file anything")
	check(Rules.advance(Rules.advance(filed)).stage == "complete", "the stamped board closes the scene")
	check(Rules.advance(build(SOLVED, "complete")).is_empty(), "complete has no next stage")
	# ---- 4. 钉单、撤行、拨数、换算 ----
	var start_state = build(START)
	for stage in ["arrival", "approach", "ready", "filing", "delivery", "complete"]:
		var locked = build(SOLVED, stage)
		check(Rules.pin(locked, 2).is_empty() and Rules.unpin(locked, 0).is_empty()
			and Rules.bump(locked, 0, 1).is_empty() and Rules.convert(locked, 0).is_empty(),
			"the board is frozen during "+stage)
	check(Rules.pin(Rules.fresh(), 2).is_empty(), "no pin before the board opens")
	check(Rules.pin(start_state, -1).is_empty() and Rules.pin(start_state, Rules.ORDERS).is_empty(),
		"unknown order numbers are refused")
	check(Rules.pin(start_state, 0).is_empty() and Rules.pin(start_state, 1).is_empty(),
		"a ticket already on the board cannot be pinned twice")
	var freed = Rules.unpin(start_state, 2)
	check(freed.lines == [[0, 6, 1], [1, 4, 1], [-1, 0, 1]] and freed.filed == Rules.empty_lines(),
		"撤下一行只改板面，正式记录还是空的")
	check(start_state.lines == START, "the previous state is left untouched")
	check(Rules.total_of(freed.lines) == 10, "putting the copy back takes its six bottles off the total")
	var green = Rules.pin(freed, 2)
	check(green.lines == [[0, 6, 1], [1, 4, 1], [2, 1, 0]],
		"a fresh copy keeps the ticket's own units: 绿单 arrives as 1 箱")
	check(Rules.pin(green, 0).is_empty() and Rules.pin(green, 2).is_empty(),
		"a full board refuses every pin: 先撤下一行")
	var aligned = Rules.convert(green, 2)
	check(aligned.lines == SOLVED and Rules.validate(aligned), "换算把 1 箱写成 3 瓶")
	check(Rules.convert(aligned, 2).lines[2] == [2, 1, 0], "换算往回走也说得通：3 瓶又是 1 箱")
	check(Rules.convert(aligned, 1).is_empty() and not Rules.can_convert(aligned, 1),
		"4 散瓶装不满整箱，只能按瓶记")
	check(Rules.can_convert(aligned, 0) and Rules.convert(aligned, 0).lines[0] == [0, 2, 0],
		"6 瓶能写成 2 箱：换的是写法，货没变")
	check(Rules.bump(Rules.unpin(start_state, 0), 0, 1).is_empty(), "an empty row has nothing to bump")
	var seven = Rules.bump(aligned, 0, 1)
	check(seven.lines[0] == [0, 7, 1] and Rules.total_of(seven.lines) == 14,
		"bumping one row moves the whole total at once")
	check(Rules.can_bump(seven, 0, 1) and Rules.bump(seven, 0, 1).lines[0] == [0, 8, 1]
		and Rules.can_bump(seven, 0, -1),
		"7 瓶还能再加一件：8 件是板面画得到的最多")
	var maxed = build([[0, 8, 1], [1, 4, 1], [2, 3, 1]])
	check(Rules.bump(maxed, 0, 1).is_empty(), "a ninth item is refused")
	check(not Rules.can_convert(maxed, 0), "8 瓶换算成箱会越过画得下的最多件数")
	var minned = build([[0, 1, 1], [1, 4, 1], [2, 3, 1]])
	check(Rules.bump(minned, 0, -1).is_empty(), "a row never drops to zero: 整行不要就撤下")
	check(Rules.bump(minned, 0, 2).is_empty() and Rules.bump(minned, 0, 0).is_empty()
		and Rules.bump(minned, -1, 1).is_empty() and Rules.bump(minned, 3, 1).is_empty(),
		"only single steps on real rows are legal")
	check(Rules.unpin(start_state, -1).is_empty() and Rules.unpin(start_state, Rules.LINES).is_empty()
		and Rules.convert(start_state, 9).is_empty(),
		"rows outside the board are refused")
	var wiped = start_state
	while not wiped.is_empty() and Rules.total_of(wiped.lines) > 0:
		for row in range(Rules.LINES):
			var step = Rules.unpin(wiped, row)
			if not step.is_empty(): wiped = step
	check(wiped.lines == Rules.empty_lines() and Rules.total_of(wiped.lines) == 0,
		"taking every row down leaves no phantom total")
	check(Rules.validate(wiped) and Rules.shortfalls(wiped).size() == 6,
		"an empty board still validates and names all six missing records")
	# ---- 5. 提交反馈：错在哪一行就说哪一行 ----
	var empty = Rules.shortfalls(wiped)
	check(empty[0] == "汇总板第 1 行还空着：三张原单各钉一行。" and empty.size() == 6,
		"empty rows are named one by one, row number included")
	var dup = Rules.shortfalls(build(START))
	check(dup.size() == 2 and "第 3 行的红单是重复抄件" in dup[0] and "绿单一次都没上板" in dup[1],
		"the shipped board names the duplicate copy and the missing ticket")
	check(Rules.total_of(START) == 16 and "16" not in dup[0] + dup[1],
		"the complaints talk about records, not about the headline total")
	var trap = Rules.shortfalls(build(TRAP))
	check(trap.size() == 3 and Rules.total_of(TRAP) == 13 and "第 3 行" in trap[0] and "绿单" in trap[1],
		"16 改成 13 只算凑数：重复、漏单与改掉的瓶数一起被点名")
	var blank = Rules.shortfalls(build([[0, 6, 1], [1, 4, 1], [-1, 0, 1]]))
	check(blank.size() == 2 and "第 3 行还空着" in blank[0] and "绿单一次都没上板" in blank[1],
		"撤下重复却不补回，两处都指出来")
	var boxed = Rules.shortfalls(build([[0, 6, 1], [1, 4, 1], [2, 1, 0]]))
	check(boxed == ["第 3 行记的是 1 箱：箱不是瓶，先换算成瓶再记。"],
		"a 13-bottle board still fails while one row is in boxes")
	var count = Rules.shortfalls(build([[0, 6, 1], [1, 4, 1], [2, 1, 1]]))
	check(count == ["第 3 行写着 1 瓶，绿单实际是 3 瓶（1 箱 × 每箱 3 瓶）。"],
		"a wrong count quotes the ticket's own notation")
	var mixed = Rules.shortfalls(build([[0, 2, 0], [1, 4, 1], [2, 3, 1]]))
	check(mixed.size() == 1 and "第 1 行记的是 2 箱" in mixed[0],
		"红单留在箱上时也是单位问题：没统一到瓶就不算完")
	var swapped = Rules.shortfalls(build([[2, 3, 1], [1, 4, 1], [0, 6, 1]]))
	check(swapped == ["第 1 行钉的是绿单：汇总板按红、蓝、绿的单号顺序记。"],
		"the right three records in the wrong rows are refused by row number")
	var two = Rules.shortfalls(build([[1, 4, 1], [0, 6, 1], [2, 3, 1]]))
	check(two == ["第 1 行钉的是蓝单：汇总板按红、蓝、绿的单号顺序记。"], "one swap is reported once, not three times")
	var both = Rules.shortfalls(build([[0, 4, 1], [1, 4, 1], [0, 3, 1]]))
	check(both.size() == 4 and "重复抄件" in both[0] and "绿单" in both[1]
		and "第 1 行写着 4 瓶" in both[2] and "第 3 行写着 3 瓶" in both[3],
		"a duplicate, a missing ticket and two wrong counts are four separate duties")
	check(Rules.shortfalls(build(SOLVED)).is_empty() and Rules.solved(build(SOLVED)),
		"the unique arrangement has no shortfall")
	# ---- 6. 撤销快照 ----
	var snap = {"lines": START.duplicate(true), "filed": Rules.empty_lines()}
	check(Rules.restore(green, snap).lines == START, "undo rewinds a pin")
	check(Rules.restore(build(START), {"lines": SOLVED.duplicate(true), "filed": Rules.empty_lines()}).lines == SOLVED,
		"undo can also put a whole board back")
	check(Rules.restore(Rules.convert(green, 2), {"lines": green.lines, "filed": Rules.empty_lines()}).lines == green.lines,
		"undo rewinds a conversion")
	check(Rules.restore(Rules.bump(build(SOLVED), 0, 1), snap).lines == START, "undo rewinds a bumped count")
	var every = 0
	for order in range(Rules.ORDERS):
		var prior = Rules.unpin(build(START), order)
		var after = Rules.pin(prior, order)
		if after.is_empty(): continue
		if Rules.restore(after, {"lines": prior.lines, "filed": prior.filed}).lines != prior.lines: every += 1
		var flipped = Rules.convert(after, Rules.LINES - 1)
		if not flipped.is_empty():
			if Rules.restore(flipped, {"lines": after.lines, "filed": after.filed}).lines != after.lines: every += 1
	check(every == 0, "every pin and conversion round-trips through the undo snapshot")
	check(Rules.restore(build(START, "arrival"), snap).is_empty(), "undo only works at the board")
	check(Rules.restore(build(SOLVED, "filing"), snap).is_empty(), "undo cannot reopen a filed record")
	check(Rules.restore(build(SOLVED, "complete"), snap).is_empty(), "undo cannot reach back from the receipt")
	check(Rules.restore(build(SOLVED), {"lines": SOLVED.duplicate(true)}).is_empty(),
		"a snapshot without the filing record is refused")
	check(Rules.restore(build(SOLVED), {"lines": START.duplicate(true), "filed": START.duplicate(true)}).is_empty(),
		"undo refuses a snapshot that carries a filed board")
	check(Rules.restore(build(SOLVED), {"lines": [[0, 9, 1], [1, 4, 1], [2, 3, 1]], "filed": Rules.empty_lines()}).is_empty(),
		"undo refuses an out-of-range count")
	check(Rules.restore(build(SOLVED), {"lines": [[0, 6, 2], [1, 4, 1], [2, 3, 1]], "filed": Rules.empty_lines()}).is_empty(),
		"undo refuses an unknown unit")
	check(Rules.restore(build(SOLVED), {"lines": [[3, 6, 1], [1, 4, 1], [2, 3, 1]], "filed": Rules.empty_lines()}).is_empty(),
		"undo refuses an order that does not exist")
	check(Rules.restore(build(SOLVED), {"lines": [[0, 6, 1], [1, 4, 1]], "filed": Rules.empty_lines()}).is_empty(),
		"undo refuses a two-row board")
	# ---- 7. 存档 schema：越界、错长、非整数、阶段不一致全部拒收 ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record "+str(bad))
	var piece = build(SOLVED); piece.sample = "market-mk07-1"
	check(not Rules.validate(piece), "a foreign sample is rejected")
	piece = build(SOLVED); piece.stage = "auditing"
	check(not Rules.validate(piece), "an unknown stage is rejected")
	piece = build(SOLVED); piece.erase("lines")
	check(not Rules.validate(piece), "a missing board is corruption, not a default")
	piece = build(SOLVED); piece.erase("filed")
	check(not Rules.validate(piece), "a missing filing record is corruption")
	piece = build(SOLVED); piece.lines[0][0] = 3
	check(not Rules.validate(piece), "an order number off the rack is rejected")
	piece = build(SOLVED); piece.lines[0][0] = -2
	check(not Rules.validate(piece), "-2 is not a way to say an empty row")
	piece = build(SOLVED); piece.lines[0] = [0, 6]
	check(not Rules.validate(piece), "a short row is corruption")
	piece = build(SOLVED); piece.lines.remove_at(1)
	check(not Rules.validate(piece), "the board is exactly three rows long")
	piece = build(SOLVED); piece.lines[0][1] = 1.5
	check(not Rules.validate(piece), "a fractional count is corruption")
	piece = build(SOLVED); piece.lines[0][2] = "瓶"
	check(not Rules.validate(piece), "a string unit is corruption")
	piece = build(SOLVED); piece.lines[0][1] = 0
	check(not Rules.validate(piece), "a pinned row cannot carry zero items")
	piece = build(SOLVED); piece.lines[0][1] = 9
	check(not Rules.validate(piece), "counts above the board are rejected")
	piece = build(SOLVED); piece.lines[2] = [-1, 3, 1]
	check(not Rules.validate(piece), "an empty row with a count is a phantom total")
	piece = build(SOLVED); piece.lines[2] = [2, 3, 2]
	check(not Rules.validate(piece), "an unknown unit is rejected")
	piece = build([[0, 6, 1], [0, 6, 1], [0, 6, 1]])
	check(not Rules.validate(piece), "three copies of one ticket exceed the drawer")
	piece = build(SOLVED); piece.hint = Rules.HINTS + 1
	check(not Rules.validate(piece), "hint level is capped")
	piece = build(SOLVED); piece.hint = -1
	check(not Rules.validate(piece), "hints cannot go negative")
	piece = build(SOLVED); piece.beat = 2
	check(not Rules.validate(piece), "a stashed arrival beat outside the arrival is corruption")
	piece = Rules.fresh(); piece.beat = Rules.BEATS
	check(not Rules.validate(piece), "arrival beats are bounded")
	piece = build(SOLVED, "puzzle"); piece.filed = SOLVED.duplicate(true)
	check(not Rules.validate(piece), "the board cannot hold a filed record mid-placement")
	piece = build(START, "puzzle"); piece.filed = START.duplicate(true)
	check(not Rules.validate(piece), "a broken board cannot be filed even while it is still on the table")
	piece = build(START, "arrival"); piece.lines = SOLVED.duplicate(true)
	check(not Rules.validate(piece), "the walk-in cannot carry a fixed board")
	piece = build(START, "filing")
	check(not Rules.validate(piece), "filing a board that was never fixed is a forged receipt")
	piece = build(TRAP, "complete")
	check(not Rules.validate(piece), "the total-corrected trap cannot close the scene")
	piece = build(SOLVED, "complete"); piece.lines = [[0, 6, 1], [1, 4, 1], [2, 1, 0]]
	check(not Rules.validate(piece), "a clear whose rows still say boxes is rejected")
	piece = build(SOLVED, "delivery"); piece.filed = [[0, 6, 1], [1, 4, 1], [-1, 0, 1]]
	check(not Rules.validate(piece), "the filing record cannot be swapped mid-hand-over")
	piece = build(SOLVED, "arrival")
	check(not Rules.validate(piece), "arrival cannot be replayed with the answer already on the board")
	check(Rules.validate(build(SOLVED)), "the fixed board at the counter is a legal save")
	check(Rules.validate(build(SOLVED, "filing")), "a staged filing is a legal save")
	check(Rules.validate(build(SOLVED, "delivery")), "the stamped hand-over is a legal save")
	check(Rules.validate(build(SOLVED, "complete")), "the cleared scene is a legal save")
	check(Rules.validate(wiped), "the emptied board is still a legal save")
	var capped = build(SOLVED); capped.hint = Rules.HINTS
	check(Rules.validate(capped), "the top hint tier is inside the bound")
	# ---- 8. 章节目录与本关身份 ----
	var entry = Catalog.LEVELS["MK08"]
	check(entry.title == "多出来的三瓶油", "the catalog title is the level title")
	check(entry.scene == "res://game/market_mk08.tscn", "the catalog points at the shipped scene path")
	check(ResourceLoader.exists(entry.scene) and Catalog.built("MK08"), "the scene file exists so the chart lights up")
	check(entry.save == "user://profiles/market-mk08-1/save-v1.json", "the catalog save path is the mk08 profile")
	check(entry.kit == "street" and entry.act == 4 and entry.after == "MK07",
		"act 4, street kit, opens after MK07")
	check(entry.goal == "对齐单位，撤下重复副本、补回漏掉的单号", "the chart states both duties")
	check(Catalog.MAIN.has("MK08") and Catalog.opens_after("MK08") == "MK07",
		"MK08 sits on the main line behind MK07")
	check(Catalog.LEVELS["MK09"].after == "MK08", "MK09 is still gated behind this scene")
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == Catalog.save_path("MK08"), "configure only fills the catalog save path as a default")
	check(probe.scene_id == "street" and probe.level_id == "MK08", "the scene declares its own identity")
	check(probe.rules == Rules and probe.world_script.resource_path.ends_with("mk08_world.gd"),
		"the host is wired to mk08")
	check(probe.durations.has("filing") and probe.durations.has("delivery"), "the host owns the stage durations")
	check(fits(probe.goal_line(), 22, 762.0) and probe.goal_line().split("\n").size() == 1,
		"the goal board holds its one line")
	probe.free()
	# ---- 9. 真实场景：热点、按钮、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.save_path == path, "an injected test path survives configure")
	check(game.state.stage == "arrival", "a new profile opens on the arrival beats")
	check(game.buttons.has("next") and game.buttons["next"].text == "继续听他们说",
		"the first beat only asks to keep listening")
	for step in range(Rules.BEATS - 1): game.advance()
	check(game.state.stage == "arrival" and game.state.beat == Rules.BEATS - 1, "the four beats play out")
	check(game.buttons["next"].text == "走到柜台前", "the last beat offers the walk-in")
	game.advance(); game.skip_animation()
	check(game.state.stage == "ready" and game.buttons.has("next"), "ready waits for the player")
	game.advance(); settle(game)
	check(game.state.stage == "puzzle" and game.state.lines == START, "the board opens exactly as 衡伯 left it")
	check(game.buttons.has("deliver") and game.buttons.deliver.text == "重新归档这块板",
		"submit is one re-filing of the whole board")
	check(game.buttons.has("undo") and game.buttons.undo.disabled, "undo is idle before the first click")
	check(game.status_line() == "板上 16 瓶 · 码头实收 13 瓶", "the counter states the mismatch it does not fix")
	var rects: Array = []
	var present = 0
	for order in range(Rules.ORDERS):
		if game.buttons.has("pin_%d" % order): present += 1
		rects.append(game.world.ticket_rect(order))
	for row in range(Rules.LINES):
		for id in ["chip", "less", "more", "unit"]:
			if game.buttons.has("%s_%d" % [id, row]): present += 1
			rects.append(game.world.call(id + "_rect", row))
	check(present == Rules.ORDERS + Rules.LINES * 4, "all three tickets and twelve row controls are live")
	var small = 0
	var outside = 0
	var overlap = 0
	var crowded = 0
	for rect in rects:
		if rect.size.x < 48 or rect.size.y < 48: small += 1
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 720: outside += 1
		if rect.end.y > 646: crowded += 1
	for first in range(rects.size()):
		for second in range(first + 1, rects.size()):
			if rects[first].intersects(rects[second]): overlap += 1
	check(small == 0, "every drop target is at least 48x48 logical pixels")
	check(outside == 0, "every hit target stays inside the 1280x720 frame")
	check(overlap == 0, "no two hit targets overlap")
	check(crowded == 0, "no hit target reaches into the bottom command bar")
	game.do_unpin(2); settle(game)
	check(game.state.lines == [[0, 6, 1], [1, 4, 1], [-1, 0, 1]] and not game.buttons.undo.disabled,
		"撤下 the duplicate red copy: its six bottles leave the board")
	check(game.status_line() == "板上 10 瓶 · 码头实收 13 瓶", "the total drops with the row, no phantom left")
	game.do_pin(2); settle(game)
	check(game.state.lines[2] == [2, 1, 0] and game.status_line() == "板上 13 瓶 · 码头实收 13 瓶",
		"绿单 comes back written in boxes: same total, wrong units")
	check(game.world.land_place == "line" and game.world.land_slot == 2,
		"only the freshly pinned row gets the drop-in landing")
	game.do_pin(0); settle(game)
	check(game.state.lines[2] == [2, 1, 0] and "已经钉在板上" in game.message,
		"a second 红单 is refused with the reason, not silence")
	game.message = ""
	game.advance()
	check(game.state.stage == "puzzle" and game.message == "第 3 行记的是 1 箱：箱不是瓶，先换算成瓶再记。",
		"submit refuses the unaligned row and names it")
	game.message = ""; game.do_convert(2); settle(game)
	check(game.state.lines == SOLVED and Rules.solved(game.state), "换算 finishes the board")
	game.undo(); settle(game)
	check(game.state.lines[2] == [2, 1, 0], "undo rewinds the conversion through the host")
	game.undo(); settle(game); game.undo(); settle(game); game.undo(); settle(game)
	check(game.state.lines == START and game.history.is_empty(), "the rewind consumes every recorded step")
	game.do_bump(0, 1); settle(game)
	check(game.state.lines[0] == [0, 7, 1] and game.status_line() == "板上 17 瓶 · 码头实收 13 瓶",
		"one bump moves the headline total")
	game.message = ""; game.do_convert(0); settle(game)
	check(game.state.lines[0] == [0, 7, 1] and "装不满整箱" in game.message,
		"7 瓶换算不了：只有整箱的倍数写得出箱")
	game.message = ""; game.do_bump(0, -1); settle(game); game.do_convert(0); settle(game)
	check(game.state.lines[0] == [0, 2, 0] and game.status_line() == "板上 16 瓶 · 码头实收 13 瓶",
		"换算 keeps the goods: 6 瓶 written as 2 箱")
	game.do_reset()
	check(game.state.lines == Rules.empty_lines() and game.state.stage == "puzzle",
		"重摆 clears the board without leaving the counter")
	var cleared = game.cleared_state()
	check(cleared.lines == Rules.empty_lines() and cleared.stage == "puzzle" and Rules.validate(cleared),
		"cleared_state empties the three rows and keeps the stage")
	var source = build(SOLVED)
	var shot = game.snapshot(source)
	shot.lines[0] = [2, 8, 1]
	check(shot.lines != source.lines and source.lines == SOLVED,
		"snapshot() copies both the board and the filing record without aliasing them")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "open"; game.do_pin(0)
	check(game.modal and game.state.lines == Rules.empty_lines() and FileAccess.get_file_as_bytes(path) == bytes,
		"a failed board save keeps the last written board untouched")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(not game.modal and game.state.lines[0] == [0, 2, 0], "retry republishes the same board")
	game.do_unpin(0); settle(game); game.do_unpin(1); settle(game); game.do_unpin(2); settle(game)
	game.message = ""
	check(Rules.total_of(game.state.lines) == 0 and game.status_line() == "板上 0 瓶 · 码头实收 13 瓶",
		"an emptied board reads zero on the counter")
	game.handle_key(KEY_1); settle(game); game.handle_key(KEY_2); settle(game)
	game.handle_key(KEY_3); settle(game); game.handle_key(KEY_D); settle(game)
	check(game.state.lines == [[0, 2, 0], [1, 4, 1], [2, 3, 1]],
		"the keyboard path pins all three tickets and converts the first row")
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and "第 1 行记的是 2 箱" in game.message,
		"the keyboard path still has to align every row")
	game.handle_key(KEY_A); settle(game)
	check(game.state.lines == SOLVED, "keyboard 换算 finishes the alignment")
	game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINTS and "第 3 行做个样子" in game.message,
		"the third hint demonstrates one conversion")
	game.hint()
	check(game.state.hint == Rules.HINTS and Rules.validate(game.state), "hints stop at the shipped tier count")
	check(game.hint_texts().size() == Rules.HINTS, "the hint bound matches the shipped hint count")
	var third = game.hint_texts()[2]
	check("撤下" not in third and "绿单" not in third, "the last hint shows a step without giving the pairing")
	var solved_state = build(SOLVED); solved_state.hint = game.state.hint
	game.commit(solved_state); settle(game)
	game.repository.fail_at = "flush"; game.advance()
	check(game.modal and game.state.stage == "puzzle" and game.state.filed == Rules.empty_lines(),
		"a failed filing save cannot file anything")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(game.state.stage == "filing" and game.state.filed == SOLVED, "retry files the whole board once")
	check(game.buttons.has("skip") and game.buttons.has("pause"), "the filing can be paused or skipped")
	var plan = game.world.filing_plan(0.25)
	check(plan.size() == 2 and game.world.hide_while_moving(plan).size() == 2,
		"only the changed row flies: one copy out, one copy in")
	check(game.world.copying_in(2, plan) and not game.world.copying_in(0, plan),
		"the flying copy is not drawn twice on the board")
	# 两半张抄件都在前半程落位；后半程整段 phase 都夹在 1.0，还报「在空中」的话
	# `draw_board()` 会为空中那一份把整行让出来，归档动画有一半时长板上是缺货的。
	var landed = game.world.filing_plan(0.60)
	check(landed.is_empty() and game.world.hide_while_moving(landed).is_empty()
		and not game.world.line_goods(2, game.world.board()).is_empty(),
		"抄件一落定，改过那一行的货样就跟着回到板面上")
	game.skip_animation(); settle(game)
	check(game.state.stage == "delivery", "the board is handed over to the dock")
	game.world.progress = 0.2
	check(game.world.stamped(0.2).size() == 1 and game.world.stamped(1.0).size() == Rules.LINES,
		"the stamps land row by row")
	check(game.world.dock_count() == 6 and game.world.dock_count() < Rules.BOOKED,
		"the dock count climbs with the stamped rows, never with the old 16")
	# 托盘上摆的就是那张单里的 13 瓶：盖讫进行中只写「点收 6 瓶」，像是在说码头只到了 6 瓶。
	var stamp_board: Array = []
	for ticket in game.world.signs():
		if str(ticket["text"]).begins_with("码头"): stamp_board = [str(ticket["text"]), ticket["rect"]]
	check(stamp_board[0] == "码头 · 点收中 6/13 瓶",
		"盖讫进行中的那块牌把「已点收」和「实收总数」分开报")
	check(carves(stamp_board[0], 16, stamp_board[1].size.x - 20),
		"这条进度读数在牌面上不换行")
	game.skip_animation(); settle(game)
	check(game.state.stage == "complete" and game.world.dock_count() == Rules.RECEIVED,
		"the stamped board closes with 13 bottles handed over")
	check(game.state.filed == SOLVED and game.buttons["next"].text == "重新体验", "the cleared scene keeps its record")
	check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
		"a standalone sample keeps its own way back to the chart")
	var on_disk = game.state.duplicate(true)
	# ---- 10. 木牌、回执、台词与重画 ----
	var spill = 0
	var boards = 0
	for stage in Rules.STAGES:
		var look = Rules.fresh() if stage == "arrival" else build(SOLVED, stage)
		game.world.state = look
		for ticket in game.world.signs():
			boards += 1
			if not carves(ticket["text"], 16, ticket["rect"].size.x - 20): spill += 1
	check(spill == 0, "all "+str(boards)+" stall boards hold their own text at every stage")
	var receipt = game.receipt_lines()
	var narrow = 0
	for line in receipt:
		if not fits(line, 16, game.receipt_text_rect().size.x): narrow += 1
	check(narrow == 0 and receipt.size() == 7, "the filing receipt fits its panel and restates the filed board")
	check("红单 2 箱 = 6 瓶" in receipt and "绿单 1 箱 = 3 瓶" in receipt, "the receipt quotes the tickets, not the copy")
	check("撤下重复抄件 1 张" in receipt and "补回漏掉的单号 1 个" in receipt,
		"the receipt counts what the player actually changed")
	check(block_height("\n".join(receipt), 16) <= game.receipt_text_rect().size.y + 8,
		"the receipt block stays inside its panel")
	var lines_ok = true
	for stage in Rules.STAGES:
		game.state = Rules.fresh() if stage == "arrival" else build(SOLVED, stage)
		if not fits(game.line(), 20, 798.0) or game.line().split("\n").size() > 2: lines_ok = false
		if not fits(game.goal_line(), 22, 762.0): lines_ok = false
		if not fits(game.status_line(), 20, 300.0): lines_ok = false
		if not fits(game.submit_label(), 20, 215.0): lines_ok = false
		for hint in game.hint_texts():
			if not fits(hint, 20, 798.0) or hint.split("\n").size() > 2: lines_ok = false
	check(lines_ok, "every spoken, goal, status, submit and hint line fits its board without auto-wrapping")
	var drawn = 0
	for stage in Rules.STAGES:
		var looks: Array = []
		if stage == "arrival": looks.append(Rules.fresh())
		elif stage in ["approach", "ready"]: looks.append(build(START, stage))
		elif stage == "puzzle": looks.append(build(START)); looks.append(build(SOLVED))
		else: looks.append(build(SOLVED, stage))
		for look in looks:
			check(Rules.validate(look), "the repaint walk carries a legal save at "+stage)
			game.apply_committed(look, [])
			for at in [0.0, 0.5, 1.0]:
				game.paused = true; game.world.progress = at
				game.refresh()
				game.world.notification(CanvasItem.NOTIFICATION_DRAW)
			drawn += 1
	game.paused = false
	check(drawn == 8 and is_instance_valid(game.world) and not game.modal,
		"every stage and both boards repaint without breaking")
	var tipped = 0
	for row in range(Rules.LINES):
		if game.world.row_foot(row).y > 620 or game.world.row_foot(row).y < 170: tipped += 1
		if game.world.line_goods(row, SOLVED).is_empty(): tipped += 1
		if game.world.chip_rect(row).intersects(game.world.ticket_rect(row)): tipped += 1
	check(tipped == 0, "the three rows sit between the spoken board and the command bar")
	# ---- 板上那一排货样就是题面：木牌最后画、底色不透明，货压在牌底下等于把要数的件数藏掉半截。
	# 每一种合法写法都量一遍（三行 × 箱/瓶 × 1..8 件），比对的是当帧画出来的全部牌面。
	var buried = 0
	var layouts = 0
	for row in range(Rules.LINES):
		for unit in [Rules.UNIT_BOX, Rules.UNIT_BOTTLE]:
			for tally in range(1, Rules.MAX_COUNT + 1):
				var look = Rules.empty_lines()
				look[row] = [row, tally, unit]
				game.world.state = build(look)
				var planks: Array = []
				for ticket in game.world.signs(): planks.append(ticket["rect"])
				# 一行的货只许长在这一行自己的底条上，爬到行外或板外都算越界。
				var strip = Rect2(game.world.row_foot(row) - Vector2(40, 34), Vector2(730, 48))
				layouts += 1
				for item in game.world.line_goods(row, look):
					var box = sprite_box(game.world, item["kit"], item["at"], item["w"])
					if not strip.encloses(box):
						buried += 1
						print("OUTSIDE row ", row + 1, " ", tally, " 件 ",
							item["kit"], " ", box, " strip ", strip)
					for board in planks:
						if board.intersects(box):
							buried += 1
							print("BURIED row ", row + 1, " ", tally, " 件 ",
								item["kit"], " ", box, " under ", board)
	check(buried == 0, "all "+str(layouts)+" ways of writing a row count out clear of every sign")
	# 扣扣 0.5 倍身位有 163 宽：puzzle 那一档镜头推到 1.10 倍、往左上抬 (64,43)，
	# 站位再往左半个身子就要被窗框切掉。按宿主自己算出来的镜头量，不另抄一遍缩放常数。
	game.apply_committed(build(SOLVED), [])
	var body = Vector2(KOUKOU.get_width(), KOUKOU.get_height()) * 0.5
	var stand = Rect2(game.world.koukou_foot() - Vector2(body.x / 2.0, body.y), body)
	var zoomed = stand.position.x * game.world.scale.x + game.world.position.x
	game.apply_committed(build(SOLVED, "complete"), []); settle(game)
	var flat = stand.position.x * game.world.scale.x + game.world.position.x
	check(absf(game.world.scale.x - 1.0) < 0.002 and zoomed >= 8.0 and flat >= 8.0,
		"both cameras leave 扣扣 whole: her left edge stays inside the window frame")
	# ---- 11. 重开、航图交棒与坏档保护 ----
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state == on_disk and game.state.stage == "complete" and game.state.hint == Rules.HINTS,
		"the filed board reloads from disk exactly as filed")
	Bridge.origin = "hub"
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
		"finishing from the chart returns to the chart")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")	# 注入 flush 故障时留下的临时文件
	print("MARKET MK08 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

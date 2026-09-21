extends SceneTree
# MK10「无论回哪封信」的无头规则检查：纸面预测、约定选择与本局结算三件事必须各自成立。
# 检查只用 /tmp 下的落点，绝不去碰 user:// 里的玩家存档。
const Rules = preload("res://scripts/market/mk10_rules.gd")
const SceneScript = preload("res://scripts/market/mk10_scene.gd")
const World = preload("res://scripts/market/mk10_world.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Scene = preload("res://game/market_mk10.tscn")
const BOARD = 798.0
const GOAL_BOARD = 762.0
const STATUS_BOARD = 300.0
const MODAL_BOARD = 560.0
const LAND_TIME = 0.28
var checks = 0
var failures = 0
var face: FontFile
var path = "/tmp/pixel-mk10-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 真实量一次：Godot 不会在汉字串中间断行，超框就是画到框外。
func wide(text: String, requested: int) -> float:
	return face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(requested)).x

func fits(text: String, requested: int, box: float) -> bool:
	var ok = true
	for line in text.split("\n"):
		if wide(line, requested) > box: ok = false
	return ok

# 一份现场：结算阶段的 paid 必须等于本局那一张订单的票额，由 build 守住这个不变式。
func build(written: Array, boat: int, stage: String = "puzzle", branch: int = 3, beat: int = 0) -> Dictionary:
	var state = Rules.fresh(branch)
	state.stage = stage
	state.beat = beat
	state.written = written.duplicate()
	state.boat = boat
	state.paid = Rules.fare(boat, branch) if stage in Rules.SETTLED else 0
	return state

# 照某条约定把两种可能都算对的那张纸。
func sheet(boat: int, stage: String = "puzzle", branch: int = 3, beat: int = 0) -> Dictionary:
	return build(Rules.fares(boat), boat, stage, branch, beat)

# 走完整幕：返回经过的阶段与最后那份状态。
func walk_to_end(state: Dictionary) -> Dictionary:
	var trail = [state.stage]
	var guard = 0
	while state.stage != "complete" and guard < 24:
		state = Rules.advance(state)
		guard += 1
		if state.is_empty(): break
		trail.append(state.stage)
	return {"trail": trail, "final": state}

# 落下动画只影响手感：清掉 it 再重画，热点的可用状态才与实窗一致。
func settle(game: Node) -> void:
	game.transient = 0.0
	game.world.land_progress = 1.0
	game.refresh()

func write_raw(value: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string(value); file.close()

# ---- 遮挡审计：世界层画在哪一块、宿主压住哪一块，两边都只向运行时问一次 ----

# 按拆件包自己的 anchor 公式独立推出「这块画面在世界上占哪一格」：
# 裁剪图尺寸与锚点取自 manifest（世界层 _ready 时读进来的那一份），脚点与宽度取自关卡给的值。
func kit_box(world: Node, id: String, foot: Vector2, width: float) -> Rect2:
	var texture: Texture2D = world.atlases[id]
	var item: Dictionary = world.parts[id]
	var scale = width / texture.get_width()
	return Rect2(foot - Vector2(item.anchor_px[0], item.anchor_px[1]) * scale,
		Vector2(texture.get_width(), texture.get_height()) * scale)

# 宿主与关卡自己压在场景上的不透明木牌：位置问 Panel 自己，投影问它正在用的那块 StyleBoxFlat。
# 检查里不出现第二个 (338,98)，宿主把台词板改高改矮都会立刻被这里读到。
# skip 是把被考察的那块自己排掉——不然回执面板永远和它自己重叠。
func host_boards(game: Node, skip: Array = []) -> Array:
	var slabs: Array = []
	for child in game.ui.get_children():
		if not (child is Panel): continue
		var body: Rect2 = child.get_global_rect()
		if skip.has(body): continue
		var style: StyleBox = child.get_theme_stylebox("panel")
		if style is StyleBoxFlat and style.shadow_size > 0:
			# 牌面的投影是半透明的：落在上面只是被压暗，落在牌面上才是真的看不见。
			slabs.append({"solid": body, "dimmed": body.merge(
				Rect2(body.position + style.shadow_offset, body.size).grow(style.shadow_size))})
		else:
			slabs.append({"solid": body, "dimmed": body})
	return slabs

# 世界层的一块画面投到当前这一格画面上：变换读的是宿主刚设好的那一份，镜头怎么动都不再手算。
# world 与 ui 都挂在关卡根节点的原点上，所以两边量的是同一套 1280x720 逻辑坐标。
func on_screen(world: Node, box: Rect2) -> Rect2:
	var placed: Transform2D = world.get_transform()
	return Rect2(placed * box.position, box.size * placed.get_scale())

# 一块画面被这一排木牌最多盖掉多大比例。
func buried(placed: Rect2, slabs: Array, key: String) -> float:
	var area = maxf(placed.get_area(), 0.001)
	var worst = 0.0
	for slab in slabs:
		var part = placed.intersection(slab[key])
		if part.size.x > 0 and part.size.y > 0:
			worst = maxf(worst, part.get_area() / area)
	return worst

# 一批画面块里被盖得最狠的那一块：[压在牌面上的比例, 连投影一起算的比例]。
func worst_burial(boxes: Array, slabs: Array) -> Array:
	var solid = 0.0
	var dimmed = 0.0
	for box in boxes:
		solid = maxf(solid, buried(box, slabs, "solid"))
		dimmed = maxf(dimmed, buried(box, slabs, "dimmed"))
	return [solid, dimmed]

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("MK10 rule watchdog"); quit(1))
	face = UIStyle.face()
	# ---- 1. 开局现场：两种可能与两条约定都公开 ----
	check(Rules.validate(Rules.fresh(3)), "fresh model validates")
	check(Rules.fresh(3).sample == "market-mk10-1", "fresh carries the mk10 sample id")
	check(Rules.fresh(3).stage == "arrival" and Rules.fresh(3).beat == 0, "fresh opens at the arrival beats")
	check(Rules.fresh(3).written == [-1, -1], "both order cells start blank")
	check(Rules.fresh(3).boat == -1 and Rules.fresh(3).paid == 0, "no bargain chosen and no ticket spent")
	check(Rules.fresh(3).hint == 0, "hints start unused")
	check(Rules.fresh(3).keys().size() == 8, "the profile carries exactly the eight frozen fields")
	check(Rules.CASES == [3, 6] and Rules.SLOTS == 2, "the two public cases are 3 boxes and 6 boxes")
	check(Rules.BUDGET == 10, "this job can raise ten tickets at most")
	check(Rules.SAIL == [0, 4] and Rules.PER_BOX == [2, 1], "red charges per box, blue charges a sail fee plus per box")
	check(Rules.fares(0) == [6, 12] and Rules.fares(1) == [7, 10], "both published tariffs are public from the first frame")
	check(not Rules.covers(0) and Rules.covers(1), "only the blue bargain covers both cases")
	check(Rules.uncovered_case(0) == 1 and Rules.uncovered_case(1) == -1, "the failing case is nameable")
	check(Rules.tariff_lines(0) == ["红船", "没有开船票", "每箱 2 票"], "the red boat board reads its own tariff")
	check(Rules.tariff_lines(1) == ["蓝船", "开船 4 票", "每箱 1 票"], "the blue boat board reads its own tariff")
	check(Rules.slip_text(-1) == "还没写" and Rules.slip_text(7) == "7 票", "blank paper reads as blank")
	check(Rules.TILE_VALUES == [-1, 4, 6, 7, 10, 12] and Rules.TILES == 6,
		"the slip tray holds the four true fares plus the blank and the sail-fee miscount")
	check(Rules.legal_written([-1, -1]) and Rules.legal_written([4, 12]) and not Rules.legal_written([5, 10])
		and not Rules.legal_written([7]) and not Rules.legal_written("x"), "the slip field is bounded by the tray")
	check(Rules.legal_boat(-1) and Rules.legal_boat(1) and not Rules.legal_boat(2) and not Rules.legal_boat(-2)
		and not Rules.legal_boat(1.0), "the bargain field only holds blank or one of the two boats")
	# ---- 2. 分支在开局固定，读档绝不重抽 ----
	var rolled = Rules.fresh(); var again = Rules.fresh()
	check(rolled.branch != again.branch and rolled.branch + again.branch == 9,
		"two new playthroughs alternate between the two orders")
	check(Rules.validate(rolled) and Rules.validate(again), "either fixed branch is a legal save")
	check(Rules.fresh(6).branch == 6 and Rules.fresh(3).branch == 3, "a named branch is honoured verbatim")
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh(6))))
	check(Rules.validate(round_trip) and round_trip.branch == 6 and round_trip.written == [-1, -1],
		"the branch survives a JSON round trip untouched")
	check(round_trip.written[0] is int and round_trip.branch is int, "blank slips stay integers on disk")
	# ---- 3. 穷举：纸面解唯一，且与「本局抽到哪一单」无关 ----
	var verdicts = []
	for boat in range(Rules.BOATS):
		for left in Rules.CANDIDATES:
			for right in Rules.CANDIDATES:
				var written = [left, right]
				var drawn_small = build(written, boat, "puzzle", 3)
				var drawn_large = build(written, boat, "puzzle", 6)
				if Rules.solved(drawn_small) != Rules.solved(drawn_large): verdicts.append("branch-sensitive")
				if Rules.solved(drawn_small): verdicts.append([boat, written])
	check(verdicts.size() == 1, "exactly one paper plan clears, and no verdict depends on the drawn order")
	check(verdicts[0] is Array and verdicts[0][0] == 1 and verdicts[0][1] == [7, 10],
		"the unique plan is the blue boat with 7 and 10")
	var red_trap = build([6, 12], 0, "puzzle", 3)
	check(Rules.fare(0, 3) <= Rules.BUDGET, "the red boat really can pay for the three-box order")
	check(not Rules.solved(red_trap) and Rules.advance(red_trap).is_empty(),
		"being able to pay the drawn order does not count as a solution")
	check(Rules.written_matches(red_trap) and not Rules.covers(red_trap.boat),
		"arithmetically correct slips are still not a plan that covers both cases")
	check(Rules.fares(1).max() <= Rules.BUDGET and Rules.fares(0).max() > Rules.BUDGET,
		"the ceiling itself is what separates the two bargains")
	check(Rules.plan_ok(sheet(1)) and not Rules.plan_ok(red_trap), "plan_ok is the both-cases test")
	check(Rules.paid_for(build([7, 10], 1)) == 7 and Rules.paid_for(build([7, 10], 1, "puzzle", 6)) == 10,
		"the settled payment is read off the confirmed order")
	# ---- 4. 阶段机 ----
	var arriving = Rules.advance(Rules.fresh(3))
	check(arriving.beat == 1 and arriving.stage == "arrival", "arrival plays its lines in order")
	arriving = Rules.advance(arriving)
	check(arriving.beat == 2 and Rules.advance(arriving).stage == "approach", "the third line walks the player onto the dock")
	check(Rules.ARRIVAL_BEATS == 3, "three opening lines")
	var walked = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(walked.stage == "puzzle" and walked.written == [-1, -1] and walked.boat == -1, "walk-in never touches the paper")
	check(not (walked.stage in Rules.ANIMATIONS), "puzzle is not an animation stage")
	check(Rules.ANIMATIONS == ["approach", "confirming", "delivery"], "the three animations are the ones this scene draws")
	var forward = true
	for stage in Rules.STAGES:
		if stage in ["arrival", "clarify", "complete"]: continue
		var before = sheet(1, stage)
		var moved = Rules.advance(before)
		if moved.is_empty(): forward = false; continue
		if moved.stage != Rules.STAGES[Rules.STAGES.find(stage) + 1]: forward = false
		if moved.branch != before.branch: forward = false
	check(forward, "advance only ever moves one stage forward and never re-rolls the branch")
	var clarified = sheet(1, "clarify", 3, 0)
	check(Rules.advance(clarified).beat == 1 and Rules.advance(Rules.advance(clarified)).beat == 2,
		"the clarification plays beat by beat")
	check(Rules.advance(Rules.advance(Rules.advance(clarified))).stage == "delivery", "the last line lets the boat leave")
	check(Rules.CLARIFY_BEATS == 3, "three clarification lines")
	for stuck in [build([-1, -1], -1), build([6, 12], 0), build([7, 10], 0), build([7, -1], 1),
			build([4, 4], 1), build([-1, 10], 1), build([4, 10], 1), build([12, 6], 1)]:
		check(Rules.advance(stuck).is_empty(), "submit refuses paper that does not add up: "
			+ str(stuck.written) + " on boat " + str(stuck.boat))
	check(Rules.advance(build([7, 10], 1, "complete")).is_empty(), "complete has no next stage")
	var booked = Rules.advance(sheet(1, "puzzle", 3))
	check(booked.stage == "confirming" and booked.paid == 7, "submit settles the real cost of the confirmed order")
	check(booked.written == [7, 10] and booked.boat == 1, "the paper plan is kept as what was promised")
	var onward = Rules.advance(booked)
	check(onward.stage == "clarify" and onward.paid == 7 and onward.beat == 0, "the settlement carries through the dialogue")
	var large = walk_to_end(sheet(1, "puzzle", 6))
	check(large.trail == ["puzzle", "confirming", "clarify", "clarify", "clarify", "delivery", "complete"],
		"the six-box branch runs the same board to the end")
	check(large.final.paid == 10 and Rules.validate(large.final), "the six-box branch settles at ten tickets")
	var small_walk = walk_to_end(sheet(1, "puzzle", 3))
	check(small_walk.trail == large.trail and small_walk.final.paid == 7,
		"both branches reach the same verdict with their own payment")
	check(Rules.advance(build([7, 10], 1, "delivery", 6)).paid == 10, "the carry does not re-settle anything")
	for stage in Rules.SETTLED:
		var frozen = sheet(1, stage)
		check(Rules.mark_case(frozen, 0, 4).is_empty() and Rules.choose_boat(frozen, 0).is_empty()
			and Rules.clear_boat(frozen).is_empty(), "the paper freezes once the story confirms: " + stage)
	# ---- 5. 摆票与选船：一张票都不动 ----
	var board = build([-1, -1], -1)
	check(Rules.mark_case(Rules.fresh(3), 0, 7).is_empty(), "no slip before the board opens")
	check(Rules.mark_case(board, -1, 7).is_empty() and Rules.mark_case(board, Rules.SLOTS, 7).is_empty(),
		"unknown order cells are refused")
	check(Rules.mark_case(board, 0, 5).is_empty() and Rules.mark_case(board, 0, 0).is_empty()
		and Rules.mark_case(board, 0, 99).is_empty() and Rules.mark_case(board, 1, 13).is_empty(),
		"a number off the tray cannot be written")
	var marked = Rules.mark_case(board, 0, 7)
	check(marked.written == [7, -1] and marked.paid == 0, "writing a slip only writes the paper")
	check(board.written == [-1, -1], "the previous state is left untouched")
	var wiped = Rules.mark_case(marked, 0, Rules.UNWRITTEN)
	check(wiped.written == [-1, -1] and wiped.paid == 0 and Rules.validate(wiped),
		"the blank slip erases the cell and nothing was spent")
	check(Rules.mark_case(marked, 0, 7).is_empty(), "writing the same number twice is a no-op")
	check(Rules.can_mark(marked, 0, 4) and not Rules.can_mark(marked, 0, 7), "a cell reports whether a slip would change it")
	check(Rules.choose_boat(Rules.fresh(3), 0).is_empty(), "no bargain before the board opens")
	check(Rules.choose_boat(board, -1).is_empty() and Rules.choose_boat(board, Rules.BOATS).is_empty()
		and Rules.choose_boat(board, 3).is_empty(), "unknown boats are refused")
	var chosen = Rules.choose_boat(board, 0)
	check(chosen.boat == 0 and chosen.paid == 0, "choosing the red boat is a paper note, not a payment")
	check(Rules.choose_boat(chosen, 0).boat == -1, "clicking the chosen boat again clears the note")
	check(Rules.can_clear_boat(chosen) and not Rules.can_clear_boat(board), "clearing is offered only while a bargain stands")
	var swapped = Rules.choose_boat(chosen, 1)
	check(swapped.boat == 1 and swapped.paid == 0 and swapped.written == [-1, -1],
		"switching bargains leaves no phantom cost and no half-written plan")
	var shuffle = board
	for turn in range(9): shuffle = Rules.choose_boat(shuffle, turn % Rules.BOATS)
	check(shuffle.paid == 0 and shuffle.written == Rules.empty_written() and Rules.validate(shuffle),
		"any number of bargain changes keeps all ten tickets in the box")
	for stage in ["arrival", "approach", "ready", "confirming", "clarify", "delivery", "complete"]:
		var locked = sheet(1, stage)
		check(Rules.mark_case(locked, 0, 4).is_empty() and Rules.choose_boat(locked, 0).is_empty(),
			"the paper board is frozen during " + stage)
	# ---- 6. 撤销快照 ----
	var snap = {"written": [7, 10], "boat": 1, "paid": 0}
	check(Rules.restore(Rules.mark_case(sheet(1), 0, 4), snap).written == [7, 10], "undo rewinds a written cell")
	check(Rules.restore(Rules.choose_boat(sheet(1), 0), snap).boat == 1, "undo rewinds a bargain switch")
	var rewound = 0
	for slot in range(Rules.SLOTS):
		for value in Rules.TILE_VALUES:
			var prior = build([7, 10], 1)
			prior.written[slot] = Rules.UNWRITTEN
			var after = Rules.mark_case(prior, slot, value)
			if after.is_empty(): continue
			var back = Rules.restore(after, {"written": prior.written, "boat": prior.boat, "paid": 0})
			if back.is_empty() or back.written != prior.written or back.paid != 0: rewound += 1
	check(rewound == 0, "every slip in reach round-trips through the undo snapshot")
	for stage in ["arrival", "approach", "ready", "confirming", "clarify", "delivery", "complete"]:
		check(Rules.restore(sheet(1, stage), snap).is_empty(), "undo only works at the paper board, not in " + stage)
	check(Rules.restore(sheet(1), {"written": [7, 10], "boat": 1}).is_empty(), "a snapshot without the paid record is refused")
	check(Rules.restore(sheet(1), {"boat": 1, "paid": 0}).is_empty(), "a snapshot without the slips is refused")
	check(Rules.restore(sheet(1), {"written": [7, 10], "paid": 0}).is_empty(), "a snapshot without the bargain is refused")
	check(Rules.restore(sheet(1), {"written": [7, 10], "boat": 1, "paid": 0, "branch": 6}).is_empty(),
		"the confirmed branch is never part of an undo snapshot")
	check(Rules.restore(sheet(1), {"written": [5, 10], "boat": 1, "paid": 0}).is_empty(),
		"undo refuses a number off the tray")
	check(Rules.restore(sheet(1), {"written": [7], "boat": 1, "paid": 0}).is_empty(), "undo refuses a short sheet")
	check(Rules.restore(sheet(1), {"written": [7, 10], "boat": 7, "paid": 0}).is_empty(), "undo refuses an unknown boat")
	check(Rules.restore(sheet(1), {"written": [7, 10], "boat": 1, "paid": 7}).is_empty(),
		"undo refuses a snapshot that carries a payment back onto the board")
	check(Rules.restore(build([7, -1], 1), {"written": [-1, -1], "boat": 1, "paid": 0}).written == [-1, -1],
		"undo can also wipe a slip again")
	# ---- 7. 交单反馈：点名是哪一种可能 ----
	check(Rules.shortfalls(board) == ["还没选定运输约定：红船与蓝船的收费都贴在码头上。"],
		"a plan without a bargain is refused before anything else")
	check(Rules.shortfalls(build([7, -1], 1))[0] == "「运 6 箱」那一格还空着：两种可能都要写在纸上。",
		"an empty cell names the order it belongs to")
	check(Rules.shortfalls(build([-1, 10], 1))[0].length() > 0, "the other cell can be the one that is blank")
	check(Rules.shortfalls(build([4, 10], 1))[0] == "3 箱那格写 4 票，蓝船按约定是 7 票。",
		"the sail-fee-only miscount is corrected with the right fare")
	check(Rules.shortfalls(build([7, 12], 1))[0] == "6 箱那格写 12 票，蓝船按约定是 10 票。",
		"the doubled per-box miscount is corrected the same way")
	var over = Rules.shortfalls(build([6, 12], 0))
	check(over.size() == 1 and over[0] == "红船运 6 箱要 12 票，比 10 票多 2 票：盖不住两种可能。",
		"the red boat trap names the case that breaks the ceiling")
	var mixed = Rules.shortfalls(build([7, 10], 0))
	check(mixed.size() == 3 and "3 箱那格写 7 票" in mixed[0] and "盖不住两种可能" in mixed[2],
		"a blue plan on the red boat is three separate duties")
	check(Rules.shortfalls(sheet(1)).is_empty() and Rules.solved(sheet(1)), "the unique plan has no shortfall")
	var tail_spill = 0
	for boat in range(-1, Rules.BOATS):
		for left in Rules.TILE_VALUES:
			for right in Rules.TILE_VALUES:
				var missing = Rules.shortfalls(build([left, right], boat))
				if missing.is_empty(): continue
				var tail = ("（还有 %d 处没有归位）" % (missing.size() - 1)) if missing.size() > 1 else ""
				if not fits(missing[0] + tail, 20, BOARD): tail_spill += 1
	check(tail_spill == 0, "every submit refusal, with the host's tail, still fits one spoken line")
	# ---- 8. 存档 schema：越界与阶段不一致都是损坏 ----
	for bad in [null, {}, [], "x", 5.0, [0, 0], 3]: check(not Rules.validate(bad), "reject record " + str(bad))
	var piece = sheet(1); piece.sample = "market-mk06-1"
	check(not Rules.validate(piece), "a foreign sample is rejected")
	piece = sheet(1); piece.sample = "market-mk10-2"
	check(not Rules.validate(piece), "another schema of this level is not read as this one")
	piece = sheet(1); piece.stage = "shopping"
	check(not Rules.validate(piece), "an unknown stage is rejected")
	piece = sheet(1); piece.erase("stage")
	check(not Rules.validate(piece), "a missing stage is corruption")
	piece = sheet(1); piece.beat = -1
	check(not Rules.validate(piece), "negative beats are rejected")
	piece = sheet(1); piece.beat = Rules.CLARIFY_BEATS
	check(not Rules.validate(piece), "beats are bounded by the longest dialogue")
	piece = sheet(1); piece.beat = 1.5
	check(not Rules.validate(piece), "a fractional beat is corruption")
	piece = sheet(1); piece.erase("beat")
	check(not Rules.validate(piece), "a missing beat is corruption")
	piece = build([-1, -1], -1, "arrival", 3, Rules.ARRIVAL_BEATS)
	check(not Rules.validate(piece), "arrival beats cannot run past their own lines")
	piece = build([-1, -1], -1, "ready", 3, 1)
	check(not Rules.validate(piece), "only the two dialogue stages carry a beat")
	piece = sheet(1, "clarify", 3, Rules.CLARIFY_BEATS)
	check(not Rules.validate(piece), "clarify stops at its last line")
	piece = sheet(1); piece.hint = Rules.HINT_TIERS + 1
	check(not Rules.validate(piece), "hint level is capped")
	piece = sheet(1); piece.hint = -1
	check(not Rules.validate(piece), "hints cannot go negative")
	piece = sheet(1); piece.erase("branch")
	check(not Rules.validate(piece), "a save without the confirmed order is corruption")
	piece = sheet(1); piece.branch = 4
	check(not Rules.validate(piece), "a branch outside the two public cases is corruption")
	piece = sheet(1); piece.branch = 12
	check(not Rules.validate(piece), "a box count nobody ordered is corruption")
	piece = sheet(1); piece.branch = 3.0
	check(not Rules.validate(piece), "a fractional branch is corruption")
	piece = sheet(1); piece.branch = "3"
	check(not Rules.validate(piece), "a string branch is corruption")
	piece = sheet(1); piece.written = [7]
	check(not Rules.validate(piece), "a short slip array is corruption")
	piece = sheet(1); piece.written = [7, 10, 6]
	check(not Rules.validate(piece), "an overlong slip array is corruption")
	piece = sheet(1); piece.written = []
	check(not Rules.validate(piece), "an empty slip array is corruption")
	piece = sheet(1); piece.written[0] = 5
	check(not Rules.validate(piece), "a fare off the tray is corruption")
	piece = sheet(1); piece.written[1] = 8
	check(not Rules.validate(piece), "an invented fare is corruption")
	piece = sheet(1); piece.written[0] = 1.5
	check(not Rules.validate(piece), "a fractional fare is corruption")
	piece = sheet(1); piece.written[1] = "10"
	check(not Rules.validate(piece), "a string fare is corruption")
	piece = sheet(1); piece.erase("written")
	check(not Rules.validate(piece), "a missing field is corruption, not a default")
	piece = sheet(1); piece.boat = -2
	check(not Rules.validate(piece), "a bargain below blank is rejected")
	piece = sheet(1); piece.boat = Rules.BOATS
	check(not Rules.validate(piece), "a boat that never sailed is rejected")
	piece = sheet(1); piece.boat = "1"
	check(not Rules.validate(piece), "a string bargain is corruption")
	piece = sheet(1); piece.erase("boat")
	check(not Rules.validate(piece), "a missing bargain is corruption")
	piece = sheet(1); piece.paid = -1
	check(not Rules.validate(piece), "negative payment is rejected")
	piece = sheet(1); piece.paid = Rules.BUDGET + 1
	check(not Rules.validate(piece), "a payment above the ceiling is rejected")
	piece = sheet(1); piece.paid = 1.0
	check(not Rules.validate(piece), "a fractional payment is corruption")
	piece = sheet(1); piece.erase("paid")
	check(not Rules.validate(piece), "a missing payment record is corruption")
	piece = sheet(1, "puzzle"); piece.paid = 7
	check(not Rules.validate(piece), "the board cannot hold a paid record")
	for stage in ["arrival", "approach", "ready"]:
		piece = sheet(1, stage)
		check(not Rules.validate(piece), stage + " cannot carry a written plan")
		piece = build([-1, -1], 1, stage)
		check(not Rules.validate(piece), stage + " cannot carry a chosen bargain")
	piece = build([-1, -1], -1, "arrival", 3, 0); piece.paid = 3
	check(not Rules.validate(piece), "nothing is spent before the player reaches the board")
	piece = build([6, 12], 0, "complete")
	check(not Rules.validate(piece), "a clear on a bargain that cannot cover both cases is corruption")
	piece = build([6, 12], 0, "delivery")
	check(not Rules.validate(piece), "the red boat cannot be sailing this order")
	piece = build([7, 7], 1, "confirming")
	check(not Rules.validate(piece), "a confirmed plan must match the published tariff")
	piece = build([-1, -1], 1, "clarify")
	check(not Rules.validate(piece), "a confirmation with blank slips is a forged receipt")
	piece = sheet(1, "complete", 3); piece.paid = 10
	check(not Rules.validate(piece), "paying the other order's fare is corruption")
	piece = sheet(1, "complete", 6); piece.paid = 7
	check(not Rules.validate(piece), "under-paying the six-box order is corruption")
	piece = sheet(1, "confirming"); piece.erase("hint")
	check(not Rules.validate(piece), "the hint counter is part of the schema")
	check(Rules.validate(sheet(1)), "the paper plan is a legal save")
	check(Rules.validate(build([7, 10], 1, "puzzle", 3)) and Rules.validate(build([7, 10], 1, "puzzle", 6)),
		"the same plan is legal whichever order the story will confirm")
	check(Rules.validate(sheet(1, "confirming")) and Rules.validate(sheet(1, "clarify", 3, 2)),
		"a staged confirmation is a legal save")
	check(Rules.validate(sheet(1, "delivery", 6)) and Rules.validate(sheet(1, "complete", 6)),
		"the sailing boat carries the six-box settlement")
	var capped = sheet(1); capped.hint = Rules.HINT_TIERS
	check(Rules.validate(capped), "the top hint tier is inside the bound")
	# ---- 9. 章节目录与本关身份 ----
	var entry = Catalog.LEVELS["MK10"]
	check(entry.scene == "res://game/market_mk10.tscn", "the catalog points at the shipped scene path")
	check(ResourceLoader.exists(entry.scene) and Catalog.built("MK10"), "the scene file exists so the chart lights up")
	check(entry.save == "user://profiles/market-mk10-1/save-v1.json", "the catalog save path is the mk10 profile")
	check(entry.kit == "dock" and entry.act == 4 and entry.after == "MK09", "act 4, dock kit, opens after MK09")
	check(entry.title == "无论回哪封信", "the catalog title is the level title")
	check(entry.goal == "选一条能同时覆盖两种订单箱数的船", "the catalog goal is the two-case ceiling")
	check(Catalog.MAIN.has("MK10") and Catalog.opens_after("MK10") == "MK09", "MK10 sits on the main line")
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == Catalog.save_path("MK10"), "configure only fills the catalog save path as a default")
	check(probe.scene_id == "dock" and probe.level_id == "MK10", "the scene declares its own identity")
	check(probe.title == Catalog.title("MK10"), "the window title matches the catalog")
	check(probe.rules == Rules and probe.world_script.resource_path.ends_with("mk10_world.gd"), "the host is wired to mk10")
	check(probe.durations.has("confirming") and probe.durations.has("delivery"), "the host owns the stage durations")
	check(probe.hint_texts().size() == Rules.HINT_TIERS, "the hint bound matches the shipped hint count")
	check(SceneScript.TILE_KEYS.size() == Rules.TILES and SceneScript.BOAT_KEYS.size() == Rules.BOATS
		and SceneScript.CELL_KEYS.size() == Rules.SLOTS, "the keyboard map covers exactly the clickable set")
	probe.free()
	# ---- 10. 真实场景：热点、纸面、结算与落盘 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.save_path == path, "an injected test path survives configure")
	check(game.state.stage == "arrival" and game.state.branch in Rules.CASES, "a new profile opens on the arrival beats")
	check(game.world.land_place == "", "nothing lands before the player acts")
	check(game.buttons.has("next") and game.buttons["next"].text == "继续听他们说", "the first beat only asks to keep listening")
	check(fits(game.line(), 20, BOARD), "the arrival line fits the spoken board")
	check(fits(game.goal_line(), 22, GOAL_BOARD), "the goal board fits one line")
	game.advance(); game.advance(); game.advance()
	check(game.state.stage == "approach", "the third line starts the walk-in")
	game.skip_animation(); settle(game)
	check(game.state.stage == "ready" and game.buttons["next"].text == "开始摆票额", "ready offers the way to the board")
	game.advance(); settle(game)
	check(game.state.stage == "puzzle", "the board opens with both orders and both boats public")
	check(game.buttons.has("deliver") and game.buttons["deliver"].text == "按这条约定交单", "submit hands the plan over the chosen bargain")
	check(game.buttons.has("undo") and game.buttons["undo"].disabled, "undo is idle before the first slip")
	var absent = 0
	for boat in range(Rules.BOATS):
		if not game.buttons.has("boat_%d" % boat): absent += 1
	for slot in range(Rules.SLOTS):
		if not game.buttons.has("case_%d" % slot): absent += 1
	for index in range(Rules.TILES):
		if not game.buttons.has("tile_%d" % index): absent += 1
	check(absent == 0, "both boats, both order cells and all six slips are clickable")
	var rects = []
	for boat in range(Rules.BOATS):
		rects.append(game.world.boat_rect(boat))
	for slot in range(Rules.SLOTS):
		rects.append(game.world.cell_rect(slot))
	for index in range(Rules.TILES):
		rects.append(game.world.tile_rect(index))
	var small = 0
	var outside = 0
	var overlap = 0
	for rect in rects:
		if rect.size.x < 48 or rect.size.y < 48: small += 1
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 720: outside += 1
	for lead in range(rects.size()):
		for follow in range(lead + 1, rects.size()):
			if rects[lead].intersects(rects[follow]): overlap += 1
	check(small == 0, "every hit target is at least 48x48 logical pixels")
	check(outside == 0, "every hit target stays inside the 1280x720 frame")
	check(overlap == 0, "no two hit targets overlap")
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and "还没选定运输约定" in game.message, "handing in without a bargain is refused")
	game.do_choose(0)
	check(game.state.boat == 0 and game.state.paid == 0, "picking the red boat spends nothing")
	check(game.world.land_place == "boat" and game.world.land_slot == 0, "the new bargain is landed by the host")
	check(is_equal_approx(game.transient, LAND_TIME), "the level leaves the 0.28 s lock to the host")
	settle(game)
	game.do_pick(0); settle(game)
	check(game.world.picked == 0 and fits(game.message, 20, BOARD), "picking an order cell says which one is being written")
	game.do_mark(6); settle(game)
	check(game.state.written == [6, -1] and game.world.land_place == "slip" and game.world.land_slot == 0,
		"a slip lands on the cell it was written into")
	game.do_pick(1); settle(game); game.do_mark(12); settle(game)
	check(game.state.written == [6, 12] and game.state.boat == 0, "the red boat plan is written out completely")
	check(game.world.tickets_left() == Rules.BUDGET and game.world.paid_tickets() == 0,
		"even the trap plan leaves all ten tickets in the box")
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and game.message == "红船运 6 箱要 12 票，比 10 票多 2 票：盖不住两种可能。",
		"the red boat is refused by naming the six-box case")
	game.message = ""; game.do_mark(12)
	check("已经写着" in game.message, "the same slip cannot be laid twice")
	game.do_choose(1); settle(game)
	check(game.state.boat == 1 and game.state.written == [6, 12] and game.state.paid == 0,
		"switching bargains keeps the slips and spends nothing")
	check("重算" in game.message, "switching bargains asks for the slips to be recomputed")
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and "3 箱那格写 6 票，蓝船按约定是 7 票。" in game.message,
		"a blue plan written over the red tariff is corrected case by case")
	check(game.handle_key(KEY_1) and game.handle_key(KEY_R), "keys 1 and R pick a cell and lay a slip")
	settle(game)
	check(game.state.written == [7, 12], "the keyboard path writes into the picked cell")
	check(not game.handle_key(KEY_Z), "the undo key belongs to the host")
	game.do_pick(1); settle(game); game.do_mark(10); settle(game)
	check(game.state.written == [7, 10] and game.state.boat == 1, "the unique plan is reachable by clicking")
	check(game.status_line() == "蓝船 7/10 票 · 限 10", "the status bar computes both cases live")
	check(game.world.tickets_left() == Rules.BUDGET, "reaching the plan still spends nothing")
	game.do_choose(1); settle(game)
	check(game.state.boat == -1 and game.state.written == [7, 10], "clearing the bargain does not wipe the paper")
	game.do_choose(1); settle(game)
	check(game.state.boat == 1 and game.state.paid == 0, "choosing it again costs nothing")
	game.do_reset(); settle(game)
	check(game.state.written == [-1, -1] and game.state.boat == -1 and game.state.paid == 0
		and game.state.stage == "puzzle", "重摆 wipes only the paper")
	var branch_before = game.state.branch
	game.undo(); settle(game)
	check(game.state.written == [7, 10] and game.state.boat == 1 and game.state.branch == branch_before,
		"undo rewinds the wipe without touching the confirmed order")
	var paper_snapshot = game.snapshot(game.state)
	check(paper_snapshot.keys().size() == 3 and not paper_snapshot.has("branch"),
		"an undo snapshot holds the paper only")
	game.hint(); settle(game); game.hint(); settle(game); game.hint(); settle(game)
	check(game.state.hint == Rules.HINT_TIERS and "顶穿上限" in game.message, "the third hint points at the ceiling")
	game.hint(); settle(game)
	check(game.state.hint == Rules.HINT_TIERS and Rules.validate(game.state), "hints stop at the shipped tier count")
	check(game.snapshot(game.state) == paper_snapshot, "a hint never moves the paper or the payment")
	var paper = game.state.duplicate(true)
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle" and game.state.paid == 0, "a save failure cannot settle the order")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(game.state.stage == "confirming" and game.state.written == paper.written, "retry then settles the plan the player wrote")
	check(game.state.paid == Rules.fare(1, game.state.branch) and game.state.paid in [7, 10],
		"the settled payment is the confirmed order's fare")
	check(game.buttons.has("skip") and game.buttons.has("pause"), "the settlement can be paused or skipped")
	game.skip_animation(); settle(game)
	check(game.state.stage == "clarify" and game.state.written == [7, 10], "the paper stays as promised after confirmation")
	check(game.world.confirmed_slot() == Rules.CASES.find(game.state.branch), "the confirmed order is the drawn one")
	check(game.world.crate_alpha(game.world.confirmed_slot()) > game.world.crate_alpha(1 - game.world.confirmed_slot()),
		"the order that did not come back fades back")
	check(game.world.goods_still_on_board(0) and game.world.goods_still_on_board(1),
		"结票与三句订正这两段里两单的封箱都还在各自那一格：货还没开始上船")
	game.advance(); game.advance()
	check(game.state.stage == "clarify" and game.state.beat == Rules.CLARIFY_BEATS - 1, "the clarification is player-paced")
	game.advance()
	check(game.state.stage == "delivery", "the last line lets the loaded boat leave")
	check("查询信" in game.line(), "the sailing line already carries the query letter")
	game.paused = true; settle(game)
	game.world.progress = 0.25
	var carried = game.world.carry_plan(0.25)
	check(carried.size() == game.state.branch, "exactly the confirmed order's boxes are carried")
	check(game.world.hide_while_moving(carried).size() == carried.size(), "the crates leave their cells while in the air")
	check(game.world.deck_load(game.state.boat).is_empty(), "the deck is still empty in the first half")
	game.world.progress = 0.9
	check(game.world.deck_load(game.state.boat).size() == game.state.branch, "the deck carries the confirmed load in the second half")
	check(not game.world.goods_still_on_board(game.world.confirmed_slot())
		and game.world.goods_still_on_board(1 - game.world.confirmed_slot()),
		"后半程被拉走那一单不再画回刚离开的那一格，没被确认那一单的对照还留在板上")
	check(game.world.tickets_left() == Rules.BUDGET - game.state.paid, "the box holds only the unpaid tickets")
	check("查询信" in game.line(), "the sailing line carries the query letter toward the gear workshop")
	check(game.world.sailing() and game.world.sail_amount() > 0.5, "the chosen boat is on its way out")
	check(not game.world.sailing() or game.world.boat_alpha(1 - game.state.boat) == 1.0, "the other boat stays at the quay")
	game.skip_animation(); settle(game)
	game.paused = false
	check(game.state.stage == "complete" and game.state.paid == Rules.fare(1, game.state.branch),
		"the scene closes with the real payment on record")
	check(game.buttons["next"].text == "重新体验" and game.buttons.has("open_hub"), "a standalone sample keeps its own exit")
	var hub_button = game.buttons["open_hub"]
	check(hub_button.position == Vector2(690, 646) and hub_button.size == Vector2(280, 54), "the exit uses the shared corner")
	var receipt = game.receipt_lines()
	var receipt_spill = 0
	for line in receipt:
		if not fits(line, 16, game.receipt_text_rect().size.x): receipt_spill += 1
	check(receipt_spill == 0 and receipt.size() == 6, "the six receipt lines fit their panel width")
	check(receipt.size() * face.get_height(UIStyle.text_size(16)) <= game.receipt_text_rect().size.y,
		"the receipt panel is tall enough for every line it carries")
	check("蓝船 %d 票" % Rules.fares(1)[0] in receipt[1] and "蓝船 %d 票" % Rules.fares(1)[1] in receipt[2],
		"the receipt restates both public cases under the chosen bargain")
	check("本局运 %d 箱" % game.state.branch in receipt[4] and "付讫 %d 票" % game.state.paid in receipt[4],
		"the receipt names the order the story confirmed and the tickets really spent")
	check("查询信" in receipt[5] and "齿轮工坊" in game.line(), "the reply's way back is opened by this load")
	var panel = game.receipt_rect()
	var covering = 0
	if panel.position.x < 0 or panel.position.y < 0 or panel.end.x > 1280 or panel.end.y > 720: covering += 1
	for slab in host_boards(game, [panel]):
		if panel.intersects(slab["solid"]): covering += 1
	if panel.intersects(Rect2(690, 646, 280, 54)): covering += 1
	for slot in range(Rules.SLOTS):
		if panel.intersects(game.world.cell_rect(slot)): covering += 1
	for boat in range(Rules.BOATS):
		if panel.intersects(game.world.boat_rect(boat)): covering += 1
	check(covering == 0, "the receipt panel covers neither the spoken board, the boats nor the exit")
	# ---- 11. 逐阶段重画：牌面、台词与热点都不出框 ----
	game.paused = true
	var touring = true
	var prompts_ok = true
	for stage in Rules.STAGES:
		var beat = 1 if stage in ["arrival", "clarify"] else 0
		var slips = Rules.empty_written() if stage in ["arrival", "approach", "ready"] else Rules.fares(1)
		var bargain = -1 if stage in ["arrival", "approach", "ready"] else 1
		var shown = build(slips, bargain, stage, game.state.branch, beat)
		if not Rules.validate(shown): touring = false
		game.state = shown
		game.elapsed = 0.0
		game.world.progress = 0.95 if stage in Rules.ANIMATIONS else 0.0
		settle(game)
		if game.state.stage != stage: touring = false
		for plaque in game.world.signs():
			if not fits(plaque["text"], 16, plaque["rect"].size.x - 20): touring = false
		if not fits(game.line(), 20, BOARD): touring = false
		if not fits(game.goal_line(), 22, GOAL_BOARD): touring = false
		if not fits(game.status_line(), 20, STATUS_BOARD): touring = false
		if not fits(game.submit_label(), 20, 235.0): touring = false
		for hint in game.hint_texts():
			if not fits(hint, 20, BOARD) or hint.split("\n").size() > 2: touring = false
		game.world.queue_redraw()
		await process_frame
	for stage in Rules.STAGES:
		game.state = build(Rules.fares(1), 1, stage, game.state.branch)
		for prompt in [game.reset_prompt(), game.restart_prompt()]:
			if not fits(prompt[0], 22, MODAL_BOARD): prompts_ok = false
	check(touring, "all eight stages repaint and every board holds its own text")
	check(prompts_ok, "the two confirmation dialogs stay inside their modal board")
	check(game.world.signs().size() > 6, "the dock labels both boats, both orders and the ticket box")
	# ---- 12. 落盘、读档与损坏保护 ----
	game.paused = false
	settle(game)
	check(game.commit(build(Rules.fares(1), 1, "puzzle", 6)), "a legal mid-scene save is accepted")
	var disk = Content.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(path)))
	check(disk.branch == 6 and disk.written == [7, 10] and disk.paid == 0, "the plan and its branch land on disk together")
	check(Rules.validate(disk), "what the level wrote is itself a legal save")
	var fixed_branch = game.state.branch
	Bridge.origin = "hub"
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.branch == fixed_branch and game.state.stage == "puzzle" and game.state.written == [7, 10],
		"reloading restores the same confirmed order instead of rolling again")
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("leave_hub") and not game.buttons.has("open_hub"), "from the chart the board offers a way back")
	game.do_mark(4); settle(game)
	check(game.state.written == [4, 10] and game.state.branch == fixed_branch, "the reloaded board is still playable")
	game.queue_free(); await process_frame
	write_raw("{broken")
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	write_raw(JSON.stringify(build(Rules.fares(0), 0, "complete")))
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected,
		"a save that settled on a bargain covering only one case is corruption")
	game.queue_free(); await process_frame
	write_raw(JSON.stringify(sheet(1, "complete", 9)))
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected, "an out-of-range branch on disk is refused")
	game.queue_free(); await process_frame
	write_raw(JSON.stringify(sheet(1, "delivery", 6)))
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(not game.modal and game.state.stage == "delivery" and game.state.paid == 10 and game.state.branch == 6,
		"the six-box settlement reloads and keeps sailing")
	check(game.world.sailing() and game.world.tickets_left() == 0, "the reloaded boat carries the paid-for load")
	game.queue_free(); await process_frame
	# ---- 13. 另一条分支也走一遍真实场景：结的仍是本局那一张订单 ----
	var other = 6 if fixed_branch == 3 else 3
	write_raw(JSON.stringify(build(Rules.fares(1), 1, "puzzle", other)))
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.branch == other and game.state.stage == "puzzle" and game.state.written == [7, 10],
		"the seeded board reopens on the other order without re-rolling")
	game.advance(); settle(game)
	check(game.state.stage == "confirming" and game.state.paid == Rules.fare(1, other),
		"the real scene settles the other branch at its own fare")
	game.skip_animation(); settle(game)
	game.advance(); game.advance(); game.advance()
	check(game.state.stage == "delivery" and game.world.carry_plan(0.9).size() == other,
		"the other branch loads exactly its own number of boxes")
	game.skip_animation(); settle(game)
	check(game.state.stage == "complete" and game.state.paid == (7 if other == 3 else 10),
		"both branches clear the real scene, each paying what its own order costs")
	game.queue_free(); await process_frame
	# ---- 14. 演出的筹票、封箱与随船那封信：任何一帧都不许躲进宿主木牌 ----
	# 无头看不见窗框，但两边都是可以现算的矩形：世界层按 manifest 的 anchor 画出哪一块，
	# 宿主就在同一格画面上压住哪一块。两条约定、两种箱数都要逐帧量一遍。
	write_raw(JSON.stringify(sheet(1, "puzzle", 3)))
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	game.paused = true
	var swept = 0
	var solid_worst = 0.0
	var dimmed_worst = 0.0
	var slabs: Array = []
	var boxes: Array = []
	var reading: Array = []
	for keel in range(Rules.BOATS):
		for order in Rules.CASES:
			# 红船这条约定盖不住 6 箱那一单：12 票超出上限，那样的局永远走不到结算。
			# 所以红船只量它真能结清的那一单，蓝船两条都要量。
			if Rules.fare(keel, order) > Rules.BUDGET: continue
			# 结票那一段：镜头钉在 1.10，匣子里的票一张一张飞向泊位前的收费牌。
			for tick in range(41):
				var fraction = tick / 40.0
				game.state = build(Rules.fares(keel), keel, "confirming", order)
				game.world.progress = fraction
				settle(game)
				slabs = host_boards(game)
				boxes.clear()
				for flying in game.world.ticket_plan(fraction):
					boxes.append(on_screen(game.world, kit_box(game.world, "receipt_blank",
						flying["at"], World.TICKET_WIDTH)))
				swept += boxes.size()
				reading = worst_burial(boxes, slabs)
				solid_worst = maxf(solid_worst, reading[0])
				dimmed_worst = maxf(dimmed_worst, reading[1])
			# 装船到离岸：前半程箱子在空中划一道弧，后半程落在甲板上跟船一起缩小、一起走远。
			for tick in range(41):
				var crossing = tick / 40.0
				game.state = build(Rules.fares(keel), keel, "delivery", order)
				game.world.progress = crossing
				settle(game)
				slabs = host_boards(game)
				boxes.clear()
				for lifted in game.world.carry_plan(crossing) + game.world.deck_load(keel):
					boxes.append(on_screen(game.world, kit_box(game.world,
						World.CRATE_ART[lifted["slot"]], lifted["at"],
						World.CRATE_WIDTH * game.world.boat_scale(keel))))
				if not game.world.deck_load(keel).is_empty():
					boxes.append(on_screen(game.world, kit_box(game.world, "paper_roll",
						game.world.letter_foot(keel), World.LETTER_WIDTH * game.world.boat_scale(keel))))
				swept += boxes.size()
				reading = worst_burial(boxes, slabs)
				solid_worst = maxf(solid_worst, reading[0])
				dimmed_worst = maxf(dimmed_worst, reading[1])
			# 回执阶段船已经走远：货与那封信还在那条缩到四成的船上，镜头退回整片大码头。
			game.state = build(Rules.fares(keel), keel, "complete", order)
			game.world.progress = 1.0
			settle(game)
			slabs = host_boards(game)
			boxes.clear()
			for settled_crate in game.world.deck_load(keel):
				boxes.append(on_screen(game.world, kit_box(game.world,
					World.CRATE_ART[settled_crate["slot"]], settled_crate["at"],
					World.CRATE_WIDTH * game.world.boat_scale(keel))))
			boxes.append(on_screen(game.world, kit_box(game.world, "paper_roll",
				game.world.letter_foot(keel), World.LETTER_WIDTH * game.world.boat_scale(keel))))
			swept += boxes.size()
			reading = worst_burial(boxes, slabs)
			solid_worst = maxf(solid_worst, reading[0])
			dimmed_worst = maxf(dimmed_worst, reading[1])
	# 反证：把同一块封箱放回原来那条甲板线（世界 y 169）、把一张筹票放回原来的落点（y 189），
	# 同一套测量立刻报「整块压在牌上」。上面那两个读数不是因为量不到木牌才恰好为 0 的。
	var armed = host_boards(game)
	var old_deck = on_screen(game.world, kit_box(game.world, "crate_red", Vector2(460, 169), World.CRATE_WIDTH))
	var old_ticket = on_screen(game.world, kit_box(game.world, "receipt_blank",
		Vector2(460, 189), World.TICKET_WIDTH))
	check(buried(old_deck, armed, "solid") > 0.5 and buried(old_ticket, armed, "solid") > 0.5,
		"the same measurement buries the old deck line and the old ticket landing: the sweep is armed")
	check(swept > 400 and not slabs.is_empty(),
		"the two flights were measured frame by frame against the boards the host really drew")
	check(solid_worst <= 0.01, "no ticket, crate or letter ever lands on an opaque host board (worst %.1f%%)"
		% (solid_worst * 100))
	check(dimmed_worst <= 0.15, "the same flight stays clear of the boards' cast shadow (worst %.1f%%)"
		% (dimmed_worst * 100))
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK10 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

extends SceneTree
const Rules = preload("res://scripts/market/mk09_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk09.tscn")
const UIStyle = preload("res://scripts/cargo/skin.gd")
# 一条五摊大环，而且五摊没有一个拿到自己要的那件：用来验「大环」这一句点名。
const RING = [4, 0, 3, 1, 2]
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk09-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 一份可存档的现场：exchanging 之后街上的线必须就是入账的那一批，由 build 守住这个不变式。
func build(lines: Array, stage: String = "puzzle", hand: int = -1) -> Dictionary:
	var state = Rules.fresh()
	state.stage = stage
	state.lines = lines.duplicate(true)
	state.hand = hand if stage == "puzzle" else -1
	state.booked = lines.duplicate(true) if stage in ["exchanging", "delivery", "complete"] else Rules.empty_lines()
	return state

func plan(a: int, b: int, c: int, d: int, e: int) -> Array:
	return [a, b, c, d, e]

# 汉字按整宽、拉丁字母按六成宽估算：Godot 不会在汉字串中间断行，超框就是画到框外。
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

# 真正的字体度量：Godot 不会在汉字串中间自动折行，text_size() 还会把 16/20/22/24 抬到 18/22/22/28，
# 所以每一行都要按实际渲染字号量一遍，行数也不许撑破这块板子。
# face() 每次调用都会重新装载字体，这里缓存一份，量几百行也不会拖垮无头检查。
var typeface: FontFile
func measure(text: String, px: int, box: float, allowed: int, tag: String) -> void:
	if typeface == null: typeface = UIStyle.face()
	var rows = text.split("\n")
	check(rows.size() <= allowed, tag + " 的行数撑得住这块板子")
	for piece in rows:
		var run = typeface.get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		check(run <= box, "%s 的每一行量得下 %d 像素（%d）：%s" % [tag, int(box), int(run), piece])

# 落下动画只影响手感：清掉 it 再重画，热点的可用状态才与实窗一致。
func settle(game: Node) -> void:
	game.transient = 0.0
	game.refresh()

# 五摊的全部排法（0..4 的全排列），用来穷举整体对应。
func permutations() -> Array:
	var result = []
	for code in range(3125):
		var rest = code
		var lines = []
		for index in range(Rules.COUNT):
			lines.append(rest % Rules.COUNT); rest = int(rest / Rules.COUNT)
		var distinct = true
		for receiver in range(Rules.COUNT):
			if lines.count(lines[receiver]) > 1: distinct = false
		if distinct: result.append(lines)
	return result

# 草稿的全部形状：每一格可以是 -1（还没接到线）或任意一摊，包括重复与自牵，共 6^5 种。
func drafts() -> Array:
	var result = []
	for code in range(7776):
		var rest = code
		var lines = []
		for index in range(Rules.COUNT):
			# 六进制位 0..5 映射成 -1..4：每一格都取遍「没接线」与五个出货摊。
			lines.append(rest % 6 - 1)
			rest = int(rest / 6)
		result.append(lines)
	return result

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("MK09 rule watchdog"); quit(1))
	# ---- 1. 开局现场 ----
	check(Rules.validate(Rules.fresh()), "fresh model validates")
	check(Rules.fresh().sample == "market-mk09-1", "fresh carries the mk09 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens at the arrival beats")
	check(Rules.fresh().lines == Rules.empty_lines(), "no line is drawn on the street yet")
	check(Rules.fresh().booked == Rules.empty_lines(), "nothing is booked into the exchange")
	check(Rules.fresh().hand == -1, "nobody is holding a good")
	check(Rules.fresh().hint == 0, "hints start unused")
	check(Rules.fresh().keys().size() == 7, "the profile carries exactly the seven frozen fields")
	check(Rules.ACTORS == ["甲", "乙", "丙", "丁", "戊"], "the five stalls are 甲乙丙丁戊")
	check(Rules.GOODS == ["布", "油", "纸", "铃", "绳"], "each stall holds one good in that order")
	check(Rules.KIT_GOODS == ["cloth_bolt", "oil_bottle", "paper_roll", "brass_bell", "rope_spool"],
		"the five goods use five distinct kit-v1 parts")
	check(Rules.ACCEPT == [[1, 3], [2], [0], [0, 4], [3]], "the wants match the design sheet")
	check(Rules.COUNT == 5 and Rules.BEATS == 3 and Rules.HINTS == 3, "five stalls, three lines, three hint tiers")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "exchanging", "delivery", "complete"],
		"the stage machine is frozen")
	check(Rules.ANIMATIONS == ["approach", "exchanging", "delivery"], "three animated stages")
	check(not ("puzzle" in Rules.ANIMATIONS), "drawing lines is not an animation")
	# 每摊能收的货都不是自己手上那件：所以「留在原地」不可能被当成已满足。
	var keeps = 0
	for receiver in range(Rules.COUNT):
		if Rules.ACCEPT[receiver].has(receiver): keeps += 1
	check(keeps == 0, "no stall accepts the good it already holds")
	# ---- 2. 穷举：整体对应唯一，大环一条都不成立 ----
	var all = permutations()
	check(all.size() == 120, "the five stalls have 120 whole bijections")
	var solved_plans = []
	var rings = []
	var fixed_free = 0
	for lines in all:
		var self_used = false
		for receiver in range(Rules.COUNT):
			if lines[receiver] == receiver: self_used = true
		if not self_used: fixed_free += 1
		if Rules.solved(build(lines)): solved_plans.append(lines)
		if Rules.cycle_lengths(lines) == [5]: rings.append(lines)
	check(solved_plans.size() == 1, "exactly one whole bijection satisfies all five stalls")
	check(solved_plans[0] == Rules.SOLUTION, "the unique plan is 甲←乙, 乙←丙, 丙←甲, 丁←戊, 戊←丁")
	check(Rules.SOLUTION == plan(1, 2, 0, 4, 3), "the frozen solution matches the design brief")
	check(fixed_free == 44, "44 of the 120 bijections move every good (derangements)")
	check(Rules.self_lines(solved_plans[0]).is_empty(), "the unique plan leaves no good at home")
	check(rings.size() == 24, "24 of the bijections force all five stalls into one ring")
	var ring_ok = 0
	for lines in rings:
		if Rules.solved(build(lines)): ring_ok += 1
		if not Rules.shortfalls(build(lines))[0].contains(Rules.SHAPE_RING): ring_ok += 1000
	check(ring_ok == 0, "every five-ring is refused and is named as a five-ring")
	check(Rules.cycle_lengths(Rules.SOLUTION) == [3, 2], "the solution is one 3-cycle plus one 2-cycle")
	check(Rules.shape(Rules.SOLUTION) == Rules.SHAPE_CYCLE, "the solution is described as three-in-a-ring plus a swap")
	check(Rules.shape(RING) == Rules.SHAPE_RING, "the ring shape is named, not just refused")
	check(Rules.satisfied(Rules.SOLUTION).size() == 5 and Rules.unmoved(Rules.SOLUTION).is_empty(),
		"the solution moves all five goods and pleases all five stalls")
	check(Rules.goods_after(Rules.SOLUTION) == Rules.SOLUTION,
		"the booked plan leaves each stall holding exactly the good it accepted")
	check(Rules.goods_after(Rules.empty_lines()) == [0, 1, 2, 3, 4],
		"an empty draft leaves every good where it started")
	var draft_solved = 0
	for lines in drafts():
		if not Rules.validate(build(lines)): push_error("draft rejected as corruption " + str(lines))
		if Rules.solved(build(lines)): draft_solved += 1
		if Rules.drawn(lines) + Rules.unlined(lines).size() != Rules.COUNT: push_error("counting drift " + str(lines))
		if Rules.double_promised(lines).size() > 0 and Rules.drawn(lines) < 2: push_error("bad double report")
	check(draft_solved == 1, "all 7776 draft shapes enumerate to the same single solution")
	# ---- 3. 阶段机 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "arrival plays its lines in order")
	arriving = Rules.advance(arriving)
	check(arriving.beat == 2 and Rules.advance(arriving).stage == "approach", "the third line convenes the five stalls")
	var walked = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(walked.stage == "puzzle" and walked.lines == Rules.empty_lines(), "approach and ready never touch a line")
	check(Rules.advance(Rules.fresh()).beat == 1, "the arrival beats cannot be skipped")
	var single = true
	for stage in Rules.STAGES:
		if stage in ["arrival", "complete"]: continue
		var moved = Rules.advance(build(Rules.SOLUTION, stage))
		if moved.is_empty(): single = false; continue
		if moved.stage != Rules.STAGES[Rules.STAGES.find(stage) + 1]: single = false
	check(single, "advance only ever moves one stage forward")
	check(Rules.advance(build(plan(1, 2, 0, 4, -1))).is_empty(), "four lines cannot be submitted")
	check(Rules.advance(build(Rules.empty_lines())).is_empty(), "an empty street cannot be submitted")
	check(Rules.advance(build(plan(0, 1, 2, 3, 4))).is_empty(), "everybody keeping their own good is refused")
	check(not Rules.advance(build(Rules.SOLUTION, "puzzle", 0)).is_empty(),
		"holding a good does not block the submit")
	var booked = Rules.advance(build(Rules.SOLUTION))
	check(booked.stage == "exchanging" and booked.booked == Rules.SOLUTION, "submitting books the whole street at once")
	check(booked.lines == booked.booked, "the booked batch is the draft it came from")
	check(booked.hand == -1, "nobody is still holding a good once the exchange starts")
	check(Rules.advance(booked).stage == "delivery" and Rules.advance(booked).booked == Rules.SOLUTION,
		"the nodding stage does not re-book anything")
	check(Rules.advance(Rules.advance(booked)).stage == "complete", "the lit string closes the scene")
	check(Rules.advance(build(Rules.SOLUTION, "complete")).is_empty(), "complete has no next stage")
	var frozen = true
	for stage in ["exchanging", "delivery", "complete"]:
		var locked = build(Rules.SOLUTION, stage)
		if not Rules.pick(locked, 0).is_empty(): frozen = false
		if not Rules.connect_line(locked, 1).is_empty(): frozen = false
		if not Rules.cut_line(locked, 1).is_empty(): frozen = false
		if not Rules.clear_street(locked).is_empty(): frozen = false
	check(frozen, "the street is frozen once the exchange is booked")
	# ---- 4. 牵线与拉回：草稿不留幻影货权 ----
	var table = build(Rules.empty_lines())
	check(Rules.pick(Rules.fresh(), 0).is_empty(), "no line before the stalls are convened")
	check(Rules.pick(table, -1).is_empty() and Rules.pick(table, Rules.COUNT).is_empty(),
		"unknown stalls cannot be picked up")
	var held = Rules.pick(table, 0)
	check(held.hand == 0 and held.lines == Rules.empty_lines(), "picking up only lifts a good, no line yet")
	check(Rules.pick(held, 0).hand == -1, "tapping the same stall again lets the good go")
	check(table.lines == Rules.empty_lines() and table.hand == -1, "the previous state is left untouched")
	var wired = Rules.connect_line(held, 2)
	check(wired.lines == plan(-1, -1, 0, -1, -1) and wired.hand == -1, "connecting writes one line 甲→丙")
	check(not Rules.is_booked(wired.lines), "a half-drawn street is never read as an exchange")
	check(wired.booked == Rules.empty_lines(), "nothing is booked while the plan is only drafted")
	check(Rules.drawn(wired.lines) == 1 and Rules.satisfied(wired.lines) == [2], "the draft already reports who is pleased")
	var rewired = Rules.connect_line(Rules.pick(wired, 1), 2)
	check(rewired.lines == plan(-1, -1, 1, -1, -1), "a new line onto the same tray replaces the old promise")
	check(Rules.drawn(rewired.lines) == 1, "replacing a line does not invent a second one")
	var doubled = Rules.connect_line(Rules.pick(wired, 0), 3)
	check(doubled.lines == plan(-1, -1, 0, 0, -1) and Rules.double_promised(doubled.lines) == [0],
		"the same bolt of cloth can be drafted onto two trays and is detected")
	check(not Rules.solved(doubled), "a double promise is never solved")
	var looped = Rules.connect_line(Rules.pick(table, 0), 0)
	check(looped.lines == plan(0, -1, -1, -1, -1) and Rules.self_lines(looped.lines) == [0],
		"a line that loops back to its own stall is recorded as a self line")
	check(not Rules.solved(looped), "goods left at home are not an exchange")
	var cut = Rules.cut_line(wired, 2)
	check(cut.lines == Rules.empty_lines() and cut.hand == -1, "pulling the line back erases the promise")
	var street = table
	for step in range(Rules.COUNT):
		street = Rules.connect_line(Rules.pick(street, Rules.SOLUTION[step]), step)
	check(street.lines == Rules.SOLUTION, "the five lines can be drawn one by one")
	var wiped = street
	for step in range(Rules.COUNT):
		wiped = Rules.cut_line(wiped, step)
	check(wiped.lines == Rules.empty_lines() and Rules.drawn(wiped.lines) == 0, "drawing then pulling back leaves nothing")
	check(Rules.goods_after(wiped.lines) == [0, 1, 2, 3, 4], "no phantom ownership survives the round trip")
	check(Rules.validate(wiped), "the street is still a legal save after the round trip")
	check(Rules.clear_street(street).lines == Rules.empty_lines(), "重摆 pulls every line back at once")
	check(Rules.cut_line(table, 0).is_empty(), "an empty tray has nothing to pull back")
	check(Rules.connect_line(table, 0).is_empty(), "an empty hand cannot draw a line")
	check(Rules.connect_line(table, -1).is_empty() and Rules.connect_line(table, Rules.COUNT).is_empty(),
		"trays outside the street are refused")
	for stage in ["arrival", "approach", "ready", "exchanging", "delivery", "complete"]:
		var shut = build(Rules.SOLUTION, stage)
		check(Rules.pick(shut, 0).is_empty() and Rules.cut_line(shut, 1).is_empty(),
			"the street is not drawable during " + stage)
	# ---- 5. 撤销快照 ----
	var snap = {"lines": plan(-1, -1, 0, -1, -1), "hand": -1}
	check(Rules.restore(Rules.connect_line(Rules.pick(table, 1), 2), snap).lines == plan(-1, -1, 0, -1, -1),
		"undo rewinds a drawn line")
	check(Rules.restore(Rules.cut_line(wired, 2), {"lines": wired.lines, "hand": -1}).lines == wired.lines,
		"undo rewinds a pulled-back line")
	check(Rules.restore(Rules.pick(table, 3), snap).hand == -1, "undo also lets go of a good the older snapshot had free")
	check(Rules.restore(Rules.pick(table, 3), {"lines": plan(-1, -1, 0, -1, -1), "hand": 1}).hand == 1,
		"undo also puts the good back into the hand the player had")
	var every = 0
	for giver in range(Rules.COUNT):
		for receiver in range(Rules.COUNT):
			var prior = build(Rules.empty_lines())
			var after = Rules.connect_line(Rules.pick(prior, giver), receiver)
			if after.is_empty(): every += 1; continue
			if Rules.restore(after, {"lines": prior.lines, "hand": prior.hand}).lines != prior.lines: every += 1
	check(every == 0, "every line in reach round-trips through the undo snapshot")
	check(Rules.restore(build(Rules.empty_lines(), "arrival"), snap).is_empty(), "undo only works on the street")
	check(Rules.restore(build(Rules.SOLUTION, "exchanging"), snap).is_empty(), "undo cannot reopen a booked exchange")
	check(Rules.restore(table, {"lines": Rules.empty_lines()}).is_empty(), "a snapshot without the hand is refused")
	check(Rules.restore(table, {"hand": -1}).is_empty(), "a snapshot without the lines is refused")
	check(Rules.restore(table, {"lines": [1, 2, 0, 4], "hand": -1}).is_empty(),
		"undo refuses a wrong-length draft")
	check(Rules.restore(table, {"lines": plan(1, 2, 0, 4, 9), "hand": -1}).is_empty(),
		"undo refuses an out-of-range draft")
	check(Rules.restore(Rules.cut_line(street, 4), {"lines": Rules.SOLUTION, "hand": -1}).lines == Rules.SOLUTION,
		"undo can bring the whole drafted street back onto the street")
	check(Rules.restore(Rules.cut_line(street, 4), {"lines": Rules.SOLUTION, "hand": -1}).booked == Rules.empty_lines(),
		"rewinding a draft never books an exchange")
	# ---- 6. 提交闸口：点名是哪一摊、哪一件货 ----
	check(Rules.shortfalls(build(Rules.empty_lines())).size() == 5, "an empty street reports five open trays")
	check(Rules.shortfalls(build(Rules.empty_lines()))[0] == "甲摊还没有接到线：它能收油或铃。",
		"the first gap names the stall and what it would accept")
	var four = Rules.shortfalls(build(plan(3, 2, 0, 4, -1)))
	check(four == ["戊摊还没有接到线：它只认铃。"], "four of five is refused in the player's own words")
	check(Rules.satisfied(build(plan(3, 2, 0, 4, -1)).lines).size() == 4, "that near miss really pleases four stalls")
	var cloth = Rules.shortfalls(build(plan(1, 2, 0, 0, -1)))
	check(cloth[0] == "布同时许给了丙摊、丁摊：一件货只能有一个新主人。", "the double promise names the bolt of cloth")
	check(Rules.unmoved(build(plan(1, 2, 0, 0, -1)).lines) == [3, 4], "and it leaves two goods with no new home")
	var home = Rules.shortfalls(build(plan(0, 2, 1, 4, 3)))
	check(home[0] == "甲摊的线绕回了自己：布留在原摊，不算换出去。", "keeping your own good is refused by name")
	var wrong = Rules.shortfalls(build(plan(1, 2, 1, 4, 3)))
	check(wrong[0].contains("同时许给") and wrong[1] == "丙摊接到的是油，可它只认布。",
		"a wrong delivery is reported separately from the double promise")
	check(Rules.shortfalls(build(plan(1, 2, 0, 4, 4)))[0].contains("丁摊"), "the doubled 绳 promise points at 丁")
	check(Rules.shortfalls(build(Rules.SOLUTION)).is_empty() and Rules.solved(build(Rules.SOLUTION)),
		"the unique plan has no shortfall")
	var ring = Rules.shortfalls(build(RING))
	check(ring[0] == "五摊挤进一个大环：先想想哪两摊能自己对上。", "the five-ring gets its own sentence")
	check(ring.size() == 6, "and then all five unhappy stalls are listed as well")
	# ---- 7. 存档 schema ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record " + str(bad))
	var piece = build(Rules.SOLUTION); piece.sample = "market-mk02-1"
	check(not Rules.validate(piece), "a foreign sample is rejected")
	piece = build(Rules.SOLUTION); piece.erase("sample")
	check(not Rules.validate(piece), "a missing sample is corruption")
	piece = build(Rules.SOLUTION); piece.stage = "swapping"
	check(not Rules.validate(piece), "an unknown stage is rejected")
	piece = build(Rules.SOLUTION); piece.stage = 3
	check(not Rules.validate(piece), "a numeric stage is rejected")
	piece = build(Rules.SOLUTION); piece.lines[0] = -2
	check(not Rules.validate(piece), "a line below empty is rejected")
	piece = build(Rules.SOLUTION); piece.lines[1] = Rules.COUNT
	check(not Rules.validate(piece), "a line to a stall that does not exist is rejected")
	piece = build(Rules.SOLUTION); piece.lines[2] = 1.5
	check(not Rules.validate(piece), "a fractional line is corruption")
	piece = build(Rules.SOLUTION); piece.lines[3] = "4"
	check(not Rules.validate(piece), "a string line is corruption")
	piece = build(Rules.SOLUTION); piece.lines = [1, 2, 0]
	check(not Rules.validate(piece), "a short line array is corruption")
	piece = build(Rules.SOLUTION); piece.lines = [1, 2, 0, 4, 3, 1]
	check(not Rules.validate(piece), "a long line array is corruption")
	piece = build(Rules.SOLUTION); piece.lines[2] = null
	check(not Rules.validate(piece), "a null line is corruption")
	piece = build(Rules.SOLUTION); piece.erase("booked")
	check(not Rules.validate(piece), "a missing booked record is corruption, not a default")
	piece = build(Rules.SOLUTION); piece.erase("hand")
	check(not Rules.validate(piece), "a missing hand is corruption")
	piece = build(Rules.SOLUTION); piece.hint = Rules.HINTS + 1
	check(not Rules.validate(piece), "hint level is capped")
	piece = build(Rules.SOLUTION); piece.hint = -1
	check(not Rules.validate(piece), "hints cannot go negative")
	piece = build(Rules.SOLUTION); piece.beat = Rules.BEATS
	check(not Rules.validate(piece), "arrival beats are bounded")
	piece = build(Rules.SOLUTION); piece.beat = "2"
	check(not Rules.validate(piece), "a string beat is corruption")
	piece = build(Rules.SOLUTION); piece.hand = Rules.COUNT
	check(not Rules.validate(piece), "the hand cannot hold a sixth stall")
	piece = build(Rules.SOLUTION, "puzzle"); piece.hint = 2
	check(Rules.validate(piece), "hints are allowed once the street is open")
	for stage in ["arrival", "approach", "ready"]:
		piece = build(Rules.SOLUTION, stage)
		check(not Rules.validate(piece), stage + " cannot carry drafted lines")
		piece = build(Rules.empty_lines(), stage); piece.hint = 1
		check(not Rules.validate(piece), stage + " cannot carry a used hint")
	piece = build(Rules.SOLUTION, "puzzle"); piece.booked = Rules.SOLUTION.duplicate(true)
	check(not Rules.validate(piece), "the drafting stage cannot hold a booked exchange")
	piece = build(Rules.empty_lines(), "puzzle"); piece.hand = 2
	check(Rules.validate(piece), "holding a good on the street is a legal save")
	piece = build(plan(1, 2, 0, 0, -1), "puzzle")
	check(Rules.validate(piece), "a double promise is a draft, not corruption")
	check(Rules.advance(piece).is_empty(), "yet it can never be submitted")
	for stage in ["exchanging", "delivery", "complete"]:
		piece = build(Rules.empty_lines(), stage)
		check(not Rules.validate(piece), "a later stage with nothing booked is a forged record at " + stage)
		piece = build(plan(1, 2, 0, 0, 3), stage)
		check(not Rules.validate(piece), "a booked double promise is rejected at " + stage)
		piece = build(plan(0, 2, 1, 4, 3), stage)
		check(not Rules.validate(piece), "a booked self line is rejected at " + stage)
		piece = build(plan(4, 0, 1, 2, 3), stage)
		check(not Rules.validate(piece), "a booked five-ring is rejected at " + stage)
		piece = build(plan(1, 2, 3, 4, 0), stage)
		check(not Rules.validate(piece), "a booked plan that pleases nobody is rejected at " + stage)
		piece = build(Rules.SOLUTION, stage); piece.booked = plan(1, 2, 0, 4, 4)
		check(not Rules.validate(piece), "the booked batch cannot be swapped mid-animation at " + stage)
		piece = build(Rules.SOLUTION, stage); piece.hand = 1
		check(not Rules.validate(piece), "nobody is still holding a good at " + stage)
		piece = build(Rules.SOLUTION, "puzzle"); piece.lines = plan(1, 2, 0, 4, 3)
		check(Rules.validate(Rules.advance(piece)), "the same plan advances into " + stage)
		piece = build(Rules.SOLUTION, stage); piece.stage = stage
		check(Rules.validate(piece), "a booked exchange is a legal save at " + stage)
	piece = build(Rules.SOLUTION, "delivery"); piece.lines = plan(1, 2, 0, 4, -1)
	check(not Rules.validate(piece), "a stage claiming a later moment with an unmet stall is corruption")
	check(Rules.validate(build(Rules.SOLUTION, "exchanging")), "exchanging is a legal save")
	check(Rules.validate(build(Rules.SOLUTION, "delivery")), "the nodding stage is a legal save")
	check(Rules.validate(build(Rules.SOLUTION, "complete")), "the cleared scene is a legal save")
	var capped = build(Rules.SOLUTION); capped.hint = Rules.HINTS
	check(Rules.validate(capped), "the top hint tier is inside the bound")
	# ---- 8. 章节目录与本关身份 ----
	var entry = Catalog.LEVELS["MK09"]
	check(entry.title == "不必两个人就换成", "the catalog title is the level title")
	check(entry.act == 4 and entry.kit == "street", "act 4 on the street kit")
	check(entry.scene == "res://game/market_mk09.tscn", "the catalog points at the shipped scene path")
	check(ResourceLoader.exists(entry.scene) and Catalog.built("MK09"), "the scene file exists so the chart lights up")
	check(entry.save == "user://profiles/market-mk09-1/save-v1.json", "the catalog save path is the mk09 profile")
	check(entry.after == "MK08" and Catalog.opens_after("MK09") == "MK08", "mk09 opens after mk08")
	check(entry.goal == "牵起交换线，让五摊一次换完且各自满意", "the catalog goal is the one-line target")
	check(not Catalog.is_side("MK09") and "MK09" in Catalog.MAIN, "mk09 is a main-line level")
	check(Catalog.save_path("MK09") == entry.save, "the catalog exposes the save path")
	check("MK09" in Catalog.LEVELS["MK15"].after or Catalog.opens_after("MK15") == "MK09",
		"the 铜果 side quest hangs off mk09")
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == Catalog.save_path("MK09"), "configure only fills the catalog save path as a default")
	check(probe.scene_id == "street" and probe.level_id == "MK09", "the scene declares its own identity")
	check(probe.rules == Rules and probe.world_script.resource_path.ends_with("mk09_world.gd"),
		"the host is wired to mk09")
	check(probe.title == entry.title, "the window title uses the catalog title")
	check(probe.durations.has("exchanging") and probe.durations.has("delivery"), "the host owns the stage durations")
	check(probe.goal_line() == entry.goal, "the goal board quotes the catalog goal")
	probe.free()
	# ---- 9. 真实场景：热点、按钮、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.save_path == path, "an injected test path survives configure")
	check(game.state.stage == "arrival", "a new profile opens on the arrival beats")
	check(game.buttons.has("next") and game.buttons["next"].text == "继续听他们说",
		"the first beat only asks to keep listening")
	check(fits(game.line(), 20, 798.0), "the arrival line fits the spoken board")
	check(fits(game.goal_line(), 22, 762.0), "the goal board fits one line")
	check(fits("千灯集市  /  " + game.title, 24, 366.0), "the title board holds the long level name")
	game.advance(); game.advance(); game.advance()
	check(game.state.stage == "approach", "the third line convenes the five stalls")
	game.skip_animation()
	check(game.state.stage == "ready" and game.buttons.has("next"), "ready offers the way to the street")
	game.advance(); settle(game)
	check(game.state.stage == "puzzle", "the street opens for drawing")
	check(game.buttons.has("deliver") and game.buttons["deliver"].text == "一次交上整条街",
		"submit commits the whole plan at once")
	check(game.buttons.has("undo") and game.buttons["undo"].disabled, "undo is idle before the first line")
	var absent = 0
	for index in range(Rules.COUNT):
		if not game.buttons.has("good_%d" % index): absent += 1
		if not game.buttons.has("tray_%d" % index): absent += 1
	check(absent == 0, "all five goods and all five trays are clickable")
	var rects = []
	for index in range(Rules.COUNT):
		rects.append(game.world.good_rect(index)); rects.append(game.world.tray_rect(index))
	var small = 0
	var outside = 0
	var overlap = 0
	for rect in rects:
		if rect.size.x < 48 or rect.size.y < 48: small += 1
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 720: outside += 1
	for first in range(rects.size()):
		for second in range(first + 1, rects.size()):
			if rects[first].intersects(rects[second]): overlap += 1
	check(small == 0, "every drop target is at least 48x48 logical pixels")
	check(outside == 0, "every hit target stays inside the 1280x720 frame")
	check(overlap == 0, "no two hit targets overlap")
	check(game.world.line_paths().is_empty(), "no line is drawn on an untouched street")
	game.choose_good(0); settle(game)
	check(game.state.hand == 0 and game.history.is_empty(), "picking up a good costs no undo step")
	check(game.world.line_paths().is_empty(), "holding a good draws no line")
	game.choose_tray(2); settle(game)
	check(game.state.lines == plan(-1, -1, 0, -1, -1) and not game.buttons["undo"].disabled,
		"connecting draws the line and enables undo")
	check(game.world.line_paths().size() == 1, "the world draws exactly the one line the player committed")
	check(game.world.draft().has(0), "the cloth is promised, not yet moved")
	check(game.world.goods_held() == [0, 1, 2, 3, 4], "the cloth is still hanging at 甲 while drafting")
	check(game.state.booked == Rules.empty_lines(), "the draft books nothing")
	check(game.status_line() == "线 1 / 5 · 满意 1 / 5", "the status restates the draft, computed by the rules")
	game.choose_tray(2); settle(game)
	check(game.state.lines == Rules.empty_lines() and game.world.line_paths().is_empty(),
		"tapping the filled tray pulls the line back")
	game.undo(); settle(game)
	check(game.state.lines == plan(-1, -1, 0, -1, -1), "undo brings the pulled line back")
	game.undo(); settle(game); game.undo(); settle(game)
	check(game.state.lines == Rules.empty_lines() and game.history.is_empty(), "the rewind consumes the drawn line")
	check(game.state.hand == 0, "the older snapshot hands the cloth back to the player, nothing else")
	game.choose_good(0); settle(game)
	check(game.state.hand == -1, "a rewound hand can be emptied again")
	game.choose_good(0); game.choose_tray(2); settle(game)
	game.choose_good(3); game.choose_tray(4); settle(game)
	check(game.state.lines == plan(-1, -1, 0, -1, 3), "two independent lines coexist")
	game.choose_good(1); game.choose_tray(0); settle(game)
	game.do_reset()
	check(game.state.lines == Rules.empty_lines() and game.state.stage == "puzzle",
		"重摆 pulls every line back without leaving the street")
	check(game.world.goods_held() == [0, 1, 2, 3, 4], "nothing moved in the world while the street was being drafted")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "open"; game.choose_good(0)
	check(game.modal and game.state.hand == -1 and FileAccess.get_file_as_bytes(path) == bytes,
		"a failed line save keeps the last written street")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(not game.modal and game.state.hand == 0, "retry republishes the same pick-up")
	game.choose_tray(2); settle(game)
	check(game.state.hand == -1 and game.state.lines[2] == 0, "the line takes the good out of the hand")
	game.choose_good(3); settle(game); game.choose_good(3); settle(game)
	check(game.state.hand == -1, "tapping the held good again lets go")
	for step in range(Rules.COUNT):
		if game.state.lines[step] >= 0: continue
		game.choose_good(Rules.SOLUTION[step]); game.choose_tray(step); settle(game)
	check(game.state.lines == Rules.SOLUTION, "the rest of the unique plan can be drawn by one hand")
	game.choose_tray(4); settle(game)
	check(game.state.lines == plan(1, 2, 0, 4, -1), "pulling the last line back leaves four of five")
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and game.message == "戊摊还没有接到线：它只认铃。",
		"submit refuses four lines and says which tray is still open")
	game.commit(build(plan(1, 2, 0, 0, -1))); settle(game); game.message = ""
	game.advance()
	check(game.state.stage == "puzzle" and game.message.begins_with("布同时许给了丙摊、丁摊"),
		"the double promise is drawable and fails at submit naming the cloth")
	game.commit(build(RING)); settle(game); game.message = ""
	game.advance()
	check(game.state.stage == "puzzle" and Rules.SHAPE_RING in game.message, "the five-ring is refused as a five-ring")
	game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINTS and "三摊就转成了一圈" in game.message,
		"the third hint demonstrates one step of the three-stall ring")
	game.hint()
	check(game.state.hint == Rules.HINTS and Rules.validate(game.state), "hints stop at the shipped tier count")
	check(game.hint_texts().size() == Rules.HINTS, "the hint bound matches the shipped hint count")
	var first_hint = game.hint_texts()[0]
	check("甲布" in first_hint and "戊绳" in first_hint, "the first tier restates who holds what")
	var second_hint = game.hint_texts()[1]
	check("丁" in second_hint and "戊" in second_hint, "the second tier narrows to the 丁/戊 pair")
	# 提示用掉的层数要跟着最后一次提交一起落盘：交表不会把用过的提示抹回 0。
	var final_plan = build(Rules.SOLUTION); final_plan.hint = game.state.hint
	game.commit(final_plan); settle(game)
	game.repository.fail_at = "flush"; game.advance()
	check(game.modal and game.state.stage == "puzzle" and game.state.booked == Rules.empty_lines(),
		"a failed exchange save cannot book any good")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(game.state.stage == "exchanging" and game.state.booked == Rules.SOLUTION,
		"retry books the whole street as one exchange")
	check(game.buttons.has("skip") and game.buttons.has("pause"), "the batched exchange can be paused or skipped")
	var carried = game.world.carry_plan(0.99)
	check(carried.size() == Rules.COUNT, "all five goods fly along the player's own lines")
	var flying = 0
	for lifted in carried:
		if lifted["phase"] < 1.0: flying += 1
	check(flying == 0, "at the end of the carry every good has landed")
	check(game.world.in_flight(game.world.carry_plan(0.05))["landed"].is_empty(), "the batch lifts off together")
	check(game.world.line_paths().size() == Rules.COUNT, "the performed exchange follows the booked plan")
	game.skip_animation(); settle(game)
	check(game.state.stage == "delivery" and game.world.goods_held() == Rules.SOLUTION,
		"the street settles with each stall holding what it accepted")
	check(game.status_line() == "满意 5 / 5", "every stall nods once the goods have landed")
	game.skip_animation(); settle(game)
	check(game.state.stage == "complete" and game.state.booked == Rules.SOLUTION, "the five stalls are swapped in one go")
	var on_disk = game.state.duplicate(true)
	check(game.buttons["next"].text == "重新体验" and game.buttons.has("open_hub"),
		"a standalone sample keeps its own exit")
	var boards = game.world.signs()
	var spill = 0
	for board in boards:
		if not fits(board["text"], 16, board["rect"].size.x - 20): spill += 1
	check(spill == 0, "all " + str(boards.size()) + " stall boards hold their own text")
	var receipt = 0
	for line in game.receipt_lines():
		if not fits(line, 18, game.receipt_text_rect().size.x): receipt += 1
	check(receipt == 0 and game.receipt_lines().size() == 7, "the receipt fits its panel and restates the booked plan")
	check(game.receipt_lines()[0] == "5 件货各走一次 · 5 摊点头", "the receipt header counts the whole batch")
	check("甲摊的布 → 丙摊" in game.receipt_lines()[1], "the receipt quotes the line the player drew")
	check("三摊转一圈，两摊对换" in game.receipt_lines()[6], "the receipt names the cycle shape")
	var lines_ok = true
	for stage in Rules.STAGES:
		game.state = build(Rules.SOLUTION, stage)
		game.world.state = game.state
		if not fits(game.line(), 20, 798.0): lines_ok = false
		if not fits(game.goal_line(), 22, 762.0): lines_ok = false
		if not fits(game.status_line(), 20, 300.0): lines_ok = false
		if len(game.line().split("\n")) > 2: lines_ok = false
		for hint in game.hint_texts():
			if not fits(hint, 20, 798.0) or hint.split("\n").size() > 2: lines_ok = false
	check(lines_ok, "every spoken, goal, status and hint line fits its board without auto-wrapping")
	# ---- 9b. 每一块中文文案按真实渲染字号（18/22/28）逐条量过 ----
	for stage in Rules.STAGES:
		var beats = Rules.BEATS if stage == "arrival" else 1
		for beat in range(beats):
			game.state = build(Rules.SOLUTION, stage); game.state.beat = beat
			game.world.state = game.state
			measure(game.line(), UIStyle.text_size(20), 798.0, 2, stage + " 的台词")
		game.state = build(Rules.SOLUTION, stage); game.world.state = game.state
		measure(game.status_line(), UIStyle.text_size(20), 300.0, 1, stage + " 的状态板")
		for key in game.stage_labels().keys():
			measure(game.stage_labels()[key], 20, 274.0, 1, "阶段按钮 " + key)
		for plate in game.world.signs():
			measure(plate["text"], 16, plate["rect"].size.x - 20.0, 1, stage + " 的街面木牌")
	game.state = build(Rules.SOLUTION, "complete"); game.world.state = game.state
	measure(game.goal_line(), UIStyle.text_size(22), 762.0, 1, "题面板")
	measure("千灯集市  /  " + game.title, UIStyle.text_size(24), 366.0, 1, "标题板")
	measure(game.submit_label(), 20, 235.0, 1, "提交按钮")
	for plate in [["回千灯航图", 280.0], ["返回千灯航图", 280.0], ["撤销 Z", 124.0], ["重摆 X", 110.0],
			["请扣扣提醒", 168.0], ["继续动画", 140.0], ["暂停动画", 140.0], ["跳过当前动画", 176.0]]:
		measure(plate[0], 20, plate[1], 1, "共用按钮")
	for draft in [Rules.empty_lines(), plan(3, 2, 0, 4, -1), plan(1, 2, 0, 0, -1), plan(0, 2, 1, 4, 3),
			plan(1, 2, 1, 4, 3), plan(1, 2, 0, 4, 4), RING]:
		for owed in Rules.shortfalls(build(draft)):
			measure(owed, UIStyle.text_size(20), 798.0, 2, "缺口说明")
	for tier in game.hint_texts():
		measure(tier, UIStyle.text_size(20), 798.0, 2, "三档提示")
	# 回执按 18 像素渲染（text_size(16)=18）、行距在场景里钉成 0：整块高度也得留在面板里。
	var pitch = typeface.get_height(UIStyle.text_size(16))
	var stacked = 0.0
	for row in game.receipt_lines():
		measure(row, UIStyle.text_size(16), game.receipt_text_rect().size.x, 1, "回执行")
		stacked += pitch
	check(stacked <= game.receipt_text_rect().size.y,
		"回执的 %d 行按 %d 像素行高装得下这块面板（%d）" % [game.receipt_lines().size(), int(pitch), int(game.receipt_text_rect().size.y)])
	# 牵线时贴近五摊，热点在 1.10 倍镜头下仍要留在画面里。
	game.state = build(Rules.SOLUTION, "puzzle"); game.world.state = game.state
	var offscreen = 0
	for index in range(Rules.COUNT):
		for rect in [game.world.good_rect(index), game.world.tray_rect(index)]:
			if rect.position.x * 1.10 - 64 < 0 or rect.position.y * 1.10 - 43 < 0: offscreen += 1
			if rect.end.x * 1.10 - 64 > 1280 or rect.end.y * 1.10 - 43 > 720: offscreen += 1
	check(offscreen == 0, "every hotspot stays on screen under the counter zoom")
	# 每个阶段都真重画一次：热点、按钮与世界层的派生数据都得活着。
	# 画布命令只能在 _draw 里发，所以这里挂上 draw 信号数一遍，而不是直接调 draw_level()。
	var repaint = 0
	# GDScript 的 lambda 按值捕获局部变量：计数要装进数组里，回调才写得到外面。
	var drawn = [0]
	var draw_probe = func(): drawn[0] += 1
	game.paused = true
	game.world.draw.connect(draw_probe)
	for stage in Rules.STAGES:
		game.state = build(Rules.SOLUTION, stage)
		game.world.state = game.state
		game.elapsed = 0.0
		for step in [0.0, 0.35, 0.6, 1.0]:
			game.world.progress = step
			if game.world.carry_plan(step).size() > Rules.COUNT: repaint += 1
			for path_value in game.world.line_paths():
				if path_value["points"].size() != 5: repaint += 1
			game.world.queue_redraw()
			await process_frame
		game.world.progress = 0.0
		game.refresh()
		if game.world.signs().is_empty(): repaint += 1
		if game.state.stage != stage: repaint += 1
	game.world.draw.disconnect(draw_probe)
	game.paused = false
	check(drawn[0] >= Rules.STAGES.size() * 4, "every stage and phase really ran the world's _draw")
	check(repaint == 0, "a repaint walk over every stage and phase draws without a single stray count")
	var clicks = 0
	for hotspot in game.world.get_children():
		if hotspot is Button and hotspot.text == "" and hotspot.size.x >= 48: clicks += 1
	check(clicks >= 0, "hotspots live in the world layer")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state == on_disk and game.state.stage == "complete" and game.state.booked == Rules.SOLUTION
		and game.state.hint == 3, "the booked exchange reloads from disk exactly as booked")
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
	print("MARKET MK09 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

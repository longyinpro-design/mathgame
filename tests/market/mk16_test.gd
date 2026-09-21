extends SceneTree
# MK16 给森林寄回一份礼物：无头规则、存档与真实场景检查。
# 运行：godot --headless --path . --script tests/market/mk16_test.gd
const Rules = preload("res://scripts/market/mk16_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Scene = preload("res://game/market_mk16.tscn")
const SAVE_DEFAULT = "user://profiles/market-mk16-1/save-v1.json"
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk16-rules-" + str(Time.get_ticks_usec()) + ".json"
var other = "/tmp/pixel-mk16-other-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 手工拼一份现场：非 arrival 幕必须已经听完三句台词，和 advance 的走位一致。
# 传进 packed 幕的 table 会被封成包裹，与玩家按下「封箱上红船」之后写进存档的一模一样。
func pose(table: Array, stage: String = "puzzle") -> Dictionary:
	var value = Rules.fresh()
	value.stage = stage
	value.table = table.duplicate(true)
	if stage != "arrival": value.beat = Rules.BEATS - 1
	# 走到码头之前台面是空的：打包台只在 puzzle 一幕才收得下货。
	if stage in ["arrival", "approach", "ready"]: value.table = []
	if stage in Rules.PACKED:
		var packed = table.duplicate(true)
		packed.sort()
		value.table = []
		value.gift = packed
		value.present = Rules.present_of(packed)
		value.sent = 1 if stage in Rules.SAILED else 0
	return value

func cup_pose(stage: String = "puzzle") -> Dictionary:
	return pose([Rules.LEAF, Rules.PAPER, Rules.CUP], stage)

func bell_pose(stage: String = "puzzle") -> Dictionary:
	return pose([Rules.LEAF, Rules.PAPER, Rules.BELL], stage)

# kit 图块真正占的那一块：底边贴脚点，按 manifest 的 anchor_px 往左上展开。
func kit_box(world: Node, id: String, foot: Vector2, width: float) -> Rect2:
	var texture: Texture2D = world.atlases[id]
	var item: Dictionary = world.parts[id]
	var scale = width / texture.get_width()
	return Rect2(foot - Vector2(item.anchor_px[0], item.anchor_px[1]) * scale,
		Vector2(texture.get_width(), texture.get_height()) * scale)

# 把所有 16 种摆法都过一遍，只把通过验收的那几组收回来。
func accepted_tables() -> Array:
	var accepted = []
	for mask in range(1 << Rules.KINDS.size()):
		var table = []
		for id in Rules.KINDS:
			if mask & (1 << id): table.append(id)
		if Rules.solved(pose(table)): accepted.append(table)
	return accepted

func named(missing: Array, word: String) -> bool:
	for line in missing:
		if word in line: return true
	return false

# 中文算整宽、数字与符号算半宽：招牌只有一到两行，超出就会写出版面外。
func units(text: String) -> float:
	var width = 0.0
	for character in text:
		width += 1.0 if character.unicode_at(0) > 0x2E00 else 0.55
	return width

# 货没落稳之前柜面不吃第二次点击（基类的 transient）。无头检查把落货一步读完，
# 真实手感与动画时长由窗口测（tests/market/mk16_playtest.gd）负责。
func pick(game: Node, ids: Array) -> void:
	for id in ids:
		game.transient = 0
		game.move_good(id)

func step(game: Node) -> void:
	game.transient = 0
	game.advance()

func rewind(game: Node) -> void:
	game.transient = 0
	game.undo()

func run() -> void:
	create_timer(40).timeout.connect(func(): push_error("MK16 rule watchdog"); quit(1))
	# ---- 开局状态与常量 ----
	check(Rules.validate(Rules.fresh()), "fresh model valid")
	check(Rules.fresh().sample == "market-mk16-1", "fresh carries the mk16 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens on the dock mouth")
	check(Rules.fresh().table == [] and Rules.fresh().gift == [], "fresh table and parcel are both empty")
	check(Rules.fresh().present == "" and Rules.fresh().sent == 0, "nothing is chosen or sailed yet")
	check(Rules.fresh().hint == 0, "fresh opens without a used hint")
	check(Rules.NAMES == ["绿叶章", "信纸", "杯", "铃"], "the four souvenirs are the authored ones")
	check(Rules.WEIGHTS == [2, 1, 4, 3], "leaf 2, paper 1, cup 4, bell 3 斤")
	check(Rules.LIMIT == 7 and Rules.PICKS == 3, "the parcel takes exactly 3 kinds up to 7 斤")
	check(Rules.MANDATORY == [Rules.LEAF, Rules.PAPER], "the forest badge and the writing paper are mandatory")
	check(Rules.CHOOSABLE == [Rules.CUP, Rules.BELL], "only the cup or the bell is the player's choice")
	check(Rules.SOLUTIONS == [[0, 1, 2], [0, 1, 3]], "both authored gifts are listed and both are legal")
	check(Rules.PRESENT_KEYS == ["", "", "cup", "bell"], "the integrator's parcel key has two values only")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "loading", "delivery", "complete"],
		"stage list is the three beats plus the walk-in and the sailing")
	check(Rules.ANIMATIONS == ["approach", "loading", "delivery"], "only the three transitions are animations")
	# ---- 数学：两条解、缺一不可、超重点名 ----
	check(accepted_tables() == Rules.SOLUTIONS, "exactly two of the sixteen layouts pass the parcel check")
	check(Rules.total([Rules.LEAF, Rules.PAPER, Rules.CUP]) == 7, "2+1+4 fills the 7 斤 limit exactly")
	check(Rules.total([Rules.LEAF, Rules.PAPER, Rules.BELL]) == 6, "2+1+3 stays under the limit")
	check(Rules.solved(cup_pose()) and Rules.solved(bell_pose()), "both authored gifts are legal parcels")
	check(Rules.solved(pose([Rules.CUP, Rules.LEAF, Rules.PAPER])), "the layout order never changes the verdict")
	check(not Rules.solved(pose([Rules.LEAF, Rules.CUP, Rules.BELL])), "a parcel without the paper is refused")
	check(not Rules.solved(pose([Rules.PAPER, Rules.CUP, Rules.BELL])), "a parcel without the badge is refused")
	check(not Rules.solved(pose([Rules.LEAF, Rules.PAPER])), "two kinds is not yet a gift")
	check(not Rules.solved(pose([])), "an empty table is not a gift")
	var four = pose([Rules.LEAF, Rules.PAPER, Rules.CUP, Rules.BELL])
	check(Rules.total(four.table) == 10, "badge + paper + cup + bell weigh 10 斤")
	var four_said = Rules.shortfalls(four)
	check(not four_said.is_empty() and "10" in four_said[0] and "7 斤" in four_said[0],
		"the four-kind refusal quotes the player's own 10 斤 against the 7 斤 limit")
	check(named(four_said, "绿叶章2 + 信纸1 + 杯4 + 铃3"), "and it names the goods the player actually put down")
	var nine = pose([Rules.LEAF, Rules.CUP, Rules.BELL])
	check(named(Rules.shortfalls(nine), "9"), "a three-kind parcel of 9 斤 is named by its own weight")
	check(named(Rules.shortfalls(nine), "信纸"), "the same parcel is also told the paper is missing")
	check(Rules.shortfalls(pose([Rules.CUP, Rules.BELL])).size() == 3, "cup and bell alone list weight, badge and paper")
	check(Rules.shortfalls(pose([])).size() == 3, "an untouched table lists the count and both mandatory items")
	check("恰好" in Rules.shortfalls(pose([Rules.LEAF]))[0], "one kind is told the count first")
	# ---- 上架与取下：真操作、不发明第二份 ----
	var table = pose([])
	var with_leaf = Rules.place(table, Rules.LEAF)
	check(with_leaf.table == [Rules.LEAF] and table.table == [], "placing the badge is a real move on the dock")
	check(Rules.place(with_leaf, Rules.LEAF).is_empty(), "the same souvenir cannot be booked twice")
	check("同一样纪念物不会有第二份" in Rules.refusal(with_leaf, Rules.LEAF), "a duplicate is refused in plain words")
	check(Rules.place(with_leaf, Rules.PAPER).table == [Rules.LEAF, Rules.PAPER], "the paper joins the badge")
	var loaded = Rules.place(Rules.place(with_leaf, Rules.PAPER), Rules.CUP)
	check(loaded.table == [Rules.LEAF, Rules.PAPER, Rules.CUP], "the cup is the third kind")
	check(Rules.place(loaded, Rules.BELL).is_empty(), "a fourth kind never reaches the table")
	var overweight = Rules.refusal(loaded, Rules.BELL)
	check("10" in overweight and "7 斤" in overweight and "铃" in overweight,
		"the fourth click names the player's own 10 斤 against the 7 斤 limit")
	check("绿叶章2 + 信纸1 + 杯4" in overweight, "and it lists what is already on the table")
	check(Rules.place(loaded, Rules.KINDS.size()).is_empty(), "a fifth souvenir does not exist on the shelf")
	check("货架上没有这一样" in Rules.refusal(loaded, 9) and "货架上没有这一样" in Rules.refusal(loaded, -1),
		"unknown ids are refused with their own reason")
	# 中文招牌不会自动折行：每一条拒绝与差处说明都要自己控制在两行、826 像素以内
	for said in four_said + Rules.shortfalls(nine) + Rules.shortfalls(pose([])) + [
			Rules.refusal(with_leaf, Rules.LEAF), overweight, Rules.refusal(loaded, 9)]:
		check(said.count("\n") <= 1, "the dock answer %s stays inside two lines" % said.left(4))
		for half in said.split("\n"):
			check(units(half) <= 36.0, "the dock answer %s fits the board width" % half.left(4))
	check(Rules.place(loaded, Rules.LEAF).is_empty() and Rules.lift(loaded, Rules.CUP).table == [Rules.LEAF, Rules.PAPER],
		"lifting the cup hands the third slot back")
	check(Rules.lift(table, Rules.LEAF).is_empty(), "an empty table cannot give anything back")
	check(Rules.place(pose([], "arrival"), Rules.LEAF).is_empty(), "nothing can be placed before the player walks in")
	check(Rules.place(pose([], "loading"), Rules.LEAF).is_empty(), "nothing can be placed while the parcel is tied")
	check(Rules.place(pose([], "complete"), Rules.LEAF).is_empty(), "nothing can be placed after the receipt")
	check(Rules.toggle(loaded, Rules.CUP).table == [Rules.LEAF, Rules.PAPER], "one click on a table item lifts it back")
	check(Rules.toggle(table, Rules.CUP).table == [Rules.CUP], "one click on a shelf item puts it down")
	# ---- 幕的推进 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "the first line hands over to the second")
	arriving = Rules.advance(arriving)
	check(arriving.beat == 2 and arriving.stage == "arrival", "the third beat is spoken before the walk-in")
	check(Rules.advance(arriving).stage == "approach", "the dock is reached only after the three lines")
	check(Rules.advance(Rules.advance(arriving)).stage == "ready", "the walk-in pauses once at the sign")
	var opened = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(opened.stage == "puzzle" and opened.table == [] and opened.gift == [], "the walk-in never touches the goods")
	check(Rules.advance(opened).is_empty(), "an unsolved table cannot be sealed")
	check(Rules.advance(pose([Rules.LEAF, Rules.CUP, Rules.BELL])).is_empty(), "a 9 斤 parcel cannot be sealed")
	var sealed = Rules.advance(cup_pose())
	check(sealed.stage == "loading" and sealed.gift == [0, 1, 2] and sealed.table == [],
		"sealing moves the three kinds from the table into the parcel")
	check(sealed.present == "cup" and sealed.sent == 0, "the parcel records the chosen charm but has not sailed")
	var bell_sealed = Rules.advance(bell_pose())
	check(bell_sealed.gift == [0, 1, 3] and bell_sealed.present == "bell", "the other gift seals as present=bell")
	check(Rules.advance(sealed).stage == "delivery" and Rules.advance(sealed).sent == 1, "the boat takes the parcel once")
	check(Rules.advance(Rules.advance(sealed)).stage == "complete", "the sailing ends the scene")
	check(Rules.advance(Rules.advance(Rules.advance(sealed))).is_empty(), "complete has no next stage to invent")
	check(Rules.advance(cup_pose("elsewhere")).is_empty(), "an unknown stage advances nowhere")
	check(Rules.advance(pose([], "arrival")).beat == 1, "a saved beat resumes on the next line")
	# ---- 撤销与快照往返 ----
	var solved_cup = cup_pose()
	check(Rules.restore(solved_cup, {"table": [Rules.LEAF, Rules.PAPER]}).table == [Rules.LEAF, Rules.PAPER],
		"undo hands the cup back to the shelf")
	check(Rules.restore(pose([Rules.LEAF]), {"table": [Rules.LEAF, Rules.PAPER]}).table == [Rules.LEAF, Rules.PAPER],
		"undo re-places a lifted souvenir")
	var kept = Rules.restore(solved_cup, {"table": [Rules.LEAF]})
	check(kept.stage == "puzzle" and kept.hint == 0 and kept.sample == "market-mk16-1",
		"undo only rewinds the table, never the scene")
	check(Rules.restore(pose([Rules.LEAF], "arrival"), {"table": []}).is_empty(), "undo only works at the packing table")
	check(Rules.restore(pose([], "delivery"), {"table": [Rules.LEAF]}).is_empty(), "undo cannot reach into the sailing")
	check(Rules.restore(solved_cup, {"goods": []}).is_empty(), "a snapshot without the table is refused")
	check(Rules.restore(solved_cup, {"table": [0, 1, 2, 3]}).is_empty(), "undo refuses a four-kind table")
	check(Rules.restore(solved_cup, {"table": [Rules.LEAF, Rules.LEAF]}).is_empty(), "undo refuses a duplicate")
	check(Rules.restore(solved_cup, {"table": [Rules.PAPER, Rules.CUP, Rules.BELL]}).is_empty(),
		"undo refuses an 8 斤 table the boat would never take")
	check(Rules.restore(solved_cup, {"table": [0, 1, 7]}).is_empty(), "undo refuses a souvenir that is not on the shelf")
	# ---- 存档 schema：损坏与非法状态 ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record " + str(bad))
	var forged = cup_pose("complete"); forged.sample = "market-mk12-1"
	check(not Rules.validate(forged), "another level's save is rejected")
	forged = cup_pose("complete"); forged.stage = "aboard"
	check(not Rules.validate(forged), "unknown stage rejected")
	forged = cup_pose(); forged.hint = 4
	check(not Rules.validate(forged), "hint level is capped by the shipped hints")
	forged = cup_pose(); forged.hint = -1
	check(not Rules.validate(forged), "a negative hint count is corruption")
	forged = cup_pose(); forged.beat = 1
	check(not Rules.validate(forged), "a stage past the walk-in cannot claim an unfinished dialogue")
	forged = pose([Rules.LEAF, Rules.PAPER, Rules.CUP, Rules.BELL])
	check(not Rules.validate(forged), "a four-kind table is corruption, not a wish")
	forged = pose([Rules.LEAF, Rules.LEAF])
	check(not Rules.validate(forged), "a duplicated souvenir is refused")
	forged = pose([Rules.LEAF, Rules.PAPER, 9])
	check(not Rules.validate(forged), "an unknown souvenir id is refused")
	forged = pose([Rules.PAPER, Rules.CUP, Rules.BELL])
	check(not Rules.validate(forged), "a table weighing 8 斤 is refused")
	forged = cup_pose(); forged.table = "leaf"
	check(not Rules.validate(forged), "a written table is not a packed one")
	forged = cup_pose(); forged.table = [0.5, 1, 2]
	check(not Rules.validate(forged), "a fractional souvenir is refused")
	forged = cup_pose(); forged.gift = [0, 1, 2]
	check(not Rules.validate(forged), "the parcel cannot be sealed before the player submits")
	forged = cup_pose("complete"); forged.table = [Rules.LEAF]
	check(not Rules.validate(forged), "goods cannot sit on the table and in the parcel at once")
	forged = pose([Rules.LEAF, Rules.PAPER], "complete")
	check(not Rules.validate(forged), "a two-kind parcel is refused at the receipt")
	forged = pose([Rules.LEAF, Rules.CUP, Rules.BELL], "complete")
	check(not Rules.validate(forged), "a parcel whose gift lacks the paper is refused")
	forged = pose([Rules.LEAF, Rules.PAPER, Rules.PAPER], "complete")
	check(not Rules.validate(forged), "a parcel claiming the same souvenir twice is refused")
	forged = cup_pose("complete"); forged.present = "bell"
	check(not Rules.validate(forged), "a parcel whose charm contradicts its contents is refused")
	forged = cup_pose("complete"); forged.present = ""
	check(not Rules.validate(forged), "a sealed parcel always records what the forest will read")
	forged = cup_pose("loading"); forged.sent = 1
	check(not Rules.validate(forged), "the parcel cannot be delivered before the boat leaves")
	forged = cup_pose("complete"); forged.sent = 2
	check(not Rules.validate(forged), "a gift cannot be claimed as delivered twice")
	forged = cup_pose(); forged.sent = 1
	check(not Rules.validate(forged), "an unsealed table cannot report a sailing")
	forged = pose([], "arrival"); forged.table = [Rules.LEAF]
	check(not Rules.validate(forged), "nothing is on the table before the player reaches the dock")
	forged = cup_pose("delivery"); forged.beat = 0
	check(not Rules.validate(forged), "the sailing cannot skip the dialogue either")
	forged = cup_pose("complete"); forged.gift = [0, 1, 2.0]
	check(not Rules.validate(forged) and Rules.validate(Content.normalize_numbers(forged)),
		"a whole number stored as a float is normalized back")
	check(Rules.validate(cup_pose("complete")) and Rules.validate(bell_pose("complete")),
		"both shipped gifts reload at the last stage")
	for stage in Rules.STAGES:
		check(Rules.validate(cup_pose(stage)), "stage %s is a legal save" % stage)
	var round_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(bell_pose("complete"))))
	check(round_trip == bell_pose("complete") and Rules.validate(round_trip),
		"the bell parcel survives a JSON round trip")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh())))),
		"the opening record survives a JSON round trip")
	# ---- 偏好改变回信、不改变主线奖励 ----
	var cup_receipt = Rules.gift_line(cup_pose("complete").gift)
	var bell_receipt = Rules.gift_line(bell_pose("complete").gift)
	check(cup_receipt == "绿叶章 2 斤 + 信纸 1 斤 + 杯 4 斤 = 7 斤", "the cup parcel is restated verbatim")
	check("7 斤" in cup_receipt and "6 斤" in bell_receipt, "each receipt weighs what the player chose")
	check(cup_receipt != bell_receipt, "the two receipts never read the same")
	check(Rules.reply_lines([0, 1, 2])[0] != Rules.reply_lines([0, 1, 3])[0],
		"the written reply follows the chosen souvenir")
	check(Rules.reply_lines([0, 1, 2]).slice(2) == Rules.reply_lines([0, 1, 3]).slice(2),
		"the reply's forest half stays the same for both gifts")
	check(Rules.REWARD in "x" + Rules.REWARD and Rules.REWARD == Rules.REWARD, "the reward line is one constant")
	check(Rules.sail_line([0, 1, 2]) != Rules.sail_line([0, 1, 3]), "the sailing line names what left the dock")
	check(Rules.chosen([0, 1, 2]) == Rules.CUP and Rules.chosen([0, 1, 3]) == Rules.BELL, "the charm is the chosen third")
	check(Rules.chosen([]) == -1 and Rules.present_of([]) == "", "an unsealed parcel has no charm yet")
	check(Rules.sum_text([]) == "空台面", "the empty table is described in the player's words")
	# ---- 台词与提示（离树探针，用完即释） ----
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == SAVE_DEFAULT, "the level defaults to the market-mk16-1 profile")
	probe.free()
	probe = Scene.instantiate(); probe.save_path = path; probe.configure()
	check(probe.save_path == path, "configure never overwrites an injected test path")
	check(probe.scene_id == "dock" and probe.level_id == "MK16", "the level declares its kit scene and id")
	check(probe.title == Catalog.title("MK16"), "the sign title matches the chapter catalogue")
	check(probe.rules == Rules and probe.world_script != null, "the host is wired to the mk16 rules and world")
	check(probe.durations.has("loading") and probe.zoom_stages.has("loading"), "the camera stays at the table while tying")
	check(probe.hint_texts().size() == Rules.HINTS, "three hints ship and no more")
	check(probe.submit_label() == "封箱上红船", "the submit button asks for the boat")
	for spoken in probe.hint_texts():
		check(not spoken.is_empty() and spoken.count("\n") <= 1, "hint %s stays inside two lines" % spoken.left(4))
		for half in spoken.split("\n"):
			check(units(half) <= 36.0, "hint line %s stays on the sign board" % half.left(4))
	probe.state = pose([])
	check("\n" not in probe.goal_line() and "\n" not in probe.status_line(), "the goal and status fit one line each")
	check(units(probe.goal_line()) <= 30.0, "the goal line fits the 790 pixel goal board")
	check("0/3" in probe.status_line() and "0 斤" in probe.status_line(), "the status counts the table in the player's words")
	probe.state = cup_pose()
	check("3/3" in probe.status_line() and "7 斤" in probe.status_line(), "the status follows the placed goods")
	for beat in range(Rules.BEATS):
		var opening = pose([], "arrival"); opening.beat = beat
		probe.state = opening
		var text = probe.line()
		check(not text.is_empty() and text.count("\n") <= 1, "arrival line %d stays inside the two-line board" % (beat + 1))
		for half in text.split("\n"):
			check(units(half) <= 36.0, "arrival line %d fits the board width" % (beat + 1))
	for stage in Rules.STAGES:
		probe.state = cup_pose(stage)
		check(not probe.line().is_empty() and probe.line().count("\n") <= 1, "stage %s speaks two lines at most" % stage)
		for half in probe.line().split("\n"):
			check(units(half) <= 36.0, "stage %s never runs past the board" % stage)
	for stage in ["arrival", "ready", "complete"]:
		probe.state = cup_pose(stage)
		check(not probe.stage_labels().has(stage) or not probe.stage_labels()[stage].is_empty(),
			"stage %s names its own next step" % stage)
	probe.state = cup_pose("complete")
	var cup_paper = probe.receipt_text()
	probe.state = bell_pose("complete")
	var bell_paper = probe.receipt_text()
	check(cup_paper != bell_paper, "the two endings really write different receipts")
	check(Rules.REWARD in cup_paper and Rules.REWARD in bell_paper, "both receipts promise the same main-line reward")
	check("白杯" in cup_paper and "铜铃" not in cup_paper, "the cup receipt only ever speaks of the cup")
	check("铃一响" in bell_paper and "白杯" not in bell_paper, "the bell receipt only ever speaks of the bell")
	for line in cup_paper.split("\n"):
		check(units(line) <= 24.0, "receipt line %s stays on the paper" % line.left(4))
	probe.state = cup_pose()
	check(probe.cleared_state().table == [Rules.LEAF, Rules.PAPER],
		"重摆 hands the chosen third back and keeps the mandatory two")
	probe.state = pose([Rules.LEAF, Rules.PAPER])
	check(probe.cleared_state().is_empty(), "重摆 invents nothing when only mandatory goods are down")
	probe.free()
	# ---- 真实场景：热点几何、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "a fresh scene opens on the dialogue")
	check(not game.buttons.has("deliver"), "the boat button waits for the packing table")
	check(game.world.scene_id == "dock", "the dock is drawn from the kit manifest")
	for name in ["packing", "boat_red", "boat_blue", "boss_foot", "lantern"]:
		check(game.world.stations.has(name), "the dock station %s is read from the manifest" % name)
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	game.commit(pose([]))
	check(game.state.stage == "puzzle" and game.history.is_empty(), "a saved table opens without history")
	var layouts = [
		[[], ["shelf_0", "shelf_1", "shelf_2", "shelf_3", "boat"]],
		[[Rules.LEAF], ["slot_0", "shelf_1", "shelf_2", "shelf_3", "boat"]],
		[[Rules.LEAF, Rules.PAPER], ["slot_0", "slot_1", "shelf_2", "shelf_3", "boat"]],
		[[Rules.LEAF, Rules.PAPER, Rules.CUP], ["slot_0", "slot_1", "slot_2", "shelf_3", "boat"]],
		[[Rules.LEAF, Rules.PAPER, Rules.BELL], ["slot_0", "slot_1", "slot_2", "shelf_2", "boat"]],
	]
	for layout in layouts:
		game.apply_committed(pose(layout[0]), [])
		var wanted = layout[1].duplicate(true)
		var sized = true
		var framed = true
		var tooltips = true
		for id in wanted:
			if not game.buttons.has(id): sized = false; framed = false; continue
			var button: Button = game.buttons[id]
			if button.size.x < 48 or button.size.y < 48: sized = false
			var rect = button.get_global_rect()
			if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
			if button.tooltip_text.is_empty(): tooltips = false
		check(sized, "layout %s registers 48 pixel targets" % str(layout[0]))
		check(framed, "layout %s keeps every target inside the frame" % str(layout[0]))
		check(tooltips, "layout %s signs every target in Chinese" % str(layout[0]))
		var stray: Array = []
		for id in game.buttons:
			if not wanted.has(id) and id not in ["undo", "reset", "hint", "deliver", "leave_hub"]:
				stray.append(id)
		check(stray.is_empty(), "layout %s adds no stray hotspot: %s" % [str(layout[0]), str(stray)])
		# 热点两两不相压：两块叠在一起，玩家点的是上面那块的名字，走的是下面那一件的剧情。
		var pairs: Array = []
		for first in wanted:
			for second in wanted:
				if first >= second: continue
				var left: Rect2 = game.buttons[first].get_global_rect()
				var right: Rect2 = game.buttons[second].get_global_rect()
				if left.intersects(right): pairs.append([first, second])
		check(pairs.is_empty(), "layout %s 的热点两两不重叠：%s" % [str(layout[0]), str(pairs)])
	game.apply_committed(pose([]), [])
	check(game.buttons.has("deliver") and not game.buttons.deliver.disabled, "the boat button is live on an empty table")
	check(game.buttons.has("undo") and game.buttons.undo.disabled, "nothing to undo on a fresh table")
	check(game.buttons.has("reset") and game.buttons.has("hint"), "the table offers 重摆 and 请扣扣提醒")
	# ---- 打包台那块读数牌：整块要在贴脸镜头里，字要装得下自己那块牌 ----
	game.apply_committed(pose([]), [])
	var board_rect = game.world.table_board()
	var view = game.world.get_transform()
	var shown_board = Rect2(view * board_rect.position, board_rect.size * view.get_scale().x)
	print("BOARD ", board_rect, " 镜头里 ", shown_board)
	check(shown_board.position.x >= 0.0 and shown_board.end.x <= 1280.0,
		"打包台那块读数牌整块留在贴脸镜头的窗框里，牌头的字不再被窗框切掉")
	check(absf(shown_board.position.x - 24.0) <= 2.0,
		"读数牌的左沿与顶上那块关卡名对齐（屏幕 x %.1f），不是贴着窗框硬塞" % shown_board.position.x)
	var under_plate: Array = []
	for id in game.buttons:
		if game.buttons[id].get_global_rect().intersects(shown_board): under_plate.append(id)
	check(under_plate.is_empty(),
		"读数牌底下不藏任何热点，玩家点牌子不会误交船：%s" % str(under_plate))
	var all_tables: Array = []
	var fit_worst := 0.0
	for mask in range(1 << Rules.KINDS.size()):
		var picks: Array = []
		for pick_id in range(Rules.KINDS.size()):
			if (mask >> pick_id) & 1: picks.append(pick_id)
		if picks.size() > Rules.PICKS: continue
		all_tables.append(picks)
		game.apply_committed(pose(picks), [])
		fit_worst = maxf(fit_worst, UIStyle.face().get_string_size(game.world.table_plaque(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	check(all_tables.size() == 15, "四样货取到三样以内的摆法共 %d 种，读数牌每一种都量过" % all_tables.size())
	check(fit_worst <= board_rect.size.x - 12.0,
		"读数牌最宽的一句 %.0f 装得进 %.0f 的内框" % [fit_worst, board_rect.size.x - 12.0])
	# ---- 红船那一泊：封箱、离岸、回执三幕逐帧量，包裹与吊牌不许躲进台词板 ----
	# 宿主那块台词条钉在屏幕 (338,98,826,86)、带阴影到 191，镜头推拉动不了它；
	# manifest 的 boat_red 在 (460,227)，船高 165、包裹 52、吊牌再加 40，整段正好落在板子里，
	# 于是「红船带着你选的那一件离岸」变成一句只有字在演的戏（实窗 09/10/13 三帧看到的）。
	var dialogue_board = Rect2(338, 92, 826, 99)
	var worst = 0.0
	var worst_at = ""
	var seen_frames = 0
	for stage in ["loading", "delivery", "complete"]:
		for look in [cup_pose(stage), bell_pose(stage)]:
			game.apply_committed(look, [])
			var steps = 1 if stage == "complete" else 20
			for frame in range(steps + 1):
				game.paused = true
				game.world.progress = float(frame) / float(steps)
				game.update_camera()
				if game.world.parcel_alpha() <= 0: continue
				seen_frames += 1
				var box = game.world.charm_box()
				var share = box.intersection(dialogue_board).get_area() / maxf(1.0, box.get_area())
				if share > worst:
					worst = share
					worst_at = "%s @%.2f %s" % [stage, game.world.progress, box]
	check(seen_frames >= 40, "两条分支三幕一共量到 %d 帧看得见包裹的画面" % seen_frames)
	print("PARCEL WORST ", worst, " at ", worst_at)
	check(worst < 0.05, "包裹最多被台词板盖住 %.0f%%（%s）：系在最外面的那一件全程看得见" % [worst * 100, worst_at])
	var berth = game.world.boat_foot()
	check(berth.y >= 300.0 and berth.y <= 400.0,
		"红船停在近岸的水道里（%s），船身与包裹都留在台词板下沿以外" % str(berth))
	# ---- 底栏读数：演出那一格念的是包裹，不是刚交出去的空台面 ----
	game.apply_committed(pose([Rules.LEAF, Rules.PAPER]), [])
	check(game.status_line() == "已选 2/3 · 共 3 斤", "摆货那一格底栏跟着台面走")
	game.apply_committed(cup_pose("loading"), [])
	check(game.status_line() == "已封箱 3 样 · 共 7 斤", "封箱演出里底栏改念包裹，不再报「已选 0/3」")
	game.apply_committed(bell_pose("delivery"), [])
	check(game.status_line() == "已封箱 3 样 · 共 6 斤", "离岸那一句报的是这条分支真正寄出去的 6 斤")
	# ---- 打包台上那张回执：五行字一行都不许出纸边 ----
	var letter_rows_seen = 0
	var letter_fill = 0.0
	for look in [cup_pose("delivery"), bell_pose("delivery")]:
		game.apply_committed(look, [])
		game.paused = true; game.world.progress = 1.0; game.update_camera()
		var paper = kit_box(game.world, "receipt_blank", game.world.station("packing"), 124.0)
		check(game.world.show_letter(), "%s 那一条把回执摊在打包台上" % look.present)
		for row in game.world.letter_rows():
			letter_rows_seen += 1
			var wide = UIStyle.face().get_string_size(row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, row[2]).x
			letter_fill = maxf(letter_fill, (row[1].x + wide - paper.position.x) / (paper.size.x - 8.0))
	check(letter_rows_seen == 10 and letter_fill <= 1.0,
		"两条分支共 %d 行回执文字，最宽的一行占到纸面 %.0f%%，没有一行出边" % [letter_rows_seen, letter_fill * 100])
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	for stage in Rules.STAGES:
		var looks = [pose([], stage)]
		if stage == "puzzle": looks.append(pose([Rules.LEAF, Rules.PAPER], stage))
		if stage in Rules.PACKED:
			looks.append(cup_pose(stage))
			looks.append(bell_pose(stage))
		for look in looks:
			game.apply_committed(look, [])
			for at in [0.0, 0.45, 1.0]:
				game.paused = true; game.world.progress = at; await process_frame
	check(is_instance_valid(game.world) and not game.modal, "every stage repaints without breaking the dock")
	game.paused = false
	# ---- 鼠标路径：放货、被拒、撤销 ----
	# 落货动画由本关 world 的 clock 记账（基类 transient 对 kit 关卡不生效，见交付文档），
	# 所以下面每一步都先把动画读完：两种行为下检查结果一致。
	game.apply_committed(pose([]), [])
	game.move_good(Rules.LEAF)
	check(game.state.table == [Rules.LEAF] and game.history.size() == 1, "clicking the badge puts it on the table")
	game.transient = 0
	game.move_good(Rules.LEAF)
	check(game.state.table == [], "the same click once more puts it back on the shelf")
	# 按下「封箱上红船」却还差承诺：柜面只按玩家自己摆下的数字回话
	pick(game, [Rules.LEAF, Rules.CUP])
	check(game.state.table == [Rules.LEAF, Rules.CUP], "the cup fits beside the badge")
	step(game)
	check(game.state.stage == "puzzle" and not game.modal, "an incomplete gift is never sealed by accident")
	check("6" in game.message and "信纸" in game.message,
		"the submit answer names the player's own 6 斤 and the missing paper")
	check(game.message.count("\n") <= 1 and units(game.message.get_slice("\n", 0)) <= 36.0,
		"the submit answer with its 还有 N 处 tail still fits the board")
	game.message = ""
	rewind(game); rewind(game)
	pick(game, [Rules.LEAF, Rules.PAPER, Rules.CUP])
	check(Rules.solved(game.state), "the mouse path can assemble the cup gift")
	game.transient = 0
	game.move_good(Rules.BELL)
	check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP] and "10" in game.message,
		"a fourth souvenir is refused with the player's own 10 斤")
	check("7 斤" in game.message and not game.modal, "the refusal stays a dock-side answer, not a scolding modal")
	check(game.history.size() == 5, "a refusal books no move: only the five real clicks are recorded")
	game.message = ""
	for back in range(5):
		rewind(game)
	check(game.state.table == [], "undo walks the whole table back to the shelf")
	check(game.history.is_empty(), "the rewind consumes every recorded step")
	check(game.buttons.undo.disabled, "nothing is left to undo once the shelf is whole again")
	# ---- 三级提示：递进、不判分、不代做 ----
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINTS and "10 斤" in game.message,
		"the third hint names the overweight and stops there")
	check(game.state.table == [], "no hint ever lays a souvenir down for the player")
	# ---- 重摆：只收回玩家那一点偏好，必带的两样留在台面 ----
	pick(game, [Rules.LEAF, Rules.PAPER, Rules.CUP])
	game.transient = 0
	game.confirm_reset()
	check(game.modal and game.buttons.has("confirm"), "重摆 asks before it touches the table")
	game.do_reset()
	check(game.state.table == [Rules.LEAF, Rules.PAPER],
		"重摆 keeps the mandatory two and returns the chosen third")
	# ---- 存档故障：一次动作要么整体生效，要么整体退回 ----
	pick(game, [Rules.BELL])
	check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.BELL], "the bell fills the third slot just as well")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.transient = 0; game.repository.fail_at = "replace"; game.move_good(Rules.BELL)
	check(game.modal and game.state.table == [Rules.LEAF, Rules.PAPER, Rules.BELL]
		and FileAccess.get_file_as_bytes(path) == bytes, "a save that cannot land leaves the table and the file alone")
	game.repository.fail_at = ""; game.retry_save()
	check(not game.modal and game.state.table == [Rules.LEAF, Rules.PAPER],
		"retry publishes the lift it had held back")
	# ---- 键盘路径：1-4 对着货板那一排，Z 撤销、空格寄出 ----
	var tap = InputEventKey.new()
	tap.pressed = true
	tap.keycode = KEY_3; tap.physical_keycode = KEY_3
	game.transient = 0; game._unhandled_key_input(tap)
	check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP], "the cup is laid down by key 3")
	tap.keycode = KEY_5; tap.physical_keycode = KEY_5
	game.transient = 0; game._unhandled_key_input(tap)
	check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP], "a key outside 1-4 lays nothing down")
	tap.keycode = KEY_4; tap.physical_keycode = KEY_4
	game.transient = 0; game._unhandled_key_input(tap)
	check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP] and "10" in game.message,
		"key 4 is refused with the same 10 斤 the mouse path reads")
	game.message = ""
	tap.keycode = KEY_2; tap.physical_keycode = KEY_2
	game.transient = 0; game._unhandled_key_input(tap)
	check(game.state.table == [Rules.LEAF, Rules.CUP], "key 2 lifts the paper back to the shelf")
	tap.keycode = KEY_Z; tap.physical_keycode = KEY_Z
	game.transient = 0; game._unhandled_key_input(tap)
	check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP], "Z puts the paper back down")
	# 提交这一下正好写不进盘：动画不该先替玩家把礼物寄出去
	game.repository.fail_at = "open"
	tap.keycode = KEY_SPACE; tap.physical_keycode = KEY_SPACE
	game.transient = 0; game._unhandled_key_input(tap)
	check(game.modal and game.state.stage == "puzzle" and game.state.gift == [],
		"a failed seal cannot start the loading animation")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "loading" and game.state.gift == [0, 1, 2],
		"retry seals the accepted gift into the parcel")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the loading animates with pause and skip")
	check(not game.buttons.has("shelf_0"), "the table hotspots are gone while the parcel is tied")
	game.skip_animation()
	check(game.state.stage == "delivery" and game.state.sent == 1, "the boat takes the parcel and says so once")
	game.skip_animation()
	check(game.state.stage == "complete" and Rules.validate(game.state), "the sailing ends on the receipt")
	check(game.buttons.has("next") and game.buttons.next.text == "再寄一份", "the last board offers to replay the scene")
	check(game.buttons.has("open_hub"), "a standalone sample still finds its way back to the chart")
	check(game.ui.get_child_count() > 2, "the receipt panel is drawn at the end")
	var cup_paper_on_disk = game.state.duplicate(true)
	var cup_card = ""
	for child in game.ui.get_children():
		if child is Label and "回执 · 给森林寄回的礼物" in child.text: cup_card = child.text
	check("白杯" in cup_card and "cup" == game.state.present, "the receipt and the parcel key agree")
	game.paused = true; game.queue_free(); await process_frame
	# ---- 读盘：偏好活过一次重载 ----
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state == cup_paper_on_disk, "the cup gift reloads from disk exactly as booked")
	check(game.state.present == "cup" and game.state.gift == [0, 1, 2], "the chosen souvenir survives a reload")
	check(not game.buttons.has("reset"), "a finished scene is not reset by an accidental click")
	game.queue_free(); await process_frame
	# ---- 第二条分支：铜铃，用另一份存档 ----
	game = Scene.instantiate(); game.save_path = other; root.add_child(game); await process_frame
	game.commit(pose([]))
	pick(game, [Rules.LEAF, Rules.PAPER, Rules.BELL])
	step(game)
	check(game.state.stage == "loading" and game.state.present == "bell", "the bell gift seals as its own parcel")
	game.skip_animation(); game.skip_animation()
	check(game.state.stage == "complete" and game.state.sent == 1, "the bell boat has sailed too")
	var bell_card = ""
	for child in game.ui.get_children():
		if child is Label and "回执 · 给森林寄回的礼物" in child.text: bell_card = child.text
	check(bell_card != cup_card and "铃一响" in bell_card, "the bell ending really reads differently")
	check(Rules.REWARD in bell_card and Rules.REWARD in cup_card,
		"both endings pay the same main-line reward")
	var on_bell = game.state.duplicate(true)
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = other; root.add_child(game); game.paused = true; await process_frame
	check(game.state == on_bell and game.state.present == "bell", "the bell choice reloads unchanged")
	game.queue_free(); await process_frame
	# ---- 中途存档与保护 ----
	var mid = cup_pose("loading")
	var writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(mid)); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "loading" and not game.modal, "an unfinished loading resumes instead of vanishing")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "the resumed loading can be paused or skipped again")
	check(Rules.validate(game.state), "the resumed stage is still a legal save")
	check(not game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
		"a running loading keeps the way out for later")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(cup_pose("complete"))); writer.close()
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
		"arriving from the chart offers only the way back")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin != "hub" and game.buttons.has("open_hub"), "a standalone launch finds the chart again")
	check(game.buttons.open_hub.text == "回千灯航图" and game.buttons.open_hub.size == Vector2(280, 54),
		"the exit button keeps the shipped contract")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	# ---- 目录一致性 ----
	check(Catalog.scene("MK16") == "res://game/market_mk16.tscn", "the catalogue points at the shipped scene")
	check(Catalog.save_path("MK16") == SAVE_DEFAULT, "the catalogue save path is the one this level writes")
	check(Catalog.LEVELS["MK16"].kit == "dock", "the catalogue keeps mk16 on the dock kit scene")
	check(Catalog.opens_after("MK16") == "MK12", "mk16 opens after the fifth act's last table")
	check(Catalog.is_side("MK16") and Catalog.act("MK16") == 5, "mk16 ships as an optional fifth-act side quest")
	check(ResourceLoader.exists(Catalog.scene("MK16")), "the chart can now light mk16 instead of 尚未制作")
	check(not Catalog.available("MK16", ["MK11"]), "mk16 stays dark until mk12 is lit")
	check(Catalog.available("MK16", ["MK12"]), "mk16 opens once mk12 is done")
	check(Catalog.goal("MK16") == "挑 3 样纪念物，带上绿叶章和信纸", "the chart's goal line matches the rules")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(other)
	print("MARKET MK16 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

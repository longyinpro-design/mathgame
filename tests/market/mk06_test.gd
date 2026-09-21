extends SceneTree
const Rules = preload("res://scripts/market/mk06_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk06.tscn")
const World = preload("res://scripts/market/mk06_world.gd")
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk06-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 一份可存档的现场：purchasing 之后订单与已买必须一致，由 build 负责守住这个不变式。
func build(a: int, b: int, c: int, stage: String = "puzzle") -> Dictionary:
	var state = Rules.fresh()
	state.stage = stage
	state.order = [a, b, c]
	state.bought = [a, b, c] if stage in ["purchasing", "delivery", "complete"] else [0, 0, 0]
	return state

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

# 落下动画只影响手感：清掉 it 再重画，热点的可用状态才与实窗一致。
func settle(game: Node) -> void:
	game.transient = 0.0
	game.refresh()

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("MK06 rule watchdog"); quit(1))
	# ---- 1. 开局现场 ----
	check(Rules.validate(Rules.fresh()), "fresh model validates")
	check(Rules.fresh().sample == "market-mk06-1", "fresh carries the mk06 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens at the arrival beats")
	check(Rules.fresh().order == [0, 0, 0] and Rules.fresh().bought == [0, 0, 0], "nothing is ordered or bought")
	check(Rules.fresh().hint == 0, "hints start unused")
	check(Rules.fresh().keys().size() == 6, "the profile carries exactly the six frozen fields")
	check(Rules.STICKS == [4, 3, 1] and Rules.PRICES == [7, 6, 3], "the three packages match the design sheet")
	check(Rules.BUDGET == 19 and Rules.ORDER_STICKS == 10, "budget 19 tickets for exactly 10 wicks")
	# ---- 2. 穷举：预算内解唯一，陷阱恰好 20 票 ----
	var mismatches = 0
	var exact = 0
	var affordable = []
	var dearest = 999
	var cheapest_over = 999
	for a in range(Rules.MAX_PER_KIND + 1):
		for b in range(Rules.MAX_PER_KIND + 1):
			for c in range(Rules.MAX_PER_KIND + 1):
				var order = [a, b, c]
				var wicks = Rules.sticks_of(order)
				var tickets = Rules.tickets_of(order)
				if Rules.paid_ok(order) != (wicks == 10 and tickets <= 19): mismatches += 1
				if Rules.solved(build(a, b, c)) != (wicks == 10 and tickets <= 19): mismatches += 1
				if wicks != 10: continue
				exact += 1
				dearest = mini(dearest, tickets)
				if tickets <= 19: affordable.append([order, tickets])
				else: cheapest_over = mini(cheapest_over, tickets)
	check(mismatches == 0, "343 order shapes agree with the hand-computed account")
	check(exact == 6, "six whole-package shapes hit exactly 10 wicks")
	check(affordable.size() == 1, "only one of them fits inside 19 tickets")
	check(affordable[0][0] == [1, 2, 0] and affordable[0][1] == 19, "1 pack of four + 2 packs of three costs 19")
	check(dearest == 19, "no 10-wick order is cheaper than 19 tickets")
	check(cheapest_over == 20, "the cheapest over-budget 10-wick order costs 20")
	var trap = [2, 0, 2]
	check(Rules.sticks_of(trap) == 10 and Rules.tickets_of(trap) == 20, "2 packs of four plus 2 loose wicks is 10 for 20")
	check(not Rules.paid_ok(trap) and not Rules.solved(build(2, 0, 2)), "the near miss is reachable but unpurchasable")
	check(Rules.PRICES[0] * Rules.STICKS[1] < Rules.PRICES[1] * Rules.STICKS[0], "the four pack is the cheapest per wick")
	check(Rules.PRICES[2] * Rules.STICKS[1] > Rules.PRICES[1], "the loose single is the dearest per wick")
	# ---- 3. 阶段机 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "arrival plays its lines in order")
	arriving = Rules.advance(arriving)
	check(arriving.beat == 2 and Rules.advance(arriving).stage == "approach", "the third line walks the player up to the stall")
	var walked = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(walked.stage == "puzzle" and walked.order == [0, 0, 0], "approach and ready never touch the goods")
	check(not (walked.stage in Rules.ANIMATIONS), "puzzle is not an animation stage")
	var single = true
	for stage in Rules.STAGES:
		if stage in ["arrival", "complete"]: continue
		var moved = Rules.advance(build(1, 2, 0, stage))
		if moved.is_empty(): single = false; continue
		if moved.stage != Rules.STAGES[Rules.STAGES.find(stage) + 1]: single = false
	check(single, "advance only ever moves one stage forward")
	check(Rules.advance(build(0, 0, 0)).is_empty(), "an empty order cannot be submitted")
	check(Rules.advance(build(2, 0, 0)).is_empty(), "8 wicks block the purchase")
	check(Rules.advance(build(2, 0, 1)).is_empty(), "9 wicks block the purchase")
	check(Rules.advance(build(2, 1, 0)).is_empty(), "11 wicks block the purchase")
	check(Rules.advance(build(2, 0, 2)).is_empty(), "20 tickets block the purchase")
	var booked = Rules.advance(build(1, 2, 0))
	check(booked.stage == "purchasing" and booked.bought == [1, 2, 0], "submit books the whole order at once")
	check(Rules.sticks_of(booked.bought) == 10 and Rules.tickets_of(booked.bought) == 19, "the booked order is the unique paid plan")
	check(Rules.advance(booked).stage == "delivery" and Rules.advance(booked).bought == [1, 2, 0], "the carry does not re-book anything")
	check(Rules.advance(Rules.advance(booked)).stage == "complete", "hanging the string closes the scene")
	check(Rules.advance(build(1, 2, 0, "complete")).is_empty(), "complete has no next stage")
	# ---- 4. 拿包与放回 ----
	var table = build(0, 0, 0)
	check(Rules.take_package(Rules.fresh(), 0).is_empty(), "no package before the table opens")
	check(Rules.take_package(table, -1).is_empty() and Rules.take_package(table, Rules.KINDS).is_empty(),
		"unknown package kinds are refused")
	var one = Rules.take_package(table, 0)
	check(one.order == [1, 0, 0] and one.bought == [0, 0, 0], "taking a pack only writes the order sheet")
	check(Rules.sticks_of(one.order) == 4 and Rules.tickets_of(one.order) == 7, "the totals are computed, not accumulated")
	check(table.order == [0, 0, 0], "the previous state is left untouched")
	var stacked = table
	for step in range(Rules.MAX_PER_KIND): stacked = Rules.take_package(stacked, 1)
	check(stacked.order == [0, 6, 0], "a row fills up to six packs")
	check(Rules.take_package(stacked, 1).is_empty(), "a seventh pack is refused")
	check(not Rules.can_return(stacked, 0, 0), "an empty row cannot give anything back")
	check(Rules.return_package(stacked, 1, 6).is_empty() and Rules.return_package(stacked, 1, -1).is_empty(),
		"row slots outside the sheet are refused")
	var back = Rules.return_package(stacked, 1, 5)
	check(back.order == [0, 5, 0] and Rules.tickets_of(back.order) == 30, "putting a pack back takes it off the bill")
	var wiped = back
	while not wiped.is_empty() and wiped.order[1] > 0: wiped = Rules.return_package(wiped, 1, wiped.order[1] - 1)
	check(wiped.order == [0, 0, 0] and Rules.tickets_of(wiped.order) == 0, "adding then removing leaves no phantom charge")
	check(Rules.validate(wiped), "the sheet is still a legal save after the round trip")
	for stage in ["arrival", "approach", "ready", "purchasing", "delivery", "complete"]:
		var locked = build(1, 2, 0, stage)
		check(Rules.take_package(locked, 0).is_empty() and Rules.return_package(locked, 0, 0).is_empty(),
			"the order sheet is frozen during "+stage)
	# ---- 5. 撤销快照 ----
	var snap = {"order": [1, 2, 0], "bought": [0, 0, 0]}
	check(Rules.restore(Rules.take_package(build(1, 2, 0), 2), snap).order == [1, 2, 0], "undo rewinds a taken pack")
	check(Rules.restore(Rules.return_package(build(1, 2, 0), 0, 0), snap).order == [1, 2, 0], "undo rewinds a returned pack")
	var every = 0
	for kind in range(Rules.KINDS):
		for step in range(Rules.MAX_PER_KIND):
			var prior_order = [0, 0, 0]; prior_order[kind] = step
			var prior = build(prior_order[0], prior_order[1], prior_order[2])
			var after = Rules.take_package(prior, kind)
			if Rules.restore(after, {"order": prior.order, "bought": prior.bought}).order != prior.order: every += 1
	check(every == 0, "every add in reach round-trips through the undo snapshot")
	check(Rules.restore(build(0, 0, 0, "arrival"), snap).is_empty(), "undo only works at the order board")
	check(Rules.restore(build(1, 2, 0, "purchasing"), snap).is_empty(), "undo cannot reopen a paid order")
	check(Rules.restore(build(1, 2, 0), {"order": [1, 2, 0]}).is_empty(), "a snapshot without the paid record is refused")
	check(Rules.restore(build(1, 2, 0), {"order": [7, 0, 0], "bought": [0, 0, 0]}).is_empty(),
		"undo refuses an out-of-range sheet")
	check(Rules.restore(build(1, 2, 0), {"order": [1, 2, 0], "bought": [1, 2, 0]}).is_empty(),
		"undo refuses a paid record at the board")
	# ---- 6. 提交反馈：数量不对与票不够分别说清 ----
	check(Rules.shortfalls(build(0, 0, 0)) == ["面包铺要恰好 10 根灯芯：订单上只有 0 根，还差 10 根。"],
		"an empty sheet names the missing wicks")
	check("还差 2 根" in Rules.shortfalls(build(2, 0, 0))[0], "8 wicks are reported as a shortfall")
	check("多了 1 根" in Rules.shortfalls(build(2, 1, 0))[0], "11 wicks are reported as an overshoot")
	check(Rules.shortfalls(build(2, 0, 2)) == ["这单要 20 票，手里只有 19 票。"], "the trap is refused in the player's own words")
	var both = Rules.shortfalls(build(3, 1, 1))
	check(both.size() == 2 and "16 根" in both[0] and "30 票" in both[1], "a wrong count and an overspend are two separate duties")
	check("票" not in both[0] and "手里只有" in both[1], "the count message never talks about tickets")
	check(Rules.shortfalls(build(1, 2, 0)).is_empty() and Rules.solved(build(1, 2, 0)), "the unique plan has no shortfall")
	# ---- 7. 存档 schema ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record "+str(bad))
	var piece = build(1, 2, 0); piece.sample = "market-mk02-1"
	check(not Rules.validate(piece), "a foreign sample is rejected")
	piece = build(1, 2, 0); piece.stage = "shopping"
	check(not Rules.validate(piece), "an unknown stage is rejected")
	piece = build(1, 2, 0); piece.order[0] = -1
	check(not Rules.validate(piece), "negative pack counts are rejected")
	piece = build(1, 2, 0); piece.order[0] = Rules.MAX_PER_KIND + 1
	check(not Rules.validate(piece), "oversized pack counts are rejected")
	piece = build(1, 2, 0); piece.order[1] = 1.5
	check(not Rules.validate(piece), "a fractional pack count is corruption")
	piece = build(1, 2, 0); piece.order[2] = "2"
	check(not Rules.validate(piece), "a string count is corruption")
	piece = build(1, 2, 0); piece.order = [1, 2]
	check(not Rules.validate(piece), "a short order array is corruption")
	piece = build(1, 2, 0); piece.erase("bought")
	check(not Rules.validate(piece), "a missing field is corruption, not a default")
	piece = build(1, 2, 0); piece.hint = Rules.HINT_TIERS + 1
	check(not Rules.validate(piece), "hint level is capped")
	piece = build(1, 2, 0); piece.hint = -1
	check(not Rules.validate(piece), "hints cannot go negative")
	piece = build(1, 2, 0); piece.beat = 3
	check(not Rules.validate(piece), "arrival beats are bounded")
	piece = build(1, 2, 0, "arrival")
	check(not Rules.validate(piece), "the walk-in cannot carry an order")
	piece = build(1, 2, 0, "puzzle"); piece.bought = [1, 2, 0]
	check(not Rules.validate(piece), "the board cannot hold a paid record")
	piece = build(0, 0, 0, "complete")
	check(not Rules.validate(piece), "a clear with nothing bought is a forged receipt")
	piece = build(2, 0, 2, "complete")
	check(not Rules.validate(piece), "a clear whose order was never affordable is rejected")
	piece = build(2, 0, 2, "delivery")
	check(not Rules.validate(piece), "the 20-ticket plan cannot hang a lantern")
	piece = build(2, 1, 2, "purchasing")
	check(not Rules.validate(piece), "a staged purchase must total ten wicks")
	piece = build(1, 2, 0, "complete"); piece.order = [1, 2, 1]
	check(not Rules.validate(piece), "the paid record must match the sheet it came from")
	piece = build(1, 2, 0, "purchasing"); piece.bought = [0, 3, 1]
	check(not Rules.validate(piece), "a purchase cannot be swapped mid-animation")
	check(Rules.validate(build(1, 2, 0, "purchasing")), "a staged purchase is a legal save")
	check(Rules.validate(build(1, 2, 0, "delivery")), "a hung string is a legal save")
	check(Rules.validate(build(1, 2, 0, "complete")), "the cleared scene is a legal save")
	var capped = build(1, 2, 0); capped.hint = Rules.HINT_TIERS
	check(Rules.validate(capped), "the top hint tier is inside the bound")
	# ---- 8. 章节目录与本关身份 ----
	var entry = Catalog.LEVELS["MK06"]
	check(entry.scene == "res://game/market_mk06.tscn", "the catalog points at the shipped scene path")
	check(ResourceLoader.exists(entry.scene) and Catalog.built("MK06"), "the scene file exists so the chart lights up")
	check(entry.save == "user://profiles/market-mk06-1/save-v1.json", "the catalog save path is the mk06 profile")
	check(entry.kit == "street" and entry.act == 3 and entry.after == "MK05", "act 3, street kit, opens after MK05")
	check(entry.title == "十根灯芯怎么凑", "the catalog title is the level title")
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == Catalog.save_path("MK06"), "configure only fills the catalog save path as a default")
	check(probe.scene_id == "street" and probe.level_id == "MK06", "the scene declares its own identity")
	check(probe.rules == Rules and probe.world_script.resource_path.ends_with("mk06_world.gd"), "the host is wired to mk06")
	check(probe.durations.has("purchasing") and probe.durations.has("delivery"), "the host owns the stage durations")
	probe.free()
	# ---- 9. 真实场景：按钮、热点、存档事务 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.save_path == path, "an injected test path survives configure")
	check(game.state.stage == "arrival", "a new profile opens on the arrival beats")
	check(game.buttons.has("next") and game.buttons["next"].text == "继续听他们说", "the first beat only asks to keep listening")
	check(fits(game.line(), 20, 798.0), "the arrival line fits the spoken board")
	check(fits(game.goal_line(), 22, 762.0), "the goal board fits one line")
	game.advance(); game.advance(); game.advance()
	check(game.state.stage == "approach", "the third line starts the walk-in")
	game.skip_animation()
	check(game.state.stage == "ready" and game.buttons.has("next"), "ready offers the way to the board")
	game.advance(); settle(game)
	check(game.state.stage == "puzzle", "the board opens")
	check(game.buttons.has("deliver") and game.buttons["deliver"].text == "一次付清这一单", "submit is one batched purchase")
	check(game.buttons.has("undo") and game.buttons["undo"].disabled, "undo is idle before the first pack")
	var absent = 0
	for kind in range(Rules.KINDS):
		if not game.buttons.has("take_%d" % kind): absent += 1
	check(absent == 0, "all three package stacks are clickable")
	var rects = []
	for kind in range(Rules.KINDS):
		rects.append(game.world.stall_rect(kind))
		for slot in range(Rules.MAX_PER_KIND): rects.append(game.world.order_rect(kind, slot))
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
	# 贴脸镜头（1.10、整体偏移 -64/-43）下扣扣不能被窗框切掉，也不能压住柜面上的票匣与付清单据。
	game.state.stage = "puzzle"; game.world.state = game.state; game.world.progress = 0.0
	var keeper = game.world.koukou_rect()
	check(keeper.end.x * 1.10 - 64 <= 1280.0 and keeper.position.x * 1.10 - 64 >= 0.0,
		"the counter keeper stays inside the frame under the close-up camera")
	check(keeper.position.x > 1014.0 and keeper.position.x > game.world.paid_slip_foot().x + World.PAID_SLIP_WIDTH / 2.0,
		"she stands clear of the ticket box and of the paid slip on the counter")
	game.do_take(0); settle(game)
	check(game.state.order == [1, 0, 0] and not game.buttons["undo"].disabled, "taking a pack writes the sheet and enables undo")
	check(game.buttons.has("row_0_0"), "the ordered pack becomes its own return target")
	game.do_take(2); settle(game); game.do_take(2); settle(game)
	check(game.state.order == [1, 0, 2] and game.status_line() == "订单 6 根 · 13 / 19 票", "the sheet restates the running totals")
	game.do_return(2, 1); settle(game)
	check(game.state.order == [1, 0, 1] and Rules.tickets_of(game.state.order) == 10, "a returned pack leaves the bill")
	game.undo(); settle(game)
	check(game.state.order == [1, 0, 2], "undo rewinds through the host")
	game.undo(); settle(game); game.undo(); settle(game); game.undo(); settle(game)
	check(game.state.order == [0, 0, 0] and game.history.is_empty(), "the rewind consumes every recorded step")
	# 空行上按 Q/W/E：不能听到「那一包已经放回摊位了」——这一摊什么都没拿过。
	game.handle_key(KEY_Q)
	check(game.message == "%d 根那一类还没有包在订单上。" % Rules.STICKS[0] and game.state.order == [0, 0, 0],
		"returning from an empty row names the row instead of inventing a returned pack")
	game.do_take(0); settle(game); game.do_take(1); settle(game); game.do_take(1); settle(game)
	game.do_reset()
	check(game.state.order == [0, 0, 0] and game.state.stage == "puzzle", "重摆 clears the sheet without leaving the stall")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "open"; game.do_take(0)
	check(game.modal and game.state.order == [0, 0, 0] and FileAccess.get_file_as_bytes(path) == bytes,
		"a failed sheet save keeps the last written order")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(not game.modal and game.state.order == [1, 0, 0], "retry republishes the same order")
	game.message = ""; game.advance()
	check(game.state.stage == "puzzle" and "还差 6 根" in game.message, "submit refuses 4 wicks and says what is missing")
	game.commit(build(2, 0, 2)); settle(game); game.message = ""
	game.advance()
	check(game.state.stage == "puzzle" and game.message == "这单要 20 票，手里只有 19 票。",
		"the 20-ticket near miss is selectable and fails at submit")
	game.hint(); game.hint(); game.hint()
	check(game.state.hint == Rules.HINT_TIERS and "局部便宜" in game.message, "the third hint points at local value versus the whole order")
	game.hint()
	check(game.state.hint == Rules.HINT_TIERS and Rules.validate(game.state), "hints stop at the shipped tier count")
	check(game.hint_texts().size() == Rules.HINT_TIERS, "the hint bound matches the shipped hint count")
	var third = game.hint_texts()[2]
	check("20 票" in third and not ("×2" in third or "2 包三根" in third), "the last hint names the trap without giving the plan")
	var paid = build(1, 2, 0); paid.hint = game.state.hint
	game.commit(paid); settle(game)
	game.repository.fail_at = "flush"; game.advance()
	check(game.modal and game.state.stage == "puzzle" and game.state.bought == [0, 0, 0],
		"a failed purchase save cannot book the order")
	game.repository.fail_at = ""; game.retry_save(); settle(game)
	check(game.state.stage == "purchasing" and game.state.bought == [1, 2, 0], "retry books the whole batch as one purchase")
	check(game.buttons.has("skip") and game.buttons.has("pause"), "the batched carry can be paused or skipped")
	var plan = game.world.carry_plan(0.25)
	check(plan.size() == 3, "the carry plan lifts all three bought packs together")
	check(game.world.hide_while_moving(plan).size() == 3, "the packs leave their row slots while the batch is in the air")
	check(game.world.shown_order() == game.state.order, "the sheet still lists the order mid-flight")
	check(game.world.ticket_plan(0.25).is_empty() and game.world.ticket_plan(0.99).size() == Rules.BUDGET,
		"all nineteen tickets fly out only after the goods have landed")
	game.skip_animation(); settle(game)
	check(game.state.stage == "delivery" and game.world.tickets_left() == 0, "the string goes up with an empty ticket box")
	game.skip_animation(); settle(game)
	check(game.state.stage == "complete" and game.state.bought == [1, 2, 0], "the first warm string is hung")
	var on_disk = game.state.duplicate(true)
	check(game.buttons["next"].text == "重新体验" and game.buttons.has("open_hub"), "a standalone sample keeps its own exit")
	var boards = game.world.signs()
	var spill = 0
	for board in boards:
		if not fits(board["text"], 16, board["rect"].size.x - 20): spill += 1
	check(spill == 0, "all "+str(boards.size())+" stall boards hold their own text")
	var receipt = 0
	for line in game.receipt_lines():
		if not fits(line, 16, 270.0): receipt += 1
	check(receipt == 0 and game.receipt_lines().size() == 6, "the receipt fits its panel and restates the paid order")
	check("×1" in game.receipt_lines()[1] and "×2" in game.receipt_lines()[2], "the receipt counts what the player bought")
	var lines_ok = true
	for stage in Rules.STAGES:
		game.state = build(1, 2, 0, stage)
		if not fits(game.line(), 20, 798.0): lines_ok = false
		if not fits(game.goal_line(), 22, 762.0): lines_ok = false
		if not fits(game.status_line(), 20, 300.0): lines_ok = false
		for hint in game.hint_texts():
			if not fits(hint, 20, 798.0) or hint.split("\n").size() > 2: lines_ok = false
	check(lines_ok, "every spoken, goal, status and hint line fits its board without auto-wrapping")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state == on_disk and game.state.stage == "complete" and game.state.bought == [1, 2, 0] and game.state.hint == 3,
		"the paid order reloads from disk exactly as booked")
	Bridge.origin = "hub"
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "the chart hand-off is consumed once")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"), "finishing from the chart returns to the chart")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK06 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

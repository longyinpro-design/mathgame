extends SceneTree
const Rules = preload("res://scripts/market/mk02_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Scene = preload("res://game/market_mk02.tscn")
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk02-rules-"+str(Time.get_ticks_usec())+".json"
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)

func flags(mask: int, slots: int) -> Array:
	var result = []
	for slot in range(slots): result.append((mask >> slot) & 1)
	return result

func build(a: int, b: int, rack: int, hook: int, stage: String = "puzzle") -> Dictionary:
	var state = Rules.fresh(); state.stage = stage
	state.a = a; state.b = b
	state.rack = flags(rack,Rules.RACK_SLOTS); state.hook = flags(hook,Rules.HOOK_SLOTS)
	return state

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("MK02 rule watchdog"); quit(1))
	check(Rules.validate(Rules.fresh()),"fresh model valid")
	check(Rules.fresh().rack == [0,0,0,0,0] and Rules.fresh().hook == [0,0],"fresh sample has an empty rack and bench")
	# Every placement in reach is compared against a hand-written account of the goods.
	var mismatches = 0
	var winners = 0
	for a in range(0,5):
		for b in range(0,7):
			for rack in range(1 << Rules.RACK_SLOTS):
				for hook in range(1 << Rules.HOOK_SLOTS):
					var state = build(a,b,rack,hook)
					var spools = Rules.SPOOL_PER_GROUP*a-Rules.GROUP*b-flags(hook,Rules.HOOK_SLOTS).count(1)
					var wicks = Rules.WICK_PER_GROUP*b-flags(rack,Rules.RACK_SLOTS).count(1)
					var reachable = spools >= 0 and wicks >= 0
					if Rules.validate(state) != reachable: mismatches += 1
					if not reachable: continue
					var promised = a == 4 and b == 5 and rack == 31 and hook == 3
					if Rules.solved(state) != promised: mismatches += 1
					if Rules.solved(state): winners += 1
	check(mismatches == 0,"4480 placement states agree with the goods account")
	check(winners == 1,"exactly one placement satisfies both promises")
	# Whole-group exchange: the pool is spent two at a time and nothing is invented.
	var empty = Rules.fresh(); empty.stage = "puzzle"
	check(Rules.affordable(empty,0) == 4 and Rules.affordable(empty,1) == 0,"the basket opens with four fruit groups")
	check(Rules.exchange(empty,0,5).is_empty() and Rules.exchange(empty,0,0).is_empty(),"group counts outside the pool are refused")
	check(Rules.exchange(empty,1,1).is_empty(),"no line-to-wick exchange without line on the table")
	var half = build(3,0,0,0)
	check(Rules.affordable(half,0) == 1 and Rules.exchange(half,0,2).is_empty(),"a pair of fruits makes exactly one more group")
	var trapped = build(4,6,31,0)
	check(Rules.validate(trapped) and not Rules.solved(trapped),"all-line trap a=4 b=6 is legal but unsolved")
	check(Rules.shortfalls(trapped)[0] == "扣扣的捆货绳还差 2 卷线。","the trap names the unmet promise first")
	check(Rules.shortfalls(trapped).size() == 2,"the trap reports the loose wick as well")
	var partial = build(4,4,31,0)
	check(Rules.shortfalls(partial) == ["扣扣的捆货绳还差 2 卷线。","台面上还有 4 卷线没归位：挂上修补台，或者换成灯芯。"],"a half plan lists both remaining duties")
	# One good, one owner.
	check(Rules.put_rack(empty,0).is_empty() and Rules.put_hook(empty,0).is_empty(),"nothing can be placed before it was exchanged")
	var wicks_ready = build(2,2,0,0)
	var placed = Rules.put_rack(wicks_ready,2)
	check(placed.rack == [0,0,1,0,0] and Rules.wicks_loose(placed) == 1,"a wick takes one rack slot and leaves the table")
	check(Rules.put_rack(placed,2).is_empty(),"an occupied rack slot is not double booked")
	check(Rules.take_rack(placed,0).is_empty() and Rules.take_rack(placed,2).rack == [0,0,0,0,0],"only a filled slot returns to the table")
	var spools_ready = build(4,0,0,0)
	var hung = Rules.put_hook(Rules.put_hook(spools_ready,1),0)
	check(hung.hook == [1,1] and Rules.spools_loose(hung) == 10,"the bench keeps exactly two spools")
	check(Rules.put_hook(hung,0).is_empty(),"a filled hook cannot take a third spool")
	# Stages: an exchange only lands once it has been saved and advanced.
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival","arrival plays its lines in order")
	arriving = Rules.advance(arriving)
	check(Rules.advance(arriving).stage == "approach" and arriving.beat == 2,"the third line walks the player in")
	arriving = Rules.advance(Rules.advance(Rules.advance(arriving)))
	check(arriving.stage == "puzzle" and arriving.a == 0,"approach and ready never touch the goods")
	check(Rules.advance(arriving).is_empty(),"an unsolved table cannot be handed over")
	var pending = Rules.exchange(arriving,0,4)
	check(pending.stage == "exchanging" and pending.exchange == [0,4] and pending.a == 0,"a batch is staged, not booked")
	var booked = Rules.advance(pending)
	check(booked.a == 4 and booked.b == 0 and booked.exchange.is_empty() and booked.stage == "puzzle","advance books exactly the staged group count")
	check(Rules.advance(build(4,5,31,3,"puzzle")).stage == "delivery","a solved table releases the delivery")
	check(Rules.advance(build(4,5,31,2,"puzzle")).is_empty(),"one missing spool blocks the hand-over")
	check(Rules.advance(build(3,3,7,3,"puzzle")).is_empty(),"fruits left in the basket block the order")
	# Undo rewinds placements and exchanges through the same snapshot.
	var snapshot = {"a":4,"b":5,"rack":flags(31,Rules.RACK_SLOTS),"hook":flags(3,Rules.HOOK_SLOTS)}
	var trail = Rules.take_rack(build(4,5,31,3),4)
	check(Rules.restore(trail,snapshot).rack == snapshot.rack,"undo restores the delivered rack")
	check(Rules.restore(trail,{"a":4,"b":6,"rack":snapshot.rack,"hook":snapshot.hook}).is_empty(),"undo refuses a state that breaks the goods account")
	check(Rules.restore(build(0,0,0,0,"arrival"),snapshot).is_empty(),"undo only works at the exchange table")
	# The save schema rejects forged or half-finished records.
	for bad in [null,{},[],"x",5.0,[0,0]]: check(not Rules.validate(bad),"reject record "+str(bad))
	var forged = build(4,5,31,3,"complete"); forged.b = 6
	check(not Rules.validate(forged),"a receipt cannot claim more line than the basket held")
	forged = build(4,5,31,3,"complete"); forged.rack[4] = 0
	check(not Rules.validate(forged),"delivery without five wicks rejected")
	check(not Rules.validate(build(0,0,0,0,"exchanging")),"an empty pending exchange is corruption")
	forged = build(0,0,0,0,"exchanging"); forged.exchange = [1,1]
	check(not Rules.validate(forged),"a pending exchange must be affordable where it is staged")
	forged = build(4,0,0,0,"exchanging"); forged.exchange = [9,1]
	check(not Rules.validate(forged),"unknown exchange rule rejected")
	forged = build(4,5,31,3,"puzzle"); forged.exchange = [0,1]
	check(not Rules.validate(forged),"puzzle must not carry a pending exchange")
	forged = build(4,5,31,3,"puzzle"); forged.hint = 4
	check(not Rules.validate(forged),"hint level is capped")
	forged = build(4,5,31,3,"puzzle"); forged.rack[0] = 2
	check(not Rules.validate(forged),"rack flags stay binary")
	forged = build(4,5,31,3,"puzzle"); forged.erase("exchange")
	check(not Rules.validate(forged),"a missing field is corruption, not a default")
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	game.commit(build(0,0,0,0))
	check(game.state.stage == "puzzle" and game.history.is_empty(),"a saved table opens without history")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.do_exchange(0,4)
	check(game.modal and game.state.a == 0 and FileAccess.get_file_as_bytes(path) == bytes,"a failed exchange save keeps the basket untouched")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "exchanging" and game.state.exchange == [0,4] and game.state.a == 0,"retry stages the exchange without booking it")
	game.paused = true; game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true
	await process_frame
	check(game.state.exchange == [0,4],"reload resumes the staged exchange")
	game.repository.fail_at = "flush"; game.skip_animation()
	check(game.modal and game.state.a == 0,"a failed booking save never publishes new goods")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.a == 4 and game.state.b == 0,"retry books the whole batch as one move")
	game.do_exchange(1,7)
	check(not game.modal and game.state.exchange.is_empty() and game.state.b == 0,"a batch beyond the table is refused without a modal")
	game.do_exchange(1,6); game.skip_animation()
	for slot in range(Rules.RACK_SLOTS):
		game.choose_rack(slot); await create_timer(0.4).timeout
	check(game.state.rack.count(1) == 5 and game.transient == 0,"five wicks fill the delivery rack")
	game.choose_hook(0)
	check(game.state.hook == [0,0],"no spool hangs when the table has spent them all")
	game.advance()
	check(game.state.stage == "puzzle" and "还有 1 处" in game.message,"the trap explains what is still missing")
	game.hint(); game.hint(); game.hint()
	check(game.state.hint == 3 and "留 2 卷给扣扣" in game.message,"the third hint gives the whole split")
	for step in range(12):
		if game.history.is_empty(): break
		game.undo(); await create_timer(0.4).timeout
	check(game.state.a == 4 and game.state.b == 0 and game.state.rack.count(1) == 0,"undo walks the trap back to twelve spools")
	check(game.history.is_empty(),"the rewind consumes every recorded step")
	game.do_reset()
	check(game.state.rack == [0,0,0,0,0] and game.state.a == 4,"clearing the rack keeps the exchanges")
	game.do_exchange(1,5); game.skip_animation()
	for slot in range(Rules.RACK_SLOTS):
		game.choose_rack(slot); await create_timer(0.4).timeout
	for slot in range(Rules.HOOK_SLOTS):
		game.choose_hook(slot); await create_timer(0.4).timeout
	check(Rules.solved(game.state),"five wicks and two spools satisfy both promises")
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle","a failed hand-over save cannot start the delivery")
	game.repository.fail_at = ""; game.retry_save(); game.paused = true
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "delivery","reload preserves an unfinished delivery")
	game.skip_animation()
	check(game.state.stage == "complete" and game.state.hook.count(1) == 2,"the delivery hands two spools to 扣扣")
	game.queue_free(); await process_frame
	Bridge.origin = "mk01"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "mk01" and Bridge.origin.is_empty(),"the harbour hand-off is consumed once")
	check(game.buttons.has("back_camp"),"arriving from the harbour offers the way back to camp")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin != "mk01" and not game.buttons.has("back_camp"),"a standalone sample keeps its own exit")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken","a corrupt save is protected without overwrite")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK02 RULES ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

extends SceneTree
const Rules = preload("res://scripts/market/mk01_rules.gd")
const Scene = preload("res://game/market_mk01.tscn")
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk01-rules-"+str(Time.get_ticks_usec())+".json"
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("MK01 rule watchdog"); quit(1))
	check(Rules.validate(Rules.fresh()),"fresh model valid")
	var winners = 0
	for a in range(-1,8):
		for b in range(-1,8):
			for c in range(-1,8):
				var slots = [a,b,c]
				if not Rules.valid_slots(slots): continue
				var independent_total = 0
				var independent_count = 0
				for id in slots:
					if id >= 0:
						independent_count += 1
						independent_total += 6 if id < 2 else (4 if id < 5 else 1)
				check(Rules.solved(slots) == (independent_count == 3 and independent_total == 11),"enumeration "+str(slots))
				if Rules.solved(slots):
					winners += 1
					check(Rules.composition(slots) == [1,1,1],"winner needs one of each type")
	check(winners == 108,"108 identity/order permutations of unique one-each combination")
	for bad in [null,{},[],[0,0,2],[0,1,8],[0,1,2.5],[true,1,2]]: check(not Rules.valid_slots(bad),"reject invalid slots "+str(bad))
	var initial = Rules.fresh(); initial.stage = "puzzle"
	var moved = Rules.place(initial,0,0); moved = Rules.place(moved,1,1); moved = Rules.place(moved,0,1)
	check(moved.slots == [-1,0,-1],"moving occupied cup replaces target without duplication")
	check(initial.slots == [-1,-1,-1],"pure command leaves input intact")
	check(Rules.place(initial,-1,0).is_empty() and Rules.place(initial,1,3).is_empty(),"reject invalid command indexes")
	var bad = Rules.fresh(); bad.stage = "complete"
	check(not Rules.validate(bad),"unsolved completed save rejected")
	bad.stage = "arrival"; bad.slots = [0,1,2]
	check(not Rules.validate(bad),"arrival cannot contain loaded cups")
	var records = [{"counts":[2,1,0],"total":16},{"counts":[1,2,0],"total":14}]
	check(Rules.candidates([records[0]]) == [[4,8],[5,6],[6,4],[7,2]],"first reading leaves four possibilities")
	check(Rules.candidates([records[1]]) == [[2,6],[4,5],[6,4],[8,3]],"reverse first reading also leaves four possibilities")
	for reverse in [false,true]:
		var trial = initial.duplicate(true)
		for slots in ([[0,2,3],[0,1,2]] if reverse else [[0,1,2],[0,2,3]]):
			trial.slots = slots
			trial = Rules.advance(trial)
			check(Rules.validate(trial),"submitted experiment valid")
			trial = Rules.advance(trial)
			check(Rules.validate(trial),"receipt valid")
			trial = Rules.advance(trial)
		check(trial.stage == "deduction" and Rules.candidates(trial.observations) == [[6,4]],"both orders uniquely infer capacities")
		for blue in range(2,9):
			for white in range(2,9):
				trial.guesses = [blue,white]
				check(Rules.confirm_capacity(trial).is_empty() == (blue != 6 or white != 4),"inference claim "+str(trial.guesses))
	bad = initial.duplicate(true); bad.observations = [records[0]]; bad.guesses = [6,4]; bad.stage = "deduction"
	check(not Rules.validate(bad) and Rules.confirm_capacity(bad).is_empty(),"lucky guess cannot skip independent evidence")
	bad.stage = "puzzle"; bad.guesses = [0,0]; bad.slots = [4,1,0]
	check(Rules.advance(bad).is_empty(),"reordering and same-type replacement do not create new evidence")
	for observations in [[records[0],records[0]],[{"counts":[2,1,0],"total":15}],[{"counts":[2.0,1,0],"total":16}]]:
		bad = initial.duplicate(true); bad.observations = observations
		check(not Rules.validate(bad),"forged or duplicate receipts rejected")
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game)
	await process_frame
	check(game.commit(initial),"initial puzzle saved")
	var old = game.state.duplicate(true)
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"
	game.select_cup(0); game.choose_slot(0)
	check(game.modal and game.state == old and FileAccess.get_file_as_bytes(path) == bytes,"save failure preserves durable and visible placement")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.slots == [0,-1,-1],"retry applies exact placement")
	await create_timer(0.4).timeout
	for pair in [[1,1],[2,2]]:
		game.select_cup(pair[0]); game.choose_slot(pair[1]); await create_timer(0.4).timeout
	game.advance(); game.paused = true
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true
	await process_frame
	check(game.state.stage == "measuring" and game.state.observations.is_empty(),"reload resumes submitted experiment without inventing receipt")
	game.repository.fail_at = "replace"; game.skip_animation()
	check(game.modal and game.state.observations.is_empty(),"failed receipt save never publishes observation")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "result" and game.state.observations == [records[0]],"retry records exactly one observation")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.observations == [records[0]],"receipt survives reload once")
	game.advance(); game.select_cup(3); game.choose_slot(1); await create_timer(0.4).timeout
	game.advance(); game.skip_animation(); game.advance()
	check(game.state.stage == "deduction" and game.state.guesses == [0,0],"two measurements require player inference")
	game.commit(Rules.set_guess(game.state,0,6)); game.commit(Rules.set_guess(game.state,1,4))
	game.repository.fail_at = "open"; game.confirm_capacity()
	check(game.modal and not game.state.calibrated,"failed inference save does not reveal order")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.calibrated and game.state.stage == "puzzle","retry unlocks delivery order")
	await create_timer(0.4).timeout
	for pair in [[0,0],[2,1],[5,2]]:
		game.select_cup(pair[0]); game.choose_slot(pair[1]); await create_timer(0.4).timeout
	game.advance(); game.skip_animation()
	check(Rules.delivered(game.state),"final load passes actual measurement")
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "result","failed delivery commit cannot move seeds")
	game.repository.fail_at = ""; game.retry_save(); game.paused = true
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "delivery","reload preserves unfinished delivery")
	game.skip_animation(); check(game.state.stage == "complete" and game.world.seed_position() == Vector2(423,411),"same seed sack lands on shore")
	game.queue_free(); await process_frame
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string("{broken"); file.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken","corrupt save protected without overwrite")
	game.queue_free(); await process_frame
	DirAccess.remove_absolute(path)
	print("MARKET MK01 RULES ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

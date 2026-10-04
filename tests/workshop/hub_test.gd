extends SceneTree
# Chapter records never replace level records; receipts must satisfy each station's own rules.
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const Progress = preload("res://scripts/workshop/chapter_progress.gd")
const Scene = preload("res://game/workshop_island.tscn")
const Bridge = preload("res://scripts/workshop/workshop_bridge.gd")
const World = preload("res://scripts/workshop/hub_world.gd")
const Market = preload("res://scripts/market/chapter_progress.gd")
var checks = 0
var failures = 0
var dir = "/tmp/workshop-hub-rules-%d" % Time.get_ticks_usec()

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)
func write_json(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
func paths() -> Dictionary:
	var result = {}
	for id in Catalog.order(): result[id] = dir + "/" + id + ".json"
	return result
func record_at(name: String) -> Progress:
	var result = Progress.new(); result.path = dir + "/" + name + "/save-v1.json"
	result.level_paths = paths(); return result
func finished(id: String) -> Dictionary:
	var rules = load("res://scripts/workshop/" + id.to_lower() + "_rules.gd")
	var state = rules.fresh()
	while state.stage != "puzzle": state = rules.advance(state)
	match id:
		"GW01": state.trays = [13,7,4]
		"GW02": state.molds = [4,4,4,4,4,4,7,7]
		"GW18": state.press = [0,1,3]; state.cool = [1,3,6]
	var guard = 0
	while state.stage != "complete" and guard < 30:
		state = rules.advance(state); guard += 1
		if state.is_empty(): break
	check(rules.validate(state) and state.get("stage") == "complete", id + " receipt follows legal rule transitions")
	return state
func run() -> void:
	create_timer(50).timeout.connect(func(): push_error("workshop hub rule watchdog"); quit(1))
	var ids = Catalog.order()
	check(ids.size() == 18 and Catalog.MAIN.size() == 14 and Catalog.SIDE.size() == 4, "18 stations partition into 14 main and 4 side")
	var saves = {}; var rects: Array = []
	for index in range(ids.size()):
		var id = ids[index]; saves[Catalog.save_path(id)] = true
		check(Catalog.built(id), id + " has a scene")
		check(Catalog.is_side(id) != Catalog.MAIN.has(id), id + " belongs to exactly one route")
		check(Catalog.act(id) >= 1 and Catalog.act(id) <= 6 and not Catalog.goal(id).is_empty(), id + " has an act and goal")
		var gate = Catalog.opens_after(id)
		check(gate.is_empty() or (ids.has(gate) and ids.find(gate) < index), id + " prerequisite points backward")
		var rect = World.card_rect(index)
		check(Rect2(20,80,1240,560).encloses(rect) and rect.size.x >= 48 and rect.size.y >= 48, id + " card fits the chart")
		for previous in rects: check(not previous.intersects(rect), id + " cards do not overlap")
		rects.append(rect)
	check(saves.size() == 18, "every level uses a separate save")
	check(Catalog.next_main([]) == "GW01" and Catalog.next_main(Catalog.MAIN) == "", "optional stations never block main completion")
	check(not Catalog.available("GW02", []) and Catalog.available("GW02", ["GW01"]), "first prerequisite unlocks GW02")
	check(Catalog.available("GW13", ["GW04"]) and not Catalog.available("GW13", ["GW12"]), "side quest follows its own prerequisite")
	check(Progress.validate(Progress.fresh()), "fresh chapter is valid")
	for value in [{}, {"chapter":"market-v1","completed":[]}, {"chapter":"workshop-v1"},
		{"chapter":"workshop-v1","completed":["GW99"]}, {"chapter":"workshop-v1","completed":["GW01","GW01"]},
		{"chapter":"workshop-v1","completed":"GW01"}]:
		check(not Progress.validate(value), "invalid chapter is rejected: " + str(value))
	check(not Market.validate(Progress.fresh()) and not Progress.validate(Market.fresh()), "market and workshop chapter domains are isolated")
	var record = record_at("chapter")
	check(record.load_record() == "new" and record.completed().is_empty(), "new chapter starts empty")
	check(not record.settle() and not FileAccess.file_exists(record.path), "missing evidence does not create progress")
	for id in ids:
		write_json(record.level_paths[id], {"stage":"complete"})
		check(not record.level_finished(id), id + " refuses a stage-only forged receipt")
		var rules = load("res://scripts/workshop/" + id.to_lower() + "_rules.gd")
		var forged = rules.fresh(); forged.stage = "complete"
		write_json(record.level_paths[id], forged)
		check(not record.level_finished(id), id + " validates completion against its own rules")
	check(not record.settle() and record.completed().is_empty(), "forged receipts cannot unlock the chapter")
	for id in ["GW01","GW02","GW18"]:
		write_json(record.level_paths[id], finished(id))
		check(record.level_finished(id), id + " accepts valid JSON numeric evidence")
	check(record.settle() and record.completed() == ["GW01","GW02","GW18"], "valid receipts settle in catalog order")
	var saved = FileAccess.get_file_as_string(record.path)
	check(not record.settle() and FileAccess.get_file_as_string(record.path) == saved, "repeat settlement is idempotent")
	check(record.is_done("GW02") and record.is_open("GW03") and not record.is_open("GW13"), "settlement unlocks only the correct successors")
	write_json(record.level_paths.GW01, load("res://scripts/workshop/gw01_rules.gd").fresh())
	check(not record.settle() and record.is_done("GW01"), "replaying a completed station does not erase its chapter credit")
	var evidence_before = FileAccess.get_sha256(record.level_paths.GW02)
	var damaged = record_at("damaged")
	write_json(damaged.path, {"chapter":"workshop-v1","completed":["GW77"]})
	var original = FileAccess.get_file_as_string(damaged.path)
	check(damaged.load_record() == "protected" and not damaged.settle(), "damaged chapter stays protected")
	check(FileAccess.get_file_as_string(damaged.path) == original and damaged.completed().is_empty(), "protected chapter keeps its exact bytes and no false progress")
	for stage in ["open","flush","replace"]:
		var failed = record_at("failed-" + stage); failed.load_record(); failed.repository.fail_at = stage
		check(not failed.settle() and failed.completed().is_empty() and not failed.error.is_empty(), stage + " failure leaves memory uncommitted")
		check(not FileAccess.file_exists(failed.path), stage + " failure does not create chapter record")
		failed.repository.fail_at = ""
		check(failed.settle() and failed.is_done("GW02"), stage + " failure can safely retry")
	check(FileAccess.get_sha256(record.level_paths.GW02) == evidence_before, "settlement and failed writes never modify station evidence")
	Bridge.progress_path = record.path; Bridge.level_paths = record.level_paths
	var hub = Scene.instantiate(); root.add_child(hub); await process_frame
	check(hub.summary().contains("3 / 18") and hub.summary().contains("3 / 14") and hub.next_id() == "GW03", "chart summarizes independent main and total progress")
	check(hub.buttons.size() == 19 and hub.buttons.has("next_station"), "chart has 18 cards and one next-station action")
	check(not hub.buttons.card_GW01.disabled and not hub.buttons.card_GW18.disabled, "completed levels remain replayable without their prerequisites")
	check(hub.buttons.card_GW04.disabled and hub.card_status("GW13").contains("GW04"), "locked cards explain their prerequisite")
	check(hub.buttons.card_GW02.tooltip_text.contains(Catalog.goal("GW02")), "card tooltip preserves its complete goal")
	Bridge.origin = ""; hub.choose("GW13")
	check(Bridge.origin.is_empty(), "locked card never starts a scene transition")
	hub.show_modal("检查用遮罩")
	check(hub.modal and hub.buttons.card_GW01.disabled, "modal blocks chapter cards")
	hub.close_modal(); check(not hub.modal and not hub.buttons.card_GW01.disabled, "closing modal restores cards")
	Bridge.progress_path = ""; Bridge.level_paths = {}; Bridge.origin = ""
	print("WORKSHOP HUB RULES ", checks-failures, "/", checks, " PASS")
	quit(1 if failures else 0)

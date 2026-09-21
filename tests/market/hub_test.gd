extends SceneTree
# 千灯集市航图的无头检查：目录契约、章节进度的读写与补记、卡片状态与可点性。
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Progress = preload("res://scripts/market/chapter_progress.gd")
const Scene = preload("res://game/market_island.tscn")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Mk02Rules = preload("res://scripts/market/mk02_rules.gd")
const World = preload("res://scripts/market/hub_world.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
var checks = 0
var failures = 0
var root_dir = "/tmp/pixel-market-hub-" + str(Time.get_ticks_usec())
var hub: Control

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

func unique(values: Array) -> Array:
	var seen: Array = []
	for value in values:
		if not seen.has(value): seen.append(value)
	return seen

func write_json(at: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(at.get_base_dir())
	var file = FileAccess.open(at, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()

func read_json(at: String) -> Variant:
	var file = FileAccess.open(at, FileAccess.READ)
	var value = JSON.parse_string(file.get_buffer(file.get_length()).get_string_from_utf8()); file.close()
	return value

func progress_at(name: String) -> Progress:
	var record = Progress.new()
	record.path = root_dir + "/" + name + "/save-v1.json"
	return record

# 补记会读每一关的存档路径：检查必须把 18 条路径全部指到临时目录，
# 否则玩家真玩过的关卡会被悄悄记进这次检查里。
func hermetic(over: Dictionary) -> Dictionary:
	var map = {}
	for id in Catalog.order(): map[id] = root_dir + "/missing-" + id + ".json"
	for id in over.keys(): map[id] = over[id]
	return map

# 一关的完成证据就是它自己存档里的 stage；这里用 MK02 的真实规则造一份合法现场。
func mk02_complete() -> Dictionary:
	var state = Mk02Rules.fresh()
	state.stage = "complete"; state.a = 4; state.b = 5
	state.rack = [1,1,1,1,1]; state.hook = [1,1]
	return state

func _initialize() -> void: call_deferred("run")

func run() -> void:
	create_timer(40).timeout.connect(func(): push_error("HUB rule watchdog"); quit(1))
	# ---- 目录契约 ----
	var ids = Catalog.order()
	check(ids.size() == 18 and Catalog.MAIN.size() == 14 and Catalog.SIDE.size() == 4,
		"the chart lists 18 stations: 14 main plus 4 side quests")
	var overlap = 0
	for id in Catalog.SIDE:
		if Catalog.MAIN.has(id): overlap += 1
	check(overlap == 0 and Catalog.MAIN.size() + Catalog.SIDE.size() == 18, "main and side quests partition the chapter")
	var paths: Array = []
	var bad_act = 0
	var bad_order = 0
	var missing_goal = 0
	for id in ids:
		paths.append(Catalog.save_path(id))
		if Catalog.act(id) < 1 or Catalog.act(id) > 6: bad_act += 1
		var gate = Catalog.opens_after(id)
		if not gate.is_empty() and (not Catalog.exists(gate) or ids.find(gate) >= ids.find(id)): bad_order += 1
		if Catalog.title(id).is_empty() or Catalog.goal(id).is_empty() or Catalog.act_name(id).is_empty(): missing_goal += 1
	check(unique(paths).size() == 18, "every station keeps its own save file")
	check(bad_act == 0, "each station belongs to one of the six acts")
	check(bad_order == 0, "a station only ever opens behind a station that came before it")
	check(missing_goal == 0, "every station shows a name, an act and a goal")
	# 目录里的底景必须与拆件包的场景成员一致，关卡不能凭空调用别人的街面。
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://art/market-kit-v1/manifest.json"))
	var scenes = {}
	for scene in manifest.scenes: scenes[scene.id] = scene.levels
	var kit_mismatches = 0
	for id in ids:
		if id == "MK01": continue
		var kit = Catalog.LEVELS[id].kit
		if not scenes.has(kit) or not scenes[kit].has(id): kit_mismatches += 1
	check(kit_mismatches == 0, "every station uses the kit-v1 scene the manifest assigns to it")
	check(Catalog.next_main([]) == "MK01" and Catalog.next_main(ids) == "",
		"the chapter opens at the harbour and ends at the lantern boat")
	check(not Catalog.available("MK02", []) and Catalog.available("MK02", ["MK01"]), "the first promise needs the cup scale")
	check(Catalog.available("MK13", ["MK04"]) and not Catalog.available("MK13", ["MK12"]),
		"side quests open on story, not on the main line")
	check(Catalog.built("MK01") and Catalog.built("MK02"), "the two shipped samples are on the chart")
	# ---- 章节进度 ----
	check(Mk02Rules.validate(mk02_complete()), "the finished nursery used as evidence is a legal station state")
	check(Progress.validate(Progress.fresh()), "a fresh chapter record is valid")
	var untouched = progress_at("fresh")
	check(untouched.load_record() == "new" and untouched.completed() == [], "an unseen chapter starts with no lamps lit")
	check(not Progress.validate({"chapter": "forest-v1", "completed": []}), "another island's record is refused")
	check(not Progress.validate({"chapter": "market-v1"}), "a record without the lamp list is refused")
	check(not Progress.validate({"chapter": "market-v1", "completed": ["MK99"]}), "an unknown station cannot light a lamp")
	check(not Progress.validate({"chapter": "market-v1", "completed": ["MK02", "MK02"]}), "a lamp is never counted twice")
	check(not Progress.validate({"chapter": "market-v1", "completed": "MK02"}), "the lamp list must be a list")
	var nothing = progress_at("empty")
	nothing.level_paths = hermetic({})
	check(not nothing.settle() and not FileAccess.file_exists(nothing.path), "nothing is written before a station is finished")
	var record = progress_at("chapter")
	var evidence = {"MK02": root_dir + "/level-mk02.json", "MK11": root_dir + "/level-mk11.json",
		"MK07": root_dir + "/level-mk07.json", "MK09": root_dir + "/level-mk09.json",
		"MK13": root_dir + "/level-mk13.json"}
	record.level_paths = hermetic(evidence)
	write_json(evidence.MK02, mk02_complete())
	write_json(evidence.MK11, {"stage": "complete"})
	write_json(evidence.MK07, {"stage": "puzzle"})
	write_json(evidence.MK09, "{not json")
	check(record.level_finished("MK02") and not record.level_finished("MK07"),
		"a finished station counts, an unfinished one does not")
	check(not record.level_finished("MK13") and not record.level_finished("MK09"), "a missing or unreadable file credits nothing")
	check(record.load_record() == "new" and record.settle(), "the chart settles once the nursery hands back its receipt")
	check(record.completed() == ["MK02", "MK11"], "lamps are listed in chart order however they were finished")
	check(not record.settle(), "settling twice adds no lamp and no write")
	check(read_json(record.path).completed == ["MK02", "MK11"], "the chapter file keeps exactly what the chart shows")
	check(record.is_done("MK02") and record.is_open("MK03") and not record.is_open("MK13"),
		"the next door opens only for what the finished station unlocks")
	var damaged = progress_at("corrupt")
	write_json(damaged.path, {"chapter": "market-v1", "completed": ["MK77"]})
	damaged.level_paths = hermetic(evidence)
	check(damaged.load_record() == "protected" and not damaged.settle() and damaged.completed() == [],
		"a damaged chapter file is kept and never overwritten")
	check(str(read_json(damaged.path).completed) == "[\"MK77\"]", "the protected record still holds the original bytes")
	# ---- 航图界面 ----
	hub = Scene.instantiate()
	hub.progress.path = root_dir + "/hub-ui/save-v1.json"
	hub.progress.level_paths = hermetic(evidence)
	root.add_child(hub)
	await process_frame
	check(hub.progress.completed() == ["MK02", "MK11"], "the chart lights only the lamps its own record carries")
	check(hub.next_id() == "MK01", "with the nursery paid but the harbour unmeasured, the first station is still owed")
	check(hub.summary() == "灯火 2 / 18 · 主线 2 / 14 · 下一站 MK01", "the heading counts lamps and main stations separately")
	var cards = 0
	var outside = 0
	var tiny = 0
	var overlaps = 0
	var rects: Array = []
	for index in range(ids.size()):
		var rect = World.card_rect(index)
		rects.append(rect)
		cards += 1
		if rect.end.x > 1280.0 or rect.end.y > 640.0 or rect.position.x < 20.0 or rect.position.y < 80.0: outside += 1
		if rect.size.x < 48.0 or rect.size.y < 48.0: tiny += 1
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]): overlaps += 1
	check(cards == 18 and hub.buttons.size() == 20, "the chart shows eighteen station cards plus the way out")
	check(outside == 0 and tiny == 0 and overlaps == 0, "cards sit apart, above the footer and inside the frame")
	# 卡片给标题留的是两行、每行九个 18px 汉字；汉字不会自动断行，超出的名字会横着爬出边框。
	var cramped = 0
	for id in ids:
		var lines = hub.wrap_title(Catalog.card_title(id)).split("\n")
		if lines.size() > 2: cramped += 1
		for line in lines:
			if line.length() > 9: cramped += 1
	check(cramped == 0, "every station name fits the two lines a card has")
	check(not hub.buttons.card_MK01.disabled and not hub.buttons.card_MK02.disabled,
		"finished and available stations can both be entered again")
	check(hub.buttons.card_MK04.disabled and hub.buttons.card_MK13.disabled, "a station without its story stays closed")
	check(hub.card_status("MK13") == "需先完成 MK04", "a closed card names the promise it is still waiting on")
	# 这条曾经按目录现况判定「哪张卡片还没做」：18 关一张张建完之后样本换到了零，
	# 再断言「存在未制作的开放站」就会永远失败。现在守的是反过来那条不变式：
	# 记录已经点亮的站，卡片必须可进、且不得停在「尚未制作」；没开放的站另由上面的
	# 「需先完成 MKxx」那条守住熄灭分支。
	var stale = 0
	for id in ids:
		if not hub.progress.is_open(id): continue
		if not hub.enterable(id) or hub.card_status(id) == "尚未制作": stale += 1
	check(stale == 0, "every station the record has opened can actually be entered")
	# 抬头木牌 (24,20,410,48) 的内框只有 382，汉字不会自动断行：任何一关把名字改长，
	# 最后一个字就被折到板外（MK17 的全名量到 386，「货」掉到了牌下面）。这条一次守住十八张。
	var wide = 0
	for id in ids:
		var probe = load(Catalog.scene(id)).instantiate()
		var name = ""
		if probe.has_method("configure"):
			probe.configure(); name = str(probe.get("title"))
		if name == "<null>" or name.is_empty(): name = Catalog.card_title(id)
		if probe != null: probe.free()
		var w = UIStyle.face().get_string_size("千灯集市  /  "+name, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(24)).x
		if w > 382.0: wide += 1
	check(wide == 0, "every station name fits the header board the host draws it on")
	# 底栏与出口那几块木牌由宿主一处写死、十八关共用：字比盒子宽就被引擎裁掉，
	# 「重摆 X」少半句就只剩「重摆」，键位等于没告诉玩家。这里直接从宿主源码里读出每块牌
	# 的字样与盒子量一遍——以后改字或改盒子都会立刻被这一条拦住。
	var narrow = 0
	var boarded = 0
	var board_pattern = RegEx.create_from_string("add_button\\(\"[a-z_]+\",\\s*\"([^\"]+)\",\\s*Rect2\\(([^)]+)\\)")
	for spoken in FileAccess.get_file_as_string("res://scripts/market/level_host.gd").split("\n"):
		var found = board_pattern.search(spoken)
		if found == null: continue
		boarded += 1
		var stub = Button.new()
		UIStyle.style_button(stub); stub.text = found.get_string(1)
		var room = float(found.get_string(2).split(",")[2])
		if stub.get_combined_minimum_size().x > room + 0.5:
			narrow += 1; print("牌装不下自己那句字：", stub.text, " 要 ",
				stub.get_combined_minimum_size().x, " 只有 ", room)
		stub.free()
	check(boarded >= 7 and narrow == 0,
		"底栏与出口的 %d 块木牌都装得下自己那句字" % boarded)
	# 回航图那颗按钮由宿主与十八关各自挂上，目的地却是同一块屏。航图自己的牌头写的是
	# 「千灯集市 / 千灯航图」，那每一颗回它的按钮就得都叫这个名字：一处「集市航图」、一处
	# 「回千灯航图」，玩家会以为是两条路、两个地方。字样与牌头都从源码里读，不抄第二遍。
	var header = ""
	for line in FileAccess.get_file_as_string("res://scripts/market/market_hub.gd").split("\n"):
		if line.begins_with("\tsign_text(\"千灯集市"): header = line
	var exits = 0
	var misnamed = 0
	var exit_pattern = RegEx.create_from_string("add_button\\(\"(?:back_hub|leave_hub|open_hub)\",\\s*\"([^\"]+)\"")
	var folder = DirAccess.open("res://scripts/market")
	for file in folder.get_files():
		if not file.ends_with("_scene.gd") and file != "level_host.gd": continue
		for line in FileAccess.get_file_as_string("res://scripts/market/" + file).split("\n"):
			var found = exit_pattern.search(line)
			if found == null: continue
			exits += 1
			if "千灯航图" not in found.get_string(1):
				misnamed += 1; print("回航图的按钮报的是别处：", file, " ", found.get_string(1))
	check("千灯航图" in header, "航图自己牌头上写的那个名字")
	check(exits >= 21 and misnamed == 0,
		"宿主与十八关那 %d 颗回航图的按钮，报的都是航图自己那个名字" % exits)
	check(hub.card_status("MK02") == "已点亮 · 可重玩" and hub.card_status("MK01") == "待出发",
		"a lit lamp still offers the station back to the player")
	check(hub.buttons.has("next_station") and hub.buttons.next_station.text == "下一站 · MK01",
		"the primary action names the station it will open")
	check(not hub.buttons.camp.disabled, "the way back to the forest camp is open")
	check("比较两张混合装法" in hub.buttons.card_MK01.tooltip_text, "a card's tip carries the full goal")
	check(hub.world.completed == ["MK02", "MK11"] and hub.world.next_id == "MK01", "the lamp strip follows the record")
	# 打磨轮补的共享守卫。热点是隐形按钮，「这个能点」只靠 hover 那一圈金边与 tooltip 说话；
	# 而 tooltip 的主题继承只到 Window，挂到宿主 Control 上会静默失效，所以这里两头都钉住。
	var tip = Button.new(); UIStyle.hotspot(tip, "检查用说明")
	var hover_box = tip.get_theme_stylebox("hover")
	check(hover_box is StyleBoxFlat and (hover_box as StyleBoxFlat).border_width_left > 0,
		"a hotspot answers the pointer the moment it arrives")
	tip.free()
	var chart_theme = UIStyle.tooltip_theme()
	check(chart_theme.get_stylebox("panel", "Tooltip") is StyleBoxFlat,
		"an explanation rides on the level's own wooden plate, not the engine default box")
	check(chart_theme.get_font("font", "TooltipLabel") == UIStyle.face(),
		"the explanation is drawn in the font every other board already uses")
	check(hub.get_window().theme != null,
		"the chart hangs that theme on the window, which is the only place tooltips read it from")
	Bridge.origin = ""
	hub.choose("MK13")
	check(Bridge.origin.is_empty(), "a locked card never sends the player anywhere")
	hub.show_modal("检查用遮罩")
	check(hub.modal and hub.buttons.card_MK01.disabled, "while a notice is up no station can be picked")
	hub.close_modal()
	check(not hub.modal and not hub.buttons.card_MK01.disabled, "closing the notice hands the chart back")
	print("MARKET HUB RULES ", checks - failures, "/", checks, " PASS")
	DirAccess.remove_absolute(root_dir)
	quit(1 if failures else 0)

extends SceneTree
# 千灯集市航图的实窗检查：1280x720 与 960x540 两档下，灯火条、卡片文字与页脚都要站得住。
const Scene = preload("res://game/market_island.tscn")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const CAPTURE = "res://docs/playtest/market-chapter-hub"
var hub: Control
var checks = 0
var failures = 0
var dir = ""

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
func write_json(at: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(at.get_base_dir())
	var file = FileAccess.open(at, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
func lamps(done: Array) -> Dictionary:
	var map = {}
	for id in Catalog.order(): map[id] = dir + "/missing-" + id + ".json"
	for id in done:
		var target = dir + "/level-" + id + ".json"
		write_json(target, {"stage": "complete"})
		map[id] = target
	return map
func make_hub(done: Array) -> void:
	hub = Scene.instantiate()
	hub.progress.path = dir + "/chapter/save-v1.json"
	hub.progress.level_paths = lamps(done)
	root.add_child(hub)
	await process_frame
func free_hub() -> void:
	hub.queue_free(); await process_frame
func tap(control: Control) -> void:
	var point = control.get_global_transform_with_canvas()*(control.size/2)*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event)
	await process_frame
func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame
func overflow_count() -> int:
	var over = 0
	for child in hub.ui.get_children():
		if not child is Label: continue
		var height = child.get_line_count()*(child.get_theme_font_size("font_size") + 5)
		if height > child.size.y + 1: over += 1
		# A label whose shortest unbreakable run is wider than its box draws past the card.
		if child.get_combined_minimum_size().x > child.size.x + 1: over += 1
	return over

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("HUB window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		dir = "/tmp/pixel-market-hub-ui-"+str(Time.get_ticks_usec())
		await make_hub(["MK02","MK11"])
		if not await Focus.ready(root): quit(1); return
		check(hub.world.parts.has("lantern_string"), "the chart loads the kit parts behind the cards")
		check(hub.buttons.size() == 20, "eighteen stations, the camp door and the next station")
		check(hub.summary() == "灯火 2 / 18 · 主线 2 / 14 · 下一站 MK01", "the heading reads the lamps it actually has")
		check(overflow_count() == 0, "no card or sign overflows the box it was given")
		check(hub.world.backdrop != null and hub.world.stations.has("counter"), "the chart stands on the lantern street")
		await capture(prefix+"01-chart-two-lamps")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == hub.buttons.camp, "Tab reaches the camp door first")
		Bridge.origin = ""
		await tap(hub.buttons.card_MK04)
		check(Bridge.origin.is_empty() and is_instance_valid(hub), "a locked card swallows the click")
		hub.show_modal("检查用遮罩")
		check(hub.buttons.card_MK01.disabled and hub.buttons.camp.disabled, "a notice covers the whole chart")
		hub.close_modal()
		check(not hub.buttons.card_MK01.disabled, "the chart answers again once the notice closes")
		check(FileAccess.file_exists(hub.progress.path), "the chapter record was written under this run's own path")
		await free_hub()
		await make_hub(Catalog.order())
		check(hub.summary().contains("18 / 18"), "the night market is fully lit when every station reports home")
		check(not hub.buttons.has("next_station"), "with nothing owed the chart stops pushing a next station")
		check(hub.buttons.card_MK18.disabled, "even a finished station stays closed until it is actually made")
		check(overflow_count() == 0, "the finished chart keeps every label inside its box")
		await capture(prefix+"02-chart-all-lamps")
		await free_hub()
		DirAccess.remove_absolute(dir)
	print("MARKET HUB WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

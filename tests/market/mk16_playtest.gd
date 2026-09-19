extends SceneTree
# MK16 实窗审计：真实窗口里走一遍「听三句 → 走到打包台 → 真把纪念物放上台面 → 封箱上红船 →
# 红船带着玩家选的那一样离岸」，在 1280×720 与 960×540 各拍一遍，两条分支都拍全：
# 白杯一条、铜铃一条，回执、船上的吊牌与回信说法都要看得出区别，两份 PNG 也不能是同一张图。
const Scene = preload("res://game/market_mk16.tscn")
const Rules = preload("res://scripts/market/mk16_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const CAPTURE = "res://docs/playtest/market-mk16-gift"
const SHELF_IDS = ["shelf_0", "shelf_1", "shelf_2", "shelf_3"]
const RECEIPT_TITLE = "回执 · 给森林寄回的礼物"
var game: Control
var checks = 0
var failures = 0
var frames = {}
var boxes = {}

func _initialize() -> void: Focus.configure(root); call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)

func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	var image = root.get_texture().get_image()
	image.save_png(CAPTURE+"/"+name+".png")
	frames[name] = image
	boxes[name] = game.world.charm_box()

# 整帧同色就是黑屏或空白，不能算看过一眼。
func has_content(image: Image) -> bool:
	var first = image.get_pixel(4, 4)
	for step in range(64, image.get_width(), 97):
		if image.get_pixel(step, image.get_height() / 2) != first: return true
	return false

func apart_at(a: Image, b: Image, x: int, y: int) -> float:
	if absf(a.get_pixel(x, y).r - b.get_pixel(x, y).r) > 0.06 \
			or absf(a.get_pixel(x, y).g - b.get_pixel(x, y).g) > 0.06 \
			or absf(a.get_pixel(x, y).b - b.get_pixel(x, y).b) > 0.06: return 1.0
	return 0.0

# 两条分支的画面差多少：whole = 整幅均匀取样；box = 只圈包裹那一块（船上的吊牌）。
func differ(from: String, to: String, region: Rect2 = Rect2()) -> float:
	var a: Image = frames[from]
	var b: Image = frames[to]
	if a == null or b == null or a.get_size() != b.get_size(): return -1.0
	var seen = 0
	var apart = 0.0
	var x0 = 0
	var y0 = 0
	var x1 = a.get_width()
	var y1 = a.get_height()
	if region.size.x > 0:
		var step = Vector2(a.get_width(), a.get_height()) / Vector2(1280, 720)
		x0 = int(maxf(0, region.position.x * step.x))
		y0 = int(maxf(0, region.position.y * step.y))
		x1 = int(minf(a.get_width(), (region.position.x + region.size.x) * step.x))
		y1 = int(minf(a.get_height(), (region.position.y + region.size.y) * step.y))
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			seen += 1
			apart += apart_at(a, b, x, y)
	return float(apart) / float(maxi(1, seen))

func click(id: String) -> void:
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false,"hotspot unavailable "+id); return
	var button: Control = game.buttons[id]
	var logical = button.get_global_transform_with_canvas()*(button.size/2)
	var point = logical*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame

func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down
		root.push_input(event)
	await process_frame
	while game.transient > 0: await process_frame

func hold(seconds: float) -> void:
	game.paused = true; game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	await process_frame

func fits(text: String, size_px: int, width: float) -> bool:
	var widest = 0.0
	for line in text.split("\n"):
		widest = maxf(widest, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UIStyle.text_size(size_px)).x)
	return widest <= width

# 汉字不会自动断行：最短的一段连续文字比盒子还宽，就会横着画到旁边的货上。
func spilled(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = child.get_combined_minimum_size()
		if needed.x > child.size.x + 1 or needed.y > child.size.y + 1:
			over += 1; print("SPILL ", child.text, " needs ", needed, " in ", child.size)
	return over

func paper_on_screen() -> String:
	for child in game.ui.get_children():
		if child is Label and RECEIPT_TITLE in child.text: return child.text
	return ""

# 三句台词听完之后的路：走过来、停一下、把台面交给玩家。调用前台面上已说到第三句。
func walk_to_table() -> void:
	await click("next")
	check(game.state.stage == "approach","the third line walks the player to the dock")
	await click("pause")
	var frozen: float = game.elapsed
	await create_timer(0.12).timeout
	check(game.elapsed == frozen,"pausing freezes the walk-in")
	await click("skip")
	check(game.state.stage == "ready","the walk-in stops before player control")
	await click("next")
	check(game.state.stage == "puzzle","the packing table is handed to the player")

# 从头听完三句台词（第二次寄礼物用）。
func listen_to_the_dock() -> void:
	for beat in range(Rules.BEATS - 1):
		await click("next")
	check(game.state.stage == "arrival" and game.state.beat == Rules.BEATS - 1,
		"the dock mouth plays its three lines again")

func lay_out(ids: Array) -> void:
	for id in ids:
		await click(SHELF_IDS[id])

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("MK16 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		frames = {}
		boxes = {}
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk16-ui-"+str(Time.get_ticks_usec())+".json"
		var other = "/tmp/pixel-mk16-ui-bell-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.state.stage == "arrival" and "连一份回礼都没凑齐" in game.line(),
			"opens on the dock mouth, not on a puzzle")
		check(game.state.table.is_empty() and game.state.gift.is_empty(),
			"nothing is chosen or sailed before the player arrives")
		await capture(prefix+"01-arrival")
		check(has_content(frames[prefix+"01-arrival"]),"the opening frame really draws the dock")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab focuses the first narrative action")
		await key(KEY_ENTER)
		check(game.state.beat == 1,"Enter advances the focused line")
		await click("next")
		check(game.state.beat == 2 and "杯和铃都想带" in game.line(),
			"the third line already names the choice the player is about to make")
		await walk_to_table()
		var small_target = 0
		var signed = 0
		for id in game.buttons:
			var button: Control = game.buttons[id]
			if not id.begins_with("shelf_") and not id.begins_with("slot_") and id != "boat": continue
			if button.size.x < 48 or button.size.y < 48: small_target += 1
			if not button.tooltip_text.is_empty(): signed += 1
		check(small_target == 0,"every souvenir and the boat are 48 pixel targets or bigger")
		check(signed == 5,"the four shelf goods and the boat all carry a Chinese tooltip")
		check(spilled(game.ui) == 0,"no dock text spills out of its box on an empty table")
		check(game.world.table_plaque().ends_with("= 0 斤 / 上限 7 斤"),
			"the scale plaque starts at zero in the player's own words")
		await capture(prefix+"02-empty-table")
		# 真操作：把绿叶章放上台面，再点一下放回货板
		await click("shelf_0")
		check(game.state.table == [Rules.LEAF],"clicking the badge puts it on the packing table")
		check(game.world.table_plaque() == "打包台 · 绿叶章2 = 2 斤 / 上限 7 斤",
			"the scale reads out the one thing the player just laid down")
		await capture(prefix+"03-one-on-table")
		await click("slot_0")
		check(game.state.table.is_empty(),"clicking it on the table puts it back on the shelf")
		# 两条承诺各说各的：差哪一样，红船就点名要哪一样，数字用玩家自己摆下的
		await lay_out([Rules.PAPER, Rules.CUP])
		check(game.state.table == [Rules.PAPER, Rules.CUP],
			"the shelf gives up exactly one of each souvenir")
		await click("deliver")
		check(game.state.stage == "puzzle" and "绿叶章" in game.message and "5" in game.message,
			"the boat asks for the forest's own badge and quotes the player's own 5 斤")
		await capture(prefix+"04-missing-badge")
		await key(KEY_Z); await key(KEY_Z)
		check(game.state.table.is_empty(),"two undos hand the paper and the cup back")
		await lay_out([Rules.LEAF, Rules.CUP])
		await click("deliver")
		check(game.state.stage == "puzzle" and "信纸" in game.message,
			"a gift without writing paper cannot be answered, and it says so")
		await key(KEY_Z); await key(KEY_Z)
		await lay_out([Rules.LEAF, Rules.PAPER, Rules.CUP])
		check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP] and Rules.solved(game.state),
			"the badge, the paper and the cup make a real gift")
		check(game.world.table_plaque() == "打包台 · 绿叶章2 + 信纸1 + 杯4 = 7 斤 / 上限 7 斤",
			"7 斤 sits exactly on the limit and the plaque still says 上限 7 斤")
		await capture(prefix+"05-cup-on-table")
		# 第四样：杯和铃都想带，红船按玩家自己的数字回话
		await click("shelf_3")
		check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP] and "10" in game.message,
			"a fourth souvenir is refused with the player's own 10 斤")
		check("7 斤" in game.message and not game.modal,
			"the refusal is a dock-side answer, not a scolding modal")
		await capture(prefix+"06-too-heavy")
		game.message = ""
		for step in range(3): await click("hint")
		check(game.state.hint == 3 and "10 斤" in game.message and "2+1+4=7" in game.message,
			"the third hint states both legal gifts and stops there")
		check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.CUP],
			"no hint lays a souvenir down for the player")
		await capture(prefix+"07-hint-three")
		game.message = ""
		await click("reset"); await click("confirm")
		check(game.state.table == [Rules.LEAF, Rules.PAPER],
			"重摆 returns only the chosen third and keeps the mandatory two")
		await capture(prefix+"08-back-to-mandatory")
		await lay_out([Rules.CUP])
		check(Rules.solved(game.state),"the player puts the cup back down")
		# 提交验收 → 场景后果：白杯一条
		await click("deliver")
		check(game.state.stage == "loading" and game.state.gift == [0, 1, 2] and game.state.present == "cup",
			"the accepted gift is sealed and the parcel records the cup")
		await hold(1.5)
		check(game.world.progress > 0.4 and game.world.progress < 0.6,
			"the three souvenirs are wrapped in one continuous motion")
		await capture(prefix+"09-wrapping-cup")
		await click("skip")
		check(game.state.stage == "delivery" and game.state.sent == 1,
			"the red boat takes the parcel and reports it once")
		check("白杯" in game.line(),"the sailing line names the cup the player chose")
		await hold(2.6); await capture(prefix+"10-sailing-cup")
		await click("skip")
		check(game.state.stage == "complete" and Rules.validate(game.state),
			"the sailing ends on the receipt")
		var cup_paper = paper_on_screen()
		check(RECEIPT_TITLE in cup_paper and "白杯" in cup_paper and "cup" == game.state.present,
			"the receipt restates the parcel the player actually sent")
		check(spilled(game.ui) == 0,"the receipt adds no spilled text")
		var paper: Label = null
		for child in game.ui.get_children():
			if child is Label and RECEIPT_TITLE in child.text: paper = child
		check(paper != null and fits(paper.text, 15, paper.size.x),"the receipt holds its own paper")
		await capture(prefix+"11-receipt-cup")
		var cup_saved = game.state.duplicate(true)
		var cup_bytes = FileAccess.get_file_as_bytes(path)
		game.queue_free(); await process_frame
		# 读盘：偏好活过一次重载
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == cup_saved and game.state.present == "cup",
			"the cup choice reloads from disk exactly as booked")
		game.queue_free(); await process_frame
		# 铜铃一条：另一份存档、另一条回信
		game = Scene.instantiate(); game.save_path = other; root.add_child(game); await process_frame
		await listen_to_the_dock()
		await walk_to_table()
		await lay_out([Rules.LEAF, Rules.PAPER, Rules.BELL])
		check(game.state.table == [Rules.LEAF, Rules.PAPER, Rules.BELL] and Rules.total(game.state.table) == 6,
			"the bell gift stays under the limit at 6 斤")
		check(game.world.table_plaque() == "打包台 · 绿叶章2 + 信纸1 + 铃3 = 6 斤 / 上限 7 斤",
			"the plaque weighs the bell gift on its own terms")
		await capture(prefix+"12-bell-table")
		await click("deliver")
		check(game.state.present == "bell","the parcel key follows the bell the player chose")
		await click("skip"); await hold(2.6)
		check(game.state.stage == "delivery" and "铜铃" in game.line(),
			"the sailing line follows the bell instead")
		await capture(prefix+"13-sailing-bell")
		await click("skip")
		var bell_paper = paper_on_screen()
		check(bell_paper != cup_paper and "铃一响" in bell_paper and Rules.REWARD in bell_paper,
			"the bell ending writes its own reply and the same main-line reward")
		check(Rules.REWARD in cup_paper,"the cup ending promises the very same reward line")
		check(spilled(game.ui) == 0,"the second receipt adds no spilled text either")
		await capture(prefix+"14-receipt-bell")
		# 两个结局真的看得出差别。整幅画面被同一片码头背景占满，两条分支之间只差不到 1%，
		# 光量整帧等于在量天空；所以按玩家实际会看的两块圈出来比：回执面板写的是寄出去的那一样，
		# 打包台上留下的则是没带走的那一样。坐标与 mk16_scene.gd 的 extra() 一致。
		var whole = differ(prefix+"11-receipt-cup", prefix+"14-receipt-bell")
		check(whole > 0.004,
			"the two endings are not the same picture (%.1f%% of samples apart)" % (whole*100))
		var panel = differ(prefix+"11-receipt-cup", prefix+"14-receipt-bell", Rect2(660, 176, 470, 190))
		check(panel > 0.02,
			"the receipt answers with the gift that was actually sent (%.1f%% of the panel)" % (panel*100))
		var keepsake = differ(prefix+"11-receipt-cup", prefix+"14-receipt-bell", Rect2(380, 470, 520, 130))
		check(keepsake > 0.02,
			"the one left on the packing table changes with the choice (%.1f%% of the table)" % (keepsake*100))
		var charm = differ(prefix+"10-sailing-cup", prefix+"13-sailing-bell", boxes[prefix+"10-sailing-cup"])
		check(charm > 0.08,"the boat leaves with a different charm tied outside the parcel (%.0f%%)" % (charm*100))
		var bell_bytes = FileAccess.get_file_as_bytes(other)
		check(bell_bytes != cup_bytes and game.state.present == "bell",
			"each branch keeps its own profile for the forest reply")
		game.queue_free(); await process_frame
		# 出口契约
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"the chart hand-off is consumed once")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"a visit from the chart offers only the way back")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub"),"a standalone launch still finds its way back to the chart")
		check(game.buttons.open_hub.text == "回千灯航图" and game.buttons.open_hub.size == Vector2(280,54),
			"the exit button keeps the shipped contract")
		await click("next")
		check(game.modal and game.state.stage == "complete","replaying the scene asks first")
		await click("cancel")
		check(game.state.present == "cup","cancelling keeps the gift the player already sent")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.present.is_empty(),
			"replaying rewinds only this dock, back to the three lines")
		await capture(prefix+"15-after-restart")
		check(has_content(frames[prefix+"15-after-restart"]),"the restarted dock is drawn again, not blanked")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path); DirAccess.remove_absolute(other)
	print("MARKET MK16 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

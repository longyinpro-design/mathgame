extends SceneTree
# MK17 实窗审计：真实窗口里走一遍「听三句 → 铜鹭踏栈桥入港 → 三张货单钉上栏 → 自己封装、
# 自己把货放上验货托盘 → 提交验收 → 翻出本局固定的那面旗 → 三站各自办成 → 码头逐盏亮灯 → 回执」。
# 两面分支都拍：旗A 一条走到底；旗B 浪费一次机会走死的那条路，看它是不是真的只给
# 「退回上一站的货」与「回到关前规划」两条出路，而不去编一个不存在的解。
# 1280×720 与 960×540 各走一遍，并检查世界层牌子上那些汉字有没有爬出自己的木牌。
const Scene = preload("res://game/market_mk17.tscn")
const Rules = preload("res://scripts/market/mk17_rules.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
const CAPTURE = "res://docs/playtest/market-mk17-inspection"
const L = Rules.LARGE
const M = Rules.MEDIUM
const S = Rules.SMALL
const HOTSPOTS = ["op_0", "op_1", "op_2", "op_3", "take_0", "take_1", "take_2",
	"berth_0", "berth_1", "berth_2", "flag"]
const BAR = ["undo", "reset", "hint", "deliver"]
const RECEIPT_HEAD = "铜鹭验货回执"
# 小窗口那一遍只留最能说明问题的一张张，两张都拍满反而看不出差别。
const LITE_KEEP = ["01-arrival", "03-cards", "06-crowded", "08-flag-a", "10-packages-fly", "14-receipt",
	"b-01-dead-end", "b-03-rewound"]
var game: Control
var path := ""
var prefix := ""
var lite = false
var checks = 0
var failures = 0
var frames = {}

func _initialize() -> void: Focus.configure(root); call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

func snap(name: String) -> void:
	if lite and not LITE_KEEP.has(name): return
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	var image = root.get_texture().get_image()
	image.save_png(CAPTURE + "/" + prefix + name + ".png")
	frames[prefix + name] = image

# 整帧同色就是黑屏或空白，不能算看过一眼。
func has_content(image: Image) -> bool:
	if image == null: return false
	var first = image.get_pixel(4, 4)
	for step in range(64, image.get_width(), 97):
		if image.get_pixel(step, image.get_height() / 2) != first: return true
	return false

func click(id: String) -> void:
	game.paused = false
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false, "点不动的牌子：" + id); return
	var button: Control = game.buttons[id]
	var logical = button.get_global_transform_with_canvas() * (button.size / 2)
	var point = logical * Vector2(root.size) / Vector2(1280, 720)
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event)
	await process_frame
	await drained()

func key(code: int) -> void:
	game.paused = false
	for down in [true, false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down
		root.push_input(event)
	await process_frame
	await drained()

# 落地锁松开之后按钮才重新亮；按了暂停就当作玩家自己把动画接着放完。
func drained() -> void:
	var steps = 0
	while game.transient > 0 and steps < 240:
		await process_frame; steps += 1
	if game.transient > 0: check(false, "落地动画松不开手，按钮一直锁着")

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

# 世界层的木牌按原号数画，不走 Label 的字号档位。
func plaque_fits(text: String, rect: Rect2, size_px: int) -> bool:
	return UIStyle.face().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x <= rect.size.x - 20.0

# 汉字不会自动断行：最短的一段连续文字比盒子还宽，就会横着画到旁边的货上。
func spilled(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = child.get_combined_minimum_size()
		if needed.x > child.size.x + 1 or needed.y > child.size.y + 1:
			over += 1; print("SPILL ", child.text, " needs ", needed, " in ", child.size)
	return over

# 热点几何：登记了吗、够不够 48、这一幕的镜头下还在不在画面里、有没有中文说明。
func frame_report(ids: Array) -> Array:
	var present = true
	var sized = true
	var framed = true
	var tips = true
	for id in ids:
		if not game.buttons.has(id): present = false; continue
		var button: Button = game.buttons[id]
		if button.size.x < 48 or button.size.y < 48: sized = false
		var rect = button.get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
		if button.text.is_empty() and button.tooltip_text.is_empty(): tips = false
	return [present, sized, framed, tips]

func tray_ids() -> Array:
	var ids = []
	for slot in range(Rules.packs_of(game.state.tray)): ids.append("tray_%d" % slot)
	return ids

func receipt_text() -> String:
	for child in game.ui.get_children():
		if child is Label and RECEIPT_HEAD in child.text: return child.text
	return ""

func booked(value: Dictionary) -> void:
	var writer = FileAccess.open(path, FileAccess.WRITE)
	check(writer != null, "本局的存档写得出去")
	writer.store_string(JSON.stringify(value)); writer.close()

# 开局：三次机会都在、旗已经固定但还没翻。
func opened(flag: int) -> Dictionary:
	var value = Rules.fresh(); value.flag = flag; return value

# 旗B 里在二站多拆一次之后的死局：三站只剩 1大1中1小、0 次机会。
func dead_board() -> Dictionary:
	return {"sample": "market-mk17-1", "stage": "puzzle", "beat": 2, "flag": Rules.FLAG_B, "shown": 1,
		"station": 3, "stock": [1, 1, 1], "tray": Rules.empty_packs(),
		"delivered": [[1, 1, 0], [0, 3, 1], [0, 0, 0]], "chances": 0, "hint": 0}

func fresh_scene() -> void:
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	if not await Focus.ready(root): quit(1); return

func close_scene() -> void:
	game.queue_free(); game = null; await process_frame

# ---- 旗A：三站一路办成 ----
func play_flag_a() -> void:
	booked(opened(Rules.FLAG_A))
	fresh_scene()
	check(game.state.stage == "arrival" and game.state.flag == Rules.FLAG_A, "读到的开局就是写进存档的那面旗")
	check(game.state.shown == 0 and game.state.chances == 3 and game.state.stock == Rules.START_STOCK,
		"开局：六只大包、三次机会、旗还收着")
	check(game.line().count("\n") <= 1 and "码头" in game.line(), "开场第一句两行说完，不超过口条的高度")
	await snap("01-arrival")
	check(has_content(frames[prefix + "01-arrival"]), "开场那一帧真的画出了大码头")
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == game.buttons.next, "Tab 先落在继续听的那块牌子上")
	await key(KEY_ENTER)
	check(game.state.beat == 1, "回车真的把台词推到第二句")
	await click("next")
	check(game.state.beat == 2 and "货单" in game.line() and "旗A" in game.line() and "旗B" in game.line(),
		"第三句：货单开局就能看，两面旗也一并讲给玩家，没人替他猜")
	await click("next")
	check(game.state.stage == "approach", "台词说完，铜鹭踏着栈桥进来")
	await click("pause")
	var frozen = game.elapsed
	await create_timer(0.12).timeout
	check(game.elapsed == frozen, "暂停把巡守的那几步定在栈桥上")
	await hold(0.95)
	await snap("02-walk")
	check(game.world.heron_pose() == 0, "走进来的时候它举的还是巡守那一态")
	await click("skip")
	check(game.state.stage == "ready", "入幕之后先停一下，把三张货单钉上栏")
	await snap("03-cards")
	await click("next")
	check(game.state.stage == "puzzle" and game.state.chances == 3, "开始验货：一台面大包，一次机会没动")
	var report = frame_report(HOTSPOTS)
	check(not game.buttons.has("tray_0"), "空托盘上没有多余的假热点骗手指")
	check(report[0], "四条封装走法、三行封包、三张货单与检查旗都登记成了热点")
	check(report[1], "每个热点至少 48×48 逻辑像素")
	check(report[2], "缩放镜头下每个热点都还在画面里，也没压住底栏")
	check(report[3], "每个热点都写着中文说明")
	check(game.buttons.has("deliver") and game.buttons.deliver.text == "提交这一站验收", "提交这块牌子写着玩家要做的事")
	check(spilled(game.ui) == 0, "空台面的文字没有爬出自己的盒子")
	check(plaque_fits("重新封装 · 剩 3 次", game.world.header_rect(), 15), "封台头的木牌装得下自己那句话")
	for index in range(Rules.OPS.size()):
		check(plaque_fits(Rules.OPS[index].name, game.world.bench_rect(index), 15),
			"走法牌「%s」不溢出木牌" % Rules.OPS[index].name)
	# 空托盘提交：只按当前这一站说话，不弹罚站的窗
	await click("deliver")
	check(game.state.stage == "puzzle" and "一站" in game.message and "托盘上还什么都没放" in game.message,
		"空托盘提交：点名一站，说托盘还空着")
	check(not game.modal, "这只是一句回话，不是罚站的弹窗")
	await snap("04-empty-tray")
	game.message = ""
	await click("op_0")
	check(game.state.chances == 2 and game.state.stock == [5, 1, 1], "点封装牌：机会真少一次，台上多一中一小")
	check(game.history.size() == 1, "这一步进了撤销栈")
	await click("take_0"); await click("take_1")
	check(game.state.tray == [1, 1, 0] and game.state.stock == [4, 0, 1], "大包与中包各上一格托盘")
	check(game.state.chances == 2, "上托盘不动封装机会")
	check(plaque_fits("验货托盘 · 5 单位 / 2 包", game.world.tray_plaque_rect(), 15), "托盘牌说得出玩家真正摆下的数")
	await snap("05-tray-two")
	for repeat in range(4): await click("take_0")
	await click("take_2")
	check(Rules.packs_of(game.state.tray) == Rules.MAX_TRAY, "托盘真摆到了 6 包")
	await click("take_0")
	check("6 包" in game.message and game.state.tray != [0, 0, 0], "第 7 包摆不下，说法里给出上限")
	var crowded = frame_report(tray_ids())
	check(crowded[0] and crowded[1] and crowded[2] and crowded[3], "摆满 6 包：每一包都点得着、在画面里、有说明")
	await snap("06-crowded")
	for step in range(4): await key(KEY_Z)
	check(game.state.tray == [1, 1, 0] and game.state.stock == [4, 0, 1] and game.state.chances == 2,
		"四步撤销只退摆法：多放的货回到台面，机会仍是已用一次")
	for step in range(4): await click("hint")
	check(game.state.hint == Rules.HINTS and not game.message.is_empty(), "提示只有三级，按到第四级也不越界")
	check(fits(game.message, 20, 798), "提示写在口条里，没有溢出")
	check(game.state.chances == 2 and Rules.held_units(game.state) == 18, "听完提示一单位也没多、机会也没送")
	await click("deliver")
	check(game.state.stage == "flag" and game.state.shown == 1 and game.state.delivered[0] == [1, 1, 0],
		"一站交完：那两包钉在栈位上，铜鹭翻旗")
	await hold(1.0)
	await snap("07-flip-mid")
	check(game.world.heron_pose() == 1, "翻旗这一幕它举的是检查旗")
	await click("skip")
	check(game.state.stage == "puzzle" and game.state.station == 2, "翻完旗回到码头摆二站的货")
	await snap("08-flag-a")
	check("大小包都收" in game.puzzle_line() and "7 单位" in game.puzzle_line(), "二站的话按翻出来的那面旗说")
	report = frame_report(HOTSPOTS + tray_ids())
	check(report[0] and report[1] and report[2] and report[3], "二站的码头上热点依旧齐全")
	await click("take_0"); await click("take_0")
	await click("deliver")
	check(game.state.stage == "puzzle" and "二站" in game.message and "7 单位" in game.message,
		"只差 1 单位：二站点名要 7 单位，不怪已经办成的一站")
	check("一站" not in game.message, "拒绝里不牵连别站")
	await snap("09-short-by-one")
	game.message = ""
	await click("take_2")
	check(game.state.tray == [2, 0, 1] and Rules.solved(game.state), "补上那只小包，旗A 的二站收下 2大+1小")
	await click("deliver")
	check(game.state.stage == "lift", "二站的货吊上蓝船")
	await hold(1.1)
	await snap("10-packages-fly")
	check(game.world.flying(), "飞行途中货确实不在托盘上")
	await click("skip")
	check(game.state.stage == "puzzle" and game.state.station == 3, "回到码头摆三站")
	await click("berth_2")
	check("三站" in game.message and "不接大包" in game.message, "点三站的货单：读出来的是那条固定约定")
	await click("op_2")
	check(game.state.stock == [0, 3, 0] and game.state.chances == 1, "两大包 → 三中包：最后一次机会也动了")
	for step in range(3): await click("take_1")
	check(game.state.tray == [0, 3, 0] and Rules.solved(game.state), "三只中包上托盘，正合三站的约定")
	await snap("11-station-three")
	await click("deliver")
	check(game.state.stage == "carrying", "三站办完，铜鹭收起旗、展翼把自己变成搬运台")
	await hold(1.9)
	await snap("12-platform")
	check(game.world.heron_pose() == 2, "搬运台那一态确实是展翼的那张原图")
	await click("skip")
	check(game.state.stage == "delivery", "离岸这一幕：码头一盏一盏亮起来")
	await hold(2.2)
	await snap("13-lights-on")
	check(int(ceil(3 * game.world.progress)) >= 2, "灯是按玩家真正办成的站数一盏一盏亮的")
	await click("skip")
	check(game.state.stage == "complete" and Rules.validate(game.state), "收在回执上，存档合法")
	check(game.state.chances == 1 and game.state.delivered == [[1, 1, 0], [2, 0, 1], [0, 3, 0]],
		"走出来的正是旗A 那条：用去 2 次机会")
	var paper = receipt_text()
	check("一站 1大包 1中包 = 5 单位" in paper and "二站 2大包 1小包 = 7 单位" in paper,
		"回执按玩家真正交出去的包复述，不多不少")
	check("旗A" in paper and "重新封装用去 2 次 · 余 1 次" in paper, "回执也复述真正翻出来的旗与真正用掉的机会")
	check(fits(paper, 17, game.receipt_rect().size.x - 30), "回执的文字装得下自己那块板")
	check(spilled(game.ui) == 0, "回执这一幕没有溢出盒子的文字")
	await snap("14-receipt")
	check(has_content(frames[prefix + "14-receipt"]), "回执那一帧不是空白")
	check(game.buttons.has("next") and game.buttons.next.text == "再巡一次", "最后一块牌子邀请再巡一次")
	check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"), "单独启动本关只给一条回航图的路")
	var finished = game.state.duplicate(true)
	await close_scene()
	fresh_scene()
	check(game.state == finished, "重读之后三站的货、那面旗与用掉的机会一字不变")
	await close_scene()
	Bridge.origin = "hub"
	fresh_scene()
	check(game.origin == "hub" and Bridge.origin.is_empty(), "航图的来路只被消费一次")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"), "从航图进来就给一条回去的路，不多给")
	await close_scene()
	fresh_scene()
	await click("next")
	check(game.modal and game.state.stage == "complete", "再巡一次之前先问一句")
	check("回到关前规划" in game.buttons.confirm.text and "留在码头" in game.buttons.cancel.text,
		"确认与取消都写着玩家听得懂的话")
	await click("cancel")
	check(game.state.chances == 1 and game.state.stage == "complete", "取消之后回执还在，一克货也没动")
	await click("next"); await click("confirm")
	check(game.state.stage == "arrival" and game.state.stock == Rules.START_STOCK and game.state.chances == 3,
		"回到关前规划：三站的货与三次机会都回来了")
	check(game.state.flag in [Rules.FLAG_A, Rules.FLAG_B] and game.state.shown == 0,
		"回到关前是重新开局：旗重新掷一面，但这一局之内它不会再变")
	await snap("15-back-to-start")
	await close_scene()

# ---- 旗B：走死了也如实说 ----
func play_flag_b() -> void:
	var board = dead_board()
	check(Rules.validate(board), "旗B 走死的那一份现场本身合法")
	booked(board)
	fresh_scene()
	check(game.state.station == 3 and game.state.flag == Rules.FLAG_B and game.state.chances == 0,
		"读到走死的三站：站在三站前，旗照旧是那面旗B")
	check(Rules.dead_end(game.state) and not Rules.can_serve(game.state), "这一步之后三站真的办不成")
	var report = frame_report(HOTSPOTS + ["rewind", "plan"])
	check(report[0], "死局里两条出路都摆在台面上：退回上一站的货 / 回到关前规划")
	check(report[1] and report[2], "两条出路都是够大、也在画面里的牌子")
	check(not game.buttons.plan.text.is_empty() and not game.buttons.rewind.text.is_empty(),
		"两条出路写着的是玩家听得懂的中文，不是一句责备")
	check(game.buttons.undo.disabled, "本站没摆过货，撤销不亮着骗人")
	check(not game.buttons.deliver.disabled, "提交照样按得动：让玩家自己听到那句拒绝")
	await snap("b-01-dead-end")
	# 把唯一能凑出 6 单位的三只包全放上托盘：缺的就是那条不接大包的约定
	await click("take_0"); await click("take_1"); await click("take_2")
	check(game.state.tray == [1, 1, 1] and Rules.units_of(game.state.tray) == Rules.DEMAND[2],
		"三站唯一能凑出 6 单位的摆法非用大包不可")
	var crowded = frame_report(tray_ids())
	check(crowded[0] and crowded[1] and crowded[2] and crowded[3], "托盘上的三包都点得着、在画面里、有说明")
	await click("deliver")
	check(game.state.stage == "puzzle" and "三站" in game.message and "大包" in game.message,
		"提交之后点名的正是办不成的那一站与那条约定")
	check(not game.modal and game.state.chances == 0, "没有罚站的弹窗，也不会偷偷补一次机会")
	check("重摆" in game.buttons.reset.text, "拒绝之外，「重摆」这条路也一直留在底栏上")
	await snap("b-02-refusal")
	game.message = ""
	await click("hint")
	check(game.state.hint == 1 and Rules.held_units(game.state) == 6, "提示不改货、也不减奖励")
	# 托盘上还摆着货：整站退不了，说清了先腾出托盘，一单位也不会凭空蒸发
	await click("rewind")
	check(game.state.station == 3 and game.state.tray == [1, 1, 1] and "放回台面" in game.message,
		"托盘还没腾开：退整站只会如实说，不会吞掉一批发好的货")
	for step in range(3): await click("tray_0")
	check(game.state.tray == [0, 0, 0] and game.state.stock == [1, 1, 1], "点托盘上的每一包，货真的回到台面")
	await click("rewind")
	check(game.state.station == 2 and game.state.tray == [0, 3, 1] and game.state.chances == 0,
		"退回上一站：那四包回到托盘，机会一次也不补")
	check(game.state.delivered[1] == [0, 0, 0] and Rules.validate(game.state), "退回来的那一站重新空着，账还是平的")
	check(Rules.held_units(game.state) + Rules.delivered_units(game.state) == Rules.TOTAL_UNITS,
		"退回整站一单位都不发明：18 单位还在玩家手里")
	await snap("b-03-rewound")
	await click("reset")
	check(game.modal and "已经用掉的封装机会不会退回来" in modal_text(), "重摆之前先问一句，并说清机会不退")
	check(game.buttons.confirm.text == "货放回台面", "确认牌上写的是玩家自己的说法")
	await click("confirm")
	check(Rules.packs_of(game.state.tray) == 0 and game.state.stock == [1, 4, 2] and game.state.chances == 0,
		"重摆把四包放回台面：不发明货物，也不退还机会")
	check(not game.buttons.has("plan"), "这里还剩得下二站的走法，就不催玩家回关前")
	var rewound = game.state.duplicate(true)
	await snap("b-04-reset-table")
	await close_scene()
	fresh_scene()
	check(game.state == rewound and game.state.flag == Rules.FLAG_B,
		"重摆之后的现场原样读回来，旗不会被重掷")
	await close_scene()

# 模态里那句话是宿主用 Label 写在遮罩上的，回执之外唯一一处正文。
func modal_text() -> String:
	for child in game.overlay.get_children():
		if child is Label and not child.text.is_empty(): return child.text
	return ""

func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("MK17 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false, true]:
		lite = small
		prefix = "small-" if small else ""
		root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
		path = "/tmp/pixel-mk17-ui-" + str(Time.get_ticks_usec()) + ".json"
		await play_flag_a()
		await play_flag_b()
		DirAccess.remove_absolute(path)
	print("MARKET MK17 WINDOW ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

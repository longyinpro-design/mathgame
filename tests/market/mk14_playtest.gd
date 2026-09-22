extends SceneTree
# MK14 实窗审计（v2）：真实窗口里走一遍「听完三句 → 走到摊前 → 点车挑一单 → 请砝码上秤、抬秤
# → 交完第一单之后每一单只许挪一枚，碰第二枚当场被拦下 → 挑错顺序会走死，柜面说实话并指出「重摆」
# → 走完 4→13→7 那条链，看迷你铜秤与逐单迁移回执」，在 1280×720 与 960×540 各拍一遍。
# 量的是这一关真正说出口的话：车顶板、式子牌、读数牌、底栏、回执与台词板的字宽；贴脸镜头下
# 有没有牌压在秤盘、砝码架或车上；扣扣有没有被窗框切掉；以及一条只有真窗口才看得见的界外事实
# ——两条空缺一起报时，宿主那句「（还有 1 处没有归位）」接在长句后面会不会爬出口述板。
const Scene = preload("res://game/market_mk14.tscn")
const Level = preload("res://scripts/market/mk14_scene.gd")
const Rules = preload("res://scripts/market/mk14_rules.gd")
const World = preload("res://scripts/market/mk14_world.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Focus = preload("res://tests/forest/window_focus.gd")
# 订单下标：0=桥头灯行 4 单位、1=中街油铺 7 单位、2=河下米行 13 单位。
const FOUR = 0
const SEVEN = 1
const THIRTEEN = 2
# 三单各自的唯一摆法（下标 0/1/2 对应 1、3、9 三枚）：这一关不写死答案，检查按同一份算术复核。
const FOUR_GOODS = [0, 0, 0]
const FOUR_FAR = [1, 1, 0]
const SEVEN_GOODS = [0, 1, 0]
const SEVEN_FAR = [1, 0, 1]
const THIRTEEN_FAR = [1, 1, 1]
# 交完 13 再挑 4、却伸手去够 7 的那一步：只挪了 3，两盘差 9 单位——被拦下的第二枚就是 9。
const REACH_GOODS = [0, 1, 0]
const REACH_FAR = [1, 0, 0]
# 台词板内框 798、底栏设计宽度 300、回执纸内框 276：都按设计尺寸量，不自抬自。
const BOARD_ROOM = 798.0
const STATUS_ROOM = 300.0
const PAPER_ROOM = 276.0
const CAPTURE = "res://docs/playtest/market-mk14-scale"
var game: Control
var checks = 0
var failures = 0

func _initialize() -> void: Focus.configure(root); call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func capture(name: String) -> void:
	await process_frame; await process_frame; RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")
# 一次真实的按下-抬起：不等帧，所以看得见 0.24 秒的砝码下落与 0.6 秒的挑单搬运。
func tap(id: String) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	if not game.buttons.has(id) or game.buttons[id].disabled:
		check(false,"button unavailable "+id); return
	var b: Control = game.buttons[id]
	var logical = b.get_global_transform_with_canvas()*(b.size/2)
	var point = logical*Vector2(root.size)/Vector2(1280,720)
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event)
func settle() -> void:
	while game.transient > 0: await process_frame
func click(id: String) -> void:
	tap(id); await process_frame; await settle()
func key(code: int) -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.pressed = down; root.push_input(event)
	await process_frame; await settle()
# 演出只推进、不暂停：先让宿主按新进度换算一次镜头，读到的才不是上一帧的旧镜头。
func pose(seconds: float) -> void:
	game.elapsed = seconds
	game.world.progress = minf(1, seconds / game.duration())
	game.world.queue_redraw() # explicit fixture pose while presentation is paused
	game.update_camera()
	await process_frame
func hold(seconds: float) -> void:
	game.paused = true; await pose(seconds)

func widest(text: String, px: int) -> float:
	var span := 0.0
	for line in text.split("\n"):
		span = maxf(span, UIStyle.face().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return span
# 底栏、台词板与回执走 UIStyle.text：20 抬到 22、16 抬到 18，量的是抬起之后的那一号。
func fits(text: String, requested: int, width: float) -> bool:
	return widest(text, UIStyle.text_size(requested)) <= width
# 汉字不会自动断行：一行最短的连续文字比盒子还宽，就会横着画到旁边的货上。
func spilled(parent: Node) -> int:
	var over = 0
	for child in parent.get_children():
		if not child is Label or child.text.is_empty(): continue
		var needed = child.get_combined_minimum_size()
		if needed.x > child.size.x + 1 or needed.y > child.size.y + 1:
			over += 1; print("SPILL ", child.text, " needs ", needed, " in ", child.size)
	return over
# 盒子挡不住溢出：拿标签的实际方框去比它脚下那块板，板边之外一个字都不许有。
func off_board() -> int:
	var over = 0
	for child in game.ui.get_children():
		if not child is Label or child.text.is_empty(): continue
		var box = Rect2(child.position, child.size)
		for other in game.ui.get_children():
			if not other is Panel: continue
			var board = Rect2(other.position, other.size)
			if not board.has_point(box.position): continue
			if box.end.y > board.end.y + 3 or box.end.x > board.end.x + 3:
				over += 1
				print("OFFBOARD ", child.text.replace("\n"," / "), " box ", box,
					" min ", child.get_combined_minimum_size(), " board ", board)
	return over
# 两块纸互相压角也是真机才看得见的缺陷：回执躲不开口述板就会把台词首字糊在纸底下。
func papers_clear() -> int:
	var list := []
	for child in game.ui.get_children():
		if child is Panel: list.append(Rect2(child.position, child.size))
	var hit = 0
	for a in range(list.size()):
		for b in range(a + 1, list.size()):
			if list[a].grow(-2.0).intersects(list[b].grow(-2.0)):
				hit += 1; print("COVERED paper ", list[a], " with ", list[b])
	return hit
# 柜面木牌由 plaque 直接画字、从不换行：量的是牌上真正用的那一号字（13、14、15）。
func board_size(board: Dictionary) -> int:
	return int(board["size"])
func is_plaque(board: Dictionary) -> bool:
	return bool(board["board"])
func board_text(needle: String) -> String:
	for board in game.world.signs():
		if str(board["text"]).contains(needle): return str(board["text"])
	return ""
func boards_fit() -> bool:
	var all := true
	for board in game.world.signs():
		var px: int = board_size(board)
		var room: float = float(board["rect"].size.x) - (20.0 if is_plaque(board) else 8.0)
		if widest(str(board["text"]), px) > room:
			all = false; print("PLAQUE ", board["text"], " needs ", widest(str(board["text"]), px), " in ", room)
		if is_plaque(board) and px > board["rect"].size.y:
			all = false; print("PLAQUE too short for ", px, "px: ", board["text"])
	return all
# 热点是真按钮：看不见的那半张脸也得量——尺寸、tooltip、两两不相交、没被推出画面。
func hotspot_rects() -> Array:
	var out := []
	for index in range(Rules.COUNT): out.append([game.world.rack_rect(index), "砝码架 " + str(index + 1)])
	for side in [Rules.GOODS, Rules.FAR]: out.append([game.world.pan_rect(side), "盘 " + str(side)])
	for index in range(Rules.CARTS.size()): out.append([game.world.cart_rect(index), "车 " + str(index)])
	return out
func hotspots() -> int:
	var live = 0
	for id in game.buttons:
		if not id.begins_with("rack_") and not id.begins_with("pan_") and not id.begins_with("cart_"): continue
		var b: Control = game.buttons[id]
		if b.size.x < 48 or b.size.y < 48 or b.tooltip_text.is_empty(): print("BAD target ", id, " ", b.size)
		else: live += 1
	return live
func hotspot_clashes() -> int:
	var hit = 0
	var list = hotspot_rects()
	for a in range(list.size()):
		var rect: Rect2 = list[a][0]
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640:
			hit += 1; print("OUTSIDE hotspot ", list[a][1], " ", rect)
		for b in range(a + 1, list.size()):
			if rect.intersects(list[b][0]):
				hit += 1; print("CLASH ", list[a][1], " ", rect, " with ", list[b][1], " ", list[b][0])
	return hit
# 镜头是 smoothstep 插值出来的，实窗只要求停在设计位上（浮点相等不作数）。
func at_camera(scale_x: float, at: Vector2) -> bool:
	return absf(game.world.scale.x - scale_x) < 0.002 and game.world.position.distance_to(at) < 0.1
# 木牌与秤上实物都在同一张世界平面上：谁压住谁只由矩形相交决定，与镜头无关。
func covered_things() -> int:
	var over = 0
	for board in game.world.signs():
		if not is_plaque(board): continue
		for side in [Rules.GOODS, Rules.FAR]:
			if board["rect"].intersects(game.world.pan_rect(side)):
				over += 1; print("COVERED 秤盘 ", side, " by ", board["text"], " ", board["rect"])
		for index in range(Rules.COUNT):
			if board["rect"].intersects(game.world.rack_rect(index)):
				over += 1; print("COVERED 砝码架 ", index + 1, " by ", board["text"], " ", board["rect"])
		for index in range(Rules.CARTS.size()):
			if board["rect"].intersects(game.world.cart_rect(index)):
				over += 1; print("COVERED 车 ", index, " by ", board["text"], " ", board["rect"])
	return over
# 牌子与 UI 纸面都在同一逻辑平面上：puzzle/weighing/result 把摊子抬到 1.10，
# 只看未放大坐标会漏掉「车顶板钻进口述板底下」这一类真机才看得见的遮挡。
func on_screen(rect: Rect2) -> Rect2:
	var xf: Transform2D = game.world.get_global_transform_with_canvas()
	var a = xf*rect.position
	var b = xf*(rect.position+rect.size)
	return Rect2(a, b-a)
# 每一块牌子（连它自己的字）都必须留在 1280×720 的逻辑画面里：镜头抬到 1.10 时
# 屏幕横坐标 = 世界 × 1.1 − 64，贴着画面两侧的牌会被窗框切掉首字。
func offscreen_boards() -> int:
	var cut = 0
	for board in game.world.signs():
		var shown: Rect2 = on_screen(board["rect"])
		if shown.position.x < 0 or shown.position.y < 0 or shown.end.x > 1280 or shown.end.y > 720:
			cut += 1; print("OFFSCREEN board ", board["text"], " at ", shown)
	return cut
# 扣扣是画在摊子上的人：贴脸镜头下整只都得在画面里，也不许压住架上那三枚砝码。
func keeper_off() -> int:
	var shown: Rect2 = on_screen(game.world.keeper_rect())
	var cut = 0
	if shown.position.x < 0 or shown.position.y < 0 or shown.end.x > 1280 or shown.end.y > 720:
		cut += 1; print("OFFSCREEN 扣扣 ", shown)
	for index in range(Rules.COUNT):
		if shown.intersects(on_screen(game.world.rack_rect(index))):
			cut += 1; print("COVERED 砝码架 ", index + 1, " by 扣扣 ", shown)
	return cut
func label_with(needle: String) -> Label:
	for child in game.ui.get_children():
		if child is Label and str(child.text).contains(needle): return child
	return null
# 回执只在三单都记完账那一格摊开：压到秤上实物、车里的货或出口按钮，就是收尾被自己挡住。
func sheet_covered() -> int:
	var over = 0
	var sheet: Rect2 = game.receipt_rect()
	for id in ["next","open_hub","back_hub"]:
		if not game.buttons.has(id): continue
		var b: Control = game.buttons[id]
		if sheet.intersects(Rect2(b.position, b.size)):
			over += 1; print("COVERED exit ", id, " by receipt ", sheet)
	for thing in [game.world.pan_rect(Rules.GOODS), game.world.pan_rect(Rules.FAR),
			game.world.rack_rect(0), game.world.rack_rect(Rules.COUNT - 1)]:
		if sheet.intersects(on_screen(thing)):
			over += 1; print("COVERED 秤上实物 by receipt ", sheet, " at ", thing)
	for index in range(Rules.ORDERS.size()):
		var bed: Vector2 = game.world.parcel_foot(index)
		var wide: float = game.world.parcel_width(index)
		var cargo := on_screen(Rect2(bed.x - wide/2.0, bed.y - wide*0.9, wide, wide*0.9))
		if sheet.intersects(cargo):
			over += 1; print("COVERED 车上那包 ", Rules.ORDERS[index], " by receipt ", sheet, " at ", cargo)
	return over
# 纪念物头顶那一横排重演的是最后一单的真摆法：任何一块牌子压上那一格，收尾就被自己盖住了。
func souvenir_seats() -> Array:
	var out := []
	var base: Vector2 = game.world.souvenir_foot() + game.world.SOUVENIR_BASE
	var factor: float = game.world.unit_scale() * game.world.SOUVENIR_SCALE
	var last: int = game.world.souvenir_order()
	for side in [Rules.GOODS, Rules.FAR]:
		var centre: Vector2 = game.world.cargo_at(base, factor, side, 0.0)
		var row: Array = game.world.souvenir_row(side)
		var items: Array = game.world.souvenir_items(side)
		for slot in range(items.size()):
			var wide: float = game.world.weight_width(items[slot]) * game.world.SOUVENIR_SCALE
			if items[slot] == game.world.PARCEL_SLOT:
				wide = game.world.parcel_width(last) * game.world.SOUVENIR_SCALE
			out.append(Rect2(row[slot].x - wide / 2.0, centre.y - 18.0, wide, 36.0))
	return out
func souvenir_covered() -> int:
	var over = 0
	for seat in souvenir_seats():
		for board in game.world.signs():
			if board["rect"].intersects(seat):
				over += 1; print("COVERED 纪念物那一格 by ", board["text"], " ", board["rect"], " seat ", seat)
	return over

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("MK14 window watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	for small in [false,true]:
		var prefix = "small-" if small else ""
		root.size = Vector2i(960,540) if small else Vector2i(1280,720)
		var path = "/tmp/pixel-mk14-ui-"+str(Time.get_ticks_usec())+".json"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game)
		await process_frame
		if not await Focus.ready(root): quit(1); return
		check(game.world.scene_id == "oil" and game.world.stations.has("scale_foot")
			and game.world.has_part("scale_beam") and game.world.has_part("weight_hex"),
			"小摊开在共用油庭院里那具货栈铜秤前")
		check(game.state.stage == "arrival" and game.state.order == Rules.NONE
			and game.state.goods == Rules.empty_pan() and game.state.far == Rules.empty_pan()
			and Rules.delivered(game.state) == 0 and game.state.weighs == 0 and game.state.hint == 0,
			"开场三枚砝码都在架上、三辆车都在街上：没抬过秤，也没交过一单")
		check(Rules.ORDERS == [4, 7, 13] and Rules.WEIGHTS == [1, 3, 9] and Rules.spans_all(),
			"三单是街上送来的 4、7、13，三枚是 1、3、9：回执那句「1 至 13 每单只一解」是真话")
		check(game.buttons.next.text == "继续听他们说" and not game.buttons.has("deliver"),
			"第一拍只请玩家继续听，抬秤的按钮还没出现")
		check(board_text("桥头灯行 · 4 单位 · 在车上") != "" and board_text("河下米行 · 13 单位 · 在车上") != "",
			"三辆车从第一幕起就停在街上，车顶板各自写着本单写好的数")
		check(off_board() == 0 and papers_clear() == 0 and boards_fit() and offscreen_boards() == 0,
			"开场台词与车顶板都待在自己的框里")
		await capture(prefix+"01-arrival")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == game.buttons.next,"Tab 把焦点交给开场那枚按钮")
		await key(KEY_ENTER)
		check(game.state.beat == 1 and "哪头沉哪头轻" in game.line(),
			"第二句先把「砝码只放对面」那个想当然摆出来")
		await click("next")
		check(game.state.beat == Rules.BEATS - 1 and game.buttons.next.text == "走到摊前",
			"第三句说清货压在货盘、一枚最多上一次秤、哪一单先上秤由玩家挑")
		check("一枚最多上一次秤" in game.line() and "秤也不提前说话" in game.line(),
			"抬秤之前不预告平不平，这句话在开场就讲定")
		await click("next")
		check(game.state.stage == "approach" and game.buttons.has("pause") and game.buttons.has("skip"),
			"走位是一段带控件的真动画")
		await click("pause")
		var paused_at: float = game.elapsed
		await create_timer(0.12).timeout
		check(game.elapsed == paused_at,"暂停真的把走位冻住")
		await hold(0.9)
		check(game.world.scale.x > 1.0 and game.world.scale.x < 1.10,"走近的过程里镜头一路收拢到铜秤")
		await capture(prefix+"02-walk-in")
		await click("skip")
		check(game.state.stage == "ready","走位停下来才交给玩家")
		check(game.buttons.next.text == "开始挑单","简报的按钮说的是挑单，不是配秤")
		check("点街上那三辆车挑一单" in game.line() and "架上 → 对面那盘 → 货盘" in game.line(),
			"简报先说清点车接单，再说清点一下砝码只挪一格")
		check(off_board() == 0 and fits(game.line(), 20, BOARD_ROOM),"简报两行都装在自己的板里")
		await click("next")
		check(game.state.stage == "puzzle" and at_camera(1.10, Vector2(-64,-43)),
			"配秤时镜头贴着铜秤与砝码架")
		check(hotspots() == Rules.COUNT + 2 + Rules.CARTS.size(),
			"三格架、两只盘、三辆车都是不小于 48 像素又带中文说明的真目标")
		check(hotspot_clashes() == 0,"架格、秤盘与车三组热点两两不相交，也都没压到按钮排")
		check(game.buttons.pan_2.tooltip_text.contains("这一盘不装货，只站砝码"),
			"空着的那盘被念成空盘，tooltip 顺手说清这一盘不装货")
		check(game.status_line() == "已交 0 单 · 还没接单",
			"底栏只说账上几单、手里挪了几枚，一个判分数字都没有")
		check(game.goal_line() == "点车接单 · 每一单只从上一式挪一枚 · 抬秤验平"
			and fits(game.goal_line(), 22, 762.0),"目标牌把这关的规矩整条摊在屏上，也装得下自己的牌")
		check(board_text("点街上那三辆车，挑一单先上秤") != "" and board_text("三枚砝码 · 一单只挪一枚") != "",
			"式子牌此刻只说「挑一单」：没摆之前不猜答案")
		check(game.world.parcel_spot(FOUR) == game.world.SPOT_CART,"三单货都还在各自的车上")
		await capture(prefix+"03-open-stall")
		await click("deliver")
		check(game.message == "街上三辆车还没有一辆被你点中：先挑一单，衡伯才把货搬上货盘。（还有 1 处没有归位）",
			"没接单又没上砝码：两句事实一起报，不给分数")
		check(off_board() == 0 and spilled(game.ui) == 0,
			"宿主那句尾巴接在长句后面，折行之后仍留在口述板里")
		check(game.state.stage == "puzzle" and not game.modal,"没动手就抬不了秤，也不弹「再想想」")
		await click("cart_2")
		check(game.state.order == THIRTEEN and game.message.is_empty(),"点第三辆车就把 13 单位那一单接上货盘")
		game.world.clock = game.world.pick_at + World.PICK_TIME * 0.5
		var mid: Array = game.world.parcel_leg(THIRTEEN)
		var straight: Vector2 = (mid[0] as Vector2).lerp(mid[1] as Vector2, float(mid[2]))
		check(absf(float(mid[2]) - 0.5) < 0.02 and straight.y - game.world.parcel_foot(THIRTEEN).y > 20.0,
			"挑单那一下货走的是带抛物线的搬运，不是瞬移")
		await click("deliver")
		check(game.message == "三枚砝码都还在架上：先请一枚上秤，空盘配不出这一单的货。",
			"接了单却一枚没上秤：还差的只剩一条，那句尾巴也跟着收起")
		check("头一单随便摆" in game.line() and fits(game.line(), 20, BOARD_ROOM),
			"头一单还没记账，柜面就老实说摆法随便")
		await click("rack_0")
		check(game.state.far == [1, 0, 0] and game.world.drop(0) < 1.0,
			"第一下把 1 请上对面那盘：它正从架上落进盘里")
		check(game.world.drop_at[0] > -99.0 and game.transient <= 0.0,
			"这一枚的下落由世界自己的时钟记下，不占用宿主那 0.28 秒的落地锁")
		await create_timer(0.12).timeout
		check(game.world.drop(0) > 0.0 and game.world.drop(0) < 1.0,
			"下落走到半路：既没贴着架，也没坐进盘")
		await capture(prefix+"04-weight-dropping")
		await create_timer(0.3).timeout
		check(game.world.drop(0) == 1.0,"下落走完，砝码稳稳站在盘里")
		await click("rack_1"); await click("rack_2")
		check(game.state.far == THIRTEEN_FAR and game.state.goods == Rules.empty_pan(),
			"9、3、1 三枚各点一下，全站到对面那盘")
		check(board_text("货 13 = 砝码 9 + 砝码 3 + 砝码 1") != "","式子牌复述玩家自己摆的那一式，不判对错")
		check(game.status_line() == "已交 0 单 · 这一单挪了 0 枚","头一单没有上一式可钉，这一格就是零")
		check(covered_things() == 0 and offscreen_boards() == 0 and keeper_off() == 0,
			"贴脸镜头下式子牌没压住盘、架或车，扣扣也整只在画面里")
		await capture(prefix+"05-thirteen-pan")
		await click("deliver")
		check(game.state.stage == "weighing" and game.state.weighs == 1,
			"提秤不看对错：请了砝码上秤，秤就抬，并且老实记一次抬秤")
		check(not game.buttons.has("rack_0") and not game.buttons.has("cart_2"),
			"抬秤期间热点全部收起，这一格里一枚也挪不动")
		await hold(1.2)
		check(absf(game.world.beam_angle()) < 0.09 and absf(game.world.beam_angle()) > 0.0,
			"配平的那一式只轻轻晃一下，既不锁死也不一头沉到底")
		await capture(prefix+"06-level-beam")
		await click("skip")
		check(game.state.stage == "delivery" and Rules.delivered(game.state) == 0
			and game.state.built_goods[THIRTEEN] == Rules.empty_pan(),
			"平了的这一单直接进交付：账要等货真的落回车上才记")
		check(game.line() == "衡伯画押：河下米行的 13 单位当场配平。\n还有 2 单在街上，下一单只许挪一枚砝码。",
			"头一单的交付说清「下一单起才只许挪一枚」，不含糊")
		check(board_text("订单三 签了收 · 这一式从架上摆起") != "",
			"头一单木牌说实话：这一式是从架上摆起来的，不是挪一枚挪出来的")
		await hold(2.6)
		check(game.world.parcel_spot(THIRTEEN) == game.world.SPOT_DONE
			and board_text("河下米行 · 13 单位 · 已交货") != "","货落回自己那辆车，车顶板跟着改口")
		check(game.world.parcel_spot(FOUR) == game.world.SPOT_CART,"另外两单的货还各自压在车上，等玩家点")
		game.paused = false; await create_timer(0.12).timeout
		var running: float = game.elapsed
		await create_timer(0.1).timeout
		check(game.elapsed > running,"取消暂停之后交付自己接着往下走")
		game.paused = true
		paused_at = game.elapsed
		game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(0.1).timeout
		check(game.paused and game.elapsed == paused_at and game.buttons.pause.text == "继续动画",
			"失焦把交付冻在当下这一帧，并提供继续")
		await capture(prefix+"07-handover")
		game._notification(NOTIFICATION_APPLICATION_FOCUS_IN) # return to the window before input
		await click("skip")
		check(game.state.stage == "puzzle" and Rules.delivered(game.state) == 1
			and game.state.order == Rules.NONE and game.state.built_far[THIRTEEN] == THIRTEEN_FAR,
			"货落回车上那一格才记账：交完之后挑哪一单仍由玩家决定")
		check(board_text(Rules.baseline_caption(game.state)) != "",
			"上一单记进账里的那一式钉在秤座上方，等玩家从它挪一枚")
		await click("cart_0")
		check(game.state.order == FOUR and game.state.far == THIRTEEN_FAR,"接单不动盘：13 那一式原样留着")
		await click("rack_2")
		check(game.state.goods == [0, 0, 1] and game.state.far == [1, 1, 0],
			"再点一下就是下一格：9 从对面那盘跨过秤梁站到货盘这头")
		await click("rack_2")
		check(game.state.goods == FOUR_GOODS and game.state.far == FOUR_FAR and Rules.solved(game.state),
			"再点一次才回到架上：4 单位这一式从头到尾只有一种摆法")
		check(game.status_line() == "已交 1 单 · 这一单挪了 1 枚","底栏说的就是这一单从上一式挪开的那一枚")
		check(board_text("货 4 = 砝码 3 + 砝码 1") != "","式子牌跟着新订单改口：货从 13 变成 4")
		check(boards_fit() and covered_things() == 0,"基线牌与式子牌各留自己的框，也没压住实物")
		await capture(prefix+"08-one-move")
		await click("deliver"); await click("skip")
		check(game.state.stage == "delivery" and board_text("订单一 签了收 · 只挪了一枚砝码") != "",
			"从第二单起木牌改口：这一式确实是挪一枚挪出来的")
		await click("skip")
		check(game.state.stage == "puzzle" and Rules.delivered(game.state) == 2
			and game.state.served == [THIRTEEN, FOUR],"两单都兑了出去，账上记的是玩家真摆过的两式")
		check(Rules.stuck(game.state) and game.line() == Rules.stuck_line(game.state),
			"挑错顺序走死了：柜面把话说在当下，不等人问")
		check("只剩 7 单位那一单" in game.line() and "两枚砝码都得动" in game.line() and "重摆" in game.line(),
			"死局那句话点名还剩哪一单、要动几枚，并指出退路")
		check(fits(game.line(), 20, BOARD_ROOM) and off_board() == 0,"两行的死局说法装在自己的板里")
		await capture(prefix+"09-dead-end")
		await click("cart_1")
		check(game.state.order == SEVEN,"走死了也还能把这单接上秤：只是两枚怎么挪都挪不平")
		await click("rack_1")
		check(game.state.goods == REACH_GOODS and game.state.far == REACH_FAR
			and Rules.moved_count(game.state) == 1,"先把 3 从对面请到货盘：这一步只挪了一枚")
		check(game.buttons.rack_0.tooltip_text.contains("这一单只许挪一枚"),
			"能动几枚写在热点文字里：玩家不必点了才知道越界")
		check(not game.buttons.rack_1.tooltip_text.contains("已经挪过了，这一单只许挪一枚"),
			"而过热点的那一枚自己也说清它是已经挪过的")
		await click("rack_0")
		check(game.message == "3 单位那一枚已经挪过了：一单只许挪一枚，先把它挪回原处。",
			"再伸手就被当场拦下，并且点名已经挪过的那一枚")
		check(game.state.far == REACH_FAR and game.state.goods == REACH_GOODS,"拦下的时候一枚也没多动")
		await capture(prefix+"10-second-weight-refused")
		await click("deliver"); await click("skip")
		check(game.state.stage == "result" and Rules.delivered(game.state) == 2,
			"秤照样如实抬起来：没配平就一单也不签")
		check(game.line() == "货盘这一头沉下去了：货盘 10 单位，对面那盘 1 单位。\n7 单位的货还压在盘上：两盘差 9 单位，秤没平，这一单就走不了。",
			"结果两行报的是真数：哪头沉、差几单位、这一单还没走")
		check(board_text("两盘差 9 单位 · 这一单还不能走") != "","柜面木牌与台词板报同一个差")
		check(game.world.beam_angle() < -0.1,"差九个单位的那一头真的沉到底：画面与规则同一个符号")
		check(off_board() == 0 and covered_things() == 0 and boards_fit(),"两行结果与读数牌都不越框、不压实物")
		await capture(prefix+"11-result")
		await click("next")
		check(game.state.stage == "puzzle" and game.state.goods == REACH_GOODS and game.state.weighs == 3,
			"回到秤前摆法原样保留：抬过三次秤，一单也没扣")
		await click("rack_1")
		check(game.state.goods == Rules.empty_pan() and Rules.moved_count(game.state) == 1,
			"把 3 挪回架上仍只算挪过这一枚：货盘这头只剩这一单的货")
		await click("rack_1")
		check(game.state.far == FOUR_FAR and Rules.moved_count(game.state) == 0,
			"挪回原处就不算挪过第二枚：这一单又从头开始挑")
		await click("cart_2")
		check(game.message == "这一单早就配平交出去了：货回到自己那辆车上，等的是另外两单。",
			"已经签了收的那一单不再上秤，说法把它留在自己那辆车上")
		await click("hint"); await click("hint"); await click("hint"); await click("hint")
		check(game.state.hint == Rules.HINT_TIERS,"提示停在出货的那一档，不再往下要")
		check(game.message == game.hint_texts()[Rules.HINT_TIERS-1] and "4→13→7" in game.message
			and "必须走在中间" in game.message,"顶档示范的是「谁走在中间」这一步，不是替玩家接单")
		check(fits(game.message, 20, BOARD_ROOM) and game.message.count("\n") == 1,"两行提示装在自己的板里")
		check(game.state.far == FOUR_FAR and game.state.order == SEVEN,"提示只多说话：一枚砝码也没替玩家挪")
		await capture(prefix+"12-hints")
		await click("reset")
		check(game.modal and "已经交出去的 2 单也会退回街上" in game.reset_prompt()[0],
			"重摆先问一句，而且话说在前面：链子留一环都不算重摆")
		await capture(prefix+"13-reset-asked")
		await click("cancel")
		check(not game.modal and Rules.delivered(game.state) == 2,"取消就留在走死的现场，一单也没丢")
		await click("reset"); await click("confirm")
		check(Rules.delivered(game.state) == 0 and game.state.goods == Rules.empty_pan()
			and game.state.order == Rules.NONE and game.state.weighs == 3,
			"重摆把整条链退回街上：抬过几次秤是发生过的事，不清零")
		await key(KEY_Z)
		check(Rules.delivered(game.state) == 0 and game.state.far == FOUR_FAR and game.state.order == SEVEN,
			"撤销只把秤上那一摆请回来：已经退回街上的那两单不会凭空签回收")
		await key(KEY_E)
		check(game.message == "9 单位 本来就还在架上。","E 请不动一枚本来就在架上的砝码，说法如实")
		await key(KEY_W)
		check(game.state.far == [1, 0, 0] and game.state.goods == Rules.empty_pan(),
			"W 把 3 直接放回架上：短的一格也是一次真挪动")
		await key(KEY_2)
		check(game.state.far == FOUR_FAR,"再按一次 2 就把它请回对面那盘")
		await key(KEY_A)
		check(game.state.order == FOUR and game.state.goods == FOUR_GOODS and Rules.solved(game.state),
			"A 挑桥头灯行：键盘换单与鼠标同一个入口，摆好的那一式正好配平")
		await click("deliver"); await click("skip"); await click("skip")
		check(game.state.served == [FOUR] and Rules.delivered(game.state) == 1,"4 单位那一单先兑出去")
		await key(KEY_D); await key(KEY_3)
		check(game.state.order == THIRTEEN and game.state.far == THIRTEEN_FAR
			and Rules.moved_count(game.state) == 1,"D 挑河下米行，只把 9 请上对面那盘：一步不多")
		await click("deliver"); await click("skip"); await click("skip")
		await key(KEY_S); await key(KEY_2)
		check(game.state.order == SEVEN and game.state.goods == SEVEN_GOODS and game.state.far == SEVEN_FAR
			and Rules.moved_count(game.state) == 1 and Rules.balanced(game.state),
			"最后一单只把 3 从对面挪到货盘：13 走在中间，前后两单都只挪一枚")
		await click("deliver"); await click("skip"); await click("skip")
		check(game.state.stage == "complete" and game.state.served == [FOUR, THIRTEEN, SEVEN]
			and Rules.validate(game.state) and at_camera(1.0, Vector2.ZERO),
			"三单都兑完，镜头拉回整座庭院：走完的顺序正是 4→13→7")
		var paper = label_with("回执 · 一单只挪一枚")
		check(paper != null and paper.text.contains("起手 4 单位：对面 3、1 · 架上 9")
			and paper.text.contains("4 → 13：只挪 9（架上→对面）")
			and paper.text.contains("13 → 7：只挪 3（对面→货盘）"),
			"回执逐单说清起手那一式与每一步挪了哪一枚、从哪儿到哪儿")
		check(paper != null and paper.text.contains("4与7差3单位，需动两枚砝码")
			and paper.text.contains("1 至 13 每单只一解"),"最后两行是三单之间的算术事实，不是作者的夸奖")
		check(paper != null and widest(paper.text, 18) <= PAPER_ROOM,"回执六行都贴得进自己那张纸的内框")
		var stacked := 0.0
		if paper != null:
			for row in range(paper.get_line_count()): stacked += paper.get_line_height(row)
		check(paper != null and paper.get_line_count() == game.receipt_lines().size()
			and paper.position.y + stacked <= game.receipt_rect().end.y,
			"六行全部写在纸上，没有一行挂在纸边之外")
		check(paper != null and paper.get_theme_font_size("font_size") >= 18,"回执不低于全章最小字号")
		check(paper != null and not "罚" in paper.text and not "失败" in paper.text,"回执里没有惩罚式措辞")
		check(board_text("迷你铜秤 · 三单的摆法") != ""
			and board_text("3. 货 7 + 砝码 3 = 砝码 9 + 砝码 1") != "",
			"纪念物头顶立着牌子，三笔记进账里的真摆法逐条写在秤座下方")
		check(game.world.souvenir_items(Rules.GOODS).size() == 2
			and game.world.souvenir_items(Rules.FAR) == [2, 0],
			"纪念物重演的是最后一单真正记下的那一式，不是写死的答案")
		check(off_board() == 0 and papers_clear() == 0 and boards_fit() and spilled(game.ui) == 0,
			"收尾没有越框的字，两块纸也不互相压角")
		check(covered_things() == 0 and sheet_covered() == 0 and souvenir_covered() == 0
			and offscreen_boards() == 0 and keeper_off() == 0,
			"回执不压秤上实物与出口，纪念物也没被任何牌子盖住")
		await capture(prefix+"14-receipt")
		var on_disk = game.state.duplicate(true)
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.state == on_disk,"重新打开就是记完三单的现场，一枚不差")
		check(game.state.served == [FOUR, THIRTEEN, SEVEN] and not game.buttons.has("reset"),
			"读档保住三笔记录：误点也清不掉已经交出去的那几单")
		game.queue_free(); await process_frame
		Bridge.origin = "hub"
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.origin == "hub" and Bridge.origin.is_empty(),"航图是谁送来的只读一次")
		check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"),
			"从航图进来只给回去的那一条路")
		var back: Control = game.buttons.back_hub
		check(back.size.x >= 48 and back.size.y >= 48,"回航图那枚按钮不小于 48 像素")
		if not small: await capture("15-from-chart")
		game.queue_free(); await process_frame
		game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
		check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"),
			"单独启动这一幕也自己长出回航图的路")
		await click("next")
		check(game.modal and game.state.stage == "complete","再配一次先问一句")
		await click("cancel")
		check(Rules.delivered(game.state) == 3,"取消就留在已经兑完三单的现场")
		await click("next"); await click("confirm")
		check(game.state.stage == "arrival" and game.state.served.is_empty()
			and game.state.goods == Rules.empty_pan() and game.state.weighs == 0 and game.state.hint == 0,
			"重新体验把这一摊的账整个倒回：三单、四次抬秤与三档提示一起清空")
		await click("next"); await click("next"); await click("next")
		check(game.state.stage == "approach","同样三句把玩家带回摊前")
		await click("skip"); await click("next")
		check(game.state.stage == "puzzle" and game.state.hint == 0,"走位仍然在交给玩家之前停住")
		await click("cart_1")
		check(game.state.order == SEVEN and game.world.parcel_spot(SEVEN) == game.world.SPOT_CART,
			"鼠标点车与键盘同一入口：货先还站在自己那辆车里")
		game.world.clock = game.world.pick_at + World.PICK_TIME
		check(game.world.parcel_spot(SEVEN) == game.world.SPOT_PAN
			and board_text("中街油铺 · 7 单位 · 上秤了") != "","搬运走完，车顶板才改口说上秤了")
		await click("rack_0"); await click("rack_1"); await click("rack_1"); await click("rack_2")
		check(game.state.goods == SEVEN_GOODS and game.state.far == SEVEN_FAR and Rules.solved(game.state),
			"三格架连点：1、9 上对面，3 跨过秤梁到货盘——7 单位那一式摆好了")
		await click("hint")
		check(game.state.hint == 1 and "只能从上一单记下的那一式挪一枚砝码" in game.message,
			"第一级只提醒关系，不给出摆法")
		check("还没交出去" in game.reset_prompt()[0],"还没记账时，重摆那句问话说的是眼下这一份现场")
		await click("reset"); await click("confirm")
		check(game.state.hint == 1 and game.state.goods == Rules.empty_pan()
			and game.state.order == Rules.NONE,"重摆只把货与砝码退回原处：问过的提示等级不没收")
		check(game.world.parcel_spot(SEVEN) == game.world.SPOT_CART,
			"重摆之后那一单的货回到自己车上，车顶板也跟着改回「在车上」")
		await capture(prefix+"16-reset-clean")
		game.queue_free(); await process_frame
		DirAccess.remove_absolute(path)
	print("MARKET MK14 WINDOW ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

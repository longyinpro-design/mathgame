extends "res://scripts/market/kit_world.gd"
# MK10 大码头「无论回哪封信」：两张还在等回信的订单并排钉在预测板上（或运 3 箱、或运 6 箱，
# 两个可能开局就公开），红船与蓝船泊在近岸、各自的收费牌挂在船底，筹票匣摆在码头空地上。
# 底景、船、封箱、回执纸、信卷与领航灯全部取自 kit-v1 拆件包；箱数、票额、站位与船的航迹
# 由引擎绘制，坐标只来自 manifest 的 dock 场景（boat_red / boat_blue / packing / boss_foot / lantern），
# 关卡里不再另立第二套摊位位置。
# 折羽没有集市拆件：它沿用森林岛共享的伙伴表 assets/runtime/forest/actors.json 的离散帧，
# 与 scripts/ui/companion_actor.gd 读同一份数据，只取 idle／talk 两帧，不是新裁的美术。
const Rules = preload("res://scripts/market/mk10_rules.gd")
const BACKDROP = preload("res://assets/runtime/market/kit-v1/backgrounds/grand-dock-clean-v1.png")
const ACTORS_PATH = "res://assets/runtime/forest/actors.json"
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const BOAT_STATIONS = ["boat_red", "boat_blue"]
const BOAT_ART = ["transport_boat_red", "transport_boat_blue"]
const CRATE_ART = ["crate_red", "crate_blue"]
const ORDER_TAGS = ["甲单", "乙单"]
const BOAT_WIDTH = 175.0
const PAPER_WIDTH = 104.0
const CRATE_WIDTH = 30.0
const TILE_WIDTH = 40.0
const TICKET_WIDTH = 26.0
const LANTERN_WIDTH = 100.0
# 查询信是船上的小件：44 宽时这张纸有 34 高，站在甲板上正好钻进台词板那条带子，
# 收到 36 之后连船带货都还留在台词板下缘之外。
const LETTER_WIDTH = 36.0
const CARD_W = 180.0
const CARD_H = 26.0
const INK_DIM = Color("b6a98d")
# 封箱在订单格里按 3 列排：3 箱一行、6 箱两行，位置由 grid() 算出来。
const CRATE_COLUMNS = 3
const CRATE_STEP = Vector2(34, 30)
const CRATE_DROP = 40.0
# 甲板线取在吃水线上方 10 像素：船身只有脚下那 52 像素露在台词板下面（红船 175..227），
# 原来钉在 -58（世界 y 169）——整批封箱落在台词板底下，玩家只看到箱子飞进那块木头里。
const DECK_LIFT = 10.0
const DECK_PITCH = 26.0
# 随船那封查询信站在甲板右舷、往下钉 4 像素贴在船帮上：宽 36 的纸有 28 高，
# 脚点正好落在甲板线上时纸顶会爬进宿主台词板的投影里那几条（装船刚收尾那几帧镜头才回到 1.0）。
# 它什么时候才出现，看的是货上没上齐（draw_boats 里跟着 deck_load 走）。
const LETTER_SHIFT = Vector2(48, 4)
# 结清的筹票落到这条船泊位前的收费牌上（牌在世界 y 239 起）：船身那一段在台词板底下，
# 票匣又正好在船的右下方，只有这块木头是 1.10 倍镜头下也全程看得见的落点。
const BERTH_LIFT = 24.0
const BERTH_PITCH = 6.0
const TILE_STEP = 48.0
const TILE_LIFT = 24.0
const TILE_FONT = 15
const FEATHER_IDLE = 0
const FEATHER_TALK = 21
const FEATHER_SCALE = 0.42
# 离岸只做整体平移并缩小（manifest 允许船只平移，不承诺轮帆骨骼），
# 消失点取两船站位的中点朝海一侧，缩到四成、淡到七成。
const SAIL_SHIFT = Vector2(60, -20)
const SAIL_FAR = 0.42
const SAIL_ALPHA = 0.7
var picked := 0
var actors: Dictionary = {}
var actor_sheets: Dictionary = {}
var _cells: Array = []
var _tiles: Array = []
var _tickets: Array = []

func ready_level() -> void:
	scene_id = "dock"
	backdrop = BACKDROP
	actors = JSON.parse_string(FileAccess.get_file_as_string(ACTORS_PATH))
	if actors.has("feather"): actor_sheets["feather"] = load(actors["feather"].path)

# 只有刚写上订单格的那张票额签、以及刚选定的那条约定需要落下动画；
# 宿主要先把提交后的状态交给世界，这里才比较得出「哪一格刚变」。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if state.stage != "puzzle" or previous.stage != "puzzle": return
	if not previous.has("written") or not state.has("written"): return
	for slot in range(Rules.SLOTS):
		if state.written[slot] != previous.written[slot]:
			land_place = "slip"; land_slot = slot
	if state.boat != previous.boat and state.boat >= 0:
		land_place = "boat"; land_slot = state.boat

# ---- 几何：一切都从 manifest 站位推出来 ----
func cell_spots() -> Array:
	if _cells.is_empty():
		_cells = grid(station("packing") + Vector2(-16, -10), Vector2(190, 0), Rules.SLOTS, Rules.SLOTS)
	return _cells

func cell_spot(slot: int) -> Vector2: return cell_spots()[slot]
func paper_foot(slot: int) -> Vector2: return cell_spot(slot) + Vector2(0, 46)
func crate_spots(slot: int) -> Array:
	return grid(cell_spot(slot) - Vector2(CRATE_STEP.x, 20), CRATE_STEP, CRATE_COLUMNS, Rules.CASES[slot])
func cell_rect(slot: int) -> Rect2: return target(paper_foot(slot), 140, 118)
func slip_rect(slot: int) -> Rect2: return Rect2(cell_spot(slot).x - 62, cell_spot(slot).y + 18, 124, CARD_H)
func order_rect(slot: int) -> Rect2: return Rect2(cell_spot(slot).x - 90, cell_spot(slot).y - 118, 180, CARD_H)
func note_rect(slot: int) -> Rect2: return Rect2(cell_spot(slot).x - 95, cell_spot(slot).y + 52, 190, CARD_H)

func boat_spot(boat: int) -> Vector2: return station(BOAT_STATIONS[boat])
func boat_rect(boat: int) -> Rect2: return target(boat_spot(boat) + Vector2(0, 50), 120, 78)
func card_rect(boat: int, line: int) -> Rect2:
	return Rect2(boat_spot(boat).x - CARD_W / 2, boat_spot(boat).y + 12 + line * (CARD_H + 2), CARD_W, CARD_H)
func deck_foot(boat: int) -> Vector2: return boat_foot(boat) + Vector2(0, -DECK_LIFT * boat_scale(boat))
# 船上的货按一条横排摆：一单几箱就占几个位置，整排以船身为中线。
# 原来分两行（层高 -13），第二行的脚点在世界 y 156——比台词板下缘（1.0 倍时 184）还高 28 像素，
# 六箱那一单有一半货从来没露过面；缩到一横排之后每一箱都站在看得见的那条船板上。
func deck_spot(boat: int, index: int, load: int) -> Vector2:
	return deck_foot(boat) + Vector2((index - (load - 1) / 2.0) * DECK_PITCH, 0) * boat_scale(boat)
# 随船那封查询信站在甲板右舷：审计量的就是这一格，画与量不会各说一套。
func letter_foot(boat: int) -> Vector2: return deck_foot(boat) + LETTER_SHIFT * boat_scale(boat)

func tile_spots() -> Array:
	if _tiles.is_empty():
		var from = station("boss_foot") + Vector2(113, -273)
		for step in range(Rules.TILES): _tiles.append(from + Vector2(0, step * TILE_STEP))
	return _tiles

func tile_spot(index: int) -> Vector2: return tile_spots()[index]
func tile_rect(index: int) -> Rect2: return target(tile_spot(index), 48, TILE_LIFT)
func tile_value(index: int) -> int: return Rules.TILE_VALUES[index]

func ticket_spots() -> Array:
	if _tickets.is_empty():
		_tickets = grid(station("boss_foot") + Vector2(-120, -200), Vector2(30, 36), 5, Rules.BUDGET)
	return _tickets

func box_spot(index: int) -> Vector2: return ticket_spots()[index]
func box_rect() -> Rect2:
	var from = box_spot(0)
	return Rect2(from.x - 44, from.y - 60, 220, CARD_H)
func paid_rect() -> Rect2: return shifted(box_rect(), Vector2(0, 104))
# Rect2 只能整体平移，这里统一走一个辅助式，免得各处手写第二个 Rect2。
func shifted(board: Rect2, offset: Vector2) -> Rect2: return Rect2(board.position + offset, board.size)
func keeper_foot() -> Vector2: return station("boss_foot") + Vector2(-67, 0)
func reader_foot() -> Vector2: return station("boss_foot") + Vector2(280, -20)
func lantern_foot() -> Vector2: return station("lantern")
func sail_point() -> Vector2: return station("boat_red").lerp(station("boat_blue"), 0.5) + SAIL_SHIFT

# manifest 的 attachment 公式：世界落点 = 脚点 + (附件像素 − anchor_px) × scale，缩放只乘一次。
func kit_point(id: String, foot: Vector2, width: float, px: Vector2) -> Vector2:
	var item: Dictionary = parts[id]
	return foot + (px - Vector2(item.anchor_px[0], item.anchor_px[1])) * (width / atlases[id].get_width())

func lantern_glass(foot: Vector2) -> Vector2:
	var item: Dictionary = parts["navigation_lantern"]
	var center = Vector2(item.attachments_px.light_center[0], item.attachments_px.light_center[1])
	return kit_point("navigation_lantern", foot, LANTERN_WIDTH, center)

# ---- 派生读数：画面不另存任何计数 ----
func written_value(slot: int) -> int: return state.written[slot]

# 交单之后剧情才确认本局是哪一单：确认的那一格亮着，另一格退成背景。
func confirmed_slot() -> int: return Rules.CASES.find(state.branch)

func crate_alpha(slot: int) -> float:
	if state.stage not in Rules.SETTLED: return 1.0
	return 1.0 if slot == confirmed_slot() else 0.34

func sail_amount() -> float:
	match state.stage:
		"delivery": return smoothstep(0.5, 1.0, progress)
		"complete": return 1.0
	return 0.0

func sailing() -> bool: return state.stage in ["delivery", "complete"] and state.boat >= 0

func boat_foot(boat: int) -> Vector2:
	if not sailing() or boat != state.boat: return boat_spot(boat)
	return boat_spot(boat).lerp(sail_point(), sail_amount())

func boat_scale(boat: int) -> float: return boat_width(boat) / BOAT_WIDTH

func boat_width(boat: int) -> float:
	if not sailing() or boat != state.boat: return BOAT_WIDTH
	return BOAT_WIDTH * lerpf(1.0, SAIL_FAR, sail_amount())

func boat_alpha(boat: int) -> float:
	if not sailing() or boat != state.boat: return 1.0
	return lerpf(1.0, SAIL_ALPHA, sail_amount())

# 装船的封箱：只搬本局确认的那一单，张数就是箱数。
func carry_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "delivery" or state.boat < 0 or not state.has("written"): return plan
	var slot = confirmed_slot()
	var phase = clampf(p / 0.5, 0, 1)
	var spots = crate_spots(slot)
	var load = Rules.CASES[slot]
	for index in range(load):
		var home: Vector2 = spots[index]
		plan.append({"slot": slot, "home": home, "at": home.lerp(deck_spot(state.boat, index, load), phase)
			- Vector2(0, sin(phase * PI) * CRATE_DROP), "phase": phase})
	return plan

# 甲板上已经就位的那一单：前半程货还在空中，后半程才落到船上。
func deck_load(boat: int) -> Array:
	var load: Array = []
	if boat != state.boat or state.boat < 0 or not sailing(): return load
	if state.stage == "delivery" and progress < 0.5: return load
	var slot = confirmed_slot()
	var count = Rules.CASES[slot]
	for index in range(count): load.append({"slot": slot, "at": deck_spot(boat, index, count)})
	return load

# 付出去的筹票：交单确认之后一张一张离开票匣，落到这条船泊位前的收费牌上才算收讫。
# 每张错开 0.03 出发、各走 0.55——匣子里的张数与牌上的「付讫」都跟着一张张走，不会一帧清空。
func ticket_phase(p: float, step: int) -> float:
	return clampf((p - step * 0.03) / 0.55, 0, 1)

func ticket_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "confirming" or state.boat < 0 or not state.has("paid"): return plan
	var spots = ticket_spots()
	for step in range(state.paid):
		var phase = ticket_phase(p, step)
		if phase <= 0.0: continue
		var home: Vector2 = spots[Rules.BUDGET - 1 - step]
		var to = boat_spot(state.boat) + Vector2(-16 + (step % 4) * 9,
			BERTH_LIFT + BERTH_PITCH * int(step / 4))
		plan.append({"home": home, "at": home.lerp(to, phase), "phase": phase})
	return plan

func tickets_left() -> int:
	match state.stage:
		"confirming": return Rules.BUDGET - ticket_plan(progress).size()
		"clarify", "delivery", "complete": return Rules.BUDGET - state.paid
	return Rules.BUDGET

func paid_tickets() -> int:
	return state.paid if state.stage in Rules.SETTLED else 0

# 已经落到收费牌上的那几张：只有它们能被「付讫」那块牌念出来，在半空的不算收讫。
func paid_landed() -> int:
	if state.stage != "confirming": return paid_tickets()
	var done = 0
	for entry in ticket_plan(progress):
		if float(entry["phase"]) >= 1.0: done += 1
	return done

# ---- 绘制 ----
func draw_boats() -> void:
	for boat in range(Rules.BOATS):
		var foot = boat_foot(boat)
		var width = boat_width(boat)
		var dim = boat_alpha(boat) * (1.0 if boat == state.boat or state.boat < 0 else 0.72)
		contact(foot, width * 0.34, 0.18 * dim)
		kit(BOAT_ART[boat], foot, width, dim)
		for entry in deck_load(boat):
			kit(CRATE_ART[entry["slot"]], entry["at"], CRATE_WIDTH * boat_scale(boat), dim)
		if not deck_load(boat).is_empty():
			# 查询信是货上齐那一刻才交上船的：装船的前半程这条船还泊在岸上、镜头收在 1.10，
			# 整个船身都压在宿主那块对白板底下，信摆上去就是给玩家看一个看不见的东西。
			kit("paper_roll", letter_foot(boat), LETTER_WIDTH * boat_scale(boat), dim)
		if state.stage == "puzzle":
			var strength = 0.62 if state.boat == boat else 0.24 + 0.16 * pulse()
			socket(foot + Vector2(0, -12), Vector2(width * 0.28, 12), strength)

# 被拉走那一单的封箱此刻还该不该画在预测板上：货一旦离格（飞在半空、已经上船、船已离岸），
# 格子里就不该再留第二份——原来装船后半程它们会凭空回到刚离开的那一格，与船上一眼看去是两批货。
func goods_still_on_board(slot: int) -> bool:
	return not (state.stage in ["delivery", "complete"] and state.boat >= 0
		and slot == confirmed_slot())

func draw_cells() -> void:
	var hidden = hide_while_moving(carry_plan(progress))
	for slot in range(Rules.SLOTS):
		var dim = crate_alpha(slot)
		kit("receipt_blank", paper_foot(slot), PAPER_WIDTH, 0.55 + 0.45 * dim)
		for foot in crate_spots(slot):
			if foot in hidden or not goods_still_on_board(slot): continue
			contact(foot, CRATE_WIDTH * 0.5, 0.22 * dim)
			kit(CRATE_ART[slot], foot, CRATE_WIDTH, dim)
		if state.stage == "puzzle" and slot == picked:
			socket(slip_rect(slot).get_center(), Vector2(66, 15), 0.34 + 0.24 * pulse())

func draw_tiles() -> void:
	for index in range(Rules.TILES):
		var foot = tile_spot(index)
		var value = tile_value(index)
		var on_sheet = state.stage == "puzzle" and value == written_value(picked)
		var label = Rules.tile_text(value)
		var wide = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TILE_FONT).x
		kit("receipt_blank", foot, TILE_WIDTH, 0.92 if value != Rules.UNWRITTEN else 0.4)
		words(label, foot + Vector2(-wide / 2, -13), TILE_FONT, INK_GOLD if on_sheet else INK_LIGHT)
		if state.stage == "puzzle":
			socket(foot - Vector2(0, 18), Vector2(23, 10), 0.5 if on_sheet else 0.18 + 0.12 * pulse())

func draw_box() -> void:
	# 匣子里只画还没交出去的那几张。收讫的那一叠原来另画在扣扣爪子上，位置落在她自己的身体
	# 范围里（0.5 倍身位有 163×122，那块纸正好在她肚子上），而 draw_figures() 在 draw_box()
	# 之后——一张都没露过面，只留下「匣外多出一叠」的幻影计数；落定的读数交给「付讫」那块牌。
	var spots = ticket_spots()
	for index in range(tickets_left()):
		kit("receipt_blank", spots[index], TICKET_WIDTH)

func draw_lantern() -> void:
	var foot = lantern_foot()
	var lit = 0.0
	match state.stage:
		"delivery": lit = smoothstep(0.3, 1.0, progress)
		"complete": lit = 1.0
	kit("navigation_lantern", foot, LANTERN_WIDTH, 0.82 + 0.18 * lit)
	if lit <= 0.0: return
	var glass = lantern_glass(foot)
	var beat = 0.88 + 0.12 * sin(clock * 3.0)
	draw_circle(glass, 26.0 * lit * beat, Color(1.0, 0.72, 0.30, 0.18 * lit))
	draw_circle(glass, 13.0 * lit, Color(1.0, 0.80, 0.38, 0.5 * lit))
	draw_circle(glass, 6.0 * lit, Color(1.0, 0.95, 0.78, 0.9 * lit))

func draw_flight(carried: Array, tickets: Array) -> void:
	# 封箱一落到甲板上就跟着船一起缩：船的宽度按 boat_scale 收，货还按 30 画，
	# 后半程就成了「一条 73 宽的船上驮着六只 30 宽的箱」。
	for entry in carried:
		kit(CRATE_ART[entry["slot"]], entry["at"], CRATE_WIDTH * boat_scale(state.boat),
			1.0 - clampf((entry["phase"] - 0.85) / 0.15, 0, 1) * 0.3)
	for entry in tickets:
		kit("receipt_blank", entry["at"], TICKET_WIDTH, 1.0 - clampf((entry["phase"] - 0.75) / 0.25, 0, 1))

func draw_figures() -> void:
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.5)
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, keeper_foot(), 0.5)
	draw_actor("feather", FEATHER_TALK if state.stage in ["clarify", "complete"] else FEATHER_IDLE, reader_foot())

func draw_actor(identity: String, index: int, foot: Vector2) -> void:
	if not actors.has(identity) or not actor_sheets.has(identity): return
	var frame: Dictionary = actors[identity].frames[index]
	var region: Array = frame.region
	var pivot: Array = frame.pivot
	var texture: Texture2D = actor_sheets[identity]
	contact(foot, 30.0, 0.16)
	draw_texture_rect_region(texture, Rect2(foot - Vector2(pivot[0], pivot[1]) * FEATHER_SCALE,
		Vector2(region[2], region[3]) * FEATHER_SCALE), Rect2(region[0], region[1], region[2], region[3]))

# 牌面集中在这里列出，画之前先被无头检查逐条量过宽度：
# 汉字在 Godot 里是一个不断词，plaque 又不换行，超框就会画到牌子外面。
func signs() -> Array:
	var boards = []
	for boat in range(Rules.BOATS):
		var lines = Rules.tariff_lines(boat)
		var chosen = state.stage == "puzzle" and state.boat == boat
		for line in range(lines.size()):
			var text: String = lines[line]
			if line == 0 and chosen: text += " · 已选"
			boards.append({"text": text, "rect": card_rect(boat, line),
				"color": INK_GOLD if chosen else INK_LIGHT})
	if state.stage == "arrival": return boards
	for slot in range(Rules.SLOTS):
		boards.append({"text": "%s · 或运 %d 箱" % [ORDER_TAGS[slot], Rules.CASES[slot]], "rect": order_rect(slot)})
		var drop = landing("slip", slot)
		var value = written_value(slot)
		boards.append({"text": Rules.slip_text(value),
			"rect": shifted(slip_rect(slot), Vector2(0, -24 * drop)),
			"color": INK_LIGHT if value != Rules.UNWRITTEN else INK_DIM})
	boards.append({"text": "筹票匣 · 上限 %d 张" % Rules.BUDGET, "rect": box_rect()})
	if state.stage == "puzzle":
		boards.append({"text": "正在写这一格", "rect": note_rect(picked)})
	if state.stage in Rules.SETTLED:
		boards.append({"text": "本局确认：运 %d 箱" % state.branch, "rect": note_rect(confirmed_slot())})
		# 结票那一段是「一张一张落定」的进行读数：牌面从 0/N 数到 N/N，
		# 一上来就报 N 会把还在半空的筹票说成已经收讫。
		boards.append({"text": "付讫 %d/%d 票" % [paid_landed(), state.paid] if state.stage == "confirming"
			else "付讫 %d 票" % paid_tickets(), "rect": paid_rect()})
	if state.stage in ["delivery", "complete"]:
		# 查询信随船去齿轮工坊：这句话挂在离岸那条船右舷外的海面上。
		# 两摞船底收费牌（每摞三条）已经占了 x 370..740、y 239..334 这一整条带子，牌子压牌子就会咬掉字；
		# 取 sail_point 右 145、下 3：左缘 760 离蓝船牌右缘 740 留 20 像素，牌底 242.5
		# 离蓝船牌上缘 252 留 9.5 像素；离岸前半程镜头还收在 1.10（世界要整体往左上放大），
		# 投影到屏幕之后牌顶是 195，刚好还在宿主对白板下缘（184 再加 7 像素投影）之外 4 像素。
		# 两条船最宽也只画到 x 737，这块牌永远不会盖住船身。
		boards.append({"text": "随船 · 一封查询信", "rect": follow_rect()})
	return boards

# 随船那句牌的位置单独露一手，好让实窗审计能量它和别的牌之间的缝。
func follow_rect() -> Rect2: return Rect2(sail_point().x + 145, sail_point().y + 3, 200, CARD_H)

func draw_signs() -> void:
	for board in signs():
		plaque(board["text"], board["rect"], 16, board.get("color", INK_LIGHT))

func draw_level() -> void:
	if not state.has("written"): return
	draw_lantern()
	draw_boats()
	draw_box()
	draw_cells()
	draw_tiles()
	draw_figures()
	draw_signs()
	# 演出的封箱与筹票最后画：它们的路径正好横穿船底那两排收费牌（y 239..306），
	# 画在牌子之前就会被整块木头盖住——实窗里那七张筹票和抬上船的箱子根本看不见。
	draw_flight(carry_plan(progress), ticket_plan(progress))

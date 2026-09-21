extends "res://scripts/market/kit_world.gd"
# MK09 灯芯街「不必两个人就换成」：五摊各挂着自己那件货，门前各摆一只收货盘。
# 底景、五摊站位、柜台与货物拆件全部来自 manifest 的 scenes[street].stations
# （counter / stall_left / stall_midleft / stall_middle / stall_midright / stall_right）；
# 摊位、货物、收货盘的落点一律由 station() 加固定偏移推出，关卡里不再另立第二套摊位坐标。
# 交换线由引擎画在街面上（draw_polyline），走的是玩家自己牵的那批线，不是写死的答案。
const Rules = preload("res://scripts/market/mk09_rules.gd")
const BACKDROP = preload("res://assets/source/market/lantern-street-stage-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
# 五摊按街上从左到右排，与 Rules.ACTORS／Rules.GOODS 同序；counter 留给扣扣与 tally。
const STALLS = ["stall_left", "stall_midleft", "stall_middle", "stall_midright", "stall_right"]
const GOOD_LIFT = 96.0
const TRAY_DROP = 34.0
# 货落在收货盘上时盘口再抬高一点，别把盘沿盖住。
const TRAY_RISE = 26.0
# 各件货的显示宽度照拆件形状配平：绳盘比布卷小一圈，五摊门前才看得出是五种货。
const GOOD_WIDTH = [44.0, 30.0, 34.0, 30.0, 40.0]
const TRAY_WIDTH = 62.0
const STRING_WIDTH = 260.0
const GOOD_TARGET = 88.0
const TRAY_TARGET = 72.0
const GOOD_LIFT_TARGET = 76.0
# 线的拱高按「收货的那一摊」取层，不按第几条线取：一条线拉回之后，剩下几条线不该跟着整排跳高度。
# 五摊的盘在街上排开，收货位不同线就不同高，两条线交叉时也各走一层（实际拱高见 arc_points 的让路）。
const ARC_LIFT = [46.0, 60.0, 52.0, 76.0, 68.0]
# 口述板的下沿：牵线阶段镜头抬到 1.10、整体下压 43 像素，世界 y 212 换算到屏幕正好是板底再往下 6 像素。
const BOARD_FLOOR = 212.0
# 一条线一种绳色：丁、戊那一对在街心十字交叉，只有颜色能说出哪根绳通向哪一个盘。
const ROPE_COLORS = [Color("ff7d63"), Color("ffd452"), Color("6fd3b8"), Color("7fb6ff"), Color("d79bff")]
# 灯串拆件里五盏灯的玻璃中心（裁剪图像素），按 manifest 的 attachment 公式换算。
const LANTERN_GLASS = [Vector2(47, 124), Vector2(136, 163), Vector2(225, 173), Vector2(316, 163), Vector2(402, 125)]

func ready_level() -> void:
	scene_id = "street"; backdrop = BACKDROP

# ---- geometry：一切从 manifest 的 street 站位推出来 ----
func foot(index: int) -> Vector2: return station(STALLS[index]) + Vector2(0, 6)
func good_spot(index: int) -> Vector2: return station(STALLS[index]) - Vector2(0, GOOD_LIFT)
func tray_spot(index: int) -> Vector2: return station(STALLS[index]) + Vector2(0, TRAY_DROP)
func good_rect(index: int) -> Rect2: return target(good_spot(index), GOOD_TARGET, GOOD_LIFT_TARGET)
func tray_rect(index: int) -> Rect2: return target(tray_spot(index), TRAY_TARGET, TRAY_TARGET - 10.0)
func name_rect(index: int) -> Rect2: return Rect2(foot(index).x - 75, foot(index).y + 52, 150, 26)
func want_rect(index: int) -> Rect2: return Rect2(foot(index).x - 75, foot(index).y + 84, 150, 26)
func counter_at(dx: float, dy: float) -> Vector2: return station("counter") + Vector2(dx, dy)
func koukou_foot() -> Vector2: return counter_at(-6, 62)
# 读数牌挂在丁摊与扣扣之间那段空街面上：490 那一版正压着扣扣的胸口和怀里的包袱。
func tally_rect() -> Rect2: return Rect2(752, 566, 200, 28)
# 街名牌挂在甲摊门面上方的檐口：世界 y 218 才躲得开贴脸镜头下压 43 像素的台词板，
# x 也从 60 挪到 72——贴脸时牌框左沿只剩 2 像素，看着像被窗框啃掉了半个字。
func street_rect() -> Rect2: return Rect2(72, 218, 220, 28)
# 灯串挂在丁、戊两摊之间的檐口下：整条串的顶端落在世界 y 216，
# 贴脸镜头（1.10，整体下压 43 像素）抬起来时仍躲得开台词板，五盏玻璃也不会被货样吃掉。
func string_foot() -> Vector2: return station("stall_midright") + Vector2(135, 12)

# 刚牵上的那条线落一次：只让新到收货盘的那件货做落下，其余原样挂着。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	if not previous.has("lines") or not state.has("lines"): return
	for receiver in range(Rules.COUNT):
		var giver: int = state.lines[receiver]
		if giver >= 0 and giver != previous.lines[receiver]:
			land_place = "tray"; land_slot = receiver

# ---- 归属永远从数组现算：草稿阶段货还在自己摊上，入账之后才按 booked 走 ----
func booked_plan() -> Array:
	return state.booked if state.stage in Rules.STAGES.slice(4) else Rules.empty_lines()

func shown_lines() -> Array:
	return draft() if state.stage == "puzzle" else booked_plan()

func draft() -> Array:
	return state.lines if state.has("lines") else Rules.empty_lines()

# 换完之后每一摊手上是哪件货：交给规则层现算，画面不另存归属。
func goods_held() -> Array:
	return Rules.goods_after(booked_plan())

# 交货演出：五件货各自沿着自己那条线离开原摊，按出货摊的先后一批起飞，全程由 booked 驱动。
# 相位为 0 的货还在原摊上，所以每一件货都出现在这份计划里，画面上不会出现「已经消失又还没到」的空档。
# 落点直接取自 arc_at()：台词说「每一件货都沿着自己的那条线走」，货就得真的压在那根画出来的线上。
func carry_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "exchanging": return plan
	var booked: Array = state.booked
	for receiver in range(Rules.COUNT):
		var giver: int = booked[receiver]
		if giver < 0: continue
		var phase = clampf((p - 0.08 * giver) / 0.55, 0.0, 1.0)
		var home = good_spot(giver); var dest = tray_spot(receiver) - Vector2(0, TRAY_RISE)
		plan.append({"giver": giver, "receiver": receiver, "home": home, "dest": dest,
			"at": arc_at(giver, receiver, smoothstep(0.0, 1.0, phase)), "phase": phase})
	return plan

func carry_by_giver(plan: Array) -> Dictionary:
	var by_giver = {}
	for entry in plan: by_giver[entry["giver"]] = entry
	return by_giver

# 起飞之后货就不在原摊上，落地之后才画进收货盘：整批一起动，但各算各的相位。
func in_flight(plan: Array) -> Dictionary:
	var flying = {}; var landed = {}
	for entry in plan:
		if entry["phase"] < 1.0: flying[entry["giver"]] = entry["at"]
		else: landed[entry["receiver"]] = true
	return {"flying": flying, "landed": landed}

# 每一件货此刻在哪：草稿阶段谁都没动，货还挂在自己摊前；入账之后才按 booked 落进收货盘。
func good_position(giver: int, carried: Dictionary) -> Dictionary:
	if state.stage not in ["exchanging", "delivery", "complete"]:
		return {"at": good_spot(giver), "mode": "home"}
	var receiver: int = state.booked.find(giver)
	if receiver < 0: return {"at": good_spot(giver), "mode": "home"}
	if state.stage == "exchanging":
		var entry = carried.get(giver, null)
		if entry == null: return {"at": good_spot(giver), "mode": "home"}
		if entry["phase"] < 1.0: return {"at": entry["at"], "mode": "fly"}
	return {"at": tray_spot(receiver) - Vector2(0, TRAY_RISE), "mode": "tray", "receiver": receiver}

func line_paths() -> Array:
	var paths: Array = []
	var lines = shown_lines()
	for receiver in range(Rules.COUNT):
		var giver: int = lines[receiver]
		if giver < 0: continue
		paths.append({"giver": giver, "receiver": receiver, "points": arc_points(giver, receiver)})
	return paths

# 一条线 = 出货摊挂着的货 → 收货摊门前的盘；自己牵给自己画成摊边的一个结。
# 两端钉死在货的家与落点上：起飞那一刻不弹一下，落地那一刻正落在盘心。
# 拱高还要给台词板让路：货是吊在线上走的，线上拱多少货顶就跟着上拱多少，
# 拱过头就等于把「布」藏进扣扣正在说的那句话底下。让不出就让这一条平一点，别整排一起动。
func arc_points(giver: int, receiver: int) -> PackedVector2Array:
	var from = good_spot(giver); var to = tray_spot(receiver) - Vector2(0, TRAY_RISE)
	if giver == receiver:
		return [from, from + Vector2(46, -26), from + Vector2(72, 12), to + Vector2(46, 26), to]
	var lift = clampf(arc_room(from, to, BOARD_FLOOR + good_rise(giver)), 0.0, ARC_LIFT[receiver])
	var mid = (from + to) * 0.5
	return [from, from.lerp(to, 0.22) - Vector2(0, lift * 0.6), mid - Vector2(0, lift),
		from.lerp(to, 0.78) - Vector2(0, lift * 0.6), to]

# 三个拱点各自能抬多高，取最小的那一个；权重与上面 0.22/0.6、0.5/1.0、0.78/0.6 一一对应。
func arc_room(from: Vector2, to: Vector2, ceiling: float) -> float:
	var best := INF
	for spot in [[0.22, 0.6], [0.5, 1.0], [0.78, 0.6]]:
		var walk: float = spot[0]
		var weight: float = spot[1]
		best = minf(best, (lerpf(from.y, to.y, walk) - ceiling) / weight)
	return best

# 货顶到货脚的高度：拆件的 anchor 就钉在货脚，缩放一次之后 anchor_px.y × scale 即这件货高出钩子多少。
func good_rise(giver: int) -> float:
	var id: String = Rules.KIT_GOODS[giver]
	var item: Dictionary = parts[id]
	return item.anchor_px[1] * (GOOD_WIDTH[giver] / atlases[id].get_width())

# 沿这条折线按路程取点：t=0 在货挂着的钩子上，t=1 在收货盘里。
func arc_at(giver: int, receiver: int, t: float) -> Vector2:
	var points := arc_points(giver, receiver)
	var legs := []
	var total := 0.0
	for index in range(1, points.size()):
		var length := points[index].distance_to(points[index - 1])
		legs.append(length); total += length
	var want := clampf(t, 0.0, 1.0) * total
	for index in range(legs.size()):
		if want > legs[index] and index + 1 < legs.size():
			want -= legs[index]; continue
		return points[index].lerp(points[index + 1], (want / legs[index]) if legs[index] > 0.0 else 1.0)
	return points[points.size() - 1]

# 方向就写在两头：出货的那一头点一颗绳结，收货的那一头画一个扎进盘里的箭头。
func draw_arrow(at: Vector2, from: Vector2, color: Color) -> void:
	var dir = (at - from).normalized()
	var wing = Vector2(-dir.y, dir.x)
	for side in [1.0, -1.0]:
		draw_line(at, at - dir * 13.0 + wing * (6.5 * side), color, 3.0, true)

func draw_lines() -> void:
	if state.stage == "arrival" or state.stage == "complete": return
	# 货各归其摊之后五条绳就该从街上收掉：留着是从空钩子上垂下一条线，替玩家把已经换完的事撤回去了。
	var fade = 1.0 - smoothstep(0.0, 0.6, progress) if state.stage == "delivery" else 1.0
	if fade <= 0.0: return
	var held = state.hand if state.stage == "puzzle" else -1
	for entry in line_paths():
		var color: Color = ROPE_COLORS[entry["receiver"]]
		if held == entry["giver"]: color = color.lightened(0.32)
		color.a *= fade
		var points: PackedVector2Array = entry["points"]
		draw_polyline(points, color, 4.6 if held == entry["giver"] else 3.2, true)
		draw_circle(points[0], 4.5, color)
		draw_arrow(points[points.size() - 1], points[points.size() - 2], color)

func draw_hung_good(giver: int, at: Vector2, swinging: bool) -> void:
	# 麻绳把货吊在摊位招牌上方；只有还挂在原摊的货才随街风轻轻摆一下。
	var post = station(STALLS[giver]) - Vector2(0, GOOD_LIFT + 44.0)
	draw_line(post, at + Vector2(0, -16.0), Color("8f6420", 0.85), 2)
	if swinging: at += Vector2(sin(clock * 1.6 + giver * 1.3) * 3.0, 0)
	kit(Rules.KIT_GOODS[giver], at, GOOD_WIDTH[giver])

func draw_stalls(carried: Dictionary) -> void:
	for index in range(Rules.COUNT):
		contact(foot(index) + Vector2(0, 14), 42, 0.2)
		kit("receiving_tray", tray_spot(index), TRAY_WIDTH, 0.95)
		if state.stage == "puzzle" and Rules.holding(state) and state.lines[index] < 0:
			socket(tray_spot(index) - Vector2(0, 20), Vector2(30, 26), 0.42 + 0.3 * pulse())
		# 刚落线的那一条在盘口亮一下：落下的是这条承诺，不是货本身（货还没离摊）。
		if state.stage == "puzzle" and landing("tray", index) > 0.0:
			socket(tray_spot(index) - Vector2(0, 20), Vector2(34, 28), 0.5 + 0.5 * landing("tray", index))
	for giver in range(Rules.COUNT):
		var where = good_position(giver, carried)
		if where["mode"] == "home":
			# 拿在手里的那一件要一眼认得出：往上抬一截、跟着手腕轻轻晃，脚下光斑也亮一档。
			var holding = state.stage == "puzzle" and state.hand == giver
			var at = where["at"] - Vector2(0, 13.0 + 2.5 * sin(clock * 3.6)) if holding else where["at"]
			draw_hung_good(giver, at, state.stage == "puzzle")
			# 摊位可牵：光斑只说「这件货还没被许出去」，不判断对面收不收。
			if state.stage == "puzzle":
				socket(at - Vector2(0, 20), Vector2(28, 24), (0.6 if holding else 0.26) + 0.18 * pulse())
			continue
		var drop = 0.0
		if where["mode"] == "tray": drop = landing("tray", where["receiver"])
		kit(Rules.KIT_GOODS[giver], where["at"] - Vector2(0, 34.0 * drop), GOOD_WIDTH[giver], 1.0 - 0.7 * drop)

func draw_figure() -> void:
	var happy = state.stage == "complete" or (state.stage == "delivery" and progress > 0.6)
	# street 场景没有人物站位：扣扣站在前景柜台正中，背对柜台面向五摊。
	# 0.5 是全章那一个身位（kit_world.figure 的默认档，MK02–MK08 都按它落位）：
	# 原先的 0.52 让她比别的关卡高出五像素，脚下的接触圈也大一圈。
	figure(KOUKOU_WAVE if happy else KOUKOU_TIE, koukou_foot(), 0.5)

# 拆件的挂点公式：世界落点 = 脚点 + (像素 − anchor_px) × scale，缩放只乘一次。
func kit_point(id: String, foot: Vector2, width: float, px: Vector2) -> Vector2:
	var item: Dictionary = parts[id]
	return foot + (px - Vector2(item.anchor_px[0], item.anchor_px[1])) * (width / atlases[id].get_width())

# 结算：五摊各自点头之后，街上第一段灯串亮起来。
func draw_lanterns(strength: float) -> void:
	if strength <= 0.0: return
	var foot = string_foot()
	# 原先是 0.4 + 0.6*strength：delivery 刚过 progress 0.1 的那一帧 strength 才 0.0001，
	# 整条串却已经从「什么都没画」跳到四成透明度——灯串是突然出现的，不是慢慢亮起来的。
	kit("lantern_string", foot, STRING_WIDTH, strength)
	for index in range(LANTERN_GLASS.size()):
		var one = clampf(strength * LANTERN_GLASS.size() - index * 0.8, 0.0, 1.0)
		if one <= 0.0: continue
		var at = kit_point("lantern_string", foot, STRING_WIDTH, LANTERN_GLASS[index])
		var beat = 0.86 + 0.14 * sin(clock * 3.2 + index * 1.7)
		draw_circle(at, 20.0 * one * beat, Color(1.0, 0.72, 0.30, 0.2 * one))
		draw_circle(at, 10.0 * one, Color(1.0, 0.86, 0.44, 0.6 * one))

# 木牌集中列在这里，画之前先被无头检查逐条量过宽度：
# 汉字在 Godot 里是一个不断词，plaque 又不换行，超框就会画到牌子外面。
func signs() -> Array:
	var boards = []
	# 交货之后门面那块牌子跟着改口，念这一摊现在手上是哪件：换完了还写着「有布」，
	# 等于把刚刚演完的那次交换又收回去。牵线阶段货仍挂在自己摊上，照原样写。
	# 换货那一段里五件货按各自相位落地（最后一件在相位 0.87 落定），牌子就在那一刻一起改口：
	# 早于这一刻等于把还在空中的货说成已经换了，晚到 delivery 又把已经躺在盘里的货还写在原摊上。
	var settled: bool = state.stage in ["delivery", "complete"] or (
		state.stage == "exchanging" and progress >= 0.87)
	var held = goods_held() if settled else range(Rules.COUNT)
	for index in range(Rules.COUNT):
		boards.append({"text": "%s摊 · 有%s" % [Rules.ACTORS[index], Rules.GOODS[held[index]]],
			"rect": name_rect(index)})
		boards.append({"text": Rules.accepts_text(index), "rect": want_rect(index)})
	if state.stage == "arrival": return boards
	boards.append({"text": "灯芯街 · 五摊当众换货", "rect": street_rect()})
	if state.stage == "puzzle":
		# 街面上的读数与底栏那一条写成同一句话：分子是阿拉伯数字、分母写成「五」，
		# 同一屏就会出现「5 摊点头」和「5 / 五」两种记法，玩家会去数哪一个才对。
		boards.append({"text": "线 %d / %d · 满意 %d / %d" % [Rules.drawn(state.lines), Rules.COUNT,
			Rules.satisfied(state.lines).size(), Rules.COUNT], "rect": tally_rect()})
	if state.stage in ["delivery", "complete"]:
		boards.append({"text": "满意 %d / %d" % [Rules.satisfied(state.booked).size(), Rules.COUNT],
			"rect": tally_rect()})
	return boards

func draw_signs() -> void:
	for board in signs(): plaque(board["text"], board["rect"])

func draw_level() -> void:
	if not state.has("lines"): return
	var carried = carry_by_giver(carry_plan(progress))
	var lit = 1.0 if state.stage == "complete" else (smoothstep(0.1, 1.0, progress) if state.stage == "delivery" else 0.0)
	draw_lanterns(lit)
	draw_lines()
	draw_stalls(carried)
	draw_figure()
	draw_signs()

extends "res://scripts/market/kit_world.gd"

# MK07 千灯集市街头：四位居民各守一个 manifest 摊位，四件援助货摆在柜台上。
# 底景、货物、托盘全部来自 kit-v1 拆件包；居民站位直接读 scenes[street].stations，不另立坐标。
# 分配用「柜面上的货 + 摊位上的半透明预定影」表示：货没有离开柜台，所以试交失败什么也没消耗。
const Rules = preload("res://scripts/market/mk07_rules.gd")
const BACKDROP = preload("res://assets/source/market/lantern-street-stage-v1.png")
const KOUKOU_TIE = preload("res://assets/runtime/market/characters/koukou-v1/tie-parcel.png")
const KOUKOU_WAVE = preload("res://assets/runtime/market/characters/koukou-v1/waving.png")
const INK_WARN = Color("ffbe9e")
const STALLS = ["stall_left","stall_midleft","stall_midright","stall_right"]
const TRAY_WIDTH = 124.0
const GOOD_WIDTH = 52.0
const HELD_WIDTH = 46.0
const ICON_WIDTH = 26.0
const STEP = 132.0
const RAISE = 36.0
# 整批交货：四件货一批离开柜台，每件晚 0.06 起步，0.44 走完，最后一件在 0.62 落位。
const STAGGER = 0.06
const TRAVEL = 0.44
# 预定影落上摊位的高度：宿主的落地锁（LAND_TIME 0.28 秒）负责计时。
const GHOST_DROP = 34.0
const GHOST_SEAT = 0.42
const GHOST_FALL = 0.86
var picked := -1
# 实窗审计要逐块量摊板上的汉字，画过的每一块都记一份，测试就不必再抄一遍坐标。
var boards: Array = []

func ready_level() -> void:
	scene_id = "street"; backdrop = BACKDROP

# ---- 站位与热点（逻辑像素，随镜头一起缩放） ----
func counter_foot(good: int) -> Vector2:
	return station("counter") + Vector2((good - 1.5) * STEP, -RAISE)

func stall(person: int) -> Vector2:
	return station(STALLS[person])

func hand_foot(person: int) -> Vector2:
	return stall(person) + Vector2(0, -12)

func good_rect(good: int) -> Rect2: return target(counter_foot(good), 62, 58)
func person_rect(person: int) -> Rect2: return target(hand_foot(person), 62, 58)

# ---- 整批交货演出 ----
func carry_phase(person: int, p: float) -> float:
	return clampf((p - STAGGER * person) / TRAVEL, 0, 1)

func carry_plan(p: float) -> Array:
	var plan: Array = []
	if state.stage != "handover": return plan
	for person in range(Rules.COUNT):
		var good: int = state.plan[person]
		if good < 0: continue
		var home := counter_foot(good)
		var glide := smoothstep(0, 1, carry_phase(person, p))
		var at := home.lerp(hand_foot(person), glide) - Vector2(0, sin(glide * PI) * 46)
		plan.append({"good": good, "person": person, "home": home, "at": at, "phase": glide})
	return plan

# 一件货在同一个时刻只能出现在一个地方：落位之前只在演出里，落位之后只在居民手里。
func at_hand(person: int) -> bool:
	if state.stage in ["delivery","complete"]: return true
	if state.stage == "handover": return carry_phase(person, progress) >= 1.0
	return false

# 上一次试交没有交齐、而且玩家还没改动方案时，才在街上标出真实缺口。
func report_plan() -> Array:
	if state.stage != "puzzle" or not state.has("failed"): return []
	var failed: Array = state.failed
	if failed.is_empty(): return []
	var last: Array = failed[failed.size() - 1]
	return last if last == state.plan else []

# 宿主在过账之后才问「谁落下来了」，所以这里能同时看到旧方案与刚提交的新方案：
# 新被预定出去的那一件就是唯一需要下坠的一户，交给基类的 landing() 与 0.28 秒落地锁。
func begin_land(previous: Dictionary) -> void:
	land_place = ""; land_slot = -1
	if previous.stage != "puzzle" or state.stage != "puzzle": return
	for person in range(Rules.COUNT):
		if state.plan[person] >= 0 and state.plan[person] != previous.plan[person]:
			land_place = "hand"; land_slot = person

# ---- 画面 ----
# plaque 从不换行，汉字又是一个不断词：把每一块画过的牌子记下来，审计才量得到真坐标。
func plaque(text: String, rect: Rect2, size_px: int = 16, color: Color = INK_LIGHT) -> void:
	boards.append({"text": text, "rect": rect, "size_px": size_px})
	super(text, rect, size_px, color)

func signs() -> Array: return boards

func draw_level() -> void:
	boards = []
	var plan: Array = state.plan if state.get("plan") is Array else Rules.empty_plan()
	draw_aid_desk()
	draw_stalls(plan)
	draw_counter(plan)
	if state.stage == "handover": draw_carried()

func draw_aid_desk() -> void:
	var foot := station("stall_middle") + Vector2(16, 4)
	figure(KOUKOU_WAVE if state.stage == "complete" else KOUKOU_TIE, foot, 0.36)
	# 牌子挂在柜台上方的木牌位上。柜台镜头是 1.10 倍、偏移 (-64,-43)，这块牌落在屏幕 y 195 起：
	# 再往上 18 像素就要钻进出口台词板（屏幕 y 98..184）的底边，牌面第一行会被压住。
	plaque("援助货 · 绳 钉 布 铃 各一件", Rect2(foot.x - 166, foot.y - 132, 320, 28))
	if state.stage in ["delivery","complete"]: kit("receipt_blank", foot + Vector2(-84, -6), 54)

func draw_stalls(plan: Array) -> void:
	var unmet: Array = Rules.unmet_of(report_plan())
	var beat := pulse()
	for person in range(Rules.COUNT):
		var foot := stall(person)
		var good: int = plan[person]
		var lacking := lacks_of(person, unmet)
		# 身份牌：这一户用得上哪几样，文字与货样图标都常显，不靠玩家记台词。
		plaque("%s · %s"%[Rules.PERSONS[person], Rules.usable_text(person)], Rect2(foot.x - 130, foot.y + 8, 260, 30))
		for index in range(Rules.ACCEPT[person].size()):
			var icon: String = Rules.KIT_GOODS[Rules.ACCEPT[person][index]]
			kit(icon, foot + Vector2(82 + index * 30, 28), ICON_WIDTH, 0.92)
		plaque(status_text(good, at_hand(person), lacking), Rect2(foot.x - 96, foot.y - 92, 192, 26),
			16, INK_WARN if not lacking.is_empty() else (INK_GOLD if good >= 0 else INK_LIGHT))
		if good >= 0: draw_held(person, good)
		if not lacking.is_empty():
			socket(foot - Vector2(0, 16), Vector2(30, 12), 0.9)
		elif state.stage == "puzzle" and good < 0:
			var ready_socket: bool = picked >= 0 and Rules.ACCEPT[person].has(picked)
			socket(foot - Vector2(0, 16), Vector2(32, 13), (0.75 if ready_socket else 0.25) * (0.6 + 0.4 * beat))

func lacks_of(person: int, unmet: Array) -> Array:
	var lacking := []
	for entry in unmet:
		if entry[0] == person: lacking.append(Rules.GOODS[entry[1]])
	return lacking

func status_text(good: int, held: bool, lacking: Array) -> String:
	if not lacking.is_empty():
		var text := "还缺："
		for index in range(lacking.size()):
			if index > 0: text += "或"
			text += lacking[index]
		return text
	if good < 0: return "还空着"
	return ("已收：" if held else "预定：") + Rules.GOODS[good]

func draw_held(person: int, good: int) -> void:
	var foot := hand_foot(person)
	if not at_hand(person):
		# 还没交货：柜台上那件是真货，摊位上只留半透明的预定影。
		# 刚预定出去的那一件从头顶坠下来坐进摊位，落定后才安静地当影子。
		if state.stage == "puzzle":
			var arrival := landing("hand", person)
			kit(Rules.KIT_GOODS[good], foot - Vector2(0, GHOST_DROP * arrival), HELD_WIDTH,
				lerpf(GHOST_SEAT, GHOST_FALL, arrival))
		return
	var settle := 0.0
	if state.stage == "delivery":
		settle = smoothstep(0.1 + STAGGER * person, 0.6 + STAGGER * person, progress) * 10.0
		socket(foot - Vector2(0, 6), Vector2(34, 14), 0.5 + 0.5 * pulse())
	contact(foot, HELD_WIDTH * 0.42, 0.24)
	kit(Rules.KIT_GOODS[good], foot - Vector2(0, settle), HELD_WIDTH)

func draw_counter(plan: Array) -> void:
	for good in range(Rules.COUNT):
		var foot := counter_foot(good)
		kit("receiving_tray", foot + Vector2(0, 8), TRAY_WIDTH)
		var holder := Rules.holder_of(plan, good)
		var label: String = Rules.GOODS[good] + (" → " + Rules.PERSONS[holder] if holder >= 0 else " · 未分配")
		if state.stage in ["delivery","complete"]:
			plaque(label, Rect2(foot.x - 70, foot.y + 40, 140, 28), 16, Color("b6a98d"))
			continue
		# 演出期间真货正在空中或已经落在居民手里，柜面只剩空托盘。
		if state.stage != "handover":
			contact(foot, GOOD_WIDTH * 0.42, 0.26)
			var lift := -14.0 if picked == good else 0.0
			kit(Rules.KIT_GOODS[good], foot, GOOD_WIDTH, 0.8 if holder >= 0 else 1.0, lift)
			if picked == good: socket(foot - Vector2(0, 10), Vector2(30, 12), 0.6 + 0.4 * pulse())
		plaque(label, Rect2(foot.x - 70, foot.y + 40, 140, 28), 16, INK_GOLD if holder >= 0 else INK_LIGHT)

func draw_carried() -> void:
	for entry in carry_plan(progress):
		if entry["phase"] >= 1.0: continue
		kit(Rules.KIT_GOODS[entry["good"]], entry["at"], GOOD_WIDTH, 1.0)

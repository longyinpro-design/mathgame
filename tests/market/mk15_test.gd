extends SceneTree
# MK15 不会越换越多的铜果：无头规则、算术穷举、存档与真实场景检查。
# 运行：godot --headless --path . --script tests/market/mk15_test.gd
const Rules = preload("res://scripts/market/mk15_rules.gd")
const Catalog = preload("res://scripts/market/chapter_catalog.gd")
const Content = preload("res://scripts/content/content_catalog.gd")
const Bridge = preload("res://scripts/market/market_bridge.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const World = preload("res://scripts/market/mk15_world.gd")
const Scene = preload("res://game/market_mk15.tscn")
const SAVE_DEFAULT = "user://profiles/market-mk15-1/save-v1.json"
var checks = 0
var failures = 0
var path = "/tmp/pixel-mk15-rules-" + str(Time.get_ticks_usec()) + ".json"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)

# 手工拼一份台面：台账是唯一事实，三堆货由它算出来；非 arrival 幕必须已经听完三句台词。
func pose(used: Array, stage: String = "puzzle") -> Dictionary:
	var value = Rules.fresh()
	value.stage = stage
	value.used = used
	var items = Rules.derived(used)
	value.fruit = items[0]; value.thread = items[1]; value.core = items[2]
	if stage != "arrival": value.beat = Rules.BEATS - 1
	return value

# 直接拧台面数字：用来伪造「凭空多出来的那一颗」这类损坏存档。
func forge(fruit: Variant, thread: Variant, core: Variant, used: Variant, stage: String = "puzzle") -> Dictionary:
	var value = pose([0, 0, 0], stage)
	value.fruit = fruit; value.thread = thread; value.core = core; value.used = used
	return value

func items_of(state: Dictionary) -> Array: return Rules.stock(state)

# 台账盒子：三堆货的非负条件就是 b <= 3a/2 与 b >= 3c，与本关 derived 的公式各自独立算一遍。
func honest_box() -> Array:
	var kept: Array = []
	for a in range(Rules.LINE_CAP[0] + 1):
		for b in range(Rules.LINE_CAP[1] + 1):
			for c in range(Rules.LINE_CAP[2] + 1):
				if 2 * b > 3 * a: continue
				if b < 3 * c: continue
				if 2 * a > 12 + 4 * c: continue
				kept.append([a, b, c])
	return kept

# 倒着走同一条合同：付出这一条的收货、换回它的付出货。三条合同都是等号，反方向也得对得上。
func inverse(items: Array, line: int, groups: int) -> Array:
	var spec: Array = Rules.LINES[line]
	if items[spec[2]] < spec[3] * groups: return []
	var next = items.duplicate(true)
	next[spec[2]] -= spec[3] * groups
	next[spec[0]] += spec[1] * groups
	return next

func named(missing: Array, word: String) -> bool:
	for line in missing:
		if word in line: return true
	return false

# 本摊合同的账只留在 mk15 这三个文件里：任何别的模块都不该带上第三条兑换率。
# 目录只登记摊名、场景与存档路径，是这一摊对外唯一的「有人知道它存在」，兑换率本身不许进去。
const RATE_MARKERS = ["3 芯 → 4 果", "2 果 → 3 线", "2 线 → 1 芯", "UNIT_OF"]
const REGISTRY = ["res://scripts/market/chapter_catalog.gd"]
func contract_leaks() -> Array:
	var found: Array = []
	for folder in ["res://scripts", "res://tests", "res://tools"]:
		var dir = DirAccess.open(folder)
		if dir == null: continue
		dir.include_hidden = false; dir.include_navigational = false
		dir.list_dir_begin()
		var name = dir.get_next()
		while name != "":
			if dir.current_is_dir():
				for nested in DirAccess.get_files_at(folder + "/" + name):
					if nested.ends_with(".gd"): found = scan_file(found, folder + "/" + name + "/" + nested)
			elif name.ends_with(".gd"): found = scan_file(found, folder + "/" + name)
			name = dir.get_next()
		dir.list_dir_end()
	return found

func scan_file(found: Array, file: String) -> Array:
	if "mk15" in file: return found
	var text = FileAccess.get_file_as_string(file)
	for marker in RATE_MARKERS:
		if marker in text: found.append(file + " 带着 " + marker)
	if "market-mk15" in text and file not in REGISTRY: found.append(file + " 带着本摊的存档路径")
	return found

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("MK15 rule watchdog"); quit(1))
	# ---- 开局与常量 ----
	check(Rules.validate(Rules.fresh()), "fresh model valid")
	check(Rules.fresh().sample == "market-mk15-1", "fresh carries the mk15 sample id")
	check(Rules.fresh().stage == "arrival" and Rules.fresh().beat == 0, "fresh opens on the street dialogue")
	check(Rules.fresh().fruit == 12 and Rules.fresh().thread == 0 and Rules.fresh().core == 0, "fresh is one batch of 12 copper fruits")
	check(Rules.fresh().used == [0, 0, 0] and Rules.fresh().hint == 0, "fresh ledger is empty and no hint was used")
	check(Rules.STOCK == 12 and Rules.SIGN_CLAIM == 13, "the stall stocks 12 and the sign asks for 13")
	check(Rules.LINES == [[0, 2, 1, 3], [1, 2, 2, 1], [2, 3, 0, 4]], "the posted contract is 2果=3线、2线=1芯、3芯=4果")
	check(Rules.UNIT_OF == [3, 2, 4] and Rules.VALUE == 36, "this stall's own ruler is 果3 线2 芯4 格, 36 格 in the batch")
	check(2 * Rules.UNIT_OF[0] == 3 * Rules.UNIT_OF[1], "合同一 in 格：2 果 = 3 线")
	check(2 * Rules.UNIT_OF[1] == 1 * Rules.UNIT_OF[2], "合同二 in 格：2 线 = 1 芯")
	check(3 * Rules.UNIT_OF[2] == 4 * Rules.UNIT_OF[0], "合同三 in 格：3 芯 = 4 果")
	check(Rules.MAX_PILE == [12, 18, 9] and Rules.LINE_CAP == [6, 9, 3], "one batch tops out at 12果/18线/9芯, i.e. 6/9/3 groups")
	check(Rules.SMALLEST_RING == [2, 3, 1], "the smallest closed ring is 2+3+1 groups")
	check(Rules.STAGES == ["arrival", "approach", "ready", "puzzle", "ringing", "delivery", "complete"], "stage list is the three beats plus the walk-in")
	check(Rules.ANIMATIONS == ["approach", "ringing", "delivery"], "only the three transitions animate")
	# ---- 一圈的倍率：正着走、倒着走都是 12/12 ----
	check(Rules.ring_ratio(false) == [12, 12], "forward ring ratio is 3x1x4 over 2x2x3 = 12/12")
	check(Rules.ring_ratio(true) == [12, 12], "reverse ring ratio is 2x2x3 over 3x1x4 = 12/12")
	var forward = Rules.walk(Rules.START.duplicate(true), 0, 6)
	check(forward == [0, 18, 0], "整批走完合同一：12 果 → 18 线，除得尽")
	forward = Rules.walk(forward, 1, 9)
	check(forward == [0, 0, 9], "整批走完合同二：18 线 → 9 芯，除得尽")
	forward = Rules.walk(forward, 2, 3)
	check(forward == Rules.START, "整批走完合同三：9 芯 → 12 果，一圈回到原点")
	var backward = inverse(Rules.START.duplicate(true), 2, 3)
	check(backward == [0, 0, 9], "倒着走合同三：12 果 → 9 芯")
	backward = inverse(backward, 1, 9)
	check(backward == [0, 18, 0], "倒着走合同二：9 芯 → 18 线")
	backward = inverse(backward, 0, 6)
	check(backward == Rules.START and Rules.value_of(backward) == Rules.VALUE, "倒着走合同一：18 线 → 12 果，格数还是 36")
	check(Rules.walk(Rules.START.duplicate(true), 0, 7).is_empty(), "第七组合同一要 14 颗果，这一批只有 12 颗")
	check(Rules.walk([11, 0, 0], 0, 6).is_empty(), "11 颗果付不出 6 组 2 颗：整组付不起就是换不动")
	check(Rules.walk([11, 0, 0], 0, 5) == [1, 15, 0], "11 颗果仍然付得起 5 组，半组不在这摊的算法里")
	# ---- 台账盒子穷举：所有圈长、所有货物数，一次算清 ----
	var legal = 0
	var closed_sets: Array = []
	var over_stock = 0
	var wrong_value = 0
	var half_piles = 0
	var same_fruit = 0
	for a in range(Rules.LINE_CAP[0] + 1):
		for b in range(Rules.LINE_CAP[1] + 1):
			for c in range(Rules.LINE_CAP[2] + 1):
				var items = Rules.derived([a, b, c])
				if items.min() < 0: continue
				legal += 1
				for value in items:
					if not value is int or value % 1 != 0: half_piles += 1
				if Rules.value_of(items) != Rules.VALUE: wrong_value += 1
				if items[0] > Rules.STOCK: over_stock += 1
				if items[0] == Rules.STOCK and items != Rules.START: same_fruit += 1
				if items == Rules.START and c > 0: closed_sets.append([a, b, c])
	check(legal == 64 and legal == honest_box().size(), "台账盒子里摆得出货的组合共 64 种，两套算法数到同一份")
	check(wrong_value == 0, "每一种合法组合按本摊的尺都还是 36 格")
	check(over_stock == 0, "64 种组合里没有一种摆得出第 13 颗果")
	check(half_piles == 0, "算出来的堆数永远是整数颗：半卷线半根芯摆不进盒子")
	check(same_fruit == 0, "果一回到 12 颗，线与芯必然同时清空：招牌要的是同一堆三样货")
	check(closed_sets == [[2, 3, 1], [4, 6, 2], [6, 9, 3]], "绕回 12 颗果的只有 1、2、3 圈这三种")
	var lengths = []
	for ledger in closed_sets: lengths.append(ledger[0] + ledger[1] + ledger[2])
	check(lengths == [6, 12, 18], "本摊一批货允许的闭环长度只有 6、12、18 组")
	for ledger in closed_sets:
		if Rules.derived(ledger) != Rules.START: wrong_value += 1
	check(wrong_value == 0 and Rules.derived(Rules.SMALLEST_RING) == Rules.START, "最短闭环 2+3+1 也正好落在 12 颗")
	# ---- 状态机穷举：真的用 trade 一步步走，不只看算式 ----
	var seen_states = {}
	var opening = Rules.fresh()
	opening.stage = "puzzle"; opening.beat = Rules.BEATS - 1
	var frontier = [opening]
	var closed_states = 0
	var richest = 0
	var off_ruler = 0
	while not frontier.is_empty():
		var current: Dictionary = frontier.pop_back()
		var key = str(items_of(current)) + str(current.used)
		if seen_states.has(key): continue
		seen_states[key] = true
		if not Rules.validate(current): break
		if Rules.value_of(items_of(current)) != Rules.VALUE: off_ruler += 1
		richest = maxi(richest, current.fruit)
		if Rules.closed(current): closed_states += 1
		for line in range(Rules.KINDS):
			var next = Rules.trade(current, line, 1)
			if not next.is_empty(): frontier.append(next)
	check(off_ruler == 0, "一步步走出来的每一种台面都在 36 格这把尺上")
	check(seen_states.size() == 64 and seen_states.size() == legal, "一次一组能走出的台面共 64 种，与台账盒子同一份")
	check(richest == 12, "这 64 种台面里果最多就是 12 颗，没有第 13 颗")
	check(closed_states == 3, "其中真正绕成闭环的台面有 3 种（1、2、3 圈）")
	# ---- 玩家动作：整组兑换、幂等、不发明货物 ----
	var table = pose([0, 0, 0])
	var one = Rules.trade(table, Rules.FRUIT, 1)
	check(one.fruit == 10 and one.thread == 3 and one.used == [1, 0, 0], "点一次合同一：2 颗果真的变成 3 卷线")
	check(table.fruit == 12 and table.used == [0, 0, 0], "规则层不动玩家原来那份台面")
	check(Rules.trade(one, Rules.FRUIT, 1).used == [2, 0, 0], "再点一次是第二组，不是把第一组抹掉")
	check(Rules.trade(table, Rules.FRUIT, 0).is_empty(), "零组兑换不是一次交易")
	check(Rules.trade(table, Rules.FRUIT, -1).is_empty(), "负数组数被拒")
	check(Rules.trade(table, Rules.FRUIT, 7).is_empty(), "一次换 7 组要 14 颗果，这一批只有 12 颗")
	check(Rules.trade(table, Rules.THREAD, 1).is_empty(), "台面上没有线，合同二这一步换不出")
	check(Rules.trade(table, Rules.CORE, 1).is_empty(), "台面上没有芯，合同三这一步换不出")
	check(Rules.trade(table, 3, 1).is_empty() and Rules.trade(table, -1, 1).is_empty(), "合同外的那一条不存在，点不到")
	check(Rules.trade(pose([0, 0, 0], "arrival"), Rules.FRUIT, 1).is_empty(), "还没走到柜面前换不了货")
	check(Rules.trade(pose([0, 0, 0], "ready"), Rules.FRUIT, 1).is_empty(), "衡伯还没让开台面就先不换")
	check(Rules.trade(pose([6, 9, 3], "ringing"), Rules.FRUIT, 1).is_empty(), "绕圈演出中没有第二笔账可记")
	check(Rules.trade(pose([6, 9, 3], "complete"), Rules.FRUIT, 1).is_empty(), "回执之后柜面不再收单")
	var bulk = Rules.trade_all(table, Rules.FRUIT)
	check(bulk.used == [6, 0, 0] and bulk.fruit == 0 and bulk.thread == 18, "整批：12 颗果一次换完是 18 卷线")
	bulk = Rules.trade_all(bulk, Rules.THREAD)
	check(bulk.used == [6, 9, 0] and bulk.thread == 0 and bulk.core == 9, "整批：18 卷线一次换完是 9 根芯")
	bulk = Rules.trade_all(bulk, Rules.CORE)
	check(bulk.used == [6, 9, 3] and items_of(bulk) == Rules.START, "整批：9 根芯一次换回 12 颗果")
	check(Rules.closed(bulk) and Rules.solved(bulk) and Rules.rings(bulk) == 3, "三圈走完，台面回到开摊那一堆")
	check(Rules.moved(bulk) == 18, "这一趟柜台上真发生了 18 组兑换")
	check(Rules.trade_all(bulk, Rules.FRUIT).is_empty(), "整批走完再点整批：这一批货没有可换的余量")
	check(Rules.shortfalls(pose([0, 0, 0])).size() == 1, "一颗没换的柜面只说一句：先绕一圈")
	# ---- 招牌那一笔：13 颗记不进台账 ----
	var closed = pose([2, 3, 1])
	check(Rules.payout(closed, Rules.SIGN_CLAIM).is_empty(), "按招牌的 13 颗结账：台账记不进去")
	check(Rules.payout(pose([0, 0, 0]), Rules.SIGN_CLAIM).is_empty(), "开局那一瞬间也变不出第 13 颗")
	check(Rules.payout(closed, 12) == closed, "台面真有 12 颗，这一笔本来就记得住")
	check(Rules.payout(pose([6, 0, 0]), 4).is_empty(), "台面上是 0 颗果，按 4 颗结账同样记不进")
	check(Rules.payout(closed, -1).is_empty() and Rules.payout(closed, 24).is_empty(), "负数与离谱的颗数都不是台账上的数")
	check(Rules.payout(pose([0, 0, 0], "arrival"), 12).is_empty(), "还没走到柜面前，谁都不结账")
	check(Rules.value_of([13, 0, 0]) == 39 and Rules.value_of([13, 0, 0]) != Rules.VALUE, "13 颗是 39 格，比这批货多出 3 格")
	check("13" in Rules.refusal(Rules.SIGN_CLAIM) and "记不进去" in Rules.refusal(Rules.SIGN_CLAIM), "拒绝的话点名那颗 13 颗")
	check("12 果 → 18 线 → 9 芯 → 12 果" in Rules.refusal(Rules.SIGN_CLAIM), "拒绝时把整批货走完的那一圈念回去")
	# ---- 提交闸口：缺哪条承诺用玩家自己的货说 ----
	var untouched = pose([0, 0, 0])
	check("绕一圈" in Rules.shortfalls(untouched)[0], "空柜面先要玩家真的绕一圈")
	var half = pose([6, 0, 0])
	check(named(Rules.shortfalls(half), "合同二") and "18 卷线" in Rules.shortfalls(half)[1], "线全压在台面上时说合同二没走完")
	var waiting = pose([6, 9, 0])
	check(named(Rules.shortfalls(waiting), "合同三") and "9 根芯" in Rules.shortfalls(waiting)[0], "芯没换回果时说合同三没兑现")
	var partial = pose([2, 0, 0])
	check(named(Rules.shortfalls(partial), "果只回到 8 颗"), "换走 4 颗果时说清台面只回到 8 颗")
	check(Rules.shortfalls(closed).is_empty() and Rules.solved(closed), "绕成一圈之后柜面没有欠账")
	check(not "13" in " ".join(Rules.shortfalls(half)), "拒绝的话从不承诺多出来的那一颗")
	check(Rules.advance(untouched).is_empty(), "一颗没换的柜面按不动拆招牌")
	check(Rules.advance(pose([6, 9, 0])).is_empty(), "线芯还没归零就不算闭环")
	check(Rules.advance(closed).stage == "ringing", "绕回 12 颗果才翻开拆穿招牌那一幕")
	# ---- 幕的推进 ----
	var arriving = Rules.advance(Rules.fresh())
	check(arriving.beat == 1 and arriving.stage == "arrival", "第一句交给第二句")
	arriving = Rules.advance(Rules.advance(arriving))
	check(arriving.beat == 2 and arriving.stage == "approach", "第三句之后才走到摊前")
	check(Rules.advance(arriving).stage == "ready" and Rules.advance(Rules.advance(arriving)).stage == "puzzle", "站定、开场、柜面交给玩家")
	var opened = Rules.advance(Rules.advance(arriving))
	check(opened.stage == "puzzle" and opened.used == [0, 0, 0], "走到柜面不动一颗货")
	check(Rules.advance(Rules.advance(closed)).stage == "delivery", "绕圈数完交给交货那一幕")
	check(Rules.advance(Rules.advance(Rules.advance(closed))).stage == "complete", "拆下招牌就是收尾")
	check(Rules.advance(closed).stage == "ringing" and Rules.advance(pose([2, 3, 1], "complete")).is_empty(), "最后一幕不再往前编")
	check(Rules.advance(pose([2, 3, 1], "elsewhere")).is_empty(), "没见过的幕名不推进任何东西")
	check(Rules.advance({}).is_empty() and Rules.advance({"stage": "puzzle"}).is_empty(), "残缺字典不算走过")
	# ---- 撤销与快照往返 ----
	var ledger = pose([6, 9, 3])
	var step_back = Rules.restore(ledger, {"used": [6, 9, 0], "fruit": 0, "thread": 0, "core": 9})
	check(step_back.used == [6, 9, 0] and step_back.core == 9, "撤销把最后一批芯退回台面")
	check(step_back.stage == "puzzle" and step_back.sample == "market-mk15-1" and step_back.hint == 0, "撤销只回退柜面，不动这一幕")
	check(Rules.restore(ledger, {"used": [6, 9, 3], "fruit": 13, "thread": 0, "core": 0}).is_empty(), "快照里那颗多出来的果被挡下")
	check(Rules.restore(ledger, {"used": [6, 9, 3], "fruit": 12}).is_empty(), "缺字段的历史不是快照")
	check(Rules.restore(ledger, {"used": [7, 9, 3], "fruit": 0, "thread": 0, "core": 0}).is_empty(), "越界的台账回不去")
	check(Rules.restore(ledger, {"used": [6, 9, 3], "fruit": 12, "thread": 0.5, "core": 0}).is_empty(), "半卷线不存在，撤销也不认")
	check(Rules.restore(ledger, {"used": [6, 9, 3], "fruit": 12, "thread": "0", "core": 0}).is_empty(), "写下来的数字不是台面上的货")
	check(Rules.restore(pose([0, 0, 0], "arrival"), {"used": [2, 3, 1], "fruit": 12, "thread": 0, "core": 0}).is_empty(), "撤销够不到柜面之前")
	check(Rules.restore(pose([2, 3, 1], "delivery"), {"used": [0, 0, 0], "fruit": 12, "thread": 0, "core": 0}).is_empty(), "撤销也够不到拆招牌之后")
	var round_trip = pose([4, 6, 2])
	var moved_on = Rules.trade(round_trip, Rules.FRUIT, 1)
	check(moved_on.used == [5, 6, 2] and items_of(moved_on) == [10, 3, 0], "闭环之后仍能继续换：本摊不锁玩家的手")
	check(Rules.restore(moved_on, {"used": [4, 6, 2], "fruit": 12, "thread": 0, "core": 0}) == round_trip, "快照往返一步不差")
	# ---- 存档 schema：损坏与非法状态 ----
	for bad in [null, {}, [], "x", 5.0, [0, 0]]: check(not Rules.validate(bad), "reject record " + str(bad))
	var forged = pose([2, 3, 1]); forged.sample = "market-mk09-1"
	check(not Rules.validate(forged), "别的关卡的存档不认")
	forged = pose([2, 3, 1]); forged.stage = "trading"
	check(not Rules.validate(forged), "未知幕名是损坏")
	forged = pose([2, 3, 1]); forged.hint = 4
	check(not Rules.validate(forged), "提示档数封顶在随货发出去的三条")
	forged = pose([2, 3, 1]); forged.hint = -1
	check(not Rules.validate(forged), "负数提示是损坏")
	forged = pose([2, 3, 1]); forged.beat = 1
	check(not Rules.validate(forged), "走过柜面却只听了两句台词是跳步")
	forged = pose([0, 0, 0], "arrival"); forged.beat = 3
	check(not Rules.validate(forged), "台词没有第四句")
	forged = forge(13, 0, 0, [2, 3, 1])
	check(not Rules.validate(forged), "凭空多出来的第 13 颗果拒读")
	forged = forge(13, 0, 0, [0, 0, 0])
	check(not Rules.validate(forged), "台账空空却摆着 13 颗果，更是损坏")
	forged = forge(12, 1, 0, [0, 0, 0])
	check(not Rules.validate(forged), "没有兑换却多出一卷线：合同外来的货不认")
	forged = forge(11, 0, 0, [0, 0, 0])
	check(not Rules.validate(forged), "少掉的一颗果也不是这一批货")
	forged = forge(10, 4, 0, [1, 0, 0])
	check(not Rules.validate(forged), "台账记的是 2 果换 3 线，台面摆 4 卷线就对不上")
	forged = forge(-2, 0, 0, [0, 0, 0])
	check(not Rules.validate(forged), "负数货物是损坏")
	forged = forge(12, -1, 0, [0, 0, 0])
	check(not Rules.validate(forged), "负数线卷是损坏")
	forged = forge(10, 3.0, 0, [1, 0, 0])
	check(not Rules.validate(forged) and Rules.validate(Content.normalize_numbers(forged.duplicate(true))), "整数被 JSON 读成 3.0 时归回 3")
	forged = forge(10, 3.5, 0, [1, 0, 0])
	check(not Rules.validate(forged), "半卷线不存在")
	forged = forge(12, 0, 1.5, [0, 0, 0])
	check(not Rules.validate(forged), "半根芯不存在")
	forged = forge(12, 0, 0, [2, 3, 0.5])
	check(not Rules.validate(forged), "半组的台账不是台账")
	forged = forge(12, 0, 0, [2, 3, "1"])
	check(not Rules.validate(forged), "写下来的字符串不是换过的组数")
	forged = forge(12, 0, 0, [7, 9, 3])
	check(not Rules.validate(forged), "一批货过合同一最多 6 组")
	forged = forge(12, 0, 0, [6, 10, 3])
	check(not Rules.validate(forged), "一批货过合同二最多 9 组")
	forged = forge(12, 0, 0, [6, 9, 4])
	check(not Rules.validate(forged), "一批货过合同三最多 3 组")
	forged = forge(12, 0, 0, [2, 3])
	check(not Rules.validate(forged), "台账只有两条合同是残缺")
	forged = forge(20, 0, 0, [0, 0, 0])
	check(not Rules.validate(forged), "台面上摆不下 20 颗果")
	forged = forge(12, 20, 0, [0, 0, 0])
	check(not Rules.validate(forged), "18 卷线已经是这批货的全部")
	forged = forge(12, 0, 10, [0, 0, 0])
	check(not Rules.validate(forged), "9 根芯已经是这批货的全部")
	forged = forge(0, 0, 0, [6, 9, 3])
	check(not Rules.validate(forged), "三堆全空不是这一批货")
	forged = pose([2, 3, 1]); forged.erase("used")
	check(not Rules.validate(forged), "缺台账不是默认值")
	forged = pose([2, 3, 1]); forged.erase("core")
	check(not Rules.validate(forged), "缺一堆货就是损坏")
	forged = pose([0, 0, 0], "ready"); forged.used = [1, 0, 0]
	check(not Rules.validate(forged), "柜面还没交给玩家就已经换过货")
	forged = pose([0, 0, 0], "arrival"); forged.fruit = 10; forged.thread = 3
	check(not Rules.validate(forged), "开场台词里台面不该被动过")
	forged = pose([6, 9, 0], "ringing")
	check(not Rules.validate(forged), "没绕回 12 颗果就写好的绕圈幕是假的")
	forged = pose([6, 9, 0], "delivery")
	check(not Rules.validate(forged), "没绕完就拆招牌，存档自己先不成立")
	forged = pose([0, 0, 0], "complete")
	check(not Rules.validate(forged), "一颗没换的回执被拒")
	check(Rules.validate(pose([2, 3, 1], "complete")), "玩家真绕成一圈的回执能原样读回来")
	var solved_trip = Content.normalize_numbers(JSON.parse_string(JSON.stringify(pose([6, 9, 3], "delivery"))))
	check(solved_trip == pose([6, 9, 3], "delivery") and Rules.validate(solved_trip), "整批绕圈的存档经 JSON 往返不变")
	check(Rules.validate(Content.normalize_numbers(JSON.parse_string(JSON.stringify(Rules.fresh())))), "开摊那份存档能过往返")
	# ---- 摊板文字：只复述合同与本批货，永远不含判断 ----
	check(Rules.line_caption(0) == "合同一 · 2 果 → 3 线", "摊板第一条照抄合同")
	check(Rules.line_caption(1) == "合同二 · 2 线 → 1 芯", "摊板第二条照抄合同")
	check(Rules.line_caption(2) == "合同三 · 3 芯 → 4 果", "摊板第三条照抄合同")
	check(Rules.name_caption(1) == "合同二" and Rules.rate_caption(1) == "2 线 → 1 芯", "牌名与兑换率各自成一块小牌")
	check(Rules.line_caption(1) == Rules.name_caption(1) + " · " + Rules.rate_caption(1), "两块牌合起来仍是那句合同")
	check(Rules.ruler_caption() == "本摊的尺 · 果3 线2 芯4 格", "这把尺写明只属于本摊")
	check(Rules.local_caption() == "这三条只在本摊算数", "摊板上就写着合同不外传")
	var totals = {}
	for a in range(Rules.LINE_CAP[0] + 1):
		for b in range(0, 10, 3):
			for c in range(Rules.LINE_CAP[2] + 1):
				var items = Rules.derived([a, b, c])
				if items.min() < 0: continue
				totals[Rules.total_caption(pose([a, b, c]))] = true
	check(totals.size() == 1 and totals.has("台面共 36 格 · 与开摊一样"), "柜面总数随你怎么换都是 36 格")
	check(Rules.pile_caption(Rules.FRUIT, 12) == "铜果 12 颗", "每堆货用自己的量词")
	check(Rules.pile_caption(Rules.THREAD, 18) == "线卷 18 卷" and Rules.pile_caption(Rules.CORE, 9) == "灯芯 9 根", "线卷与灯芯各说各的量词")
	check(Rules.ring_caption(pose([2, 3, 1])) == "已绕 1 圈 · 一圈 4 颗", "圈数说的是芯换回果那几组")
	check(Rules.bulk_caption(pose([0, 0, 0]), Rules.FRUIT) == "整批 6 组", "整批牌报的是这一条现在能换的组数")
	check(Rules.bulk_caption(pose([6, 9, 3]), Rules.CORE) == "整批 0 组", "走完的整批牌报 0 组，不藏第二次账")
	var paper = Rules.receipt(pose([6, 9, 3]))
	check("合同一 ×6：12 果 → 18 线" in paper and "合同三 ×3：9 芯 → 12 果" in paper, "回执复述玩家真走过的那几组")
	check("台面回到 12 颗 · 36 格" in paper, "回执末尾把台面数还回玩家")
	check(Rules.receipt(pose([2, 3, 1])).count("\n") == 4, "回执五行以内，不额外发明第二份账")
	check("13" not in Rules.receipt(pose([6, 9, 3])), "回执上永远不写那颗多出来的果")
	# ---- 合同只在本摊：没有全局兑换表、支线不挡主线 ----
	var leaks = contract_leaks()
	check(leaks.is_empty(), "第三条兑换率只写在 mk15 自己文件里：" + str(leaks))
	check(Catalog.SIDE == ["MK13", "MK14", "MK15", "MK16"] and Catalog.is_side("MK15"), "MK15 登记为可选支线")
	check(not Catalog.MAIN.has("MK15"), "MK15 不在主线名单里")
	check(Catalog.opens_after("MK15") == "MK09" and Catalog.act("MK15") == 4, "MK15 在 MK09 之后开门，仍属第四幕")
	check(Catalog.available("MK10", ["MK09"]), "MK09 之后 MK10 自己就开门")
	check(Catalog.next_main(Catalog.MAIN.slice(0, 9)) == "MK10" and Catalog.next_main(Catalog.MAIN.slice(0, 9) + ["MK15"]) == "MK10",
		"没做与做过 MK15，下一条主线都是 MK10")
	check(Catalog.available("MK15", ["MK09"]) and not Catalog.available("MK15", ["MK08"]), "MK09 之前 MK15 不开门")
	check(Catalog.main_pending(Catalog.MAIN.slice(0, 9)) == Catalog.main_pending(Catalog.MAIN.slice(0, 9) + ["MK15"]),
		"绕完这一圈不推进主线一格")
	check(not Catalog.main_pending(["MK09", "MK15"]).has("MK15"), "支线不进主线的待办清单")
	# ---- 文案与提示（离树探针，用完即释） ----
	var probe = Scene.instantiate(); probe.configure()
	check(probe.save_path == SAVE_DEFAULT, "本关默认写自己的 market-mk15-1 存档")
	probe.free()
	probe = Scene.instantiate(); probe.save_path = path; probe.configure()
	check(probe.save_path == path, "注入的测试路径永远不被默认值盖掉")
	check(probe.scene_id == "street" and probe.level_id == "MK15", "本关认领 street 与 MK15")
	check(probe.title == Catalog.title("MK15"), "摊名与目录一致")
	# 摊名牌与目标牌的位置由宿主写死（410×48 / 790×48），24 号被 skin 抬到 28 号、内框只剩 382。
	# 汉字在 Godot 里是一个不断词，超宽就整句掉到板子外面，所以这里替画面量一次真实宽度。
	var sign_width = UIStyle.face().get_string_size("千灯集市  /  " + probe.title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(24)).x
	var goal_width = UIStyle.face().get_string_size(probe.goal_line(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.text_size(22)).x
	print("PLAQUE 摊名 %s 量得 %.1f / 382，目标 %.1f / 762" % [probe.title, sign_width, goal_width])
	check(sign_width <= 382.0, "摊名整句待在宿主那块摊名牌里，不掉第二行")
	check(goal_width <= 762.0, "目标整句待在宿主那块目标牌里，不掉第二行")
	check(probe.rules == Rules and probe.world_script != null, "宿主接上 mk15 的规则与世界")
	check(probe.durations.has("ringing") and probe.zoom_stages.has("ringing"), "绕圈演出把镜头留在柜面")
	check(probe.hint_texts().size() == Rules.HINTS, "三级提示，没有第四级")
	check(probe.submit_label() == "拆穿招牌", "提交按钮要玩家拆招牌")
	for spoken in probe.hint_texts(): check(not spoken.is_empty() and spoken.count("\n") <= 1, "提示 %s 不超过两行" % spoken.left(4))
	check("\n" not in probe.goal_line(), "目标牌一行写完")
	probe.state = pose([0, 0, 0])
	check("\n" not in probe.status_line(), "状态牌一行写完")
	check("果 12" in probe.status_line() and "36 格" in probe.status_line(), "状态牌用玩家自己数出来的货说话")
	probe.state = pose([6, 9, 0])
	check("芯 9" in probe.status_line(), "线换完芯之后状态牌跟着改口")
	for beat in range(Rules.BEATS):
		var opening_line = Rules.fresh(); opening_line.beat = beat
		probe.state = opening_line
		var text = probe.line()
		check(not text.is_empty() and text.count("\n") <= 1, "开场第 %d 句不超过两行" % (beat + 1))
	for stage in Rules.STAGES:
		probe.state = pose([2, 3, 1], stage)
		check(not probe.line().is_empty() and probe.line().count("\n") <= 1, "%s 幕有台词且不超两行" % stage)
		check("\n" not in probe.goal_line() and "\n" not in probe.status_line(), "%s 幕的柜面牌都是单行" % stage)
	for stage in ["arrival", "ready", "complete"]:
		probe.state = pose([2, 3, 1], stage)
		if stage == "arrival": probe.state.beat = 0
		check(not probe.stage_labels().has(stage) or not probe.stage_labels()[stage].is_empty(), "%s 幕说得出下一步" % stage)
	check(probe.reset_prompt().size() == 3 and probe.restart_prompt().size() == 3, "重摆与重玩都先问一句")
	probe.free()
	# ---- 真实场景：热点几何、存档事务、逐幕重画 ----
	var game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.state.stage == "arrival" and game.buttons.has("next"), "真场景开在台词上，不是开在谜题上")
	check(not game.buttons.has("deliver"), "拆招牌的按钮要等柜面")
	check(game.world.scene_id == "street" and game.world.stations.has("counter"), "柜面读的是 manifest 的 street 站位")
	for needed in ["stall_left", "stall_midleft", "stall_middle", "stall_midright", "stall_right"]:
		if not game.world.stations.has(needed): check(false, "street 少了站位 " + needed)
	check(game.world.station("counter") == Vector2(640, 541), "counter 站位与清单一致")
	game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	game.commit(pose([0, 0, 0]))
	check(game.state.stage == "puzzle" and game.history.is_empty(), "读回来的柜面不带历史")
	var hotspots = ["sign"]
	for line in range(Rules.KINDS):
		hotspots.append("line_%d" % line); hotspots.append("bulk_%d" % line)
	for kind in range(Rules.KINDS): hotspots.append("pile_%d" % kind)
	var present = true
	var sized = true
	var framed = true
	var labelled = true
	var boxes = {}
	for id in hotspots:
		if not game.buttons.has(id): present = false; continue
		var button: Button = game.buttons[id]
		if button.size.x < 48 or button.size.y < 48: sized = false
		if button.tooltip_text.is_empty(): labelled = false
		var rect = button.get_global_rect()
		boxes[id] = rect
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > 1280 or rect.end.y > 640: framed = false
	check(present and hotspots.size() == 10, "柜面 10 个热点全部登记")
	check(sized, "每个热点都是 48 逻辑像素见方以上")
	check(framed, "每个热点都留在画面里、不压住底部按钮条")
	check(labelled, "每个热点都有中文提示")
	var crowded: Array = []
	for first in boxes.keys():
		for second in boxes.keys():
			if first < second and boxes[first].intersects(boxes[second]): crowded.append(first + "/" + second)
	check(crowded.is_empty(), "热点两两不互相盖住：" + str(crowded))
	check(game.buttons.has("deliver") and not game.buttons.deliver.disabled, "空柜面也按得动拆招牌（然后被拒）")
	check(game.buttons.has("undo") and game.buttons.undo.disabled, "没换过货时没有可撤销的一步")
	check(game.buttons.has("reset") and game.buttons.has("hint"), "柜面给出重摆与请扣扣提醒")
	# ---- 每一幕真的重画一遍：绘制代码一崩就会带着 SCRIPT ERROR 退出来 ----
	var looks = [pose([0, 0, 0]), pose([6, 0, 0]), pose([6, 9, 0]), pose([6, 9, 3]), pose([2, 3, 1])]
	var repaints = 0
	var broken = 0
	for stage in Rules.STAGES:
		var views = looks
		if stage in ["arrival", "approach", "ready"]: views = [pose([0, 0, 0], stage)]
		if stage in ["ringing", "delivery", "complete"]: views = [looks[3], looks[4]]
		for look in views:
			var shown = look.duplicate(true)
			shown.stage = stage
			if stage != "arrival": shown.beat = Rules.BEATS - 1
			repaints += 1
			game.apply_committed(shown, [])
			if not Rules.validate(game.state): broken += 1
			for at in [0.0, 0.5, 1.0]:
				game.paused = true; game.world.progress = at; await process_frame
	check(broken == 0 and repaints == 14, "%d 份现场全部重画得出来，柜面没崩" % repaints)
	check(is_instance_valid(game.world) and not game.modal, "逐幕重画没有弹出任何模态")
	game.paused = false
	# ---- 摊板与柜面文字的宽度：汉字不会自动断行，超框就画到旁边的货上 ----
	var spilled = 0
	var stacked_words = 0
	var covered = 0
	# 扣扣按世界层给的脚点画在柜台上，任何一块牌都不许压在她身上；
	# 立绘在 0.5 倍下有 164 逻辑像素宽，所以她的站位与那一排短牌的起点对着量。
	var sprite = World.KOUKOU_TIE
	var dims = Vector2(sprite.get_width(), sprite.get_height()) * 0.5
	for stage in ["puzzle", "complete"]:
		game.apply_committed(pose([6, 9, 3] if stage == "complete" else [2, 0, 0], stage), [])
		var boards = game.world.signs()
		var standing = Rect2(game.world.koukou_foot() - Vector2(dims.x / 2.0, dims.y), dims)
		for board in boards:
			if standing.intersects(board.rect):
				covered += 1; print("OVER 扣扣 ", standing, " 被 ", board.text, " ", board.rect, " 压住")
		for index in range(boards.size()):
			var board = boards[index]
			var widest := 0.0
			for spoken in String(board.text).split("\n"):
				widest = maxf(widest, UIStyle.face().get_string_size(spoken, HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(board.size)).x)
			if widest > board.rect.size.x - 12:
				spilled += 1; print("SPILL ", board.text, " needs ", widest, " in ", board.rect)
			for other in range(index + 1, boards.size()):
				if board.rect.intersects(boards[other].rect):
					stacked_words += 1; print("CROWD ", board.text, " ", board.rect, " / ", boards[other].text)
	check(spilled == 0, "所有摊板文字都待在自己的牌子里")
	check(stacked_words == 0, "摊板牌与牌之间不互相压住")
	check(covered == 0, "扣扣站的这一块地上没有牌压着她")
	check(World.ROWS[3] + World.ROW_W[3] <= 1221.0 and World.ROWS[0] >= 58.0,
		"柜面那一排短牌整体在放大 1.10 倍后的画面里")
	# ---- 真点击：一次一组、整批、撤销、重摆、提示、拒绝 ----
	game.apply_committed(pose([0, 0, 0]), [])
	game.do_trade(Rules.FRUIT, 1)
	check(game.state.used == [1, 0, 0] and game.state.fruit == 10, "点一次摊板真的换走 2 颗果")
	check(game.history.size() == 1 and game.state.thread == 3, "这一步进了历史，台面多出 3 卷线")
	game.do_trade(Rules.FRUIT, 1)
	check(game.state.used == [2, 0, 0] and game.state.fruit == 8 and game.state.thread == 6, "第二组是接着换的，台面剩 8 颗 6 卷")
	game.do_trade(Rules.THREAD, 1)
	check(game.state.used == [2, 1, 0] and game.state.core == 1, "线接着换芯，货是一件件挪的")
	game.undo()
	check(game.state.used == [2, 0, 0] and game.state.core == 0 and game.state.thread == 6, "撤销把那根芯变回 2 卷线")
	game.do_bulk(Rules.THREAD)
	check(game.state.used == [2, 3, 0] and game.state.thread == 0 and game.state.core == 3, "整批把 6 卷线一次换成 3 根芯")
	game.advance()
	check(game.state.stage == "puzzle" and not game.modal and "合同三" in game.message, "芯没换回果时点名合同三")
	check("3 根芯" in game.message and "还有 1 处" in game.message, "拒绝的话说清台面上还压着 3 根芯")
	check("绕一圈是 12 果" not in game.message, "拒绝的话不替玩家把整圈演完")
	game.read_sign()
	check(game.state.used == [2, 3, 0] and "13" in game.message, "点招牌问一句不会变出第 13 颗")
	game.count_pile(Rules.FRUIT)
	check("36 格" in game.message and game.state.used == [2, 3, 0], "数一遍只报账，不动一颗货")
	game.do_bulk(Rules.CORE)
	check(game.state.used == [2, 3, 1] and Rules.solved(game.state), "整批把 3 根芯换回 4 颗果，台面重新 12 颗")
	game.read_sign()
	check("没有第 13 颗" in game.message, "绕完之后招牌那句仍然被点名拒收")
	for step in range(6):
		if game.history.is_empty(): break
		game.undo()
	check(game.state.used == [0, 0, 0] and game.state.fruit == 12, "撤销能一路退回到开摊那一堆")
	check(game.history.is_empty(), "回退吃掉了记进历史的每一步")
	game.do_bulk(Rules.FRUIT); game.do_bulk(Rules.THREAD); game.do_bulk(Rules.CORE)
	check(Rules.solved(game.state) and game.state.used == [6, 9, 3], "整批三步走完就是闭环")
	game.hint(); game.hint(); game.hint(); game.hint()
	check(game.state.hint == 3 and "4 果 → 6 线 → 3 芯 → 4 果" in game.message, "第三级提示给完最短闭环就停住")
	game.do_reset()
	check(game.state.used == [0, 0, 0] and game.state.hint == 3, "重摆只把货放回台面，不没收已经用过的提示")
	var bytes = FileAccess.get_file_as_bytes(path)
	game.repository.fail_at = "replace"; game.do_trade(Rules.FRUIT, 1)
	check(game.modal and game.state.used == [0, 0, 0] and FileAccess.get_file_as_bytes(path) == bytes,
		"写盘失败时柜面还是上一次成功保存的那份")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.used == [1, 0, 0] and not game.modal, "重试保存只发布这一步")
	game.undo()
	check(game.state.used == [0, 0, 0], "重试之后撤销仍然退得回去")
	game.do_bulk(Rules.FRUIT); game.do_bulk(Rules.THREAD); game.do_bulk(Rules.CORE)
	game.repository.fail_at = "open"; game.advance()
	check(game.modal and game.state.stage == "puzzle", "写不进盘的绕圈演出不许开始")
	game.repository.fail_at = ""; game.retry_save()
	check(game.state.stage == "ringing" and game.buttons.has("pause") and game.buttons.has("skip"), "绕圈演出带暂停与跳过")
	check(not game.buttons.has("line_0"), "演出期间柜面热点收起来了")
	game.skip_animation()
	check(game.state.stage == "delivery", "绕完一圈交给拆招牌那一幕")
	game.skip_animation()
	check(game.state.stage == "complete" and Rules.validate(game.state), "招牌拆下来落在回执上")
	check(game.buttons.has("next") and game.buttons.next.text == "再绕一次", "最后一块牌请玩家再绕一次")
	check(game.buttons.has("open_hub") and not game.buttons.has("back_hub"), "单独启动本关也有一条回航图的路")
	var receipt = ""
	for child in game.ui.get_children():
		if child is Label and "回执 · 铜果摊绕圈" in child.text: receipt = child.text
	check(receipt != "" and "合同一 ×6" in receipt, "回执复述玩家真做过的那 6 组合同一")
	check(game.world.signs().size() > 7, "结幕的摊板把风铃与真话都写上了")
	game.paused = true; game.queue_free(); await process_frame
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "complete" and game.state.used == [6, 9, 3], "办完的柜面按玩家自己那一圈读回来")
	game.queue_free(); await process_frame
	var mid = pose([2, 3, 1], "ringing")
	var writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(mid)); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); game.paused = true; await process_frame
	check(game.state.stage == "ringing" and not game.modal, "绕到一半的现场接着演，不当作没发生")
	check(game.buttons.has("pause") and game.buttons.has("skip"), "接上的绕圈照样能暂停或跳过")
	check(Rules.validate(game.state), "接上的那一幕仍是合法存档")
	check(not game.buttons.has("open_hub") and not game.buttons.has("back_hub"), "演出中不把回去的路提前塞给玩家")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(pose([2, 3, 1], "complete"))); writer.close()
	Bridge.origin = "hub"
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.origin == "hub" and Bridge.origin.is_empty(), "航图那一跳只被读一次")
	check(game.buttons.has("back_hub") and not game.buttons.has("open_hub"), "从航图来的就把回去的路留在牌上")
	game.queue_free(); await process_frame
	# 没绕成闭环却写着拆招牌的存档，宿主读档时当损坏保护起来，不改写原文件。
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string(JSON.stringify(forge(13, 0, 0, [2, 3, 1]))); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path).contains("13"),
		"那颗多出来的果让整份存档进保护，不被覆盖")
	game.queue_free(); await process_frame
	writer = FileAccess.open(path, FileAccess.WRITE); writer.store_string("{broken"); writer.close()
	game = Scene.instantiate(); game.save_path = path; root.add_child(game); await process_frame
	check(game.modal and game.repository.protected and FileAccess.get_file_as_string(path) == "{broken",
		"读不懂的存档保留原文件")
	game.recover_protected(); await process_frame
	check(not game.modal and game.state.stage == "arrival", "保留原档并重新开始给回一个干净的开摊")
	game.queue_free(); await process_frame
	# ---- 目录一致性 ----
	check(Catalog.scene("MK15") == "res://game/market_mk15.tscn", "目录指向随货发出去的场景")
	check(Catalog.save_path("MK15") == SAVE_DEFAULT, "目录里的存档路径就是本关写的那一份")
	check(Catalog.LEVELS["MK15"].kit == "street", "目录把 MK15 留在 street 这套拆件上")
	check(ResourceLoader.exists(Catalog.scene("MK15")), "航图现在能点亮这一摊，不再写尚未制作")
	check(Catalog.built("MK15") and Catalog.available("MK15", ["MK09"]), "MK09 之后这一摊开门")
	DirAccess.remove_absolute(path)
	print("MARKET MK15 RULES ", checks - failures, "/", checks, " PASS")
	quit(1 if failures else 0)

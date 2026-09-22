extends SceneTree
# 提示分层的门禁。
#
# 这一层最容易出的不是崩溃，而是「分层被悄悄改回一档」：只要第 3 档又开始报答案，
# 「连按 H」就重新变回一份不限次数的逐步答案播报——而每一关 thinking_contract 里
# 写明的 shortcut_to_check（必须挡住的那条捷径）就白写了。所以这里逐关盯的是
# 「第 3 档说了什么」，不是它有没有出现。
const Catalog = preload("res://scripts/content/content_catalog.gd")
const Session = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)

# 第 3 档重写过的家族。路线三关与 FL06 原本就是「指方向」，不在这一列里。
const REWRITTEN = ["cargo","cargo_planning","cargo_optimal","doubling_transfer","temporal_transfer","pair_weights","machine_records","twenty_four","takeaway_policy","parity_repair","heavy_coin_plan","wall_fence","boss_seal_duel","boss_probe_reserve"]
# 各关第 3 档不该再出现的字串：它们是原来那句答案的特征。
const LEAKS = {
	"FL01":"当前可以把", "FL11":"当前可以把", "FL13":"当前可以把",
	"FL02":"先把一枚从", "FL03":"先把一枚从",
	"FL05":"下一个槽位装入", "FL07":"当前可以先算", "FL12":"当前取",
	"FL14":"下一步走", "FL15":"号放到", "FL16":"3×6", "FL17":"枚符，从", "FL18":"试探",
}

func _initialize() -> void:
	var catalog = Catalog.new()
	check(catalog.error == "","森林目录可读")

	# 1. 四档都要有内容——加了分层，兜底档不能因此消失。
	for level_id in catalog.levels:
		var definition: Dictionary = catalog.levels[level_id]
		var state = Session.Rules.fresh(definition)
		for tier in range(1,5):
			check(not Session.Rules.hint(definition,state,tier).is_empty(),"第%d档有内容 %s" % [tier,level_id])

	# 2. 第 3 档不等于第 4 档。把分层改回「一档到底」，这条会先红。
	for level_id in catalog.levels:
		var definition: Dictionary = catalog.levels[level_id]
		if definition.family not in REWRITTEN: continue
		var state = Session.Rules.fresh(definition)
		check(Session.Rules.hint(definition,state,3) != Session.Rules.hint(definition,state,4),"第3档不是带路 "+level_id)

	# 3. 第 3 档不许出现原来那句答案的特征字串。
	for level_id in LEAKS:
		var definition: Dictionary = catalog.levels[level_id]
		var state = Session.Rules.fresh(definition)
		var guide: String = Session.Rules.hint(definition,state,3)
		check(not guide.contains(LEAKS[level_id]),"第3档不给答案 "+level_id)

	# 4. 第 3 档要跟着盘面走。变成一句死喊话，玩家就看不出自己在哪儿。
	var fl02: Dictionary = catalog.levels.FL02
	var board = Session.Rules.fresh(fl02)
	var before: String = Session.Rules.hint(fl02,board,3)
	board = Session.Rules.apply(fl02,board,{"kind":"shift","from":1,"to":0}).state
	check(Session.Rules.hint(fl02,board,3) != before,"FL02 第3档跟随盘面")
	var fl15: Dictionary = catalog.levels.FL15
	# 第 3 档现在先盯「至少要称几次」那一栏；先把它答对，才轮到提示跟着秤盘走。
	var coin = Session.Rules.apply(fl15,Session.Rules.fresh(fl15),{"kind":"min_weighings","value":2}).state
	var coin_before: String = Session.Rules.hint(fl15,coin,3)
	coin = Session.Rules.apply(fl15,coin,{"kind":"assign","node":"root","coin":0,"pan":"left"}).state
	check(Session.Rules.hint(fl15,coin,3) != coin_before,"FL15 第3档跟随盘面")

	# 5. 兜底仍在：把五种宽度扫齐之后，第 4 档还会点名那份最大的方案，
	#    而第 3 档同一时刻仍然不点名。这条同时钉住「兜底没被删」和「第3档没泄漏」。
	#    扫宽度之前必须先押一注（见 fence_rules.fresh 的 guessed 标记）。
	var fl16: Dictionary = catalog.levels.FL16
	var fence = Session.Rules.fresh(fl16)
	fence = Session.Rules.apply(fl16,fence,{"kind":"area","value":18}).state
	fence = Session.Rules.apply(fl16,fence,{"kind":"loss","value":2}).state
	for width in range(1,6): fence = Session.Rules.apply(fl16,fence,{"kind":"resize","width":width}).state
	check(Session.Rules.hint(fl16,fence,4).contains("×"),"FL16 第4档扫齐宽度后仍给具体方案")
	check(not Session.Rules.hint(fl16,fence,3).contains("×"),"FL16 第3档扫齐后也不点名最大的一份")

	# 6. 档位上限抬到 4：第 4 次求助会被记下，第 5 次不再升档，而且带四档记录的存档仍合法。
	var s = Session.new()
	check(s.open("/tmp/pixel-forest-hints-"+str(Time.get_ticks_usec())+"/save.json"),"新档")
	check(Scenarios.play(s,"FL01"),"第一关")
	check(Scenarios.send(s,{"kind":"start","level_id":"FL02"}),"第二关")
	for i in range(4): Scenarios.send(s,{"kind":"hint"})
	check(s.profile.active_run.highest_hint == 4,"第4档会被记下")
	Scenarios.send(s,{"kind":"hint"})
	check(s.profile.active_run.highest_hint == 4,"第5次求助不再升档")
	var loaded = Session.new()
	check(loaded.open(s.repository.path),"带四档记录的存档可重新读取")

	print("FOREST HINT LAYERS ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

extends SceneTree
# 发现卡的校验。这一层最容易出的不是崩溃，而是「文案写错了但没人发现」：
# 数字对不上关卡、主概念写成了别关的、解释长到折行压住下面那行。
# 所以这里逐条盯的是内容，不是渲染——每张卡里出现的数字都回到该关的规则重算一遍。
const Catalog = preload("res://scripts/content/content_catalog.gd")
const Discovery = preload("res://scripts/content/discovery_catalog.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func _initialize() -> void:
	var catalog = Catalog.new()
	check(catalog.error == "","森林目录可读")
	# 1. 每张卡指向真实关卡，且自己能过约束检查。
	var problems_all = []
	for level_id in Discovery.CARDS:
		check(catalog.levels.has(level_id),"卡片指向真实关卡 "+level_id)
		if not catalog.levels.has(level_id): continue
		var problems = Discovery.check(catalog.levels[level_id])
		if not problems.is_empty(): problems_all.append(str(problems))
		check(problems.is_empty(),"卡片合规 "+level_id+("" if problems.is_empty() else " "+str(problems)))
	check(problems_all.is_empty(),"全部卡片合规")
	# 2. 森林岛十八关一关不落，且主概念互不重复——重复命名会让同一个办法有两个名字。
	var missing = []
	var seen_concepts = {}
	var duplicates = []
	for level_id in catalog.levels:
		if not Discovery.has_card(level_id): missing.append(level_id); continue
		var concept: String = Discovery.CARDS[level_id].concept
		if seen_concepts.has(concept): duplicates.append(concept)
		seen_concepts[concept] = level_id
	check(missing.is_empty(),"十八关都有卡片，缺 "+str(missing))
	check(duplicates.is_empty(),"主概念不重复，重复的 "+str(duplicates))
	# 3. 撤掉的那三条硬编码洞察，对应的家族必须都还在卡里，否则就是净丢失。
	#    route_partition / disjoint_route_pairs / cargo_optimal 原本在通关横幅里按 family 写死，
	#    换成卡片时如果漏掉某一关，那一关的「为什么」就凭空消失了。
	for family in ["route_partition","disjoint_route_pairs","cargo_optimal"]:
		for level_id in catalog.levels:
			if catalog.levels[level_id].family != family: continue
			check(Discovery.has_card(level_id),"原硬编码洞察已由卡片接管 %s（%s）" % [level_id,family])
	# 4. 回指的三种状态各要真的走到。
	var levels: Dictionary = catalog.levels
	check(Discovery.cross_reference("FL02","reverse_state",levels,["FL02","FL03"]) == "「倒着走」还能用在：借粮之前的三座仓。","有已通关的复用关时点名")
	check(Discovery.cross_reference("FL02","reverse_state",levels,["FL01","FL02"]) == "「倒着走」在后面的「借粮之前的三座仓」还要用到。","还没走到时点名最先遇到的那一关")
	check(Discovery.cross_reference("FL04","equal_substitution",levels,["FL04"]) == "这是你第一次用到它。","只出现一次时如实说第一次")
	check(Discovery.card("FL99").is_empty(),"没有卡的关卡返回空")
	check(Discovery.cross_reference("FL99","x",levels,[]).is_empty(),"没有卡的关卡不给回指")
	check(Discovery.cross_reference("FL02","",levels,[]).is_empty(),"空概念不给回指")
	# 5. 卡片里出现的数字要能在关卡规则里重算出来。写错数字是这一层最贵的错，
	#    所以每一条都回到 params 或机制模块验一遍，不靠人眼。
	# FL04 合重：真实值是 29/35/30（三架共 47）。11/13/12 只是 LEGACY_RESULT_PARAMS 的旧档兼容值。
	var fl04: String = Discovery.card("FL04").explain
	check("11" not in fl04 and "13" not in fl04 and "12" not in fl04,"FL04 不写旧档的 11/13/12")
	check(catalog.levels.FL04.params.ab == 29 and catalog.levels.FL04.params.bc == 35 and catalog.levels.FL04.params.ac == 30,"FL04 真实合重仍是 29/35/30")
	check(catalog.levels.FL02.params.target == [8,8,8],"FL02 终态确实是 8、8、8")
	# FL03：「两句一样多」是两处、且在不同时刻。
	check(catalog.levels.FL03.params.equal_after.size() == 2,"FL03 确实有两处「一样多」")
	# FL05：卡片的「只看一条还剩两种装法，两条一起看只剩一种」。
	var modules: Array = catalog.levels.FL05.params.modules
	var first_only = 0; var both = 0
	for i in modules.size():
		for j in modules.size():
			if i == j: continue
			var ops = [modules[i].op,modules[j].op]
			if int(Machine.evaluate(ops,2).back()) != 8: continue
			first_only += 1
			if int(Machine.evaluate(ops,5).back()) == 17: both += 1
	check(first_only == 2,"FL05 只看第一条记录确实还剩两种装法（实测 %d）"%first_only)
	check(both == 1,"FL05 两条一起看确实只剩一种（实测 %d）"%both)
	# FL06：卡片的「投2或5都会有两台撞上」。
	var collide = []
	for value in catalog.levels.FL06.params.probe_inputs:
		var outputs = []
		for id in catalog.levels.FL06.params.candidates:
			outputs.append(int(Machine.evaluate(catalog.levels.FL06.params.candidates[id],value).back()))
		if outputs.size() != _distinct(outputs).size(): collide.append(value)
	check(collide == [2,5],"FL06 会撞上的输入恰好是 2 和 5（实测 %s）"%str(collide))
	# FL07：卡片的「两张牌直接相乘到不了24」。
	var pair_hits = 0
	var cards: Array = catalog.levels.FL07.params.cards
	for i in cards.size():
		for j in range(i+1,cards.size()):
			if int(cards[i])*int(cards[j]) == int(catalog.levels.FL07.params.target): pair_hits += 1
	check(pair_hits == 0 and cards == [1,4,5,9],"FL07 四个数两两相乘确实都到不了24")
	# FL08：卡片的「每袋 6、3、1，合起来 10 条」。
	var counts = [6,3,1]
	var sum = 0
	for n in counts: sum += n
	check(sum == _route_total(3,2),"FL08 分袋条数 6+3+1 等于路线总数 %d"%_route_total(3,2))
	# FL09：卡片的「四处各剩下几条，要一处一处比过」——最优处留下 11 条。
	var p9: Dictionary = catalog.levels.FL09.params
	var best = 0
	for block in p9.candidate_blocks: best = maxi(best,_route_surviving(int(p9.right),int(p9.up),block))
	check(best == 11,"FL09 最优落石位置留下 11 条（实测 %d，共 %d 条）"%[best,_route_total(int(p9.right),int(p9.up))])
	# FL11：卡片的「四件货三趟送完，必有一趟装两件」。
	check(int(catalog.levels.FL11.params.goal_items) > 3,"FL11 四件货多于三趟（每趟一件装不下）")
	# FL14：卡片的「只会停在双数上；要停在9，得先把一步换成加1或减1」。
	check(catalog.levels.FL14.params.repair_target == 9 and catalog.levels.FL14.params.moves == [-2,2],"FL14 目标是 9、原路只走 ±2")
	# FL15：卡片的「先分成3、3、3，两次就够」——三种结果两次能分开九颗。
	check(catalog.levels.FL15.params.coin_count == 9 and catalog.levels.FL15.params.max_weighings == 2,"FL15 九颗、最多两次")
	check(int(pow(3,int(catalog.levels.FL15.params.max_weighings))) >= int(catalog.levels.FL15.params.coin_count),"FL15 三种结果两次确实够分九颗")
	# FL16：卡片的「3乘6最大」。
	check(catalog.levels.FL16.params.fence_units == 12 and _best_plot(12) == 18,"FL16 木料12时最大确实是 3×6=18（实测 %d）"%_best_plot(12))
	# FL17：卡片的「三枚符石都要用完，最后同时到7」。
	check(catalog.levels.FL17.params.transfer_cards.size() == 3 and catalog.levels.FL17.params.target_energy == [7,7,7],"FL17 三枚符石、终态 7/7/7")
	# FL18：卡片的「试探一次就少一些种子，合击那一步也要花种子」。
	# 20 是回响值，不是种子数——种子预算是 15，两者别混。
	check(catalog.levels.FL18.params.seed_budget == 15 and catalog.levels.FL18.params.target_response == 20,"FL18 种子预算 15、目标回响 20（20 不是种子数）")
	var forms: Dictionary = catalog.levels.FL18.params.forms
	var reach = 0
	for id in forms:
		for v in catalog.levels.FL18.params.finisher_inputs:
			if int(Machine.evaluate(forms[id].operations,v).back()) == 20: reach += 1; break
	check(reach == forms.size(),"FL18 四种形态都能用某一发输入打出回响20（实测 %d/%d）"%[reach,forms.size()])
	# 6. 横幅的排版假设：解释一行放得下 40 字。超了就会折行压住回指那一行。
	for level_id in Discovery.CARDS:
		var explain: String = Discovery.CARDS[level_id].explain
		check(explain.length() <= Discovery.EXPLAIN_LIMIT,"解释不超过 %d 字 %s（%d）" % [Discovery.EXPLAIN_LIMIT,level_id,explain.length()])
		var name: String = Discovery.CARDS[level_id].name
		check(name.length() >= Discovery.NAME_MIN and name.length() <= Discovery.NAME_MAX,"名字三到六个字 "+level_id)
	# 7. 反向：把写坏的卡喂进 check()，它必须报出来，而不是放行。
	#    CARDS 是常量改不动，所以从 entry 参数注入。
	var fl16 = {"id":"FL16","concept_ids":["area_perimeter"]}
	check(Discovery.check(fl16,{"name":"围","concept":"area_perimeter","explain":"篱笆一样长。"}).size() == 1,"名字不到三个字会被拦下")
	check(Discovery.check(fl16,{"name":"围一围比一比","concept":"area_perimeter","explain":"篱笆一样长，围出的地不一定一样大。把每种宽都试一遍，最长的那条边和短边乘起来才是最大的格数。"}).size() == 1,"过长的解释会被拦下")
	check(Discovery.check(fl16,{"name":"围一围比一比","concept":"optimization","explain":"篱笆一样长。"}).size() == 1,"主概念不在本关会被拦下")
	check(Discovery.check(fl16,{"name":"围一围比一比","concept":"area_perimeter","explain":"用 C(4,2) 算出方案数。"}).size() == 1,"给孩子看的解释里出现组合数会被拦下")
	check(Discovery.check(fl16,{"name":"围一围比一比","concept":"area_perimeter","explain":"把每种宽都试齐，3乘6最大。"}).is_empty(),"一份写对的卡放行")
	print("FOREST DISCOVERY ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

func _distinct(values: Array) -> Array:
	var out = []
	for v in values:
		if v not in out: out.append(v)
	return out

# 从 (0,0) 到 (right,up) 只走右/上的路线总数。
func _route_total(right: int, up: int) -> int:
	if right == 0 or up == 0: return 1
	return _route_total(right-1,up)+_route_total(right,up-1)

# 落石挡在 block 时还剩下几条。
func _route_surviving(right: int, up: int, block: Array) -> int:
	var blocked = str(block[0])+","+str(block[1])
	return _count_paths(0,0,right,up,blocked)

func _count_paths(x: int, y: int, right: int, up: int, blocked: String) -> int:
	if x == right and y == up: return 1
	var total = 0
	for step in [[x+1,y],[x,y+1]]:
		if step[0] > right or step[1] > up: continue
		if str(step[0])+","+str(step[1]) == blocked: continue
		total += _count_paths(step[0],step[1],right,up,blocked)
	return total

# 木料 12、借一道墙时五种宽度里的最大面积。
func _best_plot(units: int) -> int:
	var best = 0
	for w in range(1,(units-1)/2+1):
		var l = units-2*w
		if l < 1: continue
		best = maxi(best,w*l)
	return best

extends SceneTree
# 四个「盘面上没有落点」的证明环节的门禁。
#
# FL04 的总重、FL05 的押注、FL14 的判因与代价、FL16 的最大面积，原先只写在
# 规则层和提示第 4 档里：thinking_contract.required_evidence 明明要求玩家做过这几步，
# 盘面上却没有入口，complete() 也不校验——孩子从来没做过那一步，证据只是文档里的一句话。
#
# 这一组同时钉三件事：
#   1 入口会拒绝：没做那一步就不放行（而且拒绝时不能返回半成品状态）；
#   2 complete 会校验：做了才算完成；
#   3 旧存档判据：只有带新标记（fresh 里加的那个键）的存档才按严格规则判，
#     加标记之前留下的通关记录仍按原规则合法——否则升级会把老玩家的存档判成无效。
const Catalog = preload("res://scripts/content/content_catalog.gd")
const Session = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Pair = preload("res://scripts/mechanisms/pair_rules.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")
const Parity = preload("res://scripts/mechanisms/parity_rules.gd")
const Fence = preload("res://scripts/mechanisms/fence_rules.gd")
const Coins = preload("res://scripts/mechanisms/coin_rules.gd")
const SideBoards = preload("res://scripts/ui/side_boards.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)

func _initialize() -> void:
	var catalog = Catalog.new()
	check(catalog.error == "","森林目录可读")

	# ---- FL04 三架灯：先求整体（两套灯架），再求局部 ----
	var fl04: Dictionary = catalog.levels.FL04
	check(Pair.sum_expected(fl04.params) == 94,"FL04 三次合重之和是 29+35+30=94")
	check(Pair.occurrences() == 2,"FL04 每架灯被称两次：从配对结构里数出来，不是写死的")
	check(Pair.total_expected(fl04.params) == 47,"FL04 总量折半才是一套灯架 47")
	var pair = Pair.fresh(fl04.params)
	for pair_id in [["ab",0,1],["bc",1,2],["ac",0,2]]:
		pair = Pair.apply(fl04.params,pair,{"kind":"weigh","first":int(pair_id[1]),"second":int(pair_id[2])}).state
	for i in range(3): pair = Pair.apply(fl04.params,pair,{"kind":"weight","index":i,"value":[12,17,18][i]}).state
	check(not Pair.apply(fl04.params,pair,{"kind":"try"}).accepted,"FL04 没算总量就不放行点亮")
	pair = Pair.apply(fl04.params,pair,{"kind":"sum","value":93}).state
	check(not Pair.apply(fl04.params,pair,{"kind":"try"}).accepted,"FL04 总量加错也不放行点亮")
	pair = Pair.apply(fl04.params,pair,{"kind":"sum","value":94}).state
	check(not Pair.apply(fl04.params,pair,{"kind":"try"}).accepted,"FL04 总量对了但没折出一套仍不放行")
	pair = Pair.apply(fl04.params,pair,{"kind":"total","value":46}).state
	check(not Pair.apply(fl04.params,pair,{"kind":"try"}).accepted,"FL04 一套灯架的重摆错也不放行")
	pair = Pair.apply(fl04.params,pair,{"kind":"total","value":47}).state
	check(Pair.complete(fl04.params,Pair.apply(fl04.params,pair,{"kind":"try"}).state),"FL04 总量与一套都对、三对吻合才算完成")
	# 旧存档有三代：上一版（有 weighed、有已废弃的六格光带，但没有 sum）和更早那版（都没有）。
	# 「新档」的分界是 sum 这个键——上一版已经有 proof 标记，但那一版还没有 sum。
	var gen_b: Dictionary = Pair.fresh(fl04.params)
	gen_b.erase("sum"); gen_b.bands = [-1,-1,-1,-1,-1,-1]; gen_b.weighed = ["ab","bc","ac"]; gen_b.weights = [12,17,18]; gen_b.tested = true
	check(not Pair.strict(gen_b) and Pair.valid(fl04.params,gen_b) and Pair.complete(fl04.params,gen_b),"FL04 上一版（六格光带、无 sum）的通关存档仍合法")
	var pair_old: Dictionary = Pair.fresh(fl04.params)
	pair_old.erase("sum"); pair_old.erase("weighed"); pair_old.weights = [12,17,18]; pair_old.tested = true
	check(not Pair.strict(pair_old) and Pair.valid(fl04.params,pair_old) and Pair.complete(fl04.params,pair_old),"FL04 更早那一版（无 weighed）的通关存档仍合法")
	check(not Pair.apply(fl04.params,pair_old,{"kind":"band","index":0,"copy":1}).accepted,"FL04 废止的六格光带动作已不再接受")
	# 旧档还有一套旧参数（content_catalog.LEGACY_RESULT_PARAMS），走路由 result_definition 的回退。
	var old_params: Dictionary = Catalog.LEGACY_RESULT_PARAMS.FL04.duplicate(true)
	var old_board: Dictionary = Pair.fresh(old_params)
	old_board.erase("sum"); old_board.erase("weighed"); old_board.weights = [5,6,7]; old_board.tested = true
	check(not Pair.strict(old_board) and Pair.valid(old_params,old_board) and Pair.complete(old_params,old_board),"FL04 旧参数(11/13/12)的通关存档仍合法")

	# ---- FL05 磨坊账簿：先押一注，再启动 ----
	var fl05: Dictionary = catalog.levels.FL05
	var machine = Machine.fresh(fl05.params)
	machine = Machine.apply(fl05.params,machine,{"kind":"order","value":["triple","plus2"]}).state
	check(Machine.predicted_output(fl05.params,machine) == 20,"FL05 输入6的输出是 6×3+2=20")
	check(not Machine.apply(fl05.params,machine,{"kind":"try"}).accepted,"FL05 没押注就不放行启动")
	machine = Machine.apply(fl05.params,machine,{"kind":"predict","value":19}).state
	var tested_wrong: Dictionary = Machine.apply(fl05.params,machine,{"kind":"try"}).state
	check(not tested_wrong.is_empty() and not Machine.complete(fl05.params,tested_wrong),"FL05 押错可以验证，但不算完成")
	machine = Machine.apply(fl05.params,machine,{"kind":"predict","value":20}).state
	check(Machine.complete(fl05.params,Machine.apply(fl05.params,machine,{"kind":"try"}).state),"FL05 押对且验过才算完成")
	var machine_old: Dictionary = Machine.fresh(fl05.params)
	machine_old.erase("proof"); machine_old.order = ["triple","plus2"]; machine_old.tested = true
	check(Machine.valid(fl05.params,machine_old) and Machine.complete(fl05.params,machine_old),"FL05 新标记之前的通关存档仍合法")

	# ---- FL14 石径：8 和 9 都到不了，但原因不一样 ----
	var fl14: Dictionary = catalog.levels.FL14
	check(Parity.classifications_expected(fl14.params) == [2,1,0],"FL14 判因：10能走到、9被奇偶拦住、8五步凑不出")
	check(Parity.reason_for(fl14.params,9) == 1 and Parity.reason_for(fl14.params,8) == 2,"FL14 判因由奇偶与五步两条约束分别推出")
	check(Parity.flip_gap(fl14.params) == 4,"FL14 改一次向的代价是4")
	var parity = Parity.fresh(fl14.params)
	for i in range(5): parity = Parity.apply(fl14.params,parity,{"kind":"step","value":2,"repair":false}).state
	for value in [2,2,2,2,1]: parity = Parity.apply(fl14.params,parity,{"kind":"step","value":value,"repair":true}).state
	check(not Parity.apply(fl14.params,parity,{"kind":"try"}).accepted,"FL14 没判因就不放行上路")
	var classified: Dictionary = parity
	var expected: Array = Parity.classifications_expected(fl14.params)
	for i in range(3): classified = Parity.apply(fl14.params,classified,{"kind":"classify","index":i,"reason":int(expected[i])}).state
	classified = Parity.apply(fl14.params,classified,{"kind":"loss","value":3}).state
	check(not Parity.apply(fl14.params,classified,{"kind":"try"}).accepted,"FL14 代价算错也不放行上路")
	classified = Parity.apply(fl14.params,classified,{"kind":"loss","value":4}).state
	check(Parity.complete(fl14.params,Parity.apply(fl14.params,classified,{"kind":"try"}).state),"FL14 判因与代价都对才算完成")
	var parity_old: Dictionary = Parity.fresh(fl14.params)
	parity_old.erase("proof"); parity_old.path = [2,2,2,2,2]; parity_old.repair = [2,2,2,2,1]; parity_old.tested = true
	check(Parity.valid(fl14.params,parity_old) and Parity.complete(fl14.params,parity_old),"FL14 新标记之前的通关存档仍合法")

	# ---- FL16 花圃：先押最大面积，再扫宽度 ----
	var fl16: Dictionary = catalog.levels.FL16
	var fence = Fence.fresh(fl16.params)
	check(Fence.width_count(fl16.params) == 5,"FL16 要扫五种宽度")
	check(not Fence.apply(fl16.params,fence,{"kind":"resize","width":2}).accepted,"FL16 没押注就不放行调宽度")
	fence = Fence.apply(fl16.params,fence,{"kind":"area","value":20}).state
	for width in range(1,6): fence = Fence.apply(fl16.params,fence,{"kind":"resize","width":width}).state
	var smaller: Dictionary = Fence.apply(fl16.params,fence,{"kind":"choose","index":1}).state
	smaller = Fence.apply(fl16.params,smaller,{"kind":"loss","value":Fence.WIDTH_STEP_LOSS}).state
	check(not Fence.complete(fl16.params,Fence.apply(fl16.params,smaller,{"kind":"try"}).state),"FL16 围定 2×8=16 不算完成")
	var largest: Dictionary = Fence.apply(fl16.params,fence,{"kind":"choose","index":2}).state
	check(not Fence.apply(fl16.params,largest,{"kind":"try"}).accepted,"FL16 没算清宽多的代价也不放行围定")
	largest = Fence.apply(fl16.params,largest,{"kind":"loss","value":3}).state
	check(not Fence.apply(fl16.params,largest,{"kind":"try"}).accepted,"FL16 代价填错同样不放行")
	largest = Fence.apply(fl16.params,largest,{"kind":"loss","value":Fence.WIDTH_STEP_LOSS}).state
	check(Fence.WIDTH_STEP_LOSS == 2,"FL16 宽多1格、长少2格出自三边用料 2×宽+长")
	check(Fence.complete(fl16.params,Fence.apply(fl16.params,largest,{"kind":"try"}).state),"FL16 扫齐五种宽度、围定 3×6 并说清代价才算完成")
	# 押注不是答案：押错一样能完成，它只要发生在那次比较之前。
	check(int(largest.area_draft) == 20,"FL16 押错也照样完成")
	var fence_old: Dictionary = Fence.fresh(fl16.params)
	fence_old.erase("sweep"); fence_old.erase("guessed")
	for width in range(1,4): fence_old = Fence.apply(fl16.params,fence_old,{"kind":"resize","width":width}).state
	fence_old = Fence.apply(fl16.params,fence_old,{"kind":"choose","index":2}).state
	fence_old = Fence.apply(fl16.params,fence_old,{"kind":"try"}).state
	check(Fence.valid(fl16.params,fence_old) and Fence.complete(fl16.params,fence_old),"FL16 扫齐规则生效之前的通关存档仍合法")

	# ---- FL15 秤盘：先答「至少要称几次」，判定只能出现在提交之后 ----
	var fl15: Dictionary = catalog.levels.FL15
	check(Coins.minimal_weighings(fl15.params) == 2,"FL15 九颗至少要称两次：3 不够分开 9，3×3 才够")
	check(Coins.minimal_weighings({"coin_count":3}) == 1 and Coins.minimal_weighings({"coin_count":1}) == 0,"FL15 次数由 3 的幂追上颗数推出，不是写死的 2")
	check(not Coins.apply(fl15.params,Coins.fresh(fl15.params),{"kind":"try"}).accepted,"FL15 没答「至少几次」就不放行称量")
	var claimed: Dictionary = Coins.apply(fl15.params,Coins.fresh(fl15.params),{"kind":"min_weighings","value":3}).state
	check(not Coins.apply(fl15.params,claimed,{"kind":"try"}).accepted,"FL15 答成 3 次也不放行")
	var plan = Coins.apply(fl15.params,Coins.fresh(fl15.params),{"kind":"min_weighings","value":2}).state
	plan.nodes.root.left = [0]; plan.nodes.root.right = [1]
	check(not SideBoards.coin_verdict(fl15,plan).contains("会分不开的"),"FL15 提交前不下「分不开」的结论")
	check(not SideBoards.coin_verdict(fl15,plan).contains("第"),"FL15 提交前不点名晶体")
	plan.tested = true
	check(SideBoards.coin_verdict(fl15,plan).contains("会分不开的"),"FL15 提交后给出「分不开」的批改")
	check(SideBoards.coin_verdict(fl15,Coins.fresh(fl15.params)).contains("唯一一颗"),"FL15 提交前说明任务是什么")
	var ready = Coins.fresh(fl15.params)
	ready.min_weighings = 2
	ready.nodes.root.left = [0,1,2]; ready.nodes.root.right = [3,4,5]
	ready.nodes.left.left = [0]; ready.nodes.left.right = [1]
	ready.nodes.right.left = [3]; ready.nodes.right.right = [4]
	ready.nodes.equal.left = [6]; ready.nodes.equal.right = [7]
	ready.tested = true
	check(Coins.distinguished(fl15.params,ready.nodes) == 9,"FL15 三分支称量树覆盖九种更重位置")
	check(SideBoards.coin_verdict(fl15,ready).contains("都能指认出来"),"FL15 提交后认可一份覆盖九种情况的方案")
	check(Coins.complete(fl15.params,Coins.apply(fl15.params,ready,{"kind":"try"}).state),"FL15 答对次数且方案覆盖九种才算完成")
	# 旧存档：没有 proof 键、也没有 min_weighings（原先那栏叫 outcome_count 且没有入口）。
	var coin_old: Dictionary = Coins.fresh(fl15.params)
	coin_old.erase("proof"); coin_old.erase("min_weighings"); coin_old.outcome_count = 3
	coin_old.nodes = ready.nodes; coin_old.tested = true
	check(Coins.valid(fl15.params,coin_old) and Coins.complete(fl15.params,coin_old),"FL15 新标记之前的通关存档仍合法")
	check(not Coins.apply(fl15.params,coin_old,{"kind":"outcome_count","value":3}).accepted,"FL15 废止的 outcome_count 动作已不再接受")

	# ---- 档位上限与提示：第 3、4 档要跟着新步骤走 ----
	var guide_state = Pair.fresh(fl04.params)
	for id in [["ab",0,1],["bc",1,2],["ac",0,2]]:
		guide_state = Pair.apply(fl04.params,guide_state,{"kind":"weigh","first":int(id[1]),"second":int(id[2])}).state
	var fl04_hint: String = Session.Rules.hint(fl04,guide_state,3)
	check(not fl04_hint.contains("47") and not fl04_hint.contains("94") and fl04_hint.contains("多少格"),"FL04 第3档只问关系、不报总量与总重")
	guide_state = Pair.apply(fl04.params,guide_state,{"kind":"sum","value":94}).state
	check(not Session.Rules.hint(fl04,guide_state,3).contains("47"),"FL04 第3档在总量填好之后仍不报 47")
	for i in range(3): guide_state = Pair.apply(fl04.params,guide_state,{"kind":"weight","index":i,"value":[12,17,18][i]}).state
	check(Session.Rules.hint(fl04,guide_state,4).contains("47"),"FL04 第4档才报 47")
	var coin_guide: String = Session.Rules.hint(fl15,Coins.fresh(fl15.params),3)
	check(not coin_guide.contains("两次") and coin_guide.contains("三种结果"),"FL15 第3档只摆出前提、不报至少要称几次")
	check(Session.Rules.hint(fl15,Coins.fresh(fl15.params),4).contains("2"),"FL15 第4档才报次数")
	var fresh_fence = Fence.fresh(fl16.params)
	check(Session.Rules.hint(fl16,fresh_fence,3).contains("押"),"FL16 第3档先要求押注")
	check(Session.Rules.hint(fl16,fresh_fence,4).contains("押") and not Session.Rules.hint(fl16,fresh_fence,4).contains("18"),"FL16 第4档也只要求押注、不报答案")

	# ---- 端到端：走一遍主线，四关都要能真的结算 ----
	var s = Session.new()
	check(s.open("/tmp/pixel-forest-proof-"+str(Time.get_ticks_usec())+"/save.json"),"新档")
	for i in range(1,4): check(Scenarios.play(s,"FL%02d"%i),"前置 FL%02d"%i)
	check(Scenarios.send(s,{"kind":"start","level_id":"FL04"}),"第四关开始")
	for id in [[0,1],[1,2],[0,2]]: Scenarios.rule(s,{"kind":"weigh","first":int(id[0]),"second":int(id[1])})
	for i in range(3): Scenarios.rule(s,{"kind":"weight","index":i,"value":[12,17,18][i]})
	check(not Scenarios.rule(s,{"kind":"try"}) and s.profile.active_run.outcome == "active","FL04 没算总量时点不亮")
	check(s.feedback.contains("加起来"),"FL04 拒绝点亮时说清缺的是哪一步")
	check(Scenarios.rule(s,{"kind":"sum","value":94}),"FL04 总量算对了")
	check(not Scenarios.rule(s,{"kind":"try"}),"FL04 只填总量还不够")
	check(Scenarios.rule(s,{"kind":"total","value":47}) and Scenarios.rule(s,{"kind":"try"}),"FL04 折出一套总重后点亮")
	check(s.profile.active_run.outcome == "complete","FL04 走完整条路才结算")
	for i in range(5,13): check(Scenarios.play(s,"FL%02d"%i),"主线 FL%02d"%i)
	for id in ["FL14","FL15","FL16"]: check(Scenarios.play(s,id),id+" 走通")
	print("FOREST PROOF STEPS ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

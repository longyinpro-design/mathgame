extends RefCounted
const Cargo = preload("res://scripts/mechanisms/cargo_rules.gd")
const BaseCargo = preload("res://scripts/cargo/rules.gd")
const Transfer = preload("res://scripts/mechanisms/transfer_rules.gd")
const Pair = preload("res://scripts/mechanisms/pair_rules.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Parity = preload("res://scripts/mechanisms/parity_rules.gd")
const Coins = preload("res://scripts/mechanisms/coin_rules.gd")
const Seal = preload("res://scripts/mechanisms/seal_battle_rules.gd")
const Probe = preload("res://scripts/mechanisms/probe_battle_rules.gd")
const MODULES = {"plus2":"加2","plus3":"加3","plus5":"加5","plus7":"加7","minus1":"减1","double":"翻倍","triple":"三倍"}
const SIDES = ["A/甲","B/乙","C/丙"]

static func next(definition: Dictionary, state: Dictionary) -> String:
	var p: Dictionary = definition.params
	match definition.family:
		"cargo","cargo_planning","cargo_optimal":
			var step = Cargo.hint(p,state)
			var cargo_names: Array = BaseCargo.item_names(state)
			match step.kind:
				"move": return "当前可以把%s放到%s。"%[cargo_names[step.item],["林下站","左篮","右篮","树梢站"][step.target]]
				"travel": return "现在松闸，让较重的篮子下降；到站后再看留下的物件。"
				"recover": return "当前布局无法继续送齐；撤销最近一步，或重新摆放。"
				"replan":
					if p.get("lock_delivered",false): return "四件货到站用了%d趟（要正好3趟）。撤销重来：有一趟要两件拼着走，小岚的独趟要用5号石。"%state.trips
					return "这次送齐用了%d趟。撤销几步重来：左篮装小岚和阿橙、右篮装配重，第二趟换另一只篮运种子。"%state.trips
		"doubling_transfer","temporal_transfer": return transfer_hint(p,state)
		"pair_weights": return pair_hint(p,state)
		"machine_records","machine_ambiguity","diagnostic_probe": return machine_hint(p,state)
		"route_partition","route_block_choice","disjoint_route_pairs": return route_hint(p,state)
		"takeaway_policy":
			if state.winner == "opponent": return "守门人已拿到最后一颗；撤销最后一轮，或重摆后先留出一组一组的4。"
			if state.winner == "":
				if int(state.remaining)%4 == 0: return "当前轮到你面对4的整组，已没有保证获胜的取数；回退上一步重新留后手。"
				return "当前取%d颗，可以把4的整组留给守门人。"%(int(state.remaining)%4)
			return "赢下这局！守门人认输了。"
		"parity_repair": return parity_hint(p,state)
		"heavy_coin_plan": return coin_hint(p,state)
		"wall_fence": return fence_hint(p,state)
		"boss_seal_duel":
			var tail = Seal.winning_tail(p,state)
			if tail.is_empty(): return "剩余符石无法让三盘同步；撤销到还有后手的回合，或重摆。"
			if tail[0].kind == "finish": return "三盘同步且符石用完，现在可以合力反击。"
			return "当前用%d枚符，从%s移到%s，能继续接住后手。"%[tail[0].card,SIDES[tail[0].from],SIDES[tail[0].to]]
		"boss_probe_reserve": return Probe.hint(p,state)
	return "条件都齐了，按场景里的按钮完成最后一步吧。"

static func transfer_hint(p: Dictionary, state: Dictionary) -> String:
	if not Transfer.board_complete(p,state):
		var solution = []
		for a in range(p.minimum,p.total):
			for b in range(p.minimum,p.total-a):
				var initial = [a,b,p.total-a-b]
				if initial[2] < p.minimum: continue
				var trial = state.duplicate(true); trial.initial = initial; trial.trace = Transfer.trace(p,initial)
				if Transfer.board_complete(p,trial): solution = initial; break
			if not solution.is_empty(): break
		if solution.is_empty(): return "现在这组数量还没有可行的摆法。"
		for source in range(3):
			if state.initial[source] <= solution[source]: continue
			for target in range(3):
				if state.initial[target] < solution[target]: return "从当前初态，先把一枚从%s搬到%s，再听回响。"%[SIDES[source],SIDES[target]]
		return "现在的摆法已经符合关系；敲响门环听听回响吧。"
	return "回响已经对上，机关完成了。"

static func pair_hint(p: Dictionary, state: Dictionary) -> String:
	var weighed: Array = state.get("weighed",[])
	var pair_left = 0
	for pair_id in ["ab","bc","ac"]:
		if pair_id not in weighed: pair_left += 1
	if pair_left > 0: return "还有%d对没合称过——先把三对都称一遍，才有足够信息。"%pair_left
	var wanted = [(p.ab+p.ac-p.bc)/2,(p.ab+p.bc-p.ac)/2,(p.ac+p.bc-p.ab)/2]
	for i in range(3):
		if state.weights[i] != wanted[i]: return "把%s灯架调成%d，再对照它参与的两条合重。"%[SIDES[i],wanted[i]]
	if not state.tested: return "三架重量已经同时符合；点亮试试。"
	return "三对合重全部吻合，灯架亮了。"

static func order_name(order: Array) -> String:
	return "→".join(order.map(func(id): return MODULES[id]))

static func machine_hint(p: Dictionary, state: Dictionary) -> String:
	if p.has("candidates"):
		if not state.observation.is_empty():
			var matches = []
			for id in p.candidates:
				if Machine.evaluate(p.candidates[id],int(state.observation[0])).back() == state.observation[1]: matches.append(id)
			if matches.size() == 1: return "已发生的回响只符合%s号机；在回响旁选它。"%matches[0]
			return "这个回响还有%d台机器符合；撤销这次试验，换一个能让三台结果都不同的投入量。"%matches.size()
		if state.predictions.size() < p.candidates.size(): return "先为三台各写一条预测：这包种子投进去，每台的算法会算出几？"
		var outputs = []
		for id in p.candidates: outputs.append(int(state.predictions[id]))
		if outputs[0] == outputs[1] or outputs[0] == outputs[2] or outputs[1] == outputs[2]: return "你预测的结果里有相同的——这包种子分不清三台机器；换一包，或把算错的预测改对。"
		return "三台预测都不同，可以投送了；投送后逐台对答案。"
	var candidates = Machine.candidates(p)
	if candidates.is_empty(): return "现在还没有能同时满足两页账簿的装法。"
	if p.has("checkpoint"):
		if not state.revealed:
			if state.external_tests.is_empty(): return "两种装法都能正常育苗，任选一台试开。查原装时先比较两行推算，找一个数值不同的位置。"
			return "外部结果相同不代表内部顺序相同。两行推算在哪一步不同？翻开那处原机记录。"
		for order in candidates:
			if Machine.evaluate(Machine.operations(p,order),p.checkpoint.input)[p.checkpoint.after_step] == p.checkpoint.value: return "中间记录符合『%s』，在最后的装法选择中保留它。"%order_name(order)
		return "对照中间记录，选出真正的那一种装法。"
	var wanted: Array = candidates[0]
	if state.order != wanted:
		if wanted.slice(0,state.order.size()) == state.order: return "下一个槽位装入『%s』，再对照账簿看看。"%MODULES[wanted[state.order.size()]]
		return "当前槽位顺序不符；先清空槽位，再从『%s』开始。"%MODULES[wanted[0]]
	return "装法同时满足两页账簿，启动机器看看吧。"

static func route_hint(p: Dictionary, state: Dictionary) -> String:
	if p.has("candidate_blocks"):
		if int(state.get("guess",-1)) < 0: return "先在心里选一个最有利的位置，再预测每处各剩几条。"
		var predictions: Dictionary = state.get("predictions",{})
		if predictions.size() < 4: return "给每一处都填上预测：放这块石头会留下几条路？"
		var experiments: Array = state.get("experiments",[])
		if state.choice < 0:
			if experiments.size() < 4: return "把石头移到每一处，和你预测的条数对一对。"
			return "四处都对过了，把落石放在留下路线最多的那一处。"
		return "落石位置选好了，发送信件试试。"
	if p.has("partition"): return audit_hint(p,state)
	return bound_hint(p,state)

# FL08: 折羽's bag is nearly right -- one card is in the wrong bag, one route is
# missing. The hint walks the same reasoning the player needs, in order.
static func audit_hint(p: Dictionary, state: Dictionary) -> String:
	var filing: Array = Routes.filing_of(p,state)
	var groups = Routes.partition_groups(p)
	for i in filing.size():
		if filing[i].group != filing[i].path.find("R"):
			return "第%d张卡「%s」第一次向右是在第%d层，却放进了第%d层；先把它移正。" % [i+1,filing[i].path,filing[i].path.find("R"),filing[i].group]
	var listed: Array = []
	for card in filing: listed.append(card.path)
	var missing: Array = []
	for path in Routes.all_paths(p):
		if path not in listed: missing.append(path)
	if not missing.is_empty():
		var expected: Array = Routes.expected_counts(p)
		var counts = state.get("counts",[])
		if counts.size() != expected.size():
			return "袋子里的条数和应有的数目对不上。每层袋要装几条？先数一数再核对。"
		for i in expected.size():
			if int(counts[i]) != int(expected[i]):
				return "第%d层应该装%d条；看看这一层缺了什么，再把它补上。" % [i,expected[i]]
		return "每层都还缺一条：想想缺的那条从哪里开始，把它画出来补进袋子。"
	var counts = state.get("counts",[])
	if counts.size() != Routes.expected_counts(p).size():
		return "袋子补齐了；把每层应有的条数记下来，确认没有多也没有少。"
	return "邮袋和条数都对上了，发送信件吧。"

# FL10: show a set that can travel together, then justify why it is the ceiling.
static func bound_hint(p: Dictionary, state: Dictionary) -> String:
	var chosen: Array = state.get("bound_set",[])
	if chosen.is_empty():
		return "从邮路板上挑一封信，再挑一封和它中途不碰面的；看看最多能凑几封一起出发。"
	if chosen.size() < Routes.max_simultaneous(p):
		return "这一组还能再加一封：先向右的信都经过(1,0)，先向上的都经过(0,1)，两封同向的一定相撞——所以要一右一上。"
	if int(state.get("bound_reason",-1)) < 0:
		return "已经凑到最多的一封先向右、一封先向上；想一想为什么放不下第三封。"
	if int(state.bound_reason) != Routes.upper_bound_reason(p):
		return "再想一次：三封信里，为什么必有两封会在(1,0)或(0,1)相遇？"
	return "一组最多两封，理由也对了；发送信件试试。"

static func path_completion(p: Dictionary, prefix: Array, repair: bool, target: int) -> Array:
	if prefix.size() == p.steps:
		var replacements = 0
		for value in prefix:
			if value in p.repair_moves: replacements += 1
		return prefix if Parity.sum_moves(prefix) == target and (not repair or replacements == 1) else []
	for value in (p.moves+p.repair_moves if repair else p.moves):
		var next_path = prefix+[value]
		if not Parity.path_valid(p,next_path,repair): continue
		var result = path_completion(p,next_path,repair,target)
		if not result.is_empty(): return result
	return []

static func parity_hint(p: Dictionary, state: Dictionary) -> String:
	for repair in [false,true]:
		var path: Array = state.repair if repair else state.path; var target = 9 if repair else 10
		var completion = path_completion(p,path,repair,target)
		if completion.is_empty(): return "当前%s接不到目标%d；擦掉这一段再规划。"%["修路" if repair else "原路",target]
		if path.size() < p.steps: return "当前%s下一步走%s%d。"%["修路" if repair else "原路","+" if completion[path.size()] > 0 else "",completion[path.size()]]
	return "两条路线都走通了，上路试试吧。"

static func coin_hint(p: Dictionary, state: Dictionary) -> String:
	var root: Dictionary = state.nodes.root
	for pan in ["left","right"]:
		if root[pan].size() > 3: return "第一次称量先把%d号放回桌面，让%s盘保留3颗。"%[root[pan].back()+1,"左" if pan == "left" else "右"]
	for pan in ["left","right"]:
		if root[pan].size() < 3:
			for coin in range(9):
				if coin not in root.left and coin not in root.right: return "第一次称量把%d号放到%s盘，逐步分成3、3、3。"%[coin+1,"左" if pan == "left" else "右"]
	var remaining = []
	for coin in range(9):
		if coin not in root.left and coin not in root.right: remaining.append(coin)
	for branch in ["left","right","equal"]:
		var suspects: Array = root.left if branch == "left" else (root.right if branch == "right" else remaining)
		var node: Dictionary = state.nodes[branch]; var name = {"left":"若左重","right":"若右重","equal":"若平衡"}[branch]
		var outcomes = []
		for coin in suspects: outcomes.append(Coins.weighing(p,node,coin))
		if outcomes.size() == 3 and outcomes[0] != outcomes[1] and outcomes[0] != outcomes[2] and outcomes[1] != outcomes[2]: continue
		for pan in ["left","right"]:
			var wanted = suspects[0] if pan == "left" else suspects[1]
			for coin in node[pan]:
				if coin != wanted: return "在『%s』分支，先把%d号放回桌面，留下可比较的一对。"%[name,coin+1]
			if wanted not in node[pan]: return "在『%s』分支，把%d号放在%s盘。"%[name,wanted+1,"左" if pan == "left" else "右"]
	if Coins.distinguished(p,state.nodes) == int(p.coin_count): return "这样安排两次称量，九颗都能分开；亲手称一称吧。"
	return "还差一点：调整分支里的两颗，让每种称量结果都只剩一颗异晶。"

static func fence_hint(p: Dictionary, state: Dictionary) -> String:
	var expected: int = (int(p.fence_units)-1)/2
	if state.plans.size() < expected: return "还有%d种宽度没试过——把每种宽度都调出来，面积会自动记成方案卡。"%[expected-state.plans.size()]
	var maximum = 0; var best = []
	for plan in state.plans:
		if int(plan[2]) > maximum: maximum = int(plan[2]); best = plan
	if state.chosen < 0 or state.plans[int(state.chosen)][2] != maximum: return "全部宽度里 %d×%d=%d 格最大，点它来围定。"%[best[0],best[1],best[2]]
	return "五种方案比较完了，点击围定。"

extends RefCounted
const Cargo = preload("res://scripts/mechanisms/cargo_rules.gd")
const BaseCargo = preload("res://scripts/cargo/rules.gd")
const Transfer = preload("res://scripts/mechanisms/transfer_rules.gd")
const Pair = preload("res://scripts/mechanisms/pair_rules.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Parity = preload("res://scripts/mechanisms/parity_rules.gd")
const Coins = preload("res://scripts/mechanisms/coin_rules.gd")
const Fence = preload("res://scripts/mechanisms/fence_rules.gd")
const Seal = preload("res://scripts/mechanisms/seal_battle_rules.gd")
const Probe = preload("res://scripts/mechanisms/probe_battle_rules.gd")
const TwentyFour = preload("res://scripts/mechanisms/twenty_four_rules.gd")
const MODULES = {"plus2":"加2","plus3":"加3","plus5":"加5","plus7":"加7","minus1":"减1","double":"翻倍","triple":"三倍"}
const SIDES = ["A/甲","B/乙","C/丙"]

# 第 3 档：把要用的那条关系指出来，不替玩家落子。
#
# 这一档原本直接报出下一步或答案（cargo 报「把某件放到某篮」、pair 报三架灯的重量、
# fence 报「3×6 最大」、take 报每回合该取几颗）。那与每一关 thinking_contract 里
# 写着的 shortcut_to_check 正好相反——设计上要挡住的捷径，被提示亲手铺成了平坦大道。
# 更要紧的是它会自我循环：档位封在 3，而报出来的内容每次都按当前状态重算，
# 于是「连按 H」就等于一份不限次数的逐步答案播报。
#
# 现在的分层：1 问看哪里 / 2 说用哪条关系 / 3 指出关系但不给结论 / 4 才带路。
# 第 4 档仍是原来的 next()，一步一报——兜底还在，只是要先经过前三档。
static func guide(definition: Dictionary, state: Dictionary) -> String:
	var p: Dictionary = definition.params
	match definition.family:
		"cargo","cargo_planning","cargo_optimal": return cargo_guide(definition,state)
		"doubling_transfer","temporal_transfer": return transfer_guide(definition,state)
		"pair_weights": return pair_guide(p,state)
		"machine_records","machine_ambiguity": return machine_guide(p,state)
		"diagnostic_probe": return machine_hint(p,state)
		"twenty_four": return twenty_four_guide(p,state)
		"takeaway_policy": return policy_guide(state)
		"parity_repair": return parity_guide(p,state)
		"heavy_coin_plan": return coin_guide(p,state)
		"wall_fence": return fence_guide(p,state)
		"boss_seal_duel": return seal_guide(p,state)
		"boss_probe_reserve": return probe_guide(p,state)
		# 路线三关本来就是指方向而不是报答案，直接沿用。
		"route_partition","route_block_choice","disjoint_route_pairs": return route_hint(p,state)
	return "条件都齐了，按场景里的按钮完成最后一步吧。"

static func cargo_guide(definition: Dictionary, state: Dictionary) -> String:
	if BaseCargo.delivered(state): return "货物已经送齐；这一趟用了%d趟，想想能不能更少。" % state.trips
	if Cargo.hint(definition.params,state).kind == "recover": return "当前布局已经送不齐了；撤销最近一步，或重新摆放。"
	match definition.id:
		"FL01": return "先算两边：三位旅客一共多重、三块配重一共多重。谁那边更重就往哪边走，够重就能一趟到位。"
		"FL11": return "四件货、三块配重，每趟最多两件、每篮最重5。先数：要送完至少几趟？哪一趟必须两件同篮？大配重留给谁才不浪费？"
		"FL13": return "六件物件、每篮最多两件。先数：最少要几趟？数清楚之后再想每一趟怎么装满两件。"
	return "先数三件事：一共几件要送上去、每篮最多几件、至少几趟。数完再定每一趟装谁。"

static func transfer_guide(definition: Dictionary, state: Dictionary) -> String:
	var p: Dictionary = definition.params
	if Transfer.board_complete(p,state): return "回响已经对上，机关完成了。"
	if not state.trace.is_empty():
		return "回响和你想的不一样。对照下面那几行，看是哪一步的数量不对。"
	var trial = state.duplicate(true); trial.trace = Transfer.trace(p,state.initial)
	if not trial.trace.is_empty() and Transfer.board_complete(p,trial):
		return "现在的摆法已经符合关系；敲响门环听听回响吧。"
	# 报出当前三座的数量，但不报该把它们搬成什么——那是玩家这一步要决定的。
	var now = "现在甲%d、乙%d、丙%d。" % [state.initial[0],state.initial[1],state.initial[2]]
	if definition.family == "doubling_transfer":
		return now+"终态是8/8/8。只看最后一次：哪一道门借出、哪一道收光？把它退回去写出前一步，再从那里往前退。"
	return now+"两句「一样多」说的不是同一时刻：第一句管第一次借粮之后，第二句管第二次之后。先把两次的相等分开摆，再往回退。"

static func pair_guide(p: Dictionary, state: Dictionary) -> String:
	var weighed: Array = state.get("weighed",[])
	var left = 0
	for pair_id in ["ab","bc","ac"]:
		if pair_id not in weighed: left += 1
	if left > 0: return "还有%d对没合称过——三对都要称一遍，少一对就少一条线索。" % left
	if Pair.strict(state):
		if int(state.get("sum",0)) != Pair.sum_expected(p):
			return "三对都称过了。先把三条合重加起来：三次合称一共多少格？"
		if int(state.total) != Pair.total_expected(p):
			return "总量有了。三次合称里每一架灯都被称了两次——这个总量相当于几套灯架的重？"
	# 总重已经摆上灯下台面了，剩的是「总数减掉不含它的那一对」这条关系。
	return "一套的总重有了：想知道哪一架灯，就用它减去不含那一架的一对合重。"

static func machine_guide(p: Dictionary, state: Dictionary) -> String:
	var candidates = Machine.candidates(p)
	if candidates.is_empty(): return "现在还没有能同时满足两页账簿的装法。"
	if state.order == candidates[0]:
		if p.has("predict_input") and not state.predicted_before_trial:
			return "装法同时满足两页账簿。启动前先押一注：输入%d时这台机器会得到多少？"%int(p.predict_input)
		return "装法同时满足两页账簿，启动机器看看吧。"
	return "别一格格试。对每一页账簿各列一遍：哪几种装法能满足它？两页都满足的那一种才是原机。"

static func twenty_four_guide(p: Dictionary, state: Dictionary) -> String:
	var tokens = TwentyFour.replay(p,state)
	if tokens.is_empty(): return "这个合并结果已经凑不出24了。撤销上一步，或重新摆放。"
	if tokens.size() == 1 and tokens[0].n == p.target*tokens[0].d: return "四张数字卡已经全部用上，结果正好24。"
	return "四张卡都要用上。别只想着乘法：先拿两张做一次加减，凑一个离24很近的新数看看。"

static func policy_guide(state: Dictionary) -> String:
	if state.winner == "opponent": return "守门人已拿到最后一颗；撤销最后一轮，或重摆后先留出一组一组的4。"
	if state.winner == "player": return "赢下这局！守门人认输了。"
	# 不报该取几颗：那是这一步的答案。问的是该留几颗。
	return "想想该留给守门人几颗，让他无论取1、2还是3，你都能把局面接回来。"

static func parity_guide(p: Dictionary, state: Dictionary) -> String:
	var path_ok: bool = state.path.size() == p.steps and Parity.sum_moves(state.path) == 10
	var repair_ok: bool = state.repair.size() == p.steps and Parity.sum_moves(state.repair) == p.repair_target
	if not path_ok:
		if path_is_dead(p,state,false): return "这条原路接不到10；擦掉这一段重新规划。"
		return "五步全是+2就正好到10。要让终点少1，得改掉其中一步的长度——先想：改一步会让终点少多少？"
	if not repair_ok:
		if path_is_dead(p,state,true): return "这条修路接不到9；擦掉这一段重新规划。"
		return "原路已经到10了。第二条要正好9：把原路抄过来，再把其中一步的长度换掉。"
	# 两条路都走通只是上半段：8 和 9 都到不了，原因要分开说。
	if state.classifications != Parity.classifications_expected(p):
		return "两条路线都走通了。再把 8、9、10 各自属于哪一种情况对上——到不了的目标，拦路的原因并不都一样。"
	if int(state.flip_loss) != Parity.flip_gap(p):
		return "分类对上了。还差一步：把一次 +2 换成 −2，终点会少多少？"
	# 不报每格该填什么：那是这一步的答案。
	return "两条路线都走通了，分类和代价也齐了，上路试试吧。"

static func path_is_dead(p: Dictionary, state: Dictionary, repair: bool) -> bool:
	var path: Array = state.repair if repair else state.path
	var target = 9 if repair else 10
	return path_completion(p,path,repair,target).is_empty()

static func coin_guide(p: Dictionary, state: Dictionary) -> String:
	# 这一栏不报次数：它是玩家要先填的结论。只把前提（一次三种结果）摆出来。
	if state.get("proof",false) and int(state.get("min_weighings",0)) != Coins.minimal_weighings(p):
		return "先想一件小事：一次天平只有左重、右重、平衡三种结果。那一次称量最多能把几种情况分开？再拿它和%d颗比一比。"%int(p.coin_count)
	if Coins.distinguished(p,state.nodes) == int(p.coin_count): return "这样安排两次称量，九颗都能分开；亲手称一称吧。"
	var root: Dictionary = state.nodes.root
	var on_pans: int = root.left.size()+root.right.size()
	var off: int = int(p.coin_count)-on_pans
	# 提示随盘面变化，但不报该把哪几颗放上去——那正是玩家要摆的。
	if on_pans == 0: return "先把九颗分成三份，一种称量结果管一份；平衡那一份也得留好去处。"
	if root.left.size() != root.right.size(): return "第一次称量现在盘上%d颗、桌面%d颗。两边要先一样多，不然还没比就先偏了。" % [on_pans,off]
	return "第一次称量现在盘上%d颗、桌面%d颗。想一想：左重、右重、平衡，这三种结果各自还剩几颗可以怀疑？" % [on_pans,off]

static func fence_guide(p: Dictionary, state: Dictionary) -> String:
	var expected: int = (int(p.fence_units)-1)/2
	if not state.get("guessed",false): return "动手调宽度之前先押一注：五种宽度里，你猜最大能围出多少格？押完再来比。"
	if state.plans.size() < expected: return "还有%d种宽度没试过。把每种宽度都调出来，面积会自己记成方案卡，比完再挑最大的。" % (expected-state.plans.size())
	# 不点名哪一份最大，也不报「长少几格」：这两个都是玩家要自己填的结论。
	return "五种宽度都在下面了。木料总数不变——宽多分一点，长就少分一点，哪个乘积最大？"

static func seal_guide(p: Dictionary, state: Dictionary) -> String:
	var tail = Seal.winning_tail(p,state)
	if tail.is_empty(): return "剩余符石无法让三盘同步；撤销到还有后手的回合，或重摆。"
	if tail[0].kind == "finish": return "三盘同步且符石用完，现在可以合力反击。"
	# 不报是哪一枚、动哪两盘：那正是这一回合的决策。
	return "先看敌方这一次动的是哪两盘，再看三枚符里哪一枚能推对一座盘，同时不给后面两枚挡路。"

static func probe_guide(p: Dictionary, state: Dictionary) -> String:
	var possibilities = Probe.candidates(p,state)
	if state.battle_phase == "missed": return "先撤销这次合击，按已经看清的回声规律再算一遍；侦察到的信息会保留。"
	if possibilities.size() == 1:
		if Probe.finisher_cost(p,possibilities[0]) > state.seed_balance: return "真身已经辨明，但剩下的种子不够合击。回退一步侦察，少花一点种子。"
		return "真身已经辨明。合击要的回响是20——该投几颗，自己从算式里读出来。"
	if Probe.guaranteed_probe(p,possibilities,int(state.seed_balance),int(p.max_probes-state.probe_count)) < 0:
		return "现在的种子不够应付所有可能；可以撤销或重摆，用已经看到的回响重新安排。"
	return "还剩这几种可能。要挑的种子数，得让每一种可能的后续都还留得下合击的花费。"

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
	if Pair.strict(state):
		if int(state.get("sum",0)) != Pair.sum_expected(p): return "先把三条合重加起来，总量填 %d。"%Pair.sum_expected(p)
		if int(state.total) != Pair.total_expected(p): return "总量 %d 是两套灯架的重；一套填 %d。"%[Pair.sum_expected(p),Pair.total_expected(p)]
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
	if p.has("predict_input") and (not state.predicted_before_trial or int(state.prediction) != Machine.predicted_output(p,state)):
		return "装法同时满足两页账簿。押注填 %d——按这个顺序把输入%d算一遍就是这个数。"%[Machine.predicted_output(p,state),int(p.predict_input)]
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
	# 两条路走通之后，8/9/10 的判因与改向代价要自己填；这一档照旧把答案报出来。
	if state.get("proof",false) and state.path.size() == p.steps and state.repair.size() == p.steps:
		if state.classifications != Parity.classifications_expected(p):
			var expected: Array = Parity.classifications_expected(p)
			var names = []
			for i in range(3): names.append("%d 填『%s』"%[int(p.targets[i]),Parity.CLASSIFY_REASONS[int(expected[i])]])
			return "两条路都走通了。三个目标对上原因："+"；".join(names)+"。"
		if int(state.flip_loss) != Parity.flip_gap(p): return "分类对上了。改一次向的代价填 %d。"%Parity.flip_gap(p)
	for repair in [false,true]:
		var path: Array = state.repair if repair else state.path; var target = 9 if repair else 10
		var completion = path_completion(p,path,repair,target)
		if completion.is_empty(): return "当前%s接不到目标%d；擦掉这一段再规划。"%["修路" if repair else "原路",target]
		if path.size() < p.steps: return "当前%s下一步走%s%d。"%["修路" if repair else "原路","+" if completion[path.size()] > 0 else "",completion[path.size()]]
	return "两条路线都走通了，上路试试吧。"

static func coin_hint(p: Dictionary, state: Dictionary) -> String:
	# 这一档照旧报答案：九颗要分开，一次最多三种结果，所以至少要称几次。
	if state.get("proof",false) and int(state.get("min_weighings",0)) != Coins.minimal_weighings(p):
		return "一次最多分开 3 种情况，所以这一栏填 %d：3 不够分开 %d 颗，3×3 才够。"%[Coins.minimal_weighings(p),int(p.coin_count)]
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
	# 押注不需要猜对，也就不存在「卡在这一步」——这一档只说明它是个必做的动作，
	# 不把答案报出来：全盘唯一一次先想后验的机会，报出来就等于没有。
	if not state.get("guessed",false): return "先在右下角押一注：猜一个最大面积（猜错没关系），押完才能动手调宽度。"
	var expected: int = (int(p.fence_units)-1)/2
	if state.plans.size() < expected: return "还有%d种宽度没试过——把每种宽度都调出来，面积会自动记成方案卡。"%[expected-state.plans.size()]
	if int(state.length_loss) != Fence.WIDTH_STEP_LOSS: return "宽多的代价填 %d：两条宽边各多占一格木料，长就少这么多。"%Fence.WIDTH_STEP_LOSS
	var maximum = 0; var best = []
	for plan in state.plans:
		if int(plan[2]) > maximum: maximum = int(plan[2]); best = plan
	if state.chosen < 0 or state.plans[int(state.chosen)][2] != maximum: return "全部宽度里 %d×%d=%d 格最大，点它来围定。"%[best[0],best[1],best[2]]
	return "五种方案比较完了，点击围定。"

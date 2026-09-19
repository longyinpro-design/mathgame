extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")

static func fresh(params: Dictionary) -> Dictionary:
	return {"draft":"","routes":[],"classifications":{},"choice":-1,"pairs":[],"first_route":"","tested":false,"guess":-1,"experiments":[],"predictions":{},"bag_guess":[],
		"filing":seed_filing(params),"counts":[],"bound_reason":-1,"bound_set":[]}

# 折羽 already filed every route except a deliberate pair of mistakes: one card is in
# the wrong bag and one route is missing. The audit is the puzzle now, not the copying.
static func seed_filing(params: Dictionary) -> Array:
	var groups = partition_groups(params)
	if groups.size() < 2: return []
	var filing: Array = []
	var missing: String = groups[0].back() if groups[0].size() > 1 else ""
	var misplaced: String = groups[1].back() if groups[1].size() > 0 else ""
	for key in groups.keys():
		for path in groups[key]:
			if path == missing or path == misplaced: continue
			filing.append({"path":path,"group":key})
	if misplaced != "": filing.append({"path":misplaced,"group":0})
	return filing

# Routes grouped by the height at which they first step right -- an exhaustive partition.
static func partition_groups(params: Dictionary) -> Dictionary:
	var groups: Dictionary = {}
	for path in all_paths(params):
		var key = path.find("R")
		if not groups.has(key): groups[key] = []
		groups[key].append(path)
	return groups

static func filing_of(params: Dictionary, state: Dictionary) -> Array:
	return state.get("filing",seed_filing(params))

# Every route that must appear exactly once across the bags.
static func filing_complete(params: Dictionary, state: Dictionary) -> bool:
	var filing: Array = filing_of(params,state)
	var seen: Array = []
	for card in filing:
		if not card is Dictionary or not card.has_all(["path","group"]): return false
		if not legal(params,card.path) or card.path in seen: return false
		seen.append(card.path)
		if card.group != card.path.find("R"): return false
	return seen.size() == all_paths(params).size()

static func expected_counts(params: Dictionary) -> Array:
	var groups = partition_groups(params)
	var result: Array = []
	for key in groups.keys(): result.append(groups[key].size())
	return result

static func points(path: String) -> Array:
	var result = [[0,0]]; var x = 0; var y = 0
	for step in path:
		x += 1 if step == "R" else 0; y += 1 if step == "U" else 0; result.append([x,y])
	return result

static func legal(params: Dictionary, path: Variant, partial: bool = false) -> bool:
	if not path is String or path.length() > params.right+params.up: return false
	var x = 0; var y = 0
	for step in path:
		if step not in ["R","U"]: return false
		x += 1 if step == "R" else 0; y += 1 if step == "U" else 0
		if x > params.right or y > params.up or [x,y] in params.get("avoid",[]): return false
	if partial: return true
	if x != params.right or y != params.up: return false
	for point in params.get("via",[]):
		if point not in points(path): return false
	return true

static func all_paths(params: Dictionary) -> Array:
	var result = []; _paths(params,"",result); return result

static func _paths(params: Dictionary, prefix: String, result: Array) -> void:
	if not legal(params,prefix,true): return
	if prefix.length() == params.right+params.up:
		if legal(params,prefix): result.append(prefix)
		return
	_paths(params,prefix+"R",result); _paths(params,prefix+"U",result)

static func compatible(params: Dictionary, a: String, b: String) -> bool:
	if not legal(params,a) or not legal(params,b) or a == b: return false
	var inside_a = points(a).slice(1,-1); var inside_b = points(b).slice(1,-1)
	for point in inside_a:
		if point in inside_b: return false
	return true

static func all_pairs(params: Dictionary) -> Array:
	var paths = all_paths(params); var result = []
	for i in paths.size():
		for j in range(i+1,paths.size()):
			if compatible(params,paths[i],paths[j]): result.append([paths[i],paths[j]])
	return result

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["draft","routes","classifications","choice","pairs","first_route","tested"]): return false
	if not legacy_shape(state):
		if not audit_valid(params,state): return false
	if not Numbers.integer(state.get("guess",-1),-1,3): return false
	var bag_guess = state.get("bag_guess",[])
	if not bag_guess is Array or bag_guess.size() not in [0,3]: return false
	for value in bag_guess:
		if not Numbers.integer(value,0,10): return false
	var experiments = state.get("experiments",[])
	if not experiments is Array: return false
	var seen_experiments = []
	for block in experiments:
		if not Numbers.integer(block,0,3) or block in seen_experiments: return false
		seen_experiments.append(block)
	var predictions = state.get("predictions",{})
	if not predictions is Dictionary: return false
	for block in predictions:
		if not block is String or block not in ["0","1","2","3"] or not Numbers.integer(predictions[block],0,all_paths(params).size()): return false
	if not legal(params,state.draft,true) or not state.routes is Array or not state.classifications is Dictionary or not state.pairs is Array or not state.tested is bool: return false
	if not state.first_route is String or (state.first_route != "" and not legal(params,state.first_route)): return false
	if not Numbers.integer(state.choice,-1,3): return false
	var seen = []
	for route in state.routes:
		if not route is Dictionary or not route.has_all(["path","group"]) or not legal(params,route.path) or not Numbers.integer(route.group,0,params.up) or route.path in seen: return false
		seen.append(route.path)
	seen = []
	for pair in state.pairs:
		if not pair is Dictionary or not pair.has_all(["a","b","group"]) or not legal(params,pair.a) or not legal(params,pair.b) or not pair.group is String: return false
		if not compatible(params,pair.a,pair.b) or pair.group not in [pair.a,pair.b]: return false
		var key = pair_key(pair.a,pair.b)
		if key in seen: return false
		seen.append(key)
	for block in state.classifications:
		if block not in ["0","1","2","3"] or not state.classifications[block] is Dictionary: return false
		for path in state.classifications[block]:
			if not legal(params,path) or not state.classifications[block][path] is bool: return false
	return true

# A receipt written before the redesign carries the old copy-everything evidence.
static func legacy_shape(state: Dictionary) -> bool:
	var routes = state.get("routes",[])
	var pairs = state.get("pairs",[])
	return (routes is Array and not routes.is_empty()) or (pairs is Array and not pairs.is_empty())

# The redesigned board keeps only what the player reasoned about: 折羽's filing,
# the corrections, the derived per-bag expectation and the chosen upper bound.
static func audit_valid(params: Dictionary, state: Dictionary) -> bool:
	if not state.has("filing"): return false
	if not state.filing is Array or state.filing.size() > all_paths(params).size()+1: return false
	for card in state.filing:
		if not card is Dictionary or not card.has_all(["path","group"]): return false
		if not legal(params,card.path) or not Numbers.integer(card.group,0,params.up): return false
	var counts = state.get("counts",[])
	if not counts is Array or counts.size() not in [0,params.up+1]: return false
	for value in counts:
		if not Numbers.integer(value,0,all_paths(params).size()): return false
	if not state.get("bound_set",[]) is Array: return false
	var seen = []
	for path in state.bound_set:
		if not legal(params,path) or path in seen: return false
		seen.append(path)
	if state.bound_set.size() > 4: return false
	return Numbers.integer(state.get("bound_reason",-1),-1,2)


static func pair_key(a: String, b: String) -> String:
	return a+"/"+b if a < b else b+"/"+a

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true); var feedback = "路线已画在邮路板上。"
	match action.get("kind"):
		"step":
			if action.get("direction") not in ["R","U"] or not legal(params,next.draft+action.direction,true): return {"accepted":false,"feedback":"这一步越出了邮路；只能向右或向上。"}
			next.draft += action.direction
		"erase": next.draft = next.draft.left(maxi(0,next.draft.length()-1))
		"clear": next.draft = ""
		"audit_move":
			# Correct one misfiled card: it must be a real route and land in its own bag.
			var filing: Array = filing_of(params,next)
			if not Numbers.integer(action.get("index"),0,filing.size()-1): return {"accepted":false,"feedback":"先点一张要改的邮袋卡片。"}
			var card: Dictionary = filing[int(action.index)]
			if card.group == card.path.find("R"): return {"accepted":false,"feedback":"这张卡的分袋本来就和规则一致，先找出不对的那张。"}
			card.group = card.path.find("R")
			next.filing = filing; next.tested = false
			return {"accepted":true,"state":next,"feedback":"把 %s 移回 %d 层：它在第 %d 层才第一次向右。" % [card.path,card.group,card.group]}
		"audit_add":
			var listed: Array = []
			for entry in filing_of(params,next): listed.append(entry.path)
			if not legal(params,next.draft): return {"accepted":false,"feedback":"先画出一条完整路线，再把它补进邮袋。"}
			if next.draft in listed: return {"accepted":false,"feedback":"这条路线已经在折羽的袋子里了，找出真正缺的那一条。"}
			next.filing = filing_of(params,next); next.filing.append({"path":next.draft,"group":next.draft.find("R")})
			next.draft = ""; next.tested = false
			return {"accepted":true,"state":next,"feedback":"补进 %d 层邮袋。" % int(next.filing.back().group)}
		"counts":
			if not action.get("value") is Array or action.value.size() != params.up+1: return {"accepted":false,"feedback":"三层邮袋各填一个条数。"}
			for value in action.value:
				if not Numbers.integer(value,0,all_paths(params).size()): return {"accepted":false,"feedback":"每条路线只算一次，填0到%d。"%all_paths(params).size()}
			next.counts = action.value.duplicate(); next.tested = false
			return {"accepted":true,"state":next,"feedback":"条数已记下；用好这些数字找出漏掉的那条。"}
		"bound_set":
			# FL10: choose which letters leave together (order does not matter).
			if not action.get("value") is Array or action.value.is_empty() or action.value.size() > 4: return {"accepted":false,"feedback":"一次选1至4封信。"}
			var chosen: Array = []
			for path in action.value:
				if not legal(params,path) or path in chosen: return {"accepted":false,"feedback":"只能选邮路板上已有的路线。"}
				chosen.append(path)
			for i in chosen.size():
				for j in range(i+1,chosen.size()):
					if not compatible(params,chosen[i],chosen[j]):
						var shared = []
						for point in points(chosen[i]).slice(1,-1):
							if point in points(chosen[j]).slice(1,-1): shared.append("(%d,%d)"%[point[0],point[1]])
						var at = "、".join(shared) if not shared.is_empty() else "同一个路口"
						return {"accepted":false,"feedback":"这两封信会在中途的 %s 碰面——换一封，或去掉它。"%at}
			next.bound_set = chosen; next.tested = false
			if chosen.size() > max_simultaneous(params):
				return {"accepted":true,"state":next,"feedback":"这一组确实互不碰面；但还能再放一封同行的信吗？"}
			return {"accepted":true,"state":next,"feedback":"%d封信可以同时出发，互不碰面。"%chosen.size()}
		"bound_reason":
			if not Numbers.integer(action.get("value"),0,2): return {"accepted":false,"feedback":"从三个理由里选一个。"}
			next.bound_reason = int(action.value); next.tested = false
			return {"accepted":true,"state":next,"feedback":"理由已记下；发送时核对。" if int(action.value) == upper_bound_reason(params) else "理由已记下；发送时核对。"}

		"store_route":
			if not legal(params,next.draft) or not Numbers.integer(action.get("group"),0,params.up): return {"accepted":false,"feedback":"先走到终点，再选择第一次向右的高度邮袋。"}
			for route in next.routes:
				if route.path == next.draft: return {"accepted":false,"feedback":"这条路已经记录，换一个走法。"}
			next.routes.append({"path":next.draft,"group":int(action.group)}); next.draft = ""
			if next.routes.size() == all_paths(params).size():
				var totals = [0,0,0]
				for route in next.routes: totals[int(route.group)] += 1
				feedback = "十条路线收齐：三袋分别是 %d / %d / %d，加起来正好 %d 条。" % [totals[0],totals[1],totals[2],totals[0]+totals[1]+totals[2]]
				if next.get("bag_guess",[]).size() == 3:
					feedback += "你先前猜的是 %d / %d / %d。" % [int(next.bag_guess[0]),int(next.bag_guess[1]),int(next.bag_guess[2])]
		"regroup":
			if not Numbers.integer(action.get("index"),0,next.routes.size()-1) or not Numbers.integer(action.get("group"),0,params.up): return {"accepted":false,"feedback":"选择已有路线与邮袋。"}
			next.routes[int(action.index)].group = int(action.group)
		"classify":
			if not params.has("candidate_blocks") or not Numbers.integer(action.get("block"),0,params.candidate_blocks.size()-1) or not legal(params,action.get("path")) or not action.get("through") is bool: return {"accepted":false,"feedback":"选择落石点，并判断路线是否经过。"}
			var block = str(int(action.block))
			if not next.classifications.has(block): next.classifications[block] = {}
			next.classifications[block][action.path] = action.through
		"bag_guess":
			if not params.has("partition") or not action.get("value") is Array or action.value.size() != 3: return {"accepted":false,"feedback":"三只袋子各估几条，填三个数。"}
			for value in action.value:
				if not Numbers.integer(value,0,10): return {"accepted":false,"feedback":"每条路线只算一次，估计0到10之间。"}
			next.bag_guess = action.value.duplicate()
			return {"accepted":true,"state":next,"feedback":"估计已记下；走完全部路线，看看猜得准不准。"}
		"guess":
			if not params.has("candidate_blocks") or not Numbers.integer(action.get("block"),0,params.candidate_blocks.size()-1): return {"accepted":false,"feedback":"从四个位置里选一个。"}
			next.guess = int(action.block)
			feedback = "记下了你的猜测；先把四处各留几条都预测出来，再看实际结果。"
		"predict_block":
			if not params.has("candidate_blocks") or not Numbers.integer(action.get("block"),0,params.candidate_blocks.size()-1) or not Numbers.integer(action.get("value"),0,all_paths(params).size()): return {"accepted":false,"feedback":"为每个落石位置填一个0到%d的预测条数。"%all_paths(params).size()}
			if not next.has("predictions"): next.predictions = {}
			next.predictions[str(int(action.block))] = int(action.value)
			if next.predictions.size() < params.candidate_blocks.size():
				feedback = "记下了这一处；还有%d处没预测。"%[params.candidate_blocks.size()-next.predictions.size()]
			else: feedback = "四处预测都记下了；现在把石头移到各处，逐处对答案。"
		"view_block":
			if not params.has("candidate_blocks") or not Numbers.integer(action.get("block"),0,params.candidate_blocks.size()-1): return {"accepted":false,"feedback":"从四个位置里选一个。"}
			# Saves written before predictions existed keep the free-browsing rule.
			if next.has("predictions") and next.predictions.size() < params.candidate_blocks.size():
				return {"accepted":false,"feedback":"先把四处各留几条都预测出来，再看实际结果。"}
			if not next.has("experiments"): next.experiments = []
			if int(action.block) not in next.experiments: next.experiments.append(int(action.block))
			feedback = "看到了这个位置挡住和放行的路线；换一处再看看。"
		"choose":
			if not params.has("candidate_blocks") or not Numbers.integer(action.get("block"),0,params.candidate_blocks.size()-1): return {"accepted":false,"feedback":"落石必须放在四个公开位置之一。"}
			next.choice = int(action.block)
			var survives = survivors(params,int(action.block))
			var best = 0
			for i in params.candidate_blocks.size(): best = maxi(best,survivors(params,i))
			if survives < best: feedback = "这里留下%d条；还有位置能留下更多——继续对比。"%survives
			elif next.guess != next.choice: feedback = "这里留下%d条，是最多的；和你原来猜的位置不一样，但结论对了！"%survives
			else: feedback = "这里留下%d条，是最多的；猜得准！"%survives
		"first_route":
			if not legal(params,next.draft): return {"accepted":false,"feedback":"先完成第一封信的路线。"}
			next.first_route = next.draft; next.draft = ""
		"clear_first": next.first_route = ""; next.draft = ""
		"regroup_pair":
			if not Numbers.integer(action.get("index"),0,next.pairs.size()-1): return {"accepted":false,"feedback":"选择已经记录的一组路线。"}
			var pair: Dictionary = next.pairs[int(action.index)]
			if action.get("group") not in [pair.a,pair.b]: return {"accepted":false,"feedback":"用这组中的下方路线归袋。"}
			pair.group = action.group
		"store_pair":
			if not compatible(params,next.first_route,next.draft):
				var shared = []
				for point in points(next.first_route).slice(1,-1):
					if point in points(next.draft).slice(1,-1): shared.append("(%d,%d)"%[point[0],point[1]])
				if not shared.is_empty():
					return {"accepted":false,"feedback":"两封信会在中途的 %s 碰面——改一条路，绕开它。"%("、".join(shared))}
				return {"accepted":false,"feedback":"这两封信还走不到终点，或名字相同；再检查路线。"}
			var key = pair_key(next.first_route,next.draft)
			for pair in next.pairs:
				if pair_key(pair.a,pair.b) == key: return {"accepted":false,"feedback":"交换两封信的名字还是同一组；这组已记录。"}
			var lower = next.first_route if next.first_route < next.draft else next.draft
			var stored = next.first_route
			next.pairs.append({"a":next.first_route,"b":next.draft,"group":lower}); next.draft = ""; next.first_route = ""
			var total_pairs = all_pairs(params).size()
			feedback = "收下这一对。已找到 %d/%d 组不碰面的路线。" % [next.pairs.size(),total_pairs]
			if next.pairs.size() == total_pairs: feedback += " 全部找齐了！"
		"try": next.tested = true; feedback = "信件出发了；看看有没有漏掉的路线，或者中途碰面的两封信。"
		_: return {"accepted":false,"feedback":"未知邮路操作。"}
	if action.kind != "try": next.tested = false
	return {"accepted":true,"state":next,"feedback":feedback}

# Largest number of letters that can travel at once without meeting. Every
# right-first route passes (1,0) and every up-first route passes (0,1), so two
# of the same kind always collide; one of each can be arranged to avoid the other.
static func max_simultaneous(params: Dictionary) -> int:
	var best = 0
	var paths = all_paths(params)
	for i in paths.size():
		for j in range(i+1,paths.size()):
			if compatible(params,paths[i],paths[j]): best = maxi(best,2)
	return best if best > 0 else mini(1,paths.size())

# The three reasons offered for "why not more than two letters". Only the first
# is the pigeonhole argument; the others are the usual wrong shortcuts.
const BOUND_REASONS = [
	"先向右的信都会经过(1,0)，先向上的信都会经过(0,1)；三封里必有两封同向，一定在中途相撞。",
	"路线不完全一样就不会碰面。",
	"起点只有两个方向，放不下第三封。",
]

static func upper_bound_reason(_params: Dictionary) -> int:
	return 0

# FL08 redesigned completion: the filing must be correct (every route exactly
# once, in its own bag) and the player must state the per-bag counts that expose
# the missing card -- instead of copying all ten routes by hand.
static func audit_complete(params: Dictionary, state: Dictionary) -> bool:
	if not filing_complete(params,state): return false
	var expected: Array = expected_counts(params)
	var counts = state.get("counts",[])
	if counts.size() != expected.size(): return false
	for i in expected.size():
		if int(counts[i]) != int(expected[i]): return false
	return true


static func survivors(params: Dictionary, block: int) -> int:
	var remaining = 0
	for path in all_paths(params):
		if params.candidate_blocks[block] not in points(path): remaining += 1
	return remaining

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if not state.tested: return false
	var paths = all_paths(params)
	if params.has("partition"):
		# Legacy receipts copied all 10 routes and bagged them by the first right turn.
		if legacy_shape(state):
			if state.routes.size() != paths.size(): return false
			for route in state.routes:
				if route.path.find("R") != route.group: return false
			return true
		return audit_complete(params,state)
	if params.has("candidate_blocks"):
		if state.choice < 0: return false
		# Saves written before the guess step existed have no guess field; they stay completable.
		if state.has("guess") and int(state.guess) < 0: return false
		var best = 0
		for i in params.candidate_blocks.size(): best = maxi(best,survivors(params,i))
		if survivors(params,int(state.choice)) != best: return false
		# New runs must have predicted every candidate correctly before settling.
		if state.has("predictions"):
			if state.predictions.size() != params.candidate_blocks.size(): return false
			for i in params.candidate_blocks.size():
				if int(state.predictions.get(str(i),-1)) != survivors(params,i): return false
		return true
	if legacy_shape(state):
		var required = all_pairs(params)
		if state.pairs.size() != required.size(): return false
		for pair in state.pairs:
			if not compatible(params,pair.a,pair.b): return false
		return true
	if state.get("bound_set",[]).size() != max_simultaneous(params): return false
	if not state.get("bound_reason",-1) == upper_bound_reason(params): return false
	for i in state.bound_set.size():
		for j in range(i+1,state.bound_set.size()):
			if not compatible(params,state.bound_set[i],state.bound_set[j]): return false
	return true

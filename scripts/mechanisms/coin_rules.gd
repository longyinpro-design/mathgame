extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")
const OUTCOMES = ["left","right","equal"]

static func fresh(params: Dictionary) -> Dictionary:
	var nodes = {"root":{"left":[],"right":[]}}
	for id in OUTCOMES: nodes[id] = {"left":[],"right":[],"answers":{"left":-1,"right":-1,"equal":-1}}
	# proof 标记：从这一版起，动手摆方案之前要先说清「至少称几次才够」。
	# 旧存档没有这个键（也没有 min_weighings，原先那栏叫 outcome_count 且没有入口），
	# 仍按「两称覆盖九种」判定，不会被判成无效。
	return {"nodes":nodes,"min_weighings":0,"secret_id":0,"observation":[],"tested":false,"proof":true}

# 一次天平只有 3 种结果（左重/右重/平），所以 k 次最多分开 3^k 种情况。
# 九颗要分开，最少几次？——由「3 的幂追上九」推出，不是写死的 2。
static func minimal_weighings(params: Dictionary) -> int:
	var cases = 1; var weighings = 0
	while cases < int(params.coin_count):
		cases *= 3; weighings += 1
	return weighings

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["nodes","secret_id","observation","tested"]): return false
	if not state.get("proof",false) is bool: return false
	if not state.nodes is Dictionary or state.nodes.size() != 4 or not state.nodes.has_all(["root","left","right","equal"]) or not Numbers.integer(state.secret_id,0,params.coin_count-1) or not state.observation is Array or not state.tested is bool: return false
	# min_weighings 是这一版新增的「至少要称几次」；旧档没有它就按原判据。
	if state.get("proof",false) and not Numbers.integer(state.min_weighings,0,9): return false
	for id in state.nodes:
		var node = state.nodes[id]
		if not node is Dictionary or not node.has_all(["left","right"]) or not node.left is Array or not node.right is Array: return false
		var seen = []
		for coin in node.left+node.right:
			if not Numbers.integer(coin,0,params.coin_count-1) or coin in seen: return false
			seen.append(coin)
		if id != "root":
			if not node.get("answers") is Dictionary or not node.answers.has_all(OUTCOMES) or node.answers.size() != 3: return false
			for answer in node.answers.values():
				if not Numbers.integer(answer,-1,params.coin_count-1): return false
	if not state.observation.is_empty() and state.observation != simulate(params,state.nodes,int(state.secret_id)): return false
	return true

static func weighing(params: Dictionary, node: Dictionary, heavy: int) -> String:
	var left = node.left.size()*int(params.normal_weight)+(int(params.heavy_weight)-int(params.normal_weight) if heavy in node.left else 0)
	var right = node.right.size()*int(params.normal_weight)+(int(params.heavy_weight)-int(params.normal_weight) if heavy in node.right else 0)
	return "left" if left > right else ("right" if right > left else "equal")

static func outcome_pair(params: Dictionary, nodes: Dictionary, heavy: int) -> Array:
	var first = weighing(params,nodes.root,heavy)
	var second = weighing(params,nodes[first],heavy)
	return [first,second]

static func derived_answers(params: Dictionary, nodes: Dictionary) -> Dictionary:
	# Maps each observed outcome pair to its unique heavy coin; ambiguous pairs are omitted.
	var result = {}; var ambiguous = {}
	for heavy in range(int(params.coin_count)):
		var pair = outcome_pair(params,nodes,heavy)
		var key = str(pair[0])+"/"+str(pair[1])
		if result.has(key): ambiguous[key] = true
		else: result[key] = heavy
	for key in ambiguous: result.erase(key)
	return result

static func simulate(params: Dictionary, nodes: Dictionary, heavy: int) -> Array:
	var pair = outcome_pair(params,nodes,heavy)
	var key = str(pair[0])+"/"+str(pair[1])
	return [pair[0],pair[1],derived_answers(params,nodes).get(key,-1)]

static func ambiguous_pairs(params: Dictionary, nodes: Dictionary) -> Array:
	# Coins that share the same two outcomes would be indistinguishable; report them by name.
	var buckets = {}
	for heavy in range(int(params.coin_count)):
		var pair = outcome_pair(params,nodes,heavy)
		var key = str(pair[0])+"/"+str(pair[1])
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(heavy)
	var result = []
	for key in buckets:
		if buckets[key].size() > 1: result.append(buckets[key].duplicate())
	return result

static func distinguished(params: Dictionary, nodes: Dictionary) -> int:
	# How many of the nine possibilities the two-weighing plan separates.
	var pairs = {}
	for heavy in range(int(params.coin_count)):
		var pair = outcome_pair(params,nodes,heavy)
		pairs[str(pair[0])+"/"+str(pair[1])] = true
	return pairs.size()

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match action.get("kind"):
		"assign":
			if not next.nodes.has(action.get("node")) or not Numbers.integer(action.get("coin"),0,params.coin_count-1) or action.get("pan") not in ["left","right","off"]: return {"accepted":false,"feedback":"选择一颗晶体和天平位置。"}
			var node: Dictionary = next.nodes[action.node]
			node.left.erase(int(action.coin)); node.right.erase(int(action.coin))
			if action.pan != "off": node[action.pan].append(int(action.coin))
		"answer":
			if action.get("node") not in OUTCOMES or action.get("outcome") not in OUTCOMES or not Numbers.integer(action.get("coin"),0,params.coin_count-1): return {"accepted":false,"feedback":"把称量的每一种结果连到异晶身份。"}
			next.nodes[action.node].answers[action.outcome] = int(action.coin)
		"min_weighings":
			if not Numbers.integer(action.get("value"),0,9): return {"accepted":false,"feedback":"先说说九颗至少要称几次才够。"}
			next.min_weighings = int(action.value)
		"try":
			# 没想清楚「一次最多分开几种情况」就先摆方案，等于把这一关的洞察整段跳过。
			if state.get("proof",false) and int(next.min_weighings) != minimal_weighings(params):
				return {"accepted":false,"feedback":"先回答那个问题：一次天平最多分出 3 种结果，要把 %d 种情况都分开，至少要称几次？"%int(params.coin_count)}
			next.tested = true
			var derived = derived_answers(params,next.nodes)
			for first in OUTCOMES:
				for second in OUTCOMES:
					var key = first+"/"+second
					if derived.has(key): next.nodes[first].answers[second] = derived[key]
			next.observation = simulate(params,next.nodes,int(next.secret_id))
		_: return {"accepted":false,"feedback":"未知天平操作。"}
	if action.kind != "try": next.tested = false; next.observation = []
	var feedback = "天平记录保留；称量两种结果之后还要能分出是哪一颗。"
	if action.kind == "try":
		var ambiguous = ambiguous_pairs(params,next.nodes)
		if ambiguous.is_empty(): feedback = "无论哪颗更重，两次称量后都能指认；机关接受了。"
		else:
			var names = []
			for group in ambiguous:
				var labels = []
				for coin in group: labels.append("第%d颗"%(int(coin)+1))
				names.append("、".join(labels))
			feedback = "这几颗在你的安排下会得到完全一样的结果：%s——调整分支里的晶体，让它们分开。"%("；".join(names))
	return {"accepted":true,"state":next,"feedback":feedback}

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if not state.tested: return false
	# 这一版起，方案之前的那句判断也要成立（见 fresh 的 proof 标记）。
	if state.get("proof",false) and int(state.min_weighings) != minimal_weighings(params): return false
	return distinguished(params,state.nodes) == int(params.coin_count)

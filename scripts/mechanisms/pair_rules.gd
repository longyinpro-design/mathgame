extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")
# 三次合称称的就是这三对，每对正好两架灯。
const RIGS_OF_PAIR = {"ab":["a","b"],"bc":["b","c"],"ac":["a","c"]}

static func fresh(_params: Dictionary) -> Dictionary:
	return {"weights":[1,1,1],"sum":0,"total":0,"tested":false,"weighed":[]}

# 严格判据只对新档生效，而「新档」的判据是 sum 这个键的有无——
# 上一版已经有过一个 proof 标记，但它标记的那一版还没有 sum，所以不能拿它当分界；
# 更早那版连 proof 都没有。用 sum 一处就分开了三代存档：
#   更早：没有 proof、没有 weighed、没有 sum（还有已废弃的六格光带）
#   上一版：有 proof、有 weighed、有六格光带，但没有 sum
#   现在：有 sum，没有六格光带
# 三代都按各自当时的判据走，升级不会把老玩家的通关记录判成无效。
static func strict(state: Dictionary) -> bool:
	return state.has("sum")

# 一架灯在三次合称里出现几次。三架灯的答案当然相同（每对正好两架），所以数任意一架即可。
# 这个 2 是从配对结构里数出来的，不是写死的常数——它正是「总和 ÷ 2 才是一套」的依据。
static func occurrences() -> int:
	var counted = 0
	for rigs in RIGS_OF_PAIR.values():
		if "a" in rigs: counted += 1
	return counted

# 三次合称之和 = 每架灯各被计两次 = 两套灯架（整体先于局部）。
static func sum_expected(params: Dictionary) -> int:
	return int(params.ab)+int(params.bc)+int(params.ac)

static func total_expected(params: Dictionary) -> int:
	return sum_expected(params)/occurrences()

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["weights","total","tested"]): return false
	var weighed = state.get("weighed",[])
	if not weighed is Array or weighed.size() > 3: return false
	for pair_id in weighed:
		if pair_id not in ["ab","bc","ac"]: return false
		if weighed.count(pair_id) > 1: return false
	if not state.weights is Array or state.weights.size() != 3 or not state.tested is bool: return false
	# bands 是旧版的六格光带——没有入口、也没有任何一种摆放是对的，已经废弃；
	# 旧档带着它仍然合法，所以只检查形状。
	var bands = state.get("bands",[])
	if not bands is Array or bands.size() not in [0,6]: return false
	for weight in state.weights:
		if not Numbers.integer(weight,params.weight_min,params.weight_max): return false
	for band in bands:
		if not Numbers.integer(band,-1,1): return false
	if strict(state) and not Numbers.integer(state.get("sum",0),0,120): return false
	return Numbers.integer(state.total,0,60)

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true)
	match action.get("kind"):
		"weight":
			if not Numbers.integer(action.get("index"),0,2) or not Numbers.integer(action.get("value"),params.weight_min,params.weight_max): return {"accepted":false,"feedback":"灯架重量须在范围内。"}
			next.weights[int(action.index)] = int(action.value); next.tested = false
		"weigh":
			var first = action.get("first"); var second = action.get("second")
			if not Numbers.integer(first,0,2) or not Numbers.integer(second,0,2) or first == second: return {"accepted":false,"feedback":"选两架不同的灯来合称。"}
			if not next.has("weighed"): next.weighed = []
			var pair_id = ("ab" if first+second == 1 else ("bc" if first+second == 3 else "ac"))
			var total = int(params.ab) if pair_id == "ab" else (int(params.bc) if pair_id == "bc" else int(params.ac))
			if pair_id not in next.weighed: next.weighed.append(pair_id)
			var light_name = {"ab":"A与B","bc":"B与C","ac":"A与C"}[pair_id]
			return {"accepted":true,"state":next,"feedback":"把%s架上合称台：光带卷起 %d 格，这就是它们的合重。"%[light_name,total]}
		"sum":
			if not Numbers.integer(action.get("value"),0,120): return {"accepted":false,"feedback":"请把三次合称的结果加起来。"}
			next.sum = int(action.value)
			return {"accepted":true,"state":next,"feedback":"三次合称的总量记作 %d 格。"%int(action.value)}
		"total":
			if not Numbers.integer(action.get("value"),0,60): return {"accepted":false,"feedback":"请摆出一套灯架的总重。"}
			next.total = int(action.value)
			return {"accepted":true,"state":next,"feedback":"一套灯架的总重记作 %d 格。"%int(action.value)}
		"try":
			# 两步都不放行点亮：这一步是「先求整体再求局部」的落脚点。
			# 只从提示里听到 47 而没在灯下算过，thinking_contract 的那条证据就没发生。
			if strict(next):
				if int(next.sum) != sum_expected(params):
					return {"accepted":false,"feedback":"先自己把三条合重加起来：三次合称一共多少格？"}
				if int(next.total) != total_expected(params):
					return {"accepted":false,"feedback":"三次合称一共 %d 格，而且每架灯都被称了两次——里面正好是几套灯架的重？"%sum_expected(params)}
			next.tested = true
		_: return {"accepted":false,"feedback":"未知灯架动作。"}
	return {"accepted":true,"state":next,"feedback":"三对合重都吻合，灯全亮了！" if board_complete(params,next) else "每次调整会影响两场合重；先合称几对，看看目标是多少。"}

static func board_complete(params: Dictionary, state: Dictionary) -> bool:
	var w: Array = state.weights
	return state.tested and w[0]+w[1] == params.ab and w[1]+w[2] == params.bc and w[0]+w[2] == params.ac

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if not board_complete(params,state): return false
	# Saves from before the weighing step existed have no field and stay completable.
	if state.has("weighed") and state.weighed.size() < 3: return false
	# 这一版起，总量与一套灯架的重都要先在灯下算出来（旧档没有 sum，见 strict）。
	if strict(state):
		if int(state.sum) != sum_expected(params) or int(state.total) != total_expected(params): return false
	return true

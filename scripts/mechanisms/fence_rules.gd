extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")

# 三边用料是 2×宽 + 长：宽每加 1，两条宽边各占去 1，可用的长就少 2。
# 这个数是「借一道墙」这条规则本身带来的，不是调参调出来的。
const WIDTH_STEP_LOSS = 2

static func fresh(params: Dictionary) -> Dictionary:
	# Start on the narrowest complete layout so the first option is visible immediately.
	var units = int(params.fence_units)
	# guessed 标记：这一版起要先押一个「最大面积」的猜测，才允许动手调宽度。
	# 旧存档没有这个键（sweep 与 guessed 都是这一版才有的），仍按原规则判定。
	return {"width":1,"length":units-2,"area_draft":units-2,"plans":[[1,units-2,units-2]],"chosen":-1,"length_loss":0,"tested":false,"sweep":true,"guessed":false}

static func width_count(params: Dictionary) -> int:
	return (int(params.fence_units)-1)/2

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["width","length","area_draft","plans","chosen","length_loss","tested"]): return false
	if not state.get("sweep",false) is bool: return false
	if not state.get("guessed",false) is bool: return false
	if not Numbers.integer(state.area_draft,1,144): return false
	if not Numbers.integer(state.width,1,params.fence_units) or not Numbers.integer(state.length,1,params.fence_units) or not state.plans is Array or not state.tested is bool or not Numbers.integer(state.chosen,-1,state.plans.size()-1) or not Numbers.integer(state.length_loss,0,params.fence_units): return false
	var seen = []
	for plan in state.plans:
		if not plan is Array or plan.size() != 3: return false
		if not Numbers.integer(plan[0],1,params.fence_units) or not Numbers.integer(plan[1],1,params.fence_units) or not Numbers.integer(plan[2],1,params.fence_units*params.fence_units) or plan[0] in seen: return false
		if 2*plan[0]+plan[1] != params.fence_units: return false
		seen.append(plan[0])
	return true

static func note_plan(next: Dictionary, params: Dictionary) -> void:
	# Every complete layout the player adjusts to is remembered; the area is derived, never typed.
	if 2*int(next.width)+int(next.length) != params.fence_units: return
	var w = int(next.width); var l = int(next.length)
	if not next.has("plans") or not next.plans is Array: next.plans = []
	for i in next.plans.size():
		if next.plans[i][0] == w: next.plans[i] = [w,l,w*l]; return
	next.plans.append([w,l,w*l])

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true); var feedback = "调整宽度看看效果；每种方案的面积都会记在下面。"
	match action.get("kind"):
		"resize":
			if state.get("sweep",false) and not state.get("guessed",false):
				return {"accepted":false,"feedback":"先押一注：五种宽度里，你猜最大能围出多少格？"}
			if not Numbers.integer(action.get("width"),1,(int(params.fence_units)-1)/2): return {"accepted":false,"feedback":"宽度要取正整数；两条宽边至少各占1。"}
			next.width = int(action.width); next.length = int(params.fence_units)-2*int(action.width)
			note_plan(next,params)
			return {"accepted":true,"state":next,"feedback":"宽%d、长%d：用料 %d 正好用完，面积 %d 格。"%[int(next.width),int(next.length),params.fence_units,int(next.width)*int(next.length)]}
		"area":
			if not Numbers.integer(action.get("value"),1,144): return {"accepted":false,"feedback":"用整数格记录花圃面积。"}
			next.area_draft = int(action.value); next.guessed = true
			return {"accepted":true,"state":next,"feedback":"押下了 %d 格。现在把每种宽度都调出来，比完再回头对一对。"%int(action.value)}
		"dimension":
			if state.get("sweep",false) and not state.get("guessed",false):
				return {"accepted":false,"feedback":"先押一注：五种宽度里，你猜最大能围出多少格？"}
			if action.get("side") not in ["width","length"] or not Numbers.integer(action.get("value"),1,params.fence_units): return {"accepted":false,"feedback":"边长必须是正整数。"}
			next[action.side] = int(action.value); note_plan(next,params)
		"store_plan":
			if 2*next.width+next.length != params.fence_units: return {"accepted":true,"state":next,"feedback":"两条宽加一条长共用%d单位；需要恰好用完%d单位围栏。"%[2*next.width+next.length,params.fence_units]}
			note_plan(next,params)
		"choose":
			if not Numbers.integer(action.get("index"),0,next.plans.size()-1): return {"accepted":false,"feedback":"先调整宽度，看到一份完整的方案，再选它。"}
			next.chosen = int(action.index)
			var picked: Array = next.plans[int(action.index)]
			var maximum = 0
			for plan in next.plans: maximum = maxi(maximum,int(plan[2]))
			feedback = "选中的是%d×%d=%d格%s。"%[picked[0],picked[1],picked[2],"——目前最大！" if int(picked[2]) == maximum else "；还有更大的方案，再试试别的宽度。"]
		"loss":
			if not Numbers.integer(action.get("value"),0,params.fence_units): return {"accepted":false,"feedback":"宽增加1，两条宽边都需要木料。"}
			next.length_loss = int(action.value)
			return {"accepted":true,"state":next,"feedback":"记下：宽多1格，长少%d格。"%int(action.value)}
		"try":
			if state.get("sweep",false):
				if not state.get("guessed",false): return {"accepted":false,"feedback":"先押一注：五种宽度里，你猜最大能围出多少格？"}
				# 光扫完五种宽度不算想明白「为什么」：宽多1与长少2是同一笔木料的两面。
				if int(state.length_loss) != WIDTH_STEP_LOSS: return {"accepted":false,"feedback":"还差一句话：宽多1格，两条宽边都要木料——长会少几格？"}
			next.tested = true
		_: return {"accepted":false,"feedback":"未知花圃操作。"}
	if action.kind != "try": next.tested = false
	if action.kind == "try":
		var maximum = 0
		for plan in next.plans: maximum = maxi(maximum,int(plan[2]))
		if next.plans.size() < width_count(params): feedback = "还有%d种宽度没试过；把每种宽度都调出来比一比。"%[width_count(params)-next.plans.size()]
		elif next.chosen < 0: feedback = "先选一份方案的卡片，再围起来。"
		elif next.plans[int(next.chosen)][2] != maximum: feedback = "选中的不是最大的；再看看已试过的方案面积。"
		else: feedback = "花圃围好了，这就是全部宽度里最大的方案！"
	return {"accepted":true,"state":next,"feedback":feedback}

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if not state.tested or state.chosen < 0: return false
	# Saves written before the full-sweep requirement keep the earlier comparison rule.
	if not state.get("sweep",false):
		if state.plans.size() < 3: return false
		var tried_max = 0
		for plan in state.plans: tried_max = maxi(tried_max,int(plan[2]))
		return state.plans[int(state.chosen)][2] == tried_max
	if state.plans.size() < width_count(params): return false
	# 这一版起，还要先押过一个「最大面积」的猜测、说清宽多的代价（见 fresh 的 guessed 标记）。
	if not state.get("guessed",false): return false
	if int(state.length_loss) != WIDTH_STEP_LOSS: return false
	var maximum = 0
	for plan in state.plans:
		if 2*plan[0]+plan[1] != params.fence_units or plan[2] != plan[0]*plan[1]: return false
		maximum = maxi(maximum,int(plan[2]))
	return state.plans[int(state.chosen)][2] == maximum

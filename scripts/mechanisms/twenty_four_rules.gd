extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")
const SYMBOLS = {"+":"+","-":"−","*":"×","/":"÷"}

static func fresh(_params: Dictionary) -> Dictionary:
	return {"steps":[]}

static func gcd(a: int, b: int) -> int:
	a = absi(a); b = absi(b)
	while b != 0:
		var remainder = a%b; a = b; b = remainder
	return maxi(a,1)

static func fraction(n: int, d: int) -> Array:
	if d < 0: n = -n; d = -d
	var divisor = gcd(n,d)
	return [int(n/divisor),int(d/divisor)]

static func value_text(token: Dictionary) -> String:
	return str(token.n) if token.d == 1 else "%d/%d" % [token.n,token.d]

static func initial(params: Dictionary) -> Array:
	var tokens = []
	for i in params.cards.size(): tokens.append({"n":int(params.cards[i]),"d":1,"expression":str(params.cards[i]),"cards":[i]})
	return tokens

static func combine(tokens: Array, action: Variant) -> Array:
	if not action is Dictionary or not action.has_all(["left","right","op"]): return []
	if not Numbers.integer(action.left,0,tokens.size()-1) or not Numbers.integer(action.right,0,tokens.size()-1) or action.left == action.right: return []
	if not action.op is String or not SYMBOLS.has(action.op): return []
	var a: Dictionary = tokens[int(action.left)]; var b: Dictionary = tokens[int(action.right)]
	var result: Array
	match action.op:
		"+": result = fraction(a.n*b.d+b.n*a.d,a.d*b.d)
		"-": result = fraction(a.n*b.d-b.n*a.d,a.d*b.d)
		"*": result = fraction(a.n*b.n,a.d*b.d)
		"/":
			if b.n == 0: return []
			result = fraction(a.n*b.d,a.d*b.n)
	var next = tokens.duplicate(true)
	next.remove_at(maxi(int(action.left),int(action.right))); next.remove_at(mini(int(action.left),int(action.right)))
	next.append({"n":result[0],"d":result[1],"expression":"("+a.expression+" "+SYMBOLS[action.op]+" "+b.expression+")","cards":a.cards+b.cards})
	return next

static func replay(params: Dictionary, state: Variant) -> Array:
	if not state is Dictionary or state.keys() != ["steps"] or not state.steps is Array or state.steps.size() > 3: return []
	var tokens = initial(params)
	for step in state.steps:
		tokens = combine(tokens,step)
		if tokens.is_empty(): return []
	return tokens

static func valid(params: Dictionary, state: Variant) -> bool:
	return not replay(params,state).is_empty()

static func complete(params: Dictionary, state: Dictionary) -> bool:
	var tokens = replay(params,state)
	return tokens.size() == 1 and tokens[0].cards.size() == 4 and tokens[0].n == params.target*tokens[0].d

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var tokens = replay(params,state)
	if action.get("kind") != "combine" or tokens.size() < 2: return {"accepted":false,"feedback":"选两张卡，再选运算。只剩一张时可以撤销或重新摆放。"}
	var next_tokens = combine(tokens,action)
	if next_tokens.is_empty(): return {"accepted":false,"feedback":"不能除以0，也不能重复使用同一张卡；请选择两张不同的卡。"}
	var next = state.duplicate(true); next.steps.append({"left":int(action.left),"right":int(action.right),"op":action.op})
	var value: Dictionary = next_tokens.back()
	var feedback = value.expression+" = "+value_text(value)
	if next_tokens.size() == 1:
		feedback += "，正好24！" if complete(params,next) else "；还没到24，撤销一步换个算法试试。"
	elif value.n == params.target*value.d: feedback += "；还有数字卡未用完，要把它们也接进算式。"
	return {"accepted":true,"state":next,"feedback":feedback}

static func solution(tokens: Array, target: int) -> Array:
	if tokens.size() == 1: return [{"done":true}] if tokens[0].n == target*tokens[0].d else []
	for a in tokens.size():
		for b in tokens.size():
			if a == b: continue
			for op in SYMBOLS:
				var step = {"left":a,"right":b,"op":op}
				var next = combine(tokens,step)
				if next.is_empty(): continue
				var tail = solution(next,target)
				if not tail.is_empty(): return [step]+tail
	return []

static func hint(params: Dictionary, state: Dictionary) -> String:
	var tokens = replay(params,state); var path = solution(tokens,params.target)
	if path.is_empty(): return "这个合并结果已经凑不出24了。撤销上一步，或重新摆放。"
	if path[0].has("done"): return "四张数字卡已经全部用上，结果正好24。"
	var step: Dictionary = path[0]
	return "当前可以先算 %s %s %s，再继续组合余下的卡。" % [value_text(tokens[step.left]),SYMBOLS[step.op],value_text(tokens[step.right])]

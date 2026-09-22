extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")

static func fresh(params: Dictionary) -> Dictionary:
	if params.has("candidates"):
		return {"probe_input":2,"predictions":{},"observation":[],"identified":"","secret_id":params.candidates.keys()[0]}
	# proof 标记：从这一版起，启动之前必须先押一注（写下新输入的预测输出）。
	# 旧存档没有这个键，仍按「装好并试过」判定，不会被判成无效。
	return {"order":[],"tested":false,"kept":[],"rejections":{},"prediction":0,"predicted_before_trial":false,"revealed":false,"equivalence":[],"final_order":[],"external_input":1,"external_tests":[],"observation_choice":"","observations":[],"proof":true}

static func evaluate(operations: Array, input_value: int) -> Array:
	var result = [input_value]; var value = input_value
	for operation in operations:
		match operation[0]:
			"add": value += int(operation[1])
			"sub": value -= int(operation[1])
			"mul": value *= int(operation[1])
		result.append(value)
	return result

static func operations(params: Dictionary, order: Array) -> Array:
	var result = []
	for id in order:
		for module in params.modules:
			if module.id == id: result.append(module.op)
	return result

static func orders(params: Dictionary) -> Array:
	var ids = []
	for module in params.modules: ids.append(module.id)
	var result = []; _orders(ids,[],int(params.slots),result); return result

static func _orders(remaining: Array, prefix: Array, count: int, result: Array) -> void:
	if prefix.size() == count: result.append(prefix); return
	for id in remaining:
		var rest = remaining.duplicate(); rest.erase(id); _orders(rest,prefix+[id],count,result)

static func matches(params: Dictionary, order: Array, record_index: int) -> bool:
	var record: Array = params.records[record_index]
	return evaluate(operations(params,order),int(record[0])).back() == record[1]

static func candidates(params: Dictionary) -> Array:
	var result = []
	for order in orders(params):
		var fits = true
		for i in params.records.size(): fits = fits and matches(params,order,i)
		if fits: result.append(order)
	return result

static func key(order: Array) -> String:
	return "/".join(order)

static func order_label(order: Array) -> String:
	var names = []
	for module in order: names.append({"plus2":"加2","plus3":"加3","plus5":"加5","plus7":"加7","minus1":"减1","double":"翻倍","triple":"三倍"}.get(module,module))
	return " → ".join(names)

static func known_order(params: Dictionary, order: Variant, allow_partial: bool = false) -> bool:
	if not order is Array or (not allow_partial and order.size() != params.slots) or order.size() > params.slots: return false
	var found = []
	for id in order:
		if not id is String or id in found: return false
		var known = false
		for module in params.modules:
			if module.id == id: known = true
		if not known: return false
		found.append(id)
	return true

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary: return false
	if params.has("candidates"):
		if not state.has_all(["probe_input","predictions","observation","identified","secret_id"]): return false
		if not state.identified is String or not state.secret_id is String: return false
		if state.probe_input not in params.probe_inputs or not state.predictions is Dictionary or not state.observation is Array or not params.candidates.has(state.secret_id): return false
		if state.identified != "" and not params.candidates.has(state.identified): return false
		for id in state.predictions:
			if not params.candidates.has(id) or not Numbers.integer(state.predictions[id],-100,200): return false
		if not state.observation.is_empty():
			if state.observation.size() != 2 or state.observation[0] != state.probe_input: return false
			if not Numbers.integer(state.observation[1],-100,200): return false
			if state.observation[1] != evaluate(params.candidates[state.secret_id],int(state.probe_input)).back(): return false
		return true
	if not state.has_all(["order","tested","kept","rejections","prediction","predicted_before_trial","revealed","equivalence","final_order","external_input","external_tests","observation_choice"]): return false
	if not state.get("proof",false) is bool: return false
	if not Numbers.integer(state.external_input,1,10) or not state.external_tests is Array or state.external_tests.size() > 10 or state.observation_choice not in ["","external","intermediate"]: return false
	var observations = state.get("observations",[])
	if not observations is Array or observations.size() > 3: return false
	for step in observations:
		if not Numbers.integer(step,0,3): return false
		if observations.count(step) > 1: return false
	for trial in state.external_tests:
		if not trial is Dictionary or not trial.has_all(["input","orders","outputs"]) or not Numbers.integer(trial.input,1,10) or not trial.orders is Array or not trial.outputs is Array or trial.orders.size() != trial.outputs.size(): return false
		for i in trial.orders.size():
			if not known_order(params,trial.orders[i]) or not Numbers.integer(trial.outputs[i],-100,200): return false
			if trial.outputs[i] != evaluate(operations(params,trial.orders[i]),int(trial.input)).back(): return false
	if not known_order(params,state.order,true) or not state.tested is bool or not state.predicted_before_trial is bool or not state.revealed is bool or not state.kept is Array or not state.rejections is Dictionary or not state.equivalence is Array or not known_order(params,state.final_order,true): return false
	var seen = []
	for order in state.kept:
		if not known_order(params,order) or key(order) in seen: return false
		seen.append(key(order))
	var all_keys = []
	for order in orders(params): all_keys.append(key(order))
	for id in state.rejections:
		if id not in all_keys or not Numbers.integer(state.rejections[id],0,params.records.size()-1): return false
	if not state.equivalence.is_empty():
		if state.equivalence.size() != 2: return false
		for i in range(2):
			var operation = state.equivalence[i]
			if not operation is Array or operation.size() != 2 or operation[0] != ["add","mul"][i] or not Numbers.integer(operation[1],0,10): return false
	return Numbers.integer(state.prediction,-100,200)

static func valid_predictions(params: Dictionary, state: Dictionary) -> bool:
	if state.predictions.size() != params.candidates.size(): return false
	var outputs = []
	for id in params.candidates:
		var value = evaluate(params.candidates[id],int(state.probe_input)).back()
		if state.predictions.get(id) != value: return false
		if value in outputs: return false
		outputs.append(value)
	return true

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true); var feedback = "装法已记在账簿上。"
	if params.has("candidates"):
		match action.get("kind"):
			"probe_input":
				if not state.observation.is_empty() or action.get("value") not in params.probe_inputs: return {"accepted":false,"feedback":"试验已经发生；撤销或重摆后再选择。"}
				next.probe_input = int(action.value); next.predictions = {}
			"predict":
				if not state.observation.is_empty() or not params.candidates.has(action.get("id")) or not Numbers.integer(action.get("value"),-100,200): return {"accepted":false,"feedback":"试验前，为每台机器摆出预测。"}
				next.predictions[action.id] = int(action.value)
			"probe":
				if not state.observation.is_empty(): return {"accepted":false,"feedback":"这次挑战只有一次试验；记录已保留。"}
				if state.predictions.size() != params.candidates.size(): return {"accepted":false,"feedback":"先为三台机器各摆出一条预测，再投送。"}
				var claimed = []
				for id in params.candidates: claimed.append(int(state.predictions[id]))
				if claimed[0] == claimed[1] or claimed[0] == claimed[2] or claimed[1] == claimed[2]:
					return {"accepted":false,"feedback":"你的三条预测里有相同的数——这包种子自己就分不清三台机器；换一包，或改对的预测。"}
				next.observation = [next.probe_input,evaluate(params.candidates[next.secret_id],int(next.probe_input)).back()]
				var matching = 0
				for id in params.candidates:
					if evaluate(params.candidates[id],int(next.probe_input)).back() == next.observation[1]: matching += 1
				feedback = "真实回响是%d；它只符合一台机器。"%next.observation[1] if matching == 1 else "真实回响是%d；还有%d台机器给出同样的回响。撤销这次试验，换一个能分清的投入量。"%[next.observation[1],matching]
			"identify":
				if not params.candidates.has(action.get("id")) or state.observation.is_empty(): return {"accepted":false,"feedback":"先取得真实回响，再辨认机器。"}
				var matching = 0
				for id in params.candidates:
					if evaluate(params.candidates[id],int(state.observation[0])).back() == state.observation[1]: matching += 1
				if matching > 1: return {"accepted":false,"feedback":"这个回响不止一台机器符合；撤销这次试验，换一个投入量再观察。"}
				if not state.predictions.is_empty() and not valid_predictions(params,state):
					for id in params.candidates:
						var truth: int = evaluate(params.candidates[id],int(state.probe_input)).back()
						if int(state.predictions.get(id,-999)) != truth:
							return {"accepted":false,"feedback":"你对%s机的预测(%d)和实际(%d)对不上；撤销这次试验，把三台的输出都算准，再重新投送。"%[id,int(state.predictions.get(id,0)),truth]}
				next.identified = action.id
			_: return {"accepted":false,"feedback":"未知育苗机操作。"}
	else:
		match action.get("kind"):
			"order":
				if not known_order(params,action.get("value"),true): return {"accepted":false,"feedback":"每个模块只能用一次。"}
				next.order = action.value.duplicate(); next.tested = false; next.predicted_before_trial = false
			"keep":
				if not known_order(params,action.get("value")): return {"accepted":false,"feedback":"先装好一台完整机器。"}
				if action.value in next.kept: next.kept.erase(action.value)
				else: next.kept.append(action.value.duplicate())
			"reject":
				if not known_order(params,action.get("order")) or not Numbers.integer(action.get("record"),0,params.records.size()-1): return {"accepted":false,"feedback":"选择装法和它违反的账簿记录。"}
				next.rejections[key(action.order)] = int(action.record)
			"predict":
				if not Numbers.integer(action.get("value"),-100,200): return {"accepted":false,"feedback":"摆出你的预测输出。"}
				next.prediction = int(action.value); next.predicted_before_trial = true; next.tested = false
			"try":
				if params.has("checkpoint") and action.has("order"):
					if action.order not in candidates(params): return {"accepted":false,"feedback":"选择一套符合账簿的装法试开。"}
					next.order = action.order.duplicate()
				if not known_order(params,next.order): return {"accepted":false,"feedback":"先把所有位置装好。"}
				# 没押注就不许启动：连按启动等于把「先想后验」换成「先看后猜」。
				if state.get("proof",false) and params.has("predict_input") and not next.predicted_before_trial:
					return {"accepted":false,"feedback":"先押一注：写下输入%d时你算出的输出，押完再启动机器。"%int(params.predict_input)}
				next.tested = true; feedback = "这台能正常育苗，性能验证成功！另一种也能用；接下来用旧记录找回原机顺序。" if params.has("checkpoint") and next.order in candidates(params) else "两页账簿都要符合；留下所有可能的装法。"
			"equivalence": next.equivalence = action.get("value",[]).duplicate(true)
			"external_input":
				if not params.has("checkpoint") or not Numbers.integer(action.get("value"),params.input_domain[0],params.input_domain[1]): return {"accepted":false,"feedback":"额外外部输入可选1至10。"}
				next.external_input = int(action.value)
			"observe_external":
				if not params.has("checkpoint"): return {"accepted":false,"feedback":"这台机器没有额外外部记录。"}
				var compare = next.kept if not next.kept.is_empty() else candidates(params)
				if compare.is_empty(): return {"accepted":false,"feedback":"当前账簿没有能同时满足的装法。"}
				var outputs = []
				for order in compare: outputs.append(evaluate(operations(params,order),int(next.external_input)).back())
				var trial = {"input":next.external_input,"orders":compare.duplicate(true),"outputs":outputs}
				var replaced = false
				for i in next.external_tests.size():
					if next.external_tests[i].input == next.external_input: next.external_tests[i] = trial; replaced = true
				if not replaced: next.external_tests.append(trial)
				next.observation_choice = "external"; feedback = "这次外部输入%d，符合账簿的装法仍给出相同结果。还需要哪一类观察？"%next.external_input
			"reveal":
				if not params.has("checkpoint"): return {"accepted":false,"feedback":"这台机器没有中间记录可看。"}
				var step = action.get("step",1)
				if not Numbers.integer(step,0,2): return {"accepted":false,"feedback":"选择要看哪一步之后的记录。"}
				var checkpoint: Dictionary = params.checkpoint
				var results = {}
				var pool: Array = next.kept
				if pool.is_empty(): pool = candidates(params)
				if pool.is_empty(): return {"accepted":false,"feedback":"当前账簿没有符合条件的装法。"}
				for order in pool:
					var value = str(int(evaluate(operations(params,order),int(checkpoint.input))[int(step)+1]))
					if not results.has(value): results[value] = []
					results[value].append(order)
				if not next.has("observations"): next.observations = []
				if int(step) not in next.observations: next.observations.append(int(step))
				next.revealed = true; next.observation_choice = "intermediate"
				var names = ["第一步之后","第二步之后","最后一步之后"]
				var shown = []
				for value in results:
					var labels = []
					for order in results[value]: labels.append(order_label(order))
					shown.append("『%s』得到 %s"%["  』与『  ".join(labels),value])
				if results.size() > 1:
					feedback = "输入4，%s：%s——两种装法分开了！"%[names[int(step)],"；".join(shown)]
				else:
					feedback = "输入4，%s都是 %s——这一档还分不开，换一档看看。"%[names[int(step)],results.keys()[0]]
			"final_order":
				if not next.revealed or not known_order(params,action.get("value")): return {"accepted":false,"feedback":"先看看机器内部的记录，再确定装法。"}
				if next.has("observations") and next.observations.size() < 3 and (int(params.checkpoint.after_step)-1) not in next.observations:
					return {"accepted":false,"feedback":"记录还没看清：再换一档观察，找到能把两种装法分开的那一步。"}
				var checkpoint: Dictionary = params.checkpoint
				var predicted: int = evaluate(operations(params,action.value),int(checkpoint.input))[int(checkpoint.after_step)]
				next.final_order = action.value.duplicate()
				feedback = "这套也能正常育苗，但第%d步会得到%d，原机记录是%d；归档顺序还没对上。" % [checkpoint.after_step,predicted,checkpoint.value] if predicted != checkpoint.value else "原机顺序与记录相符，保养档案补齐了！"
			_: return {"accepted":false,"feedback":"未知磨坊操作。"}
	if not valid(params,next): return {"accepted":false,"feedback":"记录格式不合法，原状态保留。"}
	return {"accepted":true,"state":next,"feedback":feedback}

static func same_orders(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for order in a:
		if order not in b: return false
	return true

static func external_certificate(params: Dictionary, state: Dictionary) -> bool:
	if not same_orders(state.kept,candidates(params)): return false
	# Player composes the equivalent first two operations, then the multiplier.
	return state.equivalence == [["add",2],["mul",2]]

# 押注要押的就是新输入在这台机器上的输出。
static func predicted_output(params: Dictionary, state: Dictionary) -> int:
	return evaluate(operations(params,state.order),int(params.predict_input)).back()

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if params.has("candidates"):
		# Saves written before predictions became mandatory carry an empty table and stay completable.
		if not state.predictions.is_empty() and not valid_predictions(params,state): return false
		return not state.observation.is_empty() and state.identified == state.secret_id
	if params.has("checkpoint"):
		if not state.revealed or state.final_order not in candidates(params): return false
		var checkpoint: Dictionary = params.checkpoint
		return evaluate(operations(params,state.final_order),int(checkpoint.input))[int(checkpoint.after_step)] == checkpoint.value
	# 这一版起，启动前必须押过注，且押的数要和机器算出来的对上（见 fresh 的 proof 标记）。
	# 改动押注会把 tested 打回 false，所以「已押且已验」这条记录不会自相矛盾。
	if state.get("proof",false) and params.has("predict_input"):
		if not state.predicted_before_trial or int(state.prediction) != predicted_output(params,state): return false
	return state.tested and state.order in candidates(params)

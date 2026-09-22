extends RefCounted
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Cargo = preload("res://scripts/mechanisms/cargo_rules.gd")
static func send(session: RefCounted, action: Dictionary) -> bool:
	return session.command(action,int(session.profile.revision))
static func rule(session: RefCounted, action: Dictionary) -> bool:
	return send(session,{"kind":"rule","action":action})
static func play(session: RefCounted, id: String) -> bool:
	if not send(session,{"kind":"start","level_id":id}): return false
	var actions = []
	match id:
		"FL01":
			for i in [0,1,2]: actions.append({"kind":"move","item":i,"target":1})
			for i in [3,4,5]: actions.append({"kind":"move","item":i,"target":2})
			actions.append({"kind":"travel"})
		"FL02":
			for i in [1,2,2]: actions.append({"kind":"shift","from":i,"to":0})
			actions.append({"kind":"try"})
		"FL03":
			for i in [1,1,2,2,2,2]: actions.append({"kind":"shift","from":i,"to":0})
			actions.append({"kind":"try"})
		"FL04":
			for pair in [[0,1],[1,2],[0,2]]: actions.append({"kind":"weigh","first":pair[0],"second":pair[1]})
			for i in range(3): actions.append({"kind":"weight","index":i,"value":[12,17,18][i]})
			# 三次合重之和正好是两套灯架：先算总量，再折出一套，最后点亮。
			var pair_rules = preload("res://scripts/mechanisms/pair_rules.gd")
			var pair_params: Dictionary = session.catalog.levels.FL04.params
			actions.append({"kind":"sum","value":pair_rules.sum_expected(pair_params)})
			actions.append({"kind":"total","value":pair_rules.total_expected(pair_params)})
			actions.append({"kind":"try"})
		"FL05":
			# 押注是必填：先算出这台机器在输入6上的输出，再启动对答案。
			var machine = preload("res://scripts/mechanisms/machine_rules.gd")
			var machine_params: Dictionary = session.catalog.levels.FL05.params
			var order := ["triple","plus2"]
			var bet: int = machine.evaluate(machine.operations(machine_params,order),int(machine_params.predict_input)).back()
			actions = [{"kind":"order","value":order},{"kind":"predict","value":bet},{"kind":"try"}]
		"FL06":
			actions = [{"kind":"probe_input","value":6},{"kind":"predict","id":"A","value":16},{"kind":"predict","id":"B","value":20},{"kind":"predict","id":"C","value":18},{"kind":"probe"}]
			for action in actions:
				if not rule(session,action): return false
			actions = [{"kind":"identify","id":session.profile.active_run.state.secret_id}]
		"FL07": actions = [{"kind":"combine","left":3,"right":1,"op":"-"},{"kind":"combine","left":1,"right":2,"op":"*"},{"kind":"combine","left":1,"right":0,"op":"-"}]
		"FL08":
			# Redesigned board: repair the misfiled card, supply the missing route,
			# then state the per-bag counts that expose the omission.
			var routes = preload("res://scripts/mechanisms/route_rules.gd")
			var params: Dictionary = session.catalog.levels.FL08.params
			var filing: Array = routes.filing_of(params,session.profile.active_run.state)
			for i in filing.size():
				if filing[i].group != filing[i].path.find("R"): actions.append({"kind":"audit_move","index":i})
			var listed: Array = []
			for card in filing: listed.append(card.path)
			for path in routes.all_paths(params):
				if path in listed: continue
				for direction in path: actions.append({"kind":"step","direction":direction})
				actions.append({"kind":"audit_add"})
			actions.append({"kind":"counts","value":[6,3,1]})
			actions.append({"kind":"try"})
		"FL09":
			for i in range(4): actions.append({"kind":"predict_block","block":i,"value":[8,11,11,8][i]})
			actions.append({"kind":"guess","block":1})
			for i in range(4): actions.append({"kind":"view_block","block":i})
			actions.append_array([{"kind":"choose","block":1},{"kind":"try"}])
		"FL10":
			# Redesigned board: commit to a maximum simultaneous set plus the reason
			# that no third letter fits.
			actions.append({"kind":"bound_set","value":["RRRUU","URRUR"]})
			actions.append({"kind":"bound_reason","value":0})
			actions.append({"kind":"try"})
		"FL11":
			# Seven-object manifest: trip 1 shares 阿橙+种子 under 石5; 小岚 rides solo
			# on 石4; the parcel goes up with 石3. Exactly three trips.
			actions = [{"kind":"move","item":0,"target":1},{"kind":"move","item":2,"target":1},{"kind":"move","item":4,"target":2},{"kind":"travel"},
				{"kind":"move","item":4,"target":0},{"kind":"move","item":1,"target":2},{"kind":"move","item":5,"target":1},{"kind":"travel"},
				{"kind":"move","item":5,"target":0},{"kind":"move","item":3,"target":1},{"kind":"move","item":6,"target":2},{"kind":"travel"}]
		"FL13":
			actions = [{"kind":"move","item":0,"target":1},{"kind":"move","item":2,"target":1},{"kind":"move","item":5,"target":2},{"kind":"travel"},
				{"kind":"move","item":1,"target":2},{"kind":"move","item":3,"target":1},{"kind":"move","item":4,"target":1},{"kind":"move","item":5,"target":0},{"kind":"travel"}]
		"FL12":
			while session.profile.active_run.state.winner == "":
				var remaining: int = session.profile.active_run.state.remaining
				if not rule(session,{"kind":"take","value":remaining%4}): return false
		"FL14":
			for i in range(5): actions.append({"kind":"step","value":2,"repair":false})
			for value in [2,2,2,2,1]: actions.append({"kind":"step","value":value,"repair":true})
			# 三个目标的判因各不一样（10 能走到 / 9 被奇偶拦住 / 8 五步凑不出），
			# 改一次向让终点少4。
			actions.append_array([{"kind":"classify","index":0,"reason":2},{"kind":"classify","index":1,"reason":1},{"kind":"classify","index":2,"reason":0},
				{"kind":"loss","value":4},{"kind":"try"}])
		"FL15":
			# 先答「至少要称几次」（由 3^k 追上九颗推出），再摆三分支方案。
			var coin_rules = preload("res://scripts/mechanisms/coin_rules.gd")
			actions.append({"kind":"min_weighings","value":coin_rules.minimal_weighings(session.catalog.levels.FL15.params)})
			for coin in range(6): actions.append({"kind":"assign","node":"root","coin":coin,"pan":"left" if coin < 3 else "right"})
			for i in range(3):
				var node: String = ["left","right","equal"][i]
				actions.append_array([{"kind":"assign","node":node,"coin":i*3,"pan":"left"},{"kind":"assign","node":node,"coin":i*3+1,"pan":"right"}])
			actions.append({"kind":"try"})
		"FL16":
			# 先押一注才允许调宽度，再扫完五种宽度、说清宽多的代价，最后围定 3×6。
			actions.append_array([{"kind":"area","value":18},{"kind":"loss","value":2}])
			for width in range(1,6): actions.append({"kind":"resize","width":width})
			actions.append_array([{"kind":"choose","index":2},{"kind":"try"}])
		"FL17":
			actions = [{"kind":"transfer","card":1,"from":2,"to":1}]
			if not rule(session,actions[0]): return false
			var swap: bool = session.profile.active_run.state.enemy_response_id == "leaf_swap"
			actions = [{"kind":"transfer","card":2 if swap else 3,"from":2,"to":0},{"kind":"transfer","card":3 if swap else 2,"from":1,"to":0},{"kind":"finish"}]
		"FL18":
			if not rule(session,{"kind":"probe","value":2}): return false
			if session.profile.active_run.state.active_observations[0][1] == 8:
				if not rule(session,{"kind":"probe","value":5}): return false
			actions = [{"kind":"finish","value":{"A":8,"B":6,"C":8,"D":7}[session.profile.active_run.state.secret_form_id]}]
		_: return false
	for action in actions:
		if not rule(session,action):
			push_error(id+": "+str(action)+" / "+session.feedback); return false
	return session.profile.active_run.outcome == "complete"

extends RefCounted
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Widgets = preload("res://scripts/ui/puzzle_boards.gd")
const Coins = preload("res://scripts/mechanisms/coin_rules.gd")

static func draw(host: Control, definition: Dictionary, run: Dictionary) -> void:
	preload("res://scripts/ui/workbench.gd").mount(host.ui,definition.family)
	match definition.family:
		"parity_repair": draw_parity(host,definition,run)
		"heavy_coin_plan": draw_coins(host,definition,run)
		"wall_fence": draw_fence(host,definition,run)

static func draw_parity(host: Control, _definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var enabled = run.outcome == "active"
	host.text("石头路上每步只能是+2或−2，且始终不能走出0到10。走满5步。",Rect2(82,182,1100,40),21,true)
	for row in range(2):
		var path: Array = state.path if row == 0 else state.repair; var y = 232+row*168
		host.text("第一条：想办法正好走到10" if row == 0 else "第二条：只把其中一步换成 ±1，走到9",Rect2(83,y,640,40),22,true)
		var positions = [0]; var sum = 0
		for step in path: sum += int(step); positions.append(sum)
		host.text("路线："+" → ".join(positions.map(func(n): return str(n)))+"   已走 %d/5 步"%path.size(),Rect2(84,y+50,660,30),22,true)
		var moves = [-2,2] if row == 0 else [-2,2,-1,1]
		for i in moves.size(): host.button("parity_%d_%d"%[row,moves[i]],("+" if moves[i] > 0 else "")+str(moves[i]),Rect2(760+i*104,y,96,42),host.rule.bind({"kind":"step","repair":row == 1,"value":moves[i]}),enabled)
		host.button("parity_clear_"+str(row),"擦掉重走",Rect2(760,y+58,191,38),host.rule.bind({"kind":"clear","repair":row == 1}),enabled)
		# Reachable endings from the current position: the parity insight made visible.
		# The walk must stay in [minimum,maximum] at every step, so count the legal
		# trajectories instead of assuming each same-parity value is attainable.
		if row == 0 and path.size() > 0 and path.size() < 5:
			var here: int = positions[positions.size()-1]
			var left = 5-path.size()
			var reach: Array = reachable_endings(_definition,here,left)
			if not reach.is_empty():
				host.text("从 %d 再走 %d 步，只能走到："%[here,left]+"、".join(reach.map(func(n): return str(n))),Rect2(84,y+84,660,26),19,true)
				host.text("（每步±2，奇偶不变；沿途也不能走出0至10）",Rect2(84,y+112,660,24),18,true)
	host.button("try","上路试试",Rect2(1008,541,192,39),host.rule.bind({"kind":"try"}),enabled)

static func reachable_endings(definition: Dictionary, here: int, steps_left: int) -> Array:
	var minimum: int = int(definition.params.minimum)
	var maximum: int = int(definition.params.maximum)
	var found: Array = []
	_walk_endings(definition,here,steps_left,minimum,maximum,found)
	found.sort()
	return found

static func _walk_endings(definition: Dictionary, here: int, steps_left: int, minimum: int, maximum: int, found: Array) -> void:
	if steps_left == 0:
		if here >= minimum and here <= maximum and here not in found: found.append(here)
		return
	for move in definition.params.moves:
		var next: int = here+int(move)
		if next >= minimum and next <= maximum: _walk_endings(definition,next,steps_left-1,minimum,maximum,found)

static func draw_coins(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var enabled = run.outcome == "active"; var node_id: String = host.coin_node
	var node: Dictionary = state.nodes[node_id]
	for i in range(4):
		var id = ["root","left","right","equal"][i]
		host.button("coin_node_"+id,("✓ " if id == node_id else "")+["第一次称量","要是左边重","要是右边重","要是平衡"][i],Rect2(79+i*227,178,209,39),func(): host.coin_node = id; host.selected_coin = -1; host.refresh())
	host.text("先点一颗晶体，再点放左盘、右盘或桌面。安排两次称量：三种结果——左重、右重、平衡——都要指向唯一一颗。",Rect2(81,230,1100,40),20,true)
	for coin in range(9): host.button("coin_"+str(coin),("✓ " if host.selected_coin == coin else "")+str(coin+1),Rect2(82+coin*123,290,104,43),func(): host.selected_coin = coin; host.refresh(),enabled)
	for i in range(3):
		var pan = ["left","right","off"][i]
		var numbers = []
		for coin in range(9):
			if (pan == "off" and coin not in node.left and coin not in node.right) or (pan != "off" and coin in node[pan]): numbers.append(str(coin+1))
		host.button("pan_"+pan,["左盘","右盘","桌面"][i]+"："+" ".join(numbers),Rect2(82+i*374,360,350,48),func():
			if host.selected_coin >= 0: host.rule({"kind":"assign","node":node_id,"coin":host.selected_coin,"pan":pan}),enabled)
	var count = Coins.distinguished(definition.params,state.nodes)
	var ambiguous = Coins.ambiguous_pairs(definition.params,state.nodes)
	if ambiguous.is_empty() and _root_ready(node if node_id == "root" else state.nodes.root):
		host.text("无论哪颗更重，两次称量后都能指认出来。",Rect2(84,444,1100,34),21,true)
	elif ambiguous.is_empty():
		host.text("分支已经能分开所有情况；先安排第一次称量。",Rect2(84,444,1100,34),21,true)
	else:
		var names = []
		for group in ambiguous:
			var labels = []
			for coin in group: labels.append("第%d颗"%(int(coin)+1))
			names.append("、".join(labels))
		host.text("会分不开的："+("；".join(names))+"——把它们拆到不同分支。",Rect2(84,444,1100,34),20,true)
	host.button("try","亲手称一称",Rect2(1000,486,194,38),host.rule.bind({"kind":"try"}),enabled)
	if not state.observation.is_empty():
		var labels = {"left":"左重","right":"右重","equal":"平衡"}
		var second_node = state.nodes[state.observation[0]]
		host.text("实际结果：第一次%s → 第二次%s。%s"%[labels[state.observation[0]],labels[state.observation[1]],"按方案指认出：第%d颗"%(int(state.observation[2])+1) if int(state.observation[2]) >= 0 else "这个结果对应不到唯一一颗"],Rect2(85,532,1109,30),20,true)

static func _root_ready(root: Dictionary) -> bool:
	return not root.left.is_empty() and not root.right.is_empty()

static func draw_fence(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var enabled = run.outcome == "active"
	var units: int = int(definition.params.fence_units)
	host.text("邻居用 4×4 围了 16 格（绿色靶子）。用 %d 单位木料围三边，试试能不能超过它。"%units,Rect2(82,174,1094,38),21,true)
	var w: int = int(state.width); var l: int = int(state.length)
	var complete = 2*w+l == units
	# The plot: borrowed wall on top, two fenced widths, fenced bottom edge.
	# A fixed plot band keeps the borrowed-wall caption clear of the intro paragraph at every width.
	var plot = Rect2(150,256,420,214)
	var cell = minf(plot.size.x/maxi(l,1),plot.size.y/maxi(w,1))
	var inner = Rect2(plot.position+Vector2((plot.size.x-l*cell)/2,(plot.size.y-w*cell)/2),Vector2(l*cell,w*cell))
	var shape = ColorRect.new(); shape.position = inner.position; shape.size = inner.size
	shape.color = Color("7d9c5e") if complete else Color("6c7358"); shape.mouse_filter = Control.MOUSE_FILTER_IGNORE; host.ui.add_child(shape)
	var wall = ColorRect.new(); wall.position = inner.position-Vector2(0,14); wall.size = Vector2(inner.size.x,14)
	wall.color = Color("9a917f"); wall.mouse_filter = Control.MOUSE_FILTER_IGNORE; host.ui.add_child(wall)
	host.text("借来的墙",Rect2(inner.position.x,maxf(216.0,inner.position.y-42.0),200,24),17,true)
	for side_rect in [Rect2(inner.position+Vector2(-10,0),Vector2(10,inner.size.y)),Rect2(inner.position+Vector2(inner.size.x,0),Vector2(10,inner.size.y)),Rect2(inner.position+Vector2(0,inner.size.y),Vector2(inner.size.x,10))]:
		var rail = ColorRect.new(); rail.position = side_rect.position; rail.size = side_rect.size
		rail.color = Color("b08a58"); rail.mouse_filter = Control.MOUSE_FILTER_IGNORE; host.ui.add_child(rail)
	host.text("宽 %d × 长 %d = %d 格" % [w,l,w*l],Rect2(150,482,420,32),23,true)
	host.text("用料：2×%d + %d = %d / %d%s" % [w,l,2*w+l,units,"（正好用完，可以围定）" if complete else "（还要正好用完）"],Rect2(150,514,540,28),19,true)
	# Target comparison.
	var target = ColorRect.new(); target.position = Vector2(600,240); target.size = Vector2(140,140)
	target.color = Color("58804f"); target.mouse_filter = Control.MOUSE_FILTER_IGNORE; host.ui.add_child(target)
	host.text("邻居 4×4 = 16 格",Rect2(596,386,300,28),19,true)
	var delta = w*l-16
	host.text("你的 %d 格——%s" % [w*l,"比邻居多 %d 格！"%delta if delta > 0 else ("和邻居一样多" if delta == 0 else "还差 %d 格"%(-delta))],Rect2(596,416,330,28),19,true)
	host.text("调整宽度（长度自动配合）：",Rect2(596,462,420,28),20,true)
	host.button("fence_w_less","− 窄一点",Rect2(596,496,180,42),host.rule.bind({"kind":"resize","width":maxi(1,w-1)}),enabled and w > 1)
	host.button("fence_w_more","+ 宽一点",Rect2(790,496,130,42),host.rule.bind({"kind":"resize","width":mini((units-1)/2,w+1)}),enabled and w < (units-1)/2)
	host.text("试过的方案（点一份来围定）：",Rect2(936,240,300,28),20,true)
	for i in state.plans.size():
		var plan: Array = state.plans[i]
		host.button("fence_choose_"+str(i),("✓ " if state.chosen == i else "")+"%d×%d = %d格"%plan,Rect2(936,272+i*44,300,38),host.rule.bind({"kind":"choose","index":i}),enabled)
	host.button("try","就围这份",Rect2(936,496,300,42),host.rule.bind({"kind":"try"}),enabled)

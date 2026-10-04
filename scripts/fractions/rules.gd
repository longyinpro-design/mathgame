extends RefCounted
var definition: Dictionary
var p: Dictionary
func _init(d: Dictionary):
	definition = d.duplicate(true)
	p = definition.params
func fresh() -> Dictionary:
	return {"actions": []}
func integer(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) == floor(float(v)) and abs(float(v)) <= 10000
func keys(d: Variant, names: Array) -> bool:
	if not d is Dictionary or d.size() != names.size(): return false
	for k in names:
		if not d.has(k): return false
	return true
func initial() -> Dictionary:
	if definition.mechanism == "mosaic":
		var tiles: Array = []
		for item in p.tiles: tiles.append({"unit": int(item[0]), "amount": int(item[1]), "owner": -1})
		return {"tiles": tiles}
	return {"water": p.initial.duplicate(), "gates": [], "stage": 0, "pulses": 0, "locked": false}
func projection(s: Dictionary) -> Dictionary:
	var b := initial()
	for a in s.actions:
		b = step(b,a)
		if b.is_empty(): return {}
	return b
func validate(s: Variant) -> bool:
	if not keys(s,["actions"]) or not s.actions is Array or s.actions.size() > 4096: return false
	return not projection(s).is_empty()
func apply(s: Dictionary, a: Dictionary) -> Dictionary:
	if not validate(s) or s.actions.size() >= 4096: return {}
	if step(projection(s),a).is_empty(): return {}
	var next := s.duplicate(true)
	next.actions.append(a.duplicate(true))
	return next
func step(b: Dictionary, a: Variant) -> Dictionary:
	if not a is Dictionary or not a.has("type") or not a.type is String: return {}
	var n := b.duplicate(true)
	if definition.mechanism == "mosaic":
		if a.type == "place":
			if not keys(a,["type","tile","owner"]) or not integer(a.tile) or not integer(a.owner): return {}
			if a.tile < 0 or a.tile >= n.tiles.size() or a.owner < -1 or a.owner >= p.targets.size(): return {}
			n.tiles[int(a.tile)].owner = int(a.owner)
		elif a.type == "split":
			if not keys(a,["type","tile","parts"]) or not integer(a.tile) or not integer(a.parts): return {}
			if a.tile < 0 or a.tile >= n.tiles.size() or not int(a.parts) in p.splits or n.tiles.size()+int(a.parts)-1 > 24: return {}
			var tile: Dictionary = n.tiles[int(a.tile)]
			if tile.amount % int(a.parts) != 0: return {}
			n.tiles.remove_at(int(a.tile))
			for i in range(int(a.parts)): n.tiles.append({"unit": tile.unit, "amount": tile.amount / int(a.parts), "owner": tile.owner})
		else: return {}
		return n
	if definition.mechanism == "reverse":
		if a.type == "shift":
			if not keys(a,["type","source","target"]) or not integer(a.source) or not integer(a.target) or n.locked: return {}
			var x := int(a.source); var y := int(a.target)
			if x < 0 or y < 0 or x >= n.water.size() or y >= n.water.size() or x == y or n.water[x] < p.quantum: return {}
			if n.water[y] + p.quantum > p.capacity[y]: return {}
			n.water[x] -= p.quantum; n.water[y] += p.quantum
		elif a.type == "release":
			if not keys(a,["type"]) or n.locked: return {}
			for gift in p.gifts:
				var total := int(n.water[int(gift[0])]) * int(gift[2])
				if total % int(gift[3]) != 0: return {}
				var amount := total / int(gift[3])
				if n.water[int(gift[1])] + amount > p.capacity[int(gift[1])]: return {}
				n.water[int(gift[0])] -= amount; n.water[int(gift[1])] += amount
			n.locked = true
		else: return {}
		return n
	if a.type == "gate":
		if not keys(a,["type","edge"]) or not integer(a.edge) or a.edge < 0 or a.edge >= p.edges.size(): return {}
		if int(a.edge) in blocked(n): return {}
		if int(a.edge) in n.gates: n.gates.erase(int(a.edge))
		else: n.gates.append(int(a.edge)); n.gates.sort()
	elif a.type == "pulse":
		if not keys(a,["type"]) or n.gates.is_empty() or n.pulses >= p.max_pulses: return {}
		var outgoing: Array = []; outgoing.resize(n.water.size()); outgoing.fill(0)
		var delta := outgoing.duplicate()
		for e in n.gates:
			var edge: Array = p.edges[int(e)]
			outgoing[int(edge[0])] += edge[2]
			delta[int(edge[0])] -= edge[2]; delta[int(edge[1])] += edge[2]
		for i in range(n.water.size()):
			if outgoing[i] > n.water[i] or n.water[i]+delta[i] > p.capacity[i]: return {}
		for i in range(n.water.size()): n.water[i] += delta[i]
		n.pulses += 1
	elif a.type == "checkpoint":
		if not keys(a,["type"]) or definition.mechanism != "guardian" or not matches(n.water,p.goals[int(n.stage)]) or n.stage >= p.goals.size()-1: return {}
		n.stage += 1; n.gates.clear()
	else: return {}
	return n
func blocked(b: Dictionary) -> Array:
	return p.blocked[int(b.stage)] if definition.mechanism == "guardian" else []
func matches(w: Array, goal: Array) -> bool:
	return w == goal
func solved(s: Dictionary) -> bool:
	if not validate(s): return false
	var b := projection(s)
	if definition.mechanism == "mosaic":
		var totals: Array = []; var counts: Array = []
		for target in p.targets: totals.append(0); counts.append(0)
		for tile in b.tiles:
			if tile.owner < 0: return false
			var target: Array = p.targets[int(tile.owner)]
			if int(target[0]) >= 0 and int(target[0]) != int(tile.unit): return false
			totals[int(tile.owner)] += int(tile.amount); counts[int(tile.owner)] += 1
		for i in range(totals.size()):
			if totals[i] != p.targets[i][1]: return false
			if p.counts[i] >= 0 and counts[i] != p.counts[i]: return false
		return true
	if definition.mechanism == "reverse": return b.locked and matches(b.water,p.goal)
	if definition.mechanism == "guardian": return b.stage == p.goals.size()-1 and matches(b.water,p.goals[int(b.stage)])
	return matches(b.water,p.goal)
func feedback(s: Dictionary) -> String:
	if not validate(s): return "水庭记录不完整，请回到上一稳定局面。"
	if solved(s): return "水量守恒，所有花圃都得到约定的水！"
	var b := projection(s)
	if definition.mechanism == "mosaic": return "每片水都要归位。检查每个整体的标记、水量与指定片数。"
	if definition.mechanism == "reverse": return "先摆好原来的水，再按顺序放水；末态必须与刻线完全相同。"
	if definition.mechanism == "guardian": return "本轮刻线尚未全部吻合；吻合后按「守住本轮」再接下一轮。"
	return "尚有池水未到目标刻线。打开的闸门会同时取水，不能借用同一拍刚流入的水。"
func hint(s: Dictionary, tier: int) -> String:
	if tier <= 1: return definition.hints[0]
	if tier == 2: return definition.hints[1]
	if tier == 3: return feedback(s) + " " + definition.hints[2]
	var b := projection(s)
	if definition.mechanism == "mosaic":
		for j in range(p.targets.size()):
			var total := 0
			for tile in b.tiles:
				if tile.owner == j: total += int(tile.amount)
			if total != p.targets[j][1]: return "花圃%d目前%d格，目标%d格。点水片再点花圃；大水片可以等分，片数要求也要保留。"%[j+1,total,p.targets[j][1]]
		return "水量已经相等；再检查每片的甲/乙整体标记和各花圃片数。"
	if definition.mechanism == "reverse":
		if b.locked: return "已经按顺序放水。若末态不符，用撤销退回放水前，再调整原来的分配。"
		return definition.hints[3] + " 当前原分配："+str(b.water)
	var target: Array = p.goals[b.stage] if definition.mechanism == "guardian" else p.goal
	if b.water == target: return "本轮所有刻线吻合。" + ("按守住本轮继续。" if definition.mechanism == "guardian" and b.stage < p.goals.size()-1 else "可以验收了。")
	if b.pulses >= p.max_pulses: return "本关的拍数已用完。撤销几拍，保留更多同时流动的渠道再试。"
	var note := "比较本轮差额："
	for i in range(target.size()): note += "池%d差%+d格；"%[i+1,target[i]-b.water[i]]
	return note + "先关闭不需要的闸门，确认来源池拍前有足够水。"

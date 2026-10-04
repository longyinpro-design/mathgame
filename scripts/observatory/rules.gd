extends RefCounted
var definition: Dictionary
var p: Dictionary
var family: String
func _init(d: Dictionary):
	definition = _normal(d); p = definition.params; family = definition.mechanism
func _normal(v: Variant) -> Variant:
	if v is float and is_finite(v) and v==floor(v) and abs(v)<1000000000: return int(v)
	if v is Array:
		var a=[]
		for item in v: a.append(_normal(item))
		return a
	if v is Dictionary:
		var d={}
		for k in v: d[k]=_normal(v[k])
		return d
	return v
func _integer(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) == floor(float(v))
func _keys(d: Variant, keys: Array) -> bool:
	if not d is Dictionary or d.size() != keys.size(): return false
	for key in keys:
		if not d.has(key): return false
	return true
func _ints(a: Variant, lo: int, hi: int, count: int=-1, unique: bool=false) -> bool:
	if not a is Array or (count>=0 and a.size()!=count): return false
	var seen: Array=[]
	for v in a:
		if not _integer(v) or v<lo or v>hi or (unique and v in seen): return false
		seen.append(v)
	return true
func fresh() -> Dictionary:
	match family:
		"scale": return {"points":p.source.duplicate(true)}
		"shutters": return {"open":p.initial.duplicate(true)}
		"routes": return {"draft":[],"routes":[]}
		"schedule":
			var slots=[]
			for j in p.jobs: slots.append([-1,-1])
			return {"slots":slots}
		"storm": return {"edges":[],"phase":0,"before":[],"broken":-1}
		"finale": return {"edges":[],"starts":[-1,-1,-1,-1,-1,-1]}
	return {}
func validate(s: Variant) -> bool:
	s=_normal(s)
	match family:
		"scale":
			if not _keys(s,["points"]) or not s.points is Array or s.points.size()!=p.source.size(): return false
			for point in s.points:
				if not _ints(point,0,8,2): return false
			return true
		"shutters":
			if not _keys(s,["open"]) or not s.open is Array or s.open.size()!=p.sizes.size(): return false
			for i in range(p.sizes.size()):
				if not _ints(s.open[i],0,int(p.sizes[i])-1,-1,true): return false
				for v in s.open[i]:
					if v in p.blocked[i]: return false
			return true
		"routes":
			if not _keys(s,["draft","routes"]) or not _ints(s.draft,0,p.nodes.size()-1,-1,true) or not s.routes is Array: return false
			if not _valid_path(s.draft,false): return false
			var seen=[]
			for r in s.routes:
				if not _ints(r,0,p.nodes.size()-1,-1,true) or not _valid_path(r,true) or r in seen: return false
				seen.append(r)
			return s.routes.size()<=all_routes().size()
		"schedule":
			if not _keys(s,["slots"]) or not s.slots is Array or s.slots.size()!=p.jobs.size(): return false
			for v in s.slots:
				if not _ints(v,-1,int(p.horizon),2): return false
				if v==[-1,-1]: continue
				if v[0]<0 or v[0]>=p.tracks or v[1]<0: return false
			return true
		"storm":
			if not _keys(s,["edges","phase","before","broken"]): return false
			if not _ints(s.edges,0,p.edges.size()-1,-1,true) or not _ints(s.before,0,p.edges.size()-1,-1,true) or not _integer(s.phase) or not _integer(s.broken): return false
			if s.phase==0: return s.before.is_empty() and s.broken==-1
			if s.phase!=1 or not resilient(s.before) or network_cost(s.before)>p.budget or s.before.is_empty(): return false
			return s.broken==s.before.min() and not s.broken in s.edges
		"finale": return _keys(s,["edges","starts"]) and _ints(s.edges,0,p.edges.size()-1,-1,true) and _ints(s.starts,-1,int(p.horizon),6)
	return false
func apply(s: Dictionary, a: Dictionary) -> Dictionary:
	s=_normal(s); a=_normal(a)
	if not validate(s) or not a.get("type") is String: return {}
	var n=s.duplicate(true)
	match family:
		"scale":
			if not _keys(a,["type","piece","x","y"]) or a.type!="place": return {}
			for k in ["piece","x","y"]:
				if not _integer(a[k]): return {}
			if a.piece<0 or a.piece>=s.points.size(): return {}
			n.points[a.piece]=[a.x,a.y]
		"shutters":
			if not _keys(a,["type","window","cell"]) or a.type!="toggle" or not _integer(a.window) or not _integer(a.cell): return {}
			if a.window<0 or a.window>=p.sizes.size() or a.cell<0 or a.cell>=p.sizes[a.window] or a.cell in p.blocked[a.window]: return {}
			if a.cell in n.open[a.window]: n.open[a.window].erase(a.cell)
			else: n.open[a.window].append(a.cell); n.open[a.window].sort()
		"routes":
			match a.type:
				"append":
					if not _keys(a,["type","node"]) or not _integer(a.node): return {}
					n.draft.append(a.node)
				"clear":
					if not _keys(a,["type"]): return {}
					n.draft=[]
				"record":
					if not _keys(a,["type"]) or not _valid_path(n.draft,true) or n.draft in n.routes: return {}
					n.routes.append(n.draft.duplicate()); n.draft=[]
				"remove":
					if not _keys(a,["type","index"]) or not _integer(a.index) or a.index<0 or a.index>=n.routes.size(): return {}
					n.routes.remove_at(a.index)
				_: return {}
		"schedule":
			if not _keys(a,["type","job","track","start"]) or a.type!="schedule": return {}
			for k in ["job","track","start"]:
				if not _integer(a[k]): return {}
			if a.job<0 or a.job>=p.jobs.size(): return {}
			n.slots[a.job]=[a.track,a.start]
		"storm", "finale":
			if a.type=="cable":
				if not _keys(a,["type","edge"]) or not _integer(a.edge) or a.edge<0 or a.edge>=p.edges.size(): return {}
				if family=="storm" and a.edge==s.broken: return {}
				if a.edge in n.edges: n.edges.erase(a.edge)
				else: n.edges.append(a.edge); n.edges.sort()
			elif family=="storm" and a.type=="storm":
				if not _keys(a,["type"]) or s.phase!=0 or not resilient(s.edges) or network_cost(s.edges)>p.budget: return {}
				n.before=s.edges.duplicate(); n.broken=s.edges.min(); n.edges.erase(n.broken); n.phase=1
			elif family=="finale" and a.type=="depart":
				if not _keys(a,["type","job","start"]) or not _integer(a.job) or not _integer(a.start) or a.job<0 or a.job>=6: return {}
				n.starts[a.job]=a.start
			else: return {}
	return n if validate(n) else {}
func _valid_path(path: Array, complete: bool) -> bool:
	if path.is_empty(): return not complete
	if not path[0] in p.starts: return false
	if p.length>0 and path.size()>p.length: return false
	for i in range(1,path.size()):
		if not [path[i-1],path[i]] in p.edges: return false
		if p.length==0 and path[i-1] in p.ends: return false
	if not complete: return true
	if not path[-1] in p.ends or (p.length>0 and path.size()!=p.length): return false
	for v in p.required:
		if not v in path: return false
	return true
func all_routes() -> Array:
	var result: Array=[]
	var stack: Array=[[]]
	while not stack.is_empty():
		var path: Array=stack.pop_back()
		if _valid_path(path,true): result.append(path)
		for node in range(p.nodes.size()):
			if node in path: continue
			var next=path.duplicate(); next.append(node)
			if _valid_path(next,false): stack.append(next)
	return result
func network_cost(edges: Array) -> int:
	var cost=0
	for e in edges: cost+=int(p.edges[e][2])
	return cost
func distance(edges: Array, source: int, target: int, weighted: bool=true) -> int:
	var dist=[]
	for i in range(p.nodes.size()): dist.append(999)
	dist[source]=0
	for _pass in range(p.nodes.size()):
		for idx in edges:
			var e=p.edges[idx]; var w=int(e[3]) if weighted else 1
			dist[e[1]]=mini(dist[e[1]],dist[e[0]]+w)
			dist[e[0]]=mini(dist[e[0]],dist[e[1]]+w)
	return dist[target]
func connected(edges: Array) -> bool:
	for i in range(p.nodes.size()):
		if distance(edges,0,i)>=999: return false
	return true
func resilient(edges: Array) -> bool:
	if not connected(edges): return false
	for e in edges:
		var other=edges.duplicate(); other.erase(e)
		if not connected(other): return false
	return true
func journey(s: Dictionary, job: int) -> int:
	return maxi(1,distance(s.edges,0,int(p.jobs[job].target)))
func _overlap(a: int, da: int, b: int, db: int) -> bool:
	return a<b+db and b<a+da
func _schedule_issue(s: Dictionary) -> String:
	var cost=0; var end=0
	for i in range(p.jobs.size()):
		var slot=s.slots[i]; var j=p.jobs[i]
		if slot[0]<0: return "%s还没有安排轨道和出发时刻。" % j.name
		var duration=int(j.durations[slot[0]])
		if slot[1]<j.release: return "%s不能早于%d时出发。" % [j.name,j.release]
		if slot[1]+duration>j.deadline: return "%s会晚于%d时到达。" % [j.name,j.deadline]
		cost+=int(j.costs[slot[0]]); end=maxi(end,slot[1]+duration)
		for k in range(i):
			var prev=s.slots[k]; var dur=int(p.jobs[k].durations[prev[0]])
			if slot[0]==prev[0] and _overlap(slot[1],duration,prev[1],dur): return "%s与%s在同一轨道的航行时段重叠。" % [j.name,p.jobs[k].name]
			if slot[0]!=prev[0] and not p.cross.is_empty() and slot[1]+p.cross[slot[0]]==prev[1]+p.cross[prev[0]]: return "%s与%s会同时经过交叉点。" % [j.name,p.jobs[k].name]
	if p.max_cost>=0 and cost>p.max_cost: return "总耗晶%d超过预算%d；试试较省晶的轨道。" % [cost,p.max_cost]
	if p.max_end>=0 and end>p.max_end: return "最后一船在%d时到达，须不晚于%d时。" % [end,p.max_end]
	return ""
func _issue(s: Dictionary) -> String:
	s=_normal(s)
	if not validate(s): return "棋盘数据不完整或含不合法字段。"
	match family:
		"scale":
			for i in range(p.source.size()):
				for axis in range(2):
					if (s.points[i][axis]-p.origin[axis])*p.den != (p.source[i][axis]-p.source_origin[axis])*p.num:
						return "星点%d的%s距离未按%d:%d缩放；从金色基点量起。" % [i+1,"横向" if axis==0 else "纵向",p.num,p.den]
		"shutters":
			var changes=0
			for i in range(p.sizes.size()):
				var whole=int(p.sizes[i])-(p.blocked[i].size() if p.basis[i]=="remaining" else 0)
				if s.open[i].size()*100!=whole*p.targets[i]: return "第%d窗：整体%d格，当前%d格开放，还不是%d%%。" % [i+1,whole,s.open[i].size(),p.targets[i]]
				if p.contiguous and not s.open[i].is_empty() and s.open[i].max()-s.open[i].min()+1!=s.open[i].size(): return "亮格还没有连成一束连续的光。"
				for v in range(p.sizes[i]):
					if (v in s.open[i])!=(v in p.initial[i]): changes+=1
			if p.min_changes>=0 and changes!=p.min_changes: return "目前改变%d格；最少只需改变%d格。" % [changes,p.min_changes]
		"routes":
			var total=all_routes().size()
			if s.routes.size()!=total: return "已收藏%d条合法路线；还有未整理的分支。按相同起步分组检查。" % s.routes.size()
		"schedule": return _schedule_issue(s)
		"storm":
			if network_cost(s.edges)>p.budget: return "线缆费用%d超过%d晶。" % [network_cost(s.edges),p.budget]
			if s.phase==0: return "网络已抗风，可迎接星风。" if resilient(s.edges) else "第一阶段须任意断一条线后四塔仍连通；有塔只有一条退路。"
			var added=0
			for e in s.edges:
				if not e in s.before: added+=1
			if added>p.repair_limit: return "只能加装1条原来没有的线。"
			if not connected(s.edges): return "断线后的网络仍有孤立的塔。"
			for a in range(p.nodes.size()):
				for b in range(p.nodes.size()):
					if distance(s.edges,a,b,false)>2: return "%s到%s超过两段，请用一条新线缩短绕路。" % [p.nodes[a],p.nodes[b]]
		"finale":
			if network_cost(s.edges)>p.budget: return "线缆费用%d超过8晶；试试岛间短线。" % network_cost(s.edges)
			if not connected(s.edges): return "六座岛还没有全部与星台连通。"
			for i in range(6):
				if s.starts[i]<0: return "%s还没有出发时刻。" % p.jobs[i].name
				if s.starts[i]+journey(s,i)>p.jobs[i].deadline: return "%s按当前航线会晚到；改出发时间或缩短航线。" % p.jobs[i].name
				for j in range(i):
					if _overlap(s.starts[i],journey(s,i),s.starts[j],journey(s,j)): return "%s与%s占用总发射通道的时段重叠。" % [p.jobs[i].name,p.jobs[j].name]
	return ""
func solved(s: Dictionary) -> bool:
	return validate(s) and _issue(s).is_empty()
func feedback(s: Dictionary) -> String:
	var issue=_issue(s)
	return issue if not issue.is_empty() else "全部现场条件成立，航灯接通了。"
func hint(s: Dictionary, tier: int) -> String:
	if tier<=1:
		return {"scale":"先找到两图的金色基点。","shutters":"先说清本关的整体包含哪些格。","routes":"把第一步相同的路线放在一起找。","schedule":"先照顾最早截止的船，再给后来的船留位置。","storm":"检查每座塔有没有两条不同的退路。","finale":"先让每座岛接回星台，再根据实际航程排发船时间。"}[family]
	if tier==2:
		return {"scale":"横向和纵向距离都要乘同一比例。","shutters":"百分数表示每100份中几份，损坏格是否算整体请看说明。","routes":"每个节点都试过后，再换上一步；相反顺序不一定同一路。","schedule":"船从出发到到达占用轨道；省晶路线可能更慢。","storm":"圈形网络能留下退路；断线后要让两塔之间最多两段。","finale":"费用是装线的花费，时长是船实际航行的距离，两者不同。"}[family]
	if tier==3: return feedback(s)
	match family:
		"scale":
			for i in range(p.source.size()):
				var target=[int(p.origin[0]+(p.source[i][0]-p.source_origin[0])*p.num/p.den),int(p.origin[1]+(p.source[i][1]-p.source_origin[1])*p.num/p.den)]
				if s.points[i]!=target: return "星点%d可放在(%d,%d)，再同样量其他点。" % [i+1,target[0],target[1]]
		"shutters":
			for i in range(p.sizes.size()):
				var whole=p.sizes[i]-(p.blocked[i].size() if p.basis[i]=="remaining" else 0)
				if s.open[i].size()*100!=whole*p.targets[i]: return "第%d窗应打开%d格；仍需检查连续与最少改动条件。" % [i+1,int(whole*p.targets[i]/100)]
		"routes":
			for r in all_routes():
				if not r in s.routes:
					var names=[]
					for v in r: names.append(p.nodes[v])
					return "还没收藏这一条："+" → ".join(names)
		"schedule":
			var target=_schedule_completion(_normal(s))
			for i in range(target.size()):
				if target[i]!=s.slots[i]:return "可先把%s放在轨道%d的%d时出发，航程%d时。之后继续检查其他船。" % [p.jobs[i].name,target[i][0]+1,target[i][1],p.jobs[i].durations[target[i][0]]]
			return feedback(s)
		"storm": return "第一阶段可尝试围成四塔环；风后找最长的两塔绕路，加一条斜线。"
		"finale": return "试用两条星台直连线和四条岛间短线；再按每船显示的航程首尾相接排班。"
	return feedback(s)
# Constraint search for contextual high-tier guidance, never a stored answer.
func _schedule_completion(s: Dictionary, slots: Array=[], index: int=0) -> Array:
	if index==p.jobs.size():
		return slots if _schedule_issue({"slots":slots}).is_empty() else []
	var j=p.jobs[index];var candidates: Array=[]
	if s.slots[index][0]>=0:candidates.append(s.slots[index])
	for track in range(p.tracks):
		for start in range(int(j.release),int(j.deadline-j.durations[track])+1):
			var pair=[track,start]
			if not pair in candidates:candidates.append(pair)
	for pair in candidates:
		var track=int(pair[0]);var start=int(pair[1]);var duration=int(j.durations[track]);var legal=true
		if start<j.release or start+duration>j.deadline or (p.max_end>=0 and start+duration>p.max_end):continue
		var cost=int(j.costs[track])
		for prev in range(slots.size()):
			var other=slots[prev];cost+=int(p.jobs[prev].costs[other[0]])
			if track==other[0] and _overlap(start,duration,other[1],p.jobs[prev].durations[other[0]]):legal=false
			if track!=other[0] and not p.cross.is_empty() and start+p.cross[track]==other[1]+p.cross[other[0]]:legal=false
		if not legal or (p.max_cost>=0 and cost>p.max_cost):continue
		var next=slots.duplicate(true);next.append(pair)
		var result=_schedule_completion(s,next,index+1)
		if not result.is_empty():return result
	return []

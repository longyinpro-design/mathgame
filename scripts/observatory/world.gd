extends Node2D
const StarSkin = preload("res://scripts/cargo/skin.gd")
const Rules = preload("res://scripts/observatory/rules.gd")
const BRASS=Color("b79964")
const LIGHT=Color("f2cf88")
const TEAL=Color("83deeb")
var definition: Dictionary = {}
var state: Dictionary = {}
var presentation_paused = false
var selected = 0
var font: Font
var view_clock=0.0
var board_fingerprint=0
func _process(delta: float):
	if definition.is_empty() or state.is_empty():return
	var fingerprint=hash(state)
	if fingerprint!=board_fingerprint:board_fingerprint=fingerprint;view_clock=0.0
	if definition.mechanism=="finale" and not presentation_paused and Rules.new(definition).solved(state):
		view_clock=minf(view_clock+delta*2.0,23.0);queue_redraw()
func _ready(): font=StarSkin.face()
func label(t: String, at: Vector2, size: int=18, color: Color=Color("dfdfec")):
	if font==null: font=StarSkin.face()
	draw_string(font,at,t,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
static func shutter_rect(w: int,cell: int) -> Rect2:
	return Rect2(185+(cell%10)*57,280+w*160+floori(cell/10.0)*54,48,44)
static func route_points(count: int) -> Array:
	var points=[]
	for i in range(count):
		var a=TAU*i/count-PI/2
		points.append(Vector2(365,385)+Vector2(cos(a)*205,sin(a)*110))
	return points
static func network_points(p: Dictionary) -> Array:
	if p.nodes.size()==4: return [Vector2(180,285),Vector2(530,285),Vector2(530,495),Vector2(180,495)]
	var points=[Vector2(345,395)]
	for i in range(5):
		var a=TAU*i/5-PI/2
		points.append(Vector2(345,402)+Vector2(cos(a)*225,sin(a)*155))
	return points
static func cable_rect(p: Dictionary,e: int) -> Rect2:
	var pts=network_points(p);var edge=p.edges[e]
	var a: Vector2=pts[edge[0]];var b: Vector2=pts[edge[1]]
	var ratio=0.5
	if p.nodes.size()==4 and e>=4: ratio=0.34 if e==4 else 0.66
	var mid=a.lerp(b,ratio)
	return Rect2(mid-Vector2(28,14),Vector2(56,28))
func plate(rect: Rect2):
	draw_rect(Rect2(rect.position+Vector2(7,9),rect.size),Color("0a1120"))
	draw_rect(rect,BRASS);draw_rect(rect.grow(-5),Color("192c45"));draw_rect(rect.grow(-10),Color("233951"))
	for offset in [Vector2(8,8),Vector2(rect.size.x-8,8),Vector2(8,rect.size.y-8),rect.size-Vector2(8,8)]:
		draw_circle(rect.position+offset,2,Color("ead9a1"))
func character(at: Vector2, robe: Color):
	draw_ellipse_shadow(at+Vector2(0,25),Vector2(25,8))
	draw_rect(Rect2(at+Vector2(-16,-5),Vector2(32,31)),robe)
	draw_rect(Rect2(at+Vector2(-13,-29),Vector2(26,26)),Color("e5c198"))
	draw_rect(Rect2(at+Vector2(-16,-35),Vector2(32,11)),Color("e6d6b7"))
	draw_rect(Rect2(at+Vector2(-6,-18),Vector2(3,4)),Color("243046"));draw_rect(Rect2(at+Vector2(5,-18),Vector2(3,4)),Color("243046"))
	draw_rect(Rect2(at+Vector2(-13,25),Vector2(10,8)),Color("111d32"));draw_rect(Rect2(at+Vector2(4,25),Vector2(10,8)),Color("111d32"))
func draw_ellipse_shadow(at: Vector2, dimensions: Vector2):
	var points=PackedVector2Array()
	for i in range(16):points.append(at+Vector2(cos(TAU*i/16)*dimensions.x,sin(TAU*i/16)*dimensions.y))
	draw_colored_polygon(points,Color(0.02,0.04,0.09,0.65))
func apparatus():
	# Stepped pixel silhouettes, brass dome ribs, stone pier and telescope.
	draw_rect(Rect2(0,0,1280,720),Color("10192e"))
	for i in range(90):
		var at=Vector2((i*137+41)%1280,(i*83+23)%605)
		draw_rect(Rect2(at,Vector2(2,2)),Color("788da9"))
	draw_circle(Vector2(1120,93),54,Color("b9cde1"));draw_circle(Vector2(1140,75),53,Color("10192e"))
	for y in range(578,720,22):
		for x in range(-40,1280,96):
			draw_rect(Rect2(x+(24 if y%44==0 else 0),y,92,19),Color("29374e"))
	for x in [25,1208]:
		draw_rect(Rect2(x,180,42,430),Color("24334b"));draw_rect(Rect2(x+4,180,8,430),Color("60708c"))
		draw_rect(Rect2(x-7,575,56,29),BRASS)
	draw_arc(Vector2(640,560),587,PI,TAU,48,Color("465875"),15)
	draw_arc(Vector2(640,560),573,PI,TAU,48,BRASS,3)
	for x in [83,1185]:
		draw_rect(Rect2(x,208,8,360),BRASS)
		draw_circle(Vector2(x+4,228),8,LIGHT)
	# Physical telescope at back right; its feet contact the stone floor.
	draw_line(Vector2(1105,484),Vector2(1068,589),Color("6a7282"),8)
	draw_line(Vector2(1105,484),Vector2(1145,589),Color("6a7282"),8)
	draw_line(Vector2(1105,484),Vector2(1105,594),BRASS,6)
	draw_line(Vector2(1068,459),Vector2(1165,391),Color("625b55"),44)
	draw_line(Vector2(1068,453),Vector2(1165,385),BRASS,31)
	draw_circle(Vector2(1165,385),24,Color("d6bf87"));draw_circle(Vector2(1165,385),17,Color("34718a"));draw_circle(Vector2(1161,380),7,TEAL)
	character(Vector2(1172,561),Color("596d91"))
	character(Vector2(1013,568),Color("ba8158"))
func _draw():
	apparatus()
	if definition.is_empty() or state.is_empty(): return
	match definition.mechanism:
		"scale": draw_scale()
		"shutters": draw_shutters()
		"routes": draw_routes()
		"schedule": draw_schedule()
		"storm", "finale": draw_network()
	if Rules.new(definition).solved(state):
		for x in [87,1189]:
			draw_circle(Vector2(x,228),15,TEAL)
			draw_line(Vector2(x,228),Vector2(640,35),Color(0.5,0.85,0.95,0.35),7)
func draw_scale():
	var p=definition.params
	for base in [Vector2(150,500),Vector2(665,500)]:
		plate(Rect2(base+Vector2(-43,-282),Vector2(375,328)))
		for foot in [base+Vector2(-25,46),base+Vector2(310,46)]:
			draw_rect(Rect2(foot,Vector2(16,52)),Color("6c655b"))
		for i in range(9):
			draw_line(base+Vector2(i*35,0),base+Vector2(i*35,-256),Color("3e5874"),1)
			draw_line(base+Vector2(0,-i*32),base+Vector2(280,-i*32),Color("3e5874"),1)
			label(str(i),base+Vector2(i*35-5,23),16);label(str(i),base+Vector2(-25,-i*32+5),16)
	label("旧星图 · 每格1尺",Vector2(165,234),19)
	label("穹顶星盘 · %d:%d" % [p.num,p.den],Vector2(680,234),19)
	for grid in range(2):
		var base=Vector2(150,500) if grid==0 else Vector2(665,500)
		var points=p.source if grid==0 else state.points
		var origin=p.source_origin if grid==0 else p.origin
		draw_circle(base+Vector2(origin[0]*35,-origin[1]*32),9,LIGHT)
		for i in range(points.size()):
			var at=base+Vector2(points[i][0]*35,-points[i][1]*32)
			if i>0:
				var prev=points[i-1];draw_line(base+Vector2(prev[0]*35,-prev[1]*32),at,TEAL,3)
			draw_rect(Rect2(at-Vector2(7,7),Vector2(14,14)),LIGHT if i==selected else TEAL)
			label(str(i+1),at+Vector2(10,-8),20)
func draw_shutters():
	var p=definition.params
	for w in range(p.sizes.size()):
		plate(Rect2(160,245+w*160,620,139))
		var whole=int(p.sizes[w])-(p.blocked[w].size() if p.basis[w]=="remaining" else 0)
		label("镜窗%d · 整体%d格 · 目标%d%% · 已开%d格" % [w+1,whole,p.targets[w],state.open[w].size()],Vector2(180,270+w*160),20,LIGHT)
		for cell in range(p.sizes[w]):
			var rect=shutter_rect(w,cell)
			var lit=cell in state.open[w]
			draw_rect(rect,Color("151c2d"));draw_rect(rect.grow(-3),Color("f5cd7d") if lit else Color("57677c"))
			if lit:
				draw_rect(Rect2(rect.position,Vector2(7,44)),BRASS)
			else:
				for y in range(4):draw_line(rect.position+Vector2(4,8+y*9),rect.position+Vector2(44,8+y*9),Color("26364f"),3)
			if cell in p.blocked[w]:
				draw_line(rect.position,rect.end,Color("e89089"),3);draw_line(rect.position+Vector2(48,0),rect.position+Vector2(0,44),Color("e89089"),3)
			label(str(cell),rect.position+Vector2(17,29),17,Color("182940") if lit else Color("eef0e6"))
	label("点击百叶开闭 · 裂纹格不能打开",Vector2(180,570),20)
	if p.contiguous: label("连续一束光 · 改动按与初态不同的格数计算",Vector2(180,600),18,LIGHT)
func draw_routes():
	var p=definition.params; var pts=route_points(p.nodes.size())
	plate(Rect2(105,223,520,315));plate(Rect2(680,223,485,315))
	for edge in p.edges:
		var a:Vector2=pts[edge[0]];var b:Vector2=pts[edge[1]];var direction=(b-a).normalized()
		draw_line(a,b,Color("667c92"),2)
		var tip=a.lerp(b,0.64);draw_line(tip,tip-direction.rotated(0.6)*10,BRASS,3);draw_line(tip,tip-direction.rotated(-0.6)*10,BRASS,3)
	for i in range(1,state.draft.size()):draw_line(pts[state.draft[i-1]],pts[state.draft[i]],TEAL,7)
	for i in range(pts.size()):
		draw_circle(pts[i]+Vector2(3,6),30,Color("0c192b"));draw_circle(pts[i],29,BRASS);draw_circle(pts[i],24,Color("244157"))
		label(p.nodes[i],pts[i]+Vector2(-10,7),21,LIGHT)
		if i in state.draft: label(str(state.draft.find(i)+1),pts[i]+Vector2(22,-20),19,TEAL)
	label("已收藏 %d 条 · 按起步检查遗漏" % state.routes.size(),Vector2(695,247),19,LIGHT)
	for i in range(state.routes.size()):
		var names=[]
		for n in state.routes[i]:names.append(p.nodes[n])
		label("· "+"→".join(names),Vector2(695+floori(i/8.0)*230,278+(i%8)*31),18)
func draw_schedule():
	var p=definition.params
	plate(Rect2(440,237,770,326))
	for i in range(p.jobs.size()):
		var lines=[]
		for track in range(p.tracks):lines.append("轨%d:%d时/%d晶" % [track+1,p.jobs[i].durations[track],p.jobs[i].costs[track]])
		label("  "+"  ".join(lines),Vector2(65,317+i*78),17,LIGHT)
	for track in range(p.tracks):
		var base=Vector2(470,300+track*150)
		label("轨道%d" % [track+1],base+Vector2(0,-10),20,LIGHT)
		for time in range(p.horizon+1):
			draw_rect(Rect2(base+Vector2(time*52,0),Vector2(49,82)),Color("243b55"))
			label(str(time),base+Vector2(time*52+17,105),18)
		draw_line(base+Vector2(0,42),base+Vector2((p.horizon+1)*52-4,42),BRASS,6)
		for i in range(p.jobs.size()):
			var slot=state.slots[i]
			if slot[0]!=track:continue
			var at=base+Vector2(slot[1]*52,12+(i%2)*27);var width=p.jobs[i].durations[track]*52-6
			draw_rect(Rect2(at,Vector2(width,27)),TEAL if i==selected else Color("b89468"));label(p.jobs[i].name,at+Vector2(4,21),17,Color("142740"))
	if not p.cross.is_empty():label("交叉点：每艘离港后1时经过 · 不可同时到达",Vector2(455,592),19,LIGHT)
func draw_network():
	var p=definition.params;var pts=network_points(p);var r=Rules.new(definition)
	plate(Rect2(103,225,525,342))
	for i in range(p.edges.size()):
		var e=p.edges[i];var active=i in state.edges;var broken=definition.mechanism=="storm" and state.broken==i
		var a:Vector2=pts[e[0]];var b:Vector2=pts[e[1]]
		draw_line(a+Vector2(2,5),b+Vector2(2,5),Color("07131e"),7)
		draw_line(a,b,TEAL if active else Color("52677e"),5 if active else 2)
		var rect=cable_rect(p,i);draw_rect(rect,Color("823f46") if broken else Color("26485a") if active else Color("514e4c"));draw_rect(rect,BRASS,false,1)
		label("×" if broken else "%d/%d" % [e[2],e[3]],rect.position+Vector2(8,21),17,LIGHT)
		if definition.mechanism=="storm":label(str(i+1),rect.position+Vector2(-16,20),16,LIGHT)
	for i in range(pts.size()):
		draw_circle(pts[i]+Vector2(3,5),24,Color("0a1824"));draw_circle(pts[i],23,BRASS)
		draw_circle(pts[i],18,TEAL if r.distance(state.edges,0,i)<999 else Color("3c5167"))
		label(p.nodes[i],pts[i]+Vector2(-20,-29),19,LIGHT)
	label("线标：费用/航时 · 已用%d/%d晶" % [r.network_cost(state.edges),p.budget],Vector2(120,598),20,LIGHT)
	if definition.mechanism=="storm":
		plate(Rect2(730,240,425,135))
		label("守望者 · 第%d阶段" % [state.phase+1],Vector2(750,275),24,LIGHT)
		label("每条线都要真正留下退路" if state.phase==0 else "断线后：任意两塔最多2段",Vector2(750,312),20)
		label("迎风前≤10晶；迎风后最多加1条新线",Vector2(745,351),18)
	else:
		plate(Rect2(647,490,563,99))
		label("总发射通道 · 选船后点出发时刻",Vector2(665,479),19,LIGHT)
		for t in range(23):
			draw_rect(Rect2(665+t*23,515,22,62),Color("233e55"))
			if t%2==0:label(str(t),Vector2(665+t*23,606),16)
		for i in range(6):
			var duration=r.journey(state,i);var start=state.starts[i]
			if start<0 or duration>=999:continue
			var at=Vector2(665+start*23,516+(i%3)*19)
			draw_rect(Rect2(at,Vector2(mini(duration,23-start)*23-1,18)),TEAL if i==selected else Color("bc956e"));label(str(i+1),at+Vector2(3,15),15,Color("13263c"))
		if r.solved(state):draw_actual_departures()
		if state.starts[selected]>=0:label("当前船：%d时出发 → %d时到达" % [state.starts[selected],state.starts[selected]+r.journey(state,selected)],Vector2(670,635),18,TEAL)
func route_to(target: int) -> Array:
	var p=definition.params;var dist=[];var prev=[]
	for i in range(p.nodes.size()):dist.append(999);prev.append(-1)
	dist[0]=0
	for _pass in range(p.nodes.size()):
		for idx in state.edges:
			var e=p.edges[idx]
			if dist[e[0]]+e[3]<dist[e[1]]:dist[e[1]]=dist[e[0]]+e[3];prev[e[1]]=e[0]
			if dist[e[1]]+e[3]<dist[e[0]]:dist[e[0]]=dist[e[1]]+e[3];prev[e[0]]=e[1]
	var path=[target]
	while path[0]!=0 and prev[path[0]]>=0:path.push_front(prev[path[0]])
	return path if path[0]==0 else []
func journey_position(target: int, elapsed: float) -> Vector2:
	var pts=network_points(definition.params);var path=route_to(target)
	if path.is_empty():return pts[0]
	for i in range(1,path.size()):
		var duration=0.0
		for idx in state.edges:
			var e=definition.params.edges[idx]
			if (e[0]==path[i-1] and e[1]==path[i]) or (e[1]==path[i-1] and e[0]==path[i]):duration=e[3];break
		if elapsed<=duration:return pts[path[i-1]].lerp(pts[path[i]],clampf(elapsed/duration,0,1))
		elapsed-=duration
	return pts[path[-1]]
func draw_actual_departures():
	label("联合试航 · 第%.1f时" % view_clock,Vector2(725,232),18,TEAL)
	for i in range(6):
		if state.starts[i]<0 or view_clock<state.starts[i]:continue
		var at=journey_position(i,view_clock-state.starts[i])+Vector2(0,-8)
		draw_rect(Rect2(at+Vector2(-9,-5),Vector2(18,10)),LIGHT)
		draw_line(at+Vector2(-13,6),at+Vector2(13,6),TEAL,4)
		label(str(i+1),at+Vector2(-4,1),12,Color("122a41"))

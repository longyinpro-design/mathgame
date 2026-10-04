extends Node2D
const GardenSkin = preload("res://scripts/cargo/skin.gd")
const Rules = preload("res://scripts/fractions/rules.gd")
var definition: Dictionary = {}
var state: Dictionary = {}
var presentation_paused := false
var celebration := false
var font: Font
func _ready():
	font = GardenSkin.face()
func label(text: String, pos: Vector2, size: int=20, color: Color=Color("e5f9ed")):
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func _draw():
	if definition.is_empty() or state.is_empty(): return
	if font == null: font=GardenSkin.face()
	var rules = Rules.new(definition)
	var b: Dictionary = rules.projection(state)
	if b.is_empty(): return
	draw_rect(Rect2(0,0,1280,720),Color("122e3a"))
	for i in range(10):
		draw_line(Vector2(0,225+i*43),Vector2(1280,235+i*43),Color("234b59"),3)
	draw_rect(Rect2(22,202,1236,404),Color("1b4651"))
	for x in [34,1236]:
		draw_rect(Rect2(x,215,10,390),Color("c1b18b"))
		draw_line(Vector2(x-4,219),Vector2(x+15,219),Color("f1dfb1"),5)
	for i in range(15):
		var x := float((i*193)%1260)
		draw_circle(Vector2(x,615),24,Color("306358"))
		draw_line(Vector2(x,625),Vector2(x+13,595),Color("73a486"),3)
		draw_circle(Vector2(x+13,592),6,Color("e4b8c7"))
	# Water-garden companion, feet and reflection visibly contact the stone ledge.
	draw_set_transform(Vector2(1173,370))
	draw_ellipse_shape()
	draw_set_transform(Vector2.ZERO)
	if celebration:
		for i in range(10):
			draw_circle(Vector2(65+i*120,590),10,Color("e8c4d7"))
	if definition.mechanism == "mosaic":
		draw_rect(Rect2(50,209,910,198),Color("274e55"))
		draw_rect(Rect2(50,209,910,198),Color("6b8985"),false,3)
		for grain in range(64):
			var gx:=float(60+(grain*157)%888);var gy:=float(216+(grain*43)%181)
			draw_line(Vector2(gx,gy),Vector2(gx+8,gy-2),Color("355e62"),1)
		for row in range(1,3): draw_line(Vector2(52,210+row*64),Vector2(958,210+row*64),Color("315a5e"),1)
		for j in range(definition.params.targets.size()):
			var target: Array=definition.params.targets[j]
			var total:=0; var count:=0
			for tile in b.tiles:
				if tile.owner==j: total+=int(tile.amount); count+=1
			var x:=65+j*225
			draw_rect(Rect2(x,427,200,63),Color("386b6f"))
			draw_rect(Rect2(x,478-min(45,total*2),200,min(45,total*2)),Color("58b9bb"))
			label("%d格 / %d格"%[total,target[1]],Vector2(x+8,453))
			label("%s · %d片%s"%["任意整体" if target[0]<0 else "整体"+"甲乙"[target[0]],count," / "+str(definition.params.counts[j]) if definition.params.counts[j]>=0 else ""],Vector2(x+8,481),17)
		for i in range(b.tiles.size()):
			var tile: Dictionary=b.tiles[i]
			var x:=float(63+(i%8)*112);var y:=float(281+(i/8)*60)
			draw_rect(Rect2(x-3,y-61,102,44),Color("3c7275"))
			label("%d/%d %s"%[tile.amount,definition.params.units[tile.unit],"甲乙"[tile.unit]],Vector2(x+3,y-32),19)
			draw_rect(Rect2(x,y,98,10),Color("142e38"))
			draw_rect(Rect2(x,y,98.0*tile.amount/definition.params.units[tile.unit],10),Color("6ed6cf") if tile.unit==0 else Color("d5b1e6"))
			for tick in range(1,int(definition.params.units[tile.unit])):
				var tx: float =x+98.0*tick/definition.params.units[tile.unit]
				draw_line(Vector2(tx,y),Vector2(tx,y+10),Color("214554"),1)
			label("水台" if b.tiles[i].owner<0 else "→花圃%d"%(b.tiles[i].owner+1),Vector2(67+(i%8)*112,275+(i/8)*60),16)
		label("切片仍属于原来的整体",Vector2(974,390),18)
	else:
		if definition.mechanism != "reverse":
			for e in range(definition.params.edges.size()):
				var edge: Array = definition.params.edges[e]
				var start:=Vector2(195+edge[0]*275,410)
				var end:=Vector2(195+edge[1]*275,410)
				var y:=225+e*6
				var channel:=PackedVector2Array([start,Vector2(start.x,y),Vector2(end.x,y),end])
				draw_polyline(channel,Color("b6a785"),12)
				draw_polyline(channel,Color("63d1d1") if e in b.gates else Color("264c60"),5)
				draw_circle(Vector2((start.x+end.x)/2,y),8,Color("cfb886"))
		var goal: Array=definition.params.goals[b.stage] if definition.mechanism=="guardian" else definition.params.goal
		for i in range(b.water.size()):
			var x:=90+i*275
			var capacity: int = definition.params.capacity[i] if definition.params.has("capacity") else 24
			draw_rect(Rect2(x,280,210,160),Color("627d85"))
			draw_rect(Rect2(x+9,288,192,143),Color("183c4c"))
			var height:=130.0*float(b.water[i])/float(capacity)
			draw_rect(Rect2(x+10,430-height,190,height),Color("56b8c5"))
			var mark:=430-130.0*float(goal[i])/float(capacity)
			draw_line(Vector2(x,mark),Vector2(x+210,mark),Color("eacb83"),3)
			draw_rect(Rect2(x-4,241,234,32),Color("173b46"))
			label("池%d：%d格 → %d格"%[i+1,b.water[i],goal[i]],Vector2(x,265),21)
			label("整体 %d 格"%definition.params.units[i],Vector2(x+35,462),18)
		if definition.mechanism=="reverse":
			var text:="顺序："
			for g in definition.params.gifts: text+="池%d给池%d自身%d/%d  "%[g[0]+1,g[1]+1,g[2],g[3]]
			label(text,Vector2(60,575),21)
		else:
			draw_rect(Rect2(53,580,580,25),Color("173b46"))
			label("已放水 %d / %d 拍"%[b.pulses,definition.params.max_pulses],Vector2(60,600),18)
			if definition.mechanism=="guardian": label("守庭试炼 %d / %d"%[b.stage+1,definition.params.goals.size()],Vector2(390,600),18)

func draw_ellipse_shape():
	var lift:=160 if definition.mechanism == "mosaic" else 0
	draw_set_transform(Vector2(1173,389+lift),0,Vector2(1.4,0.35))
	draw_circle(Vector2.ZERO,27,Color(0.02,0.10,0.12,0.6))
	draw_set_transform(Vector2(1173,358+lift))
	draw_colored_polygon(PackedVector2Array([Vector2(0,-35),Vector2(-24,-7),Vector2(-28,10),Vector2(-17,28),Vector2(17,28),Vector2(28,10),Vector2(24,-7)]),Color("9edcce"))
	draw_circle(Vector2(-9,4),3,Color("173742")); draw_circle(Vector2(9,4),3,Color("173742"))
	draw_arc(Vector2(0,7),7,0,PI,12,Color("173742"),2)
	draw_circle(Vector2(-19,12),4,Color("e6b9b8"));draw_circle(Vector2(19,12),4,Color("e6b9b8"))
	draw_set_transform(Vector2.ZERO)
	label("水沫",Vector2(1151,414+lift),19)

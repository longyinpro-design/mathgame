extends Node2D
const Art = preload("res://scripts/ui/late_island_art.gd")
const GardenSkin = preload("res://scripts/cargo/skin.gd")
const Rules = preload("res://scripts/fractions/rules.gd")
var definition: Dictionary = {}
var state: Dictionary = {}
var presentation_paused := false
var celebration := false
var font: Font
func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = GardenSkin.face()
func label(text: String, pos: Vector2, size: int=20, color: Color=Color("e5f9ed")):
	draw_string_outline(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,3,Color("18333d"))
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func _draw():
	if definition.is_empty() or state.is_empty(): return
	if font == null: font=GardenSkin.face()
	var rules = Rules.new(definition)
	var b: Dictionary = rules.projection(state)
	if b.is_empty(): return
	Art.background(self,"FW")
	# Generated cast stays outside pool/piece hit targets and the shared footer.
	var cast = "shuimo_joy" if celebration else "shuimo"
	var foot = Vector2(1173,586) if definition.mechanism == "mosaic" else Vector2(1192,455)
	var width = 72.0 if definition.mechanism == "mosaic" else 62.0
	if definition.id == "FW17": cast = "floodkeeper"; foot = Vector2(1170,452); width = 126
	elif definition.id == "FW18": cast = "lotus_guardian"; foot = Vector2(1189,464); width = 68
	Art.sprite(self,cast,foot,width)
	if celebration:
		for i in range(10):
			draw_circle(Vector2(65+i*120,590),10,Color("e8c4d7"))
	if definition.mechanism == "mosaic":
		Art.panel(self,"water_panel",Rect2(50,209,910,198))
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
			Art.panel(self,"water_panel",Rect2(x,427,200,63))
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
			Art.panel(self,"water_panel",Rect2(x-6,274,222,172))
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

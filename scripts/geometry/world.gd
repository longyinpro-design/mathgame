extends Node2D
const R=preload("res://scripts/geometry/rules.gd")
var definition: Dictionary={}
var state: Dictionary={}
var presentation_paused=false
var cached_rules: RefCounted
var cached_id=""
const ORIGIN=Vector2(100,264)
const CELL=55.0
func _draw():
	draw_rect(Rect2(0,0,1280,720),Color("172c43"))
	for i in range(8):
		var x=i*195.0-80
		draw_colored_polygon(PackedVector2Array([Vector2(x,490),Vector2(x+115,105+(i%3)*32),Vector2(x+270,490)]),Color("2b435b") if i%2 else Color("345269"))
		draw_colored_polygon(PackedVector2Array([Vector2(x+82,208+(i%3)*32),Vector2(x+115,105+(i%3)*32),Vector2(x+164,225+(i%3)*32),Vector2(x+122,199+(i%3)*32)]),Color("a6c2bf"))
	draw_rect(Rect2(0,510,1280,210),Color("344b4c"))
	for i in range(15):
		var x=i*97.0
		draw_line(Vector2(x,570),Vector2(x+60,620),Color("65726a"),3)
	# Dry-stone courses, wood grain and river-bank terraces.
	for row in range(4):
		for col in range(17):
			var pos=Vector2(col*83+(row%2)*31,527+row*24)
			draw_rect(Rect2(pos,Vector2(77,20)),Color("66776b") if (row+col)%3 else Color("788777"))
			draw_line(pos+Vector2(7,3),pos+Vector2(67,3),Color("90a08a"),2)
	# Timber tool bench with a saw and pegs, grounding the manipulable stone tray.
	draw_rect(Rect2(582,240,378,363),Color("403f39"))
	for row in range(9):
		var y=248+row*38
		draw_rect(Rect2(590,y,362,34),Color("71604b") if row%2 else Color("7b6850"))
		draw_line(Vector2(610,y+9),Vector2(922,y+13),Color("91775a"),2)
		for x in [600,940]:draw_circle(Vector2(x,y+17),3,Color("383b34"))
	# Companion has a full grounded silhouette and angular crystal tail.
	draw_set_transform(Vector2(1090,573),0,Vector2(1.3,0.35));draw_circle(Vector2.ZERO,49,Color(0.08,0.12,0.15,0.5));draw_set_transform(Vector2.ZERO)
	draw_colored_polygon(PackedVector2Array([Vector2(1110,530),Vector2(1165,488),Vector2(1182,530),Vector2(1135,562)]),Color("b58253"))
	draw_colored_polygon(PackedVector2Array([Vector2(1165,488),Vector2(1182,530),Vector2(1152,532)]),Color("e8d19b"))
	draw_rect(Rect2(1065,503,51,60),Color("c79560"));draw_rect(Rect2(1077,512,25,42),Color("efd49c"))
	draw_rect(Rect2(1060,552,21,23),Color("715749"));draw_rect(Rect2(1100,552,21,23),Color("715749"))
	draw_line(Vector2(1058,515),Vector2(1039,541),Color("d1a06b"),13)
	draw_line(Vector2(1118,515),Vector2(1134,537),Color("d1a06b"),13)
	# Terraced workshop and the geometry fox companion.
	draw_rect(Rect2(65,231,470,370),Color("334b56"))
	draw_rect(Rect2(68,235,464,360),Color("425d65"),false,3)
	draw_circle(Vector2(1090,491),42,Color("deaa69"))
	draw_colored_polygon(PackedVector2Array([Vector2(1054,474),Vector2(1060,422),Vector2(1090,458)]),Color("edc789"))
	draw_colored_polygon(PackedVector2Array([Vector2(1100,454),Vector2(1131,425),Vector2(1128,484)]),Color("edc789"))
	draw_circle(Vector2(1075,480),5,Color("243441"));draw_circle(Vector2(1105,480),5,Color("243441"))
	draw_line(Vector2(1082,504),Vector2(1099,504),Color("765548"),3)
	if definition.is_empty() or state.is_empty(): return
	if cached_id!=definition.id:
		cached_rules=R.new(definition);cached_id=definition.id
	var r=cached_rules;var p=definition.params
	var target=r.target(state)
	for y in range(p.h):
		for x in range(p.w):
			var c=[x,y];var rect=Rect2(ORIGIN+Vector2(x,y)*CELL,Vector2.ONE*(CELL-3))
			var color=Color("718477")
			if r.is_tile(): color=Color("b8bda2") if c in target else Color("324853")
			elif c in state.cells: color=Color("72a890")
			if c in p.get("blocked",[]) or (r.kind=="architect_boss" and state.proofs.size()==1 and c==r.rock(state.proofs[0])): color=Color("252d38")
			draw_rect(rect,color)
			if c in p.get("seeds",[]) or c in p.get("required",[]):draw_circle(rect.get_center(),8,Color("ffd483"))
			if not r.is_tile() and c in state.cells:
				draw_line(rect.get_center()+Vector2(0,12),rect.get_center()+Vector2(0,-9),Color("d8edbb"),3)
				draw_circle(rect.get_center()+Vector2(0,-9),6,Color("f1d09c"))
	if r.is_tile():
		var colors=[Color("ce9264"),Color("70acb4"),Color("b69cc8"),Color("b7bd74")]
		for i in range(state.pieces.size()):
			var q=state.pieces[i];var shape=r.transformed(r.shapes(state)[i],int(q.r),int(q.f))
			var step=CELL if q.x>=0 else 22.0
			var origin=ORIGIN+Vector2(q.x,q.y)*CELL if q.x>=0 else Vector2(615+(i%2)*170,294+floor(i/2.0)*118)
			for c in shape:
				var rect=Rect2(origin+Vector2(c[0],c[1])*step,Vector2.ONE*(step-3))
				draw_rect(rect,colors[i%4]);draw_rect(rect.grow(-4),Color(1,1,1,0.16),false,2)
		if p.has("cut_shapes") and not state.cut:
			var cuts=[3] if definition.id=="GV10" else [2,4]
			for cut in cuts:
				var x=615+cut*22-2
				draw_dashed_line(Vector2(x,290),Vector2(x,321),Color("fff0bf"),3,4)
	else:
		# Only exposed edges get a fence stroke; shared edges disappear from the count.
		for cell in state.cells:
			var at=ORIGIN+Vector2(cell[0],cell[1])*CELL
			if not [cell[0],cell[1]-1] in state.cells:draw_line(at,at+Vector2(CELL-3,0),Color("edc98b"),3)
			if not [cell[0],cell[1]+1] in state.cells:draw_line(at+Vector2(0,CELL-3),at+Vector2(CELL-3,CELL-3),Color("edc98b"),3)
			if not [cell[0]-1,cell[1]] in state.cells:draw_line(at,at+Vector2(0,CELL-3),Color("edc98b"),3)
			if not [cell[0]+1,cell[1]] in state.cells:draw_line(at+Vector2(CELL-3,0),at+Vector2(CELL-3,CELL-3),Color("edc98b"),3)
		var mode=p.get("mode","")
		if mode in ["vertical","both"]:draw_dashed_line(ORIGIN+Vector2(p.w*CELL/2,-9),ORIGIN+Vector2(p.w*CELL/2,p.h*CELL+9),Color("ffd483"),3,7)
		if mode=="both":draw_dashed_line(ORIGIN+Vector2(-9,p.h*CELL/2),ORIGIN+Vector2(p.w*CELL+9,p.h*CELL/2),Color("ffd483"),3,7)
		if mode=="diagonal":draw_dashed_line(ORIGIN,ORIGIN+Vector2(p.w,p.h)*CELL,Color("ffd483"),3,7)
		if mode=="half":draw_arc(ORIGIN+Vector2(p.w,p.h)*CELL/2,20,0,TAU,30,Color("ffd483"),3)

	if r.kind=="mirror_boss":
		for shield in range(2):
			var base=Vector2(1008+shield*92,316)
			draw_rect(Rect2(base-Vector2(8,8),Vector2(75,110)),Color("596b6c"))
			if shield<state.proofs.size():
				var proof={"pieces":state.proofs[shield],"cells":[],"cut":false,"proofs":[]}
				for cell in r.occupied(proof):draw_rect(Rect2(base+Vector2(cell[0],cell[1])*17,Vector2(14,14)),Color("e8c986"))
	# Completion lights reflect the actual solved board; no reference solution is drawn.
	if r.solved(state):
		for i in range(7):
			var x=50+i*177
			draw_line(Vector2(x,611),Vector2(x,577),Color("b59864"),4)
			draw_circle(Vector2(x,572),8,Color("ffe7a0"))
			draw_circle(Vector2(x,572),15,Color(1.0,0.84,0.43,0.16))

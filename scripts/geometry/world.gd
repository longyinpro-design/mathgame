extends Node2D
const Art=preload("res://scripts/ui/late_island_art.gd")
const R=preload("res://scripts/geometry/rules.gd")
var definition: Dictionary={}
var state: Dictionary={}
var presentation_paused=false
var cached_rules: RefCounted
var cached_id=""
const ORIGIN=Vector2(100,264)
const CELL=55.0
func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
func _draw():
	Art.background(self,"GV")
	Art.panel(self,"wood_panel",Rect2(582,240,378,363))
	Art.panel(self,"wood_panel",Rect2(65,231,470,370))
	var cast = "lingjiao"
	if not definition.is_empty():
		if definition.mechanism == "mirror_boss": cast = "mirror_guardian"
		elif definition.mechanism == "architect_boss": cast = "valley_architect"
		elif not state.is_empty() and R.new(definition).solved(state): cast = "lingjiao_joy"
	Art.sprite(self,cast,Vector2(1102,548 if cast in ["mirror_guardian","valley_architect"] else 578),156 if cast in ["mirror_guardian","valley_architect"] else 112)
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
			Art.surface(self,"blocked_tile" if color == Color("252d38") else "stone_tile",rect,color)
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
				Art.surface(self,"stone_tile",rect,colors[i%4]);draw_rect(rect.grow(-4),Color(1,1,1,0.24),false,2)
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
		draw_rect(Rect2(984,258,250,45),Color(0.10,0.16,0.15,0.92))
		for shield in range(2):
			var base=Vector2(1008+shield*92,316)
			Art.panel(self,"wood_panel",Rect2(base-Vector2(8,8),Vector2(75,110)))
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

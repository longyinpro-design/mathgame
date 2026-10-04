extends "res://scripts/archipelago/level_host.gd"
const Catalog = preload("res://scripts/observatory/catalog.gd")
const Rules = preload("res://scripts/observatory/rules.gd")
const World = preload("res://scripts/observatory/world.gd")
var selected = 0
func configure():
	definition = Catalog.definition(level_id); rules = Rules.new(definition); world_script = World
func select_piece(i: int):
	selected=i; refresh()
func build_board():
	var p=definition.params
	match definition.mechanism:
		"scale":
			for i in range(board.points.size()):
				add_button("star_%d" % i,"★ %d%s" % [i+1," 已选" if selected==i else ""],Rect2(75+i*130,550,120,44),select_piece.bind(i))
			for x in range(9):
				for y in range(9):
					add_hotspot("grid_%d_%d" % [x,y],Rect2(665+x*35-15,500-y*32-15,30,30),func(): act({"type":"place","piece":selected,"x":x,"y":y}),"放置星点 (%d,%d)" % [x,y])
		"shutters":
			for w in range(p.sizes.size()):
				for cell in range(p.sizes[w]):
					if cell in p.blocked[w]: continue
					add_hotspot("shutter_%d_%d" % [w,cell],World.shutter_rect(w,cell),func(): act({"type":"toggle","window":w,"cell":cell}),"开闭第%d窗第%d格" % [w+1,cell])
		"routes":
			var points=World.route_points(p.nodes.size())
			for node in range(p.nodes.size()):
				add_hotspot("node_%d" % node,Rect2(points[node]-Vector2(33,33),Vector2(66,66)),func(): act({"type":"append","node":node}),"接到"+p.nodes[node])
			add_button("record_route","收藏此路",Rect2(150,550,180,44),func(): act({"type":"record"}),true)
			add_button("clear_route","清空重画",Rect2(350,550,180,44),func(): act({"type":"clear"}))
		"schedule":
			for i in range(p.jobs.size()):
				add_button("job_%d" % i,"%s · r%d d%d%s" % [p.jobs[i].name,p.jobs[i].release,p.jobs[i].deadline," ◀" if selected==i else ""],Rect2(65,250+i*78,310,45),select_piece.bind(i))
			for track in range(p.tracks):
				for time in range(p.horizon+1):
					add_hotspot("time_%d_%d" % [track,time],Rect2(470+time*52,300+track*150,49,82),func(): act({"type":"schedule","job":selected,"track":track,"start":time}),"轨%d，%d时出发" % [track+1,time])
		"storm", "finale":
			for e in range(p.edges.size()):
				add_hotspot("cable_%d" % e,World.cable_rect(p,e),func(): act({"type":"cable","edge":e}),"切换线%d，费用%d，航时%d" % [e+1,p.edges[e][2],p.edges[e][3]])
			if definition.mechanism=="storm":
				add_button("call_storm","迎接星风" if board.phase==0 else "星风已切断线%d" % [board.broken+1],Rect2(755,405,365,54),func(): act({"type":"storm"}),true)
			else:
				for i in range(6):
					var duration=rules.journey(board,i)
					var status="未接通" if duration>=999 else "航程%d时" % duration
					add_button("job_%d" % i,"%s · %s%s" % [p.jobs[i].name,status," ◀" if selected==i else ""],Rect2(655+(i%2)*285,250+floori(i/2.0)*75,275,52),select_piece.bind(i))
				for time in range(p.horizon+1):
					add_hotspot("depart_%d" % time,Rect2(665+time*23,515,22,62),func(): act({"type":"depart","job":selected,"start":time}),"%d时出发" % time)
func sync_world():
	world.selected = selected

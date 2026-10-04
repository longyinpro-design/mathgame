extends "res://scripts/archipelago/level_host.gd"
const Catalog = preload("res://scripts/fractions/catalog.gd")
const Rules = preload("res://scripts/fractions/rules.gd")
const World = preload("res://scripts/fractions/world.gd")
var selected_tile := -1
var selected_pool := -1
func configure():
	definition = Catalog.definition(level_id)
	rules = Rules.new(definition)
	world_script = World
func build_board():
	var b: Dictionary = rules.projection(board)
	if definition.mechanism == "mosaic":
		if selected_tile >= b.tiles.size(): selected_tile = -1
		for i in range(b.tiles.size()):
			var tile: Dictionary = b.tiles[i]
			var rect := Rect2(60+(i%8)*112,220+(i/8)*60,102,44)
			add_button("tile_%d"%i,("◆ " if selected_tile == i else "")+"%d/%d %s"%[tile.amount,definition.params.units[tile.unit],"甲乙"[tile.unit]],rect,func(): selected_tile=i; refresh())
		for j in range(definition.params.targets.size()):
			add_button("bed_%d"%j,"放到花圃 %d"%(j+1),Rect2(65+j*225,498,200,48),func():
				if selected_tile >= 0: act({"type":"place","tile":selected_tile,"owner":j}))
		for k in range(definition.params.splits.size()):
			var parts: int = definition.params.splits[k]
			add_button("split_%d"%parts,"等分 %d 片"%parts,Rect2(975,247+k*62,218,48),func():
				if selected_tile >= 0:
					var chosen := selected_tile; selected_tile=-1
					act({"type":"split","tile":chosen,"parts":parts}))
		add_button("return","放回水台",Rect2(975,410,218,48),func():
			if selected_tile >= 0: act({"type":"place","tile":selected_tile,"owner":-1}))
	elif definition.mechanism == "reverse":
		for i in range(b.water.size()):
			add_button("pool_%d"%i,("取水自 " if selected_pool == i else "选择池 ")+str(i+1),Rect2(95+i*290,478,235,48),func():
				if selected_pool < 0: selected_pool=i; refresh()
				else:
					var source := selected_pool; selected_pool=-1
					act({"type":"shift","source":source,"target":i}))
		add_button("release","依次开闸放水",Rect2(940,490,260,48),func(): act({"type":"release"}),true)
	else:
		for i in range(definition.params.edges.size()):
			var edge: Array = definition.params.edges[i]
			var locked: bool = i in rules.blocked(b)
			add_button("gate_%d"%i,("封闭 " if locked else "● 开 " if i in b.gates else "○ 关 ")+"%d→%d ·%d"%[edge[0]+1,edge[1]+1,edge[2]],Rect2(52+(i%4)*235,480+(i/4)*54,222,44),func(): act({"type":"gate","edge":i}))
		add_button("pulse","水流一拍",Rect2(1010,480,220,48),func(): act({"type":"pulse"}),true)
		if definition.mechanism == "guardian": add_button("checkpoint","守住本轮",Rect2(1010,541,220,48),func(): act({"type":"checkpoint"}),true)

func sync_world():
	world.celebration = stage in ["outcome","complete"]

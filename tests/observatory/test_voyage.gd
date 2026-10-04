extends SceneTree
const C=preload("res://scripts/observatory/catalog.gd")
const R=preload("res://scripts/observatory/rules.gd")
const W=preload("res://scripts/observatory/world.gd")
var failures=0
func ck(ok: bool,text: String):
	if not ok:failures+=1;push_error(text)
func _initialize():
	var fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/observatory/witnesses.json"))
	var d=C.definition("SO18");var r=R.new(d);var w=W.new();w.definition=d
	for example in fixtures.SO18.networks:
		var s=r.fresh()
		for edge in example.edges:s=r.apply(s,{"type":"cable","edge":edge})
		for i in range(6):s=r.apply(s,{"type":"depart","job":i,"start":example.starts[i]})
		ck(r.solved(s),"independent network should solve")
		w.state=s
		for target in range(6):
			var path=w.route_to(target);var duration=0
			ck(path[0]==0 and path[-1]==target,"rendered actual endpoints")
			for i in range(1,path.size()):
				var found=false
				for edge in s.edges:
					var e=d.params.edges[edge]
					if (e[0]==path[i-1] and e[1]==path[i]) or (e[1]==path[i-1] and e[0]==path[i]):found=true;duration+=int(e[3]);break
				ck(found,"rendered voyage uses only player-built edge")
			ck(maxi(1,duration)==example.durations[target],"rendered shortest path matches independent Floyd oracle")
			var pts=W.network_points(d.params)
			ck(w.journey_position(target,0).is_equal_approx(pts[0]),"departure at true hub")
			ck(w.journey_position(target,example.durations[target]).is_equal_approx(pts[target]),"arrival at intended island")
	w._process(0.5);var clock_before=w.view_clock;w.presentation_paused=true;w._process(1)
	ck(w.view_clock==clock_before,"paused voyage freezes")
	w.free()
	print("OBSERVATORY VOYAGE: ",fixtures.SO18.networks.size()," independently certified networks; ",failures," failures");quit(1 if failures else 0)

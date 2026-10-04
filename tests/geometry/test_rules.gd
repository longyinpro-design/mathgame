extends SceneTree
const C=preload("res://scripts/geometry/catalog.gd")
const R=preload("res://scripts/geometry/rules.gd")
var failures: Array=[]
func check(ok: bool, text: String):
	if not ok: failures.append(text);push_error(text)
func _initialize():
	var witnesses=preload("res://scripts/content/content_catalog.gd").normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/geometry/witnesses.json")))
	for id in C.ids():
		var d=C.definition(id);var r=R.new(d);var s=r.fresh()
		check(r.validate(s),id+" fresh");check(not r.solved(s),id+" initially unsolved")
		check(not r.feedback(s).is_empty(),id+" feedback")
		var invalid=s.duplicate(true);invalid["won"]=true
		check(not r.validate(invalid),id+" closed schema")
		check(r.apply(s,{"type":"win"}).is_empty(),id+" cannot bypass")
		check(r.apply(s,{"type":"toggle","x":NAN,"y":0}).is_empty(),id+" rejects NaN")
		check(r.apply(s,{"type":"place","piece":-1,"x":0,"y":0}).is_empty(),id+" rejects bad owner")
		for action in witnesses[id]:
			var before=s.duplicate(true);var n=r.apply(s,action)
			check(s==before,id+" immutable")
			check(not n.is_empty(),id+" action "+str(action))
			if n.is_empty():break
			s=n
			check(r.validate(JSON.parse_string(JSON.stringify(s))),id+" JSON roundtrip")
		check(r.solved(s),id+" complete")
		if id=="GV17":
			var bad=s.duplicate(true);bad.proofs[0][0].x+=1
			check(not r.validate(bad),"GV17 forged seal")
		if id=="GV18":
			var bad=s.duplicate(true);bad.proofs[0]=[[0,0]]
			check(not r.validate(bad),"GV18 forged foundation")
		for tier in range(1,5):check(not r.hint(s,tier).is_empty(),id+" hint")
	print("Geometry rule suite: %d failures, 18 action-completed levels"%failures.size())
	quit(1 if not failures.is_empty() else 0)

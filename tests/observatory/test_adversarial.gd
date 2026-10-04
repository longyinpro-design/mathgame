extends SceneTree
const C=preload("res://scripts/observatory/catalog.gd")
const R=preload("res://scripts/observatory/rules.gd")
var failures=0
func ck(ok: bool, message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():
	for id in C.ids():
		var r=R.new(C.definition(id));var s=r.fresh()
		for bad in [null,[],{},true,0,"won"]:ck(not r.validate(bad),id+" reject wrong root")
		for action in [{},{"type":true},{"type":"solved"},{"type":"storm","phase":1}]:ck(r.apply(s,action).is_empty(),id+" bad action")
		if r.family=="scale":
			for value in [NAN,INF,-1,9,true,1.5,"2"]:
				var n=s.duplicate(true);n.points[0][0]=value;ck(not r.validate(n),id+" invalid coordinate")
		elif r.family=="shutters":
			var n=s.duplicate(true);n.open[0]=[0,0];ck(not r.validate(n),id+" duplicate pane")
			ck(r.apply(s,{"type":"toggle","window":0,"cell":-1}).is_empty(),id+" negative pane")
			if id=="SO06":ck(r.apply(s,{"type":"toggle","window":0,"cell":0}).is_empty(),"broken pane forbidden")
		elif r.family=="routes":
			ck(r.apply(s,{"type":"record"}).is_empty(),id+" empty route cannot record")
			var first=r.apply(s,{"type":"append","node":r.p.starts[0]})
			ck(not first.is_empty(),id+" start legal")
			ck(r.apply(first,{"type":"append","node":r.p.starts[0]}).is_empty(),id+" no repeated vertex")
			var n=s.duplicate(true);n.routes=[[0,0]];ck(not r.validate(n),id+" forged route reject")
		elif r.family=="schedule":
			var n=s.duplicate(true);n.slots[0]=[-1,0];ck(not r.validate(n),id+" partial missing slot")
			ck(r.apply(s,{"type":"schedule","job":0,"track":r.p.tracks,"start":0}).is_empty(),id+" unknown track")
			for i in range(r.p.jobs.size()):s=r.apply(s,{"type":"schedule","job":i,"track":0,"start":0})
			ck(not r.solved(s),id+" collision not solved")
		elif r.family=="storm":
			ck(r.apply(s,{"type":"storm"}).is_empty(),"storm cannot advance empty network")
			var n=s.duplicate(true);n.phase=1;n.before=[0,1,2,3];n.broken=3;ck(not r.validate(n),"forged storm branch reject")
		elif r.family=="finale":
			for i in range(6):s=r.apply(s,{"type":"depart","job":i,"start":i})
			ck(not r.solved(s),"arithmetic timetable cannot bypass disconnected route")
			for i in range(5):s=r.apply(s,{"type":"cable","edge":i})
			ck(not r.solved(s),"all direct routes exceed real budget")
	print("OBSERVATORY ADVERSARIAL: ",failures," failures");quit(1 if failures else 0)

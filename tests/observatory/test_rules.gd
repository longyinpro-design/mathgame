extends SceneTree
const Catalog=preload("res://scripts/observatory/catalog.gd")
const Rules=preload("res://scripts/observatory/rules.gd")
var failures=0
func check(ok: bool, message: String):
	if not ok: failures+=1; push_error(message)
func _initialize():
	var fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/observatory/witnesses.json"))
	for id in Catalog.ids():
		var d=Catalog.definition(id); var r=Rules.new(d); var s=r.fresh()
		check(r.validate(s),id+" fresh")
		check(not r.solved(s),id+" fresh unsolved")
		check(not r.feedback(s).is_empty(),id+" feedback")
		var bad=s.duplicate(true);bad["cheat"]=true;check(not r.validate(bad),id+" schema closed")
		check(r.apply(s,{"type":"win"}).is_empty(),id+" no win bypass")
		var cases=[fixtures[id].actions]
		cases.append_array(fixtures[id].alternates)
		for actions in cases:
			s=r.fresh()
			for a in actions:
				var old=s.duplicate(true); var hostile=a.duplicate(true); hostile["extra"]=1
				check(r.apply(s,hostile).is_empty(),id+" unknown action key")
				var next=r.apply(s,a)
				check(s==old,id+" immutable")
				check(not next.is_empty(),id+" action "+str(a))
				if next.is_empty(): break
				check(r.validate(next),id+" next validated")
				s=next
				check(r.validate(JSON.parse_string(JSON.stringify(s))),id+" JSON round trip")
			check(r.solved(s),id+" oracle completion "+r.feedback(s))
		for tier in range(1,5):check(not r.hint(r.fresh(),tier).is_empty(),id+" hint")
		print(id+" tested")
	print("OBSERVATORY RULES: ",failures," failures")
	quit(1 if failures else 0)

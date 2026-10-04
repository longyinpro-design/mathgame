extends SceneTree
const Catalog = preload("res://scripts/fractions/catalog.gd")
const Rules = preload("res://scripts/fractions/rules.gd")
var checks := 0
func check(ok: bool, note: String):
	checks += 1
	if not ok:
		push_error(note)
		quit(1)
func _init():
	var solutions: Dictionary = Catalog.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fractions/solutions.json")))
	for id in Catalog.ids():
		var d: Dictionary = Catalog.definition(id)
		var r = Rules.new(d)
		var state: Dictionary = r.fresh()
		check(r.validate(state),id+" fresh")
		check(not r.solved(state),id+" must begin unsolved")
		check(not r.feedback(state).is_empty(),id+" feedback")
		check(not r.validate({"actions":[],"won":true}),id+" closed schema")
		check(not r.validate({"actions":[{"type":"win"}]}),id+" no bypass")
		check(not r.validate({"actions":[{"type":"gate","edge":NAN}]}),id+" finite")
		check(r.apply(state,{"type":"pulse","extra":true}).is_empty(),id+" action closed schema")
		for a in solutions[id]:
			var before := state.duplicate(true)
			var copy: Dictionary = a.duplicate(true)
			var next: Dictionary = r.apply(state,a)
			check(state==before and a==copy,id+" immutable")
			check(not next.is_empty() and r.validate(next),id+" legal "+str(a))
			state=next
			var recovered: Dictionary = JSON.parse_string(JSON.stringify(state))
			check(r.validate(recovered),id+" json roundtrip")
		check(r.solved(state),id+" solved")
		check(r.solved(JSON.parse_string(JSON.stringify(state))),id+" solved after JSON")
		check(not r.apply(state,{"type":"place","tile":999,"owner":0}),id+" invalid index")
		for tier in range(1,5): check(not r.hint(state,tier).is_empty(),id+" hint")
		print(id+" RULES PASS")
	# Equivalent partitions and reversed placement ordering must also pass.
	var r = Rules.new(Catalog.definition("FW01"));var s=r.fresh()
	s=r.apply(s,{"type":"split","tile":0,"parts":2})
	s=r.apply(s,{"type":"split","tile":0,"parts":3})
	s=r.apply(s,{"type":"place","tile":0,"owner":1})
	for i in range(1,4):s=r.apply(s,{"type":"place","tile":i,"owner":0})
	check(r.solved(s),"alternate equivalent partition")
	print("FRACTIONS PASS ",checks," checks")
	quit()

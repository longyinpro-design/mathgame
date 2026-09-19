extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func _initialize() -> void:
	var session = Session.new(); check(session.open("/tmp/pixel-forest-p3-"+str(Time.get_ticks_usec())+"/save.json"),"new P3 profile")
	for id in ["FL01","FL02","FL03","FL04"]: check(Scenarios.play(session,id),id+" transaction and proof")
	check(Scenarios.send(session,{"kind":"build","building":"roof"}) and session.profile.inventory.camp_wood == 2,"roof purchase after four quests")
	check(not Scenarios.send(session,{"kind":"build","building":"roof"}) and session.profile.inventory.camp_wood == 2,"roof cannot be purchased twice")
	for id in ["FL05","FL06","FL07"]: check(Scenarios.play(session,id),id+" transaction and proof")
	check(session.profile.progress.journey_exp == 140 and "compare" in session.profile.roster.loadouts.acheng,"P3 progression and skill")
	var restored = Session.new(); check(restored.open(session.repository.path) and restored.profile == session.profile,"P3 full readback")
	var p = session.catalog.levels.FL05.params
	check(Machine.orders(p).size() == 20 and Machine.candidates(p) == [["triple","plus2"]],"runtime enumerates complete module candidates")
	var wrong = Machine.fresh(p); wrong.order = ["plus2","double"]; wrong.prediction = 16; wrong.tested = true; wrong.predicted_before_trial = true
	check(not Machine.complete(p,wrong),"single-page machine fails joint records")
	wrong.order = ["triple","plus2"]; wrong.prediction = 20
	check(Machine.complete(p,wrong),"solved order with a trial settles; prediction is optional")
	p = session.catalog.levels.FL06.params
	for secret in ["A","B","C"]:
		var state = Machine.fresh(p); state.secret_id = secret
		state.probe_input = 2; state.predictions = {"A":8,"B":8,"C":14}
		check(not Machine.valid_predictions(p,state),"ambiguous probe 2 cannot certify "+secret)
		state.probe_input = 6; state.predictions = {"A":16,"B":20,"C":18}
		var result = Machine.apply(p,state,{"kind":"probe"}); state = result.state
		check(state.observation[1] == {"A":16,"B":20,"C":18}[secret],"actual hidden output "+secret)
		state = Machine.apply(p,state,{"kind":"identify","id":secret}).state
		check(Machine.complete(p,state),"all secret identities are playable "+secret)
		var blind = Machine.fresh(p); blind.secret_id = secret; blind.probe_input = 6
		var refused = Machine.apply(p,blind,{"kind":"probe"})
		check(not refused.accepted,"probing without written predictions is refused "+secret)
		blind.predictions = {"A":16,"B":20,"C":18}
		blind = Machine.apply(p,blind,{"kind":"probe"}).state
		check(not Machine.complete(p,blind),"a probe alone does not settle "+secret)
		blind = Machine.apply(p,blind,{"kind":"identify","id":secret}).state
		check(Machine.complete(p,blind),"identify with matching predictions settles "+secret)
	check(Scenarios.send(session,{"kind":"start","level_id":"FL06"}),"practice run starts")
	var identity = session.profile.active_run.state.secret_id
	check(Scenarios.send(session,{"kind":"reset","confirmed":true}) and session.profile.active_run.state.secret_id == identity,"reset does not reroll hidden machine")
	p = session.catalog.legacy_fl07.params
	for order in Machine.candidates(p):
		var performance = Machine.apply(p,Machine.fresh(p),{"kind":"try","order":order})
		check(performance.accepted and performance.state.tested and not Machine.complete(p,performance.state),"both equivalent candidates pass performance without claiming original identity")
		for input_value in range(1,11):
			check(Machine.evaluate(Machine.operations(p,order),input_value).back() == 2*input_value+4,"independent equivalent function reference")
	var ambiguous = Machine.fresh(p); ambiguous.kept = [["minus1","plus3","double"]]; ambiguous.equivalence = [["add",2],["mul",2]]
	check(not Machine.external_certificate(p,ambiguous),"cannot discard externally equivalent candidate early")
	ambiguous.kept.append(["plus3","minus1","double"])
	check(Machine.external_certificate(p,ambiguous),"both equivalent candidates retained")
	ambiguous.revealed = true; ambiguous.observations = [0]; ambiguous.final_order = ["plus3","minus1","double"]
	check(not Machine.complete(p,ambiguous),"intermediate record rejects wrong order")
	print("FOREST P3 ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

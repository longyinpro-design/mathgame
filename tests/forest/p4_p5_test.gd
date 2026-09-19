extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Policy = preload("res://scripts/mechanisms/policy_rules.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func _initialize() -> void:
	var session = Session.new(); check(session.open("/tmp/pixel-forest-p45-"+str(Time.get_ticks_usec())+"/save.json"),"new profile")
	for i in range(1,9): check(Scenarios.play(session,"FL%02d"%i),"quest FL%02d"%i)
	check(session.profile.roster.owned == ["acheng","mossling","feather"],"third companion joins at shared level")
	check(Scenarios.send(session,{"kind":"party","members":["mossling","feather"]}),"party can leave fox in camp")
	check(Scenarios.send(session,{"kind":"build","building":"workbench"}),"workbench after post route")
	check(not session.catalog.available("FL11",session.profile.progress.completed_levels),"two post branches required")
	check(Scenarios.play(session,"FL10"),"FL10 may precede FL09")
	check(not session.catalog.available("FL11",session.profile.progress.completed_levels),"one branch cannot unlock FL11")
	check(Scenarios.play(session,"FL09"),"FL09 optimal stone with all classifications")
	check(session.catalog.available("FL11",session.profile.progress.completed_levels),"AND branches unlock return cargo")
	check(Scenarios.play(session,"FL11"),"capacity and load limit cargo in three trips")
	check(Scenarios.play(session,"FL12"),"actual takeaway and exhaustive response policy")
	check(Scenarios.send(session,{"kind":"camp"}) and Scenarios.send(session,{"kind":"grow"}),"three story bonds grow fox at camp")
	check(not Scenarios.send(session,{"kind":"grow"}),"growth cannot repeat")
	var p = session.catalog.levels.FL08.params
	check(Routes.all_paths(p).size() == 10,"ten monotone routes")
	p = session.catalog.levels.FL10.params
	check(Routes.all_pairs(p).size() == 6,"six unordered disjoint route pairs")
	check(not Routes.compatible(p,"RRRUU","RRURU"),"individually legal but colliding paths fail")
	check(Routes.pair_key("RRRUU","UURRR") == Routes.pair_key("UURRR","RRRUU"),"swapped identities count once")
	check(not Policy.covers_all(12,[3,3,3],3),"constant take3 cannot cover every opponent")
	check(Policy.covers_all(12,[3,2,1],3),"complement policy covers all opponent moves")
	var reloaded = Session.new(); check(reloaded.open(session.repository.path) and reloaded.profile == session.profile,"P5 progress and loadout restore")
	print("FOREST P4/P5 ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

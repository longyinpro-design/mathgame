extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Seal = preload("res://scripts/mechanisms/seal_battle_rules.gd")
const Probe = preload("res://scripts/mechanisms/probe_battle_rules.gd")
const Coins = preload("res://scripts/mechanisms/coin_rules.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func _initialize() -> void:
	var session = Session.new(); check(session.open("/tmp/pixel-forest-p67-"+str(Time.get_ticks_usec())+"/save.json"),"new full chapter profile")
	for i in range(1,19): check(Scenarios.play(session,"FL%02d"%i),"full quest FL%02d"%i)
	check(session.profile.progress.completed_levels.size() == 18 and session.profile.progress.journey_exp == 340 and session.profile.inventory.camp_wood == 136,"all18 reward totals")
	for building in ["garden","roof","workbench"]: check(Scenarios.send(session,{"kind":"build","building":building}),"construction "+building)
	check(session.profile.inventory.camp_wood == 16,"all three constructions preserve optional surplus")
	var readback = Session.new(); check(readback.open(session.repository.path) and readback.profile == session.profile,"full chapter readback")
	var p = session.catalog.levels.FL17.params
	for enemy in ["stomp","leaf_swap"]:
		var state = Seal.fresh(p); state.enemy_response_id = enemy
		check(not Seal.apply(p,state,{"kind":"transfer","card":1,"from":0,"to":1}).accepted,"locked A rejected "+enemy)
		state = Seal.apply(p,state,{"kind":"transfer","card":1,"from":2,"to":1}).state
		check(state.energy == ([2,9,10] if enemy == "stomp" else [2,10,9]) and state.response_applied,"first move plus enemy is atomic "+enemy)
		check(not Seal.apply(p,state,{"kind":"transfer","card":1,"from":2,"to":0}).accepted,"spent card rejected "+enemy)
		var serialized = Session.Catalog.normalize_numbers(JSON.parse_string(JSON.stringify(state)))
		check(Seal.valid(p,serialized) and serialized == state,"enemy response stable after JSON "+enemy)
		state = Seal.apply(p,state,{"kind":"transfer","card":3 if enemy == "stomp" else 2,"from":2,"to":0}).state
		state = Seal.apply(p,state,{"kind":"transfer","card":2 if enemy == "stomp" else 3,"from":1,"to":0}).state
		check(not Seal.complete(p,state) and state.battle_phase == "ready","balanced board requires actual counterattack "+enemy)
		state = Seal.apply(p,state,{"kind":"finish"}).state
		check(Seal.valid(p,state) and Seal.complete(p,state),"final counterattack "+enemy)
		var wrong = Seal.fresh(p); wrong.enemy_response_id = enemy; wrong = Seal.apply(p,wrong,{"kind":"transfer","card":1,"from":1,"to":2}).state
		check(Seal.winning_tail(p,wrong).is_empty(),"greedy center7 loses both authored responses "+enemy)
	p = session.catalog.levels.FL18.params
	for form in ["A","B","C","D"]:
		var state = Probe.fresh(p); state.secret_form_id = form
		check(not Probe.apply(p,state,{"kind":"finish","value":8}).accepted,"cannot finish unidentified "+form)
		state = Probe.apply(p,state,{"kind":"probe","value":2}).state
		if state.active_observations[0][1] == 8: state = Probe.apply(p,state,{"kind":"probe","value":5}).state
		check(Probe.candidates(p,state) == [form],"effective observations uniquely identify "+form)
		state = Probe.apply(p,state,{"kind":"finish","value":{"A":8,"B":6,"C":8,"D":7}[form]}).state
		check(Probe.valid(p,state) and Probe.complete(p,state),"budgeted finisher all forms "+form)
	var state = Probe.fresh(p); state.secret_form_id = "B"; state = Probe.apply(p,state,{"kind":"probe","value":6}).state
	check(state.active_observations[0][1] == 20 and not state.won,"probe20 is not victory")
	state = Probe.fresh(p); state.secret_form_id = "A"; state = Probe.apply(p,state,{"kind":"probe","value":6}).state; state = Probe.apply(p,state,{"kind":"probe","value":2}).state
	check(state.seed_balance == 7 and not Probe.apply(p,state,{"kind":"finish","value":8}).accepted,"greedy probe leaves insufficient A budget")
	state = Probe.fresh(p); state.secret_form_id = "C"; state = Probe.apply(p,state,{"kind":"probe","value":2}).state; state = Probe.apply(p,state,{"kind":"finish","value":2}).state
	check(state.battle_phase == "missed" and not state.won and Probe.valid(p,state),"wrong finisher consumes budget and remains recoverable")
	p = session.catalog.levels.FL15.params
	var coins = Coins.fresh(p); coins.nodes.root.left = [0]; coins.nodes.root.right = [0]
	check(not Coins.valid(p,coins),"coin cannot occupy both pans")
	print("FOREST P6/P7 ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

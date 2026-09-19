extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func _initialize() -> void:
	var s = Session.new(); check(s.open("/tmp/pixel-forest-p8-"+str(Time.get_ticks_usec())+"/save.json"),"fresh P8 profile")
	check(Scenarios.send(s,{"kind":"dialogue","id":"camp.begin"}),"authored dialogue persists")
	check(not Scenarios.send(s,{"kind":"dialogue","id":"camp.spring"}),"unseen story dialogue unavailable")
	for id in ["FL01","FL02"]: check(Scenarios.play(s,id),"prior quest "+id)
	check(s.profile.inventory.unique_items == ["seed_letter","stone_token"],"unique story items from real completions")
	check(Scenarios.send(s,{"kind":"start","level_id":"FL13"}),"optional cargo practice fixture")
	var before = s.profile.duplicate(true)
	check(not Scenarios.send(s,{"kind":"tool","skill":"group","items":[0,1,2],"target":1}) and s.profile == before,"group over capacity rejects whole move")
	check(Scenarios.send(s,{"kind":"tool","skill":"group","items":[0,1],"target":1}) and s.profile.active_run.state.places.slice(0,2) == [1,1],"same-origin group executes atomically")
	check(Scenarios.send(s,{"kind":"undo"}) and s.profile.active_run.state.places.slice(0,2) == [0,0],"one undo reverses entire group")
	var party = s.profile.active_run.party.duplicate(); var loadouts = s.profile.active_run.loadouts.duplicate(true)
	check(Scenarios.send(s,{"kind":"party","members":["mossling"]}) and s.profile.active_run.party == party,"active party immutable while future party changes")
	check(Scenarios.send(s,{"kind":"equip","partner":"acheng","skill":"mark"}) and s.profile.active_run.loadouts == loadouts,"active skill snapshot immutable")
	check(Scenarios.send(s,{"kind":"tool","skill":"mark","index":0}) and s.profile.active_run.highest_hint == 0,"player mark is not an answer hint")
	check(Scenarios.send(s,{"kind":"hint"}),"active hint recorded")
	# Finish this active cargo with real rule commands.
	var count = 0
	while not s.profile.active_run.state.complete and count < 100:
		var action = Scenarios.Cargo.hint(s.catalog.levels.FL13.params,s.profile.active_run.state)
		check(Scenarios.rule(s,action),"optional cargo continuation"); count += 1
	check(s.profile.active_run.outcome == "complete" and s.profile.active_run.state.certificate.is_empty(),"delivery at two trips settles without a comparison card")
	var reward_count = s.profile.progress.claimed_rewards.size(); var exp = s.profile.progress.journey_exp
	check(Scenarios.play(s,"FL13"),"repeat run records practice")
	check(s.profile.progress.claimed_rewards.size() == reward_count and s.profile.progress.journey_exp == exp,"practice never repeats rewards")
	check(s.profile.learning.observations.back().prior_help and s.profile.learning.observations.back().evidence_kind == "assisted_completion","same-parameter practice preserves prior help provenance")
	for i in range(3,13): check(Scenarios.play(s,"FL%02d"%i),"main quest FL%02d"%i)
	check(Scenarios.send(s,{"kind":"party","members":["acheng","mossling"]}),"configure two trained partners")
	check(Scenarios.play(s,"FL17"),"guardian completion")
	check(Scenarios.send(s,{"kind":"start","level_id":"FL18"}),"new fixed tree case")
	check(Scenarios.send(s,{"kind":"tool","skill":"compare"}),"player snapshot stored")
	check(not s.profile.active_run.tools.snapshots[0].has("secret_form_id"),"snapshot cannot reveal hidden tree form")
	var params: Dictionary = s.catalog.levels.FL18.params
	var initial_case = s.profile.active_run.state.secret_form_id
	check(Scenarios.rule(s,{"kind":"probe","value":2}),"first observed probe")
	var committed = s.profile.duplicate(true)
	s.repository.fail_at = "replace"
	check(not Scenarios.send(s,{"kind":"undo"}) and s.profile == committed,"failed undo save does not refund or change evidence")
	s.repository.fail_at = ""; check(s.retry(),"retry exact undo candidate")
	check(s.profile.active_run.state.secret_form_id == initial_case and s.profile.active_run.state.seed_balance == 15 and s.profile.active_run.state.active_observations.is_empty() and s.profile.active_run.observation_history.size() == 1,"undo restores budget and separates history")
	check(Scenarios.send(s,{"kind":"reset","confirmed":true}) and s.profile.active_run.state.secret_form_id == initial_case and s.profile.active_run.observation_history.size() == 1,"reset also preserves secret and historical observations")
	var loaded = Session.new(); check(loaded.open(s.repository.path) and loaded.profile == s.profile,"P8 state resumes exactly")
	for point in ["open","flush","replace"]:
		s.repository.fail_at = point; var original = FileAccess.get_file_as_string(s.repository.path)
		check(not Scenarios.send(s,{"kind":"camp"}) and FileAccess.get_file_as_string(s.repository.path) == original,"save failure preserves old file at "+point)
		s.repository.fail_at = ""; check(s.retry(),"same candidate retry at "+point)
	var malformed = s.profile.duplicate(true); malformed.progress.claimed_rewards.append("invented")
	check(not s.validate(malformed),"unearned reward id rejected")
	malformed = s.profile.duplicate(true); malformed.roster.bonds.acheng = []
	check(not s.validate(malformed),"lost bond events rejected")
	malformed = s.profile.duplicate(true); malformed.learning.observations = []
	check(not s.validate(malformed),"missing completed learning records rejected")
	malformed = s.profile.duplicate(true); malformed.inventory.unique_items.append("unearned_chart")
	check(not s.validate(malformed),"unearned inventory item rejected")
	var bad_path = s.repository.path+".corrupt"
	var f = FileAccess.open(bad_path,FileAccess.WRITE); f.store_string("{broken-profile"); f.close()
	var damaged = Session.new(); check(not damaged.open(bad_path),"damaged record remains protected")
	check(not damaged.new_after_protected(false) and FileAccess.get_file_as_string(bad_path) == "{broken-profile","new journey needs explicit confirmation")
	check(damaged.new_after_protected(true) and damaged.profile.progress.completed_levels.is_empty(),"confirmed fresh journey after preserving damaged record")
	var directory = DirAccess.open(bad_path.get_base_dir()); var found_original = false
	for file in directory.get_files():
		if file.begins_with(bad_path.get_file()+".protected-") and FileAccess.get_file_as_string(bad_path.get_base_dir().path_join(file)) == "{broken-profile": found_original = true
	check(found_original,"damaged original retained byte-for-byte")
	print("FOREST P8 ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

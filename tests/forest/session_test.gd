extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
const Cargo = preload("res://scripts/mechanisms/cargo_rules.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ",label)
func send(s: RefCounted, action: Dictionary) -> bool:
	return s.command(action,int(s.profile.revision))
func _initialize() -> void:
	var path = "/tmp/pixel-forest-session-"+str(Time.get_ticks_usec())+"/save.json"
	var s = Session.new()
	check(s.open(path),"fresh profile persists")
	check(send(s,{"kind":"start","level_id":"FL01"}),"start FL01")
	check(not s.command({"kind":"camp"},0),"stale command rejected")
	var snapshot = s.profile.duplicate(true)
	s.repository.fail_at = "replace"
	check(not send(s,{"kind":"rule","action":{"kind":"move","item":0,"target":1}}),"replace failure surfaced")
	check(s.profile == snapshot and not s.pending.is_empty(),"failure leaves committed state unchanged")
	check(not send(s,{"kind":"hint"}),"pending write blocks commands")
	s.repository.fail_at = ""
	check(s.retry() and s.profile.active_run.state.places[0] == 1,"retry installs one candidate")
	var restored = Session.new()
	check(restored.open(path) and restored.profile == s.profile,"readback identical")
	check(send(s,{"kind":"undo"}) and s.profile.active_run.state.places[0] == 0,"undo commits previous board")
	check(send(s,{"kind":"hint"}),"hint stored")
	for i in [0,1,2]: check(send(s,{"kind":"rule","action":{"kind":"move","item":i,"target":1}}),"load passenger "+str(i))
	for i in [3,4,5]: check(send(s,{"kind":"rule","action":{"kind":"move","item":i,"target":2}}),"load weight "+str(i))
	check(send(s,{"kind":"rule","action":{"kind":"travel"}}),"one-trip alternate solution")
	check(s.profile.progress.journey_exp == 20 and s.profile.inventory.camp_wood == 8 and s.profile.roster.bonds.acheng == ["FL01"],"reward and bond settle together")
	check(s.profile.learning.observations[0].evidence_kind == "assisted_completion","help recorded without reward penalty")
	check(not send(s,{"kind":"rule","action":{"kind":"travel"}}) and s.profile.progress.journey_exp == 20,"completion cannot be replayed")
	check(send(s,{"kind":"start","level_id":"FL02"}),"FL02 unlocks")
	# Fresh 8/8/8 -> 11/7/6, through actual unit transfers.
	for source in [1,2,2]: check(send(s,{"kind":"rule","action":{"kind":"shift","from":source,"to":0}}),"construct FL02")
	s.repository.fail_at = "flush"
	check(not send(s,{"kind":"rule","action":{"kind":"try"}}) and "mossling" not in s.profile.roster.owned and s.profile.active_run.outcome == "active","reward save failure withholds recruitment")
	s.repository.fail_at = ""
	check(s.retry() and s.profile.progress.journey_exp == 40 and s.profile.roster.owned == ["acheng","mossling"],"same candidate retry recruits once")
	check(s.profile.active_run.outcome == "complete" and s.profile.active_run.state.reverse.is_empty(),"FL02 settles from the matched trace alone")
	check(s.retry() and s.profile.progress.journey_exp == 40,"duplicate retry no extra reward")
	check(restored.open(path) and restored.profile == s.profile,"settled profile restores")
	var bad = s.profile.duplicate(true); bad.inventory.camp_wood += 1
	check(not s.validate(bad),"tampered economy rejected")
	bad = s.profile.duplicate(true); bad.active_run.params_snapshot.total = 25
	check(not s.validate(bad),"mismatched active parameter revision rejected")
	var f = FileAccess.open(path+".bad",FileAccess.WRITE); f.store_string("{broken"); f.close()
	var broken = Session.new()
	check(not broken.open(path+".bad") and broken.repository.protected,"bad profile protected")
	check(not broken.repository.write_profile(Session.fresh(),broken.validate) and FileAccess.get_file_as_string(path+".bad") == "{broken","bad source never overwritten")
	# Legacy active run whose board already satisfies the relaxed rule settles once on resume.
	var legacy_path = "/tmp/pixel-forest-legacy-"+str(Time.get_ticks_usec())+"/save.json"
	var legacy = Session.new(); check(legacy.open(legacy_path),"legacy profile persists")
	check(Scenarios.play(legacy,"FL01"),"legacy fixture FL01")
	check(Scenarios.send(legacy,{"kind":"start","level_id":"FL02"}),"legacy fixture FL02 starts")
	for source in [1,2,2]: check(Scenarios.rule(legacy,{"kind":"shift","from":source,"to":0}),"legacy fixture shift")
	var legacy_value = legacy.profile.duplicate(true)
	# Old saves could hold an already-matched trace but stay active while proof was mandatory.
	legacy_value.active_run.outcome = "active"
	legacy_value.active_run.state.trace = [[11,7,6],[4,14,6],[4,8,12],[8,8,8]]
	var writer = FileAccess.open(legacy_path,FileAccess.WRITE); writer.store_string(JSON.stringify(legacy_value)); writer.close()
	var resumed = Session.new()
	check(resumed.open(legacy_path),"legacy solved board reopens")
	check(resumed.profile.active_run.outcome == "active" and resumed.profile.progress.completed_levels == ["FL01"],"legacy board stays active before resume")
	check(send(resumed,{"kind":"start","level_id":"FL02"}) and resumed.profile.active_run.outcome == "complete","legacy solved board settles once on resume")
	check(resumed.profile.progress.journey_exp == 40 and "mossling" in resumed.profile.roster.owned,"legacy resume grants the reward exactly once")
	# The resident NPC stays talkable even when every level in the region is completed.
	check(send(resumed,{"kind":"talk_region","region":"treetop","position":[1110,562]}),"region dialogue answers while levels remain")
	check(Scenarios.play(resumed,"FL13") and resumed.profile.progress.completed_levels == ["FL01","FL02","FL13"],"FL13 closes the treetop region")
	check(send(resumed,{"kind":"talk_region","region":"treetop","position":[1110,562]}) and resumed.profile.world.location_id == "treetop" and not resumed.profile.world.region_dialogues.is_empty(),"completed region still talks")
	print("FOREST SESSION ",checks-failures,"/",checks," PASS")
	quit(1 if failures else 0)

extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void:
	var catalog = Session.Catalog.new()
	check(catalog.error == "", "author catalog loads")
	for id in catalog.levels:
		var definition = catalog.definition(id); var original = Session.Rules.fresh(definition)
		check(Session.Rules.valid(definition,original),id+" fresh state validates")
		for key in original:
			for wrong in [null,"malformed",{"bad":true},[null]]:
				if typeof(original[key]) == typeof(wrong): continue
				var state = original.duplicate(true); state[key] = wrong
				check(not Session.Rules.valid(definition,state),id+" rejects malformed "+key)
		var damaged = definition.duplicate(true); damaged.reward.journey_exp = -1
		check(not Session.Catalog.valid_definition(damaged),id+" rejects negative reward")
		damaged = definition.duplicate(true); damaged.family = "unregistered_rule"
		check(not Session.Catalog.valid_definition(damaged),id+" rejects unknown mechanism")
		for key in Session.Catalog.PARAMETER_FIELDS[definition.family]:
			damaged = definition.duplicate(true); damaged.params.erase(key)
			check(not Session.Catalog.valid_definition(damaged),id+" requires parameter "+key)
	var session = Session.new(); session.open("/tmp/pixel-forest-boundary-"+str(Time.get_ticks_usec())+"/save.json")
	var profile = session.profile.duplicate(true)
	for key in profile:
		for wrong in [null,"malformed",{"bad":true},[null]]:
			if typeof(profile[key]) == typeof(wrong) or key == "active_run": continue
			var malformed = profile.duplicate(true); malformed[key] = wrong
			check(not session.validate(malformed),"profile rejects malformed "+key)
	session.command({"kind":"start","level_id":"FL01"},int(session.profile.revision))
	profile = session.profile.duplicate(true)
	for key in profile.active_run:
		for wrong in [null,"malformed",{"bad":true},[null]]:
			if typeof(profile.active_run[key]) == typeof(wrong): continue
			var malformed = profile.duplicate(true); malformed.active_run[key] = wrong
			check(not session.validate(malformed),"run rejects malformed "+key)
	print("FOREST BOUNDARY ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

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
	var s = Session.new(); check(s.open("/tmp/pixel-forest-review-"+str(Time.get_ticks_usec())+"/save.json"),"new repair profile")
	check(Scenarios.play(s,"FL01"),"first main quest")
	check(Scenarios.send(s,{"kind":"start","level_id":"FL13"}),"optional quest starts")
	Scenarios.rule(s,{"kind":"move","item":0,"target":1})
	for i in range(3): Scenarios.send(s,{"kind":"hint"})
	var optional = s.profile.active_run.duplicate(true)
	check(Scenarios.send(s,{"kind":"start","level_id":"FL02"}),"R1 unfinished optional does not block mainline")
	check(s.profile.suspended_runs.FL13 == optional and s.profile.progress.journey_exp == 20,"R1 exact optional board and help preserved without reward")
	var main = s.profile.active_run.duplicate(true)
	s.repository.fail_at = "replace"
	check(not Scenarios.send(s,{"kind":"start","level_id":"FL13"}) and s.profile.active_run == main,"R1 failed switch keeps current owner")
	s.repository.fail_at = ""; check(s.retry() and s.profile.active_run == optional and s.profile.suspended_runs.FL02 == main,"R1 retry switches the exact saved runs once")
	var loaded = Session.new(); check(loaded.open(s.repository.path) and loaded.profile == s.profile,"R1 suspended state survives restart")
	Scenarios.send(s,{"kind":"start","level_id":"FL02"})
	for i in range(3): Scenarios.send(s,{"kind":"hint"})
	var hint = s.feedback
	check(s.profile.active_run.highest_hint == 3 and not hint.contains("先把一枚从"),"R2 third hint stays in the guiding tier and still withholds the move")
	Scenarios.rule(s,{"kind":"shift","from":1,"to":0}); Scenarios.send(s,{"kind":"hint"})
	check(s.feedback != hint and s.profile.active_run.highest_hint == 4,"R2 fourth request escalates to the step-by-step tier and follows the changed board")
	for i in range(2): Scenarios.rule(s,{"kind":"shift","from":2,"to":0})
	Scenarios.send(s,{"kind":"hint"}); var last_hint = s.feedback
	check(Scenarios.rule(s,{"kind":"try"}) and s.profile.active_run.outcome == "complete","R2 matched trace settles FL02 directly")
	check(s.profile.learning.observations.back().hint_log.back().text == last_hint,"R2 completed journal keeps actual help")
	for i in range(3,7): check(Scenarios.play(s,"FL%02d"%i),"prerequisite FL%02d"%i)
	Scenarios.send(s,{"kind":"start","level_id":"FL07"})
	check(Scenarios.rule(s,{"kind":"combine","left":3,"right":1,"op":"-"}),"R3 24-point first combination")
	check(loaded.open(s.repository.path) and loaded.profile.active_run.state == s.profile.active_run.state,"R3 24-point board survives restart")
	check(Scenarios.rule(s,{"kind":"combine","left":1,"right":2,"op":"*"}) and Scenarios.rule(s,{"kind":"combine","left":1,"right":0,"op":"-"}),"R3 arithmetic combination settles FL07")
	Scenarios.play(s,"FL08")
	Scenarios.send(s,{"kind":"party","members":["acheng","feather"]}); Scenarios.send(s,{"kind":"start","level_id":"FL10"})
	for direction in "RRRUU": Scenarios.rule(s,{"kind":"step","direction":direction})
	check(Scenarios.send(s,{"kind":"tool","skill":"route_tag","group":0}) and s.profile.active_run.tools.route_tags.RRRUU == 0,"R5 player's chosen route tag saved")
	check(loaded.open(s.repository.path) and loaded.profile.active_run.tools.route_tags.RRRUU == 0,"R5 route tag survives restart")
	var trained = Session.new(); trained.open("/tmp/pixel-forest-recommend-"+str(Time.get_ticks_usec())+"/save.json")
	for i in range(1,13): Scenarios.play(trained,"FL%02d"%i)
	check(trained.profile.progress.journey_exp == 240,"R6 uninterrupted mainline economy")
	for id in ["FL13","FL02"]:
		check(not Session.Selector.support_for(trained.profile,trained.catalog.levels[id],trained.catalog).show_scaffold,"R6 tutorial scaffold no longer offered "+id)
	var p = trained.catalog.levels.FL08
	var route = Session.Rules.fresh(p)
	# The redesigned board audits 折羽's filing: the hint first names the misfiled card.
	var audit_hint = Session.Rules.hint(p,route,3)
	check(audit_hint.contains("移正") or audit_hint.contains("第一次向右"),"R2 postal hint starts from the misfiled card")
	for index in route.filing.size():
		if route.filing[index].group != route.filing[index].path.find("R"):
			route = Session.Rules.apply(p,route,{"kind":"audit_move","index":index}).state
	var after_fix = Session.Rules.hint(p,route,3)
	check(after_fix != audit_hint and (after_fix.contains("条数") or after_fix.contains("缺")),"R2 postal hint then asks for the per-bag counts")
	# 第 3 档现在先盯「至少要称几次」那一栏；先把它答对，才轮到提示跟着秤盘走。
	p = trained.catalog.levels.FL15; var coin = Session.Rules.apply(p,Session.Rules.fresh(p),{"kind":"min_weighings","value":2}).state
	var first_hint = Session.Rules.hint(p,coin,3)
	coin = Session.Rules.apply(p,coin,{"kind":"assign","node":"root","coin":0,"pan":"left"}).state
	check(first_hint != Session.Rules.hint(p,coin,3),"R2 weighing hint preserves current assignments")
	for id in trained.catalog.levels:
		p = trained.catalog.levels[id]; check(not Session.Rules.hint(p,Session.Rules.fresh(p),3).is_empty(),"current-state hint exists "+id)
	print("FOREST REVIEW REPAIRS ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

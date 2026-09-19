extends SceneTree
# Regression checks for the FL08 / FL10 redesign: the puzzle now asks for reasoning
# (audit a filing, supply the one missing route, state an upper bound) instead of
# copying every route by hand. Old-shape receipts must keep working.
const Session = preload("res://scripts/core/game_session.gd")
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
    checks += 1
    if ok: print("PASS ",label)
    else: failures += 1; push_error(label)
func _initialize() -> void:
    var s = Session.new(); s.open("/tmp/pixel-forest-redesign-"+str(Time.get_ticks_usec())+"/save.json")
    for i in range(1,8): check(Scenarios.play(s,"FL%02d"%i),"prior fixture FL%02d"%i)
    var p8 = s.catalog.levels.FL08.params
    var p10 = s.catalog.levels.FL10.params
    # The seed carries exactly one misfiled card and omits exactly one route.
    var filing = Routes.seed_filing(p8)
    check(filing.size() == Routes.all_paths(p8).size()-1,"seed filing omits one route")
    var misfiled = []
    var listed = []
    for card in filing:
        listed.append(card.path)
        if card.group != card.path.find("R"): misfiled.append(card.path)
    check(misfiled.size() == 1,"seed has exactly one misfiled card")
    var missing = []
    for path in Routes.all_paths(p8):
        if path not in listed: missing.append(path)
    check(missing.size() == 1,"seed omits exactly one route")
    # The per-bag counts are the combinatorial ones the level teaches.
    check(Routes.expected_counts(p8) == [6,3,1],"per-bag counts are C(4,2), C(3,2), C(2,2)")
    # Lazy checks: the board must not accept an unrepaired filing.
    var state = Routes.fresh(p8)
    check(not Routes.complete(p8,state),"fresh FL08 board is not already solved")
    check(not Routes.apply(p8,state,{"kind":"audit_move","index":all_paths_index(p8,"RRRUU")}).accepted,"correctly filed cards cannot be 'repaired'")
    # Full reasoning path completes it. Driven through the narrative so the
    # receipt the cutscene reads is committed with the run.
    s.profile.story.node = "pre_FL08"
    check(Scenarios.send(s,{"kind":"start","level_id":"FL08","narrative":true,"node":"pre_FL08"}),"FL08 opens on the narrative path")
    check(Scenarios.play(s,"FL08"),"FL08 audit completes through the rules: "+s.feedback)
    var receipt = s.profile.story.results.FL08
    check(receipt.counts == [6,3,1],"FL08 receipt records the stated counts")
    check(receipt.filing.size() == 10 and receipt.routes.is_empty(),"FL08 receipt keeps the audited filing, not a copied route table")
    # FL10: the ceiling is 2 and the pigeonhole reason is the accepted one.
    check(Routes.max_simultaneous(p10) == 2,"at most two letters travel together")
    check(Routes.upper_bound_reason(p10) == 0,"the pigeonhole reason is the accepted index")
    var b = Routes.fresh(p10)
    check(not Routes.apply(p10,b,{"kind":"bound_set","value":["RRRUU","RRURU","URRUR"]}).accepted,"three letters are rejected as colliding")
    check(Routes.apply(p10,b,{"kind":"bound_set","value":["RRRUU","URRUR"]}).accepted,"one right-first and one up-first is accepted")
    s.profile.story.node = "pre_FL10"
    check(Scenarios.send(s,{"kind":"start","level_id":"FL10","narrative":true,"node":"pre_FL10"}),"FL10 opens on the narrative path")
    check(Scenarios.play(s,"FL10"),"FL10 bound proof completes through the rules: "+s.feedback)
    check(s.profile.story.results.FL10.bound_set.size() == 2,"FL10 receipt records the simultaneous set")
    # Legacy receipts (old copy-everything evidence) stay valid and completable.
    var legacy8 = Routes.fresh(p8); legacy8.filing = []
    for path in Routes.all_paths(p8): legacy8.routes.append({"path":path,"group":path.find("R")})
    legacy8.tested = true
    check(Routes.valid(p8,legacy8) and Routes.complete(p8,legacy8),"legacy FL08 receipt still completes")
    var legacy10 = Routes.fresh(p10); legacy10.filing = []
    for pair in Routes.all_pairs(p10): legacy10.pairs.append({"a":pair[0],"b":pair[1],"group":pair[0]})
    legacy10.tested = true
    check(Routes.valid(p10,legacy10) and Routes.complete(p10,legacy10),"legacy FL10 receipt still completes")
    var reloaded = Session.new()
    check(reloaded.open(s.repository.path) and reloaded.profile == s.profile,"redesigned progress restores exactly")
    print("FOREST ROUTE REDESIGN ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)
func all_paths_index(params: Dictionary, target: String) -> int:
    var paths = Routes.all_paths(params)
    for i in paths.size():
        if paths[i] == target: return i
    return -1

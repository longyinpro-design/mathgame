extends SceneTree
const Session = preload("res://scripts/archipelago/session.gd")
const Catalog = preload("res://scripts/archipelago/catalog.gd")
const Numbers = preload("res://scripts/content/content_catalog.gd")
const Legacy = preload("res://scripts/archipelago/legacy_evidence.gd")
var checks = 0
var failures = 0
var base = "/tmp/archipelago-session-"+str(Time.get_ticks_usec())
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(description)
func write_json(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(value)); file.close()
func data(path: String) -> Variant: return Numbers.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(path)))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("campaign test timeout"); quit(1))
	var session = Session.new(); session.allow_locked = true
	check(session.open(base+"/save.json"),"fresh transaction")
	check(Catalog.ids().size()==108,"108 stable identities")
	check(not session.set_settings({"volume":2.0}) and session.pending.is_empty(),"invalid setting rejected without poisoning retry queue")
	for field in ["completed","claimed_rewards","keepsakes","roster","observations"]:
		var broken_type=session.profile.duplicate(true);broken_type[field]=7
		check(not session.validate(broken_type),"invalid array type cleanly rejected "+field)
	for island in Catalog.ISLANDS:
		check(Catalog.ids(island).size()==18 and Catalog.mains(island).size()==14,"18/14 count "+island)
		var resolved: Array = []
		for pass_index in range(18):
			for id in Catalog.ids(island):
				var d = Catalog.definition(id)
				check(not d.is_empty() and ResourceLoader.exists(d.scene),id+" real authored entry")
				var ready = true
				for dependency in d.prerequisites:
					if dependency not in resolved: ready=false
					check(Catalog.is_side(id) or not Catalog.is_side(dependency),"side does not gate main "+id)
				if ready and id not in resolved: resolved.append(id)
		check(resolved.size()==18,"acyclic dependencies "+island)
	var paths = {"geometry":"res://tests/geometry/witnesses.json","fractions":"res://tests/fractions/solutions.json","observatory":"res://tests/observatory/witnesses.json"}
	for island in Catalog.NEW:
		var witnesses = data(paths[island])
		for id in Catalog.ids(island):
			check(session.start(id),id+" start")
			check(session.run().params_snapshot==Catalog.definition(id).params,id+" frozen params")
			for line in Catalog.definition(id).intro: check(session.advance(),id+" manual intro")
			check(not session.command({"kind":"hint"},session.profile.revision-1),"stale command rejected")
			check(not session.command({"kind":"hint","extra":true},session.profile.revision),"unknown command field rejected")
			if id=="GV01":
				session.repository.fail_at="flush"
				check(not session.request_hint(),"hint write failure blocks display")
				session.repository.fail_at=""
				check(session.retry() and not session.feedback.is_empty() and session.run().highest_hint==1,"hint retry restores requested text exactly")
			else: check(session.request_hint(),id+" hint persists")
			var initial=session.run().board.duplicate(true)
			var actions: Array = witnesses[id].actions if witnesses[id] is Dictionary else witnesses[id]
			if id == "GV01":
				var before=session.profile.duplicate(true)
				session.repository.fail_at="replace"
				check(not session.edit_board(actions[0]) and session.profile==before and not session.pending.is_empty(),"save failure retains committed state")
				check(not session.request_hint(),"save failure blocks next commands")
				session.repository.fail_at=""
				check(session.retry(),"retry installs exact candidate")
				check(session.undo() and session.run().board==initial and session.run().highest_hint==1,"undo preserves hint fact")
			for action in actions: check(session.edit_board(action),id+" actual legal action")
			check(Catalog.rules_for(id).solved(session.run().board),id+" actual goal")
			var before=session.profile.duplicate(true)
			session.repository.fail_at="flush"
			check(not session.submit() and session.profile==before and id not in session.profile.completed,id+" reward withheld before successful save")
			session.repository.fail_at=""
			check(session.retry() and id in session.profile.completed,id+" reward and victory atomic")
			if not Catalog.is_side(id): check(session.story_next()==id,id+" continue preserves pending outcome before next level")
			var amount=session.profile.experience;var claimed=session.profile.claimed_rewards.duplicate()
			check(session.retry() and session.profile.experience==amount and session.profile.claimed_rewards==claimed,id+" duplicate retry cannot reward twice")
			var restored=Session.new();restored.allow_locked=true
			check(restored.open(base+"/save.json") and restored.profile==session.profile,id+" full roundtrip")
			for line in Catalog.definition(id).outro: check(session.advance(),id+" manual outcome")
			check(session.restart() and session.profile.experience==amount and session.profile.claimed_rewards==claimed,id+" replay preserves unique reward")
			check(session.run().replay,id+" replay provenance")
			var bad=session.profile.duplicate(true);bad.runs[id].params_snapshot["unknown"]=1
			check(not session.validate(bad),id+" rejects stale parameters")
			bad=session.profile.duplicate(true);bad.experience+=1
			check(not session.validate(bad),id+" rejects invented economy")
	check(session.profile.completed.size()==54,"54 new levels solved through actions")
	for fact in session.profile.observations: check(fact.kind=="assisted_completion" and fact.highest_hint==1,"learning records assistance, no mastery claim")
	check(session.recommendations().size()==54,"assisted author content creates optional practice, not mastery")
	var old_party=session.run().party.duplicate()
	check(session.set_party(["acheng","lingjiao"]) and session.run().party==old_party,"changing party preserves frozen active run")
	check(not session.set_party(["acheng","lingjiao","shuimo"]),"party maximum two")
	var old_reward=session.profile.experience
	check(session.start("GV01"),"revisit completed level")
	for line in Catalog.definition("GV01").intro: check(session.advance(),"replay manual intro")
	check(session.record_support(),"observation tool records support")
	for action in data(paths.geometry).GV01: check(session.edit_board(action),"replay real action")
	check(session.submit() and session.profile.experience==old_reward,"replay produces learning but never second reward")
	check(session.profile.learning_runs.size()==55,"per-run practice history retained")
	check(session.recommendations().size()==53,"unassisted reattempt clears only that optional suggestion")
	var source="res://docs/playtest/archipelago/proofs/forest.json"
	var original=FileAccess.get_sha256(source)
	for id in Catalog.ids("market")+Catalog.ids("workshop"): session.legacy_paths[id]=base+"/missing-"+id+".json"
	session.legacy_paths.forest=source
	check(session.sync_legacy(),"valid old forest history imports")
	check(session.profile.completed.size()==72,"old forest18 plus new54")
	check(session.profile.legacy_sources.size()==1,"old profile source retained once")
	check(FileAccess.get_sha256(source)==original,"adapter never writes legacy source")
	var revision=session.profile.revision;var xp=session.profile.experience
	check(session.sync_legacy() and session.profile.revision==revision and session.profile.experience==xp,"repeated legacy sync idempotent")
	var bad_source=data(source);bad_source.progress.completed_levels.append("FL99")
	write_json(base+"/corrupt-forest.json",bad_source)
	var fresh=Session.new();check(fresh.open(base+"/fresh.json"),"fresh second profile")
	fresh.legacy_paths=session.legacy_paths.duplicate();fresh.legacy_paths.forest=base+"/corrupt-forest.json"
	check(fresh.sync_legacy() and fresh.profile.completed.is_empty() and not Catalog.island_open("market",fresh.profile.completed),"corrupt old source cannot unlock next island")
	var partial=data(source);partial.progress.completed_levels=[]
	write_json(base+"/partial-forest.json",partial);fresh.legacy_paths.forest=base+"/partial-forest.json"
	check(fresh.sync_legacy() and not Catalog.island_open("market",fresh.profile.completed),"inconsistent partial source cannot unlock")
	write_json(base+"/bad.json",{"schema_version":100})
	var broken=Session.new();check(not broken.open(base+"/bad.json") and broken.repository.protected,"unknown campaign protected")
	print("ARCHIPELAGO SESSION: ",checks," assertions, ",failures," failures; 54 new action-completions")
	quit(1 if failures else 0)

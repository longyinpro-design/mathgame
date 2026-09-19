extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var checks = 0
var failures = 0
var paths = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else: failures += 1; push_error(label)
func send(s: RefCounted, action: Dictionary) -> bool: return Scenarios.send(s,action)
func advance(s: RefCounted) -> bool:
	var node: String = s.profile.story.node
	var beat = Session.Story.scene(node)
	if beat.get("next","").begins_with("puzzle_"): return send(s,{"kind":"start","level_id":beat.next.trim_prefix("puzzle_"),"narrative":true,"node":node})
	return send(s,{"kind":"story_advance","node":node})
func new_session() -> RefCounted:
	var s = Session.new(); var path = "/tmp/pixel-story-"+str(Time.get_ticks_usec())+".json"; paths.append(path); check(s.open(path),"fresh story"); return s
func write(path: String, value: Dictionary) -> String:
	var raw = JSON.stringify(value)+"\n"; var f = FileAccess.open(path,FileAccess.WRITE); f.store_string(raw); f.close(); return raw
func _initialize() -> void:
	var s = new_session()
	check(advance(s) and s.profile.story.node == "puzzle_FL01","story enters real FL01 directly")
	for i in range(6): check(Scenarios.rule(s,{"kind":"move","item":i,"target":1 if i < 3 else 2}),"load seed delivery")
	s.repository.fail_at = "replace"
	check(not Scenarios.rule(s,{"kind":"travel"}) and s.profile.story.node == "puzzle_FL01" and s.profile.progress.completed_levels.is_empty(),"reward + consequence withheld on failed save")
	var pending = s.pending.duplicate(true); s.repository.fail_at = ""
	check(s.retry() and s.profile == pending and s.profile.story.node == "post_FL01","retry installs exact reward and consequence")
	var reload = Session.new(); check(reload.open(s.repository.path) and reload.profile.story.node == "post_FL01","reopen at delivery, never repay reward")
	check(advance(s) and s.profile.story.node == "letter","delivery then letter")
	check(not send(s,{"kind":"story_advance","node":"post_FL01"}),"stale double click rejected")
	check(advance(s) and advance(s) and s.profile.story.node == "pre_FL02","letter then crossing then first meeting")
	check(advance(s) and s.profile.active_run.level_id == "FL02","meeting gives player FL02")
	var main_id = s.profile.active_run.run_id
	check(send(s,{"kind":"story_excursion","level_id":"FL13"}) and advance(s),"side invitation preserves main puzzle")
	check(send(s,{"kind":"story_return"}) and s.profile.story.node == "puzzle_FL02" and s.profile.story.run_id == main_id,"unfinished side returns exact main stop")
	check(send(s,{"kind":"start","level_id":"FL02","narrative":true,"node":"puzzle_FL02"}) and s.profile.active_run.run_id == main_id,"resume keeps run identity and side suspension")
	check(send(s,{"kind":"story_excursion","level_id":"FL13"}) and advance(s) and Scenarios.play(s,"FL13"),"finish side while main puzzle suspended")
	check(advance(s) and s.profile.story.node == "puzzle_FL02" and s.profile.story.run_id == main_id,"completed side main button restores exact active main stop")
	check(send(s,{"kind":"start","level_id":"FL02","narrative":true,"node":"puzzle_FL02"}) and s.profile.active_run.run_id == main_id,"completed side restores suspended board")
	check(Scenarios.play(s,"FL02") and s.profile.story.node == "post_FL02" and "mossling" in s.profile.roster.owned,"same committed result recruits and lights gates")
	check(s.profile.story.results.FL02.trace == [[11,7,6],[4,14,6],[4,8,12],[8,8,8]],"cutscene reads actual trace receipt")
	check(advance(s) and s.profile.story.node == "joined" and advance(s) and s.profile.story.node == "village_arrive","recruit scene then village arrival")
	# Saving an advance is just as transactional as completion.
	s.repository.fail_at = "flush"; check(not advance(s) and s.profile.story.node == "village_arrive","failed scene confirmation stays put")
	s.repository.fail_at = ""; check(s.retry() and s.profile.story.node == "pre_FL03","retry advances only once")
	check(not send(s,{"kind":"story_voyage"}),"the crossing stays closed until the chapter ends")
	# Both branch orders, all main puzzles, all optional invitations, no synthetic victory.
	for reverse in [false,true]:
		var full = new_session(); var count = 0
		while full.profile.story.node != "end" and count < 110:
			count += 1
			var node: String = full.profile.story.node
			if node == "post_branch":
				var id = "FL10" if reverse else "FL09"
				if id in full.profile.progress.completed_levels: id = "FL09" if reverse else "FL10"
				check(send(full,{"kind":"story_choose","level_id":id}),"choose branch "+id)
			elif node.begins_with("puzzle_"): check(Scenarios.play(full,node.trim_prefix("puzzle_")),"real solution "+node)
			else: check(advance(full),"advance "+node)
		check(full.profile.story.node == "end" and full.profile.progress.completed_levels.size() == 14,"whole chapter, optional quests not mandatory")
		for id in Session.Flow.SIDES:
			check(send(full,{"kind":"story_excursion","level_id":id}) and advance(full) and Scenarios.play(full,id) and advance(full) and full.profile.story.node == "end","optional excursion returns "+id)
		var exp = full.profile.progress.journey_exp
		check(send(full,{"kind":"story_excursion","level_id":"FL01"}) and advance(full) and Scenarios.play(full,"FL01") and advance(full) and full.profile.story.node == "end" and full.profile.progress.journey_exp == exp,"replay never progresses main or duplicates rewards")
		# Closing the chapter hands the camp a crossing to 千灯集市, and the stop survives a reopen.
		check(send(full,{"kind":"story_voyage"}) and full.profile.story.node == "voyage" and "end" in full.profile.story.seen and full.profile.story.return_node == "","chapter end opens the market crossing")
		check(not send(full,{"kind":"story_advance","node":"voyage"}),"crossing waits for the dock instead of a scripted next")
		var voyager = Session.new(); check(voyager.open(full.repository.path) and voyager.profile.story.node == "voyage","market crossing validates on reopen")
		var original = full.profile.duplicate(true); original.erase("story")
		var legacy = full.repository.path+".legacy"; paths.append(legacy); var raw = write(legacy,original)
		var migrated = Session.new(); check(migrated.open(legacy) and migrated.profile.story.node == "legacy_recap" and FileAccess.get_file_as_string(migrated.repository.migration_backup) == raw,"completed legacy preserved before migration")
		paths.append(migrated.repository.migration_backup)
	# Played active migration and tamper rejection.
	var old = s.profile.duplicate(true); old.erase("story"); var legacy = s.repository.path+".legacy"; paths.append(legacy); var raw = write(legacy,old)
	var migrated = Session.new(); migrated.repository.fail_at = "replace"
	check(not migrated.open(legacy) and migrated.profile.is_empty() and FileAccess.get_file_as_string(legacy) == raw,"played migration failure preserves source bytes")
	paths.append(migrated.repository.migration_backup); migrated.repository.fail_at = ""; check(migrated.retry() and migrated.profile.progress == old.progress,"played migration retry keeps economy")
	var old_session = new_session()
	check(Scenarios.play(old_session,"FL01") and send(old_session,{"kind":"start","level_id":"FL02"}) and Scenarios.play(old_session,"FL13"),"legacy suspended-main sequence prepared")
	var old_state = old_session.profile.duplicate(true); old_state.erase("story")
	var old_path = old_session.repository.path+".legacy"; paths.append(old_path); write(old_path,old_state)
	var restored = Session.new(); check(restored.open(old_path) and restored.profile.story.node == "puzzle_FL02" and restored.profile.story.run_id == old_state.suspended_runs.FL02.run_id,"migration prioritizes suspended main over completed side")
	paths.append(restored.repository.migration_backup)
	var empty = Session.fresh(); empty.erase("story"); empty.world.erase("region_positions"); empty.world.erase("region_dialogues")
	old_path += ".empty"; paths.append(old_path); write(old_path,empty); restored = Session.new()
	check(restored.open(old_path) and restored.profile.story.node == "pre_FL01","known empty legacy upgrades both world and narrative")
	paths.append(restored.repository.migration_backup)
	var invalid = s.profile.duplicate(true); invalid.story.node = "end"; check(not s.validate(invalid),"future narrative node rejected")
	invalid = s.profile.duplicate(true); invalid.story.results.FL02.trace[0][0] = 99; check(not s.validate(invalid),"forged presentation result rejected")
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		if FileAccess.file_exists(path+".tmp"): DirAccess.remove_absolute(path+".tmp")
	print("FOREST STORY ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

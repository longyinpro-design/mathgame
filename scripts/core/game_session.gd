extends RefCounted
const Catalog = preload("res://scripts/content/content_catalog.gd")
const Repository = preload("res://scripts/persistence/save_repository.gd")
const Rules = preload("res://scripts/mechanisms/mechanism_rules.gd")
const Roster = preload("res://scripts/progression/roster_progress.gd")
const Learning = preload("res://scripts/learning/learning_record.gd")
const Numbers = preload("res://scripts/cargo/rules.gd")
const Story = preload("res://scripts/content/story_catalog.gd")
const Selector = preload("res://scripts/learning/challenge_selector.gd")
const Flow = preload("res://scripts/progression/story_progress.gd")
const Quests = preload("res://scripts/progression/quest_progress.gd")

var catalog = Catalog.new()
var repository = Repository.new()
var profile: Dictionary = {}
var pending: Dictionary = {}
var history: Array = []
var pending_history: Array = []
var feedback = ""

static func fresh() -> Dictionary:
	return {"schema_version":1,"content_revision":Catalog.REVISION,"profile_id":"local-1","revision":0,"story":Flow.fresh(),
		"world":{"location_id":"camp","events":[],"dialogues":[],"region_dialogues":[],"tracked_level":"FL01","dismissed_recommendations":[],"region_positions":{}},
		"progress":{"completed_levels":[],"claimed_rewards":[],"journey_exp":0},
		"roster":{"owned":["acheng"],"party":["acheng"],"bonds":{"acheng":[]},"loadouts":{"acheng":["mark"]},"grown":false},
		"inventory":{"camp_wood":0,"unique_items":[],"buildings":[]},"active_run":null,"suspended_runs":{},
		"learning":{"observations":[]},"settings":{"muted":false,"volume":0.7,"short_effects":false,"persistent_goal":true}}

func open(path: String = "") -> bool:
	if path != "": repository.path = path
	if catalog.error != "": feedback = catalog.error; return false
	pending = {}; pending_history = []; history = []
	var result = repository.read_profile(validate,upgrade_story)
	if result.status == "protected": feedback = repository.error; return false
	if result.status == "migration":
		profile = {}; pending = result.profile
		feedback = "旧手记已原样备份。有几处机关换用了新题目；进行中的记录归档重开，完成进度和奖励保留。"
		return retry()
	profile = result.profile if result.status == "loaded" else fresh()
	if result.status == "new":
		pending = profile.duplicate(true); pending_history = []
		return retry()
	return true

func unique_strings(value: Variant) -> bool:
	if not value is Array: return false
	var found = {}
	for id in value:
		if not id is String or found.has(id): return false
		found[id] = true
	return true

func run_definition(run: Dictionary) -> Dictionary:
	if run.level_id == "FL07" and run.params_snapshot == catalog.legacy_fl07.params: return catalog.legacy_fl07
	var definition: Dictionary = catalog.definition(run.level_id)
	if run.params_snapshot == definition.params: return definition
	# A settled run keeps the parameters it was actually played under.
	if run.get("outcome","") == "complete" and Catalog.LEGACY_RESULT_PARAMS.has(run.level_id):
		var fallback: Dictionary = definition.duplicate(true)
		fallback.params = Catalog.LEGACY_RESULT_PARAMS[run.level_id].duplicate(true)
		if run.params_snapshot == fallback.params: return fallback
	return definition

func result_definition(id: String, state: Variant) -> Dictionary:
	if id == "FL07" and state is Dictionary and state.has("final_order"): return catalog.legacy_fl07
	var definition = catalog.definition(id)
	if state is Dictionary and Rules.valid(definition,state) and Rules.complete(definition,state): return definition
	if Catalog.LEGACY_RESULT_PARAMS.has(id) and state is Dictionary:
		var fallback: Dictionary = definition.duplicate(true)
		fallback.params = Catalog.LEGACY_RESULT_PARAMS[id].duplicate(true)
		if Rules.valid(fallback,state) and Rules.complete(fallback,state): return fallback
	return definition

func validate_story(value: Dictionary) -> bool:
	if not value.has("story") or not Flow.valid(value.story,value,catalog): return false
	if not value.story.results is Dictionary: return false
	for id in value.story.results:
		if id not in value.progress.completed_levels: return false
		var definition = result_definition(id,value.story.results[id])
		if not Rules.valid(definition,value.story.results[id]) or not Rules.complete(definition,value.story.results[id]): return false
	return true

func legacy_active(run: Variant) -> bool:
	return run is Dictionary and run.level_id == "FL07" and run.outcome == "active" and run.params_snapshot == catalog.legacy_fl07.params

# Active runs opened under earlier authored parameters cannot continue against new
# ones; upgrade_story archives and restarts them exactly like the FL07 swap did.
# Settled runs stay valid through run_definition instead of being reset.
func stale_params(run: Variant) -> bool:
	if not run is Dictionary or run.get("outcome","") != "active": return false
	var id: String = run.get("level_id","")
	if id not in ["FL04","FL07","FL11"] or not catalog.levels.has(id): return false
	return run.get("params_snapshot",{}) != catalog.levels[id].params

func validate(value: Variant) -> bool:
	if not validate_base(value) or not validate_story(value): return false
	if legacy_active(value.active_run) or stale_params(value.active_run): return false
	for run in value.suspended_runs.values():
		if legacy_active(run) or stale_params(run): return false
	return true

func upgrade_story(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var next: Dictionary = value.duplicate(true)
	if not validate_base(next):
		next = repository.upgrade_empty_development_profile(next,validate_base)
		if next.is_empty(): return {}
		next.revision -= 1
	var changed = not next.has("story")
	if changed: next.story = Flow.migrate(next)
	elif not validate_story(next): return {}
	var runs = next.suspended_runs.values()
	if next.active_run != null: runs.append(next.active_run)
	for run in runs:
		var archive_key = ""
		if legacy_active(run): archive_key = "legacy_fl07_runs"
		elif stale_params(run): archive_key = "legacy_revised_runs"
		else: continue
		changed = true
		if not next.has(archive_key): next[archive_key] = {}
		var old_id: String = run.run_id
		if next[archive_key].has(old_id): return {}
		next[archive_key][old_id] = run.duplicate(true)
		run.run_id = old_id+("/24" if archive_key == "legacy_fl07_runs" else "/revised")
		run.params_snapshot = catalog.levels[run.level_id].params.duplicate(true)
		run.state = Rules.fresh(catalog.levels[run.level_id])
		run.attempt_count = 0; run.highest_hint = 0; run.hint_log = []; run.rewind_count = 0
		run.prior_help = false; run.replanned_after_observation = false; run.observation_history = []
		run.tools = {"marks":[],"group_items":[],"snapshots":[],"used":[],"band_size":0,"route_tags":{}}
		if next.story.run_id == old_id: next.story.run_id = run.run_id
		if next.story.return_run_id == old_id: next.story.return_run_id = run.run_id
	if not changed: return {}
	next.revision += 1
	return next if validate(next) else {}

func validate_base(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["schema_version","content_revision","profile_id","revision","world","progress","roster","inventory","active_run","suspended_runs","learning","settings"]): return false
	if not Numbers.integer(value.schema_version,1,1) or not value.content_revision is String or not value.profile_id is String: return false
	if value.schema_version != 1 or value.content_revision != Catalog.REVISION or value.profile_id != "local-1" or not Numbers.integer(value.revision,0,2147483647): return false
	for key in ["world","progress","roster","inventory","learning","settings"]:
		if not value[key] is Dictionary: return false
	var progress: Dictionary = value.progress; var roster: Dictionary = value.roster; var inventory: Dictionary = value.inventory
	if not progress.has_all(["completed_levels","claimed_rewards","journey_exp"]) or not roster.has_all(["owned","party","bonds","loadouts","grown"]) or not inventory.has_all(["camp_wood","unique_items","buildings"]): return false
	if not Numbers.integer(progress.journey_exp,0,1000000) or not Numbers.integer(inventory.camp_wood,0,1000000): return false
	for list in [progress.completed_levels,progress.claimed_rewards,roster.owned,roster.party,inventory.unique_items,inventory.buildings,value.world.get("events")]:
		if not unique_strings(list): return false
	if not value.world.get("location_id") in ["camp","treetop","village","mill","post","heart"]: return false
	if not unique_strings(value.world.get("dialogues")) or not catalog.levels.has(value.world.get("tracked_level")): return false
	if not unique_strings(value.world.get("region_dialogues")): return false
	for id in value.world.region_dialogues:
		var dialogue = Story.region_dialogue(id)
		if dialogue.is_empty() or (dialogue.requires != "" and dialogue.requires not in progress.completed_levels): return false
	if not unique_strings(value.world.get("dismissed_recommendations")): return false
	if not value.world.get("region_positions") is Dictionary: return false
	for id in value.world.region_positions:
		if not Catalog.REGIONS.has(id) or not valid_position(value.world.region_positions[id]): return false
	for id in value.world.dismissed_recommendations:
		if not catalog.levels.has(id): return false
	if not catalog.available(value.world.tracked_level,progress.completed_levels): return false
	for id in value.world.dialogues:
		if not Story.DIALOGUES.has(id): return false
		for dependency in Story.DIALOGUES[id].requires:
			if dependency not in progress.completed_levels: return false
	if not roster.bonds is Dictionary or not roster.loadouts is Dictionary or not roster.grown is bool: return false
	if roster.party.size() < 1 or roster.party.size() > 2 or "acheng" not in roster.owned: return false
	var expected_owned = ["acheng"]
	if "FL02" in progress.completed_levels: expected_owned.append("mossling")
	if "FL08" in progress.completed_levels: expected_owned.append("feather")
	if roster.owned != expected_owned: return false
	for id in roster.party:
		if id not in roster.owned: return false
	for id in roster.owned:
		if not unique_strings(roster.bonds.get(id)) or not unique_strings(roster.loadouts.get(id)) or roster.loadouts[id].size() > 2: return false
		var expected_bonds = []
		for event in progress.completed_levels:
			if id in Roster.EVENTS.get(event,[]): expected_bonds.append(event)
		if roster.bonds[id] != expected_bonds: return false
		for bond in roster.bonds[id]:
			if bond not in progress.completed_levels or id not in Roster.EVENTS.get(bond,[]): return false
		for skill in roster.loadouts[id]:
			if skill not in Catalog.PARTNERS[id].skills: return false
			var gate = {"compare":"FL06","bands":"FL11","shadow":"FL10"}.get(skill,"")
			if gate != "" and gate not in progress.completed_levels: return false
	if roster.grown:
		for id in ["FL01","FL06","FL12"]:
			if id not in roster.bonds.acheng: return false
	var exp = 0; var wood = 0; var rewards = []
	for id in progress.completed_levels:
		if not catalog.available(id,progress.completed_levels): return false
		var reward: Dictionary = catalog.levels[id].reward
		exp += int(reward.journey_exp); wood += int(reward.camp_wood); rewards.append(reward.id)
	if progress.journey_exp != exp or progress.claimed_rewards.size() != rewards.size(): return false
	for reward in rewards:
		if reward not in progress.claimed_rewards: return false
	var items = []
	for id in progress.completed_levels:
		if Story.ITEMS.has(id): items.append(Story.ITEMS[id].id)
	if items != inventory.unique_items: return false
	for id in inventory.buildings:
		if not Catalog.BUILDINGS.has(id) or Catalog.BUILDINGS[id].requires not in progress.completed_levels: return false
		wood -= Catalog.BUILDINGS[id].cost
	if inventory.camp_wood != wood or wood < 0: return false
	if value.world.events != progress.completed_levels: return false
	var settings: Dictionary = value.settings
	if not settings.has_all(["muted","volume","short_effects","persistent_goal"]) or not settings.muted is bool or not settings.short_effects is bool or not settings.persistent_goal is bool: return false
	if not (settings.volume is int or settings.volume is float) or not is_finite(settings.volume) or settings.volume < 0 or settings.volume > 1: return false
	if not value.learning.get("observations") is Array: return false
	var observed_levels = []; var observation_keys = []
	for observation in value.learning.observations:
		if not observation is Dictionary or not observation.has_all(["run_id","level_id","concept_id","context_id","variant_id","outcome","highest_hint","hint_log","attempt_count","rewind_count","replanned_after_observation","evidence_kind","prior_help","effective_observations","observation_history","transcript","support_used"]): return false
		for key in ["run_id","level_id","concept_id","context_id","variant_id","outcome","evidence_kind"]:
			if not observation[key] is String: return false
		if not catalog.levels.has(observation.level_id) or observation.level_id not in progress.completed_levels: return false
		var observed_definition: Dictionary = catalog.legacy_fl07 if observation.level_id == "FL07" and observation.context_id == "machine_ambiguity" else catalog.levels[observation.level_id]
		if observation.concept_id not in observed_definition.concept_ids or not Numbers.integer(observation.highest_hint,0,3): return false
		if not observation.hint_log is Array or (observation.highest_hint == 0) != observation.hint_log.is_empty(): return false
		for entry in observation.hint_log:
			if not entry is Dictionary or not entry.has_all(["tier","text"]) or not Numbers.integer(entry.tier,1,observation.highest_hint) or not entry.text is String or entry.text.is_empty(): return false
		if not observation.run_id is String or observation.run_id.is_empty() or observation.context_id != observed_definition.family or observation.variant_id != "base" or observation.outcome != "complete": return false
		if not Numbers.integer(observation.attempt_count,0,1000000) or not Numbers.integer(observation.rewind_count,0,1000000) or not observation.replanned_after_observation is bool or not observation.prior_help is bool: return false
		var expected_kind = "assisted_completion" if observation.highest_hint > 0 or observation.prior_help else "independent_completion"
		if observation.evidence_kind != expected_kind or not observation.effective_observations is Array or not observation.observation_history is Array or not observation.transcript is Array or not unique_strings(observation.support_used): return false
		var observation_key = observation.run_id+"/"+observation.concept_id
		if observation_key in observation_keys: return false
		observation_keys.append(observation_key)
		if observation.level_id not in observed_levels: observed_levels.append(observation.level_id)
	for id in progress.completed_levels:
		if id not in observed_levels: return false
	var retired = value.get("legacy_fl07_runs",{})
	if not retired is Dictionary or retired.size() > 2: return false
	for id in retired:
		var old_run = retired[id]
		if not old_run is Dictionary or not old_run.has_all(["run_id","level_id","params_snapshot"]): return false
		if old_run.run_id != id or old_run.level_id != "FL07" or old_run.params_snapshot != catalog.legacy_fl07.params or not valid_run(old_run,progress.completed_levels,roster.owned): return false
	if value.active_run != null and not valid_run(value.active_run,progress.completed_levels,roster.owned): return false
	if not value.suspended_runs is Dictionary or value.suspended_runs.size() > catalog.levels.size(): return false
	for id in value.suspended_runs:
		var run = value.suspended_runs[id]
		if not valid_run(run,progress.completed_levels,roster.owned) or run.level_id != id or run.outcome != "active": return false
		if value.active_run != null and value.active_run.level_id == id: return false
	return true

func valid_run(run: Variant, completed: Array, owned: Array) -> bool:
	if not run is Dictionary or not run.has_all(["run_id","level_id","content_revision","variant_id","phase","params_snapshot","state","attempt_count","highest_hint","hint_log","outcome","party","rewind_count","replanned_after_observation","prior_help","observation_history","loadouts","support","tools","source_position"]): return false
	if not valid_position(run.source_position): return false
	if not run.content_revision is String or not run.variant_id is String or not Numbers.integer(run.phase,1,1) or not run.params_snapshot is Dictionary: return false
	if not run.run_id is String or run.run_id.is_empty() or run.content_revision != Catalog.REVISION or run.variant_id != "base" or run.phase != 1: return false
	if not run.level_id is String: return false
	if not catalog.available(run.level_id,completed): return false
	var definition: Dictionary = run_definition(run)
	if run.params_snapshot != definition.params or not Rules.valid(definition,run.state): return false
	if not Numbers.integer(run.attempt_count,0,1000000) or not Numbers.integer(run.highest_hint,0,3) or not Numbers.integer(run.rewind_count,0,1000000): return false
	if not run.hint_log is Array or (run.highest_hint == 0) != run.hint_log.is_empty(): return false
	for entry in run.hint_log:
		if not entry is Dictionary or not entry.has_all(["tier","text"]) or not Numbers.integer(entry.tier,1,run.highest_hint) or not entry.text is String or entry.text.is_empty(): return false
	if not run.replanned_after_observation is bool or not run.prior_help is bool or not unique_strings(run.party) or run.party.size() < 1 or run.party.size() > 2: return false
	if not run.observation_history is Array: return false
	if definition.family == "boss_probe_reserve":
		for observation in run.observation_history:
			if not observation is Array or observation.size() != 2 or observation[0] not in definition.params.probe_inputs: return false
			if not Numbers.integer(observation[1],-100,200): return false
			if observation[1] != Rules.ProbeBattle.output(definition.params,run.state.secret_form_id,int(observation[0])): return false
	elif not run.observation_history.is_empty(): return false
	for id in run.party:
		if id not in owned: return false
	if not run.loadouts is Dictionary or run.loadouts.size() != run.party.size(): return false
	for id in run.party:
		if not unique_strings(run.loadouts.get(id)) or run.loadouts[id].size() > 2: return false
		for skill in run.loadouts[id]:
			if skill not in Catalog.PARTNERS[id].skills: return false
	if not run.support is Dictionary or not run.support.has_all(["show_scaffold","offer_transfer","variant_id"]) or not run.support.show_scaffold is bool or not run.support.offer_transfer is bool or not run.support.variant_id is String or run.support.variant_id != "base": return false
	if not run.tools is Dictionary or not run.tools.has_all(["marks","group_items","snapshots","used","band_size","route_tags"]) or not run.tools.marks is Array or not run.tools.group_items is Array or not run.tools.snapshots is Array or not unique_strings(run.tools.used): return false
	for list in [run.tools.marks,run.tools.group_items]:
		var seen = []
		for index in list:
			if not Numbers.integer(index,0,8) or index in seen: return false
			seen.append(index)
	if run.tools.snapshots.size() > 2: return false
	if not Numbers.integer(run.tools.band_size,0,15) or not run.tools.route_tags is Dictionary: return false
	for path in run.tools.route_tags:
		if not path is String or path.length() > 6 or not Numbers.integer(run.tools.route_tags[path],0,3): return false
		for character in path:
			if character not in ["R","U"]: return false
	for snapshot in run.tools.snapshots:
		if not snapshot is Dictionary: return false
		var reconstructed = snapshot.duplicate(true)
		for key in ["secret_id","secret_form_id","enemy_response_id","opponent_seed"]:
			if run.state.has(key): reconstructed[key] = run.state[key]
		if not Rules.valid(definition,reconstructed): return false
	for skill in run.tools.used:
		if skill not in ["mark","compare","group","bands","route_tag","shadow"]: return false
	if run.outcome not in ["active","complete"]: return false
	# A settled run must still satisfy the mechanism; an active run may already be
	# solved under a relaxed completion rule and settles when it is next resumed.
	if run.outcome == "complete":
		if not Rules.complete(definition,run.state): return false
		if run.level_id not in completed: return false
	return true

func command(action: Dictionary, revision: int) -> bool:
	if repository.protected or profile.is_empty(): feedback = repository.error; return false
	if not pending.is_empty(): feedback = "未保存，请先重试。"; return false
	if revision != int(profile.revision): feedback = "画面已更新，请重新操作。"; return false
	var candidate = profile.duplicate(true); var next_history = history.duplicate(true)
	match action.get("kind"):
		"story_advance":
			if action.get("node") != candidate.story.node: return false
			var old_node: String = candidate.story.node
			var return_node: String = candidate.story.return_node
			var next = Flow.advance(candidate)
			if next == "" or (next.begins_with("puzzle_") and next != return_node): return false
			if old_node not in candidate.story.seen: candidate.story.seen.append(old_node)
			candidate.story.node = next; candidate.world.location_id = Story.scene(next).region; feedback = ""
		"story_choose":
			var id: String = action.get("level_id","")
			if candidate.story.node != "post_branch" or id not in ["FL09","FL10"] or id in candidate.progress.completed_levels: return false
			candidate.story.node = "pre_"+id
			if id not in candidate.story.choices: candidate.story.choices.append(id)
			feedback = ""
		"story_excursion":
			var id: String = action.get("level_id","")
			if candidate.story.return_node != "" or not catalog.available(id,candidate.progress.completed_levels): return false
			if id not in Flow.SIDES and id not in candidate.progress.completed_levels: return false
			candidate.story.return_node = candidate.story.node; candidate.story.return_run_id = candidate.story.run_id
			candidate.story.excursion = id; candidate.story.node = "pre_"+id; candidate.story.run_id = ""; feedback = ""
		"story_return":
			if candidate.story.return_node == "": return false
			# Leave the side challenge safely suspended, so a main puzzle can resume exactly.
			if candidate.active_run != null and candidate.active_run.outcome == "active" and candidate.active_run.level_id == candidate.story.excursion:
				candidate.suspended_runs[candidate.active_run.level_id] = candidate.active_run.duplicate(true)
				candidate.active_run = null; next_history = []
			candidate.story.node = candidate.story.return_node; candidate.story.run_id = candidate.story.return_run_id
			candidate.story.return_node = ""; candidate.story.return_run_id = ""; candidate.story.excursion = ""; feedback = ""
		"story_voyage":
			# The crossing to 千灯集市 opens only once the forest chapter is closed, and never
			# interrupts a side challenge that still has a place to return to.
			if "FL18" not in candidate.progress.completed_levels or candidate.story.node != "end": return false
			if candidate.story.return_node != "": return false
			if "end" not in candidate.story.seen: candidate.story.seen.append("end")
			candidate.story.node = "voyage"; candidate.world.location_id = "camp"; feedback = ""
		"start":
			var id = str(action.get("level_id",""))
			if action.get("narrative",false):
				if action.get("node") != candidate.story.node: return false
				if candidate.story.node not in ["pre_"+id,"puzzle_"+id]: return false
			if not catalog.available(id,candidate.progress.completed_levels) or Rules.implementation(catalog.levels[id].family) == null: feedback = "这条路还没有开放。"; return false
			var saved_source: Dictionary = candidate.suspended_runs.get(id,{})
			if candidate.active_run != null and candidate.active_run.level_id == id: saved_source = candidate.active_run
			var source_position = action.get("source_position",saved_source.get("source_position",[128,560]))
			if not valid_position(source_position): feedback = "这个交互位置不在林间道路上。"; return false
			candidate.world.region_positions[Catalog.region_for(id)] = source_position.duplicate()
			if candidate.active_run != null and candidate.active_run.outcome == "active" and candidate.active_run.level_id != id:
				candidate.suspended_runs[candidate.active_run.level_id] = candidate.active_run.duplicate(true)
				candidate.active_run = null; next_history = []
			if candidate.suspended_runs.has(id):
				candidate.active_run = candidate.suspended_runs[id]; candidate.suspended_runs.erase(id); next_history = []
			if candidate.active_run != null and candidate.active_run.outcome == "active" and candidate.active_run.level_id == id:
				if action.get("narrative",false):
					if candidate.story.node not in candidate.story.seen and candidate.story.node.begins_with("pre_"): candidate.story.seen.append(candidate.story.node)
					candidate.story.node = "puzzle_"+id; candidate.story.run_id = candidate.active_run.run_id
				candidate.world.location_id = Catalog.region_for(id); candidate.world.tracked_level = id; candidate.revision += 1
				# A run solved under an earlier, stricter rule set settles on resume.
				var restored: Dictionary = candidate.active_run
				if Rules.complete(catalog.definition(id),restored.state):
					_settle(candidate,catalog.definition(id)); next_history = []
				else: feedback = "从上次摆法继续；情形、队伍和帮助记录都保留。"
				if not validate(candidate): feedback = "保存的挑战无法恢复，原记录已保留。"; return false
				pending = candidate; pending_history = next_history
				return retry()
			var definition = catalog.definition(id)
			var loadouts = {}
			for partner in candidate.roster.party: loadouts[partner] = candidate.roster.loadouts[partner].duplicate()
			candidate.active_run = {"run_id":str(Time.get_unix_time_from_system())+"-"+str(candidate.revision),"level_id":id,"content_revision":Catalog.REVISION,"variant_id":"base","phase":1,"params_snapshot":definition.params.duplicate(true),"state":new_challenge_state(definition),"attempt_count":0,"highest_hint":0,"hint_log":[],"outcome":"active","party":candidate.roster.party.duplicate(),"rewind_count":0,"replanned_after_observation":false,"prior_help":Learning.prior_help(candidate,id),"observation_history":[],"loadouts":loadouts,"support":Selector.support_for(candidate,definition,catalog),"tools":{"marks":[],"group_items":[],"snapshots":[],"used":[],"band_size":0,"route_tags":{}}}
			if action.get("narrative",false):
				if candidate.story.node not in candidate.story.seen: candidate.story.seen.append(candidate.story.node)
				candidate.story.node = "puzzle_"+id; candidate.story.run_id = candidate.active_run.run_id
			candidate.active_run.source_position = source_position.duplicate()
			candidate.world.location_id = Catalog.region_for(id); candidate.world.tracked_level = id
			next_history = []; feedback = "和伙伴一起观察机关。"
		"rule","undo","reset","hint":
			if candidate.active_run == null or candidate.active_run.outcome != "active": feedback = "当前没有进行中的机关。"; return false
			var run: Dictionary = candidate.active_run; var definition = catalog.definition(run.level_id)
			if action.kind == "hint":
				run.highest_hint = mini(3,int(run.highest_hint)+1); feedback = Rules.hint(definition,run.state,int(run.highest_hint))
				if run.hint_log.is_empty() or run.hint_log.back().text != feedback: run.hint_log.append({"tier":run.highest_hint,"text":feedback})
			elif action.kind == "undo":
				if next_history.is_empty(): feedback = "没有可撤销步骤，可以确认重摆。"; return false
				if not run.observation_history.is_empty(): run.replanned_after_observation = true
				run.state = next_history.pop_back(); run.rewind_count += 1; feedback = "已回到上一步；提示记录保留。"
			elif action.kind == "reset":
				if action.get("confirmed") != true: feedback = "请先确认重新摆放。"; return false
				if not run.observation_history.is_empty(): run.replanned_after_observation = true
				var identity = {}
				for key in ["secret_id","enemy_response_id","secret_form_id","opponent_seed"]:
					if run.state.has(key): identity[key] = run.state[key]
				run.state = Rules.fresh(definition)
				for key in identity: run.state[key] = identity[key]
				run.rewind_count += 1; next_history = []; feedback = "已重新摆放；本次提示与尝试记录保留。"
			else:
				var result = Rules.apply(definition,run.state,action.get("action",{}))
				feedback = result.feedback
				if not result.accepted: return false
				next_history.append(run.state.duplicate(true)); run.state = result.state
				if action.action.get("kind") in ["try","travel","probe","finish","take","transfer","observe_external","reveal","combine"]: run.attempt_count += 1
				if definition.family == "boss_probe_reserve" and action.action.get("kind") == "probe":
					run.observation_history.append(run.state.active_observations.back().duplicate())
				if Rules.complete(definition,run.state): _settle(candidate,definition); next_history = []
		"camp": candidate.world.location_id = "camp"; feedback = "伙伴们在营地等你。"
		"location":
			var id = str(action.get("region",""))
			if not Catalog.REGIONS.has(id) or not valid_position(action.get("position")): return false
			candidate.world.location_id = id; candidate.world.region_positions[id] = action.position.duplicate()
			feedback = Story.region_line(id,candidate.progress.completed_levels)
		"talk_region":
			var id = str(action.get("region",""))
			if not Catalog.REGIONS.has(id) or not valid_position(action.get("position")): return false
			var dialogue_id = Story.region_dialogue_id(id,candidate.progress.completed_levels)
			if dialogue_id == "": return false
			if dialogue_id not in candidate.world.region_dialogues: candidate.world.region_dialogues.append(dialogue_id)
			candidate.world.location_id = id; candidate.world.region_positions[id] = action.position.duplicate()
			feedback = Story.region_dialogue(dialogue_id).text
		"track":
			if not catalog.available(str(action.get("level_id","")),candidate.progress.completed_levels): feedback = "这个目标还没有开放。"; return false
			candidate.world.tracked_level = action.level_id; feedback = "目标已经夹在手记首页。"
		"decline_recommendation":
			var id = str(action.get("level_id",""))
			if not catalog.levels.has(id): return false
			if id not in candidate.world.dismissed_recommendations: candidate.world.dismissed_recommendations.append(id)
			feedback = "这次先不练；主线照常，今后仍可从地区入口选择。"
		"dialogue":
			var id = str(action.get("id",""))
			if not Story.DIALOGUES.has(id) or Story.DIALOGUES[id].speaker not in candidate.roster.owned: return false
			for dependency in Story.DIALOGUES[id].requires:
				if dependency not in candidate.progress.completed_levels: return false
			if id not in candidate.world.dialogues: candidate.world.dialogues.append(id)
			feedback = Story.DIALOGUES[id].text
		"tool":
			if candidate.active_run == null or candidate.active_run.outcome != "active": return false
			var run: Dictionary = candidate.active_run
			var skill = str(action.get("skill","")); var equipped = false
			for partner in run.loadouts:
				if skill in run.loadouts[partner]: equipped = true
			if not equipped: feedback = "当前挑战没有装备这项伙伴能力；场景基本工具仍可完成。"; return false
			match skill:
				"mark":
					if not Numbers.integer(action.get("index"),0,8): return false
					if action.index in run.tools.marks: run.tools.marks.erase(action.index)
					else: run.tools.marks.append(int(action.index))
				"compare":
					var snapshot = run.state.duplicate(true)
					for key in ["secret_id","secret_form_id","enemy_response_id","opponent_seed"]: snapshot.erase(key)
					if run.tools.snapshots.size() == 2: run.tools.snapshots.pop_front()
					run.tools.snapshots.append(snapshot)
				"bands":
					if not Numbers.integer(action.get("size"),1,15): return false
					run.tools.band_size = int(action.size)
				"route_tag":
					if not run.state.has("draft") or run.state.draft == "" or not Numbers.integer(action.get("group"),0,3): feedback = "先画自己的路线，再选择要贴的层数。"; return false
					if not Rules.Routes.legal(catalog.levels[run.level_id].params,run.state.draft): feedback = "先把路线画到终点，再贴上你选择的层签。"; return false
					run.tools.route_tags[run.state.draft] = int(action.group)
				"group":
					var next = run.state.duplicate(true); var definition = catalog.definition(run.level_id)
					if run.state.has("initial"):
						if not Numbers.integer(action.get("count"),1,30) or not Numbers.integer(action.get("from"),0,2) or not Numbers.integer(action.get("to"),0,2) or action.from == action.to: return false
						for _unit in int(action.count):
							var result = Rules.apply(definition,next,{"kind":"shift","from":action.from,"to":action.to})
							if not result.accepted: feedback = "来源数量不足；整组留在原处。"; return false
							next = result.state
					elif run.state.has("places"):
						if not action.get("items") is Array or action.items.is_empty() or action.items.size() > 6: return false
						var items = []; var source = -1
						for item in action.items:
							if not Numbers.integer(item,0,5) or item in items: return false
							if source == -1: source = run.state.places[int(item)]
							if run.state.places[int(item)] != source: feedback = "这组物件需要先在同一个位置。"; return false
							items.append(int(item))
						for item in items:
							var result = Rules.apply(definition,next,{"kind":"move","item":item,"target":action.get("target")})
							if not result.accepted: feedback = "整组放不进去；每件都保留在原处。"; return false
							next = result.state
						run.tools.group_items = items
					else: feedback = "这项能力用于货运和分仓的离散物件。"; return false
					next_history.append(run.state.duplicate(true)); run.state = next
				"shadow":
					if not run.state.has("draft") or run.state.draft == "": feedback = "先画一段自己的路线。"; return false
					feedback = "折羽的影子沿着你画的路线走了一遍；没有添加新路。"
				_: return false
			if skill not in run.tools.used: run.tools.used.append(skill)
			if skill != "shadow": feedback = "伙伴记下了你的选择；没有替你选答案。"
		"party":
			if not unique_strings(action.get("members")) or action.members.size() < 1 or action.members.size() > 2: feedback = "选择一至两位同行伙伴。"; return false
			for id in action.members:
				if id not in candidate.roster.owned: feedback = "这位伙伴还没有加入。"; return false
			candidate.roster.party = action.members.duplicate(); feedback = "下次挑战使用这支队伍；当前机关的同行配置保留。"
		"equip":
			var partner = str(action.get("partner","")); var skill = str(action.get("skill",""))
			if partner not in candidate.roster.owned or skill not in Catalog.PARTNERS[partner].skills: return false
			var gate = {"compare":"FL06","bands":"FL11","shadow":"FL10"}.get(skill,"")
			if gate != "" and gate not in candidate.progress.completed_levels: feedback = "这项能力会在共同经历后解锁。"; return false
			if skill in candidate.roster.loadouts[partner]: candidate.roster.loadouts[partner].erase(skill)
			elif candidate.roster.loadouts[partner].size() < 2: candidate.roster.loadouts[partner].append(skill)
			else: return false
			feedback = "能力配置已留给下一次出发。"
		"build":
			var id = str(action.get("building",""))
			if not Catalog.BUILDINGS.has(id): return false
			var building: Dictionary = Catalog.BUILDINGS[id]
			if id in candidate.inventory.buildings or building.requires not in candidate.progress.completed_levels or candidate.inventory.camp_wood < building.cost: feedback = "请检查建设条件和木片数量。"; return false
			candidate.inventory.camp_wood -= building.cost; candidate.inventory.buildings.append(id); feedback = building.name+"建好了！"
		"grow":
			if not Roster.can_grow(candidate) or candidate.world.location_id != "camp": return false
			candidate.roster.grown = true; feedback = "阿橙系上了你们的同心叶结。"
		"settings":
			for key in action.get("values",{}):
				if not candidate.settings.has(key): return false
				candidate.settings[key] = action.values[key]
		_: feedback = "未知命令。"; return false
	candidate.revision += 1
	if not validate(candidate): feedback = "状态校验失败，操作未提交。"; return false
	pending = candidate; pending_history = next_history
	return retry()

func _settle(candidate: Dictionary, definition: Dictionary) -> void:
	var run: Dictionary = candidate.active_run; run.outcome = "complete"
	if definition.reward.id not in candidate.progress.claimed_rewards:
		candidate.progress.completed_levels.append(definition.id); candidate.world.events.append(definition.id)
		candidate.progress.claimed_rewards.append(definition.reward.id)
		candidate.progress.journey_exp += int(definition.reward.journey_exp); candidate.inventory.camp_wood += int(definition.reward.camp_wood)
		if Story.ITEMS.has(definition.id): candidate.inventory.unique_items.append(Story.ITEMS[definition.id].id)
		Roster.apply_completion(candidate,definition.id)
	Flow.settle(candidate,definition.id)
	Learning.record(candidate,run,definition)
	feedback = Story.REACTIONS.get(definition.id,"机关恢复了！发现已写入手记。")

func retry() -> bool:
	if pending.is_empty(): return not repository.protected
	if not repository.write_profile(pending,validate): feedback = repository.error; return false
	profile = pending; history = pending_history; pending = {}; pending_history = []
	return true

func new_after_protected(confirmed: bool) -> bool:
	if not confirmed or not repository.protected: return false
	var backup = repository.preserve_protected_file()
	if backup == "": feedback = repository.error; return false
	profile = fresh(); pending = profile.duplicate(true); pending_history = []; history = []
	feedback = "旧记录已原样保留为 "+backup.get_file()+"；新旅程从营地出发。"
	return retry()

func new_challenge_state(definition: Dictionary) -> Dictionary:
	var state = Rules.fresh(definition); var params: Dictionary = definition.params
	match definition.family:
		"diagnostic_probe": state.secret_id = params.candidates.keys()[randi()%params.candidates.size()]
		"heavy_coin_plan": state.secret_id = randi()%int(params.coin_count)
		"takeaway_policy": state.opponent_seed = randi()%3
		"boss_seal_duel": state.enemy_response_id = params.boss_responses[randi()%params.boss_responses.size()].id
		"boss_probe_reserve": state.secret_form_id = params.forms.keys()[randi()%params.forms.size()]
	return state

static func valid_position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Numbers.integer(value[0],100,1120) and Numbers.integer(value[1],527,574)

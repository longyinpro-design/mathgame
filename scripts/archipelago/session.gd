extends RefCounted
# One transactional owner for the campaign. Legacy adapters are read-only.
const Catalog = preload("res://scripts/archipelago/catalog.gd")
const Legacy = preload("res://scripts/archipelago/legacy_evidence.gd")
const Repository = preload("res://scripts/persistence/save_repository.gd")
const VERSION = "archipelago-1"
var repository = Repository.new()
var profile: Dictionary = {}
var pending: Dictionary = {}
var history: Dictionary = {}
var pending_history: Dictionary = {}
var pending_feedback = ""
var feedback = ""
var legacy_paths: Dictionary = {}
# Explicit isolated preview/test entry; the public campaign never enables this.
var allow_locked = false

static func fresh() -> Dictionary:
	return {"schema_version":1,"content_revision":VERSION,"revision":0,"proofs":{},"legacy_sources":{},"runs":{},"learning_runs":{},
		"completed":[],"claimed_rewards":[],"experience":0,"keepsakes":[],"roster":["acheng"],"party":["acheng"],"observations":[],
		"active":"","return_point":"","settings":{"muted":false,"volume":0.7,"short_effects":false}}

func open(path: String = "user://profiles/archipelago-v1/save-v1.json") -> bool:
	repository.path = path
	pending = {}; history = {}; pending_history = {}; pending_feedback = ""
	var result = repository.read_profile(validate)
	if result.status == "protected": feedback = repository.error; return false
	profile = result.profile if result.status == "loaded" else fresh()
	return commit(profile) if result.status == "new" else true

static func same_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

static func whole(value: Variant, maximum: int = 2147483646) -> bool:
	return value is int and value >= 0 and value <= maximum

func valid_run(id: String, run: Variant) -> bool:
	if not Catalog.is_new(id) or not same_keys(run,["run_id","content_revision","params_snapshot","stage","beat","board","highest_hint","attempts","replay","party","support_used"]): return false
	var d = Catalog.definition(id)
	if d.is_empty() or run.content_revision != VERSION or run.params_snapshot != d.params: return false
	if not run.run_id is String or not run.run_id.begins_with(id+"-") or not run.replay is bool: return false
	if not whole(run.highest_hint,4) or not whole(run.attempts,1000000) or not whole(run.beat,20): return false
	if not run.support_used is Array or run.support_used.size()>1 or (not run.support_used.is_empty() and run.support_used != ["observation_marks"]): return false
	if not run.party is Array or run.party.is_empty() or run.party.size()>2: return false
	for member in run.party:
		if not member is String or not Catalog.PARTNERS.has(member) or run.party.count(member)!=1: return false
	if run.stage not in ["intro","puzzle","outcome","complete"]: return false
	var rules = Catalog.rules_for(id)
	if rules == null or not rules.validate(run.board): return false
	if run.stage == "intro" and run.beat >= d.intro.size(): return false
	if run.stage == "outcome" and run.beat >= d.outro.size(): return false
	if run.stage in ["outcome","complete"] and not rules.solved(run.board): return false
	return true

func valid_proof(id: String, proof: Variant, sources: Dictionary = {}) -> bool:
	if not Catalog.exists(id): return false
	if not Catalog.is_new(id): return Legacy.valid_proof(id,proof,sources)
	if not same_keys(proof,["kind","run"]): return false
	return proof.kind == "authored" and valid_run(id,proof.run) and proof.run.stage in ["outcome","complete"]

func projection(proofs: Dictionary, learning_runs: Dictionary = {}) -> Dictionary:
	var done: Array = []; var claimed: Array = []; var keepsakes: Array = []; var observations: Array = []; var experience = 0
	for id in Catalog.ids():
		if not proofs.has(id): continue
		var d = Catalog.definition(id)
		if d.is_empty(): continue
		done.append(id); claimed.append(d.reward.id); experience += int(d.reward.experience)
		if not d.reward.keepsake.is_empty(): keepsakes.append(d.reward.keepsake)
		if not Catalog.is_new(id):
			observations.append({"level_id":id,"concept_ids":d.concept_ids.duplicate(),"context_id":"legacy_validated","variant_id":"historical","run_id":"", "kind":"imported_valid_completion","highest_hint":null,"attempts":null,"replay":false,"support_used":[]})
	var run_ids = learning_runs.keys(); run_ids.sort()
	for run_id in run_ids:
		var item = learning_runs[run_id]; var run = item.run; var d = Catalog.definition(item.level_id)
		observations.append({"level_id":item.level_id,"concept_ids":d.concept_ids.duplicate(),"context_id":d.mechanism,"variant_id":run.content_revision,"run_id":run_id,
			"kind":"assisted_completion" if run.highest_hint>0 else "unassisted_completion","highest_hint":run.highest_hint,"attempts":run.attempts,"replay":run.replay,"support_used":run.support_used.duplicate()})

	return {"completed":done,"claimed_rewards":claimed,"experience":experience,"keepsakes":keepsakes,"roster":Catalog.roster_for(done),"observations":observations}

func install_projection(candidate: Dictionary) -> void:
	var projected = projection(candidate.proofs,candidate.learning_runs)
	for key in projected: candidate[key] = projected[key]

func validate(value: Variant) -> bool:
	if not same_keys(value,["schema_version","content_revision","revision","proofs","legacy_sources","runs","learning_runs","completed","claimed_rewards","experience","keepsakes","roster","party","observations","active","return_point","settings"]): return false
	if value.schema_version != 1 or value.content_revision != VERSION or not whole(value.revision): return false
	if not value.proofs is Dictionary or not value.runs is Dictionary or not Legacy.valid_sources(value.legacy_sources): return false
	for id in value.proofs:
		if not id is String or not valid_proof(id,value.proofs[id],value.legacy_sources): return false
	if not value.learning_runs is Dictionary: return false
	for run_id in value.learning_runs:
		var item = value.learning_runs[run_id]
		if not same_keys(item,["level_id","run"]) or not item.level_id is String or not valid_run(item.level_id,item.run): return false
		if item.run.stage not in ["outcome","complete"] or item.run.run_id != run_id: return false
	for id in value.runs:
		if not id is String or not valid_run(id,value.runs[id]): return false
	if not value.active is String or (not value.active.is_empty() and not Catalog.exists(value.active)): return false
	if not value.return_point is String or (not value.return_point.is_empty() and not Catalog.exists(value.return_point)): return false
	if not same_keys(value.settings,["muted","volume","short_effects"]): return false
	if not value.settings.muted is bool or not value.settings.short_effects is bool: return false
	if not (value.settings.volume is int or value.settings.volume is float) or not is_finite(float(value.settings.volume)) or value.settings.volume < 0 or value.settings.volume > 1: return false
	for field in ["completed","claimed_rewards","keepsakes","roster","observations"]:
		if not value[field] is Array: return false
	if not whole(value.experience): return false
	if not value.party is Array or value.party.is_empty() or value.party.size()>2: return false
	for member in value.party:
		if not member is String or member not in value.roster or value.party.count(member)!=1: return false
	var projected = projection(value.proofs,value.learning_runs)
	for key in projected:
		if value[key] != projected[key]: return false
	return true

func commit(candidate: Dictionary, next_history: Variant = null) -> bool:
	if next_history == null: next_history = history
	if not pending.is_empty(): return false
	var value = candidate.duplicate(true)
	value.revision = profile.get("revision",0)+1
	install_projection(value)
	if not validate(value): feedback = "状态校验失败，未写入或阻塞原记录。"; return false
	if not repository.write_profile(value,validate):
		pending = value; pending_history = next_history.duplicate(true); feedback = repository.error; return false
	profile = value; history = next_history.duplicate(true); feedback = ""; return true

func retry() -> bool:
	if pending.is_empty(): return true
	if not repository.write_profile(pending,validate): feedback = repository.error; return false
	profile = pending; history = pending_history; pending = {}; pending_history = {}; feedback = pending_feedback; pending_feedback = ""; return true

func sync_legacy() -> bool:
	if profile.is_empty() or not pending.is_empty(): return false
	var found = Legacy.collect(legacy_paths); var next = profile.duplicate(true); var changed = false
	for key in found.__sources:
		if not next.legacy_sources.has(key): next.legacy_sources[key] = found.__sources[key]; changed = true
	for id in found:
		if id == "__sources": continue
		if not next.proofs.has(id): next.proofs[id] = found[id]; changed = true
	return commit(next) if changed else true

func fresh_run(id: String) -> Dictionary:
	var d = Catalog.definition(id)
	return {"run_id":id+"-"+str(profile.revision+1),"content_revision":VERSION,"params_snapshot":d.params.duplicate(true),
		"stage":"intro","beat":0,"board":Catalog.rules_for(id).fresh(),"highest_hint":0,"attempts":0,"replay":id in profile.completed,"party":profile.party.duplicate(),"support_used":[]}

func start(id: String) -> bool:
	if profile.is_empty() or not pending.is_empty() or not Catalog.exists(id): return false
	if not allow_locked and not Catalog.available(id,profile.completed): feedback = "先完成这条航路的前置任务。"; return false
	var next = profile.duplicate(true)
	if (Catalog.is_side(id) or id in profile.completed) and next.active != id: next.return_point = story_next()
	if Catalog.is_new(id) and not next.runs.has(id): next.runs[id] = fresh_run(id)
	next.active = id
	return commit(next)

func run() -> Dictionary:
	return profile.runs.get(profile.get("active",""),{}).duplicate(true)

func edit_board(action: Dictionary) -> bool:
	var current = run()
	if current.is_empty() or current.stage != "puzzle" or not pending.is_empty(): return false
	var id = profile.active; var rules = Catalog.rules_for(id)
	var board = rules.apply(current.board,action)
	if board.is_empty() or not rules.validate(board): feedback = "这个操作不符合当前机关的约定。"; return false
	if board == current.board: return false
	var next = profile.duplicate(true); next.runs[id].board = board
	var next_history = history.duplicate(true)
	if not next_history.has(id): next_history[id] = []
	next_history[id].append(current.board.duplicate(true))
	return commit(next,next_history)

func advance() -> bool:
	var current = run()
	if current.is_empty() or not pending.is_empty(): return false
	var id = profile.active; var d = Catalog.definition(id); var next = profile.duplicate(true)
	if current.stage == "intro":
		if current.beat+1 < d.intro.size() and not (current.replay and profile.settings.short_effects): next.runs[id].beat += 1
		else: next.runs[id].stage = "puzzle"; next.runs[id].beat = 0
	elif current.stage == "outcome":
		if current.beat+1 < d.outro.size() and not (current.replay and profile.settings.short_effects): next.runs[id].beat += 1
		else: next.runs[id].stage = "complete"; next.runs[id].beat = 0
	else: return false
	return commit(next)

func submit() -> bool:
	var current = run()
	if current.is_empty() or current.stage != "puzzle" or not pending.is_empty(): return false
	var id = profile.active; var rules = Catalog.rules_for(id); var next = profile.duplicate(true)
	next.runs[id].attempts = mini(1000000,current.attempts+1)
	var solved = rules.solved(current.board)
	if solved:
		next.runs[id].stage = "outcome"; next.runs[id].beat = 0
		if not next.proofs.has(id): next.proofs[id] = {"kind":"authored","run":next.runs[id].duplicate(true)}
		next.learning_runs[next.runs[id].run_id] = {"level_id":id,"run":next.runs[id].duplicate(true)}
	var answer = rules.feedback(current.board)
	var saved = commit(next)
	if saved: feedback = answer
	elif not pending.is_empty(): pending_feedback = answer
	return saved

func request_hint() -> bool:
	var current = run()
	if current.is_empty() or current.stage != "puzzle" or not pending.is_empty(): return false
	var next = profile.duplicate(true); var id = profile.active
	next.runs[id].highest_hint = mini(4,current.highest_hint+1)
	var hint = Catalog.rules_for(id).hint(current.board,next.runs[id].highest_hint)
	var saved = commit(next)
	if saved: feedback = hint
	elif not pending.is_empty(): pending_feedback = hint
	return saved

func undo() -> bool:
	var current = run(); var id = profile.get("active","")
	if current.is_empty() or current.stage != "puzzle" or not pending.is_empty() or history.get(id,[]).is_empty(): return false
	var next_history = history.duplicate(true); var previous = next_history[id].pop_back()
	var next = profile.duplicate(true); next.runs[id].board = previous
	return commit(next,next_history)

func reset_board() -> bool:
	var current = run(); var id = profile.get("active","")
	if current.is_empty() or current.stage != "puzzle" or not pending.is_empty(): return false
	var next = profile.duplicate(true); next.runs[id].board = Catalog.rules_for(id).fresh()
	var next_history = history.duplicate(true)
	if not next_history.has(id): next_history[id] = []
	next_history[id].append(current.board.duplicate(true))
	return commit(next,next_history)

func restart() -> bool:
	var current = run(); var id = profile.get("active","")
	if current.is_empty() or current.stage != "complete" or not pending.is_empty(): return false
	var next = profile.duplicate(true); next.runs[id] = fresh_run(id)
	var next_history = history.duplicate(true); next_history.erase(id)
	return commit(next,next_history)

func set_settings(values: Dictionary) -> bool:
	if profile.is_empty() or not pending.is_empty(): return false
	var next = profile.duplicate(true)
	for key in values:
		if not next.settings.has(key): return false
		next.settings[key] = values[key]
	return commit(next)

# External command boundary rejects events retained from an older rendered state.
func command(action: Dictionary, expected_revision: int) -> bool:
	if profile.is_empty() or expected_revision != profile.revision or not pending.is_empty(): return false
	match action.get("kind",""):
		"board": return edit_board(action.action) if same_keys(action,["kind","action"]) and action.action is Dictionary else false
		"advance": return advance() if same_keys(action,["kind"]) else false
		"submit": return submit() if same_keys(action,["kind"]) else false
		"hint": return request_hint() if same_keys(action,["kind"]) else false
		"undo": return undo() if same_keys(action,["kind"]) else false
		"reset": return reset_board() if same_keys(action,["kind"]) else false
		"restart": return restart() if same_keys(action,["kind"]) else false
		"start": return start(action.id) if same_keys(action,["kind","id"]) and action.id is String else false
		"settings": return set_settings(action.values) if same_keys(action,["kind","values"]) and action.values is Dictionary else false
	return false


# Optional authored practice only. No hidden ability score or unverified variant.
func recommendations() -> Array:
	var by_level: Dictionary = {}
	for fact in profile.get("observations",[]):
		if fact.kind == "imported_valid_completion": continue
		if not by_level.has(fact.level_id): by_level[fact.level_id] = {"helped":false,"unassisted":false}
		if fact.highest_hint > 0: by_level[fact.level_id].helped = true
		else: by_level[fact.level_id].unassisted = true
	var result: Array = []
	for id in Catalog.ids():
		if by_level.has(id) and by_level[id].helped and not by_level[id].unassisted:
			result.append({"level_id":id,"reason":"上次一起看过提示；可以带着图形支架再试一次，也可以继续故事。"})
	return result


func set_party(members: Array) -> bool:
	if profile.is_empty() or not pending.is_empty() or members.is_empty() or members.size()>2: return false
	for member in members:
		if member not in profile.roster or members.count(member)!=1: return false
	var next = profile.duplicate(true); next.party = members.duplicate()
	return commit(next)


func record_support() -> bool:
	var current = run()
	if current.is_empty() or current.stage != "puzzle" or not pending.is_empty(): return false
	if "observation_marks" in current.support_used: return true
	var next=profile.duplicate(true);next.runs[profile.active].support_used=["observation_marks"]
	return commit(next)


func story_next() -> String:
	# Victory is committed before its outcome dialogue; Continue must resume that
	# dialogue instead of silently jumping to the next unlocked level.
	var active=profile.get("active","")
	if profile.get("runs",{}).has(active):
		var current=profile.runs[active]
		if not Catalog.is_side(active) and not current.replay and current.stage!="complete": return active
	var returning=profile.get("return_point","")
	if profile.get("runs",{}).has(returning):
		var saved=profile.runs[returning]
		if not saved.replay and saved.stage!="complete": return returning
	return Catalog.next_main(profile.get("completed",[]))

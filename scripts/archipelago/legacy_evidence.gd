extends RefCounted
# Read-only compatibility adapter. Existing archives are never migrated or overwritten.
const Catalog = preload("res://scripts/archipelago/catalog.gd")
const Numbers = preload("res://scripts/content/content_catalog.gd")
const ForestSession = preload("res://scripts/core/game_session.gd")
const Market = preload("res://scripts/market/chapter_catalog.gd")
const Workshop = preload("res://scripts/workshop/chapter_catalog.gd")

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return null
	return Numbers.normalize_numbers(JSON.parse_string(file.get_as_text()))

static func path_for(id: String) -> String:
	match Catalog.island_for(id):
		"forest": return "user://profiles/local-1/save-v1.json"
		"market": return Market.save_path(id)
		"workshop": return Workshop.save_path(id)
	return ""

static func valid_sources(sources: Variant) -> bool:
	if not sources is Dictionary: return false
	if sources.is_empty(): return true
	var verifier = ForestSession.new()
	for key in sources:
		if not key is String or JSON.stringify(sources[key]).sha256_text() != key or not verifier.validate(sources[key]): return false
	return true

static func valid_proof(id: String, proof: Variant, sources: Dictionary = {}) -> bool:
	if not proof is Dictionary or proof.size() != 3 or not proof.has_all(["kind","board","revision"]): return false
	if not proof.board is Dictionary or proof.revision != 1: return false
	if proof.kind == "forest_history":
		if not id.begins_with("FL") or proof.board.size() != 1 or not proof.board.get("source") is String: return false
		var key = proof.board.source
		return sources.has(key) and id in sources[key].progress.completed_levels
	if proof.kind != "legacy": return false
	var island = Catalog.island_for(id)
	if island == "forest":
		var session = ForestSession.new()
		var definition = session.result_definition(id,proof.board)
		return not definition.is_empty() and session.Rules.valid(definition,proof.board) and session.Rules.complete(definition,proof.board)
	if island not in ["market","workshop"]: return false
	var rules = load("res://scripts/%s/%s_rules.gd"%[island,id.to_lower()])
	return rules.validate(proof.board) and proof.board.stage == "complete"

static func collect(paths: Dictionary = {}) -> Dictionary:
	var result = {"__sources":{}}
	var forest_path = paths.get("forest",path_for("FL01"))
	var forest = read_json(forest_path)
	if forest is Dictionary:
		var verifier = ForestSession.new()
		if verifier.validate(forest):
			for id in forest.progress.completed_levels:
				if forest.story.results.has(id):
					var proof = {"kind":"legacy","board":forest.story.results[id].duplicate(true),"revision":1}
					if valid_proof(id,proof): result[id] = proof
				if not result.has(id):
					# Old valid profiles may record a completed task without retaining a board.
					# Keep the original validated source once and label this only historical completion.
					var key = JSON.stringify(forest).sha256_text()
					result.__sources[key] = forest.duplicate(true)
					result[id] = {"kind":"forest_history","board":{"source":key},"revision":1}
	for island in ["market","workshop"]:
		for id in Catalog.ids(island):
			var board = read_json(paths.get(id,path_for(id)))
			var proof = {"kind":"legacy","board":board,"revision":1}
			if valid_proof(id,proof): result[id] = proof
	return result

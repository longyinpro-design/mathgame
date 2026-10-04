extends RefCounted
const Session = preload("res://scripts/archipelago/session.gd")
const Catalog = preload("res://scripts/archipelago/catalog.gd")
static var session: RefCounted
static var enabled = false
static var selected_island = ""
static var launching = false

static func ensure_session() -> RefCounted:
	if session == null:
		session = Session.new()
		session.open()
	return session

static func launch(tree: SceneTree, id: String) -> bool:
	if launching: return false
	var current = ensure_session()
	if not current.start(id): return false
	var d = Catalog.definition(id)
	if d.is_empty() or not ResourceLoader.exists(d.scene): current.feedback = "这处航路的场景尚未就绪。"; return false
	enabled = true; launching = true
	var result = tree.change_scene_to_file(d.scene)
	launching = false
	return result == OK

static func hub(tree: SceneTree, island: String = "") -> bool:
	if launching: return false
	var current = ensure_session()
	if not current.pending.is_empty(): return false
	if not current.sync_legacy(): return false
	selected_island = island; enabled = true; launching = true
	var result = tree.change_scene_to_file("res://game/archipelago.tscn")
	launching = false
	return result == OK

static func attach_legacy(host: Control, island: String) -> void:
	if not enabled or host.has_node("CampaignPortal"): return
	var portal = load("res://scripts/archipelago/legacy_portal.gd").new()
	portal.name = "CampaignPortal"; portal.host = host; portal.island = island
	host.add_child(portal)

static func legacy_path(id: String, fallback: String) -> String:
	if not enabled or session == null: return fallback
	return session.legacy_paths.get("forest" if id.begins_with("FL") else id,fallback)

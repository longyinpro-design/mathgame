extends RefCounted

static func status(catalog: RefCounted, profile: Dictionary, id: String) -> String:
	if id in profile.progress.completed_levels: return "resolved"
	if profile.active_run != null and profile.active_run.level_id == id: return "active"
	if profile.suspended_runs.has(id): return "active"
	return "available" if catalog.available(id,profile.progress.completed_levels) else "locked"

static func available(catalog: RefCounted, profile: Dictionary) -> Array:
	var result = []
	for id in catalog.levels:
		if status(catalog,profile,id) in ["available","active"]: result.append(id)
	return result

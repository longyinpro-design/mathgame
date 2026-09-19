extends RefCounted

const EVENTS = {
	"FL01":["acheng"], "FL06":["acheng"], "FL12":["acheng"],
	"FL03":["mossling"], "FL11":["mossling"], "FL18":["mossling"],
	"FL09":["feather"], "FL10":["feather"], "FL17":["feather"]
}

static func apply_completion(profile: Dictionary, id: String) -> void:
	var roster: Dictionary = profile.roster
	var joined = "mossling" if id == "FL02" else ("feather" if id == "FL08" else "")
	if joined != "" and joined not in roster.owned:
		roster.owned.append(joined)
		roster.bonds[joined] = []
		roster.loadouts[joined] = ["group"] if joined == "mossling" else ["route_tag"]
		if roster.party.size() < 2: roster.party.append(joined)
	for partner in EVENTS.get(id, []):
		if partner in roster.owned and id not in roster.bonds[partner]: roster.bonds[partner].append(id)
	var skill = {"FL06":["acheng","compare"],"FL11":["mossling","bands"],"FL10":["feather","shadow"]}.get(id, [])
	if not skill.is_empty() and skill[1] not in roster.loadouts[skill[0]]: roster.loadouts[skill[0]].append(skill[1])

static func can_grow(profile: Dictionary) -> bool:
	for id in ["FL01","FL06","FL12"]:
		if id not in profile.roster.bonds.acheng: return false
	return not profile.roster.grown

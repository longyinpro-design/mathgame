extends RefCounted

static func record(profile: Dictionary, run: Dictionary, definition: Dictionary) -> void:
	for concept in definition.concept_ids:
		profile.learning.observations.append({
			"run_id":run.run_id,"level_id":run.level_id,"concept_id":concept,
			"context_id":definition.family,"variant_id":run.variant_id,
			"outcome":"complete","highest_hint":run.highest_hint,
			"prior_help":run.prior_help,
			"hint_log":run.hint_log.duplicate(true),
			"attempt_count":run.attempt_count,"rewind_count":run.rewind_count,
			"replanned_after_observation":run.replanned_after_observation,
			"effective_observations":run.state.get("active_observations",[]).duplicate(true),
			"observation_history":run.observation_history.duplicate(true),
			"transcript":run.state.get("transcript",[]).duplicate(true),
			"support_used":run.tools.used.duplicate(),
			"evidence_kind":"assisted_completion" if run.highest_hint > 0 or run.prior_help else "independent_completion"
		})

static func prior_help(profile: Dictionary, id: String) -> bool:
	for observation in profile.learning.observations:
		if observation.level_id == id and observation.highest_hint > 0:
			if id == "FL07" and observation.context_id == "machine_ambiguity": continue
			return true
	return false

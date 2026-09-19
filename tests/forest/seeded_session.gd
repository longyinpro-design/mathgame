extends "res://scripts/core/game_session.gd"
# Test-only authored branch selection. All actions still use the production transaction boundary.
var seal_branch = "leaf_swap"
var tree_form = "A"
func new_challenge_state(definition: Dictionary) -> Dictionary:
	var state = super.new_challenge_state(definition)
	if definition.family == "boss_seal_duel": state.enemy_response_id = seal_branch
	if definition.family == "boss_probe_reserve": state.secret_form_id = tree_form
	return state

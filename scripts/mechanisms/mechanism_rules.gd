extends RefCounted
const TwentyFour = preload("res://scripts/mechanisms/twenty_four_rules.gd")
const Cargo = preload("res://scripts/mechanisms/cargo_rules.gd")
const Transfer = preload("res://scripts/mechanisms/transfer_rules.gd")
const Pair = preload("res://scripts/mechanisms/pair_rules.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Policy = preload("res://scripts/mechanisms/policy_rules.gd")
const Parity = preload("res://scripts/mechanisms/parity_rules.gd")
const Coins = preload("res://scripts/mechanisms/coin_rules.gd")
const Fence = preload("res://scripts/mechanisms/fence_rules.gd")
const SealBattle = preload("res://scripts/mechanisms/seal_battle_rules.gd")
const ProbeBattle = preload("res://scripts/mechanisms/probe_battle_rules.gd")
const CurrentHint = preload("res://scripts/mechanisms/current_hint.gd")

static func implementation(family: String) -> Variant:
	match family:
		"twenty_four": return TwentyFour
		"cargo","cargo_planning","cargo_optimal": return Cargo
		"doubling_transfer","temporal_transfer": return Transfer
		"pair_weights": return Pair
		"machine_records","diagnostic_probe","machine_ambiguity": return Machine
		"route_partition","route_block_choice","disjoint_route_pairs": return Routes
		"takeaway_policy": return Policy
		"parity_repair": return Parity
		"heavy_coin_plan": return Coins
		"wall_fence": return Fence
		"boss_seal_duel": return SealBattle
		"boss_probe_reserve": return ProbeBattle
	return null

static func fresh(definition: Dictionary) -> Dictionary:
	return implementation(definition.family).fresh(definition.params)

static func valid(definition: Dictionary, state: Variant) -> bool:
	var rules = implementation(definition.family)
	return rules != null and rules.valid(definition.params,state)

static func apply(definition: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	return implementation(definition.family).apply(definition.params,state,action)

static func complete(definition: Dictionary, state: Dictionary) -> bool:
	return implementation(definition.family).complete(definition.params,state)

static func hint(definition: Dictionary, state: Dictionary, tier: int) -> String:
	if definition.family == "twenty_four" and tier >= 3: return TwentyFour.hint(definition.params,state)
	return definition.hints[tier-1] if tier < 3 else CurrentHint.next(definition,state)

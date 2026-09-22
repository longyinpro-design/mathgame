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

# 提示分四档：1 问看哪里 / 2 说用哪条关系 / 3 指出关系但不给结论 / 4 才一步一报。
# 第 3 档以前直接报出下一步或答案，而档位封在 3、内容又按当前状态重算，
# 于是「连按 H」等于一份不限次数的逐步答案播报——这正是各关 shortcut_to_check
# 明说必须挡住的那条捷径。原来的逐句引导保留为第 4 档，兜底还在，只是要先想三轮。
static func hint(definition: Dictionary, state: Dictionary, tier: int) -> String:
	if tier <= 2: return definition.hints[tier-1]
	if tier == 3: return CurrentHint.guide(definition,state)
	if definition.family == "twenty_four": return TwentyFour.hint(definition.params,state)
	return CurrentHint.next(definition,state)

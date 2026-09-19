extends RefCounted

const SOURCE = "res://docs/production/forest_levels.json"
const REVISION = "forest-runtime-1"
const REGIONS = {"treetop":["FL01","FL13"],"village":["FL03","FL04"],"mill":["FL05","FL06","FL07","FL15"],"post":["FL08","FL09","FL10","FL14","FL16"],"heart":["FL02","FL11","FL12","FL17","FL18"]}
const PARAMETER_FIELDS = {
	"twenty_four":["cards","target"],
	"cargo":["weights","initial_places","left_low"],
	"cargo_planning":["weights","initial_places","left_low","max_items_per_basket","max_basket_weight","lock_delivered","goal_items","item_names"],
	"cargo_optimal":["weights","initial_places","left_low","max_items_per_basket"],
	"doubling_transfer":["total","minimum","moves","target"],
	"temporal_transfer":["total","minimum","moves","equal_after"],
	"pair_weights":["ab","bc","ac","weight_min","weight_max"],
	"machine_records":["modules","slots","records","predict_input"],
	"diagnostic_probe":["candidates","probe_inputs"],
	"machine_ambiguity":["modules","slots","records","input_domain","checkpoint"],
	"route_partition":["right","up","avoid","via","partition"],
	"route_block_choice":["right","up","candidate_blocks"],
	"disjoint_route_pairs":["right","up","avoid","via","shared_endpoints_only"],
	"takeaway_policy":["start_positions","max_take","last_taker","response_position"],
	"parity_repair":["start","moves","steps","minimum","maximum","targets","repair_target","repair_moves"],
	"heavy_coin_plan":["coin_count","max_weighings","normal_weight","heavy_weight"],
	"wall_fence":["fence_units","minimum_side"],
	"boss_seal_duel":["initial_energy","target_energy","transfer_cards","locked_core_by_turn","boss_response_after_turn","boss_responses"],
	"boss_probe_reserve":["forms","probe_inputs","max_probes","seed_budget","target_response","finisher_inputs"]
}
const PARTNERS = {
	"acheng": {"name":"阿橙", "skills":["mark", "compare"]},
	"mossling": {"name":"苔团", "skills":["group", "bands"]},
	"feather": {"name":"折羽", "skills":["route_tag", "shadow"]}
}
const BUILDINGS = {
	"roof": {"name":"营地屋顶", "cost":30, "requires":"FL04"},
	"workbench": {"name":"伙伴工台", "cost":40, "requires":"FL08"},
	"garden": {"name":"纪念花圃", "cost":50, "requires":"FL18"}
}
var legacy_fl07: Dictionary = normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://docs/production/legacy_fl07.json")))
# Results settled under earlier authored parameters stay valid through these
# fallbacks; active or suspended runs with stale parameters migrate instead.
const LEGACY_RESULT_PARAMS = {
	"FL04": {"ab":11,"bc":13,"ac":12,"weight_min":1,"weight_max":20},
	"FL07": {"cards":[2,3,4,6],"target":24},
	"FL11": {"weights":[2,3,1,2,3,4],"initial_places":[0,0,0,3,3,3],"left_low":true,"max_items_per_basket":2,"max_basket_weight":4,"lock_delivered":true},
}
var levels: Dictionary = {}
var error = ""

func _init(source_path: String = SOURCE) -> void:
	if legacy_fl07.get("id") != "FL07" or legacy_fl07.get("family") != "machine_ambiguity" or not valid_definition(legacy_fl07):
		error = "旧版第七关兼容数据不完整。"; return
	var parsed = JSON.new()
	if parsed.parse(FileAccess.get_file_as_string(source_path)) != OK or not parsed.data is Dictionary:
		error = "森林岛内容无法读取。"; return
	var source: Dictionary = normalize_numbers(parsed.data)
	if not source.get("levels") is Array or source.levels.is_empty():
		error = "缺少关卡目录。"; return
	var rewards = {}
	for item in source.levels:
		if not item is Dictionary or not item.has_all(["id","title","family","params","prerequisites_all","concept_ids","reward","hints"]):
			error = "关卡字段不完整。"; return
		if not valid_definition(item): error = "关卡参数、引用或奖励格式异常。"; return
		if levels.has(item.id) or rewards.has(item.reward.id):
			error = "关卡或奖励定义冲突。"; return
		var definition: Dictionary = item.duplicate(true)
		definition.erase("expected") # Author solutions never enter the runtime catalog.
		definition.revision = REVISION
		levels[item.id] = definition; rewards[item.reward.id] = true
	if not levels.has("FL07") or legacy_fl07.reward != levels.FL07.reward:
		error = "第七关的历史奖励契约不匹配。"; return
	var resolved: Array = []
	for _pass in levels.size():
		for id in levels:
			if id not in resolved and available(id, resolved): resolved.append(id)
	if resolved.size() != levels.size(): error = "关卡前置缺失或循环。"
	for i in range(1,19):
		if not levels.has("FL%02d"%i): error = "森林章节缺少关卡。"

func available(id: String, completed: Array) -> bool:
	if not levels.has(id): return false
	for dependency in levels[id].prerequisites_all:
		if dependency not in completed: return false
	return true

func definition(id: String) -> Dictionary:
	return levels[id].duplicate(true) if levels.has(id) else {}

static func region_for(id: String) -> String:
	for region in REGIONS:
		if id in REGIONS[region]: return region
	return "camp"

static func rank(experience: int) -> int:
	var result = 1
	for threshold in [40,100,180,280]:
		if experience >= threshold: result += 1
	return result

static func normalize_numbers(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and abs(value) < 9007199254740992.0: return int(value)
	if value is Array:
		var result = []
		for item in value: result.append(normalize_numbers(item))
		return result
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = normalize_numbers(value[key])
		return result
	return value

static func string_list(value: Variant) -> bool:
	if not value is Array: return false
	var seen = []
	for entry in value:
		if not entry is String or entry.is_empty() or entry in seen: return false
		seen.append(entry)
	return true

static func discrete(value: Variant) -> bool:
	if value is int: return value >= -1000000 and value <= 1000000
	if value is String or value is bool: return true
	if value is Array:
		for item in value:
			if not discrete(item): return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not discrete(value[key]): return false
		return true
	return false

static func valid_definition(item: Dictionary) -> bool:
	if not item.id is String or item.id.length() != 4 or not item.id.begins_with("FL") or not item.title is String or item.title.is_empty() or not PARAMETER_FIELDS.has(item.family): return false
	if not item.params is Dictionary or not item.params.has_all(PARAMETER_FIELDS[item.family]) or not discrete(item.params): return false
	if not string_list(item.prerequisites_all) or not string_list(item.concept_ids) or item.concept_ids.is_empty() or not string_list(item.hints) or item.hints.size() != 3: return false
	if not item.reward is Dictionary or not item.reward.has_all(["id","journey_exp","camp_wood"]): return false
	if not item.reward.id is String or item.reward.id != "forest.first_clear."+item.id.to_lower(): return false
	for key in ["journey_exp","camp_wood"]:
		if not item.reward[key] is int or item.reward[key] < 0 or item.reward[key] > 1000: return false
	if not item.get("tier") in ["intro","main","side","boss"] or not item.get("thinking_contract") is Dictionary or not item.thinking_contract.get("insight") is String: return false
	var p: Dictionary = item.params
	for key in ["total","minimum","maximum","ab","bc","ac","weight_min","weight_max","slots","predict_input","right","up","max_take","response_position","start","steps","repair_target","coin_count","max_weighings","normal_weight","heavy_weight","fence_units","minimum_side","boss_response_after_turn","max_probes","seed_budget","target_response","max_items_per_basket","max_basket_weight"]:
		if p.has(key) and not p[key] is int: return false
	for key in ["weights","initial_places","moves","target","equal_after","records","input_domain","candidate_blocks","avoid","via","initial_energy","target_energy","transfer_cards","locked_core_by_turn","probe_inputs","finisher_inputs","start_positions","repair_moves","targets"]:
		if p.has(key) and not (item.family == "twenty_four" and key == "target") and not integer_array(p[key]): return false
	# Cargo deliberately retains the accepted six-object demo identity; other layouts require a new rule revision.
	if item.family == "twenty_four":
		if not integer_array(p.cards) or p.cards.size() != 4 or not p.target is int or p.target != 24: return false
		for card in p.cards:
			if not card is int or card < 1 or card > 13: return false
	# Cargo retains the accepted six-object demo identity; FL11 carries the authored
	# seven-object manifest (four up-items, three counterweights).
	if item.family in ["cargo","cargo_planning","cargo_optimal"]:
		if item.family == "cargo_planning" and p.has("goal_items"):
			if p.weights != [2,3,1,2,5,4,3] or p.initial_places != [0,0,0,0,3,3,3] or p.left_low != true: return false
			if p.max_items_per_basket != 2 or p.max_basket_weight != 5 or p.lock_delivered != true: return false
			if not p.goal_items is int or p.goal_items != 4: return false
			if not p.item_names is Array or p.item_names != ["阿橙","小岚","种子","邮包","大配重","中配重","小配重"]: return false
		else:
			if p.weights != [2,3,1,2,3,4] or p.initial_places != [0,0,0,3,3,3] or p.left_low != true: return false
			if item.family != "cargo" and p.max_items_per_basket != 2: return false
			if item.family == "cargo_planning" and (p.max_basket_weight != 4 or p.lock_delivered != true): return false
	if item.family in ["machine_records","machine_ambiguity"]:
		if not p.modules is Array or not p.slots is int or p.slots < 1 or p.slots > p.modules.size() or not p.records is Array or p.records.size() != 2: return false
		var ids = []
		for module in p.modules:
			if not module is Dictionary or not module.has_all(["id","op"]) or not module.id is String or module.id in ids or not valid_operations([module.op]): return false
			ids.append(module.id)
		for record in p.records:
			if not record is Array or record.size() != 2 or not record[0] is int or not record[1] is int: return false
	if item.family == "diagnostic_probe":
		if not p.candidates is Dictionary or p.candidates.is_empty(): return false
		if p.probe_inputs != [2,5,6] or p.candidates.size() != 3 or not p.candidates.has_all(["A","B","C"]): return false
		for operations in p.candidates.values():
			if not valid_operations(operations): return false
	if item.family == "machine_ambiguity":
		if not p.checkpoint is Dictionary or not p.checkpoint.has_all(["input","after_step","value"]): return false
		for key in ["input","after_step","value"]:
			if not p.checkpoint[key] is int: return false
		if p.checkpoint.after_step < 0 or p.checkpoint.after_step > p.slots: return false
	if item.family == "boss_probe_reserve":
		if not p.forms is Dictionary or p.forms.size() != 4: return false
		for form in p.forms.values():
			if not form is Dictionary or not form.get("name") is String or not valid_operations(form.get("operations")): return false
		if p.probe_inputs != [2,5,6] or p.finisher_inputs != [2,3,4,5,6,7,8] or p.max_probes != 2 or p.seed_budget != 15 or p.target_response != 20: return false
	if item.family in ["doubling_transfer","temporal_transfer"]:
		if p.total < 3 or p.minimum < 1 or p.minimum*3 > p.total: return false
		var expected_moves = 3 if item.family == "doubling_transfer" else 2
		if p.moves.size() != expected_moves: return false
		for move in p.moves:
			if not move is Array or move.size() != (2 if expected_moves == 3 else 3) or move[0] < 0 or move[0] > 2 or move[1] < 0 or move[1] > 2 or move[0] == move[1]: return false
			if move.size() == 3 and move[2] < 1: return false
		if item.family == "doubling_transfer" and (p.target.size() != 3 or p.target[0]+p.target[1]+p.target[2] != p.total): return false
		if item.family == "temporal_transfer":
			if p.equal_after.size() != 2: return false
			for pair in p.equal_after:
				if not pair is Array or pair.size() != 2 or pair[0] not in [0,1,2] or pair[1] not in [0,1,2]: return false
	if item.family == "pair_weights" and (p.weight_min < 1 or p.weight_max < p.weight_min or p.ab < 1 or p.bc < 1 or p.ac < 1): return false
	if item.family in ["route_partition","route_block_choice","disjoint_route_pairs"]:
		if p.right != 3 or p.up not in [2,3]: return false
		if p.has("candidate_blocks"):
			if p.candidate_blocks.size() != 4: return false
			for point in p.candidate_blocks:
				if not point is Array or point.size() != 2 or point[0] < 0 or point[0] > p.right or point[1] < 0 or point[1] > p.up: return false
	if item.family == "takeaway_policy" and (p.start_positions != [13,14,15] or p.max_take != 3 or p.last_taker != "wins"): return false
	if item.family == "parity_repair" and (p.start != 0 or p.moves != [-2,2] or p.steps != 5 or p.minimum != 0 or p.maximum != 10 or p.targets != [8,9,10] or p.repair_target != 9 or p.repair_moves != [-1,1]): return false
	if item.family == "heavy_coin_plan" and (p.coin_count != 9 or p.max_weighings != 2 or p.normal_weight != 1 or p.heavy_weight != 2): return false
	if item.family == "wall_fence" and (p.fence_units != 12 or p.minimum_side != 1): return false
	if item.family == "boss_seal_duel":
		if p.initial_energy != [2,8,11] or p.target_energy != [7,7,7] or p.transfer_cards != [1,2,3] or p.locked_core_by_turn != [0,1,2] or p.boss_response_after_turn != 1 or not p.boss_responses is Array or p.boss_responses.size() != 2: return false
		var response_ids = []
		for response in p.boss_responses:
			if not response is Dictionary or not response.has_all(["id","permutation"]) or response.id not in ["stomp","leaf_swap"] or response.id in response_ids: return false
			if response.permutation != ([0,1,2] if response.id == "stomp" else [0,2,1]): return false
			response_ids.append(response.id)
	return true

static func integer_array(value: Variant) -> bool:
	if not value is Array: return false
	for item in value:
		if item is Array:
			if not integer_array(item): return false
		elif not item is int: return false
	return true

static func valid_operations(operations: Variant) -> bool:
	if not operations is Array or operations.is_empty(): return false
	for operation in operations:
		if not operation is Array or operation.size() != 2 or operation[0] not in ["add","sub","mul"] or not operation[1] is int: return false
	return true

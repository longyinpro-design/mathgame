extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")

static func fresh(params: Dictionary) -> Dictionary:
	return {"energy":params.initial_energy.duplicate(),"remaining_cards":params.transfer_cards.duplicate(),"turn_index":0,"enemy_response_id":params.boss_responses[0].id,"response_applied":false,"transcript":[],"battle_phase":"turns","won":false}

static func response(params: Dictionary, id: String) -> Dictionary:
	for candidate in params.boss_responses:
		if candidate.id == id: return candidate
	return {}

static func move_turn(params: Dictionary, state: Dictionary, card: int, source: int, target: int) -> Dictionary:
	var next = state.duplicate(true)
	var before: Array = next.energy.duplicate()
	next.energy[source] -= card; next.energy[target] += card
	var after_player: Array = next.energy.duplicate()
	var enemy = ""
	if next.turn_index+1 == params.boss_response_after_turn:
		var permutation: Array = response(params,next.enemy_response_id).permutation
		next.energy = [after_player[int(permutation[0])],after_player[int(permutation[1])],after_player[int(permutation[2])]]
		next.response_applied = true; enemy = next.enemy_response_id
	next.remaining_cards.erase(card); next.turn_index += 1
	next.transcript.append({"card":card,"from":source,"to":target,"before":before,"after_player":after_player,"enemy":enemy,"after":next.energy.duplicate()})
	if next.turn_index == params.locked_core_by_turn.size(): next.battle_phase = "ready" if next.energy == params.target_energy else "exhausted"
	return next

static func legal_action(params: Dictionary, state: Dictionary, card: Variant, source: Variant, target: Variant) -> bool:
	if state.battle_phase != "turns" or state.turn_index >= params.locked_core_by_turn.size() or card not in state.remaining_cards: return false
	if not Numbers.integer(source,0,2) or not Numbers.integer(target,0,2) or source == target: return false
	var locked = params.locked_core_by_turn[int(state.turn_index)]
	return source != locked and target != locked and state.energy[int(source)] >= card

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["energy","remaining_cards","turn_index","enemy_response_id","response_applied","transcript","battle_phase","won"]): return false
	if not state.energy is Array or not state.remaining_cards is Array or not Numbers.integer(state.turn_index,0,3) or not state.enemy_response_id is String or response(params,state.enemy_response_id).is_empty() or not state.response_applied is bool or not state.transcript is Array or state.transcript.size() > 3 or not state.won is bool: return false
	var replay = fresh(params); replay.enemy_response_id = state.enemy_response_id
	for row in state.transcript:
		if not row is Dictionary or not row.has_all(["card","from","to","before","after_player","enemy","after"]) or not legal_action(params,replay,row.card,row.from,row.to): return false
		replay = move_turn(params,replay,int(row.card),int(row.from),int(row.to))
		if replay.transcript.back() != row: return false
	if state.won:
		if replay.battle_phase != "ready": return false
		replay.won = true; replay.battle_phase = "victory"
	return replay == state

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	if action.get("kind") == "transfer":
		if not legal_action(params,state,action.get("card"),action.get("from"),action.get("to")): return {"accepted":false,"feedback":"这张符已用完、送出盘数量不足，或碰到了本回合封住的盘。"}
		var next = move_turn(params,state,int(action.card),int(action.from),int(action.to))
		var feedback = "符石已落位；看看下一回合封住哪座盘。"
		if state.turn_index == 0: feedback = "石灵甩叶，B/C能量互换！看清新数量，再决定下一张符。" if next.enemy_response_id == "leaf_swap" else "石灵跺脚，能量保持；下一回合封住B盘。"
		if next.battle_phase == "exhausted": feedback = "符石用完了，三盘还没有同步。可以撤销，重新留出后手。"
		if next.battle_phase == "ready": feedback = "三盘同时亮起7枚光晶！树甲张开，准备合力反击。"
		return {"accepted":true,"state":next,"feedback":feedback}
	if action.get("kind") == "finish":
		if state.battle_phase != "ready" or state.remaining_cards.size() != 0 or state.energy != params.target_energy: return {"accepted":false,"feedback":"需要三盘同时为7，而且三枚符都用完，才能合力反击。"}
		var next = state.duplicate(true); next.won = true; next.battle_phase = "victory"
		return {"accepted":true,"state":next,"feedback":"树甲化作落叶，石灵抬起树根为你们让路。"}
	return {"accepted":false,"feedback":"未知接招动作。"}

static func complete(_params: Dictionary, state: Dictionary) -> bool:
	return state.won

static func winning_tail(params: Dictionary, state: Dictionary) -> Array:
	if state.battle_phase == "ready": return [{"kind":"finish"}]
	if state.battle_phase != "turns": return []
	for card in state.remaining_cards:
		for source in range(3):
			for target in range(3):
				if not legal_action(params,state,card,source,target): continue
				var next = move_turn(params,state,card,source,target)
				var tail = winning_tail(params,next)
				if not tail.is_empty(): return [{"kind":"transfer","card":card,"from":source,"to":target}]+tail
	return []

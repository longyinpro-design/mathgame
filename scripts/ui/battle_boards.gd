extends RefCounted
const Widgets = preload("res://scripts/ui/puzzle_boards.gd")
const Probe = preload("res://scripts/mechanisms/probe_battle_rules.gd")

static func draw(host: Control, definition: Dictionary, run: Dictionary) -> void:
	host.world.visible = false; host.battle_world.visible = true
	host.battle_world.family = definition.family; host.battle_world.params = definition.params; host.battle_world.state = run.state
	host.battle_world.selected_core = host.selected_core; host.battle_world.selected_card = host.selected_card
	if definition.family == "boss_seal_duel": draw_seal(host,definition,run)
	else: draw_probe(host,definition,run)

static func draw_seal(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var enabled = run.outcome == "active"
	var phase = state.battle_phase
	host.text("%s · 三盘目标均为7"%("第%d回合"%(state.turn_index+1) if phase == "turns" else "反击时刻"),Rect2(42,137,596,37),22)
	host.text("封盘顺序 A → B → C；首回合后可能跺脚或交换B/C。",Rect2(602,137,632,46),20)
	for card in definition.params.transfer_cards:
		host.button("card_"+str(card),("✓ " if host.selected_card == card else "")+str(card)+"枚转移符",Rect2(274+(card-1)*251,533,214,46),func(): host.selected_card = card; host.selected_core = -1; host.refresh(),enabled and card in state.remaining_cards and phase == "turns")
	for i in range(3):
		var core = host.button("core_"+str(i),"",Rect2(host.battle_world.CENTERS[i]-Vector2(79,79),Vector2(158,158)),host.select_core.bind(i),enabled and phase == "turns" and definition.params.locked_core_by_turn[int(state.turn_index)] != i)
		preload("res://scripts/cargo/skin.gd").hotspot(core,"选择"+["A","B","C"][i]+"盘")
	if phase == "ready": host.button("finish","合力反击",Rect2(1004,534,236,47),host.rule.bind({"kind":"finish"}),enabled)
	if phase == "exhausted": host.text("三枚符用完，能量仍未同步；可撤销或重摆。",Rect2(274,493,924,33),20)

static func draw_probe(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var enabled = run.outcome == "active"
	var index = 0
	for id in definition.params.forms:
		host.text(id+" "+definition.params.forms[id].name+"："+Widgets.operation_text(definition.params.forms[id].operations),Rect2(44+index*311,140,302,66),20)
		index += 1
	host.text("有效侦察 %d/2 · 剩余%d颗 · 合击须恰20"%[state.probe_count,state.seed_balance],Rect2(41,208,922,42),22)
	if state.battle_phase == "probing":
		for i in definition.params.probe_inputs.size():
			var value: int = definition.params.probe_inputs[i]
			host.button("probe_"+str(value),"侦察 · %d颗"%value,Rect2(585+i*213,521,190,47),host.rule.bind({"kind":"probe","value":value}),enabled and state.probe_count < definition.params.max_probes and state.seed_balance >= value)
	elif state.battle_phase == "identified":
		var id: String = Probe.candidates(definition.params,state)[0]
		host.text("芽眼显露："+definition.params.forms[id].name+"。选择合击种子数。",Rect2(546,455,670,44),22)
		for value in range(2,9): host.button("finish_"+str(value),str(value)+"颗",Rect2(583+(value-2)*89,521,78,47),host.rule.bind({"kind":"finish","value":value}),enabled and state.seed_balance >= value)
	elif state.battle_phase == "missed": host.text("合击回响%d，未能唤醒；撤销这次合击，再调整种子数。"%state.finisher[1],Rect2(550,508,654,69),22)

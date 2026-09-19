extends RefCounted
const Numbers = preload("res://scripts/cargo/rules.gd")

static func fresh(params: Dictionary) -> Dictionary:
	return {"start":params.start_positions[0],"remaining":params.start_positions[0],"transcript":[],"opponent_seed":0,"winner":"","openings":[0,0,0],"responses":[0,0,0]}

static func opponent_take(remaining: int, turn: int, seed: int, maximum: int) -> int:
	var winning = remaining%(maximum+1)
	return winning if winning > 0 else 1+(seed+turn)%mini(maximum,remaining)

static func valid(params: Dictionary, state: Variant) -> bool:
	if not state is Dictionary or not state.has_all(["start","remaining","transcript","opponent_seed","winner","openings","responses"]): return false
	if state.start not in params.start_positions or not Numbers.integer(state.remaining,0,state.start) or not Numbers.integer(state.opponent_seed,0,2) or state.winner not in ["","player","opponent"]: return false
	if not state.transcript is Array or state.transcript.size() > state.start or not state.openings is Array or not state.responses is Array or state.openings.size() != 3 or state.responses.size() != 3: return false
	for value in state.openings+state.responses:
		if not Numbers.integer(value,0,params.max_take): return false
	var remaining = int(state.start); var winner = ""
	for turn in state.transcript.size():
		var row = state.transcript[turn]
		if not row is Array or row.size() != 2 or winner != "" or not Numbers.integer(row[0],1,mini(params.max_take,remaining)): return false
		if not Numbers.integer(row[1],0,params.max_take): return false
		remaining -= int(row[0])
		if remaining == 0:
			if row[1] != 0: return false
			winner = "player"; continue
		var expected = opponent_take(remaining,turn,state.opponent_seed,params.max_take)
		if row[1] != expected: return false
		remaining -= expected
		if remaining == 0: winner = "opponent"
	return remaining == state.remaining and winner == state.winner

static func apply(params: Dictionary, state: Dictionary, action: Dictionary) -> Dictionary:
	var next = state.duplicate(true); var feedback = "策略卡已记下；每种回应都要留后手。"
	match action.get("kind"):
		"take":
			if next.winner != "" or not Numbers.integer(action.get("value"),1,mini(params.max_take,next.remaining)): return {"accepted":false,"feedback":"每次取1至3颗，不能超过剩下的数量。"}
			var take = int(action.value); next.remaining -= take
			var opponent = 0
			if next.remaining == 0: next.winner = "player"
			else:
				opponent = opponent_take(next.remaining,next.transcript.size(),next.opponent_seed,params.max_take)
				next.remaining -= opponent
				if next.remaining == 0: next.winner = "opponent"
			next.transcript.append([take,opponent])
			var lines = ["守门人敲了敲棋盘，取走 %d 颗。"%opponent,
				"守门人想了想，把 %d 颗拢到一边。"%opponent,
				"守门人盯着剩下的棋子，取走 %d 颗。"%opponent]
			var flavor = lines[(next.transcript.size()-1)%lines.size()]
			feedback = "你取%d颗；%s"%[take,flavor]
			if next.remaining > 0:
				feedback += "还剩 %d 颗。"%next.remaining
				if next.remaining%4 == 0: feedback += "（正好是4的倍数——他占了上风。）"
			else: feedback = "你取%d颗；%s" % [take,"守门人没有棋子可取了。" if next.winner == "player" else flavor]
		"opening","response":
			if not Numbers.integer(action.get("index"),0,2) or not Numbers.integer(action.get("value"),1,params.max_take): return {"accepted":false,"feedback":"策略卡只能填合法取数。"}
			if action.kind == "opening": next.openings[int(action.index)] = int(action.value)
			else: next.responses[int(action.index)] = int(action.value)
		_: return {"accepted":false,"feedback":"未知守门人动作。"}
	return {"accepted":true,"state":next,"feedback":feedback}

static func covers_all(remaining: int, responses: Array, maximum: int) -> bool:
	if remaining == 0: return true
	for opponent in range(1,mini(maximum,remaining)+1):
		var after = remaining-opponent
		if after == 0: return false
		var player = int(responses[opponent-1])
		if player < 1 or player > mini(maximum,after): return false
		if not covers_all(after-player,responses,maximum): return false
	return true

static func complete(params: Dictionary, state: Dictionary) -> bool:
	if state.winner != "player" or params.start_positions.is_empty(): return false
	return state.start == int(params.start_positions[0])

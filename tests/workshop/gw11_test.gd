extends SceneTree
const R = preload("res://scripts/workshop/gw11_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
# 独立 oracle 只照设计题面重写一遍，不复用被测代码的任何判定函数：
# 六格开工拍各从 0 排到 15，逐条判到料、首尾相接、各自船票、共用装配台、吊机与台面。
const ORACLE_ASM = [2,3]
const ORACLE_COOL = [3,2]
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW11 rules watchdog fired")
		print("GW11 RULES: ",checks," checks, ",failures+1," failures")
		quit(1)
		return true
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")

func puzzle() -> Dictionary:
	var s = R.fresh()
	while s.stage != "puzzle": s = R.advance(s)
	return s
# 直接照六个开工拍与船票拼一个 puzzle 状态，用来逐格对照。
# 顺序是 A 装配、A 冷却、A 装船、B 装配、B 冷却、B 装船。
func state_of(ticket: int, starts: Array) -> Dictionary:
	var s = puzzle()
	s.ticket = ticket
	s.assembly = [starts[0],starts[3]]
	s.cool = [starts[1],starts[4]]
	s.load = [starts[2],starts[5]]
	return s

# ---- 独立 oracle ----
func oracle_ok(ticket: int, starts: Array) -> bool:
	for value in starts:
		if value < 6 or value > 15: return false
	if starts[1] != starts[0]+ORACLE_ASM[0] or starts[2] != starts[1]+ORACLE_COOL[0]: return false
	if starts[4] != starts[3]+ORACLE_ASM[1] or starts[5] != starts[4]+ORACLE_COOL[1]: return false
	if starts[2] != 12 or starts[5] != ticket: return false
	if starts[2]+1 > 16 or starts[5]+1 > 16: return false
	if starts[0] < starts[3]+ORACLE_ASM[1] and starts[3] < starts[0]+ORACLE_ASM[0]: return false
	if starts[2] < starts[5]+1 and starts[5] < starts[2]+1: return false
	return true
func oracle_chained(starts: Array) -> bool:
	return starts[1] == starts[0]+ORACLE_ASM[0] and starts[2] == starts[1]+ORACLE_COOL[0] \
		and starts[4] == starts[3]+ORACLE_ASM[1] and starts[5] == starts[4]+ORACLE_COOL[1]
func oracle_tickets(ticket: int, starts: Array) -> bool:
	return starts[2] == 12 and starts[5] == ticket
func oracle_table_conflict(starts: Array) -> bool:
	return starts[0] < starts[3]+ORACLE_ASM[1] and starts[3] < starts[0]+ORACLE_ASM[0]
func oracle_crane_conflict(starts: Array) -> bool:
	return starts[2] < starts[5]+1 and starts[5] < starts[2]+1
# 最笨的枚举：六格各从 0 排到 15；只有船票那条先在最外层筛掉，
# 其余每条都在 oracle_ok 里独立判过。装配台、吊机与首尾相接一条都不省。
func oracle_plans() -> Array:
	var out = []
	for ticket in [13,14]:
		for a_load in range(16):
			for b_load in range(16):
				if a_load != 12 or b_load != ticket: continue
				for a_asm in range(16):
					for a_cool in range(16):
						for b_asm in range(16):
							for b_cool in range(16):
								var starts = [a_asm,a_cool,a_load,b_asm,b_cool,b_load]
								if oracle_ok(ticket,starts): out.append({"ticket":ticket,"starts":starts})
	return out

func run() -> void:
	# ---- 独立 oracle：唯一解与 13 拍票的反例 ----
	var plans = oracle_plans()
	check(plans.size() == 1,"the brute-force oracle finds exactly one plan")
	var only = plans[0]
	check(only.ticket == 14,"the only plan takes the 14-beat ticket")
	check(only.starts == [7,9,12,9,12,14],"the only plan is A 7/9/12 with B 9/12/14")
	var thirteen = [7,9,12,8,11,13]
	check(not oracle_ok(13,thirteen),"the oracle rejects the 13-beat ticket plan")
	check(oracle_chained(thirteen),"the 13-beat plan is seamless batch by batch")
	check(oracle_tickets(13,thirteen),"the 13-beat plan sits on both tickets")
	check(oracle_table_conflict(thirteen),"the 13-beat plan collides on the shared table")
	check(not oracle_crane_conflict(thirteen),"the 13-beat plan never collides on the crane")
	check(not oracle_ok(13,[7,9,12,9,12,14]),"the 14-beat plan does not fit the 13-beat ticket")
	check(not oracle_ok(14,[6,8,11,6,9,11]),"starting both batches at arrival is not a plan")
	check(not oracle_ok(14,[7,8,11,9,12,14]),"a gap inside a batch is not a plan")
	# ---- 规则模块与 oracle 对齐 ----
	var answer = state_of(14,only.starts)
	check(R.validate(answer),"the oracle's plan is schema-legal")
	check(R.solved(answer),"rules accept the oracle's only plan")
	check(R.shortfalls(answer).is_empty(),"the real answer has no shortfall")
	check(R.advance(answer).stage == "delivery","the real answer submits into delivery")
	var rejected = state_of(13,thirteen)
	check(R.validate(rejected),"the rejected plan is still a legal puzzle state")
	check(not R.solved(rejected),"rules reject the 13-beat ticket plan")
	var gaps = R.shortfalls(rejected)
	check(gaps.size() == 1,"the 13-beat plan has exactly one shortfall")
	check("装配台" in gaps[0] and "重叠" in gaps[0],"the rejection names the shared table")
	check("7～9" in gaps[0] and "8～11" in gaps[0],"the rejection names both assembly intervals")
	check(R.advance(rejected).is_empty(),"the 13-beat plan cannot be submitted")
	check(not R.solved(state_of(14,[6,8,11,6,9,11])),"the opening draft is not a solution")
	check(not R.solved(state_of(14,[7,9,12,9,13,14])),"a broken B seam is not a solution")
	check(not R.solved(state_of(13,[7,9,12,9,12,14])),"the answer under the 13-beat ticket is not a solution")
	# ---- 逐格：从唯一解出发把每一格改成 0～15，规则判定必须与 oracle 一致 ----
	for ticket in [13,14]:
		for batch in range(2):
			for row in range(3):
				for value in range(16):
					var probe = only.starts.duplicate()
					probe[batch*3+row] = value
					var expected = oracle_ok(ticket,probe)
					var s = state_of(ticket,probe)
					check(R.solved(s) == expected,"cell %d/%d = %d agrees with the oracle"%[batch,row,value])
					check(R.shortfalls(s).is_empty() == expected,"shortfalls agree for cell %d/%d = %d"%[batch,row,value])
	# ---- 操作：从开局草稿一步步排到唯一解 ----
	var s = puzzle()
	check(not R.solved(s),"the opening draft is not solved")
	check(R.shortfalls(s)[0].begins_with("先在两张船票里"),"an unchosen ticket is named first")
	check("装配台" in " ".join(R.shortfalls(s)),"the draft clash on the shared table is reported")
	s = R.choose_ticket(s,14)
	check(s.ticket == 14 and R.validate(s),"choosing the 14-beat ticket")
	check(R.choose_ticket(s,14).is_empty(),"re-choosing the same ticket is a no-op")
	var switched = R.choose_ticket(s,13)
	check(switched.ticket == 13,"switching to the other ticket is allowed")
	s = R.choose_ticket(switched,14)
	check(s.ticket == 14,"switching back to the 14-beat ticket")
	var moves = [[0,0,1],[0,1,1],[0,2,1],[1,0,3],[1,1,3],[1,2,3]]
	for move in moves:
		for i in range(move[2]):
			var next = R.step_start(s,move[0],move[1],1)
			check(not next.is_empty(),"stepping %s batch %s up stays legal"%[R.BATCHES[move[0]],R.STAGE_NAMES[move[1]]])
			s = next
	check(R.solved(s),"the six cells can be walked from the draft to the only plan")
	check(s.assembly == [7,9] and s.cool == [9,12] and s.load == [12,14],"the walked plan is the oracle's plan")
	check(R.validate(s),"the walked plan is schema-legal")
	# ---- 守卫：只在 puzzle 里动手，越界与重复一律拒绝 ----
	check(R.choose_ticket(R.fresh(),13).is_empty(),"no ticket choice during dialogue")
	check(R.step_start(R.fresh(),0,0,1).is_empty(),"no stepping a start during dialogue")
	check(R.set_start(R.fresh(),0,0,7).is_empty(),"no setting a start during dialogue")
	var s13 = R.choose_ticket(puzzle(),13)
	check(R.choose_ticket(s13,0).is_empty(),"ticket 0 is not a printed ticket")
	check(R.choose_ticket(s13,12).is_empty() and R.choose_ticket(s13,15).is_empty(),"only the two printed tickets exist")
	check(R.set_start(s13,0,0,16).is_empty() and R.set_start(s13,0,0,-1).is_empty(),"starts outside 0..15 are refused")
	check(R.set_start(s13,-1,0,7).is_empty() and R.set_start(s13,2,0,7).is_empty(),"only two batches exist")
	check(R.set_start(s13,0,3,7).is_empty(),"only three stages exist")
	check(R.set_start(s13,0,0,6).is_empty(),"setting the same value is a no-op")
	check(R.step_start(state_of(14,[0,2,5,0,3,5]),0,0,-1).is_empty(),"stepping clamps at 0")
	check(R.step_start(state_of(14,[15,15,15,15,15,15]),0,0,1).is_empty(),"stepping clamps at 15")
	# ---- 到料、首尾相接与三条共用带各自念得清 ----
	var early = state_of(14,[5,7,10,9,12,14])
	check(not R.solved(early),"work cannot start before the material lands")
	check("第 6 拍才送到" in R.shortfalls(early)[0],"the arrival beat is named")
	var gap = state_of(14,[7,10,12,9,12,14])
	check(not R.solved(gap),"a gap between assembly and cooling is refused")
	check("首尾相接" in R.shortfalls(gap)[0],"the seam is named")
	var crowded = state_of(14,[7,8,11,9,12,14])
	check(not R.solved(crowded),"cooling cannot start before assembly ends")
	check("第 9 拍才装配完" in R.shortfalls(crowded)[0],"the real assembly end is named")
	var late = state_of(14,[7,9,12,9,12,15])
	check(not R.solved(late),"a batch cannot board the other ticket")
	check("第 14 拍开船" in " ".join(R.shortfalls(late)),"the printed ticket is named")
	var crane = state_of(13,[7,9,12,7,10,12])
	var crane_clash = R.clash(crane,2)
	check(crane_clash.has("from") and crane_clash.from == 12 and crane_clash.to == 13,"the crane clash is measured")
	check("吊机" in " ".join(R.shortfalls(crane)),"two batches cannot share the crane")
	for ticket in R.TICKETS:
		var plan = state_of(ticket,only.starts if ticket == 14 else thirteen)
		check(R.clash(plan,2).is_empty(),"the crane never overlaps on the printed tickets")
	# ---- 撤销、重摆与提示级别 ----
	var snap = {"ticket":13,"assembly":[6,6],"cool":[8,9],"load":[11,11]}
	check(R.restore(s,snap).ticket == 13,"undo restores the ticket")
	check(R.restore(s,snap).assembly == [6,6] and R.restore(s,snap).cool == [8,9],"undo restores the starts")
	check(R.restore(s,snap).load == [11,11],"undo restores the load starts")
	check(R.restore(R.fresh(),snap).is_empty(),"no undo during dialogue")
	check(R.restore(puzzle(),{"ticket":13,"assembly":[6,6]}).is_empty(),"a partial snapshot is refused")
	check(R.restore(puzzle(),{"ticket":12,"assembly":[6,6],"cool":[8,9],"load":[11,11]}).is_empty(),"a corrupt snapshot is refused")
	check(R.restore(puzzle(),{"ticket":13,"assembly":"x","cool":[8,9],"load":[11,11]}).is_empty(),"a corrupt start list is refused")
	check(R.restore(puzzle(),{"ticket":13,"assembly":[6,16],"cool":[8,9],"load":[11,11]}).is_empty(),"an out-of-range snapshot is refused")
	var helped = state_of(14,only.starts); helped.hint = 4
	check(R.restore(helped,snap).hint == 4,"undo retains help")
	# ---- 阶段推进 ----
	var delivery = R.advance(answer)
	check(R.validate(delivery),"delivery is schema-legal")
	check(R.advance(delivery).stage == "aftermath","delivery stops for dialogue")
	var done = R.advance(delivery)
	check(done.stage == "aftermath" and done.beat == 0,"aftermath starts at beat 0")
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	check(R.advance(done).is_empty(),"nothing follows complete")
	check(R.advance(answer).stage == "delivery" and R.advance(R.advance(answer)).stage == "aftermath","one submission advances exactly one stage")
	# ---- 伪造、越界、重复与旧 sample 一律拒绝 ----
	for stage in ["delivery","aftermath","complete"]:
		var good = state_of(14,only.starts); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = state_of(14,[7,9,12,8,11,13]); forged.stage = stage
		check(not R.validate(forged),"forged %s rejected"%stage)
		var off_ticket = state_of(13,[7,9,12,9,12,14]); off_ticket.stage = stage
		check(not R.validate(off_ticket),"the answer under the 13-beat ticket is rejected at %s"%stage)
		var half = state_of(14,[7,9,12,9,12,15]); half.stage = stage
		check(not R.validate(half),"a plan that misses B's ticket is rejected at %s"%stage)
	check(R.validate(state_of(14,[7,9,12,8,11,13])),"the 13-beat plan is legal while it is still being arranged")
	check(R.validate(puzzle()),"the opening draft is schema-legal")
	for bad_ticket in [-1,1,12,15,1.5,true,"14"]:
		var c = puzzle(); c.ticket = bad_ticket
		check(not R.validate(c),"invalid ticket rejected")
	for bad in [[7,9,12],[7,16],[-1,9],[7,1.5],[true,9],{"a":7},"7,9"]:
		var a = state_of(14,only.starts); a.assembly = bad
		check(not R.validate(a),"invalid assembly rejected")
		var b = state_of(14,only.starts); b.cool = bad
		check(not R.validate(b),"invalid cool rejected")
		var c = state_of(14,only.starts); c.load = bad
		check(not R.validate(c),"invalid load rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = state_of(14,only.starts); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	for bad_hint in [-1,5,1.0,true]:
		var c = state_of(14,only.starts); c.hint = bad_hint
		check(not R.validate(c),"invalid hint rejected")
	var early_plan = state_of(14,only.starts); early_plan.stage = "arrival"
	check(not R.validate(early_plan),"a plan cannot appear during dialogue")
	var early_ticket = puzzle(); early_ticket.stage = "arrival"; early_ticket.ticket = 13
	check(not R.validate(early_ticket),"a chosen ticket cannot appear during dialogue")
	var early_move = puzzle(); early_move.stage = "ready"; early_move.load = [12,11]
	check(not R.validate(early_move),"moved starts cannot appear before the puzzle")
	var unknown = state_of(14,only.starts); unknown.stage = "trial"
	check(not R.validate(unknown),"an unknown stage is rejected")
	var extra = state_of(14,only.starts); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var dropped = state_of(14,only.starts); dropped.erase("hint")
	check(not R.validate(dropped),"a missing field is rejected")
	var twice = {"sample":R.SAMPLE,"stage":"puzzle","beat":2,"ticket":14,"assembly":[7,9],
		"cool":[9,12],"load":[12,14],"hint":0,"ticket_again":14}
	check(not R.validate(twice),"a duplicated record is rejected")
	var old = state_of(14,only.starts); old.sample = "workshop-gw11-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	check(not R.validate(null) and not R.validate([]) and not R.validate("state"),"non-dictionaries are rejected")
	# ---- 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件 ----
	var partial = state_of(13,[7,9,12,8,11,13])
	var repo = Repo.new(); repo.path = "/tmp/gw11-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(partial,R.validate),"save accepted the half-arranged record")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(answer,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == partial,"restart restores the saved record")
	check(repo.write_profile(answer,R.validate),"the answer saves")
	check(repo.read_profile(R.validate).profile == answer,"the answer reads back")
	var file = FileAccess.open(repo.path,FileAccess.WRITE); file.store_string('{"broken":true}'); file.close()
	hash = FileAccess.get_sha256(repo.path)
	check(repo.read_profile(R.validate).status == "protected","bad save protected")
	check(not repo.write_profile(R.fresh(),R.validate) and FileAccess.get_sha256(repo.path) == hash,"protected file never overwritten")
	var backup = repo.preserve_protected_file()
	check(not backup.is_empty() and FileAccess.get_sha256(backup) == hash,"explicit recovery preserves backup")
	for p in [repo.path,repo.path+".tmp",backup]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(repo.path.get_base_dir())
	print("GW11 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

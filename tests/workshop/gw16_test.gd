extends SceneTree
const R = preload("res://scripts/workshop/gw16_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW16 rules watchdog fired")
		print("GW16 RULES: ",checks," checks, ",failures+1," failures")
		quit(1)
		return true
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")

# ---- 独立 oracle：用最笨的枚举把 3^4 种段序逐条筛一遍，不复用被测代码的判定。----
func oracle_legal(order: Array) -> bool:
	if order.size() != 4: return false
	var total = 0
	var threes = 0
	for value in order:
		if not value is int or value < 2 or value > 4: return false
		total += value
		if value == 3: threes += 1
	if total != 12 or threes != 2: return false
	for index in range(4):
		if order[index] == order[(index+1)%4]: return false
	return true
# 只查段内相邻、不查首尾：用来证明「把首尾当不相邻会多算」。
func oracle_linear(order: Array) -> bool:
	if order.size() != 4: return false
	var total = 0
	var threes = 0
	for value in order:
		if value < 2 or value > 4: return false
		total += value
		if value == 3: threes += 1
	if total != 12 or threes != 2: return false
	for index in range(3):
		if order[index] == order[index+1]: return false
	return true
func oracle_tunes() -> Array:
	var out = []
	for a in [2,3,4]:
		for b in [2,3,4]:
			for c in [2,3,4]:
				for d in [2,3,4]:
					if oracle_legal([a,b,c,d]): out.append([a,b,c,d])
	return out

func puzzle() -> Dictionary:
	var s = R.fresh()
	while s.stage != "puzzle": s = R.advance(s)
	return s
# 测试里直接摆好铃架，等价于玩家连按 2/3/4；返回值仍要过 validate。
func arrange(s: Dictionary, order: Array) -> Dictionary:
	var n = s.duplicate(true); n.segments = order.duplicate(); n.heard = false
	return n if R.validate(n) else {}
func heard_legal(s: Dictionary, order: Array) -> Dictionary:
	return R.listen(arrange(s,order))

func run() -> void:
	# 1) 独立枚举：3^4 里只有 4 首，且与设计文档给出的四首一致。
	var tunes = oracle_tunes()
	check(tunes.size() == 4,"oracle enumerates exactly four tunes")
	var expected = [[2,3,4,3],[4,3,2,3],[3,2,3,4],[3,4,3,2]]
	for order in expected:
		check(tunes.has(order),"oracle finds %s"%R.order_text(order))
	check(R.solution().size() == 4,"rules solution has four tunes")
	for order in R.solution():
		check(tunes.has(order),"rules solution %s is an oracle tune"%R.order_text(order))
	for order in tunes:
		check(R.solution().has(order),"rules solution covers oracle tune %s"%R.order_text(order))
	# 2) 逐格：81 种段序的合法性与 oracle 逐条一致；把首尾当不相邻会多算两首。
	var linear = 0
	for a in [2,3,4]:
		for b in [2,3,4]:
			for c in [2,3,4]:
				for d in [2,3,4]:
					var order = [a,b,c,d]
					check(R.legal(order) == oracle_legal(order),"legality agrees on %s"%R.order_text(order))
					if oracle_linear(order): linear += 1
	check(linear == 6,"ignoring the wrap accepts six orders instead of four")
	# 3) 首尾相邻反例：3/2/4/3 段内全不同，只有末段与首段相同；2/3/4/2 三处都不对。
	check(not R.legal([3,2,4,3]),"3/2/4/3 is refused although every inside pair differs")
	check(oracle_linear([3,2,4,3]) and not oracle_legal([3,2,4,3]),"the wrap is the only thing ruling out 3/2/4/3")
	check(not R.legal([3,4,2,3]),"3/4/2/3 is refused for the same wrap")
	check(R.legal([2,3,4,3]) and R.legal([3,4,3,2]),"2/3/4/3 and 3/4/3/2 are accepted")
	var wrap = R.phrase_problems([3,2,4,3])
	check(wrap.size() == 1 and "末段和首段都是 3 拍" in wrap[0],"the wrap phrase reports exactly the wrap conflict")
	check(not R.legal([2,3,4,2]),"2/3/4/2 is refused")
	var p242 = R.phrase_problems([2,3,4,2])
	check(p242.size() == 3,"2/3/4/2 reports every real violation")
	check("末段和首段都是 2 拍" in p242[0],"the wrap conflict is named first")
	check("3 拍的段有 1 段" in "；".join(p242),"the missing third is named")
	check("四段合计 11 拍" in "；".join(p242),"the short total is named")
	var p3343 = R.phrase_problems([3,3,4,3])
	check(not R.legal([3,3,4,3]),"two adjacent threes are refused")
	check("相邻两段不能相同" in "；".join(p3343),"an adjacent equal pair is named")
	check(R.phrase_problems([2,3,4,3]).is_empty(),"a legal phrase has no problems")
	check(R.beats([2,3,4,3]) == 12 and R.threes([2,3,4,3]) == 2,"beat helpers")
	check(R.order_text([2,3,4,3]) == "2/3/4/3","order text")
	check(R.phrase_problems([2,3,4]).size() == 1,"a short rack is not yet a phrase")
	# 4) 阶段推进与操作守卫。
	var s = R.fresh()
	check(s.stage == "arrival" and R.validate(s),"fresh state is legal")
	check(R.put(R.fresh(),2).is_empty(),"no arranging during dialogue")
	check(R.listen(R.fresh()).is_empty(),"no listening during dialogue")
	check(R.save_tune(R.fresh()).is_empty(),"no saving during dialogue")
	check(R.choose(R.fresh(),0).is_empty(),"no choosing during dialogue")
	check(R.take(R.fresh(),0).is_empty(),"no taking during dialogue")
	var staged = R.fresh()
	for i in range(3): staged = R.advance(staged)
	check(staged.stage == "approach","three beats reach approach")
	staged = R.advance(staged); check(staged.stage == "ready","approach reaches ready")
	staged = R.advance(staged); check(staged.stage == "puzzle","ready starts the puzzle")
	check(R.validate(staged),"puzzle state is legal")
	check(R.put(staged,1).is_empty() and R.put(staged,5).is_empty(),"only 2, 3 or 4 beat segments")
	# 5) 排段、取段、试听、保存。
	s = puzzle()
	s = R.put(s,2); check(s.segments == [2],"the first segment is placed")
	s = R.put(s,3); s = R.put(s,4); s = R.put(s,3)
	check(s.segments == [2,3,4,3],"four segments are placed")
	check(not s.heard,"placing clears the audition")
	check(R.put(s,2).is_empty(),"a full rack refuses another segment")
	s = R.listen(s); check(s.heard and R.validate(s),"listening marks the phrase heard")
	var shifted = R.take(s,0)
	check(shifted.segments == [3,4,3] and not shifted.heard,"taking a segment shifts the rack and clears the audition")
	check(R.take(s,4).is_empty() and R.take(s,-1).is_empty(),"taking outside the rack is refused")
	var heard = heard_legal(puzzle(),[2,3,4,3])
	var saved = R.save_tune(heard)
	check(saved.saved == [[2,3,4,3]],"a heard legal phrase saves")
	check(R.save_tune(saved).is_empty(),"re-saving the same tune is refused")
	check("重存同一首不算新的一首" in R.save_reason(saved),"the duplicate save names the real reason")
	var unlistened = arrange(puzzle(),[2,3,4,3])
	check(R.save_tune(unlistened).is_empty(),"saving before listening is refused")
	check("先按「试听」" in R.save_reason(unlistened),"the missing audition is named")
	var wrap_listened = heard_legal(puzzle(),[3,2,4,3])
	check(R.save_tune(wrap_listened).is_empty(),"the wrap phrase cannot be saved")
	check("末段和首段都是 3 拍" in R.save_reason(wrap_listened),"the wrap conflict is the reason")
	check("还差 4 段才能保存" in R.save_reason(puzzle()),"an empty rack names its own reason")
	# 6) 逐格 shortfalls 与收集进度。
	for a in [2,3,4]:
		for b in [2,3,4]:
			for c in [2,3,4]:
				for d in [2,3,4]:
					var order = [a,b,c,d]
					var draft = arrange(puzzle(),order)
					check(R.validate(draft),"draft %s stays legal"%R.order_text(order))
					check(not R.solved(draft),"a draft alone never solves %s"%R.order_text(order))
					check(not R.shortfalls(draft).is_empty(),"an unfinished collection reports a gap for %s"%R.order_text(order))
					if oracle_legal(order):
						check("还没保存" in R.shortfalls(draft)[0],"legal draft %s only needs saving"%R.order_text(order))
					else:
						check("四首还没收齐" not in R.shortfalls(draft)[0],"illegal draft %s names its own problem"%R.order_text(order))
	var orders = [[2,3,4,3],[4,3,2,3],[3,2,3,4],[3,4,3,2]]
	var collected = puzzle()
	for i in range(orders.size()):
		check(not R.solved(collected),"a collection of %d is not solved"%i)
		if i < R.TUNES: check("四首还没收齐" in R.shortfalls(collected)[-1],"the collection gap is reported at %d"%i)
		collected = R.save_tune(heard_legal(collected,orders[i]))
		check(collected.saved.size() == i+1,"saved %d tunes"%collected.saved.size())
	check(R.collected(collected),"all four tunes are collected")
	check(not R.solved(collected),"collecting four is not enough without the lunch choice")
	check("点收集板上的一首" in R.shortfalls(collected)[0],"the missing lunch choice is named")
	check(R.advance(collected).is_empty(),"advance needs the lunch choice")
	# 7) 收齐后留一首：选、换、撤销。
	check(R.choose(puzzle(),0).is_empty(),"cannot choose before collecting")
	check(R.choose(collected,-1).is_empty() and R.choose(collected,4).is_empty(),"the choice must be one of the four")
	check(R.cycle_chosen(collected,1).chosen == 0,"forward cycling starts at the first tune")
	check(R.cycle_chosen(collected,-1).chosen == 3,"backward cycling starts at the last tune")
	var picked = R.choose(collected,1)
	check(picked.chosen == 1 and R.solved(picked),"choosing a tune solves the level")
	check(R.shortfalls(picked).is_empty(),"the solved state has no shortfall")
	check(R.cycle_chosen(picked,1).chosen == 2,"cycling moves to the next tune")
	check(R.cycle_chosen(picked,-1).chosen == 0,"cycling moves back")
	check(R.cycle_chosen(R.choose(collected,3),1).is_empty(),"cycling clamps at the last tune")
	# 8) 提交只在解上通过；交付、余韵与完成。
	check(R.advance(puzzle()).is_empty(),"advance without a solution is refused")
	var delivery = R.advance(picked)
	check(delivery.stage == "delivery" and R.validate(delivery),"the solved state enters delivery")
	var aftermath = R.advance(delivery)
	check(aftermath.stage == "aftermath" and aftermath.beat == 0,"delivery stops for dialogue")
	var done = aftermath
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes the level")
	check(R.advance(done).is_empty(),"nothing follows complete")
	# 9) 撤销与重摆：铃架、试听、收集板与留曲都跟着快照走。
	var before = R.put(puzzle(),2)
	var snapshot = {"segments":before.segments.duplicate(),"heard":before.heard,"saved":before.saved.duplicate(true),"chosen":before.chosen}
	var after = R.put(before,3)
	check(R.restore(after,snapshot).segments == [2],"undo restores the rack")
	check(R.restore(after,snapshot).heard == false,"undo restores the audition flag")
	check(R.restore(saved,{"segments":[2,3,4,3],"heard":true,"saved":[],"chosen":-1}).saved.is_empty(),"undo takes back a saved tune")
	check(R.restore(picked,{"segments":picked.segments.duplicate(),"heard":picked.heard,"saved":picked.saved.duplicate(true),"chosen":-1}).chosen == -1,"undo takes back the lunch choice")
	check(R.restore(after,{}).is_empty(),"a snapshot without fields is refused")
	var helped = heard_legal(puzzle(),[2,3,4,3]); helped.hint = 4
	check(R.restore(helped,{"segments":[],"heard":false,"saved":[],"chosen":-1}).hint == 4,"undo retains help")
	# 10) 伪造、越界与旧档一律拒绝。
	for stage in ["delivery","aftermath","complete"]:
		var good = picked.duplicate(true); good.stage = stage
		check(R.validate(good),"completed %s is legal"%stage)
		var forged = collected.duplicate(true); forged.stage = stage
		check(not R.validate(forged),"a forged %s without the lunch choice is rejected"%stage)
		var partial = saved.duplicate(true); partial.stage = stage
		check(not R.validate(partial),"a single tune cannot be a completed %s"%stage)
	for bad in [[1],[5],[2.5],[true],[2,3,4,3,3]]:
		var c = puzzle(); c.segments = bad
		check(not R.validate(c),"invalid rack rejected "+str(bad))
	var c = puzzle(); c.heard = true
	check(not R.validate(c),"heard without a full rack is rejected")
	c = puzzle(); c.heard = 1
	check(not R.validate(c),"heard must be a bool")
	for bad_saved in [[[2,3,4,2]],[[2,3,4,3],[2,3,4,3]],[[2,3,4,3],[3,2,4,3]],[[1,3,4,4]],[[2,3,4,3],[3,2,3,4],[3,4,3,2],[4,3,2,3],[2,3,4,3]],"x"]:
		var c2 = picked.duplicate(true); c2.saved = bad_saved
		check(not R.validate(c2),"invalid collection rejected "+str(bad_saved))
	for bad_chosen in [-2,4,1.5,true]:
		var c3 = picked.duplicate(true); c3.chosen = bad_chosen
		check(not R.validate(c3),"invalid choice rejected "+str(bad_chosen))
	var early_choice = picked.duplicate(true); early_choice.chosen = 0; early_choice.saved = early_choice.saved.slice(0,3)
	check(not R.validate(early_choice),"a choice without all four tunes is rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c4 = picked.duplicate(true); c4.beat = bad_beat
		check(not R.validate(c4),"invalid beat rejected "+str(bad_beat))
	for bad_hint in [-1,5,1.0,true]:
		var c5 = picked.duplicate(true); c5.hint = bad_hint
		check(not R.validate(c5),"invalid hint rejected "+str(bad_hint))
	var early = R.put(puzzle(),2); early.stage = "arrival"
	check(not R.validate(early),"a rack cannot appear during dialogue")
	var early_saved = picked.duplicate(true); early_saved.stage = "ready"
	check(not R.validate(early_saved),"a collection cannot appear during dialogue")
	var early_hint = puzzle(); early_hint.stage = "ready"; early_hint.hint = 2
	check(not R.validate(early_hint),"hints cannot appear during dialogue")
	var extra = picked.duplicate(true); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var missing = picked.duplicate(true); missing.erase("saved")
	check(not R.validate(missing),"missing field rejected")
	var old = picked.duplicate(true); old.sample = "workshop-gw16-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	check(not R.validate(null) and not R.validate("x") and not R.validate([]),"validate only accepts the closed dictionary")
	# 11) 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw16-rules-%d/save.json"%OS.get_process_id()
	var partial_save = heard_legal(puzzle(),[2,3,4,3])
	partial_save = R.save_tune(partial_save)
	check(repo.write_profile(partial_save,R.validate),"save accepted the partial record")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(picked,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == partial_save,"restart restores the saved record")
	check(repo.write_profile(picked,R.validate),"retry exact completion")
	var file = FileAccess.open(repo.path,FileAccess.WRITE); file.store_string('{"broken":true}'); file.close()
	hash = FileAccess.get_sha256(repo.path)
	check(repo.read_profile(R.validate).status == "protected","bad save protected")
	check(not repo.write_profile(R.fresh(),R.validate) and FileAccess.get_sha256(repo.path) == hash,"protected file never overwritten")
	var backup = repo.preserve_protected_file()
	check(not backup.is_empty() and FileAccess.get_sha256(backup) == hash,"explicit recovery preserves backup")
	for p in [repo.path,repo.path+".tmp",backup]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(repo.path.get_base_dir())
	print("GW16 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

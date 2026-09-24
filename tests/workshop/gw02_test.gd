extends SceneTree
const R = preload("res://scripts/workshop/gw02_rules.gd")
const Repo = preload("res://scripts/persistence/save_repository.gd")
var checks = 0
var failures = 0
var elapsed = 0.0
# 出错时 run() 会被中断，SceneTree 不会自己退出：留一只看门狗，免得检查卡死。
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("GW02 rules watchdog fired")
		print("GW02 RULES: ",checks," checks, ",failures+1," failures")
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
# 直接摆一张台面：数值就是每片的模具，0 表示还没选。
func bench(values: Array) -> Dictionary:
	var s = puzzle(); s.molds = values.duplicate()
	return s
const SOLVED = [4,4,7,4,4,4,7,4]
const UNDER = [4,4,4,4,4,4,4,7]
const OVER = [4,4,7,7,7,7,4,4]
func run() -> void:
	var s = puzzle()
	check(R.validate(s),"fresh progression reaches legal puzzle")
	check(R.set_mould(R.fresh(),0,R.SMALL).is_empty(),"no stamping during dialogue")
	check(R.set_mould(s,8,R.SMALL).is_empty(),"no ninth sheet")
	check(R.set_mould(s,-1,R.SMALL).is_empty(),"no negative sheet")
	check(R.set_mould(s,0,0).molds[0] == 0,"zero clears a sheet")
	check(R.set_mould(s,0,5).is_empty(),"no five-hole mould")
	check(R.set_mould(s,0,R.SMALL).molds[0] == R.SMALL,"stamp four-hole")
	check(R.set_mould(s,0,R.LARGE).molds[0] == R.LARGE,"restamp seven-hole")
	check(R.clear_sheet(R.set_mould(s,3,R.LARGE),3).molds[3] == 0,"clear a sheet")
	check(R.advance(s).is_empty(),"cannot press an unassigned bench")
	# 3^8 = 6561 张排布全枚举，用独立标量算一遍该不该通过。
	var solutions = []
	for mask in range(6561):
		var values = []; var code = mask
		for i in range(R.SHEETS): values.append([0,R.SMALL,R.LARGE][code%3]); code = code/3
		var candidate = bench(values)
		var fours = 0; var sevens = 0
		for value in values:
			if value == R.SMALL: fours += 1
			elif value == R.LARGE: sevens += 1
		var expected = fours+sevens == R.SHEETS and fours > 0 and sevens > 0 and 4*fours+7*sevens == 38
		check(R.validate(candidate),"legal arrangement")
		check(R.solved(candidate) == expected,"exhaustive independent oracle")
		if expected:
			solutions.append(values)
			check(R.produced(candidate) == 38 and R.installed(candidate) == 27,"solution arithmetic")
	check(solutions.size() == 28,"all 28 two-sevens arrangements accepted")
	var shapes = {}
	for values in solutions:
		var sevens = []
		for i in range(R.SHEETS):
			if values[i] == R.LARGE: sevens.append(i)
		shapes[str(sevens)] = true
	check(shapes.size() == 28,"each arrangement distinct")
	# 留样取的是每种模在排产顺序里最靠前的一片。
	var sample = bench(SOLVED)
	check(R.sealed(sample) == [0,2],"sealed picks the first sheet of each mould")
	check(R.produced(sample) == 38 and R.installed(sample) == 27,"6 fours + 2 sevens installs 27")
	check(R.shortfalls(bench([0,0,0,0,0,0,0,0]))[0].begins_with("还有 8 片"),"unassigned bench reports count")
	check(R.shortfalls(bench([4,4,0,0,0,0,0,0]))[0].begins_with("还有 6 片"),"partial bench reports the rest")
	var one_mould = bench([4,4,4,4,4,4,4,4])
	check(R.validate(one_mould),"single-mould bench is a legal board")
	check(R.shortfalls(one_mould)[0].begins_with("四孔模和七孔模"),"single mould names the missing box")
	check(R.installed(bench(UNDER)) == 24 and "还差 3" in R.shortfalls(bench(UNDER))[0],"shortfall arithmetic")
	check(R.installed(bench(OVER)) == 33 and "多了 6" in R.shortfalls(bench(OVER))[0],"overshoot arithmetic")
	# 完整走一遍：失败试压回到摆放，正确答案才进交货。
	var pressed = R.advance(bench(UNDER))
	check(pressed.stage == "pressing" and pressed.attempts == 1,"complete bench may be pressed")
	check(R.validate(pressed),"pressing state is legal")
	var back = R.advance(pressed)
	check(back.stage == "puzzle" and R.validate(back),"wrong trial returns to the bench")
	check(R.back_to_plan(pressed).stage == "puzzle","pressing can be abandoned")
	check(R.advance(bench([0,0,0,0,0,0,0,0])).is_empty(),"incomplete bench cannot be pressed")
	var trial = R.advance(bench(SOLVED))
	check(trial.stage == "pressing","solution may be pressed")
	check(R.advance(trial).stage == "delivery","verified result enters delivery")
	var delivery = R.advance(trial)
	check(R.advance(delivery).stage == "aftermath","delivery stops for dialogue")
	var done = R.advance(delivery)
	for i in range(3): done = R.advance(done)
	check(done.stage == "complete" and R.validate(done),"manual discovery completes")
	# 伪造与坏档一律拒绝：试压那一格允许错答案（本来就该看得到失败），
	# 但没选满不能进试压，交货之后的每一格都必须是真解出来的。
	var forged = bench(SOLVED); forged.stage = "pressing"; forged.attempts = 1
	check(R.validate(forged),"pressing with a full bench is legal")
	var incomplete = bench([4,4,0,0,0,0,0,0]); incomplete.stage = "pressing"; incomplete.attempts = 1
	check(not R.validate(incomplete),"pressing an unassigned bench rejected")
	var unclaimed = bench(SOLVED); unclaimed.stage = "pressing"
	check(not R.validate(unclaimed),"pressing without an attempt rejected")
	for stage in ["delivery","aftermath","complete"]:
		var good = bench(SOLVED); good.stage = stage; good.attempts = 1
		check(R.validate(good),"completed %s is legal"%stage)
		var broken = bench(UNDER); broken.stage = stage; broken.attempts = 1
		check(not R.validate(broken),"forged %s rejected"%stage)
	var attempted = bench([4,4,0,0,0,0,0,0]); attempted.attempts = 2
	check(R.validate(attempted),"attempts allowed on the bench")
	for bad_mould in [-1,3,5,2.0,true]:
		var c = bench([4,4,4,4,4,4,4,4]); c.molds[0] = bad_mould
		check(not R.validate(c),"invalid mould rejected")
	for bad_beat in [-1,3,2.0,true]:
		var c = bench(SOLVED); c.beat = bad_beat
		check(not R.validate(c),"invalid beat rejected")
	var short_moulds = bench(SOLVED); short_moulds.molds = [0,0,0]
	check(not R.validate(short_moulds),"short mould list rejected")
	var extra = bench(SOLVED); extra.extra = true
	check(not R.validate(extra),"closed schema")
	var old = bench(SOLVED); old.sample = "workshop-gw02-0"
	check(not R.validate(old),"old version not interpreted as new progress")
	var helped = bench([4,4,0,0,0,0,0,0]); helped.hint = 4; helped.attempts = 3
	var restored = R.restore(helped,{"molds":R.empty()})
	check(restored.hint == 4 and restored.attempts == 3,"undo retains help and attempts")
	check(R.restore(bench(SOLVED),{"molds":R.empty()}).molds == R.empty(),"undo restores the board")
	# 存档事务：失败注入不覆盖上一次成功状态，坏档保留原文件。
	var repo = Repo.new(); repo.path = "/tmp/gw02-rules-%d/save.json"%OS.get_process_id()
	check(repo.write_profile(bench(SOLVED),R.validate),"save accepted board")
	var hash = FileAccess.get_sha256(repo.path)
	for fault in ["open","flush","replace"]:
		repo.fail_at = fault
		check(not repo.write_profile(trial,R.validate),"save fault rejected "+fault)
		check(FileAccess.get_sha256(repo.path) == hash,"fault retains prior save "+fault)
	repo.fail_at = ""
	check(repo.read_profile(R.validate).profile == bench(SOLVED),"restart restores saved bench")
	check(repo.write_profile(done,R.validate),"retry exact completion")
	var file = FileAccess.open(repo.path,FileAccess.WRITE); file.store_string('{"broken":true}'); file.close()
	hash = FileAccess.get_sha256(repo.path)
	check(repo.read_profile(R.validate).status == "protected","bad save protected")
	check(not repo.write_profile(R.fresh(),R.validate) and FileAccess.get_sha256(repo.path) == hash,"protected file never overwritten")
	var backup = repo.preserve_protected_file()
	check(not backup.is_empty() and FileAccess.get_sha256(backup) == hash,"explicit recovery preserves backup")
	for p in [repo.path,repo.path+".tmp",backup]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(repo.path.get_base_dir())
	print("GW02 RULES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

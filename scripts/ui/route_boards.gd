extends RefCounted
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Canvas = preload("res://scripts/ui/route_canvas.gd")
const Rules = preload("res://scripts/mechanisms/route_rules.gd")
const PuzzleBoards = preload("res://scripts/ui/puzzle_boards.gd")

static func draw(host: Control, definition: Dictionary, run: Dictionary) -> void:
	preload("res://scripts/ui/workbench.gd").mount(host.ui,definition.family)
	if definition.family == "route_block_choice": draw_blocks(host,definition,run); return
	# Receipts written before the redesign keep their original board so an in-progress
	# legacy run can still be finished; new runs use the audit / upper-bound boards.
	if definition.family == "route_partition" and not Rules.legacy_shape(run.state): draw_audit(host,definition,run); return
	if definition.family == "disjoint_route_pairs" and not Rules.legacy_shape(run.state): draw_bound(host,definition,run); return
	if definition.family == "disjoint_route_pairs" and host.board_tab == "pairs": draw_pairs(host,run); return
	var state: Dictionary = run.state; var enabled = run.outcome == "active"
	var canvas = Canvas.new(); canvas.name = "route_canvas"; canvas.position = Vector2(82,260); canvas.size = Vector2(444,240)
	canvas.columns = definition.params.right; canvas.rows = definition.params.up; canvas.path = state.draft; canvas.other_path = state.first_route; canvas.enabled = enabled
	canvas.tag = int(run.tools.route_tags.get(state.draft,-1))
	host.ui.add_child(canvas); canvas.step_requested.connect(func(direction: String): host.rule({"kind":"step","direction":direction}))
	host.text("点相邻的路口画路：先定一条作第一封，再画不碰面的另一条；每条每次都要往右或往上。",Rect2(80,184,1090,40),20,true)
	host.button("route_right","向右 →",Rect2(82,523,131,43),host.rule.bind({"kind":"step","direction":"R"}),enabled)
	host.button("route_up","向上 ↑",Rect2(225,523,131,43),host.rule.bind({"kind":"step","direction":"U"}),enabled)
	host.button("route_clear","擦掉路线",Rect2(368,523,161,43),host.rule.bind({"kind":"clear"}),enabled)
	if definition.family == "route_partition":
		var bag_guess: Array = state.get("bag_guess",[])
		host.text("先估一估：从三个高度出发的路线各有多少条？",Rect2(572,232,617,32),20,true)
		for height in range(3):
			var shown: int = int(bag_guess[height]) if bag_guess.size() == 3 else 0
			PuzzleBoards.number(host,"bag_guess_"+str(height),shown,Rect2(573+height*170,266,162,40),0,10,func(value: int):
				var current: Array = state.get("bag_guess",[])
				var values: Array = current.duplicate() if current.size() == 3 else [0,0,0]
				values[height] = value
				host.rule({"kind":"bag_guess","value":values}))
		host.text("第一次向右时在第几层，就归进第几层邮袋：",Rect2(572,314,617,30),20,true)
		for height in range(3): host.button("store_route_"+str(height),str(height)+"层邮袋",Rect2(573+height*212,348,191,40),host.rule.bind({"kind":"store_route","group":height}),enabled)
		if bag_guess.size() == 3: host.text("（先填了估计：%d/%d/%d，稍后对照）"%[int(bag_guess[0]),int(bag_guess[1]),int(bag_guess[2])],Rect2(573,506,420,24),18,true)
		var counts = [0,0,0]
		for route in state.routes: counts[int(route.group)] += 1
		var progress = "已收好%d条（共%d条）"%[state.routes.size(),Rules.all_paths(definition.params).size()]
		if bag_guess.size() == 3: progress += "；你猜的是 %d/%d/%d" % [int(bag_guess[0]),int(bag_guess[1]),int(bag_guess[2])]
		host.text(progress,Rect2(573,534,420,24),19,true)
		var scroll = ScrollContainer.new(); scroll.name = "routes_scroll"; scroll.position = Vector2(573,392); scroll.size = Vector2(621,112); host.ui.add_child(scroll)
		var content = Control.new(); content.custom_minimum_size = Vector2(590,maxi(95,state.routes.size()*46)); scroll.add_child(content)
		for i in state.routes.size():
			var route: Dictionary = state.routes[i]
			var tag = " · 签%d层"%run.tools.route_tags[route.path] if run.tools.route_tags.has(route.path) else ""
			host.text(route.path+tag,Rect2(2,i*46+3,209,39),20,true,content)
			for group in range(3): host.button("regroup_%d_%d"%[i,group],("✓" if route.group == group else "")+str(group)+"层",Rect2(214+group*116,i*46,103,37),host.rule.bind({"kind":"regroup","index":i,"group":group}),enabled,content)
	else:
		host.text("第一封："+("还没选" if state.first_route == "" else state.first_route),Rect2(578,245,610,42),22,true)
		host.button("first_route","就用这条当第一封",Rect2(577,308,290,44),host.rule.bind({"kind":"first_route"}),enabled)
		host.button("change_first","换一条第一封",Rect2(889,308,300,44),host.rule.bind({"kind":"clear_first"}),enabled)
		host.text("再画一条和它中途不碰面的路，合成一对。",Rect2(578,372,610,43),21,true)
		host.button("store_pair","这两条不碰面，收下",Rect2(577,428,613,43),host.rule.bind({"kind":"store_pair","group":state.first_route}),enabled and state.first_route != "" and state.draft != "")
		host.button("show_pairs","已找到的%d组（共6组）"%state.pairs.size(),Rect2(579,480,612,40),host.set_board_tab.bind("pairs"))
	host.button("try","送信出发",Rect2(1005,530,192,42),host.rule.bind({"kind":"try"}),enabled)

# FL08 redesigned board: audit 折羽's filing, repair one card, supply the one
# missing route, and state the per-bag counts that prove nothing else is lost.
static func draw_audit(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var p: Dictionary = definition.params
	var enabled = run.outcome == "active"
	var filing: Array = Rules.filing_of(p,state)
	host.text("折羽把每条走法都归档好了，但袋子里还混着两处错：一张卡放错袋，一条路线没归档。先复核，再补全。",Rect2(80,184,1090,30),20,true)
	host.text("规则：第一次向右时在第几层，就归进第几层邮袋。",Rect2(80,214,1090,26),19,true)
	# Left: the player draws/validates a route when supplying the missing card.
	var canvas = Canvas.new(); canvas.name = "route_canvas"; canvas.position = Vector2(80,300); canvas.size = Vector2(330,190)
	canvas.columns = p.right; canvas.rows = p.up; canvas.path = state.draft; canvas.enabled = enabled
	canvas.tag = int(run.tools.route_tags.get(state.draft,-1))
	host.ui.add_child(canvas); canvas.step_requested.connect(func(direction: String): host.rule({"kind":"step","direction":direction}))
	host.text("要补的那条路线：",Rect2(80,252,330,26),20,true)
	host.button("route_right","向右 →",Rect2(80,497,104,40),host.rule.bind({"kind":"step","direction":"R"}),enabled)
	host.button("route_up","向上 ↑",Rect2(190,497,104,40),host.rule.bind({"kind":"step","direction":"U"}),enabled)
	host.button("route_clear","擦掉",Rect2(300,497,110,40),host.rule.bind({"kind":"clear"}),enabled)
	host.button("audit_add","补进邮袋",Rect2(80,541,330,40),host.rule.bind({"kind":"audit_add"}),enabled and state.draft != "")
	# Right: the filing in two columns, so every card (including the misfiled one) is
	# visible at once. Each card shows its bag and, when wrong, its correct bag.
	host.text("折羽的邮袋（点「移正」改正放错的那张）：",Rect2(437,252,760,26),20,true)
	for i in filing.size():
		var card: Dictionary = filing[i]
		var right: bool = card.group == card.path.find("R")
		var col = i % 2; var row = i / 2
		var x = 437+col*382; var y = 284+row*46
		host.text(("✓ " if right else "✗ ")+card.path+" → "+str(card.group)+"层"+("" if right else "（应"+str(card.path.find("R"))+"层）"),Rect2(x,y+3,240,36),19,true)
		host.button("audit_move_"+str(i),"移正",Rect2(x+246,y,124,38),host.rule.bind({"kind":"audit_move","index":i}),enabled and not right)
	# Per-bag counts: the arithmetic that reveals the missing card.
	host.text("每层袋应有几条：",Rect2(437,514,200,28),20,true)
	for height in range(p.up+1):
		var counts: Array = state.get("counts",[])
		var shown: int = int(counts[height]) if counts.size() == p.up+1 else 0
		PuzzleBoards.number(host,"counts_"+str(height),shown,Rect2(650+height*160,512,150,34),0,10,func(value: int):
			var current: Array = state.get("counts",[])
			var values: Array = current.duplicate() if current.size() == p.up+1 else [0,0,0]
			values[height] = value
			host.rule({"kind":"counts","value":values}))
	host.button("try","送信出发",Rect2(1005,548,192,40),host.rule.bind({"kind":"try"}),enabled)

# FL10 redesigned board: pick the letters that can leave together, then commit to
# the reason no third letter fits. The exhaustive six-pair list is gone.
static func draw_bound(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var p: Dictionary = definition.params
	var enabled = run.outcome == "active"
	var chosen: Array = state.get("bound_set",[])
	host.text("邮路板上有%d条走法。挑出能同时出发、中途不碰面的一组信，再说清为什么不能再多。"%Rules.all_paths(p).size(),Rect2(80,180,1100,28),20,true)
	host.text("两条路线只要有同一个中途路口，两封信就会在那里碰面。",Rect2(80,208,1100,26),19,true)
	# Left: the board shows every known route, so the choice is made from evidence.
	var canvas = Canvas.new(); canvas.name = "route_canvas"; canvas.position = Vector2(74,240); canvas.size = Vector2(420,268)
	canvas.columns = p.right; canvas.rows = p.up; canvas.path = ""; canvas.enabled = false
	canvas.other_path = chosen[0] if chosen.size() > 0 else ""
	host.ui.add_child(canvas)
	host.text("已选 %d 封信"%chosen.size(),Rect2(78,522,420,28),21,true)
	# Right: one button per known route; clicking toggles it in the simultaneous set.
	var paths = Rules.all_paths(p)
	for i in paths.size():
		var path: String = paths[i]
		var x = 530+(i%2)*312; var y = 238+(i/2)*42
		host.button("pick_"+path,("✓ " if path in chosen else "")+path,Rect2(x,y,294,38),func():
			var next: Array = chosen.duplicate()
			if path in next: next.erase(path)
			else: next.append(path)
			host.rule({"kind":"bound_set","value":next}),enabled)
	if chosen.size() >= Rules.max_simultaneous(p):
		host.text("为什么放不下第三封？选一个理由：",Rect2(530,452,600,24),20,true)
		for i in Rules.BOUND_REASONS.size():
			var picked: bool = int(state.get("bound_reason",-1)) == i
			host.button("reason_"+str(i),("✓ " if picked else "")+["理由一","理由二","理由三"][i],Rect2(530,478+i*38,294,34),host.rule.bind({"kind":"bound_reason","value":i}),enabled)
		var explain = ""
		var picked_index: int = int(state.get("bound_reason",-1))
		if picked_index >= 0 and picked_index < Rules.BOUND_REASONS.size(): explain = Rules.BOUND_REASONS[picked_index]
		host.text(explain if state.get("bound_reason",-1) >= 0 else "选一个理由后，这里会显示它的完整说法。",Rect2(844,478,390,90),18,true)
	host.button("try","送信出发",Rect2(1005,540,192,40),host.rule.bind({"kind":"try"}),enabled)

static func draw_pairs(host: Control, run: Dictionary) -> void:
	host.button("back_routes","回到画路线",Rect2(83,180,242,40),host.set_board_tab.bind("initial"))
	host.text("已经找到的路线对；每一组里，两封信都不会在中途碰面。",Rect2(365,183,821,44),21,true)
	for i in run.state.pairs.size():
		var pair: Dictionary = run.state.pairs[i]; var y = 241+i*47
		var a_tag = "[签%d]"%run.tools.route_tags[pair.a] if run.tools.route_tags.has(pair.a) else ""
		var b_tag = "[签%d]"%run.tools.route_tags[pair.b] if run.tools.route_tags.has(pair.b) else ""
		host.text("第%d组：%s%s / %s%s"%[i+1,pair.a,a_tag,pair.b,b_tag],Rect2(83,y+2,1070,39),20,true)

static func draw_blocks(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var p: Dictionary = definition.params; var enabled = run.outcome == "active"
	var block_index = clampi(host.block_index,0,3)
	var experiments: Array = state.get("experiments",[])
	var guess: int = int(state.get("guess",-1))
	host.text("落石只会挡住经过它的路线。先猜：把石头放在哪个位置，能留下最多送信方式？",Rect2(81,174,1121,38),20,true)
	# Step 1: make a guess before seeing any counts.
	if guess < 0:
		for i in range(4):
			var point: Array = p.candidate_blocks[i]
			host.button("guess_"+str(i),"我猜(%d,%d)"%[point[0],point[1]],Rect2(96+i*280,252,258,52),host.rule.bind({"kind":"guess","block":i}),enabled)
		host.text("先记下你的猜测，再看试验结果。",Rect2(96,326,1090,40),19,true)
		return
	# Step 2: predict every candidate before any count is revealed.
	host.text("你猜的是(%d,%d)。先给四处各填一个预测：放这里会留下几条路？"%[p.candidate_blocks[guess][0],p.candidate_blocks[guess][1]],Rect2(81,214,1121,32),19,true)
	var predictions: Dictionary = state.get("predictions",{})
	var predicted_all: bool = predictions.size() >= 4
	for i in range(4):
		var point: Array = p.candidate_blocks[i]
		host.text("落石(%d,%d)留下"%[point[0],point[1]],Rect2(96+i*283,254,196,24),17,true)
		PuzzleBoards.number(host,"block_predict_"+str(i),int(predictions.get(str(i),0)),Rect2(96+i*283,280,180,40),0,Rules.all_paths(p).size(),func(value: int): host.rule({"kind":"predict_block","block":i,"value":value}))
	if not predicted_all:
		host.text("四处预测都填好后，才能移石头看实际结果。",Rect2(96,334,1090,30),19,true)
		return
	for i in range(4):
		var point: Array = p.candidate_blocks[i]
		var tried: bool = i in experiments
		var label: String = ("✓ " if i == block_index else "")+"落石(%d,%d)"%[point[0],point[1]]+("？" if not tried else "：留下%d条"%Rules.survivors(p,i))
		host.button("block_tab_"+str(i),label,Rect2(76+i*226,340,213,40),func():
			host.block_index = i; host.route_preview = ""
			if not (i in state.get("experiments",[])): host.rule({"kind":"view_block","block":i})
			else: host.refresh(),enabled)
	var paths = Rules.all_paths(p)
	var total_paths = paths.size()
	var canvas = Canvas.new(); canvas.name = "block_preview"; canvas.position = Vector2(78,392); canvas.size = Vector2(330,126)
	var tried_now: bool = block_index in experiments
	canvas.stone = Vector2i(p.candidate_blocks[block_index][0],p.candidate_blocks[block_index][1]) if tried_now else Vector2i(-1,-1)
	canvas.path = host.route_preview; canvas.enabled = false; host.ui.add_child(canvas)
	host.text("点一条路线看看它走不走这里" if tried_now else "先点上面的位置查看，再选路线",Rect2(82,524,560,24),17,true)
	for i in paths.size():
		var path: String = paths[i]; var x = 451+(i%5)*152; var y = 392+(i/5)*36
		var blocked = tried_now and p.candidate_blocks[block_index] in Rules.points(path)
		var caption = "路线%02d"%[i+1]
		if tried_now: caption += " ·挡" if blocked else " ·通"
		var b = host.button("preview_"+path,caption,Rect2(x,y,142,30),func():
			host.route_preview = path; host.refresh(),enabled and tried_now)
		if tried_now:
			b.mouse_entered.connect(func(): canvas.path = path; canvas.queue_redraw())
			b.focus_entered.connect(func(): canvas.path = path; canvas.queue_redraw())
	if tried_now:
		var survives = Rules.survivors(p,block_index)
		var predicted_value = int(state.get("predictions",{}).get(str(block_index),-1))
		var verdict = "" if predicted_value < 0 else ("；你预测%d ✓"%predicted_value if predicted_value == survives else "；你预测%d ✗"%predicted_value)
		host.text("这处：挡掉 %d 条，留下 %d 条（共%d条）%s" % [total_paths-survives,survives,total_paths,verdict],Rect2(82,550,560,26),17,true)
	host.button("choose_block","落石放这里",Rect2(675,542,287,36),host.rule.bind({"kind":"choose","block":block_index}),enabled and tried_now)
	host.button("try","发送信件",Rect2(984,542,213,36),host.rule.bind({"kind":"try"}),enabled)

extends RefCounted
const UIStyle = preload("res://scripts/cargo/skin.gd")
const Machine = preload("res://scripts/mechanisms/machine_rules.gd")
const MODULE_NAMES = {"plus2":"加2","plus3":"加3","plus5":"加5","plus7":"加7","minus1":"减1","double":"翻倍","triple":"三倍"}

static func number(host: Control, id: String, value: int, rect: Rect2, minimum: int, maximum: int, callback: Callable) -> LineEdit:
	var line = LineEdit.new(); line.name = id; line.position = rect.position+Vector2(49,0); line.size = rect.size-Vector2(98,0)
	line.text = str(value); line.max_length = 4; line.alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size",22); line.add_theme_color_override("font_color",UIStyle.DARK)
	line.add_theme_color_override("font_uneditable_color",UIStyle.DARK); line.add_theme_stylebox_override("read_only",paper_style())
	line.add_theme_stylebox_override("normal",paper_style()); line.tooltip_text = "输入后按Enter确认，也可点减号或加号。"
	line.editable = host.session.profile.active_run.outcome == "active"
	host.ui.add_child(line)
	line.text_submitted.connect(func(input: String):
		if host.busy or host.modal or not host.session.pending.is_empty(): return
		if input.is_valid_int() and int(input) >= minimum and int(input) <= maximum: callback.call(int(input))
		else: host.session.feedback = "请输入%d至%d的整数。"%[minimum,maximum]; host.refresh())
	host.button(id+"_minus","−",Rect2(rect.position,Vector2(42,rect.size.y)),callback.bind(maxi(minimum,value-1)),line.editable and value > minimum)
	host.button(id+"_plus","+",Rect2(rect.position+Vector2(rect.size.x-42,0),Vector2(42,rect.size.y)),callback.bind(mini(maximum,value+1)),line.editable and value < maximum)
	return line

static func paper_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new(); style.bg_color = Color("f4e8c8"); style.set_border_width_all(2); style.border_color = Color("aa9160"); style.content_margin_left = 10
	return style

static func draw(host: Control, definition: Dictionary, run: Dictionary) -> void:
	if definition.family != "pair_weights": preload("res://scripts/ui/workbench.gd").mount(host.ui,definition.family)
	match definition.family:
		"pair_weights": draw_pair(host,definition,run)
		"machine_records","machine_ambiguity": draw_machine(host,definition,run)
		"diagnostic_probe": draw_probe(host,definition,run)
		"takeaway_policy": draw_policy(host,definition,run)

static func draw_pair(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var p: Dictionary = definition.params; var enabled = run.outcome == "active"
	var weighed: Array = state.get("weighed",[])
	host.text("林婆婆把合称记录留在灯下。先称一对，再为三盏原有的村灯调好重量。",Rect2(42,168,1170,36),20)
	for i in range(3):
		var pair_id: String = ["ab","bc","ac"][i]
		var caption = ["甲 + 乙","乙 + 丙","甲 + 丙"][i]+("：%d" % [p.ab,p.bc,p.ac][i] if pair_id in weighed else " · 合称")
		host.button("weigh_"+pair_id,caption,Rect2(42+i*278,558,258,38),host.rule.bind({"kind":"weigh","first":[0,1,0][i],"second":[1,2,2][i]}),enabled and pair_id not in weighed)
	var places = [Vector2(246,341),Vector2(738,444),Vector2(1047,357)]
	for i in range(3):
		host.text(["甲灯","乙灯","丙灯"][i],Rect2(places[i]-Vector2(0,30),Vector2(160,28)),20)
		number(host,"weight_"+str(i),state.weights[i],Rect2(places[i],Vector2(181,38)),p.weight_min,p.weight_max,func(value: int): host.rule({"kind":"weight","index":i,"value":value}))
	host.button("try","点亮村灯",Rect2(1040,558,192,38),host.rule.bind({"kind":"try"}),enabled)

static func order_text(order: Array) -> String:
	var names = []
	for id in order: names.append(MODULE_NAMES[id])
	return " → ".join(names) if not names.is_empty() else "空槽 · 点击下方模块装入"

static func draw_machine(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var p: Dictionary = definition.params; var state: Dictionary = run.state; var enabled = run.outcome == "active"
	if p.has("checkpoint"):
		draw_ambiguity(host,definition,run); return
	host.text("账簿（这台机器必须同时满足）：输入%d得%d；输入%d得%d。"%[p.records[0][0],p.records[0][1],p.records[1][0],p.records[1][1]],Rect2(400,180,790,40),20,true)
	host.text(order_text(state.order),Rect2(84,240,1100,50),28,true)
	for i in p.modules.size():
		var id: String = p.modules[i].id
		host.button("module_"+id,MODULE_NAMES[id],Rect2(86+i*182,318,157,46),host.rule.bind({"kind":"order","value":state.order+[id]}),enabled and id not in state.order and state.order.size() < p.slots)
	host.button("clear_order","清空槽位",Rect2(1018,318,180,46),host.rule.bind({"kind":"order","value":[]}),enabled)
	host.text("（可选）押一注：先写下你猜的输出，启动后对答案。",Rect2(84,378,520,28),19,true)
	host.text("输入%d →"%int(p.predict_input),Rect2(620,380,168,26),19,true)
	number(host,"prediction",state.prediction,Rect2(796,374,170,36),0,100,func(value: int): host.rule({"kind":"predict","value":value}))
	host.button("try","启动机器",Rect2(1018,374,180,36),host.rule.bind({"kind":"try"}),enabled)
	if state.tested:
		var outputs = []
		for record in p.records: outputs.append("%d → %s"%[record[0],str(Machine.evaluate(Machine.operations(p,state.order),int(record[0])).slice(1))])
		var line = "齿轮留下的轨迹："+"；".join(outputs)
		if state.predicted_before_trial:
			var truth = Machine.evaluate(Machine.operations(p,state.order),int(p.predict_input)).back()
			line += "　你的押注 %d %s" % [state.prediction,"——猜对了！" if state.prediction == truth else "——实际是 %d"%truth]
		host.text(line,Rect2(84,470,1100,64),21,true)

static func draw_ambiguity(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var p: Dictionary = definition.params; var state: Dictionary = run.state
	var enabled = run.outcome == "active"
	var orders = Machine.candidates(p)
	var checkpoint: Dictionary = p.checkpoint
	var investigating: bool = state.revealed or (state.tested and state.order in orders)
	var observations: Array = state.get("observations",[int(checkpoint.after_step)-1] if state.revealed else [])
	host.text("② 查原装：两种都能育苗。请为师傅找回原机的先后顺序，补好保养档案。" if investigating else "① 验性能：两种装法都相当于先加2再翻倍。任选一台，按账簿试开。",Rect2(84,176,1120,32),20,true)
	for i in orders.size():
		var x = 86+i*560
		host.text(["装法一：","装法二："][i]+order_text(orders[i]),Rect2(x,217,540,34),24,true)
		var parts = []
		var trace = Machine.evaluate(Machine.operations(p,orders[i]),int(checkpoint.input))
		for step in range(3):
			parts.append("第%d步 %s" % [step+1,str(trace[step+1]) if investigating else "？"])
		if investigating:
			host.text("推算：输入%d → " % checkpoint.input+" → ".join(parts),Rect2(x,254,540,30),18,true)
		else:
			host.text("账簿都符合：4 → 12；7 → 18",Rect2(x,254,540,30),20,true)
			host.button("test_candidate_"+str(i),"试开装法"+["一","二"][i],Rect2(x,296,534,44),host.rule.bind({"kind":"try","order":orders[i]}),enabled)
	if not investigating:
		host.text("师傅：能正常育苗的装法，两种都算成功。",Rect2(86,374,1120,40),24,true)
		host.text("不过，保养档案还缺原机的先后顺序。验过性能后，我们再翻旧记录。",Rect2(86,425,1120,65),22,true)
		host.text("目标：先确认能工作，再用原机的中间记录恢复档案；不必猜哪种算法更正确。",Rect2(86,532,1120,34),19,true)
		return
	host.text("从外面试一试",Rect2(86,296,235,30),20,true)
	number(host,"external_input",state.external_input,Rect2(285,294,205,38),int(p.input_domain[0]),int(p.input_domain[1]),func(value: int): host.rule({"kind":"external_input","value":value}))
	host.button("observe_external","看看两种装法的结果",Rect2(515,294,270,38),host.rule.bind({"kind":"observe_external"}),enabled)
	var external = "性能已确认：任意输入的最终结果都相同；外部试验可选，只用于验证这一点。"
	if not state.external_tests.is_empty():
		var trial: Dictionary = state.external_tests.back()
		for saved in state.external_tests:
			if saved.input == state.external_input: trial = saved; break
		external = "外部试验：输入%d，两种装法都得到%d。只看输出，仍然分不开。" % [trial.input,trial.outputs[0]]
	host.text(external,Rect2(86,338,1120,30),20,true)
	host.text("推算中哪里不同？选那处翻原机记录（输入%d）" % checkpoint.input,Rect2(86,378,620,32),20,true)
	for step in range(3):
		host.button("reveal_"+str(step),("✓ " if step in observations else "查看 ")+["第1步后","第2步后","最后"][step],Rect2(701+step*166,375,154,38),host.rule.bind({"kind":"reveal","step":step}),enabled)
	var record = "先比较上面的推算，选一个能辨认先后顺序的取证点。"
	if int(checkpoint.after_step)-1 in observations:
		record = "原机记录：输入%d，第%d步后得到%d。哪种装法与它相符？" % [checkpoint.input,checkpoint.after_step,checkpoint.value]
	elif not observations.is_empty():
		var step: int = observations.back()
		# Non-discriminating positions have the same value in both valid candidates.
		var trace = Machine.evaluate(Machine.operations(p,orders[0]),int(checkpoint.input))
		record = "原机记录：输入%d，第%d步后得到%d。两种装法在这一步一样，还要换一处看。" % [checkpoint.input,step+1,trace[step+1]]
	host.text(record,Rect2(86,426,1120,44),22,true)
	var can_choose = int(checkpoint.after_step)-1 in observations
	for i in orders.size():
		host.button("final_order_"+str(i),"归档为装法"+["一：","二："][i]+order_text(orders[i]),Rect2(86+i*560,495,534,45),host.rule.bind({"kind":"final_order","value":orders[i]}),enabled and can_choose)
	host.text("另一种也能正常育苗；归档需要和原机当年的记录一致。",Rect2(86,550,1100,27),18,true)

static func operation_text(operations: Array) -> String:
	var labels = []
	for operation in operations: labels.append({"add":"加","sub":"减","mul":"乘"}[operation[0]]+str(operation[1]))
	return " → ".join(labels)

static func draw_probe(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var p: Dictionary = definition.params; var enabled = run.outcome == "active"
	host.text("A、B、C三台机器只有一台是真的，你只能投喂一次。先自己算出三台对这包种子的输出，各写一条预测，再投送对答案。",Rect2(83,176,1110,40),20,true)
	host.text("选一包种子：",Rect2(86,222,140,40),20,true)
	for i in p.probe_inputs.size():
		var input_value: int = p.probe_inputs[i]
		host.button("probe_input_"+str(input_value),("✓ " if state.probe_input == input_value else "")+str(input_value)+"颗",Rect2(226+i*164,219,140,44),host.rule.bind({"kind":"probe_input","value":input_value}),enabled and state.observation.is_empty())
	var probed: bool = not state.observation.is_empty()
	var index = 0
	for id in p.candidates:
		var x = 91+index*374
		host.text(id+"："+operation_text(p.candidates[id]),Rect2(x,286,331,42),24,true)
		if not probed:
			number(host,"predict_"+id,int(state.predictions.get(id,0)),Rect2(x+30,334,270,44),0,200,func(value: int): host.rule({"kind":"predict","id":id,"value":value}))
		else:
			var truth: int = Machine.evaluate(p.candidates[id],int(state.probe_input)).back()
			var predicted: int = int(state.predictions.get(id,-999))
			var mark = "（没写预测）" if predicted == -999 else ("✓" if predicted == truth else "✗ 实际 %d"%truth)
			host.text("你的预测 %d　%s"%[predicted,mark],Rect2(x,334,331,42),22,true)
		if probed: host.button("identify_"+id,"就是"+id+"号机",Rect2(x,503,298,44),host.rule.bind({"kind":"identify","id":id}),enabled)
		index += 1
	if not probed:
		host.text("预测填满三台才能投送；如果三台预测里有相同的数，这包种子就分不清。",Rect2(83,392,1100,42),20,true)
		host.button("probe","投送这包种子",Rect2(905,219,293,44),host.rule.bind({"kind":"probe"}),enabled)
	else:
		host.text("实际回响：%d → %d。哪一台机器的算法正好得到这个数？" % state.observation,Rect2(83,392,1100,44),24,true)

static func draw_policy(host: Control, _definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state; var enabled = run.outcome == "active"
	host.text("每次取1–3颗，拿到最后一颗获胜。守门人很精明，每一步都选对自己有利的取法。",Rect2(82,232,1100,48),21,true)
	host.text("还剩%d颗"%state.remaining,Rect2(89,296,593,50),28,true)
	for i in int(state.remaining):
		var token = ColorRect.new(); token.position = Vector2(93+(i%13)*67,380+(i/13)*46); token.size = Vector2(35,33); token.color = Color("b3975b"); token.mouse_filter = Control.MOUSE_FILTER_IGNORE; host.ui.add_child(token)
	if state.winner == "":
		host.text("守门人在数剩下的棋子。想想每一步会把什么样的局面留给他；需要时按 H 请伙伴提示。",Rect2(82,478,1100,36),19,true)
	for amount in range(1,4): host.button("take_"+str(amount),"取%d颗"%amount,Rect2(91+(amount-1)*225,516,201,46),host.rule.bind({"kind":"take","value":amount}),enabled and state.winner == "" and amount <= state.remaining)
	if state.winner != "": host.text("你拿到了最后一颗，守门人认输了！" if state.winner == "player" else "守门人拿到最后一颗；撤销或重新摆放。",Rect2(765,299,422,130),22,true)

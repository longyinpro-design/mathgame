extends RefCounted
# Page construction only; commands, navigation and save ownership stay in the host.

static func draw_camp(host: Control) -> void:
	host.navigation("森林营地","林间来信 · 第一章")
	host.text("Lv.%d   行旅经验 %d   木片 %d" % [host.Session.Catalog.rank(host.session.profile.progress.journey_exp),host.session.profile.progress.journey_exp,host.session.profile.inventory.camp_wood],Rect2(42,650,650,32),20)
	host.button("party","同行伙伴",Rect2(1090,653,153,39),host.open_page.bind("party"))
	if host.story_enabled: host.button("continue_story","继续故事",Rect2(465,252,350,52),host.resume_story,true,null,true)
	if host.session.profile.story.node in ["end","voyage"]:
		host.button("market","千灯集市 · "+("新的航路" if host.session.profile.story.node == "end" else "接货台"),Rect2(465,314,350,46),host.goto_market,true,null,true)
	var i = 0
	for id in host.REGIONS:
		var x = [66,316,566,816,1066][i]
		var unlocked = false
		for level_id in host.REGIONS[id].levels:
			if host.session.catalog.available(level_id,host.session.profile.progress.completed_levels): unlocked = true
		host.button("region_"+id,host.REGIONS[id].name+(" · 回访" if host.story_enabled else ""),Rect2(x,166+i%2*45,160,44),host.show_region.bind(id),unlocked)
		i += 1
	var run = host.session.profile.active_run
	if run != null and run.outcome == "active": host.button("resume","继续 · "+host.session.catalog.levels[run.level_id].title,Rect2(60,292,380,44),host.resume)
	for entry in [["roof",Vector2(993,341)],["workbench",Vector2(167,516)],["garden",Vector2(862,559)]]:
		var id: String = entry[0]; var building: Dictionary = host.Session.Catalog.BUILDINGS[id]
		var built = id in host.session.profile.inventory.buildings
		var available = building.requires in host.session.profile.progress.completed_levels
		if available or built:
			host.button("build_"+id,building.name+(" · 已建成" if built else " · %d木片"%building.cost),Rect2(entry[1],Vector2(233,39)),host.confirm_build.bind(id),not built)
	if host.Session.Roster.can_grow(host.session.profile): host.button("grow","给阿橙系上同心叶结",Rect2(412,404,280,43),host.dispatch.bind({"kind":"grow"}))
	host.button("chat","和伙伴聊聊",Rect2(454,556,190,36),host.camp_chat)


static func draw_journal(host: Control) -> void:
	host.navigation("林间手记","记下走过的路、遇见的人和恢复的地方。")
	host.UIStyle.panel(host.ui,Rect2(55,159,1170,430),true)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(79,181); scroll.size = Vector2(1115,384); host.ui.add_child(scroll)
	var content = VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(content)
	if host.story_enabled:
		for id in host.session.profile.story.seen:
			var beat = host.Story.scene(id)
			var label = Label.new(); label.text = beat.title+" · "+beat.speaker+"："+beat.text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size = Vector2(1060,62); label.add_theme_color_override("font_color",host.UIStyle.DARK); content.add_child(label)
		for id in host.session.catalog.levels:
			if (id in host.Session.Flow.SIDES or id in host.session.profile.progress.completed_levels) and host.session.catalog.available(id,host.session.profile.progress.completed_levels):
				var caption = "回忆 / 再玩 · " if id in host.session.profile.progress.completed_levels else "邻居的邀请 · "
				var invite = Button.new(); invite.text = caption+host.session.catalog.levels[id].title; invite.custom_minimum_size.y = 42; invite.disabled = host.session.profile.story.return_node != ""; invite.pressed.connect(host.story_excursion.bind(id)); invite.name = "invite_"+id; host.buttons["invite_"+id] = invite; content.add_child(invite)
	var lines = []
	if not host.session.profile.get("legacy_fl07_runs",{}).is_empty() or host.session.profile.story.results.get("FL07",{}).has("final_order"):
		lines.append("第七关已更新为24点；旧版中间记录与奖励保留，旧版完成不记作24点解答。")
	for id in host.session.profile.progress.completed_levels:
		lines.append("✓ "+host.session.catalog.levels[id].title)
		lines.append(host.level_reaction(id))
	for dialogue in host.session.profile.world.dialogues: lines.append(host.Story.DIALOGUES[dialogue].text)
	for dialogue in host.session.profile.world.region_dialogues: lines.append("林间对话："+host.Story.region_dialogue(dialogue).text)
	for id in host.session.profile.progress.completed_levels:
		if host.Story.ITEMS.has(id): lines.append("收藏 · "+host.Story.ITEMS[id].name+"："+host.Story.ITEMS[id].story)
	if lines.is_empty(): lines.append("第一袋种子还在树梢站。和阿橙出发吧。")
	if host.session.profile.active_run != null:
		var run: Dictionary = host.session.profile.active_run
		lines.append("当前现场："+host.session.catalog.levels[run.level_id].title+"；回到入口可以接着上次的摆法继续。")
		for entry in run.hint_log: lines.append("伙伴的想法："+entry.text)
		for i in run.tools.snapshots.size(): lines.append("前后手记第%d张："%(i+1)+host.snapshot_text(run.tools.snapshots[i]))
		for path in run.tools.route_tags: lines.append("我的路签："+path+" → %d层"%run.tools.route_tags[path])
	for id in host.session.profile.suspended_runs:
		var saved: Dictionary = host.session.profile.suspended_runs[id]
		lines.append("暂存现场："+host.session.catalog.levels[id].title+"，可从地区入口继续。")
		for entry in saved.hint_log: lines.append("暂存提示："+entry.text)
		for path in saved.tools.route_tags: lines.append("暂存路签："+path+" → %d层"%saved.tools.route_tags[path])
	for line in lines:
		var label = Label.new(); label.text = line; label.add_theme_color_override("font_color",host.UIStyle.DARK); label.add_theme_font_size_override("font_size",20); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size = Vector2(1070,42); content.add_child(label)
	host.button("back","合上手记",Rect2(1044,659,200,39),host.back)


static func draw_party(host: Control) -> void:
	host.navigation("同行伙伴","两位伙伴出行，所有已加入伙伴共享行旅等级；主线工具始终可用。")
	host.UIStyle.panel(host.ui,Rect2(55,160,1170,427),true)
	var index = 0
	for id in host.session.profile.roster.owned:
		var partner: Dictionary = host.Session.Catalog.PARTNERS[id]; var x = 86+index*376
		host.text(partner.name+"  Lv.%d"%host.Session.Catalog.rank(host.session.profile.progress.journey_exp),Rect2(x,200,310,45),28,true)
		var portrait = host.Actor.new(); portrait.identity = id; portrait.position = Vector2(x+239,299); portrait.pixel_scale = 0.35; portrait.grown = host.session.profile.roster.grown; host.ui.add_child(portrait)
		host.text("共同经历：%d"%host.session.profile.roster.bonds[id].size(),Rect2(x,277,309,41),20,true)
		for skill_index in partner.skills.size():
			var skill: String = partner.skills[skill_index]
			var gate = {"compare":"FL06","bands":"FL11","shadow":"FL10"}.get(skill,"")
			var available = gate == "" or gate in host.session.profile.progress.completed_levels
			host.button("equip_"+skill,("✓ " if skill in host.session.profile.roster.loadouts[id] else "")+host.SKILL_NAMES[skill],Rect2(x,339+skill_index*58,284,42),host.dispatch.bind({"kind":"equip","partner":id,"skill":skill}),available)
		host.button("party_"+id,"留在营地" if id in host.session.profile.roster.party else "一起出发",Rect2(x,481,264,43),host.toggle_party.bind(id))
		index += 1
	host.button("back","回到营地",Rect2(1044,659,200,39),host.go_camp)


static func draw_visit(host: Control) -> void:
	host.navigation(host.session.catalog.levels[host.visit_id].title+" · 回访",host.Story.region_line(host.region,host.session.profile.progress.completed_levels))
	host.world.page = "region"
	host.UIStyle.panel(host.ui,Rect2(65,182,702,204),true)
	host.text(host.level_reaction(host.visit_id),Rect2(93,209,646,134),24,true)
	host.text("这里已经恢复；可以看看伙伴，也可以再玩一次。",Rect2(81,424,991,92),22)
	host.button("practice","再玩一次",Rect2(82,538,274,45),host.request_level.bind(host.visit_id,true))
	host.button("back","回到林间",Rect2(1000,659,243,40),host.show_region.bind(host.region))


static func draw_settings(host: Control) -> void:
	host.navigation("设置","声音可关闭；重要提示同时显示在场景中。")
	host.UIStyle.panel(host.ui,Rect2(191,165,896,417),true)
	host.text("环境与音乐音量",Rect2(235,215,340,45),24,true)
	var slider = HSlider.new(); slider.name = "volume"; slider.position = Vector2(590,219); slider.size = Vector2(419,35); slider.min_value = 0; slider.max_value = 1; slider.step = 0.05; slider.value = host.session.profile.settings.volume; host.ui.add_child(slider)
	slider.value_changed.connect(func(value: float):
		if host.busy or host.modal or not host.session.pending.is_empty(): return
		host.session.command({"kind":"settings","values":{"volume":value}},int(host.session.profile.revision)); host.apply_audio()
		if not host.session.pending.is_empty(): host.refresh())
	host.button("mute","打开声音" if host.session.profile.settings.muted else "关闭声音",Rect2(590,291,419,44),host.dispatch.bind({"kind":"settings","values":{"muted":not host.session.profile.settings.muted}}))
	host.button("short_effects","重复演出：短" if host.session.profile.settings.short_effects else "重复演出：完整",Rect2(590,367,419,44),host.dispatch.bind({"kind":"settings","values":{"short_effects":not host.session.profile.settings.short_effects}}))
	host.text("鼠标点选或拖动；Tab切换控件，Enter确认。\n货运：数字键选物件，方向键放置，Space松闸。\nH请求提示，Z撤销，Esc取消或返回。",Rect2(235,440,780,116),20,true)
	host.button("back","返回",Rect2(1044,659,200,39),host.back)


static func draw_region(host: Control) -> void:
	host.navigation(host.REGIONS[host.region].name,host.Story.region_line(host.region,host.session.profile.progress.completed_levels))
	host.text("走近发光的物件，再按 E（或点它）互动。",Rect2(42,141,1063,35),20)
	var ids: Array = host.REGIONS[host.region].levels
	for i in ids.size():
		var id: String = ids[i]; var definition: Dictionary = host.session.catalog.levels[id]
		var complete = id in host.session.profile.progress.completed_levels
		var available = host.session.catalog.available(id,host.session.profile.progress.completed_levels)
		var point = host.Layout.point(host.region,i)
		# The object itself is the trigger: a hotspot on the prop, with a walk-then-interact flow.
		var hotspot = host.button("object_"+id,"",Rect2(point-Vector2(48,74),Vector2(96,90)),host.request_level.bind(id,false),available)
		host.UIStyle.hotspot(hotspot,definition.title)
	if host.region != "post" or "feather" not in host.session.profile.roster.owned:
		var npc_point = host.Layout.npc_foot(host.region)-Vector2(0,70)
		var npc_button = host.button("npc","",Rect2(npc_point-Vector2(92,26),Vector2(184,52)),host.interact_npc)
		host.UIStyle.hotspot(npc_button,host.Story.NPC_NAMES[host.region])
		if host.world.hero_position.distance_to(host.Layout.npc_foot(host.region)) < 150: host.text("按 E 和"+host.Story.NPC_NAMES[host.region]+"聊聊",Rect2(npc_point-Vector2(90,50),Vector2(240,30)),19)
	# Pokeable corners of the scene: small answers, no progress attached.
	host.world.flavor_spots = host.Story.FLAVOR.get(host.region,[])
	for i in host.world.flavor_spots.size():
		var spot: Array = host.world.flavor_spots[i]
		var poke = host.button("poke_"+host.region+"_"+str(i),"",Rect2(Vector2(spot[0],spot[1])-Vector2(34,34),Vector2(68,68)),host.poke_flavor.bind(i))
		host.UIStyle.hotspot(poke,spot[2])
	# Quest interactions take priority where a painted prop also has ambient flavour.
	for id in ids: host.ui.move_child(host.buttons["object_"+id],-1)


static func draw_story(host: Control) -> void:
	var node: String = host.session.profile.story.node
	var beat = host.Story.scene(node)
	if node == "post_FL07" and host.session.profile.story.excursion == "" and host.session.profile.story.results.get("FL07",{}).has("final_order"):
		beat = beat.duplicate(true); beat.title = "磨坊的旧记录"; beat.text = "旧版关卡的修复已经完成，奖励和进度保留。新的24点挑战可以从手记中再玩。"
	if beat.kind == "puzzle": host.page = "challenge"; host.draw_challenge(); return
	host.world.visible = false; host.story_stage.visible = true
	if host.story_stage.node_id != node:
		host.sound.play_cue({"delivery":"place","letter":"pickup","gates_lit":"unlock","join":"reward","bridge":"unlock","finale":"reward"}.get(beat.effect,"footstep"))
	host.story_stage.setup(node,host.session.profile,host.time_scale)
	host.region = beat.region if beat.region != "camp" else "treetop"
	host.navigation(beat.title,"林间来信 · "+("旧事与新的约定" if host.session.profile.story.seen.is_empty() and not host.session.profile.progress.completed_levels.is_empty() else "故事进行中"))
	var grain_scene = beat.region in ["village","mill","heart"] and not host.story_stage.cargo_scene and beat.effect != "bridge"
	var upper_dialogue = beat.region in ["treetop","camp"] and not host.story_stage.cargo_scene
	host.UIStyle.panel(host.ui,Rect2(60,155,1160,132) if upper_dialogue else (Rect2(60,557,1160,96) if grain_scene else Rect2(60,493,1160,158)),true)
	host.text(beat.speaker,Rect2(106,168,1070,26) if upper_dialogue else (Rect2(106,562,1070,26) if grain_scene else Rect2(106,507,1070,29)),19 if grain_scene else 21,true)
	host.text(beat.text,Rect2(106,203,1070,72) if upper_dialogue else (Rect2(106,590,1070,60) if grain_scene else Rect2(106,545,1070,100)),20 if grain_scene or upper_dialogue else 23,true)
	host.button("story_skip","跳过本段动作",Rect2(1020,110,200,36),func(): host.story_stage.skip(); host.refresh(),not host.story_stage.done)
	host.button("story_pause","继续播放" if host.story_stage.paused else "暂停",Rect2(885,110,125,36),func(): host.story_stage.paused = not host.story_stage.paused; host.refresh())
	var ready: bool = host.story_stage.done and not host.story_stage.paused
	if node == "post_branch":
		for i in range(2):
			var id: String = ["FL09","FL10"][i]
			if id not in host.session.profile.progress.completed_levels: host.button("choose_"+id,"先去落石路口" if i == 0 else "先安排两封信",Rect2(590+i*320,665,300,39),host.dispatch.bind({"kind":"story_choose","level_id":id},"story"),ready,null,true)
	else: host.button("story_continue",beat.action,Rect2(780,665,440,39),host.story_continue.bind(node),ready,null,true)
	if host.session.profile.story.return_node != "": host.button("story_return","稍后再来 · 返回故事",Rect2(60,665,330,39),func():
		if host.dispatch({"kind":"story_return"},"story"): host.resume_story())
	elif node in ["joined","rest_village","rest_post","rest_growth","end","voyage"]: host.button("story_rest","在营地歇脚",Rect2(60,665,230,39),host.go_camp)
	if node == "rest_growth" and host.Session.Roster.can_grow(host.session.profile): host.button("story_grow","系上同心叶结",Rect2(320,665,260,39),host.dispatch.bind({"kind":"grow"}),ready)
	if node.begins_with("post_") and beat.level != "":
		var reward: Dictionary = host.session.catalog.levels[beat.level].reward
		host.text(("收藏 · "+host.Story.ITEMS[beat.level].name) if host.Story.ITEMS.has(beat.level) else "林间手记 · "+host.session.catalog.levels[beat.level].title,Rect2(60,615,1120,35) if upper_dialogue else Rect2(60,153,1120,35),19)

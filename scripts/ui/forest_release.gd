extends Control
const Session = preload("res://scripts/core/game_session.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const CargoWorld = preload("res://scripts/cargo/world.gd")
const ForestWorld = preload("res://scripts/ui/forest_world.gd")
const Audio = preload("res://scripts/encounter/audio.gd")
const CargoRules = preload("res://scripts/mechanisms/cargo_rules.gd")
const BaseCargo = preload("res://scripts/cargo/rules.gd")
const TwentyFourBoard = preload("res://scripts/ui/twenty_four_board.gd")
const TwentyFourConsole = preload("res://scripts/ui/twenty_four_console.gd")
const PuzzleBoards = preload("res://scripts/ui/puzzle_boards.gd")
const RouteBoards = preload("res://scripts/ui/route_boards.gd")
const SideBoards = preload("res://scripts/ui/side_boards.gd")
const BattleWorld = preload("res://scripts/ui/battle_world.gd")
const BattleBoards = preload("res://scripts/ui/battle_boards.gd")
const StoryStage = preload("res://scripts/ui/story_stage.gd")
const Story = preload("res://scripts/content/story_catalog.gd")
const MarketSample = preload("res://scripts/market/mk01_scene.gd")
const MARKET_SCENE = "res://game/market_mk01.tscn"
const SKILL_NAMES = {"mark":"观察签","compare":"前后手记","group":"抱团搬运","bands":"分组带","route_tag":"路签","shadow":"影子探路"}
const Layout = preload("res://scripts/ui/scene_layout.gd")
var scene_detail = true
const TransferStage = preload("res://scripts/ui/transfer_stage.gd")
const Actor = preload("res://scripts/ui/companion_actor.gd")
const CargoAnnotations = preload("res://scripts/ui/cargo_annotations.gd")
const REGIONS = {
	"treetop":{"name":"树梢站","levels":["FL01","FL13"],"line":"第一袋种子，正等着搭上树梢的吊篮。"},
	"village":{"name":"晨种村","levels":["FL03","FL04"],"line":"借粮的记录留在三座仓旁，灯架还没有亮。"},
	"mill":{"name":"旧磨坊","levels":["FL05","FL06","FL07","FL15"],"line":"育苗机嗡嗡作响，账簿里的线索却不完整。"},
	"post":{"name":"林间邮路","levels":["FL08","FL09","FL10","FL14","FL16"],"line":"折羽绕着路口飞了一圈：还有信没有送到。"},
	"heart":{"name":"古林心庭","levels":["FL02","FL11","FL12","FL17","FL18"],"line":"树根深处，石灵守着森林的回声。"}
}
var story_stage: Node2D
var story_enabled = true
var session = Session.new()
var save_path = ""
var world: Node2D
var cargo_world: Node2D
var sound: Node
var ui: Control
var overlay: Control
var page = "camp"
var previous_page = "camp"
var region = "treetop"
var busy = false
var modal = false
var twenty_selection: Array = []
var twenty_board_key = ""
var selected = -1
var down_item = -1
var down_position = Vector2.ZERO
var time_scale = 1.0
var buttons: Dictionary = {}
var message: Label
var action_button: Button
var dialogue_left = 0.0
var queued_page = ""
var board_tab = "initial"
var confirmation: Callable
var confirmation_open = false
var scroll_positions: Dictionary = {}
var block_index = 0
var coin_node = "root"
var selected_coin = -1
var fence_area = 1
var battle_world: Node2D
var twenty_console: Node2D
var selected_card = -1
var selected_core = -1
var battle_presentation: Dictionary = {}
var visit_id = ""
var tool_items: Array = []
var page_stack: Array = []
var walking = false
var walk_cancelled = false
var transfer_stage: Node2D
var trace_preview = -1
var route_preview = "RRRUUU"
var tool_group_size = 1
var tool_group_source = 0

func _ready() -> void:
	get_window().title = "数字群岛 · 森林岛"
	mouse_filter = Control.MOUSE_FILTER_IGNORE; theme = UIStyle.make()
	world = ForestWorld.new(); add_child(world)
	cargo_world = CargoWorld.new(); add_child(cargo_world); cargo_world.visible = false
	battle_world = BattleWorld.new(); add_child(battle_world); battle_world.visible = false
	twenty_console = TwentyFourConsole.new(); twenty_console.z_index = 0; add_child(twenty_console); twenty_console.visible = false
	story_stage = StoryStage.new(); add_child(story_stage); story_stage.visible = false
	story_stage.finished.connect(func():
		if page == "story": refresh())
	sound = Audio.new(); add_child(sound)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; overlay.z_index = 100; add_child(overlay)
	session.open(save_path)
	if MarketSample.entry == "return":
		# Back from the market dock: the crossing was already watched, so open at the camp.
		MarketSample.entry = ""
	elif story_enabled and not session.profile.is_empty():
		page = "story"
		if Story.scene(session.profile.story.node).kind == "puzzle": resume_story()
	refresh()

func text(value: String, rect: Rect2, size_px: int = 20, paper: bool = false, parent: Node = null) -> Label:
	var label = UIStyle.text(ui if parent == null else parent,value,rect,20,UIStyle.DARK if paper else UIStyle.INK)
	label.add_theme_font_size_override("font_size",size_px)
	label.size = rect.size
	return label

func button(id: String, value: String, rect: Rect2, action: Callable, enabled: bool = true, parent: Node = null, primary: bool = false) -> Button:
	var guarded: Callable = func():
		if not busy and not modal and session.pending.is_empty() and not session.repository.protected: action.call()
	var b = UIStyle.button(ui if parent == null else parent,value,rect,guarded,primary)
	b.size = rect.size
	b.name = id; b.disabled = not enabled; buttons[id] = b
	return b

func clear_children(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func refresh() -> void:
	var focus = get_viewport().gui_get_focus_owner()
	var focus_name = str(focus.name) if is_instance_valid(focus) else ""
	for node in ui.find_children("*","ScrollContainer",true,false): scroll_positions[str(node.name)] = node.scroll_vertical
	clear_children(ui); buttons.clear(); clear_children(overlay); modal = false; confirmation_open = false
	world.page = page; world.region = region
	world.inspecting = page == "challenge" and session.profile.get("active_run") != null and session.profile.active_run.level_id in Layout.DETAIL_LEVELS and scene_detail
	world.active_level = session.profile.active_run.level_id if session.profile.get("active_run") != null else ""
	world.original_village = page == "challenge" and session.profile.get("active_run") != null and session.profile.active_run.level_id == "FL03"
	world.ground.visible = not world.original_village
	world.visible = true; cargo_world.visible = false; battle_world.visible = false; story_stage.visible = false
	twenty_console.visible = false; world.flavor_spots = []
	if session.profile.is_empty():
		text("森林手记暂时无法打开",Rect2(70,100,800,50),28)
		show_save_error(); return
	world.buildings = session.profile.inventory.buildings; world.owned = session.profile.roster.owned
	world.party = session.profile.active_run.party if page == "challenge" and session.profile.active_run != null else session.profile.roster.party
	world.completed = session.profile.progress.completed_levels; world.grown = session.profile.roster.grown
	world.suspended_ids = session.profile.suspended_runs.keys()
	var open_ids = []
	for level_id in session.catalog.levels:
		if session.catalog.available(level_id,session.profile.progress.completed_levels): open_ids.append(level_id)
	world.available_ids = open_ids
	apply_audio()
	match page:
		"story": draw_story()
		"camp": draw_camp()
		"region": draw_region()
		"challenge": draw_challenge()
		"journal": draw_journal()
		"party": draw_party()
		"settings": draw_settings()
		"visit": draw_visit()
		"tools": draw_tools()
	var foreground_party = page == "challenge" and (world.visible or battle_world.visible)
	message = text("" if page == "story" else session.feedback,Rect2(420,598,810,30 if world.original_village else 55) if foreground_party else Rect2(40,598,930,55),18 if foreground_party else 20)
	if world.original_village and busy: message.text = "正在搬粮 · 看看送出仓和接收仓的变化。"
	message.add_theme_color_override("font_color",UIStyle.GOLD)
	if busy:
		for b in buttons.values(): b.disabled = true
	if not session.pending.is_empty() or session.repository.protected: show_save_error()
	elif buttons.has(focus_name) and not buttons[focus_name].disabled: buttons[focus_name].grab_focus()
	for node in ui.find_children("*","ScrollContainer",true,false): node.set_deferred("scroll_vertical",scroll_positions.get(str(node.name),0))

func navigation(title: String, subtitle: String = "") -> void:
	text(title,Rect2(39,24,780,42),28)
	text(subtitle,Rect2(41,70,930,80),20)
	button("camp","营地",Rect2(990,30,75,38),go_camp)
	button("journal","手记",Rect2(1080,30,75,38),open_page.bind("journal"))
	button("settings","设置",Rect2(1170,30,75,38),open_page.bind("settings"))

func draw_camp() -> void:
	navigation("森林营地","林间来信 · 第一章")
	text("Lv.%d   行旅经验 %d   木片 %d" % [Session.Catalog.rank(session.profile.progress.journey_exp),session.profile.progress.journey_exp,session.profile.inventory.camp_wood],Rect2(42,650,650,32),20)
	button("party","同行伙伴",Rect2(1090,653,153,39),open_page.bind("party"))
	if story_enabled: button("continue_story","继续故事",Rect2(465,252,350,52),resume_story,true,null,true)
	if session.profile.story.node in ["end","voyage"]:
		button("market","千灯集市 · "+("新的航路" if session.profile.story.node == "end" else "接货台"),Rect2(465,314,350,46),goto_market,true,null,true)
	var i = 0
	for id in REGIONS:
		var x = [66,316,566,816,1066][i]
		var unlocked = false
		for level_id in REGIONS[id].levels:
			if session.catalog.available(level_id,session.profile.progress.completed_levels): unlocked = true
		button("region_"+id,REGIONS[id].name+(" · 回访" if story_enabled else ""),Rect2(x,166+i%2*45,160,44),show_region.bind(id),unlocked)
		i += 1
	var run = session.profile.active_run
	if run != null and run.outcome == "active": button("resume","继续 · "+session.catalog.levels[run.level_id].title,Rect2(60,292,380,44),resume)
	for entry in [["roof",Vector2(993,341)],["workbench",Vector2(167,516)],["garden",Vector2(862,559)]]:
		var id: String = entry[0]; var building: Dictionary = Session.Catalog.BUILDINGS[id]
		var built = id in session.profile.inventory.buildings
		var available = building.requires in session.profile.progress.completed_levels
		if available or built:
			button("build_"+id,building.name+(" · 已建成" if built else " · %d木片"%building.cost),Rect2(entry[1],Vector2(233,39)),confirm_build.bind(id),not built)
	if Session.Roster.can_grow(session.profile): button("grow","给阿橙系上同心叶结",Rect2(412,404,280,43),dispatch.bind({"kind":"grow"}))
	button("chat","和伙伴聊聊",Rect2(454,556,190,36),camp_chat)

func camp_chat() -> void:
	dispatch({"kind":"dialogue","id":Story.camp_dialogue(session.profile.progress.completed_levels)})
	world.reaction = 0.7; sound.play_cue("fox")
	for actor in world.actors.values(): actor.play("talk",1.4)

func goto_market() -> void:
	if busy or modal or session.profile.is_empty(): return
	if session.profile.story.node == "voyage": open_market(); return
	if dispatch({"kind":"story_voyage"},"story"): page = "story"; refresh()

func open_market() -> void:
	if busy or modal: return
	MarketSample.entry = "camp"
	get_tree().change_scene_to_file(MARKET_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if busy or modal or page not in ["camp","region"]: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse()*event.position
		var place = "camp" if page == "camp" else region
		if absf(point.y-Layout.FEET_Y[place]) < 55:
			world.destination = Layout.foot(place,point.x); get_viewport().set_input_as_handled()

func show_region(id: String) -> void:
	page_stack.clear(); region = id; page = "region"; selected = -1
	var saved_position: Array = session.profile.world.region_positions.get(id,[128,560])
	world.hero_position = Layout.foot(region,float(saved_position[0])); world.destination = world.hero_position
	session.feedback = Story.region_line(id,session.profile.progress.completed_levels); refresh()

func draw_region() -> void:
	navigation(REGIONS[region].name,Story.region_line(region,session.profile.progress.completed_levels))
	text("走近发光的物件，再按 E（或点它）互动。",Rect2(42,141,1063,35),20)
	var ids: Array = REGIONS[region].levels
	for i in ids.size():
		var id: String = ids[i]; var definition: Dictionary = session.catalog.levels[id]
		var complete = id in session.profile.progress.completed_levels
		var available = session.catalog.available(id,session.profile.progress.completed_levels)
		var point = Layout.point(region,i)
		# The object itself is the trigger: a hotspot on the prop, with a walk-then-interact flow.
		var hotspot = button("object_"+id,"",Rect2(point-Vector2(48,74),Vector2(96,90)),request_level.bind(id,false),available)
		UIStyle.hotspot(hotspot,definition.title)
	if region != "post" or "feather" not in session.profile.roster.owned:
		var npc_point = Layout.npc_foot(region)-Vector2(0,70)
		var npc_button = button("npc","",Rect2(npc_point-Vector2(92,26),Vector2(184,52)),interact_npc)
		UIStyle.hotspot(npc_button,Story.NPC_NAMES[region])
		if world.hero_position.distance_to(Layout.npc_foot(region)) < 150: text("按 E 和"+Story.NPC_NAMES[region]+"聊聊",Rect2(npc_point-Vector2(90,50),Vector2(240,30)),19)
	# Pokeable corners of the scene: small answers, no progress attached.
	world.flavor_spots = Story.FLAVOR.get(region,[])
	for i in world.flavor_spots.size():
		var spot: Array = world.flavor_spots[i]
		var poke = button("poke_"+region+"_"+str(i),"",Rect2(Vector2(spot[0],spot[1])-Vector2(34,34),Vector2(68,68)),poke_flavor.bind(i))
		UIStyle.hotspot(poke,spot[2])
	# Quest interactions take priority where a painted prop also has ambient flavour.
	for id in ids: ui.move_child(buttons["object_"+id],-1)

func poke_flavor(index: int) -> void:
	var spot: Array = world.flavor_spots[index]
	session.feedback = spot[3]
	world.poked = Vector2(spot[0],spot[1]); world.poked_time = 0.9
	world.reaction = 0.7; sound.play_cue("fox")
	for actor in world.actors.values(): actor.play("interact",0.8)
	refresh()

func interact_target() -> void:
	# E key: nearest available object, otherwise the resident if close by.
	if page != "region": return
	var best = ""; var best_distance = 150.0
	for id in REGIONS[region].levels:
		var index = REGIONS[region].levels.find(id)
		var point = Layout.point(region,index)
		var distance = absf(world.hero_position.x-point.x)
		if distance < best_distance and session.catalog.available(id,session.profile.progress.completed_levels):
			best = id; best_distance = distance
	if best != "":
		request_level(best,false); return
	if (region != "post" or "feather" not in session.profile.roster.owned) and world.hero_position.distance_to(Layout.npc_foot(region)) < 150:
		interact_npc()

func request_level(id: String, practice: bool = false) -> void:
	if story_enabled:
		if id in Session.Flow.SIDES or id in session.profile.progress.completed_levels: story_excursion(id)
		else: resume_story()
		return
	var target_region = Session.Catalog.region_for(id)
	if page != "region" or region != target_region: show_region(target_region)
	var index = REGIONS[region].levels.find(id)
	var point = Layout.point(region,index)
	if not await walk_to(Layout.foot(region,point.x-55)): return
	if practice: begin_challenge(id)
	else: start(id)

func walk_to(point: Vector2) -> bool:
	walking = true; walk_cancelled = false; busy = true; world.destination = point; world.walk_speed = 190.0/maxf(0.05,time_scale)
	refresh()
	while world.hero_position.distance_to(point) > 8 and not walk_cancelled: await get_tree().process_frame
	world.walk_speed = 190.0; walking = false; busy = false
	if walk_cancelled: world.destination = world.hero_position; session.feedback = "先停在这里，想继续时再点物件。"; refresh(); return false
	world.hero_position = point; world.destination = point; refresh(); return true

func interact_npc() -> void:
	if not await walk_to(Layout.foot(region,Layout.npc_foot(region).x-65)): return
	if dispatch({"kind":"talk_region","region":region,"position":position_record()}):
		world.npc.talking = 2.0; sound.play_cue("fox")

func position_record() -> Array:
	# Saves retain the original logical road; the art-space height is a view concern.
	return [clampi(roundi(world.hero_position.x),100,1120),560]

func return_to_region() -> void:
	if story_enabled:
		if session.profile.story.return_node != "":
			if dispatch({"kind":"story_return"},"story"): resume_story()
		else: go_camp()
		return
	if session.profile.active_run == null: return
	var run: Dictionary = session.profile.active_run
	if dispatch({"kind":"location","region":Session.Catalog.region_for(run.level_id),"position":run.source_position}): show_region(Session.Catalog.region_for(run.level_id))

func start(id: String) -> void:
	if id in session.profile.progress.completed_levels:
		visit_id = id
		if dispatch({"kind":"location","region":region,"position":position_record()},"visit"): page = "visit"; session.feedback = level_reaction(id); refresh()
		return
	begin_challenge(id)

func begin_challenge(id: String) -> void:
	page_stack.clear(); scene_detail = true; board_tab = "initial"; selected = -1; selected_core = -1; selected_card = -1
	region = Session.Catalog.region_for(id)
	if id == "FL03": world.grain_hero = TransferStage.VILLAGE_FEET.hero
	if dispatch({"kind":"start","level_id":id,"source_position":position_record()},"challenge"):
		page = "challenge"; refresh()

func resume() -> void:
	if story_enabled:
		resume_story(); return
	var id: String = session.profile.active_run.level_id
	if dispatch({"kind":"start","level_id":id},"challenge"): region = Session.Catalog.region_for(id); page = "challenge"; refresh()

func open_page(target: String) -> void:
	if target == page: return
	page_stack.append(page); previous_page = page; page = target; selected = -1; refresh()

func go_camp() -> void:
	if dispatch({"kind":"camp"},"camp"):
		page_stack.clear(); page = "camp"; world.hero_position = Vector2(470,565); world.destination = world.hero_position; refresh()

func draw_challenge() -> void:
	if session.profile.active_run == null: page = "camp"; draw_camp(); return
	var run: Dictionary = session.profile.active_run; var definition: Dictionary = session.catalog.levels[run.level_id]
	if run.level_id == "FL07" and run.outcome == "complete" and run.state.has("final_order"):
		visit_id = "FL07"; draw_visit(); return
	navigation(definition.title,goal(definition))
	button("region_back","返回林间",Rect2(846,30,131,38),return_to_region)
	if run.level_id in Layout.DETAIL_LEVELS and not scene_detail:
		draw_field_level(definition,run)
	elif definition.family == "twenty_four": TwentyFourBoard.draw(self,definition,run)
	elif definition.family in ["cargo","cargo_planning","cargo_optimal"]: draw_cargo(definition,run)
	elif definition.family in ["doubling_transfer","temporal_transfer"]: draw_transfer(definition,run)
	elif definition.family in ["route_partition","route_block_choice","disjoint_route_pairs"]: RouteBoards.draw(self,definition,run)
	elif definition.family in ["parity_repair","heavy_coin_plan","wall_fence"]: SideBoards.draw(self,definition,run)
	elif definition.family in ["boss_seal_duel","boss_probe_reserve"]:
		var view_run: Dictionary = run.duplicate(true)
		if not battle_presentation.is_empty(): view_run.state = battle_presentation
		BattleBoards.draw(self,definition,view_run)
	else: PuzzleBoards.draw(self,definition,run)
	if run.level_id in Layout.DETAIL_LEVELS:
		button("scene_view","回到现场" if scene_detail else Layout.detail_title(run.level_id),Rect2(958,110,278,36),func(): scene_detail = not scene_detail; refresh())
	button("hint","问伙伴 · H",Rect2(40,659,130,38),hint,run.outcome == "active")
	button("undo","撤销 · Z",Rect2(183,659,118,38),dispatch.bind({"kind":"undo"}),run.outcome == "active" and not session.history.is_empty())
	button("reset","重新摆放",Rect2(314,659,125,38),confirm_reset,run.outcome == "active")
	button("tools","伙伴工具",Rect2(453,659,126,38),open_page.bind("tools"),run.outcome == "active")
	button("leave","离开机关 · Esc",Rect2(728,659,180,38),return_to_region)
	if run.outcome == "complete" and not busy and not (story_enabled and session.profile.story.node == "post_"+run.level_id): draw_completion(definition,run)

func draw_field_level(definition: Dictionary, run: Dictionary) -> void:
	var index = REGIONS[region].levels.find(run.level_id)
	var anchor = Layout.point(region,index)
	text("伙伴留在现场。点亮起的物件，可以继续查看里面的记录。",Rect2(42,158,870,38),20)
	var hotspot = button("inspect_mechanism","",Rect2(anchor-Vector2(58,82),Vector2(116,108)),func(): scene_detail = true; refresh())
	UIStyle.hotspot(hotspot,Layout.detail_title(run.level_id))
	var marker = Sprite2D.new(); marker.texture = world.SPARK; marker.position = anchor-Vector2(0,30); marker.scale = Vector2.ONE*18.0/world.SPARK.get_width(); ui.add_child(marker)
	text(Layout.detail_title(run.level_id),Rect2(anchor-Vector2(145,116),Vector2(310,32)),20)

func draw_completion(definition: Dictionary, run: Dictionary) -> void:
	# Unmissable banner: the mechanism is restored, what was earned, and where to go next.
	# A soft top scrim keeps the restored mechanism visible underneath.
	var scrim = ColorRect.new(); scrim.color = Color(0.02,0.05,0.03,0.55); scrim.size = Vector2(1280,172); scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE; overlay.add_child(scrim)
	UIStyle.panel(overlay,Rect2(58,16,1164,150),true)
	text("机关恢复了！",Rect2(90,28,420,48),30,true,overlay)
	text(definition.title+" · 完成",Rect2(92,76,420,30),20,true,overlay)
	var first_clear = _first_clear_was_this_run(definition)
	if first_clear:
		text("+%d 行旅经验　+%d 木片" % [int(definition.reward.journey_exp),int(definition.reward.camp_wood)],Rect2(92,108,420,30),20,true,overlay)
	else:
		text("再玩一次 · 首通奖励已经领过",Rect2(92,108,420,30),20,true,overlay)
	var story: String = Story.REACTIONS.get(definition.id,"")
	if first_clear and Story.ITEMS.has(definition.id): story = "获得收藏："+Story.ITEMS[definition.id].name+"　"+story
	if definition.family == "disjoint_route_pairs": story = "先向右的必过(1,0)、先向上的必过(0,1)，所以三封里必有两封相撞——一组最多两封。　"+story
	# A short "why" line for levels whose insight is a counting argument.
	if definition.family == "cargo_optimal": story = "为什么不能只用一趟：3 个对象、每篮最多 2 位，一趟最多送 2 个。　"+story
	elif definition.family == "route_partition": story = "6 + 3 + 1 = 10 条路线，一条不多一条不少。　"+story
	text(story,Rect2(540,40,660,74),19,true,overlay)
	var next_id: String = ""
	for level_id in session.catalog.levels:
		if session.catalog.region_for(level_id) == region and session.catalog.available(level_id,session.profile.progress.completed_levels) and level_id not in session.profile.progress.completed_levels:
			next_id = level_id; break
	if next_id != "":
		button("to_next","去下一处机关",Rect2(884,100,320,50),goto_next_level.bind(next_id),true,overlay)
	else:
		button("to_region","回到"+(REGIONS[region].name if region != "" else "林间"),Rect2(884,100,320,50),show_region.bind(region),true,overlay)
	button("to_region_alt","回到林间看看",Rect2(540,100,320,50),show_region.bind(region),true,overlay)

func _first_clear_was_this_run(definition: Dictionary) -> bool:
	# The learning record for this run exists exactly when its reward was granted now.
	if session.profile.active_run == null: return false
	for observation in session.profile.learning.observations:
		if observation.level_id == definition.id and observation.run_id == session.profile.active_run.run_id: return true
	return false

func goto_next_level(id: String) -> void:
	clear_children(overlay); refresh()
	request_level(id,false)

func goal(definition: Dictionary) -> String:
	match definition.family:
		"twenty_four": return "用1、4、5、9和加减乘除凑出24。每张卡只能用一次；允许分数，可以撤销或重摆。"
		"cargo": return "两个篮子和绳缆保持平衡。把阿橙、小岚和种子送上树梢；旅客到站会下篮，配重留在篮里。"
		"cargo_planning": return "规则：上行货有四件——阿橙、小岚、种子和折羽的邮包——配重只有三块。每篮最多2件、总重不超过5；到站的旅客和邮包不会再上篮。请用正好3趟送齐，想一想哪两件必须拼在同一趟。"
		"cargo_optimal": return "规则：每篮最多2件，没有载重和到站限制。请用正好2趟送齐——再想想为什么1趟不可能。"
		"doubling_transfer": return "24枚光晶分在甲、乙、丙三门。先点门移动光晶，摆好三门最初的数量。然后敲响门环，三次借光按固定顺序发生：甲借给乙、乙借给丙、丙借给甲。每次借光，借出的数量等于收光门现有的数量——收光门翻倍，借出门减去同样多。要让三次借光后每门都恰好剩8枚。"
		"temporal_transfer": return "林婆婆想找回借粮前的记录。三仓共有30袋；帮她摆回最初的粮袋，再按粮账搬一遍。"
		"pair_weights": return "三架灯两两合称：甲+乙=29，乙+丙=35，甲+丙=30。请分别定出甲、乙、丙的重量，全部点亮。"
		"machine_records": return "机器装进两个不同的运算模块（先后顺序由你决定）。装好后要让两页账簿都成立：输入2得8、输入5得17。"
		"diagnostic_probe": return "A、B、C三台育苗机只有一台是真的。你只能投喂一次：选一包种子，先为三台各写下预测，投送后对答案，再指出是哪一台。"
		"machine_ambiguity": return "两种装法都能正常育苗。先任选一台验性能，再用旧记录还原原机顺序，补齐保养档案。"
		"route_partition": return "信件只能向右、向上走，共3次向右、2次向上。折羽已经按第一次向右的高度归档了每条走法，但袋子里混着两处错：一张放错袋、一条没归档。先复核，再补全。"
		"route_block_choice": return "落石会挡住经过它的路线。先猜位置，再给四处各写下预计留下的条数，然后逐处对答案，把落石放在真正留下最多路线的位置。"
		"disjoint_route_pairs": return "两封信各自都能到终点，但不能在中途碰面。请挑出一组能同时出发的路线，并说清为什么再也放不下第三封。"
		"takeaway_policy": return "每次可以取1至3颗，谁取到最后一颗谁获胜。想办法赢下守门人。"
		"parity_repair": return "从0出发走正好5步，每步可以加2或减2，不能走出0至10。先想办法走到10；再只替换一步的长度，走到9。"
		"heavy_coin_plan": return "9颗晶体里有1颗更重，其他都一样。用天平最多称两次，保证无论哪颗更重都能找出来。"
		"wall_fence": return "借着一面现成的墙，只用12单位木料围出三边。长和宽都取正整数、木料要用完。把每种宽度都试一遍，围出真正面积最大的花圃，超过邻居的16格。"
		"boss_seal_duel": return "三座盘的能量都要变成7。1、2、3枚转移符各只能用一次；三回合里，石灵会依次封住A、B、C盘。看清它的回应再出手。"
		"boss_probe_reserve": return "侦察和合击共用15颗种子：先花种子试探出树心的真身（最多两次），再用剩下的种子合击，让回响正好是20。"
	return "观察场景中的规则，与伙伴一起完成机关。"

func draw_cargo(definition: Dictionary, run: Dictionary) -> void:
	world.visible = false; cargo_world.visible = true; cargo_world.page = "cargo"
	cargo_world.state = run.state; cargo_world.lift = 0.0 if run.state.left_low else 1.0
	cargo_world.selected = selected; cargo_world.show_direction = selected >= 0
	cargo_world.limits = {}
	var p: Dictionary = definition.params
	if p.has("max_items_per_basket"):
		cargo_world.limits = {"max_items":int(p.max_items_per_basket)}
		if p.has("max_basket_weight"): cargo_world.limits.max_weight = int(p.max_basket_weight)
	if definition.family != "cargo":
		text("载重差决定谁下降；到站旅客会下篮、配重留在篮里。已经升降 %d 趟（要用正好%d趟）。"%[run.state.trips,3 if p.get("lock_delivered",false) else 2],Rect2(41,120,930,30),19)
	var annotations = CargoAnnotations.new(); annotations.world = cargo_world; annotations.marks = run.tools.marks; ui.add_child(annotations)
	action_button = button("travel","松闸 · Space",Rect2(1080,611,164,41),rule.bind({"kind":"travel"}),run.outcome == "active" and not run.state.complete)

func draw_transfer(definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state
	var doubling = definition.family == "doubling_transfer"
	transfer_stage = TransferStage.new(); transfer_stage.name = "transfer_stage"; transfer_stage.values = state.initial
	transfer_stage.warehouse = definition.family == "temporal_transfer"; transfer_stage.selected = selected; transfer_stage.marks = run.tools.marks; transfer_stage.band_size = run.tools.band_size
	if trace_preview >= 0 and trace_preview < state.trace.size(): transfer_stage.values = state.trace[trace_preview]
	ui.add_child(transfer_stage)
	if doubling: transfer_stage.scale = Vector2.ONE*0.64; transfer_stage.position = Vector2(270,130)
	if not doubling:
		draw_grain_controls(definition,run); return
	# Instructions sit above the stage so the door arches never cover them; the
	# rule line rests on a sign because the ruins behind it are too bright for bare text.
	text("点一座门，再点另一座门，就会搬过去一枚。" if doubling else "点一个仓，再点另一个仓，就会搬过去一袋。",Rect2(73,176,610,38),20)
	UIStyle.sign(ui,Rect2(668,154,556,112 if doubling else 84))
	text("算术规则：借光顺序固定 甲→乙、乙→丙、丙→甲；每次借出的数量＝收光门现有的数量，收光门翻倍。例：收光门有8枚，就借出8枚，它变成16枚。" if doubling else "算术规则：先是甲给乙4袋、两家相等；接着乙给丙3袋、两家又相等。",Rect2(690,166,530,92 if doubling else 62),18)
	for i in range(3):
		var x = 140+i*365
		var pile = button("pile_"+str(i),"",Rect2(Vector2(x,240)*0.64+Vector2(270,130),Vector2(250,274)*0.64),select_pile.bind(i),run.outcome == "active")
		UIStyle.hotspot(pile,"搬运"+["甲","乙","丙"][i]+("的光晶" if doubling else "的粮袋"))
		text(["甲门","乙门","丙门"][i] if doubling else ["甲仓","乙仓","丙仓"][i],Rect2(Vector2(x+93,249)*0.64+Vector2(270,130),Vector2(110,32)),21)
		var unit = " 枚" if doubling else " 袋"
		text(str(transfer_stage.values[i])+unit,Rect2(Vector2(x+79,469)*0.64+Vector2(270,130),Vector2(110,34)),22)
	var moves: Array = definition.params.moves
	if not state.trace.is_empty():
		var lines = []
		for i in moves.size():
			var before: Array = state.trace[i]
			var source = int(moves[i][0]); var target = int(moves[i][1])
			var sides = ["甲","乙","丙"]
			if doubling:
				var amount = int(before[target])
				lines.append("第%d次：%s有%d → %s借出%d → %s得%d" % [i+1,sides[target],amount,sides[source],amount,sides[target],amount*2])
			else:
				var amount = int(moves[i][2])
				lines.append("第%d次：%s给%s %d袋 → %s留%d、%s得%d" % [i+1,sides[source],sides[target],amount,sides[source],int(before[source])-amount,sides[target],int(before[target])+amount])
		text("   ".join(lines),Rect2(370,494,860,52),16,false)
	if definition.family == "temporal_transfer":
		var check = "目标：第1次后甲乙一样多、第2次后乙丙一样多。"
		if state.trace.size() == 3:
			var first: Array = state.trace[1]; var second: Array = state.trace[2]
			check = "现在：第1次后甲%d 乙%d、第2次后乙%d 丙%d（%s）" % [first[0],first[1],second[1],second[2],"两条相等都成立" if first[0] == first[1] and second[1] == second[2] else "还没对上"]
		text(check,Rect2(74,534,1180,26),17,false)
	if not state.trace.is_empty():
		for moment in state.trace.size():
			var trace_button = button("trace_"+str(moment),"起始" if moment == 0 else "第%d次后"%moment,Rect2(370+moment*156,555,145,32),func(): trace_preview = moment; refresh())
			trace_button.add_theme_font_size_override("font_size",18); trace_button.size.y = 32
	action_button = button("try","敲响门环" if doubling else "翻动粮账",Rect2(1030,555,171,34),rule.bind({"kind":"try"}),run.outcome == "active")

func draw_grain_controls(definition: Dictionary, run: Dictionary) -> void:
	var state: Dictionary = run.state
	for i in range(3):
		var pile = button("pile_"+str(i),"",TransferStage.DOORS[i].grow(12),select_pile.bind(i),run.outcome == "active")
		UIStyle.hotspot(pile,"搬运"+["甲","乙","丙"][i]+"仓的粮袋")
	var moment = "摆放起始粮袋 · 点送出仓门，再点接收仓门"
	if trace_preview >= 0 and trace_preview < state.trace.size(): moment = "粮账回看 · "+("起始" if trace_preview == 0 else "第%d次借粮后" % trace_preview)
	if busy: moment = "小岚正在沿石路搬粮"
	text(moment,Rect2(42,180 if run.outcome == "complete" and not busy else 156,800,28),19)
	# The road ends at y=554. Controls use only the dark foreground beneath it.
	text("先甲→乙 4袋，两仓相等；再乙→丙 3袋，两仓相等。",Rect2(42,559,900,28),19)
	if not state.trace.is_empty():
		for index in state.trace.size():
			var b = button("trace_"+str(index),"起始" if index == 0 else "第%d次后" % index,Rect2(42+index*120,597,110,32),func(): trace_preview = index; refresh())
			b.add_theme_font_size_override("font_size",17)
		if not busy: bump_grain_feedback(state)
	action_button = button("try","按粮账搬运",Rect2(1040,558,192,36),rule.bind({"kind":"try"}),run.outcome == "active")

func bump_grain_feedback(state: Dictionary) -> void:
	# Temporal equality is revealed only after trying, using the saved trace.
	var first: Array = state.trace[1]; var second: Array = state.trace[2]
	text("第一次：甲%d / 乙%d　第二次：乙%d / 丙%d" % [first[0],first[1],second[1],second[2]],Rect2(42,631,1110,24),17)

func set_board_tab(value: String) -> void:
	board_tab = value; selected = -1; refresh()

func select_pile(index: int) -> void:
	trace_preview = -1
	if selected < 0:
		selected = index
		session.feedback = "已选"+["甲","乙","丙"][index]+"仓；再点接收粮袋的仓门。" if session.profile.active_run.level_id == "FL03" else "已选中；再点接收的一座台。"
		refresh(); return
	var source = selected; selected = -1
	if source == index: refresh(); return
	rule({"kind":"shift","from":source,"to":index})

func draw_journal() -> void:
	navigation("林间手记","记下走过的路、遇见的人和恢复的地方。")
	UIStyle.panel(ui,Rect2(55,159,1170,430),true)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(79,181); scroll.size = Vector2(1115,384); ui.add_child(scroll)
	var content = VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(content)
	if story_enabled:
		for id in session.profile.story.seen:
			var beat = Story.scene(id)
			var label = Label.new(); label.text = beat.title+" · "+beat.speaker+"："+beat.text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size = Vector2(1060,62); label.add_theme_color_override("font_color",UIStyle.DARK); content.add_child(label)
		for id in session.catalog.levels:
			if (id in Session.Flow.SIDES or id in session.profile.progress.completed_levels) and session.catalog.available(id,session.profile.progress.completed_levels):
				var caption = "回忆 / 再玩 · " if id in session.profile.progress.completed_levels else "邻居的邀请 · "
				var invite = Button.new(); invite.text = caption+session.catalog.levels[id].title; invite.custom_minimum_size.y = 42; invite.disabled = session.profile.story.return_node != ""; invite.pressed.connect(story_excursion.bind(id)); invite.name = "invite_"+id; buttons["invite_"+id] = invite; content.add_child(invite)
	var lines = []
	if not session.profile.get("legacy_fl07_runs",{}).is_empty() or session.profile.story.results.get("FL07",{}).has("final_order"):
		lines.append("第七关已更新为24点；旧版中间记录与奖励保留，旧版完成不记作24点解答。")
	for id in session.profile.progress.completed_levels:
		lines.append("✓ "+session.catalog.levels[id].title)
		lines.append(level_reaction(id))
	for dialogue in session.profile.world.dialogues: lines.append(Story.DIALOGUES[dialogue].text)
	for dialogue in session.profile.world.region_dialogues: lines.append("林间对话："+Story.region_dialogue(dialogue).text)
	for id in session.profile.progress.completed_levels:
		if Story.ITEMS.has(id): lines.append("收藏 · "+Story.ITEMS[id].name+"："+Story.ITEMS[id].story)
	if lines.is_empty(): lines.append("第一袋种子还在树梢站。和阿橙出发吧。")
	if session.profile.active_run != null:
		var run: Dictionary = session.profile.active_run
		lines.append("当前现场："+session.catalog.levels[run.level_id].title+"；回到入口可以接着上次的摆法继续。")
		for entry in run.hint_log: lines.append("伙伴的想法："+entry.text)
		for i in run.tools.snapshots.size(): lines.append("前后手记第%d张："%(i+1)+snapshot_text(run.tools.snapshots[i]))
		for path in run.tools.route_tags: lines.append("我的路签："+path+" → %d层"%run.tools.route_tags[path])
	for id in session.profile.suspended_runs:
		var saved: Dictionary = session.profile.suspended_runs[id]
		lines.append("暂存现场："+session.catalog.levels[id].title+"，可从地区入口继续。")
		for entry in saved.hint_log: lines.append("暂存提示："+entry.text)
		for path in saved.tools.route_tags: lines.append("暂存路签："+path+" → %d层"%saved.tools.route_tags[path])
	for line in lines:
		var label = Label.new(); label.text = line; label.add_theme_color_override("font_color",UIStyle.DARK); label.add_theme_font_size_override("font_size",20); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size = Vector2(1070,42); content.add_child(label)
	button("back","合上手记",Rect2(1044,659,200,39),back)

func draw_party() -> void:
	navigation("同行伙伴","两位伙伴出行，所有已加入伙伴共享行旅等级；主线工具始终可用。")
	UIStyle.panel(ui,Rect2(55,160,1170,427),true)
	var index = 0
	for id in session.profile.roster.owned:
		var partner: Dictionary = Session.Catalog.PARTNERS[id]; var x = 86+index*376
		text(partner.name+"  Lv.%d"%Session.Catalog.rank(session.profile.progress.journey_exp),Rect2(x,200,310,45),28,true)
		var portrait = Actor.new(); portrait.identity = id; portrait.position = Vector2(x+239,299); portrait.pixel_scale = 0.35; portrait.grown = session.profile.roster.grown; ui.add_child(portrait)
		text("共同经历：%d"%session.profile.roster.bonds[id].size(),Rect2(x,277,309,41),20,true)
		for skill_index in partner.skills.size():
			var skill: String = partner.skills[skill_index]
			var gate = {"compare":"FL06","bands":"FL11","shadow":"FL10"}.get(skill,"")
			var available = gate == "" or gate in session.profile.progress.completed_levels
			button("equip_"+skill,("✓ " if skill in session.profile.roster.loadouts[id] else "")+SKILL_NAMES[skill],Rect2(x,339+skill_index*58,284,42),dispatch.bind({"kind":"equip","partner":id,"skill":skill}),available)
		button("party_"+id,"留在营地" if id in session.profile.roster.party else "一起出发",Rect2(x,481,264,43),toggle_party.bind(id))
		index += 1
	button("back","回到营地",Rect2(1044,659,200,39),go_camp)

func draw_visit() -> void:
	navigation(session.catalog.levels[visit_id].title+" · 回访",Story.region_line(region,session.profile.progress.completed_levels))
	world.page = "region"
	UIStyle.panel(ui,Rect2(65,182,702,204),true)
	text(level_reaction(visit_id),Rect2(93,209,646,134),24,true)
	text("这里已经恢复；可以看看伙伴，也可以再玩一次。",Rect2(81,424,991,92),22)
	button("practice","再玩一次",Rect2(82,538,274,45),request_level.bind(visit_id,true))
	button("back","回到林间",Rect2(1000,659,243,40),show_region.bind(region))

func draw_tools() -> void:
	if session.profile.active_run == null: page = "camp"; draw_camp(); return
	navigation("伙伴工具","这些工具只记录或执行你自己的选择；想请伙伴指点时，按 H 请求提示。")
	UIStyle.panel(ui,Rect2(55,161,1170,428),true)
	var run: Dictionary = session.profile.active_run; var skills = []
	for partner in run.loadouts:
		for skill in run.loadouts[partner]: skills.append(skill)
	var y = 188
	for skill in skills:
		text(SKILL_NAMES[skill],Rect2(80,y,230,39),22,true)
		match skill:
			"mark":
				var count = 6 if run.state.has("places") else (9 if run.state.has("nodes") else 3)
				for index in range(count): button("mark_"+str(index),("✓ " if index in run.tools.marks else "")+str(index+1),Rect2(334+index*84,y,72,38),dispatch.bind({"kind":"tool","skill":"mark","index":index}))
			"compare":
				button("snapshot","记下当前摆法",Rect2(334,y,287,39),dispatch.bind({"kind":"tool","skill":"compare"}))
				text("已保留%d张前后记录"%run.tools.snapshots.size(),Rect2(669,y+1,462,39),20,true)
			"group":
				if run.state.has("places"):
					var cargo_names: Array = BaseCargo.item_names(run.state)
					var item_count: int = cargo_names.size()
					var spacing: int = 140 if item_count <= 6 else 132
					var item_width: int = 127 if item_count <= 6 else 118
					for index in item_count: button("group_item_"+str(index),("✓ " if index in tool_items else "")+str(cargo_names[index]),Rect2(334+index*spacing,y,item_width,38),toggle_tool_item.bind(index))
					for target in range(4): button("group_target_"+str(target),"整组到"+["林下","左篮","右篮","树梢"][target],Rect2(334+target*207,y+47,191,38),dispatch.bind({"kind":"tool","skill":"group","items":tool_items.duplicate(),"target":target}))
					y += 47
				elif run.state.has("initial"):
					PuzzleBoards.number(self,"group_count",tool_group_size,Rect2(334,y,218,39),1,30,func(value: int): tool_group_size = value; refresh())
					for source in range(3): button("group_source_"+str(source),("✓ " if tool_group_source == source else "")+"从"+["甲","乙","丙"][source],Rect2(583+source*196,y,178,38),func(): tool_group_source = source; refresh())
					for target in range(3): button("group_transfer_"+str(target),"整组到"+["甲","乙","丙"][target],Rect2(583+target*196,y+47,178,38),dispatch.bind({"kind":"tool","skill":"group","count":tool_group_size,"from":tool_group_source,"to":target}))
					y += 47
				else: text("货运和分仓时，可选择同源物件整组搬运。",Rect2(335,y,829,39),20,true)
			"bands":
				for amount in range(1,7): button("band_size_"+str(amount),("✓ " if run.tools.band_size == amount else "")+"每组%d"%amount,Rect2(334+(amount-1)*140,y,128,38),dispatch.bind({"kind":"tool","skill":"bands","size":amount}))
			"route_tag":
				var current_tag = run.tools.route_tags.get(run.state.get("draft",""),-1)
				for group in range(3): button("route_tag_"+str(group),("✓ " if current_tag == group else "")+"当前路线贴%d层签"%group,Rect2(334+group*286,y,267,38),dispatch.bind({"kind":"tool","skill":"route_tag","group":group}))
			"shadow": button("shadow","让影子沿这条路线走一遍",Rect2(334,y,434,39),play_route_shadow)
		y += 77
	button("back","回到机关",Rect2(1013,659,230,40),back)

func toggle_tool_item(index: int) -> void:
	if index in tool_items: tool_items.erase(index)
	else: tool_items.append(index)
	refresh()

func play_route_shadow() -> void:
	if not dispatch({"kind":"tool","skill":"shadow"}): return
	page = "challenge"; refresh()
	if not ui.has_node("route_canvas"): return
	var canvas = ui.get_node("route_canvas"); var full_path: String = session.profile.active_run.state.draft
	busy = true; canvas.enabled = false
	for b in buttons.values(): b.disabled = true
	for i in range(full_path.length()+1):
		canvas.path = full_path.left(i); canvas.queue_redraw()
		await get_tree().create_timer(effect_duration(0.18)).timeout
	busy = false; refresh()

func toggle_party(id: String) -> void:
	var members: Array = session.profile.roster.party.duplicate()
	if id in members: members.erase(id)
	else:
		if members.size() == 2: members.pop_back()
		members.append(id)
	dispatch({"kind":"party","members":members})

func draw_settings() -> void:
	navigation("设置","声音可关闭；重要提示同时显示在场景中。")
	UIStyle.panel(ui,Rect2(191,165,896,417),true)
	text("环境与音乐音量",Rect2(235,215,340,45),24,true)
	var slider = HSlider.new(); slider.name = "volume"; slider.position = Vector2(590,219); slider.size = Vector2(419,35); slider.min_value = 0; slider.max_value = 1; slider.step = 0.05; slider.value = session.profile.settings.volume; ui.add_child(slider)
	slider.value_changed.connect(func(value: float):
		if busy or modal or not session.pending.is_empty(): return
		session.command({"kind":"settings","values":{"volume":value}},int(session.profile.revision)); apply_audio()
		if not session.pending.is_empty(): refresh())
	button("mute","打开声音" if session.profile.settings.muted else "关闭声音",Rect2(590,291,419,44),dispatch.bind({"kind":"settings","values":{"muted":not session.profile.settings.muted}}))
	button("short_effects","重复演出：短" if session.profile.settings.short_effects else "重复演出：完整",Rect2(590,367,419,44),dispatch.bind({"kind":"settings","values":{"short_effects":not session.profile.settings.short_effects}}))
	text("鼠标点选或拖动；Tab切换控件，Enter确认。\n货运：数字键选物件，方向键放置，Space松闸。\nH请求提示，Z撤销，Esc取消或返回。",Rect2(235,440,780,116),20,true)
	button("back","返回",Rect2(1044,659,200,39),back)

func snapshot_text(state: Dictionary) -> String:
	if state.has("steps"):
		var cards = Session.Rules.TwentyFour.replay(session.catalog.levels.FL07.params,state)
		return "24点现场："+"；".join(cards.map(func(card): return card.expression+" = "+Session.Rules.TwentyFour.value_text(card)))
	if state.has("nodes"):
		var left = state.nodes.root.left.map(func(value): return str(int(value)+1))
		var right = state.nodes.root.right.map(func(value): return str(int(value)+1))
		var answers = 0
		for branch in ["left","right","equal"]:
			for value in state.nodes[branch].answers.values():
				if value >= 0: answers += 1
		return "首称左盘：%s；右盘：%s。\n分支答案已连%d/9。"%["、".join(left) if not left.is_empty() else "空","、".join(right) if not right.is_empty() else "空",answers]
	if state.has("places"):
		var lines = []
		var cargo_names: Array = BaseCargo.item_names(state)
		for i in cargo_names.size(): lines.append(str(cargo_names[i])+"在"+["林下","左篮","右篮","树梢"][int(state.places[i])])
		return "；".join(lines)
	if state.has("initial"): return "当时摆放 "+" / ".join(state.initial.map(func(value): return str(value)))
	if state.has("energy"): return "三盘能量 "+" / ".join(state.energy.map(func(value): return str(value)))
	if state.has("seed_balance"): return "储备%d颗；有效侦察%d次。"%[state.seed_balance,state.probe_count]
	if state.has("draft"):
		if not state.classifications.is_empty():
			var pages = []
			for page_id in state.classifications: pages.append("第%d处已分%d条"%[int(page_id)+1,state.classifications[page_id].size()])
			return "；".join(pages)
		return "画出的路线 "+state.draft+"；已保存%d条、%d组配对。"%[state.routes.size(),state.pairs.size()]
	if state.has("order"): return "装配："+PuzzleBoards.order_text(state.order)+"；预测输出%d；%s。"%[state.prediction,"启动过了" if state.tested else "还没启动"]
	if state.has("predictions"): return "所选种子包%d；玩家预测：%s；实际观察：%s"%[state.probe_input,str(state.predictions),str(state.observation)]
	if state.has("width"): return "花圃 宽%d、长%d"%[state.width,state.length]
	if state.has("weights"): return "灯架重量 "+" / ".join(state.weights.map(func(value): return str(value)))
	if state.has("remaining"): return "守门人对局剩%d颗"%state.remaining
	if state.has("path"): return "原路脚步 "+str(state.path)+"；修路脚步 "+str(state.repair)
	return "已在工具中保存这次操作记录。"

func apply_audio() -> void:
	if session.profile.is_empty(): sound.enabled = false; sound.set_volume(0); return
	sound.enabled = not session.profile.settings.muted; sound.set_volume(session.profile.settings.volume)

func back() -> void:
	page = page_stack.pop_back() if not page_stack.is_empty() else "camp"; refresh()

func dispatch(action: Dictionary, after: String = "") -> bool:
	if busy or modal: return false
	var ok = session.command(action,int(session.profile.revision))
	if not ok and not session.pending.is_empty(): queued_page = after
	elif ok and after != "": page = after
	refresh(); return ok

func rule(action: Dictionary) -> void:
	if busy or modal: return
	var old: Dictionary = session.profile.active_run.state.duplicate(true)
	selected = -1; cargo_world.selected = -1
	if not dispatch({"kind":"rule","action":action}): return
	var current: Dictionary = session.profile.active_run.state
	sound.play_cue("reward" if session.profile.active_run.outcome == "complete" else "place")
	var family: String = session.catalog.levels[session.profile.active_run.level_id].family
	if family == "twenty_four":
		busy = true; refresh()
		var count = Session.Rules.TwentyFour.replay(session.catalog.levels.FL07.params,current).size()
		var merged: Button = buttons.get("number_card_"+str(count-1))
		if merged != null:
			merged.pivot_offset = merged.size/2; merged.scale = Vector2(0.86,0.86)
			var pulse = create_tween()
			pulse.tween_property(merged,"scale",Vector2(1.05,1.05),effect_duration(0.18))
			pulse.tween_property(merged,"scale",Vector2.ONE,effect_duration(0.16))
			await pulse.finished
		busy = false; refresh()
	elif family in ["boss_seal_duel","boss_probe_reserve"]:
		await animate_battle(old,current,action,family)
	elif family == "temporal_transfer" and action.kind == "shift" and old.initial != current.initial:
		busy = true; refresh()
		transfer_stage.values = old.initial
		await animate_grain_move(int(action.from),int(action.to),1)
		busy = false; refresh()
	elif family in ["doubling_transfer","temporal_transfer"] and action.kind == "try" and not current.trace.is_empty() and board_tab == "initial":
		await animate_transfer(current)
	elif family == "disjoint_route_pairs" and action.kind == "store_pair" and current.pairs.size() > old.pairs.size():
		await animate_walk_pair(current.pairs.back())
	elif family == "disjoint_route_pairs" and action.kind == "try" and current.get("bound_set",[]).size() == 2 and session.profile.active_run.outcome == "complete":
		await animate_walk_pair({"a":current.bound_set[0],"b":current.bound_set[1]})
	elif action.kind == "travel":
		busy = true; refresh()
		# Commit first, then animate the old load on the moving baskets. Delivered
		# people must not appear upstairs until their basket has actually arrived.
		cargo_world.state = old.duplicate(true); cargo_world.moving = true
		cargo_world.lift = 0.0 if old.left_low else 1.0
		var tween = create_tween(); tween.tween_property(cargo_world,"lift",0.0 if current.left_low else 1.0,effect_duration(0.9)).set_trans(Tween.TRANS_SINE)
		await tween.finished
		var landed = {}
		for i in cargo_world.item_count(): landed[i] = cargo_world.item_position(i)
		cargo_world.state = current; cargo_world.moving = false
		for i in cargo_world.item_count(): cargo_world.offsets[i] = landed[i]-cargo_world.item_position(i)
		var unload = create_tween()
		unload.tween_method(func(progress: float):
			for i in cargo_world.item_count(): cargo_world.offsets[i] = (landed[i]-cargo_world.item_position(i))*(1.0-progress),0.0,1.0,effect_duration(0.35))
		await unload.finished; cargo_world.offsets.clear(); busy = false; refresh()
	else:
		world.reaction = 0.6
		for actor in world.actors.values(): actor.play("success" if session.profile.active_run.outcome == "complete" else "interact",0.8)
	if story_enabled and session.profile.story.node == "post_"+session.profile.active_run.level_id:
		page = "story"; refresh()

func animate_walk_pair(pair: Dictionary) -> void:
	# Both letters walk their routes at once; they must never meet in the middle.
	busy = true; refresh()
	if not ui.has_node("route_canvas"): busy = false; refresh(); return
	var canvas = ui.get_node("route_canvas")
	canvas.walk_pair = [pair.a,pair.b]
	var steps = maxf(1.0,maxf(float(pair.a.length()),float(pair.b.length())))
	var duration = effect_duration(1.1)
	var elapsed = 0.0
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		canvas.walk_t = clampf(elapsed/duration,0.0,1.2)
		canvas.queue_redraw()
	canvas.walk_t = -1.0
	busy = false; refresh()

func animate_transfer(current: Dictionary) -> void:
	busy = true; trace_preview = 0; refresh()
	var params: Dictionary = session.profile.active_run.params_snapshot
	for i in params.moves.size():
		transfer_stage.values = current.trace[i]; transfer_stage.from_index = int(params.moves[i][0]); transfer_stage.to_index = int(params.moves[i][1])
		transfer_stage.quantity = int(current.trace[i][transfer_stage.to_index]) if params.moves[i].size() == 2 else int(params.moves[i][2])
		if transfer_stage.warehouse:
			await animate_grain_move(transfer_stage.from_index,transfer_stage.to_index,transfer_stage.quantity)
		else:
			transfer_stage.flight = 0.0; sound.play_cue("charge")
			var tween = create_tween(); tween.tween_property(transfer_stage,"flight",1.0,effect_duration(0.55)).set_trans(Tween.TRANS_SINE)
			await tween.finished
		transfer_stage.flight = -1.0; trace_preview = i+1
		refresh()
	busy = false; refresh()

func animate_grain_move(source: int, target: int, count: int) -> void:
	transfer_stage.from_index = source; transfer_stage.to_index = target; transfer_stage.quantity = count
	var offset = Vector2(-39,5)
	var start: Vector2 = transfer_stage.road_point(0)+offset
	world.grain_moving = true
	var approach = create_tween()
	approach.tween_property(world,"grain_hero",start,effect_duration(maxf(0.2,world.grain_hero.distance_to(start)/350.0)))
	await approach.finished
	transfer_stage.flight = 0.0; world.grain_pushing = true; sound.play_cue("place")
	var travel = create_tween()
	travel.tween_method(func(progress: float):
		transfer_stage.flight = progress
		world.grain_hero = transfer_stage.road_point(progress)+offset,
		0.0,1.0,effect_duration(absf(TransferStage.ROAD_X[target]-TransferStage.ROAD_X[source])/280.0))
	await travel.finished
	transfer_stage.flight = -1.0; world.grain_moving = false; world.grain_pushing = false

func select_core(index: int) -> void:
	if selected_card < 0: session.feedback = "先选一张剩余转移符，再选送出盘和接收盘。"; refresh(); return
	if selected_core < 0: selected_core = index; session.feedback = "已选送出盘；再点接收的一盘。"; refresh(); return
	var source = selected_core; var card = selected_card; selected_core = -1; selected_card = -1
	if source == index: refresh(); return
	rule({"kind":"transfer","card":card,"from":source,"to":index})

func animate_battle(old: Dictionary, current: Dictionary, action: Dictionary, family: String) -> void:
	busy = true; battle_presentation = old.duplicate(true); refresh()
	for actor in battle_world.actors.values(): actor.play("skill",effect_duration(1.4))
	if action.kind in ["transfer","probe","finish"]:
		battle_world.source = int(action.get("from",0)); battle_world.target = int(action.get("to",1)); battle_world.card = int(action.get("card",action.get("value",3)))
		battle_world.flight = 0.0; sound.play_cue("charge")
		var flight = create_tween(); flight.tween_property(battle_world,"flight",1.0,effect_duration(0.65)).set_trans(Tween.TRANS_SINE)
		await flight.finished; battle_world.flight = -1.0; sound.play_cue("impact")
	if family == "boss_seal_duel" and action.kind == "transfer":
		var row: Dictionary = current.transcript.back()
		battle_presentation = current.duplicate(true); battle_presentation.energy = row.after_player; battle_world.state = battle_presentation
		if row.enemy == "leaf_swap":
			battle_world.swap = 0.0; sound.play_cue("awaken")
			var swap = create_tween(); swap.tween_property(battle_world,"swap",1.0,effect_duration(0.7)).set_trans(Tween.TRANS_SINE)
			await swap.finished; battle_world.swap = -1.0
		elif row.enemy == "stomp":
			battle_world.swap = 0.0
			var stomp = create_tween(); stomp.tween_property(battle_world,"swap",0.001,effect_duration(0.3))
			await stomp.finished; battle_world.swap = -1.0
	elif family == "boss_probe_reserve" and action.kind == "probe":
		battle_world.previous_candidates = Session.Rules.ProbeBattle.candidates(battle_world.params,old)
		battle_world.state = current; battle_world.disappearing = 1.0
		var dissolve = create_tween(); dissolve.tween_property(battle_world,"disappearing",0.0,effect_duration(0.55))
		await dissolve.finished
	if current.get("won",false):
		for actor in battle_world.actors.values(): actor.play("success",effect_duration(1.4))
		battle_world.state = current; battle_world.burst = 0.01; sound.play_cue("unlock")
		var burst = create_tween(); burst.tween_property(battle_world,"burst",1.0,effect_duration(0.9))
		await burst.finished; battle_world.burst = 0.0
	busy = false; battle_presentation = {}; refresh()

func effect_duration(duration: float) -> float:
	return maxf(0.02,duration*time_scale*(0.25 if session.profile.settings.short_effects else 1.0))

func hint() -> void:
	dispatch({"kind":"hint"})

func confirm_reset() -> void:
	show_confirmation("重新摆放本次机关？\n提示与尝试记录会保留。",func(): dispatch({"kind":"reset","confirmed":true}))

func confirm_build(id: String) -> void:
	show_confirmation("用%d木片建造%s？"%[Session.Catalog.BUILDINGS[id].cost,Session.Catalog.BUILDINGS[id].name],func(): dispatch({"kind":"build","building":id}))

func show_confirmation(value: String, action: Callable) -> void:
	modal = true; confirmation_open = true; confirmation = action
	for b in buttons.values(): b.disabled = true
	var shade = ColorRect.new(); shade.color = Color(0.025,0.055,0.035,0.75); shade.size = Vector2(1280,720); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(340,242,600,250),true)
	text(value,Rect2(375,277,530,103),24,true,overlay)
	var cancel = UIStyle.button(overlay,"保留现场",Rect2(380,414,232,43),dismiss_modal); cancel.name = "cancel"
	var accept = UIStyle.button(overlay,"确认",Rect2(666,414,232,43),func():
		var callback = confirmation; dismiss_modal(); callback.call()); accept.name = "confirm"
	cancel.grab_focus()

func dismiss_modal() -> void:
	modal = false; clear_children(overlay); refresh()

func show_save_error() -> void:
	modal = true; confirmation_open = false
	for b in buttons.values(): b.disabled = true
	var shade = ColorRect.new(); shade.color = Color(0.025,0.055,0.035,0.86); shade.size = Vector2(1280,720); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(240,224,800,289),true)
	text(session.feedback,Rect2(280,259,720,107),24,true,overlay)
	var retry = UIStyle.button(overlay,"重新读取" if session.repository.protected else "重试保存",Rect2(283,416,335,44) if session.repository.protected else Rect2(423,416,434,44),func():
		var ok = session.open(save_path) if session.repository.protected else session.retry()
		if ok and queued_page != "": page = queued_page; queued_page = ""
		if ok and story_enabled and (page in ["story","challenge"] or session.profile.story.node == "pre_FL01"):
			modal = false; resume_story(); return
		if ok and page == "camp": world.hero_position = Vector2(470,565); world.destination = world.hero_position
		refresh())
	retry.name = "retry"; retry.grab_focus()
	if session.repository.protected:
		var create = UIStyle.button(overlay,"保留旧记录，开始新旅程",Rect2(651,416,347,44),func():
			clear_children(overlay)
			show_confirmation("原记录将原样保留为带protected标记的文件。\n确认从空白的新手记开始？",func(): session.new_after_protected(true); page = "story" if story_enabled else "camp"; refresh()))
		create.name = "new_profile"

func _notification(what: int) -> void:
	if is_instance_valid(story_stage):
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT: story_stage.focused = false
		elif what == NOTIFICATION_APPLICATION_FOCUS_IN: story_stage.focused = true
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if walking: walk_cancelled = true
		selected = -1; down_item = -1
		if is_instance_valid(cargo_world): cargo_world.dragging = false; cargo_world.selected = -1

func _input(event: InputEvent) -> void:
	if busy:
		if walking and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			walk_cancelled = true; get_viewport().set_input_as_handled()
		return
	if modal:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and confirmation_open: dismiss_modal(); get_viewport().set_input_as_handled()
		return
	if session.profile.is_empty(): return
	if page in ["camp","region"] and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if page == "region": interact_target(); get_viewport().set_input_as_handled()
		return
	if page != "challenge" or session.profile.active_run == null: return
	var run: Dictionary = session.profile.active_run
	var family: String = session.catalog.levels[run.level_id].family
	if family not in ["cargo","cargo_planning","cargo_optimal"] or run.outcome != "active" or run.state.complete: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed and point.y > 150 and point.y < 606:
			down_item = cargo_world.hit_item(point) if selected < 0 else -1; down_position = point
			if down_item >= 0 and selected < 0: selected = down_item; cargo_world.selected = selected; sound.play_cue("pickup"); get_viewport().gui_release_focus(); get_viewport().set_input_as_handled()
		elif not event.pressed and point.y > 150 and point.y < 606:
			var target = cargo_world.hit_zone(point)
			var was_dragging = cargo_world.dragging; cargo_world.dragging = false
			if selected >= 0 and target >= 0 and (down_item < 0 or was_dragging): place_cargo(target); get_viewport().set_input_as_handled()
			down_item = -1
		elif not event.pressed and cargo_world.dragging:
			selected = -1; down_item = -1; cargo_world.dragging = false; cargo_world.selected = -1; get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var point = get_global_transform_with_canvas().affine_inverse() * event.position; cargo_world.hovered = cargo_world.hit_item(point); cargo_world.target = cargo_world.hit_zone(point)
		if down_item >= 0 and point.distance_to(down_position) > 8: cargo_world.dragging = true; cargo_world.pointer = point

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or busy or modal: return
	if event.keycode == KEY_ESCAPE:
		if selected >= 0: selected = -1; cargo_world.selected = -1; refresh()
		elif page in ["settings","party","journal","tools"]: back()
		else: go_camp()
	elif event.keycode == KEY_E and page in ["camp","region"]:
		if page == "region": interact_target()
	elif page == "challenge" and session.profile.active_run != null and session.profile.active_run.outcome == "active":
		match event.keycode:
			KEY_H: hint()
			KEY_Z: dispatch({"kind":"undo"})
			KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7:
				if cargo_world.visible: selected = event.keycode-KEY_1; cargo_world.selected = selected; get_viewport().gui_release_focus()
			KEY_LEFT: place_cargo(1)
			KEY_RIGHT: place_cargo(2)
			KEY_UP: place_cargo(3)
			KEY_DOWN: place_cargo(0)
			KEY_SPACE:
				if cargo_world.visible: rule({"kind":"travel"})
			_: return
	else: return
	get_viewport().set_input_as_handled()

func place_cargo(target: int) -> void:
	if selected < 0 or not cargo_world.visible: return
	var item = selected; selected = -1; cargo_world.selected = -1
	rule({"kind":"move","item":item,"target":target})

func resume_story() -> void:
	if busy or modal or session.profile.is_empty(): return
	page_stack.clear(); selected = -1
	var node: String = session.profile.story.node
	var beat = Story.scene(node)
	if beat.kind == "puzzle":
		region = Session.Catalog.region_for(beat.level)
		board_tab = "initial"
		dispatch({"kind":"start","level_id":beat.level,"narrative":true,"node":node},"challenge")
		if session.profile.story.node.begins_with("post_"): page = "story"; refresh()
	else: page = "story"; refresh()

func story_excursion(id: String) -> void:
	if busy or modal: return
	if dispatch({"kind":"story_excursion","level_id":id},"story"): page_stack.clear()

func story_continue(expected: String) -> void:
	if expected != session.profile.story.node or not story_stage.done or story_stage.paused: return
	var beat = Story.scene(expected)
	if beat.next.begins_with("puzzle_"):
		region = beat.region; board_tab = "initial"; trace_preview = -1
		dispatch({"kind":"start","level_id":beat.next.trim_prefix("puzzle_"),"narrative":true,"node":expected},"challenge")
	elif beat.effect == "voyage": open_market()
	elif expected == "end": go_camp()
	elif dispatch({"kind":"story_advance","node":expected},"story"):
		if Story.scene(session.profile.story.node).kind == "puzzle": resume_story()

func draw_story() -> void:
	var node: String = session.profile.story.node
	var beat = Story.scene(node)
	if node == "post_FL07" and session.profile.story.excursion == "" and session.profile.story.results.get("FL07",{}).has("final_order"):
		beat = beat.duplicate(true); beat.title = "磨坊的旧记录"; beat.text = "旧版关卡的修复已经完成，奖励和进度保留。新的24点挑战可以从手记中再玩。"
	if beat.kind == "puzzle": page = "challenge"; draw_challenge(); return
	world.visible = false; story_stage.visible = true
	if story_stage.node_id != node:
		sound.play_cue({"delivery":"place","letter":"pickup","gates_lit":"unlock","join":"reward","bridge":"unlock","finale":"reward"}.get(beat.effect,"footstep"))
	story_stage.setup(node,session.profile,time_scale)
	region = beat.region if beat.region != "camp" else "treetop"
	navigation(beat.title,"林间来信 · "+("旧事与新的约定" if session.profile.story.seen.is_empty() and not session.profile.progress.completed_levels.is_empty() else "故事进行中"))
	var grain_scene = beat.region in ["village","mill","heart"] and not story_stage.cargo_scene and beat.effect != "bridge"
	var upper_dialogue = beat.region in ["treetop","camp"] and not story_stage.cargo_scene
	UIStyle.panel(ui,Rect2(60,155,1160,132) if upper_dialogue else (Rect2(60,557,1160,96) if grain_scene else Rect2(60,493,1160,158)),true)
	text(beat.speaker,Rect2(106,168,1070,26) if upper_dialogue else (Rect2(106,562,1070,26) if grain_scene else Rect2(106,507,1070,29)),19 if grain_scene else 21,true)
	text(beat.text,Rect2(106,203,1070,72) if upper_dialogue else (Rect2(106,590,1070,60) if grain_scene else Rect2(106,545,1070,100)),20 if grain_scene or upper_dialogue else 23,true)
	button("story_skip","跳过本段动作",Rect2(1020,110,200,36),func(): story_stage.skip(); refresh(),not story_stage.done)
	button("story_pause","继续播放" if story_stage.paused else "暂停",Rect2(885,110,125,36),func(): story_stage.paused = not story_stage.paused; refresh())
	var ready: bool = story_stage.done and not story_stage.paused
	if node == "post_branch":
		for i in range(2):
			var id: String = ["FL09","FL10"][i]
			if id not in session.profile.progress.completed_levels: button("choose_"+id,"先去落石路口" if i == 0 else "先安排两封信",Rect2(590+i*320,665,300,39),dispatch.bind({"kind":"story_choose","level_id":id},"story"),ready,null,true)
	else: button("story_continue",beat.action,Rect2(780,665,440,39),story_continue.bind(node),ready,null,true)
	if session.profile.story.return_node != "": button("story_return","稍后再来 · 返回故事",Rect2(60,665,330,39),func():
		if dispatch({"kind":"story_return"},"story"): resume_story())
	elif node in ["joined","rest_village","rest_post","rest_growth","end","voyage"]: button("story_rest","在营地歇脚",Rect2(60,665,230,39),go_camp)
	if node == "rest_growth" and Session.Roster.can_grow(session.profile): button("story_grow","系上同心叶结",Rect2(320,665,260,39),dispatch.bind({"kind":"grow"}),ready)
	if node.begins_with("post_") and beat.level != "":
		var reward: Dictionary = session.catalog.levels[beat.level].reward
		text(("收藏 · "+Story.ITEMS[beat.level].name) if Story.ITEMS.has(beat.level) else "林间手记 · "+session.catalog.levels[beat.level].title,Rect2(60,615,1120,35) if upper_dialogue else Rect2(60,153,1120,35),19)

func level_reaction(id: String) -> String:
	if id == "FL07":
		var has_new = false
		for observation in session.profile.learning.observations:
			if observation.level_id == "FL07" and observation.context_id == "twenty_four": has_new = true
		if not has_new: return "旧版磨坊关卡已完成；原有奖励保留，可以再玩新的24点挑战。"
	return Story.REACTIONS.get(id,"")

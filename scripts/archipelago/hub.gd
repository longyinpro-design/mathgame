extends Control
const Catalog = preload("res://scripts/archipelago/catalog.gd")
const Journey = preload("res://scripts/archipelago/bridge.gd")
const Campaign = preload("res://scripts/archipelago/session.gd")
const World = preload("res://scripts/archipelago/hub_world.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
var session: RefCounted
var selected_island = ""
var ui: Control
var overlay: Control
var world: Node2D
var buttons: Dictionary = {}
var modal = false
var navigating = false
var render_epoch = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = World.new(); add_child(world)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	overlay = Control.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	if session == null: session = Journey.ensure_session()
	Journey.session = session; Journey.enabled = true
	selected_island = Journey.selected_island
	get_window().title = "数字群岛 · 六岛航路"
	if session.profile.is_empty(): show_protected(); return
	if not session.sync_legacy() or not session.pending.is_empty(): show_save_error(); return
	refresh()

func label(text: String, rect: Rect2, size_px: int = 20, parent: Node = null) -> Label:
	var result = UIStyle.text(ui if parent == null else parent,text,rect,size_px)
	result.add_theme_font_size_override("font_size",size_px); result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result
func button(id: String, text: String, rect: Rect2, callback: Callable, enabled: bool = true, parent: Node = null) -> Button:
	var epoch = render_epoch
	var guarded = func():
		if epoch == render_epoch and not navigating and (not modal or parent == overlay): callback.call()
	var result = UIStyle.button(ui if parent == null else parent,text,rect,guarded)
	result.name = id; result.disabled = not enabled; buttons[id] = result; return result

func refresh() -> void:
	render_epoch += 1
	for child in ui.get_children(): ui.remove_child(child); child.queue_free()
	buttons = {}; world.presentation_paused = modal
	world.state = {"completed":session.profile.get("completed",[])}
	var done = session.profile.get("completed",[])
	UIStyle.sign(ui,Rect2(24,18,1232,62))
	label("数字群岛 · "+("六岛航路" if selected_island.is_empty() else Catalog.NAMES[selected_island]),Rect2(44,26,700,44),28)
	label("已恢复 %d / 108 · 行旅经验 %d"%[done.size(),session.profile.get("experience",0)],Rect2(814,33,420,38),19)
	if selected_island.is_empty(): build_islands(done)
	else: build_levels(done)
	button("journal","营地与手记",Rect2(24,652,190,48),show_journal)
	button("settings","设置",Rect2(228,652,110,48),show_settings)
	var next = session.story_next()
	if not selected_island.is_empty(): button("all_islands","六岛航路",Rect2(352,652,166,48),func(): selected_island=""; refresh())
	if not next.is_empty():
		label("下一段 · "+Catalog.definition(next).title,Rect2(542,657,422,35),18)
		button("continue_story","继续故事 · "+next,Rect2(980,650,276,52),launch.bind(next))
	else: label("六岛主线航路全部连通。仍可探访支线和回忆。",Rect2(556,656,680,39),21)
	if modal:
		for b in buttons.values(): b.disabled = true

func build_islands(done: Array) -> void:
	label("从一袋种子出发，让失去联系的生活重新连起来。支线随时回访，不阻挡下一座岛。",Rect2(42,101,1188,70),22)
	for i in range(6):
		var island = Catalog.ISLANDS[i]; var rect = Rect2(42+(i%3)*412,188+floor(i/3.0)*220,372,180)
		var count = 0
		for id in Catalog.ids(island):
			if id in done: count += 1
		var open = Catalog.island_open(island,done)
		var text = "%d  %s\n\n已恢复 %d / 18\n%s"%[i+1,Catalog.NAMES[island],count,"进入航路" if open else "先完成"+Catalog.NAMES[Catalog.ISLANDS[i-1]]+"主线"]
		button("island_"+island,text,rect,func(): selected_island=island; refresh(),open)

func build_levels(done: Array) -> void:
	label("每张卡是一件已经发生的请托。可选支线不会挡住主线；完成后仍可重玩。",Rect2(42,94,1188,58),21)
	var ids = Catalog.ids(selected_island)
	for i in range(ids.size()):
		var id = ids[i]; var d = Catalog.definition(id); var rect = Rect2(38+(i%6)*204,168+floor(i/6.0)*156,184,140)
		var known = not d.is_empty(); var open = known and Catalog.available(id,done)
		var status = "已恢复 · 可重玩" if id in done else "待出发" if open else "需先完成前置"
		var text = "%s · %s\n%s\n%s"%[id,"支线" if Catalog.is_side(id) else "主线",d.get("title","制作中"),status]
		var b = button("level_"+id,text,rect,launch.bind(id),open)
		b.add_theme_font_size_override("font_size",18)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.tooltip_text = d.get("goal","")

func launch(id: String) -> void:
	if modal or navigating: return
	navigating = true
	if not Journey.launch(get_tree(),id):
		navigating = false
		if not session.pending.is_empty(): show_save_error()
		else: show_modal(session.feedback); button("close","返回",Rect2(960,628,190,46),close_modal,true,overlay)

func show_modal(text: String) -> void:
	modal = true; refresh(); clear_overlay()
	var shade = ColorRect.new(); shade.size = Vector2(1280,720); shade.color = Color(0.02,0.04,0.06,0.9); overlay.add_child(shade)
	UIStyle.panel(overlay,Rect2(120,100,1040,576))
	label(text,Rect2(152,120,976,464),22,overlay)
func clear_overlay() -> void:
	for child in overlay.get_children(): overlay.remove_child(child); child.queue_free()
func close_modal() -> void:
	modal=false; clear_overlay(); refresh()
func show_journal() -> void:
	show_modal("")
	var scroll = ScrollContainer.new(); scroll.position=Vector2(154,126); scroll.size=Vector2(972,462); overlay.add_child(scroll)
	var list = VBoxContainer.new(); list.custom_minimum_size.x=940; list.add_theme_constant_override("separation",10); scroll.add_child(list)
	var partners: Array = []
	for id in session.profile.roster: partners.append(Catalog.PARTNERS[id])
	var heading = Label.new(); heading.text="同行伙伴："+"、".join(partners); heading.add_theme_font_override("font",UIStyle.face()); heading.add_theme_font_size_override("font_size",24); list.add_child(heading)
	for recommendation in session.recommendations().slice(0,4):
		var practice=Button.new();practice.text="可选再试 · "+Catalog.definition(recommendation.level_id).title;practice.custom_minimum_size.y=44;practice.add_theme_font_override("font",UIStyle.face());list.add_child(practice)
		practice.pressed.connect(func(): close_modal(); launch(recommendation.level_id))
	for observation in session.profile.observations:
		var text = "%s · %s\n%s"%[observation.level_id,Catalog.definition(observation.level_id).title,"经原关卡规则复核的历史完成；不推断求助程度或掌握水平" if observation.kind=="imported_valid_completion" else "本次使用提示" if observation.highest_hint>0 else "本次未使用提示；不等同掌握或迁移"]
		var row=Label.new(); row.text=text; row.add_theme_font_override("font",UIStyle.face()); row.add_theme_font_size_override("font_size",19); row.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; row.custom_minimum_size=Vector2(930,65); list.add_child(row)
	button("party","安排同行伙伴",Rect2(180,612,240,46),show_party,true,overlay)
	button("camp","看看营地纪念",Rect2(442,612,240,46),show_camp,true,overlay)
	button("close_journal","回到航图",Rect2(936,612,190,46),close_modal,true,overlay)
func show_settings() -> void:
	show_modal("声音设置\n主线规则和目标不依赖声音。任何时候都可以停止，没有思考倒计时。")
	button("mute","开启声音" if session.profile.settings.muted else "静音",Rect2(220,300,320,52),toggle_mute,true,overlay)
	button("short","重复演出：短" if session.profile.settings.short_effects else "重复演出：完整",Rect2(570,300,380,52),toggle_short,true,overlay)
	button("close_settings","回到航图",Rect2(936,612,190,46),close_modal,true,overlay)
func toggle_mute() -> void:
	if not session.set_settings({"muted":not session.profile.settings.muted}): show_save_error(); return
	AudioServer.set_bus_mute(0,session.profile.settings.muted); show_settings()
func toggle_short() -> void:
	if not session.set_settings({"short_effects":not session.profile.settings.short_effects}): show_save_error(); return
	show_settings()
func show_save_error() -> void:
	show_modal(session.feedback+"\n上一次成功保存的旅程保留，请重试同一个候选。")
	button("retry","重试保存",Rect2(936,612,190,46),retry_save,true,overlay)
func retry_save() -> void:
	if session.retry(): close_modal()
	else: show_save_error()
func show_protected() -> void:
	show_modal("群岛记录无法读取，原字节已保护。可关闭窗口保留它，或明确选择备份后另开旅程。各岛旧档不会被覆盖。")
	button("protect_confirm","备份旧档，另开旅程",Rect2(716,612,410,46),recover_protected,true,overlay)
func recover_protected() -> void:
	if session.repository.preserve_protected_file().is_empty(): show_protected(); return
	session.profile=Campaign.fresh()
	if session.commit(session.profile) and session.sync_legacy(): close_modal()
	else: show_save_error()


func show_party() -> void:
	show_modal("最多两位伙伴同行。配置只影响下次新挑战，已经开始的机关仍保留原队伍；主线基本工具始终可用。")
	var index=0
	for id in Catalog.PARTNERS:
		var owned=id in session.profile.roster
		var caption=Catalog.PARTNERS[id]+(" · 同行" if id in session.profile.party else " · 在营地" if owned else " · 尚未相遇")
		button("partner_"+id,caption,Rect2(180+(index%3)*310,280+floor(index/3.0)*84,288,64),toggle_partner.bind(id),owned,overlay)
		index+=1
	button("close_party","回到手记",Rect2(936,612,190,46),show_journal,true,overlay)

func toggle_partner(id: String) -> void:
	var party=session.profile.party.duplicate()
	if id in party:
		if party.size()==1: return
		party.erase(id)
	elif party.size()<2: party.append(id)
	else: return
	if session.set_party(party): show_party()
	else: show_save_error()

func show_camp() -> void:
	show_modal("营地纪念 · 由实际完成的故事解锁，不消耗或复制森林营地的木片与建设。")
	var names=["森林来信架","集市交易角","工坊小机器","山谷拼石台","水庭花园","群岛航路灯塔"]
	for index in range(6):
		var restored=Catalog.all_main_done(Catalog.ISLANDS[index],session.profile.completed)
		var rect=Rect2(166+(index%3)*318,240+floor(index/3.0)*166,298,144)
		UIStyle.sign(overlay,rect)
		label(names[index]+"\n\n"+("已经带回营地" if restored else "等待"+Catalog.NAMES[Catalog.ISLANDS[index]]+"的主线回信"),Rect2(rect.position+Vector2(16,15),rect.size-Vector2(32,20)),21,overlay)
	label("已经收好 %d 件关卡纪念。可在各岛回忆中重玩，首次奖励不会重复。"%session.profile.keepsakes.size(),Rect2(166,584,850,36),18,overlay)
	button("close_camp","回到手记",Rect2(936,626,190,42),show_journal,true,overlay)

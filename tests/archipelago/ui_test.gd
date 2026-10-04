extends SceneTree
const Hub=preload("res://game/archipelago.tscn")
const Campaign=preload("res://scripts/archipelago/session.gd")
const Journey=preload("res://scripts/archipelago/bridge.gd")
const Catalog=preload("res://scripts/archipelago/catalog.gd")
const Focus=preload("res://tests/forest/window_focus.gd")
var checks=0
var failures=0
var scene:Control
var session:RefCounted
var base=""
var headless=DisplayServer.get_name()=="headless"
func _initialize()->void:
	root.content_scale_size=Vector2i(1280,720);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if not headless:Focus.configure(root)
	call_deferred("run")
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(note)
func wait_frames()->void:
	await process_frame;await process_frame;await process_frame
func tap(control:Control)->void:
	if not headless:check(await Focus.ready(root),"native window ready")
	for child in root.get_children():child.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var at=root.get_screen_transform()*control.get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event)
	await wait_frames()
func capture(name:String)->void:
	if headless:return
	await wait_frames();RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png("res://docs/playtest/archipelago/"+name+".png")==OK,"capture "+name)
func mount()->void:
	Journey.session=session;Journey.selected_island="";Journey.enabled=true
	scene=Hub.instantiate();scene.session=session;root.add_child(scene);current_scene=scene;await wait_frames()
func unmount()->void:
	if is_instance_valid(current_scene):current_scene.queue_free()
	await wait_frames()
func copy_file(source:String,destination:String)->void:
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file=FileAccess.open(destination,FileAccess.WRITE);file.store_string(FileAccess.get_file_as_string(source));file.close()
func isolated_paths()->Dictionary:
	var result={"forest":base+"/legacy/forest.json"}
	copy_file("res://docs/playtest/archipelago/proofs/forest.json",result.forest)
	for island in ["market","workshop"]:
		for id in Catalog.ids(island):
			result[id]=base+"/legacy/"+id+".json"
			copy_file("res://docs/playtest/archipelago/proofs/"+id+".json",result[id])
	return result
func run()->void:
	create_timer(180).timeout.connect(func():push_error("campaign UI watchdog");quit(1))
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size;base="/tmp/campaign-ui-%d-%d"%[size.x,Time.get_ticks_usec()]
		session=Campaign.new();check(session.open(base+"/fresh.json"),"fresh UI profile")
		for id in Catalog.ids("market")+Catalog.ids("workshop"):session.legacy_paths[id]=base+"/absent-"+id
		session.legacy_paths.forest=base+"/absent-forest"
		await mount()
		check(not scene.buttons.island_forest.disabled and scene.buttons.island_geometry.disabled,"fresh campaign gates later islands")
		await capture(str(size.x)+"-fresh-map")
		await tap(scene.buttons.continue_story)
		check(current_scene.has_node("CampaignPortal"),"forest has nonoverlapping campaign return chrome")
		var portal=current_scene.get_node("CampaignPortal")
		await capture(str(size.x)+"-forest-portal")
		await tap(portal.back);scene=current_scene
		check(scene.has_method("show_party"),"forest returns to campaign")
		await unmount()
		copy_file("res://docs/playtest/archipelago/completed-fixture.json",base+"/complete.json")
		session=Campaign.new();check(session.open(base+"/complete.json"),"completed108 UI profile")
		session.legacy_paths=isolated_paths()
		await mount();check(session.profile.completed.size()==108,"UI sees108 proven completions")
		await capture(str(size.x)+"-completed-map")
		await tap(scene.buttons.journal);check(scene.modal,"journal modal opens")
		await tap(scene.buttons.party);check(scene.buttons.partner_xinglu.disabled==false,"earned companion configurable")
		await capture(str(size.x)+"-companions")
		await tap(scene.buttons.partner_xinglu);check("xinglu" in session.profile.party,"party selection saved")
		await tap(scene.buttons.close_party);await tap(scene.buttons.camp)
		await capture(str(size.x)+"-camp-keepsakes")
		await tap(scene.buttons.close_camp);await tap(scene.buttons.close_journal)
		for island in Catalog.ISLANDS:
			await tap(scene.buttons["island_"+island])
			var first=Catalog.ids(island)[0]
			check(scene.buttons.has("level_"+first),island+" chapter entries")
			await capture(str(size.x)+"-"+island+"-chapter")
			await tap(scene.buttons["level_"+first])
			var level=current_scene
			if Catalog.is_new(first):
				check(level.stage=="complete",first+" resumes completed stable stage")
				await tap(level.buttons.replay);check(level.modal,"replay confirmation")
				await tap(level.buttons.cancel);check(not level.modal and level.stage=="complete","cancel preserves completion")
				await tap(level.buttons.replay);await tap(level.buttons.confirm)
				check(level.stage=="intro","confirmed replay starts fresh run")
				level.notification(NOTIFICATION_APPLICATION_FOCUS_OUT);level.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
				check(level.paused and level.buttons.pause.text=="继续","interrupted intro offers Resume")
				await tap(level.buttons.pause);check(not level.paused,"native mouse resumes interrupted intro")
				var party=level.current().party.duplicate()
				check(party==session.profile.party,"new run freezes current selected party")
				for line in level.definition.intro:await tap(level.buttons.next)
				await tap(level.buttons.marks);check(level.annotation_mode,"observation marker tool toggles")
				await tap(level.buttons.marks);check(not level.annotation_mode,"marker tool exits without editing board")
				await tap(level.buttons.back_hub)
			else:
				check(level.has_node("CampaignPortal"),first+" legacy adapter navigation")
				await tap(level.get_node("CampaignPortal").back)
			scene=current_scene
			check(scene.has_method("show_party") and session.profile.completed.size()==108,first+" return preserves all earned progress")
			await tap(scene.buttons.all_islands)
		await unmount()
	Journey.enabled=false;Journey.session=null;Journey.selected_island=""
	print("CAMPAIGN UI: ",checks," assertions, ",failures," failures; ","headless" if headless else "native")
	quit(1 if failures else 0)

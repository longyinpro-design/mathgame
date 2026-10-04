extends SceneTree
const Campaign=preload("res://scripts/archipelago/session.gd")
const Journey=preload("res://scripts/archipelago/bridge.gd")
const Catalog=preload("res://scripts/archipelago/catalog.gd")
const Portal=preload("res://scripts/archipelago/legacy_portal.gd")
const Numbers=preload("res://scripts/content/content_catalog.gd")
class LegacyHost:
	extends Control
	var state={"stage":"complete"}
	var pending={}
	var modal=false
var checks=0
var failures=0
var base="/tmp/restore-ui-%d"%Time.get_ticks_usec()
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(note)
func frames()->void:await process_frame;await process_frame;await process_frame
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(60).timeout.connect(func():push_error("restore UI timeout");quit(1))
	var scene=load("res://game/geometry_gv02.tscn").instantiate();scene.save_path=base+"/epoch.json"
	root.add_child(scene);current_scene=scene;await frames()
	var next=scene.buttons.next;var revision=scene.session.profile.revision
	next.pressed.emit();next.pressed.emit()
	check(scene.session.profile.revision==revision+1 and scene.stage=="intro" and scene.beat==1,"detached next callback cannot skip another dialogue")
	scene.notification(NOTIFICATION_APPLICATION_FOCUS_OUT);scene.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(scene.paused and scene.buttons.has("pause") and scene.buttons.pause.text=="继续","intro focus interruption exposes mouse Resume")
	scene.buttons.pause.pressed.emit();check(not scene.paused,"mouse Resume unblocks story")
	scene.buttons.next.pressed.emit();check(scene.stage=="puzzle","story continues after focus recovery")
	scene.queue_free();await frames()
	var session=Campaign.new();session.allow_locked=true;check(session.open(base+"/portal.json"),"portal fresh session")
	session.legacy_paths.forest="res://docs/playtest/archipelago/proofs/forest.json"
	for island in ["market","workshop"]:
		for id in Catalog.ids(island):session.legacy_paths[id]=base+"/absent-"+id
	session.legacy_paths.MK01="res://docs/playtest/archipelago/proofs/MK01.json"
	Journey.session=session;Journey.enabled=true
	var host=LegacyHost.new();root.add_child(host);current_scene=host
	var portal=Portal.new();portal.host=host;portal.island="market";host.add_child(portal);await frames()
	session.repository.fail_at="replace";portal.go_hub();await frames()
	check(not session.pending.is_empty() and portal.retry.visible and portal.back.disabled,"legacy campaign save failure offers real retry and blocks navigation")
	var candidate=session.pending.duplicate(true)
	session.repository.fail_at="";portal.retry.pressed.emit();await frames()
	check(session.pending.is_empty() and session.profile==candidate and current_scene.has_method("show_party"),"retry installs exact pending candidate and resumes hub navigation")
	current_scene.queue_free();await frames()
	check(session.start("GV01"),"new chapter begins for return test")
	for line in Catalog.definition("GV01").intro:check(session.advance(),"intro advances")
	var actions=Numbers.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/geometry/witnesses.json"))).GV01
	for action in actions:check(session.edit_board(action),"legal geometry action")
	check(session.submit() and session.run().stage=="outcome","victory saves before outcome dialogue")
	check(session.start("MK01") and session.profile.return_point=="GV01","old-island replay preserves interrupted new outcome")
	host=LegacyHost.new();root.add_child(host);current_scene=host
	portal=Portal.new();portal.host=host;portal.island="market";host.add_child(portal);await frames()
	portal.go_next();await frames()
	check(current_scene.get("level_id")=="GV01" and current_scene.get("stage")=="outcome","legacy Continue resumes pending outcome rather than skipping to GV02")
	Journey.enabled=false;Journey.session=null
	print("RESTORE UI: ",checks," assertions, ",failures," failures")
	quit(1 if failures else 0)

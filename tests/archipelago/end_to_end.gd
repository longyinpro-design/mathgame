extends SceneTree
const Session=preload("res://scripts/archipelago/session.gd")
const Catalog=preload("res://scripts/archipelago/catalog.gd")
const Numbers=preload("res://scripts/content/content_catalog.gd")
var checks=0
var failures=0
func check(ok: bool, note: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(note)
func load_data(path:String)->Variant:return Numbers.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(path)))
func _initialize()->void:call_deferred("run")
func run()->void:
	var session=Session.new()
	var path="/tmp/archipelago-e2e-%d/save.json"%Time.get_ticks_usec()
	check(session.open(path),"fresh campaign")
	check(Catalog.next_main(session.profile.completed)=="FL01","fresh starts forest")
	check(not session.start("GV01") and not session.start("SO18"),"cannot jump to new islands")
	session.legacy_paths.forest="res://docs/playtest/archipelago/proofs/forest.json"
	for island in ["market","workshop"]:
		for id in Catalog.ids(island):
			var proof="res://docs/playtest/archipelago/proofs/%s.json"%id
			if not FileAccess.file_exists(proof):push_error("Missing actual native completion proof "+id);quit(1);return
			session.legacy_paths[id]=proof
	check(session.sync_legacy(),"54 validated original completions imported")
	check(session.profile.completed.size()==54 and Catalog.next_main(session.profile.completed)=="GV01","legacy chain reaches geometry only")
	var witnesses={"geometry":load_data("res://tests/geometry/witnesses.json"),"fractions":load_data("res://tests/fractions/solutions.json"),"observatory":load_data("res://tests/observatory/witnesses.json")}
	for island in Catalog.NEW:
		check(Catalog.island_open(island,session.profile.completed),island+" unlocked by preceding main story")
		for id in Catalog.mains(island):
			check(Catalog.next_main(session.profile.completed)==id,id+" actual main continuation")
			await solve(session,id,witnesses[island][id])
		for id in Catalog.ids(island):
			if Catalog.is_side(id): check(id not in session.profile.completed,"optional side was not required "+id)
	# All main stories now complete, while all12 new sides remain playable.
	check(Catalog.next_main(session.profile.completed).is_empty(),"all84 main levels complete without new sides")
	for island in Catalog.NEW:
		for id in Catalog.ids(island):
			if Catalog.is_side(id):await solve(session,id,witnesses[island][id])
	check(session.profile.completed.size()==108,"all108 actual-rule completions")
	check(session.profile.claimed_rewards.size()==108,"one claim identity per level")
	check(session.profile.roster.size()==8,"eight companions follow actual milestones")
	check(session.profile.learning_runs.size()==54,"54 new completed runs retain real board evidence")
	check(session.profile.observations.size()==108,"old historical facts and new factual records coexist")
	var clone=Session.new();check(clone.open(path) and clone.profile==session.profile,"whole campaign restored identically")
	var copy=FileAccess.open("res://docs/playtest/archipelago/completed-fixture.json",FileAccess.WRITE);copy.store_string(JSON.stringify(session.profile));copy.close()
	var receipt={"assertions":checks,"failures":failures,"completed":session.profile.completed,"claimed_rewards":session.profile.claimed_rewards,"roster":session.profile.roster,"scope":"108 rule-validated completions: forest action fixture +36 legacy native captures +54 new campaign action sequences; not108 full narrative native playthroughs"}
	var file=FileAccess.open("res://docs/playtest/archipelago/end-to-end.json",FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"  "));file.close()
	print("ARCHIPELAGO E2E: ",checks," assertions, ",failures," failures; 108/108 completion ledger")
	quit(1 if failures else 0)
func solve(session:RefCounted,id:String,witness:Variant)->void:
	check(session.start(id),id+" start through real prerequisites")
	for line in Catalog.definition(id).intro:check(session.advance(),id+" dialogue")
	var actions:Array=witness.actions if witness is Dictionary else witness
	for action in actions:check(session.command({"kind":"board","action":action},session.profile.revision),id+" player action")
	check(session.submit() and id in session.profile.completed,id+" legitimate victory")
	for line in Catalog.definition(id).outro:check(session.advance(),id+" outcome")
	check(session.run().stage=="complete",id+" stable return stage")
	print("E2E ",id," complete")
	await process_frame

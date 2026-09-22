extends SceneTree
# Art-space goldens are measured from the unchanged 1280x720 treehouse backdrop.
# They deliberately do not reuse scene_layout's mutable support constants.
const Cargo = preload("res://scripts/cargo/world.gd")
const Forest = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Workshop = preload("res://scripts/workshop/gw01_world.gd")
var checks = 0
var failures = 0
func _initialize():
	preload("res://tests/forest/window_focus.gd").configure(root)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; push_error(label)
func run():
	var cargo = Cargo.new(); root.add_child(cargo)
	for count in range(1,8):
		cargo.state.weights = [1,2,3,4,5,6,7].slice(0,count)
		cargo.state.places = []; cargo.state.places.resize(count); cargo.state.places.fill(0)
		for loc in [0,1,2,3]:
			cargo.state.places.fill(loc)
			for i in count:
				check(is_equal_approx(cargo.item_position(i).y,592.0 if loc == 0 else 263.0 if loc == 3 else 588.0 if loc == 1 else 259.0),"no unsupported second row %d/%d/%d"%[count,loc,i])
				check(cargo.hit_item(cargo.item_rect(i).get_center()) == i,"each crowded item is independently reachable")
	for lift in [0.0,0.25,0.5,0.75,1.0]:
		cargo.lift = lift
		for side in [1,2]: check(cargo.basket_position(side).y-90 >= 170,"sling junction stays below pulley")
		check((cargo.gangway_rect().size.x > 0) == (lift in [0.0,1.0]),"gangway only present at dock")
	for lift in [0.0,1.0]:
		cargo.lift = lift
		var basket = cargo.basket_position(2 if lift == 0 else 1)
		var deck = cargo.gangway_rect()
		check(deck.position.x <= basket.x+117 and deck.end.x >= 1190 and deck.position.y <= 263 and deck.end.y >= 263,"upper unloading has continuous support to treehouse")
		cargo.moving = true; check(cargo.gangway_rect().size == Vector2.ZERO,"bridge retracts for lift motion"); cargo.moving = false
	cargo.queue_free(); await process_frame
	var game = Forest.instantiate(); game.save_path = "/tmp/ui-support-"+str(Time.get_ticks_usec())+".json"; root.add_child(game)
	await preload("res://tests/forest/window_focus.gd").ready(root)
	check(Scenarios.play(game.session,"FL01"),"prepare real cargo result")
	game.session.profile.story.results.FL01 = game.session.profile.active_run.state.duplicate(true)
	for id in ["pre_FL01","post_FL01","letter"]:
		game.session.profile.story.node = id; game.page = "story"; game.refresh()
		game.story_stage.paused = true
		for fraction in [0.0,0.5,1.0]:
			game.story_stage.elapsed = game.story_stage.duration*fraction; game.story_stage._update_pose()
			for who in ["hero","acheng"]:
				var y: float = game.story_stage.cast[who].position.y
				check(absf(y-(592.0 if id == "pre_FL01" else 263.0)) < 1,"story feet meet painted dock "+id+" "+who)
			check(game.story_stage.npc.position.y == 263,"station master supported on upper deck")
	var shop = Workshop.new(); root.add_child(shop)
	shop.state.stage = "delivery"
	for p in [0.0,0.2,0.45,0.6,1.0]:
		shop.progress = p
		var foot = shop.tray_foot(0)
		if p <= 0.45:
			var delta = Vector2(661,309)-Vector2(270,448)
			check(absf(delta.cross(foot-Vector2(270,448))) < 0.02,"tray loading ends at lift contact")
		else: check(foot == shop.lift_foot()-Vector2(0,25),"tray remains on ascending lift")
	shop.queue_free()
	for player in game.sound.get_children():
		if player is AudioStreamPlayer:
			for c in player.finished.get_connections(): player.finished.disconnect(c.callable)
			player.stop(); player.stream = null
	await create_timer(0.15).timeout
	game.queue_free(); await process_frame; await process_frame
	print("SUPPORT ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

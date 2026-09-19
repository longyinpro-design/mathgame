extends SceneTree
# v0.7 presentation QA captures: camp, region, 24-point console, gates, story beats.
const Scene = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
var game: Control
const CAPTURE = "res://docs/playtest/v07-presentation"

func _initialize() -> void:
	preload("res://tests/forest/window_focus.gd").configure(root); call_deferred("run")

func capture(name: String) -> void:
	for i in range(3): await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(CAPTURE+"/"+name+".png")

func set_story(node: String) -> void:
	game.session.profile.story.node = node
	game.resume_story()
	for i in range(4): await process_frame

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("v07 screenshot watchdog"); quit(1))
	var path = "/tmp/pixel-v07-screens-"+str(Time.get_ticks_usec())+".json"
	game = Scene.instantiate(); game.save_path = path; game.time_scale = 0.02; root.add_child(game)
	for id in ["FL01","FL02","FL03","FL04","FL05","FL06"]: Scenarios.play(game.session,id)
	await process_frame
	# Story: opening beat with dialogue box and primary button
	game.session.profile.story.node = "pre_FL01"
	game.resume_story(); await capture("story-opening")
	# Region with pokeable spots (treetop)
	Scenarios.send(game.session,{"kind":"camp"})
	game.page = "region"; game.region = "treetop"; game.show_region("treetop")
	await capture("region-treetop")
	# Camp with gold primary button
	Scenarios.send(game.session,{"kind":"camp"}); game.go_camp()
	await capture("camp")
	# 24-point console: initial, mid-solve, complete
	game.session.profile.story.node = "pre_FL07"
	Scenarios.send(game.session,{"kind":"start","level_id":"FL07","narrative":true,"node":"pre_FL07"})
	game.resume_story(); await capture("twenty-four-start")
	# use rule API for the mid-state, the completion overlay shows the last combination
	Scenarios.rule(game.session,{"kind":"combine","left":3,"right":1,"op":"-"})
	Scenarios.rule(game.session,{"kind":"combine","left":1,"right":2,"op":"*"})
	game.refresh(); await capture("twenty-four-mid")
	Scenarios.rule(game.session,{"kind":"combine","left":1,"right":0,"op":"-"})
	game.refresh(); await capture("twenty-four-complete")
	# Gates puzzle with crystal props
	game.session.profile.story.node = "pre_FL02"
	Scenarios.send(game.session,{"kind":"start","level_id":"FL02","narrative":true,"node":"pre_FL02"})
	game.resume_story(); await capture("gates-start")
	# FL17 boss aftermath + FL18 finale story beats
	await set_story("post_FL17"); game.story_stage.skip(); await capture("story-fl17")
	await set_story("post_FL18"); game.story_stage.skip(); await capture("story-fl18")
	await set_story("finale"); game.story_stage.skip(); await capture("story-finale")
	print("V07 SCREENS DONE")
	quit(0)

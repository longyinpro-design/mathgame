extends SceneTree
var failed = false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	print("AUDIO devices=",AudioServer.get_output_device_list()," current=",AudioServer.output_device," mix=",AudioServer.get_time_since_last_mix())
	var imported = load("res://assets/audio/v3/forest_theme.wav")
	var source = AudioStreamWAV.load_from_file("res://assets/audio/v3/forest_theme.wav")
	for stream in [imported,source]:
		var handles = []
		for i in range(3):
			var player = AudioStreamPlayer.new(); player.stream = stream; root.add_child(player); player.play()
			await create_timer(0.12).timeout
			print("AUDIO position=",player.get_playback_position()," mix=",AudioServer.get_time_since_last_mix())
			handles.append(weakref(player.get_stream_playback()))
			player.stop(); player.stream = null; player.queue_free()
			await create_timer(0.12).timeout
		var alive = handles.filter(func(ref): return ref.get_ref() != null).size()
		print("AUDIO format=",stream.format," retained=",alive,"/",handles.size())
		failed = failed or alive > 0
	quit(1 if failed else 0)

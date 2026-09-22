extends RefCounted

# Render a real native window without taking the user's foreground application,
# and minimize it immediately: these checks never need to be looked at, and a
# minimized window neither steals focus nor covers whatever the user is doing.
# Input is pushed straight into the viewport (root.push_input), so visibility
# is irrelevant to the checks themselves.
static func configure(window: Window) -> void:
	window.set_flag(Window.FLAG_NO_FOCUS,true)
	window.mode = Window.MODE_MINIMIZED

static func ready(window: Window) -> bool:
	# The root window reapplies project flags during startup, after SceneTree._initialize.
	if not window.get_flag(Window.FLAG_NO_FOCUS): configure(window)
	# A later refresh may have restored the mode; minimize again before input starts.
	if window.mode != Window.MODE_MINIMIZED: window.mode = Window.MODE_MINIMIZED
	if not window.has_meta("test_background_ready"):
		var signal_path = OS.get_environment("PIXEL_FOREST_WINDOW_READY")
		if not signal_path.is_empty():
			var signal_file = FileAccess.open(signal_path,FileAccess.WRITE)
			signal_file.store_string("ready"); signal_file.close()
			var deadline = Time.get_ticks_msec()+8000
			while not FileAccess.file_exists(signal_path+".restored") and Time.get_ticks_msec() < deadline: await window.get_tree().process_frame
			if not FileAccess.file_exists(signal_path+".restored"): push_error("Runner did not restore foreground before input"); return false
			while window.has_focus() and Time.get_ticks_msec() < deadline: await window.get_tree().process_frame
			if window.has_focus(): push_error("Test window did not yield foreground before input"); return false
		await window.get_tree().process_frame
		await window.get_tree().process_frame
		window.set_meta("test_background_ready",true)
	await window.get_tree().process_frame
	if DisplayServer.get_name() == "headless" or not window.get_flag(Window.FLAG_NO_FOCUS) or window.mode != Window.MODE_MINIMIZED:
		push_error("Window test requires a native minimized non-focus-stealing window")
		return false
	# Viewport-injected input stands in for returning to the game window. Native
	# minimization sends FOCUS_OUT, but cannot send the matching FOCUS_IN while
	# these fixtures deliberately remain minimized. Frozen-state assertions run
	# before ready(); restore logical focus only when the next interaction starts.
	for child in window.get_children(): child.propagate_notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	return true

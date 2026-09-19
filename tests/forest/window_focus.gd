extends RefCounted

# Render a real native window without taking the user's foreground application.
# Viewport input still reaches real Controls; focus-loss notifications are exercised separately.
static func configure(window: Window) -> void:
	window.set_flag(Window.FLAG_NO_FOCUS,true)

static func ready(window: Window) -> bool:
	# The root window reapplies project flags during startup, after SceneTree._initialize.
	if not window.get_flag(Window.FLAG_NO_FOCUS): configure(window)
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
	if DisplayServer.get_name() == "headless" or not window.visible or not window.get_flag(Window.FLAG_NO_FOCUS):
		push_error("Window test requires a visible native non-focus-stealing window")
		return false
	return true

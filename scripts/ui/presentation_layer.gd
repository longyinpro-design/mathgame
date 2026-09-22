extends Node2D
# Visibility and pause apply to the whole presentation branch, including child
# actors. Notifications/setters still run while processing is disabled, so the
# same branch can resume without polling or resetting its animation clock.
var presentation_paused = false:
	set(value):
		presentation_paused = value
		_sync_presentation()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_sync_presentation()

func _sync_presentation() -> void:
	if not is_inside_tree(): return
	process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() and not presentation_paused else Node.PROCESS_MODE_DISABLED

func redraw_pose() -> void:
	redraw_branch(self)

static func redraw_branch(node: Node) -> void:
	if node is CanvasItem and node.is_visible_in_tree(): node.queue_redraw()
	for child in node.get_children(): redraw_branch(child)

extends "res://scripts/ui/presentation_layer.gd"
var world: Node2D
var marks: Array = []
var positions: PackedVector2Array = []

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(world): return
	var next = PackedVector2Array()
	for index in marks:
		if index < 0 or index >= world.item_count(): continue
		next.append(world.item_position(int(index))+world.offsets.get(int(index),Vector2.ZERO)-Vector2(0,85))
	if next != positions:
		positions = next
		queue_redraw()

func _draw() -> void:
	for p in positions:
		draw_colored_polygon(PackedVector2Array([p,p+Vector2(16,-5),p+Vector2(16,23),p+Vector2(8,16),p+Vector2(0,23)]),Color("ecd285"))

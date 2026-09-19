extends Node2D
var world: Node2D
var marks: Array = []
func _process(_delta: float) -> void: queue_redraw()
func _draw() -> void:
	for index in marks:
		if index < 0 or index >= 6: continue
		var p: Vector2 = world.item_position(int(index))-Vector2(0,85)
		draw_colored_polygon(PackedVector2Array([p,p+Vector2(16,-5),p+Vector2(16,23),p+Vector2(8,16),p+Vector2(0,23)]),Color("ecd285"))

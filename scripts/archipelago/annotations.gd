extends Node2D
var points: Array = []
func _draw() -> void:
	for index in range(points.size()):
		var at: Vector2 = points[index]
		draw_circle(at,18,Color(1.0,0.82,0.35,0.2))
		draw_arc(at,18,0,TAU,24,Color("ffe29a"),2)
		draw_line(at+Vector2(-24,0),at+Vector2(-14,0),Color("ffe29a"),2)
		draw_line(at+Vector2(0,-24),at+Vector2(0,-14),Color("ffe29a"),2)

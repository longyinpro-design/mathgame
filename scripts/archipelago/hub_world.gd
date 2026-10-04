extends Node2D
var definition: Dictionary = {}
var state: Dictionary = {}
var presentation_paused = false
const Catalog = preload("res://scripts/archipelago/catalog.gd")
var clock = 0.0
func _process(delta: float) -> void:
	if not presentation_paused: clock += delta; queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("153843"))
	for row in range(22):
		var y = row*35+10
		for col in range(12):
			var x = col*122+(row%2)*52
			draw_line(Vector2(x,y),Vector2(x+48,y-3),Color(0.3,0.6,0.65,0.12+0.04*sin(clock+row)),2)
	for i in range(6):
		var center = Vector2(228+(i%3)*412,260+floor(i/3.0)*258)
		var land = PackedVector2Array([center+Vector2(-160,12),center+Vector2(-130,-48),center+Vector2(-45,-79),center+Vector2(42,-65),center+Vector2(132,-32),center+Vector2(169,19),center+Vector2(105,62),center+Vector2(-32,75)])
		draw_colored_polygon(land,Color("8aa39a"))
		var inland = PackedVector2Array()
		for point in land: inland.append(center+(point-center)*0.9+Vector2(0,-8))
		draw_colored_polygon(inland,Catalog.COLORS[Catalog.ISLANDS[i]].darkened(0.05 if Catalog.all_main_done(Catalog.ISLANDS[i],state.get("completed",[])) else 0.38))
		for j in range(4):
			var x = center.x-104+j*59
			draw_rect(Rect2(x,center.y-28-(j%2)*18,42,36+(j%2)*18),Catalog.COLORS[Catalog.ISLANDS[i]])
			draw_rect(Rect2(x+4,center.y-24-(j%2)*18,8,12),Color("d0c58f"))
		if i<5:
			var next = Vector2(228+((i+1)%3)*412,260+floor((i+1)/3.0)*258)
			draw_dashed_line(center+Vector2(142,32),next+Vector2(-140,32),Color("bdc59a"),2,8)

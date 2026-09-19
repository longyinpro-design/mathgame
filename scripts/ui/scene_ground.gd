extends Node2D
# Original painted terrain owns the ground. This layer carries only local outcomes.
var region = "treetop"
var story = false
var challenge = false
var completed: Array = []
var bridge = 1.0
var time = 0.0
var light_progress = 1.0
var bridge_gap = false
const LAMPS = [Vector2(332,294),Vector2(823,395),Vector2(1178,311)]
func _process(delta: float) -> void:
	time += delta; queue_redraw()
func _draw() -> void:
	if region == "village" and "FL04" in completed:
		for i in range(3):
			if light_progress < (i+1)*0.22: continue
			for ring in range(4): draw_circle(LAMPS[i],8+ring*7,Color(1,0.8,0.35,0.045+sin(time*1.4+i)*0.006))
	if region == "mill" and "FL07" in completed:
		for x in [815,937,1045]:
			for ring in range(3): draw_circle(Vector2(x,321),9+ring*8,Color(0.96,0.81,0.39,0.06))
		for i in range(4):
			var p = Vector2(639+i*18,437)
			draw_line(p,p-Vector2(0,14),Color("81985b"),2)
			draw_circle(p-Vector2(4,12),3,Color("9aac68"))

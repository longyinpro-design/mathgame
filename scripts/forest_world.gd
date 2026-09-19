extends Node2D
const BACKGROUND = preload("res://assets/runtime/forest-ravine-v2.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
const FOX = preload("res://assets/runtime/fox-v2.png")
var hero_x: float = 170
var fox_x: float = 100
var walking: bool = false
var facing: int = 1
var bridge: float = 0
var bloom: float = 0
var time: float = 0
var glow: float = 0
var show_actors: bool = true

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(BACKGROUND,Rect2(0,0,1280,720),false)
	# Engine-owned bridge decks unfold across the empty ravine.
	for i in range(12):
		var progress = clampf(bridge*12-i,0,1)
		if progress <= 0: continue
		var x = 735+i*22
		var y = 360+(1-progress)*60
		draw_rect(Rect2(x,y,23,12),Color("584b39"))
		draw_rect(Rect2(x,y-5,23,8),Color("b29d68"))
		draw_line(Vector2(x+2,y-3),Vector2(x+19,y-3),Color("dcc788"),2)
		if i%3 == 0:
			draw_rect(Rect2(x,y-32,5,30),Color("665740"))
			draw_circle(Vector2(x+2,y-33),4,Color("e7cb7e"))
	if bridge > 0:
		draw_line(Vector2(738,336),Vector2(738+260*bridge,336),Color("9e8a5a"),3)
	# Ambient light: drifting fireflies, mist flecks, water highlights.
	for i in range(28):
		var x = fposmod(i*127.7+sin(time*0.23+i)*35,1260)+10
		var y = 180+fposmod(i*67.0+sin(time*0.4+i)*18,350)
		var alpha = 0.25+0.3*(sin(time*1.7+i)+1)/2
		draw_circle(Vector2(x,y),2,Color(0.94,0.83,0.39,alpha))
	for i in range(8):
		var y = 425+fposmod(time*28+i*41,260)
		draw_line(Vector2(838+sin(i)*28,y),Vector2(847+sin(i)*28,y),Color(0.56,0.85,0.78,0.32),2)
	if glow > 0:
		draw_circle(Vector2(605,306),12+sin(time*4)*2,Color(0.3,0.85,0.75,0.5*glow))
		draw_arc(Vector2(605,306),22,0,TAU,40,Color(0.86,0.79,0.37,glow),2)
	if show_actors:
		draw_fox(fox_x)
		draw_hero()
	if bloom > 0:
		for i in range(12):
			var x = 1025+i*16
			var h = (18+sin(i*2)*10)*bloom
			draw_line(Vector2(x,367),Vector2(x,367-h),Color("789c59"),3)
			draw_circle(Vector2(x,366-h),4*bloom,Color("edce75") if i%2 else Color("d39ba0"))

func draw_hero() -> void:
	var step = [0,1,0,2][int(time*7)%4] if walking else 0
	var col = 3 if facing > 0 else 1
	var xs = [140,500,835,1200]
	var ys = [10,350,675]
	var hs = [334,312,328]
	var rect = Rect2(xs[col],ys[step],235 if col == 3 else 220,hs[step])
	var bob = -abs(sin(time*14))*2 if walking else sin(time*2)*0.7
	draw_set_transform(Vector2(hero_x,360),0,Vector2(1,0.25))
	draw_circle(Vector2.ZERO,22,Color(0.03,0.09,0.10,0.4))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect_region(HERO,Rect2(hero_x-28,277+bob,60,83),rect)

func draw_fox(x: float) -> void:
	var bob = -abs(sin(time*11))*3 if walking else sin(time*2.5)*1.4
	draw_texture_rect(FOX,Rect2(x-46,286+bob,92,86),false)
	# A small seed satchel travels with the companion.
	draw_rect(Rect2(x-6,337+bob,17,14),Color("967043"))
	draw_rect(Rect2(x-4,337+bob,13,3),Color("d7ad55"))

extends "res://scripts/ui/presentation_layer.gd"
# 工坊航图：总机船坞的暮色底景，每关以一枚黄铜齿轮标示完成。
# 灯火只读章节进度，卡片本身由宿主层画在街上；这里不保存任何关卡状态。
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")
const BACKDROP = preload("res://assets/source/workshop/central-engine-dock-stage-v1.png")
const COLUMNS = 6
const CARD_SIZE = Vector2(184, 118)
# The extra 20px of row gutter belongs to the lamp wire: a lit row must not graze the cards.
const CARD_STEP = Vector2(204, 158)
const CARD_FROM = Vector2(38, 182)
const ROWS = 3

var completed: Array = []
var next_id = ""

static func card_rect(index: int) -> Rect2:
	var column = index % COLUMNS
	var row = floori(index / float(COLUMNS))
	return Rect2(CARD_FROM + Vector2(column * CARD_STEP.x, row * CARD_STEP.y), CARD_SIZE)

static func lamp_pos(index: int) -> Vector2:
	var rect = card_rect(index)
	return Vector2(rect.position.x + CARD_SIZE.x / 2.0, rect.position.y - 16)

static func wire_y(row: int) -> float: return CARD_FROM.y + row * CARD_STEP.y - 25.0

const SCENE_SIZE = Vector2(1280,720)
var clock = 0.0

func _process(delta: float) -> void:
	if not presentation_paused: clock += delta

func _draw() -> void:
	draw_texture_rect(BACKDROP, Rect2(Vector2.ZERO,SCENE_SIZE), false)
	draw_level()

func draw_level() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCENE_SIZE), Color(0.045, 0.055, 0.075, 0.62))
	var ids = Catalog.order()
	for row in range(ROWS):
		var pts = PackedVector2Array([Vector2(16, wire_y(row)), Vector2(1264, wire_y(row))])
		draw_polyline(pts, Color(0.10, 0.08, 0.05, 0.9), 3)
		draw_polyline(pts, Color("6c4f22"), 1)
	for index in range(ids.size()):
		lamp(ids[index], index)

func lamp(id: String, index: int) -> void:
	var at = lamp_pos(index)
	draw_line(Vector2(at.x, wire_y(floori(index / float(COLUMNS)))), at, Color("6c4f22"), 2)
	var lit = completed.has(id)
	if lit:
		var beat = 1.0 if id != next_id else 0.75 + 0.25 * (0.5 + 0.5*sin(clock*3.2))
		draw_circle(at, 16.0 * beat, Color(1.0, 0.78, 0.40, 0.26 * beat))
		draw_circle(at, 8, Color("ffd27a") if id != next_id else Color("ffeec0"))
		draw_circle(at + Vector2(-2.5, -3), 2.5, Color(1.0, 0.97, 0.86, 0.85))
	else:
		draw_circle(at, 7, Color(0.13, 0.13, 0.14, 0.95))
	var ring = PackedVector2Array()
	for step in range(25):
		var angle = TAU * step / 24.0
		ring.append(at + Vector2(cos(angle), sin(angle)) * 9.0)
	ring.append(ring[0])
	draw_polyline(ring, Color("ffe297") if lit else Color("5c5240"), 2)
	for tooth in range(8):
		var angle = TAU * tooth / 8.0
		var ray = Vector2(cos(angle), sin(angle))
		draw_line(at + ray*9, at + ray*13, Color("d7bd83") if lit else Color("5c5240"), 4)
	if id == next_id and not lit:
		draw_arc(at, 16, 0, TAU, 32, Color(1.0,0.82,0.49,0.45+0.25*sin(clock*3.2)), 2)

extends Node2D
# kit-v1 拆件包的统一世界层：底景、锚点换算、站位读取、货签文字与落地动画只在这里实现一次。
# 关卡子类只需设置 scene_id/backdrop 并实现 draw_level()。
const UIStyle = preload("res://scripts/cargo/skin.gd")
const MANIFEST_PATH = "res://art/market-kit-v1/manifest.json"
const SCENE_SIZE = Vector2(1280, 720)
const INK_LIGHT = Color("fff0d1")
const INK_GOLD = Color("ffe297")
var state: Dictionary = {}
var progress = 0.0
var clock = 0.0
var scene_id := ""
var backdrop: Texture2D
var stations: Dictionary = {}
var land_place := ""
var land_slot := -1
var land_progress := 1.0
var parts: Dictionary = {}
var atlases: Dictionary = {}
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = UIStyle.face()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	for item in parsed.sprites:
		parts[item.id] = item
		atlases[item.id] = load("res://" + item.atlas)
	for scene in parsed.scenes:
		if scene.id == scene_id: stations = scene.stations
	if stations.is_empty(): push_error("kit-v1 manifest has no scene id "+scene_id)
	ready_level()

# Overridable hooks: the base owns _ready/_process/_draw so levels never repeat their boilerplate.
func ready_level() -> void: pass
func draw_level() -> void: pass
func begin_land(_previous: Dictionary) -> void:
	land_place = ""; land_slot = -1

func _process(delta: float) -> void:
	clock += delta

func _draw() -> void:
	if font == null or parts.is_empty(): return
	if backdrop != null: draw_texture_rect(backdrop, Rect2(Vector2.ZERO, SCENE_SIZE), false)
	draw_level()

# Manifest stations are the shared interface; a typo must fail loudly in the audit.
func station(name: String) -> Vector2:
	if not stations.has(name): push_error("kit-v1 scene "+scene_id+" has no station "+name); return Vector2.ZERO
	var value: Array = stations[name]
	return Vector2(value[0], value[1])

func has_part(id: String) -> bool: return parts.has(id)

# Slot layouts are arithmetic, not hand-typed coordinate lists.
static func grid(from: Vector2, step: Vector2, columns: int, count: int) -> Array:
	var spots: Array = []
	for index in range(count):
		var row := floori(index / float(columns))
		spots.append(from + Vector2((index - row * columns) * step.x, row * step.y))
	return spots

# Hit targets are logical squares around the good's foot, never the raw alpha bounds.
static func target(foot: Vector2, size: float, lift: float) -> Rect2:
	return Rect2(foot + Vector2(-size / 2.0, -lift), Vector2(size, size))

# anchor_px is measured in cropped-image pixels and the scale is applied exactly once.
func kit(id: String, foot: Vector2, width: float, alpha: float = 1.0, drop: float = 0.0) -> void:
	var texture: Texture2D = atlases[id]
	var item: Dictionary = parts[id]
	var scale = width / texture.get_width()
	var dims = Vector2(texture.get_width(), texture.get_height()) * scale
	var origin = foot + Vector2(0, drop) - Vector2(item.anchor_px[0], item.anchor_px[1]) * scale
	draw_texture_rect(texture, Rect2(origin, dims), false, Color(1, 1, 1, alpha))

func contact(foot: Vector2, radius: float, alpha: float = 0.26) -> void:
	draw_set_transform(foot + Vector2(0, 2), 0, Vector2(1, 0.26))
	draw_circle(Vector2.ZERO, radius, Color(0.1, 0.06, 0.03, alpha))
	draw_set_transform(Vector2.ZERO)

# Characters are source-sheet crops anchored at their own feet, not manifest kit parts.
func figure(texture: Texture2D, foot: Vector2, scale: float, alpha: float = 1.0) -> void:
	var dims = Vector2(texture.get_width(), texture.get_height()) * scale
	contact(foot, 34, 0.2 * alpha)
	draw_texture_rect(texture, Rect2(foot - Vector2(dims.x / 2, dims.y), dims), false, Color(1, 1, 1, alpha))

func words(text: String, at: Vector2, size_px: int = 17, color: Color = INK_LIGHT) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 3, Color("382515"))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func plaque(text: String, rect: Rect2, size_px: int = 16, color: Color = INK_LIGHT) -> void:
	var style = UIStyle.sign_style(); style.shadow_size = 0; style.bg_color.a = 1.0
	draw_style_box(style, rect)
	words(text, rect.position + Vector2(10, rect.size.y - 9), size_px, color)

func socket(centre: Vector2, radii: Vector2, strength: float) -> void:
	var pts = PackedVector2Array()
	for i in range(25):
		var angle = TAU * i / 24.0
		pts.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	pts.append(pts[0])
	draw_colored_polygon(pts, Color(1.0, 0.87, 0.58, 0.28 * strength))
	draw_polyline(pts, Color("8f6420", 0.9 * strength), 4, true)
	draw_polyline(pts, Color("ffe297", 1.0 * strength), 2, true)

# A good changes hands one at a time, so only the newest arrival needs the drop-in bounce.
func landing(place: String, slot: int) -> float:
	return 1.0 - land_progress if land_place == place and land_slot == slot else 0.0

func pulse(speed: float = 4.6) -> float: return 0.5 + 0.5 * sin(clock * speed)

# Goods that leave a stack for a carry animation must not stay drawn in their old slot.
func hide_while_moving(plan: Array) -> Array:
	var hidden: Array = []
	if progress < 0.5:
		for entry in plan: hidden.append(entry["home"])
	return hidden

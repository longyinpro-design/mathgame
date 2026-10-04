extends RefCounted
# Imagegen scenery and discrete sprites only. This helper never owns gameplay state.
const BACKGROUNDS = {
	"GV": preload("res://assets/source/late-islands-v1/geometry-terrace.png"),
	"FW": preload("res://assets/source/late-islands-v1/fractions-garden.png"),
	"SO": preload("res://assets/source/late-islands-v1/observatory-dome.png")
}
const PARTS = {
	"lingjiao": preload("res://assets/runtime/late-islands-v1/lingjiao.tres"),
	"lingjiao_joy": preload("res://assets/runtime/late-islands-v1/lingjiao_joy.tres"),
	"mirror_guardian": preload("res://assets/runtime/late-islands-v1/mirror_guardian.tres"),
	"valley_architect": preload("res://assets/runtime/late-islands-v1/valley_architect.tres"),
	"shuimo": preload("res://assets/runtime/late-islands-v1/shuimo.tres"),
	"shuimo_joy": preload("res://assets/runtime/late-islands-v1/shuimo_joy.tres"),
	"floodkeeper": preload("res://assets/runtime/late-islands-v1/floodkeeper.tres"),
	"lotus_guardian": preload("res://assets/runtime/late-islands-v1/lotus_guardian.tres"),
	"jixing": preload("res://assets/runtime/late-islands-v1/jixing.tres"),
	"star_heron": preload("res://assets/runtime/late-islands-v1/star_heron.tres"),
	"storm_watcher": preload("res://assets/runtime/late-islands-v1/storm_watcher.tres"),
	"star_heron_joy": preload("res://assets/runtime/late-islands-v1/star_heron_joy.tres"),
	"wood_panel": preload("res://assets/runtime/late-islands-v1/wood_panel.tres"),
	"stone_tile": preload("res://assets/runtime/late-islands-v1/stone_tile.tres"),
	"water_panel": preload("res://assets/runtime/late-islands-v1/water_panel.tres"),
	"moss_tile": preload("res://assets/runtime/late-islands-v1/moss_tile.tres"),
	"star_panel": preload("res://assets/runtime/late-islands-v1/star_panel.tres"),
	"blocked_tile": preload("res://assets/runtime/late-islands-v1/blocked_tile.tres")
}
static func background(canvas: CanvasItem, island: String) -> void:
	canvas.draw_texture_rect(BACKGROUNDS[island],Rect2(0,0,1280,720),false)

static func sprite(canvas: CanvasItem, id: String, foot: Vector2, width: float) -> void:
	var texture: Texture2D = PARTS[id]
	var dims = texture.get_size()*width/texture.get_width()
	canvas.draw_set_transform(foot-Vector2(0,3),0,Vector2(1,0.22))
	canvas.draw_circle(Vector2.ZERO,width*0.32,Color(0.05,0.08,0.11,0.28))
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_texture_rect(texture,Rect2(foot-Vector2(dims.x/2,dims.y),dims),false)

static func surface(canvas: CanvasItem, id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	canvas.draw_texture_rect(PARTS[id],rect,false,tint)

static func panel(canvas: CanvasItem, id: String, rect: Rect2) -> void:
	# Atlas regions are opaque rectangular surfaces, not failed alpha cutouts.
	# Numeric content is painted afterward on a quiet center with a 12 px material rim.
	canvas.draw_texture_rect(PARTS[id],rect,false)
	var ink = Color("20354a") if id == "star_panel" else Color("244c53") if id == "water_panel" else Color("433b32")
	canvas.draw_rect(rect.grow(-12),ink)

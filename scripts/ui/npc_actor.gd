extends "res://scripts/ui/presentation_layer.gd"
static var metadata: Dictionary = {}
static var texture: Texture2D
var region = "treetop"
var clock = 0.0
var story_stage = 0
var talking = 0.0
var reaching = false
var prop_hand = Vector2.ZERO
var facing_left = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if metadata.is_empty(): metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/runtime/forest/npcs.json"))
	if texture == null: texture = load(metadata.path)

func _process(delta: float) -> void:
	clock += delta; talking = maxf(0,talking-delta); queue_redraw()

func _draw() -> void:
	if not metadata.get("frames",{}).has(region) or texture == null: return
	draw_set_transform(Vector2.ZERO,0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,26,Color(0.04,0.09,0.05,0.28)); draw_set_transform(Vector2.ZERO)
	var index = int(clock*1.8)%3
	# The middle station pose is crouching, not a breathing frame.
	if region == "treetop": index = 0
	if talking > 0: index = 2
	var frame: Dictionary = metadata.frames[region][index]; var r: Array = frame.region; var pivot: Array = frame.pivot
	var scale_value = 0.37
	draw_set_transform(Vector2.ZERO,0,Vector2(-1 if facing_left else 1,1))
	draw_texture_rect_region(texture,Rect2(-Vector2(pivot[0],pivot[1])*scale_value,Vector2(r[2],r[3])*scale_value),Rect2(r[0],r[1],r[2],r[3]))
	draw_set_transform(Vector2.ZERO)
	if reaching:
		var hand = (prop_hand-position)/scale
		draw_line(Vector2(-9,-65),hand,Color("737447"),9,true)
		draw_circle(hand,4,Color("e6bc8c"))
	if story_stage > 0:
		for i in story_stage: draw_circle(Vector2(-15+i*10,-126),2.5,Color("dac678"))

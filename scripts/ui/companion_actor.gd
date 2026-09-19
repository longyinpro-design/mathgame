extends Node2D
const FOX = preload("res://assets/runtime/fox-v2.png")
const HERO = preload("res://assets/source/explorer-sprites-v2.png")
const ACTIONS = {"idle":[0,1,2],"walk":[3,4,5],"interact":[6,7,8],"skill":[9,10,11],"affected":[12,13,14],"success":[15,16,17],"rest":[18,19,20],"talk":[21,22,23]}
# The board ends at y=592; the common footer starts at y=659.
const CHALLENGE_SCALE = 0.26
const CHALLENGE_FEET = {"hero":Vector2(128,657),"acheng":Vector2(205,657),"mossling":Vector2(282,657),"feather":Vector2(359,657)}
static var metadata: Dictionary = {}
static var textures: Dictionary = {}
var identity = "acheng"
var action = "idle"
var clock = 0.0
var remaining = 0.0
var grown = false
var facing_left = false
var pixel_scale = 0.42
var stride_distance = 0.0
var distance_driven = false
var prop_hand = Vector2.ZERO
var reaching = false
var motion_sample = Vector2.ZERO
var has_motion_sample = false

func place_at(foot: Vector2, walking: bool = false, teleport: bool = false) -> void:
	distance_driven = true
	var movement = foot-motion_sample if has_motion_sample else Vector2.ZERO
	motion_sample = foot; has_motion_sample = true
	if walking and not teleport:
		stride_distance += movement.length()
		if absf(movement.x) > 0.01: facing_left = movement.x < 0
	position = foot.round()
	if walking: action = "walk"
	elif action == "walk": action = "idle"; clock = 0.0

func hand_position() -> Vector2:
	return position+Vector2((-1 if facing_left else 1)*24,-42)*pixel_scale/0.42

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if identity == "hero" and pixel_scale == 0.42: pixel_scale = 0.48
	if metadata.is_empty(): metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/runtime/forest/actors.json"))
	if metadata.has(identity) and not textures.has(identity): textures[identity] = load(metadata[identity].path)

func play(value: String, duration: float = 0.7) -> void:
	if not ACTIONS.has(value): return
	action = value; clock = 0; remaining = duration

func _process(delta: float) -> void:
	clock += delta
	if remaining > 0:
		remaining -= delta
		if remaining <= 0: action = "idle"; clock = 0
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO,0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,28,Color(0.04,0.09,0.05,0.30)); draw_set_transform(Vector2.ZERO)
	draw_set_transform(Vector2.ZERO,0,Vector2(-1 if facing_left else 1,1))
	if metadata.has(identity) and textures.has(identity):
		var indexes: Array = ACTIONS[action]
		var speed = 3.0 if action in ["idle","rest"] else 7.0
		var phase = int(stride_distance/maxf(1.0,24.0*pixel_scale/0.42)) if action == "walk" and distance_driven else int(clock*speed)
		var index: int = indexes[phase%indexes.size()]
		var frame: Dictionary = metadata[identity].frames[index]
		var r: Array = frame.region; var pivot: Array = frame.pivot
		draw_texture_rect_region(textures[identity],Rect2(-Vector2(pivot[0],pivot[1])*pixel_scale,Vector2(r[2],r[3])*pixel_scale),Rect2(r[0],r[1],r[2],r[3]))
	elif identity == "acheng":
		var hop = sin(clock*PI*5)*7 if action == "success" else 0.0
		draw_texture_rect_region(FOX,Rect2(-46,-87-hop,92,88),Rect2(200,190,920,880))
	elif identity == "hero":
		var rect = Rect2(1200,10,235,334)
		if action == "walk": rect = Rect2(1200,350 if int(clock*7)%2 == 0 else 675,235,312 if int(clock*7)%2 == 0 else 328)
		draw_texture_rect_region(HERO,Rect2(-36,-105,73,105),rect)
	if identity == "acheng" and grown:
		draw_colored_polygon(PackedVector2Array([Vector2(4,-42),Vector2(20,-49),Vector2(22,-37),Vector2(8,-32)]),Color("d5bd61"))
		draw_colored_polygon(PackedVector2Array([Vector2(6,-40),Vector2(-5,-48),Vector2(-8,-34),Vector2(5,-33)]),Color("99ad60"))
	draw_set_transform(Vector2.ZERO)
	if reaching:
		var shoulder = Vector2((-1 if facing_left else 1)*10,-48)*pixel_scale/0.42
		draw_line(shoulder,prop_hand-position,Color("47665e") if identity == "hero" else Color("a89a65"),7*pixel_scale/0.42,true)
		draw_circle(prop_hand-position,4*pixel_scale/0.42,Color("e6bc8c"))

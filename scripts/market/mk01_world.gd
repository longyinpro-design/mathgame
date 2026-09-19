extends Node2D
const Rules = preload("res://scripts/market/mk01_rules.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/runtime/market/harbor-empty-v2.png")
const PROPS = preload("res://assets/source/market/mechanisms-source-v1.png")
const CARGO = preload("res://assets/runtime/cargo-props-v5.png")
const CUP_REGIONS = [Rect2(80,64,244,302),Rect2(347,171,288,183),Rect2(682,205,179,160)]
const SHELF_FEET = [Vector2(955,345),Vector2(1065,345),Vector2(932,423),Vector2(1010,423),Vector2(1088,423),Vector2(932,481),Vector2(1010,481),Vector2(1088,481)]
# Centres of the three recesses painted in the tray: dark ellipses in source region
# 928,153,600,196 at local x 135.5/269.5/404, y 83.5, scaled into 416,435,313,86.
const SLOT_SOCKETS = [Vector2(487,472),Vector2(557,472),Vector2(627,472)]
const SOCKET_R = Vector2(18,9.5)
const SEAT_DEPTH = 8.0
# Artwork measurements in runtime pixels at cup_size(), taken inside each source region.
# The blue jug's handle lies outside its body, so its painted axis is left of the region centre.
const CUP_AXIS_X = [-9.2,1.9,0.1]  # body axis, from the drawn rect centre
const CUP_ART_GAP = [1.8,0.0,1.9]  # region bottom to the lowest artwork pixel
const CUP_RIM = [Vector2(-69.2,15.7),Vector2(-33.3,17.0),Vector2(-21.2,9.5)]  # liquid height above the foot, radius
const CUP_BASE_R = [18.0,12.5,5.8]  # half width where the cup meets its support
const LIFT = 9.0
const DIM = Color(0.80,0.76,0.70)   # unselected cups recede while one is held
const HELD = Color(1.16,1.14,1.02)   # the held cup is lit slightly above the shelf
var state = Rules.fresh()
var selected = -1
var clock = 0.0
var progress = 0.0
var move_id = -1
var move_from = Vector2.ZERO
var move_to = Vector2.ZERO
var move_progress = 1.0
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = UIStyle.face()

func _process(delta: float) -> void:
	# The held cup breathes, so its cue needs a running clock; the scene redraws every frame.
	clock += delta

func cup_kind(id: int) -> int:
	return 0 if id < 2 else (1 if id < 5 else 2)

func cup_description(id: int) -> String:
	var kind = cup_kind(id)
	var label = ["蓝杯","白杯","小杯"][kind]
	return label+" · "+("每杯 %d 小杯"%Rules.CAPACITIES[id] if state.calibrated or kind == 2 else "容量未知（2—8 小杯）")

func kind_size(kind: int) -> Vector2:
	# The one-unit cup fits below the white-cup label, on its own shelf.
	return [Vector2(58,78),Vector2(61,42),Vector2(30,27)][kind]

func cup_size(id: int) -> Vector2:
	return kind_size(cup_kind(id))

func slot_foot(slot: int) -> Vector2:
	return SLOT_SOCKETS[slot]+Vector2(0,SEAT_DEPTH)

func cup_foot(id: int) -> Vector2:
	var slot = state.slots.find(id)
	return slot_foot(slot) if slot >= 0 else SHELF_FEET[id]

func cup_rect(id: int) -> Rect2:
	# The held cup hovers, so its hotspot follows it and stays clickable end to end.
	var foot = cup_foot(id)-Vector2(0,LIFT if selected == id else 0)
	if id >= 5: return Rect2(foot-Vector2(33,44),Vector2(66,48))
	return Rect2(foot-Vector2(33,79 if id < 2 else 55),Vector2(66,80 if id < 2 else 64))

func slot_rect(slot: int) -> Rect2:
	return Rect2(slot_foot(slot)-Vector2(32,83),Vector2(64,102))

func words(text: String, at: Vector2, size_px: int = 18, color: Color = Color("fff0d1")) -> void:
	draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,3,Color("382515"))
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func plaque(text: String, rect: Rect2, size_px: int = 16) -> void:
	var style = UIStyle.sign_style(); style.shadow_size = 0; style.bg_color.a = 1.0
	draw_style_box(style,rect)
	words(text,rect.position+Vector2(10,rect.size.y-8),size_px)

func ellipse(centre: Vector2, radii: Vector2) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(33):
		var a = TAU*i/32.0
		pts.append(centre+Vector2(cos(a)*radii.x,sin(a)*radii.y))
	pts.append(pts[0])
	return pts

func ground_mark(centre: Vector2, radii: Vector2, strength: float) -> void:
	# A flattened ring lying on the support plane marks a footprint without circling
	# the artwork the way an upright circle does.
	var ring = ellipse(centre,radii)
	draw_colored_polygon(ring,Color(1.0,0.87,0.58,0.3*strength))
	draw_polyline(ring,Color("8f6420",0.9*strength),4,true)
	draw_polyline(ring,Color("ffe297",1.0*strength),2,true)

func pin(tip: Vector2) -> void:
	var pts = PackedVector2Array([tip+Vector2(-11,-17),tip+Vector2(11,-17),tip+Vector2(0,-2)])
	draw_colored_polygon(pts,Color("ffe297"))
	var closed = pts.duplicate(); closed.append(pts[0])
	draw_polyline(closed,Color("5c3f16",0.95),2,true)

func cup(id: int, foot: Vector2, angle: float = 0.0, full: bool = true) -> void:
	var kind = cup_kind(id)
	var dims = cup_size(id)
	var chosen = selected == id
	var pulse = 0.5+0.5*sin(clock*4.6)
	var ring = CUP_BASE_R[kind]+7+2*pulse
	var seat = foot
	if chosen:
		ground_mark(seat+Vector2(0,1),Vector2(ring,ring*0.22),0.75+0.25*pulse)
		foot -= Vector2(0,LIFT+1.5*pulse)
	# Only the held cup is lit above the shelf; the rest recede behind it.
	var tint = HELD if chosen else (Color.WHITE if selected < 0 else DIM)
	if state.slots.find(id) < 0:
		# A seated cup needs no contact ellipse: the painted recess is already dark and a
		# flat shadow would spill onto the tray's front lip.
		draw_set_transform(seat+Vector2(0,1),0,Vector2(1,0.26))
		draw_circle(Vector2.ZERO,CUP_BASE_R[kind]+(3 if chosen else 4),Color(0.10,0.06,0.025,0.2 if chosen else 0.28))
	draw_set_transform(foot,angle)
	# Anchor the region by the painted body axis so the base lands on the foot point.
	var offset = Vector2(-CUP_AXIS_X[kind]-dims.x/2,CUP_ART_GAP[kind]-dims.y)
	draw_texture_rect_region(PROPS,Rect2(offset,dims),CUP_REGIONS[kind],tint)
	# The rendered liquid is a state layer; image colors never determine capacity.
	if full:
		draw_set_transform(foot+Vector2(0,CUP_RIM[kind].x).rotated(angle),angle,Vector2(1,0.22))
		draw_circle(Vector2.ZERO,CUP_RIM[kind].y,Color("72c6db")*tint)
	draw_set_transform(Vector2.ZERO)
	if chosen: pin(foot+Vector2(0,offset.y-3))

func poured_volume() -> float:
	if state.stage == "result" or state.stage in ["delivery","complete"]: return Rules.volume(state.slots)
	if state.stage != "measuring": return 0.0
	if not state.calibrated: return 0.0
	var phase = progress*3.0
	var total = 0.0
	for slot in range(3):
		var id: int = state.slots[slot]
		if id >= 0: total += Rules.CAPACITIES[id]*clampf((phase-slot-0.2)/0.55,0,1)
	return total

func seed_position() -> Vector2:
	if state.stage == "complete": return Vector2(423,411)
	if state.stage != "delivery": return Vector2(293,365)
	if progress < 0.4: return Vector2(293,365).lerp(Vector2(312,229),smoothstep(0,0.4,progress))
	if progress < 0.75: return Vector2(312,229).lerp(Vector2(423,265),smoothstep(0.4,0.75,progress))
	return Vector2(423,265).lerp(Vector2(423,411),smoothstep(0.75,1,progress))

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	# These props are removed from the backdrop and have exactly one visual owner.
	draw_texture_rect_region(PROPS,Rect2(416,435,313,86),Rect2(928,153,600,196))
	draw_texture_rect_region(PROPS,Rect2(741,416,135,98),Rect2(17,439,438,223))
	var amount = poured_volume()
	if amount > 0:
		var height = minf(amount,18)/18.0*43
		draw_rect(Rect2(752,474-height,104,height),Color(0.23,0.68,0.84,0.8))
		draw_line(Vector2(752,474-height),Vector2(856,474-height),Color("c4f5ec"),2)
	# Exact calibration: engine-drawn tick marks and numbers, not baked illustration.
	for tick in range(19):
		var y = 474-tick/18.0*43
		draw_line(Vector2(853,y),Vector2(860 if tick % 2 else 864,y),Color("f5e6bb"),1)
	words("0",Vector2(867,480),14)
	words("18",Vector2(867,433),14)
	if state.stage == "measuring":
		plaque("正在验量…",Rect2(735,525,160,34),18)
	elif state.stage in ["result","delivery","complete"]:
		plaque("验量 %d 小杯"%int(amount),Rect2(735,525,160,34),18)
	else: plaque("交货目标 11" if state.calibrated else "量槽 · 只读整盘",Rect2(730,525,175,34),17)
	for slot in range(3):
		if state.slots[slot] < 0 and selected >= 0:
			var beat = 0.5+0.5*sin(clock*4.6)
			ground_mark(SLOT_SOCKETS[slot],SOCKET_R*(1.0+0.07*beat),0.45+0.3*beat)
		var digit = str(slot+1)
		words(digit,SLOT_SOCKETS[slot]+Vector2(-font.get_string_size(digit,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x/2,45),16)
	plaque("接货托盘 · 恰好 3 只满杯",Rect2(436,531,280,34),18)
	for id in range(8):
		if id == move_id and move_progress < 1: continue
		var slot = state.slots.find(id)
		if state.stage == "measuring" and slot >= 0:
			var phase = progress*3-slot
			if phase >= 0 and phase < 1:
				var lift = sin(clampf(phase,0,1)*PI)
				var foot = slot_foot(slot).lerp(Vector2(722,419),minf(1,lift*1.8))
				var angle = 1.2*sin(clampf((phase-0.12)/0.8,0,1)*PI)
				cup(id,foot,angle,phase < 0.75)
				var rim = CUP_RIM[cup_kind(id)]
				if phase > 0.2 and phase < 0.75: draw_line(foot+Vector2(rim.y,rim.x).rotated(angle),Vector2(778,452),Color("99e2ed"),4,true)
			else: cup(id,cup_foot(id),0,phase < 0)
		else: cup(id,cup_foot(id),0,state.stage not in ["result","delivery","complete"] or slot < 0)
	if move_id >= 0 and move_progress < 1:
		var foot = move_from.lerp(move_to,smoothstep(0,1,move_progress))-Vector2(0,sin(move_progress*PI)*33)
		cup(move_id,foot)
	# The capacity signs hang on the shelf's front lip, so they stay over the cups' footprints.
	plaque("蓝杯 · 每杯 6" if state.calibrated else "蓝杯 · 容量待查",Rect2(914,348,185,27))
	plaque("白杯 · 每杯 4" if state.calibrated else "白杯 · 容量待查",Rect2(914,425,185,27))
	plaque("小杯 · 每杯 1",Rect2(914,488,185,27))
	if state.stage == "measuring" and not state.calibrated:
		# Opaque shutter covers the entire chamber, including baked glass highlights.
		plaque("三杯倒完再开",Rect2(740,411,143,104),16)
	var foot = seed_position()
	# One hanging assembly, rooted in the actual painted pulley axle.
	# When unloaded, the hook returns above the boat; no hook is baked in v2.
	var hook = Vector2(313,215) if state.stage == "complete" else foot-Vector2(0,56)
	draw_line(Vector2(313,96),hook-Vector2(0,8),Color("654324"),5,true)
	draw_line(Vector2(312,96),hook-Vector2(1,8),Color("edc78a"),2,true)
	draw_arc(hook,7,-PI*0.5,PI*0.95,14,Color("e9bc63"),4,true)
	draw_set_transform(foot,0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,32,Color(0.07,0.05,0.03,0.35)); draw_set_transform(Vector2.ZERO)
	draw_texture_rect_region(CARGO,Rect2(foot-Vector2(31,67),Vector2(62,67)),Rect2(1136,74,310,382))
	if state.stage == "complete":
		for i in range(3):
			var p = Vector2(82+i*34,306)
			draw_circle(p,13,Color(1,0.78,0.32,0.13)); draw_circle(p,4,Color("ffdf88"))

	if state.stage in ["delivery","complete"]: return
	for index in range(state.observations.size()):
		var record: Dictionary = state.observations[index]
		var origin = Vector2(108,145+index*80)
		plaque("",Rect2(origin,Vector2(256,70)))
		words("第 %d 盘 · 整盘回执"%(index+1),origin+Vector2(10,20),16)
		var cursor = 0
		for kind in range(2):
			for n in range(record.counts[kind]):
				# Receipt icons share the body-axis anchoring of the shelf and tray cups.
				var shift = CUP_AXIS_X[kind]*34/kind_size(kind).x
				draw_texture_rect_region(PROPS,Rect2(origin+Vector2(12+cursor*43-shift,28),Vector2(34,34)),CUP_REGIONS[kind])
				cursor += 1
		words("= %d"%record.total,origin+Vector2(151,59),24)

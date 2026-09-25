extends Node2D
# 工坊现场的小岚：GW02 起由宿主挂世界之上、按钮之下，站在场景里听嗒嗒说话。
# 只取 explorer-sprites-v2 里与 GW01 同一帧的一段像素；不参与规则，也不挡鼠标。
const SHEET = preload("res://assets/source/explorer-sprites-v2.png")
const REGION = Rect2(1200,10,235,334)
const SIZE = Vector2(73,105)
const ArtStyle = preload("res://scripts/cargo/skin.gd")
var foot = Vector2.ZERO
var scale_factor = 1.0
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()

func _draw() -> void:
	if font == null or foot == Vector2.ZERO: return
	# 与各关世界同一套脚点画法：先落一层压扁的影子，再画全身和名字。
	var size = SIZE*scale_factor
	draw_set_transform(foot,0,Vector2(1,0.18))
	draw_circle(Vector2.ZERO,24*scale_factor,Color(0.08,0.1,0.12,0.3))
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	draw_texture_rect_region(SHEET,Rect2(foot-Vector2(size.x/2,size.y),size),REGION)
	var at = foot+Vector2(-22,24)
	draw_string_outline(font,at,"小岚",HORIZONTAL_ALIGNMENT_LEFT,-1,int(18*scale_factor),4,Color("21313c"))
	draw_string(font,at,"小岚",HORIZONTAL_ALIGNMENT_LEFT,-1,int(18*scale_factor),Color("fff0d1"))

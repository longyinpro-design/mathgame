extends RefCounted
const ATLAS = preload("res://assets/source/terrain-textures-v1.png")

static func surface(canvas: CanvasItem, rect: Rect2, kind: String, tint: Color = Color.WHITE) -> void:
	var source: Rect2 = {"stone":Rect2(772,4,248,248),"wood":Rect2(772,260,248,248),"metal":Rect2(772,516,248,248),"earth":Rect2(516,4,248,248)}[kind]
	var tile = Vector2(124,62) if kind in ["stone","earth"] else Vector2(124,124)
	var y = rect.position.y
	while y < rect.end.y:
		var x = rect.position.x
		while x < rect.end.x:
			var size = Vector2(minf(tile.x,rect.end.x-x),minf(tile.y,rect.end.y-y))
			canvas.draw_texture_rect_region(ATLAS,Rect2(Vector2(x,y),size),Rect2(source.position,source.size*size/tile),tint)
			x += tile.x
		y += tile.y

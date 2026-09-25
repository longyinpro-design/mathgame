extends RefCounted
# 第二批美术母版的运行期图集：整张源图 + 各元素的像素范围，按使用处的脚点绘制。
# 与 GW17 取巡轨兽同一套做法：只读 assets/source/workshop 下的母版，
# 不生成 .tres、不改母版、不做整图切分；范围按母版上的实际像素量出。
# 用法：Batch2.draw_part(self,"mi_shifu",Vector2(430,634),80)
const RESIDENTS = preload("res://assets/source/workshop/residents-source-v1.png")
const ENGINE = preload("res://assets/source/workshop/master-engine-parts-source-v1.png")
const SUPPORT = preload("res://assets/source/workshop/support-props-source-v1.png")
const EFFECTS = preload("res://assets/source/workshop/state-effects-source-v1.png")
const DOCK = preload("res://assets/source/workshop/dock-moving-parts-source-v1.png")
const PARTS = {
	# 居民：弥师傅（装配班长）、阿舷（码头领班），各一张全身造型。
	"mi_shifu": [RESIDENTS, Rect2(324,144,400,708)],
	"axian": [RESIDENTS, Rect2(1004,40,540,820)],
	# 百臂总机：核心、夹爪臂、平托臂、冷却机、暂存架、确认交接杆。
	"engine_core": [ENGINE, Rect2(52,40,484,476)],
	"claw_arm": [ENGINE, Rect2(596,132,428,384)],
	"flat_arm": [ENGINE, Rect2(1036,192,488,324)],
	"cooler": [ENGINE, Rect2(32,560,524,376)],
	"engine_rack": [ENGINE, Rect2(596,624,464,312)],
	"engine_lever": [ENGINE, Rect2(1148,560,356,376)],
	# 支持道具：备用压机、敲击件、空信号灯、维修页架、重车、接收箱。
	"spare_press": [SUPPORT, Rect2(88,36,480,468)],
	"striker": [SUPPORT, Rect2(756,116,108,368)],
	"signal_lamp": [SUPPORT, Rect2(1112,56,344,448)],
	"page_rack": [SUPPORT, Rect2(44,588,428,324)],
	"heavy_cart": [SUPPORT, Rect2(536,688,508,236)],
	"receive_box": [SUPPORT, Rect2(1104,608,408,288)],
	# 状态特效：蒸汽、交接火花、灯晕、休息布牌。
	"steam": [EFFECTS, Rect2(172,232,332,252)],
	"spark": [EFFECTS, Rect2(730,240,240,210)],
	"halo": [EFFECTS, Rect2(1176,192,324,316)],
	"placard": [EFFECTS, Rect2(1788,132,200,468)],
	# 码头可动件：独立报时铃架、空货船、吊钩滑轮。
	"bell_rack": [DOCK, Rect2(64,72,576,556)],
	"cargo_ship": [DOCK, Rect2(732,40,948,612)],
	"hook": [DOCK, Rect2(1816,24,240,664)],
}

static func sheet(id: String) -> Texture2D:
	return PARTS[id][0]
static func region(id: String) -> Rect2:
	return PARTS[id][1]
static func box(id: String, width: float) -> Vector2:
	var part: Rect2 = PARTS[id][1]
	return Vector2(width,width*part.size.y/part.size.x)
# 与世界里的 prop() 同一套脚点：底部中心落在 foot 上。
static func draw_part(canvas: CanvasItem, id: String, foot: Vector2, width: float, tint: Color = Color.WHITE) -> void:
	var part: Rect2 = PARTS[id][1]
	var size = box(id,width)
	canvas.draw_texture_rect_region(PARTS[id][0],Rect2(foot-Vector2(size.x/2,size.y),size),part,tint)
# 特效类元素按中心点画：蒸汽、火花、灯晕用中心，布牌用挂点当中心。
static func draw_centered(canvas: CanvasItem, id: String, center: Vector2, width: float, tint: Color = Color.WHITE) -> void:
	var part: Rect2 = PARTS[id][1]
	var size = box(id,width)
	canvas.draw_texture_rect_region(PARTS[id][0],Rect2(center-size/2,size),part,tint)

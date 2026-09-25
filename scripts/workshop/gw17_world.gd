extends Node2D
# GW17 总机船坞现场：一段 0～9 拍的承重轨道，四辆工具车各占一段。
# 每辆车的上轨许可（最早可发）、占轨区间与最晚驶离线全部按当前开工拍现算，画面不另存一份会走样的表；
# 下面那条共用轨道按拍列出「这一拍轨上有谁」，两辆车抢同一拍就当场标成撞轨。
# 巡轨兽站在轨口：规划时放下前爪拦车，逐段放行时抬起前爪，车形沿轨道滑过；
# 已放行的车在轨道上留下「已放行」记录，空着的拍写明「空着等」。
const Rules = preload("res://scripts/workshop/gw17_rules.gd")
const ArtStyle = preload("res://scripts/cargo/skin.gd")
const BACKDROP = preload("res://assets/source/workshop/central-engine-dock-stage-v1.png")
# 巡轨兽只有拦车、放行两张离散姿态的母版，没有 kit-v1 的 tres；这里按源图像素范围取两张运行期图集，
# 不改动 assets/ 下的任何文件。
const GUARDIAN = preload("res://assets/source/workshop/rail-guardian-source-v1.png")
const GUARDIAN_BLOCK = Rect2(57,220,805,530)
const GUARDIAN_RELEASE = Rect2(863,214,873,542)
const CART = preload("res://assets/runtime/workshop/kit-v1/cart.tres")
const DADA = preload("res://assets/runtime/workshop/kit-v1/dada_idle.tres")
const Batch2 = preload("res://scripts/workshop/batch2.gd")
const TICK_LEFT = 206.0
const TICK_W = 104.0
const TICKS = Rules.HORIZON
const GRID_LEFT = TICK_LEFT-10.0
const GRID_W = TICK_W*TICKS+20.0
const ROW_TOP = 260.0
const ROW_H = 52.0
const ROW_GAP = 4.0
const BAR_TOP = 5.0
const BAR_H = 30.0
const LANE_TOP = 490.0
const LANE_H = 52.0
const TINTS = [Color("c98a5b"),Color("7fa8c9"),Color("9ec98a"),Color("c9a0cf")]
const EDGES = [Color("6b4525"),Color("33536b"),Color("41602e"),Color("6a4a70")]
const GREEN = Color("8fd694")
const RED = Color("e2604f")
const AMBER = Color("e8c06a")
var scene_id = "engine"
var state = Rules.fresh()
var focus_item = 0
var progress = 0.0
var presentation_paused = false
var land_progress = 1.0
var land_place = ""
var font: Font
var guardian_block: AtlasTexture
var guardian_release: AtlasTexture

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = ArtStyle.face()
	guardian_block = AtlasTexture.new(); guardian_block.atlas = GUARDIAN; guardian_block.region = GUARDIAN_BLOCK
	guardian_release = AtlasTexture.new(); guardian_release.atlas = GUARDIAN; guardian_release.region = GUARDIAN_RELEASE

func begin_land(_previous: Dictionary) -> void:
	land_place = ""; land_progress = 1.0

func tick_x(t: int) -> float:
	return TICK_LEFT+t*TICK_W
func row_y(index: int) -> float:
	return ROW_TOP+index*(ROW_H+ROW_GAP)
# 点这一行就选中那辆车：车名牌、占轨区间和整行空白都算同一处。
func row_rect(index: int) -> Rect2:
	return Rect2(16,row_y(index),GRID_W+180,ROW_H)
func lane_rect(tick: int) -> Rect2:
	return Rect2(tick_x(tick)+2,LANE_TOP+4,TICK_W-4,LANE_H-8)

func prop(texture: Texture2D, foot: Vector2, width: float, tint: Color = Color.WHITE) -> void:
	var dims = Vector2(texture.get_width(),texture.get_height())*width/texture.get_width()
	draw_texture_rect(texture,Rect2(foot-Vector2(dims.x/2,dims.y),dims),false,tint)
func contact(foot: Vector2, radius: float) -> void:
	draw_set_transform(foot,0,Vector2(1,0.18))
	draw_circle(Vector2.ZERO,radius,Color(0.08,0.1,0.12,0.3))
	draw_set_transform(Vector2.ZERO)
func words(value: String, at: Vector2, size_px: int = 20) -> void:
	words_tint(value,at,size_px,Color("fff0d1"))
func words_tint(value: String, at: Vector2, size_px: int, tint: Color) -> void:
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,4,Color("21313c"))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,tint)
# 靠右对齐的读数：最晚驶离贴着刻度右边时，标签得往左让，不能画到轨道外面。
func words_right(value: String, right: float, baseline: float, size_px: int, tint: Color) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	words_tint(value,Vector2(right-width,baseline),size_px,tint)
func plaque(value: String, rect: Rect2, size_px: int = 19) -> void:
	draw_style_box(ArtStyle.sign_style(),rect)
	words(value,rect.position+Vector2(10,rect.size.y-10),size_px)

func starts_text() -> String:
	var parts = []
	for index in range(Rules.COUNT):
		parts.append("%s%d"%[Rules.ITEMS[index],state.starts[index]])
	return " ".join(parts)

# 演出进行到第几拍：巡轨兽从第 0 拍扫到第 9 拍。
func playhead() -> int:
	if state.stage != "delivery": return -1
	return clampi(floori(progress*(Rules.HORIZON+1)),0,Rules.HORIZON)

# 这一拍在轨上的是哪辆车；空着的拍返回空串。
func passing() -> String:
	var tick = playhead()
	if tick < 0: return ""
	var held = Rules.holders(state,tick)
	return "" if held.is_empty() else held[0]

# 这辆车是不是已经放行过了：演出扫过它的驶离拍，或者已经收工。
func released(id: String) -> bool:
	if state.stage == "aftermath" or state.stage == "complete": return true
	if state.stage != "delivery": return false
	var tick = playhead()
	return tick >= 0 and tick >= Rules.start_of(state,id)+Rules.DURATIONS[id]

func guardian_pose() -> Texture2D:
	if state.stage in ["aftermath","complete"]: return guardian_release
	if state.stage == "delivery" and not passing().is_empty(): return guardian_release
	return guardian_block

func guardian_blocking() -> bool:
	return guardian_pose() == guardian_block

# 显示用的重叠检查：只看玩家自己排出来的两段区间有没有抢同一拍。
func overlaps(index: int) -> bool:
	var rows = Rules.plan(state)
	for other in range(Rules.COUNT):
		if other == index: continue
		if maxi(rows[index].start,rows[other].start) < mini(rows[index].end,rows[other].end): return true
	return false

func draw_table() -> void:
	plaque("工具车与放行窗口",Rect2(430,232,420,40),20)
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		plaque("%s 车 · 最早第 %d 拍 · 占轨 %d 拍 · 最晚第 %d 拍驶离"%[
			id,Rules.RELEASES[id],Rules.DURATIONS[id],Rules.DEADLINES[id]],
			Rect2(390,282+index*62,500,50),18)

func draw_headers() -> void:
	plaque("四辆车共用一段承重轨道 · 一次一辆 · 开工后不能中断",Rect2(20,190,470,34),16)
	plaque("巡轨兽逐段放行：上轨许可 → 轨道占用 → 最晚驶离",Rect2(502,190,470,34),16)
	plaque("发车 %s"%starts_text(),Rect2(984,190,276,34),16)

# 上轨许可与最晚驶离：开局就画出来，玩家的排法只决定区间落在哪一段。
func draw_limits(index: int, id: String, top: float) -> void:
	var deadline_x = tick_x(Rules.DEADLINES[id])
	draw_rect(Rect2(deadline_x,top+2,tick_x(TICKS)-deadline_x,ROW_H-4),Color(0.62,0.22,0.18,0.18))
	draw_line(Vector2(deadline_x,top),Vector2(deadline_x,top+ROW_H),RED,2)
	var late_text = "最晚 %d 拍驶离"%Rules.DEADLINES[id]
	if deadline_x+14+font.get_string_size(late_text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x > tick_x(TICKS):
		words_right(late_text,deadline_x-8,top+20,15,RED)
	else:
		words_tint(late_text,Vector2(deadline_x+8,top+20),15,RED)
	if Rules.RELEASES[id] > 0:
		var gate = tick_x(Rules.RELEASES[id])
		draw_rect(Rect2(tick_x(0),top+2,gate-tick_x(0),ROW_H-4),Color(0.72,0.52,0.18,0.22))
		draw_dashed_line(Vector2(gate,top+2),Vector2(gate,top+ROW_H-2),AMBER,2)
		words_tint("第 %d 拍才准上轨"%Rules.RELEASES[id],Vector2(tick_x(0)+6,top+18),14,AMBER)

func draw_bar(index: int, id: String, top: float) -> void:
	var start = state.starts[index]
	var finish = start+Rules.DURATIONS[id]
	# 开工拍排到轨道尽头之外时，车块裁到最后一拍，红色描边照旧说明它逾期。
	var left = tick_x(start)+3
	var right = minf(tick_x(finish),tick_x(TICKS))-3
	var bar = Rect2(left,top+BAR_TOP,maxf(right-left,26.0),BAR_H)
	var early = start < Rules.RELEASES[id]
	var late = finish > Rules.DEADLINES[id]
	var hit = overlaps(index)
	draw_rect(bar,TINTS[index])
	draw_rect(bar,EDGES[index],false,3)
	words("%s 车 · %d 拍"%[id,Rules.DURATIONS[id]],bar.position+Vector2(10,22),18)
	words_tint("第 %d 拍发车"%start,Vector2(bar.position.x+6,top+ROW_H-4),14,
		RED if early or late else Color("d8e2d2"))
	if early or late: draw_rect(bar.grow(3),RED,false,3)
	elif hit: draw_rect(bar.grow(3),Color("e8a04f"),false,3)
	if state.stage == "puzzle" and index == focus_item:
		draw_rect(bar.grow(5),Color("f6e2a8"),false,3)

func draw_rows() -> void:
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		var top = row_y(index)
		draw_rect(Rect2(GRID_LEFT,top,GRID_W,ROW_H),Color("2a3138"))
		for t in range(TICKS+1):
			draw_line(Vector2(tick_x(t),top),Vector2(tick_x(t),top+ROW_H),Color(1,1,1,0.10),1)
		draw_limits(index,id,top)
		draw_bar(index,id,top)
		plaque("%s 车 · 占轨 %d 拍"%[id,Rules.DURATIONS[id]],Rect2(16,top,176,26),15)
		plaque("最早 %d · 最晚 %d 拍"%[Rules.RELEASES[id],Rules.DEADLINES[id]],Rect2(16,top+26,176,26),14)

func draw_ruler() -> void:
	for t in range(TICKS+1):
		words(str(t),Vector2(tick_x(t)-6,ROW_TOP-6),16)
	draw_line(Vector2(tick_x(TICKS),ROW_TOP-12),Vector2(tick_x(TICKS),LANE_TOP+LANE_H),RED,2)

# 共用轨道：每一拍列出轨上的车；两辆车抢同一拍就是撞轨。
func draw_lane() -> void:
	plaque("承重轨道 · 一次一辆",Rect2(16,LANE_TOP,176,44),15)
	draw_rect(Rect2(GRID_LEFT,LANE_TOP,GRID_W,LANE_H),Color("232a30"))
	for tick in range(TICKS):
		var rect = lane_rect(tick)
		var held = Rules.holders(state,tick)
		if held.is_empty():
			draw_rect(rect,Color(0.11,0.14,0.17,0.55))
			draw_rect(rect,Color(1,1,1,0.08),false,1)
			continue
		if held.size() == 1:
			var index = Rules.ITEMS.find(held[0])
			draw_rect(rect,TINTS[index])
			draw_rect(rect,EDGES[index],false,2)
			# 已经放行的车让位给「已放行」记录，字母不再压在记录上。
			if not released(held[0]): words(held[0],rect.position+Vector2(42,34),22)
			continue
		draw_rect(rect,RED)
		draw_rect(rect,Color("7a2f26"),false,2)
		words("撞轨",rect.position+Vector2(14,34),20)
	for tick in range(TICKS+1):
		draw_line(Vector2(tick_x(tick),LANE_TOP),Vector2(tick_x(tick),LANE_TOP+LANE_H),Color(1,1,1,0.12),1)

func draw_guardian() -> void:
	var foot = Vector2(1204,545)
	contact(foot,30)
	prop(guardian_pose(),foot,104)
	plaque("巡轨兽",Rect2(1156,424,100,30),15)
	words_tint("拦车" if guardian_blocking() else "放行",Vector2(1156,470),16,
		AMBER if guardian_blocking() else GREEN)

# 逐段放行：已驶离的车在轨道上留下「已放行」，整行描绿。
func draw_releases() -> void:
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		if not released(id): continue
		var top = row_y(index)
		draw_rect(Rect2(GRID_LEFT,top,GRID_W,ROW_H),GREEN,false,3)
		var left = tick_x(state.starts[index])
		var right = minf(tick_x(state.starts[index]+Rules.DURATIONS[id]),tick_x(TICKS))
		if right-left < 12: continue
		draw_rect(Rect2(left+2,LANE_TOP+4,right-left-4,LANE_H-8),GREEN,false,3)
		if right-left >= 92:
			words_tint("已放行",Vector2(left+10,LANE_TOP+LANE_H-14),15,GREEN)
		else:
			var center = Vector2((left+right)/2,LANE_TOP+LANE_H/2)
			draw_line(center+Vector2(-8,-1),center+Vector2(-2,5),GREEN,3)
			draw_line(center+Vector2(-2,5),center+Vector2(9,-7),GREEN,3)

func draw_playhead() -> void:
	var tick = playhead()
	if tick < 0: return
	draw_line(Vector2(tick_x(tick)+TICK_W/2,ROW_TOP-10),Vector2(tick_x(tick)+TICK_W/2,LANE_TOP+LANE_H+6),
		Color("f6e2a8"),3)
	var who = passing()
	if who.is_empty():
		words_tint("第 %d 拍 · 空着等"%tick,Vector2(GRID_LEFT,LANE_TOP+LANE_H+26),18,AMBER)
	else:
		var index = Rules.ITEMS.find(who)
		words_tint("第 %d 拍 · %s 车在轨上"%[tick,who],Vector2(GRID_LEFT,LANE_TOP+LANE_H+26),18,GREEN)
		var foot = Vector2(tick_x(tick)+TICK_W/2,LANE_TOP+LANE_H-10)
		contact(foot,30); prop(CART,foot,96,TINTS[index])

func draw_arrival() -> void:
	draw_table()
	plaque("四辆工具车都在坞口等着 · 巡轨兽拦在轨口",Rect2(390,536,500,40),18)
	for index in range(Rules.COUNT):
		var id = Rules.ITEMS[index]
		var foot = Vector2(268+index*176,630)
		contact(foot,26); prop(CART,foot,104,TINTS[index])
		words(id,foot-Vector2(14,14),20)

func _draw() -> void:
	if font == null: return
	draw_texture_rect(BACKDROP,Rect2(0,0,1280,720),false)
	# 坞口的小道具：报时铃架、重车与吊钩滑轮，和背景里的吊机同一层。
	# 吊钩按背景吊机的吊点摆，正好把背景里画死的静态吊钩遮住，不叠出两个。
	Batch2.draw_part(self,"bell_rack",Vector2(1232,296),92)
	Batch2.draw_part(self,"heavy_cart",Vector2(1230,398),132)
	Batch2.draw_part(self,"hook",Vector2(1262,230),64)
	if state.stage == "arrival":
		draw_arrival()
	else:
		draw_headers()
		draw_rows()
		draw_ruler()
		draw_lane()
		if state.stage in ["delivery","aftermath","complete"]: draw_releases()
		if state.stage == "delivery": draw_playhead()
		if state.stage in ["aftermath","complete"]:
			plaque("B 1–3 · C 3–4 · A 4–7 · D 7–9 · 第 0 拍空着等",Rect2(16,548,520,44),17)
	draw_guardian()
	var dada = Vector2(1204,638)
	contact(dada,26); prop(DADA,dada,92)
	words("嗒嗒",dada-Vector2(36,4),18)

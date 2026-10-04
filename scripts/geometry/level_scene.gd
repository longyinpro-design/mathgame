extends "res://scripts/archipelago/level_host.gd"
const Catalog=preload("res://scripts/geometry/catalog.gd")
const Rules=preload("res://scripts/geometry/rules.gd")
const World=preload("res://scripts/geometry/world.gd")
var selected=0
func configure():
	definition=Catalog.definition(level_id);rules=Rules.new(definition);world_script=World
func build_board():
	var p=definition.params
	for y in range(p.h):
		for x in range(p.w):
			add_hotspot("cell_%d_%d"%[x,y],Rect2(World.ORIGIN+Vector2(x,y)*World.CELL,Vector2.ONE*World.CELL),cell_click.bind(x,y),"格子 %d,%d"%[x+1,y+1])
	if rules.is_tile():
		selected=clampi(selected,0,board.pieces.size()-1)
		for i in range(board.pieces.size()):
			add_button("piece_%d"%i,("▶ " if i==selected else "")+"石块%d"%(i+1),Rect2(610+(i%2)*170,255+floor(i/2.0)*118,145,34),select_piece.bind(i))
		add_button("rotate","旋转 R",Rect2(610,510,145,38),piece_action.bind("rotate"))
		add_button("flip","镜像 F",Rect2(770,510,145,38),piece_action.bind("flip"))
		add_button("lift","收回石块",Rect2(610,559,145,38),piece_action.bind("lift"))
		if p.has("cut_shapes") and not board.cut:add_button("cut","沿刻痕切开",Rect2(770,559,170,38),act.bind({"type":"cut"}))
	else:
		draw_label("面积 %d   周长 %d\n连通块 %d"%[board.cells.size(),rules.perimeter(board.cells),rules.components(board.cells)],Rect2(630,285,340,85),26)
		if definition.mechanism=="symmetry":draw_label("金点是原花，不能移除\n虚线／圆心标记对称方式",Rect2(630,385,340,85),22)
		elif definition.mechanism=="architect_boss":draw_label("阶段 %d/2\n%s"%[board.proofs.size()+1,"先筑地基：6格 / 14边" if board.proofs.is_empty() else "避开落石：6格 / 10边"],Rect2(630,385,340,85),22)
		else:draw_label("目标：%d格 / %d边\n角碰角不算相连"%[p.area,p.perimeter],Rect2(630,385,340,85),22)
	if definition.mechanism=="mirror_boss" and board.proofs.size()==2:
		for id in ["piece_0","rotate","flip","lift"]:
			if buttons.has(id):buttons[id].disabled=true
	if definition.mechanism=="mirror_boss":draw_label("石盾封印 %d / 2"%board.proofs.size(),Rect2(990,264,245,36),22)
	if (definition.mechanism=="mirror_boss" and board.proofs.size()<2) or (definition.mechanism=="architect_boss" and board.proofs.is_empty()):add_button("seal","封印 / 推进",Rect2(990,555,210,42),act.bind({"type":"seal"}),true)
func select_piece(i: int):selected=i;refresh()
func piece_action(type: String):act({"type":type,"piece":selected})
func cell_click(x: int,y: int):
	if rules.is_tile():
		act({"type":"place","piece":selected,"x":x,"y":y})
	else:act({"type":"toggle","x":x,"y":y})
func handle_key(key: int) -> bool:
	if not rules.is_tile():return false
	if key==KEY_R:piece_action("rotate");return true
	if key==KEY_F:piece_action("flip");return true
	return false

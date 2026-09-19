extends RefCounted
const Rules = preload("res://scripts/mechanisms/twenty_four_rules.gd")
const Style = preload("res://scripts/cargo/skin.gd")
const TILE = preload("res://assets/runtime/forest/ui/button-gold.png")
const TILE_BRIGHT = preload("res://assets/runtime/forest/ui/button-gold-bright.png")

static func tile_style(texture: Texture2D, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var s = StyleBoxTexture.new(); s.texture = texture; s.modulate_color = tint
	s.texture_margin_left = 20; s.texture_margin_right = 20; s.texture_margin_top = 18; s.texture_margin_bottom = 18
	return s
static func tag_style() -> StyleBoxFlat:
	# Small parchment tag carrying the engine-rendered expression under each tile.
	var s = StyleBoxFlat.new(); s.bg_color = Color("e9ddba"); s.set_corner_radius_all(5)
	s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 3
	s.border_color = Color("b69b65")
	return s

static func draw(host: Control, definition: Dictionary, run: Dictionary) -> void:
	var tokens = Rules.replay(definition.params,run.state)
	var key = run.run_id+JSON.stringify(run.state)
	if host.twenty_board_key != key:
		host.twenty_selection.clear(); host.twenty_board_key = key
	# The machine housing: the puzzle lives on the mill's energy console, not on paper.
	
	var console: Node2D = host.twenty_console
	console.visible = true
	console.steps = run.state.steps.size()
	console.done = Rules.complete(definition.params,run.state)
	console.target_value = float(tokens[0].n)/float(tokens[0].d) if tokens.size() == 1 else 0.0
	host.text("数字卡："+"、".join(definition.params.cards.map(func(n): return str(n)))+"　每张恰好用一次，最后只留一张24。",Rect2(335,213,744,35),19,false)
	var width = 152.0; var gap = 32.0
	var start = 339.0
	for i in tokens.size():
		var x = start+i*(width+gap)
		var index = host.twenty_selection.find(i)
		var y = 258.0
		if index >= 0: x = 489+index*244; y = 408.0
		var caption = Rules.value_text(tokens[i])+("　①" if index == 0 else ("　②" if index == 1 else ""))
		var card: Button = host.button("number_card_"+str(i),caption,Rect2(x,y,width,58),select.bind(host,i),run.outcome == "active" and tokens.size() > 1)
		card.add_theme_font_size_override("font_size",30)
		for state_key in ["normal","hover","pressed","disabled"]:
			var texture = TILE if state_key != "hover" else TILE_BRIGHT
			var tint = Color(0.72,0.68,0.58) if state_key == "disabled" else (Color(0.8,0.76,0.66) if state_key == "pressed" else Color.WHITE)
			card.add_theme_stylebox_override(state_key,tile_style(texture,tint))
		for color_key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			card.add_theme_color_override(color_key,Style.DARK)
		card.add_theme_color_override("font_disabled_color",Color(0.33,0.31,0.22))
		card.add_theme_color_override("font_outline_color",Color("f6ecd2")); card.add_theme_constant_override("outline_size",0)
		var tag = Panel.new(); tag.position = Vector2(x-2,y+62); tag.size = Vector2(width+4,40); tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_stylebox_override("panel",tag_style()); host.ui.add_child(tag)
		host.text(tokens[i].expression,Rect2(x+3,y+64,width-6,36),16,true)
	var instruction = "依次点两张卡，再选 +、−、×、÷；减法和除法按①到②的顺序。"
	if host.twenty_selection.size() == 2:
		instruction = "将计算："+Rules.value_text(tokens[host.twenty_selection[0]])+"　□　"+Rules.value_text(tokens[host.twenty_selection[1]])+"　（结果会变成一张新卡）"
	elif tokens.size() == 1:
		instruction = "正好24，磨坊启动了！" if Rules.complete(definition.params,run.state) else "现在得到"+Rules.value_text(tokens[0])+"，还不是24。可以撤销，换一种组合。"
	host.text(instruction,Rect2(335,359,742,45),18,false)
	var operators = ["+","-","*","/"]
	for i in operators.size():
		var op: String = operators[i]
		host.button("operator_"+str(i),Rules.SYMBOLS[op],Rect2(402+i*120,508,100,38),calculate.bind(host,op),run.outcome == "active" and host.twenty_selection.size() == 2)
	host.button("swap_operands","交换①②",Rect2(895,508,178,38),func(): host.twenty_selection.reverse(); host.refresh(),host.twenty_selection.size() == 2)
	# The exact expression stays on each physical result tag. No automatic strategy hint.
	if host.twenty_selection.is_empty() and tokens.size() > 1:
		host.text("① 先放一枚符牌",Rect2(496,430,155,30),18,false)
		host.text("② 再放一枚符牌",Rect2(740,430,155,30),18,false)

static func select(host: Control, index: int) -> void:
	if index in host.twenty_selection: host.twenty_selection.erase(index)
	else:
		if host.twenty_selection.size() == 2: host.twenty_selection.clear()
		host.twenty_selection.append(index)
	host.sound.play_cue("pickup"); host.refresh()

static func calculate(host: Control, op: String) -> void:
	if host.twenty_selection.size() != 2: return
	var action = {"kind":"combine","left":host.twenty_selection[0],"right":host.twenty_selection[1],"op":op}
	host.twenty_selection.clear(); host.rule(action)

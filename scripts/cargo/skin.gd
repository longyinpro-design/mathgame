extends RefCounted
const INK = Color("f1e5ca")
const GOLD = Color("d7bd83")
const MINT = Color("ccceb0")
const DARK = Color("3c3a2a")
const FONT_PATH = "res://assets/fonts/ZCOOLKuaiLe-Regular.ttf"
const PAPER_PANEL = preload("res://assets/runtime/forest/ui/panel-paper.png")
const BUTTON_STATES = {
	"normal": preload("res://assets/runtime/forest/ui/button-teal-small.png"),
	"hover": preload("res://assets/runtime/forest/ui/button-teal-bright-small.png"),
	"pressed": preload("res://assets/runtime/forest/ui/button-teal-dark-small.png"),
	"disabled": preload("res://assets/runtime/forest/ui/button-gray-small.png"),
}
const PRIMARY_STATES = {
	"normal": preload("res://assets/runtime/forest/ui/button-gold-small.png"),
	"hover": preload("res://assets/runtime/forest/ui/button-gold-bright-small.png"),
	"pressed": preload("res://assets/runtime/forest/ui/button-gold-small.png"),
	"disabled": preload("res://assets/runtime/forest/ui/button-gray-small.png"),
}
static func face() -> FontFile:
	var font: FontFile = load(FONT_PATH)
	font.allow_system_fallback = false
	font.fallbacks = [load("res://assets/fonts/NotoSansSC.ttf")]
	return font
static func text_size(requested: int) -> int:
	return 28 if requested >= 24 else 22 if requested >= 18 else 18
static func make() -> Theme:
	var result = Theme.new()
	result.default_font = face()
	result.default_font_size = 22
	result.set_color("font_color","Label",INK)
	result.set_constant("line_spacing","Label",5)
	return result
static func plank() -> AtlasTexture:
	var texture = AtlasTexture.new()
	texture.atlas = load("res://assets/runtime/cargo-props-v5.png")
	texture.region = Rect2(140,196,302,28)
	return texture
static func text(parent: Node, value: String, rect: Rect2, size_px: int = 18, color: Color = INK) -> Label:
	var label = Label.new(); label.text = value; label.position = rect.position; label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",text_size(size_px)); label.add_theme_color_override("font_color",color)
	label.add_theme_font_override("font",face())
	if color != DARK:
		label.add_theme_color_override("font_shadow_color",Color(0.035,0.06,0.035,0.65))
		label.add_theme_constant_override("shadow_offset_x",0); label.add_theme_constant_override("shadow_offset_y",1)
	parent.add_child(label); return label
static func paper_style() -> StyleBoxTexture:
	var s = StyleBoxTexture.new(); s.texture = PAPER_PANEL
	s.texture_margin_left = 36; s.texture_margin_right = 36; s.texture_margin_top = 30; s.texture_margin_bottom = 32
	s.content_margin_left = 30; s.content_margin_right = 30; s.content_margin_top = 24; s.content_margin_bottom = 22
	return s
static func dark_style() -> StyleBoxFlat:
	# Machine housing: deep moss-green wood with a brass double border.
	var s = StyleBoxFlat.new(); s.bg_color = Color("27301f")
	s.set_corner_radius_all(8)
	s.set_border_width_all(2); s.border_color = Color("93763d")
	s.shadow_color = Color(0.03,0.055,0.03,0.5); s.shadow_size = 7; s.shadow_offset = Vector2(0,4)
	return s
static func sign_style() -> StyleBoxFlat:
	# In-world wooden sign: warm walnut board with carved edge, replaces debug-black strips.
	var s = StyleBoxFlat.new(); s.bg_color = Color(0.157,0.118,0.075,0.94)
	s.set_corner_radius_all(7)
	s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 3
	s.border_color = Color(0.58,0.45,0.26,0.95)
	s.shadow_color = Color(0.02,0.04,0.02,0.45); s.shadow_size = 4; s.shadow_offset = Vector2(0,3)
	s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 7; s.content_margin_bottom = 9
	return s
static func panel(parent: Node, rect: Rect2, paper: bool = false) -> Panel:
	var p = Panel.new(); p.position = rect.position; p.size = rect.size; p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",paper_style() if paper else dark_style()); parent.add_child(p); return p
static func sign(parent: Node, rect: Rect2) -> Panel:
	# A wooden sign board placed over the scene; text goes on top by the caller.
	var p = Panel.new(); p.position = rect.position; p.size = rect.size; p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",sign_style()); parent.add_child(p); return p
static func _state_box(texture: Texture2D) -> StyleBoxTexture:
	var s = StyleBoxTexture.new(); s.texture = texture
	s.texture_margin_left = 13; s.texture_margin_right = 13; s.texture_margin_top = 11; s.texture_margin_bottom = 12
	# Content margins keep the button's minimum size equal to the old plank look,
	# so every existing 32–40px button keeps its designed rect.
	s.content_margin_left = 6; s.content_margin_right = 6; s.content_margin_top = 2; s.content_margin_bottom = 3
	return s
static func style_button(b: Button, primary: bool = false) -> void:
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size",20)
	b.add_theme_font_override("font",face())
	var states = PRIMARY_STATES if primary else BUTTON_STATES
	for key in ["normal","hover","pressed","disabled"]:
		var s = _state_box(states[key])
		if key == "pressed" and primary: s.modulate_color = Color(0.85,0.8,0.7)
		b.add_theme_stylebox_override(key,s)
	var focus = StyleBoxFlat.new(); focus.bg_color = Color.TRANSPARENT; focus.set_border_width_all(2); focus.border_color = GOLD
	focus.set_corner_radius_all(6)
	b.add_theme_stylebox_override("focus",focus)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: b.add_theme_color_override(key,INK)
	b.add_theme_color_override("font_disabled_color",Color("6e6a58"))
	b.add_theme_color_override("font_outline_color",Color("28291e")); b.add_theme_constant_override("outline_size",0)
static func button(parent: Node, value: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var b = Button.new(); b.text = value; b.position = rect.position; b.size = rect.size
	style_button(b,primary); b.pressed.connect(action); parent.add_child(b)
	return b
static func hotspot(b: Button, label: String) -> void:
	b.text = ""; b.tooltip_text = label
	for key in ["normal","hover","pressed","disabled"]: b.add_theme_stylebox_override(key,StyleBoxEmpty.new())
	# 悬停原本四态全空，玩家把鼠标移到一壶油上什么也不会变，只有光标变手型——
	# 对不认字的小孩来说「这个能点」这件事根本没被说出来。只描一圈细金边，
	# 不填充，免得在像素场景上盖出一块调试框。
	var hover = StyleBoxFlat.new(); hover.bg_color = Color.TRANSPARENT
	hover.set_border_width_all(2); hover.border_color = Color(1.0,0.87,0.58,0.72)
	hover.set_corner_radius_all(7)
	b.add_theme_stylebox_override("hover",hover)
	var pressed = StyleBoxFlat.new(); pressed.bg_color = Color(1.0,0.87,0.58,0.14)
	pressed.set_border_width_all(2); pressed.border_color = Color(1.0,0.82,0.45,0.95)
	pressed.set_corner_radius_all(7)
	b.add_theme_stylebox_override("pressed",pressed)
# 热点自身是隐形按钮，它的中文说明全靠 tooltip。默认主题下 tooltip 用系统字体、灰色无底框，
# 会直接压在石板和货签上；这里把它收进关卡同一块胡桃木牌里，字体也换成 UI 正在用的那一份。
static func tooltip_style() -> StyleBoxFlat:
	var s = sign_style()
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 8; s.content_margin_bottom = 10
	return s
static func tooltip_theme() -> Theme:
	var t = Theme.new()
	var font = face()
	t.default_font = font; t.default_font_size = 18
	t.set_stylebox("panel", "Tooltip", tooltip_style())
	t.set_font("font", "TooltipLabel", font)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_color("font_color", "TooltipLabel", Color("fff0d1"))
	t.set_color("font_outline_color", "TooltipLabel", Color("382515"))
	t.set_constant("outline_size", "TooltipLabel", 3)
	return t


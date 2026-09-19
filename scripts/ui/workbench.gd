extends Node2D
const Style = preload("res://scripts/cargo/skin.gd")
var family = ""
static func mount(host: Node, kind: String) -> void:
	var sheet = load("res://scripts/ui/workbench.gd").new()
	sheet.family = kind; host.add_child(sheet)
func _draw() -> void:
	# Explicit close inspection of a record/map; no legs, rails or replacement floor.
	var paper = StyleBoxFlat.new(); paper.bg_color = Color("e0d4b5")
	paper.set_border_width_all(3); paper.border_color = Color("8c805f")
	paper.shadow_color = Color(0.02,0.04,0.03,0.45); paper.shadow_size = 10
	draw_style_box(paper,Rect2(48,159,1184,420))

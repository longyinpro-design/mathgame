extends SceneTree
const GAME = preload("res://game/treetop.tscn")
const Style = preload("res://scripts/cargo/skin.gd")
var problems: Array[String] = []
var game: Control
var labels_checked = 0
func _initialize() -> void: call_deferred("run")
func inspect(node: Node) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Label and not node.text.is_empty():
		labels_checked += 1
		if node.get_line_count() > node.get_visible_line_count(): problems.append("Clipped label: "+node.text)
		if node.get_global_rect().end.x > 1281 or node.get_global_rect().end.y > 721: problems.append("Label beyond viewport: "+node.text)
	if node is Button and not node.text.is_empty():
		var font = node.get_theme_font("font"); var size_px = node.get_theme_font_size("font_size")
		var text_width = font.get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
		var margin = node.get_theme_stylebox("normal").get_minimum_size().x
		if text_width+margin > node.size.x+1: problems.append("Button text too wide: "+node.text)
	for child in node.get_children(): inspect(child)
func run() -> void:
	game = GAME.instantiate(); game.store.path = "/tmp/font-layout-%d.json" % OS.get_process_id(); root.add_child(game)
	await process_frame; inspect(game.ui)
	game.show_cargo(); await process_frame; inspect(game.ui)
	# The longest actual help path must fit its dynamically sized speech bubble.
	game.hint(); game.hint(); game.store.state.cargo.places = [0,0,0,0,0,0]; game.hint()
	await process_frame; inspect(game.ui)
	var recovery = game.message.text
	var height = game.message.get_line_height()*game.message.get_line_count()
	if game.message.size.y < height: problems.append("Long recovery hint exceeds speech bubble")
	game.confirm_reset(); await process_frame; inspect(game.overlay); game.close_modal()
	game.show_journal(); await process_frame; inspect(game.ui)
	game.show_settings(); await process_frame; inspect(game.ui)
	var own = FontFile.new(); own.load_dynamic_font(Style.FONT_PATH); own.allow_system_fallback = false
	var characters = {}
	for script in ["scripts/cargo/journey.gd","scripts/cargo/world.gd","scripts/cargo/store.gd","scripts/cargo/rules.gd","scripts/encounter/encounter.gd"]:
		for c in FileAccess.get_file_as_string("res://"+script):
			var code = c.unicode_at(0)
			if code >= 0x4e00 and code <= 0x9fff: characters[c] = true
	for c in characters:
		if not own.has_char(c.unicode_at(0)): problems.append("Missing primary Chinese glyph: "+c)
	for c in "0123456789":
		if not own.has_char(c.unicode_at(0)): problems.append("Missing digit: "+c)
	print("Typography: %d labels, %d primary Chinese glyphs, long help and button widths" % [labels_checked,characters.size()])
	for problem in problems: push_error(problem)
	game.queue_free(); await create_timer(0.3).timeout
	DirAccess.remove_absolute("/tmp/font-layout-%d.json" % OS.get_process_id())
	print("TYPOGRAPHY PASS" if problems.is_empty() else "TYPOGRAPHY FAIL")
	quit(0 if problems.is_empty() else 1)

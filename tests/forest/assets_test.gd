extends SceneTree
const Actor = preload("res://scripts/ui/companion_actor.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/runtime/forest/actors.json"))
	for id in ["hero","acheng","mossling","feather"]:
		check(data.has(id),"registered actor "+id)
		if not data.has(id): continue
		var record: Dictionary = data[id]
		check(FileAccess.get_sha256(record.path) == record.sha256,"source hash "+id)
		var image = Image.new(); var decode_error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(record.path))
		check(decode_error == OK,"PNG decodes "+id)
		check(image != null and image.get_format() == Image.FORMAT_RGBA8,"actual RGBA "+id)
		if image == null: continue
		check(record.frames.size() == 24,"24 measured frames "+id)
		check(record.alpha_zero_pixels > image.get_width()*image.get_height()*0.3,"substantial genuine transparency "+id)
		for frame in record.frames:
			var r: Array = frame.region; var pivot: Array = frame.pivot
			check(r[0] >= 0 and r[1] >= 0 and r[2] > 0 and r[3] > 0 and r[0]+r[2] <= image.get_width() and r[1]+r[3] <= image.get_height(),"atlas bounds "+id)
			check(pivot[0] >= 0 and pivot[0] <= r[2] and pivot[1] > 0 and pivot[1] <= r[3]+80,"ground pivot including authored hop "+id)
	var npcs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/runtime/forest/npcs.json"))
	check(FileAccess.get_sha256(npcs.path) == npcs.sha256,"NPC source hash")
	for region in ["treetop","village","mill"]:
		check(npcs.frames[region].size() == 3,"three daily NPC frames "+region)
		for frame in npcs.frames[region]:
			var r: Array = frame.region
			check(r[0] >= 0 and r[1] >= 0 and r[0]+r[2] <= npcs.size[0] and r[1]+r[3] <= npcs.size[1],"NPC measured atlas bounds "+region)
	var font = UIStyle.face(); var characters = {}
	for path in ["res://scripts/ui/forest_release.gd","res://scripts/ui/puzzle_boards.gd","res://scripts/ui/route_boards.gd","res://scripts/ui/side_boards.gd","res://scripts/ui/battle_boards.gd","res://scripts/content/story_catalog.gd"]:
		var source = FileAccess.get_file_as_string(path)
		for i in source.length():
			var code = source.unicode_at(i)
			if code >= 0x3400 and code <= 0x9fff: characters[code] = true
	for code in characters: check(font.has_char(code),"font coverage "+String.chr(code))
	print("FOREST ASSETS ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)

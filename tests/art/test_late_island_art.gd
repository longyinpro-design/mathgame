extends SceneTree
const Art = preload("res://scripts/ui/late_island_art.gd")
var checks = 0
var failures: Array = []
func require(value: bool, note: String):
	checks += 1
	if not value: failures.append(note); push_error(note)
func _init():
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://art/late-islands-v1/manifest.json"))
	require(Art.BACKGROUNDS.size() == 3,"three generated island backgrounds")
	require(Art.PARTS.size() == 18,"twelve cast poses and six material surfaces")
	for island in ["GV","FW","SO"]:
		var texture: Texture2D = Art.BACKGROUNDS[island]
		require(texture.get_width() >= 1280 and texture.get_height() >= 720,island+" full-size backdrop")
		require(manifest.islands[island].levels.size() == 18,island+" maps every level")
		for id in manifest.islands[island].levels:
			var family = "geometry" if island == "GV" else "fractions" if island == "FW" else "observatory"
			require(ResourceLoader.exists("res://game/%s_%s.tscn"%[family,id.to_lower()]),id+" has actual scene")
	for id in Art.PARTS:
		var texture: AtlasTexture = Art.PARTS[id]
		require(texture.filter_clip,id+" clips sampling to measured region")
		require(Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region),id+" region inside source")
		var r = manifest.sprites[id].region
		require(texture.region == Rect2(r[0],r[1],r[2],r[3]),id+" manifest matches runtime atlas")
		if not id.ends_with("_panel") and not id.ends_with("_tile"):
			var source = Image.new()
			var loaded = source.load_png_from_buffer(FileAccess.get_file_as_bytes(texture.atlas.resource_path))
			require(loaded == OK and source.detect_alpha() != Image.ALPHA_NONE,id+" transparent cast source")
	print("LATE ISLAND ART: %d checks, %d failures"%[checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)

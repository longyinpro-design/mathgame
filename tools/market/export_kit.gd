extends SceneTree
# Deterministic export of authored AtlasTexture regions; never repaints source art.
const MANIFEST = "res://art/market-kit-v1/manifest.json"
func _initialize() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var count = 0
	for item in data.sprites:
		var source = Image.load_from_file("res://"+item.source)
		var r = item.source_rect
		var region = Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))
		if source == null or not Rect2i(Vector2i.ZERO,source.get_size()).encloses(region):
			push_error("Invalid source region: "+item.id); quit(1); return
		var output = "res://"+item.png
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		if source.get_region(region).save_png(output) != OK: quit(1); return
		var atlas_path = "res://"+item.atlas
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(atlas_path.get_base_dir()))
		var file = FileAccess.open(atlas_path,FileAccess.WRITE)
		if file == null: quit(1); return
		file.store_string('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n[ext_resource type="Texture2D" path="res://%s" id="1"]\n\n[resource]\natlas = ExtResource("1")\nregion = Rect2(%d, %d, %d, %d)\nfilter_clip = true\n'%[item.source,region.position.x,region.position.y,region.size.x,region.size.y])
		file.close(); count += 1
	print("MARKET KIT EXPORT ",count,"/",data.sprites.size()," PASS")
	quit()

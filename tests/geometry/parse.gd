extends SceneTree
const C=preload("res://scripts/geometry/catalog.gd")
const R=preload("res://scripts/geometry/rules.gd")
func _initialize():
	for id in C.ids():
		var r=R.new(C.definition(id)); assert(r.validate(r.fresh()),id)
	print("Geometry18 fresh states validated")
	quit()

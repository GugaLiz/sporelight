class_name ChapterSurfaceMaterials
extends RefCounted

const Terrace = preload("res://presentation/native/terrace_materials.gd")
const Surfaces = preload("res://elements/surface_definitions.gd")

## Original garden2/scenery.ts terrainSurface policy, for painted chapters.
## Materials only; never changes support, visibility or puzzle state.
static func paving_for(level: Dictionary,tile: Dictionary) -> String:
	return Surfaces.paving_for(level,tile)

## Reuse the approved tread/riser/side shading with each chapter's own paint.
static func create(chapter: String, texture: Callable, solid: Callable, connector: bool = false) -> Dictionary:
	if chapter == "cloud":
		# Original cloud architecture is cream stone, independent of the main
		# valley's painted paving. Keep the native tread/collision descriptors.
		var top: StandardMaterial3D = solid.call(Color("faf5e9"))
		var side: StandardMaterial3D = solid.call(Color("d4d3bf"))
		var tread: StandardMaterial3D = solid.call(Color("efe6d3"))
		var grid := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		grid.fill(Color("faf5e9"))
		for edge in [Rect2i(0,0,128,1), Rect2i(0,127,128,1), Rect2i(0,0,1,128), Rect2i(127,0,1,128)]: grid.fill_rect(edge, Color("fffdf6"))
		top.albedo_texture = ImageTexture.create_from_image(grid)
		top.albedo_color = Color.WHITE
		for material: StandardMaterial3D in [top, side, tread]: material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return {"top": top, "side": side, "ramp": tread, "riser": side, "trim": tread,
			"key": "original_cloud_cream" + ("_connector" if connector else ""),
			"authored_terrace": false, "generic_stairs": true, "terrain_profile": null}
	var paving := str(Surfaces.theme(chapter).terrainTop)
	var key := "terrain_" + chapter + "_true_stairs" + ("_connector" if connector else "")
	var values := Terrace.create(Surfaces.material_spec(chapter,paving,connector,key), null, texture, solid)
	values.authored_terrace = false
	values.generic_stairs = true
	return values

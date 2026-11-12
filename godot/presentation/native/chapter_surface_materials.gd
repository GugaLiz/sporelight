class_name ChapterSurfaceMaterials
extends RefCounted

const Terrace = preload("res://presentation/native/terrace_materials.gd")

## Original garden2/scenery.ts terrainSurface policy, for painted chapters.
## Materials only; never changes support, visibility or puzzle state.
static func paving_for(level: Dictionary,tile: Dictionary) -> String:
	var chapter := str(level.get("chapter","valley"))
	var stone := "paving-pond" if chapter=="pond" else "paving-valley"
	if str(tile.get("kind","")) in ["water","module","shadow"]: return stone
	if bool(tile.get("small",false)) or str(tile.get("kind",""))=="root": return "paving-grass"
	for mark: Dictionary in level.get("marks",[]):
		if str(mark.get("tile",""))==str(tile.get("id","")) and not str(mark.get("kind","")) in ["rest","observe"]: return stone
	var index := str(level.get("id","0-0")).get_slice("-",1).to_int()
	var patch := posmod(int(floor((float(tile.x)+30)/2))*3+int(floor((float(tile.z)+30)/2))*5+index,8)
	if patch<(3 if chapter=="valley" else 1): return "paving-grass"
	return "paving-moss" if patch<5 else stone

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
	var paving := "paving-pond" if chapter == "pond" else "paving-moss" if chapter == "cave" else "paving-valley"
	var key := "terrain_" + chapter + "_true_stairs" + ("_connector" if connector else "")
	var masonry := "masonry-pond" if chapter == "pond" else "wall-left" if chapter == "cave" else "masonry-valley"
	var right := "wall-right" if chapter == "cave" else masonry
	var wash := Color("76a9a8") if chapter == "pond" else Color("b4b894")
	var values := Terrace.create({"paving": paving, "connector": connector, "key": key, "wall_art": masonry, "wall_art_right": right, "wall_wash": wash}, null, texture, solid)
	for name: String in ["side", "ramp", "riser"]:
		values[name].set_shader_parameter("original_stone", texture.call(paving))
	values.authored_terrace = false
	values.generic_stairs = true
	return values

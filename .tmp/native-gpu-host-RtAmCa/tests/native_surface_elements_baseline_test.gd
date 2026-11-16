extends SceneTree
## Frozen before extracting the shared surface catalog. --record is a deliberate
## baseline authoring operation, never part of normal validation or export.
const World = preload("res://core/garden_world.gd")
const First = preload("res://presentation/native/first_garden_profile.gd")
const Second = preload("res://presentation/native/second_garden_profile.gd")
const Chapter = preload("res://presentation/native/chapter_surface_materials.gd")
const Terrace = preload("res://presentation/native/terrace_materials.gd")
const Fixture := "res://tests/fixtures/surface_elements_baseline.json"
var textures := {}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _texture(alias: String) -> Texture2D:
	if not textures.has(alias):
		var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var texture := ImageTexture.create_from_image(image)
		texture.set_meta("test_alias",alias)
		textures[alias] = texture
	return textures[alias]

func _solid(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	return result

func _alias(texture: Texture2D) -> String:
	return str(texture.get_meta("test_alias","")) if texture != null else ""

func _values(level: Dictionary, tile: Dictionary) -> Dictionary:
	var profile: Script = First if level.id=="1-1" else Second if level.id=="1-2" else null
	var spec: Dictionary = profile.material_spec(tile) if profile != null else {}
	var materials: Dictionary = Terrace.create(spec,profile,_texture,_solid) if profile != null else Chapter.create(level.chapter,_texture,_solid)
	var paving: String = str(spec.paving) if profile != null else Chapter.paving_for(level,tile)
	var base_height: float = profile.base_height(tile) if profile != null and profile.has_method("base_height") else float(tile.h)*.65
	var center := Vector3(float(tile.x),base_height,float(tile.z))
	var physical: Vector3 = profile.to_physical(center) if profile != null else center
	var scale: Vector3 = profile.tile_scale(float(tile.x)) if profile != null else Vector3.ONE
	var geometry: Array = []
	for offset: Vector2 in [Vector2.ZERO,Vector2(.23,.14),Vector2(-.19,-.22)]:
		geometry.append(profile.height(Vector2(tile.x,tile.z)+offset) if profile != null else base_height)
	var side: ShaderMaterial = materials.side
	var tread: ShaderMaterial = materials.ramp
	var riser: ShaderMaterial = materials.riser
	var density: Vector2 = side.get_shader_parameter("wall_pixels_per_unit")
	var tint: Color = side.get_shader_parameter("wall_wash")
	return {"paving":paving,"wallLeft":_alias(side.get_shader_parameter("wall_art")),"wallRight":_alias(side.get_shader_parameter("wall_art_right")),"sideGrain":_alias(side.get_shader_parameter("original_stone")),"stairPaint":_alias(tread.get_shader_parameter("original_stair")),"stairGrain":_alias(tread.get_shader_parameter("original_stone")),"riserPaint":_alias(riser.get_shader_parameter("original_stair")),"density":[density.x,density.y],"wash":tint.to_html(),"connector":bool(tread.get_shader_parameter("connector")),"faceRepeat":float(tread.get_shader_parameter("face_repeat")),"topScale":[materials.top.uv1_scale.x,materials.top.uv1_scale.y,materials.top.uv1_scale.z],"center":[physical.x,physical.y,physical.z],"tileScale":[scale.x,scale.y,scale.z],"heightSamples":geometry}

func _collect(world: RefCounted, cases: Dictionary) -> void:
	var level: Dictionary = world.level
	if not cases.has(level.id): cases[level.id] = {}
	for tile: Dictionary in world.tiles():
		var key := JSON.stringify([tile.id,tile.x,tile.z,tile.h,tile.get("kind","fixed"),tile.get("small",false)])
		if cases[level.id].has(key): continue
		cases[level.id][key] = {"tile":tile.duplicate(true),"values":_values(level,tile)}

func _same(left: Variant, right: Variant) -> bool:
	if left is float or left is int:
		return (right is float or right is int) and absf(float(left)-float(right))<.00001
	if typeof(left)!=typeof(right): return false
	if left is Dictionary:
		if left.size()!=right.size(): return false
		for key: Variant in left:
			if not right.has(key) or not _same(left[key],right[key]): return false
		return true
	if left is Array:
		if left.size()!=right.size(): return false
		for i: int in left.size():
			if not _same(left[i],right[i]): return false
		return true
	return left==right

func _run() -> void:
	var cases := {}
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	for level: Dictionary in levels: _collect(World.new(level.id),cases)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in reference.cases:
		if not str(entry.name).begins_with("authored/"): continue
		var id: String = str(entry.name).trim_prefix("authored/")
		if not cases.has(id): continue
		for step: Dictionary in entry.steps: _collect(World.new(id,step.snapshot),cases)
	if "--record" in OS.get_cmdline_user_args():
		FileAccess.open(Fixture,FileAccess.WRITE).store_string(JSON.stringify({"schemaVersion":1,"purpose":"Pre-extraction mainline surface/material/physical-profile outputs; captured from current restored gameplay before catalog implementation.","levels":cases},"  ")+"\n")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Fixture))
	_check(cases.size()==12 and fixture.levels.size()==12,"all twelve mainline levels covered")
	for id: String in cases:
		_check(cases[id].size()==fixture.levels[id].size(),id+" unchanged surface state coverage")
		for key: String in cases[id]:
			_check(fixture.levels[id].has(key),id+" authored surface remains present "+key)
			if fixture.levels[id].has(key): _check(_same(cases[id][key],fixture.levels[id][key]),id+" material and geometry unchanged "+key)
	print(JSON.stringify({"suite":"surface-elements-baseline","checks":checks,"passed":failures.is_empty(),"failures":failures,"levelSurfaceStates":cases.keys().map(func(id: String)->Dictionary:return {"level":id,"states":cases[id].size()})}))
	quit(0 if failures.is_empty() else 1)

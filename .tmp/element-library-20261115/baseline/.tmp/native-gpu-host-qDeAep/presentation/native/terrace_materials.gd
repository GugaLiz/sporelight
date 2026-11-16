class_name TerraceMaterials
extends RefCounted

const IslandStoneShader = preload("res://presentation/native/garden_island_stone.gdshader")
const StairShader = preload("res://presentation/native/garden_stair.gdshader")

## The stage owns caching and texture lifetime; this factory owns face materials.
static func create(spec: Dictionary, profile: Script, texture: Callable, solid: Callable) -> Dictionary:
	var connector := bool(spec.connector)
	var top: StandardMaterial3D = solid.call(Color.WHITE)
	top.albedo_texture = texture.call(str(spec.paving))
	top.uv1_scale = spec.get("top_scale", Vector3.ONE)
	# Walls use the original vertical masonry painting in full. Cropping a
	# paving stone and inventing new brick joints loses its aged wall texture.
	var side := ShaderMaterial.new()
	side.shader = IslandStoneShader
	side.set_shader_parameter("original_stone", texture.call("paving-valley"))
	side.set_shader_parameter("wall_art", texture.call(str(spec.get("wall_art", "masonry-valley"))))
	side.set_shader_parameter("wall_art_right", texture.call(str(spec.get("wall_art_right", spec.get("wall_art", "masonry-valley")))))
	side.set_shader_parameter("wall_wash", spec.get("wall_wash", Color("b4b894")))
	side.set_shader_parameter("wall_pixels_per_unit", Vector2(70.0, 48.0 / 0.65))
	side.set_shader_parameter("stair_side", connector)
	# Sample original painted stone faces. UVs restart on every physical tread;
	# do not stretch an isometric stair picture across a flat incline.
	var ramp := ShaderMaterial.new()
	ramp.shader = StairShader
	ramp.set_shader_parameter("original_stair", texture.call("stairs"))
	ramp.set_shader_parameter("original_stone", texture.call("paving-valley"))
	ramp.set_shader_parameter("connector", connector)
	ramp.set_shader_parameter("face_repeat", float(spec.get("face_repeat", 1.0)))
	var riser := ShaderMaterial.new()
	riser.shader = StairShader
	riser.set_shader_parameter("original_stair", texture.call("stairs"))
	riser.set_shader_parameter("original_stone", texture.call("paving-valley"))
	riser.set_shader_parameter("riser", true)
	riser.set_shader_parameter("connector", connector)
	riser.set_shader_parameter("face_repeat", float(spec.get("face_repeat", 1.0)))
	var values := {"top": top, "side": side, "ramp": ramp, "riser": riser, "trim": side, "key": spec.key, "authored_terrace": true, "terrain_profile": profile}
	return values

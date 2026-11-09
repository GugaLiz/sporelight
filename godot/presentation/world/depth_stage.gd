class_name GardenDepthStage
extends SubViewport

const Target = preload("res://presentation/world/depth_paint_target.gd")
const PIXELS_PER_UNIT := 49.49747468305833
const CAMERA_RIGHT := Vector3(0.7071067811865476, 0.0, -0.7071067811865476)
const CAMERA_UP := Vector3(-0.3535533905932738, 0.8660254037844386, -0.3535533905932738)
const CAMERA_RAY := Vector3(0.6123724356957945, 0.5, 0.6123724356957945)
const SURFACES_PER_MESH := 128

var paint_target := Target.new()
var camera := Camera3D.new()
var _root := Node3D.new()
var _instances: Array[MeshInstance3D] = []
var _static_instances: Array[MeshInstance3D] = []
var _materials: Dictionary = {}
var _static_signature := 0
var _pending_static_signature := 0
var _static_valid := false
var _building_static := false
var _static_stats := {"staticCalls": 0, "staticTriangles": 0, "staticBatches": 0, "staticInstances": 0}
var last_frame := {"calls": 0, "triangles": 0, "batches": 0, "instances": 0, "staticCalls": 0, "staticTriangles": 0, "staticBatches": 0, "staticInstances": 0}

func _init() -> void:
	name = "GardenDepthStage"
	size = Vector2i(1, 1)
	transparent_bg = true
	own_world_3d = true
	world_3d = World3D.new()
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_4X
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = false
	environment.fog_enabled = false
	world_3d.environment = environment
	add_child(_root)
	_root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.01
	camera.far = 400.0
	camera.current = true

func setup_size(dimensions: Vector2, origin: Vector2, scale_factor: float) -> void:
	size = Vector2i(maxi(1, int(round(dimensions.x))), maxi(1, int(round(dimensions.y))))
	var density := PIXELS_PER_UNIT * maxf(0.00001, scale_factor)
	var center := Vector2(size) * 0.5
	var focus := CAMERA_RIGHT * ((center.x - origin.x) / density) + CAMERA_UP * ((origin.y - center.y) / density)
	camera.size = float(size.y) / density
	camera.position = focus + CAMERA_RAY * 100.0
	if camera.is_inside_tree():
		camera.look_at(focus, Vector3.UP)
	else:
		camera.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(45.0), 0.0)
	paint_target.configure(origin, scale_factor)

func begin_frame() -> void:
	paint_target.begin_frame()

## Cached vertices are real world geometry. Resizing or moving the camera does
## not invalidate them; the caller's signature covers visible scene structure.
func begin_static(signature: int) -> bool:
	if _static_valid and signature == _static_signature:
		return false
	_pending_static_signature = signature
	_building_static = true
	paint_target.begin_frame()
	return true

func end_static() -> void:
	if not _building_static:
		return
	var count := _submit(paint_target.batches, _static_instances)
	_static_stats = {"staticCalls": paint_target.calls, "staticTriangles": paint_target.triangles, "staticBatches": paint_target.batches.size(), "staticInstances": count}
	_static_signature = _pending_static_signature
	_static_valid = true
	_building_static = false
	last_frame.merge(_static_stats, true)

func invalidate_static() -> void:
	_static_valid = false
	_building_static = false
	for instance in _static_instances:
		instance.visible = false
		instance.mesh = null
	_static_stats = {"staticCalls": 0, "staticTriangles": 0, "staticBatches": 0, "staticInstances": 0}
	last_frame.merge(_static_stats, true)

func end_frame() -> void:
	var batches: Array = paint_target.batches
	var required := _submit(batches, _instances)
	last_frame = {"calls": paint_target.calls, "triangles": paint_target.triangles, "batches": batches.size(), "instances": required}
	last_frame.merge(_static_stats, true)

func _submit(batches: Array, instances: Array[MeshInstance3D]) -> int:
	var required := int(ceil(batches.size() / float(SURFACES_PER_MESH)))
	while instances.size() < required:
		var instance := MeshInstance3D.new()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(instance)
		instances.append(instance)
	for chunk in range(instances.size()):
		var instance := instances[chunk]
		instance.visible = chunk < required
		if chunk >= required:
			instance.mesh = null
			continue
		var mesh := ArrayMesh.new()
		for index in range(chunk * SURFACES_PER_MESH, mini(batches.size(), (chunk + 1) * SURFACES_PER_MESH)):
			var batch: Dictionary = batches[index]
			if batch.indices.is_empty():
				continue
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = batch.vertices
			arrays[Mesh.ARRAY_COLOR] = batch.colors
			arrays[Mesh.ARRAY_TEX_UV] = batch.uvs
			arrays[Mesh.ARRAY_INDEX] = batch.indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material(batch))
		instance.mesh = mesh
	return required

func _material(batch: Dictionary) -> StandardMaterial3D:
	var key := str(batch.key)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.albedo_color = Color.WHITE
	material.albedo_texture = batch.texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.texture_repeat = true
	material.render_priority = int(batch.get("priority", 0)) if batch.transparent else 0
	# Native alpha depth pre-pass rejects fully transparent texels and writes
	# depth for opaque sprite interiors. Soft texture edges/gradients keep alpha
	# blending; no render_priority override can place them through solid walls.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if batch.transparent else BaseMaterial3D.TRANSPARENCY_DISABLED
	_materials[key] = material
	return material

extends SceneTree
## Headless calibration and recorder contracts. These checks inspect geometry,
## Camera3D projection and material configuration, never rendered GPU pixels.

const Stage = preload("res://presentation/world/depth_stage.gd")
const Target = preload("res://presentation/world/depth_paint_target.gd")
const Iso = preload("res://presentation/world/iso_projection.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")

class CountingTexture:
	extends Texture2D
	var image_reads := 0
	var source := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	func _init() -> void:
		source.fill(Color.WHITE)
	func _get_width() -> int:
		return 2
	func _get_height() -> int:
		return 2
	func _has_alpha() -> bool:
		return true
	func _get_image() -> Image:
		image_reads += 1
		return source

var checks := 0
var failures: Array[String] = []
var output := ""
var logger := ErrorLogger.new()
var completed := false
var sections: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	create_timer(45).timeout.connect(func() -> void:
		if not completed:
			push_error("Native depth projection test timed out")
			quit(1))
	call_deferred("_run")

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.setup_size(Vector2(1280, 720), Vector2(566.15792, 363.72588), 1.29383313)
	await process_frame
	_core_projection(stage)
	_ramp_projection(stage)
	await _camera_frames(stage)
	_recording_api(stage)
	_material_contract(stage)
	_texture_classification(stage)
	_layer_budget(stage)
	_cache_budget(stage)
	await _object_bias_projection(stage)
	stage.queue_free()
	await process_frame
	failures.append_array(logger.captured_errors())
	completed = true
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var report := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
		_check(report != null, "report can be written")
		if report != null:
			report.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "sections": sections, "failures": failures, "engine": Engine.get_version_info().string, "display": DisplayServer.get_name(), "gpuVerified": false, "scope": "Headless screen/world/actual Camera3D calibration, Canvas-shaped recorder, bounded object depth bias across all paint planes, actual JPG/PNG source-alpha classification, material/transparent-priority properties and bounded reuse for a fixed persistent texture set. Does not prove PNG alpha depth behavior, transparent blending order, colors, antialiasing, occlusion or frame performance on a GPU. A changing unbounded stream of new texture identities is outside the cache-reuse claim."}, "\t") + "\n")
	if failures.is_empty():
		print("PASS native depth projection: %d checks (784 core round trips; three viewport sizes; recorder/material/layer/cache/object-bias contracts; GPU pixels not asserted)" % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 40:
		failures.append(message)

func _round_trip(stage, point: Dictionary, label: String) -> void:
	var target = stage.paint_target
	var screen: Vector2 = target.origin + Iso.raw(point) * target.scale_factor
	var world: Vector3 = target.screen_to_world(screen)
	_check(absf(world.x - float(point.x)) < 0.00001, label + " X inverse")
	_check(absf(world.z - float(point.z)) < 0.00001, label + " Z inverse")
	_check(absf(world.y - float(point.h) * float(target.WORLD_HEIGHT)) < 0.00001, label + " height inverse")
	_check(stage.camera.unproject_position(world).distance_to(screen) <= 0.002, label + " actual orthographic camera projection")

func _core_projection(stage) -> void:
	var started := checks
	var target = stage.paint_target
	for point in [{"x": -2.0, "z": 0.0, "h": 0.0}, {"x": 1.0, "z": 0.0, "h": 0.0}, {"x": 2.0, "z": 0.0, "h": 1.0}, {"x": 4.0, "z": -1.0, "h": 2.0}]:
		for plane in ["ground", "x", "z", "billboard"]:
			target.begin_object(point)
			if plane != "billboard":
				target.surface(plane, float(point.h) if plane == "ground" else float(point[plane]))
			_round_trip(stage, point, "reference " + plane)
	sections["referenceProjection"] = checks - started

func _ramp_projection(stage) -> void:
	var started := checks
	for scale in [0.55, 0.92, 1.4]:
		stage.setup_size(Vector2(1280, 720), Vector2(566.2, 363.7), scale)
		var target = stage.paint_target
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var low := {"x": -1.0, "z": 2.0, "h": 1.0}
			var high := {"x": float(low.x) + direction.x, "z": float(low.z) + direction.y, "h": 2.0}
			target.begin_object(low)
			target.ramp({"low": low, "high": high, "direction": direction, "rail_start": 0.2, "rail_end": 0.8})
			for u in [0.2, 0.35, 0.5, 0.65, 0.8]:
				for v in [-0.2, 0.0, 0.2]:
					var point := {"x": float(low.x) + direction.x * u - direction.y * v, "z": float(low.z) + direction.y * u + direction.x * v, "h": 1.0 + (u - 0.2) / 0.6}
					_round_trip(stage, point, "ramp " + str(direction))
	sections["rampProjection"] = checks - started

func _camera_frames(stage) -> void:
	var started := checks
	for framing in [[Vector2(1280, 720), Vector2(566.2, 363.7), 1.29383313], [Vector2(390, 844), Vector2(148.2, 422.0), 0.92], [Vector2(568, 320), Vector2(210.16, 160.0), 0.72]]:
		stage.setup_size(framing[0], framing[1], framing[2])
		await process_frame
		_check(stage.size == Vector2i(framing[0]), "actual SubViewport follows the new dimensions")
		_check(stage.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "camera remains orthographic after resize")
		_check(stage.camera.unproject_position(Vector3.ZERO).distance_to(framing[1]) <= 0.002, "zero world point projects to the requested origin")
		for progress in [0.0, 0.000001, 0.25, 0.5, 0.75, 0.999999, 1.0]:
			var point := {"x": 1.0 + progress, "z": 0.06, "h": progress}
			stage.begin_frame()
			stage.paint_target.begin_object(point)
			_round_trip(stage, point, "resized frame " + str(framing[0]))
			var at: Vector2 = framing[1] + Iso.raw(point) * float(framing[2])
			stage.paint_target.draw_colored_polygon(_quad(at), Color.WHITE)
			stage.end_frame()
			_check(stage.last_frame.instances == 1 and stage.last_frame.triangles == 2, "real camera frame submits a bounded mesh")
			await process_frame
	sections["cameraFrames"] = checks - started

func _quad(at := Vector2(500, 300)) -> PackedVector2Array:
	return PackedVector2Array([at, at + Vector2(12, 0), at + Vector2(12, 12), at + Vector2(0, 12)])

func _recording_api(stage) -> void:
	var started := checks
	stage.setup_size(Vector2(1280, 720), Vector2(566.2, 363.7), 1.0)
	stage.begin_frame()
	var target = stage.paint_target
	target.begin_object({"x": 1, "z": 0, "h": 0})
	target.surface("ground", 0.0)
	target.draw_colored_polygon(_quad(), Color.RED)
	target.draw_polygon(PackedVector2Array([Vector2(500, 300), Vector2(520, 300), Vector2(500, 320)]), PackedColorArray([Color.RED, Color.GREEN, Color.BLUE]))
	target.draw_primitive(PackedVector2Array([Vector2(450, 250)]), PackedColorArray([Color.WHITE]))
	target.draw_primitive(PackedVector2Array([Vector2(450, 250), Vector2(460, 260)]), PackedColorArray([Color.WHITE]))
	target.draw_primitive(PackedVector2Array([Vector2(450, 250), Vector2(460, 250), Vector2(450, 260)]), PackedColorArray([Color.WHITE]))
	target.draw_primitive(_quad(Vector2(450, 250)), PackedColorArray([Color.WHITE]))
	target.draw_polyline(PackedVector2Array([Vector2(450, 250), Vector2(460, 260), Vector2(450, 270)]), Color.WHITE, 2.0, true)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.set_pixel(0, 0, Color(1, 0, 0, 0))
	var texture := ImageTexture.create_from_image(image)
	target.billboard({"x": 1, "z": 0, "h": 0})
	target.draw_texture_rect(texture, Rect2(0, 0, 20, 30))
	target.draw_texture_rect(texture, Rect2(0, 0, 4, 6), true)
	target.draw_texture_rect(texture, Rect2(0, 0, 4, 6), true, Color.WHITE, true)
	var matrix := Transform2D(0.2, Vector2(430, 270)).scaled_local(Vector2(-1.5, 0.75))
	target.draw_set_transform_matrix(matrix)
	target.draw_texture_rect(texture, Rect2(0, 0, 20, 30), false, Color(1, 1, 1, 0.5))
	target.draw_set_transform_matrix(Transform2D.IDENTITY)
	_check(target.calls == 11 and target.triangles == 22, "polygon, all primitive lengths, line and texture APIs record the expected geometric workload")
	_check(target.batches.size() == 2, "same texture/color planes share batches instead of creating per-draw nodes")
	var batch: Dictionary = target.batches[1]
	_check(batch.texture == texture, "texture identity and original zero-alpha texel are retained")
	_check(texture.get_image().get_pixel(0, 0).a == 0.0, "transparent PNG-like texel remains transparent in source data")
	_check(batch.uvs[4] == Vector2.ZERO and batch.uvs[6] == Vector2(2, 3), "tiled texture UVs preserve repeat extents")
	_check(batch.uvs[10] == Vector2(3, 2), "transposed texture UVs preserve repeat extents")
	var expected := PackedVector2Array([Vector2.ZERO, Vector2(20, 0), Vector2(20, 30), Vector2(0, 30)])
	for index in range(4):
		var vertex: Vector3 = batch.vertices[12 + index]
		_check(stage.camera.unproject_position(vertex).distance_to(matrix * expected[index]) <= 0.002, "image target matrix is applied exactly once")
		_check(is_equal_approx(batch.colors[12 + index].a, 0.5), "modulate alpha survives recording")
	var before: int = target.calls
	target.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), PackedColorArray([Color.WHITE]))
	target.draw_texture_rect(null, Rect2(0, 0, 1, 1))
	target.draw_texture_rect(texture, Rect2())
	target.draw_polyline(PackedVector2Array([Vector2.ZERO]), Color.WHITE)
	_check(target.calls == before, "empty/invalid draw input produces no mesh workload")
	stage.end_frame()
	_check(stage.last_frame.instances == 1 and stage._instances[0].mesh.get_surface_count() == 2, "recorded batches submit to an actual ArrayMesh")
	for surface in range(stage._instances[0].mesh.get_surface_count()):
		var arrays: Array = stage._instances[0].mesh.surface_get_arrays(surface)
		_check(not arrays[Mesh.ARRAY_VERTEX].is_empty() and arrays[Mesh.ARRAY_VERTEX].size() == arrays[Mesh.ARRAY_COLOR].size(), "submitted geometry retains matching vertex/color attributes")
	sections["recordingAPI"] = checks - started

func _material_contract(stage) -> void:
	var started := checks
	_check(stage.transparent_bg and stage.own_world_3d, "depth stage uses an isolated transparent world")
	_check(stage.world_3d.environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "stage does not apply an artistic tonemap")
	for batch in stage.paint_target.batches:
		var material: StandardMaterial3D = stage._material(batch)
		_check(material == stage._material(batch), "same batch reuses its material")
		_check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and material.disable_fog, "source art avoids lighting/fog tint")
		_check(material.render_priority == 0 and not material.no_depth_test, "material keeps real depth testing without a priority override")
		_check(material.vertex_color_use_as_albedo and material.vertex_color_is_srgb, "source vertex colors retain their configured color-space interpretation")
		if batch.transparent:
			_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS, "texture material selects native alpha depth pre-pass; this is configuration evidence only")
			_check(material.albedo_texture == batch.texture, "zero-alpha source texture is not replaced by an opaque proxy")
		else:
			_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque solid geometry keeps the opaque depth path")
	sections["materialPropertiesOnly"] = checks - started

func _texture_classification(stage) -> void:
	var started := checks
	stage.begin_frame()
	var target = stage.paint_target
	var source_paths := ["res://assets/images/garden-scenery/masonry-valley.jpg", "res://assets/images/garden-scenery/paving-valley.jpg"]
	for path in source_paths:
		var jpeg: Texture2D = load(path)
		_check(jpeg != null and jpeg.get_image().detect_alpha() == Image.ALPHA_NONE, "actual authored masonry/paving JPEG has no effective alpha")
		target.begin_object({"x": 1, "z": 0, "h": 0}, 7)
		target.draw_texture_rect(jpeg, Rect2(0, 0, 12, 12))
		var opaque: Dictionary = target.batches[-1]
		_check(not opaque.transparent and opaque.priority == 0, "opaque JPEG ignores transparent priority and stays on the opaque depth path")
		var opaque_material: StandardMaterial3D = stage._material(opaque)
		_check(opaque_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and opaque_material.render_priority == 0, "actual opaque JPEG gets an opaque material without a priority override")
		target.draw_texture_rect(jpeg, Rect2(0, 0, 12, 12), false, Color(1, 1, 1, 0.5))
		var faded: Dictionary = target.batches[-1]
		_check(faded.transparent and faded.priority == 7 and faded.key != opaque.key, "modulate alpha moves the same JPEG into its separate transparent batch")
		var transparent_material: StandardMaterial3D = stage._material(faded)
		_check(transparent_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS and transparent_material.render_priority == 7 and not transparent_material.no_depth_test, "controlled transparent priority leaves native depth testing enabled")
	var flower: Texture2D = load("res://assets/images/production/flower.png")
	_check(flower != null and flower.get_image().detect_alpha() != Image.ALPHA_NONE, "actual flower PNG contains effective transparent texels")
	target.begin_object({"x": 1, "z": 0, "h": 0})
	target.draw_texture_rect(flower, Rect2(0, 0, 12, 12))
	_check(target.batches[-1].transparent and target.batches[-1].priority == 0, "actual transparent PNG retains the alpha depth path with default priority")
	var counted := CountingTexture.new()
	var before_reads := counted.image_reads
	var cached_size: int = target._texture_alpha_cache.size()
	for frame in range(4):
		target.begin_frame()
		target.begin_object({"x": 1, "z": 0, "h": 0})
		target.draw_texture_rect(counted, Rect2(0, 0, 12, 12))
		_check(not target.batches[0].transparent, "RGBA storage with every texel opaque does not force transparency")
		_check(counted.image_reads == before_reads + 1, "effective alpha image inspection occurs once across repeated frames")
		_check(target._texture_alpha_cache.size() == cached_size + 1, "alpha metadata cache remains bounded for a persistent texture identity")
	var dynamic_texture: Texture2D = stage.get_texture()
	var cached_before_viewport: int = target._texture_alpha_cache.size()
	target.begin_frame()
	target.begin_object({"x": 1, "z": 0, "h": 0}, 1)
	target.draw_texture_rect(dynamic_texture, Rect2(0, 0, 12, 12))
	_check(target.batches[0].transparent, "dynamic blend viewport is always treated as transparent without an image snapshot")
	_check(not target._texture_alpha_cache.has(dynamic_texture.get_instance_id()) and target._texture_alpha_cache.size() == cached_before_viewport, "dynamic viewport bypasses static alpha caching/readback")
	target.begin_object({"x": 1, "z": 0, "h": 0})
	target.draw_colored_polygon(_quad(), Color.WHITE)
	_check(target.batches[-1].priority == 0 and not target.batches[-1].transparent, "next default object cannot inherit the water effect's transparent priority")
	sections["effectiveSourceAlphaAndTransparentPriority"] = checks - started

func _layer_budget(stage) -> void:
	var started := checks
	stage.begin_frame()
	var target = stage.paint_target
	target.begin_object({"x": 1, "z": 0, "h": 0})
	target.surface("ground", 0.0)
	var polygon := _quad()
	for index in range(300):
		target.draw_colored_polygon(polygon, Color.WHITE)
	var batch: Dictionary = target.batches[0]
	var original: Vector3 = batch.vertices[0]
	var second: Vector3 = batch.vertices[4]
	var last: Vector3 = batch.vertices[(300 - 1) * 4]
	_check((second - original).dot(Stage.CAMERA_RAY) > 0.0, "later coplanar paint is infinitesimally closer")
	_check(last.distance_to(original) <= 0.00257, "coplanar layering remains within its capped world-depth budget")
	_check(stage.camera.unproject_position(last).distance_to(stage.camera.unproject_position(original)) <= 0.002, "layering does not move screen geometry")
	target.begin_object({"x": 1, "z": 0, "h": 0})
	target.surface("ground", 0.0)
	target.draw_colored_polygon(polygon, Color.WHITE)
	_check(batch.vertices[300 * 4].distance_to(original) <= 0.000001, "starting another object resets the tiny paint offset")
	target.surface("ground", 1.0)
	target.draw_colored_polygon(polygon, Color.WHITE)
	var different_plane: Vector3 = batch.vertices[301 * 4]
	_check(absf(different_plane.y - float(target.WORLD_HEIGHT)) <= 0.00001, "layer offsets do not replace the requested physical plane height")
	stage.end_frame()
	_check(stage.last_frame.instances == 1, "hundreds of coplanar draws still use one mesh instance")
	sections["coplanarLayerBudget"] = checks - started

func _cache_budget(stage) -> void:
	var started := checks
	var textures: Array[Texture2D] = []
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for index in range(129):
		textures.append(ImageTexture.create_from_image(image))
	var cache_size := -1
	var node_count := -1
	for frame in range(12):
		stage.begin_frame()
		for index in range(textures.size()):
			stage.paint_target.begin_object({"x": index % 4, "z": index / 4, "h": 0})
			stage.paint_target.draw_texture_rect(textures[index], Rect2(400, 200, 12, 12))
		stage.end_frame()
		if frame == 0:
			cache_size = stage._materials.size()
			node_count = stage._root.get_child_count()
		_check(stage._materials.size() == cache_size, "repeated frames with the same persistent textures do not grow the material cache")
		_check(stage._root.get_child_count() == node_count and node_count <= 3, "mesh nodes are bounded by batches, not frame count or draw count")
		_check(stage.last_frame.instances == 2 and stage.last_frame.batches == 129, "batch chunks remain bounded when crossing the per-mesh surface limit")
	stage.begin_frame()
	stage.end_frame()
	_check(stage.last_frame.instances == 0, "empty frame submits no active instances")
	for instance in stage._instances:
		_check(not instance.visible and instance.mesh == null, "unused pooled instances hide and release the previous mesh")
	stage.begin_frame()
	stage.paint_target.begin_object({"x": 0, "z": 0, "h": 0})
	stage.paint_target.draw_texture_rect(textures[0], Rect2(400, 200, 12, 12))
	stage.end_frame()
	_check(stage._materials.size() == cache_size and stage._root.get_child_count() == node_count, "small frame after a large frame reuses bounded resources")
	sections["fixedTextureSetReuse"] = checks - started

func _object_bias_draw(target, points: PackedVector2Array) -> PackedVector3Array:
	target.draw_colored_polygon(points, Color.WHITE)
	return target.batches[0].vertices.slice(target.batches[0].vertices.size() - points.size())

func _object_bias_vertices(stage, points: PackedVector2Array, vertices: PackedVector3Array, expected_bias: float, expected_anchor: Dictionary, label: String) -> void:
	var target = stage.paint_target
	for index in range(points.size()):
		var base: Vector3 = target.screen_to_world(points[index])
		var delta := vertices[index] - base
		_check(delta.distance_to(Target.VIEW_DIRECTION * expected_bias) < 0.000001, label + " uses only the expected view ray offset")
		_check(stage.camera.unproject_position(vertices[index]).distance_to(points[index]) <= 0.002, label + " actual camera screen coordinate is preserved")
	_check(target.anchor == expected_anchor, label + " does not change logical anchor")
	_check(is_equal_approx(target.plane_value, 0.0), label + " does not change plane constant")

## Headless geometry proves the small tie offset is bounded and projection-null;
## the independent GPU occlusion suite must prove the actual rendered ordering.
func _object_bias_projection(stage) -> void:
	var started := checks
	var points := PackedVector2Array([Vector2(340, 210), Vector2(360, 210), Vector2(340, 230)])
	var expected_anchor := {"x": -0.18, "z": 0.18, "h": 1.0}
	var ramp_surface := {"low": {"x": 0.0, "z": 0.0, "h": 0.0}, "high": {"x": 1.0, "z": 0.0, "h": 1.0}, "direction": Vector2.RIGHT, "rail_start": 0.2, "rail_end": 0.8}
	for framing in [[Vector2(1280, 720), Vector2(566.2, 363.7), 1.29383313], [Vector2(390, 844), Vector2(148.2, 422.0), 0.92], [Vector2(568, 320), Vector2(210.16, 160.0), 0.72]]:
		stage.setup_size(framing[0], framing[1], framing[2])
		await process_frame
		var target = stage.paint_target
		for requested_bias in [0.0, 0.0004, 0.001, 0.02, -0.02]:
			var expected_bias: float = clampf(requested_bias, -0.001, 0.001)
			target.begin_frame()
			target.begin_object(expected_anchor, 0, requested_bias)
			_object_bias_vertices(stage, points, _object_bias_draw(target, points), expected_bias, expected_anchor, "initial billboard")
			_object_bias_vertices(stage, points, _object_bias_draw(target, points), expected_bias + Target.LAYER_STEP, expected_anchor, "second object paint")
			for plane in ["ground", "x", "z", "ramp", "billboard"]:
				match plane:
					"ramp":
						target.ramp(ramp_surface)
					"billboard":
						target.billboard(expected_anchor)
					_:
						target.surface(plane, 0.0)
				_object_bias_vertices(stage, points, _object_bias_draw(target, points), expected_bias, expected_anchor, "plane switch " + plane)
				target.billboard(expected_anchor)
				# Return to billboard so each next distinct plane resets its layers.
				if plane == "billboard":
					_object_bias_vertices(stage, points, _object_bias_draw(target, points), expected_bias + Target.LAYER_STEP, expected_anchor, "same billboard layer")
			_check(is_equal_approx(target._object_bias, expected_bias), "object bias clamps to the allowed interval")
			target.begin_object(expected_anchor)
			_object_bias_vertices(stage, points, _object_bias_draw(target, points), 0.0, expected_anchor, "default next object resets object bias")
			target.begin_object(expected_anchor, 0, 0.001)
			target.begin_frame()
			_check(target._object_bias == 0.0, "begin frame resets object bias")
			_check(target.calls == 0 and target.batches.is_empty(), "begin frame retains recorder clearing")
			_check(absf(expected_bias) <= 0.001 and 0.02 - absf(expected_bias) >= 0.019, "object bias cannot consume normal separated geometry depth")
	sections["boundedObjectBiasProjection"] = checks - started

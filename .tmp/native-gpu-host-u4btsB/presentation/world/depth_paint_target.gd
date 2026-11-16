class_name GardenDepthPaintTarget
extends RefCounted

## Canvas-shaped recorder. Existing GardenPaint keeps its screen-space art;
## only these final vertices are lifted onto real 3D planes.
const WORLD_HEIGHT := 1.1197668465308115
const VIEW_DIRECTION := Vector3(0.6123724356957945, 0.5, 0.6123724356957945)
const LAYER_STEP := 0.00001

var origin := Vector2.ZERO
var scale_factor := 1.0
var plane_kind := "billboard"
var plane_value := 0.0
var anchor: Dictionary = {"x": 0.0, "z": 0.0, "h": 0.0}
var batches: Array = []
var _batch_by_key: Dictionary = {}
var _transform := Transform2D.IDENTITY
var _layer := 0
var _ramp_surface: Dictionary = {}
var _ramp_coefficients: Dictionary = {}
var _texture_alpha_cache: Dictionary = {}
var _transparent_priority := 0
var _object_bias := 0.0
var calls := 0
var triangles := 0

func configure(value_origin: Vector2, value_scale: float) -> void:
	origin = value_origin
	scale_factor = maxf(0.00001, value_scale)

func begin_frame() -> void:
	batches = []
	_batch_by_key = {}
	_transform = Transform2D.IDENTITY
	calls = 0
	triangles = 0
	begin_object({"x": 0.0, "z": 0.0, "h": 0.0})

func begin_object(value_anchor: Dictionary, transparent_priority: int = 0, depth_bias: float = 0.0) -> void:
	anchor = value_anchor.duplicate()
	plane_kind = "billboard"
	plane_value = float(anchor.get("x", 0.0)) + float(anchor.get("z", 0.0))
	_layer = 0
	_transparent_priority = clampi(transparent_priority, -128, 127)
	_object_bias = clampf(depth_bias, -0.001, 0.001)
	_transform = Transform2D.IDENTITY

func surface(kind: String, value: float) -> void:
	if kind not in ["ground", "x", "z"]:
		push_error("Unknown depth paint surface: " + kind)
		return
	if plane_kind != kind or not is_equal_approx(plane_value, value):
		_layer = 0
	plane_kind = kind
	plane_value = value

func billboard(value_anchor: Dictionary) -> void:
	anchor = value_anchor.duplicate()
	var value := float(anchor.get("x", 0.0)) + float(anchor.get("z", 0.0))
	if plane_kind != "billboard" or not is_equal_approx(plane_value, value):
		_layer = 0
	plane_kind = "billboard"
	plane_value = value

## The ramp quad and actor contact use the same low-to-high longitudinal
## coordinate. Its range is supplied by geometry; this only selects its plane.
func ramp(value_surface: Dictionary) -> void:
	if not value_surface.get("low", {}) is Dictionary or not value_surface.get("high", {}) is Dictionary or not value_surface.get("direction", Vector2.ZERO) is Vector2:
		push_error("Depth ramp needs low/high points and a Vector2 direction")
		return
	var low: Dictionary = value_surface.get("low", {})
	var high: Dictionary = value_surface.get("high", {})
	var direction: Vector2 = value_surface.get("direction", Vector2.ZERO)
	var start := float(value_surface.get("rail_start", 0.2))
	var end := float(value_surface.get("rail_end", 0.8))
	if low.is_empty() or high.is_empty() or direction.length_squared() < 0.000001 or end - start < 0.000001:
		push_error("Depth ramp has an empty endpoint, direction or run")
		return
	var rise := (float(high.h) - float(low.h)) / (end - start)
	var a := (direction.x + direction.y) * 0.5
	var b := (direction.x - direction.y) * 0.5
	var c := float(low.x) * direction.x + float(low.z) * direction.y
	var denominator := 17.5 - 48.0 * rise * a
	if absf(denominator) < 0.000001:
		push_error("Depth ramp is edge-on to the orthographic camera")
		return
	if plane_kind != "ramp" or _ramp_surface != value_surface:
		_layer = 0
	_ramp_surface = value_surface.duplicate(true)
	_ramp_coefficients = {"a": a, "b": b, "c": c, "k": rise, "start": start, "h": float(low.h), "denominator": denominator}
	plane_kind = "ramp"

func screen_to_world(screen: Vector2) -> Vector3:
	var raw := (screen - origin) / scale_factor
	var difference := raw.x / 35.0
	var x := 0.0
	var z := 0.0
	var h := 0.0
	match plane_kind:
		"ground":
			h = plane_value
			var total := (raw.y + h * 48.0) / 17.5
			x = (total + difference) * 0.5
			z = (total - difference) * 0.5
		"x":
			x = plane_value
			z = x - difference
			h = ((x + z) * 17.5 - raw.y) / 48.0
		"z":
			z = plane_value
			x = z + difference
			h = ((x + z) * 17.5 - raw.y) / 48.0
		"ramp":
			var plane := _ramp_coefficients
			var total: float = (raw.y + 48.0 * float(plane.h) + 48.0 * float(plane.k) * (float(plane.b) * difference - float(plane.c) - float(plane.start))) / float(plane.denominator)
			x = (total + difference) * 0.5
			z = (total - difference) * 0.5
			h = float(plane.h) + float(plane.k) * (float(plane.a) * total + float(plane.b) * difference - float(plane.c) - float(plane.start))
		_:
			x = (plane_value + difference) * 0.5
			z = (plane_value - difference) * 0.5
			h = (plane_value * 17.5 - raw.y) / 48.0
	return Vector3(x, h * WORLD_HEIGHT, z)

func draw_set_transform_matrix(matrix: Transform2D) -> void:
	_transform = matrix

func draw_polygon(points: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array = PackedVector2Array(), texture: Texture2D = null) -> void:
	if points.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		return
	_emit(points, colors, uvs, texture, indices)

func draw_colored_polygon(points: PackedVector2Array, color: Color, uvs: PackedVector2Array = PackedVector2Array(), texture: Texture2D = null) -> void:
	draw_polygon(points, PackedColorArray([color]), uvs, texture)

func draw_primitive(points: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array = PackedVector2Array(), texture: Texture2D = null) -> void:
	if points.size() == 3:
		_emit(points, colors, uvs, texture, PackedInt32Array([0, 1, 2]))
	elif points.size() == 4:
		_emit(points, colors, uvs, texture, PackedInt32Array([0, 1, 2, 0, 2, 3]))
	elif points.size() == 2:
		draw_polyline(points, colors[0] if not colors.is_empty() else Color.WHITE)
	elif points.size() == 1:
		var at := points[0]
		draw_colored_polygon(PackedVector2Array([at + Vector2(-0.5, -0.5), at + Vector2(0.5, -0.5), at + Vector2(0.5, 0.5), at + Vector2(-0.5, 0.5)]), colors[0] if not colors.is_empty() else Color.WHITE)

func draw_polyline(points: PackedVector2Array, color: Color, width := 1.0, _antialiased := false) -> void:
	if points.size() < 2 or width <= 0.0:
		return
	var vertices := PackedVector2Array()
	var indices := PackedInt32Array()
	var half_width := width * 0.5
	for index in range(points.size() - 1):
		var first := points[index]
		var last := points[index + 1]
		var direction := last - first
		if direction.length_squared() < 0.000001:
			continue
		var normal := Vector2(-direction.y, direction.x).normalized() * half_width
		var start := vertices.size()
		vertices.append_array(PackedVector2Array([first - normal, first + normal, last + normal, last - normal]))
		indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
	if not indices.is_empty():
		_emit(vertices, PackedColorArray([color]), PackedVector2Array(), null, indices)

func draw_texture_rect(texture: Texture2D, rect: Rect2, tile := false, modulate := Color.WHITE, transpose := false) -> void:
	if texture == null or not rect.has_area():
		return
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var extent := rect.size / Vector2(texture.get_width(), texture.get_height()) if tile else Vector2.ONE
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2(extent.x, 0.0), extent, Vector2(0.0, extent.y)])
	if transpose:
		for index in range(uvs.size()):
			uvs[index] = Vector2(uvs[index].y, uvs[index].x)
	_emit(points, PackedColorArray([modulate]), uvs, texture, PackedInt32Array([0, 1, 2, 0, 2, 3]))

## Static source textures are inspected once for their effective alpha, rather
## than treating every opaque JPEG/RGBA image as a transparent surface. The
## cache is bounded by the caller's persistent texture set, like stage materials.
## Viewport textures change without changing identity: never read them back.
func _texture_transparent(texture: Texture2D) -> bool:
	if texture == null:
		return false
	if texture is ViewportTexture:
		return true
	var identity := texture.get_instance_id()
	if _texture_alpha_cache.has(identity):
		return bool(_texture_alpha_cache[identity])
	var transparent := texture.has_alpha()
	# Imported CompressedTexture2D may report has_alpha=false in a headless
	# renderer even when its source PNG contains alpha. Inspect a static source
	# once regardless; metadata is only a fallback when no source is available.
	var source := texture.get_image()
	if source != null and not source.is_empty():
		transparent = source.detect_alpha() != Image.ALPHA_NONE
	_texture_alpha_cache[identity] = transparent
	return transparent

func _emit(points: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array, texture: Texture2D, indices: PackedInt32Array) -> void:
	var transparent := _texture_transparent(texture)
	for color in colors:
		transparent = transparent or color.a < 0.99999
	var priority := _transparent_priority if transparent else 0
	var key := str(texture.get_instance_id()) if texture != null else "solid"
	key += ":alpha" if transparent else ":opaque"
	key += ":priority:" + str(priority)
	if not _batch_by_key.has(key):
		_batch_by_key[key] = batches.size()
		batches.append({"key": key, "texture": texture, "transparent": transparent, "priority": priority, "vertices": PackedVector3Array(), "colors": PackedColorArray(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()})
	var batch: Dictionary = batches[int(_batch_by_key[key])]
	var first_vertex: int = batch.vertices.size()
	# Move along the view ray: preserve screen coordinates while separating
	# coplanar objects and the paint layers within each object.
	var bias := VIEW_DIRECTION * (_object_bias + minf(_layer, 256) * LAYER_STEP)
	for index in range(points.size()):
		batch.vertices.append(screen_to_world(_transform * points[index]) + bias)
		batch.colors.append(colors[index] if colors.size() == points.size() else colors[0] if not colors.is_empty() else Color.WHITE)
		batch.uvs.append(uvs[index] if uvs.size() == points.size() else Vector2.ZERO)
	for index in indices:
		batch.indices.append(first_vertex + index)
	_layer += 1
	calls += 1
	triangles += indices.size() / 3

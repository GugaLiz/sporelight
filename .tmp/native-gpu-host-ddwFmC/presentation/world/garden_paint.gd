class_name GardenPaint
extends RefCounted

## Small immediate-mode bridge for the original 2D illustration operations.
## Transforms affect geometry; texture UVs stay in the original local space.
var target: Variant
var images: Dictionary = {}
var matrix := Transform2D.IDENTITY
var alpha := 1.0
var _stack: Array = []
static var _soft_cache: Dictionary = {}
static var _linear_cache: Dictionary = {}
static var _halo_cache: Dictionary = {}
static var _glow_cache: Dictionary = {}
static var _oval_fans: Dictionary = {}

func _init(canvas: Variant, textures: Dictionary = {}) -> void:
	target = canvas
	images = textures

func push(origin := Vector2.ZERO, size := Vector2.ONE, angle := 0.0, opacity := 1.0) -> void:
	_stack.append([matrix, alpha])
	matrix = matrix * Transform2D(angle, origin).scaled_local(size)
	alpha *= opacity

func pop() -> void:
	var previous: Array = _stack.pop_back()
	matrix = previous[0]
	alpha = previous[1]

func poly(points: Variant, fill: Variant, stroke: Variant = null, width := 0.7) -> void:
	var source := PackedVector2Array()
	var transformed := PackedVector2Array()
	for value in points:
		var point: Vector2 = value if value is Vector2 else Vector2(value[0], value[1])
		if not source.is_empty() and source[-1].is_equal_approx(point):
			continue
		source.append(point)
		transformed.append(matrix * point)
	if source.size() > 1 and source[0].is_equal_approx(source[-1]):
		source.remove_at(source.size() - 1)
		transformed.remove_at(transformed.size() - 1)
	if transformed.size() < 3:
		return
	if fill is Dictionary:
		var bounds: Rect2 = fill.bounds
		var uvs := PackedVector2Array()
		for point in source:
			var uv := (point - bounds.position) / bounds.size
			uvs.append(Vector2(clampf(uv.x, 0, 1), clampf(uv.y, 0, 1)))
		target.draw_polygon(transformed, PackedColorArray([Color(1, 1, 1, alpha)]), uvs, fill.texture)
	else:
		var color: Color = Color(fill) if fill is String else fill
		color.a *= alpha
		target.draw_colored_polygon(transformed, color)
	if stroke != null:
		transformed.append(transformed[0])
		var color: Color = Color(stroke) if stroke is String else stroke
		color.a *= alpha
		target.draw_polyline(transformed, color, maxf(0.3, width * matrix.x.length()), true)

func line(points: Variant, color: Variant, width := 1.0, closed := false) -> void:
	var transformed := PackedVector2Array()
	for value in points:
		var point: Vector2 = value if value is Vector2 else Vector2(value[0], value[1])
		transformed.append(matrix * point)
	if transformed.size() < 2:
		return
	if closed:
		transformed.append(transformed[0])
	var ink: Color = Color(color) if color is String else color
	ink.a *= alpha
	target.draw_polyline(transformed, ink, maxf(0.3, width * matrix.x.length()), true)

func oval(x: float, y: float, rx: float, ry: float, fill: Variant, angle := 0.0, stroke: Variant = null, width := 0.7) -> void:
	var points := PackedVector2Array()
	# Tiny eye glints can be <0.2px after camera scaling. A 48-vertex polygon at
	# screen coordinates loses float precision in WebGL's triangulator. Convex
	# ellipses have a known triangle fan, so they never need ear clipping.
	var segments := clampi(int(ceil(maxf(rx, ry) * maxf(matrix.x.length(), matrix.y.length()) * 0.8)), 8, 48)
	if not _oval_fans.has(segments):
		var unit := PackedFloat64Array()
		var indices := PackedInt32Array()
		for index in range(segments):
			var theta := float(index) / segments * TAU
			unit.append(cos(theta))
			unit.append(sin(theta))
		for index in range(1, segments - 1):
			indices.append_array(PackedInt32Array([0, index, index + 1]))
		_oval_fans[segments] = {"unit": unit, "indices": indices}
	var fan: Dictionary = _oval_fans[segments]
	var unit: PackedFloat64Array = fan.unit
	for index in range(segments):
		points.append(Vector2(x, y) + Vector2(unit[index * 2] * rx, unit[index * 2 + 1] * ry).rotated(angle))
	var transformed := PackedVector2Array()
	for point in points:
		transformed.append(matrix * point)
	var uv := PackedVector2Array()
	var bounds: Rect2 = fill.bounds if fill is Dictionary else Rect2()
	var color: Color = Color(1, 1, 1, alpha) if fill is Dictionary else Color(fill) if fill is String else fill
	var texture: Texture2D = null
	if not fill is Dictionary:
		color.a *= alpha
	else:
		texture = fill.texture
		for source in points:
			var position := (source - bounds.position) / bounds.size
			uv.append(Vector2(clampf(position.x, 0, 1), clampf(position.y, 0, 1)))
	# Primitive triangles retain the explicit fan and can share GLES3 batches.
	# Per-ellipse polygon buffers regressed Web performance in isolated sampling.
	var indices: PackedInt32Array = fan.indices
	for index in range(0, indices.size(), 3):
		var a := indices[index]
		var b := indices[index + 1]
		var c := indices[index + 2]
		var triangle_uv := PackedVector2Array([uv[a], uv[b], uv[c]]) if texture != null else PackedVector2Array()
		target.draw_primitive(PackedVector2Array([transformed[a], transformed[b], transformed[c]]), PackedColorArray([color]), triangle_uv, texture)
	if stroke != null:
		transformed.append(transformed[0])
		var outline: Color = Color(stroke) if stroke is String else stroke
		outline.a *= alpha
		target.draw_polyline(transformed, outline, maxf(0.3, width * matrix.x.length()), true)

func arc(x: float, y: float, rx: float, ry: float, start: float, end: float, color: Variant, width := 1.0, angle := 0.0) -> void:
	var points := PackedVector2Array()
	for index in range(33):
		var theta := lerpf(start, end, float(index) / 32.0)
		points.append(Vector2(x, y) + Vector2(cos(theta) * rx, sin(theta) * ry).rotated(angle))
	line(points, color, width)

func quadratic(a: Vector2, control: Vector2, b: Vector2, color: Variant, width := 1.0) -> void:
	line(quadratic_points(a, control, b), color, width)

static func quadratic_points(a: Vector2, control: Vector2, b: Vector2, count := 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(count + 1):
		var t := float(index) / count
		points.append(a * (1.0 - t) * (1.0 - t) + control * 2.0 * (1.0 - t) * t + b * t * t)
	return points

static func cubic_points(a: Vector2, first: Vector2, second: Vector2, b: Vector2, count := 20) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(count + 1):
		var t := float(index) / count
		var u := 1.0 - t
		points.append(a * u * u * u + first * 3.0 * u * u * t + second * 3.0 * u * t * t + b * t * t * t)
	return points

func image(id: String, x: float, y: float, width: float, anchor := 0.9, opacity := 1.0) -> void:
	var texture: Texture2D = images.get(id)
	if texture == null:
		return
	var height := width * texture.get_height() / float(texture.get_width())
	target.draw_set_transform_matrix(matrix)
	target.draw_texture_rect(texture, Rect2(x - width / 2.0, y - height * anchor, width, height), false, Color(1, 1, 1, alpha * opacity))
	target.draw_set_transform_matrix(Transform2D.IDENTITY)

func textured_poly(points: Variant, id: String, uvs: PackedVector2Array, opacity := 1.0) -> void:
	var texture: Texture2D = images.get(id)
	if texture == null:
		return
	var transformed := PackedVector2Array()
	var clean_uvs := PackedVector2Array()
	var previous := Vector2(INF, INF)
	for index in range(points.size()):
		var point: Vector2 = points[index]
		if point.is_equal_approx(previous):
			continue
		transformed.append(matrix * point)
		clean_uvs.append(uvs[index])
		previous = point
	if transformed.size() > 1 and transformed[0].is_equal_approx(transformed[-1]):
		transformed.remove_at(transformed.size() - 1)
		clean_uvs.remove_at(clean_uvs.size() - 1)
	if transformed.size() >= 3:
		target.draw_polygon(transformed, PackedColorArray([Color(1, 1, 1, alpha * opacity)]), clean_uvs, texture)

func textured_oval(x: float, y: float, rx: float, ry: float, id: String, opacity := 1.0, angle := 0.0, texture_bounds := Rect2()) -> void:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var bounds: Rect2 = texture_bounds if texture_bounds.has_area() else Rect2(x - rx, y - ry, rx * 2, ry * 2)
	for index in range(48):
		var theta := index / 48.0 * TAU
		var point := Vector2(x, y) + Vector2(cos(theta) * rx, sin(theta) * ry).rotated(angle)
		points.append(point)
		uvs.append((point - bounds.position) / bounds.size)
	textured_poly(points, id, uvs, opacity)

func halo(at: Vector2, rx: float, ry: float, color: String, blur: float, line_width := 1.7, opacity := 1.0) -> void:
	# Rasterize the blurred stroked ellipse once. Canvas shadowBlur has no native 2D equivalent.
	var key := "%s:%.2f:%.2f:%.2f:%.2f" % [color, rx, ry, blur, line_width]
	var record: Dictionary = _halo_cache.get(key, {})
	if record.is_empty():
		var padding := maxf(2, blur * 2)
		var dimensions := Vector2i(int(ceil((rx + padding) * 2)), int(ceil((ry + padding) * 2)))
		var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
		var center := Vector2(dimensions) / 2
		var ink := Color(color)
		var sigma := maxf(0.7, blur * 0.42)
		for py in range(dimensions.y):
			for px in range(dimensions.x):
				var point := Vector2(px + 0.5, py + 0.5) - center
				var normalized := sqrt(point.x * point.x / (rx * rx) + point.y * point.y / (ry * ry))
				var distance := absf(normalized - 1.0) * minf(rx, ry)
				var strength := exp(-distance * distance / (2 * sigma * sigma)) * minf(1, line_width / maxf(1, sigma))
				image.set_pixel(px, py, Color(ink.r, ink.g, ink.b, ink.a * strength))
		record = {"texture": ImageTexture.create_from_image(image), "size": Vector2(dimensions)}
		_halo_cache[key] = record
	target.draw_set_transform_matrix(matrix)
	target.draw_texture_rect(record.texture, Rect2(at - record.size / 2, record.size), false, Color(1, 1, 1, alpha * opacity))
	target.draw_set_transform_matrix(Transform2D.IDENTITY)

func glow(at: Vector2, radius: float, color: String, opacity := 1.0, flatten := 1.0) -> void:
	if not _glow_cache.has(color):
		var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		var ink := Color(color)
		for py in range(96):
			for px in range(96):
				var distance := (Vector2(px + 0.5, py + 0.5) - Vector2(48, 48)).length() / 48.0
				image.set_pixel(px, py, Color(ink.r, ink.g, ink.b, ink.a * pow(maxf(0, 1 - distance), 1.4)))
		_glow_cache[color] = ImageTexture.create_from_image(image)
	target.draw_set_transform_matrix(matrix)
	target.draw_texture_rect(_glow_cache[color], Rect2(at - Vector2(radius, radius * flatten), Vector2(radius * 2, radius * flatten * 2)), false, Color(1, 1, 1, alpha * opacity))
	target.draw_set_transform_matrix(Transform2D.IDENTITY)

func soft(x: float, y: float, radius: float, light: String, base: String, shade: String) -> Dictionary:
	var key := light + base + shade
	if not _soft_cache.has(key):
		var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		var c0 := Color(light)
		var c1 := Color(base)
		var c2 := Color(shade)
		# Solve the same two-circle radial field used by Canvas softMaterial().
		var delta := Vector2(0.5, 0.7)
		var dr := 1.16
		var a := delta.length_squared() - dr * dr
		for py in range(96):
			for px in range(96):
				var point := Vector2((px + 0.5) / 96.0 * 3.0 - 1.5, (py + 0.5) / 96.0 * 3.0 - 1.5) - Vector2(-0.32, -0.4)
				var b := -2.0 * point.dot(delta) - 2.0 * 0.04 * dr
				var c := point.length_squared() - 0.04 * 0.04
				var t := clampf((-b - sqrt(maxf(0.0, b * b - 4.0 * a * c))) / (2.0 * a), 0.0, 1.0)
				image.set_pixel(px, py, c0.lerp(c1, t / 0.48) if t < 0.48 else c1.lerp(c2, (t - 0.48) / 0.52))
		_soft_cache[key] = ImageTexture.create_from_image(image)
	return {"texture": _soft_cache[key], "bounds": Rect2(x - radius * 1.5, y - radius * 1.5, radius * 3, radius * 3)}

func linear(bounds: Rect2, colors: Array, offsets: Array = []) -> Dictionary:
	var key := str(colors) + str(offsets)
	if not _linear_cache.has(key):
		var gradient := Gradient.new()
		var stops := PackedFloat32Array()
		var inks := PackedColorArray()
		for index in range(colors.size()):
			stops.append(float(index) / maxf(1.0, colors.size() - 1) if offsets.is_empty() else float(offsets[index]))
			inks.append(Color(colors[index]))
		gradient.offsets = stops
		gradient.colors = inks
		var texture := GradientTexture2D.new()
		texture.width = 8
		texture.height = 128
		texture.gradient = gradient
		texture.fill_from = Vector2(0, 0)
		texture.fill_to = Vector2(0, 1)
		_linear_cache[key] = texture
	return {"texture": _linear_cache[key], "bounds": bounds}

func shadow(x: float, y: float, rx: float, ry: float) -> void:
	oval(x, y, rx, ry, soft(x, y, rx, "#38473759", "#38473724", "#38473700"))

func leaf(x: float, y: float, size: float, angle := 0.0) -> void:
	push(Vector2(x, y), Vector2.ONE * size, angle)
	var points := quadratic_points(Vector2(-8, 3), Vector2(-10, -6), Vector2(7, -8))
	points.append_array(quadratic_points(Vector2(7, -8), Vector2(11, 1), Vector2(-8, 3)))
	poly(points, soft(0, -2, 10, "#c5d29b", "#8caa72", "#516d50"))
	line([Vector2(-7, 2), Vector2(5, -6)], "#d7ddb280", 0.65)
	pop()

func eye(x: float, y: float, closed := false, size := 1.0) -> void:
	if closed:
		arc(x, y - 1, 2 * size, 2 * size, 0.15, PI - 0.15, "#584437", 1.1)
		return
	oval(x, y, 2.1 * size, 2.8 * size, "#ddbea0")
	oval(x, y - 0.25, 1.65 * size, 2.2 * size, soft(x, y, 3 * size, "#715744", "#392e29", "#211f20"))
	oval(x - 0.55 * size, y - 1.1 * size, 0.6 * size, 0.8 * size, "#fff6e8")
	oval(x + 0.5 * size, y + 0.65 * size, 0.25 * size, 0.3 * size, "#d7bfa0")

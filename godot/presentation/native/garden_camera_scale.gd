extends RefCounted
## Match the approved first garden at this viewport/safe area. Big gardens use
## following at this density; overview alone fits their entire authored extent.
const World = preload("res://core/garden_world.gd")
const First = preload("res://presentation/native/first_garden_profile.gd")
static var _reference_span := Vector2.ZERO

static func reference_span() -> Vector2:
	if _reference_span != Vector2.ZERO: return _reference_span
	var model := World.new("1-1")
	var points: Array = model.level.tiles.duplicate(true)
	points.append_array(model.tiles())
	for root: Dictionary in model.level.roots:
		for socket: Array in root.get("sockets", []):
			points.append({"x": socket[0], "z": socket[1], "h": root.get("h", 0)})
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var right := Vector3(0.70710678, 0, -0.70710678)
	var up := Vector3(-0.35355339, 0.8660254, -0.35355339)
	for point: Dictionary in points:
		var at := First.to_physical(Vector3(float(point.x), float(point.h) * 0.65, float(point.z)))
		for offset: Vector3 in [Vector3(-0.5, -0.9, -0.5), Vector3(0.5, 1.6, 0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, -0.5)]:
			var vertex := at + offset
			var screen := Vector2(vertex.dot(right), vertex.dot(up))
			low = low.min(screen)
			high = high.max(screen)
	_reference_span = high - low
	return _reference_span

static func normal_size(dimensions: Vector2, safe: Rect2) -> float:
	# Retain the already approved mobile first-garden framing exactly.
	if dimensions.x < 650 or dimensions.y < 430:
		return dimensions.y / (52.0 if dimensions.y < 430 else 68.0)
	var span := reference_span()
	var aspect := safe.size.x / maxf(1.0, safe.size.y)
	var framing := maxf(span.y + 0.75, (span.x + 1.0) / aspect) * dimensions.y / maxf(1.0, safe.size.y)
	return minf(maxf(5.8, framing), dimensions.y / 57.0)

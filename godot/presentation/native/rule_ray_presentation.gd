extends RefCounted
## Clip only the drawn light to the visible garden's footprint. Domain rays
## retain their authored range, reflection points, receiver checks and reveals.

static func update_motion(stage: Node, before: RefCounted, after: RefCounted, progress: float) -> void:
	# Rule rays use discrete aligned states. The stage previews destination
	# geometry during animation; its full destination beam would falsely claim
	# that an intermediate angle already reaches the receiver. Do not invent a
	# continuous-angle rule simulation. Restore the real beam upon alignment.
	var changed: bool = before.rays() != after.rays() or before.lamp_ray() != after.lamp_ray()
	var aligned := not changed or progress >= 1.0
	for node: Node in stage._effects.get_children():
		if node.has_meta("rule_ray"):
			(node as Node3D).visible = aligned

static func visible_bounds(world: RefCounted, world_tiles: Array = []) -> Rect2:
	if world_tiles.is_empty(): world_tiles = world.tiles()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for tile: Dictionary in world_tiles:
		if not world.visible(tile, world_tiles): continue
		var point := Vector2(float(tile.x), float(tile.z))
		low = low.min(point - Vector2(0.5, 0.5))
		high = high.max(point + Vector2(0.5, 0.5))
	return Rect2(low, high - low) if low.is_finite() else Rect2()

static func segments(world: RefCounted, points: Array, world_tiles: Array = []) -> Array:
	var result: Array = []
	if points.size() < 2: return result
	var bounds := visible_bounds(world, world_tiles)
	if not bounds.has_area(): return result
	for index in range(1, points.size()):
		var clipped := clip_segment(points[index - 1], points[index], bounds)
		if not clipped.is_empty(): result.append(clipped)
	return result

static func clip_segment(a: Dictionary, b: Dictionary, bounds: Rect2) -> Array:
	if not bounds.has_area(): return []
	var start := Vector2(float(a.x), float(a.z))
	var delta := Vector2(float(b.x), float(b.z)) - start
	if delta.length_squared() < 0.00000001: return []
	var near := 0.0
	var far := 1.0
	for axis in range(2):
		if absf(delta[axis]) < 0.000001:
			if start[axis] < bounds.position[axis] or start[axis] > bounds.end[axis]: return []
			continue
		var first := (bounds.position[axis] - start[axis]) / delta[axis]
		var last := (bounds.end[axis] - start[axis]) / delta[axis]
		near = maxf(near, minf(first, last))
		far = minf(far, maxf(first, last))
		if far <= near: return []
	var height_a := float(a.get("h", 0))
	var height_b := float(b.get("h", 0))
	var clipped_a := start + delta * near
	var clipped_b := start + delta * far
	return [
		{"x": clipped_a.x, "z": clipped_a.y, "h": lerpf(height_a, height_b, near)},
		{"x": clipped_b.x, "z": clipped_b.y, "h": lerpf(height_a, height_b, far)}
	]
